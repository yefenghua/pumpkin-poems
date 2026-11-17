// Package pgstore is the PostgreSQL implementation of store.Store (pgx v5).
package pgstore

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/yefenghua/pumpkin-poems/backend/internal/store"
)

type Store struct {
	pool *pgxpool.Pool
}

var _ store.Store = (*Store)(nil)

// Open connects, runs migrations and returns a ready store.
func Open(ctx context.Context, databaseURL string) (*Store, error) {
	pool, err := pgxpool.New(ctx, databaseURL)
	if err != nil {
		return nil, err
	}
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("ping postgres: %w", err)
	}
	if err := Migrate(ctx, pool); err != nil {
		pool.Close()
		return nil, err
	}
	return &Store{pool: pool}, nil
}

func (s *Store) Close() { s.pool.Close() }

// Pool exposes the pool for tests (e.g. truncating tables).
func (s *Store) Pool() *pgxpool.Pool { return s.pool }

func (s *Store) InsertAnalyticsEvents(ctx context.Context, events []store.AnalyticsEvent) (int, int, error) {
	if len(events) == 0 {
		return 0, 0, nil
	}
	batch := &pgx.Batch{}
	for _, e := range events {
		props, err := json.Marshal(nonNilProps(e.Props))
		if err != nil {
			return 0, 0, err
		}
		batch.Queue(`INSERT INTO analytics_events
			(id, install_id, app_version, name, at, content_version, rule_version, props)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
			ON CONFLICT (id) DO NOTHING`,
			e.ID, e.InstallID, e.AppVersion, e.Name, e.At, e.ContentVersion, e.RuleVersion, props)
	}
	accepted := 0
	err := pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		br := tx.SendBatch(ctx, batch)
		for range events {
			tag, err := br.Exec()
			if err != nil {
				br.Close()
				return err
			}
			accepted += int(tag.RowsAffected())
		}
		return br.Close()
	})
	if err != nil {
		return 0, 0, err
	}
	return accepted, len(events) - accepted, nil
}

func (s *Store) ListAnalyticsEvents(ctx context.Context, from, to time.Time) ([]store.AnalyticsEvent, error) {
	rows, err := s.pool.Query(ctx, `SELECT id, install_id, app_version, name, at, content_version, rule_version, props
		FROM analytics_events WHERE at >= $1 AND at < $2 ORDER BY at, id`, from, to)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(r pgx.CollectableRow) (store.AnalyticsEvent, error) {
		var e store.AnalyticsEvent
		var rule *int32
		var props []byte
		if err := r.Scan(&e.ID, &e.InstallID, &e.AppVersion, &e.Name, &e.At, &e.ContentVersion, &rule, &props); err != nil {
			return e, err
		}
		if rule != nil {
			v := int(*rule)
			e.RuleVersion = &v
		}
		e.At = e.At.UTC()
		if err := json.Unmarshal(props, &e.Props); err != nil {
			return e, err
		}
		return e, nil
	})
}

func (s *Store) InsertFeedback(ctx context.Context, f store.Feedback) (bool, error) {
	tag, err := s.pool.Exec(ctx, `INSERT INTO feedback
		(id, install_id, at, category, message, content_version, app_version)
		VALUES ($1, $2, $3, $4, $5, $6, $7) ON CONFLICT (id) DO NOTHING`,
		f.ID, f.InstallID, f.At, f.Category, f.Message, f.ContentVersion, f.AppVersion)
	if err != nil {
		return false, err
	}
	return tag.RowsAffected() == 1, nil
}

const parentCols = `id::text, account_id, password_hash, created_at`

func scanParent(r pgx.Row) (store.Parent, error) {
	var p store.Parent
	err := r.Scan(&p.ID, &p.AccountID, &p.PasswordHash, &p.CreatedAt)
	p.CreatedAt = p.CreatedAt.UTC()
	return p, err
}

func (s *Store) CreateParent(ctx context.Context, p store.Parent) (store.Parent, error) {
	out, err := scanParent(s.pool.QueryRow(ctx, `INSERT INTO parents (id, account_id, password_hash, created_at)
		VALUES (gen_random_uuid(), $1, $2, $3) ON CONFLICT (account_id) DO NOTHING RETURNING `+parentCols,
		p.AccountID, p.PasswordHash, p.CreatedAt))
	if errors.Is(err, pgx.ErrNoRows) {
		return store.Parent{}, store.ErrConflict
	}
	return out, err
}

func (s *Store) ParentByAccountID(ctx context.Context, accountID string) (store.Parent, error) {
	p, err := scanParent(s.pool.QueryRow(ctx, `SELECT `+parentCols+` FROM parents WHERE account_id = $1`, accountID))
	if errors.Is(err, pgx.ErrNoRows) {
		return store.Parent{}, store.ErrNotFound
	}
	return p, err
}

func (s *Store) ParentByID(ctx context.Context, parentID string) (store.Parent, error) {
	p, err := scanParent(s.pool.QueryRow(ctx, `SELECT `+parentCols+` FROM parents WHERE id = $1`, parentID))
	if errors.Is(err, pgx.ErrNoRows) {
		return store.Parent{}, store.ErrNotFound
	}
	return p, err
}

func (s *Store) UpdatePassword(ctx context.Context, parentID, passwordHash string) error {
	tag, err := s.pool.Exec(ctx, `UPDATE parents SET password_hash = $2 WHERE id = $1`, parentID, passwordHash)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return store.ErrNotFound
	}
	return nil
}

func (s *Store) CreateSession(ctx context.Context, parentID string, tokenHash []byte, expiresAt time.Time) error {
	_, err := s.pool.Exec(ctx, `INSERT INTO sessions (token_hash, parent_id, expires_at) VALUES ($1, $2, $3)`,
		tokenHash, parentID, expiresAt)
	return err
}

func (s *Store) SessionParent(ctx context.Context, tokenHash []byte, now time.Time) (string, error) {
	var id string
	err := s.pool.QueryRow(ctx, `SELECT parent_id::text FROM sessions WHERE token_hash = $1 AND expires_at > $2`,
		tokenHash, now).Scan(&id)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", store.ErrNotFound
	}
	return id, err
}

func (s *Store) DeleteSession(ctx context.Context, tokenHash []byte) error {
	_, err := s.pool.Exec(ctx, `DELETE FROM sessions WHERE token_hash = $1`, tokenHash)
	return err
}

func (s *Store) DeleteOtherSessions(ctx context.Context, parentID string, keep []byte) error {
	_, err := s.pool.Exec(ctx, `DELETE FROM sessions WHERE parent_id = $1 AND ($2::bytea IS NULL OR token_hash <> $2)`,
		parentID, keep)
	return err
}

// DeleteAccount relies on ON DELETE CASCADE for sessions, profiles, events and drafts.
func (s *Store) DeleteAccount(ctx context.Context, parentID string) error {
	_, err := s.pool.Exec(ctx, `DELETE FROM parents WHERE id = $1`, parentID)
	return err
}

const profileCols = `id, parent_id::text, nickname, stage, created_at`

func scanProfile(r pgx.Row) (store.Profile, error) {
	var p store.Profile
	err := r.Scan(&p.ID, &p.ParentID, &p.Nickname, &p.Stage, &p.CreatedAt)
	p.CreatedAt = p.CreatedAt.UTC()
	return p, err
}

func (s *Store) ListProfiles(ctx context.Context, parentID string) ([]store.Profile, error) {
	rows, err := s.pool.Query(ctx, `SELECT `+profileCols+` FROM profiles WHERE parent_id = $1 ORDER BY created_at, id`, parentID)
	if err != nil {
		return nil, err
	}
	out, err := pgx.CollectRows(rows, func(r pgx.CollectableRow) (store.Profile, error) { return scanProfile(r) })
	if out == nil {
		out = []store.Profile{}
	}
	return out, err
}

func (s *Store) CreateProfile(ctx context.Context, p store.Profile) (store.Profile, bool, error) {
	created, err := scanProfile(s.pool.QueryRow(ctx, `INSERT INTO profiles (id, parent_id, nickname, stage, created_at)
		VALUES ($1, $2, $3, $4, $5) ON CONFLICT (id) DO NOTHING RETURNING `+profileCols,
		p.ID, p.ParentID, p.Nickname, p.Stage, p.CreatedAt))
	if err == nil {
		return created, true, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return store.Profile{}, false, err
	}
	existing, err := scanProfile(s.pool.QueryRow(ctx, `SELECT `+profileCols+` FROM profiles WHERE id = $1`, p.ID))
	if errors.Is(err, pgx.ErrNoRows) {
		// Deleted concurrently; let the client retry.
		return store.Profile{}, false, store.ErrConflict
	}
	if err != nil {
		return store.Profile{}, false, err
	}
	if existing.ParentID != p.ParentID {
		return store.Profile{}, false, store.ErrConflict
	}
	return existing, false, nil
}

func (s *Store) UpdateProfile(ctx context.Context, parentID, profileID string, patch store.ProfilePatch) (store.Profile, error) {
	p, err := scanProfile(s.pool.QueryRow(ctx, `UPDATE profiles SET
			nickname = COALESCE($3, nickname),
			stage = CASE WHEN $4 THEN $5 ELSE stage END
		WHERE id = $1 AND parent_id = $2 RETURNING `+profileCols,
		profileID, parentID, patch.Nickname, patch.SetStage, patch.Stage))
	if errors.Is(err, pgx.ErrNoRows) {
		return store.Profile{}, store.ErrNotFound
	}
	return p, err
}

func (s *Store) DeleteProfile(ctx context.Context, parentID, profileID string) error {
	tag, err := s.pool.Exec(ctx, `DELETE FROM profiles WHERE id = $1 AND parent_id = $2`, profileID, parentID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return store.ErrNotFound
	}
	return nil
}

func (s *Store) WithProfileSync(ctx context.Context, parentID, profileID string, fn func(store.SyncTx) error) error {
	return pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		var last int64
		err := tx.QueryRow(ctx, `SELECT last_seq FROM profiles WHERE id = $1 AND parent_id = $2 FOR UPDATE`,
			profileID, parentID).Scan(&last)
		if errors.Is(err, pgx.ErrNoRows) {
			return store.ErrNotFound
		}
		if err != nil {
			return err
		}
		return fn(&syncTx{tx: tx, profileID: profileID, lastSeq: last})
	})
}

type syncTx struct {
	tx        pgx.Tx
	profileID string
	lastSeq   int64
}

func (t *syncTx) LastSeq() int64 { return t.lastSeq }

func (t *syncTx) ExistingEventIDs(ctx context.Context, ids []string) (map[string]bool, error) {
	out := map[string]bool{}
	if len(ids) == 0 {
		return out, nil
	}
	rows, err := t.tx.Query(ctx, `SELECT id FROM sync_events WHERE profile_id = $1 AND id = ANY($2)`, t.profileID, ids)
	if err != nil {
		return nil, err
	}
	found, err := pgx.CollectRows(rows, pgx.RowTo[string])
	for _, id := range found {
		out[id] = true
	}
	return out, err
}

func (t *syncTx) InsertEvents(ctx context.Context, events []store.SyncEvent) error {
	batch := &pgx.Batch{}
	for _, e := range events {
		batch.Queue(`INSERT INTO sync_events (profile_id, id, seq, kind, poem_id, at, device_id, payload)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
			t.profileID, e.ID, e.Seq, e.Kind, e.PoemID, e.At, e.DeviceID, []byte(e.Payload))
	}
	return t.tx.SendBatch(ctx, batch).Close()
}

func (t *syncTx) GetDrafts(ctx context.Context, ids []string) (map[string]store.Draft, error) {
	out := map[string]store.Draft{}
	if len(ids) == 0 {
		return out, nil
	}
	rows, err := t.tx.Query(ctx, `SELECT seq, id, revision, deleted, updated_at, data
		FROM sync_drafts WHERE profile_id = $1 AND id = ANY($2)`, t.profileID, ids)
	if err != nil {
		return nil, err
	}
	ds, err := pgx.CollectRows(rows, scanDraft)
	for _, d := range ds {
		out[d.ID] = d
	}
	return out, err
}

func (t *syncTx) PutDrafts(ctx context.Context, drafts []store.Draft) error {
	batch := &pgx.Batch{}
	for _, d := range drafts {
		batch.Queue(`INSERT INTO sync_drafts (profile_id, id, seq, revision, deleted, updated_at, data)
			VALUES ($1, $2, $3, $4, $5, $6, $7)
			ON CONFLICT (profile_id, id) DO UPDATE SET seq = EXCLUDED.seq, revision = EXCLUDED.revision,
				deleted = EXCLUDED.deleted, updated_at = EXCLUDED.updated_at, data = EXCLUDED.data`,
			t.profileID, d.ID, d.Seq, d.Revision, d.Deleted, d.UpdatedAt, []byte(d.Data))
	}
	return t.tx.SendBatch(ctx, batch).Close()
}

func (t *syncTx) SetLastSeq(ctx context.Context, seq int64) error {
	_, err := t.tx.Exec(ctx, `UPDATE profiles SET last_seq = $2 WHERE id = $1`, t.profileID, seq)
	if err == nil {
		t.lastSeq = seq
	}
	return err
}

func (t *syncTx) EventsAfter(ctx context.Context, after int64, limit int) ([]store.SyncEvent, error) {
	rows, err := t.tx.Query(ctx, `SELECT seq, id, kind, poem_id, at, device_id, payload
		FROM sync_events WHERE profile_id = $1 AND seq > $2 ORDER BY seq LIMIT $3`, t.profileID, after, limit)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(r pgx.CollectableRow) (store.SyncEvent, error) {
		var e store.SyncEvent
		var payload []byte
		err := r.Scan(&e.Seq, &e.ID, &e.Kind, &e.PoemID, &e.At, &e.DeviceID, &payload)
		e.At = e.At.UTC()
		e.Payload = payload
		return e, err
	})
}

func (t *syncTx) DraftsAfter(ctx context.Context, after int64, limit int) ([]store.Draft, error) {
	rows, err := t.tx.Query(ctx, `SELECT seq, id, revision, deleted, updated_at, data
		FROM sync_drafts WHERE profile_id = $1 AND seq > $2 ORDER BY seq LIMIT $3`, t.profileID, after, limit)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, scanDraft)
}

func scanDraft(r pgx.CollectableRow) (store.Draft, error) {
	var d store.Draft
	var data []byte
	err := r.Scan(&d.Seq, &d.ID, &d.Revision, &d.Deleted, &d.UpdatedAt, &data)
	d.UpdatedAt = d.UpdatedAt.UTC()
	d.Data = data
	return d, err
}

func nonNilProps(p map[string]any) map[string]any {
	if p == nil {
		return map[string]any{}
	}
	return p
}

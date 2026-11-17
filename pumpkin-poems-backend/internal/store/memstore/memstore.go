// Package memstore is an in-memory store.Store for local development,
// simulator demos and tests. All data is lost on restart.
package memstore

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/json"
	"fmt"
	"slices"
	"sort"
	"sync"
	"time"

	"github.com/yefenghua/pumpkin-poems/backend/internal/store"
)

type profileData struct {
	profile store.Profile
	lastSeq int64
	events  []store.SyncEvent // ordered by seq
	eventIx map[string]bool
	drafts  map[string]store.Draft
}

type session struct {
	parentID  string
	expiresAt time.Time
}

// Store is safe for concurrent use; a single mutex serialises everything.
type Store struct {
	mu        sync.Mutex
	analytics map[string]store.AnalyticsEvent
	feedback  map[string]store.Feedback
	parents   map[string]*store.Parent // parentID -> account
	accounts  map[string]string        // accountID -> parentID
	sessions  map[string]session
	profiles  map[string]*profileData
}

var _ store.Store = (*Store)(nil)

func New() *Store {
	return &Store{
		analytics: map[string]store.AnalyticsEvent{},
		feedback:  map[string]store.Feedback{},
		parents:   map[string]*store.Parent{},
		accounts:  map[string]string{},
		sessions:  map[string]session{},
		profiles:  map[string]*profileData{},
	}
}

func (s *Store) InsertAnalyticsEvents(_ context.Context, events []store.AnalyticsEvent) (int, int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	accepted, dups := 0, 0
	for _, e := range events {
		if _, ok := s.analytics[e.ID]; ok {
			dups++
			continue
		}
		e.Props = cloneProps(e.Props)
		s.analytics[e.ID] = e
		accepted++
	}
	return accepted, dups, nil
}

func (s *Store) ListAnalyticsEvents(_ context.Context, from, to time.Time) ([]store.AnalyticsEvent, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	var out []store.AnalyticsEvent
	for _, e := range s.analytics {
		if !e.At.Before(from) && e.At.Before(to) {
			e.Props = cloneProps(e.Props)
			out = append(out, e)
		}
	}
	sort.Slice(out, func(i, j int) bool {
		if !out[i].At.Equal(out[j].At) {
			return out[i].At.Before(out[j].At)
		}
		return out[i].ID < out[j].ID
	})
	return out, nil
}

func (s *Store) InsertFeedback(_ context.Context, f store.Feedback) (bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.feedback[f.ID]; ok {
		return false, nil
	}
	s.feedback[f.ID] = f
	return true, nil
}

func (s *Store) CreateParent(_ context.Context, p store.Parent) (store.Parent, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, taken := s.accounts[p.AccountID]; taken {
		return store.Parent{}, store.ErrConflict
	}
	p.ID = newUUID()
	s.parents[p.ID] = &p
	s.accounts[p.AccountID] = p.ID
	return p, nil
}

func (s *Store) ParentByAccountID(_ context.Context, accountID string) (store.Parent, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	id, ok := s.accounts[accountID]
	if !ok {
		return store.Parent{}, store.ErrNotFound
	}
	return *s.parents[id], nil
}

func (s *Store) ParentByID(_ context.Context, parentID string) (store.Parent, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	p, ok := s.parents[parentID]
	if !ok {
		return store.Parent{}, store.ErrNotFound
	}
	return *p, nil
}

func (s *Store) UpdatePassword(_ context.Context, parentID, passwordHash string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	p, ok := s.parents[parentID]
	if !ok {
		return store.ErrNotFound
	}
	p.PasswordHash = passwordHash
	return nil
}

func (s *Store) CreateSession(_ context.Context, parentID string, tokenHash []byte, expiresAt time.Time) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if !s.parentExists(parentID) {
		return store.ErrNotFound
	}
	s.sessions[string(tokenHash)] = session{parentID: parentID, expiresAt: expiresAt}
	return nil
}

func (s *Store) SessionParent(_ context.Context, tokenHash []byte, now time.Time) (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	sess, ok := s.sessions[string(tokenHash)]
	if !ok || !now.Before(sess.expiresAt) {
		return "", store.ErrNotFound
	}
	return sess.parentID, nil
}

func (s *Store) DeleteSession(_ context.Context, tokenHash []byte) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.sessions, string(tokenHash))
	return nil
}

func (s *Store) DeleteOtherSessions(_ context.Context, parentID string, keep []byte) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	for k, sess := range s.sessions {
		if sess.parentID == parentID && k != string(keep) {
			delete(s.sessions, k)
		}
	}
	return nil
}

func (s *Store) DeleteAccount(_ context.Context, parentID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if p, ok := s.parents[parentID]; ok {
		delete(s.accounts, p.AccountID)
		delete(s.parents, parentID)
	}
	for k, sess := range s.sessions {
		if sess.parentID == parentID {
			delete(s.sessions, k)
		}
	}
	for id, p := range s.profiles {
		if p.profile.ParentID == parentID {
			delete(s.profiles, id)
		}
	}
	return nil
}

func (s *Store) ListProfiles(_ context.Context, parentID string) ([]store.Profile, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := []store.Profile{}
	for _, p := range s.profiles {
		if p.profile.ParentID == parentID {
			out = append(out, p.profile)
		}
	}
	sort.Slice(out, func(i, j int) bool {
		if !out[i].CreatedAt.Equal(out[j].CreatedAt) {
			return out[i].CreatedAt.Before(out[j].CreatedAt)
		}
		return out[i].ID < out[j].ID
	})
	return out, nil
}

func (s *Store) CreateProfile(_ context.Context, p store.Profile) (store.Profile, bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if existing, ok := s.profiles[p.ID]; ok {
		if existing.profile.ParentID != p.ParentID {
			return store.Profile{}, false, store.ErrConflict
		}
		return existing.profile, false, nil
	}
	if !s.parentExists(p.ParentID) {
		return store.Profile{}, false, store.ErrNotFound
	}
	s.profiles[p.ID] = &profileData{
		profile: p,
		eventIx: map[string]bool{},
		drafts:  map[string]store.Draft{},
	}
	return p, true, nil
}

func (s *Store) UpdateProfile(_ context.Context, parentID, profileID string, patch store.ProfilePatch) (store.Profile, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	pd, ok := s.owned(parentID, profileID)
	if !ok {
		return store.Profile{}, store.ErrNotFound
	}
	if patch.Nickname != nil {
		pd.profile.Nickname = *patch.Nickname
	}
	if patch.SetStage {
		pd.profile.Stage = patch.Stage
	}
	return pd.profile, nil
}

func (s *Store) DeleteProfile(_ context.Context, parentID, profileID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.owned(parentID, profileID); !ok {
		return store.ErrNotFound
	}
	delete(s.profiles, profileID)
	return nil
}

// WithProfileSync holds the global mutex for the duration of fn. Writes go
// straight to the maps: callers validate input before writing and the
// in-memory operations cannot fail, so there is nothing to roll back.
func (s *Store) WithProfileSync(ctx context.Context, parentID, profileID string, fn func(store.SyncTx) error) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	pd, ok := s.owned(parentID, profileID)
	if !ok {
		return store.ErrNotFound
	}
	return fn(&syncTx{pd: pd})
}

func (s *Store) owned(parentID, profileID string) (*profileData, bool) {
	pd, ok := s.profiles[profileID]
	if !ok || pd.profile.ParentID != parentID {
		return nil, false
	}
	return pd, true
}

func (s *Store) parentExists(parentID string) bool {
	_, ok := s.parents[parentID]
	return ok
}

type syncTx struct{ pd *profileData }

func (t *syncTx) LastSeq() int64 { return t.pd.lastSeq }

func (t *syncTx) ExistingEventIDs(_ context.Context, ids []string) (map[string]bool, error) {
	out := map[string]bool{}
	for _, id := range ids {
		if t.pd.eventIx[id] {
			out[id] = true
		}
	}
	return out, nil
}

func (t *syncTx) InsertEvents(_ context.Context, events []store.SyncEvent) error {
	for _, e := range events {
		if t.pd.eventIx[e.ID] {
			return fmt.Errorf("memstore: duplicate event %q", e.ID)
		}
		e.Payload = cloneRaw(e.Payload)
		t.pd.events = append(t.pd.events, e)
		t.pd.eventIx[e.ID] = true
	}
	return nil
}

func (t *syncTx) GetDrafts(_ context.Context, ids []string) (map[string]store.Draft, error) {
	out := map[string]store.Draft{}
	for _, id := range ids {
		if d, ok := t.pd.drafts[id]; ok {
			d.Data = cloneRaw(d.Data)
			out[id] = d
		}
	}
	return out, nil
}

func (t *syncTx) PutDrafts(_ context.Context, drafts []store.Draft) error {
	for _, d := range drafts {
		d.Data = cloneRaw(d.Data)
		t.pd.drafts[d.ID] = d
	}
	return nil
}

func (t *syncTx) SetLastSeq(_ context.Context, seq int64) error {
	t.pd.lastSeq = seq
	return nil
}

func (t *syncTx) EventsAfter(_ context.Context, after int64, limit int) ([]store.SyncEvent, error) {
	i := sort.Search(len(t.pd.events), func(i int) bool { return t.pd.events[i].Seq > after })
	end := min(len(t.pd.events), i+limit)
	out := slices.Clone(t.pd.events[i:end])
	for k := range out {
		out[k].Payload = cloneRaw(out[k].Payload)
	}
	return out, nil
}

func (t *syncTx) DraftsAfter(_ context.Context, after int64, limit int) ([]store.Draft, error) {
	var out []store.Draft
	for _, d := range t.pd.drafts {
		if d.Seq > after {
			d.Data = cloneRaw(d.Data)
			out = append(out, d)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Seq < out[j].Seq })
	if len(out) > limit {
		out = out[:limit]
	}
	return out, nil
}

func cloneRaw(r json.RawMessage) json.RawMessage {
	if r == nil {
		return nil
	}
	return bytes.Clone(r)
}

func cloneProps(p map[string]any) map[string]any {
	if p == nil {
		return nil
	}
	out := make(map[string]any, len(p))
	for k, v := range p {
		out[k] = v
	}
	return out
}

func newUUID() string {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		panic(err)
	}
	b[6] = b[6]&0x0f | 0x40
	b[8] = b[8]&0x3f | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:])
}

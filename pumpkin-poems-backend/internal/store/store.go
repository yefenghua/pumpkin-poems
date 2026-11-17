// Package store defines the persistence boundary of the service. Business
// rules (sync conflicts, metrics) live in other packages and talk to storage
// only through these interfaces, so the in-memory and Postgres
// implementations stay interchangeable.
package store

import (
	"context"
	"encoding/json"
	"errors"
	"time"
)

var (
	// ErrNotFound is returned for missing rows and for rows owned by another
	// parent; callers must not distinguish the two.
	ErrNotFound = errors.New("not found")
	// ErrConflict is returned when a client-chosen ID is already used by
	// another parent, or an account ID is already registered.
	ErrConflict = errors.New("conflict")
)

// Parent is a parent account. AccountID is the lower-cased login name chosen
// by the parent; PasswordHash is a PHC string (see auth.HashPassword). No
// e-mail, phone or name is stored, so a lost password cannot be recovered.
type Parent struct {
	ID           string
	AccountID    string
	PasswordHash string
	CreatedAt    time.Time
}

// AnalyticsEvent is an anonymous trial event (POST /v1/events).
type AnalyticsEvent struct {
	ID             string
	InstallID      string
	AppVersion     string
	Name           string
	At             time.Time
	ContentVersion string
	RuleVersion    *int
	Props          map[string]any // values are string, float64 or bool
}

// Feedback is a parent-written feedback message (POST /v1/feedback).
type Feedback struct {
	ID             string
	InstallID      string
	At             time.Time
	Category       string
	Message        string
	ContentVersion string
	AppVersion     string
}

// Profile is a child profile owned by a parent account.
type Profile struct {
	ID        string
	ParentID  string
	Nickname  string
	Stage     *string
	CreatedAt time.Time
}

// ProfilePatch carries optional updates; a nil field is left unchanged.
// SetStage distinguishes "stage": null (clear) from an absent key.
type ProfilePatch struct {
	Nickname *string
	SetStage bool
	Stage    *string
}

// SyncEvent is an immutable learning event in a profile's sync channel.
// JSON tags match the wire format of /v1/profiles/{id}/sync.
type SyncEvent struct {
	Seq      int64           `json:"seq"`
	ID       string          `json:"id"`
	Kind     string          `json:"kind"`
	PoemID   *string         `json:"poemID,omitempty"`
	At       time.Time       `json:"at"`
	DeviceID string          `json:"deviceID"`
	Payload  json.RawMessage `json:"payload"`
}

// Draft is the latest server version of a creation (作品). A deleted draft is
// a tombstone whose Data is null.
type Draft struct {
	Seq       int64           `json:"seq"`
	ID        string          `json:"id"`
	Revision  int64           `json:"revision"`
	Deleted   bool            `json:"deleted"`
	UpdatedAt time.Time       `json:"updatedAt"`
	Data      json.RawMessage `json:"data"`
}

// Store is implemented by memstore and pgstore.
type Store interface {
	// InsertAnalyticsEvents stores events whose IDs are new and reports how
	// many were accepted versus already present.
	InsertAnalyticsEvents(ctx context.Context, events []AnalyticsEvent) (accepted, duplicates int, err error)
	// ListAnalyticsEvents returns events with from <= At < to.
	ListAnalyticsEvents(ctx context.Context, from, to time.Time) ([]AnalyticsEvent, error)
	// InsertFeedback returns created=false when the ID already exists.
	InsertFeedback(ctx context.Context, f Feedback) (created bool, err error)

	// CreateParent registers an account; ErrConflict if AccountID is taken.
	// The ID is assigned by the store and returned.
	CreateParent(ctx context.Context, p Parent) (Parent, error)
	// ParentByAccountID looks a parent up for login; ErrNotFound if unknown.
	ParentByAccountID(ctx context.Context, accountID string) (Parent, error)
	ParentByID(ctx context.Context, parentID string) (Parent, error)
	// UpdatePassword replaces the hash; ErrNotFound if the parent is gone.
	UpdatePassword(ctx context.Context, parentID, passwordHash string) error
	CreateSession(ctx context.Context, parentID string, tokenHash []byte, expiresAt time.Time) error
	// SessionParent resolves a token hash; expired or unknown tokens yield ErrNotFound.
	SessionParent(ctx context.Context, tokenHash []byte, now time.Time) (parentID string, err error)
	// DeleteSession revokes one token (logout); unknown tokens are not an error.
	DeleteSession(ctx context.Context, tokenHash []byte) error
	// DeleteOtherSessions revokes every session of the parent except keep
	// (nil keeps none), used after a password change.
	DeleteOtherSessions(ctx context.Context, parentID string, keep []byte) error
	// DeleteAccount removes the parent, sessions, profiles and all synced data.
	DeleteAccount(ctx context.Context, parentID string) error

	ListProfiles(ctx context.Context, parentID string) ([]Profile, error)
	// CreateProfile is idempotent: an existing profile with the same ID owned
	// by parentID is returned with created=false. ErrConflict if another
	// parent owns the ID.
	CreateProfile(ctx context.Context, p Profile) (out Profile, created bool, err error)
	UpdateProfile(ctx context.Context, parentID, profileID string, patch ProfilePatch) (Profile, error)
	// DeleteProfile removes the profile with its events and drafts.
	DeleteProfile(ctx context.Context, parentID, profileID string) error

	// WithProfileSync runs fn while holding an exclusive lock on the
	// profile's sync channel; in Postgres this is one transaction that is
	// rolled back if fn returns an error. ErrNotFound if the profile does not
	// belong to parentID.
	WithProfileSync(ctx context.Context, parentID, profileID string, fn func(SyncTx) error) error
}

// SyncTx is the view of one profile's sync channel inside WithProfileSync.
type SyncTx interface {
	// LastSeq is the highest seq allocated in this channel (0 if none).
	LastSeq() int64
	// ExistingEventIDs reports which of ids are already stored.
	ExistingEventIDs(ctx context.Context, ids []string) (map[string]bool, error)
	// InsertEvents stores new events; seqs are already assigned by the caller.
	InsertEvents(ctx context.Context, events []SyncEvent) error
	// GetDrafts returns current server versions for the given IDs.
	GetDrafts(ctx context.Context, ids []string) (map[string]Draft, error)
	// PutDrafts inserts or replaces drafts.
	PutDrafts(ctx context.Context, drafts []Draft) error
	// SetLastSeq persists the channel's seq counter.
	SetLastSeq(ctx context.Context, seq int64) error
	// EventsAfter and DraftsAfter return rows with seq > after in seq order,
	// at most limit rows.
	EventsAfter(ctx context.Context, after int64, limit int) ([]SyncEvent, error)
	DraftsAfter(ctx context.Context, after int64, limit int) ([]Draft, error)
}

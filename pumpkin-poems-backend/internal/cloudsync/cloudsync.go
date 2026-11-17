// Package cloudsync implements the per-profile sync rules of
// POST /v1/profiles/{id}/sync on top of store.SyncTx: event dedupe with
// monotonically increasing seq, revisioned drafts with conflict detection,
// tombstones and cursor paging.
package cloudsync

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/yefenghua/pumpkin-poems/backend/internal/store"
)

// PageLimit is the maximum number of changes (events + drafts) per response.
const PageLimit = 1000

type Request struct {
	Cursor int64     `json:"cursor"`
	Events []InEvent `json:"events"`
	Drafts []InDraft `json:"drafts"`
}

type InEvent struct {
	ID       string          `json:"id"`
	Kind     string          `json:"kind"`
	PoemID   *string         `json:"poemID,omitempty"`
	At       time.Time       `json:"at"`
	DeviceID string          `json:"deviceID"`
	Payload  json.RawMessage `json:"payload"`
}

type InDraft struct {
	ID           string          `json:"id"`
	BaseRevision int64           `json:"baseRevision"`
	Deleted      bool            `json:"deleted"`
	UpdatedAt    time.Time       `json:"updatedAt"`
	Data         json.RawMessage `json:"data"`
}

type DraftResult struct {
	ID       string `json:"id"`
	Status   string `json:"status"` // "applied" | "conflict"
	Revision int64  `json:"revision"`
}

type Response struct {
	Cursor       int64             `json:"cursor"`
	Events       []store.SyncEvent `json:"events"`
	Drafts       []store.Draft     `json:"drafts"`
	DraftResults []DraftResult     `json:"draftResults"`
	HasMore      bool              `json:"hasMore"`
}

const (
	StatusApplied  = "applied"
	StatusConflict = "conflict"
)

// ValidationError marks a malformed request (HTTP 400).
type ValidationError struct{ Msg string }

func (e *ValidationError) Error() string { return e.Msg }

const maxIDLen = 128

// Validate checks request shape before anything is written.
func (r *Request) Validate() error {
	if r.Cursor < 0 {
		return &ValidationError{"cursor must be >= 0"}
	}
	for i, e := range r.Events {
		switch {
		case e.ID == "" || len(e.ID) > maxIDLen:
			return &ValidationError{fmt.Sprintf("events[%d].id is required (max %d chars)", i, maxIDLen)}
		case e.Kind == "" || len(e.Kind) > 64:
			return &ValidationError{fmt.Sprintf("events[%d].kind is required", i)}
		case e.At.IsZero():
			return &ValidationError{fmt.Sprintf("events[%d].at is required", i)}
		case len(e.DeviceID) > maxIDLen:
			return &ValidationError{fmt.Sprintf("events[%d].deviceID too long", i)}
		}
	}
	seen := map[string]bool{}
	for i, d := range r.Drafts {
		switch {
		case d.ID == "" || len(d.ID) > maxIDLen:
			return &ValidationError{fmt.Sprintf("drafts[%d].id is required (max %d chars)", i, maxIDLen)}
		case d.BaseRevision < 0:
			return &ValidationError{fmt.Sprintf("drafts[%d].baseRevision must be >= 0", i)}
		case seen[d.ID]:
			return &ValidationError{fmt.Sprintf("drafts[%d].id %q appears twice", i, d.ID)}
		}
		seen[d.ID] = true
	}
	return nil
}

// Apply pushes the request's events and drafts into the profile channel and
// returns every change with seq > req.Cursor (paged), plus the current server
// version of each conflicting draft.
func Apply(ctx context.Context, st store.Store, parentID, profileID string, req Request) (*Response, error) {
	if err := req.Validate(); err != nil {
		return nil, err
	}
	var resp *Response
	err := st.WithProfileSync(ctx, parentID, profileID, func(tx store.SyncTx) error {
		var err error
		resp, err = apply(ctx, tx, req)
		return err
	})
	return resp, err
}

func apply(ctx context.Context, tx store.SyncTx, req Request) (*Response, error) {
	seq := tx.LastSeq()

	// Events: dedupe by (profile, id), including duplicates within the request.
	ids := make([]string, len(req.Events))
	for i, e := range req.Events {
		ids[i] = e.ID
	}
	existing, err := tx.ExistingEventIDs(ctx, ids)
	if err != nil {
		return nil, err
	}
	var newEvents []store.SyncEvent
	for _, e := range req.Events {
		if existing[e.ID] {
			continue
		}
		existing[e.ID] = true
		seq++
		payload := e.Payload
		if len(payload) == 0 {
			payload = json.RawMessage("null")
		}
		newEvents = append(newEvents, store.SyncEvent{
			Seq: seq, ID: e.ID, Kind: e.Kind, PoemID: e.PoemID,
			At: e.At.UTC(), DeviceID: e.DeviceID, Payload: payload,
		})
	}
	if len(newEvents) > 0 {
		if err := tx.InsertEvents(ctx, newEvents); err != nil {
			return nil, err
		}
	}

	// Drafts: optimistic concurrency on revision. A tombstone keeps its
	// revision, so a stale device (baseRevision < tombstone revision) gets a
	// conflict instead of resurrecting the draft.
	draftIDs := make([]string, len(req.Drafts))
	for i, d := range req.Drafts {
		draftIDs[i] = d.ID
	}
	current, err := tx.GetDrafts(ctx, draftIDs)
	if err != nil {
		return nil, err
	}
	results := make([]DraftResult, 0, len(req.Drafts))
	var writes []store.Draft
	conflicts := map[string]store.Draft{}
	for _, d := range req.Drafts {
		cur, exists := current[d.ID]
		var curRev int64
		if exists {
			curRev = cur.Revision
		}
		if d.BaseRevision != curRev {
			results = append(results, DraftResult{ID: d.ID, Status: StatusConflict, Revision: curRev})
			if exists {
				conflicts[d.ID] = cur
			}
			continue
		}
		seq++
		nd := store.Draft{
			Seq: seq, ID: d.ID, Revision: curRev + 1, Deleted: d.Deleted,
			UpdatedAt: d.UpdatedAt.UTC(), Data: d.Data,
		}
		if nd.UpdatedAt.IsZero() {
			nd.UpdatedAt = time.Now().UTC()
		}
		if d.Deleted || len(nd.Data) == 0 {
			nd.Data = json.RawMessage("null")
		}
		writes = append(writes, nd)
		results = append(results, DraftResult{ID: d.ID, Status: StatusApplied, Revision: nd.Revision})
	}
	if len(writes) > 0 {
		if err := tx.PutDrafts(ctx, writes); err != nil {
			return nil, err
		}
	}
	if seq != tx.LastSeq() {
		if err := tx.SetLastSeq(ctx, seq); err != nil {
			return nil, err
		}
	}

	// Changes since cursor, merged by seq and capped at PageLimit.
	evs, err := tx.EventsAfter(ctx, req.Cursor, PageLimit+1)
	if err != nil {
		return nil, err
	}
	drs, err := tx.DraftsAfter(ctx, req.Cursor, PageLimit+1)
	if err != nil {
		return nil, err
	}
	resp := &Response{Cursor: seq, Events: []store.SyncEvent{}, Drafts: []store.Draft{}, DraftResults: results}
	if req.Cursor > seq {
		// Client cursor is ahead of the server (e.g. data was deleted); report
		// the real position so the client can resync.
		resp.Cursor = seq
	}
	i, j := 0, 0
	for n := 0; n < PageLimit && (i < len(evs) || j < len(drs)); n++ {
		if j >= len(drs) || (i < len(evs) && evs[i].Seq < drs[j].Seq) {
			resp.Events = append(resp.Events, evs[i])
			i++
		} else {
			resp.Drafts = append(resp.Drafts, drs[j])
			j++
		}
	}
	if i < len(evs) || j < len(drs) {
		resp.HasMore = true
		var last int64
		if len(resp.Events) > 0 {
			last = resp.Events[len(resp.Events)-1].Seq
		}
		if len(resp.Drafts) > 0 {
			last = max(last, resp.Drafts[len(resp.Drafts)-1].Seq)
		}
		resp.Cursor = last
	}

	// Conflicting drafts must reach the client even if their seq is at or
	// below the cursor (or beyond this page).
	inPage := map[string]bool{}
	for _, d := range resp.Drafts {
		inPage[d.ID] = true
	}
	for _, d := range req.Drafts {
		if c, ok := conflicts[d.ID]; ok && !inPage[d.ID] {
			resp.Drafts = append(resp.Drafts, c)
			inPage[d.ID] = true
		}
	}
	return resp, nil
}

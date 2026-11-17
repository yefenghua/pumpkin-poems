// Package storetest is a conformance suite run against every store.Store
// implementation. Sync behaviour is exercised through cloudsync.Apply so the
// rules are verified end to end on each backend.
package storetest

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"testing"
	"time"

	"github.com/yefenghua/pumpkin-poems/backend/internal/cloudsync"
	"github.com/yefenghua/pumpkin-poems/backend/internal/store"
)

// Run executes the suite; newStore must return an empty store.
func Run(t *testing.T, newStore func(t *testing.T) store.Store) {
	tests := map[string]func(*testing.T, store.Store){
		"AnalyticsDedupe":          testAnalyticsDedupe,
		"FeedbackIdempotent":       testFeedbackIdempotent,
		"Accounts":                 testAccounts,
		"Sessions":                 testSessions,
		"ProfileOwnership":         testProfileOwnership,
		"SyncEventDedupe":          testSyncEventDedupe,
		"SyncCursorPaging":         testSyncCursorPaging,
		"DraftRevisionConflict":    testDraftRevisionConflict,
		"TombstoneBlocksResurrect": testTombstone,
		"DeleteProfileRemovesData": testDeleteProfile,
		"DeleteAccountRemovesData": testDeleteAccount,
	}
	for name, fn := range tests {
		t.Run(name, func(t *testing.T) { fn(t, newStore(t)) })
	}
}

var t0 = time.Date(2026, 11, 1, 3, 4, 5, 0, time.UTC)

func ctx() context.Context { return context.Background() }

func parent(t *testing.T, s store.Store, key string) string {
	t.Helper()
	p, err := s.CreateParent(ctx(), store.Parent{AccountID: key, PasswordHash: "$hash:" + key, CreatedAt: t0})
	if err != nil {
		t.Fatal(err)
	}
	return p.ID
}

func profile(t *testing.T, s store.Store, parentID, id string) {
	t.Helper()
	if _, _, err := s.CreateProfile(ctx(), store.Profile{ID: id, ParentID: parentID, Nickname: "小明", CreatedAt: t0}); err != nil {
		t.Fatal(err)
	}
}

func ev(id string) cloudsync.InEvent {
	poem := "hk-ks1-10"
	return cloudsync.InEvent{ID: id, Kind: "quiz", PoemID: &poem, At: t0, DeviceID: "dev-1",
		Payload: json.RawMessage(`{"score":5,"answers":[1,2]}`)}
}

func sync(t *testing.T, s store.Store, parentID, profileID string, req cloudsync.Request) *cloudsync.Response {
	t.Helper()
	resp, err := cloudsync.Apply(ctx(), s, parentID, profileID, req)
	if err != nil {
		t.Fatalf("sync: %v", err)
	}
	return resp
}

func testAnalyticsDedupe(t *testing.T, s store.Store) {
	mk := func(id string) store.AnalyticsEvent {
		return store.AnalyticsEvent{ID: id, InstallID: "i1", Name: "quiz_completed", At: t0,
			ContentVersion: "r1", Props: map[string]any{"passed": true, "n": 2.0, "poemID": "x"}}
	}
	acc, dup, err := s.InsertAnalyticsEvents(ctx(), []store.AnalyticsEvent{mk("a"), mk("b"), mk("a")})
	if err != nil || acc != 2 || dup != 1 {
		t.Fatalf("first insert = %d,%d,%v; want 2,1", acc, dup, err)
	}
	acc, dup, err = s.InsertAnalyticsEvents(ctx(), []store.AnalyticsEvent{mk("a"), mk("c")})
	if err != nil || acc != 1 || dup != 1 {
		t.Fatalf("second insert = %d,%d,%v; want 1,1", acc, dup, err)
	}
	got, err := s.ListAnalyticsEvents(ctx(), t0, t0.Add(time.Second))
	if err != nil || len(got) != 3 {
		t.Fatalf("list = %d,%v; want 3", len(got), err)
	}
	if got[0].Props["passed"] != true || got[0].Props["n"] != 2.0 {
		t.Fatalf("props round trip: %#v", got[0].Props)
	}
	if got, _ := s.ListAnalyticsEvents(ctx(), t0.Add(time.Second), t0.Add(time.Hour)); len(got) != 0 {
		t.Fatalf("window should exclude events, got %d", len(got))
	}
}

func testFeedbackIdempotent(t *testing.T, s store.Store) {
	f := store.Feedback{ID: "f1", InstallID: "i1", At: t0, Category: "bug", Message: "按鈕無反應"}
	if created, err := s.InsertFeedback(ctx(), f); err != nil || !created {
		t.Fatalf("first = %v,%v", created, err)
	}
	if created, err := s.InsertFeedback(ctx(), f); err != nil || created {
		t.Fatalf("second = %v,%v; want not created", created, err)
	}
}

func testAccounts(t *testing.T, s store.Store) {
	p1 := parent(t, s, "k1")
	if _, err := s.CreateParent(ctx(), store.Parent{AccountID: "k1", PasswordHash: "x", CreatedAt: t0}); !errors.Is(err, store.ErrConflict) {
		t.Fatalf("duplicate account err = %v; want ErrConflict", err)
	}
	if p2 := parent(t, s, "k2"); p2 == p1 {
		t.Fatal("different accounts share a parent")
	}
	got, err := s.ParentByAccountID(ctx(), "k1")
	if err != nil || got.ID != p1 || got.AccountID != "k1" || got.PasswordHash != "$hash:k1" || !got.CreatedAt.Equal(t0) {
		t.Fatalf("lookup = %+v, %v", got, err)
	}
	if _, err := s.ParentByAccountID(ctx(), "nobody"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("unknown account err = %v", err)
	}
	if byID, err := s.ParentByID(ctx(), p1); err != nil || byID != got {
		t.Fatalf("ParentByID = %+v, %v; want %+v", byID, err, got)
	}
	if _, err := s.ParentByID(ctx(), "00000000-0000-4000-8000-000000000000"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("unknown parent id err = %v", err)
	}
	if err := s.UpdatePassword(ctx(), p1, "$hash:new"); err != nil {
		t.Fatal(err)
	}
	if got, _ := s.ParentByAccountID(ctx(), "k1"); got.PasswordHash != "$hash:new" {
		t.Fatalf("password not updated: %+v", got)
	}
	if err := s.UpdatePassword(ctx(), "00000000-0000-4000-8000-000000000000", "x"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("update unknown parent err = %v", err)
	}
	if err := s.DeleteAccount(ctx(), p1); err != nil {
		t.Fatal(err)
	}
	// The account ID is free again after deletion.
	if again := parent(t, s, "k1"); again == p1 {
		t.Fatal("deleted parent id reused")
	}
}

func testSessions(t *testing.T, s store.Store) {
	p1, p2 := parent(t, s, "k1"), parent(t, s, "k2")
	h1, h2, h3 := []byte("0123456789abcdef0123456789abcdef"), []byte("session-2-session-2-session-2-ab"), []byte("other-parent-other-parent-other-")
	for _, c := range []struct {
		p string
		h []byte
	}{{p1, h1}, {p1, h2}, {p2, h3}} {
		if err := s.CreateSession(ctx(), c.p, c.h, t0.Add(time.Hour)); err != nil {
			t.Fatal(err)
		}
	}
	if got, err := s.SessionParent(ctx(), h1, t0); err != nil || got != p1 {
		t.Fatalf("session = %q,%v", got, err)
	}
	if _, err := s.SessionParent(ctx(), h1, t0.Add(time.Hour)); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("expired session err = %v", err)
	}
	if err := s.DeleteOtherSessions(ctx(), p1, h1); err != nil {
		t.Fatal(err)
	}
	if _, err := s.SessionParent(ctx(), h2, t0); !errors.Is(err, store.ErrNotFound) {
		t.Fatal("other session of p1 survived")
	}
	if got, _ := s.SessionParent(ctx(), h1, t0); got != p1 {
		t.Fatal("kept session revoked")
	}
	if got, _ := s.SessionParent(ctx(), h3, t0); got != p2 {
		t.Fatal("p2's session revoked")
	}
	if err := s.DeleteSession(ctx(), h1); err != nil {
		t.Fatal(err)
	}
	if err := s.DeleteSession(ctx(), h1); err != nil {
		t.Fatalf("deleting a revoked token must be a no-op, got %v", err)
	}
	if _, err := s.SessionParent(ctx(), h1, t0); !errors.Is(err, store.ErrNotFound) {
		t.Fatal("logout did not revoke token")
	}
	if err := s.DeleteOtherSessions(ctx(), p2, nil); err != nil {
		t.Fatal(err)
	}
	if _, err := s.SessionParent(ctx(), h3, t0); !errors.Is(err, store.ErrNotFound) {
		t.Fatal("DeleteOtherSessions(nil) kept a session")
	}
}

func testProfileOwnership(t *testing.T, s store.Store) {
	alice, bob := parent(t, s, "alice"), parent(t, s, "bob")
	p, created, err := s.CreateProfile(ctx(), store.Profile{ID: "p1", ParentID: alice, Nickname: "小明", CreatedAt: t0})
	if err != nil || !created || p.Nickname != "小明" {
		t.Fatalf("create = %+v,%v,%v", p, created, err)
	}
	p, created, err = s.CreateProfile(ctx(), store.Profile{ID: "p1", ParentID: alice, Nickname: "other", CreatedAt: t0.Add(time.Hour)})
	if err != nil || created || p.Nickname != "小明" || !p.CreatedAt.Equal(t0) {
		t.Fatalf("idempotent create = %+v,%v,%v", p, created, err)
	}
	if _, _, err := s.CreateProfile(ctx(), store.Profile{ID: "p1", ParentID: bob, Nickname: "x", CreatedAt: t0}); !errors.Is(err, store.ErrConflict) {
		t.Fatalf("bob create err = %v; want ErrConflict", err)
	}
	if ps, _ := s.ListProfiles(ctx(), bob); len(ps) != 0 {
		t.Fatalf("bob sees %d profiles", len(ps))
	}
	nick := "小華"
	if _, err := s.UpdateProfile(ctx(), bob, "p1", store.ProfilePatch{Nickname: &nick}); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("bob update err = %v", err)
	}
	if err := s.DeleteProfile(ctx(), bob, "p1"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("bob delete err = %v", err)
	}
	if _, err := cloudsync.Apply(ctx(), s, bob, "p1", cloudsync.Request{}); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("bob sync err = %v", err)
	}
	stage := "p5"
	p, err = s.UpdateProfile(ctx(), alice, "p1", store.ProfilePatch{SetStage: true, Stage: &stage})
	if err != nil || p.Nickname != "小明" || p.Stage == nil || *p.Stage != "p5" {
		t.Fatalf("stage update = %+v,%v", p, err)
	}
	p, err = s.UpdateProfile(ctx(), alice, "p1", store.ProfilePatch{Nickname: &nick, SetStage: true})
	if err != nil || p.Nickname != "小華" || p.Stage != nil {
		t.Fatalf("nickname+clear stage = %+v,%v", p, err)
	}
	if ps, _ := s.ListProfiles(ctx(), alice); len(ps) != 1 || ps[0].ID != "p1" {
		t.Fatalf("alice profiles = %+v", ps)
	}
}

func testSyncEventDedupe(t *testing.T, s store.Store) {
	a := parent(t, s, "a")
	profile(t, s, a, "p1")
	r1 := sync(t, s, a, "p1", cloudsync.Request{Events: []cloudsync.InEvent{ev("e1"), ev("e2"), ev("e1")}})
	if r1.Cursor != 2 || len(r1.Events) != 2 || r1.Events[0].Seq != 1 || r1.Events[1].Seq != 2 {
		t.Fatalf("first push: %+v", r1)
	}
	if string(r1.Events[0].Payload) != `{"score":5,"answers":[1,2]}` || *r1.Events[0].PoemID != "hk-ks1-10" || !r1.Events[0].At.Equal(t0) {
		t.Fatalf("event not preserved: %+v", r1.Events[0])
	}
	// Re-upload from a second device (guest migration repeated): no new seqs.
	changed := ev("e1")
	changed.Payload = json.RawMessage(`{"tampered":true}`)
	r2 := sync(t, s, a, "p1", cloudsync.Request{Cursor: 2, Events: []cloudsync.InEvent{changed, ev("e3")}})
	if r2.Cursor != 3 || len(r2.Events) != 1 || r2.Events[0].ID != "e3" || r2.Events[0].Seq != 3 {
		t.Fatalf("second push: %+v", r2)
	}
	all := sync(t, s, a, "p1", cloudsync.Request{})
	if len(all.Events) != 3 || string(all.Events[0].Payload) != `{"score":5,"answers":[1,2]}` {
		t.Fatalf("existing event was rewritten: %+v", all.Events)
	}
	// Same event IDs in another profile are independent.
	profile(t, s, a, "p2")
	if r := sync(t, s, a, "p2", cloudsync.Request{Events: []cloudsync.InEvent{ev("e1")}}); r.Cursor != 1 || len(r.Events) != 1 {
		t.Fatalf("other profile: %+v", r)
	}
}

func testSyncCursorPaging(t *testing.T, s store.Store) {
	a := parent(t, s, "a")
	profile(t, s, a, "p1")
	var evs []cloudsync.InEvent
	for i := range 1500 {
		evs = append(evs, ev(fmt.Sprintf("e%04d", i)))
	}
	r := sync(t, s, a, "p1", cloudsync.Request{Events: evs[:1200]})
	if !r.HasMore || len(r.Events) != 1000 || r.Cursor != 1000 {
		t.Fatalf("page 1: hasMore=%v n=%d cursor=%d", r.HasMore, len(r.Events), r.Cursor)
	}
	// A draft lands after the 1200 events (seq 1201).
	r = sync(t, s, a, "p1", cloudsync.Request{Cursor: r.Cursor, Drafts: []cloudsync.InDraft{
		{ID: "d1", BaseRevision: 0, UpdatedAt: t0, Data: json.RawMessage(`{"title":"秋"}`)},
	}})
	if r.HasMore || len(r.Events) != 200 || len(r.Drafts) != 1 || r.Cursor != 1201 || r.Events[0].Seq != 1001 {
		t.Fatalf("page 2: hasMore=%v events=%d drafts=%d cursor=%d", r.HasMore, len(r.Events), len(r.Drafts), r.Cursor)
	}
	r = sync(t, s, a, "p1", cloudsync.Request{Cursor: r.Cursor, Events: evs[1200:]})
	if r.HasMore || len(r.Events) != 300 || r.Cursor != 1501 {
		t.Fatalf("page 3: hasMore=%v n=%d cursor=%d", r.HasMore, len(r.Events), r.Cursor)
	}
	r = sync(t, s, a, "p1", cloudsync.Request{Cursor: r.Cursor})
	if r.HasMore || len(r.Events) != 0 || len(r.Drafts) != 0 || r.Cursor != 1501 {
		t.Fatalf("idle: %+v", r)
	}
	// Full resync from 0 in pages; seqs strictly increase across pages.
	cursor, seen, last := int64(0), 0, int64(0)
	for range 5 {
		r = sync(t, s, a, "p1", cloudsync.Request{Cursor: cursor})
		for _, e := range r.Events {
			if e.Seq <= last {
				t.Fatalf("seq not increasing: %d after %d", e.Seq, last)
			}
			last = e.Seq
		}
		seen += len(r.Events) + len(r.Drafts)
		cursor = r.Cursor
		if !r.HasMore {
			break
		}
	}
	if seen != 1501 || cursor != 1501 {
		t.Fatalf("resync saw %d changes, cursor %d", seen, cursor)
	}
}

func testDraftRevisionConflict(t *testing.T, s store.Store) {
	a := parent(t, s, "a")
	profile(t, s, a, "p1")
	d := func(base int64, title string) cloudsync.InDraft {
		return cloudsync.InDraft{ID: "d1", BaseRevision: base, UpdatedAt: t0,
			Data: json.RawMessage(fmt.Sprintf(`{"title":%q}`, title))}
	}
	r := sync(t, s, a, "p1", cloudsync.Request{Drafts: []cloudsync.InDraft{d(0, "v1")}})
	if res := r.DraftResults[0]; res.Status != cloudsync.StatusApplied || res.Revision != 1 {
		t.Fatalf("create: %+v", res)
	}
	cursorA := r.Cursor
	// Device A edits (base 1 -> 2).
	r = sync(t, s, a, "p1", cloudsync.Request{Cursor: cursorA, Drafts: []cloudsync.InDraft{d(1, "A")}})
	if res := r.DraftResults[0]; res.Status != cloudsync.StatusApplied || res.Revision != 2 {
		t.Fatalf("A edit: %+v", res)
	}
	// Device B still on revision 1, and its cursor already covers seq 2... the
	// conflicting server version must be returned regardless of the cursor.
	r = sync(t, s, a, "p1", cloudsync.Request{Cursor: 100, Drafts: []cloudsync.InDraft{d(1, "B")}})
	res := r.DraftResults[0]
	if res.Status != cloudsync.StatusConflict || res.Revision != 2 {
		t.Fatalf("B edit: %+v", res)
	}
	if len(r.Drafts) != 1 || r.Drafts[0].Revision != 2 || string(r.Drafts[0].Data) != `{"title":"A"}` {
		t.Fatalf("conflict response drafts: %+v", r.Drafts)
	}
	// Server version unchanged; B's conflict copy is a new draft.
	r = sync(t, s, a, "p1", cloudsync.Request{Drafts: []cloudsync.InDraft{
		{ID: "d1-copy", BaseRevision: 0, UpdatedAt: t0, Data: json.RawMessage(`{"title":"B","conflictOf":"d1"}`)},
	}})
	if len(r.Drafts) != 2 {
		t.Fatalf("want both versions kept, got %+v", r.Drafts)
	}
	// A base revision ahead of the server is also a conflict.
	r = sync(t, s, a, "p1", cloudsync.Request{Drafts: []cloudsync.InDraft{d(7, "future")}})
	if r.DraftResults[0].Status != cloudsync.StatusConflict {
		t.Fatalf("future base: %+v", r.DraftResults[0])
	}
}

func testTombstone(t *testing.T, s store.Store) {
	a := parent(t, s, "a")
	profile(t, s, a, "p1")
	sync(t, s, a, "p1", cloudsync.Request{Drafts: []cloudsync.InDraft{
		{ID: "d1", BaseRevision: 0, UpdatedAt: t0, Data: json.RawMessage(`{"title":"v1"}`)},
	}})
	r := sync(t, s, a, "p1", cloudsync.Request{Drafts: []cloudsync.InDraft{
		{ID: "d1", BaseRevision: 1, Deleted: true, UpdatedAt: t0, Data: json.RawMessage(`{"title":"v1"}`)},
	}})
	if res := r.DraftResults[0]; res.Status != cloudsync.StatusApplied || res.Revision != 2 {
		t.Fatalf("delete: %+v", res)
	}
	var tomb store.Draft
	for _, d := range r.Drafts {
		if d.ID == "d1" {
			tomb = d
		}
	}
	if !tomb.Deleted || string(tomb.Data) != "null" {
		t.Fatalf("tombstone = %+v", tomb)
	}
	// An old device that never saw the deletion tries to save (base 1) and
	// to recreate it (base 0): both conflict and receive the tombstone.
	for _, base := range []int64{1, 0} {
		r = sync(t, s, a, "p1", cloudsync.Request{Cursor: 1000, Drafts: []cloudsync.InDraft{
			{ID: "d1", BaseRevision: base, UpdatedAt: t0, Data: json.RawMessage(`{"title":"zombie"}`)},
		}})
		res := r.DraftResults[0]
		if res.Status != cloudsync.StatusConflict || res.Revision != 2 {
			t.Fatalf("base %d: %+v", base, res)
		}
		if len(r.Drafts) != 1 || !r.Drafts[0].Deleted {
			t.Fatalf("base %d drafts: %+v", base, r.Drafts)
		}
	}
	all := sync(t, s, a, "p1", cloudsync.Request{})
	if len(all.Drafts) != 1 || !all.Drafts[0].Deleted || all.Drafts[0].Revision != 2 {
		t.Fatalf("draft resurrected: %+v", all.Drafts)
	}
}

func testDeleteProfile(t *testing.T, s store.Store) {
	a := parent(t, s, "a")
	profile(t, s, a, "p1")
	sync(t, s, a, "p1", cloudsync.Request{Events: []cloudsync.InEvent{ev("e1")}, Drafts: []cloudsync.InDraft{
		{ID: "d1", UpdatedAt: t0, Data: json.RawMessage(`{}`)},
	}})
	if err := s.DeleteProfile(ctx(), a, "p1"); err != nil {
		t.Fatal(err)
	}
	if _, err := cloudsync.Apply(ctx(), s, a, "p1", cloudsync.Request{}); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("sync after delete: %v", err)
	}
	profile(t, s, a, "p1")
	if r := sync(t, s, a, "p1", cloudsync.Request{}); r.Cursor != 0 || len(r.Events)+len(r.Drafts) != 0 {
		t.Fatalf("data survived profile deletion: %+v", r)
	}
}

func testDeleteAccount(t *testing.T, s store.Store) {
	a, b := parent(t, s, "a"), parent(t, s, "b")
	profile(t, s, a, "pa")
	profile(t, s, b, "pb")
	hash := []byte("session-hash-for-account-a-00000")
	if err := s.CreateSession(ctx(), a, hash, t0.Add(time.Hour)); err != nil {
		t.Fatal(err)
	}
	sync(t, s, a, "pa", cloudsync.Request{Events: []cloudsync.InEvent{ev("e1")}})
	sync(t, s, b, "pb", cloudsync.Request{Events: []cloudsync.InEvent{ev("e1")}})

	if err := s.DeleteAccount(ctx(), a); err != nil {
		t.Fatal(err)
	}
	if _, err := s.SessionParent(ctx(), hash, t0); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("session survived: %v", err)
	}
	if ps, _ := s.ListProfiles(ctx(), a); len(ps) != 0 {
		t.Fatalf("profiles survived: %+v", ps)
	}
	if _, err := cloudsync.Apply(ctx(), s, a, "pa", cloudsync.Request{}); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("sync data reachable: %v", err)
	}
	// Signing in again yields a fresh, empty account.
	if again := parent(t, s, "a"); again == a {
		t.Fatal("deleted account was reused")
	}
	// The other family is untouched.
	if r := sync(t, s, b, "pb", cloudsync.Request{}); len(r.Events) != 1 {
		t.Fatalf("other account affected: %+v", r)
	}
}

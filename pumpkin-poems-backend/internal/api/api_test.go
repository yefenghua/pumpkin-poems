package api

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/yefenghua/pumpkin-poems/backend/internal/auth"
	"github.com/yefenghua/pumpkin-poems/backend/internal/content"
	"github.com/yefenghua/pumpkin-poems/backend/internal/store/memstore"
)

const adminToken = "admin-secret"

type env struct {
	t          *testing.T
	srv        *httptest.Server
	contentDir string
	now        time.Time
}

func newEnv(t *testing.T) *env {
	t.Helper()
	e := &env{t: t, contentDir: t.TempDir(), now: time.Date(2026, 11, 20, 0, 0, 0, 0, time.UTC)}
	h := New(Config{
		Store:      memstore.New(),
		Content:    content.NewRepo(e.contentDir),
		AdminToken: adminToken,
		Logger:     slog.New(slog.NewTextHandler(io.Discard, nil)),
		Now:        func() time.Time { return e.now },
	})
	e.srv = httptest.NewServer(h)
	t.Cleanup(e.srv.Close)
	return e
}

type resp struct {
	status int
	header http.Header
	body   []byte
}

func (r resp) json(t *testing.T, v any) {
	t.Helper()
	if err := json.Unmarshal(r.body, v); err != nil {
		t.Fatalf("decode %s: %v", r.body, err)
	}
}

func (r resp) errCode(t *testing.T) string {
	t.Helper()
	var b errorBody
	r.json(t, &b)
	return b.Error.Code
}

func (e *env) do(method, path, token string, body any, hdr ...string) resp {
	e.t.Helper()
	var rd io.Reader
	switch b := body.(type) {
	case nil:
	case string:
		rd = strings.NewReader(b)
	default:
		j, _ := json.Marshal(b)
		rd = bytes.NewReader(j)
	}
	req, _ := http.NewRequest(method, e.srv.URL+path, rd)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	for i := 0; i+1 < len(hdr); i += 2 {
		req.Header.Set(hdr[i], hdr[i+1])
	}
	res, err := e.srv.Client().Do(req)
	if err != nil {
		e.t.Fatal(err)
	}
	defer res.Body.Close()
	b, _ := io.ReadAll(res.Body)
	return resp{res.StatusCode, res.Header, b}
}

const testPassword = "correct horse battery"

// login registers the account on first use and signs in afterwards.
func (e *env) login(accountID string) (token, parentID string) {
	e.t.Helper()
	creds := map[string]string{"accountID": accountID, "password": testPassword}
	r := e.do("POST", "/v1/auth/register", "", creds)
	if r.status == 409 {
		r = e.do("POST", "/v1/auth/login", "", creds)
	}
	if r.status != 200 && r.status != 201 {
		e.t.Fatalf("auth: %d %s", r.status, r.body)
	}
	var tr tokenResponse
	r.json(e.t, &tr)
	return tr.AccessToken, tr.ParentID
}

func TestContentEndpoints(t *testing.T) {
	e := newEnv(t)
	r := e.do("GET", "/healthz", "", nil)
	if r.status != 200 || string(bytes.TrimSpace(r.body)) != `{"ok":true,"release":null}` {
		t.Fatalf("healthz before publish: %d %s", r.status, r.body)
	}
	if r := e.do("GET", "/v1/content/manifest", "", nil); r.status != 404 || r.errCode(t) != "no_release" {
		t.Fatalf("manifest before publish: %d %s", r.status, r.body)
	}

	_, err := content.Publish(content.PublishOptions{
		PacksDir: "../content/testdata/packs", ReviewFile: "../content/testdata/review-status.json",
		OutDir: e.contentDir, Release: "2026-11-01.1", AllowUnreviewed: true, Now: e.now,
	})
	if err != nil {
		t.Fatal(err)
	}
	r = e.do("GET", "/healthz", "", nil)
	if !strings.Contains(string(r.body), `"release":"2026-11-01.1"`) {
		t.Fatalf("healthz: %s", r.body)
	}
	r = e.do("GET", "/v1/content/manifest", "", nil)
	if r.status != 200 || r.header.Get("Cache-Control") != "no-cache" {
		t.Fatalf("manifest: %d %v", r.status, r.header)
	}
	var m content.Manifest
	r.json(t, &m)
	if m.Release != "2026-11-01.1" || len(m.Packs) != 2 || m.WithdrawnQuestions == nil {
		t.Fatalf("manifest = %+v", m)
	}
	if r2 := e.do("GET", "/v1/content/manifest", "", nil, "If-None-Match", r.header.Get("ETag")); r2.status != 304 {
		t.Fatalf("conditional manifest: %d", r2.status)
	}
	for _, p := range m.Packs {
		pr := e.do("GET", p.URL, "", nil)
		sum := sha256.Sum256(pr.body)
		if pr.status != 200 || int64(len(pr.body)) != p.Size || hex.EncodeToString(sum[:]) != p.SHA256 {
			t.Fatalf("pack %s: status %d, size %d/%d", p.ID, pr.status, len(pr.body), p.Size)
		}
		if !strings.Contains(pr.header.Get("Cache-Control"), "immutable") {
			t.Fatalf("pack cache header: %v", pr.header)
		}
	}
	for _, path := range []string{"/v1/content/packs/base/2026-11-01.1.json", "/v1/content/packs/farewell/x.json",
		"/v1/content/packs/farewell/2026-11-01.1", "/v1/content/packs/../current"} {
		if r := e.do("GET", path, "", nil); r.status != 404 {
			t.Fatalf("%s: %d", path, r.status)
		}
	}

	// Withdrawing a question is visible without restarting.
	if _, err := content.WithdrawQuestion(e.contentDir, "fw-01-q2", "2026-11-01.2", "t", e.now); err != nil {
		t.Fatal(err)
	}
	e.do("GET", "/v1/content/manifest", "", nil).json(t, &m)
	if m.Release != "2026-11-01.2" || len(m.WithdrawnQuestions) != 1 {
		t.Fatalf("after withdraw: %+v", m)
	}
}

func TestEventsAndFeedback(t *testing.T) {
	e := newEnv(t)
	ev := func(id string) map[string]any {
		return map[string]any{"id": id, "name": "quiz_completed", "at": "2026-11-01T03:04:05Z",
			"contentVersion": "2026-11-01.1", "ruleVersion": 2,
			"props": map[string]any{"poemID": "hk-ks1-10", "passed": true, "isReview": false, "usedHints": false}}
	}
	body := map[string]any{"installID": "inst-1", "appVersion": "1.1", "events": []any{ev("a"), ev("b"), ev("c")}}
	var out map[string]int
	e.do("POST", "/v1/events", "", body).json(t, &out)
	if out["accepted"] != 3 || out["duplicates"] != 0 {
		t.Fatalf("first upload: %v", out)
	}
	body["events"] = []any{ev("a"), ev("b"), ev("d")}
	e.do("POST", "/v1/events", "", body).json(t, &out)
	if out["accepted"] != 1 || out["duplicates"] != 2 {
		t.Fatalf("re-upload: %v", out)
	}

	bad := ev("x")
	bad["props"] = map[string]any{"nested": map[string]any{"a": 1}}
	r := e.do("POST", "/v1/events", "", map[string]any{"installID": "i", "events": []any{bad}})
	if r.status != 400 || r.errCode(t) != "invalid_event" {
		t.Fatalf("nested props: %d %s", r.status, r.body)
	}
	if r := e.do("POST", "/v1/events", "", "{not json"); r.status != 400 || r.errCode(t) != "invalid_json" {
		t.Fatalf("bad json: %d %s", r.status, r.body)
	}
	huge := `{"installID":"i","events":[],"pad":"` + strings.Repeat("x", limitEvents) + `"}`
	if r := e.do("POST", "/v1/events", "", huge); r.status != 413 {
		t.Fatalf("oversized body: %d", r.status)
	}

	fb := map[string]any{"id": "fb-1", "installID": "inst-1", "at": "2026-11-01T03:04:05Z", "category": "content",
		"message": "「疑是地上霜」的解釋很好", "contentVersion": "2026-11-01.1", "appVersion": "1.1"}
	if r := e.do("POST", "/v1/feedback", "", fb); r.status != 201 || string(bytes.TrimSpace(r.body)) != "{}" {
		t.Fatalf("feedback: %d %s", r.status, r.body)
	}
	if r := e.do("POST", "/v1/feedback", "", fb); r.status != 200 {
		t.Fatalf("feedback replay: %d", r.status)
	}
	fb["id"], fb["category"] = "fb-2", "spam"
	if r := e.do("POST", "/v1/feedback", "", fb); r.status != 400 {
		t.Fatalf("bad category: %d", r.status)
	}

	// Admin metrics.
	if r := e.do("GET", "/v1/admin/metrics?from=2026-11-01&to=2026-11-15", "", nil); r.status != 401 {
		t.Fatalf("metrics without token: %d", r.status)
	}
	if r := e.do("GET", "/v1/admin/metrics?from=2026-11-01&to=2026-11-15", "wrong", nil); r.status != 401 {
		t.Fatalf("metrics with wrong token: %d", r.status)
	}
	if r := e.do("GET", "/v1/admin/metrics?from=2026-11-15&to=2026-11-01", adminToken, nil); r.status != 400 {
		t.Fatalf("reversed range: %d", r.status)
	}
	e.do("POST", "/v1/events", "", map[string]any{"installID": "inst-1", "events": []any{
		map[string]any{"id": "s1", "name": "poem_learning_started", "at": "2026-11-01T01:00:00Z", "contentVersion": "2026-11-01.1"},
	}})
	r = e.do("GET", "/v1/admin/metrics?from=2026-11-01&to=2026-11-15", adminToken, nil)
	var mr struct {
		From, To string
		Groups   []struct {
			ContentVersion     string
			LearningCompletion struct{ Numerator, Denominator int }
			SecondWeekReturn   struct{ Numerator, Denominator int }
		}
	}
	r.json(t, &mr)
	if r.status != 200 || mr.From != "2026-11-01" || len(mr.Groups) != 1 {
		t.Fatalf("metrics: %d %s", r.status, r.body)
	}
	g := mr.Groups[0]
	if g.ContentVersion != "2026-11-01.1" || g.LearningCompletion.Numerator != 1 || g.LearningCompletion.Denominator != 1 ||
		g.SecondWeekReturn.Denominator != 1 {
		t.Fatalf("metrics group: %+v", g)
	}
}

func TestRegisterAndLogin(t *testing.T) {
	e := newEnv(t)
	var a tokenResponse
	r := e.do("POST", "/v1/auth/register", "", map[string]string{"accountID": " Mama.Lee ", "password": testPassword})
	if r.status != 201 {
		t.Fatalf("register: %d %s", r.status, r.body)
	}
	r.json(t, &a)
	if a.AccessToken == "" || a.ParentID == "" || a.AccountID != "mama.lee" {
		t.Fatalf("register response: %+v", a)
	}
	exp, err := time.Parse(time.RFC3339, a.ExpiresAt)
	if err != nil || !exp.Equal(e.now.Add(auth.TokenTTL)) {
		t.Fatalf("expiresAt = %q", a.ExpiresAt)
	}
	if r := e.do("POST", "/v1/auth/register", "", map[string]string{"accountID": "MAMA.LEE", "password": "another-pass"}); r.status != 409 || r.errCode(t) != "account_id_taken" {
		t.Fatalf("duplicate (case-insensitive) register: %d %s", r.status, r.body)
	}
	for _, c := range []struct{ id, pw, code string }{
		{"ab", testPassword, "invalid_account_id"},
		{"mama@lee", testPassword, "invalid_account_id"},
		{"papa.lee", "short", "weak_password"},
		{"papa.lee", "Papa.Lee", "weak_password"},
	} {
		if r := e.do("POST", "/v1/auth/register", "", map[string]string{"accountID": c.id, "password": c.pw}); r.status != 400 || r.errCode(t) != c.code {
			t.Fatalf("register %q/%q: %d %s", c.id, c.pw, r.status, r.body)
		}
	}

	var b tokenResponse
	r = e.do("POST", "/v1/auth/login", "", map[string]string{"accountID": "MAMA.LEE", "password": testPassword})
	if r.status != 200 {
		t.Fatalf("login: %d %s", r.status, r.body)
	}
	r.json(t, &b)
	if b.ParentID != a.ParentID || b.AccessToken == a.AccessToken || b.AccountID != "mama.lee" {
		t.Fatalf("login must give the same parent with a fresh token: %+v %+v", a, b)
	}
	for _, creds := range []map[string]string{
		{"accountID": "mama.lee", "password": "wrong password"},
		{"accountID": "nobody.here", "password": testPassword},
		{"accountID": "mama.lee", "password": ""},
		{"accountID": "", "password": testPassword},
	} {
		if r := e.do("POST", "/v1/auth/login", "", creds); r.status != 401 || r.errCode(t) != "invalid_credentials" {
			t.Fatalf("login %v: %d %s", creds, r.status, r.body)
		}
	}
	// Both tokens work until they expire.
	for _, tok := range []string{a.AccessToken, b.AccessToken} {
		if r := e.do("GET", "/v1/profiles", tok, nil); r.status != 200 {
			t.Fatalf("token unusable: %d", r.status)
		}
	}
	var acct map[string]string
	e.do("GET", "/v1/account", a.AccessToken, nil).json(t, &acct)
	if acct["accountID"] != "mama.lee" || acct["parentID"] != a.ParentID || acct["createdAt"] == "" {
		t.Fatalf("account: %v", acct)
	}
	e.now = e.now.Add(auth.TokenTTL)
	if r := e.do("GET", "/v1/profiles", a.AccessToken, nil); r.status != 401 {
		t.Fatalf("expired token accepted: %d", r.status)
	}
	// No Apple or dev login any more.
	for _, path := range []string{"/v1/auth/apple", "/v1/auth/dev"} {
		if r := e.do("POST", path, "", map[string]string{"identityToken": "x", "parentKey": "k"}); r.status != 404 {
			t.Fatalf("%s should not exist: %d", path, r.status)
		}
	}
}

func TestLoginThrottle(t *testing.T) {
	e := newEnv(t)
	e.login("mama.lee")
	bad := map[string]string{"accountID": "mama.lee", "password": "wrong password"}
	for i := 0; i < 10; i++ {
		if r := e.do("POST", "/v1/auth/login", "", bad); r.status != 401 {
			t.Fatalf("attempt %d: %d", i, r.status)
		}
	}
	good := map[string]string{"accountID": "mama.lee", "password": testPassword}
	r := e.do("POST", "/v1/auth/login", "", good)
	if r.status != 429 || r.errCode(t) != "too_many_attempts" || r.header.Get("Retry-After") == "" {
		t.Fatalf("after 10 failures even the right password must wait: %d %s %v", r.status, r.body, r.header)
	}
	// Other accounts are unaffected; unknown accounts are throttled too (no enumeration).
	e.login("papa.lee")
	for i := 0; i < 10; i++ {
		e.do("POST", "/v1/auth/login", "", map[string]string{"accountID": "ghost.acct", "password": "x"})
	}
	if r := e.do("POST", "/v1/auth/login", "", map[string]string{"accountID": "ghost.acct", "password": "x"}); r.status != 429 {
		t.Fatalf("unknown account not throttled: %d", r.status)
	}
	e.now = e.now.Add(15*time.Minute + time.Second)
	if r := e.do("POST", "/v1/auth/login", "", good); r.status != 200 {
		t.Fatalf("after the window: %d %s", r.status, r.body)
	}
}

func TestLogoutAndChangePassword(t *testing.T) {
	e := newEnv(t)
	phone, _ := e.login("mama.lee")
	tablet, _ := e.login("mama.lee")
	old, _ := e.login("mama.lee")

	if r := e.do("POST", "/v1/auth/logout", old, nil); r.status != 204 {
		t.Fatalf("logout: %d", r.status)
	}
	if r := e.do("GET", "/v1/profiles", old, nil); r.status != 401 {
		t.Fatalf("token survived logout: %d", r.status)
	}
	if r := e.do("GET", "/v1/profiles", phone, nil); r.status != 200 {
		t.Fatalf("logout revoked another device: %d", r.status)
	}
	if r := e.do("POST", "/v1/auth/logout", "", nil); r.status != 401 {
		t.Fatalf("logout without token: %d", r.status)
	}

	change := func(tok, cur, next string) resp {
		return e.do("POST", "/v1/auth/password", tok, map[string]string{"currentPassword": cur, "newPassword": next})
	}
	if r := change(phone, "wrong password", "new password 123"); r.status != 403 || r.errCode(t) != "wrong_password" {
		t.Fatalf("wrong current password: %d %s", r.status, r.body)
	}
	if r := change(phone, testPassword, "short"); r.status != 400 || r.errCode(t) != "weak_password" {
		t.Fatalf("weak new password: %d %s", r.status, r.body)
	}
	if r := change(phone, testPassword, "new password 123"); r.status != 204 {
		t.Fatalf("change password: %d %s", r.status, r.body)
	}
	if r := e.do("GET", "/v1/profiles", phone, nil); r.status != 200 {
		t.Fatalf("changing device signed out: %d", r.status)
	}
	if r := e.do("GET", "/v1/profiles", tablet, nil); r.status != 401 {
		t.Fatalf("other device still signed in after password change: %d", r.status)
	}
	if r := e.do("POST", "/v1/auth/login", "", map[string]string{"accountID": "mama.lee", "password": testPassword}); r.status != 401 {
		t.Fatalf("old password still works: %d", r.status)
	}
	if r := e.do("POST", "/v1/auth/login", "", map[string]string{"accountID": "mama.lee", "password": "new password 123"}); r.status != 200 {
		t.Fatalf("new password rejected: %d %s", r.status, r.body)
	}
}

func TestProfilesOwnershipAndSync(t *testing.T) {
	e := newEnv(t)
	alice, _ := e.login("alice")
	bob, _ := e.login("bob.chan")

	if r := e.do("GET", "/v1/profiles", "", nil); r.status != 401 || r.errCode(t) != "unauthorized" {
		t.Fatalf("no token: %d", r.status)
	}
	if r := e.do("GET", "/v1/profiles", "garbage", nil); r.status != 401 {
		t.Fatalf("bad token: %d", r.status)
	}

	pid := "8a0b6c1e-0000-4000-8000-000000000001"
	create := map[string]any{"id": pid, "nickname": "小明", "stage": nil}
	r := e.do("POST", "/v1/profiles", alice, create)
	if r.status != 201 || !strings.Contains(string(r.body), `"stage":null`) {
		t.Fatalf("create: %d %s", r.status, r.body)
	}
	create["nickname"] = "改名"
	if r := e.do("POST", "/v1/profiles", alice, create); r.status != 200 || !strings.Contains(string(r.body), "小明") {
		t.Fatalf("idempotent create: %d %s", r.status, r.body)
	}
	if r := e.do("POST", "/v1/profiles", bob, create); r.status != 409 {
		t.Fatalf("bob reusing alice's id: %d", r.status)
	}
	if r := e.do("POST", "/v1/profiles", alice, map[string]any{"id": "p2", "nickname": "x", "stage": "p9"}); r.status != 400 {
		t.Fatalf("bad stage: %d", r.status)
	}

	r = e.do("PATCH", "/v1/profiles/"+pid, alice, map[string]any{"stage": "p5"})
	if r.status != 200 || !strings.Contains(string(r.body), `"stage":"p5"`) || !strings.Contains(string(r.body), "小明") {
		t.Fatalf("patch: %d %s", r.status, r.body)
	}
	r = e.do("PATCH", "/v1/profiles/"+pid, alice, map[string]any{"stage": nil})
	if !strings.Contains(string(r.body), `"stage":null`) {
		t.Fatalf("clear stage: %s", r.body)
	}

	syncBody := map[string]any{
		"cursor": 0,
		"events": []any{map[string]any{"id": "ev-1", "kind": "quiz", "poemID": "hk-ks1-10", "at": "2026-11-01T03:04:05Z",
			"deviceID": "dev-1", "payload": map[string]any{"score": 4}}},
		"drafts": []any{map[string]any{"id": "dr-1", "baseRevision": 0, "deleted": false, "updatedAt": "2026-11-01T03:05:00Z",
			"data": map[string]any{"title": "秋夜", "lines": []string{"月光照窗前"}, "mode": "free", "form": 5, "status": "draft"}}},
	}
	// Bob cannot see, change, sync or delete Alice's profile: always 404.
	for _, c := range []struct {
		method, path string
		body         any
	}{
		{"PATCH", "/v1/profiles/" + pid, map[string]any{"nickname": "x"}},
		{"POST", "/v1/profiles/" + pid + "/sync", syncBody},
		{"DELETE", "/v1/profiles/" + pid, nil},
	} {
		if r := e.do(c.method, c.path, bob, c.body); r.status != 404 || r.errCode(t) != "not_found" {
			t.Fatalf("bob %s %s: %d %s", c.method, c.path, r.status, r.body)
		}
	}
	var bobList struct{ Profiles []any }
	e.do("GET", "/v1/profiles", bob, nil).json(t, &bobList)
	if len(bobList.Profiles) != 0 {
		t.Fatalf("bob lists alice's profiles: %v", bobList)
	}

	r = e.do("POST", "/v1/profiles/"+pid+"/sync", alice, syncBody)
	if r.status != 200 {
		t.Fatalf("sync: %d %s", r.status, r.body)
	}
	var sr map[string]any
	r.json(t, &sr)
	for _, k := range []string{"cursor", "events", "drafts", "draftResults", "hasMore"} {
		if _, ok := sr[k]; !ok {
			t.Fatalf("sync response missing %q: %s", k, r.body)
		}
	}
	if sr["cursor"].(float64) != 2 || sr["hasMore"] != false ||
		!strings.Contains(string(r.body), `"payload":{"score":4}`) ||
		!strings.Contains(string(r.body), `{"id":"dr-1","status":"applied","revision":1}`) {
		t.Fatalf("sync body: %s", r.body)
	}
	if r := e.do("POST", "/v1/profiles/"+pid+"/sync", alice, map[string]any{"events": []any{map[string]any{"id": ""}}}); r.status != 400 {
		t.Fatalf("invalid sync: %d", r.status)
	}

	// Deleting the profile removes its data.
	if r := e.do("DELETE", "/v1/profiles/"+pid, alice, nil); r.status != 204 {
		t.Fatalf("delete profile: %d", r.status)
	}
	if r := e.do("POST", "/v1/profiles/"+pid+"/sync", alice, syncBody); r.status != 404 {
		t.Fatalf("sync deleted profile: %d", r.status)
	}
}

func TestDeleteAccount(t *testing.T) {
	e := newEnv(t)
	tok, parent := e.login("family")
	e.do("POST", "/v1/profiles", tok, map[string]any{"id": "p1", "nickname": "小明"})
	e.do("POST", "/v1/profiles/p1/sync", tok, map[string]any{"events": []any{
		map[string]any{"id": "e1", "kind": "read", "at": "2026-11-01T00:00:00Z", "deviceID": "d", "payload": map[string]any{}},
	}})
	if r := e.do("DELETE", "/v1/account", tok, nil); r.status != 204 {
		t.Fatalf("delete account: %d", r.status)
	}
	if r := e.do("GET", "/v1/profiles", tok, nil); r.status != 401 {
		t.Fatalf("token survived account deletion: %d", r.status)
	}
	// The account ID is free again; registering it gives a fresh, empty account.
	if r := e.do("POST", "/v1/auth/login", "", map[string]string{"accountID": "family", "password": testPassword}); r.status != 401 {
		t.Fatalf("deleted account can still log in: %d", r.status)
	}
	tok2, parent2 := e.login("family")
	if parent2 == parent {
		t.Fatal("deleted account resurrected")
	}
	var list struct{ Profiles []any }
	e.do("GET", "/v1/profiles", tok2, nil).json(t, &list)
	if len(list.Profiles) != 0 {
		t.Fatalf("profiles survived: %v", list.Profiles)
	}
	// The old profile ID is free again and its channel is empty.
	e.do("POST", "/v1/profiles", tok2, map[string]any{"id": "p1", "nickname": "小明"})
	var sr struct {
		Cursor int64
		Events []any
	}
	e.do("POST", "/v1/profiles/p1/sync", tok2, map[string]any{}).json(t, &sr)
	if sr.Cursor != 0 || len(sr.Events) != 0 {
		t.Fatalf("old sync data visible: %+v", sr)
	}
}

func TestUnknownRoute(t *testing.T) {
	e := newEnv(t)
	if r := e.do("GET", "/v2/nothing", "", nil); r.status != 404 || r.errCode(t) != "not_found" {
		t.Fatalf("unknown route: %d %s", r.status, r.body)
	}
}

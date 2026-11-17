package content

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

var now = time.Date(2026, 11, 1, 2, 0, 0, 0, time.UTC)

// fixture copies testdata into a temp dir so tests can modify it.
func fixture(t *testing.T) (packsDir, reviewPath, outDir string) {
	t.Helper()
	root := t.TempDir()
	packsDir = filepath.Join(root, "packs")
	if err := os.MkdirAll(packsDir, 0o755); err != nil {
		t.Fatal(err)
	}
	files, _ := filepath.Glob("testdata/packs/*.json")
	for _, f := range files {
		copyFile(t, f, filepath.Join(packsDir, filepath.Base(f)))
	}
	reviewPath = filepath.Join(root, "review-status.json")
	copyFile(t, "testdata/review-status.json", reviewPath)
	return packsDir, reviewPath, filepath.Join(root, "content-releases")
}

func copyFile(t *testing.T, src, dst string) {
	t.Helper()
	b, err := os.ReadFile(src)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(dst, b, 0o644); err != nil {
		t.Fatal(err)
	}
}

func setStatus(t *testing.T, reviewPath, poemID, status string) {
	t.Helper()
	r, err := LoadReview(reviewPath)
	if err != nil {
		t.Fatal(err)
	}
	e := r.Poems[poemID]
	e.Status = status
	r.Poems[poemID] = e
	b, _ := json.Marshal(r)
	if err := os.WriteFile(reviewPath, b, 0o644); err != nil {
		t.Fatal(err)
	}
}

func editPack(t *testing.T, path string, fn func(map[string]any)) {
	t.Helper()
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var m map[string]any
	if err := json.Unmarshal(b, &m); err != nil {
		t.Fatal(err)
	}
	fn(m)
	b, _ = json.Marshal(m)
	if err := os.WriteFile(path, b, 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestValidateFixture(t *testing.T) {
	packs, review, rep, err := LoadAndValidate("testdata/packs", "testdata/review-status.json")
	if err != nil {
		t.Fatal(err)
	}
	if !rep.OK() {
		t.Fatalf("fixture should validate: %v", rep.Errors)
	}
	if len(packs) != 3 || len(review.Poems) != 5 {
		t.Fatalf("loaded %d packs, %d review entries", len(packs), len(review.Poems))
	}
}

func TestValidateErrors(t *testing.T) {
	packsDir, reviewPath, _ := fixture(t)
	editPack(t, filepath.Join(packsDir, "farewell.json"), func(m map[string]any) {
		poems := m["poems"].([]any)
		p0 := poems[0].(map[string]any)
		p0["questions"] = p0["questions"].([]any)[:4]                                                 // too few questions
		poems[1].(map[string]any)["id"] = "hk-ks1-10"                                                 // duplicate of a base poem
		poems = append(poems, map[string]any{"id": "fw-new", "theme": "farewell", "questions": []any{ // not in review, dup question
			map[string]any{"id": "se-01-q1"}, map[string]any{"id": "a"}, map[string]any{"id": "b"},
			map[string]any{"id": "c"}, map[string]any{"id": "d"}}})
		m["poems"] = poems
		m["formatVersion"] = 1
	})
	_, _, rep, err := LoadAndValidate(packsDir, reviewPath)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{
		"formatVersion is 1",
		"poem fw-01 has 4 questions",
		"poem hk-ks1-10 already defined",
		"poem fw-new is missing from the review checklist",
		"question se-01-q1",
	}
	all := strings.Join(rep.Errors, "\n")
	for _, w := range want {
		if !strings.Contains(all, w) {
			t.Errorf("missing error %q in:\n%s", w, all)
		}
	}
	if !strings.Contains(strings.Join(rep.Warnings, "\n"), "fw-02 is not in any pack") {
		t.Errorf("expected warning for orphan review entry, got %v", rep.Warnings)
	}
}

func TestPublishRequiresReview(t *testing.T) {
	packsDir, reviewPath, outDir := fixture(t)
	_, err := Publish(PublishOptions{PacksDir: packsDir, ReviewFile: reviewPath, OutDir: outDir, Release: "2026-11-01.1", Now: now})
	if err == nil || !strings.Contains(err.Error(), "se-01") {
		t.Fatalf("want refusal naming the pending poem, got %v", err)
	}
	if _, err := CurrentRelease(outDir); !errors.Is(err, ErrNoRelease) {
		t.Fatalf("nothing should be published: %v", err)
	}

	res, err := Publish(PublishOptions{PacksDir: packsDir, ReviewFile: reviewPath, OutDir: outDir,
		Release: "2026-11-01.1", AllowUnreviewed: true, Now: now})
	if err != nil {
		t.Fatal(err)
	}
	if len(res.Unreviewed) != 1 || !strings.HasPrefix(res.Unreviewed[0], "se-01") {
		t.Fatalf("unreviewed = %v", res.Unreviewed)
	}

	setStatus(t, reviewPath, "fw-01", StatusWithdrawn)
	_, err = Publish(PublishOptions{PacksDir: packsDir, ReviewFile: reviewPath, OutDir: outDir,
		Release: "2026-11-01.2", AllowUnreviewed: true, Now: now})
	if err == nil || !strings.Contains(err.Error(), "withdrawn") {
		t.Fatalf("withdrawn poem must block publishing even with --allow-unreviewed: %v", err)
	}
}

func TestPublishLayout(t *testing.T) {
	packsDir, reviewPath, outDir := fixture(t)
	setStatus(t, reviewPath, "se-01", StatusApproved)
	res, err := Publish(PublishOptions{PacksDir: packsDir, ReviewFile: reviewPath, OutDir: outDir, Release: "2026-11-01.1", Now: now})
	if err != nil {
		t.Fatal(err)
	}
	m := res.Manifest
	if m.Release != "2026-11-01.1" || m.FormatVersion != 2 || !m.PublishedAt.Equal(now) || len(m.Packs) != 2 {
		t.Fatalf("manifest = %+v", m)
	}
	for _, p := range m.Packs {
		if p.ID == BasePackID {
			t.Fatal("base pack must not be in the manifest")
		}
		if p.Version != "2026-11-01.1" || p.URL != "/v1/content/packs/"+p.ID+"/2026-11-01.1.json" || p.Audio == nil {
			t.Fatalf("entry = %+v", p)
		}
		b, err := os.ReadFile(PackPath(outDir, p.ID, p.Version))
		if err != nil {
			t.Fatal(err)
		}
		sum := sha256.Sum256(b)
		if int64(len(b)) != p.Size || hex.EncodeToString(sum[:]) != p.SHA256 {
			t.Fatalf("%s: size/sha mismatch", p.ID)
		}
		pk, err := ParsePack(p.ID, b)
		if err != nil || pk.Version != "2026-11-01.1" || pk.PackID != p.ID {
			t.Fatalf("published pack header: %+v, %v", pk, err)
		}
		if _, ok := pk.Raw["sceneMatch"]; !ok {
			t.Fatal("unknown fields must be preserved")
		}
	}
	fw := m.Packs[0]
	if fw.ID != "farewell" || fw.Title["zh-Hans"] != "友情送别" || fw.PoemCount != 2 {
		t.Fatalf("farewell entry = %+v", fw)
	}
	b, _ := os.ReadFile(PackPath(outDir, "farewell", fw.Version))
	if !strings.Contains(string(b), "<朋友> & 酒") {
		t.Fatal("HTML characters should not be escaped in pack files")
	}
	if cur, _ := CurrentRelease(outDir); cur != "2026-11-01.1" {
		t.Fatalf("current = %q", cur)
	}
	if _, err := Publish(PublishOptions{PacksDir: packsDir, ReviewFile: reviewPath, OutDir: outDir, Release: "2026-11-01.1", Now: now}); err == nil {
		t.Fatal("re-publishing an existing release must fail")
	}

	// Second release: farewell unchanged keeps its version, seasons changes.
	editPack(t, filepath.Join(packsDir, "seasons.json"), func(m map[string]any) {
		m["hantToHans"] = map[string]any{"來": "来", "書": "书"}
	})
	res, err = Publish(PublishOptions{PacksDir: packsDir, ReviewFile: reviewPath, OutDir: outDir, Release: "2026-11-02.1", Now: now.Add(24 * time.Hour)})
	if err != nil {
		t.Fatal(err)
	}
	versions := map[string]string{}
	for _, p := range res.Manifest.Packs {
		versions[p.ID] = p.Version
	}
	if versions["farewell"] != "2026-11-01.1" || versions["seasons"] != "2026-11-02.1" {
		t.Fatalf("versions = %v", versions)
	}
	if len(res.Reused) != 1 || res.Reused[0] != "farewell" {
		t.Fatalf("reused = %v", res.Reused)
	}

	repo := NewRepo(outDir)
	if p, err := repo.PackFile("farewell", "2026-11-01.1"); err != nil || !strings.Contains(p, filepath.Join("releases", "2026-11-01.1")) {
		t.Fatalf("pack lookup = %q, %v", p, err)
	}
	for _, bad := range [][2]string{{"..", "x"}, {"farewell", "../current"}, {"farewell", "2026-11-09.1"}} {
		if _, err := repo.PackFile(bad[0], bad[1]); !errors.Is(err, os.ErrNotExist) {
			t.Fatalf("PackFile(%v) err = %v", bad, err)
		}
	}
}

func TestRollbackAndWithdraw(t *testing.T) {
	packsDir, reviewPath, outDir := fixture(t)
	for i, rel := range []string{"r1", "r2", "r3"} {
		if _, err := Publish(PublishOptions{PacksDir: packsDir, ReviewFile: reviewPath, OutDir: outDir, Release: rel,
			AllowUnreviewed: true, Now: now.Add(time.Duration(i) * time.Hour)}); err != nil {
			t.Fatal(err)
		}
	}
	repo := NewRepo(outDir)
	if rel, _, _ := repo.Manifest(); rel != "r3" {
		t.Fatalf("current = %s", rel)
	}
	if rel, err := Rollback(outDir, "", "tester", now); err != nil || rel != "r2" {
		t.Fatalf("rollback = %s, %v", rel, err)
	}
	if rel, _, _ := repo.Manifest(); rel != "r2" {
		t.Fatalf("repo did not pick up rollback: %s", rel)
	}
	if rel, err := Rollback(outDir, "", "tester", now); err != nil || rel != "r1" {
		t.Fatalf("second rollback = %s, %v", rel, err)
	}
	if _, err := Rollback(outDir, "", "tester", now); err == nil {
		t.Fatal("rolling back past the oldest release must fail")
	}
	if rel, err := Rollback(outDir, "r3", "tester", now); err != nil || rel != "r3" {
		t.Fatalf("rollback --to r3 = %s, %v", rel, err)
	}
	if _, err := Rollback(outDir, "nope", "tester", now); err == nil {
		t.Fatal("unknown release must fail")
	}

	m, err := WithdrawQuestion(outDir, "hk-ks1-10-q3", "", "tester", now.Add(48*time.Hour))
	if err != nil {
		t.Fatal(err)
	}
	if m.Release != "2026-11-03.1" || len(m.WithdrawnQuestions) != 1 || m.WithdrawnQuestions[0] != "hk-ks1-10-q3" {
		t.Fatalf("withdraw manifest = %+v", m)
	}
	prev, _, _ := ReadManifest(outDir, "r3")
	if len(m.Packs) != len(prev.Packs) || m.Packs[0].URL != prev.Packs[0].URL || m.Packs[0].SHA256 != prev.Packs[0].SHA256 {
		t.Fatal("withdraw must keep the same pack versions")
	}
	if _, err := WithdrawQuestion(outDir, "hk-ks1-10-q3", "", "tester", now.Add(48*time.Hour)); err == nil {
		t.Fatal("withdrawing twice must fail")
	}
	// Withdrawn questions survive the next publish.
	res, err := Publish(PublishOptions{PacksDir: packsDir, ReviewFile: reviewPath, OutDir: outDir, Release: "r4",
		AllowUnreviewed: true, Now: now.Add(72 * time.Hour)})
	if err != nil || len(res.Manifest.WithdrawnQuestions) != 1 {
		t.Fatalf("publish after withdraw: %+v, %v", res, err)
	}
	// Rolling back the withdrawal release restores the previous list.
	if _, err := Rollback(outDir, "r3", "tester", now); err != nil {
		t.Fatal(err)
	}
	_, body, _ := repo.Manifest()
	var cur Manifest
	_ = json.Unmarshal(body, &cur)
	if len(cur.WithdrawnQuestions) != 0 {
		t.Fatalf("r3 should have no withdrawn questions: %v", cur.WithdrawnQuestions)
	}

	rels, err := ListReleases(outDir)
	if err != nil || len(rels) != 5 {
		t.Fatalf("list = %+v, %v", rels, err)
	}
	if rels[2].Name != "r3" || !rels[2].Current || rels[4].Name != "r4" {
		t.Fatalf("list order/current = %+v", rels)
	}
	audit, _ := os.ReadFile(filepath.Join(outDir, "audit.log"))
	if strings.Count(string(audit), "\n") != 9 || !strings.Contains(string(audit), "withdraw-question") {
		t.Fatalf("audit log:\n%s", audit)
	}
	leftovers, _ := filepath.Glob(filepath.Join(outDir, "releases", ".tmp-*"))
	if len(leftovers) != 0 {
		t.Fatalf("temp dirs left behind: %v", leftovers)
	}
}

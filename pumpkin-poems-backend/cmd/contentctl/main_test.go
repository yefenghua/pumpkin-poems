package main

import (
	"bytes"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestCLI(t *testing.T) {
	out := filepath.Join(t.TempDir(), "content-releases")
	packs, review := "../../internal/content/testdata/packs", "../../internal/content/testdata/review-status.json"
	clock := time.Date(2026, 11, 1, 2, 0, 0, 0, time.UTC)
	now := func() time.Time { clock = clock.Add(time.Minute); return clock }
	cli := func(wantCode int, args ...string) string {
		t.Helper()
		var stdout, stderr bytes.Buffer
		if code := run(args, &stdout, &stderr, now); code != wantCode {
			t.Fatalf("contentctl %v = %d, want %d\nstdout:\n%s\nstderr:\n%s", args, code, wantCode, stdout.String(), stderr.String())
		}
		return stdout.String() + stderr.String()
	}

	if s := cli(0, "validate", "--packs", packs, "--review", review); !strings.Contains(s, "OK: 3 pack(s), 5 poem(s)") {
		t.Fatalf("validate: %s", s)
	}
	cli(1, "publish", "--packs", packs, "--review", review, "--out", out, "--release", "r1")
	if s := cli(0, "publish", "--packs", packs, "--review", review, "--out", out, "--release", "r1", "--allow-unreviewed"); !strings.Contains(s, "WITHOUT TEACHER REVIEW") {
		t.Fatalf("missing loud warning: %s", s)
	}
	cli(0, "publish", "--packs", packs, "--review", review, "--out", out, "--release", "r2", "--allow-unreviewed")
	if s := cli(0, "rollback", "--out", out); !strings.Contains(s, "now r1") {
		t.Fatalf("rollback: %s", s)
	}
	cli(1, "withdraw-question", "--out", out, "--question", "nope", "--packs", packs)
	if s := cli(0, "withdraw-question", "--out", out, "--question", "hk-ks1-10-q1", "--release", "r3"); !strings.Contains(s, "base pack") {
		t.Fatalf("base question should warn but succeed: %s", s)
	}
	s := cli(0, "list", "--out", out)
	if !strings.Contains(s, "* r3") || !strings.Contains(s, "withdrawn=1") {
		t.Fatalf("list: %s", s)
	}
	cli(2, "publish", "--packs", packs)
	cli(2, "bogus")
}

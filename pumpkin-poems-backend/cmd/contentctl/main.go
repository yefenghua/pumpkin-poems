// Command contentctl is the controlled content release tool: it validates
// pack files against the review checklist, publishes immutable releases,
// rolls back and withdraws questions. It works on CONTENT_DIR directly and
// is run by content operators, never through the public API.
package main

import (
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/user"
	"strings"
	"time"

	"github.com/yefenghua/pumpkin-poems/backend/internal/content"
)

const usage = `usage: contentctl <command> [flags]

commands:
  validate           --packs DIR --review FILE
  publish            --packs DIR --review FILE --out CONTENT_DIR --release NAME [--allow-unreviewed]
  rollback           --out CONTENT_DIR [--to RELEASE]
  withdraw-question  --out CONTENT_DIR --question ID [--release NAME] [--packs DIR]
  list               --out CONTENT_DIR
`

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr, time.Now))
}

func run(args []string, stdout, stderr io.Writer, now func() time.Time) int {
	if len(args) == 0 {
		fmt.Fprint(stderr, usage)
		return 2
	}
	cmd, rest := args[0], args[1:]
	fs := flag.NewFlagSet("contentctl "+cmd, flag.ContinueOnError)
	fs.SetOutput(stderr)
	packs := fs.String("packs", "", "directory of <packID>.json files from the client build")
	review := fs.String("review", "", "review checklist (content/review-status.json)")
	out := fs.String("out", envOr("CONTENT_DIR", "./content-releases"), "content release directory (CONTENT_DIR)")
	release := fs.String("release", "", "release name, e.g. 2026-11-01.1")
	allow := fs.Bool("allow-unreviewed", false, "publish poems that are not approved (trial builds only)")
	to := fs.String("to", "", "release to roll back to (default: the previous one)")
	question := fs.String("question", "", "question id to withdraw")
	if err := fs.Parse(rest); err != nil {
		return 2
	}
	fail := func(err error) int {
		fmt.Fprintln(stderr, "error:", err)
		return 1
	}
	need := func(names ...string) bool {
		for _, n := range names {
			if fs.Lookup(n).Value.String() == "" {
				fmt.Fprintf(stderr, "error: --%s is required\n", n)
				return false
			}
		}
		return true
	}

	switch cmd {
	case "validate":
		if !need("packs", "review") {
			return 2
		}
		packList, _, rep, err := content.LoadAndValidate(*packs, *review)
		if err != nil {
			return fail(err)
		}
		printReport(stdout, rep)
		if !rep.OK() {
			fmt.Fprintf(stdout, "FAILED: %d error(s)\n", len(rep.Errors))
			return 1
		}
		poems := 0
		for _, p := range packList {
			poems += len(p.Poems)
		}
		fmt.Fprintf(stdout, "OK: %d pack(s), %d poem(s)\n", len(packList), poems)
		return 0

	case "publish":
		if !need("packs", "review", "out", "release") {
			return 2
		}
		res, err := content.Publish(content.PublishOptions{
			PacksDir: *packs, ReviewFile: *review, OutDir: *out, Release: *release,
			AllowUnreviewed: *allow, Actor: actor(), Now: now(),
		})
		var vf *content.ValidationFailed
		if errors.As(err, &vf) {
			printReport(stdout, vf.Report)
			return fail(errors.New("validation failed; nothing published"))
		}
		if err != nil {
			return fail(err)
		}
		printReport(stdout, res.Report)
		if len(res.Unreviewed) > 0 {
			banner := strings.Repeat("!", 72)
			fmt.Fprintf(stderr, "%s\nWARNING: PUBLISHED %d POEM(S) WITHOUT TEACHER REVIEW (--allow-unreviewed).\n"+
				"This release is for the closed trial only. Do not ship to the public.\n  %s\n%s\n",
				banner, len(res.Unreviewed), strings.Join(res.Unreviewed, "\n  "), banner)
		}
		m := res.Manifest
		fmt.Fprintf(stdout, "published %s (%d pack(s), %d withdrawn question(s)) -> current\n",
			m.Release, len(m.Packs), len(m.WithdrawnQuestions))
		for _, p := range m.Packs {
			fmt.Fprintf(stdout, "  %-16s %-16s %3d poems %8d bytes %s\n", p.ID, p.Version, p.PoemCount, p.Size, p.SHA256[:12])
		}
		fmt.Fprintln(stdout, "reminder: mark shipped poems as \"published\" in the review checklist.")
		return 0

	case "rollback":
		if !need("out") {
			return 2
		}
		rel, err := content.Rollback(*out, *to, actor(), now())
		if err != nil {
			return fail(err)
		}
		fmt.Fprintf(stdout, "current release is now %s\n", rel)
		return 0

	case "withdraw-question":
		if !need("out", "question") {
			return 2
		}
		published, err := content.PublishedQuestionIDs(*out)
		if err != nil {
			return fail(err)
		}
		if !published[*question] {
			known := false
			if *packs != "" {
				ps, err := content.LoadPackDir(*packs)
				if err != nil {
					return fail(err)
				}
				known = content.QuestionIDs(ps)[*question]
				if !known {
					return fail(fmt.Errorf("question %s not found in published packs or in %s", *question, *packs))
				}
			}
			if !known {
				fmt.Fprintf(stderr, "warning: question %s is not in any published pack (fine if it is in the built-in base pack; pass --packs to check)\n", *question)
			}
		}
		m, err := content.WithdrawQuestion(*out, *question, *release, actor(), now())
		if err != nil {
			return fail(err)
		}
		fmt.Fprintf(stdout, "released %s withdrawing %s (%d withdrawn in total) -> current\n",
			m.Release, *question, len(m.WithdrawnQuestions))
		return 0

	case "list":
		rels, err := content.ListReleases(*out)
		if err != nil {
			return fail(err)
		}
		if len(rels) == 0 {
			fmt.Fprintln(stdout, "no releases")
			return 0
		}
		for _, r := range rels {
			mark := " "
			if r.Current {
				mark = "*"
			}
			fmt.Fprintf(stdout, "%s %-20s %s  packs=%d withdrawn=%d\n", mark, r.Name,
				r.PublishedAt.Format(time.RFC3339), r.Packs, r.Withdrawn)
		}
		return 0

	default:
		fmt.Fprint(stderr, usage)
		return 2
	}
}

func printReport(w io.Writer, r *content.Report) {
	for _, e := range r.Errors {
		fmt.Fprintln(w, "ERROR  ", e)
	}
	for _, e := range r.Warnings {
		fmt.Fprintln(w, "warning", e)
	}
}

func actor() string {
	if u, err := user.Current(); err == nil {
		return u.Username
	}
	return os.Getenv("USER")
}

func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

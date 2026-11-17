package content

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"sort"
	"strings"
	"time"
)

type PublishOptions struct {
	PacksDir        string
	ReviewFile      string
	OutDir          string // CONTENT_DIR
	Release         string
	AllowUnreviewed bool
	Actor           string // recorded in audit.log
	Now             time.Time
}

type PublishResult struct {
	Manifest *Manifest
	Report   *Report
	// Unreviewed lists poems shipped without approval (only possible with
	// AllowUnreviewed).
	Unreviewed []string
	// Reused lists packs whose content is unchanged and keep their old version.
	Reused []string
}

// ValidationFailed is returned when packs do not pass Validate.
type ValidationFailed struct{ Report *Report }

func (e *ValidationFailed) Error() string {
	return fmt.Sprintf("validation failed with %d error(s):\n  %s", len(e.Report.Errors), strings.Join(e.Report.Errors, "\n  "))
}

// LoadAndValidate is the shared first step of validate and publish.
func LoadAndValidate(packsDir, reviewPath string) ([]*Pack, *ReviewFile, *Report, error) {
	packs, err := LoadPackDir(packsDir)
	if err != nil {
		return nil, nil, nil, err
	}
	review, err := LoadReview(reviewPath)
	if err != nil {
		return nil, nil, nil, err
	}
	return packs, review, Validate(packs, review), nil
}

// Publish validates the packs, enforces review status, writes a new
// immutable release and switches CONTENT_DIR/current to it. The base pack
// is validated but not published. Packs whose content did not change since
// the current release keep their previous version so clients do not
// re-download them.
func Publish(o PublishOptions) (*PublishResult, error) {
	if !ValidName(o.Release) {
		return nil, fmt.Errorf("invalid release name %q (use e.g. 2026-11-01.1)", o.Release)
	}
	if o.Now.IsZero() {
		o.Now = time.Now()
	}
	packs, review, rep, err := LoadAndValidate(o.PacksDir, o.ReviewFile)
	if err != nil {
		return nil, err
	}
	if !rep.OK() {
		return nil, &ValidationFailed{rep}
	}
	if _, err := os.Stat(releaseDir(o.OutDir, o.Release)); err == nil {
		return nil, fmt.Errorf("release %s already exists; releases are immutable, pick a new name", o.Release)
	}

	res := &PublishResult{Report: rep}
	var withdrawnPoems []string
	for _, p := range packs {
		if p.PackID == BasePackID {
			continue
		}
		for _, poem := range p.Poems {
			switch review.Poems[poem.ID].Status {
			case StatusApproved, StatusPublished:
			case StatusWithdrawn:
				withdrawnPoems = append(withdrawnPoems, poem.ID)
			default:
				res.Unreviewed = append(res.Unreviewed, fmt.Sprintf("%s (%s, %s)", poem.ID, p.PackID, review.Poems[poem.ID].Status))
			}
		}
	}
	if len(withdrawnPoems) > 0 {
		return nil, fmt.Errorf("withdrawn poems must be removed from packs before publishing: %s", strings.Join(withdrawnPoems, ", "))
	}
	if len(res.Unreviewed) > 0 && !o.AllowUnreviewed {
		return nil, fmt.Errorf("%d poem(s) are not approved; refusing to publish (use --allow-unreviewed for trial builds only):\n  %s",
			len(res.Unreviewed), strings.Join(res.Unreviewed, "\n  "))
	}

	var prev *Manifest
	if cur, err := CurrentRelease(o.OutDir); err == nil {
		if prev, _, err = ReadManifest(o.OutDir, cur); err != nil {
			return nil, err
		}
	} else if !errors.Is(err, ErrNoRelease) {
		return nil, err
	}

	if err := os.MkdirAll(releasesDir(o.OutDir), 0o755); err != nil {
		return nil, err
	}
	tmp, err := os.MkdirTemp(releasesDir(o.OutDir), ".tmp-"+o.Release+"-")
	if err != nil {
		return nil, err
	}
	defer os.RemoveAll(tmp) // no-op after the rename succeeds

	m := &Manifest{
		Release:            o.Release,
		FormatVersion:      FormatVersion,
		PublishedAt:        o.Now.UTC().Truncate(time.Second),
		Packs:              []PackEntry{},
		WithdrawnQuestions: []string{},
	}
	if prev != nil {
		m.WithdrawnQuestions = append(m.WithdrawnQuestions, prev.WithdrawnQuestions...)
	}
	sorted := slices.Clone(packs)
	sort.Slice(sorted, func(i, j int) bool { return sorted[i].PackID < sorted[j].PackID })
	for _, p := range sorted {
		if p.PackID == BasePackID {
			continue
		}
		version, body, reused, err := packVersion(o.OutDir, prev, p, o.Release)
		if err != nil {
			return nil, err
		}
		if reused {
			res.Reused = append(res.Reused, p.PackID)
		} else {
			dst := filepath.Join(tmp, "packs", p.PackID, version+".json")
			if err := writeFileSync(dst, body); err != nil {
				return nil, err
			}
		}
		sum := sha256.Sum256(body)
		title, summary := p.displayText()
		m.Packs = append(m.Packs, PackEntry{
			ID: p.PackID, Version: version, Title: title, Summary: summary,
			PoemCount: len(p.Poems), Size: int64(len(body)), SHA256: hex.EncodeToString(sum[:]),
			URL: PackURL(p.PackID, version), Audio: []AudioFile{},
		})
	}
	if err := writeRelease(o.OutDir, tmp, m); err != nil {
		return nil, err
	}
	if err := SwitchCurrent(o.OutDir, o.Release); err != nil {
		return nil, err
	}
	res.Manifest = m
	detail := fmt.Sprintf("packs=%d reused=%s", len(m.Packs), strings.Join(res.Reused, ","))
	if len(res.Unreviewed) > 0 {
		detail += fmt.Sprintf(" UNREVIEWED=%d", len(res.Unreviewed))
	}
	appendAudit(o.OutDir, o.Now, o.Actor, "publish", o.Release, detail)
	return res, nil
}

// packVersion renders the pack with its version rewritten. If the current
// release already has an identical pack it is reused under its old version.
func packVersion(outDir string, prev *Manifest, p *Pack, release string) (version string, body []byte, reused bool, err error) {
	if prev != nil {
		for _, e := range prev.Packs {
			if e.ID != p.PackID {
				continue
			}
			candidate, err := renderPack(p, e.Version)
			if err != nil {
				return "", nil, false, err
			}
			old, err := os.ReadFile(PackPath(outDir, e.ID, e.Version))
			if err == nil && bytes.Equal(old, candidate) {
				return e.Version, candidate, true, nil
			}
		}
	}
	body, err = renderPack(p, release)
	return release, body, false, err
}

func renderPack(p *Pack, version string) ([]byte, error) {
	raw := make(map[string]json.RawMessage, len(p.Raw))
	for k, v := range p.Raw {
		raw[k] = v
	}
	v, _ := json.Marshal(version)
	raw["version"] = v
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(raw); err != nil {
		return nil, fmt.Errorf("%s: %w", p.File, err)
	}
	return buf.Bytes(), nil
}

// writeRelease writes manifest.json into tmp and renames tmp into place, so
// a release directory is either complete or absent.
func writeRelease(outDir, tmp string, m *Manifest) error {
	b, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		return err
	}
	if err := writeFileSync(filepath.Join(tmp, "manifest.json"), append(b, '\n')); err != nil {
		return err
	}
	if err := os.Chmod(tmp, 0o755); err != nil {
		return err
	}
	return os.Rename(tmp, releaseDir(outDir, m.Release))
}

// SwitchCurrent atomically points CONTENT_DIR/current at release.
func SwitchCurrent(outDir, release string) error {
	if _, err := os.Stat(manifestPath(outDir, release)); err != nil {
		return fmt.Errorf("release %s: %w", release, err)
	}
	f, err := os.CreateTemp(outDir, ".current-")
	if err != nil {
		return err
	}
	defer os.Remove(f.Name())
	if _, err := f.WriteString(release + "\n"); err != nil {
		f.Close()
		return err
	}
	if err := f.Sync(); err != nil {
		f.Close()
		return err
	}
	if err := f.Close(); err != nil {
		return err
	}
	if err := os.Chmod(f.Name(), 0o644); err != nil {
		return err
	}
	return os.Rename(f.Name(), filepath.Join(outDir, "current"))
}

type ReleaseInfo struct {
	Name        string
	PublishedAt time.Time
	Packs       int
	Withdrawn   int
	Current     bool
}

// ListReleases returns releases in publish order (oldest first).
func ListReleases(outDir string) ([]ReleaseInfo, error) {
	entries, err := os.ReadDir(releasesDir(outDir))
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	cur, _ := CurrentRelease(outDir)
	var out []ReleaseInfo
	for _, e := range entries {
		if !e.IsDir() || strings.HasPrefix(e.Name(), ".") {
			continue
		}
		m, _, err := ReadManifest(outDir, e.Name())
		if err != nil {
			return nil, err
		}
		out = append(out, ReleaseInfo{
			Name: e.Name(), PublishedAt: m.PublishedAt, Packs: len(m.Packs),
			Withdrawn: len(m.WithdrawnQuestions), Current: e.Name() == cur,
		})
	}
	sort.Slice(out, func(i, j int) bool {
		if !out[i].PublishedAt.Equal(out[j].PublishedAt) {
			return out[i].PublishedAt.Before(out[j].PublishedAt)
		}
		return out[i].Name < out[j].Name
	})
	return out, nil
}

// Rollback switches current to `to`, or to the release published just before
// the current one when `to` is empty. It returns the new current release.
func Rollback(outDir, to, actor string, now time.Time) (string, error) {
	cur, err := CurrentRelease(outDir)
	if err != nil {
		return "", err
	}
	if to == "" {
		rels, err := ListReleases(outDir)
		if err != nil {
			return "", err
		}
		for i, r := range rels {
			if r.Name == cur {
				if i == 0 {
					return "", fmt.Errorf("release %s is the oldest; nothing to roll back to", cur)
				}
				to = rels[i-1].Name
			}
		}
		if to == "" {
			return "", fmt.Errorf("current release %s not found under releases/", cur)
		}
	}
	if !ValidName(to) {
		return "", fmt.Errorf("invalid release name %q", to)
	}
	if to == cur {
		return "", fmt.Errorf("release %s is already current", to)
	}
	if err := SwitchCurrent(outDir, to); err != nil {
		return "", err
	}
	appendAudit(outDir, now, actor, "rollback", to, "from="+cur)
	return to, nil
}

// WithdrawQuestion creates a new release identical to the current one plus
// questionID in withdrawnQuestions, and makes it current. Pack files are not
// copied: the manifest keeps pointing at the existing immutable versions.
func WithdrawQuestion(outDir, questionID, release, actor string, now time.Time) (*Manifest, error) {
	if questionID == "" {
		return nil, errors.New("question id is required")
	}
	cur, err := CurrentRelease(outDir)
	if err != nil {
		return nil, err
	}
	prev, _, err := ReadManifest(outDir, cur)
	if err != nil {
		return nil, err
	}
	if slices.Contains(prev.WithdrawnQuestions, questionID) {
		return nil, fmt.Errorf("question %s is already withdrawn in %s", questionID, cur)
	}
	if release == "" {
		if release, err = NextReleaseName(outDir, now); err != nil {
			return nil, err
		}
	}
	if !ValidName(release) {
		return nil, fmt.Errorf("invalid release name %q", release)
	}
	if _, err := os.Stat(releaseDir(outDir, release)); err == nil {
		return nil, fmt.Errorf("release %s already exists", release)
	}
	m := *prev
	m.Release = release
	m.PublishedAt = now.UTC().Truncate(time.Second)
	m.WithdrawnQuestions = append(slices.Clone(prev.WithdrawnQuestions), questionID)
	sort.Strings(m.WithdrawnQuestions)

	if err := os.MkdirAll(releasesDir(outDir), 0o755); err != nil {
		return nil, err
	}
	tmp, err := os.MkdirTemp(releasesDir(outDir), ".tmp-"+release+"-")
	if err != nil {
		return nil, err
	}
	defer os.RemoveAll(tmp)
	if err := writeRelease(outDir, tmp, &m); err != nil {
		return nil, err
	}
	if err := SwitchCurrent(outDir, release); err != nil {
		return nil, err
	}
	appendAudit(outDir, now, actor, "withdraw-question", release, "question="+questionID+" from="+cur)
	return &m, nil
}

// PublishedQuestionIDs returns question IDs found in the current release's
// pack files (the base pack is not among them).
func PublishedQuestionIDs(outDir string) (map[string]bool, error) {
	cur, err := CurrentRelease(outDir)
	if err != nil {
		return nil, err
	}
	m, _, err := ReadManifest(outDir, cur)
	if err != nil {
		return nil, err
	}
	var packs []*Pack
	for _, e := range m.Packs {
		p, err := LoadPack(PackPath(outDir, e.ID, e.Version))
		if err != nil {
			return nil, err
		}
		packs = append(packs, p)
	}
	return QuestionIDs(packs), nil
}

// NextReleaseName returns "<YYYY-MM-DD>.<n>" with the smallest unused n.
func NextReleaseName(outDir string, now time.Time) (string, error) {
	day := now.UTC().Format("2006-01-02")
	for n := 1; n < 1000; n++ {
		name := fmt.Sprintf("%s.%d", day, n)
		if _, err := os.Stat(releaseDir(outDir, name)); errors.Is(err, os.ErrNotExist) {
			return name, nil
		}
	}
	return "", errors.New("too many releases today")
}

func writeFileSync(path string, b []byte) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_EXCL, 0o644)
	if err != nil {
		return err
	}
	if _, err := f.Write(b); err != nil {
		f.Close()
		return err
	}
	if err := f.Sync(); err != nil {
		f.Close()
		return err
	}
	return f.Close()
}

// appendAudit is best effort: the release itself is already in place.
func appendAudit(outDir string, now time.Time, actor, action, release, detail string) {
	if actor == "" {
		actor = "unknown"
	}
	f, err := os.OpenFile(filepath.Join(outDir, "audit.log"), os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		return
	}
	defer f.Close()
	fmt.Fprintf(f, "%s\t%s\t%s\t%s\t%s\n", now.UTC().Format(time.RFC3339), actor, action, release, detail)
}

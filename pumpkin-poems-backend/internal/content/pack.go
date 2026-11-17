package content

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// Review statuses (审核状态). Only approved/published poems may ship
// unless publish is run with --allow-unreviewed.
const (
	StatusDraft     = "draft"
	StatusPending   = "pending"
	StatusApproved  = "approved"
	StatusPublished = "published"
	StatusWithdrawn = "withdrawn"
)

var validStatuses = map[string]bool{
	StatusDraft: true, StatusPending: true, StatusApproved: true, StatusPublished: true, StatusWithdrawn: true,
}

type ReviewEntry struct {
	Status        string `json:"status"`
	TextReviewed  bool   `json:"textReviewed"`
	AudioReviewed bool   `json:"audioReviewed"`
	Reviewer      string `json:"reviewer"`
	Note          string `json:"note"`
}

type ReviewFile struct {
	Poems map[string]ReviewEntry `json:"poems"`
}

func LoadReview(path string) (*ReviewFile, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var r ReviewFile
	if err := json.Unmarshal(b, &r); err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	if r.Poems == nil {
		r.Poems = map[string]ReviewEntry{}
	}
	return &r, nil
}

// Pack is a parsed pack file. Raw keeps every top-level field so publishing
// can rewrite "version" without dropping fields this tool does not know.
type Pack struct {
	File          string
	FormatVersion int
	PackID        string
	Version       string
	Themes        []Theme
	Poems         []Poem
	Title         LocalizedText
	Summary       LocalizedText
	Raw           map[string]json.RawMessage
}

type Theme struct {
	ID      string        `json:"id"`
	Name    LocalizedText `json:"name"`
	Summary LocalizedText `json:"summary"`
}

type Poem struct {
	ID        string     `json:"id"`
	Theme     string     `json:"theme"`
	Questions []Question `json:"questions"`
}

type Question struct {
	ID string `json:"id"`
}

func LoadPack(path string) (*Pack, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	return ParsePack(path, b)
}

func ParsePack(name string, b []byte) (*Pack, error) {
	p := &Pack{File: name}
	if err := json.Unmarshal(b, &p.Raw); err != nil {
		return nil, fmt.Errorf("%s: %w", name, err)
	}
	var head struct {
		FormatVersion int             `json:"formatVersion"`
		PackID        string          `json:"packID"`
		Version       string          `json:"version"`
		Themes        []Theme         `json:"themes"`
		Poems         []Poem          `json:"poems"`
		Title         LocalizedText   `json:"title"`
		Summary       LocalizedText   `json:"summary"`
		HantToHans    json.RawMessage `json:"hantToHans"`
	}
	if err := json.Unmarshal(b, &head); err != nil {
		return nil, fmt.Errorf("%s: %w", name, err)
	}
	p.FormatVersion, p.PackID, p.Version = head.FormatVersion, head.PackID, head.Version
	p.Themes, p.Poems, p.Title, p.Summary = head.Themes, head.Poems, head.Title, head.Summary
	return p, nil
}

// LoadPackDir loads every *.json in dir, sorted by file name.
func LoadPackDir(dir string) ([]*Pack, error) {
	files, err := filepath.Glob(filepath.Join(dir, "*.json"))
	if err != nil {
		return nil, err
	}
	if len(files) == 0 {
		return nil, fmt.Errorf("no pack files (*.json) in %s", dir)
	}
	sort.Strings(files)
	var packs []*Pack
	for _, f := range files {
		p, err := LoadPack(f)
		if err != nil {
			return nil, err
		}
		packs = append(packs, p)
	}
	return packs, nil
}

// Report collects validation problems. Errors block publishing; warnings
// are informational.
type Report struct {
	Errors   []string
	Warnings []string
}

func (r *Report) errorf(format string, a ...any) {
	r.Errors = append(r.Errors, fmt.Sprintf(format, a...))
}
func (r *Report) warnf(format string, a ...any) {
	r.Warnings = append(r.Warnings, fmt.Sprintf(format, a...))
}

func (r *Report) OK() bool { return len(r.Errors) == 0 }

// MinQuestionsPerPoem is the phase-2 rule "每首至少 5 道练习".
const MinQuestionsPerPoem = 5

// Validate checks pack structure and cross-pack invariants: required fields,
// poem and question IDs unique across all packs (including base), at least
// five questions per poem, known themes, and every poem listed in the review
// checklist with a valid status.
func Validate(packs []*Pack, review *ReviewFile) *Report {
	r := &Report{}
	poemPack := map[string]string{}
	questionPoem := map[string]string{}
	packIDs := map[string]bool{}
	themes := map[string]bool{}
	for _, p := range packs {
		for _, t := range p.Themes {
			themes[t.ID] = true
		}
	}

	for _, p := range packs {
		where := filepath.Base(p.File)
		if p.FormatVersion != FormatVersion {
			r.errorf("%s: formatVersion is %d, want %d", where, p.FormatVersion, FormatVersion)
		}
		switch {
		case p.PackID == "":
			r.errorf("%s: packID is required", where)
		case !ValidName(p.PackID):
			r.errorf("%s: packID %q must match [A-Za-z0-9._-]", where, p.PackID)
		case strings.TrimSuffix(where, ".json") != p.PackID:
			r.errorf("%s: file name must be %s.json", where, p.PackID)
		case packIDs[p.PackID]:
			r.errorf("%s: duplicate packID %q", where, p.PackID)
		}
		packIDs[p.PackID] = true
		if p.Version == "" {
			r.errorf("%s: version is required", where)
		}
		for _, key := range []string{"themes", "poems", "hantToHans"} {
			if _, ok := p.Raw[key]; !ok {
				r.errorf("%s: missing %q", where, key)
			}
		}
		if len(p.Poems) == 0 {
			r.errorf("%s: pack has no poems", where)
		}
		for i, t := range p.Themes {
			if t.ID == "" {
				r.errorf("%s: themes[%d].id is required", where, i)
			}
		}
		for i, poem := range p.Poems {
			if poem.ID == "" {
				r.errorf("%s: poems[%d].id is required", where, i)
				continue
			}
			if other, dup := poemPack[poem.ID]; dup {
				r.errorf("%s: poem %s already defined in %s", where, poem.ID, other)
			}
			poemPack[poem.ID] = where
			if poem.Theme != "" && !themes[poem.Theme] {
				r.errorf("%s: poem %s references unknown theme %q", where, poem.ID, poem.Theme)
			}
			if len(poem.Questions) < MinQuestionsPerPoem {
				r.errorf("%s: poem %s has %d questions, need at least %d", where, poem.ID, len(poem.Questions), MinQuestionsPerPoem)
			}
			for j, q := range poem.Questions {
				if q.ID == "" {
					r.errorf("%s: poem %s questions[%d].id is required", where, poem.ID, j)
					continue
				}
				if other, dup := questionPoem[q.ID]; dup {
					r.errorf("%s: question %s (poem %s) already used by poem %s", where, q.ID, poem.ID, other)
				}
				questionPoem[q.ID] = poem.ID
			}
			entry, ok := review.Poems[poem.ID]
			switch {
			case !ok:
				r.errorf("%s: poem %s is missing from the review checklist", where, poem.ID)
			case !validStatuses[entry.Status]:
				r.errorf("review: poem %s has invalid status %q", poem.ID, entry.Status)
			}
		}
	}
	ids := make([]string, 0, len(review.Poems))
	for id := range review.Poems {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	for _, id := range ids {
		if _, ok := poemPack[id]; !ok {
			r.warnf("review: poem %s is not in any pack", id)
		}
	}
	return r
}

// QuestionIDs returns every question ID in the packs.
func QuestionIDs(packs []*Pack) map[string]bool {
	out := map[string]bool{}
	for _, p := range packs {
		for _, poem := range p.Poems {
			for _, q := range poem.Questions {
				out[q.ID] = true
			}
		}
	}
	return out
}

// displayText picks the manifest title/summary: explicit pack-level fields
// win, then the theme whose id equals the pack ID, then the first theme.
func (p *Pack) displayText() (title, summary LocalizedText) {
	title, summary = p.Title, p.Summary
	var theme *Theme
	for i := range p.Themes {
		if p.Themes[i].ID == p.PackID {
			theme = &p.Themes[i]
			break
		}
	}
	if theme == nil && len(p.Themes) > 0 {
		theme = &p.Themes[0]
	}
	if theme != nil {
		if len(title) == 0 {
			title = theme.Name
		}
		if len(summary) == 0 {
			summary = theme.Summary
		}
	}
	if len(title) == 0 {
		title = LocalizedText{"zh-Hant": p.PackID, "zh-Hans": p.PackID}
	}
	if summary == nil {
		summary = LocalizedText{}
	}
	return title, summary
}

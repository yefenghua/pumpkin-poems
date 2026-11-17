// Package content owns the on-disk release layout shared by the server
// (read side) and contentctl (write side):
//
//	CONTENT_DIR/
//	  current                                   name of the live release
//	  audit.log                                 one line per contentctl action
//	  releases/<release>/manifest.json
//	  releases/<release>/packs/<packID>/<version>.json
//
// Releases are immutable once written. A pack file lives in the release
// where its version was first published (its version equals that release
// name); later releases that reuse the pack point at the same URL.
package content

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"time"
)

const FormatVersion = 2

// BasePackID is the pack bundled in the app; it is validated but never
// listed in the manifest.
const BasePackID = "base"

type LocalizedText map[string]string

type AudioFile struct {
	Path   string `json:"path"`
	Size   int64  `json:"size"`
	SHA256 string `json:"sha256"`
	URL    string `json:"url"`
}

type PackEntry struct {
	ID        string        `json:"id"`
	Version   string        `json:"version"`
	Title     LocalizedText `json:"title"`
	Summary   LocalizedText `json:"summary"`
	PoemCount int           `json:"poemCount"`
	Size      int64         `json:"size"`
	SHA256    string        `json:"sha256"`
	URL       string        `json:"url"`
	Audio     []AudioFile   `json:"audio"`
}

type Manifest struct {
	Release            string      `json:"release"`
	FormatVersion      int         `json:"formatVersion"`
	PublishedAt        time.Time   `json:"publishedAt"`
	Packs              []PackEntry `json:"packs"`
	WithdrawnQuestions []string    `json:"withdrawnQuestions"`
}

// ErrNoRelease means nothing has been published yet.
var ErrNoRelease = errors.New("no content release published")

var safeName = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$`)

// ValidName reports whether s is safe as a release name, pack ID or version
// (it becomes a path component).
func ValidName(s string) bool {
	return safeName.MatchString(s) && !strings.Contains(s, "..")
}

func PackURL(packID, version string) string {
	return fmt.Sprintf("/v1/content/packs/%s/%s.json", packID, version)
}

func releasesDir(dir string) string { return filepath.Join(dir, "releases") }

func releaseDir(dir, release string) string { return filepath.Join(dir, "releases", release) }

func manifestPath(dir, release string) string {
	return filepath.Join(releaseDir(dir, release), "manifest.json")
}

// PackPath is where a published pack version is stored.
func PackPath(dir, packID, version string) string {
	return filepath.Join(releaseDir(dir, version), "packs", packID, version+".json")
}

// CurrentRelease reads CONTENT_DIR/current.
func CurrentRelease(dir string) (string, error) {
	b, err := os.ReadFile(filepath.Join(dir, "current"))
	if errors.Is(err, os.ErrNotExist) {
		return "", ErrNoRelease
	}
	if err != nil {
		return "", err
	}
	name := strings.TrimSpace(string(b))
	if name == "" {
		return "", ErrNoRelease
	}
	if !ValidName(name) {
		return "", fmt.Errorf("current: invalid release name %q", name)
	}
	return name, nil
}

func ReadManifest(dir, release string) (*Manifest, []byte, error) {
	b, err := os.ReadFile(manifestPath(dir, release))
	if err != nil {
		return nil, nil, err
	}
	var m Manifest
	if err := json.Unmarshal(b, &m); err != nil {
		return nil, nil, fmt.Errorf("release %s manifest: %w", release, err)
	}
	return &m, b, nil
}

// Repo serves the live release. It re-reads CONTENT_DIR/current on every
// call, so publish and rollback take effect without a restart; manifests are
// cached per release name because releases are immutable.
type Repo struct {
	Dir string

	mu    sync.Mutex
	cache map[string][]byte
}

func NewRepo(dir string) *Repo { return &Repo{Dir: dir, cache: map[string][]byte{}} }

// Manifest returns the current release name and its manifest bytes.
func (r *Repo) Manifest() (string, []byte, error) {
	rel, err := CurrentRelease(r.Dir)
	if err != nil {
		return "", nil, err
	}
	r.mu.Lock()
	b, ok := r.cache[rel]
	r.mu.Unlock()
	if ok {
		return rel, b, nil
	}
	_, b, err = ReadManifest(r.Dir, rel)
	if err != nil {
		return "", nil, err
	}
	r.mu.Lock()
	r.cache[rel] = b
	r.mu.Unlock()
	return rel, b, nil
}

// PackFile returns the path of a published pack file, or os.ErrNotExist.
func (r *Repo) PackFile(packID, version string) (string, error) {
	if !ValidName(packID) || !ValidName(version) {
		return "", os.ErrNotExist
	}
	p := PackPath(r.Dir, packID, version)
	if _, err := os.Stat(p); err != nil {
		return "", err
	}
	return p, nil
}

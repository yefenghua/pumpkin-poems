package api

import (
	"errors"
	"net/http"
	"os"
	"strings"

	"github.com/yefenghua/pumpkin-poems/backend/internal/content"
)

func (s *Server) healthz(w http.ResponseWriter, r *http.Request) {
	var release *string
	if rel, err := content.CurrentRelease(s.cfg.Content.Dir); err == nil {
		release = &rel
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "release": release})
}

func (s *Server) manifest(w http.ResponseWriter, r *http.Request) {
	rel, body, err := s.cfg.Content.Manifest()
	if errors.Is(err, content.ErrNoRelease) {
		writeError(w, http.StatusNotFound, "no_release", "no content release has been published")
		return
	}
	if err != nil {
		s.internalError(w, r, err)
		return
	}
	etag := `"` + rel + `"`
	w.Header().Set("ETag", etag)
	w.Header().Set("Cache-Control", "no-cache")
	if r.Header.Get("If-None-Match") == etag {
		w.WriteHeader(http.StatusNotModified)
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	_, _ = w.Write(body)
}

// packFile serves an immutable pack version from the release directory that
// first published it.
func (s *Server) packFile(w http.ResponseWriter, r *http.Request) {
	version, ok := strings.CutSuffix(r.PathValue("file"), ".json")
	if !ok {
		writeError(w, http.StatusNotFound, "not_found", "pack not found")
		return
	}
	path, err := s.cfg.Content.PackFile(r.PathValue("packID"), version)
	if errors.Is(err, os.ErrNotExist) {
		writeError(w, http.StatusNotFound, "not_found", "pack not found")
		return
	}
	if err != nil {
		s.internalError(w, r, err)
		return
	}
	f, err := os.Open(path)
	if err != nil {
		s.internalError(w, r, err)
		return
	}
	defer f.Close()
	st, err := f.Stat()
	if err != nil {
		s.internalError(w, r, err)
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
	http.ServeContent(w, r, "", st.ModTime(), f)
}

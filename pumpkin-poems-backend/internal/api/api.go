// Package api wires the HTTP endpoints of docs/api/phase2-api.md.
package api

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/yefenghua/pumpkin-poems/backend/internal/auth"
	"github.com/yefenghua/pumpkin-poems/backend/internal/content"
	"github.com/yefenghua/pumpkin-poems/backend/internal/store"
)

type Config struct {
	Store      store.Store
	Content    *content.Repo
	Limiter    *auth.LoginLimiter // nil → default limiter
	AdminToken string             // empty disables /v1/admin/*
	Logger     *slog.Logger
	Now        func() time.Time
}

type Server struct {
	cfg Config
	mux *http.ServeMux
}

// Body size limits per endpoint family.
const (
	limitSmall    = 16 << 10
	limitFeedback = 64 << 10
	limitEvents   = 1 << 20
	limitSync     = 16 << 20 // guest migration pushes the whole local history at once
)

func New(cfg Config) *Server {
	if cfg.Logger == nil {
		cfg.Logger = slog.Default()
	}
	if cfg.Now == nil {
		cfg.Now = time.Now
	}
	if cfg.Limiter == nil {
		cfg.Limiter = auth.NewLoginLimiter()
		cfg.Limiter.Now = cfg.Now
	}
	s := &Server{cfg: cfg, mux: http.NewServeMux()}
	s.routes()
	return s
}

func (s *Server) routes() {
	m := s.mux
	m.HandleFunc("GET /healthz", s.healthz)

	m.HandleFunc("GET /v1/content/manifest", s.manifest)
	m.HandleFunc("GET /v1/content/packs/{packID}/{file}", s.packFile)

	m.HandleFunc("POST /v1/events", s.postEvents)
	m.HandleFunc("POST /v1/feedback", s.postFeedback)
	m.HandleFunc("GET /v1/admin/metrics", s.admin(s.getMetrics))

	m.HandleFunc("POST /v1/auth/register", s.register)
	m.HandleFunc("POST /v1/auth/login", s.login)
	m.HandleFunc("POST /v1/auth/logout", s.authed(s.logout))
	m.HandleFunc("POST /v1/auth/password", s.authed(s.changePassword))
	m.HandleFunc("GET /v1/account", s.authed(s.getAccount))

	m.HandleFunc("GET /v1/profiles", s.authed(s.listProfiles))
	m.HandleFunc("POST /v1/profiles", s.authed(s.createProfile))
	m.HandleFunc("PATCH /v1/profiles/{id}", s.authed(s.updateProfile))
	m.HandleFunc("DELETE /v1/profiles/{id}", s.authed(s.deleteProfile))
	m.HandleFunc("POST /v1/profiles/{id}/sync", s.authed(s.syncProfile))
	m.HandleFunc("DELETE /v1/account", s.authed(s.deleteAccount))

	m.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		writeError(w, http.StatusNotFound, "not_found", "no such endpoint")
	})
}

func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	start := time.Now()
	rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
	defer func() {
		if v := recover(); v != nil {
			s.cfg.Logger.Error("panic", "path", r.URL.Path, "panic", fmt.Sprint(v))
			if !rec.wrote {
				writeError(rec, http.StatusInternalServerError, "internal", "internal error")
			}
		}
		_, pattern := s.mux.Handler(r)
		s.cfg.Logger.Info("request", "method", r.Method, "route", pattern, "status", rec.status,
			"dur_ms", time.Since(start).Milliseconds())
	}()
	s.mux.ServeHTTP(rec, r)
}

type statusRecorder struct {
	http.ResponseWriter
	status int
	wrote  bool
}

func (r *statusRecorder) WriteHeader(code int) {
	if !r.wrote {
		r.status, r.wrote = code, true
	}
	r.ResponseWriter.WriteHeader(code)
}

func (r *statusRecorder) Write(b []byte) (int, error) {
	r.wrote = true
	return r.ResponseWriter.Write(b)
}

type errorBody struct {
	Error struct {
		Code    string `json:"code"`
		Message string `json:"message"`
	} `json:"error"`
}

func writeError(w http.ResponseWriter, status int, code, msg string) {
	var b errorBody
	b.Error.Code, b.Error.Message = code, msg
	writeJSON(w, status, b)
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	enc := json.NewEncoder(w)
	enc.SetEscapeHTML(false)
	_ = enc.Encode(v)
}

func (s *Server) internalError(w http.ResponseWriter, r *http.Request, err error) {
	if errors.Is(err, context.Canceled) {
		return
	}
	s.cfg.Logger.Error("internal error", "method", r.Method, "path", r.URL.Path, "err", err)
	writeError(w, http.StatusInternalServerError, "internal", "internal error")
}

// decode reads a JSON body under a size limit. It writes the error response
// itself and returns false on failure.
func decode(w http.ResponseWriter, r *http.Request, limit int64, v any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, limit)
	dec := json.NewDecoder(r.Body)
	if err := dec.Decode(v); err != nil {
		var tooBig *http.MaxBytesError
		if errors.As(err, &tooBig) {
			writeError(w, http.StatusRequestEntityTooLarge, "payload_too_large",
				fmt.Sprintf("request body exceeds %d bytes", limit))
			return false
		}
		writeError(w, http.StatusBadRequest, "invalid_json", err.Error())
		return false
	}
	return true
}

type ctxKey struct{}

// authed requires a valid access token and passes the parent ID along.
func (s *Server) authed(h func(http.ResponseWriter, *http.Request, string)) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		token, ok := bearer(r)
		if !ok {
			writeError(w, http.StatusUnauthorized, "unauthorized", "missing bearer token")
			return
		}
		parentID, err := s.cfg.Store.SessionParent(r.Context(), auth.HashToken(token), s.cfg.Now())
		if errors.Is(err, store.ErrNotFound) {
			writeError(w, http.StatusUnauthorized, "unauthorized", "invalid or expired token")
			return
		}
		if err != nil {
			s.internalError(w, r, err)
			return
		}
		h(w, r, parentID)
	}
}

// admin guards operator endpoints with ADMIN_TOKEN, which is unrelated to
// learner/parent accounts.
func (s *Server) admin(h http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		token, ok := bearer(r)
		if s.cfg.AdminToken == "" || !ok ||
			subtle.ConstantTimeCompare([]byte(token), []byte(s.cfg.AdminToken)) != 1 {
			writeError(w, http.StatusUnauthorized, "unauthorized", "admin token required")
			return
		}
		h(w, r)
	}
}

func bearer(r *http.Request) (string, bool) {
	h := r.Header.Get("Authorization")
	const prefix = "Bearer "
	if len(h) <= len(prefix) || !strings.EqualFold(h[:len(prefix)], prefix) {
		return "", false
	}
	return strings.TrimSpace(h[len(prefix):]), true
}

func formatTime(t time.Time) string { return t.UTC().Format(time.RFC3339Nano) }

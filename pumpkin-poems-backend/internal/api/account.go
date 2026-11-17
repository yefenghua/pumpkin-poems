package api

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/yefenghua/pumpkin-poems/backend/internal/auth"
	"github.com/yefenghua/pumpkin-poems/backend/internal/cloudsync"
	"github.com/yefenghua/pumpkin-poems/backend/internal/store"
)

const maxNicknameRunes = 20

var validStages = map[string]bool{"p4": true, "p5": true, "p6": true, "s1": true}

type tokenResponse struct {
	AccessToken string `json:"accessToken"`
	ExpiresAt   string `json:"expiresAt"`
	ParentID    string `json:"parentID"`
	AccountID   string `json:"accountID"`
}

type credentials struct {
	AccountID string `json:"accountID"`
	Password  string `json:"password"`
}

// register creates a parent account from an account ID and a password and
// signs it in. The server stores only the lower-cased account ID and an
// Argon2id hash: there is no e-mail, so a forgotten password cannot be reset.
func (s *Server) register(w http.ResponseWriter, r *http.Request) {
	var req credentials
	if !decode(w, r, limitSmall, &req) {
		return
	}
	accountID, err := auth.NormalizeAccountID(req.AccountID)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid_account_id", err.Error())
		return
	}
	if err := auth.ValidatePassword(req.Password, accountID); err != nil {
		writeError(w, http.StatusBadRequest, "weak_password", err.Error())
		return
	}
	parent, err := s.cfg.Store.CreateParent(r.Context(), store.Parent{
		AccountID: accountID, PasswordHash: auth.HashPassword(req.Password),
		CreatedAt: s.cfg.Now().UTC().Truncate(time.Microsecond),
	})
	if errors.Is(err, store.ErrConflict) {
		writeError(w, http.StatusConflict, "account_id_taken", "this account id is already registered")
		return
	}
	if err != nil {
		s.internalError(w, r, err)
		return
	}
	s.issueToken(w, r, parent, http.StatusCreated)
}

// login verifies the password. Unknown account and wrong password give the
// same answer (and take the same time) so account IDs cannot be enumerated;
// repeated failures on one account are throttled by the login limiter.
func (s *Server) login(w http.ResponseWriter, r *http.Request) {
	var req credentials
	if !decode(w, r, limitSmall, &req) {
		return
	}
	accountID, err := auth.NormalizeAccountID(req.AccountID)
	if err != nil || req.Password == "" {
		writeError(w, http.StatusUnauthorized, "invalid_credentials", "account id or password is wrong")
		return
	}
	if ok, wait := s.cfg.Limiter.Allow(accountID); !ok {
		w.Header().Set("Retry-After", fmt.Sprint(int(wait.Seconds())+1))
		writeError(w, http.StatusTooManyRequests, "too_many_attempts", "too many failed logins; try again later")
		return
	}
	parent, err := s.cfg.Store.ParentByAccountID(r.Context(), accountID)
	hash := parent.PasswordHash
	if errors.Is(err, store.ErrNotFound) {
		hash, err = auth.DummyHash, nil
	}
	if err != nil {
		s.internalError(w, r, err)
		return
	}
	if !auth.VerifyPassword(hash, req.Password) || parent.ID == "" {
		s.cfg.Limiter.Fail(accountID)
		writeError(w, http.StatusUnauthorized, "invalid_credentials", "account id or password is wrong")
		return
	}
	s.cfg.Limiter.Reset(accountID)
	s.issueToken(w, r, parent, http.StatusOK)
}

func (s *Server) issueToken(w http.ResponseWriter, r *http.Request, parent store.Parent, status int) {
	token, hash := auth.NewAccessToken()
	expires := s.cfg.Now().Add(auth.TokenTTL).UTC().Truncate(time.Second)
	if err := s.cfg.Store.CreateSession(r.Context(), parent.ID, hash, expires); err != nil {
		s.internalError(w, r, err)
		return
	}
	writeJSON(w, status, tokenResponse{AccessToken: token, ExpiresAt: formatTime(expires), ParentID: parent.ID, AccountID: parent.AccountID})
}

// logout revokes the presented token only; other devices stay signed in.
func (s *Server) logout(w http.ResponseWriter, r *http.Request, _ string) {
	token, _ := bearer(r)
	if err := s.cfg.Store.DeleteSession(r.Context(), auth.HashToken(token)); err != nil {
		s.internalError(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// changePassword needs the current password and signs every other device out.
func (s *Server) changePassword(w http.ResponseWriter, r *http.Request, parentID string) {
	var req struct {
		CurrentPassword string `json:"currentPassword"`
		NewPassword     string `json:"newPassword"`
	}
	if !decode(w, r, limitSmall, &req) {
		return
	}
	ctx := r.Context()
	parent, err := s.cfg.Store.ParentByID(ctx, parentID)
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusUnauthorized, "unauthorized", "account no longer exists")
		return
	}
	if err != nil {
		s.internalError(w, r, err)
		return
	}
	if !auth.VerifyPassword(parent.PasswordHash, req.CurrentPassword) {
		writeError(w, http.StatusForbidden, "wrong_password", "current password is wrong")
		return
	}
	if err := auth.ValidatePassword(req.NewPassword, parent.AccountID); err != nil {
		writeError(w, http.StatusBadRequest, "weak_password", err.Error())
		return
	}
	if err := s.cfg.Store.UpdatePassword(ctx, parentID, auth.HashPassword(req.NewPassword)); err != nil {
		s.internalError(w, r, err)
		return
	}
	token, _ := bearer(r)
	if err := s.cfg.Store.DeleteOtherSessions(ctx, parentID, auth.HashToken(token)); err != nil {
		s.internalError(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) getAccount(w http.ResponseWriter, r *http.Request, parentID string) {
	parent, err := s.cfg.Store.ParentByID(r.Context(), parentID)
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusUnauthorized, "unauthorized", "account no longer exists")
		return
	}
	if err != nil {
		s.internalError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"parentID": parent.ID, "accountID": parent.AccountID, "createdAt": formatTime(parent.CreatedAt)})
}

func (s *Server) deleteAccount(w http.ResponseWriter, r *http.Request, parentID string) {
	if err := s.cfg.Store.DeleteAccount(r.Context(), parentID); err != nil {
		s.internalError(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

type profileJSON struct {
	ID        string  `json:"id"`
	Nickname  string  `json:"nickname"`
	Stage     *string `json:"stage"`
	CreatedAt string  `json:"createdAt"`
}

func toProfileJSON(p store.Profile) profileJSON {
	return profileJSON{ID: p.ID, Nickname: p.Nickname, Stage: p.Stage, CreatedAt: formatTime(p.CreatedAt)}
}

func (s *Server) listProfiles(w http.ResponseWriter, r *http.Request, parentID string) {
	ps, err := s.cfg.Store.ListProfiles(r.Context(), parentID)
	if err != nil {
		s.internalError(w, r, err)
		return
	}
	out := make([]profileJSON, len(ps))
	for i, p := range ps {
		out[i] = toProfileJSON(p)
	}
	writeJSON(w, http.StatusOK, map[string]any{"profiles": out})
}

func validNickname(n string) bool {
	return strings.TrimSpace(n) != "" && utf8.RuneCountInString(n) <= maxNicknameRunes
}

func (s *Server) createProfile(w http.ResponseWriter, r *http.Request, parentID string) {
	var req struct {
		ID       string  `json:"id"`
		Nickname string  `json:"nickname"`
		Stage    *string `json:"stage"`
	}
	if !decode(w, r, limitSmall, &req) {
		return
	}
	switch {
	case req.ID == "" || len(req.ID) > 128:
		writeError(w, http.StatusBadRequest, "invalid_request", "id is required")
		return
	case !validNickname(req.Nickname):
		writeError(w, http.StatusBadRequest, "invalid_request", "nickname is required (max 20 characters)")
		return
	case req.Stage != nil && !validStages[*req.Stage]:
		writeError(w, http.StatusBadRequest, "invalid_request", "stage must be p4, p5, p6, s1 or null")
		return
	}
	p, created, err := s.cfg.Store.CreateProfile(r.Context(), store.Profile{
		ID: req.ID, ParentID: parentID, Nickname: req.Nickname, Stage: req.Stage,
		CreatedAt: s.cfg.Now().UTC().Truncate(time.Microsecond),
	})
	if errors.Is(err, store.ErrConflict) {
		writeError(w, http.StatusConflict, "profile_id_taken", "profile id is already in use")
		return
	}
	if err != nil {
		s.internalError(w, r, err)
		return
	}
	status := http.StatusOK
	if created {
		status = http.StatusCreated
	}
	writeJSON(w, status, toProfileJSON(p))
}

func (s *Server) updateProfile(w http.ResponseWriter, r *http.Request, parentID string) {
	var raw map[string]json.RawMessage
	if !decode(w, r, limitSmall, &raw) {
		return
	}
	var patch store.ProfilePatch
	if v, ok := raw["nickname"]; ok {
		var n string
		if json.Unmarshal(v, &n) != nil || !validNickname(n) {
			writeError(w, http.StatusBadRequest, "invalid_request", "nickname must be 1-20 characters")
			return
		}
		patch.Nickname = &n
	}
	if v, ok := raw["stage"]; ok {
		var st *string
		if json.Unmarshal(v, &st) != nil || (st != nil && !validStages[*st]) {
			writeError(w, http.StatusBadRequest, "invalid_request", "stage must be p4, p5, p6, s1 or null")
			return
		}
		patch.SetStage, patch.Stage = true, st
	}
	p, err := s.cfg.Store.UpdateProfile(r.Context(), parentID, r.PathValue("id"), patch)
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, "not_found", "profile not found")
		return
	}
	if err != nil {
		s.internalError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, toProfileJSON(p))
}

func (s *Server) deleteProfile(w http.ResponseWriter, r *http.Request, parentID string) {
	err := s.cfg.Store.DeleteProfile(r.Context(), parentID, r.PathValue("id"))
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, "not_found", "profile not found")
		return
	}
	if err != nil {
		s.internalError(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) syncProfile(w http.ResponseWriter, r *http.Request, parentID string) {
	var req cloudsync.Request
	if !decode(w, r, limitSync, &req) {
		return
	}
	resp, err := cloudsync.Apply(r.Context(), s.cfg.Store, parentID, r.PathValue("id"), req)
	var verr *cloudsync.ValidationError
	switch {
	case errors.As(err, &verr):
		writeError(w, http.StatusBadRequest, "invalid_request", verr.Msg)
		return
	case errors.Is(err, store.ErrNotFound):
		writeError(w, http.StatusNotFound, "not_found", "profile not found")
		return
	case err != nil:
		s.internalError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, resp)
}

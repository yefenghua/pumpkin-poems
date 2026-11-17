package api

import (
	"fmt"
	"net/http"
	"regexp"
	"time"
	"unicode/utf8"

	"github.com/yefenghua/pumpkin-poems/backend/internal/metrics"
	"github.com/yefenghua/pumpkin-poems/backend/internal/store"
)

const (
	maxEventsPerBatch = 500
	maxPropsPerEvent  = 32
	maxFeedbackRunes  = 5000
	maxMetricsDays    = 366
)

var eventName = regexp.MustCompile(`^[a-z][a-z0-9_]{0,63}$`)

type eventsRequest struct {
	InstallID  string `json:"installID"`
	AppVersion string `json:"appVersion"`
	Events     []struct {
		ID             string         `json:"id"`
		Name           string         `json:"name"`
		At             time.Time      `json:"at"`
		ContentVersion string         `json:"contentVersion"`
		RuleVersion    *int           `json:"ruleVersion"`
		Props          map[string]any `json:"props"`
	} `json:"events"`
}

func (s *Server) postEvents(w http.ResponseWriter, r *http.Request) {
	var req eventsRequest
	if !decode(w, r, limitEvents, &req) {
		return
	}
	if req.InstallID == "" || len(req.InstallID) > 128 {
		writeError(w, http.StatusBadRequest, "invalid_request", "installID is required")
		return
	}
	if len(req.Events) > maxEventsPerBatch {
		writeError(w, http.StatusBadRequest, "too_many_events",
			fmt.Sprintf("at most %d events per request", maxEventsPerBatch))
		return
	}
	events := make([]store.AnalyticsEvent, 0, len(req.Events))
	for i, e := range req.Events {
		if msg := validateEvent(e.ID, e.Name, e.At, e.Props); msg != "" {
			writeError(w, http.StatusBadRequest, "invalid_event", fmt.Sprintf("events[%d]: %s", i, msg))
			return
		}
		events = append(events, store.AnalyticsEvent{
			ID: e.ID, InstallID: req.InstallID, AppVersion: req.AppVersion, Name: e.Name,
			At: e.At.UTC(), ContentVersion: e.ContentVersion, RuleVersion: e.RuleVersion, Props: e.Props,
		})
	}
	accepted, dups, err := s.cfg.Store.InsertAnalyticsEvents(r.Context(), events)
	if err != nil {
		s.internalError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]int{"accepted": accepted, "duplicates": dups})
}

// validateEvent enforces the contract: props values are strings, numbers or
// booleans only. Unknown event names are accepted so newer clients do not
// get stuck retrying.
func validateEvent(id, name string, at time.Time, props map[string]any) string {
	switch {
	case id == "" || len(id) > 128:
		return "id is required"
	case !eventName.MatchString(name):
		return "name must be snake_case"
	case at.IsZero():
		return "at is required"
	case len(props) > maxPropsPerEvent:
		return fmt.Sprintf("at most %d props", maxPropsPerEvent)
	}
	for k, v := range props {
		switch v.(type) {
		case string, float64, bool:
		default:
			return fmt.Sprintf("props.%s must be a string, number or boolean", k)
		}
	}
	return ""
}

var feedbackCategories = map[string]bool{"content": true, "bug": true, "idea": true, "other": true}

type feedbackRequest struct {
	ID             string    `json:"id"`
	InstallID      string    `json:"installID"`
	At             time.Time `json:"at"`
	Category       string    `json:"category"`
	Message        string    `json:"message"`
	ContentVersion string    `json:"contentVersion"`
	AppVersion     string    `json:"appVersion"`
}

func (s *Server) postFeedback(w http.ResponseWriter, r *http.Request) {
	var req feedbackRequest
	if !decode(w, r, limitFeedback, &req) {
		return
	}
	switch {
	case req.ID == "" || len(req.ID) > 128:
		writeError(w, http.StatusBadRequest, "invalid_request", "id is required")
		return
	case req.InstallID == "" || len(req.InstallID) > 128:
		writeError(w, http.StatusBadRequest, "invalid_request", "installID is required")
		return
	case !feedbackCategories[req.Category]:
		writeError(w, http.StatusBadRequest, "invalid_request", "category must be content, bug, idea or other")
		return
	case req.Message == "" || utf8.RuneCountInString(req.Message) > maxFeedbackRunes:
		writeError(w, http.StatusBadRequest, "invalid_request",
			fmt.Sprintf("message is required (max %d characters)", maxFeedbackRunes))
		return
	}
	at := req.At
	if at.IsZero() {
		at = s.cfg.Now()
	}
	created, err := s.cfg.Store.InsertFeedback(r.Context(), store.Feedback{
		ID: req.ID, InstallID: req.InstallID, At: at.UTC(), Category: req.Category,
		Message: req.Message, ContentVersion: req.ContentVersion, AppVersion: req.AppVersion,
	})
	if err != nil {
		s.internalError(w, r, err)
		return
	}
	status := http.StatusOK
	if created {
		status = http.StatusCreated
	}
	writeJSON(w, status, struct{}{})
}

// getMetrics: from/to are inclusive calendar dates (YYYY-MM-DD). Days are
// UTC unless the optional tz parameter names an IANA zone (e.g.
// Asia/Hong_Kong); install-days and the second-week window use that zone.
func (s *Server) getMetrics(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	loc := time.UTC
	if tz := q.Get("tz"); tz != "" {
		l, err := time.LoadLocation(tz)
		if err != nil {
			writeError(w, http.StatusBadRequest, "invalid_request", "unknown tz")
			return
		}
		loc = l
	}
	from, err1 := time.ParseInLocation(time.DateOnly, q.Get("from"), loc)
	to, err2 := time.ParseInLocation(time.DateOnly, q.Get("to"), loc)
	if err1 != nil || err2 != nil {
		writeError(w, http.StatusBadRequest, "invalid_request", "from and to must be YYYY-MM-DD")
		return
	}
	end := to.AddDate(0, 0, 1)
	if !end.After(from) || end.Sub(from) > maxMetricsDays*24*time.Hour+time.Hour {
		writeError(w, http.StatusBadRequest, "invalid_request",
			fmt.Sprintf("to must not be before from and the range is at most %d days", maxMetricsDays))
		return
	}
	events, err := s.cfg.Store.ListAnalyticsEvents(r.Context(), from, end)
	if err != nil {
		s.internalError(w, r, err)
		return
	}
	groups := metrics.Compute(events, metrics.Window{Start: from, End: end, Loc: loc, Now: s.cfg.Now()})
	writeJSON(w, http.StatusOK, map[string]any{
		"from": q.Get("from"), "to": q.Get("to"), "groups": groups,
	})
}

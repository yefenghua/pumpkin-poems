// Package metrics computes the five phase-2 trial metrics (phase-2 plan §8,
// API contract §2) from anonymous analytics events.
package metrics

import (
	"sort"
	"time"

	"github.com/yefenghua/pumpkin-poems/backend/internal/store"
)

type Ratio struct {
	Numerator   int `json:"numerator"`
	Denominator int `json:"denominator"`
}

type Group struct {
	ContentVersion         string `json:"contentVersion"`
	LearningCompletion     Ratio  `json:"learningCompletion"`
	DueReviewParticipation Ratio  `json:"dueReviewParticipation"`
	CrossDayUnaidedPass    Ratio  `json:"crossDayUnaidedPass"`
	SecondWeekReturn       Ratio  `json:"secondWeekReturn"`
	CreationCompletion     Ratio  `json:"creationCompletion"`
}

// Window is [Start, End) with calendar days evaluated in Loc.
type Window struct {
	Start, End time.Time
	Loc        *time.Location
	// Now caps the observation end for secondWeekReturn when the window
	// extends into the future.
	Now time.Time
}

// Compute groups events by contentVersion and evaluates every metric inside
// each group independently. Events outside the window are ignored.
//
//   - learningCompletion: installs with a quiz_completed whose isReview is not
//     true, among installs with poem_learning_started.
//   - dueReviewParticipation: install-days with review_completed, among
//     install-days where poem_learning_started / review_completed /
//     app_day_opened reported dueCount > 0.
//   - crossDayUnaidedPass: review_completed with passed && !usedHints over all
//     review_completed.
//   - secondWeekReturn: installs with quiz_completed on calendar days 8–14
//     (day 1 = day of their first poem_learning_started), among installs whose
//     day 14 has ended before the observation end.
//   - creationCompletion: installs with creation_saved among installs with
//     creation_started.
//
// Numerators of the install / install-day ratios only count members of the
// denominator, so every ratio stays within [0, 1].
func Compute(events []store.AnalyticsEvent, w Window) []Group {
	loc := w.Loc
	if loc == nil {
		loc = time.UTC
	}
	obsEnd := w.End
	if !w.Now.IsZero() && w.Now.Before(obsEnd) {
		obsEnd = w.Now
	}

	byVersion := map[string][]store.AnalyticsEvent{}
	for _, e := range events {
		if e.At.Before(w.Start) || !e.At.Before(w.End) {
			continue
		}
		byVersion[e.ContentVersion] = append(byVersion[e.ContentVersion], e)
	}
	versions := make([]string, 0, len(byVersion))
	for v := range byVersion {
		versions = append(versions, v)
	}
	sort.Strings(versions)

	groups := make([]Group, 0, len(versions))
	for _, v := range versions {
		g := compute(byVersion[v], loc, obsEnd)
		g.ContentVersion = v
		groups = append(groups, g)
	}
	return groups
}

type installDay struct {
	install string
	day     civilDay
}

type civilDay struct {
	y int
	m time.Month
	d int
}

func dayOf(t time.Time, loc *time.Location) civilDay {
	y, m, d := t.In(loc).Date()
	return civilDay{y, m, d}
}

// daysBetween returns b - a in whole calendar days.
func daysBetween(a, b civilDay) int {
	ta := time.Date(a.y, a.m, a.d, 12, 0, 0, 0, time.UTC)
	tb := time.Date(b.y, b.m, b.d, 12, 0, 0, 0, time.UTC)
	return int(tb.Sub(ta).Round(24*time.Hour) / (24 * time.Hour))
}

func compute(events []store.AnalyticsEvent, loc *time.Location, obsEnd time.Time) Group {
	var g Group

	learnStarted := map[string]bool{}
	firstLearn := map[string]time.Time{}
	quizFirst := map[string]bool{}
	creationStarted := map[string]bool{}
	creationSaved := map[string]bool{}
	dueDays := map[installDay]bool{}
	reviewDays := map[installDay]bool{}
	var quizzes []store.AnalyticsEvent

	for _, e := range events {
		inst := e.InstallID
		day := installDay{inst, dayOf(e.At, loc)}
		switch e.Name {
		case "poem_learning_started":
			learnStarted[inst] = true
			if t, ok := firstLearn[inst]; !ok || e.At.Before(t) {
				firstLearn[inst] = e.At
			}
		case "quiz_completed":
			if !boolProp(e.Props, "isReview") {
				quizFirst[inst] = true
			}
			quizzes = append(quizzes, e)
		case "review_completed":
			reviewDays[day] = true
			g.CrossDayUnaidedPass.Denominator++
			if boolProp(e.Props, "passed") && !boolProp(e.Props, "usedHints") {
				g.CrossDayUnaidedPass.Numerator++
			}
		case "creation_started":
			creationStarted[inst] = true
		case "creation_saved":
			creationSaved[inst] = true
		}
		switch e.Name {
		case "poem_learning_started", "review_completed", "app_day_opened":
			if numProp(e.Props, "dueCount") > 0 {
				dueDays[day] = true
			}
		}
	}

	g.LearningCompletion = subsetRatio(learnStarted, quizFirst)
	g.CreationCompletion = subsetRatio(creationStarted, creationSaved)
	g.DueReviewParticipation = subsetRatio(dueDays, reviewDays)

	// secondWeekReturn: eligible once the whole second week is observable.
	obsEndDay := dayOf(obsEnd, loc) // first day not fully observed
	eligible := map[string]civilDay{}
	for inst, t := range firstLearn {
		first := dayOf(t, loc)
		if daysBetween(first, obsEndDay) >= 14 {
			eligible[inst] = first
		}
	}
	returned := map[string]bool{}
	for _, q := range quizzes {
		first, ok := eligible[q.InstallID]
		if !ok {
			continue
		}
		if d := daysBetween(first, dayOf(q.At, loc)); d >= 7 && d <= 13 {
			returned[q.InstallID] = true
		}
	}
	g.SecondWeekReturn = Ratio{Numerator: len(returned), Denominator: len(eligible)}
	return g
}

func subsetRatio[K comparable](denom, num map[K]bool) Ratio {
	r := Ratio{Denominator: len(denom)}
	for k := range num {
		if denom[k] {
			r.Numerator++
		}
	}
	return r
}

func boolProp(p map[string]any, key string) bool {
	b, _ := p[key].(bool)
	return b
}

func numProp(p map[string]any, key string) float64 {
	switch v := p[key].(type) {
	case float64:
		return v
	case int:
		return float64(v)
	case int64:
		return float64(v)
	}
	return 0
}

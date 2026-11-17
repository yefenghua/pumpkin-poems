package metrics

import (
	"fmt"
	"testing"
	"time"

	"github.com/yefenghua/pumpkin-poems/backend/internal/store"
)

var day0 = time.Date(2026, 11, 1, 0, 0, 0, 0, time.UTC)

func at(day int, hour int) time.Time {
	return day0.AddDate(0, 0, day).Add(time.Duration(hour) * time.Hour)
}

var n int

func e(install, name string, t time.Time, props map[string]any) store.AnalyticsEvent {
	n++
	return store.AnalyticsEvent{ID: fmt.Sprint(n), InstallID: install, Name: name, At: t, ContentVersion: "r1", Props: props}
}

func TestCompute(t *testing.T) {
	events := []store.AnalyticsEvent{
		// learningCompletion: A, B, C start; A completes a first quiz; B only
		// a review quiz; D completes without a start event (not counted).
		e("A", "poem_learning_started", at(0, 1), map[string]any{"dueCount": 0.0}),
		e("A", "quiz_completed", at(0, 2), map[string]any{"isReview": false, "passed": true}),
		e("B", "poem_learning_started", at(0, 1), nil),
		e("B", "quiz_completed", at(0, 2), map[string]any{"isReview": true}),
		e("C", "poem_learning_started", at(3, 1), nil),
		e("D", "quiz_completed", at(0, 2), map[string]any{"isReview": false}),

		// dueReviewParticipation: A has due work on days 1 and 2, reviews on
		// day 1 only (twice: still one install-day); B due on day 1 via
		// review_completed itself; C reviews on a day with no due report.
		e("A", "app_day_opened", at(1, 1), map[string]any{"dueCount": 3.0}),
		e("A", "review_completed", at(1, 2), map[string]any{"passed": true, "usedHints": false}),
		e("A", "review_completed", at(1, 3), map[string]any{"passed": true, "usedHints": true}),
		e("A", "app_day_opened", at(2, 1), map[string]any{"dueCount": 1.0}),
		e("B", "review_completed", at(1, 5), map[string]any{"passed": false, "dueCount": 2.0}),
		e("C", "review_completed", at(4, 5), map[string]any{"passed": true}),
		e("C", "app_day_opened", at(5, 5), map[string]any{"dueCount": 0.0}),

		// secondWeekReturn: A first learned day 0 → second week is days 7–13.
		e("A", "quiz_completed", at(9, 1), map[string]any{"isReview": true}),
		// B learns day 0 and returns on day 14 (third week): not counted.
		e("B", "quiz_completed", at(14, 1), map[string]any{"isReview": true}),

		// creationCompletion: A starts and saves, B only starts.
		e("A", "creation_started", at(2, 1), nil),
		e("A", "creation_saved", at(2, 2), nil),
		e("B", "creation_started", at(2, 1), nil),
		e("C", "creation_saved", at(2, 1), nil),
	}
	other := e("A", "quiz_completed", at(0, 5), nil)
	other.ContentVersion = "r0"
	events = append(events, other, e("Z", "poem_learning_started", day0.AddDate(0, 1, 0), nil)) // outside window

	w := Window{Start: day0, End: day0.AddDate(0, 0, 15), Loc: time.UTC, Now: day0.AddDate(1, 0, 0)}
	groups := Compute(events, w)
	if len(groups) != 2 || groups[0].ContentVersion != "r0" || groups[1].ContentVersion != "r1" {
		t.Fatalf("groups = %+v", groups)
	}
	g := groups[1]
	check := func(name string, got Ratio, num, den int) {
		t.Helper()
		if got.Numerator != num || got.Denominator != den {
			t.Errorf("%s = %d/%d, want %d/%d", name, got.Numerator, got.Denominator, num, den)
		}
	}
	check("learningCompletion", g.LearningCompletion, 1, 3)
	check("dueReviewParticipation", g.DueReviewParticipation, 2, 3)
	check("crossDayUnaidedPass", g.CrossDayUnaidedPass, 2, 4)
	// A and B are eligible (day 0 + 14 <= window end day 15); C (day 3) is not.
	check("secondWeekReturn", g.SecondWeekReturn, 1, 2)
	check("creationCompletion", g.CreationCompletion, 1, 2)

	// A window ending on day 13 cannot observe anyone's full second week.
	w.End = day0.AddDate(0, 0, 13)
	g = Compute(events, w)[1]
	check("secondWeekReturn (short window)", g.SecondWeekReturn, 0, 0)

	// "Now" caps observation when the window extends into the future.
	w.End, w.Now = day0.AddDate(0, 0, 30), at(13, 23)
	g = Compute(events, w)[1]
	check("secondWeekReturn (now cap)", g.SecondWeekReturn, 0, 0)
}

func TestComputeTimeZone(t *testing.T) {
	hk, err := time.LoadLocation("Asia/Hong_Kong")
	if err != nil {
		t.Skip("no tzdata")
	}
	// 23:30 UTC on Nov 1 is Nov 2 07:30 in Hong Kong: same HK day as the review.
	events := []store.AnalyticsEvent{
		e("A", "app_day_opened", time.Date(2026, 11, 1, 23, 30, 0, 0, time.UTC), map[string]any{"dueCount": 1.0}),
		e("A", "review_completed", time.Date(2026, 11, 2, 2, 0, 0, 0, time.UTC), nil),
	}
	w := Window{Start: day0, End: day0.AddDate(0, 0, 5)}
	if g := Compute(events, w)[0]; g.DueReviewParticipation != (Ratio{0, 1}) {
		t.Fatalf("UTC: %+v", g.DueReviewParticipation)
	}
	w.Loc = hk
	if g := Compute(events, w)[0]; g.DueReviewParticipation != (Ratio{1, 1}) {
		t.Fatalf("HK: %+v", g.DueReviewParticipation)
	}
}

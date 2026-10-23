import Foundation

/// Review state for one poem, independent of storage so the rules can be tested directly.
struct ReviewState: Equatable {
    var firstPassedAt: Date?
    var lastPassedAt: Date?
    var reviewStep = 0
    var nextReviewAt: Date?
    /// Set the first time the poem is passed again on a later day (记忆较稳).
    var stableAt: Date?
    /// Card proficiency shown in the growth book; 0 until the first pass.
    var cardLevel = 0
}

enum ReviewEvent: Equatable {
    /// First successful practice: a poem card is earned.
    case firstPass
    /// Passed again on a later calendar day.
    case reviewPassed
    /// Passed again on the same day; no extra reward or schedule change.
    case repeatedSameDay
    case failed
}

/// Local, adjustable review rule: after the first pass, review on day 1, 3, 7, 14, then every 30 days.
/// Any mistake (or a failed practice) brings the next review forward to tomorrow.
struct ReviewScheduler {
    static let intervals = [1, 3, 7, 14, 30]
    static let maxCardLevel = 5

    var calendar = Calendar.current

    func apply(passed: Bool, hadMistakes: Bool, at now: Date, to state: inout ReviewState) -> ReviewEvent {
        let today = calendar.startOfDay(for: now)
        let tomorrow = day(1, after: today)
        let event: ReviewEvent

        if passed {
            if state.firstPassedAt == nil {
                state.firstPassedAt = now
                state.reviewStep = 0
                state.cardLevel = 1
                state.nextReviewAt = day(Self.intervals[0], after: today)
                event = .firstPass
            } else if let last = state.lastPassedAt, calendar.startOfDay(for: last) < today {
                state.reviewStep += 1
                state.stableAt = state.stableAt ?? now
                state.cardLevel = min(state.cardLevel + 1, Self.maxCardLevel)
                let interval = Self.intervals[min(state.reviewStep, Self.intervals.count - 1)]
                state.nextReviewAt = day(interval, after: today)
                event = .reviewPassed
            } else {
                event = .repeatedSameDay
            }
            state.lastPassedAt = now
            if hadMistakes, let next = state.nextReviewAt, next > tomorrow {
                state.nextReviewAt = tomorrow
            }
        } else {
            if state.firstPassedAt != nil {
                state.reviewStep = max(0, state.reviewStep - 1)
                state.nextReviewAt = tomorrow
            }
            event = .failed
        }
        return event
    }

    func isDue(_ state: ReviewState, at now: Date) -> Bool {
        guard let next = state.nextReviewAt else { return false }
        return next <= now
    }

    private func day(_ days: Int, after date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }
}

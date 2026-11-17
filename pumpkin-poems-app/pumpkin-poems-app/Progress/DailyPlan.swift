import Foundation

/// 每日学习计划 (phase-2 §3.2): a light goal of about 5, 10 or 15 minutes turned into a task amount — due reviews
/// first (poems with open mistakes first), then one new poem. A backlog is split over the following days instead
/// of being cleared at once, and the learner can rest for a day. Pure logic over poem IDs, so it is tested directly.
struct DailyPlan: Equatable {
    static let goalOptions = [5, 10, 15]
    static let defaultMinutes = 10

    struct Quota: Equatable {
        let reviews: Int
        let newPoems: Int
    }

    static func quota(minutes: Int, hasDueReviews: Bool) -> Quota {
        switch minutes {
        case ..<10: Quota(reviews: 2, newPoems: hasDueReviews ? 0 : 1)
        case 10..<15: Quota(reviews: 3, newPoems: 1)
        default: Quota(reviews: 5, newPoems: 1)
        }
    }

    let minutes: Int
    let isPaused: Bool
    /// Reviews to do today, in order.
    let reviewsToday: [String]
    /// Due reviews left for the next days.
    let backlog: Int
    let reviewsDone: Int
    let reviewTarget: Int
    /// The new poem to start, if today's plan still has room for one.
    let newPoem: String?
    let newDone: Int
    let newTarget: Int

    /// - Parameters:
    ///   - due: due poems already ordered (open mistakes first, then longest overdue).
    ///   - reviewedToday: distinct poems with a due review taken today (passed or not).
    ///   - startedToday: distinct poems opened for the first time today.
    ///   - nextNew: the next unstarted poem, if any.
    init(minutes: Int, pausedOn: Date?, today: Date, due: [String], reviewedToday: Int, startedToday: Int, nextNew: String?) {
        self.minutes = minutes
        isPaused = pausedOn == today
        let quota = Self.quota(minutes: minutes, hasDueReviews: !due.isEmpty || reviewedToday > 0)
        reviewTarget = min(quota.reviews, due.count + reviewedToday)
        reviewsDone = min(reviewedToday, reviewTarget)
        let remaining = isPaused ? 0 : max(0, quota.reviews - reviewedToday)
        reviewsToday = Array(due.prefix(remaining))
        backlog = due.count - reviewsToday.count
        newTarget = nextNew == nil && startedToday == 0 ? 0 : quota.newPoems
        newDone = min(startedToday, newTarget)
        newPoem = isPaused || newDone >= newTarget ? nil : nextNew
    }

    var isComplete: Bool {
        !isPaused && reviewsDone >= reviewTarget && newDone >= newTarget && (reviewTarget + newTarget) > 0
    }

    var hasNothingToDo: Bool { reviewTarget == 0 && newTarget == 0 }
}

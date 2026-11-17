import Foundation

/// Review state for one poem, independent of storage so the rules can be tested directly.
struct ReviewState: Equatable, Codable {
    var firstPassedAt: Date?
    var lastPassedAt: Date?
    /// Review nodes completed so far (0 … intervals.count).
    var reviewStep = 0
    var nextReviewAt: Date?
    /// 记忆较稳 — kept once earned, even if a later rule version is stricter.
    var stableAt: Date?
    /// Card proficiency shown in the growth book; 0 until the first pass.
    var cardLevel = 0
    /// Start-of-day dates of due reviews passed without hints.
    var unaidedReviewDays: [Date] = []
}

/// One practice round as the scheduler sees it.
struct QuizResult: Equatable {
    var passed: Bool
    var usedHints: Bool
}

enum ReviewEvent: String, Equatable, Codable {
    /// First successful practice: a poem card is earned.
    case firstPass
    /// A due review passed without hints: on to the next node.
    case reviewPassed
    /// A due review passed with hints: counts as 有提示完成, the same node comes back tomorrow.
    case reviewHinted
    /// A due review not passed: the same node comes back tomorrow.
    case reviewFailed
    /// Practice on a day nothing was due (including again on the same day): no schedule change.
    case practice
    /// Not passed, outside a due review.
    case failed

    /// Whether this round was a cross-day review (for statistics and the completion page).
    var isReview: Bool { self == .reviewPassed || self == .reviewHinted || self == .reviewFailed }
}

/// Phase-2 review rule (§3.2), version 2:
/// - review nodes on day 1, 3, 7, 14 and 30 counted from the first pass;
/// - a due review that is not passed (or passed only with hints) retries the same node tomorrow;
/// - overdue nodes are never stacked: after a late review the next node is at the earliest tomorrow;
/// - 记忆较稳 needs unaided reviews on at least two different days, the latest at least 7 days after the first pass.
struct ReviewScheduler {
    static let ruleVersion = 2
    static let intervals = [1, 3, 7, 14, 30]
    static let maxCardLevel = 5
    static let stableMinReviews = 2
    static let stableMinSpanDays = 7

    var calendar = Calendar.current

    func apply(_ result: QuizResult, at now: Date, to state: inout ReviewState) -> ReviewEvent {
        let today = calendar.startOfDay(for: now)
        let tomorrow = day(1, after: today)

        guard let firstPassedAt = state.firstPassedAt else {
            guard result.passed else { return .failed }
            state.firstPassedAt = now
            state.lastPassedAt = now
            state.reviewStep = 0
            state.cardLevel = max(state.cardLevel, 1)
            state.nextReviewAt = day(Self.intervals[0], after: today)
            return .firstPass
        }

        let isDue = state.nextReviewAt.map { $0 <= now } ?? false
        guard isDue else {
            if result.passed {
                state.lastPassedAt = now
                return .practice
            }
            // A failed extra practice brings the next review forward, never back.
            if let next = state.nextReviewAt, next > tomorrow { state.nextReviewAt = tomorrow }
            return .failed
        }

        guard result.passed else {
            state.nextReviewAt = tomorrow
            return .reviewFailed
        }
        state.lastPassedAt = now
        guard !result.usedHints else {
            state.nextReviewAt = tomorrow
            return .reviewHinted
        }

        state.reviewStep += 1
        state.cardLevel = min(state.cardLevel + 1, Self.maxCardLevel)
        if !state.unaidedReviewDays.contains(today) {
            state.unaidedReviewDays.append(today)
        }
        let firstDay = calendar.startOfDay(for: firstPassedAt)
        if state.reviewStep < Self.intervals.count {
            state.nextReviewAt = max(day(Self.intervals[state.reviewStep], after: firstDay), tomorrow)
        } else {
            state.nextReviewAt = nil
        }
        if state.stableAt == nil, isStable(state, firstDay: firstDay, today: today) {
            state.stableAt = now
        }
        return .reviewPassed
    }

    func isDue(_ state: ReviewState, at now: Date) -> Bool {
        guard let next = state.nextReviewAt else { return false }
        return next <= now
    }

    /// The review plan is finished once every node has been passed.
    func isPlanComplete(_ state: ReviewState) -> Bool {
        state.firstPassedAt != nil && state.reviewStep >= Self.intervals.count
    }

    private func isStable(_ state: ReviewState, firstDay: Date, today: Date) -> Bool {
        guard Set(state.unaidedReviewDays).count >= Self.stableMinReviews else { return false }
        let span = calendar.dateComponents([.day], from: firstDay, to: today).day ?? 0
        return span >= Self.stableMinSpanDays
    }

    private func day(_ days: Int, after date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }
}

/// Scores one practice round (§3.2 rule 1–3). Only first submissions count; an answer reached with a hint counts
/// towards the score but marks the round as 有提示完成.
struct QuizEvaluation: Equatable {
    struct Answer: Equatable, Codable {
        let questionID: String
        let kind: Question.Kind
        let correct: Bool
        let hinted: Bool
    }

    let score: Int
    let total: Int
    let understanding: (correct: Int, total: Int)
    let memory: (correct: Int, total: Int)
    let usedHints: Bool
    let passed: Bool

    init(_ answers: [Answer]) {
        score = answers.filter(\.correct).count
        total = answers.count
        func tally(_ dimension: LearningDimension) -> (Int, Int) {
            let items = answers.filter { $0.kind.dimension == dimension }
            return (items.filter(\.correct).count, items.count)
        }
        understanding = tally(.understanding)
        memory = tally(.memory)
        usedHints = answers.contains(where: \.hinted)
        // 80% overall, and at least one right in each dimension that was asked.
        let overall = total > 0 && score * 5 >= total * 4
        let eachDimension = [understanding, memory].allSatisfy { $0.total == 0 || $0.correct > 0 }
        passed = overall && eachDimension
    }

    static func == (lhs: QuizEvaluation, rhs: QuizEvaluation) -> Bool {
        lhs.score == rhs.score && lhs.total == rhs.total && lhs.passed == rhs.passed && lhs.usedHints == rhs.usedHints
            && lhs.understanding == rhs.understanding && lhs.memory == rhs.memory
    }
}

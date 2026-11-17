import Foundation

/// 家长周报 (phase-2 §3.6): 理解, 记忆 and 复习 reported separately for the last seven days, never merged into one
/// "mastery" figure and never based on time spent. With too few answers a part says 记录还不够 instead of guessing.
/// Pure logic over plain values so it is tested directly.
struct WeeklyReport: Equatable {
    /// One practice round as recorded (first submissions only).
    struct Round: Equatable {
        let date: Date
        let poemID: String
        let answers: [QuizEvaluation.Answer]
        /// A due cross-day review (nil for 错题重做).
        let isReview: Bool?
        let passed: Bool
    }

    struct Ratio: Equatable {
        let correct: Int
        let total: Int
        /// Below this many answers the report does not judge.
        static let minimumSample = 5

        var isEnough: Bool { total >= Self.minimumSample }
        var fraction: Double { total == 0 ? 0 : Double(correct) / Double(total) }
    }

    enum Suggestion: Equatable {
        /// Ask the child to explain a line in their own words.
        case explain(poemID: String)
        /// Listen to the child recite, hinting only the first character.
        case recite(poemID: String)
        /// Do the due reviews one a day together.
        case review(dueCount: Int)
        /// Keep going; ask what picture the poem brings to mind.
        case keepGoing(poemID: String?)
        /// Not enough records to suggest anything specific.
        case startSmall
    }

    let from: Date
    let to: Date
    let studyDays: Int
    let rounds: Int
    let understanding: Ratio
    let memory: Ratio
    let reviewsDone: Int
    let reviewsUnaided: Int
    let dueNow: Int
    /// Missed answers by category this week, most first.
    let commonMistakes: [(category: MistakeCategory, count: Int)]
    let suggestion: Suggestion

    var hasEnoughRecords: Bool { rounds > 0 }

    init(rounds input: [Round], activeDays: Set<Date>, dueNow: Int, now: Date, calendar: Calendar = .current) {
        let end = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -6, to: end) ?? end
        from = start
        to = end
        let week = input.filter { calendar.startOfDay(for: $0.date) >= start && $0.date <= now }
        rounds = week.count
        studyDays = activeDays.filter { $0 >= start && $0 <= end }.count

        let answers = week.flatMap(\.answers)
        func ratio(_ dimension: LearningDimension) -> Ratio {
            let items = answers.filter { $0.kind.dimension == dimension }
            return Ratio(correct: items.filter(\.correct).count, total: items.count)
        }
        understanding = ratio(.understanding)
        memory = ratio(.memory)

        let reviews = week.filter { $0.isReview == true }
        reviewsDone = reviews.count
        reviewsUnaided = reviews.filter { $0.passed && !$0.answers.contains(where: \.hinted) }.count
        self.dueNow = dueNow

        var counts: [MistakeCategory: Int] = [:]
        for answer in answers where !answer.correct {
            counts[answer.kind.mistakeCategory, default: 0] += 1
        }
        commonMistakes = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.rawValue < $1.key.rawValue }
            .map { (category: $0.key, count: $0.value) }

        // The poem with the most misses in the weaker dimension anchors the suggestion.
        func weakestPoem(_ dimension: LearningDimension) -> String? {
            var misses: [String: Int] = [:]
            for round in week {
                misses[round.poemID, default: 0] += round.answers.filter { $0.kind.dimension == dimension && !$0.correct }.count
            }
            return misses.filter { $0.value > 0 }.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key
        }
        let understandingWeak = understanding.isEnough && understanding.fraction < 0.7
        let memoryWeak = memory.isEnough && memory.fraction < 0.7
        if week.isEmpty {
            suggestion = dueNow > 0 ? .review(dueCount: dueNow) : .startSmall
        } else if understandingWeak, !memoryWeak || understanding.fraction <= memory.fraction,
                  let poem = weakestPoem(.understanding) {
            suggestion = .explain(poemID: poem)
        } else if memoryWeak, let poem = weakestPoem(.memory) {
            suggestion = .recite(poemID: poem)
        } else if dueNow >= 3 {
            suggestion = .review(dueCount: dueNow)
        } else {
            suggestion = .keepGoing(poemID: week.last?.poemID)
        }
    }

    static func == (lhs: WeeklyReport, rhs: WeeklyReport) -> Bool {
        lhs.from == rhs.from && lhs.rounds == rhs.rounds && lhs.understanding == rhs.understanding && lhs.memory == rhs.memory
            && lhs.reviewsDone == rhs.reviewsDone && lhs.suggestion == rhs.suggestion
            && lhs.commonMistakes.map(\.category) == rhs.commonMistakes.map(\.category)
    }
}

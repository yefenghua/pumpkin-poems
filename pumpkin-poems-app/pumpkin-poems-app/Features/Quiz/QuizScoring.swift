import Foundation

/// Scores the complete poem's question set, ignoring unrelated IDs and counting missing answers
/// as incorrect. A partial or stale answer dictionary must never award a full-practice card.
struct QuizScoring {
    let answers: [String: Bool]
    let score: Int
    let total: Int

    var passed: Bool { Self.isPassing(score: score, total: total) }

    init(questions: [Question], answers submitted: [String: Bool]) {
        answers = Dictionary(uniqueKeysWithValues: questions.map { ($0.id, submitted[$0.id] ?? false) })
        total = questions.count
        score = answers.values.filter { $0 }.count
    }

    static func isPassing(score: Int, total: Int) -> Bool {
        total > 0 && score >= 0 && score <= total && score * 5 >= total * 4
    }
}

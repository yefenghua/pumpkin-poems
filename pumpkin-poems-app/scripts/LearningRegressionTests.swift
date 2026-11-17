import Foundation

func runLearningRegressionChecks(content: PoemContent) {
    let questions = content.poems[0].questions
    let first = questions[0]
    let partial = QuizScoring(questions: questions, answers: [first.id: true])
    check(partial.score == 1 && partial.total == questions.count && !partial.passed,
          "one correct answer cannot earn the full quiz card")
    check(partial.answers.values.filter { !$0 }.count == questions.count - 1,
          "missing answers remain visible as mistakes")

    var submitted = Dictionary(uniqueKeysWithValues: questions.map { ($0.id, true) })
    submitted["another-poem-question"] = true
    let complete = QuizScoring(questions: questions, answers: submitted)
    check(complete.score == questions.count && complete.total == questions.count && complete.passed,
          "unrelated stale answer IDs do not affect score or total")
    check(complete.answers["another-poem-question"] == nil,
          "unrelated answers cannot create mistakes for the wrong poem")
    check(!QuizScoring(questions: [], answers: [:]).passed, "empty quiz does not pass")
    check(QuizScoring.isPassing(score: 4, total: 5), "four of five passes")
    check(!QuizScoring.isPassing(score: 3, total: 5), "three of five fails")
    check(!QuizScoring.isPassing(score: 6, total: 5), "invalid score above total does not pass")

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Hong_Kong")!
    let scheduler = ReviewScheduler(calendar: calendar)
    let lateNight = calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 23, minute: 59))!
    let nextMorning = calendar.date(byAdding: .minute, value: 2, to: lateNight)!
    var state = ReviewState()
    _ = scheduler.apply(passed: true, hadMistakes: false, at: lateNight, to: &state)
    check(scheduler.isDue(state, at: nextMorning), "review uses local midnight, not 24 elapsed hours")
    _ = scheduler.apply(passed: true, hadMistakes: false, at: nextMorning, to: &state)
    let level = state.cardLevel
    let scheduled = state.nextReviewAt
    _ = scheduler.apply(passed: true, hadMistakes: false, at: nextMorning.addingTimeInterval(60), to: &state)
    check(state.cardLevel == level && state.nextReviewAt == scheduled,
          "replaying a perfect quiz in the same demo day neither farms rewards nor delays review")
    for index in 1...10 {
        let date = calendar.date(byAdding: .day, value: index, to: nextMorning)!
        _ = scheduler.apply(passed: true, hadMistakes: false, at: date, to: &state)
    }
    check(state.cardLevel == ReviewScheduler.maxCardLevel, "card level stays within displayed stars")
    let beforeFailure = state.cardLevel
    _ = scheduler.apply(passed: false, hadMistakes: true, at: nextMorning, to: &state)
    check(state.cardLevel == beforeFailure && state.firstPassedAt != nil,
          "failed review keeps the previously earned card")
}

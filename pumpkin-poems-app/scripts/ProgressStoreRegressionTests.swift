import Foundation
import SwiftData

@main
struct ProgressStoreRegressionTests {
    @MainActor
    static func main() throws {
        let contentURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let content = try JSONDecoder().decode(PoemContent.self, from: Data(contentsOf: contentURL))
        let library = PoemLibrary(content: content)
        let schema = Schema(ProgressSchema.models)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let store = ProgressStore(context: context, library: library)
        let poem = library.poems[0]
        let question = poem.questions[0]
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            checks += 1
        }

        store.markRead(poem.id)
        store.advance(poem.id, to: .reciting)
        store.advance(poem.id, to: .quizzing)
        store.advance(poem.id, to: .reading)
        check(store.existingProgress(for: poem.id)?.step == .quizzing, "quiz resume step must not move backwards")
        store.recordSelfAssessment(poem.id)
        check(store.existingProgress(for: poem.id)?.hasPassed == false, "self-assessment must not award a quiz pass")
        store.toggleFavorite(poem.id)
        check(store.existingProgress(for: poem.id)?.isFavorite == true, "favorite saved")

        let partial = store.recordQuiz(poem: poem, answers: [question.id: true])
        check(!partial.passed && partial.total == poem.questions.count, "partial submission cannot pass")
        let mistakes = try context.fetch(FetchDescriptor<Mistake>())
        check(mistakes.filter { !$0.isResolved }.count == poem.questions.count - 1, "missing answers saved as mistakes")
        let mistake = mistakes[0]
        check(!store.recordRetry(questionID: mistake.questionID, poemID: poem.id, correct: false), "wrong retry remains unresolved")
        check(store.recordRetry(questionID: mistake.questionID, poemID: poem.id, correct: true), "correct retry resolves existing mistake")
        check(!store.recordRetry(questionID: mistake.questionID, poemID: poem.id, correct: true), "resolved mistake is not counted twice")

        let allCorrect = Dictionary(uniqueKeysWithValues: poem.questions.map { ($0.id, true) })
        let passed = store.recordQuiz(poem: poem, answers: allCorrect)
        check(passed.passed && passed.event == .firstPass && passed.cardLevel == 1, "full first pass earns a card")
        let repeated = store.recordQuiz(poem: poem, answers: allCorrect)
        check(repeated.event == .repeatedSameDay && repeated.cardLevel == 1, "same-day practice preserves earned level")
        check(try context.fetch(FetchDescriptor<QuizAttempt>()).count == 3, "one attempt saved per completed round")
        let secondContext = ModelContext(container)
        let reloaded = ProgressStore(context: secondContext, library: library).existingProgress(for: poem.id)
        check(reloaded?.hasPassed == true && reloaded?.isFavorite == true, "saved progress survives a new context")

        let draft = store.saveDraft(id: nil, title: "秋夜", themeID: "autumn", wordIDs: ["月"], lines: ["月照小橋頭", "秋風送葉走"])
        let id = draft.id
        store.saveDraft(id: id, title: "月夜", themeID: "autumn", wordIDs: ["月"], lines: ["月照小橋頭", "清風吹葉走"])
        check(try context.fetch(FetchDescriptor<PoemDraft>()).count == 1 && store.draft(id)?.title == "月夜", "editing a draft updates instead of duplicating")
        store.deleteDraft(draft)
        check(store.draft(id) == nil, "draft deletion persists")
        check(store.recordGame(mode: "entry", character: "月", score: 3) == 0, "first game has no previous best")
        check(store.recordGame(mode: "entry", character: "月", score: 5) == 3, "game returns actual previous best")
        store.resetAll()
        check(try context.fetch(FetchDescriptor<PoemProgress>()).isEmpty, "reset clears poem progress")
        check(try context.fetch(FetchDescriptor<QuizAttempt>()).isEmpty, "reset clears attempts")
        check(try context.fetch(FetchDescriptor<Mistake>()).isEmpty, "reset clears mistakes")
        check(try context.fetch(FetchDescriptor<GameRecord>()).isEmpty, "reset clears game records")

        // Grade plans are views over the same records: switching scope never mutates progress.
        for stage in 1...2 {
            let plan = LearningSnapshot(progress: [], library: library, targetKeyStage: stage)
            check(plan.planTotalCount > 0 && plan.planPoems.allSatisfy { $0.keyStage == stage }, "each primary stage has a playable learning plan")
            check(plan.nextUnstarted?.keyStage == stage && plan.planPassedCount == 0 && !plan.isPlanComplete,
                  "a new plan starts with a lesson in its own stage")
        }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let primary = library.poems.filter { $0.keyStage == 1 }
        let upperPrimary = library.poems.filter { $0.keyStage == 2 }
        let reading = PoemProgress(poemID: primary[0].id)
        reading.step = .reciting; reading.readAt = now; reading.lastStudiedAt = now.addingTimeInterval(-600)
        let older = PoemProgress(poemID: primary[1].id)
        older.step = .completed; older.firstPassedAt = now.addingTimeInterval(-86_400)
        older.nextReviewAt = now.addingTimeInterval(-300)
        let withMistake = PoemProgress(poemID: primary[2].id)
        withMistake.step = .completed; withMistake.firstPassedAt = now.addingTimeInterval(-86_400)
        withMistake.nextReviewAt = now.addingTimeInterval(-100)
        let outside = PoemProgress(poemID: upperPrimary[0].id)
        outside.step = .reading; outside.lastStudiedAt = now
        outside.nextReviewAt = now.addingTimeInterval(-900)
        let stale = PoemProgress(poemID: "removed-lesson")
        stale.step = .reading; stale.lastStudiedAt = now.addingTimeInterval(10)
        let records = [reading, older, withMistake, outside, stale]
        let unresolved = Mistake(questionID: primary[2].questions[0].id, poemID: primary[2].id, at: now)
        let plan = LearningSnapshot(progress: records, library: library, targetKeyStage: 1)
        check(plan.inProgress?.poem.id == primary[0].id && plan.inProgress?.step == .reciting,
              "continue learning ignores newer out-of-grade and stale records")
        check(plan.nextUnstarted?.id == primary[3].id && plan.planPassedCount == 2 && plan.hasAnyRecord,
              "next lesson and progress counts use the selected stage")
        check(plan.dueReviews(mistakes: [unresolved], now: now).map(\.id) == [primary[2].id, primary[1].id],
              "grade review keeps mistake priority and excludes other stages")
        check(plan.recommended(excluding: primary[0].id, now: now)?.keyStage == 1,
              "recommendations stay within the chosen plan")
        let changedPlan = LearningSnapshot(progress: records, library: library, targetKeyStage: 2)
        check(changedPlan.inProgress?.poem.id == upperPrimary[0].id && changedPlan.planPassedCount == 0,
              "switching grade selects that grade's saved lesson")
        let restoredPlan = LearningSnapshot(progress: records, library: library, targetKeyStage: 1)
        check(restoredPlan.inProgress?.poem.id == primary[0].id && older.nextReviewAt == now.addingTimeInterval(-300),
              "switching back preserves both resume position and review date")
        let global = LearningSnapshot(progress: records, library: library)
        check(global.planTotalCount == library.poems.count && global.count(.passed) == 2,
              "growth book's default snapshot still sees the full library")
        let untouched = LearningSnapshot(progress: [outside], library: library, targetKeyStage: 1)
        check(!untouched.hasAnyRecord && untouched.inProgress == nil, "another stage's record does not mark this plan as started")
        let finished = primary.map { poem in
            let record = PoemProgress(poemID: poem.id)
            record.step = .completed; record.firstPassedAt = now
            return record
        }
        let complete = LearningSnapshot(progress: finished, library: library, targetKeyStage: 1)
        check(complete.isPlanComplete && complete.planPassedCount == primary.count && complete.nextUnstarted == nil,
              "completion depends on this plan rather than the entire library")
        let emptyPlan = LearningSnapshot(progress: records, library: library, targetKeyStage: 99)
        check(emptyPlan.planPoems.isEmpty && !emptyPlan.isPlanComplete && emptyPlan.inProgress == nil
              && emptyPlan.nextUnstarted == nil && emptyPlan.recommended(excluding: nil, now: now) == nil,
              "an unavailable stage is not falsely complete and never falls back to unrelated poems")
        for stage in 3...4 {
            let futurePlan = LearningSnapshot(progress: records, library: library, targetKeyStage: stage)
            check(futurePlan.planTotalCount == 0 && !futurePlan.isPlanComplete && futurePlan.nextUnstarted == nil
                  && futurePlan.dueReviews(mistakes: [unresolved], now: now).isEmpty,
                  "secondary grade interface does not mislabel primary lessons or erase existing records")
        }
        print("All \(checks) SwiftData progress checks passed.")
    }
}

import Foundation
import SwiftData

/// Result of finishing a quiz round, used by the completion page.
struct QuizOutcome {
    let score: Int
    let total: Int
    let passed: Bool
    let event: ReviewEvent
    let nextReviewAt: Date?
    let cardLevel: Int
    /// Earlier mistakes answered correctly this time (进步反馈).
    let resolvedMistakes: Int
    /// The theme whose last poem was just passed for the first time.
    let completedTheme: PoemTheme?
}

/// All writes to local learning records go through here.
struct ProgressStore {
    /// Pass when at least 80% of the questions are correct.
    static func isPassing(score: Int, total: Int) -> Bool {
        total > 0 && score * 5 >= total * 4
    }

    let context: ModelContext
    var library = PoemLibrary.shared
    var scheduler = ReviewScheduler()

    func existingProgress(for poemID: String) -> PoemProgress? {
        var descriptor = FetchDescriptor<PoemProgress>(predicate: #Predicate { $0.poemID == poemID })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func progress(for poemID: String) -> PoemProgress {
        if let existing = existingProgress(for: poemID) {
            return existing
        }
        let progress = PoemProgress(poemID: poemID)
        context.insert(progress)
        return progress
    }

    /// Moves the poem's flow forward; never moves it back.
    func advance(_ poemID: String, to step: LearningStep) {
        let progress = progress(for: poemID)
        if progress.step < step {
            progress.step = step
        }
        progress.lastStudiedAt = AppClock.now
        save()
    }

    func markRead(_ poemID: String) {
        let progress = progress(for: poemID)
        if progress.readAt == nil {
            progress.readAt = AppClock.now
        }
        if progress.step < .reading {
            progress.step = .reading
        }
        progress.lastStudiedAt = AppClock.now
        save()
    }

    func toggleFavorite(_ poemID: String) {
        let progress = progress(for: poemID)
        progress.isFavorite.toggle()
        save()
    }

    func recordSelfAssessment(_ poemID: String) {
        progress(for: poemID).selfAssessedAt = AppClock.now
        save()
    }

    /// Records a full quiz round. `answers` maps question IDs to correctness.
    func recordQuiz(poem: Poem, answers: [String: Bool]) -> QuizOutcome {
        let now = AppClock.now
        let progress = progress(for: poem.id)
        let score = answers.values.filter { $0 }.count
        let total = answers.count
        let passed = Self.isPassing(score: score, total: total)
        let wasReview = progress.lastPassedAt.map {
            scheduler.calendar.startOfDay(for: $0) < scheduler.calendar.startOfDay(for: now)
        } ?? false

        var resolved = 0
        for (questionID, correct) in answers {
            if updateMistake(questionID: questionID, poemID: poem.id, correct: correct, at: now) {
                resolved += 1
            }
        }

        var state = progress.reviewState
        let event = scheduler.apply(passed: passed, hadMistakes: score < total, at: now, to: &state)
        progress.reviewState = state
        progress.lastScore = score
        progress.lastTotal = total
        progress.lastStudiedAt = now
        if passed {
            progress.step = .completed
        } else if progress.step < .quizzing {
            progress.step = .quizzing
        }
        context.insert(QuizAttempt(poemID: poem.id, date: now, score: score, total: total,
                                   passed: passed, isReview: wasReview))

        var completedTheme: PoemTheme?
        if event == .firstPass {
            let themePoems = library.poems(inTheme: poem.theme)
            let allPassed = themePoems.allSatisfy { other in
                other.id == poem.id || (existingProgress(for: other.id)?.hasPassed ?? false)
            }
            if allPassed {
                completedTheme = library.theme(poem.theme)
            }
        }
        save()
        return QuizOutcome(score: score, total: total, passed: passed, event: event,
                           nextReviewAt: state.nextReviewAt, cardLevel: state.cardLevel,
                           resolvedMistakes: resolved, completedTheme: completedTheme)
    }

    /// Retrying one question from 错题回看. Returns true when this answer resolved a mistake.
    @discardableResult
    func recordRetry(questionID: String, poemID: String, correct: Bool) -> Bool {
        let resolved = updateMistake(questionID: questionID, poemID: poemID, correct: correct, at: AppClock.now)
        save()
        return resolved
    }

    /// Saves a 飞花令 round and returns the previous best for that mode.
    func recordGame(mode: String, character: String, score: Int) -> Int {
        let descriptor = FetchDescriptor<GameRecord>(predicate: #Predicate { $0.mode == mode })
        let previousBest = ((try? context.fetch(descriptor)) ?? []).map(\.score).max() ?? 0
        context.insert(GameRecord(mode: mode, character: character, score: score, date: AppClock.now))
        save()
        return previousBest
    }

    // MARK: 小小诗人

    func draft(_ id: UUID) -> PoemDraft? {
        var descriptor = FetchDescriptor<PoemDraft>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Creates or updates a piece in 我的诗集. Returns the stored draft.
    @discardableResult
    func saveDraft(id: UUID?, title: String, themeID: String, wordIDs: [String], lines: [String]) -> PoemDraft {
        let now = AppClock.now
        if let id, let existing = draft(id) {
            existing.title = title
            existing.themeID = themeID
            existing.wordIDs = wordIDs
            existing.lines = lines
            existing.updatedAt = now
            save()
            return existing
        }
        let created = PoemDraft(title: title, themeID: themeID, wordIDs: wordIDs, lines: lines, at: now)
        context.insert(created)
        save()
        return created
    }

    func deleteDraft(_ draft: PoemDraft) {
        context.delete(draft)
        save()
    }

    func resetAll() {
        for model in ProgressSchema.models {
            try? context.delete(model: model)
        }
        save()
    }

    #if DEBUG
    /// Fills a few records for demos (`-demoSeed YES`): some poems passed, one with a mistake, one game.
    func seedDemoData() {
        for (index, poem) in library.poems.prefix(5).enumerated() {
            markRead(poem.id)
            var answers = Dictionary(uniqueKeysWithValues: poem.questions.map { ($0.id, true) })
            if index == 1, let first = poem.questions.first {
                answers[first.id] = false
            }
            _ = recordQuiz(poem: poem, answers: answers)
        }
        if let poem = library.poems.dropFirst(5).first {
            markRead(poem.id)
            advance(poem.id, to: .reciting)
        }
        _ = recordGame(mode: FeiHuaLingMode.entry.rawValue, character: "月", score: 4)
    }
    #endif

    func save() {
        do {
            try context.save()
        } catch {
            assertionFailure("Saving progress failed: \(error)")
        }
    }

    /// Returns true when a previously wrong question is now answered correctly.
    private func updateMistake(questionID: String, poemID: String, correct: Bool, at now: Date) -> Bool {
        var descriptor = FetchDescriptor<Mistake>(predicate: #Predicate { $0.questionID == questionID })
        descriptor.fetchLimit = 1
        let existing = try? context.fetch(descriptor).first
        if correct {
            guard let existing, existing.resolvedAt == nil else { return false }
            existing.resolvedAt = now
            return true
        }
        let mistake = existing ?? {
            let created = Mistake(questionID: questionID, poemID: poemID, at: now)
            context.insert(created)
            return created
        }()
        mistake.wrongCount += 1
        mistake.lastWrongAt = now
        mistake.resolvedAt = nil
        return false
    }
}

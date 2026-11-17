import Foundation
import SwiftData

/// Result of finishing a quiz round, used by the completion page.
struct QuizOutcome {
    let evaluation: QuizEvaluation
    let event: ReviewEvent
    let nextReviewAt: Date?
    let cardLevel: Int
    /// Earlier mistakes now answered correctly on a later day without hints (移出待巩固).
    let resolvedMistakes: Int
    /// Mistakes corrected on the same day: 订正, still 待巩固.
    let correctedMistakes: Int
    /// The theme whose last poem was just passed for the first time.
    let completedTheme: PoemTheme?

    var score: Int { evaluation.score }
    var total: Int { evaluation.total }
    var passed: Bool { evaluation.passed }
}

extension Notification.Name {
    /// Posted after local learning records change, so the sync engine can upload them.
    static let learningRecordsChanged = Notification.Name("learningRecordsChanged")
}

/// All writes to learning records go through here. Each action appends a `LearningEvent` and applies it to the
/// derived models; `rebuild` replays events (for example after a sync brought in another device's events).
struct ProgressStore {
    let context: ModelContext
    var library = PoemLibrary.shared
    var scheduler = ReviewScheduler()

    // MARK: Lookups

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

    func events() -> [LearningEvent] {
        let descriptor = FetchDescriptor<LearningEvent>(sortBy: [SortDescriptor(\.at), SortDescriptor(\.id)])
        return (try? context.fetch(descriptor)) ?? []
    }

    /// The latest 每日目标; 10 minutes until the learner picks one.
    func currentGoal() -> LearningEventPayload.Goal {
        let kind = LearningEventKind.goal.rawValue
        var descriptor = FetchDescriptor<LearningEvent>(predicate: #Predicate { $0.kind == kind },
                                                        sortBy: [SortDescriptor(\.at, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor).first)?.decode(LearningEventPayload.Goal.self)
            ?? LearningEventPayload.Goal(minutes: DailyPlan.defaultMinutes, pausedOn: nil)
    }

    // MARK: Recording

    /// Moves the poem's flow forward; never moves it back.
    func advance(_ poemID: String, to step: LearningStep) {
        record(.step, poemID: poemID, LearningEventPayload.Step(step: step.rawValue))
    }

    func markRead(_ poemID: String) {
        let firstTime = existingProgress(for: poemID)?.readAt == nil
        record(.read, poemID: poemID, LearningEventPayload.Empty())
        if firstTime {
            Telemetry.shared.log("poem_learning_started", ["poemID": .string(poemID), "dueCount": .int(dueCount())])
        }
    }

    func toggleFavorite(_ poemID: String) {
        let current = existingProgress(for: poemID)?.isFavorite ?? false
        record(.favorite, poemID: poemID, LearningEventPayload.Favorite(value: !current))
    }

    func recordSelfAssessment(_ poemID: String) {
        record(.selfAssess, poemID: poemID, LearningEventPayload.Empty())
    }

    /// Records a full quiz round from first submissions only.
    func recordQuiz(poem: Poem, answers: [QuizEvaluation.Answer]) -> QuizOutcome {
        let payload = LearningEventPayload.Quiz(answers: answers, contentVersion: library.version,
                                                ruleVersion: ReviewScheduler.ruleVersion,
                                                wrong: snapshots(for: answers.filter { !$0.correct }, in: poem))
        let event = makeEvent(.quiz, poemID: poem.id, payload)
        let outcome = applyQuiz(event, payload: payload, live: true)
        save()
        if let outcome {
            let name = outcome.event.isReview ? "review_completed" : "quiz_completed"
            Telemetry.shared.log(name, ["poemID": .string(poem.id), "passed": .bool(outcome.passed),
                                        "isReview": .bool(outcome.event.isReview), "usedHints": .bool(outcome.evaluation.usedHints),
                                        "dueCount": .int(dueCount())])
        }
        return outcome ?? QuizOutcome(evaluation: QuizEvaluation(answers), event: .failed, nextReviewAt: nil,
                                      cardLevel: 0, resolvedMistakes: 0, correctedMistakes: 0, completedTheme: nil)
    }

    /// Retrying questions from 错题回看. Returns how many left 待巩固 and how many were only corrected today.
    func recordRetry(answers: [QuizEvaluation.Answer]) -> (resolved: Int, corrected: Int) {
        var resolved = 0, corrected = 0
        let byPoem = Dictionary(grouping: answers) { library.question($0.questionID)?.poem.id ?? "" }
        for (poemID, poemAnswers) in byPoem where !poemID.isEmpty {
            let poem = library.poem(poemID)
            let payload = LearningEventPayload.Quiz(answers: poemAnswers, contentVersion: library.version,
                                                    ruleVersion: ReviewScheduler.ruleVersion,
                                                    wrong: poem.map { snapshots(for: poemAnswers.filter { !$0.correct }, in: $0) } ?? [:])
            let event = makeEvent(.retry, poemID: poemID, payload)
            let result = applyAnswers(payload, poemID: poemID, at: event.at)
            resolved += result.resolved
            corrected += result.corrected
        }
        save()
        return (resolved, corrected)
    }

    /// Saves a 飞花令 round and returns the previous best for that mode.
    func recordGame(mode: String, character: String, score: Int) -> Int {
        let descriptor = FetchDescriptor<GameRecord>(predicate: #Predicate { $0.mode == mode })
        let previousBest = ((try? context.fetch(descriptor)) ?? []).map(\.score).max() ?? 0
        record(.game, poemID: nil, LearningEventPayload.Game(mode: mode, character: character, score: score))
        return previousBest
    }

    func setGoal(minutes: Int, pausedToday: Bool) {
        let today = Calendar.current.startOfDay(for: AppClock.now)
        record(.goal, poemID: nil, LearningEventPayload.Goal(minutes: minutes, pausedOn: pausedToday ? today : nil))
    }

    func recordSceneMatch(roundID: String, poemID: String, pictureCorrect: Bool, evidenceCorrect: Bool) {
        record(.sceneMatch, poemID: poemID, LearningEventPayload.SceneMatch(roundID: roundID, pictureCorrect: pictureCorrect,
                                                                         evidenceCorrect: evidenceCorrect))
    }

    // MARK: Applying events

    /// Replays events into the derived models. `poemIDs == nil` rebuilds everything, including 飞花令 records.
    func rebuild(poemIDs: Set<String>? = nil) {
        let all = events()
        if let poemIDs {
            for progress in (try? context.fetch(FetchDescriptor<PoemProgress>())) ?? [] where poemIDs.contains(progress.poemID) {
                context.delete(progress)
            }
            for attempt in (try? context.fetch(FetchDescriptor<QuizAttempt>())) ?? [] where poemIDs.contains(attempt.poemID) {
                context.delete(attempt)
            }
            for mistake in (try? context.fetch(FetchDescriptor<Mistake>())) ?? [] where poemIDs.contains(mistake.poemID) {
                context.delete(mistake)
            }
        } else {
            try? context.delete(model: PoemProgress.self)
            try? context.delete(model: QuizAttempt.self)
            try? context.delete(model: Mistake.self)
            try? context.delete(model: GameRecord.self)
        }
        // Deletions must land before re-inserting rows with the same unique keys.
        try? context.save()
        for event in all {
            if let poemIDs {
                guard let poemID = event.poemID, poemIDs.contains(poemID) else { continue }
            }
            apply(event)
        }
        save(notify: false)
    }

    /// Applies one event that is already in the store (used by replay and by sync for new remote events).
    func apply(_ event: LearningEvent) {
        guard let kind = event.eventKind else { return }
        let at = event.at
        switch kind {
        case .read:
            guard let poemID = event.poemID else { return }
            let progress = progress(for: poemID)
            if progress.readAt == nil { progress.readAt = at }
            if progress.step < .reading { progress.step = .reading }
            touch(progress, at)
        case .step:
            guard let poemID = event.poemID, let payload = event.decode(LearningEventPayload.Step.self),
                  let step = LearningStep(rawValue: payload.step) else { return }
            let progress = progress(for: poemID)
            if progress.step < step { progress.step = step }
            touch(progress, at)
        case .selfAssess:
            guard let poemID = event.poemID else { return }
            progress(for: poemID).selfAssessedAt = at
        case .favorite:
            guard let poemID = event.poemID, let payload = event.decode(LearningEventPayload.Favorite.self) else { return }
            progress(for: poemID).isFavorite = payload.value
        case .quiz:
            guard let payload = event.decode(LearningEventPayload.Quiz.self) else { return }
            _ = applyQuiz(event, payload: payload, live: false)
        case .retry:
            guard let poemID = event.poemID, let payload = event.decode(LearningEventPayload.Quiz.self) else { return }
            _ = applyAnswers(payload, poemID: poemID, at: at)
        case .game:
            guard let payload = event.decode(LearningEventPayload.Game.self) else { return }
            let eventID = event.id
            let existing = (try? context.fetchCount(FetchDescriptor<GameRecord>(predicate: #Predicate { $0.eventID == eventID }))) ?? 0
            guard existing == 0 else { return }
            let record = GameRecord(mode: payload.mode, character: payload.character, score: payload.score, date: at)
            record.eventID = event.id
            context.insert(record)
        case .legacySnapshot:
            guard let poemID = event.poemID, let payload = event.decode(LearningEventPayload.Legacy.self) else { return }
            applyLegacy(payload, poemID: poemID)
        case .goal, .sceneMatch:
            // Read straight from the event log (每日目标, 诗境配对 history); nothing derived.
            break
        }
    }

    @discardableResult
    private func applyQuiz(_ event: LearningEvent, payload: LearningEventPayload.Quiz, live: Bool) -> QuizOutcome? {
        guard let poemID = event.poemID else { return nil }
        let at = event.at
        let progress = progress(for: poemID)
        let evaluation = QuizEvaluation(payload.answers)
        let mistakeResult = applyAnswers(payload, poemID: poemID, at: at)
        let wasPassed = progress.hasPassed

        var state = progress.reviewState
        let reviewEvent = scheduler.apply(QuizResult(passed: evaluation.passed, usedHints: evaluation.usedHints), at: at, to: &state)
        progress.reviewState = state
        progress.lastScore = evaluation.score
        progress.lastTotal = evaluation.total
        progress.lastUsedHints = evaluation.usedHints
        touch(progress, at)
        if evaluation.passed {
            progress.step = .completed
        } else if progress.step < .quizzing {
            progress.step = .quizzing
        }

        let attempt = QuizAttempt(poemID: poemID, date: at, score: evaluation.score, total: evaluation.total,
                                  passed: evaluation.passed, isReview: reviewEvent.isReview)
        attempt.understandingCorrect = evaluation.understanding.correct
        attempt.understandingTotal = evaluation.understanding.total
        attempt.memoryCorrect = evaluation.memory.correct
        attempt.memoryTotal = evaluation.memory.total
        attempt.usedHints = evaluation.usedHints
        attempt.outcome = reviewEvent.rawValue
        attempt.contentVersion = payload.contentVersion
        attempt.eventID = event.id
        context.insert(attempt)

        var completedTheme: PoemTheme?
        if live, !wasPassed, reviewEvent == .firstPass, let poem = library.poem(poemID) {
            let allPassed = library.poems(inTheme: poem.theme).allSatisfy { other in
                other.id == poemID || (existingProgress(for: other.id)?.hasPassed ?? false)
            }
            if allPassed { completedTheme = library.theme(poem.theme) }
        }
        return QuizOutcome(evaluation: evaluation, event: reviewEvent, nextReviewAt: state.nextReviewAt,
                           cardLevel: state.cardLevel, resolvedMistakes: mistakeResult.resolved,
                           correctedMistakes: mistakeResult.corrected, completedTheme: completedTheme)
    }

    private func applyAnswers(_ payload: LearningEventPayload.Quiz, poemID: String, at: Date) -> (resolved: Int, corrected: Int) {
        var resolved = 0, corrected = 0
        for answer in payload.answers {
            switch updateMistake(answer, poemID: poemID, at: at, snapshot: payload.wrong[answer.questionID]) {
            case .resolved: resolved += 1
            case .corrected: corrected += 1
            case .none: break
            }
        }
        return (resolved, corrected)
    }

    private enum MistakeChange { case resolved, corrected }

    private func updateMistake(_ answer: QuizEvaluation.Answer, poemID: String, at: Date,
                               snapshot: LearningEventPayload.QuestionSnapshot?) -> MistakeChange? {
        let questionID = answer.questionID
        var descriptor = FetchDescriptor<Mistake>(predicate: #Predicate { $0.questionID == questionID })
        descriptor.fetchLimit = 1
        let existing = try? context.fetch(descriptor).first
        let calendar = scheduler.calendar
        if answer.correct {
            guard let existing, existing.resolvedAt == nil else { return nil }
            if !answer.hinted, calendar.startOfDay(for: at) > calendar.startOfDay(for: existing.lastWrongAt) {
                existing.resolvedAt = at
                return .resolved
            }
            existing.correctedAt = at
            return .corrected
        }
        let mistake = existing ?? {
            let created = Mistake(questionID: questionID, poemID: poemID, at: at)
            context.insert(created)
            return created
        }()
        mistake.wrongCount += 1
        mistake.lastWrongAt = at
        mistake.resolvedAt = nil
        mistake.correctedAt = nil
        mistake.category = answer.kind.mistakeCategory.rawValue
        if let snapshot {
            mistake.questionRev = snapshot.rev
            mistake.snapshot = try? APIClient.encoder.encode(snapshot)
        }
        return nil
    }

    private func applyLegacy(_ payload: LearningEventPayload.Legacy, poemID: String) {
        let progress = progress(for: poemID)
        progress.step = LearningStep(rawValue: payload.step) ?? .notStarted
        progress.lastStudiedAt = payload.lastStudiedAt
        progress.readAt = payload.readAt
        progress.selfAssessedAt = payload.selfAssessedAt
        progress.isFavorite = payload.isFavorite
        progress.reviewState = payload.review
        progress.lastScore = payload.lastScore
        progress.lastTotal = payload.lastTotal
        for item in payload.mistakes {
            let mistake = Mistake(questionID: item.questionID, poemID: poemID, at: item.lastWrongAt)
            mistake.wrongCount = item.wrongCount
            mistake.resolvedAt = item.resolvedAt
            mistake.category = library.question(item.questionID)?.question.mistakeCategory.rawValue ?? ""
            context.insert(mistake)
        }
        for item in payload.attempts {
            context.insert(QuizAttempt(poemID: poemID, date: item.date, score: item.score, total: item.total,
                                       passed: item.passed, isReview: item.isReview))
        }
    }

    private func touch(_ progress: PoemProgress, _ at: Date) {
        if (progress.lastStudiedAt ?? .distantPast) < at { progress.lastStudiedAt = at }
    }

    // MARK: Migration

    /// Phase-1 installs have derived records but no event log. Converts each poem's record (and 飞花令 rounds)
    /// into events once, then replays them, so nothing earned before the upgrade is lost or reset.
    func migrateLegacyRecordsIfNeeded() {
        guard ((try? context.fetchCount(FetchDescriptor<LearningEvent>())) ?? 0) == 0 else { return }
        let progresses = (try? context.fetch(FetchDescriptor<PoemProgress>())) ?? []
        let games = (try? context.fetch(FetchDescriptor<GameRecord>())) ?? []
        guard !progresses.isEmpty || !games.isEmpty else { return }
        let mistakes = (try? context.fetch(FetchDescriptor<Mistake>())) ?? []
        let attempts = (try? context.fetch(FetchDescriptor<QuizAttempt>())) ?? []
        let calendar = scheduler.calendar

        for progress in progresses {
            let poemAttempts = attempts.filter { $0.poemID == progress.poemID }
            var review = progress.reviewState
            review.unaidedReviewDays = Array(Set(poemAttempts.filter { $0.isReview && $0.passed }
                .map { calendar.startOfDay(for: $0.date) })).sorted()
            let payload = LearningEventPayload.Legacy(
                step: progress.stepRaw, lastStudiedAt: progress.lastStudiedAt, readAt: progress.readAt,
                selfAssessedAt: progress.selfAssessedAt, isFavorite: progress.isFavorite, review: review,
                lastScore: progress.lastScore, lastTotal: progress.lastTotal,
                mistakes: mistakes.filter { $0.poemID == progress.poemID }.map {
                    .init(questionID: $0.questionID, wrongCount: $0.wrongCount, lastWrongAt: $0.lastWrongAt, resolvedAt: $0.resolvedAt)
                },
                attempts: poemAttempts.map {
                    .init(date: $0.date, score: $0.score, total: $0.total, passed: $0.passed, isReview: $0.isReview)
                })
            let at = [progress.lastStudiedAt, progress.readAt, progress.firstPassedAt].compactMap { $0 }.min() ?? AppClock.now
            _ = makeEvent(.legacySnapshot, poemID: progress.poemID, payload, at: at)
        }
        for game in games {
            _ = makeEvent(.game, poemID: nil, LearningEventPayload.Game(mode: game.mode, character: game.character, score: game.score),
                          at: game.date)
        }
        try? context.save()
        rebuild()
    }

    // MARK: 小小诗人

    func draft(_ id: UUID) -> PoemDraft? {
        var descriptor = FetchDescriptor<PoemDraft>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Creates or updates a piece. Autosave passes `.draft`; 收进我的诗集 passes `.finished`.
    @discardableResult
    func saveDraft(id: UUID?, title: String, themeID: String, wordIDs: [String], lines: [String], mode: WritingMode,
                   form: Int, exampleLineID: String?, status: DraftStatus) -> PoemDraft {
        let now = AppClock.now
        let draft: PoemDraft
        if let id, let existing = self.draft(id) {
            draft = existing
            draft.title = title
            draft.themeID = themeID
            draft.wordIDs = wordIDs
            draft.lines = lines
            draft.updatedAt = now
        } else {
            draft = PoemDraft(title: title, themeID: themeID, wordIDs: wordIDs, lines: lines, at: now)
            context.insert(draft)
        }
        let wasFinished = draft.draftStatus == .finished && id != nil
        draft.mode = mode.rawValue
        draft.form = form
        draft.exampleLineID = exampleLineID
        draft.status = status.rawValue
        draft.pendingDeletion = false
        draft.isDirty = true
        save()
        if status == .finished, !wasFinished {
            Telemetry.shared.log("creation_saved", ["mode": .string(mode.rawValue), "lineCount": .int(lines.count)])
        }
        return draft
    }

    @discardableResult
    func copyDraft(_ draft: PoemDraft, suffix: String) -> PoemDraft {
        let copy = PoemDraft(title: draft.title + suffix, themeID: draft.themeID, wordIDs: draft.wordIDs,
                             lines: draft.lines, at: AppClock.now)
        copy.mode = draft.mode
        copy.form = draft.form
        copy.exampleLineID = draft.exampleLineID
        copy.status = draft.status
        context.insert(copy)
        save()
        return copy
    }

    /// Hides the piece at once; `undoDelete` brings it back until `purgeDeletedDrafts` runs.
    func deleteDraft(_ draft: PoemDraft) {
        draft.pendingDeletion = true
        draft.isDirty = true
        draft.updatedAt = AppClock.now
        save()
    }

    func undoDelete(_ draft: PoemDraft) {
        draft.pendingDeletion = false
        save()
    }

    /// Removes deleted pieces that never reached the server; uploaded ones stay as tombstones until synced.
    func purgeDeletedDrafts() {
        let drafts = (try? context.fetch(FetchDescriptor<PoemDraft>(predicate: #Predicate { $0.pendingDeletion }))) ?? []
        for draft in drafts where draft.serverRevision == 0 {
            context.delete(draft)
        }
        save(notify: false)
    }

    func resetAll() {
        for model in ProgressSchema.models {
            try? context.delete(model: model)
        }
        save(notify: false)
    }

    #if DEBUG
    /// Fills a few records for demos (`-demoSeed YES`): some poems passed, one with a mistake, one game.
    func seedDemoData() {
        for (index, poem) in library.poems.prefix(5).enumerated() {
            markRead(poem.id)
            let answers = poem.questions.enumerated().map { offset, question in
                QuizEvaluation.Answer(questionID: question.id, kind: question.kind,
                                      correct: !(index == 1 && offset == 0), hinted: false)
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

    func save(notify: Bool = true) {
        do {
            try context.save()
        } catch {
            assertionFailure("Saving progress failed: \(error)")
        }
        if notify {
            NotificationCenter.default.post(name: .learningRecordsChanged, object: nil)
        }
    }

    // MARK: Private

    @discardableResult
    private func record<Payload: Encodable>(_ kind: LearningEventKind, poemID: String?, _ payload: Payload) -> LearningEvent {
        let event = makeEvent(kind, poemID: poemID, payload)
        apply(event)
        save()
        return event
    }

    private func makeEvent<Payload: Encodable>(_ kind: LearningEventKind, poemID: String?, _ payload: Payload,
                                               at: Date = AppClock.now) -> LearningEvent {
        let data = (try? APIClient.encoder.encode(payload)) ?? Data("{}".utf8)
        let event = LearningEvent(kind: kind, poemID: poemID, at: at, payload: data)
        context.insert(event)
        return event
    }

    private func snapshots(for answers: [QuizEvaluation.Answer], in poem: Poem) -> [String: LearningEventPayload.QuestionSnapshot] {
        var result: [String: LearningEventPayload.QuestionSnapshot] = [:]
        for answer in answers {
            guard let question = poem.question(answer.questionID) else { continue }
            let correct = question.answer.flatMap { question.options.indices.contains($0) ? question.options[$0] : nil }
            result[question.id] = .init(rev: question.rev, prompt: question.prompt, answer: correct, explanation: question.explanation)
        }
        return result
    }

    private func dueCount() -> Int {
        let now = AppClock.now
        let progresses = (try? context.fetch(FetchDescriptor<PoemProgress>())) ?? []
        return progresses.filter { $0.nextReviewAt.map { $0 <= now } ?? false }.count
    }
}

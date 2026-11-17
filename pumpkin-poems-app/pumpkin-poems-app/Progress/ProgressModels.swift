import Foundation
import SwiftData

/// Where the learner is inside one poem's flow, used by "继续学习".
enum LearningStep: Int, Codable, Comparable {
    case notStarted = 0
    case reading
    case reciting
    case quizzing
    case completed

    static func < (lhs: LearningStep, rhs: LearningStep) -> Bool { lhs.rawValue < rhs.rawValue }
}

// MARK: - Event log (source of truth)

/// One immutable learning event. Everything else in this file except `PoemDraft` is derived from these by
/// `ProgressStore.apply`, so a profile can be rebuilt on any device by replaying its events in order.
/// IDs are stable UUIDs: uploading the same event twice never counts twice.
@Model
final class LearningEvent {
    @Attribute(.unique) var id: String
    var kind: String
    var poemID: String?
    var at: Date
    var deviceID: String
    /// JSON body; see `LearningEventPayload`.
    var payload: Data
    /// Uploaded to the account (always false for guests).
    var isSynced = false

    init(id: String = UUID().uuidString.lowercased(), kind: LearningEventKind, poemID: String?, at: Date,
         deviceID: String = ServerConfig.deviceID, payload: Data) {
        self.id = id
        self.kind = kind.rawValue
        self.poemID = poemID
        self.at = at
        self.deviceID = deviceID
        self.payload = payload
    }

    var eventKind: LearningEventKind? { LearningEventKind(rawValue: kind) }

    func decode<Payload: Decodable>(_ type: Payload.Type) -> Payload? {
        try? APIClient.decoder.decode(type, from: payload)
    }
}

enum LearningEventKind: String, Codable {
    /// Phase-1 records converted once on upgrade.
    case legacySnapshot
    case read, step, selfAssess, favorite, quiz, retry, game, goal, sceneMatch
}

enum LearningEventPayload {
    struct Empty: Codable {}

    struct Step: Codable {
        let step: Int
    }

    struct Favorite: Codable {
        let value: Bool
    }

    /// What the learner saw when a question was missed, so 错题回看 can show that version after a revision.
    struct QuestionSnapshot: Codable, Hashable {
        let rev: String
        let prompt: LocalizedText
        let answer: LocalizedText?
        let explanation: LocalizedText
    }

    struct Quiz: Codable {
        let answers: [QuizEvaluation.Answer]
        let contentVersion: String
        let ruleVersion: Int
        let wrong: [String: QuestionSnapshot]
    }

    struct Game: Codable {
        let mode: String
        let character: String
        let score: Int
    }

    /// 每日目标. `pausedOn` is a start-of-day: the plan rests that day.
    struct Goal: Codable {
        let minutes: Int
        let pausedOn: Date?
    }

    struct SceneMatch: Codable {
        let roundID: String
        let pictureCorrect: Bool
        let evidenceCorrect: Bool
    }

    struct Legacy: Codable {
        struct LegacyMistake: Codable {
            let questionID: String
            let wrongCount: Int
            let lastWrongAt: Date
            let resolvedAt: Date?
        }
        struct LegacyAttempt: Codable {
            let date: Date
            let score: Int
            let total: Int
            let passed: Bool
            let isReview: Bool
        }
        let step: Int
        let lastStudiedAt: Date?
        let readAt: Date?
        let selfAssessedAt: Date?
        let isFavorite: Bool
        let review: ReviewState
        let lastScore: Int
        let lastTotal: Int
        let mistakes: [LegacyMistake]
        let attempts: [LegacyAttempt]
    }
}

// MARK: - Derived state

/// Learning record for one poem. Keyed by the stable `poemID` shared by both scripts.
@Model
final class PoemProgress {
    @Attribute(.unique) var poemID: String
    var stepRaw: Int = LearningStep.notStarted.rawValue
    var lastStudiedAt: Date?
    /// 已读过: finished reading or listening.
    var readAt: Date?
    /// "我记住了" self-assessment, recorded separately from practice results.
    var selfAssessedAt: Date?
    var isFavorite = false

    var firstPassedAt: Date?
    var lastPassedAt: Date?
    var reviewStep = 0
    var nextReviewAt: Date?
    /// 记忆较稳.
    var stableAt: Date?
    var cardLevel = 0
    var lastScore = 0
    var lastTotal = 0
    /// Start-of-day dates of due reviews passed without hints.
    var unaidedReviewDays: [Date] = []
    /// The last round leaned on hints (有提示完成); suggested for another look.
    var lastUsedHints = false

    init(poemID: String) {
        self.poemID = poemID
    }

    var step: LearningStep {
        get { LearningStep(rawValue: stepRaw) ?? .notStarted }
        set { stepRaw = newValue.rawValue }
    }

    var reviewState: ReviewState {
        get {
            ReviewState(firstPassedAt: firstPassedAt, lastPassedAt: lastPassedAt, reviewStep: reviewStep,
                        nextReviewAt: nextReviewAt, stableAt: stableAt, cardLevel: cardLevel,
                        unaidedReviewDays: unaidedReviewDays)
        }
        set {
            firstPassedAt = newValue.firstPassedAt
            lastPassedAt = newValue.lastPassedAt
            reviewStep = newValue.reviewStep
            nextReviewAt = newValue.nextReviewAt
            stableAt = newValue.stableAt
            cardLevel = newValue.cardLevel
            unaidedReviewDays = newValue.unaidedReviewDays
        }
    }

    var hasRead: Bool { readAt != nil }
    var hasPassed: Bool { firstPassedAt != nil }
    var isStable: Bool { stableAt != nil }
}

/// One completed quiz round, with the 理解／记忆 split.
@Model
final class QuizAttempt {
    var poemID: String
    var date: Date
    var score: Int
    var total: Int
    var passed: Bool
    /// A due cross-day review.
    var isReview: Bool
    var understandingCorrect = 0
    var understandingTotal = 0
    var memoryCorrect = 0
    var memoryTotal = 0
    var usedHints = false
    /// `ReviewEvent.rawValue`
    var outcome = ""
    var contentVersion = ""
    var eventID = ""

    init(poemID: String, date: Date, score: Int, total: Int, passed: Bool, isReview: Bool) {
        self.poemID = poemID
        self.date = date
        self.score = score
        self.total = total
        self.passed = passed
        self.isReview = isReview
    }
}

/// A question answered wrongly. It stays 待巩固 until answered correctly without a hint on a later day;
/// a correct retry on the same day only counts as 订正.
@Model
final class Mistake {
    @Attribute(.unique) var questionID: String
    var poemID: String
    var wrongCount = 0
    var lastWrongAt: Date
    /// Moved out of 待巩固: correct, unaided, on a later day than the last mistake.
    var resolvedAt: Date?
    /// Corrected on the same day as the mistake (订正); still waiting for a later day.
    var correctedAt: Date?
    /// `MistakeCategory.rawValue`
    var category = ""
    /// The question version that was missed, and what it said then.
    var questionRev = ""
    var snapshot: Data?

    init(questionID: String, poemID: String, at date: Date) {
        self.questionID = questionID
        self.poemID = poemID
        self.lastWrongAt = date
    }

    var isResolved: Bool { resolvedAt != nil }
    var isCorrected: Bool { !isResolved && correctedAt != nil }

    var questionSnapshot: LearningEventPayload.QuestionSnapshot? {
        snapshot.flatMap { try? APIClient.decoder.decode(LearningEventPayload.QuestionSnapshot.self, from: $0) }
    }
}

/// One finished 飞花令 round.
@Model
final class GameRecord {
    /// `FeiHuaLingMode.rawValue`
    var mode: String
    /// The target character in Simplified form.
    var character: String
    var score: Int
    var date: Date
    var eventID = ""

    init(mode: String, character: String, score: Int, date: Date) {
        self.mode = mode
        self.character = character
        self.score = score
        self.date = date
    }
}

/// One piece written in 小小诗人 and kept in 我的诗集. Never scored. Synced as a revisioned record, not as events:
/// concurrent edits keep both versions (冲突副本) and deletions travel as tombstones.
@Model
final class PoemDraft {
    @Attribute(.unique) var id: UUID
    var title: String
    /// `PoetWorkshopTheme.id`
    var themeID: String
    /// Chosen imagery words, Simplified keys (`ImageryWord.id`).
    var wordIDs: [String]
    /// The written lines, in order, exactly as typed (switching 繁简 never rewrites them).
    var lines: [String]
    var createdAt: Date
    var updatedAt: Date
    /// `WritingMode.rawValue`: 仿写 or 自由写.
    var mode = WritingMode.free.rawValue
    /// Chosen line length: 5, 7, or 0 for any.
    var form = 0
    /// `DraftStatus.rawValue`. Phase-1 pieces were all finished.
    var status = DraftStatus.finished.rawValue
    /// The library line shown as the example when imitating.
    var exampleLineID: String?
    /// Set on a 冲突副本: the piece it was split from.
    var conflictOf: UUID?
    /// Server revision last seen; 0 = never uploaded.
    var serverRevision = 0
    /// Changed locally since the last upload.
    var isDirty = true
    /// Deleted, waiting to upload the tombstone. Hidden everywhere.
    var pendingDeletion = false

    init(title: String, themeID: String, wordIDs: [String], lines: [String], at date: Date) {
        id = UUID()
        self.title = title
        self.themeID = themeID
        self.wordIDs = wordIDs
        self.lines = lines
        createdAt = date
        updatedAt = date
    }

    var draftStatus: DraftStatus { DraftStatus(rawValue: status) ?? .finished }
    var writingMode: WritingMode { WritingMode(rawValue: mode) ?? .free }
}

enum WritingMode: String, Codable, CaseIterable {
    /// 仿写: borrow the shape of an example line.
    case imitate
    /// 自由写
    case free
}

enum DraftStatus: String, Codable {
    /// Autosaved while writing; resumes after leaving or restarting.
    case draft
    case finished
}

enum ProgressSchema {
    static let models: [any PersistentModel.Type] = [
        PoemProgress.self, QuizAttempt.self, Mistake.self, GameRecord.self, PoemDraft.self, LearningEvent.self,
    ]
}

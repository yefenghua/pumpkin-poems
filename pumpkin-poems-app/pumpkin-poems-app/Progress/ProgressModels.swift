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
    /// 记忆较稳: passed again on a later day.
    var stableAt: Date?
    var cardLevel = 0
    var lastScore = 0
    var lastTotal = 0

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
                        nextReviewAt: nextReviewAt, stableAt: stableAt, cardLevel: cardLevel)
        }
        set {
            firstPassedAt = newValue.firstPassedAt
            lastPassedAt = newValue.lastPassedAt
            reviewStep = newValue.reviewStep
            nextReviewAt = newValue.nextReviewAt
            stableAt = newValue.stableAt
            cardLevel = newValue.cardLevel
        }
    }

    var hasRead: Bool { readAt != nil }
    var hasPassed: Bool { firstPassedAt != nil }
    var isStable: Bool { stableAt != nil }
}

/// One completed quiz round.
@Model
final class QuizAttempt {
    var poemID: String
    var date: Date
    var score: Int
    var total: Int
    var passed: Bool
    /// Taken on a later day than the first pass.
    var isReview: Bool

    init(poemID: String, date: Date, score: Int, total: Int, passed: Bool, isReview: Bool) {
        self.poemID = poemID
        self.date = date
        self.score = score
        self.total = total
        self.passed = passed
        self.isReview = isReview
    }
}

/// A question answered wrongly, kept for 错题回看 until answered correctly.
@Model
final class Mistake {
    @Attribute(.unique) var questionID: String
    var poemID: String
    var wrongCount = 0
    var lastWrongAt: Date
    var resolvedAt: Date?

    init(questionID: String, poemID: String, at date: Date) {
        self.questionID = questionID
        self.poemID = poemID
        self.lastWrongAt = date
    }

    var isResolved: Bool { resolvedAt != nil }
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

    init(mode: String, character: String, score: Int, date: Date) {
        self.mode = mode
        self.character = character
        self.score = score
        self.date = date
    }
}

/// One piece written in 小小诗人 and kept in 我的诗集 (P2). Stored locally only; never scored.
@Model
final class PoemDraft {
    @Attribute(.unique) var id: UUID
    var title: String
    /// `PoetWorkshopTheme.id`
    var themeID: String
    /// Chosen imagery words, Simplified keys (`ImageryWord.id`).
    var wordIDs: [String]
    /// The written lines, in order, as typed.
    var lines: [String]
    var createdAt: Date
    var updatedAt: Date

    init(title: String, themeID: String, wordIDs: [String], lines: [String], at date: Date) {
        id = UUID()
        self.title = title
        self.themeID = themeID
        self.wordIDs = wordIDs
        self.lines = lines
        createdAt = date
        updatedAt = date
    }
}

enum ProgressSchema {
    static let models: [any PersistentModel.Type] = [PoemProgress.self, QuizAttempt.self, Mistake.self, GameRecord.self, PoemDraft.self]
}

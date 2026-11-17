import Foundation

/// Text script. Traditional and Simplified share every content ID, so switching never touches progress.
enum Script: String, CaseIterable, Identifiable, Codable {
    case hant = "zh-Hant"
    case hans = "zh-Hans"

    var id: String { rawValue }
}

/// A piece of text available in both scripts.
struct LocalizedText: Decodable, Hashable {
    let hant: String
    let hans: String

    enum CodingKeys: String, CodingKey {
        case hant = "zh-Hant"
        case hans = "zh-Hans"
    }

    init(hant: String, hans: String) {
        self.hant = hant
        self.hans = hans
    }

    func callAsFunction(_ script: Script) -> String {
        script == .hant ? hant : hans
    }
}

/// Values stored per script, e.g. annotation positions.
struct PerScript<Value: Decodable & Hashable>: Decodable, Hashable {
    let hant: Value
    let hans: Value

    enum CodingKeys: String, CodingKey {
        case hant = "zh-Hant"
        case hans = "zh-Hans"
    }

    func callAsFunction(_ script: Script) -> Value {
        script == .hant ? hant : hans
    }
}

struct PoemTheme: Decodable, Identifiable, Hashable {
    let id: String
    let name: LocalizedText
    let badge: LocalizedText
    let summary: LocalizedText
}

/// Illustration used for a poem's header. Each scene must agree with the poem's meaning
/// (e.g. the moon night has no frost on the ground).
enum SceneKind: String, Decodable {
    case moonNight, riverMountain, spring, summer, autumn, winter
}

struct Poem: Decodable, Identifiable, Hashable {
    let id: String
    let theme: String
    let scene: SceneKind
    /// Content pack the poem ships in; `base` is bundled with the app.
    let pack: String
    let keyStage: Int
    /// 1 easy … 3 harder.
    let difficulty: Int
    /// Key imagery words, each literally in the poem.
    let imagery: [LocalizedText]
    let sources: [ContentSource]
    let title: LocalizedText
    let dynasty: LocalizedText
    let genre: LocalizedText
    let author: PoemAuthor
    let tagline: LocalizedText
    let understanding: Understanding
    let lines: [PoemLine]
    let annotations: [Annotation]
    let questions: [Question]

    static func == (lhs: Poem, rhs: Poem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    func line(_ id: String) -> PoemLine? { lines.first { $0.id == id } }
    func question(_ id: String) -> Question? { questions.first { $0.id == id } }

    /// A copy without the given (withdrawn) questions.
    func removingQuestions(_ ids: Set<String>) -> Poem {
        guard questions.contains(where: { ids.contains($0.id) }) else { return self }
        return Poem(id: id, theme: theme, scene: scene, pack: pack, keyStage: keyStage, difficulty: difficulty,
                    imagery: imagery, sources: sources, title: title, dynasty: dynasty, genre: genre, author: author,
                    tagline: tagline, understanding: understanding, lines: lines, annotations: annotations,
                    questions: questions.filter { !ids.contains($0.id) })
    }
}

struct ContentSource: Decodable, Hashable {
    let label: LocalizedText
    let url: String
}

struct PoemAuthor: Decodable, Hashable {
    let id: String
    let name: LocalizedText
    let bio: LocalizedText
}

struct Understanding: Decodable, Hashable {
    let scene: LocalizedText
    let feeling: LocalizedText
    let background: LocalizedText
}

struct PoemLine: Decodable, Identifiable, Hashable {
    let id: String
    let text: LocalizedText
    /// Code-point range [start, end) of the recitation keyword; identical in both scripts.
    let keyword: [Int]
    /// 读懂这句: shown by default.
    let explain: LocalizedText
    /// 再想一想: imagery, feeling or technique, expanded on demand.
    let think: LocalizedText?
}

struct Annotation: Decodable, Identifiable, Hashable {
    let id: String
    let term: LocalizedText
    let definition: LocalizedText
    let occurrences: PerScript<[AnnotationSpot]>
}

/// Position inside a line, as a 0-based code-point range [start, end).
/// Swift `Character` offsets match because poem lines contain no combining sequences.
struct AnnotationSpot: Decodable, Hashable {
    let lineID: String
    let start: Int
    let end: Int
}

struct Question: Decodable, Identifiable, Hashable {
    enum Kind: String, Codable {
        /// 诗意理解
        case meaning
        /// 字词理解
        case word
        /// 诗意配对
        case match
        /// 关键词填空
        case fill
        /// 上下句补全
        case next
        /// 诗句排序
        case order
    }

    let id: String
    let kind: Kind
    let prompt: LocalizedText
    /// The line with a blank, for fill-in questions.
    let context: LocalizedText?
    let options: [LocalizedText]
    /// Correct option index for single-choice questions.
    let answer: Int?
    /// Option indices in the poem's order, for ordering questions.
    let answerOrder: [Int]?
    let explanation: LocalizedText
    /// The lines this question is about, shown first in 错题回看.
    let lineIDs: [String]
    /// Content hash; changes whenever the question is revised.
    let rev: String

    var dimension: LearningDimension { kind.dimension }
    var mistakeCategory: MistakeCategory { kind.mistakeCategory }
}

/// The two halves of a practice round. A pass needs at least one correct answer in each.
enum LearningDimension: String, Codable, CaseIterable {
    /// 理解
    case understanding
    /// 记忆
    case memory
}

/// Why a question was missed, for 错题回看 (phase-2 §3.3).
enum MistakeCategory: String, Codable, CaseIterable {
    /// 字词不理解
    case word
    /// 诗意判断
    case meaning
    /// 顺序记忆
    case order
    /// 诗句补全
    case completion
}

extension Question.Kind {
    var dimension: LearningDimension {
        switch self {
        case .meaning, .word, .match: .understanding
        case .fill, .next, .order: .memory
        }
    }

    var mistakeCategory: MistakeCategory {
        switch self {
        case .word: .word
        case .meaning, .match: .meaning
        case .order: .order
        case .fill, .next: .completion
        }
    }
}

/// One content pack file: the bundled `base` pack or a downloaded theme pack (formatVersion 2).
struct PoemContent: Decodable {
    let formatVersion: Int?
    let packID: String?
    let version: String
    let themes: [PoemTheme]
    let feiHuaLing: [LocalizedText]
    let poems: [Poem]
    let hantToHans: [String: String]
    let sceneMatch: SceneMatchContent?
}

// MARK: - 诗境配对

/// Pick the picture that fits the lines, then the words in the lines that prove it.
struct SceneMatchContent: Decodable, Hashable {
    struct Picture: Decodable, Hashable, Identifiable {
        let id: String
        let describe: LocalizedText
    }

    struct Evidence: Decodable, Hashable {
        let prompt: LocalizedText
        let options: [LocalizedText]
        let answer: Int
        let explanation: LocalizedText
    }

    struct Round: Decodable, Hashable, Identifiable {
        let id: String
        let poemID: String
        let lineIDs: [String]
        let pictures: [String]
        let answer: String
        let pictureFeedback: [String: LocalizedText]
        let evidence: Evidence
    }

    let theme: String
    let pictures: [Picture]
    let rounds: [Round]

    func picture(_ id: String) -> Picture? { pictures.first { $0.id == id } }
}

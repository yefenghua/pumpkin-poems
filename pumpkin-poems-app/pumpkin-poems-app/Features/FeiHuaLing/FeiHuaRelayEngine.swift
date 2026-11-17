import Foundation

/// A recall puzzle: the companion verse is the clue, and the answer is rebuilt from shuffled tiles.
struct FeiHuaRelayRound: Identifiable {
    let id: String
    let verse: GameVerse
    let tiles: [LocalizedText]
}

struct FeiHuaRelayEngine {
    enum Feedback: Equatable { case editing, incorrect, solved, skipped }

    let rounds: [FeiHuaRelayRound]
    private let normalizer: TextNormalizer
    private(set) var index = 0
    private(set) var selected: [Int] = []
    private(set) var hints = 0
    private(set) var mistakes = 0
    private(set) var score = 0
    private(set) var streak = 0
    private(set) var solvedCount = 0
    private(set) var gained = 0
    private(set) var feedback: Feedback = .editing

    var current: FeiHuaRelayRound? { rounds.indices.contains(index) ? rounds[index] : nil }
    var isResolved: Bool { feedback == .solved || feedback == .skipped }
    var isLast: Bool { index + 1 >= rounds.count }
    var answerLength: Int { current?.verse.text.hans.count ?? 0 }
    var canSubmit: Bool { !isResolved && selected.count == answerLength && answerLength > 0 }
    var basePoints: Int { max(20, 100 - hints * 20 - mistakes * 10) }

    init(character: LocalizedText, verses: [GameVerse], normalizer: TextNormalizer, count: Int = 5) {
        var generator = SystemRandomNumberGenerator()
        self.init(character: character, verses: verses, normalizer: normalizer, count: count, using: &generator)
    }

    init<G: RandomNumberGenerator>(character: LocalizedText, verses: [GameVerse], normalizer: TextNormalizer,
                                   count: Int = 5, using generator: inout G) {
        self.normalizer = normalizer
        let target = normalizer.normalize(character.hans)
        var seen: Set<String> = []
        let candidates = verses.filter {
            let key = normalizer.normalize($0.text.hans)
            return !target.isEmpty && key.contains(target) && [5, 7].contains(key.count)
                && $0.text.hant.count == $0.text.hans.count && $0.companion != nil
                && seen.insert(key).inserted
        }
        // Familiar classroom poems come first; the larger corpus fills a five-round session.
        let familiar = candidates.filter(\.hasLearningPage).shuffled(using: &generator)
        let extra = candidates.filter { !$0.hasLearningPage }.shuffled(using: &generator)
        var chosen: [GameVerse] = []
        var poemIDs: Set<String> = []
        for verse in familiar + extra where chosen.count < max(0, count) {
            if poemIDs.insert(verse.poemID).inserted { chosen.append(verse) }
        }
        for verse in familiar + extra where chosen.count < max(0, count) && !chosen.contains(verse) {
            chosen.append(verse)
        }
        // Five-character verses are a gentler first step; no answer is shown in reading order.
        chosen.sort { $0.text.hans.count < $1.text.hans.count }
        let pool = verses.flatMap { Self.characters($0.text) }
        rounds = chosen.map { verse in
            var tiles = Self.characters(verse.text)
            let answerCharacters = Set(tiles.map { normalizer.normalize($0.hans) })
            var seenDistractors: Set<String> = []
            let distractors = pool.shuffled(using: &generator).filter {
                let key = normalizer.normalize($0.hans)
                return !answerCharacters.contains(key) && seenDistractors.insert(key).inserted
            }.prefix(3)
            tiles += distractors
            tiles.shuffle(using: &generator)
            // Avoid the unlikely shuffle that leaves the complete answer at the front.
            if tiles.prefix(verse.text.hans.count).map(\.hans).joined() == verse.text.hans { tiles.reverse() }
            return FeiHuaRelayRound(id: verse.id, verse: verse, tiles: tiles)
        }
    }

    private static func characters(_ text: LocalizedText) -> [LocalizedText] {
        zip(text.hant, text.hans).map { LocalizedText(hant: String($0.0), hans: String($0.1)) }
    }

    func assembled(_ script: Script) -> String {
        guard let current else { return "" }
        return selected.map { current.tiles[$0](script) }.joined()
    }

    mutating func select(_ tile: Int) {
        guard let current, !isResolved, current.tiles.indices.contains(tile),
              !selected.contains(tile), selected.count < answerLength else { return }
        selected.append(tile)
        feedback = .editing
    }

    mutating func remove(at position: Int) {
        guard !isResolved, selected.indices.contains(position) else { return }
        selected.remove(at: position)
        feedback = .editing
    }

    mutating func clear() {
        guard !isResolved else { return }
        selected.removeAll()
        feedback = .editing
    }

    mutating func requestHint() {
        guard !isResolved, current != nil, hints < 2 else { return }
        hints += 1
        streak = 0
    }

    @discardableResult
    mutating func submit() -> Bool {
        guard canSubmit, let current else { return false }
        if normalizer.normalize(assembled(.hans)) == normalizer.normalize(current.verse.text.hans) {
            let independent = hints == 0 && mistakes == 0
            streak = independent ? streak + 1 : 0
            gained = basePoints + min(max(0, streak - 1), 3) * 20
            score += gained
            solvedCount += 1
            feedback = .solved
            return true
        }
        mistakes += 1
        streak = 0
        feedback = .incorrect
        return false
    }

    mutating func skip() {
        guard !isResolved, current != nil else { return }
        streak = 0
        gained = 0
        feedback = .skipped
    }

    mutating func next() {
        guard isResolved else { return }
        index += 1
        selected.removeAll()
        hints = 0
        mistakes = 0
        gained = 0
        feedback = .editing
    }
}

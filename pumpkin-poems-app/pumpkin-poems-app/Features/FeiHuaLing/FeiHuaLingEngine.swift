import Foundation

enum FeiHuaLingMode: String, CaseIterable, Identifiable {
    /// Legacy selection-mode key, retained for historic records only.
    case entry
    /// Reconstruct the verse from a companion-line clue and shuffled tiles.
    case relay
    /// 挑战: type a line from memory, with first-character hints and no timer.
    case challenge

    var id: String { rawValue }
}

/// A poem line that can be used as a 飞花令 answer.
struct FeiHuaLingLine: Hashable, Identifiable {
    let poemID: String
    let lineID: String
    let text: LocalizedText
    /// Normalized forms of both scripts.
    let keys: Set<String>

    var id: String { lineID }
}

/// Deterministic judging for single-player 飞花令 against the built-in library.
/// Answers outside the library are reported as "not collected", never as wrong.
struct FeiHuaLingEngine {
    enum Verdict: Equatable {
        case accepted(FeiHuaLingLine)
        case alreadyUsed(FeiHuaLingLine)
        /// A library line that does not contain the target character.
        case missingCharacter(FeiHuaLingLine)
        /// Not in the built-in library: neutral, not judged wrong.
        case notCollected
        case empty
    }

    struct Round: Identifiable {
        let id: Int
        let options: [FeiHuaLingLine]
        let answer: Int
    }

    let character: LocalizedText
    let allLines: [FeiHuaLingLine]
    let validLines: [FeiHuaLingLine]
    private(set) var used: [FeiHuaLingLine] = []
    private let normalizer: TextNormalizer

    init(character: LocalizedText, poems: [Poem], normalizer: TextNormalizer) {
        let lines = poems.flatMap { poem in
            poem.lines.map { line in
                FeiHuaLingLine(poemID: poem.id, lineID: line.id, text: line.text,
                               keys: [normalizer.normalize(line.text.hant), normalizer.normalize(line.text.hans)])
            }
        }
        self.init(character: character, lines: lines, normalizer: normalizer)
    }

    init(character: LocalizedText, verses: [GameVerse], normalizer: TextNormalizer) {
        let lines = verses.map { verse in
            FeiHuaLingLine(poemID: verse.poemID, lineID: verse.id, text: verse.text,
                           keys: [normalizer.normalize(verse.text.hant), normalizer.normalize(verse.text.hans)])
        }
        self.init(character: character, lines: lines, normalizer: normalizer)
    }

    private init(character: LocalizedText, lines: [FeiHuaLingLine], normalizer: TextNormalizer) {
        self.character = character
        self.normalizer = normalizer
        let target = normalizer.normalize(character.hans)
        // A repeated verse may belong to multiple poems. Keep one source per answer,
        // otherwise submit() can never reach the second copy and the game cannot finish.
        var seen: Set<String> = []
        allLines = lines.filter { line in
            let keys = line.keys.filter { !$0.isEmpty }
            guard !keys.isEmpty, seen.isDisjoint(with: keys) else { return false }
            seen.formUnion(keys)
            return true
        }
        validLines = allLines.filter { line in
            !target.isEmpty && line.keys.contains { $0.contains(target) }
        }
    }

    var isExhausted: Bool { used.count >= validLines.count }

    mutating func submit(_ input: String) -> Verdict {
        let key = normalizer.normalize(input)
        guard !key.isEmpty else { return .empty }
        guard let line = allLines.first(where: { $0.keys.contains(key) }) else { return .notCollected }
        if !validLines.contains(line) { return .missingCharacter(line) }
        if used.contains(line) { return .alreadyUsed(line) }
        used.append(line)
        return .accepted(line)
    }

    /// An unused valid line whose first character can be shown as a hint.
    func hint() -> FeiHuaLingLine? {
        validLines.first { !used.contains($0) }
    }

    /// Up to `count` rounds, each with one line containing the character and three without.
    func entryRounds(count: Int = 5) -> [Round] {
        var generator = SystemRandomNumberGenerator()
        return entryRounds(count: count, using: &generator)
    }

    func entryRounds<G: RandomNumberGenerator>(count: Int, using generator: inout G) -> [Round] {
        guard count > 0 else { return [] }
        let others = allLines.filter { !validLines.contains($0) }
        guard others.count >= 3 else { return [] }
        return validLines.shuffled(using: &generator).prefix(count).enumerated().map { index, correct in
            var options = Array(others.shuffled(using: &generator).prefix(3)) + [correct]
            options.shuffle(using: &generator)
            return Round(id: index, options: options, answer: options.firstIndex(of: correct) ?? 0)
        }
    }
}

import Foundation

/// Feihualing's own catalogue: concrete imagery characters with at least six usable verses.
/// The source collection is shared on disk, but this game owns its filtering and round rules.
struct FlyingFlowerCatalog {
    static let imagery = [
        LocalizedText(hant: "花", hans: "花"), LocalizedText(hant: "水", hans: "水"),
        LocalizedText(hant: "月", hans: "月"), LocalizedText(hant: "山", hans: "山"),
        LocalizedText(hant: "雲", hans: "云"), LocalizedText(hant: "雪", hans: "雪"),
        LocalizedText(hant: "風", hans: "风"), LocalizedText(hant: "雨", hans: "雨"),
    ]
    let verses: [GameVerse]
    let normalizer: TextNormalizer

    init(verses: [GameVerse], normalizer: TextNormalizer) {
        self.normalizer = normalizer
        var seen: Set<String> = []
        self.verses = verses.filter {
            let key = normalizer.normalize($0.text.hans)
            return [5, 7].contains(key.count) && $0.text.hans.count == key.count
                && $0.text.hant.count == key.count && seen.insert(key).inserted
        }
    }

    var characters: [LocalizedText] {
        Self.imagery.filter { lines(for: $0).count >= 6 }
    }

    func lines(for character: LocalizedText) -> [GameVerse] {
        let target = normalizer.normalize(character.hans)
        guard target.count == 1 else { return [] }
        return verses.filter { normalizer.normalize($0.text.hans).contains(target) }
    }
}

struct FlyingFlowerRound: Identifiable {
    let id: String
    let seed: GameVerse
    let fixedPositions: [Int]
    let alternatives: [GameVerse]
    var length: Int { seed.text.hans.count }
    var openPositions: [Int] { (0..<length).filter { !fixedPositions.contains($0) } }
}

/// Six poem-completion rounds. Any genuine catalogue verse matching all target positions is valid.
struct FlyingFlowerEngine {
    enum Verdict: Equatable { case editing, incorrect, duplicate, accepted, skipped }
    let character: LocalizedText
    let rounds: [FlyingFlowerRound]
    let libraryLetters: [LocalizedText]
    private let normalizer: TextNormalizer
    private(set) var index = 0
    private(set) var entered: [LocalizedText] = []
    private(set) var usedKeys: Set<String> = []
    private(set) var score = 0
    private(set) var mistakes = 0
    private(set) var verdict: Verdict = .editing
    private(set) var acceptedVerse: GameVerse?
    private(set) var solvedCount = 0
    private(set) var gained = 0
    private(set) var hintVerse: GameVerse?
    private(set) var hintPosition: Int?
    private(set) var hintLetter: LocalizedText?

    var current: FlyingFlowerRound? { rounds.indices.contains(index) ? rounds[index] : nil }
    var resolved: Bool { verdict == .accepted || verdict == .skipped }
    /// Absolute verse positions the player can still fill; a supplied hint is permanently fixed.
    var inputPositions: [Int] { current?.openPositions.filter { $0 != hintPosition } ?? [] }
    var full: Bool { current != nil && entered.count == inputPositions.count }
    var isLast: Bool { index + 1 >= rounds.count }
    var availableAlternatives: [GameVerse] {
        current?.alternatives.filter { verse in
            guard !usedKeys.contains(normalizer.normalize(verse.text.hans)) else { return false }
            guard let hintPosition, let hintLetter else { return true }
            return letterKey(hintLetter) == normalizer.normalize(String(Array(verse.text.hans)[hintPosition]))
        } ?? []
    }
    var possibleAnswers: [GameVerse] {
        guard current != nil else { return [] }
        return availableAlternatives.filter { verse in
            let letters = Array(verse.text.hans)
            return entered.enumerated().allSatisfy { offset, text in
                normalizer.normalize(text.hans) == normalizer.normalize(String(letters[inputPositions[offset]]))
            }
        }
    }

    init(character: LocalizedText, catalog: FlyingFlowerCatalog) {
        var generator = SystemRandomNumberGenerator()
        self.init(character: character, catalog: catalog, using: &generator)
    }

    init<G: RandomNumberGenerator>(character: LocalizedText, catalog: FlyingFlowerCatalog, using generator: inout G) {
        self.character = character
        normalizer = catalog.normalizer
        var seenLetters: Set<String> = []
        let target = catalog.normalizer.normalize(character.hans)
        libraryLetters = catalog.verses.flatMap { verse in
            zip(verse.text.hant, verse.text.hans).map {
                LocalizedText(hant: String($0.0), hans: String($0.1))
            }
        }.filter {
            let key = catalog.normalizer.normalize($0.hans)
            return key != target && seenLetters.insert(key).inserted
        }
        let candidates = catalog.lines(for: character)
        guard candidates.count >= 6 else { rounds = []; return }
        func positions(_ verse: GameVerse) -> [Int] {
            Array(catalog.normalizer.normalize(verse.text.hans)).indices.filter {
                String(Array(catalog.normalizer.normalize(verse.text.hans))[$0]) == target
            }
        }
        let familiar = candidates.filter(\.hasLearningPage).shuffled(using: &generator)
        let extended = candidates.filter { !$0.hasLearningPage }.shuffled(using: &generator)
        let chosen = Array((familiar + extended).prefix(6)).sorted { $0.text.hans.count < $1.text.hans.count }
        rounds = chosen.map { seed in
            let fixed = positions(seed)
            let alternatives = candidates.filter { $0.text.hans.count == seed.text.hans.count && positions($0) == fixed }
            return FlyingFlowerRound(id: seed.id, seed: seed, fixedPositions: fixed, alternatives: alternatives)
        }
    }

    func slots(_ script: Script) -> [String?] {
        guard let current else { return [] }
        var result = [String?](repeating: nil, count: current.length)
        for position in current.fixedPositions { result[position] = character(script) }
        if let hintPosition, let hintLetter { result[hintPosition] = hintLetter(script) }
        for (offset, text) in entered.enumerated() { result[inputPositions[offset]] = text(script) }
        return result
    }

    /// First hint step: show a real source matching the current input whenever possible.
    @discardableResult
    mutating func revealSourceHint() -> GameVerse? {
        guard current != nil, !resolved else { return nil }
        if hintPosition != nil { return hintVerse }
        hintVerse = possibleAnswers.first ?? availableAlternatives.first
        return hintVerse
    }

    /// Second hint step: fix one character at the first empty slot, preserving entered text.
    /// Hints cost no points and must be requested in source-then-character order.
    @discardableResult
    mutating func fillHintLetter() -> Bool {
        guard current != nil, !resolved, !full, hintPosition == nil, let hintVerse else { return false }
        let position = inputPositions[entered.count]
        let hant = Array(hintVerse.text.hant), hans = Array(hintVerse.text.hans)
        hintPosition = position
        hintLetter = LocalizedText(hant: String(hant[position]), hans: String(hans[position]))
        verdict = .editing
        return true
    }

    @discardableResult
    mutating func enter(_ text: LocalizedText) -> Bool {
        guard !resolved, !full, current != nil, text.hans.count == 1, text.hant.count == 1,
              TextNormalizer.isHan(text.hans.first!) else { return false }
        entered.append(text)
        verdict = .editing
        return true
    }

    mutating func undo() {
        guard !resolved, !entered.isEmpty else { return }
        entered.removeLast()
        verdict = .editing
    }

    mutating func clear() {
        guard !resolved else { return }
        entered.removeAll()
        verdict = .editing
    }

    @discardableResult
    mutating func submit() -> Verdict {
        guard !resolved, full, let current else { return verdict }
        let key = normalizer.normalize(slots(.hans).compactMap { $0 }.joined())
        guard let verse = current.alternatives.first(where: { normalizer.normalize($0.text.hans) == key }) else {
            mistakes += 1
            entered.removeAll()
            verdict = .incorrect
            return verdict
        }
        guard !usedKeys.contains(key) else {
            entered.removeAll()
            verdict = .duplicate
            return verdict
        }
        usedKeys.insert(key)
        acceptedVerse = verse
        gained = max(20, 100 - mistakes * 10)
        score += gained
        solvedCount += 1
        verdict = .accepted
        return verdict
    }

    mutating func skip() {
        guard !resolved, let current else { return }
        acceptedVerse = availableAlternatives.first ?? current.seed
        gained = 0
        verdict = .skipped
    }

    mutating func next() {
        guard resolved else { return }
        index += 1
        entered.removeAll()
        mistakes = 0
        gained = 0
        acceptedVerse = nil
        hintVerse = nil
        hintPosition = nil
        hintLetter = nil
        verdict = .editing
    }

    /// All valid alternatives contribute their characters, so equivalent genuine answers are playable.
    var answerLetters: [LocalizedText] {
        guard current != nil else { return [] }
        var seen: Set<String> = []
        return availableAlternatives.flatMap { verse in
            let hant = Array(verse.text.hant), hans = Array(verse.text.hans)
            return inputPositions.map { LocalizedText(hant: String(hant[$0]), hans: String(hans[$0])) }
        }.filter { seen.insert(normalizer.normalize($0.hans)).inserted }
    }

    var nextNeededLetter: LocalizedText? {
        guard current != nil, !full, let candidate = possibleAnswers.first else { return nil }
        let position = inputPositions[entered.count]
        return LocalizedText(hant: String(Array(candidate.text.hant)[position]), hans: String(Array(candidate.text.hans)[position]))
    }

    func letterKey(_ text: LocalizedText) -> String { normalizer.normalize(text.hans) }

    /// Normal supply mixes 60% answer letters with diverse, non-answer characters from this game library.
    /// The field requests a needed letter periodically; all visible normalized characters are excluded.
    func fallingLetter<G: RandomNumberGenerator>(excluding visible: Set<String>, prioritizeNeeded: Bool,
                                                  using generator: inout G) -> LocalizedText? {
        guard current != nil, !resolved, !full else { return nil }
        if prioritizeNeeded, let nextNeededLetter, !visible.contains(letterKey(nextNeededLetter)) {
            return nextNeededLetter
        }
        let allAnswers = answerLetters
        let answerKeys = Set(allAnswers.map(letterKey))
        let answers = allAnswers.filter { !visible.contains(letterKey($0)) }
        let distractors = libraryLetters.filter {
            let key = letterKey($0)
            return !visible.contains(key) && !answerKeys.contains(key)
        }
        if Int.random(in: 0..<10, using: &generator) < 6 {
            return answers.randomElement(using: &generator) ?? distractors.randomElement(using: &generator)
        }
        return distractors.randomElement(using: &generator) ?? answers.randomElement(using: &generator)
    }

    /// Kept for source compatibility; live play uses FlyingGlyphField's time-based guarantee.
    func fallingLetter<G: RandomNumberGenerator>(spawn: Int, using generator: inout G) -> LocalizedText? {
        fallingLetter(excluding: [], prioritizeNeeded: spawn.isMultiple(of: 3), using: &generator)
    }
}

import Foundation

/// One canonical character can be pressed repeatedly; the keyboard itself has no duplicates.
nonisolated struct PoemWordleKey: Identifiable, Hashable, Sendable {
    let id: String
    let text: LocalizedText
}

nonisolated struct PoemWordlePuzzle: Sendable {
    let length: Int
    /// Four or five different poems, with one verse per poem.
    let candidates: [GameVerse]
    /// Extra poems used only when the original keyboard has fewer than twenty characters.
    let supplements: [GameVerse]
    let answer: GameVerse
    let answerKeys: [String]
    let keyboard: [PoemWordleKey]
    let sharedCharacter: String
    /// All complete verses in the player-selected library, normalized across scripts.
    let validGuesses: Set<String>

    var allSources: [GameVerse] { candidates + supplements }

    static func make(length: Int, verses: [GameVerse], normalizer: TextNormalizer) -> Self? {
        var random = SystemRandomNumberGenerator()
        return make(length: length, verses: verses, normalizer: normalizer, using: &random)
    }

    static func make<G: RandomNumberGenerator>(length: Int, verses: [GameVerse],
                                               normalizer: TextNormalizer, using random: inout G, randomAttempts: Int = 120) -> Self? {
        guard length == 5 || length == 7 else { return nil }
        let pool = verses.filter {
            $0.text.hant.count == length && $0.text.hans.count == length
                && normalizer.normalize($0.text.hans).count == length
        }.sorted { $0.id < $1.id }
        guard Set(pool.map(\.poemID)).count >= 4 else { return nil }
        let normalized = Dictionary(pool.map { ($0.id, normalizer.normalize($0.text.hans)) },
                                    uniquingKeysWith: { first, _ in first })
        // A shared character occurs in at least three DIFFERENT poems, not just three lines.
        var sharedPoems: [String: Set<String>] = [:]
        for verse in pool {
            for character in Set(normalized[verse.id] ?? "") {
                sharedPoems[String(character), default: []].insert(verse.poemID)
            }
        }
        let common = sharedPoems.keys.filter { sharedPoems[$0, default: []].count >= 3 }.sorted()
        guard !common.isEmpty else { return nil }

        let poemGroups = Dictionary(grouping: pool, by: \.poemID)
        let commonGroups = Dictionary(uniqueKeysWithValues: common.map { shared in
            (shared, Dictionary(grouping: pool.filter { normalized[$0.id]?.contains(shared) == true }, by: \.poemID))
        })
        guard Set(normalized.values.flatMap(Array.init)).count >= 20,
              poemGroups.values.reduce(0, { total, group in
                  total + (group.map { Set(normalized[$0.id] ?? "").count }.max() ?? 0)
              }) - 2 >= 20 else { return nil }

        func finish(_ candidates: [GameVerse], supplements: [GameVerse], shared: String,
                    random: inout G) -> Self? {
            guard let answer = candidates.randomElement(using: &random) else { return nil }
            // Prefer the answer's spelling when variants share a normalized character.
            var display: [String: LocalizedText] = [:]
            for verse in [answer] + candidates + supplements {
                let hans = Array(verse.text.hans), hant = Array(verse.text.hant)
                let canonical = Array(normalized[verse.id] ?? "")
                for index in canonical.indices {
                    let key = String(canonical[index])
                    if display[key] == nil {
                        display[key] = LocalizedText(hant: String(hant[index]), hans: String(hans[index]))
                    }
                }
            }
            guard (20...30).contains(display.count) else { return nil }
            let keyboard = display.keys.sorted().shuffled(using: &random).compactMap { key in
                display[key].map { PoemWordleKey(id: key, text: $0) }
            }
            return Self(length: length, candidates: candidates.shuffled(using: &random), supplements: supplements,
                        answer: answer, answerKeys: Array(normalized[answer.id] ?? "").map(String.init),
                        keyboard: keyboard, sharedCharacter: shared, validGuesses: Set(normalized.values))
        }

        for _ in 0..<max(0, randomAttempts) {
            if Task<Never, Never>.isCancelled { return nil }
            let shared = common[Int.random(in: common.indices, using: &random)]
            let overlapPool = commonGroups[shared]!
            let overlapPoems = overlapPool.keys.sorted().shuffled(using: &random)
            let candidateCount = poemGroups.count >= 5 ? Int.random(in: 4...5, using: &random) : 4
            let sharedCount = Int.random(in: 3...min(4, overlapPoems.count, candidateCount), using: &random)
            var candidates: [GameVerse] = overlapPoems.prefix(sharedCount).compactMap { id in
                overlapPool[id]?.randomElement(using: &random)
            }
            var usedPoems = Set(candidates.map(\.poemID))
            for verse in pool.shuffled(using: &random) where candidates.count < candidateCount {
                if usedPoems.insert(verse.poemID).inserted { candidates.append(verse) }
            }
            guard candidates.count == candidateCount,
                  (3...4).contains(candidates.filter { normalized[$0.id]?.contains(shared) == true }.count) else { continue }
            var keys = Set(candidates.flatMap { Array(normalized[$0.id] ?? "") })
            guard keys.count <= 30 else { continue }
            var supplements: [GameVerse] = []
            if keys.count < 20 {
                for verse in pool.shuffled(using: &random) where !usedPoems.contains(verse.poemID) {
                    let enlarged = keys.union(normalized[verse.id] ?? "")
                    guard enlarged.count > keys.count else { continue }
                    supplements.append(verse)
                    usedPoems.insert(verse.poemID)
                    keys = enlarged
                    if keys.count >= 20 { break }
                }
            }
            if let puzzle = finish(candidates, supplements: supplements, shared: shared, random: &random) { return puzzle }
        }

        // Random sampling is only a fast path. Search the selected library before saying
        // it cannot form a game: a narrowly valid custom library must not fail by luck.
        // Any feasible 5-line base can be represented by a 4-line base plus a supplement.
        for shared in common.shuffled(using: &random) {
            let groups = poemGroups.keys.sorted().map { poemGroups[$0]! }.sorted {
                let left = $0.contains { normalized[$0.id]?.contains(shared) == true }
                let right = $1.contains { normalized[$0.id]?.contains(shared) == true }
                return left && !right
            }
            let keySets = groups.map { $0.map { Set(normalized[$0.id] ?? "") } }
            var suffixKeys = Array(repeating: Set<Character>(), count: groups.count + 1)
            var suffixShared = Array(repeating: 0, count: groups.count + 1)
            for index in groups.indices.reversed() {
                suffixKeys[index] = suffixKeys[index + 1].union(keySets[index].reduce(into: Set<Character>()) { $0.formUnion($1) })
                suffixShared[index] = suffixShared[index + 1] + (groups[index].contains { normalized[$0.id]?.contains(shared) == true } ? 1 : 0)
            }
            var failed: Set<String> = []
            func search(_ index: Int, selected: [GameVerse], keys: Set<Character>, sharedCount: Int) -> [GameVerse]? {
                if Task<Never, Never>.isCancelled { return nil }
                if selected.count >= 4 && sharedCount >= 3 && keys.count >= 20 { return selected }
                guard index < groups.count, selected.count + groups.count - index >= 4,
                      sharedCount + suffixShared[index] >= 3, keys.union(suffixKeys[index]).count >= 20 else { return nil }
                let state = "\(index):\(min(4, selected.count)):\(min(3, sharedCount)):\(String(keys.sorted()))"
                guard !failed.contains(state) else { return nil }
                let options = groups[index].indices.sorted {
                    let lhsShared = normalized[groups[index][$0].id]?.contains(shared) == true
                    let rhsShared = normalized[groups[index][$1].id]?.contains(shared) == true
                    if sharedCount < 3 && lhsShared != rhsShared { return lhsShared }
                    return keySets[index][$0].subtracting(keys).count > keySets[index][$1].subtracting(keys).count
                }
                for option in options {
                    let verse = groups[index][option]
                    let addsShared = normalized[verse.id]?.contains(shared) == true
                    if selected.count >= 4 && (!addsShared || sharedCount >= 3) && keySets[index][option].isSubset(of: keys) { continue }
                    if let result = search(index + 1, selected: selected + [verse], keys: keys.union(keySets[index][option]),
                                           sharedCount: sharedCount + (addsShared ? 1 : 0)) { return result }
                }
                if let result = search(index + 1, selected: selected, keys: keys, sharedCount: sharedCount) { return result }
                failed.insert(state)
                return nil
            }
            guard let selected = search(0, selected: [], keys: [], sharedCount: 0) else { continue }
            var candidates = Array(selected.filter { normalized[$0.id]?.contains(shared) == true }.prefix(3))
            if let fourth = selected.first(where: { verse in !candidates.contains { $0.poemID == verse.poemID } }) {
                candidates.append(fourth)
            }
            var keys = Set(candidates.flatMap { Array(normalized[$0.id] ?? "") })
            var supplements: [GameVerse] = []
            for verse in selected where !candidates.contains(where: { $0.poemID == verse.poemID }) && keys.count < 20 {
                let enlarged = keys.union(normalized[verse.id] ?? "")
                if enlarged.count > keys.count { supplements.append(verse); keys = enlarged }
            }
            if let puzzle = finish(candidates, supplements: supplements, shared: shared, random: &random) { return puzzle }
        }
        return nil
    }
}

nonisolated struct PoemWordleEngine {
    enum Mark: Int, Equatable, Comparable {
        case absent = 0, misplaced, correct
        static func < (lhs: Mark, rhs: Mark) -> Bool { lhs.rawValue < rhs.rawValue }
    }
    struct Guess: Identifiable {
        let id: Int
        let keys: [String]
        let marks: [Mark]
    }
    enum Submission: Equatable { case accepted, incomplete, notInLibrary, finished }

    static let maximumGuesses = 6
    let puzzle: PoemWordlePuzzle
    private(set) var input: [String] = []
    private(set) var guesses: [Guess] = []

    var won: Bool { guesses.last?.marks.allSatisfy { $0 == .correct } == true }
    var finished: Bool { won || guesses.count >= Self.maximumGuesses }
    var remainingGuesses: Int { max(0, Self.maximumGuesses - guesses.count) }
    var keyboardMarks: [String: Mark] {
        var result: [String: Mark] = [:]
        for guess in guesses {
            for (key, mark) in zip(guess.keys, guess.marks) {
                result[key] = max(result[key] ?? .absent, mark)
            }
        }
        return result
    }

    mutating func append(_ key: String) {
        guard !finished, input.count < puzzle.length, puzzle.keyboard.contains(where: { $0.id == key }) else { return }
        input.append(key)
    }

    mutating func backspace() { if !finished && !input.isEmpty { input.removeLast() } }
    mutating func clear() { if !finished { input.removeAll() } }

    @discardableResult
    mutating func submit() -> Submission {
        guard !finished else { return .finished }
        guard input.count == puzzle.length else { return .incomplete }
        guard puzzle.validGuesses.contains(input.joined()) else { return .notInLibrary }
        let marks = Self.grade(guess: input, answer: puzzle.answerKeys)
        guesses.append(Guess(id: guesses.count, keys: input, marks: marks))
        input.removeAll()
        return .accepted
    }

    /// Greens consume answer occurrences first. Only the remaining counts can turn yellow.
    static func grade(guess: [String], answer: [String]) -> [Mark] {
        guard guess.count == answer.count else { return [] }
        var marks = Array(repeating: Mark.absent, count: guess.count)
        var remaining: [String: Int] = [:]
        for index in answer.indices {
            if guess[index] == answer[index] { marks[index] = .correct }
            else { remaining[answer[index], default: 0] += 1 }
        }
        for index in guess.indices where marks[index] != .correct {
            if remaining[guess[index], default: 0] > 0 {
                marks[index] = .misplaced
                remaining[guess[index], default: 0] -= 1
            }
        }
        return marks
    }
}

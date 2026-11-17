import Foundation

private struct GridTestRandom: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

func runVerseGridTests(verses: [GameVerse], normalizer: TextNormalizer) {
    for size in [6, 7] {
        for seed in 0..<12 {
            var random = GridTestRandom(state: UInt64(seed))
            let requested = size == 6 ? 3 : 4
            guard let puzzle = VerseGridPuzzle.make(verses: verses, size: size, targetCount: requested,
                                                    normalizer: normalizer, using: &random) else {
                check(false, "grid size \(size), seed \(seed) generates")
                continue
            }
            check(puzzle.cells.count == size * size && puzzle.targets.count == requested, "grid dimensions and target count")
            check(Set(puzzle.targets.map { normalizer.normalize($0.verse.text.hans) }).count == requested, "grid targets have distinct answer text")
            var engine = VerseGridEngine(puzzle: puzzle, normalizer: normalizer)
            for target in puzzle.targets {
                check(target.path.count == Set(target.path).count && target.path.allSatisfy { puzzle.cells.indices.contains($0) }, "generated witness path never reuses a cell")
                check(target.path.map { puzzle.cells[$0].text.hans }.joined() == target.verse.text.hans, "all generated answers are discoverable in simplified script")
                check(target.path.map { puzzle.cells[$0].text.hant }.joined() == target.verse.text.hant, "all generated answers are discoverable in traditional script")
                for index in target.path { engine.select(index) }
                check(engine.submit() == .found(target.id), "witness path solves target")
            }
            check(engine.isComplete && engine.foundIDs.count == requested, "finding every target finishes game")
            check(engine.selection.isEmpty && engine.revealStart() == nil, "completed grid has no active selection or hint")
            let count = engine.attempts
            engine.select(0)
            check(engine.submit() == .empty && engine.attempts == count, "completed puzzle cannot record extra answers")
        }
    }
    var firstRandom = GridTestRandom(state: 42), secondRandom = GridTestRandom(state: 42)
    let first = VerseGridPuzzle.make(verses: verses, size: 6, targetCount: 3, normalizer: normalizer, using: &firstRandom)
    let second = VerseGridPuzzle.make(verses: verses, size: 6, targetCount: 3, normalizer: normalizer, using: &secondRandom)
    check(first?.cells == second?.cells && first?.targets.map(\.path) == second?.targets.map(\.path), "seeded grid generation is reproducible")
    check(VerseGridPuzzle.make(verses: [], size: 6, targetCount: 3, normalizer: normalizer) == nil, "empty grid corpus is handled")
    check(VerseGridPuzzle.make(verses: verses, size: -1, targetCount: 3, normalizer: normalizer) == nil, "invalid grid dimensions are handled")
    check(VerseGridPuzzle.make(verses: verses, size: 6, targetCount: 0, normalizer: normalizer) == nil, "empty target request is handled")

    guard let fixtureVerse = verses.first else { return }
    func verse(_ id: String, _ text: String) -> GameVerse {
        GameVerse(id: id, poemID: fixtureVerse.poemID, title: fixtureVerse.title, author: fixtureVerse.author,
                  text: LocalizedText(hant: text, hans: text), companion: nil, hasLearningPage: false)
    }
    // Identical letters on different cells are legal; large jumps and turns are legal.
    let repeated = verse("grid-repeated", "月月照山河")
    let other = verse("grid-other", "春風吹草生")
    let path = [0, 15, 3, 12, 5], otherPath = [1, 2, 4, 6, 7]
    var characters = Array(repeating: "雲", count: 16)
    for (index, letter) in zip(path, repeated.text.hans) { characters[index] = String(letter) }
    for (index, letter) in zip(otherPath, other.text.hans) { characters[index] = String(letter) }
    let cells = characters.enumerated().map { VerseGridPuzzle.Cell(id: $0.offset, text: LocalizedText(hant: $0.element, hans: $0.element)) }
    let puzzle = VerseGridPuzzle(size: 4, cells: cells,
        targets: [.init(verse: repeated, path: path), .init(verse: other, path: otherPath)])
    var engine = VerseGridEngine(puzzle: puzzle, normalizer: normalizer)
    check(engine.select(-1) == .ignored && engine.select(100) == .ignored, "out-of-bounds cell indices ignored")
    check(engine.submit() == .empty && engine.attempts == 0, "empty selection doesn't consume an attempt")
    check(engine.select(0) == .added && engine.select(15) == .added, "non-neighbouring grid cells accepted")
    check(engine.selectedText(.hans) == "月月", "repeated character accepted on two different cells")
    check(engine.select(15) == .ignored, "staying in a cell doesn't add or vibrate again")
    check(engine.select(3) == .added && engine.select(0) == .ignored, "earlier used cell cannot be appended again")
    check(engine.select(15) == .backtracked && engine.selection == [0, 15], "returning to preceding cell undoes last character")
    engine.undo()
    check(engine.selection == [0], "undo removes one letter")
    engine.clearSelection()
    check(engine.selection.isEmpty, "clear selection resets path")
    check(engine.revealStart() == 0 && engine.hintsUsed == 1, "hint reveals unsolved first letter and records hint")
    for index in path { engine.select(index) }
    check(engine.submit() == .found(repeated.id) && engine.foundPaths[repeated.id] == path, "cross-grid solution accepted and path retained")
    for index in path { engine.select(index) }
    check(engine.submit() == .alreadyFound(repeated.id) && engine.foundIDs.count == 1, "duplicate solution gives no extra progress")
    check(engine.revealStart() == otherPath.first, "next hint skips found answers")
    engine.select(8)
    check(engine.submit() == .notTarget && engine.selection.isEmpty && engine.foundIDs.count == 1, "wrong partial path clears safely without adding progress")
    for index in otherPath { engine.select(index) }
    check(engine.submit() == .found(other.id) && engine.isComplete, "second target completes fixture")

    // A selected library remains the entire source of both target and filler letters.
    let chosen = Array(verses.filter { $0.text.hans.count == 5 }.prefix(3))
    let chosenIDs = Set(chosen.map(\.id))
    if let restricted = VerseGridPuzzle.make(verses: chosen, size: 6, targetCount: 3, normalizer: normalizer) {
        check(Set(restricted.targets.map { $0.verse.id }) == chosenIDs, "grid targets stay inside selected library")
        let selectedCharacters = Set(chosen.flatMap { Array($0.text.hans) })
        check(restricted.cells.allSatisfy { selectedCharacters.contains($0.text.hans.first!) },
              "grid fillers cannot introduce outside-library characters")
    } else { check(false, "three unique selected five-character verses can start") }
    check(VerseGridPuzzle.make(verses: Array(chosen.prefix(2)), size: 6, targetCount: 3, normalizer: normalizer) == nil,
          "insufficient selected library does not silently expand")

    // Duplicating corpus sources cannot inflate the target count with identical answers.
    let duplicates = [repeated, repeated, repeated]
    check(VerseGridPuzzle.make(verses: duplicates, size: 6, targetCount: 3, normalizer: normalizer) == nil,
          "duplicate verses never produce unreachable additional targets")
}

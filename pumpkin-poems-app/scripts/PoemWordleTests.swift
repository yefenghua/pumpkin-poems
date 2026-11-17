import Foundation

private struct WordleTestRandom: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

func runPoemWordleTests(verses: [GameVerse], normalizer: TextNormalizer) {
    typealias Engine = PoemWordleEngine
    func keys(_ string: String) -> [String] { string.map(String.init) }
    check(Engine.grade(guess: keys("月月山月水"), answer: keys("月山月水水"))
          == [.correct, .misplaced, .misplaced, .absent, .correct],
          "Wordle duplicate guesses consume the remaining occurrence count")
    check(Engine.grade(guess: keys("月月月月月"), answer: keys("床前明月光"))
          == [.absent, .absent, .absent, .correct, .absent],
          "Wordle exact-position occurrence is reserved before yellows")
    check(Engine.grade(guess: keys("夜月明前床"), answer: keys("床前明月光"))
          == [.absent, .misplaced, .correct, .misplaced, .misplaced],
          "Wordle ordinary exact/elsewhere/absent feedback")
    check(Engine.grade(guess: ["月"], answer: keys("床前明月光")).isEmpty,
          "mismatched lengths do not produce misleading grades")

    var random = WordleTestRandom(state: 76453)
    check(PoemWordlePuzzle.make(length: 6, verses: verses, normalizer: normalizer, using: &random) == nil,
          "Wordle rejects unsupported verse length")
    check(PoemWordlePuzzle.make(length: 5, verses: [], normalizer: normalizer, using: &random) == nil,
          "Wordle empty corpus fails gracefully")
    let onePoem = verses.filter { $0.poemID == verses.first?.poemID }
    check(PoemWordlePuzzle.make(length: 5, verses: onePoem, normalizer: normalizer, using: &random) == nil,
          "many verses from one poem cannot satisfy different-poem constraint")

    for length in [5, 7] {
        for seed in 1...60 {
            var rng = WordleTestRandom(state: UInt64(seed))
            guard let puzzle = PoemWordlePuzzle.make(length: length, verses: verses, normalizer: normalizer, using: &rng) else {
                check(false, "Wordle generates length \(length), seed \(seed)")
                continue
            }
            check((4...5).contains(puzzle.candidates.count), "4-5 original candidate lines")
            check(Set(puzzle.candidates.map(\.poemID)).count == puzzle.candidates.count, "one candidate per poem")
            check(puzzle.candidates.contains(puzzle.answer), "answer belongs to the original selected poems")
            let sharing = puzzle.candidates.filter { normalizer.normalize($0.text.hans).contains(puzzle.sharedCharacter) }
            check((3...4).contains(sharing.count), "3-4 candidate poems share a character")
            check((20...30).contains(puzzle.keyboard.count), "keyboard has 20-30 unique keys")
            check(Set(puzzle.keyboard.map(\.id)).count == puzzle.keyboard.count, "keyboard keys are deduplicated")
            check(Set(puzzle.answerKeys).isSubset(of: Set(puzzle.keyboard.map(\.id))), "answer always typeable")
            let sourceKeys = Set(puzzle.allSources.flatMap { keys(normalizer.normalize($0.text.hans)) })
            check(sourceKeys == Set(puzzle.keyboard.map(\.id)), "keyboard comes entirely from selected/source verses")
            check(Set(puzzle.allSources.map(\.poemID)).count == puzzle.allSources.count,
                  "supplemental lines also come from distinct poems")
            check(puzzle.allSources.allSatisfy { $0.text.hans.count == length }, "all source lines match selected length")
            check(puzzle.keyboard.allSatisfy {
                normalizer.normalize($0.text.hant) == $0.id && normalizer.normalize($0.text.hans) == $0.id
            }, "both displayed scripts map to same keyboard identity")

            var game = Engine(puzzle: puzzle)
            check(game.submit() == .incomplete && game.guesses.isEmpty, "blank guess does not spend round")
            game.append("not-a-key")
            check(game.input.isEmpty, "unknown input cannot enter the keyboard")
            game.append(puzzle.answerKeys[0]); game.backspace()
            check(game.input.isEmpty, "backspace removes last character")
            for key in puzzle.answerKeys { game.append(key) }
            game.append(puzzle.answerKeys[0])
            check(game.input.count == length, "input cannot exceed selected length")
            check(game.submit() == .accepted && game.won && game.finished, "correct answer wins and ends immediately")
            check(game.submit() == .finished && game.guesses.count == 1, "finished game cannot gain extra guesses")
            let count = game.input.count
            game.append(puzzle.answerKeys[0]); game.backspace(); game.clear()
            check(game.input.count == count, "finished input is immutable")

            var invalid = Engine(puzzle: puzzle)
            let absent = puzzle.keyboard.first { !puzzle.answerKeys.contains($0.id) }!.id
            for _ in 0..<length { invalid.append(absent) }
            check(invalid.submit() == .notInLibrary && invalid.guesses.isEmpty && invalid.remainingGuesses == 6,
                  "invented complete text is rejected without consuming a round")
            check(invalid.input.count == length && invalid.keyboardMarks.isEmpty,
                  "unrecognized guess remains editable and gives no color information")
            invalid.clear()
            for key in puzzle.answerKeys { invalid.append(key) }
            check(invalid.submit() == .accepted && invalid.won, "valid verse can follow an unrecognized attempt")

            var losing = Engine(puzzle: puzzle)
            let wrongVerse = puzzle.candidates.first { normalizer.normalize($0.text.hans) != puzzle.answerKeys.joined() }!
            let wrongKeys = keys(normalizer.normalize(wrongVerse.text.hans))
            for _ in 0..<6 {
                for key in wrongKeys { losing.append(key) }
                check(losing.submit() == .accepted, "real complete source verse is accepted")
            }
            check(losing.finished && !losing.won && losing.guesses.count == 6, "exactly six failed rounds end the game")
            check(losing.remainingGuesses == 0 && losing.submit() == .finished, "seventh guess cannot be submitted")
            check(puzzle.validGuesses == Set(verses.filter { $0.text.hans.count == length }
                .map { normalizer.normalize($0.text.hans) }), "allowed guesses include exactly the selected same-length corpus")

            var evolving = Engine(puzzle: puzzle)
            for key in wrongKeys { evolving.append(key) }
            _ = evolving.submit()
            for key in puzzle.answerKeys { evolving.append(key) }
            _ = evolving.submit()
            check(puzzle.answerKeys.allSatisfy { evolving.keyboardMarks[$0] == .correct },
                  "keyboard keeps strongest observed mark for repeated characters")
        }
    }
    // Reusing only the chosen poems must retain enough information for both generation
    // and validation; no fallback may draw extra letters from the wider corpus.
    for length in [5, 7] {
        var sourceRandom = WordleTestRandom(state: 123)
        guard let source = PoemWordlePuzzle.make(length: length, verses: verses, normalizer: normalizer, using: &sourceRandom) else { continue }
        let ids = Set(source.allSources.map(\.poemID))
        let selected = verses.filter { ids.contains($0.poemID) }
        for seed in 1...20 {
            var rng = WordleTestRandom(state: UInt64(seed))
            guard let restricted = PoemWordlePuzzle.make(length: length, verses: selected, normalizer: normalizer, using: &rng) else {
                check(false, "a known feasible selected library never randomly fails")
                continue
            }
            check(restricted.allSources.allSatisfy { ids.contains($0.poemID) }, "source generation stays inside selected poems")
            check(restricted.validGuesses == Set(selected.filter { $0.text.hans.count == length }
                .map { normalizer.normalize($0.text.hans) }), "validation cannot admit unselected poem lines")
        }
        var fallbackRandom = WordleTestRandom(state: 89)
        let fallback = PoemWordlePuzzle.make(length: length, verses: source.allSources, normalizer: normalizer,
                                             using: &fallbackRandom, randomAttempts: 0)
        check(fallback != nil && (20...30).contains(fallback?.keyboard.count ?? 0),
              "deterministic fallback finds a feasible library without random attempts")
        if let fallback {
            check(fallback.candidates.count == 4 && Set(fallback.allSources.map(\.poemID)).count == fallback.allSources.count,
                  "fallback keeps distinct source poems and four base candidates")
            check((3...4).contains(fallback.candidates.filter { normalizer.normalize($0.text.hans).contains(fallback.sharedCharacter) }.count),
                  "fallback retains the shared-character constraint")
        }
        // The same exact witness verses also form a feasible narrow library.
        for seed in 1...20 {
            var rng = WordleTestRandom(state: UInt64(seed))
            check(PoemWordlePuzzle.make(length: length, verses: source.allSources, normalizer: normalizer, using: &rng) != nil,
                  "narrow witness library generates for every random seed")
        }
    }
    // Same seed and sorted corpus must reproduce the exact puzzle for debugging.
    var a = WordleTestRandom(state: 771), b = WordleTestRandom(state: 771)
    let first = PoemWordlePuzzle.make(length: 5, verses: verses, normalizer: normalizer, using: &a)
    let again = PoemWordlePuzzle.make(length: 5, verses: verses, normalizer: normalizer, using: &b)
    check(first?.answer.id == again?.answer.id && first?.keyboard == again?.keyboard,
          "Wordle seeded generation is reproducible")
}

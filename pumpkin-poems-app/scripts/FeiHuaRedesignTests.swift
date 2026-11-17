import Foundation

private struct FlyingFlowerTestRandom: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

func runFeiHuaRedesignTests(verses: [GameVerse], normalizer: TextNormalizer) {
    let moon = LocalizedText(hant: "月", hans: "月")
    let catalog = FlyingFlowerCatalog(verses: verses, normalizer: normalizer)
    func fill(_ engine: inout FlyingFlowerEngine, with verse: GameVerse) {
        guard engine.current != nil else { return }
        engine.clear()
        let hans = Array(verse.text.hans), hant = Array(verse.text.hant)
        for index in engine.inputPositions {
            engine.enter(LocalizedText(hant: String(hant[index]), hans: String(hans[index])))
        }
    }
    func fixedPositions(_ verse: GameVerse, target: String) -> [Int] {
        Array(normalizer.normalize(verse.text.hans)).enumerated().compactMap { $0.element.description == target ? $0.offset : nil }
    }

    check(catalog.characters.count == 8, "all eight imagery choices have a six-line pool")
    check(catalog.characters.allSatisfy { catalog.lines(for: $0).count >= 6 }, "every visible flying character supports a full session")
    let sparse = FlyingFlowerCatalog(verses: Array(catalog.lines(for: moon).prefix(5)), normalizer: normalizer)
    check(!sparse.characters.contains(moon), "five lines cannot expose an unplayable six-round choice")
    let deduped = FlyingFlowerCatalog(verses: verses + verses, normalizer: normalizer)
    check(deduped.verses.count == catalog.verses.count, "duplicated source lines never inflate the playable pool")

    // A real six-line group shares the final 月 slot, exercising alternate answers and reuse.
    let sameTemplate = catalog.lines(for: moon).filter {
        $0.text.hans.count == 5 && fixedPositions($0, target: "月") == [4]
    }
    check(sameTemplate.count >= 6, "six genuine moon-end fixtures are available")
    let focused = FlyingFlowerCatalog(verses: sameTemplate, normalizer: normalizer)
    var rng = FlyingFlowerTestRandom(state: 42)
    var game = FlyingFlowerEngine(character: moon, catalog: focused, using: &rng)
    check(game.rounds.count == 6, "a session contains exactly six rounds")
    check(game.slots(.hans).compactMap { $0 } == ["月"], "only the fixed flying character starts visible")
    check(game.submit() == .editing && game.score == 0 && game.mistakes == 0, "incomplete submission cannot score or penalise")
    game.next()
    check(game.index == 0, "an unresolved round cannot advance")
    check(!game.enter(LocalizedText(hant: "ab", hans: "ab")), "non-character input is rejected")
    check(!game.enter(LocalizedText(hant: "1", hans: "1")), "non-Han tiles are rejected")
    if let round = game.current, let alternative = round.alternatives.first(where: { $0.id != round.seed.id }) {
        let needed = Set(round.openPositions.map { String(Array(alternative.text.hans)[$0]) })
        check(needed.isSubset(of: Set(game.answerLetters.map(\.hans))), "alternate verse characters are included in falling pool")
        fill(&game, with: alternative)
        check(game.full && game.submit() == .accepted, "a real matching alternative is accepted instead of only the seed")
        check(game.acceptedVerse?.id == alternative.id && game.score == 100, "feedback attributes the actual accepted verse and scores it")
        let entered = game.entered
        game.clear(); game.undo(); game.skip()
        check(!game.enter(moon) && game.entered == entered, "resolved round cannot be edited")
        game.submit()
        check(game.score == 100 && game.solvedCount == 1, "repeated submission cannot score twice")
        game.next()
        fill(&game, with: alternative)
        check(game.submit() == .duplicate && game.score == 100, "a previously scored phrase cannot earn points in another round")
        check(game.entered.isEmpty && !game.full && game.slots(.hans).compactMap { $0 } == ["月"], "duplicate submission automatically clears only entered characters")
        check(game.availableAlternatives.allSatisfy { $0.id != alternative.id }, "used phrase is removed from eligible hints and answer pool")
        game.undo()
        check(game.verdict == .duplicate, "automatic clearing retains duplicate verdict for short UI feedback")
        game.enter(LocalizedText(hant: "舉", hans: "举")); game.undo()
        check(game.verdict == .editing && game.entered.isEmpty, "entering a new tile clears old feedback and supports undo")
        game.clear()
        check(game.entered.isEmpty && game.slots(.hans).last! == "月", "retry clears entered characters and retains fixed positions")
        for _ in game.current!.openPositions { game.enter(LocalizedText(hant: "龜", hans: "龟")) }
        check(game.submit() == .incorrect && game.mistakes == 1, "a false full-length phrase is retryable with penalty")
        check(game.entered.isEmpty && !game.full && game.slots(.hans).compactMap { $0 } == ["月"], "wrong submission automatically clears input while preserving fixed target")
        game.submit()
        check(game.mistakes == 1 && game.verdict == .incorrect, "repeated empty submission retains feedback without another penalty")
        if let replacement = game.availableAlternatives.first {
            fill(&game, with: replacement)
            check(game.submit() == .accepted && game.gained == 90 && game.score == 190, "correcting one wrong answer earns ninety points")
        }
        game.next(); game.skip()
        check(game.resolved && game.acceptedVerse != nil && game.gained == 0 && game.score == 190, "skip reveals a real source without points")
    } else { check(false, "matching alternate fixture exists") }

    // The user's example must be playable: __月__ accepts both genuine Li Bai lines.
    let exampleLines = catalog.lines(for: moon).filter { ["我歌月徘徊", "暂伴月将影"].contains($0.text.hans) }
    check(exampleLines.count == 2, "both user-specified alternative phrases exist in the game catalogue")
    let exampleCatalog = FlyingFlowerCatalog(verses: exampleLines + Array(sameTemplate.prefix(4)), normalizer: normalizer)
    var exampleGame = FlyingFlowerEngine(character: moon, catalog: exampleCatalog)
    while exampleGame.current != nil && exampleGame.current?.fixedPositions != [2] { exampleGame.skip(); exampleGame.next() }
    check(Set(exampleGame.current?.alternatives.map(\.text.hans) ?? []).isSuperset(of: ["我歌月徘徊", "暂伴月将影"]), "the user's two real phrases are accepted under one position template")
    if let verse = exampleLines.first { fill(&exampleGame, with: verse); check(exampleGame.submit() == .accepted, "the user example is accepted end to end") }

    // Every occurrence of the flying character stays fixed, not only the first occurrence.
    let mountain = LocalizedText(hant: "山", hans: "山")
    if let repeated = catalog.lines(for: mountain).first(where: { $0.text.hans.filter { $0 == "山" }.count == 2 }) {
        let mountainCatalog = FlyingFlowerCatalog(verses: [repeated] + Array(catalog.lines(for: mountain).filter { $0.id != repeated.id }.prefix(5)), normalizer: normalizer)
        var mountainGame = FlyingFlowerEngine(character: mountain, catalog: mountainCatalog)
        while let current = mountainGame.current, current.seed.id != repeated.id { mountainGame.skip(); mountainGame.next() }
        check(mountainGame.current?.fixedPositions == fixedPositions(repeated, target: "山"), "all repeated target positions are fixed")
        check(mountainGame.slots(.hant).compactMap { $0 }.filter { $0 == "山" }.count == 2, "both target occurrences display before play")
        fill(&mountainGame, with: repeated)
        check(mountainGame.submit() == .accepted, "repeated-target template remains solvable")
    } else { check(false, "repeated-target fixture exists") }

    // Each seed/character generates a full, solvable session in both scripts without reused answers.
    for seed in 0..<12 {
        for character in catalog.characters {
            var generator = FlyingFlowerTestRandom(state: UInt64(seed))
            var session = FlyingFlowerEngine(character: character, catalog: catalog, using: &generator)
            check(session.rounds.count == 6 && Set(session.rounds.map(\.id)).count == 6, "six unique seeds are produced")
            for _ in 0..<6 {
                guard let round = session.current, let answer = session.availableAlternatives.first else {
                    check(false, "alternate answers never exhaust a future round"); break
                }
                check(round.fixedPositions == fixedPositions(answer, target: character.hans), "all valid alternatives match every target position")
                for _ in round.openPositions {
                    guard let expected = session.nextNeededLetter else { check(false, "a compatible next letter exists"); break }
                    let next = session.fallingLetter(spawn: 3, using: &generator)
                    check(next == expected, "every third spawn guarantees the next compatible character")
                    session.enter(expected)
                }
                check(session.slots(.hant).compactMap { $0 }.joined() == answer.text.hant, "traditional tiles preserve the same source phrase")
                check(session.submit() == .accepted, "guaranteed falling characters can solve every generated round")
                check(session.fallingLetter(spawn: 0, using: &generator) == nil, "completed rounds spawn no more characters")
                session.next()
            }
            check(session.current == nil && session.score == 600 && session.solvedCount == 6 && session.usedKeys.count == 6, "six unique completions finish with exactly six hundred points")
        }
    }
    var empty = FlyingFlowerEngine(character: moon, catalog: sparse)
    empty.next(); empty.skip(); empty.clear(); empty.undo(); empty.submit()
    check(empty.current == nil && empty.score == 0 && empty.answerLetters.isEmpty, "insufficient-content sessions stay safe")
    runFlyingHintTests(catalog: catalog)
    runFlyingGlyphFieldTests(catalog: catalog)
}

private func runFlyingHintTests(catalog: FlyingFlowerCatalog) {
    let moon = LocalizedText(hant: "月", hans: "月")
    let candidates = catalog.lines(for: moon).filter { $0.text.hans.count == 5 && $0.text.hans.last == "月" }
    guard let primary = candidates.first(where: { $0.text.hans == "举头望明月" }),
          let alternative = candidates.first(where: { $0.text.hans == "举杯邀明月" }) else {
        check(false, "real shared-prefix hint fixtures are available"); return
    }
    let focused = FlyingFlowerCatalog(verses: [primary] + candidates.filter { $0.id != primary.id }, normalizer: catalog.normalizer)
    func letter(_ verse: GameVerse, at position: Int) -> LocalizedText {
        LocalizedText(hant: String(Array(verse.text.hant)[position]), hans: String(Array(verse.text.hans)[position]))
    }
    func fill(_ game: inout FlyingFlowerEngine, with verse: GameVerse) {
        game.clear()
        for position in game.inputPositions { game.enter(letter(verse, at: position)) }
    }

    var game = FlyingFlowerEngine(character: moon, catalog: focused)
    check(!game.fillHintLetter() && game.hintPosition == nil, "a character hint cannot precede the source hint")
    check(game.revealSourceHint()?.id == primary.id && game.hintVerse?.author == primary.author, "first hint reveals the actual source and author")
    check(game.entered.isEmpty && game.hintPosition == nil && game.score == 0 && game.mistakes == 0, "revealing a source neither fills a character nor changes score")
    check(game.fillHintLetter() && game.hintPosition == 0, "second hint fills the first empty position")
    check(game.hintLetter == LocalizedText(hant: "舉", hans: "举"), "hint stores aligned traditional and simplified characters")
    check(game.slots(.hant)[0] == "舉" && game.slots(.hans)[0] == "举" && game.slots(.hans)[4] == "月", "hint and flying character display in their fixed positions in both scripts")
    check(game.inputPositions == [1, 2, 3] && game.entered.isEmpty, "hinted slot is excluded from player input positions")
    check(game.nextNeededLetter == letter(primary, at: 1), "next-needed character skips the fixed hint")
    let expectedPool = Set(game.availableAlternatives.flatMap { verse in game.inputPositions.map { game.letterKey(letter(verse, at: $0)) } })
    check(Set(game.answerLetters.map(game.letterKey)) == expectedPool && !expectedPool.contains("举"), "falling answer pool omits the fixed hint while retaining usable alternative characters")
    check(!game.fillHintLetter() && game.score == 0 && game.mistakes == 0, "only one character may be supplied per round at no point cost")
    game.enter(letter(alternative, at: 1))
    check(game.revealSourceHint()?.id == primary.id, "supplied character locks the originally revealed source")
    game.undo(); game.undo(); game.clear()
    check(game.entered.isEmpty && game.slots(.hans).compactMap { $0 } == ["举", "月"], "undo and retry never erase fixed hint or target characters")
    for _ in game.inputPositions { game.enter(LocalizedText(hant: "龜", hans: "龟")) }
    check(game.submit() == .incorrect && game.entered.isEmpty, "wrong hinted answers still auto-clear entered characters")
    check(game.hintPosition == 0 && game.hintLetter?.hans == "举" && game.slots(.hans).compactMap { $0 } == ["举", "月"], "automatic clearing preserves the hint exactly")
    check(game.mistakes == 1 && game.score == 0 && !game.fillHintLetter(), "wrong submission does not unlock a second hint")
    fill(&game, with: primary)
    check(game.submit() == .accepted && game.gained == 90 && game.score == 90, "hinted success applies only the ordinary wrong-answer penalty")
    let resolvedSlots = game.slots(.hans)
    check(!game.fillHintLetter() && game.revealSourceHint() == nil && game.slots(.hans) == resolvedSlots, "resolved round cannot be changed by hints")
    game.next()
    check(game.hintVerse == nil && game.hintLetter == nil && game.hintPosition == nil && game.inputPositions == [0, 1, 2, 3], "advancing clears all per-round hint state")
    check(game.revealSourceHint() != nil && game.fillHintLetter(), "a new round receives its own one-character hint")

    var alternateGame = FlyingFlowerEngine(character: moon, catalog: focused)
    alternateGame.revealSourceHint(); alternateGame.fillHintLetter()
    fill(&alternateGame, with: alternative)
    check(alternateGame.submit() == .accepted && alternateGame.acceptedVerse?.id == alternative.id && alternateGame.gained == 100,
          "another real phrase matching the hinted slot remains valid at full points")
    alternateGame.next(); alternateGame.revealSourceHint(); alternateGame.fillHintLetter()
    fill(&alternateGame, with: alternative)
    check(alternateGame.submit() == .duplicate && alternateGame.entered.isEmpty && alternateGame.hintLetter?.hans == "举",
          "duplicate answers clear player input while preserving the new round's fixed hint")
    check(alternateGame.score == 100 && alternateGame.mistakes == 0, "hints and duplicate submission do not change earned score")

    var prefixGame = FlyingFlowerEngine(character: moon, catalog: focused)
    prefixGame.revealSourceHint()
    for position in [0, 1] { prefixGame.enter(letter(alternative, at: position)) }
    let before = prefixGame.entered
    check(prefixGame.revealSourceHint()?.id == alternative.id, "before filling, source hint adapts to the current compatible prefix")
    check(prefixGame.fillHintLetter() && prefixGame.hintPosition == 2 && prefixGame.entered == before, "a source-consistent hint fills only the next empty slot without editing the prefix")
    check(prefixGame.possibleAnswers.contains(alternative) && prefixGame.nextNeededLetter == letter(alternative, at: 3), "candidate matching and next-needed supply respect a middle hint position")
    prefixGame.enter(letter(alternative, at: 3))
    check(prefixGame.full && prefixGame.slots(.hans).compactMap { $0 }.joined() == alternative.text.hans && prefixGame.submit() == .accepted,
          "input after a middle hint assembles and submits in correct verse order")

    var fallbackGame = FlyingFlowerEngine(character: moon, catalog: focused)
    fallbackGame.enter(LocalizedText(hant: "龜", hans: "龟"))
    check(fallbackGame.possibleAnswers.isEmpty && fallbackGame.revealSourceHint()?.id == primary.id, "an incompatible prefix falls back to an unused valid source")
    check(fallbackGame.fillHintLetter() && fallbackGame.hintPosition == 1 && fallbackGame.entered.first?.hans == "龟", "fallback hint leaves incompatible player input unchanged")
    fallbackGame.clear()
    check(fallbackGame.slots(.hans)[0] == nil && fallbackGame.slots(.hans)[1] == "头" && fallbackGame.slots(.hant)[1] == "頭", "clearing a prefix preserves a middle hint in both scripts")
    check(fallbackGame.nextNeededLetter == letter(primary, at: 0), "after clearing, supply returns to the earliest remaining empty slot")
    fill(&fallbackGame, with: primary)
    check(fallbackGame.submit() == .accepted && fallbackGame.score == 100, "reconstructed hinted phrase earns full points without a submitted mistake")

    var lastSlotGame = FlyingFlowerEngine(character: moon, catalog: focused)
    for position in [0, 1, 2] { lastSlotGame.enter(letter(primary, at: position)) }
    lastSlotGame.revealSourceHint()
    check(lastSlotGame.fillHintLetter() && lastSlotGame.hintPosition == 3 && lastSlotGame.full, "hint can fill the final empty slot and make the answer complete")
    check(lastSlotGame.nextNeededLetter == nil && !lastSlotGame.enter(moon) && lastSlotGame.submit() == .accepted && lastSlotGame.score == 100,
          "a final-slot hint requires no extra tile and incurs no score penalty")

    var fullGame = FlyingFlowerEngine(character: moon, catalog: focused)
    fill(&fullGame, with: primary); fullGame.revealSourceHint()
    check(!fullGame.fillHintLetter() && fullGame.hintPosition == nil && fullGame.full, "already-full input cannot be replaced by a hint")
    var empty = FlyingFlowerEngine(character: moon, catalog: FlyingFlowerCatalog(verses: [], normalizer: catalog.normalizer))
    check(empty.revealSourceHint() == nil && !empty.fillHintLetter(), "empty sessions safely reject both hint steps")

    let mountain = LocalizedText(hant: "山", hans: "山")
    let mountainLines = catalog.lines(for: mountain)
    if let repeated = mountainLines.first(where: { $0.text.hans.count == 7 && $0.text.hans.filter { $0 == "山" }.count == 2 }) {
        let fixture = FlyingFlowerCatalog(verses: [repeated] + Array(mountainLines.filter { $0.id != repeated.id }.prefix(5)), normalizer: catalog.normalizer)
        var seven = FlyingFlowerEngine(character: mountain, catalog: fixture)
        while seven.current != nil && seven.current?.seed.id != repeated.id { seven.skip(); seven.next() }
        seven.revealSourceHint(); seven.fillHintLetter(); seven.clear()
        check(seven.slots(.hans).compactMap { $0 }.count == 3 && seven.slots(.hans).compactMap { $0 }.filter { $0 == "山" }.count == 2,
              "seven-character hints preserve every repeated flying-character occurrence")
        if let source = seven.hintVerse {
            fill(&seven, with: source)
            check(seven.submit() == .accepted && seven.gained == 100, "seven-character hinted answers remain correctly ordered and score normally")
        } else { check(false, "seven-character source hint exists") }
    } else { check(false, "seven-character repeated-target hint fixture exists") }
}

private func runFlyingGlyphFieldTests(catalog: FlyingFlowerCatalog) {
    var random = FlyingFlowerTestRandom(state: 3107)
    let game = FlyingFlowerEngine(character: LocalizedText(hant: "月", hans: "月"), catalog: catalog, using: &random)
    let answers = Set(game.answerLetters.map(game.letterKey))
    let imagery = Set(FlyingFlowerCatalog.imagery.map(game.letterKey))
    check(game.libraryLetters.count > 100, "distractor library draws on diverse poetry characters")
    var answerCount = 0
    var otherKeys: Set<String> = []
    for _ in 0..<1000 {
        if let letter = game.fallingLetter(excluding: [], prioritizeNeeded: false, using: &random) {
            let key = game.letterKey(letter)
            if answers.contains(key) { answerCount += 1 } else { otherKeys.insert(key) }
        }
    }
    check((520...680).contains(answerCount), "normal supply gives approximately sixty percent answer characters")
    check(otherKeys.subtracting(imagery).count > 50, "non-answer supply is not restricted to eight preset imagery characters")
    let allKeys = Set(game.libraryLetters.map(game.letterKey))
    check(game.fallingLetter(excluding: allKeys, prioritizeNeeded: true, using: &random) == nil, "normalized exclusion can exhaust all supply without duplicate fallback")

    var signatures: Set<String> = []
    var sawBoostDensity = false
    var sawNaturalRetreat = false
    for width in [80.0, 244.0, 320.0, 390.0, 620.0] {
        for reduced in [false, true] {
            for seed in 1...4 {
                var field = FlyingGlyphField(width: width, height: 300, reduceMotion: reduced, seed: UInt64(seed))
                var duplicate = false
                var overlap = false
                var outOfBounds = false
                var excessive = false
                var invalidBirth = false
                var jumped = false
                var instantRemoval = false
                var seenIDs: Set<UInt64> = []
                var births: [Double] = []
                var lanes: Set<Int> = []
                var horizontalOffsets: Set<Int> = []
                var fixedPositions: [UInt64: FlyingGlyphField.Position] = [:]
                var reachedNeeded = false
                let desired = game.nextNeededLetter.map(game.letterKey)
                for tick in 0...240 {
                    let now = Double(tick) * 0.25
                    if tick == 48 {
                        let before = field.glyphs
                        let positions = before.map { field.position(of: $0, at: now) }
                        field.shake(at: now)
                        jumped = jumped || field.glyphs != before || field.glyphs.map { field.position(of: $0, at: now) } != positions
                        check(field.isBoosted(at: now) && !field.isBoosted(at: now + 6), "shake boost lasts six seconds")
                    }
                    let previous = field.glyphs
                    field.update(at: now, game: game)
                    // Nothing expires at precisely 18s in this seeded 0.25s-clock check unless its
                    // own lifetime elapsed; boost expiry must not itself remove a live token.
                    if tick == 72 {
                        let lifetime = (300 + FlyingGlyphField.tileHeight / 2 + 28) / FlyingGlyphField.speed
                        let alive = previous.filter { now - $0.born < lifetime }
                        instantRemoval = !Set(alive.map(\.id)).isSubset(of: Set(field.glyphs.map(\.id)))
                    }
                    let keys = field.glyphs.map(\.normalizedKey)
                    duplicate = duplicate || Set(keys).count != keys.count
                    excessive = excessive || field.glyphs.count > 7
                    if now < 12 || now >= 34 { excessive = excessive || field.glyphs.count > 4 }
                    if field.isBoosted(at: now) && field.glyphs.count > 4 { sawBoostDensity = true }
                    if now >= 18 && field.glyphs.count > 4 { sawNaturalRetreat = true }
                    if now <= 20, let desired, keys.contains(desired) { reachedNeeded = true }
                    for glyph in field.glyphs {
                        let point = field.position(of: glyph, at: now)
                        jumped = jumped || field.position(of: glyph, at: now + 0.37).x != point.x
                        outOfBounds = outOfBounds || point.x - 22 < -0.01 || point.x + 22 > width + 0.01
                        if reduced {
                            outOfBounds = outOfBounds || point.y - 24 < -0.01 || point.y + 24 > 300.01
                            if let original = fixedPositions[glyph.id] { jumped = jumped || original != point }
                            fixedPositions[glyph.id] = point
                        }
                        if seenIDs.insert(glyph.id).inserted {
                            births.append(glyph.born); lanes.insert(glyph.lane)
                            horizontalOffsets.insert(Int((glyph.offsetX * 1000).rounded()))
                            invalidBirth = invalidBirth || glyph.born != now
                            if !reduced { invalidBirth = invalidBirth || field.position(of: glyph, at: glyph.born).y != -28 }
                        }
                    }
                    for first in field.glyphs.indices {
                        for second in field.glyphs.indices where second > first {
                            let a = field.position(of: field.glyphs[first], at: now)
                            let b = field.position(of: field.glyphs[second], at: now)
                            overlap = overlap || (abs(a.x - b.x) < 44 && abs(a.y - b.y) < 64 - 0.01)
                        }
                    }
                    if tick == 32, let tapped = field.glyphs.first {
                        let count = field.glyphs.count
                        let nextBirth = field.nextSpawnAt
                        check(field.remove(id: tapped.id) == tapped.text && field.glyphs.count == count - 1, "catch removes exactly the selected token")
                        field.update(at: now, game: game)
                        check(field.glyphs.count == count - 1 && field.nextSpawnAt == nextBirth, "catch does not spawn or reschedule a replacement")
                        check(field.remove(id: tapped.id) == nil, "a second tap cannot remove the same token twice")
                    }
                }
                check(!duplicate, "normalized visible characters remain unique across random seeds and widths")
                check(!overlap && !outOfBounds, "safe lanes and static slots prevent overlap at all sampled times")
                check(!excessive, "normal, boosted and settled density caps remain bounded")
                check(!invalidBirth, "new falling glyphs are born now and offscreen without age jumps")
                check(!jumped && !instantRemoval, "shake and boost expiry preserve live glyph trajectories")
                check(reachedNeeded, "needed character becomes available within a bounded period")
                if field.laneCount > 1 { check(lanes.count > 1, "random births use multiple eligible lanes") }
                check(horizontalOffsets.count > 1, "safe horizontal offsets are randomized once per glyph")
                let ordinaryBirths = births.filter { $0 < 12 }
                let intervals = zip(ordinaryBirths.dropFirst(), ordinaryBirths).map { $0 - $1 }
                check(intervals.allSatisfy { abs($0 - field.normalInterval) <= 0.251 }, "ordinary births keep one fixed beat within the sampling tolerance")
                signatures.insert(births.prefix(5).map(String.init(describing:)).joined(separator: ",") + "-" + horizontalOffsets.sorted().prefix(4).description)
            }
        }
    }
    check(signatures.count > 8, "different random seeds produce different character positions")
    check(sawBoostDensity && sawNaturalRetreat, "boost creates a denser field which naturally settles after expiry")

    var field = FlyingGlyphField(width: 320, height: 300, seed: 9)
    field.update(at: 0, game: game)
    field.update(at: 1000, game: game)
    check(field.glyphs.count <= 1 && field.glyphs.allSatisfy { $0.born == 1000 }, "large elapsed-time jumps cannot dump backdated tokens")
    let resumedIDs = field.glyphs.map(\.id)
    field.update(at: 1000.1, game: game)
    check(field.glyphs.map(\.id) == resumedIDs && field.nextSpawnAt == 1000 + field.normalInterval, "a long jump starts a fresh beat without a second catch-up birth")
    field.reset(at: 1001)
    check(field.glyphs.isEmpty && !field.isBoosted(at: 1001) && field.nextSpawnAt > 1001, "new question clears the old field and schedules a fresh future birth")
    runFlyingCadenceTests(game: game)
}

private func runFlyingCadenceTests(game: FlyingFlowerEngine) {
    check(FlyingGlyphField.speed == 56, "falling speed increases to fifty-six points per second")
    for width in [80.0, 320.0] {
        for height in [80.0, 300.0, 740.0] {
            for reduced in [false, true] {
                var field = FlyingGlyphField(width: width, height: height, reduceMotion: reduced, seed: 42)
                var births: [Double] = []
                var seen: Set<UInt64> = []
                var exceeded = false
                // Deliberately vary the 10 Hz sampling latency to catch accumulated timer drift.
                for tick in 0...600 {
                    let now = Double(tick) * 0.1 + (tick.isMultiple(of: 3) ? 0.017 : 0)
                    field.update(at: now, game: game)
                    exceeded = exceeded || field.glyphs.count > 4
                    for glyph in field.glyphs where seen.insert(glyph.id).inserted { births.append(glyph.born) }
                }
                let intervals = zip(births.dropFirst(), births).map { $0 - $1 }
                let noGaps = intervals.allSatisfy { abs($0 - field.normalInterval) <= 0.118 }
                check(!exceeded && noGaps, "sixty seconds of untouched normal play has no full-cap pauses at any field size")
                if let first = births.first {
                    let deviations = births.enumerated().map { abs($0.element - first - Double($0.offset) * field.normalInterval) }
                    check(deviations.allSatisfy { $0 <= 0.118 }, "normal absolute deadlines do not accumulate sampling drift")
                    let expectedCount = Int((60.017 - first) / field.normalInterval) + 1
                    check(abs(births.count - expectedCount) <= 1, "normal supply remains continuous for a full minute without taps")
                } else { check(false, "normal field emits characters") }
                if height == 300 { check(field.normalInterval == 1.8, "the iPhone field uses one birth every 1.8 seconds") }
            }
        }
    }

    for reduced in [false, true] {
        var field = FlyingGlyphField(width: 320, height: 300, reduceMotion: reduced, seed: 73)
        var births: [Double] = []
        var seen: Set<UInt64> = []
        var densityAfterSettling = 0
        for tick in 0...700 {
            let now = Double(tick) * 0.1
            if tick == 120 { field.shake(at: now) }
            field.update(at: now, game: game)
            for glyph in field.glyphs where seen.insert(glyph.id).inserted { births.append(glyph.born) }
            if now >= 25 { densityAfterSettling = max(densityAfterSettling, field.glyphs.count) }
        }
        let afterBoost = zip(births.dropFirst(), births).filter { $0.0 >= 18 }
        check(afterBoost.allSatisfy { abs(($0.0 - $0.1) - field.normalInterval) <= 0.101 }, "boost returns directly to the ordinary beat without waiting for density to drain")
        let duringBoost = zip(births.dropFirst(), births).filter { $0.0 > 13 && $0.0 < 18 }
        check(!duringBoost.isEmpty && duringBoost.allSatisfy { $0.0 - $0.1 < 1.8 }, "shaking briefly increases birth frequency")
        check(densityAfterSettling <= 4, "normal cadence naturally restores ordinary density after a boost")
    }
}

import Foundation

func runGameWorkshopRegressionTests(content: PoemContent, normalizer: TextNormalizer) {
    let moon = LocalizedText(hant: "月", hans: "月")
    // Identical verses can occur in multiple sources. Every displayed answer must be reachable.
    var game = FeiHuaLingEngine(character: moon, poems: content.poems + content.poems, normalizer: normalizer)
    let singleLibrary = FeiHuaLingEngine(character: moon, poems: content.poems, normalizer: normalizer)
    check(game.validLines.count == singleLibrary.validLines.count, "duplicate corpus entries do not inflate challenge total")
    for line in game.validLines {
        if case .accepted = game.submit(line.text.hant) {} else {
            check(false, "every displayed challenge answer is reachable")
        }
    }
    check(game.isExhausted, "challenge finishes after all distinct verses are submitted")
    check(game.hint() == nil, "completed challenge has no unused hint")
    check(game.entryRounds(count: -1).isEmpty, "negative round count safely produces no rounds")
    check(game.entryRounds(count: 0).isEmpty, "zero round count produces no rounds")
    let blankTarget = FeiHuaLingEngine(character: LocalizedText(hant: "", hans: ""), poems: content.poems, normalizer: normalizer)
    check(blankTarget.validLines.isEmpty, "blank target never matches every verse")

    let words = [ImageryWord("月")]
    let six = PoetWorkshopCheck.check(lines: ["明月照在窗前", "白雲飄過山間"], words: words, normalizer: normalizer)
    check(six.hasLines && six.canSave && !six.evenLength, "six-character writing remains saveable without a five/seven-character checkmark")
    let seven = PoetWorkshopCheck.check(lines: ["一輪明月照窗前", "一片白雲過山間"], words: words, normalizer: normalizer)
    check(seven.evenLength, "seven-character couplet receives the suggested-length checkmark")
    check(PoetWorkshopCheck.suggestedTitle(from: ["「風 吹，黃葉落」"], normalizer: normalizer) == "風吹黃葉", "suggested title ignores punctuation while preserving Traditional characters")
    check(PoetWorkshopContent.exampleLines(for: words, in: content.poems, normalizer: normalizer, limit: 0).isEmpty,
          "zero requested examples returns no examples")
}

import Foundation

func runLanguageRegressionTests() {
    let name = "pumpkin-language-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let settings = AppSettings(defaults: defaults)
    check(settings.script == .hant && settings.voice == .cantonese, "Hong Kong defaults")
    settings.poemScale = 1.2
    settings.applyPresentation(.mandarin)
    check(settings.script == .hans && settings.voice == .mandarin, "Mandarin demo preset")
    check(settings.t("詩庫", "诗库") == "诗库", "Mandarin preset selects simplified UI")
    let restored = AppSettings(defaults: defaults)
    check(restored.script == .hans && restored.voice == .mandarin && restored.poemScale == 1.2, "Language and font settings survive restart")
    restored.applyPresentation(.cantonese)
    check(restored.script == .hant && restored.voice == .cantonese && restored.poemScale == 1.2, "Cantonese preset keeps font preference")
    restored.script = .hans
    let text = LocalizedText(hant: "舉頭望明月", hans: "举头望明月")
    check(restored.t(text) == text.hans && restored.spoken(text) == text.hant, "Cantonese speech remains independent of visible simplified text")
    restored.voice = .mandarin
    restored.script = .hant
    check(restored.t(text) == text.hant && restored.spoken(text) == text.hans, "Mandarin speech remains independent of visible traditional text")
    check(VoiceLanguage.cantonese.accepts(voiceCode: "zh-HK"), "Cantonese zh-HK voice")
    check(VoiceLanguage.cantonese.accepts(voiceCode: "yue-HK"), "Cantonese yue-HK voice")
    check(!VoiceLanguage.cantonese.accepts(voiceCode: "zh-CN"), "Never substitute Mandarin for Cantonese")
    check(!VoiceLanguage.mandarin.accepts(voiceCode: "zh-HK"), "Never substitute Cantonese for Mandarin")
    check(VoiceLanguage.mandarin.accepts(voiceCode: "zh-CN"), "Mandarin zh-CN voice")
    check(!VoiceLanguage.mandarin.accepts(voiceCode: "en-US"), "Never substitute system English voice")

    check(settings.targetGrade == nil && !settings.hasCompletedOnboarding, "first launch waits for grade and language selection")
    check(LearningGrade.allCases.count == 12, "onboarding offers all twelve primary and secondary grades")
    let expectedStages = [1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 4]
    check(LearningGrade.allCases.map(\.keyStage) == expectedStages, "grades map to the source curriculum stages")
    for grade in LearningGrade.allCases {
        restored.completeOnboarding(grade: grade, language: .mandarin)
        let restarted = AppSettings(defaults: defaults)
        check(restarted.hasCompletedOnboarding && restarted.targetGrade == grade,
              "selected grade and completed setup survive restart for \(grade.rawValue)")
        check(restarted.script == .hans && restarted.voice == .mandarin && restarted.poemScale == 1.2,
              "setup saves language without resetting text size")
    }
    restored.targetGrade = .primary2
    restored.applyPresentation(.cantonese)
    let changed = AppSettings(defaults: defaults)
    check(changed.targetGrade == .primary2 && changed.hasCompletedOnboarding,
          "editing grade keeps onboarding complete and persists")
    check(changed.script == .hant && changed.voice == .cantonese,
          "later Cantonese selection restores both display and speech")
}

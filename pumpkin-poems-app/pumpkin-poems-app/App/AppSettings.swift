import Foundation
import Observation

/// School year chosen by the learner; source poems are grouped into four curriculum stages.
nonisolated enum LearningGrade: Int, CaseIterable, Identifiable, Sendable {
    case primary1 = 1, primary2, primary3, primary4, primary5, primary6
    // TODO: Integrate secondary lessons and their study plans when that content is available.
    case secondary1, secondary2, secondary3, secondary4, secondary5, secondary6

    var id: Int { rawValue }
    var keyStage: Int { (rawValue - 1) / 3 + 1 }

    private var year: String { ["一", "二", "三", "四", "五", "六"][(rawValue - 1) % 6] }

    var title: LocalizedText {
        rawValue <= 6
            ? LocalizedText(hant: "小學\(year)年級", hans: "小学\(year)年级")
            : LocalizedText(hant: "中學\(year)年級", hans: "中学\(year)年级")
    }

    var shortTitle: LocalizedText {
        let text = (rawValue <= 6 ? "小" : "中") + year
        return LocalizedText(hant: text, hans: text)
    }
}

/// Spoken language for read-aloud; chosen independently of the text script.
enum VoiceLanguage: String, CaseIterable, Identifiable {
    case cantonese = "zh-HK"
    case mandarin = "zh-CN"

    var id: String { rawValue }

    var preferredScript: Script { self == .cantonese ? .hant : .hans }

    func accepts(voiceCode: String) -> Bool {
        let code = voiceCode.lowercased().replacingOccurrences(of: "_", with: "-")
        switch self {
        case .cantonese: return code == "zh-hk" || code == "zh-hant-hk" || code == "yue" || code.hasPrefix("yue-")
        case .mandarin: return code == "zh-cn" || code == "zh-hans-cn"
        }
    }
}

/// User preferences, persisted in UserDefaults. Hong Kong defaults: Traditional text, Cantonese voice.
@Observable
final class AppSettings {
    private enum Key {
        static let script = "settings.script"
        static let voice = "settings.voice"
        static let poemScale = "settings.poemScale"
        static let targetGrade = "settings.targetGrade"
        static let onboardingCompleted = "settings.onboardingCompleted"
    }

    static let poemScales: [Double] = [0.9, 1.0, 1.2, 1.4]

    @ObservationIgnored private let defaults: UserDefaults

    var script: Script {
        didSet { defaults.set(script.rawValue, forKey: Key.script) }
    }

    var voice: VoiceLanguage {
        didSet { defaults.set(voice.rawValue, forKey: Key.voice) }
    }

    var targetGrade: LearningGrade? {
        didSet {
            if let targetGrade { defaults.set(targetGrade.rawValue, forKey: Key.targetGrade) }
            else {
                defaults.removeObject(forKey: Key.targetGrade)
                hasCompletedOnboarding = false
            }
        }
    }

    private(set) var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.onboardingCompleted) }
    }

    /// Multiplier applied on top of Dynamic Type for poem text.
    var poemScale: Double {
        didSet { defaults.set(poemScale, forKey: Key.poemScale) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        script = defaults.string(forKey: Key.script).flatMap(Script.init(rawValue:)) ?? .hant
        voice = defaults.string(forKey: Key.voice).flatMap(VoiceLanguage.init(rawValue:)) ?? .cantonese
        let scale = defaults.double(forKey: Key.poemScale)
        poemScale = Self.poemScales.contains(scale) ? scale : 1.0
        let grade = LearningGrade(rawValue: defaults.integer(forKey: Key.targetGrade))
        targetGrade = grade
        hasCompletedOnboarding = grade != nil && defaults.bool(forKey: Key.onboardingCompleted)
    }

    /// Picks the UI string for the current script.
    func t(_ hant: String, _ hans: String) -> String {
        script == .hant ? hant : hans
    }

    func t(_ text: LocalizedText) -> String {
        text(script)
    }

    /// One-tap presentation presets; independent controls remain available afterwards.
    func applyPresentation(_ language: VoiceLanguage) {
        script = language.preferredScript
        voice = language
    }

    func completeOnboarding(grade: LearningGrade, language: VoiceLanguage) {
        targetGrade = grade
        applyPresentation(language)
        hasCompletedOnboarding = true
    }

    /// Spoken text follows the voice even when the visible script is set independently.
    func spoken(_ text: LocalizedText) -> String { text(voice.preferredScript) }

    var locale: Locale { Locale(identifier: script == .hant ? "zh_HK" : "zh_CN") }
}

/// The app's notion of "now". Debug builds can shift it by whole days to demo next-day review.
enum AppClock {
    static let dayOffsetKey = "debug.dayOffset"

    static var now: Date {
        #if DEBUG
        let offset = UserDefaults.standard.integer(forKey: dayOffsetKey)
        if offset != 0 {
            return Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        }
        #endif
        return Date()
    }
}

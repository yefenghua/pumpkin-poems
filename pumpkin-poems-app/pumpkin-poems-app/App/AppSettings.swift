import Foundation
import Observation

/// Spoken language for read-aloud; chosen independently of the text script.
enum VoiceLanguage: String, CaseIterable, Identifiable {
    case cantonese = "zh-HK"
    case mandarin = "zh-CN"

    var id: String { rawValue }
}

/// User preferences, persisted in UserDefaults. Hong Kong defaults: Traditional text, Cantonese voice.
@Observable
final class AppSettings {
    private enum Key {
        static let script = "settings.script"
        static let voice = "settings.voice"
        static let poemScale = "settings.poemScale"
    }

    static let poemScales: [Double] = [0.9, 1.0, 1.2, 1.4]

    @ObservationIgnored private let defaults: UserDefaults

    var script: Script {
        didSet { defaults.set(script.rawValue, forKey: Key.script) }
    }

    var voice: VoiceLanguage {
        didSet { defaults.set(voice.rawValue, forKey: Key.voice) }
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
    }

    /// Picks the UI string for the current script.
    func t(_ hant: String, _ hans: String) -> String {
        script == .hant ? hant : hans
    }

    func t(_ text: LocalizedText) -> String {
        text(script)
    }
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

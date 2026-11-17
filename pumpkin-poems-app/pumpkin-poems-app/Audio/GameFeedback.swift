import AVFoundation
import Observation
import SwiftUI
import UIKit

/// Shared game audio, with persistent controls and a quiet bed beneath spoken words.
@MainActor @Observable
final class GameFeedback {
    static let shared = GameFeedback()
    enum Cue: String { case tap, success, error, complete }

    var musicEnabled: Bool { didSet { defaults.set(musicEnabled, forKey: "game.music"); updateMusic() } }
    var effectsEnabled: Bool { didSet { defaults.set(effectsEnabled, forKey: "game.effects") } }
    var hapticsEnabled: Bool { didSet { defaults.set(hapticsEnabled, forKey: "game.haptics") } }
    private(set) var sessionActive = false
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var music: AVAudioPlayer?
    @ObservationIgnored private var effects: [AVAudioPlayer] = []
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var speechActive = false
    @ObservationIgnored private var suspended = false
    @ObservationIgnored private let impact = UIImpactFeedbackGenerator(style: .light)
    @ObservationIgnored private let notification = UINotificationFeedbackGenerator()

    private init() {
        let defaults = UserDefaults.standard
        self.defaults = defaults
        musicEnabled = defaults.object(forKey: "game.music") as? Bool ?? true
        effectsEnabled = defaults.object(forKey: "game.effects") as? Bool ?? true
        hapticsEnabled = defaults.object(forKey: "game.haptics") as? Bool ?? true
        observe(UIApplication.didEnterBackgroundNotification) { $0.suspend() }
        observe(UIApplication.didBecomeActiveNotification) { $0.resume() }
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
                                                               object: nil, queue: .main) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) ?? 0
            let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
            Task { @MainActor [weak self] in
                if type == AVAudioSession.InterruptionType.began.rawValue { self?.suspend() }
                else if AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) { self?.resume() }
            }
        })
    }

    private func observe(_ name: Notification.Name, action: @escaping @MainActor @Sendable (GameFeedback) -> Void) {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in if let self { action(self) } }
        })
    }

    func beginSession() {
        sessionActive = true
        suspended = false
        impact.prepare()
        activateAudio()
        updateMusic()
    }

    func endSession() {
        sessionActive = false
        music?.stop()
        effects.forEach { $0.stop() }
        effects.removeAll()
        if !speechActive { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }

    func speechBegan() { speechActive = true; music?.setVolume(0.045, fadeDuration: 0.1) }

    /// True means game playback still needs the shared audio session.
    @discardableResult func speechEnded() -> Bool {
        speechActive = false
        music?.setVolume(0.18, fadeDuration: 0.25)
        return sessionActive
    }

    func play(_ cue: Cue) {
        if hapticsEnabled {
            switch cue {
            case .tap: impact.impactOccurred(intensity: 0.55); impact.prepare()
            case .success, .complete: notification.notificationOccurred(.success)
            case .error: notification.notificationOccurred(.warning)
            }
        }
        guard effectsEnabled, !suspended else { return }
        effects.removeAll { !$0.isPlaying }
        guard let url = Bundle.main.url(forResource: "game-\(cue.rawValue)", withExtension: "wav"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return }
        activateAudio()
        player.volume = speechActive ? 0.1 : 0.3
        effects.append(player)
        player.play()
    }

    private func activateAudio() {
        if !speechActive { try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers]) }
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func updateMusic() {
        guard sessionActive, musicEnabled, !suspended else { music?.pause(); return }
        if music == nil, let url = Bundle.main.url(forResource: "game-garden", withExtension: "wav") {
            music = try? AVAudioPlayer(contentsOf: url)
            music?.numberOfLoops = -1
            music?.prepareToPlay()
        }
        activateAudio()
        music?.volume = speechActive ? 0.045 : 0.18
        music?.play()
    }

    private func suspend() { suspended = true; music?.pause(); effects.forEach { $0.stop() } }
    private func resume() { suspended = false; updateMusic() }
}

struct GameSoundControls: View {
    @Environment(AppSettings.self) private var settings
    @Bindable private var feedback = GameFeedback.shared

    var body: some View {
        Menu {
            Toggle(settings.t("背景音樂", "背景音乐"), systemImage: "music.note", isOn: $feedback.musicEnabled)
            Toggle(settings.t("音效", "音效"), systemImage: "speaker.wave.2", isOn: $feedback.effectsEnabled)
            Toggle(settings.t("輕震", "轻震"), systemImage: "iphone.radiowaves.left.and.right", isOn: $feedback.hapticsEnabled)
        } label: {
            Image(systemName: feedback.musicEnabled || feedback.effectsEnabled ? "speaker.wave.2" : "speaker.slash")
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel(settings.t("聲音與輕震", "声音与轻震"))
    }
}

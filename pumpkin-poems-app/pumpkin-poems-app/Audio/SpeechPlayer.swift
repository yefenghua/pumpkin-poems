import AVFoundation
import Observation

/// Reads poem lines aloud in Cantonese or Mandarin and reports which line is being read,
/// so the reading page can highlight it.
///
/// Phase 1 uses the system's on-device voices (works offline). Reviewed human recordings
/// for the 12 poems can replace this later without changing callers.
@Observable
final class SpeechPlayer: NSObject, AVSpeechSynthesizerDelegate {
    private(set) var speakingLineID: String?
    private(set) var isSpeaking = false

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var lineIDs: [ObjectIdentifier: String] = [:]
    @ObservationIgnored private var pending = 0

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Languages that have an installed voice. Listing the voices talks to the speech service and takes
    /// over a second on a real device the first time, so it runs once and the answer is kept for the process.
    private static let installedLanguages: Set<String> = Set(AVSpeechSynthesisVoice.speechVoices().map(\.language))

    /// Starts the one-off voice query in the background so the first poem page does not pay for it.
    /// A plain GCD queue, not a Swift concurrency task: the voice list blocks on a sync service call, which
    /// the runtime flags as a structural concurrency issue when it happens on the cooperative pool.
    static func warmUp() {
        DispatchQueue.global(qos: .utility).async { _ = installedLanguages }
    }

    /// Whether the device has a voice for the language; otherwise the system default voice is used.
    static func hasVoice(for language: VoiceLanguage) -> Bool {
        installedLanguages.contains(language.rawValue)
    }

    /// Speaks the given lines in order, replacing anything currently playing.
    func speak(_ lines: [(id: String, text: String)], language: VoiceLanguage) {
        stop()
        activateAudioSession()
        let voice = AVSpeechSynthesisVoice(language: language.rawValue)
        for line in lines {
            let utterance = AVSpeechUtterance(string: line.text)
            utterance.voice = voice
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.8
            utterance.postUtteranceDelay = 0.35
            lineIDs[ObjectIdentifier(utterance)] = line.id
            pending += 1
            synthesizer.speak(utterance)
        }
        isSpeaking = !lines.isEmpty
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        lineIDs.removeAll()
        pending = 0
        speakingLineID = nil
        isSpeaking = false
    }

    private func activateAudioSession() {
        #if os(iOS) || os(visionOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    private func didStart(_ key: ObjectIdentifier) {
        guard let lineID = lineIDs[key] else { return }
        speakingLineID = lineID
    }

    private func didEnd(_ key: ObjectIdentifier) {
        guard lineIDs.removeValue(forKey: key) != nil else { return }
        pending = max(0, pending - 1)
        if pending == 0 {
            speakingLineID = nil
            isSpeaking = false
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let key = ObjectIdentifier(utterance)
        Task { @MainActor in self.didStart(key) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let key = ObjectIdentifier(utterance)
        Task { @MainActor in self.didEnd(key) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let key = ObjectIdentifier(utterance)
        Task { @MainActor in self.didEnd(key) }
    }
}

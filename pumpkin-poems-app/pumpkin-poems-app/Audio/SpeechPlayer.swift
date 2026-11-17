import AVFoundation
import Observation

/// Only the immutable identity crosses executors. Retaining the utterance until the callback
/// is handled prevents its address being reused by a newly queued utterance after stop().
private nonisolated final class SpeechCallbackReference: @unchecked Sendable {
    let key: ObjectIdentifier
    private let retainedUtterance: AVSpeechUtterance

    init(_ utterance: AVSpeechUtterance) {
        key = ObjectIdentifier(utterance)
        retainedUtterance = utterance
    }
}

/// On-device Cantonese / Mandarin playback. Never substitutes another language silently.
@MainActor @Observable
final class SpeechPlayer: NSObject, AVSpeechSynthesizerDelegate {
    enum Problem {
        case missingVoice, audioUnavailable, didNotStart
    }

    private(set) var speakingLineID: String?
    private(set) var isSpeaking = false
    private(set) var isCheckingVoices = false
    private(set) var availableVoices: [AVSpeechSynthesisVoice] = []
    private(set) var completionCount = 0
    private(set) var completedLineIDs: [String] = []
    var lastProblem: Problem?

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var lineIDs: [ObjectIdentifier: String] = [:]
    @ObservationIgnored private var queuedLineIDs: [String] = []
    @ObservationIgnored private var playbackID = UUID()

    override init() {
        super.init()
        synthesizer.delegate = self
        refreshVoices()
    }

    /// Refresh after downloading a voice or returning from system settings.
    func refreshVoices() {
        guard !isCheckingVoices else { return }
        isCheckingVoices = true
        DispatchQueue.global(qos: .utility).async {
            let voices = AVSpeechSynthesisVoice.speechVoices()
            DispatchQueue.main.async { [self] in
                availableVoices = voices
                isCheckingVoices = false
            }
        }
    }

    func voice(for language: VoiceLanguage) -> AVSpeechSynthesisVoice? {
        availableVoices.filter { language.accepts(voiceCode: $0.language) }
            .sorted {
                if $0.quality.rawValue != $1.quality.rawValue { return $0.quality.rawValue > $1.quality.rawValue }
                return $0.identifier < $1.identifier
            }.first
    }

    func hasVoice(for language: VoiceLanguage) -> Bool { voice(for: language) != nil }

    @discardableResult
    func speak(_ lines: [(id: String, text: String)], language: VoiceLanguage) -> Bool {
        stop()
        lastProblem = nil
        let lines = lines.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !lines.isEmpty else { return false }
        guard let voice = voice(for: language) else {
            lastProblem = .missingVoice
            refreshVoices()
            return false
        }
        do {
            #if os(iOS) || os(visionOS)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
        } catch {
            lastProblem = .audioUnavailable
            return false
        }
        queuedLineIDs = lines.map(\.id)
        #if os(iOS)
        GameFeedback.shared.speechBegan()
        #endif
        isSpeaking = true
        let currentPlayback = playbackID
        for line in lines {
            let utterance = AVSpeechUtterance(string: line.text)
            utterance.voice = voice
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.8
            utterance.postUtteranceDelay = 0.35
            lineIDs[ObjectIdentifier(utterance)] = line.id
            synthesizer.speak(utterance)
        }
        // A missing/unusable system voice can otherwise leave the UI playing forever.
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, self.playbackID == currentPlayback, self.isSpeaking,
                  self.speakingLineID == nil else { return }
            self.stop()
            self.lastProblem = .didNotStart
        }
        return true
    }

    func stop() {
        playbackID = UUID()
        // Clear first: delayed callbacks from an old queue must not finish the new playback.
        lineIDs.removeAll()
        queuedLineIDs.removeAll()
        speakingLineID = nil
        isSpeaking = false
        synthesizer.stopSpeaking(at: .immediate)
        deactivateAudioSession()
    }

    private func deactivateAudioSession() {
        #if os(iOS)
        if GameFeedback.shared.speechEnded() { return }
        #endif
        #if os(iOS) || os(visionOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    private func didStart(_ key: ObjectIdentifier) {
        guard let lineID = lineIDs[key] else { return }
        speakingLineID = lineID
    }

    private func didFinish(_ key: ObjectIdentifier) {
        guard lineIDs.removeValue(forKey: key) != nil else { return }
        if lineIDs.isEmpty {
            completedLineIDs = queuedLineIDs
            queuedLineIDs.removeAll()
            completionCount += 1
            speakingLineID = nil
            isSpeaking = false
            deactivateAudioSession()
        }
    }

    private func didCancel(_ key: ObjectIdentifier) {
        guard lineIDs[key] != nil else { return }
        stop()
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let reference = SpeechCallbackReference(utterance)
        Task { @MainActor in self.didStart(reference.key) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let reference = SpeechCallbackReference(utterance)
        Task { @MainActor in self.didFinish(reference.key) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let reference = SpeechCallbackReference(utterance)
        Task { @MainActor in self.didCancel(reference.key) }
    }
}

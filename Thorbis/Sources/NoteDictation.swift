import AVFoundation
@preconcurrency import Speech
import SwiftUI
import UIKit

/// One-tap phrases for the most common field notes. Tapping one adds it to the draft; it never
/// sends. There is no owner-configured template contract yet, so the set lives here, in one place.
enum QuickNotes {
    static let phrases = [
        "Customer not home",
        "Needs part — returning",
        "Photos added",
        "Explained options to customer",
        "Work complete, tested",
    ]
}

/// How dictated or tapped text joins what the technician already typed. Pure so it stays obvious.
enum NoteDraftText {
    /// `prefix` with `addition` after it, separated by one space unless the prefix is empty or
    /// already ends in whitespace. An empty addition leaves the prefix untouched.
    static func joined(_ prefix: String, _ addition: String) -> String {
        let addition = addition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !addition.isEmpty else { return prefix }
        guard let last = prefix.last else { return addition }
        if last.isWhitespace { return prefix + addition }
        // A tapped phrase after a finished sentence reads as a new sentence.
        return prefix + (".!?".contains(last) ? " " : ". ") + addition
    }

    /// The live field while dictating: the text from before the mic was tapped, then the
    /// transcript so far (which the recognizer rewrites as it hears more).
    static func dictated(prefix: String, transcript: String) -> String {
        let transcript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return prefix }
        guard let last = prefix.last else { return transcript }
        return prefix + (last.isWhitespace ? "" : " ") + transcript
    }
}

/// Speech-to-text for the job note composer. On-device recognition when the phone supports it;
/// server recognition only when online. The audio tap and recognizer callbacks run off the main
/// actor (see `DictationEngine`) and hop back here to update the draft.
@MainActor
final class NoteDictation: ObservableObject {
    enum Problem: Equatable {
        case denied
        case needsConnection
        case unavailable
        case failed
        var message: String {
            switch self {
            case .denied: "Dictation needs Microphone and Speech Recognition. Turn them on for Thorbis in Settings."
            case .needsConnection: "Dictation needs a connection on this phone. Type the note, or try again with signal."
            case .unavailable: "Dictation isn't available on this device right now. Type the note instead."
            case .failed: "Dictation stopped. Your note is kept; tap the mic to keep talking."
            }
        }
    }

    @Published private(set) var isListening = false
    @Published var problem: Problem?
    private var engine: DictationEngine?
    private var prefix = ""

    /// Starts listening, asking for microphone and speech access the first time. `update`
    /// receives the whole draft (earlier text plus the live transcript) on the main actor.
    func start(draft: String, isOffline: Bool, update: @escaping @MainActor (String) -> Void) async {
        guard !isListening else { return }
        problem = nil
        guard await Self.authorize() else { problem = .denied; return }
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else { problem = .unavailable; return }
        let onDevice = recognizer.supportsOnDeviceRecognition
        if !onDevice && isOffline { problem = .needsConnection; return }
        prefix = draft
        let engine = DictationEngine()
        do {
            try engine.start(recognizer: recognizer, onDevice: onDevice) { [weak self] transcript, finished, failed in
                Task { @MainActor in
                    guard let self, self.engine === engine else { return }
                    if let transcript { update(NoteDraftText.dictated(prefix: self.prefix, transcript: transcript)) }
                    if failed && transcript == nil { self.problem = .failed }
                    if finished || failed { self.stop() }
                }
            }
        } catch {
            engine.stop()
            problem = .unavailable
            return
        }
        self.engine = engine
        isListening = true
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    /// Stops listening and keeps whatever was heard in the draft.
    func stop() {
        guard let engine else { return }
        self.engine = nil
        engine.stop()
        isListening = false
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    private static func authorize() async -> Bool {
        let speech: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { done in
            let current = SFSpeechRecognizer.authorizationStatus()
            guard current == .notDetermined else { done.resume(returning: current); return }
            SFSpeechRecognizer.requestAuthorization { done.resume(returning: $0) }
        }
        guard speech == .authorized else { return false }
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        default: return await AVAudioApplication.requestRecordPermission()
        }
    }
}

/// Owns the audio engine and recognition task. Deliberately not main-actor isolated: the input
/// tap and recognizer result handler are called on their own queues.
private final class DictationEngine: @unchecked Sendable {
    private let audio = AVAudioEngine()
    private let request = SFSpeechAudioBufferRecognitionRequest()
    private var task: SFSpeechRecognitionTask?

    /// `handler(transcript, isFinal, failed)` is called on a background queue.
    nonisolated func start(recognizer: SFSpeechRecognizer, onDevice: Bool,
                           handler: @escaping @Sendable (String?, Bool, Bool) -> Void) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = onDevice
        request.addsPunctuation = true
        let input = audio.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw DictationError.noInput }
        let request = request
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        audio.prepare()
        try audio.start()
        task = recognizer.recognitionTask(with: request) { result, error in
            handler(result?.bestTranscription.formattedString, result?.isFinal ?? false, error != nil)
        }
    }

    nonisolated func stop() {
        if audio.isRunning { audio.stop() }
        audio.inputNode.removeTap(onBus: 0)
        request.endAudio()
        task?.finish()
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private enum DictationError: Error { case noInput }
}

/// The quiet row of one-tap phrases above the note field.
struct QuickNotesRow: View {
    let insert: (String) -> Void
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(QuickNotes.phrases, id: \.self) { phrase in
                    ThorbisChipToggle(label: phrase, isOn: false) { insert(phrase) }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                        .accessibilityLabel("Add “\(phrase)”")
                        .accessibilityIdentifier("quick-note")
                }
            }
        }
        .scrollClipDisabled()
        .accessibilityLabel("Quick notes")
    }
}

/// The mic beside the note field: a quiet circle, ink while listening.
struct DictateNoteButton: View {
    let isListening: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: isListening ? "stop.fill" : "mic")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(isListening ? Theme.onInk : Theme.foreground)
                .frame(width: 44, height: 44)
                .background(isListening ? Theme.ink : Theme.fill, in: Circle())
                .symbolEffect(.pulse, isActive: isListening)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(isListening ? "Stop dictation" : "Dictate note")
        .accessibilityIdentifier("dictate-note")
    }
}

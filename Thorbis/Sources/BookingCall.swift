import AVFoundation
import SwiftUI

/// JS-05: the call that booked the job. Server contract `GET /v1/jobs/{id}/booking-call`
/// (job.view on the job). The route is dark behind the call_recording feature (403) and answers
/// `{ call: null }` when no call is linked; both mean the section isn't there at all.
struct BookingCallRecord: Decodable, Equatable {
    let id: String
    let status: String
    let callerNumber: String?
    let callerName: String?
    /// The job the office linked this call to; the call log offers to change it.
    let jobId: String?
    let startedAt: String
    let endedAt: String?
    let durationSeconds: Int?
    let recording: Recording
    let summary: Summary?
    let transcript: [Segment]
    let disclosure: String?

    struct Recording: Decodable, Equatable {
        let status: String
        let durationSeconds: Int?
        let contentPath: String?
    }

    struct Summary: Decodable, Equatable {
        let text: String
        let reason: String?
    }

    struct Segment: Decodable, Equatable, Identifiable {
        let sequence: Int
        let speaker: String
        let text: String
        var id: Int { sequence }
        /// The caller, or the business that answered.
        var label: String { speaker == "caller" ? "Caller" : "Office" }
    }

    enum CodingKeys: String, CodingKey {
        case id, status, callerNumber, callerName, jobId, startedAt, endedAt, durationSeconds, recording, summary, transcript, disclosure
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        status = try c.decode(String.self, forKey: .status)
        callerNumber = try c.decodeIfPresent(String.self, forKey: .callerNumber)
        callerName = try c.decodeIfPresent(String.self, forKey: .callerName)
        jobId = try c.decodeIfPresent(String.self, forKey: .jobId)
        startedAt = try c.decode(String.self, forKey: .startedAt)
        endedAt = try c.decodeIfPresent(String.self, forKey: .endedAt)
        durationSeconds = try c.decodeIfPresent(Int.self, forKey: .durationSeconds)
        recording = try c.decode(Recording.self, forKey: .recording)
        summary = try c.decodeIfPresent(Summary.self, forKey: .summary)
        transcript = (try c.decodeIfPresent([Segment].self, forKey: .transcript) ?? []).sorted { $0.sequence < $1.sequence }
        disclosure = try c.decodeIfPresent(String.self, forKey: .disclosure)
    }

    /// "Dana Ruiz", else the number, else "Unknown caller".
    var caller: String {
        if let callerName, !callerName.isEmpty { return callerName }
        if let callerNumber, !callerNumber.isEmpty { return callerNumber }
        return "Unknown caller"
    }

    /// Only a finished recording the server streams from its own calls route is playable.
    var playablePath: String? {
        guard recording.status == "available", let path = recording.contentPath,
              path.range(of: #"^/v1/calls/[0-9A-Fa-f-]{36}/recording$"#, options: .regularExpression) != nil else { return nil }
        return path
    }

    /// What the tech reads instead of a player, in words (JS-11). Nil when there's a player.
    var recordingNote: String? {
        switch status {
        case "missed": return "Missed call. Nothing was recorded."
        case "failed": return "The call dropped. Nothing was recorded."
        case "in_progress": return "The call is still going."
        default: break
        }
        switch recording.status {
        case "pending": return "The recording is still processing."
        case "failed": return "The recording didn't save."
        case "none": return "This call wasn't recorded."
        default: return playablePath == nil ? "The recording isn't available." : nil
        }
    }

    var length: Int? { recording.durationSeconds ?? durationSeconds }

    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

private struct BookingCallEnvelope: Decodable {
    let call: BookingCallRecord?
}

extension APIClient {
    /// Nil when no call is linked, or the feature is off for this workspace (403) or unknown (404).
    func fieldBookingCall(_ jobID: String) async throws -> BookingCallRecord? {
        guard UUID(uuidString: jobID) != nil else { throw Problem(title: "Invalid job ID", status: nil, detail: jobID) }
        do {
            let envelope: BookingCallEnvelope = try await send("GET", "/v1/jobs/\(jobID)/booking-call")
            return envelope.call
        } catch let problem as Problem where problem.status == 403 || problem.status == 404 {
            return nil
        }
    }
}

/// Plays one recording, downloaded once with the session's credentials (the stream is never a
/// public URL). Main actor: the view reads it, and AVAudioPlayer is driven from here only.
@MainActor
final class BookingCallPlayer: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var failed = false
    @Published private(set) var current: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    private var player: AVAudioPlayer?
    private var ticker: Task<Void, Never>?

    func toggle(api: APIClient, path: String) async {
        if let player {
            if player.isPlaying { pause() } else { play(player) }
            return
        }
        isLoading = true
        failed = false
        defer { isLoading = false }
        do {
            let data = try await api.audioData(path)
            let loaded = try AVAudioPlayer(data: data)
            loaded.prepareToPlay()
            player = loaded
            duration = loaded.duration
            play(loaded)
        } catch is CancellationError {
        } catch {
            failed = true
        }
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        player.currentTime = min(max(0, time), player.duration)
        current = player.currentTime
    }

    func stop() {
        player?.stop()
        ticker?.cancel()
        isPlaying = false
    }

    private func play(_ player: AVAudioPlayer) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        if player.currentTime >= player.duration - 0.05 { player.currentTime = 0 }
        player.play()
        isPlaying = true
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, let player = self.player else { return }
                self.current = player.currentTime
                if !player.isPlaying {
                    self.isPlaying = false
                    return
                }
            }
        }
    }

    private func pause() {
        player?.pause()
        ticker?.cancel()
        isPlaying = false
        current = player?.currentTime ?? current
    }
}

/// JS-05: who called and when, what they asked for, the recording and its transcript.
struct JobBookingCallSection: View {
    let call: BookingCallRecord
    var title = "Booking call"
    @EnvironmentObject private var api: APIClient
    @StateObject private var player = BookingCallPlayer()
    @State private var showTranscript = false
    @State private var scrubbing: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaperGroupHeader(title: title)
            VStack(alignment: .leading, spacing: 12) {
                byline
                if let summary = call.summary {
                    Text(summary.text).font(Theme.font(15)).lineSpacing(4).textSelection(.enabled)
                }
                if let path = call.playablePath {
                    playerRow(path)
                    if let disclosure = call.disclosure, !disclosure.isEmpty {
                        Text("Caller heard: \u{201C}\(disclosure)\u{201D}")
                            .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    }
                } else if let note = call.recordingNote {
                    Text(note).font(Theme.font(15)).foregroundStyle(Theme.muted)
                }
                if !call.transcript.isEmpty { transcript }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).stroke(Theme.border))
        }
        .onDisappear { player.stop() }
    }

    private var byline: some View {
        HStack(spacing: 6) {
            Image(systemName: call.status == "missed" ? "phone.arrow.down.left" : "phone.arrow.down.left.fill")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.muted)
                .accessibilityHidden(true)
            Text(call.caller).font(Theme.font(15, weight: .medium))
            if let when = JobFiltering.date(call.startedAt) {
                Text("· \(when.formatted(.dateTime.month(.abbreviated).day().hour().minute()))")
                    .font(Theme.font(15)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
            if let length = call.length {
                Text(BookingCallRecord.clock(length)).font(Theme.monoFont(13)).foregroundStyle(Theme.muted)
                    .accessibilityLabel("\(length / 60) minutes \(length % 60) seconds")
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func playerRow(_ path: String) -> some View {
        let total = max(player.duration, Double(call.length ?? 0), 1)
        let position = scrubbing ?? player.current
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Button { Task { await player.toggle(api: api, path: path) } } label: {
                    ZStack {
                        Circle().fill(Theme.foreground)
                        if player.isLoading {
                            ProgressView().tint(Theme.background)
                        } else {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.background)
                        }
                    }
                    .frame(width: 44, height: 44)
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(player.isPlaying ? "Pause recording" : "Play recording")
                Slider(value: Binding(get: { position }, set: { scrubbing = $0 }), in: 0...total) { editing in
                    if !editing, let scrubbing {
                        player.seek(to: scrubbing)
                        self.scrubbing = nil
                    }
                }
                .tint(Theme.foreground)
                .disabled(player.duration == 0)
                .accessibilityLabel("Recording position")
                .accessibilityValue(BookingCallRecord.clock(Int(position)))
            }
            HStack {
                Text(BookingCallRecord.clock(Int(position)))
                Spacer()
                Text("-" + BookingCallRecord.clock(Int(total - position)))
            }
            .font(Theme.monoFont(12)).foregroundStyle(Theme.muted)
            .padding(.leading, 56)
            .accessibilityHidden(true)
            if player.failed {
                Text("The recording didn't load. Tap play to try again.")
                    .font(Theme.font(13)).foregroundStyle(Theme.warning)
            }
        }
    }

    private var transcript: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withMotion(.snappy) { showTranscript.toggle() } } label: {
                HStack {
                    Text(showTranscript ? "Hide transcript" : "Transcript")
                        .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.brandText)
                    Spacer()
                    Image(systemName: "chevron.down").rotationEffect(.degrees(showTranscript ? 180 : 0))
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.muted)
                }
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showTranscript {
                ForEach(call.transcript) { segment in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(segment.label).font(Theme.font(13, weight: .medium))
                            .foregroundStyle(segment.speaker == "caller" ? Theme.foreground : Theme.muted)
                        Text(segment.text).font(Theme.font(15)).textSelection(.enabled)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

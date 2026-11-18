import AVFoundation
import SwiftUI
import UIKit

// MARK: - Recording playback

/// One recording at a time for a whole thread: starting a second call's recording stops the
/// first. The audio is downloaded once with the session's own credentials (`api.audioData`),
/// so the stream is never a public URL.
@MainActor
final class CommsRecordingPlayer: ObservableObject {
    @Published private(set) var activeID: String?
    @Published private(set) var isPlaying = false
    @Published private(set) var loadingID: String?
    @Published private(set) var failedID: String?
    @Published private(set) var current: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    private var player: AVAudioPlayer?
    private var ticker: Task<Void, Never>?

    func toggle(_ callID: String, path: String, api: APIClient) async {
        if activeID == callID, let player {
            if player.isPlaying { pause() } else { play(player) }
            return
        }
        stop()
        loadingID = callID
        failedID = nil
        defer { loadingID = nil }
        do {
            let data = try await api.audioData(path)
            let loaded = try AVAudioPlayer(data: data)
            loaded.prepareToPlay()
            player = loaded
            activeID = callID
            duration = loaded.duration
            current = 0
            play(loaded)
        } catch is CancellationError {
        } catch {
            failedID = callID
        }
    }

    func seek(_ callID: String, to fraction: Double) {
        guard activeID == callID, let player else { return }
        player.currentTime = min(max(0, fraction), 1) * player.duration
        current = player.currentTime
    }

    func stop() {
        player?.stop()
        ticker?.cancel()
        player = nil
        activeID = nil
        isPlaying = false
        current = 0
        duration = 0
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
                if !player.isPlaying { self.isPlaying = false; return }
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

/// The play control: an ink circle, a thin track you can drag or adjust with VoiceOver, and the
/// times in mono. Thorbis-drawn; no stock slider.
struct CommsRecordingControl: View {
    let callID: String
    let path: String
    let length: Int?
    @ObservedObject var player: CommsRecordingPlayer
    @EnvironmentObject private var api: APIClient

    var body: some View {
        let active = player.activeID == callID
        let total = active && player.duration > 0 ? player.duration : Double(length ?? 0)
        let position = active ? player.current : 0
        let fraction = total > 0 ? min(1, position / total) : 0
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 14) {
                Button { Task { await player.toggle(callID, path: path, api: api) } } label: {
                    ZStack {
                        // Paper 51: the 48pt play circle is the brand's, its glyph white.
                        Circle().fill(Theme.brand)
                        if player.loadingID == callID {
                            ProgressView().tint(Color.white)
                        } else if active && player.isPlaying {
                            Image(systemName: "pause.fill").font(.system(size: 16, weight: .medium)).foregroundStyle(Color.white)
                        } else {
                            PaperIcon(.playSolid, size: 18, color: .white)
                        }
                    }
                    .frame(width: 48, height: 48)
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(active && player.isPlaying ? "Pause recording" : "Play recording")
                .accessibilityIdentifier("inbox-play-\(callID)")
                VStack(spacing: 6) {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.foreground.opacity(0.14)).frame(height: 4)
                            Capsule().fill(Theme.brand).frame(width: max(4, proxy.size.width * fraction), height: 4)
                            Circle().fill(Theme.brand).frame(width: 12, height: 12)
                                .offset(x: max(0, min(proxy.size.width - 12, proxy.size.width * fraction - 6)))
                        }
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle().inset(by: -16))
                        .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                            guard proxy.size.width > 0 else { return }
                            player.seek(callID, to: value.location.x / proxy.size.width)
                        })
                    }
                    .frame(height: 12)
                    .accessibilityElement()
                    .accessibilityLabel("Recording position")
                    .accessibilityValue("\(BookingCallRecord.clock(Int(position))) of \(BookingCallRecord.clock(Int(total)))")
                    .accessibilityAdjustableAction { direction in
                        guard total > 0 else { return }
                        let step = 10 / total
                        player.seek(callID, to: fraction + (direction == .increment ? step : -step))
                    }
                    HStack {
                        Text(BookingCallRecord.clock(Int(position))).foregroundStyle(Theme.subtle)
                        Spacer()
                        Text(BookingCallRecord.clock(Int(total))).foregroundStyle(Theme.muted)
                    }
                    .font(Theme.font(13)).monospacedDigit()
                    .accessibilityHidden(true)
                }
            }
            if player.failedID == callID {
                Text("The recording didn\u{2019}t load. Tap play to try again.")
                    .font(Theme.font(13)).foregroundStyle(Theme.warning)
            }
        }
    }
}

// MARK: - The thread's own menu

/// Star, read, archive and bin for one conversation (web RowActions), as a Thorbis menu in the bar.
struct CommsThreadMenu: View {
    let id: String
    let name: String
    let unread: Bool
    @ObservedObject var store: CommsLocalStore
    var onMoved: () -> Void = {}

    var body: some View {
        let flags = store.flags(id)
        var items = [
            ThorbisMenuItem(flags.starredAt == nil ? "Star" : "Unstar", icon: flags.starredAt == nil ? "star" : "star.slash") { store.toggleStar(id) },
            ThorbisMenuItem(unread ? "Mark read" : "Mark unread", icon: unread ? "envelope.open" : "envelope.badge") { store.setUnread(id, !unread) },
        ]
        if flags.place == .inbox {
            items.append(ThorbisMenuItem("Archive", icon: "archivebox") { if store.archive(id) { onMoved() } })
        } else {
            items.append(ThorbisMenuItem("Move to Inbox", icon: "tray") { store.moveToInbox(id) })
        }
        if flags.place != .bin {
            items.append(ThorbisMenuItem("Move to Bin", icon: "trash", role: .destructive) { if store.bin(id) { onMoved() } })
        }
        return ThorbisMenu(items: items, title: name, accessibilityLabel: "Conversation options") {
            CreamCircleLabel(symbol: "ellipsis")
        }
        .accessibilityIdentifier("inbox-thread-menu")
    }
}

/// The top of a conversation (Paper 49C): the name in 17 Semibold centred between the bar's
/// circles, how to reach them in 13 under it, and where it is filed when that isn't the inbox.
private struct CommsThreadHeader: View {
    let name: String
    let detail: String?
    let place: CommsFolder

    private var line: String {
        var parts: [String] = []
        if let detail, !detail.isEmpty, detail != name { parts.append(detail) }
        if place != .inbox { parts.append("In \(place.title)") }
        return parts.joined(separator: " \u{00B7} ")
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(name).font(Theme.font(17, weight: .semibold)).foregroundStyle(Theme.foreground)
                .lineLimit(1).minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
            if !line.isEmpty {
                Text(line).font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: 220)
        .accessibilityElement(children: .combine)
    }
}

/// Paper 49C's call circle: the phone's dialer for this number, when it has one to dial.
private struct CommsCallCircle: View {
    let url: URL
    let name: String
    @Environment(\.openURL) private var openURL

    /// The dialer link for a number, or nil when there is nothing to dial.
    static func url(_ phone: String?) -> URL? {
        guard let phone, !phone.isEmpty else { return nil }
        return OfficeContact(name: "", phone: phone).callURL
    }

    var body: some View {
        Button { openURL(url) } label: { CreamCircleLabel(symbol: "phone") }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Call \(name)")
    }
}

// MARK: - Call thread

private struct CommsThreadStorageWarning: View {
    var body: some View {
        Text("Couldn't save changes on this device. Copy unsaved work before restarting the app, then check saved messages.")
            .font(Theme.font(14)).foregroundStyle(Theme.foreground)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.gutter).padding(.vertical, 10)
            .background(Theme.canvas)
            .accessibilityIdentifier("inbox-thread-storage-error")
    }
}

/// Every call from one number, newest first (web thread.tsx calls): each a card with when, how
/// long, its status, the recording, what was said, and the job it is linked to.
struct CommsCallThreadView: View {
    let threadID: String
    @ObservedObject var model: CommsInboxModel
    @ObservedObject var local: CommsLocalStore
    @StateObject private var player = CommsRecordingPlayer()
    @EnvironmentObject private var session: SessionController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let thread = model.thread(threadID)
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let thread {
                    // Paper 51's title block: "CALL-0142 · (916) 555-0148" (14 muted) over the
                    // caller (34 Bold, -0.025em), 20 from the edge; the chips sit 14 under it.
                    VStack(alignment: .leading, spacing: 2) {
                        let place = local.flags(threadID).place
                        Text(([thread.calls.first.map { "CALL-\($0.id.suffix(4).uppercased())" },
                               thread.displayNumber == thread.name ? nil : thread.displayNumber,
                               place == .inbox ? nil : "In \(place.title)"] as [String?]).compactMap { $0 }.joined(separator: " \u{00B7} "))
                            .font(Theme.font(14)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(thread.name).font(Theme.font(34, weight: .bold)).tracking(-0.85).foregroundStyle(Theme.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                    }
                    .padding(.horizontal, 4).padding(.top, 2).padding(.bottom, -14)
                    .accessibilityIdentifier("inbox-call-title")
                    ForEach(thread.calls, id: \.id) { call in
                        CommsCallCard(call: call, model: model, player: player,
                                      canLink: session.can("job.edit") && session.can("customer.view"))
                    }
                } else {
                    ListRoomEmpty(title: "These calls aren\u{2019}t in the log anymore", message: "Pull to refresh Messages.")
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .background(Theme.canvas)
        .foregroundStyle(Theme.foreground)
        .safeAreaInset(edge: .top) {
            if local.storageBlocked { CommsThreadStorageWarning() }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let thread {
                if let call = CommsCallCircle.url(thread.number) {
                    ThorbisToolbarItem(placement: .topBarTrailing) {
                        CommsCallCircle(url: call, name: thread.name)
                    }
                }
                ThorbisToolbarItem(placement: .topBarTrailing) {
                    CommsThreadMenu(id: threadID, name: thread.name,
                                    unread: CommsInboxScope.callUnread(thread, flags: local.flags(threadID), seen: model.seenIDs),
                                    store: local) { dismiss() }
                }
            }
        }
        .onAppear {
            if let thread {
                model.markSeen(thread)
                local.clearCallUnread(threadID)
            }
        }
        .onDisappear { player.stop() }
    }
}

struct CommsCallCard: View {
    let call: BookingCallRecord
    @ObservedObject var model: CommsInboxModel
    @ObservedObject var player: CommsRecordingPlayer
    let canLink: Bool
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @State private var showTranscript = false
    @State private var transcriptError: String?
    @State private var choosingJob = false
    @State private var linking = false
    @State private var linkError: String?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let kind = call.kind
        let card = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        // Paper 51: the call's chips, the player on its own card, the summary on the next, then
        // the transcript under its label, and the job it belongs to.
        VStack(alignment: .leading, spacing: 12) {
            chips(kind)
            if let path = call.playablePath {
                VStack(alignment: .leading, spacing: 10) {
                    CommsRecordingControl(callID: call.id, path: path, length: call.length, player: player)
                    if let disclosure = call.disclosure, !disclosure.isEmpty {
                        Text("Caller heard: \u{201C}\(disclosure)\u{201D}").font(Theme.font(13)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(.top, 4)
            } else if let note = call.recordingNote, kind != .missed {
                Text(note).font(Theme.font(14)).foregroundStyle(Theme.muted).padding(.horizontal, 4)
            }
            if let summary = call.summary?.text, !summary.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        PaperIcon(.sparkle, size: 14, color: Theme.brandText)
                        Text(kind == .voicemail ? "Voicemail" : "AI summary").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.brandText)
                    }
                    Text(kind == .voicemail ? "\u{201C}\(summary)\u{201D}" : summary)
                        .font(Theme.font(15)).lineSpacing(3).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: card)
            }
            if hasTranscript { transcript }
            jobRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .sheet(isPresented: $choosingJob) {
            CommsLinkJobSheet(call: call, jobs: CallLogRules.linkableJobs(store.jobs)) { jobID in
                choosingJob = false
                Task { await link(to: jobID) }
            } onClose: { choosingJob = false }
        }
    }

    /// Paper 51's chips, 40 tall: which way the call went (brand at 24%; a missed or dropped call
    /// in the destructive ink), when, and how long.
    private func chips(_ kind: CommsCallKind) -> some View {
        let alarming = kind == .missed || kind == .dropped
        let word: String = switch kind {
        case .answered: "Inbound"
        case .missed: "Missed"
        case .voicemail: "Voicemail"
        case .ongoing: "On the call"
        case .dropped: "Dropped"
        }
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                                                  : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
        return layout {
            HStack(spacing: 6) {
                PaperIcon(.arrowInbound, size: 14, color: alarming ? Theme.destructive : Theme.brandText)
                Text(word).font(Theme.font(14, weight: .semibold)).foregroundStyle(alarming ? Theme.destructive : Theme.brandText)
            }
            .padding(.horizontal, 12).frame(minHeight: 40)
            .background(alarming ? Theme.destructiveSurface : Theme.brandTint, in: Capsule())
            if let when = call.startedDate {
                HStack(spacing: 6) {
                    PaperIcon(.clockSmall, size: 14, color: Theme.muted)
                    Text(Self.stamp(when)).font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.subtle)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12).frame(minHeight: 40)
                .background(Theme.card, in: Capsule())
            }
            if let length = call.length, kind != .missed {
                Text(length >= 60 ? "\(length / 60)m \(length % 60)s" : "\(length)s")
                    .font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.subtle)
                    .padding(.horizontal, 12).frame(minHeight: 40)
                    .background(Theme.card, in: Capsule())
                    .accessibilityLabel("\(length / 60) minutes \(length % 60) seconds")
            }
        }
    }

    /// "Today · 8:42 AM", "Yesterday · 4:27 PM", "Nov 14 · 6:33 PM".
    private static func stamp(_ date: Date, calendar: Calendar = .current) -> String {
        let day = calendar.isDateInToday(date) ? "Today"
            : calendar.isDateInYesterday(date) ? "Yesterday" : date.formatted(.dateTime.month(.abbreviated).day())
        return "\(day) \u{00B7} \(date.tradeTime)"
    }

    private var hasTranscript: Bool {
        guard call.kind != .missed else { return false }
        return !call.transcript.isEmpty || !["none", "failed"].contains(call.transcriptStatus ?? "")
    }

    private var transcript: some View {
        let detail = model.details[call.id]
        let segments = detail?.transcript ?? call.transcript
        return VStack(alignment: .leading, spacing: 0) {
            // Paper 51: "Transcript" as the group's label, how many turns trailing; it opens the card.
            Button {
                withMotion(.snappy) { showTranscript.toggle() }
                if showTranscript && detail == nil { Task { await loadTranscript() } }
            } label: {
                HStack(spacing: 8) {
                    Text(showTranscript ? "Hide transcript" : "Transcript")
                        .font(Theme.font(13, weight: .semibold)).foregroundStyle(showTranscript ? Theme.muted : Theme.brandText)
                    Spacer()
                    if showTranscript && !segments.isEmpty {
                        Text("\(segments.count)").font(Theme.font(13)).foregroundStyle(Theme.muted)
                    }
                    PaperIcon(.chevronDown, size: 12, color: Theme.muted).rotationEffect(.degrees(showTranscript ? 180 : 0))
                }
                .padding(.horizontal, 4)
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            if showTranscript {
                VStack(alignment: .leading, spacing: 14) {
                    if let transcriptError {
                        InlineProblem(message: transcriptError)
                    } else if segments.isEmpty && detail == nil {
                        SkeletonRows(count: 2, leading: false, inset: 0)
                    } else if segments.isEmpty {
                        PaperInlineEmpty("No transcript was kept for this call.")
                    } else {
                        ForEach(segments) { segment in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(segment.label).font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.foreground)
                                Text(segment.text).font(Theme.font(15)).lineSpacing(3).foregroundStyle(Theme.subtle)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            }
        }
    }

    @ViewBuilder private var jobRow: some View {
        let linked = call.jobId.flatMap { id in store.jobs.first { $0.id == id } }
        VStack(alignment: .leading, spacing: 8) {
            if let jobID = call.jobId {
                NavigationLink(value: PaperRoute.job(jobID)) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(linked?.title ?? "Open the linked job").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                                .lineLimit(2)
                            Text("Linked job").font(Theme.font(14)).foregroundStyle(Theme.muted)
                        }
                        Spacer(minLength: 0)
                        PaperRowChevron()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .frame(minHeight: 60).contentShape(Rectangle())
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                }
                .buttonStyle(PressStyle())
                .accessibilityHint("Opens the job this call is linked to")
            }
            if canLink {
                Button { choosingJob = true } label: {
                    HStack(spacing: 6) {
                        if linking { ProgressView() } else { Image(systemName: "link").font(.system(size: 13, weight: .medium)) }
                        Text(call.jobId == nil ? "Link to job" : "Change job")
                    }
                    .paperButton(.secondary, tone: .quiet)
                }
                .buttonStyle(PressStyle())
                .disabled(linking)
                .accessibilityIdentifier("inbox-link-job-\(call.id)")
            }
            if let linkError { InlineProblem(message: linkError) }
        }
    }

    private func loadTranscript() async {
        do {
            _ = try await model.detail(call.id, api: api)
            transcriptError = nil
        } catch is CancellationError {
        } catch {
            transcriptError = error.isConnectivityFailure ? "The transcript needs a connection." : error.localizedDescription
        }
    }

    private func link(to jobID: String?) async {
        linking = true
        defer { linking = false }
        do {
            _ = try await api.linkCall(call.id, jobID: jobID)
            // The link answer has no transcript; re-read the call so the card keeps it.
            model.replace(try await api.call(call.id))
            linkError = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch is CancellationError {
        } catch {
            linkError = (error as? Problem)?.status == 403 ? "Linking needs permission to edit that job." : error.localizedDescription
        }
    }
}

/// The newest jobs on this phone, as web's Link to job menu offers, in a Thorbis sheet.
struct CommsLinkJobSheet: View {
    let call: BookingCallRecord
    let jobs: [Job]
    let onPick: (String?) -> Void
    let onClose: () -> Void

    var body: some View {
        ThorbisSheetScaffold(title: call.jobId == nil ? "Link to job" : "Change job", onClose: onClose) {
            Text("The tech sent to that job hears the call and reads its summary.")
                .font(Theme.font(14)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            if jobs.isEmpty {
                Text("No jobs on this phone yet. Open Jobs once, then come back.")
                    .font(Theme.font(15)).foregroundStyle(Theme.muted)
            } else {
                ThorbisSheetGroup {
                    ForEach(Array(jobs.enumerated()), id: \.element.id) { index, job in
                        if index > 0 { ThorbisSheetDivider() }
                        Button { onPick(job.id) } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(job.title).font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(job.shortRef).font(Theme.monoFont(12)).foregroundStyle(Theme.muted)
                                }
                                Spacer(minLength: 8)
                                if job.id == call.jobId {
                                    Image(systemName: "checkmark").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.foreground)
                                        .accessibilityLabel("Linked")
                                }
                            }
                            .padding(.horizontal, 14).frame(minHeight: 52).contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle())
                    }
                }
            }
            if call.jobId != nil {
                Button { onPick(nil) } label: {
                    Text("Unlink from the job").font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.destructive)
                        .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }
        }
        .thorbisSheetPresentation()
    }
}

// MARK: - Text and email thread

/// A text or email conversation kept on this device (web thread.tsx). Texts get the composer at
/// the bottom; email gets Reply. Nothing here sends: a text saves as a Draft (Queued when given
/// a time) and an email queues, as on the web, because no provider is connected.
struct CommsLocalThreadView: View {
    let threadID: String
    @ObservedObject var store: CommsLocalStore
    @Environment(\.dismiss) private var dismiss
    @State private var mail: CommsMailDraft?
    @State private var recoveredThreadID: String?
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var work: Store
    /// The customer this thread's number belongs to, once the server has matched it. Their open
    /// job is Paper 49C's strip over the conversation.
    @State private var customer: Customer?
    /// The strip's job, pushed by state so it opens from the inbox and from a customer's page alike.
    @State private var openedJobID: String?

    /// The matched customer's open job, if there is one.
    private var linkedJob: Job? {
        customer.flatMap { JobFiltering.customerJobSummary(work.jobs, customerID: $0.id)?.job }
    }

    /// Paper 49C's job strip: the status dot, "AC not cooling · JOB-2214" (15 Semibold) over where
    /// the job stands (13 muted), a chevron. On a card, radius 16, 52 tall, 16 from the edges.
    private func jobStrip(_ job: Job) -> some View {
        let tone = StatusTone(jobStatus: job.status, hasTime: job.scheduledFor != nil)
        let when = JobFiltering.date(job.scheduledFor).map { $0.visitLabel() }
        return Button { openedJobID = job.id } label: {
            HStack(spacing: 10) {
                Circle().fill(tone.hue).frame(width: 8, height: 8).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(job.title) \u{00B7} \(job.shortRef)").font(Theme.font(15, weight: .semibold)).foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    Text([job.status.statusLabel, when].compactMap { $0 }.joined(separator: " \u{00B7} "))
                        .font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                PaperIcon(.chevronRight, size: 16, color: Theme.muted)
            }
            .padding(.horizontal, 14).padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(RowPressStyle())
        .padding(.horizontal, 16).padding(.top, 12)
        .background(Theme.canvas)
        .accessibilityHint("Opens the job")
        .accessibilityIdentifier("inbox-thread-job")
    }

    /// "Today", "Yesterday", "Jul 21", or with its year before this one.
    private func dayLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
            ? date.formatted(.dateTime.month(.abbreviated).day())
            : date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    /// True when this message opens a new day in the conversation (Paper 49C's centred day label).
    private func startsDay(_ index: Int, in messages: [CommsLocalMessage]) -> Date? {
        guard let date = JobFiltering.date(messages[index].at) else { return nil }
        if index > 0, let before = JobFiltering.date(messages[index - 1].at), Calendar.current.isDate(before, inSameDayAs: date) { return nil }
        return date
    }

    var body: some View {
        let thread = store.thread(threadID)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let thread {
                        if thread.messages.isEmpty {
                            Text("No messages yet. What you write below is saved as a draft on this device.")
                                .font(Theme.font(14)).foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(Array(thread.messages.enumerated()), id: \.element.id) { index, message in
                            if thread.channel == .sms, let day = startsDay(index, in: thread.messages) {
                                Text(dayLabel(day)).font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.subtleForeground)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.top, index == 0 ? 0 : 6)
                                    .accessibilityAddTraits(.isHeader)
                            }
                            if message.channel == .email { emailCard(message, thread: thread) } else { bubble(message, thread: thread) }
                        }
                        Color.clear.frame(height: 1).id("end")
                    } else {
                        ListRoomEmpty(title: "This conversation is gone", message: "It may have been discarded on this device.")
                    }
                }
                .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear { proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: thread?.messages.count) { _, _ in withMotion(.snappy) { proxy.scrollTo("end", anchor: .bottom) } }
        }
        .background(Theme.canvas)
        .foregroundStyle(Theme.foreground)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                if store.storageBlocked && thread?.channel == .email { CommsThreadStorageWarning() }
                if thread?.channel == .sms, let job = linkedJob { jobStrip(job) }
            }
        }
        .task(id: thread?.phone) {
            guard let phone = thread?.phone, thread?.channel == .sms else { return }
            if case .found(let match)? = try? await api.lookupCustomer(phone: phone) { customer = match }
            #if DEBUG
            // The design preview has no phone index: its sample thread belongs to the sample customer.
            if PaperPreview.enabled, customer == nil { customer = work.customers.first { $0.name == thread?.contactName } }
            #endif
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let thread {
                ThorbisToolbarItem(placement: .principal) {
                    CommsThreadHeader(name: thread.contactName, detail: thread.channel == .email ? thread.email : thread.phone,
                                      place: thread.flags.place)
                }
                if thread.channel == .sms, let call = CommsCallCircle.url(thread.phone) {
                    ThorbisToolbarItem(placement: .topBarTrailing) {
                        CommsCallCircle(url: call, name: thread.contactName)
                    }
                }
                ThorbisToolbarItem(placement: .topBarTrailing) {
                    CommsThreadMenu(id: threadID, name: thread.contactName, unread: thread.unread, store: store) { dismiss() }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let thread {
                if thread.channel == .sms {
                    CommsTextComposer(thread: thread, store: store)
                } else {
                    PaperActionBar(title: "Reply", symbol: "arrowshape.turn.up.left", identifier: "inbox-email-reply") {
                        mail = CommsMailDraft(threadID: thread.id, to: thread.email ?? "",
                                              subject: CommsMailDraft.reply(thread.subject ?? ""))
                    }
                }
            }
        }
        .sheet(item: $mail) { draft in
            CommsMailSheet(draft: draft, store: store) { id in
                mail = nil
                if id != threadID { recoveredThreadID = id }
            } onClose: { mail = nil }
        }
        .thorbisDestination(item: $recoveredThreadID) { id in
            CommsLocalThreadView(threadID: id, store: store).tabletReadable()
        }
        .thorbisDestination(item: $openedJobID) { JobDetailView(jobId: $0).tabletReadable() }
        .onAppear { if thread?.unread == true { store.setUnread(threadID, false) } }
    }

    private func statusLine(_ message: CommsLocalMessage) -> (tone: StatusTone, word: String)? {
        switch message.status {
        case .received: return nil
        case .draft: return (.unscheduled, "Draft")
        case .queued:
            if let when = JobFiltering.date(message.scheduledAt) { return (.scheduled, "Queued for \(when.stampLabel(year: false))") }
            return (.scheduled, "Queued, not sent")
        }
    }

    private func messageMenu(_ message: CommsLocalMessage, thread: CommsLocalThread) -> [ThorbisMenuItem] {
        var items: [ThorbisMenuItem] = []
        if message.channel == .email && message.status == .draft {
            items.append(ThorbisMenuItem("Edit draft", icon: "pencil") { mail = CommsMailDraft(message: message, threadID: thread.id) })
        }
        if message.status == .queued && message.scheduledAt != nil {
            items.append(ThorbisMenuItem("Cancel schedule", icon: "xmark.circle") { store.cancelScheduled(thread.id, messageID: message.id) })
        }
        if message.status == .draft {
            items.append(ThorbisMenuItem("Discard draft", icon: "trash", role: .destructive) {
                let leaving = thread.channel == .email && thread.messages.count == 1
                if store.discardDraft(thread.id, messageID: message.id), leaving { dismiss() }
            })
        }
        return items
    }

    @ViewBuilder private func bubble(_ message: CommsLocalMessage, thread: CommsLocalThread) -> some View {
        let ours = message.direction == .outbound
        // Paper 49C: theirs on the card, ours on the brand side, each with a 6pt corner toward its
        // side. Nothing here is ever sent (no provider), so ours stays on the brand tint rather
        // than Paper's solid "delivered" blue; a draft adds a dashed rim.
        let draft = ours && message.status == .draft
        let shape = UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: ours ? 18 : 6,
                                           bottomTrailingRadius: ours ? 6 : 18, topTrailingRadius: 18, style: .continuous)
        VStack(alignment: ours ? .trailing : .leading, spacing: 4) {
            Text(message.body).font(Theme.font(16)).lineSpacing(2)
                .foregroundStyle(Theme.foreground)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(ours ? Theme.brandSurface : Theme.card, in: shape)
                .overlay {
                    if draft {
                        shape.strokeBorder(Theme.brand, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                .frame(maxWidth: 280, alignment: ours ? .trailing : .leading)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let status = statusLine(message) { StatusLabel(tone: status.tone, word: status.word, emphasis: .quiet, size: 12) }
                if let when = JobFiltering.date(message.at) {
                    Text(when.tradeTime).font(Theme.font(12)).foregroundStyle(Theme.subtleForeground)
                }
                let items = messageMenu(message, thread: thread)
                if !items.isEmpty {
                    ThorbisMenu(items: items, accessibilityLabel: "Options for this message") {
                        Image(systemName: "ellipsis").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.muted)
                            .frame(width: 44, height: 32).contentShape(Rectangle())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: ours ? .trailing : .leading)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func emailCard(_ message: CommsLocalMessage, thread: CommsLocalThread) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(message.subject ?? thread.subject ?? "(no subject)").font(Theme.font(16, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let when = JobFiltering.date(message.at) {
                    Text(when.stampLabel(year: false)).font(Theme.monoFont(12)).foregroundStyle(Theme.muted)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                if let to = message.to, !to.isEmpty { addressLine("To", to) }
                if let cc = message.cc, !cc.isEmpty { addressLine("Cc", cc) }
                if let bcc = message.bcc, !bcc.isEmpty { addressLine("Bcc", bcc) }
            }
            Text(message.body).font(Theme.font(15)).lineSpacing(3).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
            HStack(spacing: 6) {
                if let status = statusLine(message) { StatusLabel(tone: status.tone, word: status.word, emphasis: .quiet, size: 12) }
                Spacer(minLength: 0)
                let items = messageMenu(message, thread: thread)
                if !items.isEmpty {
                    ThorbisMenu(items: items, accessibilityLabel: "Options for this email") {
                        Image(systemName: "ellipsis").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.muted)
                            .frame(width: 44, height: 32).contentShape(Rectangle())
                    }
                }
            }
            if message.status == .queued {
                Text("No email provider is connected, so this waits in Sent and won\u{2019}t go out.")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private func addressLine(_ label: String, _ addresses: [String]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label).font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
            Text(addresses.joined(separator: ", ")).font(Theme.font(13)).foregroundStyle(Theme.subtle)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The text composer (web thread.tsx Composer): canned replies, a field that grows as you write,
/// Save draft, Schedule draft, and the count in 160-character SMS segments. What you type is kept
/// on this device as you go.
struct CommsTextComposer: View {
    let thread: CommsLocalThread
    @ObservedObject var store: CommsLocalStore
    @State private var body_: String = ""
    @State private var loaded = false
    @State private var scheduling = false
    @State private var managing = false
    @FocusState private var focused: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let ready = !body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let stacked = typeSize.isAccessibilitySize
        // Paper 49C: a 44pt card circle, then the field on a card capsule with the brand send
        // circle inside it; the footnote centred under them.
        VStack(alignment: .leading, spacing: 8) {
            if stacked { capsule(actions: false) }
            HStack(alignment: .bottom, spacing: 8) {
                ThorbisMenu(items: plusItems(ready: ready), title: "Add to this text", accessibilityLabel: "Canned replies and schedule", arrowEdge: .bottom) {
                    CreamCircleLabel(symbol: "plus")
                }
                .accessibilityIdentifier("inbox-canned")
                if stacked {
                    Spacer(minLength: 0)
                    sendButton(ready: ready)
                } else {
                    capsule(actions: true)
                }
            }
            // A footnote, not content: capped so at the largest sizes it doesn't take the room the
            // conversation needs.
            if store.storageBlocked {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Couldn't save this text on your device. Copy it before closing.")
                        .font(Theme.font(13)).foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("inbox-text-storage-error")
                    if !body_.isEmpty {
                        Button("Copy text") { UIPasteboard.general.string = body_ }
                            .inboxQuietAction()
                            .accessibilityIdentifier("inbox-text-copy-unsaved")
                    }
                }
                .padding(.horizontal, 4)
            } else {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Text("Drafts stay on this device").font(Theme.font(12)).foregroundStyle(Theme.muted)
                    if let counter = CommsSMS.counter(body_) {
                        Text(counter).font(Theme.font(12)).monospacedDigit().foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 0)
                }
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 6)
        .background(Theme.background)
        .onAppear {
            guard !loaded else { return }
            body_ = thread.composing ?? ""
            loaded = true
        }
        .onChange(of: body_) { _, value in if loaded { store.setComposing(thread.id, value) } }
        .sheet(isPresented: $scheduling) {
            CommsScheduleSheet { date in
                scheduling = false
                save(date)
            } onClose: { scheduling = false }
        }
        .sheet(isPresented: $managing) { CommsCannedRepliesSheet(store: store) { managing = false } }
    }

    private var field: some View {
        TextField("Message", text: $body_, prompt: .placeholder("Text \(thread.contactName.split(separator: " ").first.map(String.init) ?? thread.contactName)\u{2026}"), axis: .vertical)
            .lineLimit(1...6)
            .font(Theme.font(16))
            .focused($focused)
            .padding(.vertical, 11)
            .frame(minHeight: 44)
            .accessibilityIdentifier("inbox-text-field")
    }

    /// The field on its 48-tall card capsule; with `actions`, Schedule and the send circle sit
    /// inside it at the trailing end.
    private func capsule(actions: Bool) -> some View {
        let ready = !body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(alignment: .bottom, spacing: 2) {
            field
            if actions { sendButton(ready: ready) }
        }
        .padding(.leading, 16).padding(.trailing, actions ? 2 : 16)
        .frame(minHeight: 48)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    /// Paper 49C keeps the field to the words and the send circle, so Schedule draft leads the
    /// plus menu, over the canned replies.
    private func plusItems(ready: Bool) -> [ThorbisMenuItem] {
        [ThorbisMenuItem("Schedule draft", icon: "clock", isDisabled: !ready) { scheduling = true }] + cannedItems
    }

    /// Saves the text as a draft (nothing sends): the brand circle with an up arrow.
    private func sendButton(ready: Bool) -> some View {
        Button { save(nil) } label: {
            Image(systemName: "arrow.up").font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.white)
                .frame(width: 36, height: 36)
                .background(Theme.brand, in: Circle())
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(!ready)
        .opacity(ready ? 1 : 0.4)
        .accessibilityLabel("Save draft")
        .accessibilityIdentifier("inbox-save-draft")
    }

    private var cannedItems: [ThorbisMenuItem] {
        var items = store.cannedReplies.map { reply in
            ThorbisMenuItem(reply.name, subtitle: String(reply.body.prefix(60))) {
                body_ = body_.isEmpty ? reply.body : body_ + " " + reply.body
                focused = true
            }
        }
        if !body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(ThorbisMenuItem("Save as canned reply", icon: "plus") { store.saveCannedReply(name: "", body: body_) })
        }
        items.append(ThorbisMenuItem("Manage canned replies", icon: "slider.horizontal.3") { managing = true })
        return items
    }

    private func save(_ scheduledAt: Date?) {
        guard store.commitText(thread.id, body: body_, scheduledAt: scheduledAt) else { return }
        body_ = ""
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

private struct CommsScheduleSheet: View {
    let onSchedule: (Date) -> Void
    let onClose: () -> Void
    @State private var date = Date().addingTimeInterval(3_600)

    var body: some View {
        ThorbisSheetScaffold(title: "Schedule draft", onClose: onClose) {
            DatePicker("Scheduled time", selection: $date, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.graphical)
                .tint(Theme.foreground)
                .font(Theme.font(15))
            Text("With no messaging provider connected, a scheduled draft holds its time but never sends itself.")
                .font(Theme.font(13)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button { onSchedule(date) } label: { Text("Schedule").inkCommit() }
                .buttonStyle(PressStyle())
        }
        .thorbisSheetPresentation([.large])
    }
}

private struct CommsCannedRepliesSheet: View {
    @ObservedObject var store: CommsLocalStore
    let onClose: () -> Void
    @State private var name = ""
    @State private var text = ""

    var body: some View {
        ThorbisSheetScaffold(title: "Canned replies", onClose: onClose) {
            Text("Saved on this device. Pick one from the composer to drop it into a text.")
                .font(Theme.font(14)).foregroundStyle(Theme.muted)
            if !store.cannedReplies.isEmpty {
                ThorbisSheetGroup {
                    ForEach(Array(store.cannedReplies.enumerated()), id: \.element.id) { index, reply in
                        if index > 0 { ThorbisSheetDivider() }
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(reply.name).font(Theme.font(15, weight: .medium))
                                Text(reply.body).font(Theme.font(14)).foregroundStyle(Theme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            PaperCircleButton(symbol: "trash", label: "Delete \(reply.name)", size: 32, fill: Theme.fill) {
                                store.deleteCannedReply(reply.id)
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                    }
                }
            }
            PaperFormField("New canned reply") {
                VStack(spacing: 8) {
                    TextField("Name", text: $name, prompt: .placeholder("Name")).font(Theme.font(16)).fieldWell()
                        .accessibilityIdentifier("inbox-canned-name")
                    TextField("Reply", text: $text, prompt: .placeholder("What it says"), axis: .vertical)
                        .lineLimit(2...5).font(Theme.font(16)).fieldWell()
                        .accessibilityIdentifier("inbox-canned-reply")
                }
            }
            if store.storageBlocked {
                Text("Couldn't save this reply on your device. Copy it before closing.")
                    .font(Theme.font(14)).foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("inbox-canned-storage-error")
                if !name.isEmpty || !text.isEmpty {
                    Button("Copy reply") {
                        UIPasteboard.general.string = name.isEmpty ? text : "\(name)\n\(text)"
                    }
                    .inboxQuietAction()
                    .accessibilityIdentifier("inbox-canned-copy-unsaved")
                }
            }
            Button {
                if store.saveCannedReply(name: name, body: text) {
                    name = ""
                    text = ""
                }
            } label: { Text("Save reply").inkCommit(enabled: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                .buttonStyle(PressStyle())
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .thorbisSheetPresentation([.large])
    }
}

// MARK: - Starting a conversation

enum CommsComposeKind: String, Identifiable {
    case text, email
    var id: String { rawValue }
}

/// New text: who to text, then the conversation opens with the composer. New email: the mail form.
struct CommsComposeSheet: View {
    let kind: CommsComposeKind
    @ObservedObject var store: CommsLocalStore
    let onOpen: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        switch kind {
        case .email:
            CommsMailSheet(draft: CommsMailDraft(), store: store) { id in onOpen(id) } onClose: { dismiss() }
        case .text:
            CommsNewMessageSheet(store: store, onOpen: onOpen) { dismiss() }
        }
    }
}

/// Paper 49D "New message": who it is to (a customer by name, or a number), the saved replies as
/// templates, and the words. Nothing sends from here: the arrow opens the conversation with the
/// words waiting in its composer, where drafts stay on this phone.
private struct CommsNewMessageSheet: View {
    @ObservedObject var store: CommsLocalStore
    let onOpen: (String) -> Void
    let onClose: () -> Void
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @State private var to = ""
    /// The customer picked from the list; typing in To again lets go of them.
    @State private var picked: CustomerRecord?
    @State private var message = ""
    @State private var customers: [CustomerRecord] = []
    @State private var openFailed = false
    @FocusState private var focus: Field?

    private enum Field { case to, message }

    private var words: String { to.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// The number the conversation opens for: the picked customer's, else a typed number.
    private var phone: String? {
        if let picked { return picked.phone }
        let digits = words.filter(\.isNumber)
        let letters = words.contains { $0.isLetter }
        return !letters && digits.count >= 7 ? words : nil
    }
    private var ready: Bool { CommsCallGrouping.key(phone) != nil }
    private var matches: [CustomerRecord] {
        guard picked == nil, !words.isEmpty else { return [] }
        let digits = words.filter(\.isNumber)
        return Array(customers.lazy.filter { customer in
            if Self.nameRange(customer.name, words) != nil { return true }
            if words.count >= 3, customer.address?.localizedCaseInsensitiveContains(words) == true { return true }
            return digits.count >= 3 && (customer.phone ?? "").filter(\.isNumber).contains(digits)
        }.prefix(6))
    }

    var body: some View {
        VStack(spacing: 0) {
            taskBar
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    toCard.paperCardMargin()
                    if openFailed {
                        Text("Couldn't open this text. Copy any unsaved work before restarting the app, then check saved messages.")
                            .font(Theme.font(14)).foregroundStyle(Theme.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, PaperCardMetrics.margin + 4).padding(.top, 12)
                            .accessibilityIdentifier("inbox-new-text-storage-error")
                    }
                    let found = matches
                    if !found.isEmpty {
                        PaperCardLabel(title: "Customers").padding(.top, 20)
                        PaperRowsCard {
                            ForEach(Array(found.enumerated()), id: \.element.id) { index, customer in
                                if index > 0 { WellDivider(leading: 64) }
                                customerRow(customer)
                            }
                        }
                    }
                    if !store.cannedReplies.isEmpty {
                        PaperCardLabel(title: "Templates").padding(.top, 20)
                        PaperRowsCard {
                            ForEach(Array(store.cannedReplies.enumerated()), id: \.element.id) { index, reply in
                                if index > 0 { WellDivider(leading: 0) }
                                templateRow(reply)
                            }
                        }
                    }
                }
                .padding(.top, 16).padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background.ignoresSafeArea())
        .thorbisSheetPresentation([.large])
        .task {
            if session.can("customer.view", feature: "core_crm") {
                customers = (try? await api.fieldCustomers()) ?? []
            }
            #if DEBUG
            // `--paper-preview-new-text-typed`: Paper 49D's capture, with "M" typed in To.
            if PaperPreview.enabled, ProcessInfo.processInfo.arguments.contains("--paper-preview-new-text-typed") { to = "M" }
            #endif
        }
        // Opened to text someone: who it is to is the first thing to type.
        .task { try? await Task.sleep(for: .milliseconds(400)); if focus == nil { focus = .to } }
    }

    /// Paper's task bar: Cancel on a card pill, the title centred, nothing trailing.
    private var taskBar: some View {
        ZStack {
            Text("New message").font(Theme.font(17, weight: .semibold))
                .lineLimit(1).accessibilityAddTraits(.isHeader)
            HStack {
                Button(action: onClose) {
                    Text("Cancel").font(Theme.font(16, weight: .medium)).lineLimit(1).fixedSize().foregroundStyle(Theme.foreground)
                        .padding(.horizontal, 16).frame(minHeight: 44)
                        .background(Theme.card, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 2)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    /// "To" in the muted ink (16, 44 wide) and the name or number at 17 Medium, 54 tall.
    private var toCard: some View {
        HStack(spacing: 10) {
            Text("To").font(Theme.font(16)).foregroundStyle(Theme.muted)
                .frame(width: 44, alignment: .leading).accessibilityHidden(true)
            TextField("", text: Binding(get: { to }, set: { next in
                if next != to { picked = nil }
                to = next
            }), prompt: .placeholder("Name or phone number"))
                .font(Theme.font(17, weight: .medium))
                .textContentType(.name).autocorrectionDisabled()
                .focused($focus, equals: .to)
                .submitLabel(.next).onSubmit { if ready { focus = .message } }
                .accessibilityLabel("To")
                .accessibilityIdentifier("inbox-new-text-phone")
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    /// 36pt initials on the brand surface, the name (16 Medium, the typed letters heavier) over
    /// the number and street (14 muted), 64 tall. Without a number there is nothing to text.
    private func customerRow(_ customer: CustomerRecord) -> some View {
        let textable = CommsCallGrouping.key(customer.phone) != nil
        let street = customer.address?.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) }
        let line = [textable ? customer.phone : "No phone number", street]
            .compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " \u{00B7} ")
        return Button {
            picked = customer
            to = customer.name
            focus = .message
        } label: {
            HStack(alignment: .center, spacing: 12) {
                PaperInitials(name: customer.name, size: 36)
                VStack(alignment: .leading, spacing: 0) {
                    Text(matchedName(customer.name)).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(line).font(Theme.font(14)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .contentShape(Rectangle())
            .opacity(textable ? 1 : 0.5)
        }
        .buttonStyle(RowPressStyle())
        .disabled(!textable)
        .accessibilityHint(textable ? "" : "No phone number on file")
        .accessibilityIdentifier("inbox-new-text-customer-\(customer.id)")
    }

    /// The name with the typed letters in bold, as Paper marks them.
    private func matchedName(_ name: String) -> AttributedString {
        var marked = AttributedString(name)
        if let found = Self.nameRange(name, words), let range = Range(found, in: marked) {
            marked[range].font = Theme.font(16, weight: .bold)
        }
        return marked
    }

    /// Where the typed letters sit in a name: at the start of one of its words (so "M" finds
    /// Marlowe and Mei, not every name with an m in it); three or more letters match anywhere.
    static func nameRange(_ name: String, _ typed: String) -> Range<String.Index>? {
        guard !typed.isEmpty else { return nil }
        var from = name.startIndex
        while from < name.endIndex,
              let range = name.range(of: typed, options: [.caseInsensitive, .diacriticInsensitive], range: from..<name.endIndex) {
            let startsWord = range.lowerBound == name.startIndex || !name[name.index(before: range.lowerBound)].isLetter
            if startsWord || typed.count >= 3 { return range }
            from = range.upperBound
        }
        return nil
    }

    /// A saved reply: its name (16 Medium) over its words (14 muted). Choosing one writes it.
    private func templateRow(_ reply: CommsCannedReply) -> some View {
        Button {
            message = reply.body
            focus = ready ? .message : .to
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(reply.name).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Text(reply.body).font(Theme.font(14)).foregroundStyle(Theme.muted)
                    .lineLimit(2).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityHint("Writes this in the message")
    }

    /// The words on a 44-tall card capsule and the arrow circle (44): brand once there is someone
    /// to text. It opens the conversation with the words in its composer; nothing is sent.
    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("", text: $message, prompt: .placeholder("Text message"), axis: .vertical)
                .lineLimit(1...4)
                .font(Theme.font(16))
                .focused($focus, equals: .message)
                .padding(.horizontal, 16).padding(.vertical, 11)
                .frame(minHeight: 44)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .accessibilityLabel("Text message")
                .accessibilityIdentifier("inbox-new-text-message")
            Button(action: start) {
                PaperIcon(.arrowUp, size: 18, color: ready ? Color.white : Theme.subtleForeground)
                    .frame(width: 44, height: 44)
                    .background(ready ? Theme.brand : Theme.fill, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(PressStyle())
            .disabled(!ready)
            .accessibilityLabel("Start text")
            .accessibilityHint("Opens the conversation with these words. Nothing is sent.")
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8)
        .background(Theme.background)
    }

    private func start() {
        guard let phone, ready else { return }
        let name = picked?.name ?? ""
        guard let id = store.threadForPhone(phone, contactName: name) else {
            openFailed = true
            return
        }
        openFailed = false
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { store.setComposing(id, text) }
        onOpen(id)
    }
}

private extension PaperGlyph {
    /// Paper 49D's send arrow (18 box).
    static let arrowUp = PaperGlyph(box: 18, [.stroke("M9 14.5V3.5M4.5 8L9 3.5L13.5 8", 1.8)])
}

/// An email being written: a new one, a reply, or a saved draft being edited.
struct CommsMailDraft: Identifiable {
    let id = UUID()
    var threadID: String?
    var messageID: String?
    var to = ""
    var cc = ""
    var bcc = ""
    var subject = ""
    var body = ""

    init(threadID: String? = nil, to: String = "", subject: String = "") {
        self.threadID = threadID
        self.to = to
        self.subject = subject
    }

    init(mail: MailDraft) {
        to = mail.recipients.joined(separator: ", ")
        cc = mail.cc.joined(separator: ", ")
        bcc = mail.bcc.joined(separator: ", ")
        subject = mail.subject ?? ""
        body = mail.body ?? ""
    }

    init(message: CommsLocalMessage, threadID: String) {
        self.threadID = threadID
        messageID = message.id
        to = (message.to ?? []).joined(separator: ", ")
        cc = (message.cc ?? []).joined(separator: ", ")
        bcc = (message.bcc ?? []).joined(separator: ", ")
        subject = message.subject == "(no subject)" ? "" : (message.subject ?? "")
        body = message.body
    }

    static func reply(_ subject: String) -> String {
        subject.isEmpty || subject.lowercased().hasPrefix("re:") ? subject : "Re: \(subject)"
    }

    static func addresses(_ raw: String) -> [String] {
        raw.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == " " || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var mail: CommsLocalStore.Mail {
        .init(to: Self.addresses(to), cc: Self.addresses(cc), bcc: Self.addresses(bcc), subject: subject, body: body)
    }

    /// Explicit recovery copy, including all fields the technician entered.
    var recoveryText: String {
        "To: \(to)\nCc: \(cc)\nBcc: \(bcc)\nSubject: \(subject)\n\n\(body)"
    }
}

/// The email composer (web compose.tsx): To, Cc and Bcc, subject, body. Save draft keeps it on
/// this device; queued messages do not send automatically.
struct CommsMailSheet: View {
    #if DEBUG
    @EnvironmentObject private var session: SessionController
    #endif
    @State var draft: CommsMailDraft
    @ObservedObject var store: CommsLocalStore
    let onSaved: (String) -> Void
    let onClose: () -> Void
    @State private var showCopies = false
    @State private var confirmClose = false
    @State private var saveFailure: CommsLocalStore.MailSaveFailure?
    @State private var mailHandoff: DeviceHandoff?
    @State private var recoveryCandidate: CommsEmailRecovery?
    @State private var recoveryError: String?
    @State private var recoveryLoaded = false
    @State private var recoveryBlocked = false
    @State private var savedThreadAwaitingCleanup: String?
    private let recoveryScope: CommsEmailRecoveryScope?
    private let recoveryCurrent: @MainActor () -> Bool
    private let recoveryStore: CommsEmailRecoveryStoring
    private let original: CommsLocalStore.Mail
    @FocusState private var toFocused: Bool

    init(draft: CommsMailDraft, store: CommsLocalStore, recoveryScope: CommsEmailRecoveryScope? = nil,
         recoveryCurrent: @escaping @MainActor () -> Bool = { true },
         recoveryStore: CommsEmailRecoveryStoring = KeychainCommsEmailRecoveryStore.shared,
         onSaved: @escaping (String) -> Void, onClose: @escaping () -> Void) {
        _draft = State(initialValue: draft)
        self.original = draft.mail
        self.store = store; self.recoveryScope = recoveryScope; self.recoveryCurrent = recoveryCurrent; self.recoveryStore = recoveryStore
        self.onSaved = onSaved
        self.onClose = onClose
    }

    private func recoveryField(_ key: WritableKeyPath<CommsMailDraft, String>) -> Binding<String> {
        Binding(get: { draft[keyPath: key] }, set: { value in
            guard store.isActive, recoveryCurrent(), recoveryCandidate == nil, !recoveryBlocked, savedThreadAwaitingCleanup == nil else { return }
            var next = draft; next[keyPath: key] = value
            if let recoveryScope {
                do { try recoveryStore.save(CommsEmailRecovery(next), scope: recoveryScope); recoveryError = nil }
                catch { recoveryError = "This draft could not be protected. Copy it before leaving this screen." }
            }
            draft = next
        })
    }

    private func removeRecovery() -> Bool {
        guard let recoveryScope else { return true }
        guard store.isActive, recoveryCurrent() else { return false }
        do { try recoveryStore.remove(scope: recoveryScope); return true }
        catch { recoveryError = "The saved recovery copy could not be removed. Try again."; return false }
    }

    private func loadRecovery() {
        guard !recoveryLoaded, store.isActive, recoveryCurrent() else { return }
        recoveryLoaded = true
        guard let recoveryScope else { return }
        do { recoveryCandidate = try recoveryStore.load(scope: recoveryScope); recoveryBlocked = false; recoveryError = nil }
        catch { recoveryBlocked = true; recoveryError = "Saved email recovery could not be checked. Try again before editing." }
    }

    private var hasChanges: Bool { draft.mail != original }
    private var canSave: Bool {
        let mail = draft.mail
        return !mail.to.isEmpty || !mail.cc.isEmpty || !mail.bcc.isEmpty ||
            !mail.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !mail.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var deviceMail: MailDraft? {
        let mail = draft.mail
        return MailDraft(recipients: mail.to, cc: mail.cc, bcc: mail.bcc, subject: mail.subject, body: mail.body)
    }

    var body: some View {
        let ready = !draft.mail.to.isEmpty
        ThorbisSheetScaffold(title: draft.messageID != nil ? "Edit draft" : draft.threadID != nil ? "Reply" : "New email", onClose: requestClose) {
            #if DEBUG
            if PaperPreview.enabled && ProcessInfo.processInfo.arguments.contains("--paper-preview-email-session-replace") {
                Button("Replace email session (test)") { Task { await session.restore() } }
                    .accessibilityIdentifier("inbox-mail-replace-session")
            }
            if PaperPreview.enabled && ProcessInfo.processInfo.arguments.contains("--paper-preview-invalidate-inbox") {
                Button("Invalidate inbox session (test)") { store.invalidate() }
                    .accessibilityIdentifier("inbox-test-invalidate")
            }
            if PaperPreview.enabled && ProcessInfo.processInfo.arguments.contains("--paper-preview-conflict-inbox"),
               let threadID = draft.threadID, let messageID = draft.messageID {
                Button("Remove original draft (test)") { store.discardDraft(threadID, messageID: messageID) }
                    .accessibilityIdentifier("inbox-test-conflict")
            }
            #endif
            if let recoveryCandidate, store.isActive, recoveryCurrent() {
                VStack(alignment: .leading, spacing: 8) {
                    Text("A protected email to \(recoveryCandidate.to) is available. It may be older or already saved; review drafts before sending.")
                        .font(Theme.font(14)).fixedSize(horizontal: false, vertical: true)
                    Button("Restore email draft") {
                        guard store.isActive, recoveryCurrent() else { return }
                        var restored = draft; recoveryCandidate.applying(to: &restored); draft = restored; self.recoveryCandidate = nil
                    }
                    .inboxQuietAction()
                    Button("Discard recovered email", role: .destructive) {
                        if removeRecovery() { self.recoveryCandidate = nil }
                    }
                    .inboxQuietAction(destructive: true)
                }
            }
            if let savedThreadAwaitingCleanup {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your email was saved, but its recovery copy could not be removed. Check drafts before restoring it later.")
                        .font(Theme.font(14)).fixedSize(horizontal: false, vertical: true)
                    Button("Close saved email") { onSaved(savedThreadAwaitingCleanup) }
                        .inboxQuietAction()
                }
            }
            if let recoveryError {
                VStack(alignment: .leading, spacing: 8) {
                    Text(recoveryError).font(Theme.font(14)).foregroundStyle(Theme.warning)
                    if recoveryBlocked {
                        Button("Retry recovery") { recoveryLoaded = false; loadRecovery() }
                            .inboxQuietAction()
                    } else {
                        Button("Copy email") { UIPasteboard.general.string = draft.recoveryText }
                            .inboxQuietAction()
                    }
                }
            }
            PaperFormField("To") {
                TextField("To", text: recoveryField(\.to), prompt: .placeholder("name@example.com"))
                    .keyboardType(.emailAddress).textContentType(.emailAddress).textInputAutocapitalization(.never)
                    .autocorrectionDisabled().font(Theme.font(16)).fieldWell()
                    .focused($toFocused)
                    .accessibilityIdentifier("inbox-mail-to")
                    .disabled(recoveryCandidate != nil || recoveryBlocked || savedThreadAwaitingCleanup != nil)
            }
            if showCopies || !draft.cc.isEmpty || !draft.bcc.isEmpty {
                PaperFormField("Cc") {
                    TextField("Cc", text: recoveryField(\.cc), prompt: .placeholder("Optional"))
                        .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .font(Theme.font(16)).fieldWell()
                        .accessibilityLabel("Cc").accessibilityIdentifier("inbox-mail-cc").disabled(recoveryCandidate != nil || recoveryBlocked || savedThreadAwaitingCleanup != nil)
                }
                PaperFormField("Bcc") {
                    TextField("Bcc", text: recoveryField(\.bcc), prompt: .placeholder("Optional"))
                        .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .font(Theme.font(16)).fieldWell()
                        .accessibilityLabel("Bcc").accessibilityIdentifier("inbox-mail-bcc").disabled(recoveryCandidate != nil || recoveryBlocked || savedThreadAwaitingCleanup != nil)
                }
            } else {
                Button { showCopies = true } label: {
                    Text("Add Cc or Bcc").font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }
            PaperFormField("Subject") {
                TextField("Subject", text: recoveryField(\.subject), prompt: .placeholder("What it\u{2019}s about")).font(Theme.font(16)).fieldWell()
                    .accessibilityLabel("Subject").accessibilityIdentifier("inbox-mail-subject").disabled(recoveryCandidate != nil || recoveryBlocked || savedThreadAwaitingCleanup != nil)
            }
            PaperFormField("Message") {
                TextField("Message", text: recoveryField(\.body), prompt: .placeholder("Write your email"), axis: .vertical)
                    .lineLimit(6...14).font(Theme.font(16)).fieldWell()
                    .accessibilityIdentifier("inbox-mail-body").disabled(recoveryCandidate != nil || recoveryBlocked || savedThreadAwaitingCleanup != nil)
            }
            Text("Send queues it \u{2014} no email provider is connected. Drafts stay on this device.")
                .font(Theme.font(13)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            if let saveFailure {
                VStack(alignment: .leading, spacing: 8) {
                    Text(saveFailure == .storage
                         ? "The save could not be confirmed. Copy your email, reopen the app, and check drafts before trying again."
                         : saveFailure == .recipient ? "Add a recipient before queueing this email."
                         : "This draft or conversation changed. Your text is still here; save a new draft to keep it.")
                        .font(Theme.font(14)).foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                    if saveFailure == .conflict {
                        Button("Save as new draft") { saveSeparateDraft() }
                            .inboxQuietAction()
                            .accessibilityIdentifier("inbox-mail-save-copy")
                    } else if saveFailure == .storage {
                        Button("Copy email") { UIPasteboard.general.string = draft.recoveryText }
                            .inboxQuietAction()
                            .accessibilityIdentifier("inbox-mail-copy-text")
                    }
                }
            }
            VStack(spacing: 4) {
                Button { commit(send: true) } label: { Text("Send").inkCommit(enabled: ready) }
                    .buttonStyle(PressStyle())
                    .disabled(!ready || saveFailure == .storage || recoveryCandidate != nil || recoveryBlocked || savedThreadAwaitingCleanup != nil)
                    .accessibilityHint("Saves the email on this device. It will not send automatically.")
                    .accessibilityIdentifier("inbox-mail-send")
                Button {
                    guard store.isActive, recoveryCurrent(), let mail = deviceMail else { return }
                    mailHandoff = .mail(mail)
                } label: {
                    Text("Send with Mail").font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                        .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .disabled(deviceMail == nil || recoveryCandidate != nil || recoveryBlocked || savedThreadAwaitingCleanup != nil)
                .accessibilityHint("Opens your mail app with this message. Thorbis does not mark it sent.")
                Button { commit(send: false) } label: {
                    Text("Save draft").font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                        .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .disabled(!canSave || saveFailure == .storage || recoveryCandidate != nil || recoveryBlocked || savedThreadAwaitingCleanup != nil)
            }
        }
        .thorbisSheetPresentation([.large])
        .deviceHandoffs($mailHandoff, isCurrent: { store.isActive && recoveryCurrent() })
        .interactiveDismissDisabled(hasChanges && store.isActive)
        .disabled(!store.isActive)
        .onAppear { if !store.isActive { onClose() } else { loadRecovery() } }
        .onChange(of: store.isActive) { _, active in
            if !active { onClose() }
        }
        .thorbisConfirm("Keep your changes?",
                        message: canSave ? "Save this draft on your device or discard your changes." : "Keep editing or discard your changes.",
                        isPresented: $confirmClose, cancelTitle: "Keep editing",
                        actions: (canSave && saveFailure != .storage ? [ThorbisConfirmAction("Save draft") { commit(send: false) }] : [])
                            + [ThorbisConfirmAction("Discard changes", role: .destructive) { if removeRecovery() { onClose() } }])
        // A new email starts at To; a reply or a saved draft already has one.
        .task {
            guard draft.to.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(400))
            toFocused = true
        }
    }

    private func requestClose() {
        if let savedThreadAwaitingCleanup { onSaved(savedThreadAwaitingCleanup); return }
        guard hasChanges else {
            if recoveryCandidate != nil || recoveryBlocked || removeRecovery() { onClose() }
            return
        }
        // The keyboard can cover the confirmation's cancel action on iPhone.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        confirmClose = true
    }

    private func commit(send: Bool) {
        guard saveFailure != .storage, savedThreadAwaitingCleanup == nil, recoveryCurrent() else { return }
        guard let id = store.commitMail(draft.mail, send: send, threadID: draft.threadID, editing: draft.messageID,
                                        expected: draft.messageID == nil ? nil : original) else {
            if store.isActive { saveFailure = store.lastMailSaveFailure ?? .storage }
            return
        }
        if removeRecovery() { onSaved(id) } else { savedThreadAwaitingCleanup = id }
    }

    private func saveSeparateDraft() {
        guard savedThreadAwaitingCleanup == nil, recoveryCurrent(), let id = store.commitMail(draft.mail, send: false) else {
            if store.isActive { saveFailure = store.lastMailSaveFailure ?? .storage }
            return
        }
        if removeRecovery() { onSaved(id) } else { savedThreadAwaitingCleanup = id }
    }
}

private extension View {
    /// The inbox's quiet text action (recovery and copy): 15 Medium in the foreground, 44 tall,
    /// pressed like every other Thorbis text button instead of the system's tinted default.
    func inboxQuietAction(destructive: Bool = false) -> some View {
        font(Theme.font(15, weight: .medium))
            .foregroundStyle(destructive ? Theme.destructive : Theme.foreground)
            .frame(minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
            .buttonStyle(PressStyle())
    }
}

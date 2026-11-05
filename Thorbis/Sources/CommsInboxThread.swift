import AVFoundation
import SwiftUI

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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Button { Task { await player.toggle(callID, path: path, api: api) } } label: {
                    ZStack {
                        Circle().fill(Theme.ink)
                        if player.loadingID == callID {
                            ProgressView().tint(Theme.onInk)
                        } else {
                            Image(systemName: active && player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.onInk)
                        }
                    }
                    .frame(width: 44, height: 44)
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(active && player.isPlaying ? "Pause recording" : "Play recording")
                .accessibilityIdentifier("inbox-play-\(callID)")
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.fill).frame(height: 4)
                        Capsule().fill(Theme.foreground).frame(width: max(4, proxy.size.width * fraction), height: 4)
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                        guard proxy.size.width > 0 else { return }
                        player.seek(callID, to: value.location.x / proxy.size.width)
                    })
                }
                .frame(height: 44)
                .accessibilityElement()
                .accessibilityLabel("Recording position")
                .accessibilityValue("\(BookingCallRecord.clock(Int(position))) of \(BookingCallRecord.clock(Int(total)))")
                .accessibilityAdjustableAction { direction in
                    guard total > 0 else { return }
                    let step = 10 / total
                    player.seek(callID, to: fraction + (direction == .increment ? step : -step))
                }
            }
            HStack {
                Text(BookingCallRecord.clock(Int(position)))
                Spacer()
                Text(BookingCallRecord.clock(Int(total)))
            }
            .font(Theme.monoFont(12)).foregroundStyle(Theme.muted)
            .padding(.leading, 56)
            .accessibilityHidden(true)
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
            items.append(ThorbisMenuItem("Archive", icon: "archivebox") { store.archive(id); onMoved() })
        } else {
            items.append(ThorbisMenuItem("Move to Inbox", icon: "tray") { store.moveToInbox(id) })
        }
        if flags.place != .bin {
            items.append(ThorbisMenuItem("Move to Bin", icon: "trash", role: .destructive) { store.bin(id); onMoved() })
        }
        return ThorbisMenu(items: items, title: name, accessibilityLabel: "Conversation options") {
            PaperCircleLabel(symbol: "ellipsis", size: 36, fill: Theme.card, bordered: true)
        }
        .accessibilityIdentifier("inbox-thread-menu")
    }
}

/// The top of a conversation: who, how to reach them, and where it is filed.
private struct CommsThreadHeader: View {
    let name: String
    let initials: String?
    let symbol: String
    let detail: String?
    let place: CommsFolder
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if !typeSize.isAccessibilitySize { CommsAvatar(initials: initials, symbol: symbol, size: 48) }
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(Theme.font(24, weight: .medium)).tracking(-0.4)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let detail, !detail.isEmpty, detail != name {
                    Text(detail).font(Theme.monoFont(14)).foregroundStyle(Theme.muted).textSelection(.enabled)
                }
                if place != .inbox {
                    Text("In \(place.title)").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Call thread

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
            VStack(alignment: .leading, spacing: 16) {
                if let thread {
                    CommsThreadHeader(name: thread.name, initials: thread.initials, symbol: "phone.fill",
                                      detail: thread.displayNumber, place: local.flags(threadID).place)
                        .padding(.bottom, 4)
                    ForEach(thread.calls, id: \.id) { call in
                        CommsCallCard(call: call, model: model, player: player,
                                      canLink: session.can("job.edit") && session.can("customer.view"))
                    }
                } else {
                    ListRoomEmpty(title: "These calls aren\u{2019}t in the log anymore.", message: "Pull to refresh the Inbox.")
                }
            }
            .padding(.horizontal, Theme.gutter).padding(.vertical, 12)
        }
        .background(Theme.canvas)
        .foregroundStyle(Theme.foreground)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let thread {
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
        let headingLayout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                                                         : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        VStack(alignment: .leading, spacing: 12) {
            headingLayout {
                Image(systemName: kind.symbol).font(.system(size: 13, weight: .medium))
                    .foregroundStyle(kind == .missed || kind == .dropped ? Theme.destructive : Theme.muted)
                    .accessibilityHidden(true)
                Text(kind.heading).font(Theme.font(15, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                if let when = call.startedDate {
                    Text(when.stampLabel(year: false)).font(Theme.monoFont(12)).foregroundStyle(Theme.muted)
                }
            }
            .accessibilityElement(children: .combine)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                StatusLabel(tone: kind.status.tone, word: kind.status.word)
                if let length = call.length, kind != .missed {
                    Text(BookingCallRecord.clock(length)).font(Theme.monoFont(13)).foregroundStyle(Theme.muted)
                        .accessibilityLabel("\(length / 60) minutes \(length % 60) seconds")
                }
            }
            if let summary = call.summary?.text, !summary.isEmpty {
                Text(kind == .voicemail ? "\u{201C}\(summary)\u{201D}" : summary)
                    .font(Theme.font(15)).lineSpacing(3).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let path = call.playablePath {
                CommsRecordingControl(callID: call.id, path: path, length: call.length, player: player)
                if let disclosure = call.disclosure, !disclosure.isEmpty {
                    Text("Caller heard: \u{201C}\(disclosure)\u{201D}").font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if let note = call.recordingNote, kind != .missed {
                Text(note).font(Theme.font(14)).foregroundStyle(Theme.muted)
            }
            if hasTranscript { transcript }
            jobRow
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ThorbisPanelStyle(), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .sheet(isPresented: $choosingJob) {
            CommsLinkJobSheet(call: call, jobs: CallLogRules.linkableJobs(store.jobs)) { jobID in
                choosingJob = false
                Task { await link(to: jobID) }
            } onClose: { choosingJob = false }
        }
    }

    private var hasTranscript: Bool {
        guard call.kind != .missed else { return false }
        return !call.transcript.isEmpty || !["none", "failed"].contains(call.transcriptStatus ?? "")
    }

    private var transcript: some View {
        let detail = model.details[call.id]
        let segments = detail?.transcript ?? call.transcript
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withMotion(.snappy) { showTranscript.toggle() }
                if showTranscript && detail == nil { Task { await loadTranscript() } }
            } label: {
                HStack {
                    Text(showTranscript ? "Hide transcript" : "Transcript")
                        .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                    Spacer()
                    Image(systemName: "chevron.down").rotationEffect(.degrees(showTranscript ? 180 : 0))
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.muted)
                }
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showTranscript {
                if let transcriptError {
                    InlineProblem(message: transcriptError)
                } else if segments.isEmpty && detail == nil {
                    SkeletonRows(count: 2, leading: false, inset: 0)
                } else if segments.isEmpty {
                    Text("No transcript was kept for this call.").font(Theme.font(14)).foregroundStyle(Theme.muted)
                } else {
                    ForEach(segments) { segment in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(segment.label).font(Theme.font(13, weight: .medium))
                                .foregroundStyle(segment.speaker == "caller" ? Theme.foreground : Theme.muted)
                            Text(segment.text).font(Theme.font(15)).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    @ViewBuilder private var jobRow: some View {
        let linked = call.jobId.flatMap { id in store.jobs.first { $0.id == id } }
        VStack(alignment: .leading, spacing: 4) {
            if let jobID = call.jobId {
                NavigationLink(value: PaperRoute.job(jobID)) {
                    HStack(spacing: 6) {
                        Image(systemName: "briefcase").font(.system(size: 13)).foregroundStyle(Theme.muted)
                        Text(linked?.title ?? "Open the linked job").font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                        PaperDisclosure()
                    }
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityHint("Opens the job this call is linked to")
            }
            if canLink {
                Button { choosingJob = true } label: {
                    HStack(spacing: 6) {
                        if linking { ProgressView() } else { Image(systemName: "link").font(.system(size: 13, weight: .medium)) }
                        Text(call.jobId == nil ? "Link to job" : "Change job").font(Theme.font(15, weight: .medium))
                    }
                    .foregroundStyle(Theme.foreground)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                    .contentShape(Rectangle())
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
private struct CommsLinkJobSheet: View {
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

    var body: some View {
        let thread = store.thread(threadID)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let thread {
                        CommsThreadHeader(name: thread.contactName, initials: thread.initials,
                                          symbol: thread.channel == .email ? "envelope.fill" : "bubble.left.fill",
                                          detail: thread.channel == .email ? thread.email : thread.phone, place: thread.flags.place)
                            .padding(.bottom, 6)
                        if thread.messages.isEmpty {
                            Text("No messages yet. What you write below is saved as a draft on this device.")
                                .font(Theme.font(14)).foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(thread.messages) { message in
                            if message.channel == .email { emailCard(message, thread: thread) } else { bubble(message, thread: thread) }
                        }
                        Color.clear.frame(height: 1).id("end")
                    } else {
                        ListRoomEmpty(title: "This conversation is gone.", message: "It may have been discarded on this device.")
                    }
                }
                .padding(.horizontal, Theme.gutter).padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear { proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: thread?.messages.count) { _, _ in withMotion(.snappy) { proxy.scrollTo("end", anchor: .bottom) } }
        }
        .background(Theme.canvas)
        .foregroundStyle(Theme.foreground)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let thread {
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
            CommsMailSheet(draft: draft, store: store) { _ in mail = nil } onClose: { mail = nil }
        }
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
                store.discardDraft(thread.id, messageID: message.id)
                if leaving { dismiss() }
            })
        }
        return items
    }

    @ViewBuilder private func bubble(_ message: CommsLocalMessage, thread: CommsLocalThread) -> some View {
        let ours = message.direction == .outbound
        VStack(alignment: ours ? .trailing : .leading, spacing: 4) {
            Text(message.body).font(Theme.font(16)).lineSpacing(2)
                .foregroundStyle(Theme.foreground)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(ours ? Theme.surface : Theme.fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    if ours {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: 1, dash: message.status == .draft ? [4, 3] : []))
                    }
                }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let status = statusLine(message) { StatusLabel(tone: status.tone, word: status.word, emphasis: .quiet, size: 12) }
                if let when = JobFiltering.date(message.at) {
                    Text(when.tradeTime).font(Theme.monoFont(12)).foregroundStyle(Theme.muted)
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
        .padding(ours ? .leading : .trailing, 40)
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
        .background(ThorbisPanelStyle(), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
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
        VStack(alignment: .leading, spacing: 6) {
            if stacked { field }
            HStack(alignment: .bottom, spacing: 8) {
                ThorbisMenu(items: cannedItems, title: "Canned replies", accessibilityLabel: "Canned replies", arrowEdge: .bottom) {
                    PaperCircleLabel(symbol: "text.bubble", size: 36, fill: Theme.fill)
                }
                .accessibilityIdentifier("inbox-canned")
                if stacked { Spacer(minLength: 0) } else { field }
                Button { scheduling = true } label: {
                    PaperCircleLabel(symbol: "clock", size: 36, fill: Theme.fill)
                }
                .buttonStyle(PressStyle())
                .disabled(!ready)
                .opacity(ready ? 1 : 0.4)
                .accessibilityLabel("Schedule draft")
                Button { save(nil) } label: {
                    Image(systemName: "arrow.up").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.onInk)
                        .frame(width: 36, height: 36)
                        .background(Theme.ink, in: Circle())
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .disabled(!ready)
                .opacity(ready ? 1 : 0.4)
                .accessibilityLabel("Save draft")
                .accessibilityIdentifier("inbox-save-draft")
            }
            // A footnote, not content: capped so at the largest sizes it doesn't take the room the
            // conversation needs.
            HStack {
                Text("Drafts stay on this device").font(Theme.font(12)).foregroundStyle(Theme.muted)
                Spacer(minLength: 8)
                if let counter = CommsSMS.counter(body_) {
                    Text(counter).font(Theme.monoFont(12)).foregroundStyle(Theme.muted)
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 6)
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
        TextField("Message", text: $body_, prompt: .placeholder("Text \(thread.contactName)\u{2026}"), axis: .vertical)
            .lineLimit(1...6)
            .font(Theme.font(16))
            .focused($focused)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .accessibilityIdentifier("inbox-text-field")
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
                    TextField("Reply", text: $text, prompt: .placeholder("What it says"), axis: .vertical)
                        .lineLimit(2...5).font(Theme.font(16)).fieldWell()
                }
            }
            Button {
                store.saveCannedReply(name: name, body: text)
                name = ""
                text = ""
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
    @State private var phone = ""
    @State private var name = ""

    var body: some View {
        switch kind {
        case .email:
            CommsMailSheet(draft: CommsMailDraft(), store: store) { id in onOpen(id) } onClose: { dismiss() }
        case .text:
            ThorbisSheetScaffold(title: "New text", onClose: { dismiss() }) {
                PaperFormField("Phone number") {
                    TextField("Phone number", text: $phone, prompt: .placeholder("(555) 010-0100"))
                        .keyboardType(.phonePad).textContentType(.telephoneNumber).font(Theme.font(16)).fieldWell()
                        .accessibilityIdentifier("inbox-new-text-phone")
                }
                PaperFormField("Name", note: "Optional") {
                    TextField("Name", text: $name, prompt: .placeholder("Who it is")).textContentType(.name).font(Theme.font(16)).fieldWell()
                }
                Text("An existing conversation with this number opens instead of a new one. Drafts stay on this device.")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                let ready = CommsCallGrouping.key(phone) != nil
                Button { onOpen(store.threadForPhone(phone, contactName: name)) } label: {
                    Text("Start text").inkCommit(enabled: ready)
                }
                .buttonStyle(PressStyle())
                .disabled(!ready)
            }
            .thorbisSheetPresentation([.medium, .large])
        }
    }
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
}

/// The email composer (web compose.tsx): To, Cc and Bcc, subject, body. Save draft keeps it on
/// this device; Send queues it, because no email provider is connected.
struct CommsMailSheet: View {
    @State var draft: CommsMailDraft
    @ObservedObject var store: CommsLocalStore
    let onSaved: (String) -> Void
    let onClose: () -> Void
    @State private var showCopies = false

    var body: some View {
        let ready = !draft.mail.to.isEmpty
        ThorbisSheetScaffold(title: draft.messageID != nil ? "Edit draft" : draft.threadID != nil ? "Reply" : "New email", onClose: onClose) {
            PaperFormField("To") {
                TextField("To", text: $draft.to, prompt: .placeholder("name@example.com"))
                    .keyboardType(.emailAddress).textContentType(.emailAddress).textInputAutocapitalization(.never)
                    .autocorrectionDisabled().font(Theme.font(16)).fieldWell()
                    .accessibilityIdentifier("inbox-mail-to")
            }
            if showCopies || !draft.cc.isEmpty || !draft.bcc.isEmpty {
                PaperFormField("Cc") {
                    TextField("Cc", text: $draft.cc, prompt: .placeholder("Optional"))
                        .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .font(Theme.font(16)).fieldWell()
                }
                PaperFormField("Bcc") {
                    TextField("Bcc", text: $draft.bcc, prompt: .placeholder("Optional"))
                        .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .font(Theme.font(16)).fieldWell()
                }
            } else {
                Button { showCopies = true } label: {
                    Text("Add Cc or Bcc").font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }
            PaperFormField("Subject") {
                TextField("Subject", text: $draft.subject, prompt: .placeholder("Subject")).font(Theme.font(16)).fieldWell()
            }
            PaperFormField("Message") {
                TextField("Message", text: $draft.body, prompt: .placeholder("Write your email"), axis: .vertical)
                    .lineLimit(6...14).font(Theme.font(16)).fieldWell()
            }
            Text("Send queues it \u{2014} no email provider is connected. Drafts stay on this device.")
                .font(Theme.font(13)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 4) {
                Button { commit(send: true) } label: { Text("Send").inkCommit(enabled: ready) }
                    .buttonStyle(PressStyle())
                    .disabled(!ready)
                    .accessibilityHint("Queues the email. It won\u{2019}t go out until an email provider is connected.")
                    .accessibilityIdentifier("inbox-mail-send")
                Button { commit(send: false) } label: {
                    Text("Save draft").font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                        .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .disabled(!ready)
            }
        }
        .thorbisSheetPresentation([.large])
    }

    private func commit(send: Bool) {
        guard let id = store.commitMail(draft.mail, send: send, threadID: draft.threadID, editing: draft.messageID) else { return }
        onSaved(id)
    }
}

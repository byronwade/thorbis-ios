import SwiftUI

// The office call log (web Inbox › calls, apps/web features/inbox/server-calls.tsx).
// `GET /v1/calls` needs customer.view across the whole company and the call_recording feature;
// a narrower role gets 403 and sees no Calls tab content, as on the web. Their booking call
// reaches them on the job instead (JS-05).

struct CallLogPage: Decodable {
    let items: [BookingCallRecord]
    let nextCursor: String?
}

extension APIClient {
    func callLog(cursor: String? = nil) async throws -> CallLogPage {
        try await send("GET", "/v1/calls", queryItems: [URLQueryItem(name: "limit", value: "50")], cursor: cursor)
    }

    func call(_ id: String) async throws -> BookingCallRecord {
        try await send("GET", "/v1/calls/\(try Self.callID(id))")
    }

    /// Links the call to the job it booked, or unlinks it with nil. The server checks job.edit.
    func linkCall(_ id: String, jobID: String?) async throws -> BookingCallRecord {
        struct Body: Encodable {
            let jobId: String?
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(jobId, forKey: .jobId)  // null unlinks, so it is always sent
            }
            enum CodingKeys: String, CodingKey { case jobId }
        }
        return try await send("POST", "/v1/calls/\(try Self.callID(id))/link", body: Body(jobId: jobID))
    }

    private static func callID(_ id: String) throws -> String {
        guard UUID(uuidString: id) != nil else { throw Problem(title: "Invalid call ID", status: nil, detail: id) }
        return id.lowercased()
    }
}

enum CallLogRules {
    /// The Calls tab shows for roles that can read the log; the server still decides (403 hides it).
    @MainActor static func available(_ session: SessionController) -> Bool {
        session.can("customer.view", feature: "call_recording")
    }

    /// The newest jobs on this phone, as the web's Link to job menu offers.
    static func linkableJobs(_ jobs: [Job], limit: Int = 20) -> [Job] {
        Array(jobs.sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }.prefix(limit))
    }

    static func detail(_ call: BookingCallRecord) -> String {
        var parts: [String] = []
        if let when = JobFiltering.date(call.startedAt) {
            parts.append(when.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))
        }
        if call.status == "missed" { parts.append("Missed") }
        else if let length = call.length { parts.append(BookingCallRecord.clock(length)) }
        if call.jobId != nil { parts.append("Linked to a job") }
        return parts.joined(separator: " · ")
    }
}

/// The Calls tab inside Inbox: newest first, one row per call.
struct CallLogList: View {
    @EnvironmentObject private var api: APIClient
    @State private var calls: [BookingCallRecord] = []
    @State private var nextCursor: String?
    @State private var loading = false
    @State private var loaded = false
    @State private var denied = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if denied {
                PaperEmptyState(symbol: "phone.badge.waveform", title: "Calls are for the office",
                                message: "The call log needs access to every customer. Calls linked to your jobs show on the job.")
            } else {
                if let error { ErrorBanner(message: error) { await refresh() } }
                if loading && calls.isEmpty && error == nil { SkeletonRows(count: 5) }
                if !calls.isEmpty {
                    // Paper v2: the calls on one card (radius 20), 16 from the edges, a hairline
                    // between rows that starts at the words.
                    let shape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(calls.enumerated()), id: \.element.id) { index, call in
                            if index > 0 { WellDivider(leading: 48) }
                            NavigationLink {
                                CallDetailView(callID: call.id) { updated in
                                    if let index = calls.firstIndex(where: { $0.id == updated.id }) { calls[index] = updated }
                                }
                            } label: { row(call) }
                            .buttonStyle(RowPressStyle())
                        }
                    }
                    .background(Theme.card, in: shape)
                    .clipShape(shape)
                    .padding(.horizontal, 16).padding(.top, 16)
                }
                if nextCursor != nil {
                    Button { Task { await loadMore() } } label: {
                        Text(loading ? "Loading\u{2026}" : "Load older calls")
                            .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                            .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .disabled(loading)
                    .padding(.top, 12)
                }
                if loaded && calls.isEmpty && error == nil {
                    PaperEmptyState(symbol: "phone", title: "No calls yet",
                                    message: "Calls to your business number land here with a recording and a summary.")
                }
            }
        }
        .task { if !loaded { await refresh() } }
    }

    private func row(_ call: BookingCallRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: call.status == "missed" ? "phone.arrow.down.left" : "phone.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(call.status == "missed" ? Theme.warning : Theme.muted)
                .frame(width: 20).padding(.top, 3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(call.caller).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                if let summary = call.summary {
                    Text(summary.text).font(Theme.font(14)).foregroundStyle(Theme.subtle).lineLimit(2)
                }
                Text(CallLogRules.detail(call)).font(Theme.font(14)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            PaperChevron()
                .foregroundStyle(Theme.muted).padding(.top, 4).accessibilityHidden(true)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the call")
    }

    func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false; loaded = true }
        do {
            let page = try await api.callLog()
            calls = page.items
            nextCursor = page.nextCursor
            error = nil
            denied = false
        } catch is CancellationError {
        } catch let problem as Problem where problem.status == 403 || problem.status == 404 {
            denied = true
        } catch {
            self.error = error.isConnectivityFailure ? "The call log needs a connection." : error.localizedDescription
        }
    }

    private func loadMore() async {
        guard !loading, let cursor = nextCursor else { return }
        loading = true
        defer { loading = false }
        do {
            let page = try await api.callLog(cursor: cursor)
            guard page.nextCursor != cursor else {
                throw Problem(title: "Call pagination stopped", status: nil, detail: "The server repeated its cursor.")
            }
            let known = Set(calls.map(\.id))
            calls.append(contentsOf: page.items.filter { !known.contains($0.id) })
            nextCursor = page.nextCursor
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

/// One call: summary, recording, transcript, and the job it booked.
struct CallDetailView: View {
    let callID: String
    var onChange: (BookingCallRecord) -> Void = { _ in }
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController
    @State private var call: BookingCallRecord?
    @State private var error: String?
    @State private var linkError: String?
    @State private var linking = false
    @State private var choosingJob = false
    @StateObject private var player = BookingCallPlayer()
    @State private var scrubbing: Double?

    private var canLink: Bool { session.can("job.edit") }

    var body: some View {
        ScrollView {
            // Paper 51: the caller, its chips, the player on its own card, the summary on the
            // next, then the transcript as a section. The job it booked follows.
            VStack(alignment: .leading, spacing: 0) {
                if let call {
                    header(call)
                    chips(call).padding(.top, 14)
                    playerCard(call).padding(.top, 16)
                    if let summary = call.summary, !summary.text.isEmpty {
                        summaryCard(summary).padding(.top, 12)
                    }
                    if !call.transcript.isEmpty {
                        transcriptSection(call).padding(.top, 22)
                    }
                    jobSection(call).padding(.top, 22)
                } else if let error {
                    ErrorBanner(message: error) { await load() }.padding(.horizontal, -PaperCardMetrics.margin)
                } else {
                    SkeletonRows(count: 4, leading: false, inset: 0)
                }
            }
            .paperCardMargin().padding(.top, 8).padding(.bottom, 24)
        }
        .background(Theme.background)
        .foregroundStyle(Theme.foreground)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let call, canLink {
                // Paper 51's ••• circle: the call's own actions.
                ThorbisToolbarItem(placement: .topBarTrailing) {
                    ThorbisMenu(items: moreItems(call), title: call.caller, accessibilityLabel: "Call options") {
                        CreamCircleLabel(symbol: "ellipsis")
                    }
                }
            }
        }
        .refreshable { await load() }
        .task { await load() }
        .onDisappear { player.stop() }
    }

    private func moreItems(_ call: BookingCallRecord) -> [ThorbisMenuItem] {
        var items = [ThorbisMenuItem(call.jobId == nil ? "Link to job" : "Change job", icon: "link") { choosingJob = true }]
        if call.jobId != nil {
            items.append(ThorbisMenuItem("Unlink", icon: "xmark.circle", role: .destructive) {
                Task { await link(call, to: nil) }
            })
        }
        return items
    }

    /// Paper 51: a quiet 14 line (the number, when a name leads), then the caller in 34 Bold.
    private func header(_ call: BookingCallRecord) -> some View {
        let named = !(call.callerName ?? "").isEmpty
        let number: String? = named ? call.callerNumber.map { CommsCallGrouping.display($0) } : nil
        return VStack(alignment: .leading, spacing: 2) {
            if let number, !number.isEmpty {
                Text(number).font(Theme.font(14)).monospacedDigit().foregroundStyle(Theme.muted)
            }
            Text(call.caller).font(Theme.font(34, weight: .bold)).tracking(-0.85)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.horizontal, Theme.gutter - PaperCardMetrics.margin).padding(.top, 6)
        .accessibilityElement(children: .combine)
    }

    /// Paper 51's chips: which way the call went (on the brand tint), when, and how long. 40 tall.
    private func chips(_ call: BookingCallRecord) -> some View {
        let missed = call.status == "missed"
        let outbound = call.direction == "outbound"
        let word = missed ? "Missed" : (outbound ? "Outbound" : "Inbound")
        let symbol = outbound ? "arrow.up.right" : "arrow.down.left"
        let started = JobFiltering.date(call.startedAt)
        let length: Int? = missed ? nil : call.length
        return FlowRow(spacing: 8, lineSpacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).accessibilityHidden(true)
                Text(word).font(Theme.font(14, weight: .semibold))
            }
            .foregroundStyle(missed ? Theme.destructive : Theme.brandText)
            .padding(.horizontal, 12).frame(minHeight: 40)
            .background(missed ? Theme.destructiveSurface : Theme.brandSurface, in: Capsule())
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(word) call")
            if let started {
                HStack(spacing: 6) {
                    Image(systemName: "clock").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted)
                        .accessibilityHidden(true)
                    Text(Calendar.current.isDateInToday(started) ? "Today \u{00B7} \(started.tradeTime)" : started.stampLabel(year: false))
                        .font(Theme.font(14, weight: .medium)).monospacedDigit().foregroundStyle(Theme.subtle)
                }
                .padding(.horizontal, 12).frame(minHeight: 40)
                .background(Theme.card, in: Capsule())
                .accessibilityElement(children: .combine)
            }
            if let length {
                Text("\(length / 60)m \(length % 60)s")
                    .font(Theme.font(14, weight: .medium)).monospacedDigit().foregroundStyle(Theme.subtle)
                    .padding(.horizontal, 12).frame(minHeight: 40)
                    .background(Theme.card, in: Capsule())
                    .accessibilityLabel("\(length / 60) minutes \(length % 60) seconds")
            }
        }
    }

    /// Paper 51's player: the 48pt brand play circle, the track with its times under it, and the
    /// speed pill, on one card (radius 22). A call with nothing to play says why instead.
    private func playerCard(_ call: BookingCallRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let path = call.playablePath {
                let total = max(player.duration, Double(call.length ?? 0), 1)
                let position = scrubbing ?? player.current
                HStack(alignment: .center, spacing: 14) {
                    Button { Task { await player.toggle(api: api, path: path) } } label: {
                        ZStack {
                            Circle().fill(Theme.brand)
                            if player.isLoading {
                                ProgressView().tint(Color.white)
                            } else {
                                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 17, weight: .medium)).foregroundStyle(Color.white)
                            }
                        }
                        .frame(width: 48, height: 48)
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel(player.isPlaying ? "Pause recording" : "Play recording")
                    VStack(alignment: .leading, spacing: 2) {
                        Slider(value: Binding(get: { position }, set: { scrubbing = $0 }), in: 0...total) { editing in
                            if !editing, let scrubbing {
                                player.seek(to: scrubbing)
                                self.scrubbing = nil
                            }
                        }
                        .tint(Theme.brand)
                        .disabled(player.duration == 0)
                        .accessibilityLabel("Recording position")
                        .accessibilityValue(BookingCallRecord.clock(Int(position)))
                        HStack {
                            Text(BookingCallRecord.clock(Int(position))).foregroundStyle(Theme.subtle)
                            Spacer(minLength: 8)
                            Text(BookingCallRecord.clock(Int(total))).foregroundStyle(Theme.muted)
                        }
                        .font(Theme.font(13)).monospacedDigit()
                        .accessibilityHidden(true)
                    }
                    Button { player.cycleRate() } label: {
                        Text(player.rateLabel).monospacedDigit().paperButton(.secondary, tone: .quiet)
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Playback speed")
                    .accessibilityValue(player.rateLabel)
                }
                if player.failed {
                    Text("The recording didn't load. Tap play to try again.")
                        .font(Theme.font(13)).foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let disclosure = call.disclosure, !disclosure.isEmpty {
                    Text("Caller heard: \u{201C}\(disclosure)\u{201D}")
                        .font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(call.recordingNote ?? "The recording isn't available.")
                    .font(Theme.font(15)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// Paper 51: "AI summary" in the brand's words colour over what was said, on its own card.
    /// A summary the model didn't write is labelled "Summary".
    private func summaryCard(_ summary: BookingCallRecord.Summary) -> some View {
        let model = summary.source == "model"
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if model {
                    Image(systemName: "sparkles").font(.system(size: 12, weight: .semibold)).accessibilityHidden(true)
                }
                Text(model ? "AI summary" : "Summary").font(Theme.font(13, weight: .semibold))
            }
            .foregroundStyle(model ? Theme.brandText : Theme.muted)
            .accessibilityAddTraits(.isHeader)
            Text(summary.text).font(Theme.font(15)).lineSpacing(3).foregroundStyle(Theme.foreground)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    /// Paper 51: "Transcript" with how many turns, then every turn on one card: who spoke in
    /// 14 Semibold, what they said in 15 under it.
    private func transcriptSection(_ call: BookingCallRecord) -> some View {
        PaperSection("Transcript", count: call.transcript.count) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(call.transcript) { segment in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(segment.label).font(Theme.font(14, weight: .semibold)).foregroundStyle(Theme.foreground)
                        Text(segment.text).font(Theme.font(15)).lineSpacing(3).foregroundStyle(Theme.subtle)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(6)
        }
    }

    private func jobSection(_ call: BookingCallRecord) -> some View {
        let linked = call.jobId.flatMap { id in store.jobs.first { $0.id == id } }
        return PaperSection("Job") {
            if let jobID = call.jobId {
                NavigationLink(value: PaperRoute.job(jobID)) {
                    PaperDetailRow(label: "Booked") {
                        HStack(spacing: 4) {
                            Text(linked?.title ?? "Open job").foregroundStyle(Theme.foreground)
                            PaperDisclosure()
                        }
                    }
                    .padding(.horizontal, PaperCardMetrics.inset).frame(minHeight: 52)
                }
                .buttonStyle(RowPressStyle())
            } else {
                Text("Link the call to the job it booked, so the tech sent there hears it and reads the summary.")
                    .font(Theme.font(15)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 14)
            }
            if canLink {
                WellDivider()
                linkMenu(call)
            }
            if let linkError {
                InlineProblem(message: linkError)
                    .padding(.horizontal, PaperCardMetrics.inset).padding(.bottom, 12)
            }
        }
    }

    /// A button that opens a scrolling list: twenty jobs don't fit a menu card on a phone.
    private func linkMenu(_ call: BookingCallRecord) -> some View {
        Button { choosingJob = true } label: {
            HStack(spacing: 8) {
                if linking { ProgressView() } else { Image(systemName: "link").accessibilityHidden(true) }
                Text(call.jobId == nil ? "Link to job" : "Change job")
                Spacer(minLength: 0)
            }
            .font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.brandText)
            .padding(.horizontal, PaperCardMetrics.inset)
            .frame(maxWidth: .infinity, minHeight: 52).contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .disabled(linking || (store.jobs.isEmpty && call.jobId == nil))
        .sheet(isPresented: $choosingJob) { jobPicker(call) }
    }

    /// The same Thorbis sheet the Inbox's call card opens: the newest jobs on one group, the
    /// linked one checked, and "Unlink from the job" under it.
    private func jobPicker(_ call: BookingCallRecord) -> some View {
        CommsLinkJobSheet(call: call, jobs: CallLogRules.linkableJobs(store.jobs), onPick: { jobID in
            choosingJob = false
            Task { await link(call, to: jobID) }
        }, onClose: { choosingJob = false })
    }

    private func load() async {
        do {
            call = try await api.call(callID)
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.isConnectivityFailure ? "This call needs a connection to open." : error.localizedDescription
        }
    }

    private func link(_ current: BookingCallRecord, to jobID: String?) async {
        linking = true
        defer { linking = false }
        do {
            _ = try await api.linkCall(current.id, jobID: jobID)
            // The link answer has no transcript; re-read the call so the screen keeps it.
            let updated = try await api.call(current.id)
            call = updated
            linkError = nil
            onChange(updated)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch is CancellationError {
        } catch {
            linkError = (error as? Problem)?.status == 403
                ? "Linking needs permission to edit that job." : error.localizedDescription
        }
    }
}

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
                ForEach(calls, id: \.id) { call in
                    NavigationLink {
                        CallDetailView(callID: call.id) { updated in
                            if let index = calls.firstIndex(where: { $0.id == updated.id }) { calls[index] = updated }
                        }
                    } label: { row(call) }
                    .buttonStyle(PressStyle())
                }
                if nextCursor != nil {
                    Button("Load older calls") { Task { await loadMore() } }
                        .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.brandText)
                        .frame(maxWidth: .infinity, minHeight: 44).disabled(loading)
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
            VStack(alignment: .leading, spacing: 3) {
                Text(call.caller).font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                if let summary = call.summary {
                    Text(summary.text).font(Theme.font(13)).foregroundStyle(Theme.foreground).lineLimit(2)
                }
                Text(CallLogRules.detail(call)).font(Theme.font(13)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.muted).padding(.top, 4).accessibilityHidden(true)
        }
        .padding(.horizontal, Theme.gutter).padding(.vertical, 10)
        .frame(minHeight: 52)
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

    private var canLink: Bool { session.can("job.edit") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let call {
                    JobBookingCallSection(call: call, title: "Call")
                    jobSection(call)
                } else if let error {
                    ErrorBanner(message: error) { await load() }.padding(.horizontal, -Theme.gutter)
                } else {
                    SkeletonRows(count: 4, leading: false, inset: 0)
                }
            }
            .padding(.horizontal, Theme.gutter).padding(.vertical, 12)
        }
        .background(Theme.background)
        .foregroundStyle(Theme.foreground)
        .navigationTitle(call?.caller ?? "Call")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func jobSection(_ call: BookingCallRecord) -> some View {
        let linked = call.jobId.flatMap { id in store.jobs.first { $0.id == id } }
        return VStack(alignment: .leading, spacing: 0) {
            PaperGroupHeader(title: "Job")
            if let jobID = call.jobId {
                NavigationLink(value: PaperRoute.job(jobID)) {
                    PaperDetailRow(label: "Booked") {
                        HStack(spacing: 4) {
                            Text(linked?.title ?? "Open job").foregroundStyle(Theme.foreground)
                            PaperDisclosure()
                        }
                    }
                }
            } else {
                Text("Link the call to the job it booked, so the tech sent there hears it and reads the summary.")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted).padding(.vertical, 6)
            }
            if canLink { linkMenu(call) }
            if let linkError { InlineProblem(message: linkError) }
        }
    }

    private func linkMenu(_ call: BookingCallRecord) -> some View {
        let jobs = CallLogRules.linkableJobs(store.jobs)
        var items = jobs.map { job in
            ThorbisMenuItem(job.title, icon: "wrench.and.screwdriver", isSelected: job.id == call.jobId) {
                Task { await link(call, to: job.id) }
            }
        }
        if call.jobId != nil {
            items.append(ThorbisMenuItem("Unlink", icon: "link.badge.plus", role: .destructive) {
                Task { await link(call, to: nil) }
            })
        }
        return ThorbisMenu(items: items, title: "Link to job", accessibilityLabel: call.jobId == nil ? "Link to job" : "Change job") {
            HStack(spacing: 6) {
                if linking { ProgressView() } else { Image(systemName: "link") }
                Text(call.jobId == nil ? "Link to job" : "Change job")
            }
            .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.brandText)
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .disabled(linking || (jobs.isEmpty && call.jobId == nil))
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

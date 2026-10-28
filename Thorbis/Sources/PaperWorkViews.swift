import SwiftUI
import UIKit

func statusIcon(_ status: String) -> (String, Color) {
    switch status {
    case "completed": ("checkmark.circle.fill", Theme.success)
    case "in_progress", "arrived": ("circle.lefthalf.filled", Theme.warning)
    case "paused": ("pause.circle", Theme.warning)
    case "en_route": ("arrow.right.circle", Theme.brandText)
    case "dispatched": ("circle.dashed", Theme.brandText)
    case "canceled": ("xmark.circle", Theme.muted)
    default: ("circle", Theme.muted)
    }
}

/// How a job is shared in words: what, who and when, never an internal ID.
enum JobShareText {
    static func text(title: String, customer: String, scheduledFor: String?) -> String {
        var parts = [title, customer]
        if let date = JobFiltering.date(scheduledFor) {
            parts.append(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
        }
        return parts.joined(separator: " · ")
    }
}

extension View {
    /// design.thorbis.com MA-12: a job row's common actions on long-press. Each one also exists on
    /// the job itself, so the gesture is a shortcut, never the only way.
    func jobContextMenu(_ job: Job, customer: String) -> some View {
        contextMenu {
            Button("Copy job number", systemImage: "doc.on.doc") { UIPasteboard.general.string = job.shortRef }
            ShareLink(item: JobShareText.text(title: job.title, customer: customer, scheduledFor: job.scheduledFor)) {
                Label("Share job", systemImage: "square.and.arrow.up")
            }
        }
    }
}

enum PaperWorkGroups {
    static func inProgress(_ jobs: [Job]) -> [Job] {
        jobs.filter { ["in_progress", "arrived", "en_route", "paused"].contains($0.status) }
    }
    static func scheduled(_ jobs: [Job]) -> [Job] {
        jobs.filter { ["scheduled", "dispatched"].contains($0.status) }
    }
    static func completed(_ jobs: [Job]) -> [Job] { jobs.filter { $0.status == "completed" } }
    /// The job under way, else the earliest booked one: what "open my next job" means.
    static func next(_ jobs: [Job]) -> Job? {
        inProgress(jobs).first ?? scheduled(jobs).min {
            (JobFiltering.date($0.scheduledFor) ?? .distantFuture) < (JobFiltering.date($1.scheduledFor) ?? .distantFuture)
        }
    }
    static func other(_ jobs: [Job]) -> [Job] {
        jobs.filter { !["in_progress", "arrived", "en_route", "paused", "scheduled", "dispatched", "completed"].contains($0.status) }
    }
}

/// Paper 18 / 79: the technician's day. "Next up" carries the one commit that
/// moves the job forward (On my way), so the old Arrive tab lives here now.
struct ScheduleView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var outbox: FieldOutbox
    @State private var tab = "Today"
    @State private var search = ""
    @State private var searchVisible = false
    @State private var showNew = false
    @State private var busyJobID: String?
    @State private var progressError: String?
    /// The Next up job as GET /v1/jobs/{id} returns it: list items carry no allowed transitions,
    /// so the hero's commit is read from the server rather than guessed from status.
    @State private var hero: JobRecord?
    @State private var committed = 0

    private var range: ScheduleRange {
        switch tab {
        case "Week": .week
        case "Unscheduled": .unscheduled
        case "Map": .today
        default: .today
        }
    }
    private var jobs: [Job] {
        let filtered = JobFiltering.schedule(store.jobs, range: range)
        guard !search.isEmpty else { return filtered }
        return filtered.filter { $0.title.localizedCaseInsensitiveContains(search)
            || $0.shortRef.localizedCaseInsensitiveContains(search)
            || store.customerName($0.customerId).localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PaperHeader(title: "Schedule", subtitle: subtitle) { withAnimation { searchVisible.toggle() } }
                OfflineBanner()
                if searchVisible { PaperSearchField(text: $search, prompt: "Search schedule") }
                PaperTabs(options: ["Today", "Week", "Map", "Unscheduled"], selection: $tab)
                if let error = store.error { ErrorBanner(message: error) { _ = await store.refresh(api) } }
                if let progressError { ErrorBanner(message: progressError) }
                if store.loading && store.jobs.isEmpty {
                    SkeletonRows()
                } else if jobs.isEmpty {
                    emptyState
                } else if tab == "Map" {
                    ScheduleMapView(jobs: jobs.filter { $0.status != "canceled" })
                } else if range == .week {
                    weekContent
                } else {
                    dayContent
                }
            }
            .padding(.bottom, 24)
        }
        .refreshable { await store.refresh(api) }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showNew) { NewJobSheet() }
        .sensoryFeedback(.success, trigger: committed)
        #if DEBUG
        .onAppear {
            if PaperPreview.enabled && PaperPreview.screen == "schedule-map" { tab = "Map" }
            if PaperPreview.enabled && PaperPreview.screen == "schedule-week" { tab = "Week" }
        }
        #endif
    }

    private var subtitle: String {
        let day = Date().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let count = jobs.count
        return switch range {
        case .today: "\(greeting) · \(day)\(count > 0 ? " · \(count) job\(count == 1 ? "" : "s")" : "")"
        case .week: "This week · \(count) job\(count == 1 ? "" : "s")"
        case .unscheduled: "\(count) job\(count == 1 ? "" : "s") need a time"
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let part = hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"
        let first = session.user?.name?.split(separator: " ").first.map(String.init)
        return first.map { "\(part), \($0)" } ?? part
    }

    @ViewBuilder private var dayContent: some View {
        if let first = jobs.first {
            PaperGroupHeader(title: range == .unscheduled ? "Needs a time" : "Next up")
                .padding(.horizontal, Theme.gutter).padding(.top, 4)
            ScheduleHero(job: first, customer: store.customerName(first.customerId), pendingStatus: outbox.pendingStatus(for: first.id)) { commit(for: first) }
                .padding(.bottom, 16)
                .task(id: "\(first.id)|\(first.status)|\(first.updatedAt ?? "")") { await loadHero(first) }
            if jobs.count > 1 {
                PaperGroupHeader(title: range == .today ? "Later today" : "More jobs", count: jobs.count - 1)
                    .padding(.horizontal, Theme.gutter)
                ForEach(Array(jobs.dropFirst())) { job in
                    ScheduleCompactRow(job: job, customer: store.customerName(job.customerId), timeStyle: .time)
                }
            }
        }
    }

    /// Paper 79: one section per day with a count.
    @ViewBuilder private var weekContent: some View {
        let calendar = Calendar.current
        let days = Dictionary(grouping: jobs) { calendar.startOfDay(for: JobFiltering.date($0.scheduledFor) ?? .now) }
        ForEach(days.keys.sorted(), id: \.self) { day in
            let dayJobs = days[day] ?? []
            PaperGroupHeader(title: dayTitle(day), count: dayJobs.count)
                .padding(.horizontal, Theme.gutter).padding(.top, 8)
            ForEach(dayJobs) { job in
                ScheduleCompactRow(job: job, customer: store.customerName(job.customerId), timeStyle: .time)
            }
        }
    }

    private func dayTitle(_ day: Date) -> String {
        let label = day.formatted(.dateTime.weekday(.abbreviated).day())
        if Calendar.current.isDateInToday(day) { return "\(label) · Today" }
        if Calendar.current.isDateInTomorrow(day) { return "\(label) · Tomorrow" }
        return label
    }

    @ViewBuilder private var emptyState: some View {
        let boardEmpty = store.jobs.isEmpty && search.isEmpty
        PaperEmptyState(
            symbol: "calendar",
            title: boardEmpty ? "Nothing on the board yet" : search.isEmpty ? (range == .unscheduled ? "Everything has a time" : "No jobs \(range == .today ? "today" : "this week")") : "No matching jobs",
            message: boardEmpty ? "Your workspace is live. New jobs will land here."
                : range == .unscheduled ? "Jobs without a scheduled time appear here." : "Try another range, or check Jobs for everything open.",
            actionTitle: boardEmpty && session.can("job.create", feature: "jobs") ? "Create your first job" : nil,
            action: { showNew = true }
        )
        .padding(.top, 40)
    }

    /// The next field step for the Next up job, in lifecycle order.
    private func nextStep(for job: Job) -> String? {
        guard session.can("job.edit", feature: "jobs") else { return nil }
        let allowed: [String]
        let status: String
        if let queued = outbox.pendingStatus(for: job.id) {
            // Already queued a step: only offer what the server allowed from that status before.
            status = queued
            allowed = outbox.offlineSteps(from: queued)
        } else if let hero, hero.id == job.id {
            status = hero.status
            allowed = hero.allowedTransitions ?? []
        } else if session.isOffline {
            status = job.status
            allowed = outbox.offlineSteps(from: job.status)
        } else {
            return nil
        }
        return ["en_route", "arrived", "in_progress"].first { allowed.contains($0) && !(status == "paused" && $0 == "in_progress") }
    }

    @ViewBuilder private func commit(for job: Job) -> some View {
        switch nextStep(for: job) {
        case "en_route":
            Menu {
                Button("On my way") { Task { await progress(job, .enRoute(etaMinutes: nil)) } }
                ForEach([15, 30, 45, 60], id: \.self) { minutes in
                    Button("On my way · ETA \(minutes) min") { Task { await progress(job, .enRoute(etaMinutes: minutes)) } }
                }
            } label: { commitLabel("On my way", symbol: "location.fill", busy: busyJobID == job.id) }
            .disabled(busyJobID != nil)
            .accessibilityHint("Tells the office and customer you are driving to this job")
        case "arrived":
            Button { Task { await progress(job, .arrived()) } } label: {
                commitLabel("Mark arrived", symbol: "mappin.and.ellipse", busy: busyJobID == job.id)
            }
            .buttonStyle(PressStyle()).disabled(busyJobID != nil)
        case "in_progress":
            Button { Task { await progress(job, .start) } } label: {
                commitLabel("Start work", symbol: "wrench.and.screwdriver", busy: busyJobID == job.id)
            }
            .buttonStyle(PressStyle()).disabled(busyJobID != nil)
        default:
            EmptyView()
        }
    }

    /// MA-08: Next up's one commit is ink and 50 tall; pending keeps the words and swaps the mark.
    private func commitLabel(_ title: String, symbol: String, busy: Bool) -> some View {
        HStack(spacing: 7) {
            if busy { ProgressView().tint(Theme.onInk) } else { Image(systemName: symbol) }
            Text(title)
        }
        .inkCommit()
    }

    private func loadHero(_ job: Job) async {
        guard session.can("job.view", feature: "jobs") else { return }
        let generation = session.generation
        do {
            let record = try await api.fieldJob(job.id)
            guard session.generation == generation else { return }
            hero = record
            outbox.learn(record)
        } catch is CancellationError {} catch {
            // Without the server's transitions the band stays a link to the job.
            guard session.generation == generation else { return }
            hero = nil
        }
    }

    private func progress(_ job: Job, _ request: FieldProgressRequest) async {
        guard busyJobID == nil else { return }
        if session.isOffline || !outbox.pending.filter({ $0.jobID == job.id }).isEmpty {
            queue(job, request)
            return
        }
        busyJobID = job.id
        defer { busyJobID = nil }
        do {
            _ = try await api.progressFieldJob(job.id, request: request)
            committed += 1
            await loadHero(job)
            progressError = nil
            if await store.refresh(api) == .failed {
                progressError = "Saved. The latest schedule could not be refreshed."
            }
        } catch is CancellationError {
        } catch {
            if error.isConnectivityFailure { queue(job, request) } else { progressError = error.localizedDescription }
        }
    }

    /// No signal: save the step on the phone; it is sent in order when signal returns.
    private func queue(_ job: Job, _ request: FieldProgressRequest) {
        guard let payload = OutboxEntry.ProgressPayload(jobID: job.id, request: request) else {
            progressError = "That change needs a connection."
            return
        }
        outbox.enqueue(.progress(payload), policyVersion: session.policyVersion ?? 0)
        committed += 1
        progressError = nil
        if !session.isOffline {
            Task {
                await outbox.drain(api: api, useCommandEndpoint: session.isFeatureOn("offline_sync"))
                await store.refresh(api)
            }
        }
    }
}

/// The "Next up" band: inset surface, mono time lane, title, chips, one commit.
private struct ScheduleHero<Commit: View>: View {
    let job: Job
    let customer: String
    var pendingStatus: String? = nil
    @ViewBuilder var commit: () -> Commit
    @ScaledMetric(relativeTo: .caption) private var laneWidth: CGFloat = 60

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if let date = JobFiltering.date(job.scheduledFor) {
                    Text(date.formatted(.dateTime.hour().minute()))
                } else { Text("No time") }
            }
            .font(Theme.monoFont(12, weight: .medium)).foregroundStyle(Theme.foreground)
            .lineLimit(1).minimumScaleFactor(0.8)
            .frame(width: laneWidth, alignment: .leading).padding(.top, 3)
            VStack(alignment: .leading, spacing: 10) {
                NavigationLink(value: job) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(job.title).font(Theme.font(17, weight: .semibold)).foregroundStyle(Theme.foreground)
                                .multilineTextAlignment(.leading)
                            Text(customer).font(Theme.font(13)).foregroundStyle(Theme.muted)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted).padding(.top, 4)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .jobContextMenu(job, customer: customer)
                .accessibilityLabel("\(job.title), \(customer), \(job.status.statusLabel)")
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { chips }
                    VStack(alignment: .leading, spacing: 6) { chips }
                }
                commit()
            }
        }
        .padding(.horizontal, Theme.gutter).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .overlay(alignment: .top) { Theme.border.frame(height: 1) }
        .overlay(alignment: .bottom) { Theme.border.frame(height: 1) }
    }
}

private extension ScheduleHero {
    @ViewBuilder var chips: some View {
        let status = pendingStatus ?? job.status
        let (symbol, color) = statusIcon(status)
        Chip(text: pendingStatus == nil ? status.statusLabel : "\(status.statusLabel) · waiting to sync", icon: pendingStatus == nil ? symbol : "clock.arrow.circlepath",
             tint: pendingStatus == nil ? color : Theme.warning,
             bg: pendingStatus != nil ? Theme.warningSurface : status == "en_route" || status == "dispatched" ? Theme.brandSurface : Theme.fill)
        Text(job.shortRef).font(Theme.monoFont(12, weight: .medium)).foregroundStyle(Theme.muted)
            .lineLimit(1).fixedSize()
            .padding(.horizontal, 10).frame(minHeight: Theme.chipHeight)
            .background(Theme.fill, in: Capsule())
    }
}

private struct ScheduleCompactRow: View {
    enum TimeStyle { case time }
    let job: Job
    let customer: String
    var timeStyle: TimeStyle = .time
    @ScaledMetric(relativeTo: .caption) private var laneWidth: CGFloat = 60
    @Environment(\.dynamicTypeSize) private var typeSize

    private var time: some View {
        Group {
            if let date = JobFiltering.date(job.scheduledFor) {
                Text(date.formatted(.dateTime.hour().minute()))
            } else { Text("—") }
        }
        .font(Theme.monoFont(12, weight: .medium)).foregroundStyle(Theme.foreground)
        .lineLimit(1).minimumScaleFactor(0.8)
    }

    var body: some View {
        NavigationLink(value: job) {
            HStack(alignment: .center, spacing: 10) {
                if !typeSize.isAccessibilitySize {
                    time.frame(width: laneWidth, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 1) {
                    if typeSize.isAccessibilitySize { time }
                    Text(job.title).font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                        .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                    Text("\(job.status.statusLabel) · \(customer)")
                        .font(Theme.font(13)).foregroundStyle(Theme.muted).lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                }
                Spacer(minLength: 0)
                StatusRing(status: job.status)
            }
            .padding(.horizontal, Theme.gutter).padding(.vertical, 5)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .jobContextMenu(job, customer: customer)
    }
}

/// Paper 20: every job, grouped by where it stands.
struct JobsView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController
    @State private var tab = "Assigned"
    @State private var search = ""
    @State private var searchVisible = false
    @State private var showNew = false
    @Environment(\.dynamicTypeSize) private var typeSize

    private var jobs: [Job] {
        let assigned = tab == "Assigned" ? (session.user?.id ?? "") : nil
        return JobFiltering.jobs(store.jobs, assignedTo: assigned, search: search)
    }
    private var activeCount: Int { jobs.filter { !["completed", "canceled"].contains($0.status) }.count }
    private var attentionCount: Int { jobs.filter { $0.status == "paused" }.count }
    private var subtitle: String {
        attentionCount > 0 ? "\(activeCount) active · \(attentionCount) paused" : "\(activeCount) active"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PaperHeader(title: "Jobs", subtitle: subtitle) { withAnimation { searchVisible.toggle() } }
                OfflineBanner()
                if searchVisible { PaperSearchField(text: $search, prompt: "Title or job number") }
                PaperTabs(options: ["Assigned", "All jobs", "Recent"], selection: $tab)
                if let error = store.error { ErrorBanner(message: error) { _ = await store.refresh(api) } }
                VStack(alignment: .leading, spacing: 14) {
                    if store.loading && store.jobs.isEmpty {
                        SkeletonRows().padding(.horizontal, -Theme.gutter)
                    } else if tab == "Recent" {
                        group("Recently updated", jobs: Array(jobs.prefix(25)), first: true)
                    } else {
                        let groups = [("In progress", PaperWorkGroups.inProgress(jobs)), ("Scheduled", PaperWorkGroups.scheduled(jobs)),
                                      ("Done", PaperWorkGroups.completed(jobs)), ("Other", PaperWorkGroups.other(jobs))]
                        let lead = groups.first { !$0.1.isEmpty }?.0
                        ForEach(groups, id: \.0) { title, members in group(title, jobs: members, first: title == lead) }
                    }
                    if MyDayRules.shouldShowEmptyState(isEmpty: jobs.isEmpty, isLoading: store.loading, hasError: store.error != nil) {
                        PaperEmptyState(
                            symbol: "briefcase",
                            title: !search.isEmpty ? "No matching jobs" : tab == "Assigned" ? "Nothing assigned to you" : "No jobs yet",
                            message: !search.isEmpty ? "Try another title or job number." : tab == "Assigned" ? "Jobs dispatched to you appear here. All jobs shows the whole board." : "New jobs appear here as soon as they are created.",
                            actionTitle: session.can("job.create", feature: "jobs") && search.isEmpty ? "New job" : nil,
                            action: { showNew = true }
                        )
                    }
                }
                .padding(.horizontal, Theme.gutter).padding(.top, 4)
            }
            .padding(.bottom, 24)
        }
        .refreshable { await store.refresh(api) }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showNew) { NewJobSheet() }
    }

    /// Customer, then when (or the state when there is no time), then the job number.
    private func detail(_ job: Job, customer: String) -> String {
        var parts = [customer]
        if let date = JobFiltering.date(job.scheduledFor), !["completed", "canceled"].contains(job.status) {
            parts.append(Calendar.current.isDateInToday(date)
                ? "Today \(date.formatted(date: .omitted, time: .shortened))"
                : date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
        } else {
            parts.append(job.status.statusLabel)
        }
        parts.append(job.shortRef)
        return parts.joined(separator: " · ")
    }

    /// One "New job" entry point, on the first group shown, instead of a plus on every group.
    @ViewBuilder private func group(_ title: String, jobs: [Job], first: Bool = false) -> some View {
        if !jobs.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                PaperGroupHeader(title: title, count: jobs.count) {
                    if session.can("job.create", feature: "jobs") && first {
                        Button { showNew = true } label: {
                            Image(systemName: "plus").font(.system(size: 14, weight: .medium))
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("New job")
                    }
                }
                ForEach(jobs) { job in
                    let customer = store.customerName(job.customerId)
                    NavigationLink(value: job) {
                        // MA-11: what, then who and when, on two lines; same record, same row.
                        HStack(spacing: 12) {
                            StatusRing(status: job.status)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(job.title).font(Theme.font(15, weight: .medium))
                                    .foregroundStyle(job.status == "completed" ? Theme.muted : Theme.foreground)
                                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                                Text(detail(job, customer: customer))
                                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                            }
                            Spacer(minLength: 0)
                            if job.assignedToUserId != nil && job.assignedToUserId == session.user?.id {
                                Text(initials(session.user?.name ?? "Me"))
                                    .font(Theme.font(12, weight: .medium))
                                    .foregroundStyle(Theme.brandText)
                                    .frame(width: 26, height: 26)
                                    .background(Theme.brandSurface, in: Circle())
                                    .dynamicTypeSize(...DynamicTypeSize.large)
                                    .accessibilityLabel("Assigned to you")
                            }
                        }
                        .padding(.horizontal, 8)
                        .frame(minHeight: 56)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                    .jobContextMenu(job, customer: customer)
                    .padding(.horizontal, -8)
                }
            }
        }
    }
}

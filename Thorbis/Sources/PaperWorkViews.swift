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
enum ScheduleLead {
    /// Statuses that mean the tech is already on this job.
    static let activeStatuses: Set<String> = ["en_route", "arrived", "in_progress", "paused"]
}

struct ScheduleView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var outbox: FieldOutbox
    @State private var tab = "Today"
    /// Nil until the person picks; until then the role decides (technicians: Mine).
    @State private var pickedScope: ScheduleScope?
    @State private var showNew = false
    /// A job without a time whose Schedule button was tapped; the sheet reads it fresh.
    @State private var scheduling: Job?
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
    private var scope: ScheduleScope {
        pickedScope ?? .initial(schedulesOwnDay: WorkRole(session).schedulesOwnDay, actorID: session.user?.id)
    }
    private var scopeBinding: Binding<ScheduleScope> {
        Binding(get: { scope }, set: { pickedScope = $0 })
    }
    /// Mine/Everyone applies to a day, week or map; Unscheduled is everyone's queue.
    private var showsScope: Bool { range != .unscheduled && session.user?.id != nil }
    /// Finding a job is the bar's Search; this screen narrows by range and whose jobs only.
    private var jobs: [Job] {
        JobFiltering.schedule(store.jobs, range: range, assignedTo: scope.assignee(session.user?.id, range: range))
    }
    private var canSchedule: Bool { session.can("job.assign", feature: "jobs") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PaperHeader(title: "Schedule", subtitle: subtitle)
                OfflineBanner()
                PaperTabs(options: ["Today", "Week", "Map", "Unscheduled"], selection: $tab)
                if showsScope {
                    ThorbisSegmented(options: [(ScheduleScope.mine, "My jobs"), (ScheduleScope.everyone, "Everyone")],
                                     selection: scopeBinding)
                        .padding(.horizontal, Theme.gutter).padding(.top, 4).padding(.bottom, 8)
                        .accessibilityLabel("Whose jobs")
                }
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
        .sheet(item: $scheduling) { QuickScheduleSheet(jobID: $0.id) }
        .sensoryFeedback(.success, trigger: committed)
        #if DEBUG
        .onAppear {
            if PaperPreview.enabled && PaperPreview.screen == "schedule-map" { tab = "Map" }
            if PaperPreview.enabled && PaperPreview.screen == "schedule-week" { tab = "Week" }
            if PaperPreview.enabled && PaperPreview.screen == "schedule-unscheduled" { tab = "Unscheduled" }
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

    /// The job the tech is on right now leads, even when an earlier slot is still open;
    /// otherwise the next one by time.
    private var leadJob: Job? {
        jobs.first { ScheduleLead.activeStatuses.contains($0.status) } ?? jobs.first
    }

    /// The day at a glance: how many, how many under way, and when the next one starts (or how
    /// many are done once nothing is left to start).
    private var todayStats: [PaperStatRow.Stat] {
        let active = jobs.filter { ScheduleLead.activeStatuses.contains($0.status) }.count
        let done = jobs.filter { $0.status == "completed" }.count
        let next = jobs.filter { ["scheduled", "dispatched"].contains($0.status) }
            .compactMap { JobFiltering.date($0.scheduledFor) }.filter { $0 > .now }.min()
        return [
            .init(label: "Jobs", value: "\(jobs.count)"),
            .init(label: "Under way", value: "\(active)", tint: active > 0 ? Theme.warning : Theme.foreground),
            next.map { .init(label: "Next", value: $0.formatted(.dateTime.hour().minute())) }
                ?? .init(label: "Done", value: "\(done)", tint: done > 0 ? Theme.success : Theme.foreground),
        ]
    }

    @ViewBuilder private var dayContent: some View {
        if let first = leadJob {
            let isActive = ScheduleLead.activeStatuses.contains(first.status)
            if range == .today {
                PaperStatRow(stats: todayStats).paperCardMargin().padding(.top, 4).padding(.bottom, 18)
            }
            PaperGroupHeader(title: range == .unscheduled ? "Needs a time" : isActive ? "Now" : "Next up")
                .padding(.horizontal, Theme.gutter).padding(.top, range == .today ? 0 : 4)
            ScheduleHero(job: first, customer: store.customerName(first.customerId), pendingStatus: outbox.pendingStatus(for: first.id)) { commit(for: first) }
                .paperCardMargin()
                .padding(.bottom, 18)
                .task(id: "\(first.id)|\(first.status)|\(first.updatedAt ?? "")") { await loadHero(first) }
            let rest = jobs.filter { $0.id != first.id }
            if !rest.isEmpty {
                PaperGroupHeader(title: range == .today ? (isActive ? "Also today" : "Later today") : "More jobs", count: rest.count)
                    .padding(.horizontal, Theme.gutter)
                jobCard(rest, timeStyle: range == .unscheduled ? .age : .time)
            }
        }
    }

    /// A card of compact job rows, separated by space rather than rules.
    private func jobCard(_ list: [Job], timeStyle: ScheduleCompactRow.TimeStyle = .time) -> some View {
        VStack(spacing: 0) {
            PaperCardList(data: list) { job in
                ScheduleCompactRow(job: job, customer: store.customerName(job.customerId), timeStyle: timeStyle,
                                   schedule: job.scheduledFor == nil && canSchedule ? { scheduling = job } : nil)
            }
        }
        .paperCardMargin()
        .padding(.bottom, 18)
    }

    /// Paper 79: one section per day with a count.
    @ViewBuilder private var weekContent: some View {
        let calendar = Calendar.current
        let days = Dictionary(grouping: jobs) { calendar.startOfDay(for: JobFiltering.date($0.scheduledFor) ?? .now) }
        ForEach(days.keys.sorted(), id: \.self) { day in
            let dayJobs = days[day] ?? []
            PaperGroupHeader(title: dayTitle(day), count: dayJobs.count)
                .padding(.horizontal, Theme.gutter).padding(.top, 4)
            jobCard(dayJobs)
        }
    }

    private func dayTitle(_ day: Date) -> String {
        let label = day.formatted(.dateTime.weekday(.abbreviated).day())
        if Calendar.current.isDateInToday(day) { return "\(label) · Today" }
        if Calendar.current.isDateInTomorrow(day) { return "\(label) · Tomorrow" }
        return label
    }

    @ViewBuilder private var emptyState: some View {
        let boardEmpty = store.jobs.isEmpty
        let mine = showsScope && scope == .mine
        PaperEmptyState(
            symbol: "calendar",
            title: boardEmpty ? "Nothing on the board yet" : range == .unscheduled ? "Everything has a time" : "No jobs \(mine ? "for you " : "")\(range == .today ? "today" : "this week")",
            message: boardEmpty ? "Your workspace is live. New jobs will land here."
                : range == .unscheduled ? "Jobs without a scheduled time appear here."
                : mine ? "Choose Everyone to see the whole team's jobs." : "Try another range, or check Jobs for everything open.",
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
        // Only ever forward: a job already in progress never offers "Mark arrived" again.
        let order = ["scheduled": 0, "dispatched": 0, "en_route": 1, "arrived": 2, "in_progress": 3, "paused": 3]
        let current = order[status] ?? 0
        return ["en_route", "arrived", "in_progress"].first {
            allowed.contains($0) && (order[$0] ?? 0) > current && !(status == "paused" && $0 == "in_progress")
        }
    }

    @ViewBuilder private func commit(for job: Job) -> some View {
        if job.scheduledFor == nil, canSchedule, !ScheduleLead.activeStatuses.contains(job.status) {
            // Needs a time: booking it is the one next step, straight to the schedule sheet.
            Button { scheduling = job } label: {
                commitLabel("Schedule", symbol: "calendar.badge.plus", busy: false)
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Schedule \(job.title)")
            .accessibilityHint("Choose a day and arrival window")
            .accessibilityIdentifier("schedule-row-\(job.id)")
        } else {
            stepCommit(for: job)
        }
    }

    @ViewBuilder private func stepCommit(for job: Job) -> some View {
        switch nextStep(for: job) {
        case "en_route":
            ThorbisMenu(
                items: [ThorbisMenuItem("On my way", icon: "location.fill") {
                    Task { await progress(job, .enRoute(etaMinutes: nil)) }
                }] + ([15, 30, 45, 60] as [Int]).map { minutes in
                    ThorbisMenuItem("ETA \(minutes) min", icon: "clock") {
                        Task { await progress(job, .enRoute(etaMinutes: minutes)) }
                    }
                },
                title: "On my way",
                accessibilityLabel: "On my way"
            ) { commitLabel("On my way", symbol: "location.fill", busy: busyJobID == job.id) }
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
            // On the job already: the next thing is wrapping it up, so that is the commit.
            if (outbox.pendingStatus(for: job.id) ?? job.status) == "in_progress", session.can("job.edit", feature: "jobs") {
                NavigationLink { JobCloseoutView(jobID: job.id) } label: {
                    commitLabel("Wrap up", symbol: "checkmark.seal", busy: false)
                }
                .buttonStyle(PressStyle())
                .accessibilityHint("Opens the closeout checklist for this job")
            }
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

/// The "Next up" card: status tile, title and customer, the time and status as words, one commit.
private struct ScheduleHero<Commit: View>: View {
    let job: Job
    let customer: String
    var pendingStatus: String? = nil
    @ViewBuilder var commit: () -> Commit
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        PaperCard(padding: 16) {
            NavigationLink(value: job) {
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                                                          : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
                layout {
                    StatusTile(status: pendingStatus ?? job.status, pending: pendingStatus != nil)
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(job.title).font(Theme.font(17, weight: .medium)).foregroundStyle(Theme.foreground)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(customer).font(Theme.font(13)).foregroundStyle(Theme.muted)
                                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                        }
                        Spacer(minLength: 0)
                        PaperDisclosure().padding(.top, 4)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .jobContextMenu(job, customer: customer)
            .accessibilityLabel("\(job.title), \(customer), \(job.status.statusLabel)")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { chips }
                VStack(alignment: .leading, spacing: 6) { chips }
            }
            .padding(.top, 12)
            commit().padding(.top, 12)
        }
    }
}

private extension ScheduleHero {
    @ViewBuilder var chips: some View {
        let status = pendingStatus ?? job.status
        let (symbol, color) = statusIcon(status)
        if let date = JobFiltering.date(job.scheduledFor) {
            Fact(text: date.formatted(.dateTime.hour().minute()), icon: "clock", tint: Theme.foreground)
        } else {
            Fact(text: "No time", icon: "clock")
        }
        Chip(text: pendingStatus == nil ? status.statusLabel : "\(status.statusLabel) · waiting to sync", icon: pendingStatus == nil ? symbol : "clock.arrow.circlepath",
             tint: pendingStatus == nil ? color : Theme.warning,
             bg: pendingStatus != nil ? Theme.warningSurface : status == "en_route" || status == "dispatched" ? Theme.brandSurface : Theme.fill)
        // The reference is a fact, not a second pill.
        Text(job.shortRef).font(Theme.monoFont(13, weight: .medium)).foregroundStyle(Theme.muted)
            .lineLimit(1).fixedSize()
            .frame(minHeight: Theme.chipHeight)
    }
}

struct ScheduleCompactRow: View {
    /// `.age` is for jobs without a time: the lane shows how long the job has been waiting.
    enum TimeStyle { case time, age }
    let job: Job
    let customer: String
    var timeStyle: TimeStyle = .time
    /// Set on a row with no time for someone who may schedule: a trailing Schedule button.
    var schedule: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.paperRowInset) private var inset

    private var time: Text {
        let text: Text
        if timeStyle == .age, let created = JobFiltering.date(job.createdAt) {
            text = Text(Self.age(since: created)).foregroundStyle(Theme.foreground)
                .accessibilityLabel("Waiting since \(created.formatted(date: .abbreviated, time: .omitted))")
        } else if let date = JobFiltering.date(job.scheduledFor) {
            text = Text(date.formatted(.dateTime.hour().minute())).foregroundStyle(Theme.foreground)
        } else {
            text = Text("No time").foregroundStyle(Theme.muted)
        }
        return text.font(Theme.monoFont(13, weight: .medium))
    }

    /// "Today", "2d", "3w": short enough to lead the row's second line.
    nonisolated static func age(since date: Date, now: Date = .now) -> String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: date),
                                                   to: Calendar.current.startOfDay(for: now)).day ?? 0
        switch days {
        case ..<1: return "Today"
        case 1..<14: return "\(days)d"
        case 14..<120: return "\(days / 7)w"
        default: return "\(days / 30)mo"
        }
    }

    var body: some View {
        // The Schedule button sits beside the row's link, not inside it, so each is its own target.
        HStack(alignment: .center, spacing: 8) {
            NavigationLink(value: job) {
                HStack(alignment: .center, spacing: 12) {
                    StatusTile(status: job.status)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(job.title).font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                            .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                        // When, then the status as a word, then who: two lines at most.
                        (time + Text(" · \(job.status.statusLabel) · \(customer)").font(Theme.font(13)).foregroundStyle(Theme.muted))
                            .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    }
                    Spacer(minLength: 0)
                    if schedule == nil { PaperDisclosure() }
                }
                .padding(.leading, inset).padding(.trailing, schedule == nil ? inset : 0).padding(.vertical, 10)
                .frame(minHeight: 60)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .jobContextMenu(job, customer: customer)
            if let schedule {
                ScheduleRowButton(job: job, action: schedule).padding(.trailing, inset)
            }
        }
    }
}

/// Paper 20: every job, grouped by where it stands.
struct JobsView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController
    @State private var tab = "Assigned"
    @State private var showDisplay = false
    @State private var scheduling: Job?
    @State private var display = DisplayOptions()
    /// Empty means every status; otherwise only the ticked ones.
    @State private var statusFilter: Set<String> = []
    @State private var showNew = false
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Statuses offered as filter chips, in lifecycle order.
    private let statusChips = ["scheduled", "dispatched", "en_route", "arrived", "in_progress", "paused", "completed", "canceled"]
    /// A filter is on when the sheet narrows the board past its defaults.
    private var filterActive: Bool { !statusFilter.isEmpty || !display.showCompleted || display.ordering != .recent }

    private var jobs: [Job] {
        let assigned = tab == "Assigned" ? (session.user?.id ?? "") : nil
        // Finding a job by name or number is the bar's Search; the board narrows with Filters.
        return JobFiltering.board(store.jobs, assignedTo: assigned, search: "",
                                  showCompleted: display.showCompleted, statuses: statusFilter,
                                  ordering: display.ordering)
    }
    private var activeCount: Int { jobs.filter { !["completed", "canceled"].contains($0.status) }.count }
    private var attentionCount: Int { jobs.filter { $0.status == "paused" }.count }
    private var subtitle: String {
        attentionCount > 0 ? "\(activeCount) active · \(attentionCount) paused" : "\(activeCount) active"
    }
    private var canSchedule: Bool { session.can("job.assign", feature: "jobs") }
    /// What the Filters sheet is doing to the board, in words, so a narrowed list never looks empty by accident.
    private var filterSummary: String {
        var parts: [String] = []
        if !statusFilter.isEmpty {
            parts.append(statusChips.filter { statusFilter.contains($0) }.map(\.statusLabel).joined(separator: ", "))
        }
        if !display.showCompleted { parts.append("Hiding completed") }
        if display.ordering != .recent { parts.append("By \(display.ordering.label.lowercased())") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PaperHeader(title: "Jobs", subtitle: subtitle) { showDisplay = true }
                OfflineBanner()
                PaperTabs(options: ["Assigned", "All jobs", "Recent"], selection: $tab)
                if filterActive { filterBar }
                if let error = store.error { ErrorBanner(message: error) { _ = await store.refresh(api) } }
                VStack(alignment: .leading, spacing: 14) {
                    if store.loading && store.jobs.isEmpty {
                        SkeletonRows().padding(.horizontal, -PaperCardMetrics.margin)
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
                            title: filterActive ? "No jobs match these filters" : tab == "Assigned" ? "Nothing assigned to you" : "No jobs yet",
                            message: filterActive ? "Clear the filters to see the whole board." : tab == "Assigned" ? "Jobs dispatched to you appear here. All jobs shows the whole board." : "New jobs appear here as soon as they are created.",
                            actionTitle: session.can("job.create", feature: "jobs") && !filterActive ? "New job" : nil,
                            action: { showNew = true }
                        )
                    }
                }
                .paperCardMargin().padding(.top, 4)
            }
            .padding(.bottom, 24)
        }
        .refreshable { await store.refresh(api) }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if session.can("job.create", feature: "jobs") && !jobs.isEmpty {
                FloatingCreateButton(title: "New job") { showNew = true }
            }
        }
        .sheet(isPresented: $showNew) { NewJobSheet() }
        .sheet(isPresented: $showDisplay) { displaySheet }
        .sheet(item: $scheduling) { QuickScheduleSheet(jobID: $0.id) }
    }

    /// The active filters in one quiet line under the tabs, with a way back to the whole board.
    private var filterBar: some View {
        HStack(spacing: 8) {
            Button { showDisplay = true } label: {
                Label(filterSummary, systemImage: "line.3.horizontal.decrease")
                    .font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.foreground)
                    .lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Filtered: \(filterSummary)")
            .accessibilityHint("Opens the filters")
            Button("Clear") { withMotion { statusFilter = []; display = DisplayOptions() } }
                .font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.brandText)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Clear filters")
        }
        .padding(.horizontal, Theme.gutter)
    }

    /// Ordering, completed work and status: the real ways to narrow the board.
    private var displaySheet: some View {
        ThorbisSheetScaffold(title: "Filters", onClose: { showDisplay = false }) {
            ThorbisSheetGroup {
                ThorbisSheetRow(label: "Ordering", value: display.ordering.label,
                                options: DisplayOptions.Ordering.allCases.map(\.label)) { picked in
                    display.ordering = DisplayOptions.Ordering.allCases.first { $0.label == picked } ?? .recent
                }
                ThorbisSheetDivider()
                ThorbisSheetToggleRow(label: "Show completed", isOn: $display.showCompleted)
            }

            HStack {
                Text("Status").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                Spacer(minLength: 0)
                if filterActive {
                    Button("Reset") { statusFilter = []; display = DisplayOptions() }
                        .font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.brandText)
                }
            }
            ThorbisChipGroup(data: statusChips, id: \.self,
                             isOn: { statusFilter.contains($0) },
                             label: { $0.statusLabel }) { status in
                if statusFilter.contains(status) { statusFilter.remove(status) } else { statusFilter.insert(status) }
            }
        }
    }

    /// The status as a word, then who, then when. The job number lives on the job and in search;
    /// in a row it only pushed the time off the end.
    private func detail(_ job: Job, customer: String) -> String {
        var parts = [job.status.statusLabel, customer]
        if let date = JobFiltering.date(job.scheduledFor), !["completed", "canceled"].contains(job.status) {
            parts.append(date.visitLabel())
        }
        return parts.joined(separator: " · ")
    }

    /// A titled group of job rows; New job is the floating pill, not a plus on a group.
    @ViewBuilder private func group(_ title: String, jobs: [Job], first: Bool = false) -> some View {
        if !jobs.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                PaperGroupHeader(title: title, count: jobs.count).padding(.horizontal, Theme.gutter - PaperCardMetrics.margin)
                PaperCardList(data: jobs) { job in
                    let customer = store.customerName(job.customerId)
                    let needsTime = canSchedule && job.scheduledFor == nil && !["completed", "canceled"].contains(job.status)
                        && !ScheduleLead.activeStatuses.contains(job.status)
                    HStack(spacing: 8) {
                    NavigationLink(value: job) {
                        // MA-11: what, then its status, who and when; same record, same row.
                        HStack(spacing: 12) {
                            StatusTile(status: job.status)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(job.title).font(Theme.font(15, weight: .medium))
                                    .foregroundStyle(job.status == "completed" ? Theme.muted : Theme.foreground)
                                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                                Text(detail(job, customer: customer))
                                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                            }
                            Spacer(minLength: 0)
                            // On Assigned every row is yours, so the badge would only repeat itself.
                            if tab != "Assigned" && job.assignedToUserId != nil && job.assignedToUserId == session.user?.id {
                                Text(initials(session.user?.name ?? "Me"))
                                    .font(Theme.font(12, weight: .medium))
                                    .foregroundStyle(Theme.brandText)
                                    .frame(width: 26, height: 26)
                                    .background(Theme.brandSurface, in: Circle())
                                    .dynamicTypeSize(...DynamicTypeSize.large)
                                    .accessibilityLabel("Assigned to you")
                            }
                            if !needsTime { PaperDisclosure() }
                        }
                        .padding(.leading, PaperCardMetrics.inset).padding(.trailing, needsTime ? 0 : PaperCardMetrics.inset)
                        .padding(.vertical, 10)
                        .frame(minHeight: 60)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                    .jobContextMenu(job, customer: customer)
                    // No time yet: book it from the row (beside the link, so each is its own target).
                    if needsTime {
                        ScheduleRowButton(job: job) { scheduling = job }.padding(.trailing, PaperCardMetrics.inset)
                    }
                    }
                }
            }
        }
    }
}

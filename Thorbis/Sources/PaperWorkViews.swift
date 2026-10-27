import SwiftUI

func statusIcon(_ status: String) -> (String, Color) {
    switch status {
    case "completed": ("checkmark.circle.fill", Theme.success)
    case "in_progress", "arrived", "paused": ("circle.lefthalf.filled", Theme.warning)
    case "en_route", "dispatched": ("arrow.right.circle", Theme.brand)
    case "canceled": ("xmark.circle", Theme.destructive)
    default: ("circle", Theme.muted)
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
    static func other(_ jobs: [Job]) -> [Job] {
        jobs.filter { !["in_progress", "arrived", "en_route", "paused", "scheduled", "dispatched", "completed"].contains($0.status) }
    }
}

struct ScheduleView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController
    @State private var tab = "Today"
    @State private var search = ""
    @State private var searchVisible = false
    @State private var showNew = false

    private var range: ScheduleRange {
        switch tab {
        case "Week": .week
        case "Unscheduled": .unscheduled
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
        VStack(spacing: 0) {
            PaperHeader(title: "Schedule", icon: "calendar", subtitle: subtitle) { searchVisible.toggle() }
            if searchVisible { PaperSearchField(text: $search, prompt: "Search schedule") }
            HStack(spacing: 0) {
                PaperTabs(options: ["Today", "Week", "Map"], selection: $tab)
                rangeMenu
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let error = store.error { ErrorBanner(message: error) }
                    if store.loading { ProgressView("Updating schedule…") }
                    if tab == "Map" {
                        ContentUnavailableView("Map unavailable", systemImage: "map",
                            description: Text("Job list records do not include map coordinates. Use Today or Week to open a job."))
                            .frame(maxWidth: .infinity)
                    } else {
                        scheduleContent
                    }
                }
                .padding(.bottom, 24)
            }
            .refreshable { await store.refresh(api) }
        }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showNew) { NewJobSheet() }
    }

    private var subtitle: String {
        let day = Date().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return switch tab {
        case "Today": "\(day) · \(jobs.count) job\(jobs.count == 1 ? "" : "s") today"
        case "Week": "\(jobs.count) job\(jobs.count == 1 ? "" : "s") this week"
        case "Unscheduled": "\(jobs.count) unscheduled job\(jobs.count == 1 ? "" : "s")"
        default: "Location data unavailable"
        }
    }

    private var rangeMenu: some View {
        Menu {
            Button("Today") { tab = "Today" }
            Button("Week") { tab = "Week" }
            Button("Unscheduled") { tab = "Unscheduled" }
        } label: {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 16)).foregroundStyle(tab == "Unscheduled" ? Theme.brand : Theme.muted)
                .frame(width: 36, height: 36)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Schedule range, \(tab)")
        .padding(.trailing, 16)
        .padding(.bottom, 12)
    }

    @ViewBuilder private var scheduleContent: some View {
        if let first = jobs.first {
            Text(tab == "Unscheduled" ? "Needs a time" : "Next up")
                .font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                .padding(.horizontal, 16).padding(.bottom, 6)
            ScheduleHero(job: first, customer: store.customerName(first.customerId)).padding(.bottom, 14)
            if jobs.count > 1 {
                HStack {
                    Text(tab == "Today" ? "Later today" : tab == "Week" ? "Later this week" : "More jobs")
                        .font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                    Spacer()
                    Text("\(jobs.count - 1) jobs").font(Theme.monoFont(12)).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 16).padding(.bottom, 6)
                ForEach(Array(jobs.dropFirst())) { job in
                    ScheduleCompactRow(job: job, customer: store.customerName(job.customerId))
                }
            }
        } else if !store.loading {
            VStack(spacing: 12) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 30)).foregroundStyle(Theme.brand)
                    .frame(width: 64, height: 64)
                    .background(Theme.brandSurface, in: RoundedRectangle(cornerRadius: 16))
                Text(store.jobs.isEmpty && search.isEmpty ? "Nothing on the board yet" : "No jobs in this view")
                    .font(Theme.font(17, weight: .semibold)).foregroundStyle(Theme.foreground)
                Text(store.jobs.isEmpty && search.isEmpty ? "Your workspace is live. New jobs will land here."
                    : range == .unscheduled ? "Jobs without a scheduled time appear here."
                    : "Try another date range or search.")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                if store.jobs.isEmpty && session.can("job.create", feature: "jobs") {
                    Button("Create your first job") { showNew = true }
                        .font(Theme.font(14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18).frame(minHeight: 44)
                        .background(Theme.brand, in: RoundedRectangle(cornerRadius: 9))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 44)
            .padding(.horizontal, 20)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)
        }
    }
}

private struct ScheduleHero: View {
    let job: Job
    let customer: String

    var body: some View {
        NavigationLink(value: job) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    if let date = JobFiltering.date(job.scheduledFor) {
                        Text(date.formatted(.dateTime.hour().minute()))
                            .font(Theme.monoFont(12, weight: .medium)).foregroundStyle(Theme.foreground)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    } else {
                        Text("No time").font(Theme.monoFont(12)).foregroundStyle(Theme.muted)
                    }
                    Capsule().fill(Theme.brand).frame(width: 22, height: 3)
                }
                .frame(width: 56, alignment: .leading)
                .padding(.top, 2)
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(job.title).font(Theme.font(16, weight: .semibold)).foregroundStyle(Theme.foreground)
                            .multilineTextAlignment(.leading)
                        Text(customer).font(Theme.font(13)).foregroundStyle(Theme.muted)
                    }
                    HStack(spacing: 6) {
                        HStack(spacing: 5) {
                            Image(systemName: statusIcon(job.status).0)
                            Text(job.status.statusLabel)
                        }
                        .font(Theme.font(12, weight: .medium))
                        .foregroundStyle(statusIcon(job.status).1)
                        .padding(.horizontal, 8).frame(height: 22)
                        .background(statusIcon(job.status).1.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                        Text(job.shortRef).font(Theme.monoFont(11, weight: .medium)).foregroundStyle(Theme.muted)
                            .padding(.horizontal, 8).frame(height: 22)
                            .background(Theme.fill, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Theme.surface)
            .overlay(alignment: .top) { Theme.border.frame(height: 1) }
            .overlay(alignment: .bottom) { Theme.border.frame(height: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(job.title), \(customer), \(job.status.statusLabel)")
    }
}

private struct ScheduleCompactRow: View {
    let job: Job
    let customer: String

    var body: some View {
        NavigationLink(value: job) {
            HStack(alignment: .center, spacing: 10) {
                Group {
                    if let date = JobFiltering.date(job.scheduledFor) {
                        Text(date.formatted(.dateTime.hour().minute()))
                    } else { Text("—") }
                }
                .font(Theme.monoFont(12, weight: .medium)).foregroundStyle(Theme.foreground)
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(width: 56, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text(job.title).font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground).lineLimit(1)
                    Text("\(job.status.statusLabel) · \(customer)")
                        .font(Theme.font(13)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: statusIcon(job.status).0)
                    .font(.system(size: 16)).foregroundStyle(statusIcon(job.status).1)
            }
            .padding(.horizontal, 16).padding(.vertical, 5)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
    }
}

enum JobsViewMode: Equatable {
    case myDay, jobs, arrive

    var initialFilter: String {
        switch self {
        case .myDay, .arrive: "My Day"
        case .jobs: "All jobs"
        }
    }

    var showsFilters: Bool { self != .arrive }
}

struct JobsView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController
    private let mode: JobsViewMode
    @State private var tab: String
    @State private var search = ""
    @State private var searchVisible = false
    @State private var showNew = false
    @State private var busyJobID: String?
    @State private var startedDriving: Set<String> = []
    @State private var progressError: String?

    init(mode: JobsViewMode = .myDay) {
        self.mode = mode
        _tab = State(initialValue: mode.initialFilter)
    }

    private var jobs: [Job] {
        if tab == "My Day" {
            let today = JobFiltering.myDay(store.jobs, actorID: session.user?.id)
            guard !search.isEmpty else { return today }
            return today.filter { $0.title.localizedCaseInsensitiveContains(search) || $0.shortRef.localizedCaseInsensitiveContains(search) }
        }
        let assigned = tab == "Assigned" ? (session.user?.id ?? "") : nil
        return JobFiltering.jobs(store.jobs, assignedTo: assigned, search: search)
    }
    private var activeCount: Int { jobs.filter { !["completed", "canceled"].contains($0.status) }.count }
    private var attentionCount: Int { jobs.filter { ["paused", "canceled"].contains($0.status) }.count }

    var body: some View {
        VStack(spacing: 0) {
            PaperHeader(title: mode == .arrive ? "Arrive" : tab == "My Day" ? "My Day" : "Jobs", icon: mode == .arrive ? "location.north.circle" : tab == "My Day" ? "sun.max" : "briefcase", subtitle: tab == "My Day" ? "\(jobs.count) visits · \(Date.now.formatted(date: .abbreviated, time: .omitted))" : "\(activeCount) active · \(attentionCount) need attention") {
                searchVisible.toggle()
            }
            if searchVisible { PaperSearchField(text: $search, prompt: "Title or job reference") }
            if mode.showsFilters { PaperTabs(options: ["My Day", "Assigned", "All jobs", "Recent"], selection: $tab) }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let error = store.error { ErrorBanner(message: error) }
                    if let progressError { ErrorBanner(message: progressError) }
                    if store.loading { ProgressView("Updating jobs…") }
                    if tab == "My Day" {
                        Label("Today's schedule uses your local date. Job updates require a live connection.", systemImage: "wifi")
                            .font(Theme.font(12)).foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 2)
                        ForEach(jobs) { job in myDayJob(job) }
                    } else if tab == "Recent" {
                        group("Recently updated", jobs: jobs)
                    } else {
                        group("In progress", jobs: PaperWorkGroups.inProgress(jobs))
                        group("Scheduled", jobs: PaperWorkGroups.scheduled(jobs))
                        group("Completed", jobs: PaperWorkGroups.completed(jobs))
                        group("Other", jobs: PaperWorkGroups.other(jobs))
                    }
                    if MyDayRules.shouldShowEmptyState(isEmpty: jobs.isEmpty, isLoading: store.loading, hasError: store.error != nil) {
                        ContentUnavailableView(tab == "My Day" ? "No jobs scheduled today" : (search.isEmpty ? "No jobs" : "No matching jobs"), systemImage: tab == "My Day" ? "sun.max" : "briefcase",
                            description: Text(tab == "My Day" ? "Jobs assigned to you for today will appear here." : (search.isEmpty ? "Jobs in this view appear here." : "Try another title or job reference.")))
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
            .refreshable { await store.refresh(api) }
        }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showNew) { NewJobSheet() }
    }

    @ViewBuilder private func myDayJob(_ job: Job) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if let date = JobFiltering.date(job.scheduledFor) {
                    Text(date.formatted(date: .omitted, time: .shortened))
                        .font(Theme.monoFont(12, weight: .medium)).foregroundStyle(Theme.brand)
                }
                Text(job.shortRef).font(Theme.monoFont(11, weight: .medium)).foregroundStyle(Theme.muted)
                Spacer()
                Text(job.status.statusLabel).font(Theme.font(11, weight: .medium)).foregroundStyle(Theme.muted)
            }
            NavigationLink(value: job) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(job.title).font(Theme.font(16, weight: .semibold)).foregroundStyle(Theme.foreground).lineLimit(2)
                        Text(store.customerName(job.customerId)).font(Theme.font(13)).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(Theme.font(12, weight: .semibold)).foregroundStyle(Theme.muted).padding(.top, 3)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)

            if startedDriving.contains(job.id) {
                Label("Driving started", systemImage: "checkmark.circle.fill")
                    .font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.success)
            } else if MyDayRules.canStartDriving(job, canEdit: session.can("job.edit", feature: "jobs")) {
                Menu {
                    Button("On my way") { Task { await startDriving(job, etaMinutes: nil) } }
                    ForEach([15, 30, 45, 60], id: \.self) { minutes in
                        Button("On my way · ETA \(minutes) min") { Task { await startDriving(job, etaMinutes: minutes) } }
                    }
                } label: {
                    HStack(spacing: 7) {
                        if busyJobID == job.id { ProgressView().tint(.white).scaleEffect(0.8) }
                        else { Image(systemName: "car.side.fill") }
                        Text(busyJobID == job.id ? "Updating…" : "On my way")
                    }
                    .font(Theme.font(13, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 13).frame(minHeight: 44)
                    .background(Theme.brand, in: Capsule())
                }
                .disabled(busyJobID != nil)
            }
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
    }

    private func startDriving(_ job: Job, etaMinutes: Int?) async {
        guard busyJobID == nil, !startedDriving.contains(job.id),
              MyDayRules.canStartDriving(job, canEdit: session.can("job.edit", feature: "jobs")) else { return }
        busyJobID = job.id
        defer { busyJobID = nil }
        do {
            _ = try await api.progressFieldJob(job.id, request: .enRoute(etaMinutes: etaMinutes))
            startedDriving.insert(job.id)
            progressError = nil
            if await store.refresh(api) == .failed {
                progressError = "Driving started. The latest job list could not be refreshed."
            }
        } catch is CancellationError {
        } catch {
            progressError = error.localizedDescription
        }
    }

    @ViewBuilder private func group(_ title: String, jobs: [Job]) -> some View {
        if !jobs.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(title).font(Theme.font(13, weight: .medium))
                Text("\(jobs.count)").font(Theme.monoFont(12))
                Spacer()
                if session.can("job.create", feature: "jobs") {
                    Button { showNew = true } label: { Image(systemName: "plus").font(.system(size: 13)).frame(width: 20, height: 20).frame(width: 44, height: 44).contentShape(Rectangle()) }.accessibilityLabel("New job")
                }
            }.foregroundStyle(Theme.muted)
            .padding(.horizontal, 2).padding(.bottom, 6)
            VStack(spacing: 2) {
                ForEach(jobs) { job in
                    NavigationLink(value: job) {
                        HStack(spacing: 10) {
                            Image(systemName: statusIcon(job.status).0)
                                .font(.system(size: 16)).foregroundStyle(statusIcon(job.status).1)
                                .frame(width: 22)
                            Text(job.shortRef).font(Theme.monoFont(12, weight: .medium)).foregroundStyle(Theme.muted)
                                .frame(width: 62, alignment: .leading)
                            Text(job.title).font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if let name = job.assignedToUserId == session.user?.id ? session.user?.name : nil {
                                Text(initials(name)).font(Theme.font(10, weight: .semibold))
                                    .foregroundStyle(Theme.brand)
                                    .frame(width: 24, height: 24)
                                    .background(Theme.brandSurface, in: Circle())
                            }
                        }
                        .padding(.horizontal, 2).padding(.vertical, 4)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            }
        }
    }
}

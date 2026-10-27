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
            PaperTabs(options: ["Today", "Week", "Map"], selection: $tab)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let error = store.error { ErrorBanner(message: error) }
                    if store.loading { ProgressView("Updating schedule…") }
                    if tab == "Map" {
                        ContentUnavailableView("Map unavailable", systemImage: "map",
                            description: Text("Job list records do not include map coordinates. Use Today or Week to open a job."))
                            .frame(maxWidth: .infinity)
                    } else {
                        rangeMenu
                        scheduleContent
                    }
                }
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 120)
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
        HStack {
            Spacer()
            Menu {
                Button("Today") { tab = "Today" }
                Button("Week") { tab = "Week" }
                Button("Unscheduled") { tab = "Unscheduled" }
            } label: {
                Label(tab == "Unscheduled" ? "Unscheduled" : "More ranges", systemImage: "calendar.badge.clock")
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    @ViewBuilder private var scheduleContent: some View {
        if let first = jobs.first {
            Text(tab == "Unscheduled" ? "Needs a time" : "Next up")
                .font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
            ScheduleHero(job: first, customer: store.customerName(first.customerId))
            if jobs.count > 1 {
                HStack {
                    Text(tab == "Today" ? "Later today" : tab == "Week" ? "Later this week" : "More jobs")
                        .font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                    Text("\(jobs.count - 1)").font(Theme.monoFont(12)).foregroundStyle(Theme.muted)
                    Spacer()
                }
                VStack(spacing: 0) {
                    ForEach(Array(jobs.dropFirst())) { job in
                        ScheduleCompactRow(job: job, customer: store.customerName(job.customerId))
                        if job.id != jobs.last?.id { Rectangle().fill(Theme.border).frame(height: 1) }
                    }
                }
                .padding(.horizontal, 14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
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
                        .padding(.horizontal, 18).frame(height: 42)
                        .background(Theme.brand, in: RoundedRectangle(cornerRadius: 9))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 44)
            .padding(.horizontal, 20)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

private struct ScheduleHero: View {
    let job: Job
    let customer: String

    var body: some View {
        NavigationLink(value: job) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    if let date = JobFiltering.date(job.scheduledFor) {
                        Text(date.formatted(.dateTime.hour().minute()))
                            .font(Theme.monoFont(13, weight: .semibold)).foregroundStyle(Theme.brand)
                    } else {
                        Text("Time not set").font(Theme.monoFont(13)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Text(job.shortRef).font(Theme.monoFont(11)).foregroundStyle(Theme.muted)
                }
                Text(job.title).font(Theme.font(19, weight: .semibold)).foregroundStyle(Theme.foreground)
                    .multilineTextAlignment(.leading)
                Text(customer).font(Theme.font(13)).foregroundStyle(Theme.muted)
                HStack(spacing: 6) {
                    Image(systemName: statusIcon(job.status).0)
                    Text(job.status.statusLabel)
                }
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(statusIcon(job.status).1)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(statusIcon(job.status).1.opacity(0.12), in: Capsule())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
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
                VStack(alignment: .leading, spacing: 2) {
                    if let date = JobFiltering.date(job.scheduledFor) {
                        Text(date.formatted(.dateTime.hour().minute())).font(Theme.monoFont(12, weight: .medium))
                    } else { Text("—").font(Theme.monoFont(12)) }
                    Text(job.shortRef).font(Theme.monoFont(10)).foregroundStyle(Theme.muted)
                }
                .frame(width: 74, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    Text(job.title).font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.foreground).lineLimit(1)
                    Text("\(customer) · \(job.status.statusLabel)")
                        .font(Theme.font(12)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Theme.muted)
            }
            .padding(.vertical, 13)
        }
        .buttonStyle(.plain)
    }
}

struct JobsView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController
    @State private var tab = "Assigned"
    @State private var search = ""
    @State private var searchVisible = false
    @State private var showNew = false

    private var jobs: [Job] {
        let assigned = tab == "Assigned" ? (session.user?.id ?? "") : nil
        return JobFiltering.jobs(store.jobs, assignedTo: assigned, search: search)
    }
    private var activeCount: Int { jobs.filter { !["completed", "canceled"].contains($0.status) }.count }
    private var attentionCount: Int { jobs.filter { ["paused", "canceled"].contains($0.status) }.count }

    var body: some View {
        VStack(spacing: 0) {
            PaperHeader(title: "Jobs", icon: "briefcase", subtitle: "\(activeCount) active · \(attentionCount) need attention") {
                searchVisible.toggle()
            }
            if searchVisible { PaperSearchField(text: $search, prompt: "Title or job reference") }
            PaperTabs(options: ["Assigned", "All jobs", "Recent"], selection: $tab)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let error = store.error { ErrorBanner(message: error) }
                    if store.loading { ProgressView("Updating jobs…") }
                    if tab == "Recent" {
                        group("Recently updated", jobs: jobs)
                    } else {
                        group("In progress", jobs: PaperWorkGroups.inProgress(jobs))
                        group("Scheduled", jobs: PaperWorkGroups.scheduled(jobs))
                        group("Completed", jobs: PaperWorkGroups.completed(jobs))
                        group("Other", jobs: PaperWorkGroups.other(jobs))
                    }
                    if jobs.isEmpty && !store.loading {
                        ContentUnavailableView(search.isEmpty ? "No jobs" : "No matching jobs", systemImage: "briefcase",
                            description: Text(search.isEmpty ? "Jobs in this view appear here." : "Try another title or job reference."))
                    }
                }
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 120)
            }
            .refreshable { await store.refresh(api) }
        }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if session.can("job.create", feature: "jobs") {
                Button { showNew = true } label: {
                    Label("New job", systemImage: "plus")
                        .font(Theme.font(14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18).frame(height: 42)
                        .background(Theme.brand, in: Capsule())
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 16).padding(.bottom, 7)
            }
        }
        .sheet(isPresented: $showNew) { NewJobSheet() }
    }

    @ViewBuilder private func group(_ title: String, jobs: [Job]) -> some View {
        if !jobs.isEmpty {
            HStack(spacing: 8) {
                Text(title).font(Theme.font(13, weight: .medium))
                Text("\(jobs.count)").font(Theme.monoFont(12))
                Spacer()
                Rectangle().fill(Theme.border).frame(width: 22, height: 1)
            }.foregroundStyle(Theme.muted)
            VStack(spacing: 0) {
                ForEach(jobs) { job in
                    NavigationLink(value: job) {
                        HStack(spacing: 10) {
                            Image(systemName: statusIcon(job.status).0)
                                .font(.system(size: 16)).foregroundStyle(statusIcon(job.status).1)
                                .frame(width: 22)
                            Text(job.shortRef).font(Theme.monoFont(11)).foregroundStyle(Theme.muted)
                                .frame(width: 72, alignment: .leading)
                            Text(job.title).font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.foreground)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if let name = job.assignedToUserId == session.user?.id ? session.user?.name : nil {
                                Text(initials(name)).font(Theme.font(10, weight: .semibold))
                                    .foregroundStyle(Theme.brand)
                                    .frame(width: 24, height: 24)
                                    .background(Theme.brandSurface, in: Circle())
                            }
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

import SwiftUI

/// PIM-0's middle and detail columns. RootView supplies the 244-point sidebar.
struct PaperTabletSchedule: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController
    @State private var range = "Today"
    @State private var selectedID: String?
    @State private var showNewJob = false

    private var jobs: [Job] {
        guard session.can("job.view", feature: "jobs") else { return [] }
        return JobFiltering.schedule(store.jobs, range: range == "Week" ? .week : .today)
    }
    private var selectedJob: Job? { jobs.first { $0.id == selectedID } }
    private var subtitle: String {
        if range == "Week" { return "\(jobs.count) jobs this week" }
        return "\(Date().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · \(jobs.count) jobs today"
    }

    var body: some View {
        HStack(spacing: 0) {
            scheduleColumn
                .frame(width: 350)
                .overlay(alignment: .trailing) { Rectangle().fill(Theme.border).frame(width: 1) }
            NavigationStack {
                Group {
                    if range == "Map" {
                        ContentUnavailableView("Map unavailable", systemImage: "map", description: Text("Job list records do not include map coordinates. Select Today or Week to view your schedule."))
                    } else if let selectedJob {
                        JobDetailView(jobId: selectedJob.id, showsBack: false)
                            .id(selectedJob)
                    } else if store.loading {
                        ProgressView("Updating schedule…")
                    } else {
                        ContentUnavailableView("No job selected", systemImage: "calendar", description: Text("Choose a scheduled job to view its details."))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background)
                .navigationDestination(for: Job.self) { JobDetailView(jobId: $0.id) }
                .navigationDestination(for: Customer.self) { CustomerDetailView(customer: $0) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background)
        .onChange(of: jobs.map(\.id), initial: true) { _, ids in
            if selectedID.map({ ids.contains($0) }) != true { selectedID = ids.first }
        }
        .sheet(isPresented: $showNewJob) { NewJobSheet() }
    }

    private var scheduleColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text("Schedule").font(Theme.font(16, weight: .semibold)).tracking(-0.16)
                    Spacer()
                    if session.can("job.create", feature: "jobs") {
                        Button { showNewJob = true } label: {
                            Image(systemName: "plus").font(.system(size: 15)).frame(width: 26, height: 26)
                                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 6))
                        }.buttonStyle(.plain).accessibilityLabel("New job")
                    }
                }.frame(minHeight: 26)
                Text(subtitle).font(Theme.font(13)).foregroundStyle(Theme.muted).frame(minHeight: 18, alignment: .leading)
            }
            .padding(.horizontal, 18).padding(.bottom, 12)
            HStack(spacing: 3) {
                ForEach(["Today", "Week", "Map"], id: \.self) { item in
                    Button { range = item } label: {
                        Text(item).font(Theme.font(13, weight: range == item ? .semibold : .medium))
                            .foregroundStyle(range == item ? Theme.foreground : Theme.muted)
                            .padding(.vertical, 5).padding(.horizontal, 11)
                            .background(range == item ? Theme.fill : .clear, in: Capsule())
                    }.buttonStyle(.plain).accessibilityAddTraits(range == item ? .isSelected : [])
                }
            }.padding(.horizontal, 14).padding(.bottom, 12)
            ScrollView {
                LazyVStack(spacing: 0) {
                    if let error = store.error { ErrorBanner(message: error) }
                    if range == "Map" {
                        Text("Select Today or Week to view scheduled jobs.")
                            .font(Theme.font(13)).foregroundStyle(Theme.muted).padding(18)
                    } else {
                        ForEach(jobs) { job in scheduleRow(job) }
                        if jobs.isEmpty && !store.loading {
                            ContentUnavailableView("No scheduled jobs", systemImage: "calendar", description: Text(range == "Week" ? "No active jobs this week." : "No active jobs today."))
                        }
                        if store.loading { ProgressView("Updating…").padding(18) }
                    }
                }.padding(.horizontal, 8).padding(.bottom, 16)
            }
            .refreshable { await store.refresh(api) }
        }
        .padding(.top, 16)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func scheduleRow(_ job: Job) -> some View {
        let selected = selectedID == job.id
        return Button { selectedID = job.id } label: {
            HStack(spacing: 10) {
                Text(time(job.scheduledFor))
                    .font(Theme.monoFont(12, weight: .medium))
                    .foregroundStyle(selected ? Theme.foreground : Theme.muted)
                    .frame(width: 52, alignment: .leading)
                Capsule().fill(selected ? Theme.brand : statusColor(job.status)).frame(width: 3, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(job.title).font(Theme.font(14, weight: selected ? .semibold : .medium))
                        .foregroundStyle(Theme.foreground).lineLimit(2)
                    Text("\(job.status.statusLabel) · \(store.customerName(job.customerId))")
                        .font(Theme.font(12)).foregroundStyle(Theme.muted).lineLimit(2)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10).padding(.vertical, 6).frame(minHeight: 56)
            .background(selected ? Theme.fill : .clear, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel("\(time(job.scheduledFor)), \(job.title), \(job.status.statusLabel)")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "en_route", "dispatched": Theme.brand
        case "in_progress", "arrived", "paused": Theme.warning
        default: Color.white.opacity(0.4)
        }
    }
    private func time(_ raw: String?) -> String {
        guard let date = JobFiltering.date(raw) else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mma"
        formatter.amSymbol = "a"
        formatter.pmSymbol = "p"
        return formatter.string(from: date)
    }
}

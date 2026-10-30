import SwiftUI

/// PIM-0's middle and detail columns. RootView supplies the 244-point sidebar.
struct PaperTabletSchedule: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController
    @State private var range = "Today"
    @State private var selectedID: String?
    @State private var showNewJob = false
    @Binding var typedPath: [PaperTypedJobsRoute]
    let typedOwner: PaperTypedJobsOwner
    @Binding var priceBook: Bool
    @Binding var drafts: Bool

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
            Group {
                if PaperTypedRouteExperiment.enabled {
                    NavigationStack(path: Binding(get: { typedPath }, set: { next in
                        let old = typedPath
                        typedPath = next
                        typedOwner.changed(from: old, to: next)
                    })) {
                        detailContent
                            .environment(\.paperTypedJobsOwner, typedOwner)
                            .navigationDestination(for: PaperTypedJobsRoute.self) { route in
                                PaperTypedDestination(route: route).environment(\.paperTypedJobsOwner, typedOwner)
                            }
                            .navigationDestination(isPresented: $priceBook) {
                                WorkspacePriceBookView(api: api, canList: true, canViewDetail: session.can("organization.settings.edit", feature: "price_book")).id(session.generation)
                            }
                            .navigationDestination(isPresented: $drafts) {
                                if let actor = session.user?.id, let org = session.activeOrganization?.id {
                                    InboxLocalDraftView(actorID: actor, organizationID: org)
                                }
                            }
                    }
                } else {
                    NavigationStack {
                        detailContent
                            .environment(\.paperTypedJobsOwner, nil)
                            .navigationDestination(for: Job.self) { JobDetailView(jobId: $0.id) }
                            .navigationDestination(for: Customer.self) { CustomerDetailView(customer: $0) }
                            .navigationDestination(for: PaperRoute.self) { PaperRouteView(route: $0) }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background)
        .onChange(of: jobs.map(\.id), initial: true) { _, ids in
            if selectedID.map({ ids.contains($0) }) != true { selectedID = ids.first }
        }
        .onChange(of: selectedID) { _, _ in
            if PaperTypedRouteExperiment.enabled { typedOwner.discardPendingPop(); typedPath = [] }
        }
        .sheet(isPresented: $showNewJob) { NewJobSheet() }
    }

    private var detailContent: some View {
        Group {
                    if range == "Map" {
                        // iPad gets the same route map as the phone, beside today's list.
                        ScrollView {
                            ScheduleMapView(jobs: jobs.filter { $0.status != "canceled" }, selection: $selectedID).padding(.top, 16)
                        }
                        .background(Theme.background)
                    } else if let selectedJob {
                        JobDetailView(jobId: selectedJob.id, showsBack: false)
                            .id(selectedJob)
                    } else if store.loading && store.jobs.isEmpty {
                        SkeletonRows(count: 8, leading: false)
                            .frame(maxHeight: .infinity, alignment: .top)
                    } else {
                        PaperEmptyState(symbol: "calendar", title: "Pick a job",
                                        message: "Choose a job on the left to see its details, notes and invoice here.")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background)
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
                                .background(Theme.fill, in: Circle())
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("New job")
                    }
                }.frame(minHeight: 44)
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
                            .frame(minHeight: 44)
                    }.buttonStyle(.plain).accessibilityAddTraits(range == item ? .isSelected : [])
                }
            }.padding(.horizontal, 14).padding(.bottom, 12)
            ScrollView {
                LazyVStack(spacing: 0) {
                    if let error = store.error { ErrorBanner(message: error) }
                    Group {
                        ForEach(jobs) { job in scheduleRow(job) }
                        if jobs.isEmpty && !store.loading {
                            PaperEmptyState(symbol: "calendar", title: range == "Week" ? "Nothing booked this week" : "Nothing booked today",
                                            message: "Booked jobs show here in time order.",
                                            actionTitle: session.can("job.create", feature: "jobs") ? "New job" : nil,
                                            action: session.can("job.create", feature: "jobs") ? { showNewJob = true } : nil)
                        }
                        if store.loading && jobs.isEmpty { SkeletonRows(count: 5, leading: false) }
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
            .background(selected ? Theme.fill : .clear, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
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

import SwiftUI

/// PIM-0's middle and detail columns. RootView supplies the 244-point sidebar.
struct PaperTabletSchedule: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController
    @State private var range = "Today"
    @State private var selectedID: String?
    @State private var showNewJob = false
    @StateObject private var addresses = JobAddressBook()

    private var jobs: [Job] {
        guard session.can("job.view", feature: "jobs") else { return [] }
        return JobFiltering.schedule(store.jobs, range: range == "Week" ? .week : .today)
    }
    private var selectedJob: Job? { jobs.first { $0.id == selectedID } }
    private var subtitle: String {
        if range == "Week" { return "\(jobs.count) jobs this week" }
        return "\(Date().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · \(jobs.count) jobs today"
    }

    /// The detail pane is rebuilt only when a different job is chosen. `Job` hashes every field,
    /// so keying on it rebuilt the pane on each store refresh and lost the chosen invoice.
    static func detailIdentity(_ job: Job) -> String { job.id }

    var body: some View {
        HStack(spacing: 0) {
            scheduleColumn
                .frame(width: 350)
                .overlay(alignment: .trailing) { Rectangle().fill(Theme.border).frame(width: 1) }
            // No NavigationStack here: RootView's tablet stack owns every push from this pane
            // (invoice, estimate, customer, activity rows) as well as deep links. A second stack
            // nested in its root dropped those pushes.
            Group {
                if range == "Map" {
                    // iPad gets the same route map as the phone, beside today's list.
                    ScrollView {
                        ScheduleMapView(jobs: jobs.filter { $0.status != "canceled" }, selection: $selectedID).padding(.top, 16)
                    }
                    .background(Theme.background)
                } else if let selectedJob {
                    JobDetailView(jobId: selectedJob.id, showsBack: false)
                        .id(Self.detailIdentity(selectedJob))
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
        .foregroundStyle(Theme.foreground)
        .background(Theme.background)
        .onChange(of: jobs.map(\.id), initial: true) { _, ids in
            if selectedID.map({ ids.contains($0) }) != true { selectedID = ids.first }
        }
        .sheet(isPresented: $showNewJob) { NewJobSheet() }
        .task(id: "addr|\(jobs.map { "\($0.id):\($0.locationId ?? "")" }.joined(separator: ","))|\(session.generation)") {
            guard session.can("customer.view", feature: "core_crm") else { return }
            await addresses.load(jobs, api: api, organizationID: session.activeOrganization?.id,
                                 identity: "\(session.user?.id ?? "")|\(session.activeOrganization?.id ?? "")|\(session.generation)")
        }
    }

    private var scheduleColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text("Schedule").font(Theme.font(22, weight: .medium)).tracking(-0.3)
                    Spacer()
                    if session.can("job.create", feature: "jobs") {
                        Button { showNewJob = true } label: {
                            PaperCircleLabel(symbol: "plus", size: 36)
                        }.buttonStyle(PressStyle()).accessibilityLabel("New job")
                    }
                }.frame(minHeight: 44)
                Text(subtitle).font(Theme.font(13)).foregroundStyle(Theme.muted).frame(minHeight: 18, alignment: .leading)
            }
            .padding(.horizontal, 18).padding(.bottom, 12)
            // design 2026-10-30: the one segmented selector.
            PaperTabs(options: ["Today", "Week", "Map"], selection: $range)
                .environment(\.paperRowInset, 14)
                .padding(.horizontal, -6).padding(.bottom, 8)
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

    /// The phone's row: time column, street first (the job title when there's no place),
    /// status as a word. The chosen job sits on a quiet fill; nothing else is tinted.
    private func scheduleRow(_ job: Job) -> some View {
        let selected = selectedID == job.id
        let street = addresses.street(job)
        let customer = store.customerName(job.customerId)
        return Button { selectedID = job.id } label: {
            PaperListRow(leading: .text(time(job.scheduledFor)), title: street ?? job.title,
                         subtitle: street != nil ? "\(job.title) · \(customer)" : customer,
                         subtitleLines: 2, dimmed: job.status == "completed") {
                StatusWord(jobStatus: job.status)
            }
            .environment(\.paperRowInset, 10)
            .background(selected ? Theme.fill : .clear, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
            .contentShape(Rectangle())
        }.buttonStyle(RowPressStyle())
            .accessibilityLabel("\(time(job.scheduledFor)), \(street ?? job.title), \(job.status.statusLabel)")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func time(_ raw: String?) -> String {
        guard let date = JobFiltering.date(raw) else { return "No time" }
        return date.tradeTime
    }
}

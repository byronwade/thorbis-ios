import SwiftUI

/// The iPad Schedule's list column: Today / Week / Map, then the day's jobs. TabletRoot owns the
/// detail column beside it (the job or the map) and the selection; Week is a full-width board.
struct PaperTabletSchedule: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController
    @Binding var range: String
    @Binding var selectedID: String?
    @ObservedObject var addresses: JobAddressBook
    let newJob: (() -> Void)?

    static let ranges = ["Today", "Week", "Map"]

    /// The detail pane is rebuilt only when a different job is chosen. `Job` hashes every field,
    /// so keying on it rebuilt the pane on each store refresh and lost the chosen invoice.
    static func detailIdentity(_ job: Job) -> String { job.id }

    /// Today's jobs (also what the map plots).
    static func todayJobs(_ jobs: [Job], canView: Bool) -> [Job] {
        canView ? JobFiltering.schedule(jobs, range: .today) : []
    }

    private var jobs: [Job] { Self.todayJobs(store.jobs, canView: session.can("job.view", feature: "jobs")) }
    private var subtitle: String {
        "\(Date().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · \(jobs.count) \(jobs.count == 1 ? "job" : "jobs") today"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Schedule").font(Theme.font(30, weight: .medium)).tracking(-0.6)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle).font(Theme.font(15)).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, Theme.gutter).padding(.top, 12).padding(.bottom, 12)
            // design 2026-10-30: the one segmented selector.
            PaperTabs(options: Self.ranges, selection: $range)
                .padding(.bottom, 8)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let error = store.error { ErrorBanner(message: error) }
                    if !jobs.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(jobs.enumerated()), id: \.element.id) { index, job in
                                scheduleRow(job, showsPeriod: TimeColumn.showsPeriod(jobs, at: index))
                            }
                        }
                            .padding(4)
                            .panelBackground(cornerRadius: Theme.cardRadius)
                            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.border.opacity(0.6)))
                    }
                    if jobs.isEmpty && !store.loading {
                        PaperEmptyState(symbol: "calendar", title: "Nothing booked today",
                                        actionTitle: newJob == nil ? nil : "Book a job", action: newJob)
                    }
                    if store.loading && jobs.isEmpty { SkeletonRows(count: 5, leading: false) }
                }
                .padding(.horizontal, 12).padding(.bottom, 16)
            }
            .refreshable { await store.refresh(api) }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .foregroundStyle(Theme.foreground)
        .background(Theme.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: jobs.map(\.id), initial: true) { _, ids in
            if selectedID.map({ ids.contains($0) }) != true, let first = ids.first { selectedID = first }
        }
    }

    /// The phone's row: time column, street first (the job title when there's no place),
    /// status as a word. The chosen job sits on the blue selection fill.
    private func scheduleRow(_ job: Job, showsPeriod: Bool) -> some View {
        let selected = selectedID == job.id
        let street = addresses.street(job)
        let customer = store.customerName(job.customerId)
        let date = JobFiltering.date(job.scheduledFor)
        let time = date?.tradeTime ?? "No time"
        // The column reads 10:30, 12:15, 1:00: the period under the time only where it changes.
        let leading: PaperRowLeading = date.map { .clock($0.columnTime, period: showsPeriod ? $0.periodMark : nil, accessibility: $0.tradeTime) }
            ?? .text(time)
        return Button { selectedID = job.id } label: {
            PaperListRow(leading: leading, title: street ?? job.title,
                         subtitle: street != nil ? "\(job.title) · \(customer)" : customer,
                         subtitleLines: 2, dimmed: job.status == "completed") {
                StatusWord(jobStatus: job.status)
            }
            .environment(\.paperRowInset, 12)
            .background {
                if selected { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.brandSurface) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .jobContextMenu(job, customer: customer)
        .accessibilityLabel("\(time), \(street ?? job.title), \(job.status.statusLabel)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

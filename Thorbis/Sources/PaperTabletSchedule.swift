import SwiftUI

/// Paper T01, the iPad Schedule's list column: the title and +, Search or ask, the Today / Week / Map
/// segments, then the day's jobs on one card. TabletRoot owns the detail column beside it (the job
/// or the map) and the selection; Week and Board are full-width.
struct PaperTabletSchedule: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController
    @Binding var range: String
    @Binding var selectedID: String?
    @ObservedObject var addresses: JobAddressBook
    let newJob: (() -> Void)?
    /// Opens search everywhere (the column's "Search or ask" field). Nil hides the field.
    var search: (() -> Void)? = nil
    /// The rows' swipes, as on the phone's Today: Call and Directions to the right, the next move to the left.
    @StateObject private var swipes = JobRowSwipeBook()

    static let ranges = ["Today", "Week", "Map"]
    /// Roles that assign work also get the Board (Paper T12C), as on the phone's Schedule.
    static func rangeOptions(board: Bool) -> [String] { board ? ["Today", "Week", "Board", "Map"] : ranges }
    /// The column's side margin: Paper sets its cards 8 from the columns beside them.
    static let margin: CGFloat = 8

    /// The detail pane is rebuilt only when a different job is chosen. `Job` hashes every field,
    /// so keying on it rebuilt the pane on each store refresh and lost the chosen invoice.
    static func detailIdentity(_ job: Job) -> String { job.id }

    /// Today's jobs (also what the map plots).
    static func todayJobs(_ jobs: [Job], canView: Bool) -> [Job] {
        canView ? JobFiltering.schedule(jobs, range: .today) : []
    }

    private var jobs: [Job] { Self.todayJobs(store.jobs, canView: session.can("job.view", feature: "jobs")) }
    private var options: [String] { Self.rangeOptions(board: session.can("job.assign", feature: "jobs")) }
    /// "Tuesday, July 21 · 4 jobs today"
    private var subtitle: String {
        "\(Date().formatted(.dateTime.weekday(.wide).month(.wide).day())) · \(jobs.count) \(jobs.count == 1 ? "job" : "jobs") today"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Schedule").font(Theme.font(34, weight: .bold)).tracking(-0.68)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("schedule-title")
                    Text(subtitle).font(Theme.font(15)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let newJob {
                    Button(action: newJob) { CreamCircleLabel(symbol: "plus") }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel("New job")
                        .accessibilityIdentifier("schedule-new-job")
                }
            }
            .padding(.leading, Self.margin + 4).padding(.trailing, Self.margin).padding(.top, 10)
            if let search {
                Button(action: search) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .medium))
                            .accessibilityHidden(true)
                        Text("Search or ask").font(Theme.font(16)).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Search")
                .accessibilityHint("Jobs, customers, invoices")
                .accessibilityIdentifier("schedule-search")
                .padding(.horizontal, Self.margin).padding(.top, 14)
            }
            // Paper's segments: the card track with the raised pill (the tabs bring a 16 margin of their own).
            PaperTabs(options: options, selection: $range)
                .padding(.horizontal, Self.margin - PaperCardMetrics.margin)
                .padding(.top, 12)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if let error = store.error { ErrorBanner(message: error) }
                    if let problem = swipes.problem { ErrorBanner(message: problem) }
                    if !jobs.isEmpty {
                        // The day on one card, the chosen job on the blue fill.
                        VStack(spacing: 0) {
                            ForEach(Array(jobs.enumerated()), id: \.element.id) { index, job in
                                scheduleRow(job, ruled: index > 0 && selectedID != job.id && selectedID != jobs[index - 1].id)
                            }
                        }
                        .padding(6)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    }
                    if jobs.isEmpty && !store.loading {
                        PaperEmptyState(symbol: "calendar", title: "Nothing booked today",
                                        actionTitle: newJob == nil ? nil : "Book a job", action: newJob)
                    }
                    if store.loading && jobs.isEmpty { SkeletonRows(count: 5, leading: false) }
                }
                .padding(.horizontal, Self.margin).padding(.top, 16).padding(.bottom, 16)
            }
            .refreshable { await store.refresh(api) }
            .onScrollPhaseChange { _, phase in if phase != .idle { swipes.rows.close() } }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .foregroundStyle(Theme.foreground)
        .background(Theme.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .sensoryFeedback(.success, trigger: swipes.confirmed)
        .sensoryFeedback(.impact(weight: .light), trigger: swipes.queued)
        .task(id: "swipes|\(session.user?.id ?? "")|\(session.activeOrganization?.id ?? "")|\(session.generation)") {
            swipes.reset(identity: "\(session.user?.id ?? "")|\(session.activeOrganization?.id ?? "")|\(session.generation)")
        }
        .onChange(of: jobs.map(\.id), initial: true) { _, ids in
            if selectedID.map({ ids.contains($0) }) != true, let first = ids.first { selectedID = first }
        }
    }

    /// Paper T01's row: the time in a 76pt column, "AC not cooling — Marlowe" over
    /// "Working · 412 Birchwood Ln". The chosen job sits on the blue selection fill; a hairline
    /// separates the others (`ruled`).
    private func scheduleRow(_ job: Job, ruled: Bool) -> some View {
        let selected = selectedID == job.id
        let street = addresses.street(job)
        let customer = store.customerName(job.customerId)
        let time = JobFiltering.date(job.scheduledFor)?.tradeTime ?? "No time"
        let title = "\(job.title) \u{2014} \(customer)"
        let detail = [job.status.statusLabel, street].compactMap { $0 }.joined(separator: " · ")
        return JobSwipeRow(job: job, customer: customer, book: swipes, places: addresses) { actions in
            Button { selectedID = job.id } label: {
                HStack(alignment: .center, spacing: 0) {
                    Text(time).font(Theme.font(14, weight: .medium)).monospacedDigit()
                        .foregroundStyle(selected ? Theme.foreground : Theme.subtle)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(width: 76, alignment: .leading)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title.dashKeptWithWordBefore).font(Theme.font(16, weight: .medium)).tracking(-0.16)
                            .foregroundStyle(Theme.foreground)
                            .lineLimit(2).multilineTextAlignment(.leading)
                        Text(detail).font(Theme.font(14))
                            .foregroundStyle(selected ? Theme.subtle : Theme.muted)
                            .lineLimit(2).multilineTextAlignment(.leading)
                    }
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                    .overlay(alignment: .top) {
                        if ruled { Rectangle().fill(Theme.hairline).frame(height: 1).accessibilityHidden(true) }
                    }
                }
                .padding(.leading, 10).padding(.trailing, 8)
                .opacity(job.status == "completed" ? 0.7 : 1)
                .background {
                    if selected { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.brandSurface) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .jobContextMenu(job, customer: customer)
            .accessibilityLabel("\(time), \(street ?? job.title), \(job.status.statusLabel)")
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("today-row-\(job.id)")
            .rowSwipeAccessibility(actions)
        }
    }
}

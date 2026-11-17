import SwiftUI

/// `GET /v1/reports/operations` (services/api composition/reports.ts OperationsReport).
struct OperationsReport: Decodable {
    struct Estimates: Decodable { let drafts, presented, approved, declined, conversionBps: Int }
    struct Jobs: Decodable { let booked, completed, canceled, open: Int }
    struct Month: Decodable, Identifiable { let month: String; let booked, completed: Int; var id: String { month } }
    let generatedAt: String
    let reportVersion: Int
    let estimates: Estimates
    let jobs: Jobs
    let months: [Month]
    let truncated: Bool
}

/// `GET /v1/reports/schedule` (ScheduleReport). Booked time only; no invented capacity.
struct ScheduleReport: Decodable {
    struct Day: Decodable, Identifiable { let day: String; let scheduled, completed: Int; var id: String { day } }
    struct Backlog: Decodable { let unscheduledOpenJobs, overdueScheduledJobs: Int }
    let generatedAt: String
    let reportVersion: Int
    let days: [Day]
    let backlog: Backlog
    let truncated: Bool
}

/// `GET /v1/reports/payment-activity` (PaymentActivityReport). Integer minor units; reversals never netted.
struct PaymentActivityReport: Decodable {
    struct Month: Decodable, Identifiable {
        let month: String
        let recorded, refunded, discounts, depositCredits, retainageWithheld, otherAdjustments: Int
        var id: String { month }
    }
    struct Totals: Decodable {
        let recordedCount, recorded, refundedCount, refunded, discountCount, discounts: Int
        let depositCreditCount, depositCredits, retainageWithheldCount, retainageWithheld: Int
        let otherAdjustmentCount, otherAdjustments: Int
    }
    let generatedAt: String
    let reportVersion: Int
    let months: [Month]
    let totals: Totals
    let truncated: Bool
}

/// `GET /v1/reports/activity` (CustomerActivityReport): all-time counts and invoice revenue per customer.
struct CustomerActivityReport: Decodable {
    struct Row: Decodable, Identifiable {
        let customerId: String
        let estimates, jobs, invoices, revenue: Int
        var id: String { customerId }
    }
    let generatedAt: String
    let customers: [Row]
    let truncated: Bool

    /// Who buys: the five customers with the most invoiced revenue.
    var topCustomers: [Row] { Array(customers.filter { $0.revenue > 0 }.sorted { $0.revenue > $1.revenue }.prefix(5)) }
}

extension APIClient {
    func customerActivityReport() async throws -> CustomerActivityReport { try await send("GET", "/v1/reports/activity") }
    func paymentActivityReport() async throws -> PaymentActivityReport { try await send("GET", "/v1/reports/payment-activity") }
    func operationsReport() async throws -> OperationsReport { try await send("GET", "/v1/reports/operations") }
    func scheduleReport() async throws -> ScheduleReport { try await send("GET", "/v1/reports/schedule") }
}

/// Paper 60: the numbers an owner checks, as words and mono figures; each report says when it's incomplete.
/// For anyone who can see revenue this is the one Money place: Revenue first, then the reports, so
/// every figure from the old Money and Reports screens is one tab away.
struct ReportsView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    /// Money: Overview (web money.tsx) and Revenue lead the tabs and the header reads Money.
    var includesRevenue = false
    @State private var tab: String
    @State private var refreshes = 0
    @State private var operations: OperationsReport?
    @State private var schedule: ScheduleReport?
    @State private var payments: PaymentActivityReport?
    @State private var activity: CustomerActivityReport?
    @EnvironmentObject private var store: Store
    @State private var error: String?

    init(includesRevenue: Bool = false, initialTab: String? = nil) {
        self.includesRevenue = includesRevenue
        var start = initialTab ?? (includesRevenue ? "Overview" : "Operations")
        #if DEBUG
        // Screenshot-only: `--paper-preview-money-tab Payments` opens Money on that tab.
        let args = ProcessInfo.processInfo.arguments
        if PaperPreview.enabled, let at = args.firstIndex(of: "--paper-preview-money-tab"), args.indices.contains(at + 1) {
            start = args[at + 1]
        }
        #endif
        _tab = State(initialValue: start)
    }

    private var tabs: [String] {
        var result: [String] = []
        if includesRevenue && session.can("invoice.view", feature: "invoicing") { result.append("Overview") }
        if includesRevenue && MenuItem.money.permitted(session) { result.append("Revenue") }
        if session.can("estimate.view", feature: "estimates") { result.append("Operations") }
        if session.can("job.view", feature: "jobs") { result.append("Schedule") }
        if session.can("invoice.view", feature: "invoicing") { result.append("Payments") }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Paper 59/60: the 34 Bold title over the company and the day. A place root keeps the
                // drawer's circle; pushed, the back button leads.
                PaperHeader(title: includesRevenue ? "Money" : "Reports", subtitle: headerSubtitle)
                    .environment(\.paperMenuButton, false)
                // Paper's segmented control; wrapping keeps every report reachable on a narrow phone.
                if tabs.count > 1 { PaperTabs(options: tabs, selection: $tab, wrapOverflow: true).padding(.top, 4) }
                if let error { ErrorBanner(message: error) }
                Group {
                    if tabs.isEmpty {
                        PaperEmptyState(symbol: "chart.bar", title: "You can't see reports", message: "Your role doesn't include estimates, jobs or invoices. Ask an owner for access.")
                    } else if (tabs.contains(tab) ? tab : tabs[0]) == "Overview" {
                        MoneyOverviewView(embedded: true).id(refreshes)
                    } else if (tabs.contains(tab) ? tab : tabs[0]) == "Revenue" {
                        // Rebuilt on pull to refresh, so its figures reload with the rest.
                        WorkspaceRevenueView(api: api, available: true, embedded: true).id(refreshes)
                    } else if (tabs.contains(tab) ? tab : tabs[0]) == "Operations" {
                        if let operations { operationsContent(operations) } else { loadingState }
                    } else if (tabs.contains(tab) ? tab : tabs[0]) == "Payments" {
                        if let payments { paymentsContent(payments) } else { loadingState }
                    } else {
                        if let schedule { scheduleContent(schedule) } else { loadingState }
                    }
                }
                .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 16)
            }
            .padding(.bottom, 40)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .reportExports()
        .refreshable { refreshes += 1; await load() }
        .task { await load() }
    }

    /// "Wade's Plumbing · Tue, Jul 21" (Paper 59); Reports leads with what it covers (Paper 60).
    private var headerSubtitle: String {
        let company = session.activeOrganization?.name
        let date = Date.now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        if includesRevenue { return [company, date].compactMap { $0 }.joined(separator: " \u{00B7} ") }
        return ["Work and payments", company].compactMap { $0 }.joined(separator: " \u{00B7} ")
    }

    private var loadingState: some View { SkeletonRows(count: 4, leading: false, inset: 0) }

    // design 2026-10-30: every figure on a panel under its 13pt label; list rows are PaperListRow
    // with the figure on the right, never loose rows on the cream ground.
    @ViewBuilder private func operationsContent(_ report: OperationsReport) -> some View {
        if report.truncated { incomplete }
        else {
            VStack(alignment: .leading, spacing: 20) {
                PaperSection("Estimates") {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(report.estimates.conversionBps / 100)%").font(Theme.monoFont(34, weight: .bold)).tracking(-0.8)
                        Text("of presented estimates approved").font(Theme.font(15)).foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 4)
                    .accessibilityElement(children: .combine)
                    statRows( [
                        stat("Presented", report.estimates.presented),
                        stat("Approved", report.estimates.approved),
                        stat("Declined", report.estimates.declined),
                    ])
                }
                PaperSection("Jobs") {
                    statRows( [
                        stat("Booked", report.jobs.booked),
                        stat("Completed", report.jobs.completed),
                        stat("Open", report.jobs.open),
                    ])
                }
                if !report.months.isEmpty {
                    PaperSection("Jobs by month", count: report.months.count) {
                        rows(report.months.suffix(6).reversed().map { month in
                            (month.id, monthName(month.month), "\(month.completed) of \(month.booked) done")
                        })
                    }
                }
                if let activity, !activity.truncated, !activity.topCustomers.isEmpty {
                    PaperSection("Who buys", count: activity.topCustomers.count) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(activity.topCustomers) { row in
                                PaperListRow(title: store.customerName(row.customerId),
                                             subtitle: row.jobs == 1 ? "1 job" : "\(row.jobs) jobs") {
                                    // Paper 60: a row's figure in 16 Semibold tabular.
                                    Text(money(row.revenue, currency: "USD")).font(Theme.monoFont(16, weight: .semibold))
                                        .foregroundStyle(Theme.foreground)
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                        .padding(.vertical, PaperCardMetrics.edge)
                    }
                }
                footer(report.reportVersion, report.generatedAt)
            }
        }
    }

    @ViewBuilder private func scheduleContent(_ report: ScheduleReport) -> some View {
        if report.truncated { incomplete }
        else {
            VStack(alignment: .leading, spacing: 20) {
                PaperSection("Needs attention") {
                    statRows( [
                        stat("Unscheduled", report.backlog.unscheduledOpenJobs, alert: report.backlog.unscheduledOpenJobs > 0),
                        stat("Past due", report.backlog.overdueScheduledJobs, alert: report.backlog.overdueScheduledJobs > 0),
                    ])
                }
                let recent = Array(report.days.suffix(14).reversed())
                if !recent.isEmpty {
                    PaperSection("By day", count: recent.count) {
                        rows(recent.map { day in (day.id, dayName(day.day), "\(day.completed) of \(day.scheduled) done") })
                    }
                }
                footer(report.reportVersion, report.generatedAt)
            }
        }
    }

    @ViewBuilder private func paymentsContent(_ report: PaymentActivityReport) -> some View {
        if report.truncated { incomplete }
        else {
            VStack(alignment: .leading, spacing: 20) {
                PaperSection("All time") {
                    statRows( [
                        .init(label: "Payments", value: money(report.totals.recorded, currency: "USD"),
                              detail: entries(report.totals.recordedCount)),
                        .init(label: "Refunds", value: money(report.totals.refunded, currency: "USD"),
                              detail: entries(report.totals.refundedCount)),
                    ])
                }
                let credits = [("Discounts", report.totals.discounts, report.totals.discountCount),
                               ("Deposits applied", report.totals.depositCredits, report.totals.depositCreditCount),
                               ("Retainage withheld", report.totals.retainageWithheld, report.totals.retainageWithheldCount),
                               ("Other adjustments", report.totals.otherAdjustments, report.totals.otherAdjustmentCount)]
                    .filter { $0.2 > 0 }
                if !credits.isEmpty {
                    PaperSection("Credits on invoices") {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(credits, id: \.0) { credit in
                                PaperListRow(title: credit.0, subtitle: entries(credit.2), amount: money(credit.1, currency: "USD"))
                                    .accessibilityElement(children: .combine)
                            }
                        }
                        .padding(.vertical, PaperCardMetrics.edge)
                    }
                }
                if !report.months.isEmpty {
                    PaperSection("By month", count: report.months.count) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(report.months.suffix(6).reversed()) { month in
                                PaperListRow(title: monthName(month.month),
                                             subtitle: month.refunded > 0 ? "\(money(month.refunded, currency: "USD")) refunded" : nil,
                                             amount: money(month.recorded, currency: "USD"))
                                    .accessibilityElement(children: .combine)
                            }
                        }
                        .padding(.vertical, PaperCardMetrics.edge)
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("Refunds are shown on their own, never subtracted from payments.")
                        .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    footer(report.reportVersion, report.generatedAt)
                }
            }
        }
    }

    /// v2: figures as quiet rows (label, then the tabular figure on the trailing edge), not a row of
    /// equal tiles. A figure that needs someone carries its word with the mark.
    /// Paper 60's P&L rows: the label in 16 Medium, the figure in 16 Semibold tabular, 56 tall, a
    /// hairline between rows inset to the words.
    private func statRows(_ stats: [PaperStatRow.Stat]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(stats.enumerated()), id: \.element.id) { index, stat in
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        if stat.tint != Theme.foreground {
                            StatusLabel(tone: .attention, word: stat.label, size: 16)
                        } else {
                            Text(stat.label).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                        }
                        if let detail = stat.detail {
                            Text(detail).font(Theme.font(14)).monospacedDigit().foregroundStyle(Theme.muted)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(stat.value).font(Theme.monoFont(16, weight: .semibold)).foregroundStyle(Theme.foreground)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .padding(.trailing, 16).padding(.vertical, 10)
                .frame(minHeight: 56)
                .overlay(alignment: .top) { if index > 0 { WellDivider(leading: 0) } }
                .padding(.leading, 16)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func entries(_ count: Int) -> String { count == 1 ? "1 entry" : "\(count) entries" }

    /// Label on the left, the figure on the right, on one panel.
    private func rows(_ items: [(String, String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items, id: \.0) { item in
                PaperListRow(title: item.1) {
                    Text(item.2).font(Theme.font(15)).monospacedDigit().foregroundStyle(Theme.muted)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, PaperCardMetrics.edge)
    }

    private var incomplete: some View {
        PaperEmptyState(symbol: "exclamationmark.triangle", title: "This report is too big for the phone",
                        message: "These counts would come up short. Open the full report on the web.")
    }

    private func stat(_ label: String, _ value: Int, alert: Bool = false) -> PaperStatRow.Stat {
        .init(label: label, value: "\(value)", tint: alert ? Theme.warning : Theme.foreground)
    }

    private func footer(_ version: Int, _ generatedAt: String) -> some View {
        Text(generatedLabel(generatedAt)).font(Theme.font(13)).foregroundStyle(Theme.muted).padding(.top, 4)
    }

    private func generatedLabel(_ raw: String) -> String {
        guard let date = JobFiltering.date(raw) else { return "Months follow UTC" }
        // Under a minute reads "just now", not "1 second ago" on one tab and "now" on the next.
        let when = Date().timeIntervalSince(date) < 60 ? "just now" : date.formatted(.relative(presentation: .named))
        return "Updated \(when) · months follow UTC"
    }

    private func monthName(_ raw: String) -> String {
        let parts = raw.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]),
              let date = Calendar(identifier: .gregorian).date(from: DateComponents(timeZone: .gmt, year: year, month: month, day: 15)) else { return raw }
        return date.formatted(.dateTime.month(.wide).year())
    }

    private func dayName(_ raw: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .gmt
        guard let date = formatter.date(from: raw) else { return raw }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private func load() async {
        let generation = session.generation
        do {
            if session.can("estimate.view", feature: "estimates") {
                let loaded = try await api.operationsReport()
                guard session.generation == generation else { return }
                operations = loaded
            }
            if session.can("invoice.view", feature: "invoicing"), session.isFeatureOn("estimates"), session.isFeatureOn("jobs") {
                // Optional extra: the funnel still shows if this one fails.
                let loaded = try? await api.customerActivityReport()
                guard session.generation == generation else { return }
                activity = loaded
            }
            if session.can("job.view", feature: "jobs") {
                let loaded = try await api.scheduleReport()
                guard session.generation == generation else { return }
                schedule = loaded
            }
            if session.can("invoice.view", feature: "invoicing") {
                let loaded = try await api.paymentActivityReport()
                guard session.generation == generation else { return }
                payments = loaded
            }
            error = nil
        } catch is CancellationError {} catch {
            guard session.generation == generation else { return }
            self.error = error.localizedDescription
        }
    }
}

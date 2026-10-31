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

extension APIClient {
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
    /// Money: Revenue leads the tabs and the header reads Money.
    var includesRevenue = false
    @State private var tab: String
    @State private var refreshes = 0
    @State private var operations: OperationsReport?
    @State private var schedule: ScheduleReport?
    @State private var payments: PaymentActivityReport?
    @State private var error: String?

    init(includesRevenue: Bool = false, initialTab: String? = nil) {
        self.includesRevenue = includesRevenue
        _tab = State(initialValue: initialTab ?? (includesRevenue ? "Revenue" : "Operations"))
    }

    private var tabs: [String] {
        var result: [String] = []
        if includesRevenue && MenuItem.money.permitted(session) { result.append("Revenue") }
        if session.can("estimate.view", feature: "estimates") { result.append("Operations") }
        if session.can("job.view", feature: "jobs") { result.append("Schedule") }
        if session.can("invoice.view", feature: "invoicing") { result.append("Payments") }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(includesRevenue ? "Money" : "Reports").font(Theme.font(30, weight: .medium)).tracking(-0.6).accessibilityAddTraits(.isHeader)
                    Text(includesRevenue ? "Revenue, receivables and how work is moving" : "How work and money are moving")
                        .font(Theme.font(15)).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, Theme.gutter).padding(.bottom, 8)
                if tabs.count > 1 { PaperTabs(options: tabs, selection: $tab, wrapOverflow: true) }
                if let error { ErrorBanner(message: error) }
                Group {
                    if tabs.isEmpty {
                        PaperEmptyState(symbol: "chart.bar", title: "You can't see reports", message: "Your role doesn't include estimates, jobs or invoices. Ask an owner for access.")
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
                .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 8)
            }
            .padding(.bottom, 24)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { refreshes += 1; await load() }
        .task { await load() }
    }

    private var loadingState: some View { SkeletonRows(count: 4, leading: false, inset: 0) }

    // design 2026-10-30: every figure on a panel under its 13pt label; list rows are PaperListRow
    // with the figure on the right, never loose rows on the cream ground.
    @ViewBuilder private func operationsContent(_ report: OperationsReport) -> some View {
        if report.truncated { incomplete }
        else {
            VStack(alignment: .leading, spacing: 22) {
                PaperSection("Estimates") {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(report.estimates.conversionBps / 100)%").font(Theme.moneyHeroFont).tracking(-0.6)
                        Text("of presented estimates approved").font(Theme.font(15)).foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, PaperCardMetrics.inset).padding(.top, 14)
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
                footer(report.reportVersion, report.generatedAt)
            }
        }
    }

    @ViewBuilder private func scheduleContent(_ report: ScheduleReport) -> some View {
        if report.truncated { incomplete }
        else {
            VStack(alignment: .leading, spacing: 22) {
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
            VStack(alignment: .leading, spacing: 22) {
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
    private func statRows(_ stats: [PaperStatRow.Stat]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(stats) { stat in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        if stat.tint != Theme.foreground {
                            StatusLabel(tone: .attention, word: stat.label, size: 15)
                        } else {
                            Text(stat.label).font(Theme.font(15)).foregroundStyle(Theme.foreground)
                        }
                        if let detail = stat.detail {
                            Text(detail).font(Theme.font(14)).monospacedDigit().foregroundStyle(Theme.muted)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(stat.value).font(Theme.rowAmountFont(15)).foregroundStyle(Theme.foreground)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 10)
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, PaperCardMetrics.edge)
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
        return "Updated \(date.formatted(.relative(presentation: .named))) · months follow UTC"
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

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
struct ReportsView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @State private var tab = "Operations"
    @State private var operations: OperationsReport?
    @State private var schedule: ScheduleReport?
    @State private var payments: PaymentActivityReport?
    @State private var error: String?

    private var tabs: [String] {
        var result: [String] = []
        if session.can("estimate.view", feature: "estimates") { result.append("Operations") }
        if session.can("job.view", feature: "jobs") { result.append("Schedule") }
        if session.can("invoice.view", feature: "invoicing") { result.append("Payments") }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reports").font(Theme.font(30, weight: .medium)).tracking(-0.6).accessibilityAddTraits(.isHeader)
                    Text("How work and money are moving").font(Theme.font(15)).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, Theme.gutter).padding(.bottom, 8)
                if tabs.count > 1 { PaperTabs(options: tabs, selection: $tab) }
                if let error { ErrorBanner(message: error) }
                Group {
                    if tabs.isEmpty {
                        PaperEmptyState(symbol: "chart.bar", title: "Reports unavailable", message: "Your role can't view estimate, job or payment reports.")
                    } else if (tabs.contains(tab) ? tab : tabs[0]) == "Operations" {
                        if let operations { operationsContent(operations) } else { loadingState }
                    } else if (tabs.contains(tab) ? tab : tabs[0]) == "Payments" {
                        if let payments { paymentsContent(payments) } else { loadingState }
                    } else {
                        if let schedule { scheduleContent(schedule) } else { loadingState }
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }
            .padding(.bottom, 24)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private var loadingState: some View { SkeletonRows(count: 4, leading: false, inset: 0) }

    @ViewBuilder private func operationsContent(_ report: OperationsReport) -> some View {
        if report.truncated { incomplete }
        else {
            PaperGroupHeader(title: "Estimates")
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(report.estimates.conversionBps / 100)%").font(Theme.monoFont(34, weight: .semibold))
                Text("of presented estimates approved").font(Theme.font(13)).foregroundStyle(Theme.muted)
            }
            .padding(.bottom, 10)
            HStack(spacing: 10) {
                tile("Presented", report.estimates.presented)
                tile("Approved", report.estimates.approved)
                tile("Declined", report.estimates.declined)
            }
            PaperGroupHeader(title: "Jobs").padding(.top, 18)
            HStack(spacing: 10) {
                tile("Booked", report.jobs.booked)
                tile("Completed", report.jobs.completed)
                tile("Open", report.jobs.open)
            }
            if !report.months.isEmpty {
                PaperGroupHeader(title: "Jobs by month", count: report.months.count).padding(.top, 18)
                ForEach(report.months.suffix(6).reversed()) { month in
                    HStack {
                        Text(monthName(month.month)).font(Theme.font(15, weight: .medium))
                        Spacer()
                        Text("\(month.completed) of \(month.booked) done").font(Theme.monoFont(13, weight: .medium)).foregroundStyle(Theme.muted)
                    }
                    .frame(minHeight: 44)
                }
            }
            footer(report.reportVersion, report.generatedAt)
        }
    }

    @ViewBuilder private func scheduleContent(_ report: ScheduleReport) -> some View {
        if report.truncated { incomplete }
        else {
            PaperGroupHeader(title: "Needs attention")
            HStack(spacing: 10) {
                tile("Unscheduled", report.backlog.unscheduledOpenJobs, alert: report.backlog.unscheduledOpenJobs > 0)
                tile("Past due", report.backlog.overdueScheduledJobs, alert: report.backlog.overdueScheduledJobs > 0)
            }
            let recent = Array(report.days.suffix(14).reversed())
            if !recent.isEmpty {
                PaperGroupHeader(title: "By day", count: recent.count).padding(.top, 18)
                ForEach(recent) { day in
                    HStack {
                        Text(dayName(day.day)).font(Theme.font(15, weight: .medium))
                        Spacer()
                        Text("\(day.completed) of \(day.scheduled) done").font(Theme.monoFont(13, weight: .medium)).foregroundStyle(Theme.muted)
                    }
                    .frame(minHeight: 44)
                }
            }
            footer(report.reportVersion, report.generatedAt)
        }
    }

    @ViewBuilder private func paymentsContent(_ report: PaymentActivityReport) -> some View {
        if report.truncated { incomplete }
        else {
            PaperGroupHeader(title: "All time")
            HStack(spacing: 10) {
                moneyTile("Payments", report.totals.recorded, count: report.totals.recordedCount)
                moneyTile("Refunds", report.totals.refunded, count: report.totals.refundedCount)
            }
            let credits = [("Discounts", report.totals.discounts, report.totals.discountCount),
                           ("Deposits applied", report.totals.depositCredits, report.totals.depositCreditCount),
                           ("Retainage withheld", report.totals.retainageWithheld, report.totals.retainageWithheldCount),
                           ("Other adjustments", report.totals.otherAdjustments, report.totals.otherAdjustmentCount)]
                .filter { $0.2 > 0 }
            if !credits.isEmpty {
                PaperGroupHeader(title: "Credits on invoices").padding(.top, 18)
                ForEach(credits, id: \.0) { credit in
                    HStack {
                        Text(credit.0).font(Theme.font(15, weight: .medium))
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(money(credit.1, currency: "USD")).moneyStyle(.row)
                            Text("\(credit.2)").font(Theme.font(13)).foregroundStyle(Theme.muted)
                        }
                    }
                    .frame(minHeight: 44)
                    .accessibilityElement(children: .combine)
                }
            }
            if !report.months.isEmpty {
                PaperGroupHeader(title: "By month", count: report.months.count).padding(.top, 18)
                ForEach(report.months.suffix(6).reversed()) { month in
                    HStack {
                        Text(monthName(month.month)).font(Theme.font(15, weight: .medium))
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(money(month.recorded, currency: "USD")).moneyStyle(.row)
                            if month.refunded > 0 {
                                Text("\(money(month.refunded, currency: "USD")) refunded").font(Theme.font(15)).monospacedDigit().foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    .frame(minHeight: 44)
                    .accessibilityElement(children: .combine)
                }
            }
            Text("Refunds are shown on their own, never subtracted from payments.")
                .font(Theme.font(12)).foregroundStyle(Theme.muted).padding(.top, 12)
            footer(report.reportVersion, report.generatedAt)
        }
    }

    private func moneyTile(_ label: String, _ amount: Int, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(Theme.font(13)).foregroundStyle(Theme.muted)
            Text(money(amount, currency: "USD")).moneyStyle(.total)
            Text(count == 1 ? "1 entry" : "\(count) entries").font(Theme.font(12)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.border))
        .accessibilityElement(children: .combine)
    }

    private var incomplete: some View {
        PaperEmptyState(symbol: "exclamationmark.triangle", title: "Report incomplete",
                        message: "The server reached its scan limit, so these counts would understate the totals. Open the report on the web.")
    }

    private func tile(_ label: String, _ value: Int, alert: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(Theme.font(13)).foregroundStyle(Theme.muted)
            Text("\(value)").font(Theme.monoFont(22, weight: .semibold)).foregroundStyle(alert ? Theme.warning : Theme.foreground)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.border))
        .accessibilityElement(children: .combine)
    }

    private func footer(_ version: Int, _ generatedAt: String) -> some View {
        Text(generatedLabel(generatedAt)).font(Theme.font(12)).foregroundStyle(Theme.muted).padding(.top, 16)
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

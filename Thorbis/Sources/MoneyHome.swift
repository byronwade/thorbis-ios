import SwiftUI

// Paper 59 (Owner · Money), 54 (Office · Money) and 60 (Owner · Reports). The figures are the ones
// the server keeps: invoiced and collected by month, what is owed and overdue, the payments tape.
// Cash position, bank accounts, bills, payroll, costs and profit are not kept anywhere the app can
// read, so those cards are not drawn (see the notes on each screen).

/// Whole dollars, as Paper prints money on dashboards ("$62,140").
func wholeDollars(_ cents: Int, currency: String = "USD") -> String {
    (Double(cents) / 100).formatted(.currency(code: currency).precision(.fractionLength(0)))
}

/// "2026-07" → "Jul" / "Jul 2026". Report months follow UTC.
enum ReportMonth {
    static func date(_ key: String) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]) else { return nil }
        return Calendar(identifier: .gregorian).date(from: DateComponents(timeZone: .gmt, year: year, month: month, day: 15))
    }
    static func short(_ key: String) -> String { date(key)?.formatted(.dateTime.month(.abbreviated)) ?? key }
    static func shortWithYear(_ key: String) -> String { date(key)?.formatted(.dateTime.month(.abbreviated).year()) ?? key }
}

struct MoneyHomeView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var revenue: RevenueReport?
    @State private var payments: [CompanyPayment] = []
    @State private var paymentsComplete = false
    @State private var loaded = false
    @State private var error: String?
    @State private var showPayments = false
    @State private var showReports = false
    @State private var period = "This week"
    @State private var refreshes = 0

    /// Paper 59 is the owner's Money; everyone else with Money gets the office's (Paper 54).
    private var isOwner: Bool { session.can("organization.settings.edit") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if isOwner { owner } else { office }
            }
            .padding(.bottom, 40)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { refreshes += 1; await load() }
        .task(id: session.generation) {
            await load()
            #if DEBUG
            if PaperPreview.enabled, PaperPreview.screen == "payments-list" { showPayments = true }
            #endif
        }
        .thorbisDestination(isPresented: $showPayments) { CompanyPaymentsView() }
        .thorbisDestination(isPresented: $showReports) { ReportsSummaryView().thorbisBackButton() }
    }

    // MARK: Owner (Paper 59)

    /// Paper 59 with what the server keeps: the lead card is this month's collected money over the
    /// trailing months (Paper's "Total cash position" needs bank balances), then Outstanding AR
    /// with what is overdue, and the way into the reports. Upcoming bills, Payroll run and Paid
    /// out are not drawn.
    @ViewBuilder private var owner: some View {
        DashboardHeader(title: "Money", subtitle: ownerSubtitle)
            .environment(\.paperMenuButton, false)
        if let error { ErrorBanner(message: error) { await load() } }
        VStack(alignment: .leading, spacing: 10) {
            if let report = revenue, !report.truncated {
                collectedCard(report)
                receivableTile(report.receivable)
            } else if !loaded {
                SkeletonRows(count: 3, leading: false, inset: 0)
            }
        }
        .paperCardMargin()
        .padding(.top, 2)
        Button { showReports = true } label: {
            DashboardMarkRow(glyph: .bars, tint: Theme.brand, title: "Reports and trends",
                             subtitle: "Revenue, jobs and payments by month")
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .paperCardMargin()
        .padding(.top, 16)
        .accessibilityIdentifier("money-reports")
        moneyDoors
    }

    /// Paper's Map: Estimates and Invoices open "from Money", and so do the payouts. The billing
    /// schedules and what needs attention are money's too, so they are listed here, not in the menu.
    @ViewBuilder private var moneyDoors: some View {
        VStack(alignment: .leading, spacing: 22) {
            PlaceDoorRows(door: .money, title: "Documents")
            if session.can("organization.settings.edit") {
                AccountGroup(title: "Getting paid") {
                    NavigationLink(value: PaperRoute.payments) {
                        AccountRow(glyph: .bizCard, glyphSize: 22, title: "Payouts and card payments",
                                   subtitle: "Where customer payments land", end: .chevronLarge)
                    }
                    .buttonStyle(RowPressStyle())
                    .accessibilityIdentifier("money-payouts")
                }
            }
        }
        .paperCardMargin()
        .padding(.top, 22)
    }

    private var ownerSubtitle: String {
        let date = Date.now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return [session.activeOrganization?.name, date].compactMap { $0 }.joined(separator: " \u{00B7} ")
    }

    /// The lead card: 13 Semibold label and "Trailing 12 mo", the figure in 44 Bold, "↑ 8% vs Jun"
    /// and one bar per month. Opens Payments, where each one is listed.
    @ViewBuilder private func collectedCard(_ report: RevenueReport) -> some View {
        let months = Array(report.months.suffix(12))
        if let totals = DashboardPeriod.month.totals(report.months.map { (key: $0.month, value: $0.collected) }) {
            Button { showPayments = true } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Collected this month").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if months.count > 1 {
                            Text("Trailing \(months.count) mo").font(Theme.font(13)).foregroundStyle(Theme.muted)
                        }
                    }
                    HStack(alignment: .bottom, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(wholeDollars(totals.now))
                                .font(Theme.display()).tracking(Theme.displayTracking())
                                .foregroundStyle(Theme.foreground)
                                .lineLimit(1).minimumScaleFactor(0.5)
                            if let delta = DashboardDelta.percent(now: totals.now, before: totals.before, versus: totals.versus) {
                                DashboardDeltaLine(delta: delta, lead: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if months.count > 1 && !typeSize.isAccessibilitySize {
                            DashboardMonthBars(values: months.map(\.collected))
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(PressStyle())
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens payments")
            .accessibilityIdentifier("money-collected")
        }
    }

    /// "Outstanding AR" over the open balance, "$2,140 overdue" in red under it (Paper 59). Half
    /// the row: Paper's other tile, Upcoming bills, has no source. Opens the unpaid invoices.
    private func receivableTile(_ receivable: RevenueReport.Receivable) -> some View {
        let stacked = typeSize.isAccessibilitySize
        let pair = stacked ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
        return pair {
            NavigationLink(value: PaperRoute.homeList(.unpaid)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Outstanding AR").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                    Text(wholeDollars(receivable.balance)).font(Theme.font(26, weight: .bold)).tracking(-0.52)
                        .foregroundStyle(Theme.foreground).lineLimit(1).minimumScaleFactor(0.6)
                    if receivable.overdueBalance > 0 {
                        Text("\(wholeDollars(receivable.overdueBalance)) overdue").font(Theme.font(14)).foregroundStyle(Theme.destructive)
                    } else {
                        Text(receivable.openInvoices == 0 ? "Nothing owed" : "\(receivable.openInvoices) open invoice\(receivable.openInvoices == 1 ? "" : "s")")
                            .font(Theme.font(14)).foregroundStyle(Theme.muted)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            }
            .buttonStyle(PressStyle())
            .accessibilityElement(children: .combine)
            .accessibilityHint("Lists unpaid invoices")
            if !stacked { Color.clear.frame(maxWidth: .infinity).frame(height: 1).accessibilityHidden(true) }
        }
    }

    // MARK: Office (Paper 54)

    /// Paper 54 with what the server keeps: the open balance under the title, Search, the period
    /// segments, what came in over the period, then who to get paid by. Bank accounts ("Total
    /// available", Operating / Payroll / Reserve) and Spend are not drawn.
    @ViewBuilder private var office: some View {
        PaperHeader(title: "Money", subtitle: officeSubtitle)
            .environment(\.paperMenuButton, false)
        if let error { ErrorBanner(message: error) { await load() } }
        PaperSearchBar(placeholder: "Search or ask") { EmptyView() }
            .paperCardMargin()
            .padding(.top, 2)
        PaperTabs(options: ["This week", "Month", "Quarter"], selection: $period).padding(.top, 16)
        VStack(alignment: .leading, spacing: 10) {
            cameIn
        }
        .paperCardMargin()
        .padding(.top, 16)
        MoneyOverviewView(embedded: true, chasingOnly: true).id(refreshes)
            .paperCardMargin()
            .padding(.top, 18)
        moneyDoors
    }

    private var officeSubtitle: String {
        guard let receivable = revenue?.receivable else { return loaded ? "What's owed and what came in" : "Reading\u{2026}" }
        if receivable.balance == 0 { return "Nothing open" }
        var parts = ["\(wholeDollars(receivable.balance)) open"]
        if receivable.overdueBalance > 0 { parts.append("\(wholeDollars(receivable.overdueBalance)) overdue") }
        return parts.joined(separator: " \u{00B7} ")
    }

    private var range: DateInterval {
        switch period {
        case "Month": OfficePeriod.month.range().current
        case "Quarter": DashboardPeriod.quarter.range().current
        default: OfficePeriod.week.range().current
        }
    }

    /// The lead card: what was collected in the period in 44 Bold, how many payments under it.
    /// Drawn only when the payments read reaches back to the period's start, so it is never short.
    @ViewBuilder private var cameIn: some View {
        let range = range
        let covers = paymentsComplete || payments.contains { (JobFiltering.date($0.recordedAt) ?? .distantFuture) < range.start }
        if loaded, covers {
            let inRange = payments.filter { payment in
                guard let date = JobFiltering.date(payment.recordedAt) else { return false }
                return date >= range.start
            }
            let taken = inRange.filter { !$0.refunded }
            let refunded = inRange.filter(\.refunded).reduce(0) { $0 + ($1.refundedAmount > 0 ? $1.refundedAmount : $1.amount) }
            Button { showPayments = true } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Collected \(period == "This week" ? "this week" : period == "Month" ? "this month" : "this quarter")")
                        .font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                    Text(wholeDollars(taken.reduce(0) { $0 + $1.amount }))
                        .font(Theme.display()).tracking(Theme.displayTracking())
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    HStack(spacing: 5) {
                        PaperIcon(.trendUp, size: 12, color: Theme.success)
                        Text("\(taken.count)").font(Theme.font(14, weight: .semibold)).foregroundStyle(Theme.success)
                        Text("payment\(taken.count == 1 ? "" : "s") in").font(Theme.font(14)).foregroundStyle(Theme.muted)
                        if refunded > 0 {
                            PaperIcon(.trendDown, size: 12, color: Theme.foreground).padding(.leading, 9)
                            Text(wholeDollars(refunded)).font(Theme.font(14, weight: .semibold)).foregroundStyle(Theme.foreground)
                            Text("refunded").font(Theme.font(14)).foregroundStyle(Theme.muted)
                        }
                    }
                    .frame(minHeight: 20)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(PressStyle())
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens payments")
            .accessibilityIdentifier("money-collected")
        }
    }

    private func load() async {
        let generation = session.generation
        do {
            let report = try await api.revenueReport()
            guard session.generation == generation else { return }
            revenue = report
            error = nil
        } catch is CancellationError {
            return
        } catch {
            guard session.generation == generation else { return }
            self.error = error.localizedDescription
        }
        if !isOwner, let tape = try? await api.companyPayments() {
            guard session.generation == generation else { return }
            payments = tape.payments
            paymentsComplete = tape.complete
        }
        loaded = true
    }
}

/// Paper 60: the report an owner opens. Revenue and what was collected for the month, against the
/// month before; the last six months as bars; and the way into the full reports. Paper's cost,
/// gross profit, expense and net profit rows need costs the server does not keep, so the table
/// holds the rows it can stand behind and the trend is revenue, not net profit.
struct ReportsSummaryView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @State private var revenue: RevenueReport?
    @State private var activity: PaymentActivityReport?
    @State private var loaded = false
    @State private var error: String?
    @State private var period = "This month"
    @State private var tableCollapsed = false
    @State private var trendCollapsed = false
    @State private var showFull = false

    var body: some View {
        if MenuItem.money.permitted(session) {
            summary
        } else {
            // Without revenue there is no summary to draw: the work reports are the screen.
            ReportsView(initialTab: "Operations")
        }
    }

    private var summary: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PaperHeader(title: "Reports", subtitle: ["Revenue", session.activeOrganization?.name].compactMap { $0 }.joined(separator: " \u{00B7} "))
                    .environment(\.paperMenuButton, false)
                if let error { ErrorBanner(message: error) { await load() } }
                PaperTabs(options: ["This month", "Last month", "YTD"], selection: $period).padding(.top, 2)
                if let report = revenue, !report.truncated, !report.months.isEmpty {
                    table(report).paperCardMargin().padding(.top, 18)
                    trend(report).paperCardMargin().padding(.top, 18)
                } else if !loaded {
                    SkeletonRows(count: 4, leading: false, inset: 0).paperCardMargin().padding(.top, 16)
                } else if revenue?.truncated == true {
                    PaperEmptyState(symbol: "exclamationmark.triangle", title: "This report is too big for the phone",
                                    message: "These totals would come up short. Open the full report on the web.")
                }
                Button { showFull = true } label: {
                    DashboardMarkRow(glyph: .bars, tint: Theme.muted, title: "View full report",
                                     subtitle: "Aging, estimates, jobs, schedule and payments")
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                }
                .buttonStyle(PressStyle())
                .paperCardMargin()
                .padding(.top, 16)
                .accessibilityIdentifier("reports-full")
                // My scorecard is a report; it opens from here, not from the menu.
                PlaceDoorRows(door: .reports, showsSubtitles: true)
                    .paperCardMargin()
                    .padding(.top, 16)
            }
            .padding(.bottom, 40)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .reportExports()
        .refreshable { await load() }
        .task(id: session.generation) { await load() }
        .thorbisDestination(isPresented: $showFull) { ReportsView(includesRevenue: true, initialTab: "Overview").thorbisBackButton() }
    }

    private struct Line: Identifiable {
        let id: String
        let label: String
        let now: Int
        let before: Int?
        var negative = false
    }

    /// The month keys the chosen segment covers, what they are compared with, and the label.
    private func scope(_ keys: [String]) -> (current: [String], before: [String]?, label: String) {
        guard let latest = keys.last else { return ([], nil, "") }
        switch period {
        case "Last month":
            guard keys.count >= 2 else { return ([], nil, "") }
            let month = keys[keys.count - 2]
            let prior = keys.count >= 3 ? keys[keys.count - 3] : nil
            return ([month], prior.map { [$0] },
                    [ReportMonth.shortWithYear(month), prior.map { "vs \(ReportMonth.short($0))" }].compactMap { $0 }.joined(separator: " \u{00B7} "))
        case "YTD":
            let split = DashboardPeriod.year.keys(latest: latest, known: Set(keys))
            let year = String(latest.prefix(4))
            return (split.current.filter(keys.contains), split.before,
                    [year, split.before == nil ? nil : split.versus].compactMap { $0 }.joined(separator: " \u{00B7} "))
        default:
            let prior = keys.count >= 2 ? keys[keys.count - 2] : nil
            return ([latest], prior.map { [$0] },
                    [ReportMonth.shortWithYear(latest), prior.map { "vs \(ReportMonth.short($0))" }].compactMap { $0 }.joined(separator: " \u{00B7} "))
        }
    }

    private func lines(_ report: RevenueReport) -> (lines: [Line], label: String) {
        let scope = scope(report.months.map(\.month))
        func sum(_ keys: [String]?, _ value: (RevenueReport.Month) -> Int) -> Int? {
            guard let keys else { return nil }
            return report.months.filter { keys.contains($0.month) }.reduce(0) { $0 + value($1) }
        }
        var lines = [Line(id: "revenue", label: "Revenue", now: sum(scope.current, \.revenue) ?? 0, before: sum(scope.before, \.revenue)),
                     Line(id: "collected", label: "Collected", now: sum(scope.current, \.collected) ?? 0, before: sum(scope.before, \.collected))]
        if let activity, !activity.truncated {
            let refunded = activity.months.filter { scope.current.contains($0.month) }.reduce(0) { $0 + $1.refunded }
            if refunded > 0 { lines.append(Line(id: "refunded", label: "Refunded", now: refunded, before: nil, negative: true)) }
        }
        return (lines, scope.label)
    }

    /// Paper 60's table: rows 56 tall, the label in 16 Medium, a 52-wide lane for "↑ 12%" in 13
    /// Medium, then the amount right-aligned in 16 Medium.
    private func table(_ report: RevenueReport) -> some View {
        let content = lines(report)
        return PaperSection(title: "Revenue and payments", collapsed: $tableCollapsed) {
            VStack(spacing: 0) {
                ForEach(Array(content.lines.enumerated()), id: \.element.id) { index, line in
                    HStack(alignment: .center, spacing: 8) {
                        Text(line.label).font(Theme.font(16, weight: .medium)).tracking(-0.16)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let delta = DashboardDelta.percent(now: line.now, before: line.before) {
                            HStack(spacing: 3) {
                                PaperIcon(delta.up ? .trendUp : .trendDown, size: 12, color: delta.up ? Theme.success : Theme.destructive)
                                Text(delta.text).font(Theme.font(13, weight: .medium))
                                    .foregroundStyle(delta.up ? Theme.success : Theme.destructive)
                            }
                            .frame(minWidth: 52, alignment: .leading)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(delta.up ? "up" : "down") \(delta.text)")
                        }
                        Text((line.negative ? "-" : "") + wholeDollars(line.now)).font(Theme.font(16, weight: .medium))
                            .foregroundStyle(line.negative ? Theme.muted : Theme.foreground)
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .frame(minWidth: 84, alignment: .trailing)
                    }
                    .padding(.trailing, 16)
                    .frame(minHeight: 56)
                    .overlay(alignment: .top) { if index > 0 { WellDivider(leading: 0) } }
                    .padding(.leading, 16)
                    .accessibilityElement(children: .combine)
                }
            }
        } accessory: {
            Text(content.label).font(Theme.font(13))
        }
    }

    /// Paper 60's trend card: six 10-wide bars in a 64-tall lane, each over its month in 13 Medium;
    /// the latest in brand blue with its month in bold ink.
    private func trend(_ report: RevenueReport) -> some View {
        let months = Array(report.months.suffix(6))
        let peak = max(months.map(\.revenue).max() ?? 1, 1)
        return PaperSection(title: "Revenue trend", collapsed: $trendCollapsed) {
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(months.enumerated()), id: \.element.id) { index, month in
                    let latest = index == months.count - 1
                    VStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(latest ? Theme.brand : Theme.borderStrong)
                            .frame(width: 10, height: max(6, 56 * CGFloat(month.revenue) / CGFloat(peak)))
                            .frame(height: 64, alignment: .bottom)
                        Text(ReportMonth.short(month.month)).font(Theme.font(13, weight: latest ? .bold : .medium))
                            .foregroundStyle(latest ? Theme.foreground : Theme.muted)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(minWidth: 40)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(ReportMonth.shortWithYear(month.month)), \(wholeDollars(month.revenue))")
                    if !latest { Spacer(minLength: 0) }
                }
            }
            .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 14)
        } accessory: {
            Text("\(months.count) mo").font(Theme.font(13))
        }
    }

    private func load() async {
        let generation = session.generation
        do {
            let report = try await api.revenueReport()
            guard session.generation == generation else { return }
            revenue = report
            error = nil
        } catch is CancellationError {
            return
        } catch {
            guard session.generation == generation else { return }
            self.error = error.localizedDescription
        }
        if let report = try? await api.paymentActivityReport() {
            guard session.generation == generation else { return }
            activity = report
        }
        loaded = true
    }
}

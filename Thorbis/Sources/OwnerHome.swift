import SwiftUI

// The owner's first place: "how is today going and what needs me?". Every figure is read from
// lists the app already loads (jobs, invoices, estimates, the assignee roster and the revenue
// report); nothing here is estimated or made up. Each figure opens the records behind it.

/// Where a job sits today, in the owner's words. Status colours only ever sit beside the word.
enum HomeJobState: String, CaseIterable, Hashable {
    case scheduled, onTheWay, onSite, done

    var title: String {
        switch self {
        case .scheduled: "Scheduled"
        case .onTheWay: "On the way"
        case .onSite: "On site"
        case .done: "Done"
        }
    }

    var tint: Color? {
        switch self {
        case .scheduled: nil
        case .onTheWay: StatusWord.jobTint("en_route")
        case .onSite: StatusWord.jobTint("in_progress")
        case .done: StatusWord.jobTint("completed")
        }
    }

    /// The job glyph's tone for this state (redesign phase 3): ring, quarter, half, check.
    var tone: StatusTone {
        switch self {
        case .scheduled: .scheduled
        case .onTheWay: .dispatched
        case .onSite: .inProgress
        case .done: .done
        }
    }

    init(status: String) {
        switch status {
        case "en_route": self = .onTheWay
        case "arrived", "in_progress", "paused": self = .onSite
        case "completed": self = .done
        default: self = .scheduled
        }
    }
}

/// The focused lists Home opens. Pushed as `PaperRoute.home(_)`, so iPhone and iPad share them.
enum HomeList: Hashable {
    case jobs(HomeJobState)
    /// One technician's day; `nil` is today's jobs nobody is assigned to.
    case tech(userID: String?, name: String)
    /// Everyone with work today, each opening their day (Paper 52's Active techs).
    case techs
    case unscheduled
    case unpaid
    case invoicedToday
    /// `staleOnly`: the Needs attention rule (sent a week or more ago).
    case estimatesWaiting(staleOnly: Bool)
}

/// Pure reads over the job list, so the screen and its lists agree on every count.
enum OwnerDay {
    static let activeStatuses: Set<String> = ["en_route", "arrived", "in_progress", "paused"]

    /// Today's visits, finished ones included; canceled ones are not part of the day.
    static func today(_ jobs: [Job], now: Date = .now, calendar: Calendar = .current) -> [Job] {
        jobs.filter { job in
            job.status != "canceled" &&
                (JobFiltering.date(job.scheduledFor).map { calendar.isDate($0, inSameDayAs: now) } ?? false)
        }
        .sortedByDate(\.scheduledFor, missing: .distantFuture)
    }

    /// People with a job they are driving to or working on right now, on any day's job.
    static func techsOut(_ jobs: [Job]) -> Int {
        Set(jobs.filter { activeStatuses.contains($0.status) }.compactMap(\.assignedToUserId)).count
    }

    struct TechDay: Identifiable, Equatable {
        let userID: String
        /// The job they are on or driving to, if any.
        let active: Job?
        /// Their next booked visit today that has not started.
        let next: Job?
        let total: Int
        let done: Int
        var id: String { userID }
    }

    /// Everyone with work today or a job in hand, in a stable order: busy first, then by next time.
    static func techs(_ jobs: [Job], now: Date = .now, calendar: Calendar = .current) -> [TechDay] {
        let day = today(jobs, now: now, calendar: calendar)
        let ids = Set(day.compactMap(\.assignedToUserId))
            .union(jobs.filter { activeStatuses.contains($0.status) }.compactMap(\.assignedToUserId))
        let priority = ["in_progress": 0, "arrived": 1, "paused": 2, "en_route": 3]
        return ids.map { id in
            let theirs = day.filter { $0.assignedToUserId == id }
            let active = jobs.filter { $0.assignedToUserId == id && priority[$0.status] != nil }
                .min { (priority[$0.status] ?? 9, $0.id) < (priority[$1.status] ?? 9, $1.id) }
            let next = theirs.first { !activeStatuses.contains($0.status) && $0.status != "completed" }
            return TechDay(userID: id, active: active, next: next, total: theirs.count,
                           done: theirs.filter { $0.status == "completed" }.count)
        }
        .sorted { left, right in
            let l = (left.active == nil ? 1 : 0, JobFiltering.date(left.next?.scheduledFor) ?? .distantFuture, left.userID)
            let r = (right.active == nil ? 1 : 0, JobFiltering.date(right.next?.scheduledFor) ?? .distantFuture, right.userID)
            return l < r
        }
    }
}

/// Sums kept per currency, so two currencies are never added together.
struct HomeAmounts {
    private(set) var totals: [String: Int] = [:]
    mutating func add(_ cents: Int, _ currency: String) { totals[currency, default: 0] += cents }
    var isEmpty: Bool { totals.isEmpty }
    var text: String {
        totals.keys.sorted().map { money(totals[$0] ?? 0, currency: $0) }.joined(separator: " + ")
    }
    /// Paper's dashboards print whole dollars ("$7,330").
    var wholeText: String {
        totals.keys.sorted().map { key in
            (Double(totals[key] ?? 0) / 100).formatted(.currency(code: key).precision(.fractionLength(0)))
        }.joined(separator: " + ")
    }
}

struct OwnerHomeView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var outbox: FieldOutbox
    @EnvironmentObject private var media: PendingMediaStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var invoices: [InvoiceRecord] = []
    @State private var estimates: [EstimateRecord] = []
    @State private var revenue: RevenueReport?
    @State private var operations: OperationsReport?
    @State private var loaded = false
    @State private var error: String?
    @State private var reviewScope: SavedWorkScope?
    @State private var showPayments = false
    /// What came in today, when the newest page of payments reaches back past midnight; nil until
    /// then, so a partial read never prints a smaller, wrong figure.
    @State private var collectedToday: Int?
    /// Paper 52/58: each section's label folds its card away (the chevron before the label).
    @State private var needsCollapsed = false
    @State private var moneyCollapsed = false
    /// Paper 58: This month / Quarter / YTD. Paper 52: Today / Week / Month.
    @State private var ownerPeriod = DashboardPeriod.month.rawValue
    @State private var officePeriod = OfficePeriod.today.rawValue

    private var canInvoices: Bool { session.can("invoice.view", feature: "invoicing") }
    private var canEstimates: Bool { session.can("estimate.view", feature: "estimates") }
    private var todayJobs: [Job] { OwnerDay.today(store.jobs) }
    /// The owner's dashboard (Paper 58) is the business over a month or more; everyone else in the
    /// office gets today's board (Paper 52).
    private var isOwner: Bool { session.can("organization.settings.edit") }

    var body: some View {
        let day = todayJobs
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Paper 52/58: the menu and Search circles, "Dashboard" and its line, the period
                // segments, the figures, then what needs someone (and, for the office, Money).
                DashboardHeader(title: "Dashboard", subtitle: isOwner ? ownerHeadline : headline(day))
                OfflineBanner()
                SavedCopyNote(savedAt: savedAt).padding(.bottom, 6)
                if let error = store.error { ErrorBanner(message: error) { _ = await store.refresh(api) } }
                if let error { ErrorBanner(message: error) }
                if isOwner {
                    PaperTabs(options: DashboardPeriod.allCases.map(\.rawValue), selection: $ownerPeriod).padding(.top, 2)
                } else {
                    PaperTabs(options: OfficePeriod.allCases.map(\.rawValue), selection: $officePeriod).padding(.top, 2)
                }
                VStack(alignment: .leading, spacing: 10) {
                    if isOwner {
                        ownerFigures
                    } else {
                        officeRevenue
                        if store.loading && store.jobs.isEmpty {
                            SkeletonRows().padding(.horizontal, -PaperCardMetrics.margin)
                        } else {
                            officeGlance(day)
                        }
                    }
                }
                .paperCardMargin()
                .padding(.top, 16)
                needsYou(day)
                    .paperCardMargin()
                    .padding(.top, 18)
                if !isOwner, canInvoices {
                    moneyToday
                        .paperCardMargin()
                        .padding(.top, 16)
                }
            }
            .padding(.bottom, 40)
        }
        .background(Theme.canvas)
        .foregroundStyle(Theme.foreground)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.generation) { await load() }
        .thorbisDestination(isPresented: $showPayments) { CompanyPaymentsView() }
        .refreshable {
            _ = await store.refresh(api)
            await SavedCopies.$liveOnly.withValue(true) { await load() }
        }
        .sheet(item: $reviewScope) { value in SheetSurface { SavedWorkReviewView(scope: value) } }
    }

    // MARK: Header

    /// "Tue, Jul 21 · 12 jobs in progress" (Paper 52); a quiet day says how many are booked instead.
    private func headline(_ day: [Job]) -> String {
        let date = Date.now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let active = day.filter { OwnerDay.activeStatuses.contains($0.status) }.count
        let jobs = active > 0
            ? "\(active) job\(active == 1 ? "" : "s") in progress"
            : "\(day.count) job\(day.count == 1 ? "" : "s") today"
        return [date, jobs].joined(separator: " · ")
    }

    /// "Wade's Plumbing · Tue, Jul 21" (Paper 58).
    private var ownerHeadline: String {
        let date = Date.now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return [session.activeOrganization?.name, date].compactMap { $0 }.joined(separator: " · ")
    }

    /// The oldest copy on screen that came from this phone instead of the server.
    private var savedAt: Date? {
        [store.cachedAt, canInvoices ? api.savedCopyDate("/v1/invoices") : nil,
         canEstimates ? api.savedCopyDate("/v1/estimates") : nil].compactMap { $0 }.min()
    }

    // MARK: Owner figures (Paper 58)

    /// Paper 58's cards, drawn only for figures the server keeps: Revenue with its trailing months,
    /// then Avg ticket, Jobs completed and Close rate two by two. Gross margin, Net margin and
    /// Utilization need costs and capacity the server does not have, so they are not drawn.
    @ViewBuilder private var ownerFigures: some View {
        let period = DashboardPeriod(rawValue: ownerPeriod) ?? .month
        ownerRevenue(period)
        let tiles = ownerTiles(period)
        if !tiles.isEmpty {
            let stacked = typeSize.isAccessibilitySize
            ForEach(Array(stride(from: 0, to: tiles.count, by: 2)), id: \.self) { start in
                let pair = stacked ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
                pair {
                    tiles[start]
                    if start + 1 < tiles.count {
                        tiles[start + 1]
                    } else if !stacked {
                        Color.clear.frame(maxWidth: .infinity).frame(height: 1).accessibilityHidden(true)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// "Revenue" over the period's invoiced total in 44 Bold, "↑ 12% vs Jun" under it, and the
    /// report's months as bars with "Trailing 12 mo" above them. Opens Revenue.
    @ViewBuilder private func ownerRevenue(_ period: DashboardPeriod) -> some View {
        if let report = revenue, !report.truncated,
           let totals = period.totals(report.months.map { (key: $0.month, value: $0.revenue) }) {
            let months = Array(report.months.suffix(12))
            NavigationLink(value: PaperRoute.revenue) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Revenue").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if months.count > 1 {
                            Text("Trailing \(months.count) mo").font(Theme.font(13)).foregroundStyle(Theme.muted)
                        }
                    }
                    HStack(alignment: .bottom, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(wholeMoney(totals.now))
                                .font(Theme.display()).tracking(Theme.displayTracking())
                                .foregroundStyle(Theme.foreground)
                                .lineLimit(1).minimumScaleFactor(0.5)
                            if let delta = DashboardDelta.percent(now: totals.now, before: totals.before, versus: totals.versus) {
                                DashboardDeltaLine(delta: delta, lead: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if months.count > 1 && !typeSize.isAccessibilitySize {
                            DashboardMonthBars(values: months.map(\.revenue))
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
            .accessibilityHint("Opens revenue")
            .accessibilityIdentifier("home-revenue")
        }
    }

    /// Paper prints dashboard money in whole dollars ("$142,300").
    private func wholeMoney(_ cents: Int, currency: String = "USD") -> String {
        (Double(cents) / 100).formatted(.currency(code: currency).precision(.fractionLength(0)))
    }

    private func ownerTiles(_ period: DashboardPeriod) -> [AnyView] {
        var tiles: [AnyView] = []
        let range = period.range()
        let versus: String? = nil
        if canInvoices, loaded, let ticket = DashboardBooks.averageTicket(invoices, in: range.current) {
            let before = range.before.flatMap { DashboardBooks.averageTicket(invoices, in: $0) }
            tiles.append(AnyView(NavigationLink(value: PaperRoute.revenue) {
                DashboardTile(label: "Avg ticket", value: wholeMoney(ticket),
                              delta: .percent(now: ticket, before: before, versus: versus))
            }.buttonStyle(PressStyle()).accessibilityHint("Opens revenue")))
        }
        if let report = operations, !report.truncated,
           let totals = period.totals(report.months.map { (key: $0.month, value: $0.completed) }) {
            tiles.append(AnyView(DashboardTile(label: "Jobs completed", value: "\(totals.now)",
                                               delta: .difference(now: totals.now, before: totals.before))))
        }
        if canEstimates, loaded, let rate = DashboardBooks.closeRate(estimates, in: range.current) {
            let before = range.before.flatMap { DashboardBooks.closeRate(estimates, in: $0) }
            tiles.append(AnyView(DashboardTile(label: "Close rate", value: "\(rate)%",
                                               delta: .difference(now: rate, before: before, unit: " pts"))))
        }
        return tiles
    }

    // MARK: Office figures (Paper 52)

    /// "Revenue today" (this week, this month): what was invoiced in the period in 44 Bold, with
    /// "↑ 12% vs last Tue" under it when there is a figure to compare. Opens the invoices behind it.
    @ViewBuilder private var officeRevenue: some View {
        if canInvoices, loaded {
            let period = OfficePeriod(rawValue: officePeriod) ?? .today
            let range = period.range()
            let sent = DashboardBooks.issued(invoices, in: range.current)
            let total = sent.reduce(into: HomeAmounts()) { $0.add(DashboardBooks.total($1), $1.currency) }
            let single = total.totals.count <= 1
            let now = total.totals.values.first ?? 0
            let before = range.before.map { DashboardBooks.issued(invoices, in: $0).reduce(0) { $0 + DashboardBooks.total($1) } }
            NavigationLink(value: period == .today ? PaperRoute.homeList(.invoicedToday) : PaperRoute.revenue) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Revenue \(period.suffix)").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                    Text(single ? wholeMoney(now, currency: total.totals.keys.first ?? "USD") : total.text)
                        .font(Theme.display()).tracking(Theme.displayTracking())
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    if single, let delta = DashboardDelta.percent(now: now, before: before, versus: range.versus) {
                        DashboardDeltaLine(delta: delta, lead: true)
                    } else {
                        Text(sent.isEmpty ? "No invoices sent" : "\(sent.count) invoice\(sent.count == 1 ? "" : "s") sent")
                            .font(Theme.font(14)).foregroundStyle(Theme.muted).frame(minHeight: 20)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(PressStyle())
            .accessibilityElement(children: .combine)
            .accessibilityHint(period == .today ? "Lists them" : "Opens revenue")
            .accessibilityIdentifier("home-revenue")
        }
    }

    /// Paper 52's cards: Active techs and Jobs in progress side by side (live, whatever the
    /// period), then Completed with its count on the right. Each opens what is behind it.
    @ViewBuilder private func officeGlance(_ day: [Job]) -> some View {
        let counts = Dictionary(grouping: day) { HomeJobState(status: $0.status) }.mapValues(\.count)
        let people = OwnerDay.techs(store.jobs)
        let out = OwnerDay.techsOut(store.jobs)
        let onSite = counts[.onSite] ?? 0
        let onTheWay = counts[.onTheWay] ?? 0
        let stacked = typeSize.isAccessibilitySize
        let pair = stacked ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
        pair {
            NavigationLink(value: PaperRoute.homeList(.techs)) {
                DashboardTile(label: "Active techs",
                              value: people.isEmpty ? "0" : "\(out)/\(people.count)",
                              detail: people.isEmpty ? "No one booked today"
                                  : out == people.count ? "Everyone is on a job"
                                  : "\(people.count - out) not on a job",
                              figureSize: 28)
            }
            .buttonStyle(PressStyle())
            .accessibilityHint("Shows the techs")
            .accessibilityIdentifier("home-techs")
            NavigationLink(value: PaperRoute.homeList(.jobs(.onSite))) {
                DashboardTile(label: "Jobs in progress", value: "\(onSite)",
                              detail: onTheWay == 0 ? "None on the way" : "\(onTheWay) on the way",
                              figureSize: 28)
            }
            .buttonStyle(PressStyle())
            .accessibilityHint("Lists them")
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("home-glance")
        completedCard(day)
    }

    /// "Completed today" over one line, the count in 28 Bold on the right (Paper 52). Today's opens
    /// the finished jobs; a week or a month counts the finished visits booked in it.
    private func completedCard(_ day: [Job]) -> some View {
        let period = OfficePeriod(rawValue: officePeriod) ?? .today
        let range = period.range().current
        let booked: [Job] = period == .today ? day : store.jobs.filter { job in
            guard job.status != "canceled", let date = JobFiltering.date(job.scheduledFor) else { return false }
            return date >= range.start && date <= Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))!
        }
        let done = booked.filter { $0.status == "completed" }.count
        return NavigationLink(value: PaperRoute.homeList(.jobs(.done))) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Completed \(period.suffix)").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                    Text(booked.isEmpty ? "No visits booked" : "of \(booked.count) booked")
                        .font(Theme.font(14)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(done)").font(Theme.font(28, weight: .bold)).tracking(-0.56).foregroundStyle(Theme.foreground)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Lists today's finished jobs")
        .accessibilityIdentifier("home-progress")
    }

    // MARK: Money (Paper 52)

    private static func isToday(_ raw: String?) -> Bool {
        JobFiltering.date(raw).map { Calendar.current.isDateInToday($0) } ?? false
    }

    /// Paper 52's Money card: Outstanding (AR) and Collected today, the open balance beside the
    /// label. Payroll due is not drawn: the server keeps no payroll. Each row opens its records.
    @ViewBuilder private var moneyToday: some View {
        let unpaid = NeedsAttention.unpaid(invoices)
        let owed = unpaid.reduce(into: HomeAmounts()) { $0.add($1.1, $1.0.currency) }
        PaperSection(title: "Money", collapsed: $moneyCollapsed) {
            VStack(spacing: 0) {
                if !loaded {
                    PaperListRow(title: "Reading invoices…")
                } else {
                    NavigationLink(value: PaperRoute.homeList(.unpaid)) {
                        DashboardAmountRow(title: "Outstanding (AR)", amount: owed.isEmpty ? wholeMoney(0) : owed.wholeText)
                    }
                    .buttonStyle(RowPressStyle())
                    .accessibilityHint("Lists unpaid invoices")
                    if let collectedToday {
                        Button { showPayments = true } label: {
                            DashboardAmountRow(title: "Collected today", amount: wholeMoney(collectedToday), divider: true)
                        }
                        .buttonStyle(RowPressStyle())
                        .accessibilityHint("Opens payments")
                    }
                }
            }
        } accessory: {
            if loaded && !owed.isEmpty {
                Text("\(owed.wholeText) open").font(Theme.font(13))
            }
        }
        .accessibilityIdentifier("home-money")
    }

    // MARK: Needs attention

    private var savedWork: SavedWorkSnapshot? {
        guard let scope = SavedWorkScope.capture(session: session, api: api, media: media, outbox: outbox) else { return nil }
        return .make(scope: scope, entries: outbox.entries, media: media.items, mediaErrors: media.errors,
                     unverifiedMediaIDs: media.unverifiedIDs, uploadingMediaID: media.uploadingID,
                     commandsSyncing: outbox.syncing, jobs: store.jobs, listingWarning: media.storageWarning ?? outbox.storageWarning)
    }

    /// One thing that needs someone: a tinted mark, what it is, how much or how old, and where it leads.
    private struct NeedItem: Identifiable {
        let id: String
        let glyph: PaperGlyph
        let tint: Color
        let title: String
        let subtitle: String
        /// The next step, spoken to VoiceOver; the row itself opens it.
        let action: String
        /// Nil opens the saved-work review instead of a list.
        let route: PaperRoute?
        var identifier: String? = nil
    }

    /// Paper 52/58's Needs attention card: each row a coloured mark, a 16 Medium title over one
    /// muted line, and a chevron. The item-by-item list is the menu's Needs attention.
    @ViewBuilder private func needsYou(_ day: [Job]) -> some View {
        let unpaid = NeedsAttention.unpaid(invoices)
        let stale = NeedsAttention.waiting(estimates)
        let unscheduled = NeedsAttention.unscheduled(store.jobs)
        let unassigned = day.filter { $0.assignedToUserId == nil && $0.status != "completed" }
        let work = savedWork
        let syncProblem = (work?.attentionCount ?? 0) > 0 || (work?.hasListingWarning ?? false)
        let items: [NeedItem] = {
            var rows: [NeedItem] = []
            if syncProblem, let work {
                rows.append(NeedItem(id: "sync", glyph: .alertSync, tint: Theme.warning,
                                     title: work.hasListingWarning ? "Saved work needs checking" : "\(work.attentionCount) change\(work.attentionCount == 1 ? "" : "s") did not sync",
                                     subtitle: "Saved on this phone, not on the server yet", action: "Review", route: nil,
                                     identifier: "home-needs-sync"))
            }
            if !unassigned.isEmpty {
                rows.append(NeedItem(id: "unassigned", glyph: .alertTriangle, tint: Theme.destructive,
                                     title: "\(unassigned.count) same-day job\(unassigned.count == 1 ? "" : "s") unassigned",
                                     subtitle: "No tech assigned yet",
                                     action: session.can("job.assign", feature: "jobs") ? "Assign" : "Review",
                                     route: .homeList(.tech(userID: nil, name: "Not assigned"))))
            }
            if !unpaid.isEmpty {
                let owed = unpaid.reduce(into: HomeAmounts()) { $0.add($1.1, $1.0.currency) }
                rows.append(NeedItem(id: "unpaid", glyph: .alertClock, tint: Theme.warning,
                                     title: "\(PaperCount.text(unpaid.count)) invoice\(unpaid.count == 1 ? "" : "s") unpaid",
                                     subtitle: "\(owed.wholeText)\(oldest(unpaid.first?.0.issuedAt))",
                                     action: "Review", route: .homeList(.unpaid)))
            }
            if !stale.isEmpty {
                rows.append(NeedItem(id: "estimates", glyph: .alertDocument, tint: Theme.muted,
                                     title: "\(stale.count) estimate\(stale.count == 1 ? "" : "s") waiting on the customer",
                                     subtitle: "Sent a week or more ago\(oldest(stale.first?.sentAt))",
                                     action: "Follow up", route: .homeList(.estimatesWaiting(staleOnly: true))))
            }
            if !unscheduled.isEmpty {
                rows.append(NeedItem(id: "unscheduled", glyph: .alertCalendar, tint: Theme.muted,
                                     title: "\(PaperCount.text(unscheduled.count)) job\(unscheduled.count == 1 ? "" : "s") without a time",
                                     subtitle: "Booked, not on the schedule yet",
                                     action: session.can("job.assign", feature: "jobs") ? "Schedule" : "Review",
                                     route: .homeList(.unscheduled)))
            }
            return rows
        }()
        // Paper 58 speaks to the owner ("Needs your attention"); Paper 52's office title is plain.
        PaperSection(isOwner ? "Needs your attention" : "Needs attention",
                     count: items.isEmpty ? nil : items.count, collapsed: $needsCollapsed) {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    needLink(item, divider: index > 0)
                }
                if items.isEmpty {
                    PaperListRow(title: loaded ? "Nothing needs you right now" : "Checking…",
                                 subtitle: loaded ? "Unassigned jobs, unpaid invoices, waiting estimates, jobs without a time and failed syncs show up here." : nil,
                                 subtitleLines: 3)
                        .environment(\.paperRowInset, 16)
                }
            }
        }
        .accessibilityIdentifier("home-needs-you")
    }

    @ViewBuilder private func needLink(_ item: NeedItem, divider: Bool) -> some View {
        let row = DashboardMarkRow(glyph: item.glyph, tint: item.tint, title: item.title, subtitle: item.subtitle, divider: divider)
            .accessibilityHint(item.action)
        if let route = item.route {
            NavigationLink(value: route) { row }
                .buttonStyle(RowPressStyle())
                .modifier(OptionalIdentifier(identifier: item.identifier))
        } else {
            Button { reviewScope = SavedWorkScope.capture(session: session, api: api, media: media, outbox: outbox) } label: { row }
                .buttonStyle(RowPressStyle())
                .modifier(OptionalIdentifier(identifier: item.identifier))
        }
    }

    /// " · oldest 21 days" (Paper 52/58).
    private func oldest(_ raw: String?) -> String {
        guard let date = JobFiltering.date(raw) else { return "" }
        let days = PaperAge.days(from: date)
        return days <= 0 ? " · oldest today" : " · oldest \(PaperAge.span(days: days))"
    }

    // MARK: Loading

    private func load() async {
        async let invoiceList: [InvoiceRecord] = canInvoices ? api.fieldInvoices() : []
        async let estimateList: [EstimateRecord] = canEstimates ? api.fieldEstimates() : []
        do {
            invoices = try await invoiceList
            estimates = try await estimateList
            error = nil
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
        loaded = true
        if isOwner {
            if MenuItem.money.permitted(session) { revenue = (try? await api.revenueReport()) ?? revenue }
            if canEstimates { operations = (try? await api.operationsReport()) ?? operations }
        }
        // Paper 52 "Collected today": the newest page of payments, counted only when it reaches
        // back past midnight (or is the whole tape), so the row never comes up short.
        if !isOwner, canInvoices, let tape = try? await api.companyPayments(maxPages: 1) {
            let midnight = Calendar.current.startOfDay(for: .now)
            let covers = tape.complete
                || tape.payments.contains { (JobFiltering.date($0.recordedAt) ?? .distantFuture) < midnight }
            collectedToday = covers
                ? CompanyPayment.collected(tape.payments.filter { Self.isToday($0.recordedAt) })
                : nil
        }
    }
}

/// The list behind one Home figure: the same rows the rest of the app uses, nothing more.
struct OwnerHomeListView: View {
    let list: HomeList
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var outbox: FieldOutbox
    @StateObject private var addresses = JobAddressBook()
    @State private var invoices: [InvoiceRecord] = []
    @State private var estimates: [EstimateRecord] = []
    @State private var loaded = false
    @State private var error: String?
    @State private var scheduling: Job?
    @State private var roster: [String: String] = [:]
    @State private var rosterLoaded = false

    private var title: String {
        switch list {
        case .jobs(let state): "\(state.title) today"
        case .tech(_, let name): name
        case .techs: "Techs"
        case .unscheduled: "Jobs without a time"
        case .unpaid: "Unpaid invoices"
        case .invoicedToday: "Invoiced today"
        case .estimatesWaiting(let stale): stale ? "Waiting a week or more" : "Estimates waiting"
        }
    }

    private var jobs: [Job] {
        switch list {
        case .jobs(let state): OwnerDay.today(store.jobs).filter { HomeJobState(status: $0.status) == state }
        case .tech(let userID, _):
            // Their day, plus a job they are on that was booked for another day. Today's ids are read
            // once: asking for today inside the filter re-scans the whole book for every job.
            {
                let today = OwnerDay.today(store.jobs)
                let todayIDs = Set(today.map(\.id))
                return today.filter { $0.assignedToUserId == userID }
                    + (userID == nil ? [] : store.jobs.filter {
                        $0.assignedToUserId == userID && OwnerDay.activeStatuses.contains($0.status) && !todayIDs.contains($0.id)
                    })
            }()
        case .unscheduled: NeedsAttention.unscheduled(store.jobs)
        // The techs list reads addresses for the jobs people are on or heading to.
        case .techs:
            {
                let today = OwnerDay.today(store.jobs)
                let todayIDs = Set(today.map(\.id))
                return today + store.jobs.filter { OwnerDay.activeStatuses.contains($0.status) && !todayIDs.contains($0.id) }
            }()
        default: []
        }
    }

    private var isJobList: Bool {
        switch list {
        case .jobs, .tech, .unscheduled, .techs: true
        default: false
        }
    }

    var body: some View {
        let rows = jobs
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(Theme.font(30, weight: .medium)).tracking(-0.6).accessibilityAddTraits(.isHeader)
                    Text(subtitle(rows.count)).font(Theme.font(15)).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, Theme.gutter).padding(.bottom, 12)
                if let error { ErrorBanner(message: error) }
                if list == .techs { techsContent } else if isJobList { jobContent(rows) } else { documentContent }
            }
            .padding(.bottom, 24)
        }
        .background(Theme.canvas)
        .foregroundStyle(Theme.foreground)
        .navigationBarTitleDisplayMode(.inline)
        .task { if !isJobList { await load() } }
        .task(id: session.generation) {
            // Names for the Techs rows. The roster is never kept on the phone, so offline the rows
            // say "Technician" rather than guess.
            guard list == .techs, session.can("job.view", feature: "jobs"), let people = try? await api.fieldAssignees() else { return }
            roster = Dictionary(people.map { ($0.userId, $0.displayName) }, uniquingKeysWith: { first, _ in first })
            rosterLoaded = true
        }
        .refreshable {
            if isJobList { _ = await store.refresh(api) } else { await SavedCopies.$liveOnly.withValue(true) { await load() } }
        }
        .task(id: "addr|\(rows.map { "\($0.id):\($0.locationId ?? "")" }.joined(separator: ","))|\(session.generation)") {
            guard isJobList, session.can("customer.view", feature: "core_crm") else { return }
            await addresses.load(rows, api: api, organizationID: session.activeOrganization?.id,
                                 identity: "\(session.user?.id ?? "")|\(session.activeOrganization?.id ?? "")|\(session.generation)")
        }
        .sheet(item: $scheduling) { value in SheetSurface { QuickScheduleSheet(jobID: value.id) } }
    }

    private func subtitle(_ jobCount: Int) -> String {
        switch list {
        case .jobs, .tech: return "Today · \(jobCount) job\(jobCount == 1 ? "" : "s")"
        case .techs:
            let people = OwnerDay.techs(store.jobs)
            let out = OwnerDay.techsOut(store.jobs)
            return people.isEmpty ? "No one booked today" : "\(out) of \(people.count) on a job"
        case .unscheduled: return "\(jobCount) job\(jobCount == 1 ? "" : "s") need a time"
        case .unpaid: return loaded ? "\(unpaid.count) with a balance" : "Checking…"
        case .invoicedToday: return loaded ? "\(issuedToday.count) sent today" : "Checking…"
        case .estimatesWaiting: return loaded ? "\(waiting.count) not answered yet" : "Checking…"
        }
    }

    @ViewBuilder private func jobContent(_ rows: [Job]) -> some View {
        if rows.isEmpty {
            PaperEmptyState(symbol: "calendar", title: "No jobs here", message: "Pull down to check again.")
        } else {
            let canSchedule = session.can("job.assign", feature: "jobs")
            PaperCard {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, job in
                    ScheduleCompactRow(job: job, customer: store.customerName(job.customerId), street: addresses.street(job),
                                       timeStyle: list == .unscheduled ? .age : .time,
                                       pendingStatus: outbox.pendingStatus(for: job.id),
                                       showsPeriod: TimeColumn.showsPeriod(rows, at: index),
                                       schedule: list == .unscheduled && canSchedule ? { scheduling = job } : nil)
                }
                .padding(.vertical, PaperCardMetrics.edge)
            }
            .paperCardMargin()
        }
    }

    // MARK: Techs

    /// Everyone with work today: who they are, where they are, how far through the day. Each row
    /// opens that person's jobs; today's jobs nobody is assigned to sit last.
    @ViewBuilder private var techsContent: some View {
        let people = OwnerDay.techs(store.jobs)
        let unassigned = OwnerDay.today(store.jobs).filter { $0.assignedToUserId == nil }
        if people.isEmpty && unassigned.isEmpty {
            PaperEmptyState(symbol: "person.2", title: "No one booked today", message: "Pull down to check again.")
        } else {
            PaperCard {
                VStack(spacing: 0) {
                    ForEach(people) { tech in
                        let name = name(tech.userID)
                        NavigationLink(value: PaperRoute.homeList(.tech(userID: tech.userID, name: name))) {
                            let state = techState(tech)
                            PaperListRow(title: name, subtitle: state.line, meta: tech.total == 0 ? nil : "\(tech.done) of \(tech.total) done today",
                                         subtitleLines: 2, status: StatusWord(text: state.word, tint: state.tint))
                        }.buttonStyle(RowPressStyle())
                    }
                    if !unassigned.isEmpty {
                        NavigationLink(value: PaperRoute.homeList(.tech(userID: nil, name: "Not assigned"))) {
                            PaperListRow(title: "Not assigned", subtitle: "\(unassigned.count) of today's jobs have no tech",
                                         status: StatusWord(text: "\(unassigned.count) job\(unassigned.count == 1 ? "" : "s")", tint: Theme.warning))
                        }.buttonStyle(RowPressStyle())
                    }
                }
                .padding(.vertical, PaperCardMetrics.edge)
            }
            .paperCardMargin()
            .accessibilityIdentifier("home-techs-list")
        }
    }

    private func name(_ userID: String) -> String {
        if let known = roster[userID] { return known }
        if userID == session.user?.id { return "You" }
        return rosterLoaded ? "Someone outside your roster" : "Technician"
    }

    private func place(_ job: Job) -> String { addresses.street(job) ?? job.title }

    private func techState(_ tech: OwnerDay.TechDay) -> (word: String, line: String, tint: Color?) {
        if let job = tech.active {
            switch job.status {
            case "en_route": return ("On the way", "On the way to \(place(job))", StatusWord.jobTint("en_route"))
            case "paused": return ("Paused", "Paused at \(place(job))", StatusWord.jobTint("paused"))
            default: return ("On site", "On site at \(place(job))", StatusWord.jobTint("in_progress"))
            }
        }
        if let next = tech.next {
            let time = JobFiltering.date(next.scheduledFor)?.tradeTime ?? "later"
            return ("Idle", "Next at \(time) · \(place(next))", nil)
        }
        if tech.total > 0 && tech.done == tech.total { return ("Done", "Finished today's jobs", StatusWord.jobTint("completed")) }
        return ("Idle", "Nothing booked for the rest of today", nil)
    }

    private var unpaid: [(InvoiceRecord, Int)] { NeedsAttention.unpaid(invoices) }
    private var issuedToday: [InvoiceRecord] {
        invoices.filter { $0.status != "void" && $0.status != "draft" &&
            (JobFiltering.date($0.issuedAt).map { Calendar.current.isDateInToday($0) } ?? false) }
    }
    private var waiting: [EstimateRecord] {
        if case .estimatesWaiting(true) = list { return NeedsAttention.waiting(estimates) }
        return estimates.filter { $0.status == "sent" }.sorted { (JobFiltering.date($0.sentAt) ?? .now) < (JobFiltering.date($1.sentAt) ?? .now) }
    }

    @ViewBuilder private var documentContent: some View {
        if !loaded {
            SkeletonRows(count: 4, leading: false)
        } else {
            switch list {
            case .unpaid, .invoicedToday:
                let rows: [(InvoiceRecord, Int?)] = list == .unpaid ? unpaid.map { ($0.0, $0.1) } : issuedToday.map { ($0, nil) }
                if rows.isEmpty {
                    PaperEmptyState(symbol: "doc.plaintext", title: list == .unpaid ? "Nothing unpaid" : "No invoices sent today",
                                    message: "Pull down to check again.")
                } else {
                    PaperCard {
                        ForEach(rows, id: \.0.id) { invoice, balance in
                            NavigationLink(value: PaperRoute.invoice(invoice.id)) {
                                let total = paperLinesTotal(invoice.lines) ?? 0
                                PaperListRow(title: store.customerName(invoice.customerId),
                                             subtitle: "INV-\(invoice.id.suffix(4).uppercased()) · \(invoice.status == "paid" ? "Paid" : balance != nil ? "Unpaid" : "Sent")",
                                             amount: money(balance ?? total, currency: invoice.currency))
                            }.buttonStyle(RowPressStyle())
                        }
                        .padding(.vertical, PaperCardMetrics.edge)
                    }
                    .paperCardMargin()
                }
            default:
                if waiting.isEmpty {
                    PaperEmptyState(symbol: "doc.text", title: "No estimates waiting", message: "Pull down to check again.")
                } else {
                    PaperCard {
                        ForEach(waiting) { estimate in
                            NavigationLink(value: PaperRoute.estimate(estimate.id)) {
                                PaperListRow(title: estimate.title,
                                             subtitle: "\(store.customerName(estimate.customerId)) · sent \(JobFiltering.date(estimate.sentAt)?.formatted(.relative(presentation: .named)) ?? "")",
                                             amount: paperLinesTotal(estimate.lines).map { money($0, currency: estimate.lines.first?.unitPrice.currency ?? "USD") } ?? "")
                            }.buttonStyle(RowPressStyle())
                        }
                        .padding(.vertical, PaperCardMetrics.edge)
                    }
                    .paperCardMargin()
                }
            }
        }
    }

    private func load() async {
        do {
            switch list {
            case .unpaid, .invoicedToday: invoices = try await api.fieldInvoices()
            case .estimatesWaiting: estimates = try await api.fieldEstimates()
            default: break
            }
            error = nil
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
        loaded = true
    }
}

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
}

struct OwnerHomeView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var outbox: FieldOutbox
    @EnvironmentObject private var media: PendingMediaStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @StateObject private var addresses = JobAddressBook()
    @State private var invoices: [InvoiceRecord] = []
    @State private var estimates: [EstimateRecord] = []
    @State private var roster: [String: String] = [:]
    @State private var rosterLoaded = false
    @State private var revenue: RevenueReport?
    @State private var loaded = false
    @State private var error: String?
    @State private var reviewScope: SavedWorkScope?
    @State private var showPayments = false
    @State private var showMoney = false
    /// What came in today, when the newest page of payments reaches back past midnight; nil until
    /// then, so a partial read never prints a smaller, wrong figure.
    @State private var collectedToday: Int?
    /// Paper 52/58: each section's label folds its card away (the chevron before the label).
    @State private var needsCollapsed = false
    @State private var moneyCollapsed = false
    @State private var techsCollapsed = false

    private var canInvoices: Bool { session.can("invoice.view", feature: "invoicing") }
    private var canEstimates: Bool { session.can("estimate.view", feature: "estimates") }
    private var todayJobs: [Job] { OwnerDay.today(store.jobs) }

    var body: some View {
        let day = todayJobs
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Paper 52/58: the Dashboard title, the day and what's moving under it.
                PaperHeader(title: "Dashboard", subtitle: headline(day), showsCreate: true)
                OfflineBanner()
                SavedCopyNote(savedAt: savedAt).padding(.bottom, 6)
                if let error = store.error { ErrorBanner(message: error) { _ = await store.refresh(api) } }
                if let error { ErrorBanner(message: error) }
                // The figures: the month's money large, then today's people and jobs as cards.
                VStack(alignment: .leading, spacing: 10) {
                    revenueHero
                    if store.loading && store.jobs.isEmpty {
                        SkeletonRows().padding(.horizontal, -PaperCardMetrics.margin)
                    } else {
                        glance(day, proxy: proxy)
                    }
                }
                .paperCardMargin()
                .padding(.top, 4)
                VStack(alignment: .leading, spacing: 20) {
                    needsYou(day)
                    if canInvoices || canEstimates { moneyToday }
                    techs(day).id("home-techs")
                }
                .paperCardMargin()
                .padding(.top, 22)
                // Every section is a semibold label with its count over one card.
                .environment(\.paperGroupedWells, true)
            }
            .padding(.bottom, 40)
        }
        #if DEBUG
        // Screenshots of the lower sections: --paper-preview-scroll-end.
        .task(id: loaded) {
            guard PaperPreview.enabled, loaded, ProcessInfo.processInfo.arguments.contains("--paper-preview-scroll-end") else { return }
            try? await Task.sleep(for: .milliseconds(800))
            proxy.scrollTo("home-techs", anchor: .bottom)
        }
        #endif
        }
        .background(Theme.canvas)
        .foregroundStyle(Theme.foreground)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.generation) { await load() }
        .thorbisDestination(isPresented: $showPayments) { CompanyPaymentsView() }
        .thorbisDestination(isPresented: $showMoney) { ReportsView(includesRevenue: true, initialTab: "Overview") }
        .refreshable {
            _ = await store.refresh(api)
            await SavedCopies.$liveOnly.withValue(true) { await load() }
        }
        .task(id: "addr|\(day.map { "\($0.id):\($0.locationId ?? "")" }.joined(separator: ","))|\(session.generation)|\(session.isOffline)") {
            guard session.can("customer.view", feature: "core_crm") else { return }
            await addresses.load(day + store.jobs.filter { OwnerDay.activeStatuses.contains($0.status) }, api: api,
                                 organizationID: session.activeOrganization?.id,
                                 identity: "\(session.user?.id ?? "")|\(session.activeOrganization?.id ?? "")|\(session.generation)")
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

    /// The oldest copy on screen that came from this phone instead of the server.
    private var savedAt: Date? {
        [store.cachedAt, canInvoices ? api.savedCopyDate("/v1/invoices") : nil,
         canEstimates ? api.savedCopyDate("/v1/estimates") : nil].compactMap { $0 }.min()
    }

    // MARK: Figures

    /// Paper's figure card: 16 padding on the card, radius 20.
    private static let cardPadding: CGFloat = 16

    /// The month's money, large (Paper 52 "Revenue today", 58 "Revenue"). The revenue report is kept
    /// in whole months, so the card names its month and says it is the month so far, never "today".
    /// The bars are the months the report carries, this month in brand blue. Opens Revenue.
    @ViewBuilder private var revenueHero: some View {
        if let report = revenue, !report.truncated, let month = report.months.last {
            let months = Array(report.months.suffix(12))
            NavigationLink(value: PaperRoute.revenue) {
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Collected in \(Self.monthName(month.month))")
                            .font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                        Text(money(month.collected, currency: "USD"))
                            // Paper 52/58: the lead figure in 44 Bold; one line, shrinking before it clips.
                            .font(Theme.display()).tracking(Theme.displayTracking())
                            .foregroundStyle(Theme.foreground)
                            .lineLimit(1).minimumScaleFactor(0.5)
                        Text("Month so far").font(Theme.font(14)).foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if months.count > 1 && !typeSize.isAccessibilitySize {
                        VStack(alignment: .trailing, spacing: 10) {
                            Text("Trailing \(months.count) mo").font(Theme.font(13)).foregroundStyle(Theme.muted)
                            Self.monthBars(months)
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
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

    /// Paper 58's trailing bars: one per month, the latest in brand blue. Decorative; the card's
    /// words carry the figure.
    private static func monthBars(_ months: [RevenueReport.Month]) -> some View {
        let peak = max(months.map(\.collected).max() ?? 1, 1)
        return HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(months.enumerated()), id: \.element.id) { index, month in
                Capsule()
                    .fill(index == months.count - 1 ? Theme.brand : Theme.muted.opacity(0.55))
                    .frame(width: 5, height: max(5, 38 * CGFloat(month.collected) / CGFloat(peak)))
            }
        }
        .frame(height: 38, alignment: .bottom)
        .accessibilityHidden(true)
    }

    /// Today's people and jobs as Paper 52's cards: Active techs and Jobs in progress side by side,
    /// then Completed today with its count on the right and the day's progress under it. Each card
    /// opens the jobs (or the techs) behind it.
    @ViewBuilder private func glance(_ day: [Job], proxy: ScrollViewProxy) -> some View {
        let counts = Dictionary(grouping: day) { HomeJobState(status: $0.status) }.mapValues(\.count)
        let people = OwnerDay.techs(store.jobs)
        let out = OwnerDay.techsOut(store.jobs)
        let onSite = counts[.onSite] ?? 0
        let onTheWay = counts[.onTheWay] ?? 0
        let stacked = typeSize.isAccessibilitySize
        let pair = stacked ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
        VStack(alignment: .leading, spacing: 10) {
            pair {
                Button {
                    withMotion(.easeOut(duration: 0.3)) { proxy.scrollTo("home-techs", anchor: .top) }
                } label: {
                    statTile(label: "Active techs",
                             value: people.isEmpty ? "0" : "\(out)/\(people.count)",
                             detail: people.isEmpty ? "No one booked today"
                                 : out == people.count ? "Everyone is on a job"
                                 : "\(people.count - out) not on a job")
                }
                .buttonStyle(PressStyle())
                .accessibilityHint("Shows the techs")
                NavigationLink(value: PaperRoute.homeList(.jobs(.onSite))) {
                    statTile(label: "Jobs in progress", value: "\(onSite)",
                             detail: onTheWay == 0 ? "None on the way" : "\(onTheWay) on the way")
                }
                .buttonStyle(PressStyle())
                .accessibilityHint("Lists them")
            }
            .fixedSize(horizontal: false, vertical: true)
            completedCard(done: counts[.done] ?? 0, scheduled: counts[.scheduled] ?? 0, total: day.count)
            // Kept from before Paper v2 (not in Paper 52): today's still-to-start and on-the-way
            // lists stay one tap away, shown only when they hold jobs.
            let scheduled = counts[.scheduled] ?? 0
            if scheduled > 0 || onTheWay > 0 {
                HStack(spacing: 16) {
                    if scheduled > 0 { glanceLink("\(scheduled) still to start", state: .scheduled) }
                    if onTheWay > 0 { glanceLink("\(onTheWay) on the way", state: .onTheWay) }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 4)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home-glance")
    }

    private func glanceLink(_ title: String, state: HomeJobState) -> some View {
        NavigationLink(value: PaperRoute.homeList(.jobs(state))) {
            HStack(spacing: 4) {
                Text(title).font(Theme.font(14, weight: .medium)).monospacedDigit()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).accessibilityHidden(true)
            }
            .foregroundStyle(Theme.brandText)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }

    /// A figure card: 13 Semibold label, the figure in bold tabular, one muted line.
    private func statTile(label: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
            // Paper 52: the figure in 28 Bold, tabular.
            Text(value).font(Theme.heading().monospacedDigit()).tracking(-0.56).foregroundStyle(Theme.foreground)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(detail).font(Theme.font(14)).foregroundStyle(Theme.muted)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Self.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// "Completed today" with the count on the right (Paper 52), then a thin bar in the done green;
    /// an empty day says so instead of 0 of 0. Opens today's finished jobs.
    private func completedCard(done: Int, scheduled: Int, total: Int) -> some View {
        NavigationLink(value: PaperRoute.homeList(.jobs(.done))) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Completed today").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                        Text(total == 0 ? "No visits booked today"
                             : scheduled == 0 ? "\(done) of \(total) done"
                             : "\(done) of \(total) done · \(scheduled) still to start")
                            .font(Theme.font(14)).monospacedDigit().foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(done)").font(Theme.heading().monospacedDigit()).tracking(-0.56).foregroundStyle(Theme.foreground)
                }
                if total > 0 {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.fill)
                            Capsule().fill(Theme.statusDone)
                                .frame(width: max(done == 0 ? 0 : 6, geometry.size.width * CGFloat(done) / CGFloat(total)))
                        }
                    }
                    .frame(height: 6)
                    .accessibilityHidden(true)
                }
            }
            .padding(Self.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Lists them")
        .accessibilityIdentifier("home-progress")
    }

    // MARK: Money

    private static func isToday(_ raw: String?) -> Bool {
        JobFiltering.date(raw).map { Calendar.current.isDateInToday($0) } ?? false
    }

    /// Where a money row leads.
    private enum MoneyTarget {
        case route(PaperRoute)
        case overview
        case payments
    }

    private struct MoneyItem: Identifiable {
        let id: String
        let title: String
        var amount: String? = nil
        /// A quiet word before the amount (Paper's "Fri" beside Payroll due).
        var note: String? = nil
        var subtitle: String? = nil
        let target: MoneyTarget
    }

    /// Paper 52's Money card: label rows 56 tall, the amount in semibold tabular on the right, the
    /// open balance beside the section label. Each row opens the records behind it.
    @ViewBuilder private var moneyToday: some View {
        let issuedToday = invoices.filter { $0.status != "void" && $0.status != "draft" && Self.isToday($0.issuedAt) }
        let invoiced = issuedToday.reduce(into: HomeAmounts()) { $0.add(paperLinesTotal($1.lines) ?? 0, $1.currency) }
        let unpaid = NeedsAttention.unpaid(invoices)
        let owed = unpaid.reduce(into: HomeAmounts()) { $0.add($1.1, $1.0.currency) }
        let sent = estimates.filter { $0.status == "sent" }
        let waiting = sent.reduce(into: HomeAmounts()) {
            $0.add(paperLinesTotal($1.lines) ?? 0, $1.lines.first?.unitPrice.currency ?? "USD")
        }
        let zero = money(0, currency: "USD")
        let items: [MoneyItem] = {
            var rows: [MoneyItem] = []
            guard loaded else { return rows }
            if canInvoices {
                rows.append(MoneyItem(id: "unpaid", title: "Outstanding (AR)", amount: owed.isEmpty ? zero : owed.text,
                                      note: unpaid.isEmpty ? nil : "\(unpaid.count)",
                                      target: .route(.homeList(.unpaid))))
                // Paper 52's second row. Opens Payments, where today's are listed one by one.
                if let collectedToday {
                    rows.append(MoneyItem(id: "collected", title: "Collected today",
                                          amount: money(collectedToday, currency: "USD"), target: .payments))
                }
                rows.append(MoneyItem(id: "invoiced", title: "Invoiced today", amount: invoiced.isEmpty ? zero : invoiced.text,
                                      note: issuedToday.isEmpty ? nil : "\(issuedToday.count)",
                                      target: .route(.homeList(.invoicedToday))))
            }
            if canEstimates {
                rows.append(MoneyItem(id: "estimates", title: "Estimates waiting", amount: waiting.isEmpty ? zero : waiting.text,
                                      note: sent.isEmpty ? nil : "\(sent.count)",
                                      target: .route(.homeList(.estimatesWaiting(staleOnly: false)))))
            }
            if canInvoices {
                // Web parity: outstanding, aging and who to chase (money.tsx); every payment collected.
                rows.append(MoneyItem(id: "overview", title: "Money overview", subtitle: "Outstanding, aging and who to chase", target: .overview))
                rows.append(MoneyItem(id: "payments", title: "Payments", subtitle: "Every payment, by card or cash", target: .payments))
            }
            return rows
        }()
        PaperSection(title: "Money", collapsed: $moneyCollapsed) {
            VStack(spacing: 0) {
                if !loaded {
                    PaperListRow(title: "Reading invoices and estimates…")
                }
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    moneyLink(item, divider: index > 0)
                }
            }
        } accessory: {
            if loaded && canInvoices && !owed.isEmpty {
                Text("\(owed.text) open").font(Theme.font(13)).monospacedDigit()
            }
        }
        .accessibilityIdentifier("home-money")
    }

    @ViewBuilder private func moneyLink(_ item: MoneyItem, divider: Bool) -> some View {
        switch item.target {
        case .route(let route):
            NavigationLink(value: route) { moneyRow(item, divider: divider) }.buttonStyle(RowPressStyle())
        case .overview:
            Button { showMoney = true } label: { moneyRow(item, divider: divider) }.buttonStyle(RowPressStyle())
        case .payments:
            Button { showPayments = true } label: { moneyRow(item, divider: divider) }.buttonStyle(RowPressStyle())
        }
    }

    /// 16 Medium label, the amount in 16 Semibold tabular (a count before it in the muted 13), or a
    /// chevron for a row that opens a place. A hairline sits between rows, inset to the text.
    private func moneyRow(_ item: MoneyItem, divider: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle = item.subtitle {
                    Text(subtitle).font(Theme.font(14)).foregroundStyle(Theme.muted)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let amount = item.amount {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let note = item.note {
                        Text(note).font(Theme.font(13)).monospacedDigit().foregroundStyle(Theme.muted)
                    }
                    Text(amount).font(Theme.monoFont(16, weight: .semibold)).foregroundStyle(Theme.foreground)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
            } else {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.muted).accessibilityHidden(true)
            }
        }
        .padding(.trailing, Self.cardPadding).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .overlay(alignment: .top) { if divider { WellDivider(leading: 0) } }
        .padding(.leading, Self.cardPadding)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private static func monthName(_ key: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "UTC")
        parser.dateFormat = "yyyy-MM"
        guard let date = parser.date(from: key) else { return key }
        let out = DateFormatter()
        out.timeZone = TimeZone(identifier: "UTC")
        out.setLocalizedDateFormatFromTemplate("MMMM")
        return out.string(from: date)
    }

    // MARK: Needs attention

    private var savedWork: SavedWorkSnapshot? {
        guard let scope = SavedWorkScope.capture(session: session, api: api, media: media, outbox: outbox) else { return nil }
        return .make(scope: scope, entries: outbox.entries, media: media.items, mediaErrors: media.errors,
                     unverifiedMediaIDs: media.unverifiedIDs, uploadingMediaID: media.uploadingID,
                     commandsSyncing: outbox.syncing, jobs: store.jobs, listingWarning: media.storageWarning)
    }

    /// One thing that needs someone: a tinted mark, what it is, how much or how old, and where it leads.
    private struct NeedItem: Identifiable {
        let id: String
        let symbol: String
        let tint: Color
        let title: String
        let subtitle: String
        /// The next step, spoken to VoiceOver; the row itself opens it.
        let action: String
        /// Nil opens the saved-work review instead of a list.
        let route: PaperRoute?
        var identifier: String? = nil
    }

    /// Paper 52's Needs attention card: each row a coloured mark, a 16 Medium title over one muted
    /// line, and a chevron. The full list, item by item, stays one tap away under it.
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
                rows.append(NeedItem(id: "sync", symbol: "arrow.triangle.2.circlepath", tint: Theme.warning,
                                     title: work.hasListingWarning ? "Saved work needs checking" : "\(work.attentionCount) change\(work.attentionCount == 1 ? "" : "s") did not sync",
                                     subtitle: "Saved on this phone, not on the server yet", action: "Review", route: nil,
                                     identifier: "home-needs-sync"))
            }
            if !unassigned.isEmpty {
                rows.append(NeedItem(id: "unassigned", symbol: "exclamationmark.triangle", tint: Theme.destructive,
                                     title: "\(unassigned.count) same-day job\(unassigned.count == 1 ? "" : "s") unassigned",
                                     subtitle: "No tech assigned yet",
                                     action: session.can("job.assign", feature: "jobs") ? "Assign" : "Review",
                                     route: .homeList(.tech(userID: nil, name: "Not assigned"))))
            }
            if !unpaid.isEmpty {
                let owed = unpaid.reduce(into: HomeAmounts()) { $0.add($1.1, $1.0.currency) }
                rows.append(NeedItem(id: "unpaid", symbol: "clock", tint: Theme.warning,
                                     title: "\(unpaid.count) unpaid invoice\(unpaid.count == 1 ? "" : "s")",
                                     subtitle: "\(owed.text)\(oldest(unpaid.first?.0.issuedAt, verb: "issued"))",
                                     action: "Review", route: .homeList(.unpaid)))
            }
            if !stale.isEmpty {
                rows.append(NeedItem(id: "estimates", symbol: "doc.text", tint: Theme.brandText,
                                     title: "\(stale.count) estimate\(stale.count == 1 ? "" : "s") waiting on the customer",
                                     subtitle: "Sent a week or more ago\(oldest(stale.first?.sentAt, verb: "sent"))",
                                     action: "Follow up", route: .homeList(.estimatesWaiting(staleOnly: true))))
            }
            if !unscheduled.isEmpty {
                rows.append(NeedItem(id: "unscheduled", symbol: "calendar.badge.exclamationmark", tint: Theme.muted,
                                     title: "\(unscheduled.count) job\(unscheduled.count == 1 ? "" : "s") without a time",
                                     subtitle: "Booked, not on the schedule yet",
                                     action: session.can("job.assign", feature: "jobs") ? "Schedule" : "Review",
                                     route: .homeList(.unscheduled)))
            }
            return rows
        }()
        // Paper 58 speaks to the owner ("Needs your attention"); Paper 52's office title is plain.
        PaperSection(session.can("organization.settings.edit") ? "Needs your attention" : "Needs attention",
                     count: items.isEmpty ? nil : items.count, collapsed: $needsCollapsed) {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    needLink(item, divider: index > 0)
                }
                if items.isEmpty {
                    PaperListRow(title: loaded ? "Nothing needs you right now" : "Checking…",
                                 subtitle: loaded ? "Unassigned jobs, unpaid invoices, waiting estimates, jobs without a time and failed syncs show up here." : nil,
                                 subtitleLines: 3)
                        .environment(\.paperRowInset, Self.cardPadding)
                }
                NavigationLink(value: PaperRoute.attention) {
                    needRow(NeedItem(id: "all", symbol: "list.bullet", tint: Theme.muted,
                                     title: "Everything in Needs attention", subtitle: "Each invoice, estimate and job, one by one",
                                     action: "Opens the list", route: .attention),
                            divider: true)
                }.buttonStyle(RowPressStyle())
            }
        }
        .accessibilityIdentifier("home-needs-you")
    }

    @ViewBuilder private func needLink(_ item: NeedItem, divider: Bool) -> some View {
        if let route = item.route {
            NavigationLink(value: route) { needRow(item, divider: divider) }
                .buttonStyle(RowPressStyle())
                .modifier(OptionalIdentifier(identifier: item.identifier))
        } else {
            Button { reviewScope = SavedWorkScope.capture(session: session, api: api, media: media, outbox: outbox) } label: {
                needRow(item, divider: divider)
            }
            .buttonStyle(RowPressStyle())
            .modifier(OptionalIdentifier(identifier: item.identifier))
        }
    }

    /// A 34-wide lane for the mark, then the words and a chevron; the hairline between rows starts
    /// at the words, as in Paper.
    private func needRow(_ item: NeedItem, divider: Bool) -> some View {
        HStack(alignment: .center, spacing: 0) {
            Image(systemName: item.symbol).font(.system(size: 20, weight: .regular)).foregroundStyle(item.tint)
                .frame(width: 34, alignment: .leading)
                .accessibilityHidden(true)
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.title).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.subtitle).font(Theme.font(14)).monospacedDigit().foregroundStyle(Theme.muted)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.muted).accessibilityHidden(true)
            }
            .padding(.trailing, 14).padding(.vertical, 11)
            .frame(minHeight: 56)
            .overlay(alignment: .top) { if divider { WellDivider(leading: 0) } }
        }
        .padding(.leading, Self.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(item.action)
    }

    /// " · oldest issued 12 days ago".
    private func oldest(_ raw: String?, verb: String) -> String {
        guard let date = JobFiltering.date(raw) else { return "" }
        let days = Calendar.current.dateComponents([.day], from: date, to: .now).day ?? 0
        switch days {
        case ...0: return " · oldest \(verb) today"
        case 1..<14: return " · oldest \(verb) \(days) day\(days == 1 ? "" : "s") ago"
        case 14..<60: return " · oldest \(verb) \(days / 7) weeks ago"
        default: return " · oldest \(verb) \(days / 30) month\(days / 30 == 1 ? "" : "s") ago"
        }
    }

    // MARK: Techs

    @ViewBuilder private func techs(_ day: [Job]) -> some View {
        let people = OwnerDay.techs(store.jobs)
        let unassigned = day.filter { $0.assignedToUserId == nil }
        if !people.isEmpty || !unassigned.isEmpty {
            PaperSection(title: "Techs", count: people.count, collapsed: $techsCollapsed) {
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
            } accessory: {
                if rosterLoaded == false && !people.isEmpty && loaded {
                    Text("Names need a connection").font(Theme.font(13)).foregroundStyle(Theme.muted)
                }
            }
            .accessibilityIdentifier("home-techs")
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
        // Names for the Techs rows. The roster is never kept on the phone, so offline the rows say
        // "Technician" rather than guess.
        if session.can("job.view", feature: "jobs"), let people = try? await api.fieldAssignees() {
            roster = Dictionary(people.map { ($0.userId, $0.displayName) }, uniquingKeysWith: { first, _ in first })
            rosterLoaded = true
        }
        if MenuItem.money.permitted(session) { revenue = (try? await api.revenueReport()) ?? revenue }
        // Paper 52 "Collected today": the newest page of payments, counted only when it reaches
        // back past midnight (or is the whole tape), so the row never comes up short.
        if canInvoices, let tape = try? await api.companyPayments(maxPages: 1) {
            let midnight = Calendar.current.startOfDay(for: .now)
            let covers = tape.complete
                || tape.payments.contains { (JobFiltering.date($0.recordedAt) ?? .distantFuture) < midnight }
            collectedToday = covers
                ? tape.payments.filter { !$0.refunded && Self.isToday($0.recordedAt) }.reduce(0) { $0 + $1.amount }
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

    private var title: String {
        switch list {
        case .jobs(let state): "\(state.title) today"
        case .tech(_, let name): name
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
            // Their day, plus a job they are on that was booked for another day.
            OwnerDay.today(store.jobs).filter { $0.assignedToUserId == userID }
                + (userID == nil ? [] : store.jobs.filter {
                    $0.assignedToUserId == userID && OwnerDay.activeStatuses.contains($0.status)
                        && !OwnerDay.today(store.jobs).contains($0)
                })
        case .unscheduled: NeedsAttention.unscheduled(store.jobs)
        default: []
        }
    }

    private var isJobList: Bool {
        switch list {
        case .jobs, .tech, .unscheduled: true
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
                if isJobList { jobContent(rows) } else { documentContent }
            }
            .padding(.bottom, 24)
        }
        .background(Theme.canvas)
        .foregroundStyle(Theme.foreground)
        .navigationBarTitleDisplayMode(.inline)
        .task { if !isJobList { await load() } }
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

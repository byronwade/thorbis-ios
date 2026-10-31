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

    private var canInvoices: Bool { session.can("invoice.view", feature: "invoicing") }
    private var canEstimates: Bool { session.can("estimate.view", feature: "estimates") }
    private var todayJobs: [Job] { OwnerDay.today(store.jobs) }

    var body: some View {
        let day = todayJobs
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PaperHeader(title: "Home", subtitle: headline(day), showsCreate: true)
                OfflineBanner()
                SavedCopyNote(savedAt: savedAt).padding(.bottom, 6)
                if let error = store.error { ErrorBanner(message: error) { _ = await store.refresh(api) } }
                if let error { ErrorBanner(message: error) }
                VStack(alignment: .leading, spacing: 18) {
                    if store.loading && store.jobs.isEmpty {
                        SkeletonRows().padding(.horizontal, -PaperCardMetrics.margin)
                    } else {
                        glance(day)
                    }
                    if canInvoices || canEstimates { moneyToday }
                    needsYou
                    techs(day).id("home-techs")
                }
                .paperCardMargin()
                // Redesign phase 3: every section is a semibold header with its count over one well.
                .environment(\.paperGroupedWells, true)
            }
            .padding(.bottom, 24)
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
        .background(Theme.background)
        .foregroundStyle(Theme.foreground)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.generation) { await load() }
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
        .sheet(item: $reviewScope) { SavedWorkReviewView(scope: $0) }
    }

    // MARK: Header

    /// "Sat, Oct 31 · 14 jobs · 3 techs out".
    private func headline(_ day: [Job]) -> String {
        let date = Date.now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let out = OwnerDay.techsOut(store.jobs)
        var parts = [date, "\(day.count) job\(day.count == 1 ? "" : "s")"]
        parts.append(out == 0 ? "no techs out" : "\(out) tech\(out == 1 ? "" : "s") out")
        return parts.joined(separator: " · ")
    }

    /// The oldest copy on screen that came from this phone instead of the server.
    private var savedAt: Date? {
        [store.cachedAt, canInvoices ? api.savedCopyDate("/v1/invoices") : nil,
         canEstimates ? api.savedCopyDate("/v1/estimates") : nil].compactMap { $0 }.min()
    }

    // MARK: Today at a glance

    /// Today's progress, Linear style: "4 of 14 done" over a thin bar, then the four states as
    /// counts led by their status glyph. Each count opens the jobs behind it.
    @ViewBuilder private func glance(_ day: [Job]) -> some View {
        let counts = Dictionary(grouping: day) { HomeJobState(status: $0.status) }.mapValues(\.count)
        PaperSection("Today", count: day.isEmpty ? nil : day.count) {
            VStack(alignment: .leading, spacing: 0) {
                progress(done: counts[.done] ?? 0, total: day.count)
                WellDivider()
                if typeSize.isAccessibilitySize {
                    VStack(spacing: 0) {
                        ForEach(Array(HomeJobState.allCases.enumerated()), id: \.element) { index, state in
                            let count = counts[state] ?? 0
                            NavigationLink(value: PaperRoute.homeList(.jobs(state))) {
                                PaperListRow(title: state.title) {
                                    Text("\(count)").font(Theme.font(20, weight: .semibold)).monospacedDigit()
                                        .foregroundStyle(count == 0 ? Theme.muted : Theme.foreground)
                                }
                            }
                            .buttonStyle(RowPressStyle())
                            .accessibilityLabel("\(state.title), \(count) job\(count == 1 ? "" : "s") today")
                            if index < HomeJobState.allCases.count - 1 { WellDivider() }
                        }
                    }
                } else {
                    Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                        GridRow {
                            glanceCell(.scheduled, counts)
                            glanceCell(.onTheWay, counts)
                        }
                        GridRow {
                            glanceCell(.onSite, counts)
                            glanceCell(.done, counts)
                        }
                    }
                    .padding(PaperCardMetrics.edge)
                }
            }
        }
        .accessibilityIdentifier("home-glance")
    }

    /// "4 of 14 done" and a thin bar in the done green; an empty day says so instead of 0 of 0.
    private func progress(done: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(total == 0 ? "No visits booked today" : "\(done) of \(total) done")
                    .font(Theme.font(17, weight: .semibold)).monospacedDigit()
                Spacer(minLength: 8)
                if total > 0 {
                    Text("\(Int((Double(done) / Double(total) * 100).rounded()))%")
                        .font(Theme.font(15)).monospacedDigit().foregroundStyle(Theme.muted)
                }
            }
            if total > 0 {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.fill)
                        Capsule().fill(Theme.statusDone)
                            .frame(width: max(done == 0 ? 0 : 6, proxy.size.width * CGFloat(done) / CGFloat(total)))
                    }
                }
                .frame(height: 6)
                .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 14)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home-progress")
    }

    private func glanceCell(_ state: HomeJobState, _ counts: [HomeJobState: Int]) -> some View {
        let count = counts[state] ?? 0
        return NavigationLink(value: PaperRoute.homeList(.jobs(state))) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(count)").font(Theme.font(30, weight: .semibold)).monospacedDigit().tracking(-0.6)
                    .foregroundStyle(count == 0 ? Theme.muted : Theme.foreground)
                HStack(spacing: 6) {
                    StatusGlyph(tone: state.tone, label: state.title).accessibilityHidden(true)
                    Text(state.title).font(Theme.font(13, weight: .medium))
                        .foregroundStyle(count == 0 ? Theme.muted : state.tone.text)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, PaperCardMetrics.inset - PaperCardMetrics.edge).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(state.title), \(count) job\(count == 1 ? "" : "s") today")
        .accessibilityHint("Lists them")
    }

    // MARK: Money

    private static func isToday(_ raw: String?) -> Bool {
        JobFiltering.date(raw).map { Calendar.current.isDateInToday($0) } ?? false
    }

    @ViewBuilder private var moneyToday: some View {
        let issuedToday = invoices.filter { $0.status != "void" && $0.status != "draft" && Self.isToday($0.issuedAt) }
        let invoiced = issuedToday.reduce(into: HomeAmounts()) { $0.add(paperLinesTotal($1.lines) ?? 0, $1.currency) }
        let unpaid = NeedsAttention.unpaid(invoices)
        let owed = unpaid.reduce(into: HomeAmounts()) { $0.add($1.1, $1.0.currency) }
        let sent = estimates.filter { $0.status == "sent" }
        let waiting = sent.reduce(into: HomeAmounts()) {
            $0.add(paperLinesTotal($1.lines) ?? 0, $1.lines.first?.unitPrice.currency ?? "USD")
        }
        // Collected first when the report has it (money in), then what's due: unpaid and waiting.
        let collected = revenue.flatMap { report in report.truncated ? nil : report.months.last }
        PaperSection("Money") {
            VStack(spacing: 0) {
                if !loaded {
                    PaperListRow(title: "Reading invoices and estimates…")
                }
                if let month = collected {
                    // The server reports whole months (UTC); the label names its month, never "today".
                    NavigationLink(value: PaperRoute.revenue) {
                        moneyRow(symbol: "arrow.down.circle", tint: Theme.markForest,
                                 title: "Collected in \(Self.monthName(month.month))",
                                 subtitle: "Month so far · from Reports",
                                 amount: money(month.collected, currency: "USD"))
                    }.buttonStyle(RowPressStyle())
                }
                if loaded && canInvoices {
                    if collected != nil { WellDivider(leading: Self.moneyDivider) }
                    NavigationLink(value: PaperRoute.homeList(.unpaid)) {
                        moneyRow(symbol: "exclamationmark.circle", tint: unpaid.isEmpty ? Theme.markGrey : Theme.markRed,
                                 title: "Unpaid",
                                 subtitle: unpaid.isEmpty ? "Every sent invoice is paid" : "\(unpaid.count) invoice\(unpaid.count == 1 ? "" : "s") with a balance",
                                 amount: owed.isEmpty ? money(0, currency: "USD") : owed.text)
                    }.buttonStyle(RowPressStyle())
                    WellDivider(leading: Self.moneyDivider)
                    NavigationLink(value: PaperRoute.homeList(.invoicedToday)) {
                        moneyRow(symbol: "doc.plaintext", tint: Theme.markTeal,
                                 title: "Invoiced today",
                                 subtitle: issuedToday.isEmpty ? "No invoices sent yet today" : "\(issuedToday.count) invoice\(issuedToday.count == 1 ? "" : "s")",
                                 amount: invoiced.isEmpty ? money(0, currency: "USD") : invoiced.text)
                    }.buttonStyle(RowPressStyle())
                }
                if loaded && canEstimates {
                    if canInvoices || collected != nil { WellDivider(leading: Self.moneyDivider) }
                    NavigationLink(value: PaperRoute.homeList(.estimatesWaiting(staleOnly: false))) {
                        moneyRow(symbol: "doc.text", tint: Theme.markAccent,
                                 title: "Estimates waiting",
                                 subtitle: sent.isEmpty ? "No estimates out with customers" : "\(sent.count) sent, not answered yet",
                                 amount: waiting.isEmpty ? money(0, currency: "USD") : waiting.text)
                    }.buttonStyle(RowPressStyle())
                }
            }
            .padding(.vertical, PaperCardMetrics.edge)
        }
        .accessibilityIdentifier("home-money")
    }

    /// The hairline under a money row starts past its place mark.
    private static let moneyDivider: CGFloat = PaperCardMetrics.inset + 26 + 12

    /// A money figure as a row: the place mark, what it is and how many, the amount in semibold.
    private func moneyRow(symbol: String, tint: Color, title: String, subtitle: String, amount: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            PlaceMark(symbol: symbol, tint: tint)
            PaperListRow(title: title, subtitle: subtitle, subtitleLines: 2) {
                Text(amount).font(Theme.amountFont(17)).foregroundStyle(Theme.foreground)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .environment(\.paperRowInset, 0)
        }
        .padding(.horizontal, PaperCardMetrics.inset)
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

    // MARK: Needs you

    private var savedWork: SavedWorkSnapshot? {
        guard let scope = SavedWorkScope.capture(session: session, api: api, media: media, outbox: outbox) else { return nil }
        return .make(scope: scope, entries: outbox.entries, media: media.items, mediaErrors: media.errors,
                     unverifiedMediaIDs: media.unverifiedIDs, uploadingMediaID: media.uploadingID,
                     commandsSyncing: outbox.syncing, jobs: store.jobs, listingWarning: media.storageWarning)
    }

    @ViewBuilder private var needsYou: some View {
        let unpaid = NeedsAttention.unpaid(invoices)
        let stale = NeedsAttention.waiting(estimates)
        let unscheduled = NeedsAttention.unscheduled(store.jobs)
        let work = savedWork
        let syncProblem = (work?.attentionCount ?? 0) > 0 || (work?.hasListingWarning ?? false)
        let count = (unpaid.isEmpty ? 0 : 1) + (stale.isEmpty ? 0 : 1) + (unscheduled.isEmpty ? 0 : 1) + (syncProblem ? 1 : 0)
        PaperSection("Needs you", count: count == 0 ? nil : count) {
            VStack(spacing: 0) {
                if syncProblem, let work {
                    Button { reviewScope = SavedWorkScope.capture(session: session, api: api, media: media, outbox: outbox) } label: {
                        needRow(title: work.hasListingWarning ? "Saved work needs checking" : "\(work.attentionCount) change\(work.attentionCount == 1 ? "" : "s") did not sync",
                                subtitle: "Saved on this phone, not on the server yet", action: "Review", tint: Theme.warning)
                    }
                    .buttonStyle(RowPressStyle())
                    .accessibilityIdentifier("home-needs-sync")
                }
                if !unpaid.isEmpty {
                    let owed = unpaid.reduce(into: HomeAmounts()) { $0.add($1.1, $1.0.currency) }
                    NavigationLink(value: PaperRoute.homeList(.unpaid)) {
                        needRow(title: "\(unpaid.count) unpaid invoice\(unpaid.count == 1 ? "" : "s")",
                                subtitle: "\(owed.text) owed\(oldest(unpaid.first?.0.issuedAt, verb: "issued"))", action: "Review")
                    }.buttonStyle(RowPressStyle())
                }
                if !stale.isEmpty {
                    NavigationLink(value: PaperRoute.homeList(.estimatesWaiting(staleOnly: true))) {
                        needRow(title: "\(stale.count) estimate\(stale.count == 1 ? "" : "s") waiting on the customer",
                                subtitle: "Sent a week or more ago\(oldest(stale.first?.sentAt, verb: "sent"))", action: "Follow up")
                    }.buttonStyle(RowPressStyle())
                }
                if !unscheduled.isEmpty {
                    NavigationLink(value: PaperRoute.homeList(.unscheduled)) {
                        needRow(title: "\(unscheduled.count) job\(unscheduled.count == 1 ? "" : "s") without a time",
                                subtitle: "Booked, not on the schedule yet", action: session.can("job.assign", feature: "jobs") ? "Schedule" : "Review")
                    }.buttonStyle(RowPressStyle())
                }
                if count == 0 {
                    PaperListRow(title: loaded ? "Nothing needs you right now" : "Checking…",
                                 subtitle: loaded ? "Unpaid invoices, waiting estimates, jobs without a time and failed syncs show up here." : nil,
                                 subtitleLines: 3)
                }
                // The full list, item by item, stays one tap away.
                WellDivider()
                NavigationLink(value: PaperRoute.attention) {
                    PaperListRow(title: "Everything in Needs attention", subtitle: "Each invoice, estimate and job, one by one")
                }.buttonStyle(RowPressStyle())
            }
            .padding(.vertical, PaperCardMetrics.edge)
        }
        .accessibilityIdentifier("home-needs-you")
    }

    /// Something that needs the owner: a red attention glyph (amber for unsynced work on this
    /// phone), what it is and how old, and the next step as a word.
    private func needRow(title: String, subtitle: String, action: String, tint: Color? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            StatusGlyph(tone: tint == nil ? .attention : .inProgress, label: title)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                .accessibilityHidden(true)
            PaperListRow(title: title, subtitle: subtitle, subtitleLines: 2) {
                Text(action).font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                    .fixedSize()
            }
            .environment(\.paperRowInset, 0)
        }
        .padding(.horizontal, PaperCardMetrics.inset)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(action)
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
            PaperSection(title: "Techs", count: people.count) {
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
        .background(Theme.background)
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
        .sheet(item: $scheduling) { QuickScheduleSheet(jobID: $0.id) }
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
                ForEach(rows) { job in
                    ScheduleCompactRow(job: job, customer: store.customerName(job.customerId), street: addresses.street(job),
                                       timeStyle: list == .unscheduled ? .age : .time,
                                       pendingStatus: outbox.pendingStatus(for: job.id),
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

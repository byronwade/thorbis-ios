import SwiftUI

// MARK: - Cream sheet (owner-approved direction, 2026-11-01)
//
// The grammar the sidebar, Today and the job page share (C-Nav, C-Today, C-Job .dc.html): places are
// grouped under plain headings and every place a role can reach is
// listed; a numbers row instead of stat cards; a quiet map strip with a drive pill; labelled rimmed
// buttons 12pt apart; clusters that are space, not a card per field; one ink commit. Light is the
// cream sheet, dark the Linear greys; every colour comes from `Theme`.

/// The headings the sidebar groups places under.
enum PlaceSection: String, CaseIterable, Identifiable {
    case pinned = "Pinned", customized = "Your places", personal = "Personal", work = "Work", customers = "Customers"
    case money = "Money", reports = "Reports", operations = "Operations", other = "Other", phone = "On this phone"
    /// Paper v2 (Navigation 29N/57N/58N): the role's main places, listed with no heading, then the
    /// role's second group (Tools, Manage or Business), then places Paper reaches from inside a hub.
    case primary = "", tools = "Tools", manage = "Manage", business = "Business", more = "More"
    var id: String { rawValue.isEmpty ? "primary" : rawValue }
    /// Whether the section is drawn under a heading of its own.
    var hasHeading: Bool { self != .primary }

    /// The order places take inside their section (C-Nav.dc.html).
    static let canonical: [MenuItem] = [.home, .inbox, .schedule, .jobs, .estimates, .invoices, .team,
                                        .customers, .properties, .money, .billing, .reports, .scorecard,
                                        .priceBook, .attention, .notices, .drafts, .businessSettings,
                                        .timeClock, .receipts, .truckStock, .training, .pipeline, .vendors, .marketing]
}

extension MenuItem {
    func sidebarTitle(_ title: String, localHeading: String) -> String {
        self == .drafts ? "\(title) · \(localHeading)" : title
    }

    /// Where the place is listed in the sidebar.
    var placeSection: PlaceSection {
        switch self {
        case .home, .inbox, .schedule: .personal
        case .jobs, .estimates, .invoices, .team: .work
        case .customers, .properties: .customers
        case .money: .money
        case .reports: .reports
        case .priceBook: .operations
        case .billing, .scorecard, .attention, .notices, .drafts, .businessSettings, .timeClock, .receipts,
             .truckStock, .training, .pipeline, .vendors, .marketing: .other
        }
    }

    /// The sidebar's quiet place hues (C-Nav.dc.html): the day in the accent mixed down, Jobs and the
    /// price book olive, Customers forest, Inbox pumpkin, what needs you and Money burnt; paperwork and
    /// the shop in the marker grey. Outlined at rest, filled when it is the place.
    var sidebarTint: Color {
        switch self {
        case .home, .schedule: Theme.markAccent
        case .jobs, .priceBook: Theme.markOlive
        case .customers, .properties: Theme.markForest
        case .inbox: Theme.markPumpkin
        case .attention, .money: Theme.markBurnt
        case .estimates, .invoices, .billing, .reports, .scorecard, .team, .notices, .drafts, .businessSettings,
             .timeClock, .receipts, .truckStock, .training, .pipeline, .vendors, .marketing: Theme.markGrey
        }
    }
}

/// Every place a person can reach, grouped as the sidebar lists it. Pure, so the owner's rule (every
/// reachable place, each exactly once) is unit-tested per role.
struct DrawerSections: Equatable {
    /// One row of a Paper-ordered section: a place, or a record kept with the company's books.
    enum Entry: Equatable, Identifiable {
        case place(MenuItem), local(LocalWorkspaceSection)
        var id: String {
            switch self {
            case .place(let item): item.rawValue
            case .local(let section): "local-\(section.rawValue)"
            }
        }
    }

    struct Section: Equatable, Identifiable {
        let kind: PlaceSection
        var places: [MenuItem]
        var local: [LocalWorkspaceSection] = []
        /// Paper's row order when places and records interleave; nil lists places, then records.
        var entries: [Entry]? = nil
        var id: String { kind.id }
        var rows: [Entry] { entries ?? (places.map(Entry.place) + local.map(Entry.local)) }
    }

    /// Paper v2's drawer for each role (Navigation 29N, 57N, 58N), in Paper's order. Time clock,
    /// Receipts, Truck stock, Training, Pipeline, Marketing and Vendors and POs keep their records on
    /// this phone until the server has them.
    static func paperLayout(_ role: WorkRole) -> (primary: [Entry], heading: PlaceSection, secondary: [Entry]) {
        switch role {
        case .technician:
            return (primary: [.place(.schedule), .place(.jobs), .place(.customers), .place(.inbox), .place(.timeClock)],
                    heading: PlaceSection.tools,
                    secondary: [.place(.priceBook), .place(.receipts), .place(.truckStock), .local(.equipment), .place(.training)])
        case .office:
            return (primary: [.place(.home), .place(.schedule), .place(.jobs), .place(.money), .place(.customers),
                              .place(.pipeline), .place(.inbox)],
                    heading: PlaceSection.manage,
                    secondary: [.place(.team), .place(.vendors), .place(.properties), .local(.equipment), .local(.agreements),
                                .place(.reports)])
        case .owner:
            return (primary: [.place(.home), .place(.money), .place(.reports), .place(.schedule), .place(.inbox)],
                    heading: PlaceSection.business,
                    secondary: [.place(.customers), .place(.pipeline), .place(.marketing), .local(.agreements), .place(.properties),
                                .local(.equipment), .local(.fleet), .place(.vendors), .place(.businessSettings)])
        }
    }

    var sections: [Section]

    /// The places in the order they are listed, pinned ones first.
    var places: [MenuItem] { sections.flatMap(\.places) }

    /// - Parameters:
    ///   - pins: the layout's pinned places (company or this phone), from Edit menu.
    ///   - explicitPins: true when the person or company chose pins; the role's own defaults never
    ///     count, so a role that never edited its menu sees no Pinned section.
    ///   - hidden: places the person or company turned off in Customize menu (none by default).
    ///   - order: Edit menu's global order; customized menus keep this order across groups.
    ///   - local: records kept on this phone (Fleet, Equipment, Agreements) this role may open.
    ///   - opens: whether this role can open the place.
    ///   - role: Paper v2's per-role order (primary places, then Tools / Manage / Business, then More).
    ///     Nil keeps the older grouping by kind.
    static func make(pins: [MenuItem] = [], explicitPins: Bool = false, roleDefaults: [MenuItem] = [],
                     hidden: Set<MenuItem> = [], order: [MenuItem] = [], local: [LocalWorkspaceSection] = [],
                     role: WorkRole? = nil, opens: (MenuItem) -> Bool) -> DrawerSections {
        func reachable(_ item: MenuItem) -> Bool { opens(item) && !hidden.contains(item) }
        let pinned = explicitPins ? unique(pins.filter { reachable($0) && !roleDefaults.contains($0) }) : []
        var sections: [Section] = []
        if !pinned.isEmpty { sections.append(Section(kind: .pinned, places: pinned)) }
        let available = PlaceSection.canonical.filter { reachable($0) && !pinned.contains($0) }
        if order.isEmpty, let role {
            let layout = paperLayout(role)
            func keep(_ entries: [Entry]) -> [Entry] {
                entries.filter { entry -> Bool in
                    switch entry {
                    case .place(let item): return available.contains(item)
                    case .local(let section): return local.contains(section)
                    }
                }
            }
            func split(_ kind: PlaceSection, _ entries: [Entry]) -> Section? {
                let rows = keep(entries)
                guard !rows.isEmpty else { return nil }
                let places = rows.compactMap { entry -> MenuItem? in
                    if case .place(let item) = entry { return item }
                    return nil
                }
                let records = rows.compactMap { entry -> LocalWorkspaceSection? in
                    if case .local(let section) = entry { return section }
                    return nil
                }
                return Section(kind: kind, places: places, local: records, entries: rows)
            }
            if let primary = split(.primary, layout.primary) { sections.append(primary) }
            if let second = split(layout.heading, layout.secondary) { sections.append(second) }
            let listed = Set(sections.flatMap(\.places))
            let rest = available.filter { !listed.contains($0) }
            if !rest.isEmpty { sections.append(Section(kind: .more, places: rest)) }
            let placedLocal = Set(sections.flatMap(\.local))
            let restLocal = local.filter { !placedLocal.contains($0) }
            if !restLocal.isEmpty { sections.append(Section(kind: .phone, places: [], local: restLocal)) }
            return DrawerSections(sections: sections)
        }
        if !order.isEmpty {
            let items = unique(order.filter(available.contains) + available)
            if !items.isEmpty { sections.append(Section(kind: .customized, places: items)) }
        } else {
            for kind in [PlaceSection.personal, .work, .customers, .money, .reports, .operations, .other] {
                let items = available.filter { $0.placeSection == kind }
                if !items.isEmpty { sections.append(Section(kind: kind, places: items)) }
            }
        }
        if !local.isEmpty { sections.append(Section(kind: .phone, places: [], local: local)) }
        return DrawerSections(sections: sections)
    }

    private static func unique(_ items: [MenuItem]) -> [MenuItem] {
        items.reduce(into: [MenuItem]()) { if !$0.contains($1) { $0.append($1) } }
    }
}

/// Projects reachable native destinations into the web's personal tier and workspaces.
/// The caller supplies only authorized, non-hidden items; unsupported web routes are absent.
struct WebSidebarProjection {
    struct Group: Identifiable {
        let section: PlaceSection
        let items: [MenuItem]
        let expanded: Bool
        var id: String { section.rawValue }
    }
    let personal: [MenuItem]
    let groups: [Group]

    static func make(places: [MenuItem], current: MenuItem?) -> Self {
        let available = Set(places)
        let canonical = PlaceSection.canonical.filter(available.contains)
        let personal = canonical.filter { $0.placeSection == .personal }
        let groups = [PlaceSection.work, .customers, .money, .reports, .operations, .other].compactMap { section -> Group? in
            let items = canonical.filter { $0.placeSection == section }
            guard !items.isEmpty else { return nil }
            return Group(section: section, items: items, expanded: items.count > 1 && current.map(items.contains) == true)
        }
        return Self(personal: personal, groups: groups)
    }
}

/// What a place row says at its trailing edge: a count in tabular figures, or the accent dot.
struct PlaceCount: Equatable {
    var text: String?
    /// Set in the accent (unread Inbox).
    var accent = false
    /// What VoiceOver reads as the row's value.
    var spoken: String
    /// Paper v2: how the count is drawn — a plain number, a warning ("2 overdue"), a good word
    /// ("2h 14m" on the clock) or the brand badge (unread messages).
    enum Tone: Equatable { case plain, warning, success, badge }
    var tone: Tone = .plain

    static func number(_ value: Int, spoken: String) -> PlaceCount? {
        value > 0 ? PlaceCount(text: "\(value)", spoken: spoken) : nil
    }
    /// Unread messages: Paper's filled brand badge with the number.
    static func badge(_ value: Int, spoken: String) -> PlaceCount? {
        value > 0 ? PlaceCount(text: "\(value)", accent: true, spoken: spoken, tone: .badge) : nil
    }
    static let unread = PlaceCount(text: nil, accent: true, spoken: "Unread")
}

/// The trailing count of a place row (Paper v2 drawer).
struct PlaceCountLabel: View {
    let count: PlaceCount

    var body: some View {
        if let text = count.text {
            switch count.tone {
            case .badge:
                Text(text).font(Theme.font(12, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 6).frame(minWidth: 20, minHeight: 20)
                    .background(Theme.brand, in: Capsule())
                    .fixedSize()
            case .warning:
                Text(text).font(Theme.font(14, weight: .semibold)).foregroundStyle(Theme.warning).lineLimit(1).fixedSize()
            case .success:
                Text(text).font(Theme.font(14, weight: .semibold)).foregroundStyle(Theme.success).lineLimit(1).fixedSize()
            case .plain:
                Text(text).font(Theme.monoFont(14)).foregroundStyle(count.accent ? Theme.brandText : Theme.subtleForeground)
                    .lineLimit(1).fixedSize()
            }
        } else if count.accent {
            DrawerDot()
        }
    }
}

/// The day's numbers, shared by Today's numbers row and the sidebar's "N left" so they always agree.
enum TodayNumbers {
    /// Today's visits for `assignee` (nil: everyone's), finished ones included, canceled ones not.
    static func visits(_ jobs: [Job], assignee: String?, now: Date = .now, calendar: Calendar = .current) -> [Job] {
        jobs.filter { job in
            job.status != "canceled" && (assignee == nil || job.assignedToUserId == assignee) &&
                (JobFiltering.date(job.scheduledFor).map { calendar.isDate($0, inSameDayAs: now) } ?? false)
        }
    }

    /// Stops not finished yet.
    static func left(_ visits: [Job], status: (Job) -> String = { $0.status }) -> Int {
        visits.filter { status($0) != "completed" }.count
    }

    /// Booked stops whose time has passed (the list's "Late" word, counted).
    static func late(_ visits: [Job], now: Date = .now, status: (Job) -> String = { $0.status }) -> Int {
        visits.filter { job in
            ["scheduled", "dispatched"].contains(status(job)) && (JobFiltering.date(job.scheduledFor).map { $0 < now } ?? false)
        }.count
    }

    /// Jobs still open (not finished or canceled), for the Jobs row.
    static func open(_ jobs: [Job]) -> Int {
        jobs.filter { !["completed", "canceled"].contains($0.status) }.count
    }
}

/// What issued invoices still have owing, in cents. Nil when any amount can't be read safely (a
/// foreign currency, an overflow, a negative line), so nothing shows rather than a wrong sum.
enum InvoiceBalance {
    static func due(_ invoices: [InvoiceRecord], currency: String = "USD") -> Int? {
        let issued = invoices.filter { $0.status == "issued" && $0.currency == currency }
        var total = 0
        for invoice in issued {
            var invoiceTotal = 0
            for line in invoice.lines {
                guard line.quantity >= 0, line.unitPrice.amount >= 0, line.unitPrice.currency == invoice.currency else { return nil }
                let (lineTotal, lineOverflow) = line.quantity.multipliedReportingOverflow(by: line.unitPrice.amount)
                let (next, sumOverflow) = invoiceTotal.addingReportingOverflow(lineTotal)
                guard !lineOverflow, !sumOverflow else { return nil }
                invoiceTotal = next
            }
            let (owing, owingOverflow) = invoiceTotal.subtractingReportingOverflow(invoice.amountPaid)
            guard !owingOverflow, owing >= 0 else { return nil }
            let (next, overflow) = total.addingReportingOverflow(owing)
            guard !overflow else { return nil }
            total = next
        }
        return total
    }
}

/// What is owed on the workspace's issued invoices, read once per session for people who may see
/// invoices: Today's "to collect" (today's stops) and the sidebar's Money. Empty until read, and
/// cleared when the person or workspace changes, so it never shows another workspace's money.
@MainActor
final class DayMoney: ObservableObject {
    static let shared = DayMoney()
    @Published private(set) var dueByJob: [String: Int] = [:]
    @Published private(set) var totalDue: Int?
    private var identity = ""

    func load(api: APIClient, organizationID: String?, identity: String) async {
        if identity != self.identity { self.identity = identity; dueByJob = [:]; totalDue = nil }
        guard let organizationID, let invoices = try? await api.fieldInvoices(), identity == self.identity else { return }
        let mine = invoices.filter { $0.organizationId == organizationID }
        let byJob = Dictionary(grouping: mine.filter { $0.jobId != nil }) { $0.jobId ?? "" }
        dueByJob = byJob.compactMapValues { InvoiceBalance.due($0) }.filter { $0.value > 0 }
        totalDue = InvoiceBalance.due(mine)
    }

    /// Owed on these jobs' invoices; nil until the invoices have been read.
    func toCollect(_ jobs: [Job]) -> Int? {
        guard totalDue != nil else { return nil }
        return jobs.reduce(0) { $0 + (dueByJob[$1.id] ?? 0) }
    }

    /// Reads once per identity; `load` reads again (a pull to refresh).
    func loadIfNeeded(api: APIClient, organizationID: String?, identity: String) async {
        guard identity != self.identity || totalDue == nil else { return }
        await load(api: api, organizationID: organizationID, identity: identity)
    }

    func reset() { identity = ""; dueByJob = [:]; totalDue = nil }
}

/// Whole dollars for a count beside a place ("$1,240"); two decimals stay on records.
func compactMoney(_ cents: Int, currency: String = "USD") -> String {
    (Double(cents) / 100).formatted(.currency(code: currency).precision(.fractionLength(0)))
}

// MARK: - The sidebar's list (phone drawer and iPad column)

@MainActor private enum SidebarPreferenceStore {
    static let work: UserDefaults = {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if PaperPreview.enabled, let index = args.firstIndex(of: "--paper-preview-menu-suite"),
           args.indices.contains(index + 1), let uuid = UUID(uuidString: args[index + 1]) {
            return UserDefaults(suiteName: "thorbis.preview.menu.\(uuid.uuidString)") ?? .standard
        }
        #endif
        return .standard
    }()
}

/// The grouped places: a 12 Medium heading per section, then rows. A row is the place's mark in its
/// quiet hue (filled when it is the place), the word in body (lifted to ink when here) and a count in
/// tabular figures at the trailing edge. The place showing sits on the selected fill.
struct PlacesList: View {
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var api: APIClient
    @ObservedObject private var recordFavorites = ScopedRecordFavorites.shared
    @AppStorage("thorbis.sidebar.favoritesCollapsed") private var favoritesCollapsed = false
    @AppStorage("thorbis.sidebar.customCollapsed") private var customCollapsed = false
    @AppStorage("thorbis.sidebar.workCollapsed", store: SidebarPreferenceStore.work) private var workCollapsed = false
    @State private var workspaceExpansion: [PlaceSection: Bool] = [:]
    let sections: DrawerSections
    let title: (MenuItem) -> String
    let isCurrent: (MenuItem) -> Bool
    let isCurrentLocal: (LocalWorkspaceSection) -> Bool
    let count: (MenuItem) -> PlaceCount?
    /// "drawer" or "sidebar": rows are `<prefix>-<place>` (`drawer-jobs`, `sidebar-local-fleet`).
    let idPrefix: String
    var phoneHeading = PlaceSection.phone.rawValue
    /// Paper's office and owner menus (57N / 58N) draw 40pt rows under a 34pt heading; the
    /// technician's (29N) draws 46 under 38. The iPad sidebar keeps the taller rows.
    var compactRows = false
    var savedWork: AppBottomBar.Sync? = nil
    var savedWorkTitle = "Saved on this phone"
    let openPlace: (MenuItem) -> Void
    let openLocal: (LocalWorkspaceSection) -> Void
    var openSavedWork: () -> Void = {}
    var openFavorite: (ScopedRecordFavorites.Visible) -> Void = { _ in }

    private struct FavoritesReload: Equatable {
        let scope: ScopedRecordFavorites.Scope?
        let entries: [ScopedRecordFavorites.Entry]
    }
    private var favoriteScope: ScopedRecordFavorites.Scope? { ScopedRecordFavorites.currentScope(session: session, api: api) }
    private func canOpenFavorite(_ kind: ScopedRecordFavorites.Kind) -> Bool {
        switch kind {
        case .job: session.can("job.view", feature: "jobs")
        case .customer: session.can("customer.view", feature: "core_crm")
        }
    }
    private var safeFavorites: [ScopedRecordFavorites.Visible] {
        guard recordFavorites.isBound(to: favoriteScope) else { return [] }
        return recordFavorites.visible.filter { canOpenFavorite($0.entry.kind) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Paper v2: the role's places as flat rows; a heading only above the second group.
            let listed = sections.sections.filter { ![.pinned, .customized, .phone].contains($0.kind) }
            ForEach(Array(listed.enumerated()), id: \.element.id) { index, section in
                if section.kind.hasHeading { heading(section.kind.rawValue) }
                ForEach(section.rows) { entry in
                    switch entry {
                    case .place(let item): place(item)
                    case .local(let local): localRows([local])
                    }
                }
                if index == 0 { favorites }
            }
            if listed.isEmpty { favorites }
            if let custom = sections.sections.first(where: { $0.kind == .customized }), !custom.places.isEmpty {
                disclosureHeading("Your places", collapsed: $customCollapsed, id: "custom")
                if !customCollapsed {
                    ForEach(custom.places) { item in place(item, prefix: "\(idPrefix)-custom") }
                }
            }
            if let phone = sections.sections.first(where: { $0.kind == .phone }) {
                // Equipment and Agreements read the company's shared books; only the rest is the phone's.
                let shared = phone.local.filter { $0 == .equipment || $0 == .agreements }
                let phoneOnly = phone.local.filter { $0 != .equipment && $0 != .agreements }
                if !shared.isEmpty {
                    heading("Records")
                    localRows(shared)
                }
                if !phoneOnly.isEmpty || savedWork != nil {
                    heading(phoneHeading)
                    localRows(phoneOnly)
                    if let savedWork { savedWorkRow(savedWork) }
                }
            }
            // Saved work with no local places still gets its heading.
            if let savedWork, !sections.sections.contains(where: { $0.kind == .phone }) {
                heading(phoneHeading)
                savedWorkRow(savedWork)
            }
        }
        .onChange(of: sections.places.first(where: isCurrent)) { _, place in
            if let place, place.placeSection != .work { workspaceExpansion[place.placeSection] = true }
        }
        .onChange(of: favoriteScope, initial: true) { recordFavorites.bind(favoriteScope) }
        .task(id: FavoritesReload(scope: favoriteScope, entries: recordFavorites.entries)) {
            let expected = favoriteScope
            recordFavorites.bind(expected)
            guard expected != nil else { return }
            await recordFavorites.refresh(api: api, canOpen: canOpenFavorite, isCurrent: { favoriteScope == expected })
        }
    }

    /// Pinned places and favorite records, under the role's main places.
    @ViewBuilder private var favorites: some View {
        VStack(alignment: .leading, spacing: 0) {
            let pins = sections.sections.first(where: { $0.kind == .pinned })?.places ?? []
            let hasSavedRecords = recordFavorites.isBound(to: favoriteScope) && !recordFavorites.entries.isEmpty
            if !pins.isEmpty || hasSavedRecords {
                disclosureHeading("Favorites", collapsed: $favoritesCollapsed, id: "favorites", forceExpanded: pins.contains(where: isCurrent))
                if !favoritesCollapsed || pins.contains(where: isCurrent) {
                    ForEach(pins) { item in place(item, prefix: "\(idPrefix)-favorite") }
                    ForEach(safeFavorites) { item in
                        Button {
                            guard recordFavorites.isBound(to: favoriteScope), canOpenFavorite(item.entry.kind),
                                  recordFavorites.visible.contains(item) else { return }
                            openFavorite(item)
                        } label: {
                            Label(item.title, systemImage: "star.fill")
                                .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.subtle)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .padding(.horizontal, 12).contentShape(Rectangle())
                        }
                        .buttonStyle(RowPressStyle())
                        .contextMenu {
                            Button("Remove from favorites", role: .destructive) {
                                guard recordFavorites.isBound(to: favoriteScope) else { return }
                                recordFavorites.toggle(item.entry.kind, id: item.entry.id)
                            }
                        }
                        .accessibilityIdentifier("\(idPrefix)-favorite-record-\(item.entry.id)")
                    }
                    if hasSavedRecords && safeFavorites.isEmpty {
                        Text("Favorites appear after access is checked.")
                            .font(Theme.font(13)).foregroundStyle(Theme.muted)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                    }
                }
            }
        }
    }

    private func toggleWorkspace(_ section: PlaceSection, expanded: Bool) {
        if section == .work { workCollapsed = expanded }
        else { workspaceExpansion[section] = !expanded }
    }

    private func place(_ item: MenuItem, prefix: String? = nil) -> some View {
        PlaceRow(title: item.sidebarTitle(title(item), localHeading: phoneHeading), symbol: item.symbol, tint: item.sidebarTint,
                 here: isCurrent(item), count: count(item), id: "\(prefix ?? idPrefix)-\(item.rawValue)",
                 height: compactRows ? 40 : 46) { openPlace(item) }
    }

    private func disclosureHeading(_ text: String, collapsed: Binding<Bool>, id: String, forceExpanded: Bool = false) -> some View {
        Button { collapsed.wrappedValue.toggle() } label: {
            HStack { Text(text); Spacer(); Image(systemName: collapsed.wrappedValue && !forceExpanded ? "chevron.right" : "chevron.down") }
                .font(Theme.font(12, weight: .medium)).foregroundStyle(Theme.muted)
                .padding(.horizontal, 12).frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityValue(collapsed.wrappedValue && !forceExpanded ? "Collapsed" : "Expanded")
        .accessibilityIdentifier("\(idPrefix)-\(id)-disclosure")
    }

    /// Paper 29N: 13/18 Medium in `subtle-foreground`, 14 above and 6 below (57N / 58N: 12 and 4).
    private func heading(_ text: String) -> some View {
        Text(text)
            .font(Theme.font(13, weight: .medium))
            .foregroundStyle(Theme.subtleForeground)
            .padding(.horizontal, 12)
            .padding(.top, compactRows ? 12 : 14).padding(.bottom, compactRows ? 4 : 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private func localRows(_ local: [LocalWorkspaceSection]) -> some View {
        ForEach(local, id: \.self) { section in
            PlaceRow(title: section.title, symbol: section.moreSymbol, tint: Theme.markGrey, here: isCurrentLocal(section),
                     count: nil, id: "\(idPrefix)-local-\(section.rawValue)",
                     height: compactRows ? 40 : 46) { openLocal(section) }
        }
    }

    private func savedWorkRow(_ sync: AppBottomBar.Sync) -> some View {
        Button(action: openSavedWork) {
            HStack(alignment: .center, spacing: 12) {
                PlaceRowIcon(symbol: sync.needsPerson ? "exclamationmark.triangle" : "arrow.triangle.2.circlepath",
                             tint: sync.needsPerson ? Theme.warning : Theme.markGrey, filled: false)
                VStack(alignment: .leading, spacing: 1) {
                    Text(savedWorkTitle).font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.subtle)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(sync.words).font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if sync.needsPerson { DrawerDot() }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(savedWorkTitle)
        .accessibilityValue(sync.words)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Review what is waiting to sync")
        .accessibilityIdentifier("\(idPrefix)-saved-work")
    }
}

/// A place's mark in a row (Paper v2): an 18pt line icon, never filled.
struct PlaceRowIcon: View {
    let symbol: String
    let tint: Color
    let filled: Bool
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 18

    var body: some View {
        // Paper's own drawer glyph where it draws one (29N / 57N / 58N); the symbol otherwise.
        if let glyph = PaperGlyph.place(symbol: symbol) {
            PaperIcon(glyph, size: 18, color: tint, scales: true)
        } else {
            Image(systemName: symbol)
                .font(.system(size: size - 1, weight: .regular))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}

/// One place (Paper v2 drawer row): an 18pt line icon in the secondary grey, the word at 16 Medium
/// and the count at the trailing edge, 14 apart, 40 tall. The place showing sits on the sidebar
/// accent (radius 12) with its icon in brand text and its word in 16 Semibold.
/// `tint` is kept so call sites compile; Paper draws every icon in the same grey.
struct PlaceRow: View {
    let title: String
    let symbol: String
    let tint: Color
    let here: Bool
    let count: PlaceCount?
    let id: String
    /// Paper 29N (technician) draws 46; 57N / 58N (office, owner) draw 40.
    var height: CGFloat = 46
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 14) {
                PlaceRowIcon(symbol: symbol, tint: here ? Theme.brandText : Theme.subtle, filled: false)
                Text(title)
                    .font(Theme.font(16, weight: here ? .semibold : .medium))
                    .foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let count { PlaceCountLabel(count: count) }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
            .background {
                if here { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.sidebarAccent) }
            }
            // A 40pt row still takes a 44pt touch: the target reaches 2pt past the row each way.
            .contentShape(Rectangle().inset(by: min(0, (height - 44) / 2)))
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(count?.spoken ?? "")
        .accessibilityAddTraits(here ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(id)
    }
}

// MARK: - Controls

/// A round control on the canvas (Paper v2 header circles): 44pt on the card, no rim. `ink` is the
/// create circle: brand blue with a white glyph.
struct CreamCircleLabel: View {
    let symbol: String
    var size: CGFloat = 44
    var ink = false
    /// Paper's own glyph for this circle (the two-line menu, the +); wins over `symbol`.
    var glyph: PaperGlyph? = nil
    var glyphSize: CGFloat = 20

    var body: some View {
        Group {
            // Paper's own mark wherever it draws one (share, search, back, "…", call, message), so
            // this circle and `PaperCircleLabel` never draw the same button two ways.
            if let glyph = glyph ?? PaperGlyph.chrome(symbol: symbol) {
                PaperIcon(glyph, size: size >= 44 ? glyphSize : min(glyphSize, size >= 40 ? 18 : 16),
                          color: ink ? .white : Theme.foreground)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: ink ? .semibold : .medium))
                    .foregroundStyle(ink ? Color.white : Theme.foreground)
            }
        }
            .frame(width: size, height: size)
            .background(ink ? Theme.brand : Theme.card, in: Circle())
            .frame(width: max(44, size), height: max(44, size))
            .contentShape(Circle())
    }
}

/// Call, Text, Directions: a labelled rimmed button (radius 10, 44 tall) that lifts a step off the
/// sheet, 12pt from its neighbour. Disabled fades it and keeps the word.
struct RimmedButtonLabel: View {
    let title: String
    let symbol: String
    var enabled = true
    /// Paper's field stop card (F1) draws these pills 52 tall with a 17 Semibold word.
    var height: CGFloat = 50
    var size: CGFloat = 16
    @Environment(\.thorbisPressed) private var pressed
    /// The glyph grows with the word beside it.
    @ScaledMetric(relativeTo: .subheadline) private var glyph: CGFloat = 15

    /// Paper v2: a pill on the field fill, the glyph and a 16 Semibold word, 50 tall.
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: glyph, weight: .medium)).accessibilityHidden(true)
            Text(title).font(Theme.font(size, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(Theme.foreground.opacity(enabled ? 1 : 0.4))
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: height)
        .background(Theme.fill.opacity(pressed ? 0.7 : 1), in: Capsule())
        .contentShape(Capsule())
    }
}

/// The place header's mark: the place's symbol on a tinted tile (radius 10).
struct PlaceMarkTile: View {
    let symbol: String
    var tint: Color = Theme.markAccent
    @ScaledMetric(relativeTo: .title) private var size: CGFloat = 34

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .regular))
            .foregroundStyle(Theme.onInk)
            .frame(width: size, height: size)
            .background(tint, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A row of numbers on the canvas, no cards (C-Today: "4 stops left · $1,240 to collect · 1 running
/// late"). The number in tabular figures, its word under it. Stacks at accessibility sizes.
struct NumbersRow: View {
    struct Item: Identifiable {
        let value: String
        let label: String
        var tint: Color = Theme.foreground
        var spoken: String
        var id: String { label }
    }
    let items: [Item]
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                                                  : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
        layout {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.value).font(Theme.monoFont(22, weight: .medium)).tracking(-0.3)
                        .foregroundStyle(item.tint)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(item.label).font(Theme.font(12, weight: .medium)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: typeSize.isAccessibilitySize ? nil : .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(item.spoken)
            }
        }
    }
}

/// The quiet map strip: a drawn street grid (no tiles, no network) with the stop's pin, and a drive
/// pill ("18 min · 6.2 mi") when the drive time is known. A reserved aspect so cards never jump.
struct MapStrip: View {
    var pill: String? = nil
    var aspect: CGFloat = 366 / 112
    var pillAtBottom = false
    var hasPlace = true

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            var major = Path()
            major.move(to: CGPoint(x: 0, y: h * 0.27)); major.addLine(to: CGPoint(x: w, y: h * 0.27))
            major.move(to: CGPoint(x: 0, y: h * 0.75)); major.addLine(to: CGPoint(x: w, y: h * 0.75))
            major.move(to: CGPoint(x: w * 0.16, y: 0)); major.addLine(to: CGPoint(x: w * 0.16, y: h))
            major.move(to: CGPoint(x: w * 0.49, y: 0)); major.addLine(to: CGPoint(x: w * 0.6, y: h))
            major.move(to: CGPoint(x: w * 0.82, y: 0)); major.addLine(to: CGPoint(x: w * 0.82, y: h))
            context.stroke(major, with: .color(Theme.card), lineWidth: 7)
            var minor = Path()
            minor.move(to: CGPoint(x: 0, y: h * 0.52)); minor.addLine(to: CGPoint(x: w * 0.33, y: h * 0.52))
            minor.move(to: CGPoint(x: w * 0.66, y: h * 0.11)); minor.addLine(to: CGPoint(x: w, y: h * 0.11))
            minor.move(to: CGPoint(x: w * 0.33, y: 0)); minor.addLine(to: CGPoint(x: w * 0.33, y: h))
            context.stroke(minor, with: .color(Theme.border), lineWidth: 3)
            guard hasPlace else { return }
            let pin = CGPoint(x: w * 0.57, y: h * 0.27)
            let ring = Path(ellipseIn: CGRect(x: pin.x - 9, y: pin.y - 9, width: 18, height: 18))
            context.fill(ring, with: .color(Theme.brand))
            // The ring is the sheet the strip sits on, so in dark it stays a grey, not a white halo.
            context.stroke(ring, with: .color(Theme.card), lineWidth: 3)
        }
        .background(Theme.fill)
        .aspectRatio(aspect, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .overlay(alignment: pillAtBottom ? .bottomLeading : .topLeading) {
            if let pill {
                Text(pill)
                    .font(Theme.monoFont(12, weight: .medium))
                    .foregroundStyle(Theme.foreground)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Theme.card, in: Capsule())
                    .shadow(color: .black.opacity(0.08), radius: 1, x: 0, y: 1)
                    .padding(10)
            }
        }
        .accessibilityHidden(true)
    }

    /// "18 min · 6.2 mi", or the minutes alone when the distance isn't known.
    static func drive(minutes: Int?, miles: Double?) -> String? {
        guard let minutes else { return nil }
        guard let miles else { return "\(minutes) min drive" }
        return "\(minutes) min · \(miles.formatted(.number.precision(.fractionLength(1)))) mi"
    }
}

/// A cluster row (C-Job "At this address", "Money"): the key in the marker grey, the value on the
/// trailing edge; values in tabular figures where they are numbers. Space, not a card.
struct ClusterRow: View {
    let key: String
    let value: String
    var mono = false
    var strong = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                                                  : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        layout {
            Text(key).font(Theme.font(14, weight: strong ? .medium : .regular))
                .foregroundStyle(strong ? Theme.foreground : Theme.muted)
            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
            Text(value)
                .font(mono ? Theme.monoFont(15, weight: strong ? .medium : .regular) : Theme.font(14, weight: strong ? .medium : .regular))
                .foregroundStyle(Theme.foreground)
                .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A cluster's heading: 16 Medium, generous space above (C-Job `.h`).
struct ClusterHeading: View {
    let title: String
    var body: some View {
        Text(title).font(Theme.font(16, weight: .medium))
            .foregroundStyle(Theme.foreground)
            .padding(.top, 8).padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Search from a place

/// Opens Search over the place showing (set by the phone shell; nil elsewhere).
struct PaperSearchAction: @unchecked Sendable {
    let run: () -> Void
}

private struct PaperSearchKey: EnvironmentKey { static let defaultValue: PaperSearchAction? = nil }
extension EnvironmentValues {
    var paperSearch: PaperSearchAction? {
        get { self[PaperSearchKey.self] }
        set { self[PaperSearchKey.self] = newValue }
    }
}

// MARK: - A place's header

/// A place root's header (C-Today.dc.html): the menu circle on the left of the top bar, Search and
/// the ink + on its right; then the place's mark on a tinted tile, its title and a muted line, with
/// the place's own circles (view, layout) at the trailing edge. The title scrolls with the content.
struct CreamPlaceHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    let symbol: String
    var tint: Color = Theme.markAccent
    var titleIdentifier: String? = nil
    var showsCreate = true
    @ViewBuilder var trailing: Trailing
    @Environment(\.paperCreate) private var create
    @Environment(\.paperDrawer) private var drawer
    @Environment(\.paperSearch) private var search
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 4) {
                if let drawer { DrawerMenuCircle(control: drawer) }
                Spacer(minLength: 0)
                if let search {
                    Button(action: search.run) { CreamCircleLabel(symbol: "magnifyingglass") }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel("Search")
                        .accessibilityIdentifier("header-search")
                }
                if showsCreate, let create {
                    Button(action: create.run) { CreamCircleLabel(symbol: "plus", ink: true) }
                        .buttonStyle(PressStyle())
                        .contextMenu {
                            ForEach(create.choices) { choice in
                                Button(action: choice.run) { Label(choice.title, systemImage: choice.symbol) }
                            }
                        }
                        .accessibilityLabel(create.label)
                        .accessibilityIdentifier("header-create")
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            let row = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                                                   : AnyLayout(HStackLayout(alignment: .center, spacing: 10))
            row {
                HStack(alignment: .center, spacing: 10) {
                    PlaceMarkTile(symbol: symbol, tint: tint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(Theme.font(28, weight: .medium)).tracking(-0.5)
                            .foregroundStyle(Theme.foreground)
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .accessibilityAddTraits(.isHeader)
                            .modifier(OptionalIdentifier(identifier: titleIdentifier))
                        DotLine(subtitle)
                            .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    }
                }
                // The title column takes every point the circles leave (a Spacer would split the
                // room with it, and the subtitle would wrap with half the row empty).
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 4) { trailing }.fixedSize()
            }
            .padding(.leading, Theme.gutter).padding(.trailing, 14)
            .padding(.top, 14)
        }
    }
}

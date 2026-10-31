import SwiftUI

/// Everything an owner can place in the tab bar or the More menu. Search and More stay fixed so
/// nothing can be lost: whatever is not in the tab bar is in More (or under Hidden in Customize).
enum MenuItem: String, CaseIterable, Codable, Identifiable {
    case home, schedule, jobs, customers, attention, inbox, estimates, invoices, billing, priceBook, money, reports, team, notices, drafts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .schedule: "Schedule"
        case .jobs: "Jobs"
        case .customers: "Customers"
        case .attention: "Needs attention"
        case .inbox: "Inbox"
        case .estimates: "Estimates"
        case .invoices: "Invoices"
        case .billing: "Billing schedules"
        case .priceBook: "Price book"
        case .money: "Money"
        case .reports: "Reports"
        case .team: "Team & permissions"
        case .notices: "Notification rules"
        case .drafts: "Message drafts"
        }
    }

    /// The tab bar has little room; long names get a short label there.
    var tabTitle: String {
        switch self {
        // The bar says what the place is for: the day's work (redesign 2026-10-31).
        case .schedule: "Today"
        case .billing: "Billing"
        case .attention: "Attention"
        case .team: "Team"
        case .notices: "Rules"
        case .drafts: "Drafts"
        default: title
        }
    }

    /// Places whose root hides the navigation bar and leads with `PaperHeader`, which carries the
    /// drawer's menu circle. The others (a visible bar: Inbox, Estimates, Reports, …) carry it in the bar.
    var drawerCircleInHeader: Bool { [.home, .schedule, .jobs, .customers, .priceBook].contains(self) }

    // The drawer's words for a place are `DrawerPlaces.title(_:role:)` (Today for technicians).

    var symbol: String {
        switch self {
        case .home: "house"
        case .schedule: "calendar"
        case .jobs: "briefcase"
        case .customers: "person.2"
        case .attention: "exclamationmark.circle"
        case .inbox: "tray"
        case .estimates: "doc.text"
        case .invoices: "doc.plaintext"
        case .billing: "list.bullet.rectangle"
        case .priceBook: "book.closed"
        case .money: "chart.bar"
        case .reports: "chart.xyaxis.line"
        case .team: "person.2.badge.gearshape"
        case .notices: "bell.badge"
        case .drafts: "bubble.left"
        }
    }

    /// The place mark's hue (v2, design.thorbis.com "A soft olive Jobs mark. The word stays cream"):
    /// olive, forest, pumpkin, burnt and the accent mixed down; quiet colour on chrome, not candy.
    var tint: Color {
        switch self {
        case .jobs: Theme.markOlive
        case .home, .schedule: Theme.markAccent
        case .inbox: Theme.markPumpkin
        case .customers: Theme.markForest
        case .attention: Theme.markRed
        case .estimates: Theme.markPumpkin
        case .invoices, .billing, .money: Theme.markForest
        case .priceBook: Theme.markBurnt
        case .reports: Theme.markOlive
        case .team, .notices, .drafts: Theme.markGrey
        }
    }

    var subtitle: String? {
        switch self {
        case .home: "Today at a glance, money and what needs you"
        case .attention: "Unpaid invoices, waiting estimates, jobs without a time"
        case .inbox: "Booked, changed and assigned jobs"
        case .billing: "Progress billing, deposits, retainage"
        case .money: "Revenue, overdue and reports"
        case .reports: "Estimate conversion and schedule"
        case .notices: "Who hears about booked and changed jobs"
        case .drafts: "Saved here, not sent"
        default: nil
        }
    }

    enum Group: String, CaseIterable { case work = "Work", business = "Business", phone = "On this phone" }

    var group: Group {
        switch self {
        case .team, .notices: .business
        case .drafts: .phone
        default: .work
        }
    }

    /// Where the item opens when it is not a tab of its own.
    var route: PaperRoute? {
        switch self {
        case .schedule, .jobs, .customers: nil
        case .home: .home
        case .attention: .attention
        case .inbox: .inbox
        case .estimates: .estimates
        case .invoices: .invoices
        case .billing: .billing
        case .priceBook: .priceBook
        case .money: .revenue
        case .reports: .reports
        case .team: .team
        case .notices: .notices
        case .drafts: .drafts
        }
    }

    /// The id the company layout API uses (Thorbis-TanStack organization/mobile-layout).
    var serverID: String { self == .money ? "revenue" : rawValue }
    /// Tabs the company layout can carry; other items can still be tabs on a single phone.
    static let companyTabs: Set<MenuItem> = [.schedule, .jobs, .customers, .money, .inbox]

    init?(serverTab id: String) { self.init(rawValue: id == "revenue" ? "money" : id) }

    /// Whether the place is listed in the menu, the iPad sidebar and Customize menu. Notification
    /// rules live in Settings; Reports sits inside Money for anyone who can open Money, so a role
    /// without Money still finds Reports on its own. Neither changes what a role can open.
    @MainActor func listed(_ session: SessionController) -> Bool {
        Self.listed(self, permitted: { $0.permitted(session) })
    }

    static func listed(_ item: MenuItem, permitted: (MenuItem) -> Bool) -> Bool {
        switch item {
        case .notices: false
        case .reports: permitted(.reports) && !permitted(.money)
        default: permitted(item)
        }
    }

    @MainActor func permitted(_ session: SessionController) -> Bool {
        switch self {
        case .schedule, .jobs: session.can("job.view", feature: "jobs")
        // The owner's day at a glance; other roles keep their menus exactly as they were.
        case .home: session.can("job.view", feature: "jobs") && WorkRole(session) == .owner
        case .customers: session.can("customer.view", feature: "core_crm")
        case .attention: session.can("invoice.view", feature: "invoicing") || session.can("estimate.view", feature: "estimates")
        case .inbox: session.can("job.view", feature: "job_booking_notices")
        case .estimates: session.can("estimate.view", feature: "estimates")
        case .invoices: session.can("invoice.view", feature: "invoicing")
        case .billing: session.can("invoice.view", feature: "progress_billing")
        case .priceBook: session.can("pricebook.view", feature: "price_book")
        case .money: session.can("invoice.view", feature: "invoicing") && session.can("invoice.view", feature: "payments")
        case .reports: session.can("estimate.view", feature: "estimates") || session.can("job.view", feature: "jobs")
        case .team: session.can("organization.members.manage") || session.can("organization.permissions.manage")
        case .notices: session.can("organization.settings.edit", feature: "job_booking_notices")
        case .drafts: session.user?.id != nil && session.activeOrganization?.id != nil
        }
    }
}

/// Who the bottom bar is first set up for, read from capabilities the server already grants
/// (no new roles): owners edit company settings, office staff assign jobs, everyone else is in
/// the field.
enum WorkRole: Equatable {
    case technician, office, owner

    init(can: (String, String?) -> Bool) {
        if can("organization.settings.edit", nil) { self = .owner }
        else if can("job.assign", "jobs") { self = .office }
        else { self = .technician }
    }

    @MainActor init(_ session: SessionController) { self.init(can: { session.can($0, feature: $1) }) }

    /// Technicians open Schedule on their own day; office and owners see everyone's.
    var schedulesOwnDay: Bool { self == .technician }
}

/// The phone's menu layout: which items sit in the tab bar (in order) and which are hidden from More.
/// Stored on this phone; a company-wide layout from the server can later supply the defaults.
@MainActor
final class MenuLayout: ObservableObject {
    static let maxTabs = 4
    static let defaultTabs: [MenuItem] = [.schedule, .jobs, .customers]

    /// The bar a role starts with when neither the company nor this phone has saved one.
    /// Places the role cannot open drop out and the technician bar fills the gap, so the bar
    /// never shrinks to one place. Schedule stays, because the app opens on it (owners open on
    /// Home when it leads their bar; Needs attention moved into Home and the menu).
    static func defaultTabs(for role: WorkRole, permitted: (MenuItem) -> Bool) -> [MenuItem] {
        let wanted: [MenuItem] = switch role {
        case .technician: [.schedule, .jobs, .customers]
        case .office: [.schedule, .inbox, .customers, .jobs]
        case .owner: [.home, .schedule, .money, .customers]
        }
        let allowed = (wanted + defaultTabs).reduce(into: [MenuItem]()) { result, item in
            if !result.contains(item), permitted(item) || defaultTabs.contains(item) { result.append(item) }
        }
        return Array(allowed.prefix(maxTabs))
    }

    /// The default this phone falls back to; set from the person's role once they sign in.
    private(set) var roleDefaultTabs: [MenuItem] = MenuLayout.defaultTabs

    @Published var tabs: [MenuItem] { didSet { changed() } }
    @Published var hidden: Set<MenuItem> { didSet { changed() } }
    /// The order of places in the phone menu below the bar's; places not listed follow in their usual order.
    @Published var menuOrder: [MenuItem] { didSet { changed() } }
    /// Where the layout comes from: this phone, or the owner's company-wide layout.
    @Published private(set) var source: Source = .phone
    enum Source { case phone, company }

    /// The company layout's job tab order, sent back unchanged when an owner saves.
    private var companyJobTabs: [String] = []
    private var applying = false
    private var pendingUpload: Task<Void, Never>?
    weak var api: APIClient?

    private struct Stored: Codable {
        var tabs: [String]
        var hidden: [String]
        /// Absent in layouts saved before the menu could be reordered.
        var menu: [String]?
    }

    private let defaults: UserDefaults
    private let key = "thorbis.menuLayout.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Stored.self, from: $0) }
        // Unknown ids (from a newer or older app) are ignored rather than breaking the layout.
        let tabs = stored?.tabs.compactMap(MenuItem.init(rawValue:)) ?? Self.defaultTabs
        self.tabs = Array(NSOrderedSet(array: tabs).array.compactMap { $0 as? MenuItem }.prefix(Self.maxTabs))
        self.hidden = Set(stored?.hidden.compactMap(MenuItem.init(rawValue:)) ?? [])
        self.menuOrder = stored?.menu?.compactMap(MenuItem.init(rawValue:)) ?? []
    }

    var isDefault: Bool { tabs == roleDefaultTabs && hidden.isEmpty && menuOrder.isEmpty }

    /// True once this phone has a saved layout of its own.
    var hasSavedPhoneLayout: Bool { defaults.data(forKey: key) != nil }

    /// Sets the bar for the person's role, but never over a saved phone layout or a company one.
    func applyRoleDefaults(_ role: WorkRole, permitted: (MenuItem) -> Bool) {
        roleDefaultTabs = Self.defaultTabs(for: role, permitted: permitted)
        guard source == .phone, !hasSavedPhoneLayout, tabs != roleDefaultTabs else { return }
        applying = true
        defer { applying = false }
        tabs = roleDefaultTabs
    }

    /// Whether `item` can sit in the bar: a company layout carries only `companyTabs`.
    func canBeTab(_ item: MenuItem) -> Bool { source != .company || MenuItem.companyTabs.contains(item) }

    /// Live arranging from the phone menu: `bar` becomes the tabs (up to `maxTabs`, extras spill to
    /// the top of the menu) and `menu` the menu order. Places this role cannot see keep their tab.
    func arrange(bar: [MenuItem], menu: [MenuItem], permitted: (MenuItem) -> Bool) {
        let allowed = bar.filter(canBeTab)
        let keep = tabs.filter { !permitted($0) && !bar.contains($0) && !menu.contains($0) }
        let newTabs = Array((allowed + keep).prefix(Self.maxTabs))
        let spilled = bar.filter { !newTabs.contains($0) }
        let newMenu = spilled + menu.filter { !newTabs.contains($0) }
        if newTabs != tabs { tabs = newTabs }
        if newMenu != menuOrder { menuOrder = newMenu }
    }

    func visibleTabs(_ session: SessionController) -> [MenuItem] { tabs.filter { $0.permitted(session) } }

    /// More shows every permitted item that is not already a tab and not hidden.
    func moreItems(in group: MenuItem.Group, session: SessionController) -> [MenuItem] {
        MenuItem.allCases.filter { $0.group == group && !tabs.contains($0) && !hidden.contains($0) && $0.listed(session) }
    }

    func addTab(_ item: MenuItem) {
        guard !tabs.contains(item), tabs.count < Self.maxTabs else { return }
        hidden.remove(item)
        tabs.append(item)
    }

    func removeTab(_ item: MenuItem) { tabs.removeAll { $0 == item } }

    func reset() {
        tabs = roleDefaultTabs
        hidden = []
        menuOrder = []
    }

    /// Reads the company layout. A 404 (none saved yet, or an older server) keeps this phone's own.
    func refreshCompanyLayout(api: APIClient) async {
        self.api = api
        do {
            let layout: CompanyMobileLayout = try await api.send("GET", "/v1/organization/mobile-layout")
            apply(layout)
        } catch {
            if source == .company { restorePhoneLayout() }
        }
    }

    /// Owners editing the company layout: every change is saved for everyone after a short pause.
    func uploadCompanyLayout() {
        guard source == .company, let api else { return }
        let body = CompanyMobileLayout(tabs: tabs.filter(MenuItem.companyTabs.contains).map(\.serverID) + ["more"],
                                       hiddenTabs: [],
                                       moreMenu: (menuOrder + MenuItem.allCases).reduce(into: [MenuItem]()) { if !$0.contains($1) { $0.append($1) } }
                                           // Home is this app's own place; the company layout API does not list it.
                                           .filter { $0.route != nil && $0 != .home }.map {
                                           .init(id: $0.serverID, hidden: hidden.contains($0))
                                       },
                                       jobTabs: companyJobTabs, version: nil, updatedAt: nil, updatedBy: nil)
        pendingUpload?.cancel()
        pendingUpload = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            if let saved: CompanyMobileLayout = try? await api.send("POST", "/v1/organization/mobile-layout", body: body) {
                self?.apply(saved)
            }
        }
    }

    /// Lets an owner start a company layout from what this phone shows now.
    func makeCompanyLayout() {
        source = .company
        tabs = tabs.filter(MenuItem.companyTabs.contains)
        uploadCompanyLayout()
    }

    private func apply(_ layout: CompanyMobileLayout) {
        applying = true
        defer { applying = false }
        let hiddenTabs = Set(layout.hiddenTabs ?? [])
        tabs = Array(layout.tabs.filter { !hiddenTabs.contains($0) }.compactMap(MenuItem.init(serverTab:))
            .filter(MenuItem.companyTabs.contains).prefix(Self.maxTabs))
        hidden = Set((layout.moreMenu ?? []).filter(\.hidden).compactMap { MenuItem(serverTab: $0.id) })
        menuOrder = (layout.moreMenu ?? []).compactMap { MenuItem(serverTab: $0.id) }
        companyJobTabs = layout.jobTabs ?? []
        source = .company
    }

    private func restorePhoneLayout() {
        let stored = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Stored.self, from: $0) }
        applying = true
        defer { applying = false }
        tabs = Array((stored?.tabs.compactMap(MenuItem.init(rawValue:)) ?? roleDefaultTabs).prefix(Self.maxTabs))
        hidden = Set(stored?.hidden.compactMap(MenuItem.init(rawValue:)) ?? [])
        menuOrder = stored?.menu?.compactMap(MenuItem.init(rawValue:)) ?? []
        source = .phone
    }

    private func changed() {
        if source == .company { if !applying { uploadCompanyLayout() } } else { save() }
    }

    private func save() {
        // The company layout lives on the server; it never overwrites this phone's own layout.
        guard !applying, source == .phone else { return }
        let stored = Stored(tabs: tabs.map(\.rawValue), hidden: hidden.map(\.rawValue).sorted(),
                            menu: menuOrder.map(\.rawValue))
        if let data = try? JSONEncoder().encode(stored) { defaults.set(data, forKey: key) }
    }
}

/// GET/POST /v1/organization/mobile-layout. Unknown ids are dropped on both sides.
struct CompanyMobileLayout: Codable {
    struct MoreItem: Codable { let id: String; let hidden: Bool }
    let tabs: [String]
    let hiddenTabs: [String]?
    let moreMenu: [MoreItem]?
    let jobTabs: [String]?
    let version: Int?
    let updatedAt: String?
    let updatedBy: String?
}

/// More → Customize menu: pick and order up to four tabs, and hide what a role never uses.
struct CustomizeMenuView: View {
    @EnvironmentObject private var layout: MenuLayout
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var api: APIClient

    private var isOwner: Bool { session.can("organization.settings.edit") }
    private var company: Bool { layout.source == .company }
    /// Members follow the owner's company layout; only owners change it.
    private var editable: Bool { !company || isOwner }
    private func canBeTab(_ item: MenuItem) -> Bool { layout.canBeTab(item) }

    var body: some View {
        List {
            Section {
                ForEach(layout.tabs) { item in
                    Label(item.title, systemImage: item.symbol)
                        .opacity(item.permitted(session) ? 1 : 0.45)
                }
                .onMove { if editable { layout.tabs.move(fromOffsets: $0, toOffset: $1) } }
                .onDelete { offsets in if editable { offsets.map { layout.tabs[$0] }.forEach(layout.removeTab) } }
                .moveDisabled(!editable)
                .deleteDisabled(!editable)
            } header: {
                Text("Pinned to the top")
            } footer: {
                Text(footer)
            }

            let addable = MenuItem.allCases.filter { !layout.tabs.contains($0) && $0.listed(session) && canBeTab($0) }
            if editable, layout.tabs.count < MenuLayout.maxTabs, !addable.isEmpty {
                Section("Pin to the top") {
                    ForEach(addable) { item in
                        Button { withAnimation { layout.addTab(item) } } label: {
                            Label(item.title, systemImage: item.symbol)
                                .foregroundStyle(Theme.foreground)
                        }
                    }
                }
            }

            Section {
                ForEach(MenuItem.allCases.filter { !layout.tabs.contains($0) && $0.listed(session) && $0.route != nil }) { item in
                    Toggle(isOn: Binding(get: { !layout.hidden.contains(item) },
                                         set: { show in if show { layout.hidden.remove(item) } else { layout.hidden.insert(item) } })) {
                        Label(item.title, systemImage: item.symbol)
                    }
                    .disabled(!editable)
                }
            } header: {
                Text("Show in menu")
            } footer: {
                Text("Hidden places stay here to turn back on; nothing is removed.")
            }

            if isOwner && !company {
                Section {
                    Button("Use this layout for everyone") { withAnimation { layout.makeCompanyLayout() } }
                } footer: {
                    Text("Everyone in \(session.activeOrganization?.name ?? "your company") gets these pinned places and this menu.")
                }
            } else if !company && !layout.isDefault {
                Section {
                    Button("Reset to the standard layout") { withAnimation { layout.reset() } }
                }
            }
        }
        .environment(\.editMode, .constant(editable ? .active : .inactive))
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle("Customize menu")
        .navigationBarTitleDisplayMode(.inline)
        .task { await layout.refreshCompanyLayout(api: api) }
    }

    private var footer: String {
        let name = session.activeOrganization?.name ?? "your company"
        if company && isOwner { return "Up to \(MenuLayout.maxTabs) pinned places. Changes apply to everyone in \(name)." }
        if company { return "Set by \(name). Ask an owner to change it." }
        return "Up to \(MenuLayout.maxTabs) pinned places. Drag to reorder, swipe to remove."
    }
}

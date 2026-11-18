import SwiftUI

/// Everything an owner can place in the tab bar or the More menu. Search and More stay fixed so
/// nothing can be lost: whatever is not in the tab bar is in More (or under Hidden in Customize).
enum MenuItem: String, CaseIterable, Codable, Identifiable {
    case home, schedule, jobs, customers, properties, attention, inbox, estimates, invoices, billing, priceBook, money, reports, scorecard, team, notices, drafts, businessSettings
    // Paper places kept on this phone until the server has them (29N, 57N, 58N).
    case timeClock, receipts, truckStock, training, pipeline, vendors, marketing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Dashboard"
        case .schedule: "Schedule"
        case .jobs: "Jobs"
        case .customers: "Customers"
        case .properties: "Properties"
        case .attention: "Needs attention"
        case .inbox: "Messages"
        case .estimates: "Estimates"
        case .invoices: "Invoices"
        case .billing: "Billing schedules"
        case .priceBook: "Price book"
        case .money: "Money"
        case .reports: "Reports"
        case .scorecard: "My scorecard"
        case .team: "Team"
        case .notices: "Notification rules"
        case .drafts: "Message drafts"
        case .businessSettings: "Business settings"
        case .timeClock: "Time clock"
        case .receipts: "Receipts"
        case .truckStock: "Truck stock"
        case .training: "Training"
        case .pipeline: "Pipeline"
        case .vendors: "Vendors and POs"
        case .marketing: "Marketing"
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
        case .home: "square.grid.2x2"
        case .schedule: "calendar"
        case .jobs: "briefcase"
        case .customers: "person"
        case .properties: "house"
        case .attention: "exclamationmark.circle"
        case .inbox: "bubble.left"
        case .estimates: "doc.text"
        case .invoices: "doc.plaintext"
        case .billing: "list.bullet.rectangle"
        case .priceBook: "book.closed"
        case .money: "banknote"
        case .reports: "chart.bar"
        case .scorecard: "target"
        case .team: "person.2"
        case .notices: "bell.badge"
        case .drafts: "square.and.pencil"
        case .businessSettings: "building.2"
        case .timeClock: "clock"
        case .receipts: "receipt"
        case .truckStock: "cube"
        case .training: "graduationcap"
        case .pipeline: "line.3.horizontal.decrease"
        case .vendors: "cart"
        case .marketing: "megaphone"
        }
    }

    /// The place mark's hue (v2, design.thorbis.com "A soft olive Jobs mark. The word stays cream"):
    /// olive, forest, pumpkin, burnt and the accent mixed down; quiet colour on chrome, not candy.
    var tint: Color {
        switch self {
        case .jobs: Theme.markOlive
        case .home, .schedule: Theme.markAccent
        case .inbox: Theme.markPumpkin
        case .customers, .properties: Theme.markForest
        case .attention: Theme.markRed
        case .estimates: Theme.markPumpkin
        case .invoices, .billing, .money: Theme.markForest
        case .priceBook: Theme.markBurnt
        case .reports, .scorecard: Theme.markOlive
        case .team, .notices, .drafts, .businessSettings, .timeClock, .receipts, .truckStock, .training,
             .pipeline, .vendors, .marketing: Theme.markGrey
        }
    }

    var subtitle: String? {
        switch self {
        case .home: "Today at a glance, money and what needs you"
        case .properties: "Every service address, across customers"
        case .attention: "Unpaid invoices, waiting estimates, jobs without a time"
        case .inbox: "Messages, calls and job notices"
        case .billing: "Progress billing, deposits, retainage"
        case .money: "Revenue, overdue and reports"
        case .reports: "Estimate conversion and schedule"
        case .scorecard: "What you sold this week"
        case .notices: "Who hears about booked and changed jobs"
        case .drafts: "Saved here, not sent"
        default: nil
        }
    }

    enum Group: String, CaseIterable { case work = "Work", business = "Business", phone = "On this phone" }

    var group: Group {
        switch self {
        case .team, .notices, .businessSettings: .business
        case .drafts: .phone
        default: .work
        }
    }

    /// Where the item opens when it is not a tab of its own.
    var route: PaperRoute? {
        switch self {
        case .schedule, .jobs, .customers: nil
        case .home: .home
        case .properties: .properties
        case .attention: .attention
        case .inbox: .inbox
        case .estimates: .estimates
        case .invoices: .invoices
        case .billing: .billing
        case .priceBook: .priceBook
        case .money: .revenue
        case .reports: .reports
        case .scorecard: .scorecard
        case .team: .team
        case .notices: .notices
        case .drafts: .drafts
        case .businessSettings: .businessSetup
        case .timeClock: .timeClock
        case .receipts: .receipts
        case .truckStock: .truckStock
        case .training: .training
        case .pipeline: .pipeline
        case .vendors: .vendors
        case .marketing: .marketing
        }
    }

    /// The id the company layout API uses (Thorbis-TanStack organization/mobile-layout).
    var serverID: String { self == .money ? "revenue" : rawValue }
    /// Tabs the company layout can carry; other items can still be tabs on a single phone.
    static let companyTabs: Set<MenuItem> = [.schedule, .jobs, .customers, .money, .inbox]

    init?(serverTab id: String) { self.init(rawValue: id == "revenue" ? "money" : id) }

    /// Whether the place is listed in the menu, the iPad sidebar and Customize menu. Notification
    /// rules live in Settings. Paper v2 lists Reports as a place of its own for office and owners.
    @MainActor func listed(_ session: SessionController) -> Bool {
        Self.listed(self, permitted: { $0.permitted(session) })
    }

    static func listed(_ item: MenuItem, permitted: (MenuItem) -> Bool) -> Bool {
        switch item {
        case .notices: false
        default: permitted(item)
        }
    }

    @MainActor func permitted(_ session: SessionController) -> Bool {
        switch self {
        case .schedule, .jobs: session.can("job.view", feature: "jobs")
        // Paper v2: the Dashboard leads the office and owner menus (52, 58).
        case .home: session.can("job.view", feature: "jobs") && WorkRole(session) != .technician
        case .customers, .properties: session.can("customer.view", feature: "core_crm")
        case .attention: session.can("invoice.view", feature: "invoicing") || session.can("estimate.view", feature: "estimates")
        case .inbox: CommsInboxAccess(session).visible
        case .estimates: session.can("estimate.view", feature: "estimates")
        case .invoices: session.can("invoice.view", feature: "invoicing")
        case .billing: session.can("invoice.view", feature: "progress_billing")
        case .priceBook: session.can("pricebook.view", feature: "price_book")
        case .money: session.can("invoice.view", feature: "invoicing") && session.can("invoice.view", feature: "payments")
        case .reports: session.can("estimate.view", feature: "estimates") || session.can("job.view", feature: "jobs")
        case .scorecard: session.can("job.view", feature: "jobs")
        case .team: session.can("organization.members.manage") || session.can("organization.permissions.manage")
        case .notices: session.can("organization.settings.edit", feature: "job_booking_notices")
            || PushNotifications.receivesMorningDigest(session)
        case .drafts: session.user?.id != nil && session.activeOrganization?.id != nil
        // Paper 58N: the owner's menu ends on Business settings (61N).
        case .businessSettings: session.can("organization.settings.edit")
        // Kept on this phone: anyone who works jobs has a clock, receipts, a truck and training.
        case .timeClock, .receipts, .truckStock, .training: session.can("job.view", feature: "jobs")
        case .pipeline: session.can("customer.view", feature: "core_crm") && WorkRole(session) != .technician
        case .vendors: WorkRole(session) != .technician
        case .marketing: session.can("organization.settings.edit")
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

    /// Bottom bar or sidebar on this iPhone (Paper 65A "Navigation"). Saved under its own key, never
    /// through `changed()`: it is this device's choice, not part of a company layout.
    @Published var navigationStyle: PhoneNavigationStyle {
        didSet {
            guard navigationStyle != oldValue, !isPad, !preview else { return }
            defaults.set(navigationStyle.rawValue, forKey: PhoneNavigationStyle.key)
        }
    }
    /// iPad keeps its sidebar and does not offer the choice.
    let isPad: Bool
    /// The design preview keeps its choice in memory so a test never changes the next one's.
    private let preview: Bool

    /// The bottom bar is on (an iPhone, or a narrow window that is not an iPad).
    var usesBottomBar: Bool { navigationStyle == .bottomBar }

    init(defaults: UserDefaults = .standard, isPad: Bool? = nil, preview: Bool? = nil, previewFlag: String? = nil) {
        self.defaults = defaults
        let isPad = isPad ?? (UIDevice.current.userInterfaceIdiom == .pad)
        let preview = preview ?? PhoneNavigationStyle.isPreview
        self.isPad = isPad
        self.preview = preview
        self.navigationStyle = PhoneNavigationStyle.resolve(
            saved: preview ? nil : defaults.string(forKey: PhoneNavigationStyle.key), isPad: isPad,
            preview: preview, previewFlag: previewFlag ?? (preview ? PhoneNavigationStyle.previewFlag : nil))
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

/// Paper 65A Menu and start screen, in its three sections: "Open the app to" (the start screen),
/// "Your menu" (the role's main rows, dragged into the person's order) and "More" (What's new),
/// with the reset pill under them. On iPad (Paper T10B) where the app opens sits beside the menu.
/// Pinning to the top and hiding places are gone: the menu is Paper's rows for the role.
struct CustomizeMenuView: View {
    @EnvironmentObject private var layout: MenuLayout
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var api: APIClient
    @State private var startupDestination: StartupDestination = .automatic
    @State private var showingWhatsNew = false
    @State private var showingNavigation = false

    private var company: Bool { layout.source == .company }
    /// A company layout is set on the web for everyone; the order here is this phone's own.
    private var editable: Bool { !company }
    private var role: WorkRole { WorkRole(session) }

    /// Two columns need this much room; a narrower iPad window keeps the phone's one list.
    private static let wideWidth: CGFloat = 640
    /// Paper 65A: rows are 56 tall, their words 16 from the card's edge.
    private static let rowInsets = EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)

    /// The role's main menu rows this person can open, in the order their menu shows them.
    private var menuRows: [MenuItem] {
        MenuArrangement.rows(role: role, order: editable ? layout.menuOrder : [], opens: { $0.permitted(session) })
    }

    var body: some View {
        Group {
            if UIDevice.current.userInterfaceIdiom == .pad {
                GeometryReader { geometry in
                    if geometry.size.width >= Self.wideWidth { tabletColumns } else { phoneList }
                }
            } else {
                phoneList
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .thorbisDestination(isPresented: $showingWhatsNew) { WhatsNewHistoryView() }
        .thorbisDestination(isPresented: $showingNavigation) { NavigationChoiceView() }
        .task { await layout.refreshCompanyLayout(api: api) }
        .task(id: StartupDestination.scope(session: session, api: api)?.key) {
            startupDestination = StartupDestination.scope(session: session, api: api).map { StartupDestinationPreferences().get(for: $0) } ?? .automatic
        }
        .accessibilityIdentifier("menu-and-start-screen")
    }

    /// The phone's screen: one list, top to bottom.
    private var phoneList: some View {
        List {
            // Paper 65A: the title in 34 Bold on the canvas, one muted line under it.
            Section {
                titleBlock
                    .listRowBackground(Color.clear)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 14)
                    .listRowInsets(EdgeInsets(top: PaperHeaderMetrics.titleTopUnderBar, leading: 0, bottom: 0, trailing: 0))
                    .listRowSeparator(.hidden)
            }
            startSection
            menuSection
            moreSection
            actionSection
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(22)
        .listRowSeparatorTint(Theme.hairline)
        .contentMargins(.horizontal, PaperCardMetrics.margin, for: .scrollContent)
        .contentMargins(.top, 0, for: .scrollContent)
        .environment(\.defaultMinListRowHeight, 56)
        .environment(\.editMode, .constant(editable ? .active : .inactive))
        .scrollContentBackground(.hidden)
    }

    /// Paper T10B (iPad): the title across the top; "Open the app to", More and the layout action on
    /// the left, "Your menu" on the right.
    private var tabletColumns: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleBlock
                .padding(.horizontal, Theme.gutter).padding(.top, 12).padding(.bottom, 4)
            HStack(alignment: .top, spacing: 0) {
                List {
                    startSection
                    moreSection
                    actionSection
                }
                .listStyle(.insetGrouped)
                .listSectionSpacing(20)
                .listRowSeparatorTint(Theme.hairline)
                .scrollContentBackground(.hidden)
                List {
                    menuSection
                }
                .listStyle(.insetGrouped)
                .listSectionSpacing(20)
                .listRowSeparatorTint(Theme.hairline)
                .environment(\.editMode, .constant(editable ? .active : .inactive))
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var titleBlock: some View {
        // The list row places the block (its own insets); the shared title draws the words.
        PaperPageTitle(title: "Menu and start screen", subtitle: "Make the menu yours", columnInset: Theme.gutter, top: 0)
    }

    /// What the start-screen control shows as chosen: a place this role lost falls back to Automatic.
    private var chosenStart: StartupDestination {
        startupDestination.permitted(session) ? startupDestination : .automatic
    }

    /// Paper 65A "Open the app to": Automatic and the role's main rows, each with a radio mark. A
    /// start screen chosen in an older build that is not one of those rows keeps its own row, so it
    /// still shows as chosen and still opens.
    @ViewBuilder private var startSection: some View {
        if let scope = StartupDestination.scope(session: session, api: api) {
            let choices = MenuArrangement.startChoices(rows: menuRows, chosen: chosenStart)
            Section {
                ForEach(choices, id: \.rawValue) { destination in
                    startRadioRow(destination, scope: scope)
                }
                .moveDisabled(true)
                .deleteDisabled(true)
                .listRowBackground(Theme.card)
                .listRowInsets(Self.rowInsets)
            } header: {
                sectionLabel("Open the app to")
            }
        }
    }

    /// Paper 65A's start-screen row: the place in 16 Medium, a 22pt radio mark at the trailing edge.
    private func startRadioRow(_ destination: StartupDestination, scope: StartupDestinationScope) -> some View {
        let chosen = chosenStart == destination
        return Button {
            StartupDestinationPreferences().set(destination, for: scope)
            startupDestination = destination
        } label: {
            HStack(spacing: 12) {
                Text(destination.displayTitle).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                ZStack {
                    Circle().strokeBorder(chosen ? Theme.brand : Theme.borderStrong, lineWidth: chosen ? 2 : 1.5)
                    if chosen { Circle().fill(Theme.brand).frame(width: 10, height: 10) }
                }
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityHint("Applies the next time you open the app on this device")
        .accessibilityIdentifier("start-\(destination.rawValue)")
    }

    /// Paper 65A "Your menu": the role's main rows; drag one to change the order the menu lists them.
    private var menuSection: some View {
        Section {
            ForEach(menuRows) { item in
                Text(item.title).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .accessibilityIdentifier("menu-row-\(item.rawValue)")
            }
            .onMove { source, destination in
                guard editable else { return }
                var rows = menuRows
                rows.move(fromOffsets: source, toOffset: destination)
                layout.menuOrder = rows
                UISelectionFeedbackGenerator().selectionChanged()
            }
            .moveDisabled(!editable)
            .deleteDisabled(true)
            .listRowBackground(Theme.card)
            .listRowInsets(Self.rowInsets)
        } header: {
            sectionLabel("Your menu")
        } footer: {
            if company {
                sectionNote("Set by \(session.activeOrganization?.name ?? "your company").")
            }
        }
    }

    /// Paper 65A / T10B "More": Navigation (bottom bar or sidebar, iPhone only: iPad keeps its
    /// sidebar) and what changed in the app, one tap away.
    private var moreSection: some View {
        Section {
            if !layout.isPad {
                Button { showingNavigation = true } label: {
                    HStack(spacing: 8) {
                        Text("Navigation").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Text(layout.navigationStyle.title).font(Theme.font(15)).foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.trailing)
                        PaperIcon(.acctChevron, size: 14, color: Theme.muted)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Navigation")
                .accessibilityValue(layout.navigationStyle.title)
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("menu-navigation")
                .moveDisabled(true)
                .deleteDisabled(true)
                .listRowBackground(Theme.card)
                .listRowInsets(Self.rowInsets)
            }
            // A button, not a link: the phone's list is in edit mode, where row links don't open.
            Button { showingWhatsNew = true } label: {
                HStack(spacing: 8) {
                    Text("What's new").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                    Spacer(minLength: 8)
                    PaperIcon(.acctChevron, size: 14, color: Theme.muted)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .moveDisabled(true)
            .deleteDisabled(true)
            .listRowBackground(Theme.card)
            .listRowInsets(Self.rowInsets)
        } header: {
            sectionLabel("More")
        }
    }

    /// Paper 65A: one quiet pill at the end, shown once this phone's layout differs from the
    /// standard one (an order dragged here, or pins and hidden places kept from an older build).
    @ViewBuilder private var actionSection: some View {
        if !company && !layout.isDefault {
            Section {
                Button { withAnimation { layout.reset() } } label: { RimmedButtonLabel(title: "Reset to the standard layout", symbol: "arrow.counterclockwise") }
                    .buttonStyle(PressStyle())
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .accessibilityIdentifier("menu-reset")
            }
        }
    }

    /// Paper's section label: 13 Semibold, muted, sentence case.
    private func sectionLabel(_ title: String) -> some View {
        Text(title).font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted).textCase(nil)
            .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 8, trailing: 4))
    }

    private func sectionNote(_ text: String) -> some View {
        Text(text).font(Theme.font(13)).foregroundStyle(Theme.muted)
    }
}

/// Paper 65 / 65A "Navigation": how this iPhone moves between places. Two radio rows in Menu and
/// start screen's grammar; the choice is this device's own and applies at once.
struct NavigationChoiceView: View {
    @EnvironmentObject private var layout: MenuLayout

    var body: some View {
        List {
            Section {
                PaperPageTitle(title: "Navigation", subtitle: "Choose how you move around the app", columnInset: Theme.gutter, top: 0)
                    .listRowBackground(Color.clear)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 14)
                    .listRowInsets(EdgeInsets(top: PaperHeaderMetrics.titleTopUnderBar, leading: 0, bottom: 0, trailing: 0))
                    .listRowSeparator(.hidden)
            }
            Section {
                ForEach(PhoneNavigationStyle.allCases) { style in
                    row(style)
                }
                .listRowBackground(Theme.card)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            } footer: {
                Text("The bottom bar keeps your main places one tap away; More opens the full menu. The sidebar opens from the menu button at the top of each place.")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(22)
        .listRowSeparatorTint(Theme.hairline)
        .contentMargins(.horizontal, PaperCardMetrics.margin, for: .scrollContent)
        .contentMargins(.top, 0, for: .scrollContent)
        .environment(\.defaultMinListRowHeight, 56)
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("navigation-choice")
    }

    private func row(_ style: PhoneNavigationStyle) -> some View {
        let chosen = layout.navigationStyle == style
        return Button {
            layout.navigationStyle = style
        } label: {
            HStack(spacing: 12) {
                PaperIcon(style == .bottomBar ? .navBottomBar : .navSidebar, size: 18, color: Theme.muted)
                Text(style.title).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                ZStack {
                    Circle().strokeBorder(chosen ? Theme.brand : Theme.borderStrong, lineWidth: chosen ? 2 : 1.5)
                    if chosen { Circle().fill(Theme.brand).frame(width: 10, height: 10) }
                }
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityIdentifier("navigation-\(style.rawValue)")
    }
}

/// What Menu and start screen arranges, kept pure so it is unit-tested: the role's main menu rows
/// in the person's order, and the start screens offered.
enum MenuArrangement {
    /// The role's main rows (Paper 29N / 57N / 58N, first group) this person can open, in their
    /// saved order. Ids in a saved order that are not main rows are ignored.
    static func rows(role: WorkRole, order: [MenuItem], opens: (MenuItem) -> Bool) -> [MenuItem] {
        DrawerSections.make(order: order, role: role, opens: opens).sections.first { $0.kind == .primary }?.places ?? []
    }

    /// Automatic, then the main rows. A start screen chosen earlier that is not a main row (older
    /// builds offered every place) is listed too, so it stays visible and can be changed.
    static func startChoices(rows: [MenuItem], chosen: StartupDestination) -> [StartupDestination] {
        var choices = [StartupDestination.automatic] + rows.compactMap { StartupDestination(rawValue: $0.rawValue) }
        if !choices.contains(chosen) { choices.append(chosen) }
        return choices
    }
}

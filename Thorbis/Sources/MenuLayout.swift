import SwiftUI

/// Everything an owner can place in the tab bar or the More menu. Search and More stay fixed so
/// nothing can be lost: whatever is not in the tab bar is in More (or under Hidden in Customize).
enum MenuItem: String, CaseIterable, Codable, Identifiable {
    case schedule, jobs, customers, attention, inbox, estimates, invoices, billing, priceBook, money, reports, team, notices, drafts

    var id: String { rawValue }

    var title: String {
        switch self {
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
        case .notices: "Job notices"
        case .drafts: "Message drafts"
        }
    }

    /// The tab bar has little room; long names get a short label there.
    var tabTitle: String {
        switch self {
        case .billing: "Billing"
        case .attention: "Attention"
        case .team: "Team"
        case .notices: "Notices"
        case .drafts: "Drafts"
        default: title
        }
    }

    var symbol: String {
        switch self {
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

    /// Tile color in menus; one hue per kind of work so the menu scans at a glance.
    var tint: Color {
        switch self {
        case .schedule, .jobs: Theme.brandText
        case .customers, .team: Color(hex: 0x8B5CF6)
        case .attention: Theme.warning
        case .inbox, .notices: Color(hex: 0x06B6D4)
        case .estimates, .invoices, .billing: Theme.success
        case .money, .reports: Color(hex: 0xEC4899)
        case .priceBook: Color(hex: 0xF97316)
        case .drafts: Theme.muted
        }
    }

    var subtitle: String? {
        switch self {
        case .attention: "Unpaid invoices, waiting estimates, jobs without a time"
        case .inbox: "Job notices and assignments"
        case .billing: "Progress billing, deposits, retainage"
        case .money: "Revenue, collected and overdue"
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

    @MainActor func permitted(_ session: SessionController) -> Bool {
        switch self {
        case .schedule, .jobs: session.can("job.view", feature: "jobs")
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

/// The phone's menu layout: which items sit in the tab bar (in order) and which are hidden from More.
/// Stored on this phone; a company-wide layout from the server can later supply the defaults.
@MainActor
final class MenuLayout: ObservableObject {
    static let maxTabs = 4
    static let defaultTabs: [MenuItem] = [.schedule, .jobs, .customers]

    @Published var tabs: [MenuItem] { didSet { changed() } }
    @Published var hidden: Set<MenuItem> { didSet { changed() } }
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
    }

    var isDefault: Bool { tabs == Self.defaultTabs && hidden.isEmpty }

    func visibleTabs(_ session: SessionController) -> [MenuItem] { tabs.filter { $0.permitted(session) } }

    /// More shows every permitted item that is not already a tab and not hidden.
    func moreItems(in group: MenuItem.Group, session: SessionController) -> [MenuItem] {
        MenuItem.allCases.filter { $0.group == group && !tabs.contains($0) && !hidden.contains($0) && $0.permitted(session) }
    }

    func addTab(_ item: MenuItem) {
        guard !tabs.contains(item), tabs.count < Self.maxTabs else { return }
        hidden.remove(item)
        tabs.append(item)
    }

    func removeTab(_ item: MenuItem) { tabs.removeAll { $0 == item } }

    func reset() {
        tabs = Self.defaultTabs
        hidden = []
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
                                       moreMenu: MenuItem.allCases.filter { $0.route != nil }.map {
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
        companyJobTabs = layout.jobTabs ?? []
        source = .company
    }

    private func restorePhoneLayout() {
        let stored = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Stored.self, from: $0) }
        applying = true
        defer { applying = false }
        tabs = Array((stored?.tabs.compactMap(MenuItem.init(rawValue:)) ?? Self.defaultTabs).prefix(Self.maxTabs))
        hidden = Set(stored?.hidden.compactMap(MenuItem.init(rawValue:)) ?? [])
        source = .phone
    }

    private func changed() {
        if source == .company { if !applying { uploadCompanyLayout() } } else { save() }
    }

    private func save() {
        // The company layout lives on the server; it never overwrites this phone's own layout.
        guard !applying, source == .phone else { return }
        let stored = Stored(tabs: tabs.map(\.rawValue), hidden: hidden.map(\.rawValue).sorted())
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
    private func canBeTab(_ item: MenuItem) -> Bool { !company || MenuItem.companyTabs.contains(item) }

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
                Text("Tab bar")
            } footer: {
                Text(footer)
            }

            let addable = MenuItem.allCases.filter { !layout.tabs.contains($0) && $0.permitted(session) && canBeTab($0) }
            if editable, layout.tabs.count < MenuLayout.maxTabs, !addable.isEmpty {
                Section("Add to tab bar") {
                    ForEach(addable) { item in
                        Button { withAnimation { layout.addTab(item) } } label: {
                            Label(item.title, systemImage: item.symbol)
                                .foregroundStyle(Theme.foreground)
                        }
                    }
                }
            }

            Section {
                ForEach(MenuItem.allCases.filter { !layout.tabs.contains($0) && $0.permitted(session) && $0.route != nil }) { item in
                    Toggle(isOn: Binding(get: { !layout.hidden.contains(item) },
                                         set: { show in if show { layout.hidden.remove(item) } else { layout.hidden.insert(item) } })) {
                        Label(item.title, systemImage: item.symbol)
                    }
                    .disabled(!editable)
                }
            } header: {
                Text("Show in More")
            } footer: {
                Text("Hidden items stay available here; nothing is removed.")
            }

            if isOwner && !company {
                Section {
                    Button("Use this layout for everyone") { withAnimation { layout.makeCompanyLayout() } }
                } footer: {
                    Text("Everyone in \(session.activeOrganization?.name ?? "your company") gets these tabs and this More menu.")
                }
            } else if !company && !layout.isDefault {
                Section {
                    Button("Reset to the standard layout") { withAnimation { layout.reset() } }
                }
            }
        }
        .environment(\.editMode, .constant(editable ? .active : .inactive))
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Customize menu")
        .navigationBarTitleDisplayMode(.inline)
        .task { await layout.refreshCompanyLayout(api: api) }
    }

    private var footer: String {
        let name = session.activeOrganization?.name ?? "your company"
        if company && isOwner { return "Up to \(MenuLayout.maxTabs) tabs, plus More and Search. Changes apply to everyone in \(name)." }
        if company { return "Set by \(name). Ask an owner to change it." }
        return "Up to \(MenuLayout.maxTabs) tabs, plus More and Search. Drag to reorder, swipe to remove."
    }
}

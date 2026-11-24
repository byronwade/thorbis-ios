import SwiftUI

// MARK: - Where a place opens when the menu does not list it
//
// The menu lists Paper's rows for the role and nothing else (Navigation 29N / 57N / 58N). Every
// other place still has a door: the screen Paper's Map says it belongs to (Estimates and Invoices
// "from Money", My scorecard from Reports, Team and Notification rules in Business settings), and,
// where Paper names no parent for this role, "Other places" in Settings. Search lists every place.
// Pure, so "nothing is unreachable" is unit-tested per role.

/// The screen a place is reached from.
enum PlaceDoor: String, Equatable, CaseIterable {
    /// A row of the role's menu.
    case menu
    /// Money: Estimates, Invoices, Billing schedules, Needs attention.
    case money
    /// Reports: My scorecard.
    case reports
    /// Messages: its Drafts folder.
    case messages
    /// Team: Team additions.
    case team
    /// Business settings: Price book, Notification rules, Team and permissions.
    case businessSettings
    /// Settings › Other places: what Paper gives no parent for this role.
    case settings
}

struct PlaceDoors {
    let role: WorkRole
    /// Whether this person may open the place.
    let opens: (MenuItem) -> Bool
    /// The records (Fleet, Equipment, Maintenance plans, Team additions) this person may open.
    let local: [LocalWorkspaceSection]
    /// Business settings lists Price book for this person.
    var businessPriceBook = false
    /// Business settings lists Team and permissions for this person.
    var businessTeam = false

    @MainActor init(session: SessionController) {
        role = WorkRole(session)
        opens = { $0.permitted(session) }
        local = session.user?.id != nil && session.activeOrganization?.id != nil
            ? LocalWorkspaceSection.allCases.filter { session.can($0.requiredCapability, feature: $0.requiredFeature) } : []
        // The same checks Business settings makes for its own rows.
        let reachesBusiness = session.can("organization.settings.edit")
        businessPriceBook = reachesBusiness && (session.can("pricebook.edit", feature: "price_book")
            || session.can("organization.settings.edit", feature: "price_book"))
        businessTeam = reachesBusiness && MenuItem.team.permitted(session)
    }

    init(role: WorkRole, local: [LocalWorkspaceSection] = LocalWorkspaceSection.allCases, businessPriceBook: Bool = false,
         businessTeam: Bool = false, opens: @escaping (MenuItem) -> Bool) {
        self.role = role
        self.opens = opens
        self.local = local
        self.businessPriceBook = businessPriceBook
        self.businessTeam = businessTeam
    }

    /// The role's menu rows this person can open.
    private var menu: [DrawerSections.Entry] {
        DrawerSections.make(local: local, role: role, opens: opens).sections.flatMap(\.rows)
    }

    /// Where the place opens. Nil when this person may not open it at all.
    func door(_ entry: DrawerSections.Entry) -> PlaceDoor? {
        let menu = menu
        func inMenu(_ item: MenuItem) -> Bool { menu.contains(.place(item)) }
        switch entry {
        case .place(let item):
            guard opens(item) else { return nil }
            if inMenu(item) { return .menu }
            switch item {
            case .estimates, .invoices, .billing, .attention: return inMenu(.money) ? .money : .settings
            // Reports draws its summary (and this row) only for people who see Money's figures.
            case .scorecard: return inMenu(.reports) && opens(.money) ? .reports : .settings
            case .drafts: return inMenu(.inbox) ? .messages : .settings
            // Paper 61N: rules sit under Operations. People without the owner's menu row reach
            // Business settings from Settings.
            case .notices: return .businessSettings
            case .team: return businessTeam && inMenu(.businessSettings) ? .businessSettings : .settings
            case .priceBook: return businessPriceBook && inMenu(.businessSettings) ? .businessSettings : .settings
            default: return .settings
            }
        case .local(let section):
            guard local.contains(section) else { return nil }
            if menu.contains(entry) { return .menu }
            // Team additions folds into Team, for anyone who can open Team from their menu or
            // from Business settings.
            if section == .team, opens(.team), inMenu(.team) || (businessTeam && inMenu(.businessSettings)) { return .team }
            return .settings
        }
    }

    /// Every place and record there is, in the order rows are listed.
    static var everything: [DrawerSections.Entry] {
        PlaceSection.canonical.map(DrawerSections.Entry.place)
            + MenuItem.allCases.filter { !PlaceSection.canonical.contains($0) }.map(DrawerSections.Entry.place)
            + LocalWorkspaceSection.allCases.map(DrawerSections.Entry.local)
    }

    /// The places a screen lists because the menu does not.
    func places(behind door: PlaceDoor) -> [DrawerSections.Entry] {
        Self.everything.filter { self.door($0) == door }
    }
}

extension DrawerSections.Entry {
    var doorTitle: String {
        switch self {
        case .place(let item): item.title
        case .local(let section): section.title
        }
    }

    var doorSymbol: String {
        switch self {
        case .place(let item): item.symbol
        case .local(let section): section.moreSymbol
        }
    }

    var doorSubtitle: String? {
        switch self {
        case .place(let item): item.subtitle
        case .local(let section): section.moreSubtitle
        }
    }

    /// The route the row pushes. Schedule, Jobs and Customers are always menu rows, never doors.
    var doorRoute: PaperRoute? {
        switch self {
        case .place(let item): item.route
        case .local(let section): .local(section)
        }
    }
}

/// The rows a screen carries for the places behind it: Paper's settings rows (a glyph, the place's
/// name, a chevron) on one card. Draws nothing when every such place is in this person's menu.
struct PlaceDoorRows: View {
    let door: PlaceDoor
    var title: String? = nil
    /// Skips places the host screen already links in its own way.
    var except: Set<MenuItem> = []
    var showsSubtitles = false
    @EnvironmentObject private var session: SessionController

    var body: some View {
        let entries = PlaceDoors(session: session).places(behind: door).filter { entry in
            if case .place(let item) = entry { return !except.contains(item) }
            return true
        }
        if !entries.isEmpty {
            AccountGroup(title: title) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { WellDivider(leading: AccountRow<EmptyView>.dividerInset) }
                    if let route = entry.doorRoute {
                        NavigationLink(value: route) {
                            AccountRow(glyph: PaperGlyph.place(symbol: entry.doorSymbol), symbol: entry.doorSymbol, glyphSize: 18,
                                       title: entry.doorTitle, subtitle: showsSubtitles ? entry.doorSubtitle : nil)
                        }
                        .buttonStyle(RowPressStyle())
                        .accessibilityIdentifier("door-\(entry.id)")
                    }
                }
            }
        }
    }
}

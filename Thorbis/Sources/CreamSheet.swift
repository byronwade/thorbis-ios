import SwiftUI

// MARK: - Cream sheet (owner-approved direction, 2026-11-01)
//
// The grammar the sidebar, Today and the job page share (C-Nav, C-Today, C-Job .dc.html): places are
// grouped under plain headings (Work, Money, Shop, On this phone) and every place a role can reach is
// listed; a numbers row instead of stat cards; a quiet map strip with a drive pill; labelled rimmed
// buttons 12pt apart; clusters that are space, not a card per field; one ink commit. Light is the
// cream sheet, dark the Linear greys; every colour comes from `Theme`.

/// The headings the sidebar groups places under.
enum PlaceSection: String, CaseIterable, Identifiable {
    case pinned = "Pinned", work = "Work", money = "Money", shop = "Shop", phone = "On this phone"
    var id: String { rawValue }

    /// The order places take inside their section (C-Nav.dc.html).
    static let canonical: [MenuItem] = [.home, .schedule, .jobs, .customers, .properties, .inbox, .attention,
                                        .money, .estimates, .invoices, .billing, .reports, .scorecard, .priceBook,
                                        .team, .notices, .drafts]
}

extension MenuItem {
    /// Where the place is listed in the sidebar.
    var placeSection: PlaceSection {
        switch self {
        case .home, .schedule, .jobs, .customers, .properties, .inbox, .attention: .work
        case .money, .estimates, .invoices, .billing, .reports, .scorecard, .priceBook: .money
        case .team, .notices, .drafts: .shop
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
        case .estimates, .invoices, .billing, .reports, .scorecard, .team, .notices, .drafts: Theme.markGrey
        }
    }
}

/// Every place a person can reach, grouped as the sidebar lists it. Pure, so the owner's rule (every
/// reachable place, each exactly once) is unit-tested per role.
struct DrawerSections: Equatable {
    struct Section: Equatable, Identifiable {
        let kind: PlaceSection
        var places: [MenuItem]
        var local: [LocalWorkspaceSection] = []
        var id: String { kind.rawValue }
    }

    var sections: [Section]

    /// The places in the order they are listed, pinned ones first.
    var places: [MenuItem] { sections.flatMap(\.places) }

    /// - Parameters:
    ///   - pins: the layout's pinned places (company or this phone), from Edit menu.
    ///   - explicitPins: true when the person or company chose pins; the role's own defaults never
    ///     count, so a role that never edited its menu sees no Pinned section.
    ///   - hidden: places the person or company turned off in Customize menu (none by default).
    ///   - order: Edit menu's order; it leads inside each section.
    ///   - local: records kept on this phone (Fleet, Equipment, Agreements) this role may open.
    ///   - opens: whether this role can open the place.
    static func make(pins: [MenuItem] = [], explicitPins: Bool = false, roleDefaults: [MenuItem] = [],
                     hidden: Set<MenuItem> = [], order: [MenuItem] = [], local: [LocalWorkspaceSection] = [],
                     opens: (MenuItem) -> Bool) -> DrawerSections {
        func reachable(_ item: MenuItem) -> Bool { opens(item) && !hidden.contains(item) }
        let pinned = explicitPins ? unique(pins.filter { reachable($0) && !roleDefaults.contains($0) }) : []
        var sections: [Section] = []
        if !pinned.isEmpty { sections.append(Section(kind: .pinned, places: pinned)) }
        for kind in [PlaceSection.work, .money, .shop] {
            let members = PlaceSection.canonical.filter { $0.placeSection == kind && reachable($0) && !pinned.contains($0) }
            let items = unique(order.filter(members.contains) + members)
            if !items.isEmpty { sections.append(Section(kind: kind, places: items)) }
        }
        if !local.isEmpty { sections.append(Section(kind: .phone, places: [], local: local)) }
        return DrawerSections(sections: sections)
    }

    private static func unique(_ items: [MenuItem]) -> [MenuItem] {
        items.reduce(into: [MenuItem]()) { if !$0.contains($1) { $0.append($1) } }
    }
}

/// What a place row says at its trailing edge: a count in tabular figures, or the accent dot.
struct PlaceCount: Equatable {
    var text: String?
    /// Set in the accent (unread Inbox).
    var accent = false
    /// What VoiceOver reads as the row's value.
    var spoken: String

    static func number(_ value: Int, spoken: String) -> PlaceCount? {
        value > 0 ? PlaceCount(text: "\(value)", spoken: spoken) : nil
    }
    static let unread = PlaceCount(text: nil, accent: true, spoken: "Unread")
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

/// The grouped places: a 12 Medium heading per section, then rows. A row is the place's mark in its
/// quiet hue (filled when it is the place), the word in body (lifted to ink when here) and a count in
/// tabular figures at the trailing edge. The place showing sits on the selected fill.
struct PlacesList: View {
    let sections: DrawerSections
    let title: (MenuItem) -> String
    let isCurrent: (MenuItem) -> Bool
    let isCurrentLocal: (LocalWorkspaceSection) -> Bool
    let count: (MenuItem) -> PlaceCount?
    /// "drawer" or "sidebar": rows are `<prefix>-<place>` (`drawer-jobs`, `sidebar-local-fleet`).
    let idPrefix: String
    var phoneHeading = PlaceSection.phone.rawValue
    var savedWork: AppBottomBar.Sync? = nil
    var savedWorkTitle = "Saved on this phone"
    let openPlace: (MenuItem) -> Void
    let openLocal: (LocalWorkspaceSection) -> Void
    var openSavedWork: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(sections.sections) { section in
                heading(section.kind == .phone ? phoneHeading : section.kind.rawValue)
                ForEach(section.places) { item in
                    PlaceRow(title: title(item), symbol: item.symbol, tint: item.sidebarTint, here: isCurrent(item),
                             count: count(item), id: "\(idPrefix)-\(item.rawValue)") { openPlace(item) }
                }
                if section.kind == .phone {
                    localRows(section.local)
                    if let savedWork { savedWorkRow(savedWork) }
                }
            }
            // Saved work with no local places still gets its heading.
            if let savedWork, !sections.sections.contains(where: { $0.kind == .phone }) {
                heading(phoneHeading)
                savedWorkRow(savedWork)
            }
        }
    }

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(Theme.font(12, weight: .medium))
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 12)
            .padding(.top, 16).padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private func localRows(_ local: [LocalWorkspaceSection]) -> some View {
        ForEach(local, id: \.self) { section in
            PlaceRow(title: section.title, symbol: section.moreSymbol, tint: Theme.markGrey, here: isCurrentLocal(section),
                     count: nil, id: "\(idPrefix)-local-\(section.rawValue)") { openLocal(section) }
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

/// A place's mark in a row: the symbol in its quiet hue, outlined at rest and filled when here.
struct PlaceRowIcon: View {
    let symbol: String
    let tint: Color
    let filled: Bool
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 18

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .regular))
            .symbolVariant(filled ? .fill : .none)
            .foregroundStyle(tint)
            .frame(width: size + 4)
            .accessibilityHidden(true)
    }
}

/// One place: mark, word, count. Selected: filled mark, the selected fill and the word in ink.
struct PlaceRow: View {
    let title: String
    let symbol: String
    let tint: Color
    let here: Bool
    let count: PlaceCount?
    let id: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                PlaceRowIcon(symbol: symbol, tint: tint, filled: here)
                Text(title)
                    .font(Theme.font(15, weight: .medium))
                    .foregroundStyle(here ? Theme.foreground : Theme.subtle)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let count {
                    if let text = count.text {
                        Text(text).font(Theme.monoFont(12, weight: .medium))
                            .foregroundStyle(count.accent ? Theme.brandText : Theme.muted)
                            .lineLimit(1).fixedSize()
                    } else if count.accent {
                        DrawerDot()
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background {
                if here { RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).fill(Theme.fill) }
            }
            .contentShape(Rectangle())
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

/// A round control on the canvas: the fill with a 1px rim (C-Today's menu and search circles).
struct CreamCircleLabel: View {
    let symbol: String
    var size: CGFloat = 40
    var ink = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: ink ? .semibold : .medium))
            .foregroundStyle(ink ? Theme.onInk : Theme.foreground)
            .frame(width: size, height: size)
            .background(ink ? Theme.ink : Theme.fill, in: Circle())
            .overlay(Circle().strokeBorder(Theme.border, lineWidth: 1))
            .shadow(color: .black.opacity(ink ? 0.22 : 0), radius: 0, x: 0, y: 1)
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
    @Environment(\.thorbisPressed) private var pressed
    /// The glyph grows with the word beside it.
    @ScaledMetric(relativeTo: .subheadline) private var glyph: CGFloat = 15

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: glyph, weight: .medium)).accessibilityHidden(true)
            Text(title).font(Theme.font(14, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(Theme.foreground.opacity(enabled ? 1 : 0.4))
        .padding(.horizontal, 8).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(Theme.selectedSegment, in: shape)
        .overlay(shape.strokeBorder(Theme.border, lineWidth: 1))
        .shadow(color: .black.opacity(pressed || !enabled ? 0 : 0.07), radius: 0, x: 0, y: 1)
        .contentShape(shape)
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
            context.stroke(ring, with: .color(.white), lineWidth: 3)
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
                        Text(subtitle)
                            .font(Theme.font(13)).foregroundStyle(Theme.muted)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                HStack(spacing: 4) { trailing }
            }
            .padding(.leading, Theme.gutter).padding(.trailing, 14)
            .padding(.top, 14)
        }
    }
}

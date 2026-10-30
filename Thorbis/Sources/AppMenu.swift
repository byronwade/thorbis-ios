import SwiftUI

/// Jobs and customers opened on this phone, newest first, for the phone's search.
@MainActor
final class RecentItems: ObservableObject {
    struct Item: Codable, Hashable, Identifiable {
        enum Kind: String, Codable { case job, customer }
        let kind: Kind
        let id: String
        let title: String
        let subtitle: String
    }

    static let shared = RecentItems()
    /// Only the verified person and workspace's history; empty until one is bound.
    @Published private(set) var items: [Item] = []
    private var owner: String?
    private var byOwner: [String: [Item]]
    private let key = "thorbis.recentItems.v2"

    private init() {
        UserDefaults.standard.removeObject(forKey: "thorbis.recentItems.v1")
        byOwner = UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([String: [Item]].self, from: $0) } ?? [:]
    }

    /// Follows the session's verified identity, like the workspace cache, so a workspace switch
    /// or a different sign-in never shows the previous identity's records.
    func bind(actorID: String?, organizationID: String?) {
        if let actorID, let organizationID {
            owner = "\(actorID.lowercased())|\(organizationID.lowercased())"
        } else {
            owner = nil
        }
        items = owner.flatMap { byOwner[$0] } ?? []
    }

    func record(_ kind: Item.Kind, id: String, title: String, subtitle: String) {
        guard let owner else { return }
        let item = Item(kind: kind, id: id, title: title, subtitle: subtitle)
        guard items.first != item else { return }
        items.removeAll { $0.kind == kind && $0.id == id }
        items.insert(item, at: 0)
        items = Array(items.prefix(8))
        byOwner[owner] = items
        save()
    }

    func clear() {
        items = []
        byOwner = [:]
        UserDefaults.standard.removeObject(forKey: key)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(byOwner) { UserDefaults.standard.set(data, forKey: key) }
    }
}

/// Places in the phone menu: bar places first, then every other permitted place.
enum AppMenuContent {
    static func places(tabs: [MenuItem], hidden: Set<MenuItem>, order: [MenuItem] = [],
                       permitted: (MenuItem) -> Bool) -> [MenuItem] {
        tabs + menu(tabs: tabs, hidden: hidden, order: order, permitted: permitted)
    }

    /// The places below the bar's, in the person's order, then any they have not placed yet.
    static func menu(tabs: [MenuItem], hidden: Set<MenuItem>, order: [MenuItem],
                     permitted: (MenuItem) -> Bool) -> [MenuItem] {
        (order + MenuItem.allCases).reduce(into: [MenuItem]()) { list, item in
            guard !list.contains(item), !tabs.contains(item), !hidden.contains(item), permitted(item) else { return }
            list.append(item)
        }
    }

    /// The bar's last slot: the place showing now when it is not pinned, else the last one opened from the menu.
    static func switcher(current: MenuItem?, last: MenuItem?, pinned: [MenuItem]) -> MenuItem? {
        if let current, !pinned.contains(current) { return current }
        if let last, !pinned.contains(last) { return last }
        return nil
    }
}

/// Shared look for the floating bar, its action button and the menu: a frosted card with a hairline rim.
struct FloatingSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    func body(content: Content) -> some View {
        content
            // The shadow belongs to the surface alone, so rows and pills inside cast none.
            .background {
                shape.fill(Theme.card.opacity(0.55))
                    .background(.regularMaterial, in: shape)
                    .shadow(color: .black.opacity(0.10), radius: 16, y: 6)
            }
            .overlay(shape.strokeBorder(Theme.border, lineWidth: 1))
    }
}

/// The phone's only navigation, laid out like Linear: a floating capsule of pinned places that ends in
/// a switcher slot, then round Search and New job buttons on the same line. There is no side
/// menu and no system tab bar. Tapping the switcher slot goes to its place; tapping it again (or when
/// it is empty) opens `AppMenu`. The bar sits low, partly over the home indicator's margin.
struct AppBottomBar: View {
    /// One entry in a round button's long-press menu.
    struct QuickAction: Identifiable {
        let title: String
        let symbol: String
        var enabled = true
        let run: () -> Void
        var id: String { title }
    }

    /// What the field outbox is doing, worn by the Search button so a tech can see a change went through.
    enum Sync: Equatable {
        case syncing(Int)
        case waiting(Int)
        case needsReview(Int)
    }

    let pinned: [MenuItem]
    let switcher: MenuItem?
    /// The place showing right now (a MenuItem id or "more").
    let current: String
    let menuOpen: Bool
    let select: (MenuItem) -> Void
    let openMenu: () -> Void
    let search: () -> Void
    /// The + after Search: what it makes follows the screen showing (New customer on Customers).
    var create: (label: String, run: () -> Void)?
    var sync: Sync?
    /// Long-press menus, in sections: recent records on Search, quick creates on New job.
    var searchActions: [[QuickAction]] = []
    var newActions: [[QuickAction]] = []
    /// Search lives in the bar: when active the places and + give way to a field and a close button.
    var searchActive = false
    var searchQuery: Binding<String> = .constant("")
    var closeSearch: () -> Void = {}
    @FocusState private var fieldFocused: Bool
    @Namespace private var pill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Bumped per place on each tap, so only the tapped icon bounces.
    @State private var taps: [String: Int] = [:]

    var body: some View {
        Group {
            if searchActive { searchRow } else { placesRow }
        }
        .padding(.horizontal, 16)
    }

    /// The Search circle widens into this field; + becomes the close button.
    private var searchRow: some View {
        HStack(alignment: .center, spacing: AppBottomBar.gap) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.muted)
                TextField("Jobs, customers, invoices", text: searchQuery)
                    .font(Theme.font(16))
                    .focused($fieldFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if !searchQuery.wrappedValue.isEmpty {
                    Button { searchQuery.wrappedValue = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 32, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .foregroundStyle(Theme.foreground)
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .frame(height: AppBottomBar.circle)
            .frame(maxWidth: .infinity)
            .modifier(FloatingSurface(shape: Capsule()))
            .matchedGeometryEffect(id: "search", in: pill)
            .onAppear { fieldFocused = true }
            Button(action: closeSearch) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.foreground)
                    .frame(width: AppBottomBar.circle, height: AppBottomBar.circle)
                    .modifier(FloatingSurface(shape: Circle()))
                    .contentShape(Circle())
            }
            .buttonStyle(PressStyle())
            .matchedGeometryEffect(id: "trailing", in: pill)
            .accessibilityLabel("Close search")
        }
    }

    private var placesRow: some View {
        HStack(alignment: .center, spacing: AppBottomBar.gap) {
            HStack(spacing: 2) {
                ForEach(pinned) { item in slot(item) }
                switcherSlot
            }
            .padding(4)
            // The selection pill glides to the new place instead of jumping.
            .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82), value: current)
            .frame(maxWidth: .infinity)
            .modifier(FloatingSurface(shape: Capsule()))
            // The menu grows out of the capsule and covers it while open.
            .opacity(menuOpen ? 0 : 1)
            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
            circle("magnifyingglass", label: searchLabel, actions: searchActions, action: search)
                .overlay { syncRing }
                .overlay(alignment: .topTrailing) { syncBadge }
                .matchedGeometryEffect(id: "search", in: pill)
            if let create {
                circle("plus", label: create.label, actions: newActions, action: create.run)
                    .matchedGeometryEffect(id: "trailing", in: pill)
            }
        }
    }

    /// The round buttons' size; the capsule (4 + 42 + 4) is the same height so every edge lines up.
    static let circle: CGFloat = 50
    static let gap: CGFloat = 8
    /// How far the bar sits above the screen's bottom edge, into the home indicator's margin.
    static let bottomGap: CGFloat = 20

    /// A round button. Tap runs `action`; a long press opens `actions` as a menu.
    private func circle(_ symbol: String, label: String, actions: [[QuickAction]],
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.foreground)
                .frame(width: AppBottomBar.circle, height: AppBottomBar.circle)
                .modifier(FloatingSurface(shape: Circle()))
                .contentShape(.contextMenuPreview, Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .contextMenu {
            ForEach(actions.indices, id: \.self) { index in
                Section {
                    ForEach(actions[index]) { item in
                        Button(action: item.run) { Label(item.title, systemImage: item.symbol) }
                            .disabled(!item.enabled)
                    }
                }
            }
        }
        .accessibilityLabel(label)
    }

    private var searchLabel: String {
        switch sync {
        case .syncing(let count): "Search. Syncing \(count) change\(count == 1 ? "" : "s")"
        case .waiting(let count): "Search. \(count) change\(count == 1 ? "" : "s") waiting to sync"
        case .needsReview(let count): "Search. \(count) change\(count == 1 ? "" : "s") couldn't sync"
        case nil: "Search"
        }
    }

    /// A green arc that runs around Search while changes are going up.
    @ViewBuilder private var syncRing: some View {
        if case .syncing = sync {
            SyncRing(reduceMotion: reduceMotion)
                .frame(width: AppBottomBar.circle + 4, height: AppBottomBar.circle + 4)
                .allowsHitTesting(false)
        }
    }

    /// How many changes are still on this phone; red when the server refused some.
    @ViewBuilder private var syncBadge: some View {
        switch sync {
        case .waiting(let count), .needsReview(let count):
            let refused = { if case .needsReview = sync { true } else { false } }()
            Text("\(count)")
                .font(Theme.monoFont(12, weight: .medium))
                .foregroundStyle(refused ? Color.white : Theme.foreground)
                .frame(minWidth: 20, minHeight: 20)
                .padding(.horizontal, count > 9 ? 4 : 0)
                .background(refused ? Theme.destructive : Theme.warningSurface, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.background, lineWidth: 2))
                .offset(x: 4, y: -4)
                .transition(.scale.combined(with: .opacity))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        default:
            EmptyView()
        }
    }

    private func tap(_ item: MenuItem) {
        if current != item.rawValue {
            UISelectionFeedbackGenerator().selectionChanged()
            if !reduceMotion { taps[item.rawValue, default: 0] += 1 }
        }
        select(item)
    }

    private func slot(_ item: MenuItem) -> some View {
        let here = current == item.rawValue
        return Button { tap(item) } label: {
            Image(systemName: item.symbol)
                .symbolVariant(here ? .fill : .none)
                .font(.system(size: 18, weight: .medium))
                .symbolEffect(.bounce.down, value: taps[item.rawValue] ?? 0)
                .foregroundStyle(Theme.foreground)
                .frame(maxWidth: .infinity).frame(height: AppBottomBar.circle - 8)
                .background { if here { selectionPill } }
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(item.tabTitle)
        .accessibilityAddTraits(here ? .isSelected : [])
    }

    /// One pill shared by every slot, so selection slides between them.
    private var selectionPill: some View {
        Capsule().fill(Theme.fill).matchedGeometryEffect(id: "selection", in: pill)
    }

    private var switcherSlot: some View {
        let here = switcher.map { current == $0.rawValue } ?? false
        return Button {
            if let switcher, !here { tap(switcher) } else { openMenu() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: switcher?.symbol ?? "square.grid.2x2")
                    .symbolVariant(here ? .fill : .none)
                    .font(.system(size: 18, weight: .medium))
                    .symbolEffect(.bounce.down, value: switcher.flatMap { taps[$0.rawValue] } ?? 0)
                    // A new place in the slot crossfades its icon rather than popping.
                    .contentTransition(.symbolEffect(.replace))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
            .foregroundStyle(Theme.foreground)
            .frame(maxWidth: .infinity).frame(height: AppBottomBar.circle - 8)
            .background { if here { selectionPill } }
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(switcher.map { here ? "\($0.title), open menu" : $0.title } ?? "Menu")
        .accessibilityAddTraits(here ? .isSelected : [])
        .accessibilityAction(named: "Open menu", openMenu)
    }
}

/// An arc that circles the Search button while the outbox sends. Reduce Motion holds it still.
private struct SyncRing: View {
    let reduceMotion: Bool
    @State private var spin = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.28)
            .stroke(Theme.success, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .rotationEffect(.degrees(spin ? 360 : 0))
            .animation(reduceMotion ? nil : .linear(duration: 1.1).repeatForever(autoreverses: false), value: spin)
            .onAppear { spin = true }
    }
}

/// The job this person is on right now, floating above the bar (the in-app twin of the Live
/// Activity). A soft pulse marks it live; a tap opens the job.
struct CurrentJobChip: View {
    let job: Job
    let customer: String
    let open: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Theme.success.opacity(0.25))
                        .frame(width: 22, height: 22)
                        .scaleEffect(pulse ? 1 : 0.5)
                        .opacity(pulse ? 0 : 1)
                    StatusRing(status: job.status)
                }
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(job.title)
                        .font(Theme.font(15, weight: .medium))
                        .lineLimit(1)
                    Text("\(job.status.statusLabel) · \(customer)")
                        .font(Theme.font(13))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
            .foregroundStyle(Theme.foreground)
            .padding(.leading, 14)
            .padding(.trailing, 16)
            .frame(minHeight: 52)
            .modifier(FloatingSurface(shape: Capsule()))
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .padding(.horizontal, 16)
        .accessibilityLabel("Current job, \(job.title), \(job.status.statusLabel), \(customer)")
        .accessibilityHint("Opens the job")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

/// The pop-up menu over the bar (Linear's): the business on top with its switcher and an edit
/// button, then every place, then Settings and Search. Edit turns the menu into `AppMenuEditor`.
struct AppMenu: View {
    /// The screen width; the menu matches the bar's capsule, and editing widens it to the gutters.
    let width: CGFloat
    /// Round buttons beside the capsule (Search, and + when there is something to create).
    var circles: CGFloat = 2
    let places: [MenuItem]
    let local: [LocalWorkspaceSection]
    /// The place showing right now (a MenuItem id or "more").
    let current: String
    let open: (MenuItem) -> Void
    let openLocal: (LocalWorkspaceSection) -> Void
    let manageBusinesses: () -> Void
    let settings: () -> Void
    let search: () -> Void
    let close: () -> Void
    @EnvironmentObject private var session: SessionController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editing = false
    @State private var rowsHeight: CGFloat = 0
    @State private var moreBelow = false

    /// As wide as the bar's capsule, so the menu reads as the capsule opening up.
    private var capsuleWidth: CGFloat {
        width - 32 - circles * (AppBottomBar.circle + AppBottomBar.gap)
    }

    private var businessName: String { session.activeOrganization?.name ?? "Business" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if editing {
                AppMenuEditor { withAnimation(animation) { editing = false } }
            } else {
                header
                Rectangle().fill(Theme.border).frame(height: 1).padding(.horizontal, 12)
                // Sized to its rows, so a short menu sits at its own height and a long one scrolls inside
                // the room it has. The lower edge fades only while there is more below.
                ScrollView {
                    rows.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowsHeight = $0 }
                }
                .frame(maxHeight: rowsHeight > 0 ? rowsHeight : nil)
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y + geometry.containerSize.height < geometry.contentSize.height - 1
                } action: { _, more in moreBelow = more }
                .mask {
                    VStack(spacing: 0) {
                        Color.black
                        LinearGradient(colors: [.black, .black.opacity(moreBelow ? 0 : 1)], startPoint: .top, endPoint: .bottom)
                            .frame(height: 28)
                    }
                }
            }
        }
        // The editor takes all the room it is given, so long lists can be dragged end to end.
        .frame(width: max(editing ? width - 32 : capsuleWidth, 0))
        .frame(maxHeight: editing ? .infinity : nil, alignment: .top)
        .foregroundStyle(Theme.foreground)
        // Nothing inside, scrolled or not, draws outside the card's rounded edge.
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .modifier(FloatingSurface(shape: RoundedRectangle(cornerRadius: 30, style: .continuous)))
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, close)
        #if DEBUG
        .task { if PaperPreview.enabled, PaperPreview.screen == "app-menu-edit" { editing = true } }
        #endif
    }

    private var animation: Animation { reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.9) }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(places) { item in
                row(item.title, symbol: item.symbol, here: current == item.rawValue) { open(item) }
            }
            ForEach(local, id: \.self) { section in
                row(section.title, symbol: section.moreSymbol, here: false) { openLocal(section) }
            }
            row("Settings", symbol: "gearshape", here: false, action: settings)
            row("Search", symbol: "magnifyingglass", here: false, action: search)
        }
        .padding(8)
    }

    /// Every business this person belongs to, the current one checked, then Add a business.
    private var businessItems: [ThorbisMenuItem] {
        session.organizations.map { organization in
            let current = organization.id == session.activeOrganization?.id
            return ThorbisMenuItem(organization.name, isSelected: current) {
                close()
                guard !current else { return }
                Task { await session.selectOrganization(id: organization.id) }
            }
        } + [ThorbisMenuItem("Add a business", icon: "plus", action: manageBusinesses)]
    }

    /// The business and its switcher. Every business this person belongs to is one tap away.
    private var header: some View {
        HStack(spacing: 8) {
            ThorbisMenu(items: businessItems, title: "Switch business",
                        accessibilityLabel: "\(businessName). Switch business") {
                HStack(spacing: 10) {
                    Avatar(name: businessName, size: 28, fill: Theme.fill)
                    Text(businessName)
                        .font(Theme.font(17, weight: .medium))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
                .foregroundStyle(Theme.foreground)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            Spacer(minLength: 0)
            Button { withAnimation(animation) { editing = true } } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.foreground)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Edit menu")
        }
        .padding(.leading, 20)
        .padding(.trailing, 10)
        .padding(.vertical, 8)
    }

    /// One icon and a label; the place showing now sits on a soft pill.
    private func row(_ title: String, symbol: String, here: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .symbolVariant(here ? .fill : .none)
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 26)
                Text(title)
                    .font(Theme.font(17, weight: here ? .medium : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.foreground)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background {
                if here { RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.fill) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityAddTraits(here ? .isSelected : [])
    }
}

/// Arranging the bar and the menu in place. One list: the bar's places, a divider, then the menu's.
/// Drag a place across the divider to move it between the bar and the menu, or tap its pin.
/// Every change is saved as it happens, so the bar behind already shows it.
struct AppMenuEditor: View {
    let done: () -> Void
    @EnvironmentObject private var layout: MenuLayout
    @EnvironmentObject private var session: SessionController

    private enum Entry: Hashable, Identifiable {
        case place(MenuItem)
        case divider
        var id: String {
            switch self {
            case .place(let item): item.rawValue
            case .divider: "divider"
            }
        }
    }

    private func permitted(_ item: MenuItem) -> Bool { item.permitted(session) }
    private var bar: [MenuItem] { layout.visibleTabs(session) }
    private var menu: [MenuItem] {
        AppMenuContent.menu(tabs: layout.tabs, hidden: layout.hidden, order: layout.menuOrder, permitted: permitted)
    }
    private var entries: [Entry] { bar.map(Entry.place) + [.divider] + menu.map(Entry.place) }
    /// Members follow an owner's company layout; only owners change it.
    private var editable: Bool { layout.source != .company || session.can("organization.settings.edit") }
    private var barFull: Bool { layout.tabs.count >= MenuLayout.maxTabs }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Edit menu").font(Theme.font(17, weight: .medium))
                Spacer(minLength: 0)
                Button("Done", action: done)
                    .font(Theme.font(17, weight: .medium))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .padding(.leading, 20)
            .padding(.trailing, 12)
            .padding(.vertical, 8)
            Rectangle().fill(Theme.border).frame(height: 1).padding(.horizontal, 12)
            list
        }
        .foregroundStyle(Theme.foreground)
    }

    private var list: some View {
        List {
            Section {
                ForEach(entries) { entry in entryView(entry) }
                    .onMove { source, destination in
                        if editable { move(from: source, to: destination) }
                    }
            } header: {
                caption("Bottom bar · up to \(MenuLayout.maxTabs)")
            } footer: {
                if !editable { caption(lockedNote) }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 44)
        .environment(\.editMode, Binding.constant(editable ? EditMode.active : EditMode.inactive))
    }

    private var lockedNote: String {
        "Set by \(session.activeOrganization?.name ?? "your company"). Ask an owner to change it."
    }

    @ViewBuilder private func entryView(_ entry: Entry) -> some View {
        switch entry {
        case .place(let item): row(item)
        case .divider: divider
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(Theme.font(13))
            .foregroundStyle(Theme.muted)
            .textCase(nil)
    }

    private var divider: some View {
        caption("In the menu")
            .padding(.top, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .moveDisabled(true)
            .accessibilityAddTraits(.isHeader)
    }

    private func row(_ item: MenuItem) -> some View {
        let inBar = bar.contains(item)
        let canPin = inBar || (!barFull && layout.canBeTab(item))
        return HStack(spacing: 14) {
            Image(systemName: item.symbol)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 26)
            Text(item.title)
                .font(Theme.font(17))
                .lineLimit(1)
            Spacer(minLength: 0)
            if editable {
                Button { toggle(item) } label: {
                    Image(systemName: inBar ? "minus.circle" : "plus.circle")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(canPin ? Theme.foreground : Theme.muted.opacity(0.5))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(!canPin)
                .accessibilityLabel(inBar ? "Move \(item.title) to the menu" : "Add \(item.title) to the bar")
            }
        }
        .frame(minHeight: 44)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 4))
    }

    private func move(from source: IndexSet, to destination: Int) {
        var list = entries
        list.move(fromOffsets: source, toOffset: destination)
        apply(list)
    }

    private func toggle(_ item: MenuItem) {
        var list = entries.filter { $0 != .place(item) }
        let divider = list.firstIndex(of: .divider) ?? list.endIndex
        // Out of the bar it heads the menu; into the bar it goes last.
        list.insert(.place(item), at: bar.contains(item) ? divider + 1 : divider)
        withAnimation { apply(list) }
    }

    private func places(in entries: ArraySlice<Entry>) -> [MenuItem] {
        entries.compactMap { entry -> MenuItem? in
            guard case .place(let item) = entry else { return nil }
            return item
        }
    }

    private func apply(_ list: [Entry]) {
        let split = list.firstIndex(of: .divider) ?? list.endIndex
        layout.arrange(bar: places(in: list[..<split]), menu: places(in: list[split...]), permitted: permitted)
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

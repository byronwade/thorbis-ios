import SwiftUI

/// Jobs and customers opened on this phone, and the words searched for, newest first, for search.
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
    /// Words this person searched for and then opened something from, newest first.
    @Published private(set) var searches: [String] = []
    private var owner: String?
    private var byOwner: [String: [Item]]
    private var searchesByOwner: [String: [String]]
    private let key = "thorbis.recentItems.v2"
    private let searchKey = "thorbis.recentSearches.v1"

    private init() {
        UserDefaults.standard.removeObject(forKey: "thorbis.recentItems.v1")
        byOwner = UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([String: [Item]].self, from: $0) } ?? [:]
        searchesByOwner = UserDefaults.standard.data(forKey: searchKey).flatMap { try? JSONDecoder().decode([String: [String]].self, from: $0) } ?? [:]
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
        searches = owner.flatMap { searchesByOwner[$0] } ?? []
    }

    /// Kept when a search led somewhere, not on every keystroke.
    func recordSearch(_ text: String) {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let owner, !words.isEmpty else { return }
        searches.removeAll { $0.caseInsensitiveCompare(words) == .orderedSame }
        searches.insert(words, at: 0)
        searches = Array(searches.prefix(6))
        searchesByOwner[owner] = searches
        saveSearches()
    }

    /// Search's Clear: only this person and workspace's searches.
    func clearSearches() {
        guard let owner else { return }
        searches = []
        searchesByOwner[owner] = nil
        saveSearches()
    }

    /// Search's Clear on recently opened records: only this person and workspace's.
    func clearOpened() {
        guard let owner else { return }
        items = []
        byOwner[owner] = nil
        save()
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
        searches = []
        searchesByOwner = [:]
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: searchKey)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(byOwner) { UserDefaults.standard.set(data, forKey: key) }
    }

    private func saveSearches() {
        if let data = try? JSONEncoder().encode(searchesByOwner) { UserDefaults.standard.set(data, forKey: searchKey) }
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
            guard !list.contains(item), !tabs.contains(item), !hidden.contains(item),
                  MenuItem.listed(item, permitted: permitted) else { return }
            list.append(item)
        }
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

/// The phone's only navigation (redesign 2026-10-31): a floating labeled tab bar, like Linear and
/// Jobber. The person's pinned places (Today · Jobs · Customers by default; owners and office staff
/// get their role's bar, and anyone can rearrange it) then a fixed More, each an icon over an 11pt
/// label. The tab showing sits on a brand-tinted pill with icon and label in brand. Search stays a
/// separate round button to the right. New moved to the screen headers' + circle. More is a real
/// screen listing every other place, so nothing hides behind a switcher.
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
        case needsChecking
    }

    let pinned: [MenuItem]
    /// The place showing right now (a MenuItem id or "more").
    let current: String
    let select: (MenuItem) -> Void
    /// Opens More (also where any place not pinned lives).
    let openMore: () -> Void
    let search: () -> Void
    var sync: Sync?
    /// Long-press Search: recent records, and the outbox when it holds anything.
    var searchActions: [[QuickAction]] = []
    /// Search lives in the bar: when active the tabs give way to a field and a close button.
    var searchActive = false
    var searchQuery: Binding<String> = .constant("")
    var closeSearch: () -> Void = {}
    /// Return in the field: search opens its top hit.
    var submitSearch: () -> Void = {}
    @FocusState private var fieldFocused: Bool
    @Namespace private var pill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Bumped per place on each tap, so only the tapped icon bounces.
    @State private var taps: [String: Int] = [:]

    static let moreID = "more"

    var body: some View {
        Group {
            if searchActive { searchRow } else { tabsRow }
        }
        .padding(.horizontal, 16)
    }

    /// The Search circle widens into this field; the close button takes the circle's place.
    private var searchRow: some View {
        HStack(alignment: .center, spacing: AppBottomBar.gap) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.muted)
                TextField("Street, name, phone or number", text: searchQuery)
                    .font(Theme.font(16))
                    .focused($fieldFocused)
                    .submitLabel(.search)
                    .onSubmit(submitSearch)
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
            .matchedGeometryEffect(id: "search", in: pill)
            .accessibilityLabel("Close search")
        }
    }

    private var tabsRow: some View {
        HStack(alignment: .center, spacing: AppBottomBar.gap) {
            HStack(spacing: 0) {
                ForEach(pinned) { item in
                    tab(id: item.rawValue, title: item.tabTitle, symbol: item.symbol) { tap(item) }
                }
                tab(id: Self.moreID, title: "More", symbol: "ellipsis.circle", here: moreHere) {
                    if !moreHere { UISelectionFeedbackGenerator().selectionChanged() }
                    if !reduceMotion { taps[Self.moreID, default: 0] += 1 }
                    openMore()
                }
            }
            .padding(4)
            // The selection pill glides to the new tab instead of jumping.
            .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82), value: current)
            .frame(maxWidth: .infinity)
            .modifier(FloatingSurface(shape: Capsule()))
            searchCircle
                .accessibilityIdentifier("bottom-bar-search")
                .overlay { syncRing }
                .overlay(alignment: .topTrailing) { syncBadge }
                .matchedGeometryEffect(id: "search", in: pill)
        }
        // The bar's words stay one size so five tabs fit; the large content viewer shows them big.
        .dynamicTypeSize(...DynamicTypeSize.large)
    }

    /// More is selected on its own list and on any place that is not pinned.
    private var moreHere: Bool { !pinned.contains { $0.rawValue == current } }

    /// The bar's height: the capsule (4 + 48 + 4) and the Search circle line up.
    static let circle: CGFloat = 56
    static let gap: CGFloat = 8
    /// How far the bar sits above the screen's bottom edge, into the home indicator's margin.
    static let bottomGap: CGFloat = 20

    private var searchCircle: some View {
        Button(action: search) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Theme.foreground)
                .frame(width: AppBottomBar.circle, height: AppBottomBar.circle)
                .modifier(FloatingSurface(shape: Circle()))
                .contentShape(.contextMenuPreview, Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .contextMenu {
            ForEach(searchActions.indices, id: \.self) { index in
                Section {
                    ForEach(searchActions[index]) { item in
                        Button(action: item.run) { Label(item.title, systemImage: item.symbol) }
                            .disabled(!item.enabled)
                    }
                }
            }
        }
        .accessibilityLabel(searchLabel)
        .accessibilityShowsLargeContentViewer { Label("Search", systemImage: "magnifyingglass") }
    }

    private var searchLabel: String {
        switch sync {
        case .syncing(let count): count == 0 ? "Search. Syncing saved work" : "Search. Syncing \(count) saved item\(count == 1 ? "" : "s")"
        case .waiting(let count): "Search. \(count) saved item\(count == 1 ? "" : "s") waiting to sync"
        case .needsReview(let count): "Search. \(count) saved item\(count == 1 ? "" : "s") need\(count == 1 ? "s" : "") attention"
        case .needsChecking: "Search. Saved work needs checking"
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
                .font(Theme.monoFont(12, weight: .semibold))
                .foregroundStyle(refused ? Color.white : Theme.foreground)
                .frame(minWidth: 20, minHeight: 20)
                .padding(.horizontal, count > 9 ? 4 : 0)
                .background(refused ? Theme.destructiveFill : Theme.warningSurface, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.background, lineWidth: 2))
                .offset(x: 4, y: -4)
                .transition(.scale.combined(with: .opacity))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        case .needsChecking:
            Image(systemName: "exclamationmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 20, height: 20)
                .background(Theme.destructiveFill, in: Circle())
                .overlay(Circle().strokeBorder(Theme.background, lineWidth: 2))
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

    /// One labeled tab: icon over word. The showing tab sits on the brand-tinted pill in brand.
    private func tab(id: String, title: String, symbol: String, here explicit: Bool? = nil,
                     action: @escaping () -> Void) -> some View {
        let here = explicit ?? (current == id)
        return Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .symbolVariant(here ? .fill : .none)
                    .font(.system(size: 18, weight: .medium))
                    .symbolEffect(.bounce.down, value: taps[id] ?? 0)
                    .frame(height: 22)
                Text(title)
                    .font(Theme.font(12, weight: here ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(here ? Theme.brandText : Theme.muted)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity).frame(height: AppBottomBar.circle - 8)
            .background { if here { selectionPill } }
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        // One element per tab: the word is the label, so tests and VoiceOver see one "Jobs", not two.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(here ? [.isButton, .isSelected] : .isButton)
        .accessibilityShowsLargeContentViewer { Label(title, systemImage: symbol) }
        .accessibilityIdentifier("bottom-bar-\(id)")
    }

    /// One pill shared by every tab, so selection slides between them.
    private var selectionPill: some View {
        Capsule().fill(Theme.brandSurface).matchedGeometryEffect(id: "selection", in: pill)
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

/// The job this person is on right now, docked on the bar (the in-app twin of the Live Activity).
/// The title, then the status as a word with a soft live pulse on its dot, then who. A tap opens
/// the job. It sits on `BarGround`, so it never floats over a list's rows.
struct CurrentJobChip: View {
    let job: Job
    let customer: String
    let open: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        let tint = StatusWord.jobTint(job.status) ?? Theme.muted
        Button(action: open) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(tint.opacity(0.3))
                        .frame(width: 18, height: 18)
                        .scaleEffect(pulse ? 1 : 0.4)
                        .opacity(pulse ? 0 : 1)
                    Circle().fill(tint).frame(width: 8, height: 8)
                }
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(job.title)
                        .font(Theme.font(15, weight: .medium))
                        .lineLimit(2)
                    Text("\(job.status.statusLabel) · \(customer)")
                        .font(Theme.font(13))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text("Open").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
            }
            .foregroundStyle(Theme.foreground)
            .padding(.leading, 16)
            .padding(.trailing, 18)
            .padding(.vertical, 6)
            .frame(minHeight: 52)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(PressStyle())
        // Docked above the bar: past the first accessibility size it would take a third of the
        // screen, so it stops growing there and wraps to two lines instead of cutting words.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .padding(.horizontal, 16)
        .accessibilityLabel("Current job, \(job.title), \(job.status.statusLabel), \(customer)")
        .accessibilityHint("Opens the job")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

/// The ground under the bar while the current-job chip rides on it: the cream canvas with a short
/// fade at the top, reaching the screen's bottom edge. Rows scroll under it like under a toolbar,
/// never under a floating card, and each place's root reserves its height (`barReserve`).
struct BarGround: View {
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [Theme.background.opacity(0), Theme.background], startPoint: .top, endPoint: .bottom)
                .frame(height: 16)
            Theme.background
        }
        .padding(.top, -16)
        .padding(.bottom, -(AppBottomBar.bottomGap + 40))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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

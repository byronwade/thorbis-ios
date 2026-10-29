import SwiftUI

/// Jobs and customers opened on this phone, newest first, for the side menu's Recents.
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

/// The phone's side menu, laid out like the Claude app: the app title and one round button,
/// a plain list, Pinned and Recents, then the account and New job along the bottom.
/// Search is not in that bar. It sits above the list and shows when the menu is pulled down.
/// The tab bar stays; this is a second way to get anywhere in one tap.
struct SideMenu: View {
    let open: (MenuItem) -> Void
    let openRecent: (RecentItems.Item) -> Void
    let search: () -> Void
    let newJob: () -> Void
    let settings: () -> Void
    let close: () -> Void
    /// The place showing right now (a MenuItem id, "more" or "search").
    var current: String = ""
    var switchWorkspace: (() -> Void)? = nil
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var layout: MenuLayout
    @ObservedObject private var recents = RecentItems.shared
    /// Search lives above `menu`. The menu starts at the top, so a pull downward uncovers search.
    @State private var scroll = ScrollPosition(id: "menu", anchor: .top)

    private var pinned: [MenuItem] { layout.visibleTabs(session) }
    private var everything: [MenuItem] {
        // Like More, only places that can open on their own. The tab-bar items are Pinned.
        MenuItem.allCases.filter { !pinned.contains($0) && !layout.hidden.contains($0) && $0.permitted(session) && $0.route != nil }
    }
    private var accountName: String {
        let name = session.user?.name ?? ""
        return name.isEmpty ? "Account" : name
    }
    /// Screenshot fixture: start with the pull-down search already in view.
    private var showSearch: Bool {
        #if DEBUG
        PaperPreview.enabled && PaperPreview.screen == "side-menu-search"
        #else
        false
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        searchField
                            .id("search")
                        menu
                            .id("menu")
                            // Taller than the viewport, so the search row rests above the fold
                            // and a pull downward brings it in.
                            .frame(minHeight: geometry.size.height, alignment: .top)
                    }
                    .padding(.horizontal, 8)
                }
                .scrollPosition($scroll, anchor: .top)
                .scrollIndicators(.hidden)
            }
            footer
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.surface.ignoresSafeArea())
        .task { reveal(showSearch ? "search" : "menu") }
        // MA-04: VoiceOver's escape gesture closes the menu; the app behind is hidden meanwhile.
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { close() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Button { switchWorkspace?() } label: {
                HStack(spacing: 6) {
                    Text("Thorbis")
                        .font(Theme.font(30, weight: .medium))
                        .tracking(-0.6)
                        .lineLimit(1)
                    if switchWorkspace != nil {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .allowsHitTesting(switchWorkspace != nil)
            .accessibilityLabel(switchWorkspace == nil
                ? "Thorbis"
                : "Thorbis, \(session.activeOrganization?.name ?? "company"). Switch company")
            Spacer(minLength: 0)
            PaperCircleButton(symbol: "magnifyingglass", label: "Search", action: search)
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    /// The field that a downward pull uncovers. It opens company search; it is not a second list filter.
    private var searchField: some View {
        Button(action: search) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                Text("Search")
                Spacer(minLength: 0)
            }
            .font(Theme.font(16))
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Search")
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var menu: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !pinned.isEmpty {
                section("Pinned")
                ForEach(pinned) { item in row(item) }
                Color.clear.frame(height: 8)
            }
            ForEach(everything) { item in row(item) }
            if !recents.items.isEmpty {
                section("Recents")
                ForEach(recents.items) { item in recent(item) }
            }
        }
        .padding(.bottom, 12)
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: settings) {
                Avatar(name: accountName, size: 40)
                    .overlay(Circle().strokeBorder(Theme.border, lineWidth: 1))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Settings, \(accountName)")
            Spacer(minLength: 0)
            if session.can("job.create", feature: "jobs") {
                Button(action: newJob) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 15, weight: .medium))
                        Text("New job")
                    }
                    .font(Theme.font(15, weight: .medium))
                    .foregroundStyle(Theme.onInk)
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .background(Theme.ink, in: Capsule())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("New job")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Theme.surface)
    }

    private func reveal(_ id: String) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { scroll.scrollTo(id: id, anchor: .top) }
    }

    private func section(_ title: String) -> some View {
        Text(title)
            .font(Theme.font(13, weight: .medium))
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 12)
            .padding(.top, 22)
            .padding(.bottom, 6)
            .accessibilityAddTraits(.isHeader)
    }

    /// A plain row: one dark icon and a label, with room between rows. The current place is 500 and filled.
    private func row(_ item: MenuItem) -> some View {
        let here = current == item.rawValue
        return Button { open(item) } label: {
            HStack(spacing: 16) {
                Image(systemName: item.symbol)
                    .symbolVariant(here ? .fill : .none)
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.foreground)
                    .frame(width: 28)
                Text(item.title)
                    .font(Theme.font(17, weight: here ? .medium : .regular))
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityAddTraits(here ? .isSelected : [])
    }

    private func recent(_ item: RecentItems.Item) -> some View {
        Button { openRecent(item) } label: {
            HStack(spacing: 16) {
                Image(systemName: item.kind == .job ? "briefcase" : "person")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 28)
                Text(item.title)
                    .font(Theme.font(17))
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityLabel("\(item.kind == .job ? "Job" : "Customer"), \(item.title)")
        .accessibilityHint(item.subtitle)
    }
}

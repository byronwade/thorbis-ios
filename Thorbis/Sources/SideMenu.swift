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

/// A side menu like the web app's sidebar (and ChatGPT's): workspace and search at the top, the
/// pinned tabs, every other place, recent jobs and customers, then New job and settings. The tab
/// bar stays; this is a second way to get anywhere in one tap.
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

    private var pinned: [MenuItem] { layout.visibleTabs(session) }
    private var everything: [MenuItem] {
        // Like More, only places that can open on their own; Schedule, Jobs and Customers are tabs.
        MenuItem.allCases.filter { !pinned.contains($0) && !layout.hidden.contains($0) && $0.permitted(session) && $0.route != nil }
    }

    /// design.thorbis.com MA-02: workspace, places (current one marked), recents, then the thumb
    /// zone: search and the one ink New job, and the person opening Settings.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The company is a control when there is another to switch to.
            Button { switchWorkspace?() } label: {
                HStack(spacing: 10) {
                    Text(String((session.activeOrganization?.name ?? "T").prefix(1)).uppercased())
                        .font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.onInk)
                        .frame(width: 28, height: 28)
                        .background(Theme.ink, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .dynamicTypeSize(...DynamicTypeSize.large)
                    Text(session.activeOrganization?.name ?? "Thorbis").font(Theme.font(17, weight: .medium))
                        .lineLimit(1)
                    if switchWorkspace != nil {
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 48).contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .allowsHitTesting(switchWorkspace != nil)
            .accessibilityLabel(switchWorkspace == nil ? "Company: \(session.activeOrganization?.name ?? "Thorbis")"
                                                       : "Company: \(session.activeOrganization?.name ?? "Thorbis"). Switch company")
            .padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(pinned) { item in row(item) }
                    if !everything.isEmpty {
                        section("More places")
                        ForEach(everything) { item in row(item) }
                    }
                    if !recents.items.isEmpty {
                        section("Recent")
                        ForEach(recents.items) { item in
                            Button { openRecent(item) } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: item.kind == .job ? "briefcase" : "person")
                                        .font(.system(size: 15)).foregroundStyle(Theme.muted).frame(width: 22)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.title).font(Theme.font(15)).foregroundStyle(Theme.foreground).lineLimit(1)
                                        Text(item.subtitle).font(Theme.font(13)).foregroundStyle(Theme.muted).lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 12)
                                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(RowPressStyle())
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)

            // Thumb zone (MA-06): search fills the row, the one ink commit beside it.
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Button(action: search) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                            Text("Search")
                            Spacer(minLength: 0)
                        }
                        .font(Theme.font(15)).foregroundStyle(Theme.muted)
                        .padding(.horizontal, 14).frame(height: 44)
                        .background(Theme.fill, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(PressStyle())
                    if session.can("job.create", feature: "jobs") {
                        Button(action: newJob) {
                            Label("New job", systemImage: "plus")
                                .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.onInk)
                                .padding(.horizontal, 16).frame(height: 44)
                                .background(Theme.ink, in: Capsule())
                                .fixedSize()
                        }
                        .buttonStyle(PressStyle())
                    }
                }
                Button(action: settings) {
                    HStack(spacing: 10) {
                        Text(initials(session.user?.name ?? session.user?.email ?? ""))
                            .font(Theme.font(12, weight: .medium)).foregroundStyle(Theme.foreground)
                            .frame(width: 30, height: 30).background(Theme.fill, in: Circle())
                            .dynamicTypeSize(...DynamicTypeSize.large)
                        Text(session.user?.name ?? "Account").font(Theme.font(15, weight: .medium)).lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "gearshape").foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, 6)
                    .frame(minHeight: 48).contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
                .accessibilityLabel("Settings, \(session.user?.name ?? "account")")
            }
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 4)
            .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.surface.ignoresSafeArea())
        // MA-04: VoiceOver's escape gesture closes the menu; the app behind is hidden meanwhile.
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { close() }
    }

    private func section(_ title: String) -> some View {
        Text(title).font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
            .padding(.horizontal, 12).padding(.top, 18).padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }

    /// MA-02: the current place sits in the well fill with its word at 500 and its mark filled;
    /// the others are 400 with a quiet place hue on the mark only.
    private func row(_ item: MenuItem) -> some View {
        let here = current == item.rawValue
        return Button { open(item) } label: {
            HStack(spacing: 14) {
                Image(systemName: item.symbol).symbolVariant(here ? .fill : .none)
                    .font(.system(size: 17)).foregroundStyle(here ? Theme.foreground : item.tint).frame(width: 22)
                Text(item.title).font(Theme.font(15, weight: here ? .medium : .regular))
                    .foregroundStyle(Theme.foreground)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 46)
            .background(here ? Theme.fill : .clear, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityAddTraits(here ? .isSelected : [])
    }
}

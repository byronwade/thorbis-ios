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
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var layout: MenuLayout
    @ObservedObject private var recents = RecentItems.shared

    private var pinned: [MenuItem] { layout.visibleTabs(session) }
    private var everything: [MenuItem] {
        // Like More, only places that can open on their own; Schedule, Jobs and Customers are tabs.
        MenuItem.allCases.filter { !pinned.contains($0) && !layout.hidden.contains($0) && $0.permitted(session) && $0.route != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(String((session.activeOrganization?.name ?? "T").prefix(1)))
                    .font(Theme.font(12, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 24, height: 24).background(Theme.brand, in: RoundedRectangle(cornerRadius: 7))
                Text(session.activeOrganization?.name ?? "Thorbis").font(Theme.font(17, weight: .semibold)).lineLimit(1)
                Spacer()
                PaperCircleButton(symbol: "magnifyingglass", label: "Search", action: search)
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(pinned) { item in row(item) }
                    if !everything.isEmpty {
                        section("More places")
                        ForEach(everything) { item in row(item) }
                    }
                    if !recents.items.isEmpty {
                        section("Recent")
                        ForEach(recents.items) { item in
                            Button { openRecent(item) } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.title).font(Theme.font(15)).foregroundStyle(Theme.foreground).lineLimit(1)
                                    Text(item.subtitle).font(Theme.font(12)).foregroundStyle(Theme.muted).lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .padding(.horizontal, 16)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.bottom, 12)
            }

            HStack(spacing: 10) {
                Button(action: settings) {
                    HStack(spacing: 10) {
                        Text(initials(session.user?.name ?? session.user?.email ?? ""))
                            .font(Theme.font(12, weight: .semibold)).foregroundStyle(Theme.brandText)
                            .frame(width: 32, height: 32).background(Theme.brandSurface, in: Circle())
                        Text(session.user?.name ?? "Account").font(Theme.font(15, weight: .medium)).lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "gearshape").foregroundStyle(Theme.muted)
                    }
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
                if session.can("job.create", feature: "jobs") {
                    Button(action: newJob) {
                        Label("New job", systemImage: "plus").font(Theme.font(15, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 16).frame(height: 44)
                            .background(Theme.brand, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 0.5) }
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.surface.ignoresSafeArea())
    }

    private func section(_ title: String) -> some View {
        Text(title).font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 4)
    }

    private func row(_ item: MenuItem) -> some View {
        Button { open(item) } label: {
            HStack(spacing: 14) {
                Image(systemName: item.symbol).font(.system(size: 17)).foregroundStyle(item.tint).frame(width: 22)
                Text(item.title).font(Theme.font(15, weight: .medium))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

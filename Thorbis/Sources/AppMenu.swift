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

    /// Search's × on one recent search: removes those words from this person and workspace's list.
    func removeSearch(_ text: String) {
        guard let owner else { return }
        searches.removeAll { $0.caseInsensitiveCompare(text) == .orderedSame }
        searchesByOwner[owner] = searches.isEmpty ? nil : searches
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

/// Places in the phone drawer: pinned places first, then every other permitted place.
enum AppMenuContent {
    static func places(tabs: [MenuItem], hidden: Set<MenuItem>, order: [MenuItem] = [],
                       permitted: (MenuItem) -> Bool) -> [MenuItem] {
        tabs + menu(tabs: tabs, hidden: hidden, order: order, permitted: permitted)
    }

    /// The places below the pinned ones, in the person's order, then any they have not placed yet.
    static func menu(tabs: [MenuItem], hidden: Set<MenuItem>, order: [MenuItem],
                     permitted: (MenuItem) -> Bool) -> [MenuItem] {
        (order + MenuItem.allCases).reduce(into: [MenuItem]()) { list, item in
            guard !list.contains(item), !tabs.contains(item), !hidden.contains(item),
                  MenuItem.listed(item, permitted: permitted) else { return }
            list.append(item)
        }
    }

}

/// Helper types the phone shell shares (the floating tab bar they were born in was replaced by
/// the side drawer on 2026-10-31): a create or shortcut entry, and what the field outbox is doing.
enum AppBottomBar {
    /// One entry in a create menu or a long-press menu.
    struct QuickAction: Identifiable {
        let title: String
        let symbol: String
        var enabled = true
        let run: () -> Void
        var id: String { title }
    }

    /// What the field outbox is doing, worn by the menu circle and the drawer's saved-work row so a
    /// tech can see a change went through.
    enum Sync: Equatable {
        case syncing(Int)
        case waiting(Int)
        case needsReview(Int)
        case needsChecking

        /// The words, for VoiceOver and the drawer row.
        var words: String {
            switch self {
            case .syncing(let count): count == 0 ? "Syncing saved work" : "Syncing \(count) saved item\(count == 1 ? "" : "s")"
            case .waiting(let count): "\(count) saved item\(count == 1 ? "" : "s") waiting to sync"
            case .needsReview(let count): "\(count) saved item\(count == 1 ? "" : "s") need\(count == 1 ? "s" : "") attention"
            case .needsChecking: "Saved work needs checking"
            }
        }

        /// Refused or unreadable work needs the person, so it raises the drawer's dot.
        var needsPerson: Bool {
            switch self {
            case .needsReview, .needsChecking: true
            default: false
            }
        }
    }
}

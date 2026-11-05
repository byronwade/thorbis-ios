import Combine
import Foundation

/// A device-local favorite is a whitelisted native destination, never a URL or a stored label.
@MainActor
final class ScopedPageFavorites: ObservableObject {
    struct Page: Codable, Hashable, Identifiable {
        enum Kind: String, Codable { case menu, local }
        let kind: Kind
        let value: String
        var id: String { "\(kind.rawValue)|\(value)" }

        var isKnown: Bool {
            switch kind {
            case .menu: MenuItem(rawValue: value) != nil
            case .local: LocalWorkspaceSection(rawValue: value) != nil
            }
        }
    }
    private struct Owner: Codable {
        let actorID: String
        let organizationID: String
        let origin: String
    }
    static let storageKey = "thorbis.pageFavorites.v1"
    static let shared = ScopedPageFavorites()
    @Published private(set) var pages: [Page] = []
    private let defaults: UserDefaults
    private var scope: ScopedRecordFavorites.Scope?
    private var byOwner: [String: [Page]]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        byOwner = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([String: [Page]].self, from: $0) } ?? [:]
    }

    func bind(_ candidate: ScopedRecordFavorites.Scope?) {
        let next = candidate.flatMap { value in
            value.actorID.isEmpty || value.organizationID.isEmpty || value.origin.isEmpty ? nil : value
        }
        guard next != scope else { return }
        scope = next
        let stored = next.flatMap { ownerKey($0).flatMap { byOwner[$0] } } ?? []
        pages = stored.reduce(into: [Page]()) { result, page in
            if page.isKnown && !result.contains(page) && result.count < 100 { result.append(page) }
        }
    }

    func isBound(to expected: ScopedRecordFavorites.Scope?) -> Bool { expected != nil && scope == expected }

    /// Every consumer supplies current reachability; stored identifiers never grant access.
    func visible(allowed: (Page) -> Bool) -> [Page] {
        guard scope != nil else { return [] }
        return pages.filter { $0.isKnown && allowed($0) }
    }

    @discardableResult func toggle(_ page: Page, allowed: (Page) -> Bool) -> Bool {
        guard let scope, let key = ownerKey(scope), page.isKnown, allowed(page) else { return false }
        if let index = pages.firstIndex(of: page) { pages.remove(at: index) }
        else {
            guard pages.count < 100 else { return false }
            pages.append(page)
        }
        byOwner[key] = pages
        if let data = try? JSONEncoder().encode(byOwner) { defaults.set(data, forKey: Self.storageKey) }
        return true
    }

    func retireAPI(origin: String?, generation: UUID, savedCopyRevision: UUID) {
        guard let scope, scope.origin == origin, scope.apiGeneration == generation,
              scope.savedCopyRevision == savedCopyRevision else { return }
        bind(nil)
    }

    func retireSession(generation: UUID, authority: UUID) {
        guard let scope, scope.sessionGeneration == generation, scope.authorityRevision == authority else { return }
        bind(nil)
    }

    private func ownerKey(_ scope: ScopedRecordFavorites.Scope) -> String? {
        let owner = Owner(actorID: scope.actorID.lowercased(), organizationID: scope.organizationID.lowercased(), origin: scope.origin)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(owner))?.base64EncodedString()
    }
}

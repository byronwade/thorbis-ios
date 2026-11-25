import Combine
import SwiftUI

/// Device-local favorites contain record identities only. A label may appear only after a fresh
/// authorized read in the currently bound actor, workspace, origin and authority context.
@MainActor
final class ScopedRecordFavorites: ObservableObject {
    enum Kind: String, Codable, Hashable { case job, customer }
    struct Entry: Codable, Hashable, Identifiable {
        let kind: Kind
        let id: String
        var identity: String { "\(kind.rawValue)|\(id)" }
    }
    struct Visible: Identifiable, Equatable {
        let entry: Entry
        let title: String
        var id: String { entry.identity }
    }
    struct Scope: Equatable {
        let actorID: String
        let organizationID: String
        let origin: String
        let sessionGeneration: UUID
        let authorityRevision: UUID
        let apiGeneration: UUID
        let savedCopyRevision: UUID
    }
    private struct Owner: Codable {
        let actorID: String
        let organizationID: String
        let origin: String
    }

    static let storageKey = "thorbis.recordFavorites.v1"
    static let shared = ScopedRecordFavorites(defaults: launchDefaults())
    @Published private(set) var entries: [Entry] = []
    @Published private(set) var visible: [Visible] = []
    private let defaults: UserDefaults
    private var scope: Scope?
    private var request = UUID()
    private var byOwner: [String: [Entry]]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.byOwner = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([String: [Entry]].self, from: $0) } ?? [:]
    }

    /// The app's favorites live in the standard defaults. A UI test that has to carry a favorite
    /// across a relaunch names its own suite (`--paper-preview-favorites-suite <uuid>`), so what it
    /// saves never reaches another test and no other test's favorites reach it.
    private static func launchDefaults() -> UserDefaults {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if PaperPreview.enabled, let index = args.firstIndex(of: "--paper-preview-favorites-suite"),
           args.indices.contains(index + 1), let uuid = UUID(uuidString: args[index + 1]),
           let suite = UserDefaults(suiteName: "thorbis.preview.favorites.\(uuid.uuidString)") {
            return suite
        }
        #endif
        return .standard
    }

    static func currentScope(session: SessionController, api: APIClient) -> Scope? {
        guard session.phase == .ready, let actor = session.user?.id,
              let organization = session.activeOrganization?.id, let origin = api.normalizedOrigin else { return nil }
        return Scope(actorID: actor, organizationID: organization, origin: origin,
                     sessionGeneration: session.generation, authorityRevision: session.authorityRevision,
                     apiGeneration: api.requestGeneration, savedCopyRevision: api.savedCopyScopeRevision)
    }

    func isBound(to expected: Scope?) -> Bool { expected != nil && scope == expected }

    /// A different API client must not retire the active account's favorites.
    func retireAPI(origin: String?, generation: UUID, savedCopyRevision: UUID) {
        guard let scope, scope.origin == origin, scope.apiGeneration == generation,
              scope.savedCopyRevision == savedCopyRevision else { return }
        bind(nil)
    }

    /// Session epochs are unique to the owning controller; compare the old value before clearing.
    func retireSession(generation: UUID, authority: UUID) {
        guard let scope, scope.sessionGeneration == generation, scope.authorityRevision == authority else { return }
        bind(nil)
    }

    /// Call on every verified identity, authority, API generation, origin or saved-copy scope change.
    /// Passing nil immediately hides all records when there is no verified session.
    func bind(_ candidate: Scope?) {
        let next = candidate.flatMap { scope in
            scope.actorID.isEmpty || scope.organizationID.isEmpty || scope.origin.isEmpty ? nil : scope
        }
        guard next != scope else { return }
        request = UUID()
        scope = next
        visible = []
        entries = next.flatMap { ownerKey($0).flatMap { byOwner[$0] } } ?? []
    }

    /// Makes the bound scope hold the record as a favorite (`favorite: true`) or not (`false`). The
    /// caller states the outcome it wants, so a row that reads "Add to favorites" can never remove
    /// one and "Remove from favorites" can never add one, even if the row was drawn from older
    /// state. When the store already holds that state nothing changes: names already checked stay
    /// visible and nothing is written. A newly added record stays invisible until refresh succeeds.
    /// Returns whether the store now holds the requested state; false when no scope is bound, the
    /// id is not a record id, or 100 favorites are already saved.
    @discardableResult func set(_ kind: Kind, id: String, favorite: Bool) -> Bool {
        guard let scope, !scope.actorID.isEmpty, !scope.organizationID.isEmpty,
              !scope.origin.isEmpty, let uuid = UUID(uuidString: id), let key = ownerKey(scope) else { return false }
        let entry = Entry(kind: kind, id: uuid.uuidString.lowercased())
        let index = entries.firstIndex(of: entry)
        guard favorite != (index != nil) else { return true }
        if let index { entries.remove(at: index) }
        else {
            guard entries.count < 100 else { return false }
            entries.append(entry)
        }
        request = UUID()
        visible = []
        byOwner[key] = entries
        if let data = try? JSONEncoder().encode(byOwner) { defaults.set(data, forKey: Self.storageKey) }
        return true
    }

    /// Revalidate whenever the sidebar presents favorites. `isCurrent` must compare the verified
    /// session and all authority/feature state; `canOpen` must check this kind's current capability.
    /// A denied, stale, offline or mismatched read never exposes a stored title or route.
    func refresh(api: APIClient, canOpen: @escaping @MainActor (Kind) -> Bool,
                 isCurrent: @escaping @MainActor () -> Bool) async {
        request = UUID()
        let token = request
        visible = []
        guard let expected = scope else { return }
        func current() -> Bool {
            !Task.isCancelled && request == token && scope == expected && isCurrent() &&
                api.normalizedOrigin == expected.origin && api.requestGeneration == expected.apiGeneration &&
                api.savedCopyScopeRevision == expected.savedCopyRevision
        }
        func discardIfCurrentRequest() {
            if request == token { visible = [] }
        }
        func removeUnavailable() {
            visible.removeAll { !canOpen($0.entry.kind) }
        }
        guard current() else { discardIfCurrentRequest(); return }
        for entry in entries {
            guard current() else { discardIfCurrentRequest(); return }
            removeUnavailable()
            guard canOpen(entry.kind) else { continue }
            do {
                let title: String
                switch entry.kind {
                case .job:
                    let job = try await api.fieldJob(entry.id, requireFresh: true)
                    guard current() else { discardIfCurrentRequest(); return }
                    removeUnavailable()
                    guard canOpen(entry.kind), job.id.lowercased() == entry.id,
                          job.organizationId.lowercased() == expected.organizationID.lowercased() else { continue }
                    title = job.title
                case .customer:
                    let customer = try await api.fieldCustomer(entry.id, requireFresh: true)
                    guard current() else { discardIfCurrentRequest(); return }
                    removeUnavailable()
                    guard canOpen(entry.kind), customer.id.lowercased() == entry.id,
                          customer.organizationId.lowercased() == expected.organizationID.lowercased() else { continue }
                    title = customer.name
                }
                guard current() else { discardIfCurrentRequest(); return }
                removeUnavailable()
                guard canOpen(entry.kind) else { continue }
                visible.append(Visible(entry: entry, title: title))
            } catch is CancellationError { discardIfCurrentRequest(); return }
            catch {
                guard current() else { discardIfCurrentRequest(); return }
                removeUnavailable()
            }
        }
    }

    private func ownerKey(_ scope: Scope) -> String? {
        let owner = Owner(actorID: scope.actorID.lowercased(), organizationID: scope.organizationID.lowercased(), origin: scope.origin)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(owner))?.base64EncodedString()
    }
}

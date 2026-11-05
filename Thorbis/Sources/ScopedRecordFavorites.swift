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
    static let shared = ScopedRecordFavorites()
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

    /// Adds or removes an identity; newly added records remain invisible until refresh succeeds.
    @discardableResult func toggle(_ kind: Kind, id: String) -> Bool {
        guard let scope, !scope.actorID.isEmpty, !scope.organizationID.isEmpty,
              !scope.origin.isEmpty, let uuid = UUID(uuidString: id), let key = ownerKey(scope) else { return false }
        let entry = Entry(kind: kind, id: uuid.uuidString.lowercased())
        request = UUID()
        visible = []
        if let index = entries.firstIndex(of: entry) { entries.remove(at: index) }
        else {
            guard entries.count < 100 else { return false }
            entries.append(entry)
        }
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
        guard current() else { return }
        for entry in entries {
            guard current() else { return }
            guard canOpen(entry.kind) else { continue }
            do {
                let title: String
                switch entry.kind {
                case .job:
                    let job = try await api.fieldJob(entry.id, requireFresh: true)
                    guard job.id.lowercased() == entry.id, job.organizationId.lowercased() == expected.organizationID.lowercased() else { continue }
                    title = job.title
                case .customer:
                    let customer = try await api.fieldCustomer(entry.id, requireFresh: true)
                    guard customer.id.lowercased() == entry.id, customer.organizationId.lowercased() == expected.organizationID.lowercased() else { continue }
                    title = customer.name
                }
                guard current() else { return }
                guard canOpen(entry.kind) else { continue }
                visible.append(Visible(entry: entry, title: title))
            } catch is CancellationError { return }
            catch { if !current() { return } }
        }
    }

    private func ownerKey(_ scope: Scope) -> String? {
        let owner = Owner(actorID: scope.actorID.lowercased(), organizationID: scope.organizationID.lowercased(), origin: scope.origin)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(owner))?.base64EncodedString()
    }
}

/// A record may be saved from either device class; saved identities are reauthorized before display.
struct FavoriteRecordButton: View {
    let kind: ScopedRecordFavorites.Kind
    let id: String
    let organizationID: String
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @ObservedObject private var favorites = ScopedRecordFavorites.shared

    private var context: ScopedRecordFavorites.Scope? { ScopedRecordFavorites.currentScope(session: session, api: api) }
    private var allowed: Bool {
        guard let context, context.organizationID.caseInsensitiveCompare(organizationID) == .orderedSame else { return false }
        switch kind {
        case .job: return session.can("job.view", feature: "jobs")
        case .customer: return session.can("customer.view", feature: "core_crm")
        }
    }
    private var selected: Bool {
        favorites.isBound(to: context) && favorites.entries.contains { $0.kind == kind && $0.id == id.lowercased() }
    }

    var body: some View {
        if allowed {
            Button {
                guard allowed, let context else { return }
                favorites.bind(context)
                favorites.toggle(kind, id: id)
            } label: {
                PaperCircleLabel(symbol: selected ? "star.fill" : "star", fill: Theme.card, bordered: true)
            }
            .buttonStyle(PressStyle())
            .disabled(!favorites.isBound(to: context))
            .accessibilityLabel(selected ? "Remove from favorites" : "Add to favorites")
            .accessibilityIdentifier("record-favorite-\(kind.rawValue)-\(id)")
            .onChange(of: context, initial: true) { favorites.bind(context) }
        }
    }
}

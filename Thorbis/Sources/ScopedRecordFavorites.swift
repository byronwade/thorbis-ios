import Combine
import Foundation

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

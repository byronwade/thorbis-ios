import Combine
import Foundation

/// Held prerequisite: no screen uses this until bounded, authorized full search is available.
/// Online-only until saved pages can be bound to the authority that produced them.
/// A terminal cursor is not a database snapshot.
@MainActor final class InvoicePageController: ObservableObject {
    @Published private(set) var items: [InvoiceRecord] = []
    @Published private(set) var error: String?
    @Published private(set) var loading = false
    var hasMore: Bool { started && nextCursor != nil }
    var isExhausted: Bool { started && nextCursor == nil }

    private let api: APIClient
    private let session: SessionController
    private var subscriptions = Set<AnyCancellable>()
    private var revision = UUID()
    private var sessionGeneration: UUID?
    private var authorityRevision: UUID?
    private var actorID: String?
    private var organizationID: String?
    private var generation: UUID?
    private var savedCopyScope: String?
    private var savedCopyScopeRevision: UUID?
    private var origin: String?
    private var nextCursor: String?
    private var started = false
    private var seenCursors = Set<String>()
    private var seenIDs = Set<UUID>()

    init(api: APIClient, session: SessionController) {
        self.api = api; self.session = session
        session.$authorityRevision.dropFirst().sink { [weak self] _ in MainActor.assumeIsolated { self?.retire() } }.store(in: &subscriptions)
        session.$phase.dropFirst().sink { [weak self] _ in MainActor.assumeIsolated { self?.retire() } }.store(in: &subscriptions)
        session.$user.dropFirst().sink { [weak self] _ in MainActor.assumeIsolated { self?.retire() } }.store(in: &subscriptions)
        session.$activeOrganization.dropFirst().sink { [weak self] _ in MainActor.assumeIsolated { self?.retire() } }.store(in: &subscriptions)
        api.$requestGeneration.dropFirst().sink { [weak self] _ in MainActor.assumeIsolated { self?.retire() } }.store(in: &subscriptions)
        api.$baseURL.dropFirst().sink { [weak self] _ in MainActor.assumeIsolated { self?.retire() } }.store(in: &subscriptions)
        api.$savedCopyScope.dropFirst().sink { [weak self] _ in MainActor.assumeIsolated { self?.retire() } }.store(in: &subscriptions)
    }

    func retire() {
        revision = UUID(); sessionGeneration = nil; authorityRevision = nil
        actorID = nil; organizationID = nil; generation = nil; savedCopyScope = nil
        savedCopyScopeRevision = nil; origin = nil; nextCursor = nil; started = false
        seenCursors = []; seenIDs = []; items = []; error = nil; loading = false
    }

    /// Owners must call this immediately when their own context or authority lease changes.
    func ownerContextChanged(isCurrent: @MainActor () -> Bool) {
        if !current(isCurrent) { retire() }
    }

    func start(isCurrent: @escaping @MainActor () -> Bool) async {
        retire()
        guard isCurrent(), session.can("invoice.view", feature: "invoicing"),
              let actor = session.user?.id, let organization = session.activeOrganization?.id,
              UUID(uuidString: actor) != nil, UUID(uuidString: organization) != nil,
              let scope = api.savedCopyScope, scope == SavedCopies.scope(actorID: actor, organizationID: organization),
              let origin = api.normalizedOrigin else {
            error = "Invoice access is not available."
            return
        }
        actorID = actor; organizationID = organization; savedCopyScope = scope; self.origin = origin
        savedCopyScopeRevision = api.savedCopyScopeRevision; generation = api.requestGeneration
        sessionGeneration = session.generation; authorityRevision = session.authorityRevision
        await loadNext(isCurrent: isCurrent)
    }

    func loadNext(isCurrent: @escaping @MainActor () -> Bool) async {
        guard !loading, generation != nil else { return }
        guard current(isCurrent) else { retire(); return }
        guard !started || nextCursor != nil else { return }
        let requestRevision = revision, cursor = nextCursor
        loading = true
        defer { if revision == requestRevision { loading = false } }
        do {
            let response = try await api.fieldInvoicePage(cursor: cursor)
            try Task.checkCancellation()
            guard revision == requestRevision else { return }
            guard current(isCurrent) else { retire(); return }
            let provenance = response.provenance
            guard provenance.origin == origin, provenance.savedCopyScope == savedCopyScope,
                  provenance.savedCopyScopeRevision == savedCopyScopeRevision,
                  provenance.generation == generation, provenance.path == "/v1/invoices", provenance.cursor == cursor,
                  provenance.source == .urlSession(cacheBypassed: true),
                  let organizationID, let organization = UUID(uuidString: organizationID) else {
                throw Problem(title: "Invoice page could not be verified.", status: nil, detail: nil)
            }
            var pageIDs = Set<UUID>()
            var previous = cursor.flatMap(UUID.init(uuidString:))?.uuidString
            for invoice in response.value.items {
                guard let id = UUID(uuidString: invoice.id), UUID(uuidString: invoice.organizationId) == organization,
                      !seenIDs.contains(id), pageIDs.insert(id).inserted,
                      previous.map({ id.uuidString < $0 }) ?? true else {
                    throw Problem(title: "Invoice page could not be verified.", status: nil, detail: nil)
                }
                previous = id.uuidString
            }
            if let next = response.value.nextCursor {
                guard let nextID = UUID(uuidString: next), let last = response.value.items.last,
                      UUID(uuidString: last.id) == nextID, cursor.flatMap(UUID.init(uuidString:)) != nextID,
                      !seenCursors.contains(nextID.uuidString) else {
                    throw Problem(title: "Invoice page could not be verified.", status: nil, detail: nil)
                }
            }
            if let cursor, let id = UUID(uuidString: cursor) { seenCursors.insert(id.uuidString) }
            seenIDs.formUnion(pageIDs); items.append(contentsOf: response.value.items)
            nextCursor = response.value.nextCursor; started = true; error = nil
        } catch is CancellationError {
            if revision == requestRevision && !current(isCurrent) { retire() }
        } catch {
            guard revision == requestRevision else { return }
            guard current(isCurrent) else { retire(); return }
            if let status = (error as? Problem)?.status, [401, 403].contains(status) {
                retire(); self.error = "Invoice access is no longer available."; return
            }
            self.error = "Couldn't load invoices. Try again."
        }
    }

    private func current(_ isCurrent: @MainActor () -> Bool) -> Bool {
        isCurrent() && session.can("invoice.view", feature: "invoicing") &&
        session.generation == sessionGeneration && session.authorityRevision == authorityRevision &&
        session.user?.id == actorID && session.activeOrganization?.id == organizationID &&
        api.requestGeneration == generation && api.savedCopyScope == savedCopyScope &&
        api.savedCopyScopeRevision == savedCopyScopeRevision && api.normalizedOrigin == origin
    }
}

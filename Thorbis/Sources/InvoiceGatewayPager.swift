import Combine
import Foundation

/// Held prototype, not used by any screen. Gateway search is a separate online
/// source; even a terminal cursor is partial until projection freshness,
/// permissions and parity with invoice-name search are qualified.
@MainActor final class InvoiceGatewayPager: ObservableObject {
    @Published private(set) var items: [ServerSearchResult] = []
    @Published private(set) var error: String?
    @Published private(set) var loading = false
    let isPartial = true

    private let api: APIClient
    private let session: SessionController
    private var subscriptions = Set<AnyCancellable>()
    private var sessionGeneration: UUID?
    private var authorityRevision: UUID?
    private var actorID: String?
    private var organizationID: String?
    private var revision = UUID()
    private var generation: UUID?
    private var savedCopyScope: String?
    private var origin: String?
    private var query: String?
    private var nextCursor: String?
    private var started = false
    private var seenCursors = Set<String>()
    private var seenIDs = Set<String>()

    init(api: APIClient, session: SessionController) {
        self.api = api
        self.session = session
        session.$authorityRevision.dropFirst().sink { [weak self] _ in MainActor.assumeIsolated { self?.retire() } }.store(in: &subscriptions)
        session.$phase.dropFirst().sink { [weak self] _ in MainActor.assumeIsolated { self?.retire() } }.store(in: &subscriptions)
        session.$user.dropFirst().sink { [weak self] _ in MainActor.assumeIsolated { self?.retire() } }.store(in: &subscriptions)
        session.$activeOrganization.dropFirst().sink { [weak self] _ in MainActor.assumeIsolated { self?.retire() } }.store(in: &subscriptions)
        api.$requestGeneration.dropFirst().sink { [weak self] _ in MainActor.assumeIsolated { self?.retire() } }.store(in: &subscriptions)
        api.$baseURL.dropFirst().sink { [weak self] _ in MainActor.assumeIsolated { self?.retire() } }.store(in: &subscriptions)
        api.$savedCopyScope.dropFirst().sink { [weak self] _ in MainActor.assumeIsolated { self?.retire() } }.store(in: &subscriptions)
    }

    static func customerQuery(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "type:invoice customer:\"\(escaped)\""
    }

    /// Caller must immediately retire when its own session/authority lease changes.
    func retire() {
        revision = UUID(); generation = nil; savedCopyScope = nil; origin = nil; query = nil
        sessionGeneration = nil; authorityRevision = nil; actorID = nil; organizationID = nil
        items = []; nextCursor = nil; seenCursors = []; seenIDs = []; started = false
        error = nil; loading = false
    }

    func start(customer: String, isCurrent: @escaping @MainActor () -> Bool) async {
        retire()
        let term = customer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, term.utf16.count <= 128, !term.hasPrefix("\""),
              !term.contains(where: { $0.isNewline }),
              isCurrent(), session.can("invoice.view", feature: "invoicing"),
              session.can("customer.view", feature: "core_crm"),
              let actor = session.user?.id, let organization = session.activeOrganization?.id,
              let scope = api.savedCopyScope, scope == SavedCopies.scope(actorID: actor, organizationID: organization),
              let origin = api.normalizedOrigin else {
            error = "This search needs current access and a shorter name that doesn't begin with a quote."
            return
        }
        savedCopyScope = scope; self.origin = origin; generation = api.requestGeneration
        actorID = actor; organizationID = organization; sessionGeneration = session.generation
        authorityRevision = session.authorityRevision
        query = Self.customerQuery(term)
        await loadNext(isCurrent: isCurrent)
    }

    func loadNext(isCurrent: @escaping @MainActor () -> Bool) async {
        guard !loading, let query else { return }
        guard current(isCurrent) else { retire(); return }
        guard !started || nextCursor != nil else { return }
        let requestRevision = revision
        let cursor = nextCursor
        loading = true
        defer { if revision == requestRevision { loading = false } }
        do {
            let page: ServerSearchPage = try await api.send("GET", "/v1/search", queryItems: [
                URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: "50")
            ], cursor: cursor, requireFresh: true)
            try Task.checkCancellation()
            guard revision == requestRevision else { return }
            guard current(isCurrent) else { retire(); return }
            var pageIDs = Set<String>()
            for item in page.items {
                guard item.sourceId == "invoices", item.resultType == "invoice",
                      let id = UUID(uuidString: item.entityId)?.uuidString.lowercased(),
                      !seenIDs.contains(id), pageIDs.insert(id).inserted else {
                    throw Problem(title: "Search results could not be verified.", status: nil, detail: nil)
                }
            }
            if let next = page.nextCursor, next.isEmpty || next == cursor || seenCursors.contains(next) {
                throw Problem(title: "Search page could not be verified.", status: nil, detail: nil)
            }
            if let cursor { seenCursors.insert(cursor) }
            seenIDs.formUnion(pageIDs); items.append(contentsOf: page.items)
            nextCursor = page.nextCursor; started = true; error = nil
        } catch is CancellationError {
            if revision == requestRevision && !current(isCurrent) { retire() }
            return
        } catch {
            guard revision == requestRevision else { return }
            guard current(isCurrent) else { retire(); return }
            if let status = (error as? Problem)?.status, [401, 403].contains(status) {
                retire()
                self.error = "Search access is no longer available."
                return
            }
            self.error = "Couldn't load more search results. Try again."
        }
    }

    /// A search hit is not authority to open an invoice. Fetch the exact
    /// resource live and recheck the complete session lease before returning it.
    func authorizedInvoice(id: String, isCurrent: @escaping @MainActor () -> Bool) async -> InvoiceRecord? {
        guard current(isCurrent) else { retire(); return nil }
        guard items.contains(where: { $0.entityId == id }) else { return nil }
        let requestRevision = revision
        do {
            let invoice = try await SavedCopies.$liveOnly.withValue(true) { try await api.liveFieldInvoice(id) }
            try Task.checkCancellation()
            guard revision == requestRevision else { return nil }
            guard current(isCurrent), invoice.id == id, invoice.organizationId == organizationID else {
                retire(); return nil
            }
            return invoice
        } catch {
            if revision == requestRevision, let status = (error as? Problem)?.status,
               [401, 403, 404].contains(status) { retire() }
            return nil
        }
    }

    private func current(_ isCurrent: @MainActor () -> Bool) -> Bool {
        isCurrent() && session.can("invoice.view", feature: "invoicing") &&
        session.can("customer.view", feature: "core_crm") && session.generation == sessionGeneration &&
        session.authorityRevision == authorityRevision && session.user?.id == actorID &&
        session.activeOrganization?.id == organizationID && api.requestGeneration == generation &&
        api.savedCopyScope == savedCopyScope && api.normalizedOrigin == origin
    }
}

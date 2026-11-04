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
    private var revision = UUID()
    private var generation: UUID?
    private var savedCopyScope: String?
    private var origin: String?
    private var query: String?
    private var nextCursor: String?
    private var started = false
    private var seenCursors = Set<String>()
    private var seenIDs = Set<String>()

    init(api: APIClient) { self.api = api }

    static func customerQuery(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "type:invoice customer:\"\(escaped)\""
    }

    /// Caller must immediately retire when its own session/authority lease changes.
    func retire() {
        revision = UUID(); generation = nil; savedCopyScope = nil; origin = nil; query = nil
        items = []; nextCursor = nil; seenCursors = []; seenIDs = []; started = false
        error = nil; loading = false
    }

    func start(customer: String, isCurrent: @escaping @MainActor () -> Bool) async {
        retire()
        let term = customer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, term.count <= 100, !term.contains(where: { $0.isNewline }),
              isCurrent(), let scope = api.savedCopyScope, let origin = api.normalizedOrigin else {
            error = "Search needs a valid customer name and current access."
            return
        }
        savedCopyScope = scope; self.origin = origin; generation = api.requestGeneration
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
            guard revision == requestRevision, current(isCurrent) else { return }
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
            return
        } catch {
            guard revision == requestRevision, current(isCurrent) else { return }
            error = "Couldn't load more search results. Try again."
        }
    }

    private func current(_ isCurrent: @MainActor () -> Bool) -> Bool {
        isCurrent() && api.requestGeneration == generation && api.savedCopyScope == savedCopyScope && api.normalizedOrigin == origin
    }
}

import Foundation

/// Held page assembly, not an authorization grant. A caller must still bind
/// these pages to its transport lifecycle, current authority and record digests.
/// This does not replace the existing job invoice loader or offline behavior.
struct JobInvoiceEvidenceAccumulator {
    struct Result {
        let records: [InvoiceRecord]
        let pages: [InvoiceEvidencePage]
        let allNetwork: Bool
    }
    enum Failure: Error { case invalidPage }
    private let scope: InvoiceReadScope
    private var pages: [InvoiceEvidencePage] = []
    private var records: [InvoiceRecord] = []
    private var ids = Set<UUID>()
    private var cursors = Set<String>()
    private var next: String?
    private var complete = false
    private var invalid = false

    init(scope: InvoiceReadScope) { self.scope = scope }

    mutating func append(_ page: InvoiceEvidencePage, current: InvoiceReadScope?) throws {
        do {
            guard !invalid, !complete, scope == current, pages.count < 100,
                  page.cursor == next else { throw Failure.invalidPage }
            if let next = page.nextCursor {
                guard !next.isEmpty, cursors.insert(next).inserted else { throw Failure.invalidPage }
            }
            for record in page.items {
                guard let id = UUID(uuidString: record.id), ids.insert(id).inserted,
                      UUID(uuidString: record.organizationId) == scope.organization,
                      UUID(uuidString: record.customerId) == scope.customer,
                      record.jobId.flatMap(UUID.init(uuidString:)) == scope.job else { throw Failure.invalidPage }
            }
            records.append(contentsOf: page.items)
            pages.append(page)
            next = page.nextCursor
            complete = next == nil
        } catch {
            invalid = true
            throw error
        }
    }

    func finish(current: InvoiceReadScope?) throws -> Result {
        guard !invalid, complete, !pages.isEmpty, scope == current else { throw Failure.invalidPage }
        return .init(records: records, pages: pages, allNetwork: pages.allSatisfy { $0.source == .network })
    }
}

import Foundation
import Combine

struct InvoiceRecord { let id, jobId, organizationId, customerId: String }
struct EstimateRecord { let id, organizationId, customerId: String }
final class APIClient {}
struct JobDocumentRead<Record> {
    let scope: JobDocumentScope
    let records: [Record]
    let freshIDs: Set<String>
    let isComplete: Bool
    let unavailableIDs: [String]
    init(scope: JobDocumentScope, records: [Record], freshIDs: Set<String>, isComplete: Bool,
         unavailableIDs: [String] = [], kind: String) {
        self.scope = scope; self.records = records; self.freshIDs = freshIDs
        self.isComplete = isComplete; self.unavailableIDs = unavailableIDs
    }
}
extension JobDocumentRead where Record == InvoiceRecord {
    func replacing(_ invoice: InvoiceRecord) -> Self { self }
}
enum JobInvoiceMemory {
    static func ids(_ job: String) -> [String] { [] }
    static func replace(_ ids: [String], jobID: String) {}
    static func remember(_ id: String, jobID: String) {}
}
enum JobDetailCache { static func save(invoices: [InvoiceRecord], jobID: String) {} }
@MainActor enum JobDocumentsLoader {
    static var pending: [CheckedContinuation<JobDocumentRead<InvoiceRecord>?, Never>] = []
    static func estimates(scope: JobDocumentScope, api: APIClient, retaining: JobDocumentRead<EstimateRecord>?,
                          isCurrent: @escaping @MainActor () -> Bool) async -> JobDocumentRead<EstimateRecord>? { nil }
    static func invoices(scope: JobDocumentScope, api: APIClient, knownIDs: [String], retaining: JobDocumentRead<InvoiceRecord>?,
                         isCurrent: @escaping @MainActor () -> Bool) async -> JobDocumentRead<InvoiceRecord>? {
        await withCheckedContinuation { pending.append($0) }
    }
}

// JOB_DOCUMENT_PUBLICATION_SOURCE

@main struct Probe {
    @MainActor static func main() async {
        let scope = JobDocumentScope(jobID: "job", organizationID: "org", customerID: "customer")
        let good = InvoiceRecord(id: "invoice", jobId: "job", organizationId: "org", customerId: "customer")
        let foreign = InvoiceRecord(id: "invoice", jobId: "other", organizationId: "org", customerId: "customer")
        let wrongCustomer = InvoiceRecord(id: "invoice", jobId: "job", organizationId: "org", customerId: "other")
        let wrongOrg = InvoiceRecord(id: "invoice", jobId: "job", organizationId: "other", customerId: "customer")
        precondition(scope.contains(good) && !scope.contains(foreign) && !scope.contains(wrongCustomer) && !scope.contains(wrongOrg))
        let estimate = EstimateRecord(id: "estimate", organizationId: "org", customerId: "customer")
        precondition(scope.contains(estimate, requestedID: "estimate") && !scope.contains(estimate, requestedID: "other"))
        print("PASS exact document identity")

        let collection = JobDocumentCollections(), api = APIClient()
        var current = true
        let pending = Task { await collection.loadInvoices(scope: scope, api: api) { current } }
        while JobDocumentsLoader.pending.count < 1 { await Task.yield() }
        current = false
        JobDocumentsLoader.pending.removeFirst().resume(returning: .init(scope: scope, records: [good], freshIDs: [good.id], isComplete: true, kind: "invoices"))
        let retiredPublished = await pending.value
        precondition(!retiredPublished && collection.invoices == nil)
        print("PASS retired authority prevents publication")

        current = true
        let first = Task { await collection.loadInvoices(scope: scope, api: api) { current } }
        while JobDocumentsLoader.pending.count < 1 { await Task.yield() }
        let second = Task { await collection.loadInvoices(scope: scope, api: api) { current } }
        while JobDocumentsLoader.pending.count < 2 { await Task.yield() }
        let newer = InvoiceRecord(id: "new", jobId: "job", organizationId: "org", customerId: "customer")
        JobDocumentsLoader.pending.removeLast().resume(returning: .init(scope: scope, records: [newer], freshIDs: [newer.id], isComplete: true, kind: "invoices"))
        let secondPublished = await second.value
        precondition(secondPublished)
        JobDocumentsLoader.pending.removeFirst().resume(returning: .init(scope: scope, records: [good], freshIDs: [good.id], isComplete: true, kind: "invoices"))
        let firstPublished = await first.value
        precondition(!firstPublished && collection.invoices?.records.first?.id == "new")
        print("PASS superseded response cannot replace newer read")
    }
}

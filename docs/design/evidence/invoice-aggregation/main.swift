import Foundation

enum InvoiceResponseSource: Equatable { case network, savedCopy }
struct InvoiceRecord { let id: String; let organizationId: String; let customerId: String; let jobId: String? }
struct InvoiceEvidencePage { let items: [InvoiceRecord]; let cursor: String?; let nextCursor: String?; let source: InvoiceResponseSource }
struct InvoiceReadScope: Equatable { let actor: UUID, organization: UUID, job: UUID, customer: UUID; let origin: String; let session: UUID, authority: UUID, transport: UUID }
let org = UUID(), customer = UUID(), job = UUID()
let scope = InvoiceReadScope(actor: UUID(), organization: org, job: job, customer: customer, origin: "https://example.com", session: UUID(), authority: UUID(), transport: UUID())
let invoice = InvoiceRecord(id: UUID().uuidString, organizationId: org.uuidString, customerId: customer.uuidString, jobId: job.uuidString)
func expectFailure(_ body: () throws -> Void) { do { try body(); fatalError("expected failure") } catch {} }
var pages = JobInvoiceEvidenceAccumulator(scope: scope)
try pages.append(.init(items: [invoice], cursor: nil, nextCursor: "next", source: .savedCopy), current: scope)
try pages.append(.init(items: [], cursor: "next", nextCursor: nil, source: .network), current: scope)
let result = try pages.finish(current: scope)
precondition(result.records.count == 1 && !result.allNetwork)
expectFailure { try pages.append(.init(items: [], cursor: nil, nextCursor: nil, source: .network), current: scope) }
var duplicate = JobInvoiceEvidenceAccumulator(scope: scope)
try duplicate.append(.init(items: [invoice], cursor: nil, nextCursor: "next", source: .network), current: scope)
expectFailure { try duplicate.append(.init(items: [invoice], cursor: "next", nextCursor: nil, source: .network), current: scope) }
var wrongCursor = JobInvoiceEvidenceAccumulator(scope: scope)
expectFailure { try wrongCursor.append(.init(items: [], cursor: "unexpected", nextCursor: nil, source: .network), current: scope) }
var wrongCustomer = JobInvoiceEvidenceAccumulator(scope: scope)
let wrong = InvoiceRecord(id: UUID().uuidString, organizationId: org.uuidString, customerId: UUID().uuidString, jobId: job.uuidString)
expectFailure { try wrongCustomer.append(.init(items: [wrong], cursor: nil, nextCursor: nil, source: .network), current: scope) }
var cycle = JobInvoiceEvidenceAccumulator(scope: scope)
try cycle.append(.init(items: [], cursor: nil, nextCursor: "a", source: .network), current: scope)
expectFailure { try cycle.append(.init(items: [], cursor: "a", nextCursor: "a", source: .network), current: scope) }
var incomplete = JobInvoiceEvidenceAccumulator(scope: scope)
try incomplete.append(.init(items: [], cursor: nil, nextCursor: "a", source: .network), current: scope)
expectFailure { _ = try incomplete.finish(current: scope) }
let changed = InvoiceReadScope(actor: scope.actor, organization: scope.organization, job: scope.job, customer: scope.customer, origin: scope.origin, session: UUID(), authority: scope.authority, transport: scope.transport)
expectFailure { _ = try incomplete.finish(current: changed) }
var emptyCursor = JobInvoiceEvidenceAccumulator(scope: scope)
expectFailure { try emptyCursor.append(.init(items: [], cursor: nil, nextCursor: "", source: .network), current: scope) }
expectFailure { try emptyCursor.append(.init(items: [], cursor: nil, nextCursor: nil, source: .network), current: scope) }
var wrongJob = JobInvoiceEvidenceAccumulator(scope: scope)
let misplaced = InvoiceRecord(id: UUID().uuidString, organizationId: org.uuidString, customerId: customer.uuidString, jobId: UUID().uuidString)
expectFailure { try wrongJob.append(.init(items: [misplaced], cursor: nil, nextCursor: nil, source: .network), current: scope) }
var changedScope = JobInvoiceEvidenceAccumulator(scope: scope)
expectFailure { try changedScope.append(.init(items: [invoice], cursor: nil, nextCursor: nil, source: .network), current: changed) }
var network = JobInvoiceEvidenceAccumulator(scope: scope)
try network.append(.init(items: [invoice], cursor: nil, nextCursor: nil, source: .network), current: scope)
let networkResult = try network.finish(current: scope)
precondition(networkResult.allNetwork)
print("PASS: held invoice page aggregation")

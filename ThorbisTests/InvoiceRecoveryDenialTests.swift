import XCTest
@testable import Thorbis

@MainActor
final class InvoiceRecoveryDenialTests: XCTestCase {
    func testRecoveryRouteRetiresDeniedInvoiceAndRequiresCompleteLiveRevalidation() async throws {
        for denialInHistory in [false, true] {
            let invoiceID = UUID().uuidString.lowercased()
            let organizationID = "00000000-0000-4000-8000-000000000002"
            let body = #"{"id":"\#(invoiceID)","organizationId":"\#(organizationID)","customerId":"00000000-0000-4000-8000-000000000003","createdByUserId":"00000000-0000-4000-8000-000000000004","origin":"job_completion","sourceOperationKey":"fixture","status":"issued","lines":[{"id":"00000000-0000-4000-8000-00000000000c","description":"Service","quantity":1,"unitPrice":{"amount":10000,"currency":"USD"}}],"linesRevision":1,"amountPaid":0,"currency":"USD","createdAt":"2026-10-26T11:00:00Z","updatedAt":"2026-10-26T12:00:00Z"}"#
            let denial: URLProtocolFixture.Reply = .init(403, #"{"title":"Invoice access denied","status":403}"#)
            var replies: [URLProtocolFixture.Reply] = [.init(200, body), .init(200, #"{"items":[]}"#)]
            if denialInHistory { replies.append(.init(200, body)) }
            replies.append(denial)
            replies.append(URLProtocolFixture.offline)
            replies.append(contentsOf: [.init(200, body), .init(200, #"{"items":[]}"#)])
            let api = APIClient(session: URLProtocolFixture.session(replies), baseURL: "https://app.thorbis.com")
            api.savedCopyScope = UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: "recovery-" + UUID().uuidString))
            let outbox = FieldOutbox(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), defaults: defaults)
            outbox.bind(actorID: "00000000-0000-4000-8000-000000000004", organizationID: organizationID)
            let request = OutboxEntry.PaymentPayload(invoiceId: invoiceID, jobId: nil, amountCents: 500, method: "cash", idempotencyKey: UUID().uuidString)
            XCTAssertNotNil(outbox.enqueue(.payment(request), policyVersion: 1))
            let model = InvoicePaymentCollectionModel(api: api, invoiceID: invoiceID, protectDeniedAccess: true)
            model.outbox = outbox
            await model.load(); XCTAssertNotNil(model.invoice)
            api.invalidateRequests(); await model.load()
            XCTAssertNil(model.invoice)
            XCTAssertFalse(model.canRecordPayment)
            let stale = try JSONDecoder().decode(InvoiceRecord.self, from: Data(body.utf8))
            XCTAssertFalse(model.acceptInvoiceMutationResponse(stale))
            XCTAssertEqual(outbox.waitingPayments(invoiceID: invoiceID).count, 1)
            api.invalidateRequests(); await model.load()
            XCTAssertNil(model.invoice, "A connection failure cannot restore a denied invoice")
            XCTAssertEqual(outbox.waitingPayments(invoiceID: invoiceID).count, 1)
            api.invalidateRequests(); await model.load()
            XCTAssertNotNil(model.invoice, "Both live invoice and payment history are required for recovery")
        }
    }
}

import XCTest
@testable import Thorbis

@MainActor
final class FinancialActionAPITests: XCTestCase {
    private let estimateID = "00000000-0000-4000-8000-000000000008"
    private let invoiceID = "00000000-0000-4000-8000-00000000000a"
    private let estimate = #"{"id":"00000000-0000-4000-8000-000000000008","organizationId":"00000000-0000-4000-8000-000000000002","customerId":"00000000-0000-4000-8000-000000000003","createdByUserId":"00000000-0000-4000-8000-000000000004","status":"sent","currentRevisionNumber":1,"title":"Quote","lines":[],"createdAt":"2026-10-26T12:00:00Z","updatedAt":"2026-10-26T12:00:00Z"}"#
    private let invoice = #"{"id":"00000000-0000-4000-8000-00000000000a","organizationId":"00000000-0000-4000-8000-000000000002","customerId":"00000000-0000-4000-8000-000000000003","createdByUserId":"00000000-0000-4000-8000-000000000004","origin":"job_completion","sourceOperationKey":"completion:test","status":"draft","lines":[],"linesRevision":3,"amountPaid":0,"currency":"USD","createdAt":"2026-10-26T12:00:00Z","updatedAt":"2026-10-26T12:00:00Z"}"#

    func testEstimateActionsSendExplicitRevisionEvidence() async throws {
        let client = APIClient(session: URLProtocolFixture.session([.init(200, estimate), .init(200, estimate), .init(200, estimate)]), baseURL: "https://app.thorbis.com")
        _ = try await client.sendFieldEstimate(estimateID, expectedRevisionNumber: 0)
        _ = try await client.approveFieldEstimate(estimateID, revisionNumber: 1)
        _ = try await client.declineFieldEstimate(estimateID, revisionNumber: 1)
        let requests = URLProtocolFixture.recorded
        XCTAssertEqual(requests.map { $0.url?.path }, ["/v1/estimates/\(estimateID)/send", "/v1/estimates/\(estimateID)/approve", "/v1/estimates/\(estimateID)/decline"])
        let bodies = try requests.map { try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap($0.body)) as? [String: Any]) }
        XCTAssertEqual(bodies[0]["expectedRevisionNumber"] as? Int, 0)
        XCTAssertEqual(bodies[1]["revisionNumber"] as? Int, 1)
        XCTAssertEqual(bodies[2]["revisionNumber"] as? Int, 1)
    }

    func testEstimateReviseAndInvoiceIssuePreserveReviewedLineRevisions() async throws {
        let client = APIClient(session: URLProtocolFixture.session([.init(200, estimate), .init(200, invoice), .init(200, invoice)]), baseURL: "https://app.thorbis.com")
        let line = FieldEstimateLineInput(description: "Repair", quantity: 1, unitPrice: .init(amount: 2500, currency: "USD"))
        _ = try await client.reviseFieldEstimate(estimateID, request: .init(expectedRevisionNumber: 1, title: "Revised quote", lines: [line]))
        _ = try await client.replaceFieldInvoiceLines(invoiceID, request: .init(expectedLinesRevision: 3, lines: [line]))
        _ = try await client.issueFieldInvoice(invoiceID, expectedLinesRevision: 3)
        let requests = URLProtocolFixture.recorded
        XCTAssertEqual(requests.map { $0.url?.path }, ["/v1/estimates/\(estimateID)/revise", "/v2/invoices/\(invoiceID)/lines", "/v1/invoices/\(invoiceID)/issue"])
        let bodies = try requests.map { try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap($0.body)) as? [String: Any]) }
        XCTAssertEqual(bodies[0]["expectedRevisionNumber"] as? Int, 1)
        XCTAssertEqual(bodies[1]["expectedLinesRevision"] as? Int, 3)
        XCTAssertEqual(bodies[2]["expectedLinesRevision"] as? Int, 3)
        XCTAssertEqual(((bodies[1]["lines"] as? [[String: Any]])?.first?["unitPrice"] as? [String: Any])?["amount"] as? Int, 2500)
    }

    func testCashPaymentRequiresStableKeyAndDecodesPhysicalServiceProvenance() async throws {
        let payment = #"{"id":"00000000-0000-4000-8000-00000000000b","organizationId":"00000000-0000-4000-8000-000000000002","invoiceId":"00000000-0000-4000-8000-00000000000a","amount":{"amount":2500,"currency":"USD"},"method":"cash","status":"recorded","collectionEvidence":{"purpose":"physical_service","source":{"kind":"job","id":"00000000-0000-4000-8000-000000000001"}},"idempotencyKey":"cash-receipt-1","recordedAt":"2026-10-26T12:00:00Z"}"#
        let client = APIClient(session: URLProtocolFixture.session([.init(201, payment), .init(200, "{\"items\":[\(payment)]}")]), baseURL: "https://app.thorbis.com")
        let result = try await client.recordFieldPayment(invoiceID, request: .init(amount: .init(amount: 2500, currency: "USD"), method: .cash, idempotencyKey: "cash-receipt-1"))
        let listed = try await client.fieldPayments(invoiceID)
        XCTAssertEqual(result.collectionEvidence.source?.kind, .job)
        XCTAssertEqual(listed.first?.id, result.id)
        let sent = try XCTUnwrap(URLProtocolFixture.recorded.first)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(sent.body)) as? [String: Any])
        XCTAssertEqual(body["idempotencyKey"] as? String, "cash-receipt-1")
        XCTAssertEqual(body["method"] as? String, "cash")
        XCTAssertNil(body["collectionEvidence"])
    }

    func testUnknownPaymentProvenanceIsRejected() throws {
        let response = #"{"id":"00000000-0000-4000-8000-00000000000b","organizationId":"00000000-0000-4000-8000-000000000002","invoiceId":"00000000-0000-4000-8000-00000000000a","amount":{"amount":2500,"currency":"USD"},"method":"cash","status":"recorded","collectionEvidence":{"purpose":"other"},"idempotencyKey":"cash-receipt-1","recordedAt":"2026-10-26T12:00:00Z"}"#
        XCTAssertThrowsError(try JSONDecoder().decode(FieldPaymentRecord.self, from: Data(response.utf8)))
    }
}

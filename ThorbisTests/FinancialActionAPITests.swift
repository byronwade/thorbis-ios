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
        let updatedInvoice = invoice.replacingOccurrences(of: #""linesRevision":3"#, with: #""linesRevision":4"#)
        let client = APIClient(session: URLProtocolFixture.session([.init(200, estimate), .init(200, updatedInvoice), .init(200, updatedInvoice)]), baseURL: "https://app.thorbis.com")
        let line = FieldEstimateLineInput(description: "Repair", quantity: 1, unitPrice: .init(amount: 2500, currency: "USD"))
        _ = try await client.reviseFieldEstimate(estimateID, request: .init(expectedRevisionNumber: 1, title: "Revised quote", lines: [line]))
        let updated = try await client.replaceFieldInvoiceLines(invoiceID, request: .init(expectedLinesRevision: 3, lines: [FieldInvoiceLineInput(description: line.description, quantity: line.quantity, unitPrice: line.unitPrice)]))
        XCTAssertEqual(updated.linesRevision, 4)
        _ = try await client.issueFieldInvoice(invoiceID, expectedLinesRevision: updated.linesRevision)
        let requests = URLProtocolFixture.recorded
        XCTAssertEqual(requests.map { $0.url?.path }, ["/v1/estimates/\(estimateID)/revise", "/v2/invoices/\(invoiceID)/lines", "/v1/invoices/\(invoiceID)/issue"])
        let bodies = try requests.map { try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap($0.body)) as? [String: Any]) }
        XCTAssertEqual(bodies[0]["expectedRevisionNumber"] as? Int, 1)
        XCTAssertEqual(bodies[1]["expectedLinesRevision"] as? Int, 3)
        XCTAssertEqual(bodies[2]["expectedLinesRevision"] as? Int, 4)
        XCTAssertEqual(((bodies[1]["lines"] as? [[String: Any]])?.first?["unitPrice"] as? [String: Any])?["amount"] as? Int, 2500)
    }

    func testStaleInvoiceLineRevisionIsReturnedWithoutAnAutomaticRetry() async throws {
        let conflict = #"{"title":"Conflict","status":409,"detail":"stale invoice lines revision: expected 3, current 4; review the current invoice"}"#
        let client = APIClient(session: URLProtocolFixture.session([.init(409, conflict)]), baseURL: "https://app.thorbis.com")
        let line = FieldInvoiceLineInput(description: "Repair", quantity: 1, unitPrice: .init(amount: 2500, currency: "USD"))

        do {
            _ = try await client.replaceFieldInvoiceLines(invoiceID, request: .init(expectedLinesRevision: 3, lines: [line]))
            XCTFail("Expected stale revision conflict")
        } catch let problem as Problem {
            XCTAssertEqual(problem.status, 409)
            XCTAssertTrue(problem.localizedDescription.contains("review the current invoice"))
        }

        XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
        XCTAssertEqual(URLProtocolFixture.recorded.first?.url?.path, "/v2/invoices/\(invoiceID)/lines")
    }

    func testDirectPriceBookSelectionSendsOnlyExactItemRevision() throws {
        let line = FieldInvoiceLineInput(
            description: "Replace capacitor", quantity: 2,
            unitPrice: .init(amount: 12500, currency: "USD"),
            source: .priceBookSelection(itemID: "11111111-1111-4111-8111-111111111111", revision: 3)
        )

        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(FieldInvoiceLinesRequest(expectedLinesRevision: 3, lines: [line]))) as? [String: Any]
        let source = try XCTUnwrap((body?["lines"] as? [[String: Any]])?.first?["source"] as? [String: Any])

        XCTAssertEqual(Set(source.keys), Set(["kind", "priceBookItemId", "priceBookRevision"]))
        XCTAssertEqual(source["kind"] as? String, "price_book")
        XCTAssertEqual(source["priceBookRevision"] as? Int, 3)
    }

    func testRetainedPriceBookSnapshotPreservesServerEvidenceWithoutNullFields() throws {
        let source = FieldLineSource(
            kind: "price_book", priceBookItemId: "11111111-1111-4111-8111-111111111111",
            priceBookRevision: 3, originalDescription: "Capacitor", originalUnit: "each",
            originalUnitPrice: .init(amount: 12500, currency: "USD"),
            originalTaxClassification: "taxable", originalItemKind: "material",
            addedByUserId: "00000000-0000-4000-8000-000000000004", capturedAt: "2026-10-26T12:00:00Z",
            overriddenFields: []
        )
        let line = FieldInvoiceLineInput(
            description: "Capacitor", quantity: 1, unitPrice: .init(amount: 12500, currency: "USD"),
            source: .retainedPriceBook(source)
        )

        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(FieldInvoiceLinesRequest(expectedLinesRevision: 3, lines: [line]))) as? [String: Any]
        let encodedSource = try XCTUnwrap((body?["lines"] as? [[String: Any]])?.first?["source"] as? [String: Any])

        XCTAssertEqual(encodedSource["originalUnit"] as? String, "each")
        XCTAssertEqual(encodedSource["originalTaxClassification"] as? String, "taxable")
        XCTAssertEqual(encodedSource["originalItemKind"] as? String, "material")
        XCTAssertNil(encodedSource["estimateId"])
    }

    func testEstimateLineSourceRetainsTheCanonicalTupleAndNestedSnapshot() throws {
        let line = FieldInvoiceLineInput(
            description: "Quoted repair", quantity: 1,
            unitPrice: .init(amount: 2500, currency: "USD"),
            source: .estimate(
                id: "00000000-0000-4000-8000-000000000008", revision: 2,
                lineID: "00000000-0000-4000-8000-000000000009",
                snapshot: .init(kind: "manual", addedByUserId: "00000000-0000-4000-8000-000000000004",
                               capturedAt: "2026-10-26T12:00:00Z")
            )
        )

        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(FieldInvoiceLinesRequest(expectedLinesRevision: 3, lines: [line]))) as? [String: Any]
        let source = try XCTUnwrap((body?["lines"] as? [[String: Any]])?.first?["source"] as? [String: Any])
        let snapshot = try XCTUnwrap(source["estimateLineSource"] as? [String: Any])

        XCTAssertEqual(source["kind"] as? String, "estimate")
        XCTAssertEqual(source["estimateRevisionNumber"] as? Int, 2)
        XCTAssertEqual(snapshot["kind"] as? String, "manual")
        XCTAssertEqual(Set(snapshot.keys), Set(["kind", "addedByUserId", "capturedAt"]))
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

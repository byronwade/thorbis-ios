import XCTest
@testable import Thorbis

@MainActor
final class InvoicePaymentCollectionTests: XCTestCase {
    private let invoiceID = "00000000-0000-4000-8000-00000000000a"
    private let paymentID = "00000000-0000-4000-8000-00000000000b"

    func testPaymentAmountUsesExactMinorUnitsAndCanonicalLimit() {
        let maximum = 1_000_000_000_000
        XCTAssertEqual(MoneyInput.cents("12.34", maximumCents: maximum), 1234)
        XCTAssertEqual(MoneyInput.cents("10000000000.00", maximumCents: maximum), maximum)
        XCTAssertNil(MoneyInput.cents("10000000000.01", maximumCents: maximum))
        XCTAssertNil(MoneyInput.cents("1.005", maximumCents: maximum))
    }

    func testRetryAfterTransientFailureReusesSamePaymentIntent() async {
        let accepted = payment(method: "card", idempotencyKey: "retryable-key")
        let client = APIClient(session: URLProtocolFixture.session([
            .init(200, invoice()), .init(200, #"{"items":[]}"#),
            .init(503, #"{"title":"Temporary failure","status":503,"detail":"retry safely"}"#),
            .init(200, invoice()), .init(200, #"{"items":[]}"#),
            .init(201, accepted), .init(200, invoice(amountPaid: 2500)),
            .init(200, #"{"items":[\#(accepted)]}"#)
        ]), baseURL: "https://app.thorbis.com")
        let (intentStore, defaults, suite) = makeIntentStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = InvoicePaymentCollectionModel(api: client, invoiceID: invoiceID,
                                                  intentStore: intentStore,
                                                  makeIdempotencyKey: { "retryable-key" })
        await model.load()

        let firstResult = await model.record(amountCents: 2500, method: .card)
        XCTAssertFalse(firstResult)
        let firstKey = model.pendingRequest?.idempotencyKey
        XCTAssertNotNil(firstKey)

        // Simulate leaving the invoice and recreating the model after an uncertain POST.
        let relaunchedModel = InvoicePaymentCollectionModel(
            api: client,
            invoiceID: invoiceID,
            intentStore: intentStore,
            makeIdempotencyKey: { "must-not-replace-persisted-key" }
        )
        await relaunchedModel.load()
        XCTAssertEqual(relaunchedModel.pendingRequest?.idempotencyKey, firstKey)

        let retryResult = await relaunchedModel.record(amountCents: 2500, method: .card)
        XCTAssertTrue(retryResult)
        let posts = URLProtocolFixture.recorded.filter { $0.method == "POST" }
        let bodies = posts.compactMap { request -> [String: Any]? in
            guard let data = request.body else { return nil }
            return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
        XCTAssertEqual(bodies.count, 2)
        XCTAssertEqual(bodies.map { $0["idempotencyKey"] as? String }, [firstKey, firstKey])
        XCTAssertEqual(bodies.map { $0["method"] as? String }, ["card", "card"])
        XCTAssertEqual(bodies.map { ($0["amount"] as? [String: Any])?["amount"] as? Int }, [2500, 2500])
        XCTAssertNil(intentStore.load(
            organizationID: "00000000-0000-4000-8000-000000000002",
            invoiceID: invoiceID
        ))
    }

    func testRefundedPaymentWithoutNetAmountContributesZeroToReconciliation() async {
        let refunded = payment(method: "card", idempotencyKey: "refunded-key")
            .replacingOccurrences(of: #""status":"recorded""#, with: #""status":"refunded""#)
        let client = APIClient(session: URLProtocolFixture.session([
            .init(200, invoice()), .init(200, #"{"items":[\#(refunded)]}"#)
        ]), baseURL: "https://app.thorbis.com")
        let model = InvoicePaymentCollectionModel(api: client, invoiceID: invoiceID)
        await model.load()

        XCTAssertEqual(model.paymentTotalCents, 0)
        XCTAssertTrue(model.canRecordPayment)
    }

    func testIssuedInvoiceMutationRemainsCurrentWhenRefreshFails() async throws {
        let client = APIClient(session: URLProtocolFixture.session([
            .init(200, invoice(status: "draft")), .init(200, #"{"items":[]}"#),
            .init(503, #"{"title":"Temporary failure","status":503}"#)
        ]), baseURL: "https://app.thorbis.com")
        let model = InvoicePaymentCollectionModel(api: client, invoiceID: invoiceID)
        await model.load()

        let issued = try JSONDecoder().decode(InvoiceRecord.self, from: Data(invoice().utf8))
        model.acceptInvoiceMutationResponse(issued)
        await model.load()

        XCTAssertEqual(model.invoice?.status, "issued")
        XCTAssertTrue(model.canOfferCollection)
        XCTAssertFalse(model.canRecordPayment)
        XCTAssertNotNil(model.loadError)
    }

    func testDuplicateSubmitDuringRequestDoesNotPostTwice() async {
        let gate = URLProtocolFixture.Gate()
        let accepted = payment(method: "check", idempotencyKey: "duplicate-key")
        let client = APIClient(session: URLProtocolFixture.session([
            .init(200, invoice()), .init(200, #"{"items":[]}"#),
            .init(201, accepted, gate: gate), .init(200, invoice(amountPaid: 2500)),
            .init(200, #"{"items":[\#(accepted)]}"#)
        ]), baseURL: "https://app.thorbis.com")
        let model = InvoicePaymentCollectionModel(api: client, invoiceID: invoiceID,
                                                  makeIdempotencyKey: { "duplicate-key" })
        await model.load()

        let first = Task { await model.record(amountCents: 2500, method: .check) }
        await waitForRequests(3)
        let duplicate = await model.record(amountCents: 2500, method: .check)
        XCTAssertFalse(duplicate)
        XCTAssertEqual(URLProtocolFixture.recorded.filter { $0.method == "POST" }.count, 1)

        gate.release()
        let firstResult = await first.value
        XCTAssertTrue(firstResult)
        XCTAssertEqual(URLProtocolFixture.recorded.filter { $0.method == "POST" }.count, 1)
    }

    func testInvoiceAndHistoryStayLockedUntilReceiptReconciles() async {
        let accepted = payment(method: "cash", idempotencyKey: "projection-key")
        let client = APIClient(session: URLProtocolFixture.session([
            .init(200, invoice()), .init(200, #"{"items":[]}"#),
            .init(201, accepted), .init(200, invoice()), .init(200, #"{"items":[]}"#),
            .init(200, invoice(amountPaid: 2500)), .init(200, #"{"items":[\#(accepted)]}"#)
        ]), baseURL: "https://app.thorbis.com")
        let model = InvoicePaymentCollectionModel(api: client, invoiceID: invoiceID,
                                                  makeIdempotencyKey: { "projection-key" })
        await model.load()

        let recorded = await model.record(amountCents: 2500, method: .cash)
        XCTAssertFalse(recorded)
        XCTAssertEqual(model.invoice?.amountPaid, 0)
        XCTAssertTrue(model.waitingForProjection)
        XCTAssertFalse(model.canRecordPayment)

        await model.load()
        XCTAssertEqual(model.invoice?.amountPaid, 2500)
        XCTAssertFalse(model.waitingForProjection)
        XCTAssertTrue(model.canRecordPayment)
    }

    func testNonIssuedInvoiceCannotRecordPayment() async {
        let client = APIClient(session: URLProtocolFixture.session([
            .init(200, invoice(status: "draft")), .init(200, #"{"items":[]}"#)
        ]), baseURL: "https://app.thorbis.com")
        let model = InvoicePaymentCollectionModel(api: client, invoiceID: invoiceID)
        await model.load()

        XCTAssertFalse(model.canRecordPayment)
        let result = await model.record(amountCents: 2500, method: .cash)
        XCTAssertFalse(result)
        XCTAssertEqual(URLProtocolFixture.recorded.filter { $0.method == "POST" }.count, 0)
    }

    func testPaymentCannotExceedOutstandingBalance() async {
        let client = APIClient(session: URLProtocolFixture.session([
            .init(200, invoice()), .init(200, #"{"items":[]}"#)
        ]), baseURL: "https://app.thorbis.com")
        let model = InvoicePaymentCollectionModel(api: client, invoiceID: invoiceID)
        await model.load()

        let result = await model.record(amountCents: 10_001, method: .cash)
        XCTAssertFalse(result)
        XCTAssertTrue(model.paymentError?.contains("greater than the invoice balance") == true)
        XCTAssertEqual(URLProtocolFixture.recorded.filter { $0.method == "POST" }.count, 0)
    }

    func testPermissionErrorIsShownAndRejectedIntentCanBeEdited() async {
        let client = APIClient(session: URLProtocolFixture.session([
            .init(200, invoice()), .init(200, #"{"items":[]}"#),
            .init(403, #"{"title":"Forbidden","status":403,"detail":"invoice.payment.create permission required"}"#)
        ]), baseURL: "https://app.thorbis.com")
        let model = InvoicePaymentCollectionModel(api: client, invoiceID: invoiceID,
                                                  makeIdempotencyKey: { "forbidden-key" })
        await model.load()

        let result = await model.record(amountCents: 2500, method: .ach)
        XCTAssertFalse(result)
        XCTAssertNotNil(model.paymentError)
        XCTAssertNil(model.pendingRequest)
    }

    private func invoice(status: String = "issued", amountPaid: Int = 0) -> String {
        #"{"id":"\#(invoiceID)","organizationId":"00000000-0000-4000-8000-000000000002","customerId":"00000000-0000-4000-8000-000000000003","createdByUserId":"00000000-0000-4000-8000-000000000004","origin":"job_completion","sourceOperationKey":"completion:test","locationId":null,"scheduleId":null,"sourceEstimateId":null,"sourceEstimateRevisionNumber":null,"manualPhysicalServiceEvidence":null,"status":"\#(status)","lines":[{"id":"00000000-0000-4000-8000-00000000000c","description":"Service visit","quantity":1,"unitPrice":{"amount":10000,"currency":"USD"}}],"linesRevision":3,"amountPaid":\#(amountPaid),"currency":"USD","issuedAt":"2026-10-26T12:00:00Z","paidAt":null,"voidedAt":null,"createdAt":"2026-10-26T11:00:00Z","updatedAt":"2026-10-26T12:00:00Z"}"#
    }

    private func payment(method: String = "card", idempotencyKey: String) -> String {
        #"{"id":"\#(paymentID)","organizationId":"00000000-0000-4000-8000-000000000002","invoiceId":"\#(invoiceID)","amount":{"amount":2500,"currency":"USD"},"method":"\#(method)","status":"recorded","collectionEvidence":{"purpose":"physical_service","source":{"kind":"job","id":"00000000-0000-4000-8000-000000000001"}},"idempotencyKey":"\#(idempotencyKey)","recordedAt":"2026-10-26T12:30:00Z"}"#
    }

    private func waitForRequests(_ count: Int) async {
        let deadline = Date().addingTimeInterval(3)
        while URLProtocolFixture.recorded.count < count && Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertGreaterThanOrEqual(URLProtocolFixture.recorded.count, count)
    }

    private func makeIntentStore() -> (InvoicePaymentIntentStore, UserDefaults, String) {
        let suite = "InvoicePaymentCollectionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (InvoicePaymentIntentStore(defaults: defaults), defaults, suite)
    }
}

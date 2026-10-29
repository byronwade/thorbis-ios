import XCTest
@testable import Thorbis

@MainActor
final class InvoicePaymentCollectionTests: XCTestCase {
    private let invoiceID = "00000000-0000-4000-8000-00000000000a"
    private let paymentID = "00000000-0000-4000-8000-00000000000b"

    func testPartialRefundUsesOnlyTheRemainingReceivedAmount() async throws {
        var receipt = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(payment(idempotencyKey: "partial-refund").utf8)) as? [String: Any])
        receipt["refundedAmount"] = 1000
        receipt["netAmount"] = ["amount": 1500, "currency": "USD"]
        let page = String(decoding: try JSONSerialization.data(withJSONObject: ["items": [receipt]]), as: UTF8.self)
        let client = APIClient(session: URLProtocolFixture.session([.init(200, invoice(amountPaid: 1500)), .init(200, page)]), baseURL: "https://app.thorbis.com")
        let model = InvoicePaymentCollectionModel(api: client, invoiceID: invoiceID)
        await model.load()
        XCTAssertTrue(model.historyComplete)
        XCTAssertEqual(model.paymentTotalCents, 1500)
        XCTAssertEqual(model.outstandingCents, 8500)
        XCTAssertTrue(model.canRecordPayment)
    }

    func testCancellationDoesNotLeaveAnActionableInvoiceOrHistory() async {
        let gate = URLProtocolFixture.Gate()
        defer { gate.release() }
        let client = APIClient(session: URLProtocolFixture.session([.init(200, invoice(), gate: gate)]), baseURL: "https://app.thorbis.com")
        let model = InvoicePaymentCollectionModel(api: client, invoiceID: invoiceID)
        let loading = Task { await model.load() }
        await waitForRequests(1)
        loading.cancel()
        gate.release()
        await loading.value
        XCTAssertNil(model.invoice)
        XCTAssertFalse(model.historyComplete)
        XCTAssertFalse(model.canRecordPayment)
    }

    func testMalformedHistoryCannotEnableCollectionOrPublishMoney() async throws {
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(payment(idempotencyKey: "malformed-history").utf8)) as? [String: Any])
        for changed: [String: Any] in [
            ["amount": ["amount": -2500, "currency": "USD"]],
            ["amount": ["amount": 2500, "currency": "EUR"]],
            ["netAmount": ["amount": -1, "currency": "USD"]],
            ["refundedAmount": 3000],
            ["refundedAmount": 1000]
        ] {
            var malformed = original
            changed.forEach { malformed[$0.key] = $0.value }
            let page = String(decoding: try JSONSerialization.data(withJSONObject: ["items": [malformed]]), as: UTF8.self)
            let client = APIClient(session: URLProtocolFixture.session([.init(200, invoice()), .init(200, page)]), baseURL: "https://app.thorbis.com")
            let model = InvoicePaymentCollectionModel(api: client, invoiceID: invoiceID)
            await model.load()
            XCTAssertFalse(model.historyComplete)
            XCTAssertTrue(model.payments.isEmpty)
            XCTAssertFalse(model.canRecordPayment)
            XCTAssertNotNil(model.loadError)
        }
    }

    func testChangedAPIContextCannotPublishTheFormerInvoicesHistory() async {
        let gate = URLProtocolFixture.Gate()
        defer { gate.release() }
        let client = APIClient(session: URLProtocolFixture.session([.init(200, invoice()), .init(200, #"{"items":[]}"#, gate: gate)]), baseURL: "https://app.thorbis.com")
        let model = InvoicePaymentCollectionModel(api: client, invoiceID: invoiceID)
        let loading = Task { await model.load() }
        await waitForRequests(2)
        client.invalidateRequests()
        gate.release()
        await loading.value
        XCTAssertNil(model.invoice)
        XCTAssertTrue(model.payments.isEmpty)
        XCTAssertFalse(model.historyComplete)
        XCTAssertFalse(model.canRecordPayment)
    }

    func testDiscountedIssuedInvoiceKeepsItsCorrectCollectableBalance() async throws {
        let rows: [[String: Any]] = [
            ["id": "charge", "description": "Service", "quantity": 1, "unitPrice": ["amount": 10000, "currency": "USD"]],
            ["id": "discount", "description": "Member discount", "quantity": 1, "unitPrice": ["amount": -1500, "currency": "USD"]]
        ]
        let client = APIClient(session: URLProtocolFixture.session([.init(200, try editedInvoice(["lines": rows])), .init(200, #"{"items":[]}"#)]), baseURL: "https://app.thorbis.com")
        let model = InvoicePaymentCollectionModel(api: client, invoiceID: invoiceID)
        await model.load()
        XCTAssertEqual(model.totalCents, 8500)
        XCTAssertEqual(model.outstandingCents, 8500)
        XCTAssertTrue(model.canRecordPayment)
    }

    func testForeignOrDuplicatedHistoryCannotBeShownAsThisInvoicesPayments() async throws {
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(payment(idempotencyKey: "test-history").utf8)) as? [String: Any])
        for changed in [["invoiceId": paymentID], ["organizationId": paymentID]] {
            var foreign = original
            changed.forEach { foreign[$0.key] = $0.value }
            let page = String(decoding: try JSONSerialization.data(withJSONObject: ["items": [foreign]]), as: UTF8.self)
            let client = APIClient(session: URLProtocolFixture.session([.init(200, invoice(amountPaid: 2500)), .init(200, page)]), baseURL: "https://app.thorbis.com")
            let model = InvoicePaymentCollectionModel(api: client, invoiceID: invoiceID)
            await model.load()
            XCTAssertFalse(model.historyComplete)
            XCTAssertTrue(model.payments.isEmpty)
            XCTAssertFalse(model.canRecordPayment)
            XCTAssertNotNil(model.loadError)
        }
        let duplicate = payment(idempotencyKey: "test-history")
        let client = APIClient(session: URLProtocolFixture.session([.init(200, invoice(amountPaid: 5000)), .init(200, #"{"items":[\#(duplicate),\#(duplicate)]}"#)]), baseURL: "https://app.thorbis.com")
        let model = InvoicePaymentCollectionModel(api: client, invoiceID: invoiceID)
        await model.load()
        XCTAssertFalse(model.historyComplete)
        XCTAssertTrue(model.payments.isEmpty)
        XCTAssertFalse(model.canRecordPayment)
    }

    func testScopedRefreshRejectsForeignContentsAndLocksExistingPaper() async throws {
        let scope = JobDocumentScope(jobID: "00000000-0000-4000-8000-000000000001",
            organizationID: "00000000-0000-4000-8000-000000000002", customerID: "00000000-0000-4000-8000-000000000003")
        let good = try editedInvoice(["jobId": scope.jobID])
        for fields: [String: Any] in [["id": paymentID], ["organizationId": paymentID], ["customerId": paymentID],
                                      ["jobId": paymentID], ["jobId": NSNull()]] {
            var changed = fields
            if fields["jobId"] == nil { changed["jobId"] = scope.jobID }
            let bad = try editedInvoice(changed)
            let client = APIClient(session: URLProtocolFixture.session([
                .init(200, good), .init(200, #"{"items":[]}"#), .init(200, bad)
            ]), baseURL: "https://app.thorbis.com")
            let model = InvoicePaymentCollectionModel(api: client, invoiceID: invoiceID, expectedJobScope: scope)
            await model.load()
            XCTAssertTrue(model.canRecordPayment)
            await model.load()
            XCTAssertNil(model.invoice)
            XCTAssertFalse(model.canRecordPayment)
            XCTAssertFalse(model.historyComplete)
            XCTAssertNotNil(model.loadError)
            XCTAssertEqual(URLProtocolFixture.recorded.count, 3, "Never read history for an unverified invoice")
        }
    }

    func testMutationResponseMustKeepTheRequestedInvoiceAndJobScope() async throws {
        let scope = JobDocumentScope(jobID: "00000000-0000-4000-8000-000000000001",
            organizationID: "00000000-0000-4000-8000-000000000002", customerID: "00000000-0000-4000-8000-000000000003")
        let client = APIClient(session: URLProtocolFixture.session([
            .init(200, try editedInvoice(["jobId": scope.jobID])), .init(200, #"{"items":[]}"#)
        ]), baseURL: "https://app.thorbis.com")
        let model = InvoicePaymentCollectionModel(api: client, invoiceID: invoiceID, expectedJobScope: scope)
        await model.load()
        let foreign = try JSONDecoder().decode(InvoiceRecord.self, from: Data(editedInvoice(["jobId": paymentID]).utf8))
        XCTAssertFalse(model.acceptInvoiceMutationResponse(foreign))
        XCTAssertNil(model.invoice)
        XCTAssertFalse(model.canRecordPayment)
    }

    private func editedInvoice(_ fields: [String: Any]) throws -> String {
        var value = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(invoice().utf8)) as? [String: Any])
        fields.forEach { value[$0.key] = $0.value }
        return String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
    }

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

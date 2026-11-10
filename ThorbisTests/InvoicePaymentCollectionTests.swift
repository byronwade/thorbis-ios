import XCTest
import Combine
@testable import Thorbis

@MainActor
final class InvoicePaymentCollectionTests: XCTestCase {
    private let invoiceID = "00000000-0000-4000-8000-00000000000a"
    private let paymentID = "00000000-0000-4000-8000-00000000000b"

    func testSavedCopyScopeRevisionPublishesAwayAndBackChanges() {
        let client = APIClient(session: URLProtocolFixture.session([]), baseURL: "https://app.thorbis.com")
        var revisions: [UUID] = []
        let observation = client.$savedCopyScopeRevision.dropFirst().sink { revisions.append($0) }
        client.savedCopyScope = "scope-A"
        client.savedCopyScope = "scope-B"
        client.savedCopyScope = "scope-A"
        XCTAssertEqual(revisions.count, 3)
        XCTAssertEqual(Set(revisions).count, 3)
        withExtendedLifetime(observation) {}
    }

    func testSavedInvoiceSourceSurvivesConcurrentLiveInvoiceResponse() async throws {
        let gate = URLProtocolFixture.Gate(); defer { gate.release() }
        let client = APIClient(session: URLProtocolFixture.session([
            .init(200, invoice()), .init(200, invoice(amountPaid: 2500), gate: gate)
        ]), baseURL: "https://app.thorbis.com")
        client.savedCopyScope = "invoice-provenance-" + UUID().uuidString
        let path = "/v1/invoices/\(invoiceID)"
        _ = try await client.fieldInvoice(invoiceID)
        let scope = try XCTUnwrap(client.savedCopyScope)
        let key = SavedCopies.key(origin: "https://app.thorbis.com", path: path, query: [])
        SavedCopyStore.shared.waitForQueuedWrites()
        XCTAssertTrue(SavedCopyStore.shared.exists(scope: scope, key: key))
        client.invalidateRequests()
        let live = Task { try await client.fieldInvoiceWithProvenance(invoiceID) }
        await waitForRequests(2)
        client.knownOffline = true
        let saved = try await client.fieldInvoiceWithProvenance(invoiceID)
        XCTAssertEqual(saved.value.amountPaid, 0)
        XCTAssertNotNil(client.savedCopyDate(path))
        gate.release()
        let fresh = try await live.value
        XCTAssertEqual(fresh.value.amountPaid, 2500)
        guard case .savedCopy = saved.provenance.source else { return XCTFail("The saved response must retain its own source") }
        XCTAssertEqual(fresh.provenance.source, .urlSession(cacheBypassed: false))
        XCTAssertEqual(saved.provenance.savedCopyScope, scope)
        XCTAssertEqual(saved.provenance.path, path)
        XCTAssertEqual(saved.provenance.origin, "https://app.thorbis.com")
        XCTAssertEqual(saved.provenance.generation, fresh.provenance.generation)
    }

    func testPaymentHistoryProvenanceCoversEachFreshPage() async throws {
        let client = APIClient(session: URLProtocolFixture.session([
            .init(200, #"{"items":[],"nextCursor":"next"}"#), .init(200, #"{"items":[]}"#)
        ]), baseURL: "https://app.thorbis.com")
        let scope = "history-provenance-" + UUID().uuidString
        client.savedCopyScope = scope
        let result = try await SavedCopies.$liveOnly.withValue(true) { try await client.fieldPaymentsWithProvenance(invoiceID) }
        XCTAssertTrue(result.payments.isEmpty)
        XCTAssertEqual(result.pages.count, 2)
        XCTAssertEqual(result.pages.map(\.cursor), [nil, "next"])
        XCTAssertTrue(result.pages.allSatisfy { $0.source == .urlSession(cacheBypassed: true) && $0.savedCopyScope == scope })
        XCTAssertTrue(URLProtocolFixture.recorded.allSatisfy { $0.cachePolicy == .reloadIgnoringLocalCacheData && $0.header("Cache-Control") == "no-cache" })
    }

    func testPaymentHistoryStopsBeforeNextPageWhenSavedScopeChanges() async throws {
        let gate = URLProtocolFixture.Gate(); defer { gate.release() }
        let client = APIClient(session: URLProtocolFixture.session([
            .init(200, #"{"items":[],"nextCursor":"next"}"#, gate: gate),
            .init(200, #"{"items":[]}"#)
        ]), baseURL: "https://app.thorbis.com")
        client.savedCopyScope = "history-original-" + UUID().uuidString
        let originalGeneration = client.requestGeneration
        var rejected = false
        let pending = Task { @MainActor in
            do { _ = try await client.fieldPaymentsWithProvenance(invoiceID) }
            catch is CancellationError { rejected = true }
            catch { XCTFail("Unexpected error: \(error)") }
        }
        await waitForRequests(1)
        client.savedCopyScope = "history-replacement-" + UUID().uuidString
        XCTAssertEqual(client.requestGeneration, originalGeneration)
        gate.release()
        await pending.value
        XCTAssertTrue(rejected, "History must not combine pages from different saved-copy scopes")
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1, "A retired scope must not begin the next page")
    }

    func testPaymentHistoryDoesNotPublishDelayedFinalPageAfterScopeChanges() async throws {
        let gate = URLProtocolFixture.Gate(); defer { gate.release() }
        let client = APIClient(session: URLProtocolFixture.session([
            .init(200, #"{"items":[],"nextCursor":"next"}"#),
            .init(200, #"{"items":[]}"#, gate: gate)
        ]), baseURL: "https://app.thorbis.com")
        client.savedCopyScope = "history-before-" + UUID().uuidString
        var rejected = false
        let pending = Task { @MainActor in
            do { _ = try await client.fieldPaymentsWithProvenance(invoiceID) }
            catch is CancellationError { rejected = true }
            catch { XCTFail("Unexpected error: \(error)") }
        }
        await waitForRequests(2)
        client.savedCopyScope = "history-after-" + UUID().uuidString
        gate.release(); await pending.value
        XCTAssertTrue(rejected, "A final page from a retired scope must not be published")
    }

    func testPaymentHistoryRejectsScopeAwayAndBackDuringPage() async throws {
        let gate = URLProtocolFixture.Gate(); defer { gate.release() }
        let client = APIClient(session: URLProtocolFixture.session([
            .init(200, #"{"items":[],"nextCursor":"next"}"#, gate: gate), .init(200, #"{"items":[]}"#)
        ]), baseURL: "https://app.thorbis.com")
        let original = "history-aba-" + UUID().uuidString
        client.savedCopyScope = original
        let originalGeneration = client.requestGeneration
        var rejected = false
        let pending = Task { @MainActor in
            do { _ = try await client.fieldPaymentsWithProvenance(invoiceID) }
            catch is CancellationError { rejected = true }
            catch { XCTFail("Unexpected error: \(error)") }
        }
        await waitForRequests(1)
        client.savedCopyScope = "history-other-" + UUID().uuidString
        client.savedCopyScope = original
        XCTAssertEqual(client.requestGeneration, originalGeneration)
        gate.release(); await pending.value
        XCTAssertTrue(rejected)
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
    }

    func testInvoiceProvenanceDoesNotCallProtocolCacheBypassLiveAuthorization() async throws {
        let client = APIClient(session: URLProtocolFixture.session([.init(200, invoice())]), baseURL: "https://app.thorbis.com")
        let result = try await client.fieldInvoiceWithProvenance(invoiceID)
        XCTAssertEqual(result.provenance.source, .urlSession(cacheBypassed: false))
        XCTAssertEqual(result.value.id, invoiceID)
    }

    func testSameAmountCardFromAnotherAttemptCannotConfirmTap() async {
        let receipt = payment(idempotencyKey: "tap:\(invoiceID):00000000-0000-4000-8000-00000000000e")
        let api = APIClient(session: URLProtocolFixture.session([
            .init(200, invoice(amountPaid: 2500)), .init(200, #"{"items":[\#(receipt)]}"#)
        ]), baseURL: "https://app.thorbis.com")
        let model = InvoicePaymentCollectionModel(api: api, invoiceID: invoiceID)
        await model.load()
        XCTAssertTrue(model.historyComplete)
        XCTAssertEqual(model.paymentTotalCents, 2500)
        XCTAssertFalse(model.hasRecordedCardPresentPayment(tapIntent))
    }

    func testWorkspaceInvalidationCannotConfirmFormerlyVerifiedTapReceipt() async {
        let receipt = payment(idempotencyKey: "tap:\(invoiceID):\(tapIntent.attemptId)")
        let api = APIClient(session: URLProtocolFixture.session([
            .init(200, invoice(amountPaid: 2500)), .init(200, #"{"items":[\#(receipt)]}"#)
        ]), baseURL: "https://app.thorbis.com")
        let model = InvoicePaymentCollectionModel(api: api, invoiceID: invoiceID)
        await model.load()
        XCTAssertTrue(model.hasRecordedCardPresentPayment(tapIntent))
        api.invalidateRequests()
        XCTAssertFalse(model.hasRecordedCardPresentPayment(tapIntent))
    }

    func testUnrelatedReceiptCannotConfirmTapEvenWhenInvoiceIsPaid() async throws {
        var receipt = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(payment(idempotencyKey: "another-attempt").utf8)) as? [String: Any])
        receipt["amount"] = ["amount": 10000, "currency": "USD"]
        let page = String(decoding: try JSONSerialization.data(withJSONObject: ["items": [receipt]]), as: UTF8.self)
        let api = APIClient(session: URLProtocolFixture.session([
            .init(200, invoice(amountPaid: 10000)), .init(200, page)
        ]), baseURL: "https://app.thorbis.com")
        let model = InvoicePaymentCollectionModel(api: api, invoiceID: invoiceID)
        await model.load()
        XCTAssertEqual(model.outstandingCents, 0)
        XCTAssertEqual(model.payments.count, 1)
        XCTAssertFalse(model.hasRecordedCardPresentPayment(tapIntent))
    }

    func testExactTapReceiptConfirmsOnlyAfterValidatedHistoryLoads() async {
        let receipt = payment(idempotencyKey: "tap:\(invoiceID):\(tapIntent.attemptId)")
        let api = APIClient(session: URLProtocolFixture.session([
            .init(200, invoice(amountPaid: 2500)), .init(200, #"{"items":[\#(receipt)]}"#),
            .init(200, invoice(amountPaid: 2500)), .init(503, #"{"title":"Unavailable","status":503}"#)
        ]), baseURL: "https://app.thorbis.com")
        let model = InvoicePaymentCollectionModel(api: api, invoiceID: invoiceID)
        XCTAssertFalse(model.hasRecordedCardPresentPayment(tapIntent))
        await model.load()
        XCTAssertTrue(model.hasRecordedCardPresentPayment(tapIntent))
        XCTAssertEqual(model.outstandingCents, 7500, "Attempt confirmation is independent of the remaining balance")
        await model.load()
        XCTAssertFalse(model.hasRecordedCardPresentPayment(tapIntent), "A failed refresh cannot reuse the formerly verified receipt")
    }

    func testMatchingTapKeyCannotConfirmWrongTenderAmountOrRefundedReceipt() async throws {
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(payment(idempotencyKey: "tap:\(invoiceID):\(tapIntent.attemptId)").utf8)) as? [String: Any])
        for changes: [String: Any] in [
            ["method": "cash"],
            ["amount": ["amount": 2000, "currency": "USD"]],
            ["status": "refunded"],
            ["refundedAmount": 500, "netAmount": ["amount": 2000, "currency": "USD"]],
            ["invoiceId": paymentID],
            ["organizationId": paymentID]
        ] {
            var receipt = original
            changes.forEach { receipt[$0.key] = $0.value }
            let page = String(decoding: try JSONSerialization.data(withJSONObject: ["items": [receipt]]), as: UTF8.self)
            let received = changes["status"] != nil ? 0 :
                ((changes["amount"] != nil || changes["refundedAmount"] != nil) ? 2000 : 2500)
            let api = APIClient(session: URLProtocolFixture.session([
                .init(200, invoice(amountPaid: received)), .init(200, page)
            ]), baseURL: "https://app.thorbis.com")
            let model = InvoicePaymentCollectionModel(api: api, invoiceID: invoiceID)
            await model.load()
            XCTAssertFalse(model.hasRecordedCardPresentPayment(tapIntent), "Rejected receipt: \(changes.keys.sorted())")
        }
    }

    private var tapIntent: CardPresentIntent {
        CardPresentIntent(attemptId: "00000000-0000-4000-8000-00000000000d",
                          clientSecret: "synthetic-unused", paymentIntentId: "pi_synthetic",
                          locationId: "tml_synthetic", amount: FieldMoney(amount: 2500, currency: "USD"),
                          expiresAt: "2026-10-29T12:00:00Z")
    }

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
        XCTAssertFalse(model.hasRecordedCardPresentPayment(tapIntent))
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

    func testDeniedInvoiceRefreshStopsNewPaymentAttempts() async {
        let client = APIClient(session: URLProtocolFixture.session([
            .init(200, invoice()), .init(200, #"{"items":[]}"#),
            .init(403, #"{"title":"Forbidden","status":403}"#)
        ]), baseURL: "https://app.thorbis.com")
        let model = InvoicePaymentCollectionModel(api: client, invoiceID: invoiceID)
        await model.load()
        XCTAssertTrue(model.canRecordPayment)
        await model.load()
        XCTAssertFalse(model.canRecordPayment)
        let result = await model.record(amountCents: 2500, method: .cash)
        XCTAssertFalse(result)
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

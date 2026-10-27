import XCTest
@testable import Thorbis

@MainActor
final class InvoicePaymentRefundTests: XCTestCase {
    private let actorID = "00000000-0000-4000-8000-000000000004"
    private let organizationID = "00000000-0000-4000-8000-000000000002"
    private let invoiceID = "00000000-0000-4000-8000-00000000000a"
    private let paymentID = "00000000-0000-4000-8000-00000000000b"
    private let reason = "Customer approved the reversal."

    func testOnlyRecordedUnrefundedPaymentCanOfferRefund() {
        let store = MemoryRefundIntentStore()
        XCTAssertTrue(makeModel(payment: payment(), store: store).canOfferRefund)
        XCTAssertFalse(makeModel(payment: payment(status: .refunded, refundedAmount: 2_500), store: store).canOfferRefund)
        XCTAssertFalse(makeModel(payment: payment(refundedAmount: 1), store: store).canOfferRefund)
    }

    func testDraftIsSavedAndRestoredOnlyForTheSameActorWorkspaceAndPayment() throws {
        let store = MemoryRefundIntentStore()
        let first = makeModel(store: store)
        first.updateReasonDraft(reason)

        let restored = makeModel(store: store)
        XCTAssertEqual(restored.reasonDraft, reason)
        XCTAssertEqual(restored.intent?.state, .draft)
        XCTAssertEqual(try store.load(actorID: actorID, organizationID: organizationID, paymentID: paymentID)?.reason, reason)
        XCTAssertEqual(makeModel(actorID: "other-actor", store: store).reasonDraft, "")
        XCTAssertEqual(makeModel(payment: payment(id: "other-payment"), store: store).reasonDraft, "")
    }

    func testIntentStoreReadFailureFailsClosed() async {
        let client = APIClient(session: URLProtocolFixture.session([]), baseURL: "https://app.thorbis.com")
        let store = MemoryRefundIntentStore()
        store.failLoad = true
        let model = makeModel(api: client, store: store)
        model.updateReasonDraft(reason)

        let completed = await model.submitRefund()

        XCTAssertFalse(completed)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(URLProtocolFixture.recorded.filter { $0.method == "POST" }.count, 0)
    }

    func testIntentStoreWriteFailurePreventsRefundRequest() async {
        let client = APIClient(session: URLProtocolFixture.session([]), baseURL: "https://app.thorbis.com")
        let store = MemoryRefundIntentStore()
        store.failSave = true
        let model = makeModel(api: client, store: store)
        model.updateReasonDraft(reason)

        let completed = await model.submitRefund()

        XCTAssertFalse(completed)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(URLProtocolFixture.recorded.filter { $0.method == "POST" }.count, 0)
    }

    func testShortReasonIsRejectedBeforeAnyRefundRequest() async {
        let client = APIClient(session: URLProtocolFixture.session([]), baseURL: "https://app.thorbis.com")
        let model = makeModel(api: client)
        model.updateReasonDraft(" x ")

        let completed = await model.submitRefund()

        XCTAssertFalse(completed)
        XCTAssertFalse(model.isSubmitting)
        XCTAssertEqual(URLProtocolFixture.recorded.count, 0)
        XCTAssertTrue(model.errorMessage?.contains("3") == true)

        model.updateReasonDraft(String(repeating: "x", count: 2_001))
        let tooLongCompleted = await model.submitRefund()
        XCTAssertFalse(tooLongCompleted)
        XCTAssertEqual(URLProtocolFixture.recorded.count, 0)
    }

    func testUncertainRefundIntentIsSavedBeforeRequestAndRestoredAfterFailure() async throws {
        let client = APIClient(session: URLProtocolFixture.session([
            .init(503, #"{"title":"Temporary failure","status":503,"detail":"Try again explicitly."}"#),
            .init(200, refundedPayment())
        ]), baseURL: "https://app.thorbis.com")
        let store = MemoryRefundIntentStore()
        let model = makeModel(api: client, store: store)
        model.updateReasonDraft(reason)

        let completed = await model.submitRefund()

        XCTAssertFalse(completed)
        XCTAssertEqual(model.intent?.state, .uncertain)
        XCTAssertEqual(try store.load(actorID: actorID, organizationID: organizationID, paymentID: paymentID)?.reason, reason)
        XCTAssertEqual(URLProtocolFixture.recorded.filter { $0.method == "POST" }.count, 1)

        let restored = makeModel(api: client, store: store)
        XCTAssertEqual(restored.reasonDraft, reason)
        XCTAssertEqual(restored.intent?.state, .uncertain)
        XCTAssertEqual(URLProtocolFixture.recorded.filter { $0.method == "POST" }.count, 1)

        let recovered = await restored.checkRefundStatus()
        XCTAssertTrue(recovered)
        XCTAssertTrue(restored.didComplete)
        XCTAssertNil(try store.load(actorID: actorID, organizationID: organizationID, paymentID: paymentID))
        let refundRequests = URLProtocolFixture.recorded.filter { $0.method == "POST" }
        let reasons = try refundRequests.map { request -> String? in
            let body = try XCTUnwrap(request.body)
            return (try JSONSerialization.jsonObject(with: body) as? [String: String])?["reason"]
        }
        XCTAssertEqual(reasons, [reason, reason])
    }

    func testPendingRecoveryReplaysIdenticalReasonAndDistinguishesReconciliation() async throws {
        let pending = #"{"outcome":"pending","paymentId":"00000000-0000-4000-8000-00000000000b"}"#
        let reconciliation = #"{"outcome":"reconciliation_required","paymentId":"00000000-0000-4000-8000-00000000000b"}"#
        let client = APIClient(session: URLProtocolFixture.session([.init(202, pending), .init(202, reconciliation)]), baseURL: "https://app.thorbis.com")
        let model = makeModel(api: client)
        model.updateReasonDraft(reason)

        let initialCompleted = await model.submitRefund()
        XCTAssertFalse(initialCompleted)
        XCTAssertEqual(model.intent?.state, .pending)
        let recoveryCompleted = await model.checkRefundStatus()
        XCTAssertFalse(recoveryCompleted)
        XCTAssertEqual(model.intent?.state, .reconciliationRequired)

        let requests = URLProtocolFixture.recorded.filter { $0.method == "POST" }
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.map { $0.url?.path }, Array(repeating: "/v1/payments/\(paymentID)/refund", count: 2))
        let reasons = try requests.map { request -> String? in
            let body = try XCTUnwrap(request.body)
            return (try JSONSerialization.jsonObject(with: body) as? [String: String])?["reason"]
        }
        XCTAssertEqual(reasons, [reason, reason])
    }

    func testCanonicalRefundUpdatesPaymentAndClearsIntent() async throws {
        let client = APIClient(session: URLProtocolFixture.session([.init(200, refundedPayment())]), baseURL: "https://app.thorbis.com")
        let store = MemoryRefundIntentStore()
        let model = makeModel(api: client, store: store)
        model.updateReasonDraft(reason)

        let completed = await model.submitRefund()

        XCTAssertTrue(completed)
        XCTAssertEqual(model.payment.status.rawValue, "refunded")
        XCTAssertNil(try store.load(actorID: actorID, organizationID: organizationID, paymentID: paymentID))
        XCTAssertNil(model.intent)
    }

    func testCanonicalPaymentOnReopenClearsSavedRefundIntent() throws {
        let store = MemoryRefundIntentStore()
        try store.save(
            FieldPaymentRefundIntent(reason: reason, state: .pending),
            actorID: actorID,
            organizationID: organizationID,
            paymentID: paymentID
        )

        let restored = makeModel(payment: payment(status: .refunded, refundedAmount: 2_500), store: store)

        XCTAssertFalse(restored.canOfferRefund)
        XCTAssertNil(restored.intent)
        XCTAssertNil(try store.load(actorID: actorID, organizationID: organizationID, paymentID: paymentID))
    }

    func testDuplicateRefundSubmissionWhileRequestIsOpenSendsOnlyOnePost() async {
        let gate = URLProtocolFixture.Gate()
        let pending = #"{"outcome":"pending","paymentId":"00000000-0000-4000-8000-00000000000b"}"#
        let client = APIClient(session: URLProtocolFixture.session([.init(202, pending, gate: gate)]), baseURL: "https://app.thorbis.com")
        let model = makeModel(api: client)
        model.updateReasonDraft(reason)

        let first = Task { await model.submitRefund() }
        await waitForRequests(1)
        XCTAssertTrue(model.isSubmitting)
        let duplicateCompleted = await model.submitRefund()
        XCTAssertFalse(duplicateCompleted)
        XCTAssertEqual(URLProtocolFixture.recorded.filter { $0.method == "POST" }.count, 1)

        gate.release()
        let firstCompleted = await first.value
        XCTAssertFalse(firstCompleted)
        XCTAssertEqual(model.intent?.state, .pending)
    }

    func testUnresolvedRefundIntentCannotBeDiscarded() throws {
        let store = MemoryRefundIntentStore()
        try store.save(
            FieldPaymentRefundIntent(reason: reason, state: .pending),
            actorID: actorID,
            organizationID: organizationID,
            paymentID: paymentID
        )
        let model = makeModel(store: store)

        model.discardSavedIntent()

        XCTAssertEqual(model.intent?.state, .pending)
        XCTAssertEqual(model.reasonDraft, reason)
        XCTAssertEqual(
            try store.load(actorID: actorID, organizationID: organizationID, paymentID: paymentID),
            FieldPaymentRefundIntent(reason: reason, state: .pending)
        )
    }

    func testExplicitDiscardRemovesSavedReason() throws {
        let store = MemoryRefundIntentStore()
        let model = makeModel(store: store)
        model.updateReasonDraft(reason)

        model.discardSavedIntent()

        XCTAssertNil(model.intent)
        XCTAssertEqual(model.reasonDraft, "")
        XCTAssertNil(try store.load(actorID: actorID, organizationID: organizationID, paymentID: paymentID))
    }

    private func makeModel(
        api: APIClient? = nil,
        actorID: String? = nil,
        payment: FieldPaymentRecord? = nil,
        store: MemoryRefundIntentStore = MemoryRefundIntentStore()
    ) -> InvoicePaymentRefundModel {
        InvoicePaymentRefundModel(
            api: api ?? APIClient(session: URLProtocolFixture.session([]), baseURL: "https://app.thorbis.com"),
            actorID: actorID ?? self.actorID,
            payment: payment ?? self.payment(),
            intentStore: store
        )
    }

    private func payment(
        id: String? = nil,
        status: FieldPaymentStatus = .recorded,
        refundedAmount: Int? = nil
    ) -> FieldPaymentRecord {
        FieldPaymentRecord(
            id: id ?? paymentID,
            organizationId: organizationID,
            invoiceId: invoiceID,
            amount: FieldMoney(amount: 2_500, currency: "USD"),
            method: "card",
            status: status,
            collectionEvidence: .physicalService(.init(kind: .job, id: "00000000-0000-4000-8000-000000000001")),
            idempotencyKey: "payment-key",
            recordedAt: "2026-10-26T12:30:00Z",
            refundedAmount: refundedAmount,
            netAmount: nil,
            refundedAt: nil
        )
    }

    private func refundedPayment() -> String {
        #"{"id":"00000000-0000-4000-8000-00000000000b","organizationId":"00000000-0000-4000-8000-000000000002","invoiceId":"00000000-0000-4000-8000-00000000000a","amount":{"amount":2500,"currency":"USD"},"method":"card","status":"refunded","collectionEvidence":{"purpose":"physical_service","source":{"kind":"job","id":"00000000-0000-4000-8000-000000000001"}},"idempotencyKey":"payment-key","recordedAt":"2026-10-26T12:30:00Z","refundedAmount":2500,"netAmount":{"amount":0,"currency":"USD"},"refundedAt":"2026-10-26T13:00:00Z"}"#
    }

    private func waitForRequests(_ count: Int) async {
        let deadline = Date().addingTimeInterval(3)
        while URLProtocolFixture.recorded.count < count && Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertGreaterThanOrEqual(URLProtocolFixture.recorded.count, count)
    }
}

@MainActor
private final class MemoryRefundIntentStore: PaymentRefundIntentStoring {
    private struct Key: Hashable {
        let actorID: String
        let organizationID: String
        let paymentID: String
    }

    private var intents: [Key: FieldPaymentRefundIntent] = [:]
    var failLoad = false
    var failSave = false

    func load(actorID: String, organizationID: String, paymentID: String) throws -> FieldPaymentRefundIntent? {
        if failLoad { throw Failure.unavailable }
        return intents[Key(actorID: actorID, organizationID: organizationID, paymentID: paymentID)]
    }

    func save(_ intent: FieldPaymentRefundIntent, actorID: String, organizationID: String, paymentID: String) throws {
        if failSave { throw Failure.unavailable }
        intents[Key(actorID: actorID, organizationID: organizationID, paymentID: paymentID)] = intent
    }

    func remove(actorID: String, organizationID: String, paymentID: String) throws {
        intents[Key(actorID: actorID, organizationID: organizationID, paymentID: paymentID)] = nil
    }

    private enum Failure: LocalizedError {
        case unavailable
        var errorDescription: String? { "Secure storage unavailable." }
    }
}

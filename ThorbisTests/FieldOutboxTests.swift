import XCTest
@testable import Thorbis

@MainActor
final class FieldOutboxTests: XCTestCase {
    private let actor = "019f0000-0000-7000-8000-000000000011"
    private let org = "019f0000-0000-7000-8000-000000000001"
    private let jobA = "019f0000-0000-7000-8000-0000000000a1"
    private let jobB = "019f0000-0000-7000-8000-0000000000b1"
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("outbox-tests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func outbox() -> FieldOutbox {
        let box = FieldOutbox(directory: directory, defaults: UserDefaults(suiteName: "outbox.\(UUID().uuidString)")!)
        box.bind(actorID: actor, organizationID: org)
        return box
    }

    private func api(_ replies: [URLProtocolFixture.Reply]) -> APIClient {
        APIClient(session: URLProtocolFixture.session(replies), baseURL: "https://app.thorbis.com")
    }

    func testQueuedChangesSurviveRelaunchAndStayBoundToTheirIdentity() throws {
        let first = outbox()
        first.enqueue(.progress(.init(jobId: jobA, to: "en_route", etaMinutes: 15)), policyVersion: 4)
        first.enqueue(.note(.init(jobId: jobA, body: "Gate code 4417")), policyVersion: 4)

        let relaunched = outbox()
        XCTAssertEqual(relaunched.pending.map(\.command), ["jobs.progress", "jobs.addNote"])
        XCTAssertEqual(relaunched.pendingStatus(for: jobA), "en_route")

        relaunched.bind(actorID: "019f0000-0000-7000-8000-000000000099", organizationID: org)
        XCTAssertTrue(relaunched.entries.isEmpty, "Another actor never sees these changes")
    }

    func testSignOutWarningCountsChangesQueuedInOtherWorkspaces() {
        let box = outbox()
        box.enqueue(.note(.init(jobId: jobA, body: "Gate code 4417")), policyVersion: 4)
        box.bind(actorID: actor, organizationID: "019f0000-0000-7000-8000-000000000002")
        XCTAssertTrue(box.entries.isEmpty)
        XCTAssertTrue(box.signOutWarning.hasPrefix("1 change"), "Sign-out deletes every workspace's queue, so the warning counts them all")
    }

    func testCommandEnvelopesMatchTheServerContractAndAppliedOrDuplicateClearTheQueue() async throws {
        let box = outbox()
        let progress = try XCTUnwrap(box.enqueue(.progress(.init(jobId: jobA, to: "arrived", arrival: .init(method: "manual"))), policyVersion: 4))
        let note = try XCTUnwrap(box.enqueue(.note(.init(jobId: jobA, body: "On site")), policyVersion: 4))
        let reply = #"{"outcomes":[{"commandId":"\#(progress.id)","status":"applied","result":{}},{"commandId":"\#(note.id)","status":"duplicate","result":{}}]}"#

        await box.drain(api: api([.init(200, reply)]), useCommandEndpoint: true)

        XCTAssertTrue(box.entries.isEmpty)
        XCTAssertEqual(box.lastSyncSent, 2)
        let request = try XCTUnwrap(URLProtocolFixture.recorded.first)
        XCTAssertEqual(request.url?.path, "/v1/commands")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.body)) as? [String: Any])
        let commands = try XCTUnwrap(body["commands"] as? [[String: Any]])
        XCTAssertEqual(commands.count, 2)
        XCTAssertEqual(commands[0]["command"] as? String, "jobs.progress")
        XCTAssertEqual(commands[0]["commandId"] as? String, progress.id)
        XCTAssertEqual(commands[0]["actorId"] as? String, actor)
        XCTAssertEqual(commands[0]["organizationId"] as? String, org)
        XCTAssertEqual(commands[0]["policyVersion"] as? Int, 4)
        XCTAssertNotNil(commands[0]["deviceId"] as? String)
        XCTAssertNotNil(commands[0]["clientCreatedAt"] as? String)
        let payload = try XCTUnwrap(commands[0]["payload"] as? [String: Any])
        XCTAssertEqual(Set(payload.keys), ["jobId", "to", "arrival"], "Strict server schema: no extra keys")
        XCTAssertEqual(commands[1]["payload"] as? [String: String], ["jobId": jobA, "body": "On site"])
    }

    func testARejectedChangeHoldsLaterChangesToTheSameJobOnly() async throws {
        let box = outbox()
        let refused = try XCTUnwrap(box.enqueue(.progress(.init(jobId: jobA, to: "arrived", arrival: .init(method: "manual"))), policyVersion: 1))
        let later = try XCTUnwrap(box.enqueue(.progress(.init(jobId: jobA, to: "in_progress")), policyVersion: 1))
        let other = try XCTUnwrap(box.enqueue(.note(.init(jobId: jobB, body: "Parts ordered")), policyVersion: 1))
        let reply = #"{"outcomes":[{"commandId":"\#(refused.id)","status":"rejected","category":"conflict","detail":"Job is already completed"},{"commandId":"\#(later.id)","status":"rejected","category":"conflict","detail":"x"},{"commandId":"\#(other.id)","status":"applied","result":{}}]}"#

        await box.drain(api: api([.init(200, reply)]), useCommandEndpoint: true)

        XCTAssertEqual(box.entries.first { $0.id == refused.id }?.state, .rejected("Job is already completed"))
        XCTAssertNotNil(box.entries.first { $0.id == later.id })
        XCTAssertNil(box.entries.first { $0.id == other.id })
        XCTAssertTrue(box.pending.isEmpty)
        XCTAssertEqual(box.needsReview.count, 2)
    }

    func testNoSignalKeepsEverythingQueued() async {
        let box = outbox()
        box.enqueue(.note(.init(jobId: jobA, body: "Still here")), policyVersion: 1)

        await box.drain(api: api([URLProtocolFixture.offline]), useCommandEndpoint: true)

        XCTAssertEqual(box.pending.count, 1)
    }

    func testBatchesAreCappedAtFiftyCommands() async throws {
        let box = outbox()
        for index in 0..<51 { box.enqueue(.note(.init(jobId: jobA, body: "Note \(index)")), policyVersion: 1) }
        let firstIDs = box.pending.prefix(50).map(\.id)
        let reply = #"{"outcomes":["# + firstIDs.map { #"{"commandId":"\#($0)","status":"applied","result":{}}"# }.joined(separator: ",") + "]}"

        await box.drain(api: api([.init(200, reply), URLProtocolFixture.offline]), useCommandEndpoint: true)

        let first = try XCTUnwrap(URLProtocolFixture.recorded.first?.body)
        let commands = try XCTUnwrap((JSONSerialization.jsonObject(with: first) as? [String: Any])?["commands"] as? [Any])
        XCTAssertEqual(commands.count, 50)
        XCTAssertEqual(box.pending.count, 1, "The 51st waits for the next batch")
    }

    func testRESTReplayRejectsAClientErrorAndStopsOnNoSignal() async throws {
        let box = outbox()
        let refused = try XCTUnwrap(box.enqueue(.progress(.init(jobId: jobA, to: "arrived", arrival: .init(method: "manual"))), policyVersion: 1))
        box.enqueue(.note(.init(jobId: jobB, body: "Later")), policyVersion: 1)

        let canceled = #"{"id":"\#(jobA)","organizationId":"\#(org)","customerId":"\#(jobB)","title":"T","status":"canceled","createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z"}"#
        await box.drain(api: api([.init(409, #"{"title":"Conflict","status":409,"detail":"Illegal transition"}"#), .init(200, canceled), URLProtocolFixture.offline]),
                        useCommandEndpoint: false)

        XCTAssertEqual(box.entries.first { $0.id == refused.id }?.state, .rejected("Illegal transition"))
        XCTAssertEqual(box.pending.count, 1)
        XCTAssertEqual(URLProtocolFixture.recorded.map { $0.url?.path }, [
            "/v1/jobs/\(jobA)/progress", "/v1/jobs/\(jobA)", "/v1/jobs/\(jobB)/notes"
        ], "A 409 re-reads the job before calling the step refused")
    }

    func testOfflineStepsOnlyOfferWhatTheServerAllowedFromThatStatus() throws {
        let box = outbox()
        XCTAssertEqual(box.offlineSteps(from: "en_route"), [])
        let json = #"{"id":"\#(jobA)","organizationId":"\#(org)","customerId":"\#(jobB)","title":"T","status":"en_route","createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z","allowedTransitions":["arrived","canceled"]}"#
        box.learn(try JSONDecoder().decode(JobRecord.self, from: Data(json.utf8)))
        XCTAssertEqual(box.offlineSteps(from: "en_route"), ["arrived", "canceled"])
    }

    func testATimedOutStepThatAlreadyLandedIsClearedNotRefused() async throws {
        let box = outbox()
        box.enqueue(.progress(.init(jobId: jobA, to: "en_route")), policyVersion: 1)
        let arrived = #"{"id":"\#(jobA)","organizationId":"\#(org)","customerId":"\#(jobB)","title":"T","status":"arrived","createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z"}"#

        await box.drain(api: api([.init(409, #"{"title":"Conflict","status":409,"detail":"Illegal transition"}"#), .init(200, arrived)]),
                        useCommandEndpoint: false)

        XCTAssertTrue(box.entries.isEmpty)
        XCTAssertEqual(box.lastSyncSent, 1)
    }

    func testDismissingARefusedChangeReleasesTheJobsHeldChanges() throws {
        let box = outbox()
        let refused = try XCTUnwrap(box.enqueue(.progress(.init(jobId: jobA, to: "arrived", arrival: .init(method: "manual"))), policyVersion: 1))
        box.enqueue(.note(.init(jobId: jobA, body: "Held")), policyVersion: 1)
        box.markRejectedForTesting(refused.id, reason: "No")
        XCTAssertTrue(box.pending.isEmpty)

        box.dismiss(try XCTUnwrap(box.entries.first { $0.id == refused.id }))

        XCTAssertEqual(box.pending.map(\.command), ["jobs.addNote"])
    }

    func testAStalePermissionSnapshotFallsBackToTheRESTRoute() async throws {
        let box = outbox()
        let note = try XCTUnwrap(box.enqueue(.note(.init(jobId: jobA, body: "Queued offline")), policyVersion: 1))
        let superseded = #"{"outcomes":[{"commandId":"\#(note.id)","status":"rejected","category":"policy_superseded","detail":"permission snapshot is stale; refresh permissions and retry"}]}"#
        let saved = #"{"id":"019f0000-0000-7000-8000-0000000000c1","organizationId":"\#(org)","jobId":"\#(jobA)","authorUserId":"\#(actor)","body":"Queued offline","createdAt":"2026-10-27T13:00:00Z"}"#

        await box.drain(api: api([.init(200, superseded), .init(201, saved)]), useCommandEndpoint: true)

        XCTAssertTrue(box.entries.isEmpty)
        XCTAssertEqual(URLProtocolFixture.recorded.map { $0.url?.path }, ["/v1/commands", "/v1/jobs/\(jobA)/notes"])
    }
    // MARK: - Closeout, signatures and cash offline (design.thorbis.com/offline)

    private let invoice = "019f0000-0000-7000-8000-0000000000e1"

    private func payment(_ key: String) -> String {
        #"{"id":"019f0000-0000-7000-8000-0000000000f1","organizationId":"\#(org)","invoiceId":"\#(invoice)","amount":{"amount":48000,"currency":"USD"},"method":"cash","status":"recorded","collectionEvidence":{"purpose":"physical_service","source":{"kind":"job","id":"\#(jobA)"}},"idempotencyKey":"\#(key)","recordedAt":"2026-10-28T12:00:00Z"}"#
    }

    func testCloseoutChecksAndCompletionGoThroughTheCommandEndpointWithStrictPayloads() async throws {
        let box = outbox()
        let check = try XCTUnwrap(box.enqueue(.acknowledgeCheck(.init(jobId: jobA, checkKey: "cleanup")), policyVersion: 2, label: "Area cleaned up"))
        let complete = try XCTUnwrap(box.enqueue(.complete(.init(jobId: jobA)), policyVersion: 2))
        XCTAssertEqual(box.pendingStatus(for: jobA), "completed")
        XCTAssertEqual(box.waitingChecks(jobID: jobA), ["cleanup"])
        XCTAssertEqual(check.summary, "Confirmed: Area cleaned up")
        let reply = #"{"outcomes":[{"commandId":"\#(check.id)","status":"applied","result":{}},{"commandId":"\#(complete.id)","status":"applied","result":{}}]}"#

        await box.drain(api: api([.init(200, reply)]), useCommandEndpoint: true)

        XCTAssertTrue(box.entries.isEmpty)
        let body = try XCTUnwrap(URLProtocolFixture.recorded.first?.body)
        let commands = try XCTUnwrap((JSONSerialization.jsonObject(with: body) as? [String: Any])?["commands"] as? [[String: Any]])
        XCTAssertEqual(commands.map { $0["command"] as? String }, ["jobs.acknowledgeCheck", "jobs.complete"])
        XCTAssertEqual(commands[0]["payload"] as? [String: String], ["jobId": jobA, "checkKey": "cleanup"])
        XCTAssertEqual(commands[1]["payload"] as? [String: String], ["jobId": jobA], "No label or empty disposition reaches the strict schema")
    }

    func testCashNeverEntersTheCommandQueueAndLandsInOrderWithItsOwnKey() async throws {
        let box = outbox()
        let note = try XCTUnwrap(box.enqueue(.note(.init(jobId: jobA, body: "Collected cash")), policyVersion: 1))
        let cash = OutboxEntry.PaymentPayload(invoiceId: invoice, jobId: jobA, amountCents: 48000, method: "cash", idempotencyKey: "cash-1")
        let queued = try XCTUnwrap(box.enqueue(.payment(cash), policyVersion: 1))
        XCTAssertEqual(box.enqueue(.payment(cash), policyVersion: 1)?.id, queued.id, "The same collected payment is queued once")
        let complete = try XCTUnwrap(box.enqueue(.complete(.init(jobId: jobA)), policyVersion: 1))
        XCTAssertNil(queued.command)
        XCTAssertEqual(queued.summary, "Cash $480.00")
        XCTAssertEqual(box.waitingPayments(invoiceID: invoice).map(\.amountCents), [48000])

        await box.drain(api: api([
            .init(200, #"{"outcomes":[{"commandId":"\#(note.id)","status":"applied","result":{}}]}"#),
            .init(201, payment("cash-1")),
            .init(200, #"{"outcomes":[{"commandId":"\#(complete.id)","status":"applied","result":{}}]}"#),
        ]), useCommandEndpoint: true)

        XCTAssertTrue(box.entries.isEmpty)
        XCTAssertEqual(box.lastSyncSent, 3)
        XCTAssertEqual(box.syncGeneration, 1, "Open invoice screens reload after a sync")
        XCTAssertEqual(box.recordedPayments.map(\.idempotencyKey), ["cash-1"], "Held until the invoice screen sees it")
        XCTAssertEqual(outbox().recordedPayments.map(\.idempotencyKey), ["cash-1"], "Still held after the app restarts")
        box.forgetRecorded(seen: ["cash-1"])
        XCTAssertTrue(outbox().recordedPayments.isEmpty, "Released once a saved history holds it")
        XCTAssertEqual(URLProtocolFixture.recorded.map { $0.url?.path }, [
            "/v1/commands", "/v1/invoices/\(invoice)/payments", "/v1/commands",
        ], "The payment lands before the completion that may depend on it")
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(URLProtocolFixture.recorded[1].body)) as? [String: Any])
        XCTAssertEqual(sent["idempotencyKey"] as? String, "cash-1")
        XCTAssertEqual(sent["method"] as? String, "cash")
    }

    func testARefusedPaymentWaitsForReviewAndHoldsTheJobsLaterChanges() async throws {
        let box = outbox()
        let cash = try XCTUnwrap(box.enqueue(.payment(.init(invoiceId: invoice, jobId: jobA, amountCents: 48000, method: "cash", idempotencyKey: "cash-2")), policyVersion: 1))
        box.enqueue(.complete(.init(jobId: jobA)), policyVersion: 1)

        await box.drain(api: api([
            .init(422, #"{"title":"Unprocessable","status":422,"detail":"The payment cannot be greater than the invoice balance."}"#),
        ]), useCommandEndpoint: true)

        XCTAssertEqual(box.entries.first { $0.id == cash.id }?.state, .rejected("The payment cannot be greater than the invoice balance."))
        XCTAssertTrue(box.pending.isEmpty, "The completion is held behind the refused payment")
        XCTAssertEqual(box.needsReview.count, 2)
    }

    func testATimedOutPaymentThatAlreadyLandedIsClearedNotRefused() async throws {
        let box = outbox()
        box.enqueue(.payment(.init(invoiceId: invoice, jobId: jobA, amountCents: 48000, method: "cash", idempotencyKey: "cash-3")), policyVersion: 1)

        await box.drain(api: api([
            .init(409, #"{"title":"Conflict","status":409,"detail":"Idempotency key reused"}"#),
            .init(200, #"{"items":[\#(payment("cash-3"))],"nextCursor":null}"#),
        ]), useCommandEndpoint: false)

        XCTAssertTrue(box.entries.isEmpty)
        XCTAssertEqual(box.lastSyncSent, 1)
    }

    func testASignatureKeepsItsInkOnThePhoneUntilItIsSent() throws {
        let box = outbox()
        let asset = UUID().uuidString.lowercased()
        let payload = OutboxEntry.SignaturePayload(jobId: jobA, invoiceId: invoice, expectedLinesRevision: 3, signerName: "Danielle Marlowe",
                                                   signedAt: "2026-10-28T12:00:00Z", clientAssetId: asset)
        let entry = try XCTUnwrap(box.enqueueSignature(Data([0x89, 0x50, 0x4e, 0x47]), payload: payload, policyVersion: 1))
        XCTAssertNil(entry.command)
        XCTAssertEqual(box.signatureData(asset), Data([0x89, 0x50, 0x4e, 0x47]))
        XCTAssertEqual(box.waitingSignature(invoiceID: invoice)?.signerName, "Danielle Marlowe")

        box.dismiss(entry)

        XCTAssertNil(box.signatureData(asset), "Discarding removes the ink with the change")
        XCTAssertNil(box.waitingSignature(invoiceID: invoice))
    }
}

@MainActor
final class OrganizationFactOutboxTests: XCTestCase {
    private let actor = "019f0000-0000-7000-8000-000000000011"
    private let org = "019f0000-0000-7000-8000-000000000001"

    func testAnOfflineCompanyDetailWaitsKeepsOnlyTheNewestValueAndReplaysThroughTheFactsRoute() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("outbox-facts-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let box = FieldOutbox(directory: directory, defaults: UserDefaults(suiteName: "outbox.\(UUID().uuidString)")!)
        box.bind(actorID: actor, organizationID: org)
        box.enqueue(.organizationFact(.init(factKey: "sales_tax_rate", value: "8", label: "Sales tax rate")), policyVersion: 3)
        box.enqueue(.organizationFact(.init(factKey: "sales_tax_rate", value: "8.25", label: "Sales tax rate")), policyVersion: 3)
        XCTAssertEqual(box.pending.count, 1)
        XCTAssertNil(box.pending.first?.command, "Company details replay through REST only")
        XCTAssertEqual(box.pending.first?.jobID, OutboxEntry.organizationRecord)

        let api = APIClient(session: URLProtocolFixture.session([.init(201, "{}")]), baseURL: "https://app.thorbis.com")
        await box.drain(api: api, useCommandEndpoint: true)
        XCTAssertTrue(box.pending.isEmpty)
        let request = try XCTUnwrap(URLProtocolFixture.recorded.last)
        XCTAssertEqual(request.url?.path, "/v1/organization/facts")
        let body = try XCTUnwrap(request.body.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        XCTAssertEqual(body["factKey"] as? String, "sales_tax_rate")
        XCTAssertEqual(body["value"] as? String, "8.25")
        XCTAssertEqual((body["expectedIdentity"] as? [String: String])?["organizationId"], org)
    }
}

@MainActor
final class OrganizationFactDiscardTests: XCTestCase {
    func testAnOnlineSaveDropsTheOlderWaitingValue() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("outbox-discard-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let box = FieldOutbox(directory: directory, defaults: UserDefaults(suiteName: "outbox.\(UUID().uuidString)")!)
        box.bind(actorID: "019f0000-0000-7000-8000-000000000011", organizationID: "019f0000-0000-7000-8000-000000000001")
        box.enqueue(.organizationFact(.init(factKey: "timezone", value: "America/Denver", label: "Time zone")), policyVersion: 1)
        box.enqueue(.organizationFact(.init(factKey: "sales_tax_rate", value: "7", label: "Sales tax rate")), policyVersion: 1)
        box.discardPendingFact("timezone")
        XCTAssertEqual(box.pending.count, 1)
        if case .organizationFact(let fact) = box.pending.first?.action { XCTAssertEqual(fact.factKey, "sales_tax_rate") }
        else { XCTFail("Expected the tax rate to keep waiting") }
    }
}

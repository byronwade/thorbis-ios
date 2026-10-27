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
}

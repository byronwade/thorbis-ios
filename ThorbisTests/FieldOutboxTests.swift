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

    func testFailedDiskWriteDoesNotReportSavedOrDiscardExistingQueue() throws {
        let box = outbox()
        let existing = try XCTUnwrap(box.enqueue(.note(.init(jobId: jobA, body: "Existing")), policyVersion: 1))
        let queue = directory.appendingPathComponent("Outbox")
        let backup = directory.appendingPathComponent("Outbox-backup")
        try FileManager.default.moveItem(at: queue, to: backup)
        try Data("not a directory".utf8).write(to: queue)

        XCTAssertNil(box.enqueue(.note(.init(jobId: jobA, body: "Unsaved")), policyVersion: 1))
        XCTAssertEqual(box.entries.map(\.id), [existing.id])

        try FileManager.default.removeItem(at: queue)
        try FileManager.default.moveItem(at: backup, to: queue)
        XCTAssertEqual(outbox().entries.map(\.id), [existing.id])
    }

    func testUnreadableExistingQueueIsNotOverwrittenByNewNote() throws {
        let queue = directory.appendingPathComponent("Outbox")
        try FileManager.default.createDirectory(at: queue, withIntermediateDirectories: true)
        let file = queue.appendingPathComponent("\(actor)_\(org).json")
        let unreadable = Data("invalid retained queue".utf8)
        try unreadable.write(to: file)
        let box = outbox()

        XCTAssertNil(box.enqueue(.note(.init(jobId: jobA, body: "Unsaved")), policyVersion: 1))
        XCTAssertEqual(try Data(contentsOf: file), unreadable)
        XCTAssertTrue(box.entries.isEmpty)
    }

    func testSignOutWarnsWhenAnyQueueCannotBeRead() throws {
        let queue = directory.appendingPathComponent("Outbox")
        try FileManager.default.createDirectory(at: queue, withIntermediateDirectories: true)
        try Data("invalid".utf8).write(to: queue.appendingPathComponent("other-workspace.json"))
        let box = outbox()
        XCTAssertTrue(box.signOutWarning.contains("could not be read"))
        XCTAssertTrue(box.signOutWarning.contains("Signing out"))
    }

    func testSignOutWarnsWhenQueueDirectoryCannotBeRead() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not a directory".utf8).write(to: directory.appendingPathComponent("Outbox"))
        let box = outbox()
        XCTAssertTrue(box.signOutWarning.contains("could not be read"))
        XCTAssertTrue(box.signOutWarning.contains("Signing out"))
    }

    func testRebindingSameIdentityReloadsPreviouslyUnreadableQueue() throws {
        let first = outbox()
        let saved = try XCTUnwrap(first.enqueue(.note(.init(jobId: jobA, body: "Keep")), policyVersion: 1))
        let file = directory.appendingPathComponent("Outbox/\(actor)_\(org).json")
        let bytes = try Data(contentsOf: file)
        try Data("invalid".utf8).write(to: file)
        let retry = outbox()
        XCTAssertTrue(retry.entries.isEmpty)
        try bytes.write(to: file)
        retry.bind(actorID: actor, organizationID: org)
        XCTAssertEqual(retry.entries.map(\.id), [saved.id])
    }

    func testRetryingNoteReloadsQueueAfterStorageBecomesReadable() throws {
        let first = outbox()
        let saved = try XCTUnwrap(first.enqueue(.note(.init(jobId: jobA, body: "Keep")), policyVersion: 1))
        let file = directory.appendingPathComponent("Outbox/\(actor)_\(org).json")
        let bytes = try Data(contentsOf: file)
        try Data("invalid".utf8).write(to: file)
        let retry = outbox()
        let context = try XCTUnwrap(retry.captureContext(matchingActorID: actor, organizationID: org))
        XCTAssertNil(retry.enqueue(.note(.init(jobId: jobA, body: "New")), policyVersion: 1, matching: context))
        try bytes.write(to: file)
        let new = try XCTUnwrap(retry.enqueue(.note(.init(jobId: jobA, body: "New")), policyVersion: 1, matching: context))
        XCTAssertEqual(outbox().entries.map(\.id), [saved.id, new.id])
    }

    func testRetrySucceedsWhenPreviouslyUnreadableQueueIsDefinitelyAbsent() throws {
        let queue = directory.appendingPathComponent("Outbox")
        try FileManager.default.createDirectory(at: queue, withIntermediateDirectories: true)
        let file = queue.appendingPathComponent("\(actor)_\(org).json")
        try Data("unreadable".utf8).write(to: file)
        let box = outbox()
        let context = try XCTUnwrap(box.captureContext(matchingActorID: actor, organizationID: org))
        XCTAssertNil(box.enqueue(.note(.init(jobId: jobA, body: "New")), policyVersion: 1, matching: context))
        try FileManager.default.removeItem(at: file)
        let saved = try XCTUnwrap(box.enqueue(.note(.init(jobId: jobA, body: "New")), policyVersion: 1, matching: context))
        XCTAssertEqual(outbox().entries.map(\.id), [saved.id])
    }

    func testDirectoryAtQueuePathIsNotTreatedAsMissing() throws {
        let file = directory.appendingPathComponent("Outbox/\(actor)_\(org).json")
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        let box = outbox()
        XCTAssertNil(box.enqueue(.note(.init(jobId: jobA, body: "New")), policyVersion: 1))
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testInitialBindDoesNotAdoptOrOverwriteQueueWithAnotherOwner() throws {
        let foreign = outbox()
        foreign.bind(actorID: "other-actor", organizationID: org)
        try XCTUnwrap(foreign.enqueue(.note(.init(jobId: jobA, body: "Private")), policyVersion: 1))
        let queue = directory.appendingPathComponent("Outbox")
        let foreignFile = queue.appendingPathComponent("other-actor_\(org).json")
        let file = queue.appendingPathComponent("\(actor)_\(org).json")
        let bytes = try Data(contentsOf: foreignFile)
        try bytes.write(to: file)

        let box = outbox()
        XCTAssertTrue(box.entries.isEmpty)
        XCTAssertTrue(box.signOutWarning.contains("could not be read"))
        XCTAssertNil(box.enqueue(.note(.init(jobId: jobA, body: "New")), policyVersion: 1))
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }

    func testInitialBindRejectsQueueFromAnotherWorkspace() throws {
        let foreign = outbox()
        foreign.bind(actorID: actor, organizationID: "other-workspace")
        try XCTUnwrap(foreign.enqueue(.note(.init(jobId: jobA, body: "Private")), policyVersion: 1))
        let queue = directory.appendingPathComponent("Outbox")
        let bytes = try Data(contentsOf: queue.appendingPathComponent("\(actor)_other-workspace.json"))
        let file = queue.appendingPathComponent("\(actor)_\(org).json")
        try bytes.write(to: file)
        let box = outbox()
        XCTAssertTrue(box.entries.isEmpty)
        XCTAssertNil(box.enqueue(.note(.init(jobId: jobA, body: "New")), policyVersion: 1))
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }

    func testDelayedNoteAndProgressCannotEnterAnotherWorkspaceQueue() throws {
        let box = outbox()
        let context = try XCTUnwrap(box.captureContext(matchingActorID: actor, organizationID: org))
        box.bind(actorID: actor, organizationID: "other-workspace")
        XCTAssertNil(box.enqueue(.note(.init(jobId: jobA, body: "Private note")), policyVersion: 1, matching: context))
        XCTAssertNil(box.enqueue(.progress(.init(jobId: jobA, to: "en_route")), policyVersion: 1, matching: context))
        XCTAssertTrue(box.entries.isEmpty)
        box.bind(actorID: actor, organizationID: org)
        XCTAssertNil(box.enqueue(.note(.init(jobId: jobA, body: "Old request")), policyVersion: 1, matching: context))
        XCTAssertTrue(box.entries.isEmpty)
    }

    func testMatchingContextIsReadOnlyAndRedundantVerifiedBindingStaysStable() throws {
        let box = outbox()
        let note = try XCTUnwrap(box.enqueue(.note(.init(jobId: jobA, body: "Retain")), policyVersion: 1))
        let before = box.entries
        let context = try XCTUnwrap(box.captureContext(matchingActorID: actor, organizationID: org))
        XCTAssertNil(box.captureContext(matchingActorID: "other", organizationID: org))
        XCTAssertNil(box.captureContext(matchingActorID: actor, organizationID: "other"))
        XCTAssertEqual(box.entries, before)
        box.bind(actorID: actor, organizationID: org)
        XCTAssertEqual(box.captureContext(matchingActorID: actor, organizationID: org), context)
        XCTAssertEqual(box.entries, before)
        box.bind(actorID: nil, organizationID: nil)
        XCTAssertNil(box.captureContext(matchingActorID: actor, organizationID: org))
        box.bind(actorID: actor, organizationID: org)
        XCTAssertNotEqual(box.captureContext(matchingActorID: actor, organizationID: org), context)
        XCTAssertEqual(box.entries.map(\.id), [note.id])
    }
    func testJobActivityOnlyReadsNotesFromTheMatchingQueueBindingAndJob() throws {
        let box = outbox()
        let note = try XCTUnwrap(box.enqueue(.note(.init(jobId: jobA, body: "Saved offline")), policyVersion: 4))
        box.enqueue(.note(.init(jobId: jobB, body: "Other job")), policyVersion: 4)
        box.enqueue(.progress(.init(jobId: jobA, to: "arrived")), policyVersion: 4)
        XCTAssertEqual(box.activityNotes(for: jobA, actorID: actor, organizationID: org).map(\.id), [note.id])
        XCTAssertTrue(box.activityNotes(for: jobA, actorID: "other", organizationID: org).isEmpty)
        XCTAssertTrue(box.activityNotes(for: jobA, actorID: actor, organizationID: "other").isEmpty)
        box.bind(actorID: nil, organizationID: nil)
        XCTAssertTrue(box.activityNotes(for: jobA, actorID: actor, organizationID: org).isEmpty)
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
    private func waitForRequests(_ count: Int) async throws {
        for _ in 0..<200 {
            if URLProtocolFixture.recorded.count >= count { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Expected intercepted request count \(count)")
    }

    func testDelayedCommandCompletionInvalidatesSavedWorkReview() async throws {
        let reviewGate = SavedWorkMutationGate()
        let box = FieldOutbox(directory: directory, defaults: UserDefaults(suiteName: "outbox.\(UUID().uuidString)")!, mutationGate: reviewGate)
        box.bind(actorID: actor, organizationID: org)
        let note = try XCTUnwrap(box.enqueue(.note(.init(jobId: jobA, body: "Saved")), policyVersion: 1))
        let networkGate = URLProtocolFixture.Gate()
        let reply = #"{"outcomes":[{"commandId":"\#(note.id)","status":"applied"}]}"#
        let client = api([.init(200, reply, gate: networkGate)])
        let pendingDrain = Task { await box.drain(api: client, useCommandEndpoint: true) }
        try await waitForRequests(1)
        let review = reviewGate.beginReview()
        networkGate.release()
        await pendingDrain.value
        XCTAssertTrue(box.entries.isEmpty)
        XCTAssertFalse(reviewGate.performIfCurrent(review) {})
    }

    func testRevocationDuringCommandBatchStopsLaterDelivery() async throws {
        let box = outbox()
        for index in 0..<51 { box.enqueue(.note(.init(jobId: jobA, body: "Note \(index)")), policyVersion: 1) }
        let original = box.entries
        let reply = #"{"outcomes":["# + original.prefix(50).map { #"{"commandId":"\#($0.id)","status":"applied"}"# }.joined(separator: ",") + "]}"
        let gate = URLProtocolFixture.Gate(); var allowed = true
        let client = api([.init(200, reply, gate: gate), URLProtocolFixture.offline])
        let task = Task { await box.drain(api: client, useCommandEndpoint: true, canSend: { allowed }) }
        try await waitForRequests(1); allowed = false; gate.release(); await task.value
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
        XCTAssertEqual(box.entries, original); XCTAssertEqual(box.lastSyncSent, 0)
        XCTAssertEqual(outbox().entries, original)
    }

    func testRevocationDuringRESTStopsNextCommand() async throws {
        let box = outbox()
        box.enqueue(.note(.init(jobId: jobA, body: "First")), policyVersion: 1)
        box.enqueue(.note(.init(jobId: jobB, body: "Second")), policyVersion: 1)
        let original = box.entries
        let saved = #"{"id":"019f0000-0000-7000-8000-0000000000c1","organizationId":"\#(org)","jobId":"\#(jobA)","authorUserId":"\#(actor)","body":"First","createdAt":"2026-10-27T13:00:00Z"}"#
        let gate = URLProtocolFixture.Gate(); var allowed = true
        let client = api([.init(201, saved, gate: gate), URLProtocolFixture.offline])
        let task = Task { await box.drain(api: client, useCommandEndpoint: false, canSend: { allowed }) }
        try await waitForRequests(1); allowed = false; gate.release(); await task.value
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
        XCTAssertEqual(box.entries, original); XCTAssertEqual(outbox().entries, original)
    }

    func testBindingFlipAndReturnCannotCommitOldResponse() async throws {
        let box = outbox()
        let note = try XCTUnwrap(box.enqueue(.note(.init(jobId: jobA, body: "Keep original")), policyVersion: 1))
        let original = box.entries; let gate = URLProtocolFixture.Gate()
        let client = api([.init(200, #"{"outcomes":[{"commandId":"\#(note.id)","status":"applied"}]}"#, gate: gate)])
        let task = Task { await box.drain(api: client, useCommandEndpoint: true) }
        try await waitForRequests(1)
        box.bind(actorID: actor, organizationID: "other")
        box.bind(actorID: actor, organizationID: org)
        gate.release(); await task.value
        XCTAssertEqual(box.entries, original); XCTAssertEqual(outbox().entries, original)
        XCTAssertEqual(box.lastSyncSent, 0)
    }

    func testOldDrainCannotClearNewDrainSendingStateAfterBindingRoundTrip() async throws {
        let box = outbox()
        let note = try XCTUnwrap(box.enqueue(.note(.init(jobId: jobA, body: "Keep original")), policyVersion: 1))
        let oldGate = URLProtocolFixture.Gate(), newGate = URLProtocolFixture.Gate()
        defer { oldGate.release(); newGate.release() }
        let response = #"{"outcomes":[{"commandId":"\#(note.id)","status":"applied"}]}"#
        let client = api([.init(200, response, gate: oldGate), .init(200, response, gate: newGate)])
        let old = Task { await box.drain(api: client, useCommandEndpoint: true) }
        try await waitForRequests(1)
        box.bind(actorID: actor, organizationID: "other")
        box.bind(actorID: actor, organizationID: org)
        let fresh = Task { await box.drain(api: client, useCommandEndpoint: true) }
        try await waitForRequests(2)
        oldGate.release(); await old.value
        XCTAssertTrue(box.syncing, "Old drain's defer must not retire the current sender")
        XCTAssertEqual(box.entries.map(\.id), [note.id])
        newGate.release(); await fresh.value
        XCTAssertFalse(box.syncing); XCTAssertTrue(box.entries.isEmpty)
    }
    func testRevocationBeforeRESTFallbackPreventsRequest() async throws {
        let box = outbox()
        let note = try XCTUnwrap(box.enqueue(.note(.init(jobId: jobA, body: "Queued offline")), policyVersion: 1))
        let original = box.entries; let gate = URLProtocolFixture.Gate(); var allowed = true
        let response = #"{"outcomes":[{"commandId":"\#(note.id)","status":"rejected","category":"policy_superseded"}]}"#
        let client = api([.init(200, response, gate: gate), URLProtocolFixture.offline])
        let task = Task { await box.drain(api: client, useCommandEndpoint: true, canSend: { allowed }) }
        try await waitForRequests(1); allowed = false; gate.release(); await task.value
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
        XCTAssertEqual(box.entries, original); XCTAssertEqual(outbox().entries, original)
    }

    func testRevocationDuringConflictGETPreventsReconciliation() async throws {
        let box = outbox()
        box.enqueue(.progress(.init(jobId: jobA, to: "arrived", arrival: .init(method: "manual"))), policyVersion: 1)
        let original = box.entries; let gate = URLProtocolFixture.Gate(); var allowed = true
        let arrived = #"{"id":"\#(jobA)","organizationId":"\#(org)","customerId":"\#(jobB)","title":"T","status":"arrived","createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z"}"#
        let client = api([.init(409, #"{"title":"Conflict","status":409,"detail":"Conflict"}"#), .init(200, arrived, gate: gate)])
        let task = Task { await box.drain(api: client, useCommandEndpoint: false, canSend: { allowed }) }
        try await waitForRequests(2); allowed = false; gate.release(); await task.value
        XCTAssertEqual(URLProtocolFixture.recorded.count, 2)
        XCTAssertEqual(box.entries, original); XCTAssertEqual(outbox().entries, original)
        XCTAssertEqual(box.lastSyncSent, 0)
    }

    func testCanceledReviewDoesNotRejectOrRemovePendingCommands() async throws {
        let box = outbox()
        let note = try XCTUnwrap(box.enqueue(.note(.init(jobId: jobA, body: "Keep")), policyVersion: 1))
        let original = box.entries; let gate = URLProtocolFixture.Gate()
        let client = api([.init(200, #"{"outcomes":[{"commandId":"\#(note.id)","status":"applied"}]}"#, gate: gate)])
        let task = Task { await box.drain(api: client, useCommandEndpoint: true) }
        try await waitForRequests(1); task.cancel(); gate.release(); await task.value
        XCTAssertEqual(box.entries, original); XCTAssertEqual(outbox().entries, original)
    }

}

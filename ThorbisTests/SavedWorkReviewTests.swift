import XCTest
@testable import Thorbis

@MainActor
final class SavedWorkReviewTests: XCTestCase {
    private let actor = "019f0000-0000-7000-8000-000000000011"
    private let org = "019f0000-0000-7000-8000-000000000001"
    private let jobA = "019f0000-0000-7000-8000-0000000000a1"
    private let jobB = "019f0000-0000-7000-8000-0000000000b1"
    private let itemID = "33333333-3333-4333-8333-333333333333"
    private var root: URL!
    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDown() async throws { try FileManager.default.removeItem(at: root) }
    private var owner: PendingMediaScope { .init(actorID: actor, organizationID: org, origin: "https://app.thorbis.com") }
    private func mediaStore() -> PendingMediaStore {
        let media = PendingMediaStore(directory: root); media.bind(owner); return media
    }
    private func scope(_ media: PendingMediaStore) throws -> SavedWorkScope {
        let box = FieldOutbox(directory: root, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        box.bind(actorID: actor, organizationID: org)
        return SavedWorkScope(id: UUID(), actorID: actor, organizationID: org, normalizedOrigin: owner.origin,
                       sessionGeneration: UUID(), requestGeneration: UUID(), mediaContext: try XCTUnwrap(media.captureContext),
                       outboxContext: try XCTUnwrap(box.captureContext(matchingActorID: actor, organizationID: org)))
    }
    private func command(_ id: String, job: String? = nil, date: Double = 10, state: OutboxEntry.State = .pending, actor: String? = nil, org: String? = nil) -> OutboxEntry {
        .init(id: id, deviceId: "device", actorId: actor ?? self.actor, organizationId: org ?? self.org, policyVersion: 1,
              createdAt: Date(timeIntervalSince1970: date), action: .note(.init(jobId: job ?? jobA, body: "Private note body")), state: state)
    }
    private func photo(_ id: String? = nil, job: String? = nil, date: Double = 10) -> PendingMedia {
        .init(id: id ?? itemID, jobID: job ?? jobA, filename: "before.jpg", tags: ["Before"], capturedAt: Date(timeIntervalSince1970: date), kind: "photo", mime: "image/jpeg")
    }
    private func snapshot(entries: [OutboxEntry] = [], media: [PendingMedia] = [], errors: [String: String] = [:], unverified: Set<String> = [], uploading: String? = nil, syncing: Bool = false, warning: String? = nil) throws -> SavedWorkSnapshot {
        .make(scope: try scope(mediaStore()), entries: entries, media: media, mediaErrors: errors, unverifiedMediaIDs: unverified,
              uploadingMediaID: uploading, commandsSyncing: syncing, jobs: [], listingWarning: warning)
    }
    private func ready(expiry: Date? = nil) async -> (SessionController, APIClient, PendingMediaStore, FieldOutbox) {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let deadline = expiry.map(formatter.string) ?? "2099-10-27T12:00:00Z"
        let sessionJSON = #"{"user":{"id":"\#(actor)","name":"Fixture"},"session":{"userId":"\#(actor)","activeOrganizationId":"\#(org)","expiresAt":"\#(deadline)"}}"#
        let catalog = #"{"authority":{"actorId":"\#(actor)","organizationId":"\#(org)","policyVersion":1,"generation":"fixture"},"capabilities":["job.view","job.edit"],"resources":[],"views":[]}"#
        let features = #"{"organizationId":"\#(org)","evaluatedAt":"2026-10-29T00:00:00Z","features":{"jobs":{"enabled":true,"released":true,"entitled":true}}}"#
        let api = APIClient(session: URLProtocolFixture.session([.init(200, sessionJSON), .init(200, #"[{"id":"\#(org)","name":"Fixture workspace"}]"#), .init(200, catalog), .init(200, features)]), baseURL: owner.origin)
        let session = SessionController(api: api, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await session.restore()
        let media = mediaStore(); let outbox = FieldOutbox(directory: root, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        outbox.bind(actorID: actor, organizationID: org)
        return (session, api, media, outbox)
    }

    func testMixedCommandsAndMediaCountOnceAndKeepTypedIDs() throws {
        let state = try snapshot(entries: [command(itemID)], media: [photo()])
        XCTAssertEqual(state.totalCount, 2)
        XCTAssertEqual(Set(state.groups.flatMap(\.rows).map(\.id)), ["command:33333333-3333-4333-8333-333333333333", "media:33333333-3333-4333-8333-333333333333"])
    }
    func testGroupOrderUsesOldestWorkAndStableTieBreak() throws {
        let state = try snapshot(entries: [command("z", date: 10), command("a", job: jobB, date: 5)], media: [photo(date: 10)])
        XCTAssertEqual(state.groups.map(\.jobID), [jobB, jobA])
        XCTAssertEqual(state.groups.last?.rows.map(\.id), ["command:z", "media:33333333-3333-4333-8333-333333333333"])
        XCTAssertEqual(state.groups.first?.title, "Job")
    }
    func testForeignActorOrWorkspaceCommandsAreAbsent() throws {
        let state = try snapshot(entries: [command("own"), command("foreign-actor", actor: "other"), command("foreign-org", org: "other")])
        XCTAssertEqual(state.groups.flatMap(\.rows).map(\.id), ["command:own"])
        XCTAssertEqual(state.totalCount, 1)
    }
    func testMediaSendingDoesNotRelabelEveryCommand() throws {
        let state = try snapshot(entries: [command("own")], media: [photo()], errors: [itemID: "Old error"], uploading: itemID, syncing: true)
        let rows = state.groups.flatMap(\.rows)
        XCTAssertEqual(rows.first { $0.id == "command:own" }?.state, .waitingToSync)
        XCTAssertEqual(rows.first { $0.id == "media:\(itemID)" }?.state, .uploading)
        XCTAssertTrue(state.isSending); XCTAssertTrue(state.hasPendingWork)
    }
    func testEmptyRowsWhileSenderActiveNeverClaimsSynced() throws {
        let state = try snapshot(syncing: true)
        XCTAssertEqual(state.totalCount, 0); XCTAssertTrue(state.isSending); XCTAssertTrue(state.hasPendingWork)
    }
    func testRefusedHeldAndUnverifiedStayDistinct() throws {
        let state = try snapshot(entries: [command("rejected", state: .rejected("Job changed")), command("held", state: .held)], media: [photo()], unverified: [itemID])
        let rows = Dictionary(uniqueKeysWithValues: state.groups.flatMap(\.rows).map { ($0.id, $0.state) })
        XCTAssertEqual(rows["command:rejected"], .rejected("Job changed"))
        XCTAssertEqual(rows["command:held"], .held)
        XCTAssertEqual(rows["media:\(itemID)"], .needsChecking)
        XCTAssertEqual(state.attentionCount, 3)
    }
    func testEmptyMetadataWithListingWarningNeverClaimsSyncedOrExposesFilename() throws {
        let state = try snapshot(warning: "Foreign customer private-photo.jpg")
        XCTAssertTrue(state.hasListingWarning); XCTAssertTrue(state.hasPendingWork)
        XCTAssertFalse(String(describing: state).contains("private-photo.jpg"))
    }
    func testCaptureRequiresReadyMatchingVerifiedMediaOwner() async throws {
        let (session, api, media, box) = await ready()
        XCTAssertNotNil(SavedWorkScope.capture(session: session, api: api, media: media, outbox: box))
        media.bind(.init(actorID: "other", organizationID: org, origin: owner.origin))
        XCTAssertNil(SavedWorkScope.capture(session: session, api: api, media: media, outbox: box))
    }
    func testScopeFlipAndReturnCannotReuseActionToken() async throws {
        let (session, api, media, box) = await ready()
        let current = SavedWorkScope(id: UUID(), actorID: actor, organizationID: org, normalizedOrigin: owner.origin,
                                     sessionGeneration: session.generation, requestGeneration: api.requestGeneration, mediaContext: try XCTUnwrap(media.captureContext),
                       outboxContext: try XCTUnwrap(box.captureContext(matchingActorID: actor, organizationID: org)))
        XCTAssertTrue(current.isCurrent(session: session, api: api, media: media, outbox: box))
        media.bind(nil); media.bind(owner)
        XCTAssertFalse(current.isCurrent(session: session, api: api, media: media, outbox: box))
    }
    func testDiscardConfirmationRefetchesCurrentRejectedEntry() async throws {
        let (session, api, media, box) = await ready()
        let entry = try XCTUnwrap(box.enqueue(.note(.init(jobId: jobA, body: "Keep me")), policyVersion: 1))
        box.markRejectedForTesting(entry.id, reason: "Conflict")
        let current = try XCTUnwrap(SavedWorkScope.capture(session: session, api: api, media: media, outbox: box))
        box.retry(entry)
        XCTAssertFalse(current.discardCommand(entry.id, session: session, api: api, media: media, outbox: box))
        XCTAssertEqual(box.entries.map(\.id), [entry.id]); XCTAssertEqual(box.entries.first?.state, .pending)
    }
    func testCurrentRejectedDiscardPreservesOtherJobAndReleasesHeld() async throws {
        let (session, api, media, box) = await ready()
        let first = try XCTUnwrap(box.enqueue(.note(.init(jobId: jobA, body: "Discard")), policyVersion: 1))
        let later = try XCTUnwrap(box.enqueue(.note(.init(jobId: jobA, body: "Keep")), policyVersion: 1))
        let other = try XCTUnwrap(box.enqueue(.note(.init(jobId: jobB, body: "Other")), policyVersion: 1))
        box.markRejectedForTesting(first.id, reason: "Conflict")
        let current = try XCTUnwrap(SavedWorkScope.capture(session: session, api: api, media: media, outbox: box))
        XCTAssertTrue(current.discardCommand(first.id, session: session, api: api, media: media, outbox: box))
        XCTAssertEqual(box.entries.map(\.id), [later.id, other.id]); XCTAssertTrue(box.entries.allSatisfy { $0.state == .pending })
    }
    func testCurrentRetryKeepsOriginalIDAndReleasesHeldWithoutDiscardingMedia() async throws {
        let (session, api, media, box) = await ready()
        let first = try XCTUnwrap(box.enqueue(.note(.init(jobId: jobA, body: "Retry")), policyVersion: 1))
        let later = try XCTUnwrap(box.enqueue(.note(.init(jobId: jobA, body: "Later")), policyVersion: 1))
        box.markRejectedForTesting(first.id, reason: "Conflict")
        let current = try XCTUnwrap(SavedWorkScope.capture(session: session, api: api, media: media, outbox: box))
        let before = media.items
        XCTAssertTrue(current.retryCommand(first.id, session: session, api: api, media: media, outbox: box))
        XCTAssertEqual(box.entries.map(\.id), [first.id, later.id])
        XCTAssertTrue(box.entries.allSatisfy { $0.state == .pending })
        XCTAssertEqual(media.items, before)
    }
    func testReadySessionAndMediaCannotCaptureForeignBoundOutboxOrSendIt() async throws {
        let (session, api, media, box) = await ready()
        let current = try XCTUnwrap(SavedWorkScope.capture(session: session, api: api, media: media, outbox: box))
        box.bind(actorID: "other", organizationID: org)
        box.enqueue(.note(.init(jobId: jobA, body: "Other owner's pending note")), policyVersion: 1)
        XCTAssertNil(SavedWorkScope.capture(session: session, api: api, media: media, outbox: box))
        let before = URLProtocolFixture.recorded.count
        await box.drain(api: api, useCommandEndpoint: false, canSend: { current.canEdit(session: session, api: api, media: media, outbox: box) })
        XCTAssertEqual(URLProtocolFixture.recorded.count, before, "No request may leave for the foreign queue")
    }
    func testOutboxOnlyBindingRoundTripRetiresRetryDiscardAndSyncLease() async throws {
        let (session, api, media, box) = await ready()
        let entry = try XCTUnwrap(box.enqueue(.note(.init(jobId: jobA, body: "Keep original")), policyVersion: 1))
        box.markRejectedForTesting(entry.id, reason: "Conflict")
        let original = box.entries
        // Persist the refused fixture before simulating a real binding/reload round trip.
        let file = root.appendingPathComponent("Outbox/\(actor)_\(org).json")
        try JSONEncoder().encode(original).write(to: file)
        let originalBytes = try Data(contentsOf: file)
        let current = try XCTUnwrap(SavedWorkScope.capture(session: session, api: api, media: media, outbox: box))
        box.bind(actorID: "other", organizationID: org)
        box.bind(actorID: actor, organizationID: org)
        XCTAssertFalse(current.isCurrent(session: session, api: api, media: media, outbox: box))
        XCTAssertFalse(current.canEdit(session: session, api: api, media: media, outbox: box))
        XCTAssertFalse(current.retryCommand(entry.id, session: session, api: api, media: media, outbox: box))
        XCTAssertFalse(current.discardCommand(entry.id, session: session, api: api, media: media, outbox: box))
        XCTAssertEqual(box.entries, original)
        XCTAssertEqual(try Data(contentsOf: file), originalBytes)
    }
    func testDirectAPIInvalidationRetiresScopeWithoutChangingSessionIdentity() async throws {
        let (session, api, media, box) = await ready()
        let current = try XCTUnwrap(SavedWorkScope.capture(session: session, api: api, media: media, outbox: box))
        let sessionGeneration = session.generation
        api.invalidateRequests()
        XCTAssertEqual(session.generation, sessionGeneration)
        XCTAssertFalse(current.isCurrent(session: session, api: api, media: media, outbox: box))
        XCTAssertNotNil(SavedWorkScope.capture(session: session, api: api, media: media, outbox: box))
    }
    func testChangedOriginCannotRetryOrDiscardSavedWork() async throws {
        let (session, api, media, box) = await ready()
        let entry = try XCTUnwrap(box.enqueue(.note(.init(jobId: jobA, body: "Keep")), policyVersion: 1))
        box.markRejectedForTesting(entry.id, reason: "Conflict")
        let original = box.entries
        let current = try XCTUnwrap(SavedWorkScope.capture(session: session, api: api, media: media, outbox: box))
        api.baseURL = "http://localhost:9999"
        XCTAssertFalse(current.retryCommand(entry.id, session: session, api: api, media: media, outbox: box))
        XCTAssertFalse(current.discardCommand(entry.id, session: session, api: api, media: media, outbox: box))
        XCTAssertEqual(box.entries, original)
    }
    func testAuthorityDeadlineRetiresScopeAndRefusesDiscard() async throws {
        let (session, api, media, box) = await ready(expiry: Date().addingTimeInterval(2))
        let entry = try XCTUnwrap(box.enqueue(.note(.init(jobId: jobA, body: "Keep")), policyVersion: 1))
        box.markRejectedForTesting(entry.id, reason: "Conflict")
        let original = box.entries
        let current = try XCTUnwrap(SavedWorkScope.capture(session: session, api: api, media: media, outbox: box))
        try await Task.sleep(for: .milliseconds(2100))
        XCTAssertFalse(current.isCurrent(session: session, api: api, media: media, outbox: box))
        XCTAssertFalse(current.discardCommand(entry.id, session: session, api: api, media: media, outbox: box))
        XCTAssertEqual(box.entries, original)
    }
}

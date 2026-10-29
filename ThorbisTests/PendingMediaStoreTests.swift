import XCTest
@testable import Thorbis

@MainActor
final class PendingMediaStoreTests: XCTestCase {
    private var root: URL!
    private let scope = PendingMediaScope(actorID: "actor-a", organizationID: "44444444-4444-4444-8444-444444444444", origin: "https://app.thorbis.com")
    private let job = "11111111-1111-4111-8111-111111111111"
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDown() async throws { try FileManager.default.removeItem(at: root) }
    private func store() -> PendingMediaStore { PendingMediaStore(directory: root) }
    private func media(document: Bool = false) -> PendingMedia {
        PendingMedia(id: UUID().uuidString, jobID: job, filename: document ? "scan.pdf" : "before.jpg", tags: document ? [] : ["Before"], capturedAt: date, kind: document ? "document" : "photo", mime: document ? "application/pdf" : "image/jpeg")
    }
    private func files(_ name: String) -> [URL] {
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!
        return enumerator.compactMap { $0 as? URL }.filter { $0.lastPathComponent == name }
    }

    func testPhotoAndScanRecoverExactBytesAndCaptureIdentityAfterRelaunch() throws {
        let original = store(); original.bind(scope)
        let photo = media(), scan = media(document: true)
        try original.save(photo, data: Data("jpeg".utf8), context: try XCTUnwrap(original.captureContext)); try original.save(scan, data: Data("%PDF-scan".utf8), context: try XCTUnwrap(original.captureContext))
        let relaunched = store(); relaunched.bind(scope)
        XCTAssertEqual(Set(relaunched.items), Set([photo, scan]))
        XCTAssertEqual(try relaunched.read(scan), Data("%PDF-scan".utf8))
        XCTAssertEqual(try relaunched.read(photo), Data("jpeg".utf8))
        XCTAssertEqual(relaunched.items.first { $0.id == scan.id }?.capturedAt, date)
    }

    func testActorOrganizationOriginIsolationAndUnbindRetainOriginalWork() throws {
        let queue = store(); queue.bind(scope)
        let photo = media(); try queue.save(photo, data: Data("jpeg".utf8), context: try XCTUnwrap(queue.captureContext))
        for different in [PendingMediaScope(actorID: "b", organizationID: scope.organizationID, origin: scope.origin),
                          PendingMediaScope(actorID: scope.actorID, organizationID: "other", origin: scope.origin),
                          PendingMediaScope(actorID: scope.actorID, organizationID: scope.organizationID, origin: "http://localhost:3000")] {
            queue.bind(different); XCTAssertTrue(queue.items.isEmpty); XCTAssertThrowsError(try queue.read(photo))
        }
        let oldContext = try XCTUnwrap(queue.captureContext)
        queue.bind(nil); XCTAssertTrue(queue.items.isEmpty); XCTAssertThrowsError(try queue.save(media(), data: Data([1]), context: oldContext))
        queue.bind(scope); XCTAssertEqual(queue.items, [photo]); XCTAssertEqual(try queue.read(photo), Data("jpeg".utf8))
    }

    func testTrustedOriginNormalizationDoesNotBroadenAPITrust() throws {
        let queue = store()
        queue.bind(PendingMediaScope(actorID: scope.actorID, organizationID: scope.organizationID, origin: "https://APP.THORBIS.COM/"))
        let context = try XCTUnwrap(queue.captureContext)
        let scan = media(document: true); try queue.save(scan, data: Data([1]), context: context)
        queue.bind(scope); XCTAssertEqual(queue.items, [scan])
        for untrusted in ["https://evil.example", "https://app.thorbis.com:443", "https://app.thorbis.com/path", "https://user@app.thorbis.com", "https://app.thorbis.com?token=x"] {
            queue.bind(PendingMediaScope(actorID: scope.actorID, organizationID: scope.organizationID, origin: untrusted))
            XCTAssertNil(queue.captureContext); XCTAssertTrue(queue.items.isEmpty)
            XCTAssertThrowsError(try queue.save(media(), data: Data([2]), context: context))
        }
        queue.bind(scope); XCTAssertEqual(queue.items, [scan])
    }

    func testMissingAndCorruptPayloadKeepMetadataAndReportFailure() throws {
        let queue = store(); queue.bind(scope)
        let photo = media(); try queue.save(photo, data: Data("jpeg".utf8), context: try XCTUnwrap(queue.captureContext))
        let payload = try XCTUnwrap(files("payload").first)
        try Data("bad!".utf8).write(to: payload)
        XCTAssertThrowsError(try queue.read(photo)); XCTAssertNotNil(queue.errors[photo.id])
        try FileManager.default.removeItem(at: payload)
        XCTAssertThrowsError(try queue.read(photo)); XCTAssertEqual(queue.items, [photo]); XCTAssertEqual(queue.totalPendingCount, 1)
        let relaunched = store(); relaunched.bind(scope)
        XCTAssertNotNil(relaunched.errors[photo.id]); XCTAssertEqual(relaunched.items, [photo])
    }

    func testFailedCommitDoesNotPublishSavedItemOrEraseExistingQueue() throws {
        let queue = store(); queue.bind(scope)
        let photo = media(); try queue.save(photo, data: Data([1]), context: try XCTUnwrap(queue.captureContext))
        XCTAssertThrowsError(try queue.save(photo, data: Data([2]), context: try XCTUnwrap(queue.captureContext)))
        XCTAssertEqual(try queue.read(photo), Data([1]))
        let blocked = root.appendingPathComponent("blocked")
        try Data([1]).write(to: blocked)
        let failing = PendingMediaStore(directory: blocked); failing.bind(scope)
        XCTAssertThrowsError(try failing.save(media(document: true), data: Data([1]), context: try XCTUnwrap(failing.captureContext)))
        XCTAssertTrue(failing.items.isEmpty); XCTAssertEqual(queue.items, [photo])
    }

    func testMetadataEncodingFailureRemovesOnlyItsStagingPayload() throws {
        let queue = store(); queue.bind(scope)
        let kept = media(); try queue.save(kept, data: Data([1]), context: try XCTUnwrap(queue.captureContext))
        let invalidDate = PendingMedia(id: UUID().uuidString, jobID: job, filename: "scan.pdf", tags: [],
            capturedAt: Date(timeIntervalSince1970: .nan), kind: "document", mime: "application/pdf")
        XCTAssertThrowsError(try queue.save(invalidDate, data: Data("%PDF-synthetic".utf8), context: try XCTUnwrap(queue.captureContext)))
        XCTAssertEqual(queue.items, [kept]); XCTAssertEqual(queue.totalPendingCount, 1)
        XCTAssertEqual(files("payload").count, 1)
        XCTAssertEqual(try queue.read(kept), Data([1]))
    }

    func testCorruptMetadataWarnsWithoutErasingCommittedUnit() throws {
        let queue = store(); queue.bind(scope); try queue.save(media(), data: Data([1]), context: try XCTUnwrap(queue.captureContext))
        let metadata = try XCTUnwrap(files("metadata.json").first)
        try Data("broken".utf8).write(to: metadata)
        let recovered = store(); recovered.bind(scope)
        XCTAssertNotNil(recovered.storageWarning); XCTAssertEqual(recovered.totalPendingCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: metadata.path))
    }

    func testProtectionBackupExclusionAndSignOutLossAcrossScopesAndLegacy() throws {
        let queue = store(); queue.bind(scope); try queue.save(media(), data: Data([1]), context: try XCTUnwrap(queue.captureContext))
        queue.bind(PendingMediaScope(actorID: "other", organizationID: scope.organizationID, origin: scope.origin))
        try queue.save(media(document: true), data: Data([2]), context: try XCTUnwrap(queue.captureContext))
        let legacy = root.appendingPathComponent("PendingPhotos")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data([3]).write(to: legacy.appendingPathComponent("old.jpg"))
        try Data("{}".utf8).write(to: legacy.appendingPathComponent("old.json"))
        queue.reload()
        XCTAssertEqual(queue.totalPendingCount, 3); XCTAssertEqual(queue.legacyCount, 1)
        XCTAssertEqual(queue.items.count, 1)
        let warning = queue.signOutWarning(outboxWarning: "Other workspace changes will be deleted.")
        XCTAssertTrue(warning.contains("3")); XCTAssertTrue(warning.contains("Other workspace changes"))
        for file in files("payload") + files("metadata.json") {
            XCTAssertEqual(try file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        }
        queue.clearAll(); XCTAssertEqual(queue.totalPendingCount, 0); XCTAssertTrue(queue.items.isEmpty)
        let relaunched = store(); relaunched.bind(scope)
        XCTAssertTrue(relaunched.items.isEmpty); XCTAssertEqual(relaunched.totalPendingCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
    }

    func testCommittedFilesUseProtectionUntilFirstUnlock() throws {
        let queue = store(); queue.bind(scope); try queue.save(media(), data: Data([1]), context: try XCTUnwrap(queue.captureContext))
        for file in files("payload") + files("metadata.json") {
            let protection = try FileManager.default.attributesOfItem(atPath: file.path)[.protectionKey] as? FileProtectionType
            #if targetEnvironment(simulator)
            if protection == nil { throw XCTSkip("Simulator does not expose data-protection attributes; verify on physical iPhone.") }
            #endif
            XCTAssertEqual(protection, .completeUntilFirstUserAuthentication)
        }
    }

    func testDelayedCaptureCannotAdoptReboundWorkspaceEvenAfterReturning() async throws {
        let queue = store(); queue.bind(scope)
        let context = try XCTUnwrap(queue.captureContext)
        let scan = media(document: true)
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let callback = Task {
            for await _ in stream {
                try queue.save(scan, data: Data("%PDF-delayed".utf8), context: context)
                return
            }
        }
        queue.bind(PendingMediaScope(actorID: "b", organizationID: "other", origin: scope.origin))
        queue.bind(scope)
        continuation.yield(()); continuation.finish()
        do { try await callback.value; XCTFail("A stale capture cannot adopt a new binding") } catch {}
        XCTAssertTrue(queue.items.isEmpty); XCTAssertEqual(queue.totalPendingCount, 0)
    }

    func testInterruptedCommitRemainsRecoverableAndNeverUploadsAsSaved() async throws {
        let queue = store(); queue.bind(scope); try queue.save(media(), data: Data([1]), context: try XCTUnwrap(queue.captureContext))
        let committed = try XCTUnwrap(files("metadata.json").first).deletingLastPathComponent()
        let staged = committed.deletingLastPathComponent().appendingPathComponent(".staging-interrupted")
        try FileManager.default.moveItem(at: committed, to: staged)
        queue.reload()
        XCTAssertTrue(queue.items.isEmpty); XCTAssertNotNil(queue.storageWarning); XCTAssertEqual(queue.totalPendingCount, 1)
        let network = URLProtocolFixture.session([])
        await queue.drain(api: APIClient(session: network, baseURL: scope.origin), canUpload: { true }, storageSession: network)
        XCTAssertTrue(URLProtocolFixture.recorded.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.appendingPathComponent("payload").path))
    }

    func testInvalidScopeAndDeniedCapabilityNeverRegister() async throws {
        let queue = store(); queue.bind(scope); try queue.save(media(), data: Data("hello".utf8), context: try XCTUnwrap(queue.captureContext))
        let network = URLProtocolFixture.session([])
        let api = APIClient(session: network, baseURL: scope.origin)
        await queue.drain(api: api, canUpload: { false }, storageSession: network)
        XCTAssertTrue(URLProtocolFixture.recorded.isEmpty); XCTAssertEqual(queue.items.count, 1)
        let oldContext = try XCTUnwrap(queue.captureContext)
        queue.bind(PendingMediaScope(actorID: "a", organizationID: "b", origin: "https://evil.example"))
        XCTAssertThrowsError(try queue.save(media(), data: Data([1]), context: oldContext))
    }

    private func asset(_ item: PendingMedia, state: String = "stored") -> String {
        #"{"id":"22222222-2222-4222-8222-222222222222","organizationId":"44444444-4444-4444-8444-444444444444","jobId":"11111111-1111-4111-8111-111111111111","uploaderUserId":"actor-a","kind":"\#(item.kind)","mime":"\#(item.mime)","sizeBytes":5,"originalFilename":"\#(item.filename)","contentHash":"2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824","storageKey":"tenant/jobs/work.jpg","uploadState":"\#(state)","tags":[],"archived":false,"createdAt":"2026-10-26T00:00:00Z","updatedAt":"2026-10-26T00:00:00Z"}"#
    }
    private func registration(_ item: PendingMedia) -> String {
        #"{"asset":\#(asset(item, state: "pending")),"uploadTarget":{"url":"https://storage.example/upload","method":"PUT","expiresAt":"2030-12-31T00:00:00Z","headers":{}}}"#
    }
    private func waitForRequests(_ count: Int) async throws {
        for _ in 0..<200 { if URLProtocolFixture.recorded.count >= count { return }; try await Task.sleep(for: .milliseconds(10)) }
        XCTFail("Expected intercepted request count \(count)")
    }

    func testConcurrentDrainsSendOneStableOperationAndOnlyStoredConfirmationDeletes() async throws {
        let queue = store(); queue.bind(scope)
        let scan = media(document: true); try queue.save(scan, data: Data("hello".utf8), context: try XCTUnwrap(queue.captureContext))
        let gate = URLProtocolFixture.Gate()
        let network = URLProtocolFixture.session([.init(201, registration(scan)), .init(200, "{}", gate: gate), .init(200, asset(scan))])
        let api = APIClient(session: network, baseURL: scope.origin)
        let first = Task { await queue.drain(api: api, canUpload: { true }, storageSession: network) }
        try await waitForRequests(2)
        await queue.drain(api: api, canUpload: { true }, storageSession: network)
        XCTAssertEqual(queue.items.count, 1); XCTAssertEqual(URLProtocolFixture.recorded.count, 2)
        gate.release(); await first.value
        XCTAssertTrue(queue.items.isEmpty); XCTAssertEqual(queue.totalPendingCount, 0)
        let body = try XCTUnwrap(URLProtocolFixture.recorded.first?.body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["clientAssetId"] as? String, scan.id)
        XCTAssertEqual(json["capturedAt"] as? String, "2023-11-14T22:13:20Z")
        XCTAssertEqual(json["kind"] as? String, "document")
    }

    func testWorkspaceChangeDuringFirstUploadStopsSecondAndPreservesBoth() async throws {
        let queue = store(); queue.bind(scope)
        let first = media(), second = media(); try queue.save(first, data: Data("hello".utf8), context: try XCTUnwrap(queue.captureContext)); try queue.save(second, data: Data("hello".utf8), context: try XCTUnwrap(queue.captureContext))
        let firstItem = try XCTUnwrap(queue.items.first)
        let gate = URLProtocolFixture.Gate()
        let network = URLProtocolFixture.session([.init(201, registration(firstItem)), .init(200, "{}", gate: gate), .init(200, asset(firstItem))])
        let api = APIClient(session: network, baseURL: scope.origin)
        let drain = Task { await queue.drain(api: api, canUpload: { true }, storageSession: network) }
        try await waitForRequests(2)
        queue.bind(PendingMediaScope(actorID: "b", organizationID: "other", origin: scope.origin)); api.invalidateRequests()
        gate.release(); await drain.value
        XCTAssertEqual(URLProtocolFixture.recorded.count, 2)
        queue.bind(scope); XCTAssertEqual(queue.items.count, 2)
    }

    func testForeignRegistrationNeverSendsLocalBytes() async throws {
        for (original, replacement) in [(scope.organizationID, "88888888-8888-4888-8888-888888888888"),
                                         (job, "77777777-7777-4777-8777-777777777777"), ("image/jpeg", "application/pdf"), ("photo", "document")] {
            let queue = store(); queue.bind(scope)
            let photo = media(); try queue.save(photo, data: Data("hello".utf8), context: try XCTUnwrap(queue.captureContext))
            let badRegistration = registration(photo).replacingOccurrences(of: original, with: replacement)
            let network = URLProtocolFixture.session([.init(201, badRegistration)])
            let api = APIClient(session: network, baseURL: scope.origin)
            await queue.drain(api: api, canUpload: { true }, storageSession: network)
            XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
            XCTAssertEqual(queue.items, [photo]); XCTAssertNotNil(queue.errors[photo.id])
            XCTAssertEqual(try queue.read(photo), Data("hello".utf8))
            queue.clearAll()
        }
    }

    func testCapabilityRevokedDuringTransferPreservesSavedMedia() async throws {
        let queue = store(); queue.bind(scope)
        let scan = media(document: true); try queue.save(scan, data: Data("hello".utf8), context: try XCTUnwrap(queue.captureContext))
        let gate = URLProtocolFixture.Gate()
        let network = URLProtocolFixture.session([.init(201, registration(scan)), .init(200, "{}", gate: gate), .init(200, asset(scan))])
        let api = APIClient(session: network, baseURL: scope.origin)
        var allowed = true
        let task = Task { await queue.drain(api: api, canUpload: { allowed }, storageSession: network) }
        try await waitForRequests(2)
        allowed = false
        gate.release(); await task.value
        XCTAssertEqual(queue.items, [scan]); XCTAssertEqual(try queue.read(scan), Data("hello".utf8))
        XCTAssertEqual(URLProtocolFixture.recorded.count, 2, "Revoked authority must not confirm")
    }

    func testAmbiguousConfirmationAndRetryPreserveBytesAndClientID() async throws {
        let queue = store(); queue.bind(scope)
        let photo = media(); try queue.save(photo, data: Data("hello".utf8), context: try XCTUnwrap(queue.captureContext))
        let network = URLProtocolFixture.session([.init(201, registration(photo)), .init(200, "{}"), .init(200, asset(photo, state: "pending")),
                                                .init(200, #"{"asset":\#(asset(photo))}"#)])
        let api = APIClient(session: network, baseURL: scope.origin)
        await queue.drain(api: api, canUpload: { true }, storageSession: network)
        XCTAssertEqual(queue.items, [photo]); XCTAssertEqual(try queue.read(photo), Data("hello".utf8)); XCTAssertNotNil(queue.errors[photo.id])
        await queue.drain(api: api, canUpload: { true }, storageSession: network)
        XCTAssertTrue(queue.items.isEmpty)
        let registrations = URLProtocolFixture.recorded.filter { $0.url?.path == "/v1/jobs/\(job)/media" }
        XCTAssertEqual(registrations.count, 2)
        let first = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(registrations[0].body)) as? NSDictionary)
        let second = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(registrations[1].body)) as? NSDictionary)
        XCTAssertEqual(first, second)
    }
    func testRevocationWhileRegisteringNeverStartsPUT() async throws {
        let queue = store(); queue.bind(scope)
        let photo = media(); try queue.save(photo, data: Data("hello".utf8), context: try XCTUnwrap(queue.captureContext))
        let gate = URLProtocolFixture.Gate()
        let network = URLProtocolFixture.session([.init(201, registration(photo), gate: gate), .init(200, "{}"), .init(200, asset(photo))])
        let api = APIClient(session: network, baseURL: scope.origin)
        var allowed = true
        let task = Task { await queue.drain(api: api, canUpload: { allowed }, storageSession: network) }
        try await waitForRequests(1); allowed = false; gate.release(); await task.value
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
        XCTAssertEqual(try queue.read(photo), Data("hello".utf8))
    }

    func testKnownIntegrityFailureSurvivesRebindingAndRelaunchWithoutUploadAuthority() async throws {
        let queue = store(); queue.bind(scope)
        let photo = media(); try queue.save(photo, data: Data("hello".utf8), context: try XCTUnwrap(queue.captureContext))
        let payload = try XCTUnwrap(files("payload").first)
        try Data("wrong".utf8).write(to: payload)
        XCTAssertThrowsError(try queue.read(photo)); XCTAssertNotNil(queue.errors[photo.id])
        queue.bind(.init(actorID: "actor-b", organizationID: scope.organizationID, origin: scope.origin))
        XCTAssertNil(queue.errors[photo.id], "Integrity state must not leak into another actor's scope")
        queue.bind(scope)
        XCTAssertNotNil(queue.errors[photo.id], "Known corruption cannot become saved again")
        let relaunched = store(); relaunched.bind(scope)
        let network = URLProtocolFixture.session([])
        await relaunched.drain(api: APIClient(session: network, baseURL: scope.origin), canUpload: { false }, storageSession: network)
        XCTAssertNotNil(relaunched.errors[photo.id]); XCTAssertEqual(relaunched.items, [photo])
        XCTAssertTrue(URLProtocolFixture.recorded.isEmpty)
    }

    func testRestoredUnverifiedBytesNeverClaimSavedBeforeValidation() throws {
        let queue = store(); queue.bind(scope)
        let scan = media(document: true); try queue.save(scan, data: Data("hello".utf8), context: try XCTUnwrap(queue.captureContext))
        let payload = try XCTUnwrap(files("payload").first)
        try Data("wrong".utf8).write(to: payload)
        let relaunched = store(); relaunched.bind(scope)
        XCTAssertTrue(relaunched.unverifiedIDs.contains(scan.id))
        XCTAssertThrowsError(try relaunched.read(scan)); XCTAssertNotNil(relaunched.errors[scan.id])
    }

    func testCleanupFailureRemainsVisibleAfterUnbind() throws {
        let queue = store(); queue.bind(scope)
        try queue.save(media(), data: Data([1]), context: try XCTUnwrap(queue.captureContext))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path) }
        queue.clearAll()
        XCTAssertNotNil(queue.cleanupWarning, "Real filesystem removal must fail while the parent is read-only")
        queue.bind(nil); queue.reload()
        XCTAssertNotNil(queue.cleanupWarning)
    }

}

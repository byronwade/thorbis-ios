import XCTest
@testable import Thorbis

@MainActor
final class LegacyMediaRecoveryTests: XCTestCase {
    private var root: URL!
    private let job = "11111111-1111-4111-8111-111111111111"
    private let org = "44444444-4444-4444-8444-444444444444"
    private let id = "33333333-3333-4333-8333-333333333333"
    private let date = Date(timeIntervalSince1970: 1_700_000_000)
    private var scope: PendingMediaScope { .init(actorID: "actor-a", organizationID: org, origin: "https://app.thorbis.com") }
    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDown() async throws { try FileManager.default.removeItem(at: root) }
    private var legacy: URL { root.appendingPathComponent("PendingPhotos") }
    private func metadata(id: String? = nil, job: String? = nil) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["id": id ?? self.id, "jobID": job ?? self.job, "filename": "before-original.jpg", "tags": ["Before"], "takenAt": date.timeIntervalSinceReferenceDate])
    }
    private func seed(id: String? = nil, job: String? = nil, bytes: Data = Data("hello".utf8)) throws {
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try metadata(id: id, job: job).write(to: legacy.appendingPathComponent("\(id ?? self.id).json"))
        try bytes.write(to: legacy.appendingPathComponent("\(id ?? self.id).jpg"))
    }
    private func jobBody(id: String? = nil, org: String? = nil) -> String {
        #"{"id":"\#(id ?? job)","organizationId":"\#(org ?? self.org)","customerId":"55555555-5555-4555-8555-555555555555","title":"Verified destination job","status":"dispatched","createdAt":"2026-10-28T00:00:00Z","updatedAt":"2026-10-28T00:00:00Z"}"#
    }
    private func setup(_ replies: [URLProtocolFixture.Reply]) -> (PendingMediaStore, APIClient) {
        let queue = PendingMediaStore(directory: root); queue.bind(scope)
        return (queue, APIClient(session: URLProtocolFixture.session(replies), baseURL: scope.origin))
    }
    private func waitForRequest() async throws {
        for _ in 0..<200 { if !URLProtocolFixture.recorded.isEmpty { return }; try await Task.sleep(for: .milliseconds(10)) }
        XCTFail("Fresh canonical job proof was not requested")
    }

    func testOnlyVerifiedMatchingJobMetadataIsOfferedWithoutAdoption() async throws {
        try seed(); try seed(id: "66666666-6666-4666-8666-666666666666", job: "77777777-7777-4777-8777-777777777777")
        let (queue, api) = setup([.init(200, jobBody())])
        let destination = try await queue.prepareLegacyRecovery(api: api, jobID: job, canUpload: { true })
        XCTAssertEqual(destination.job.title, "Verified destination job")
        XCTAssertEqual(destination.candidates.map(\.id), [id])
        XCTAssertTrue(queue.items.isEmpty); XCTAssertEqual(queue.legacyCount, 2)
        XCTAssertEqual(try Data(contentsOf: legacy.appendingPathComponent("\(id).jpg")), Data("hello".utf8))
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1); XCTAssertEqual(URLProtocolFixture.recorded[0].method, "GET")
        XCTAssertEqual(URLProtocolFixture.recorded[0].cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(URLProtocolFixture.recorded[0].header("Cache-Control"), "no-cache")
    }

    func testExplicitRecoveryPreservesExactIdentityBytesAndDateAndIsIdempotent() async throws {
        try seed()
        let (queue, api) = setup([.init(200, jobBody()), .init(200, jobBody()), .init(200, jobBody())])
        let destination = try await queue.prepareLegacyRecovery(api: api, jobID: job, canUpload: { true })
        let candidate = try XCTUnwrap(destination.candidates.first)
        try await queue.recoverLegacy(candidate, destination: destination, api: api, canUpload: { true })
        XCTAssertEqual(queue.items.count, 1)
        let recovered = try XCTUnwrap(queue.items.first)
        XCTAssertEqual(recovered.id, id); XCTAssertEqual(recovered.jobID, job); XCTAssertEqual(recovered.tags, ["Before"])
        XCTAssertEqual(recovered.capturedAt, date); XCTAssertEqual(recovered.filename, "before-original.jpg")
        XCTAssertEqual(try queue.read(recovered), Data("hello".utf8)); XCTAssertEqual(queue.legacyCount, 0)
        try await queue.recoverLegacy(candidate, destination: destination, api: api, canUpload: { true })
        XCTAssertEqual(queue.items.count, 1); XCTAssertEqual(try queue.read(recovered), Data("hello".utf8))
        XCTAssertTrue(URLProtocolFixture.recorded.allSatisfy { $0.method == "GET" })
    }

    func testForeignOrDeniedDestinationNeverOffersOrAdoptsLegacy() async throws {
        try seed()
        for body in [jobBody(org: "other"), jobBody(id: "77777777-7777-4777-8777-777777777777")] {
            let (queue, api) = setup([.init(200, body)])
            do { _ = try await queue.prepareLegacyRecovery(api: api, jobID: job, canUpload: { true }); XCTFail("Foreign job offered") } catch {}
            XCTAssertTrue(queue.items.isEmpty); XCTAssertEqual(queue.legacyCount, 1)
        }
        let (queue, api) = setup([])
        do { _ = try await queue.prepareLegacyRecovery(api: api, jobID: job, canUpload: { false }); XCTFail("Denied destination offered") } catch {}
        XCTAssertTrue(URLProtocolFixture.recorded.isEmpty)
    }

    func testWorkspaceChangeDuringCanonicalProofNeverExposesLegacy() async throws {
        try seed(); let gate = URLProtocolFixture.Gate()
        let (queue, api) = setup([.init(200, jobBody(), gate: gate)])
        let task = Task { try await queue.prepareLegacyRecovery(api: api, jobID: job, canUpload: { true }) }
        try await waitForRequest()
        queue.bind(.init(actorID: "b", organizationID: org, origin: scope.origin)); gate.release()
        do { _ = try await task.value; XCTFail("Stale job proof exposed legacy") } catch {}
        XCTAssertTrue(queue.items.isEmpty); XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.appendingPathComponent("\(id).jpg").path))
    }

    func testAdoptionRechecksAuthorityAndFreshJobBeforePersisting() async throws {
        try seed()
        let (queue, api) = setup([.init(200, jobBody()), .init(200, jobBody(org: "other"))])
        let destination = try await queue.prepareLegacyRecovery(api: api, jobID: job, canUpload: { true })
        let candidate = try XCTUnwrap(destination.candidates.first)
        do { try await queue.recoverLegacy(candidate, destination: destination, api: api, canUpload: { false }); XCTFail("Revoked recovery") } catch {}
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
        do { try await queue.recoverLegacy(candidate, destination: destination, api: api, canUpload: { true }); XCTFail("Moved destination accepted") } catch {}
        XCTAssertEqual(URLProtocolFixture.recorded.count, 2); XCTAssertTrue(queue.items.isEmpty); XCTAssertEqual(queue.legacyCount, 1)
    }

    func testScopedCollisionAndFailedCommitPreserveLegacyOriginal() async throws {
        try seed()
        let (queue, api) = setup([.init(200, jobBody()), .init(200, jobBody())])
        let destination = try await queue.prepareLegacyRecovery(api: api, jobID: job, canUpload: { true })
        let candidate = try XCTUnwrap(destination.candidates.first)
        try queue.save(candidate.media, data: Data("wrong".utf8), context: try XCTUnwrap(queue.captureContext))
        do { try await queue.recoverLegacy(candidate, destination: destination, api: api, canUpload: { true }); XCTFail("Collision overwritten") } catch {}
        XCTAssertEqual(try queue.read(candidate.media), Data("wrong".utf8))
        XCTAssertEqual(try Data(contentsOf: legacy.appendingPathComponent("\(id).jpg")), Data("hello".utf8))
        queue.clearAll(); queue.bind(scope); try seed()
        let network = URLProtocolFixture.session([.init(200, jobBody()), .init(200, jobBody())])
        let nextAPI = APIClient(session: network, baseURL: scope.origin)
        let next = try await queue.prepareLegacyRecovery(api: nextAPI, jobID: job, canUpload: { true })
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path) }
        do { try await queue.recoverLegacy(try XCTUnwrap(next.candidates.first), destination: next, api: nextAPI, canUpload: { true }); XCTFail("Unwritable destination accepted") } catch {}
        XCTAssertTrue(queue.items.isEmpty); XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.appendingPathComponent("\(id).jpg").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.appendingPathComponent("\(id).json").path))
    }

    func testRevocationDuringAdoptionProofPreservesLegacy() async throws {
        try seed(); let gate = URLProtocolFixture.Gate()
        let (queue, api) = setup([.init(200, jobBody()), .init(200, jobBody(), gate: gate)])
        var allowed = true
        let destination = try await queue.prepareLegacyRecovery(api: api, jobID: job, canUpload: { allowed })
        let candidate = try XCTUnwrap(destination.candidates.first)
        let task = Task { try await queue.recoverLegacy(candidate, destination: destination, api: api, canUpload: { allowed }) }
        for _ in 0..<200 { if URLProtocolFixture.recorded.count == 2 { break }; try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(URLProtocolFixture.recorded.count, 2)
        allowed = false; gate.release()
        do { try await task.value; XCTFail("Revoked recovery committed") } catch {}
        XCTAssertTrue(queue.items.isEmpty); XCTAssertEqual(queue.legacyCount, 1)
    }

    func testUnknownLegacyMetadataRemainsWithoutBeingOffered() async throws {
        try seed()
        try Data("corrupt".utf8).write(to: legacy.appendingPathComponent("\(id).json"))
        let (queue, api) = setup([.init(200, jobBody())])
        let destination = try await queue.prepareLegacyRecovery(api: api, jobID: job, canUpload: { true })
        XCTAssertTrue(destination.candidates.isEmpty); XCTAssertTrue(queue.items.isEmpty); XCTAssertEqual(queue.legacyCount, 1)
        XCTAssertEqual(try Data(contentsOf: legacy.appendingPathComponent("\(id).jpg")), Data("hello".utf8))
    }

    func testInterruptedLegacyCleanupReusesVerifiedScopedCopy() async throws {
        try seed()
        let (queue, api) = setup(Array(repeating: .init(200, jobBody()), count: 6))
        let destination = try await queue.prepareLegacyRecovery(api: api, jobID: job, canUpload: { true })
        let candidate = try XCTUnwrap(destination.candidates.first)
        try await queue.recoverLegacy(candidate, destination: destination, api: api, canUpload: { true })
        for remaining in ["json", "jpg"] {
            // Either older source can remain after interruption; scoped receipt and
            // verified bytes must resume cleanup without creating a new operation.
            try (remaining == "json" ? metadata() : Data("hello".utf8)).write(to: legacy.appendingPathComponent("\(id).\(remaining)"))
            let relaunched = PendingMediaStore(directory: root); relaunched.bind(scope)
            let resumed = try await relaunched.prepareLegacyRecovery(api: api, jobID: job, canUpload: { true })
            try await relaunched.recoverLegacy(try XCTUnwrap(resumed.candidates.first), destination: resumed, api: api, canUpload: { true })
            XCTAssertEqual(relaunched.items.count, 1); XCTAssertEqual(relaunched.legacyCount, 0)
            XCTAssertEqual(try relaunched.read(candidate.media), Data("hello".utf8))
        }
    }
}

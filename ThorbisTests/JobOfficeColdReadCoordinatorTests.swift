import XCTest
import CryptoKit
import Darwin
@testable import Thorbis

@MainActor final class JobOfficeColdReadCoordinatorTests: XCTestCase {
    private final class Markers: JobOfficeColdMarkerStorage {
        var values: [String: Data] = [:]; var failWrites = false
        func read(_ key: String) throws -> Data? { values[key] }
        func write(_ data: Data, key: String) throws { if failWrites { throw CocoaError(.fileWriteNoPermission) }; values[key] = data }
        func removeAll() throws { values.removeAll() }
    }
    private let actor = "018f0000-0000-7000-8000-000000000002"
    private let org = "018f0000-0000-7000-8000-000000000001"
    private let job = "018f0000-0000-7000-8000-000000000003"
    private let session = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased() + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    private func scope(_ deadline: Date) -> JobOfficeColdScope { .init(actor: actor, organization: org, origin: "https://app.thorbis.com", job: job, policyVersion: 3, authorityGeneration: "authority", sessionDigest: session, deadline: deadline) }
    private func record() throws -> JobRecord { try JSONDecoder().decode(JobRecord.self, from: Data("{\"id\":\"\(job)\",\"organizationId\":\"\(org)\",\"customerId\":\"018f0000-0000-7000-8000-000000000004\",\"title\":\"Repair\",\"notes\":\"Office\",\"status\":\"scheduled\",\"createdAt\":\"2026-11-03T00:00:00Z\",\"updatedAt\":\"2026-11-03T00:00:00Z\"}".utf8)) }
    func testStorageFailureNeverStartsLiveRead() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let markers = Markers(); markers.failWrites = true; let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = JobOfficeColdOfflineStore(directory: root, markers: markers, clock: { now })
        let coordinator = JobOfficeColdReadCoordinator(store: store)
        var calls = 0
        let result = await coordinator.read(scope: scope(now.addingTimeInterval(60)), isCurrent: { true }) { calls += 1; return .connectivity }
        XCTAssertEqual(calls, 0)
        guard case .unavailable = result else { return XCTFail("Preflight failure must not issue a read") }
    }
    func testScopeRetirementAfterAwaitCannotPublishOrRestore() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_800_000_000); let store = JobOfficeColdOfflineStore(directory: root, markers: Markers(), clock: { now })
        let coordinator = JobOfficeColdReadCoordinator(store: store); let scope = scope(now.addingTimeInterval(60)); var current = true
        let result = await coordinator.read(scope: scope, isCurrent: { current }) { current = false; return .success(try! self.record()) }
        guard case .retired = result else { return XCTFail("Stale success must not publish") }
        XCTAssertNil(store.offline(scope: scope, authorized: true))
    }
    func testDenialAfterExpiryRetiresPriorGrant() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let start = Date(timeIntervalSince1970: 1_800_000_000); var now = start
        let store = JobOfficeColdOfflineStore(directory: root, markers: Markers(), clock: { now }); let coordinator = JobOfficeColdReadCoordinator(store: store)
        let long = scope(start.addingTimeInterval(100)); let first = try store.beginLive(scope: long)
        _ = try store.completeLive(scope: long, ticket: first, job: record(), stillAuthorized: true)
        let short = scope(start.addingTimeInterval(10))
        let result = await coordinator.read(scope: short, isCurrent: { now < short.deadline }) { now = start.addingTimeInterval(11); return .denied }
        guard case .denied = result else { return XCTFail("The observed denial must be persisted") }
        let renewed = scope(start.addingTimeInterval(120))
        XCTAssertThrowsError(try store.beginLive(scope: renewed))
    }
    func testCanceledReadDoesNotRestorePriorGrantOnNextOfflineAttempt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_800_000_000); let store = JobOfficeColdOfflineStore(directory: root, markers: Markers(), clock: { now })
        let coordinator = JobOfficeColdReadCoordinator(store: store), scope = scope(now.addingTimeInterval(60)); let first = try store.beginLive(scope: scope)
        _ = try store.completeLive(scope: scope, ticket: first, job: record(), stillAuthorized: true)
        let result = await coordinator.read(scope: scope, isCurrent: { true }) { .cancelled }
        guard case .retired = result else { return XCTFail("Canceled attempt must be abandoned") }
        let next = await coordinator.read(scope: scope, isCurrent: { true }) { .connectivity }
        guard case .unavailable = next else { return XCTFail("Canceled attempt must not restore an old grant") }
    }
    func testDenialAfterScopeRetirementStillBlocksOldGrant() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_800_000_000); let store = JobOfficeColdOfflineStore(directory: root, markers: Markers(), clock: { now })
        let coordinator = JobOfficeColdReadCoordinator(store: store), scope = scope(now.addingTimeInterval(60)); let first = try store.beginLive(scope: scope)
        _ = try store.completeLive(scope: scope, ticket: first, job: record(), stillAuthorized: true)
        var current = true
        let result = await coordinator.read(scope: scope, isCurrent: { current }) { current = false; return .denied }
        guard case .denied = result else { return XCTFail("Late denial must retire the captured identity") }
        XCTAssertThrowsError(try store.beginLive(scope: scope))
    }
    func testTaskCancellationAfterFetchAbandonsGrant() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_800_000_000); let store = JobOfficeColdOfflineStore(directory: root, markers: Markers(), clock: { now })
        let coordinator = JobOfficeColdReadCoordinator(store: store), scope = scope(now.addingTimeInterval(60)); let first = try store.beginLive(scope: scope)
        _ = try store.completeLive(scope: scope, ticket: first, job: record(), stillAuthorized: true)
        let task = Task { @MainActor in
            await coordinator.read(scope: scope, isCurrent: { true }) {
                withUnsafeCurrentTask { $0?.cancel() }
                return .connectivity
            }
        }
        guard case .retired = await task.value else { return XCTFail("Canceled task must not restore") }
        let next = await coordinator.read(scope: scope, isCurrent: { true }) { .connectivity }
        guard case .unavailable = next else { return XCTFail("Canceled attempt must be abandoned") }
    }
    func testDenialStorageFailureDoesNotExposeOldGrant() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_800_000_000), markers = Markers()
        let store = JobOfficeColdOfflineStore(directory: root, markers: markers, clock: { now }, writeDenial: { _, _ in throw CocoaError(.fileWriteNoPermission) })
        let coordinator = JobOfficeColdReadCoordinator(store: store), scope = scope(now.addingTimeInterval(60)); let first = try store.beginLive(scope: scope)
        _ = try store.completeLive(scope: scope, ticket: first, job: record(), stillAuthorized: true)
        let result = await coordinator.read(scope: scope, isCurrent: { true }) { .denied }
        guard case .unavailable = result else { return XCTFail("Failed denial persistence must fail closed") }
        XCTAssertNil(store.offline(scope: scope, authorized: true))
        XCTAssertThrowsError(try store.beginLive(scope: scope), "A failed marker write must keep this identity unavailable")
    }
    func testDenialSurvivesContendedScopeLock() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_800_000_000); let store = JobOfficeColdOfflineStore(directory: root, markers: Markers(), clock: { now })
        let coordinator = JobOfficeColdReadCoordinator(store: store), scope = scope(now.addingTimeInterval(60)); let first = try store.beginLive(scope: scope)
        _ = try store.completeLive(scope: scope, ticket: first, job: record(), stillAuthorized: true)
        let fields = [scope.actor, scope.organization, scope.origin, scope.job, scope.sessionDigest]
        let key = SHA256.hash(data: Data(fields.map { "\($0.utf8.count):\($0)" }.joined().utf8)).map { String(format: "%02x", $0) }.joined()
        var descriptor: Int32 = -1
        let result = await coordinator.read(scope: scope, isCurrent: { true }) {
            descriptor = open(root.appendingPathComponent("\(key).lock").path, O_RDWR)
            guard descriptor >= 0, flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { return .failed }
            return .denied
        }
        guard descriptor >= 0 else { return XCTFail("Could not acquire contention lock") }
        _ = flock(descriptor, LOCK_UN); close(descriptor)
        guard case .denied = result else { return XCTFail("Denial must survive lock contention") }
        XCTAssertNil(store.offline(scope: scope, authorized: true))
        XCTAssertThrowsError(try store.beginLive(scope: scope))
    }
}

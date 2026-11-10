import XCTest
import Darwin
import Security
@testable import Thorbis

@MainActor final class JobOfficeColdOfflineStoreTests: XCTestCase {
    private let actor = "018f0000-0000-7000-8000-000000000002"
    private let org = "018f0000-0000-7000-8000-000000000001"
    private let job = "018f0000-0000-7000-8000-000000000003"
    private let authority = UUID().uuidString
    private final class Markers: JobOfficeColdMarkerStorage {
        var values: [String: Data] = [:]
        var failReads = false
        var failWrites = false
        var failDeletes = false
        func read(_ key: String) throws -> Data? { if failReads { throw CocoaError(.fileReadNoPermission) }; return values[key] }
        func write(_ data: Data, key: String) throws { if failWrites { throw CocoaError(.fileWriteNoPermission) }; values[key] = data }
        func removeAll() throws { if failDeletes { throw CocoaError(.fileWriteNoPermission) }; values.removeAll() }
    }
    private func scope(deadline: Date) -> JobOfficeColdScope {
        .init(actor: actor, organization: org, origin: "https://app.thorbis.com", job: job, policyVersion: 3, authorityGeneration: authority, sessionDigest: String(repeating: "a", count: 64), deadline: deadline)
    }
    private func record() throws -> JobRecord {
        try JSONDecoder().decode(JobRecord.self, from: Data("{\"id\":\"\(job)\",\"organizationId\":\"\(org)\",\"customerId\":\"018f0000-0000-7000-8000-000000000004\",\"title\":\"Repair\",\"notes\":\"Office instructions\",\"status\":\"scheduled\",\"createdAt\":\"2026-11-03T00:00:00Z\",\"updatedAt\":\"2026-11-03T00:00:00Z\"}".utf8))
    }
    func testColdReopenAndExpiry() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let markers = Markers(); let now = Date(timeIntervalSince1970: 1_800_000_000)
        let scope = scope(deadline: now.addingTimeInterval(60))
        let store = JobOfficeColdOfflineStore(directory: directory, markers: markers, clock: { now })
        let ticket = try store.beginLive(scope: scope)
        let saved = try XCTUnwrap(store.completeLive(scope: scope, ticket: ticket, job: record(), stillAuthorized: true))
        let reopened = JobOfficeColdOfflineStore(directory: directory, markers: markers, clock: { now })
        XCTAssertEqual(reopened.offline(scope: scope, authorized: true)?.epoch, saved.epoch)
        let differentSession = JobOfficeColdScope(actor: actor, organization: org, origin: "https://app.thorbis.com", job: job, policyVersion: 3, authorityGeneration: authority, sessionDigest: String(repeating: "b", count: 64), deadline: now.addingTimeInterval(60))
        XCTAssertNil(reopened.offline(scope: differentSession, authorized: true))
        let rawSession = JobOfficeColdScope(actor: actor, organization: org, origin: "https://app.thorbis.com", job: job, policyVersion: 3, authorityGeneration: authority, sessionDigest: "raw-session-id", deadline: now.addingTimeInterval(60))
        XCTAssertThrowsError(try reopened.beginLive(scope: rawSession))
        let expired = JobOfficeColdOfflineStore(directory: directory, markers: markers, clock: { now.addingTimeInterval(61) })
        XCTAssertNil(expired.offline(scope: scope, authorized: true))
    }
    func testWriteAheadDenialAndCrashSurviveReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let markers = Markers(); let now = Date(timeIntervalSince1970: 1_800_000_000); let scope = scope(deadline: now.addingTimeInterval(60))
        let store = JobOfficeColdOfflineStore(directory: directory, markers: markers, clock: { now })
        let first = try store.beginLive(scope: scope)
        _ = try store.completeLive(scope: scope, ticket: first, job: record(), stillAuthorized: true)
        let pending = try store.beginLive(scope: scope)
        XCTAssertNil(JobOfficeColdOfflineStore(directory: directory, markers: markers, clock: { now }).offline(scope: scope, authorized: true))
        try store.deny(scope: scope)
        XCTAssertNil(try store.completeLive(scope: scope, ticket: pending, job: record(), stillAuthorized: true))
        XCTAssertNil(JobOfficeColdOfflineStore(directory: directory, markers: markers, clock: { now }).offline(scope: scope, authorized: true))
    }
    func testKeychainFailureCannotStartAReadOrReturnACopy() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let markers = Markers(); let now = Date(timeIntervalSince1970: 1_800_000_000); let scope = scope(deadline: now.addingTimeInterval(60))
        let store = JobOfficeColdOfflineStore(directory: directory, markers: markers, clock: { now })
        markers.failWrites = true
        XCTAssertThrowsError(try store.beginLive(scope: scope))
        XCTAssertNil(store.offline(scope: scope, authorized: true))
        markers.failWrites = false; markers.failReads = true
        XCTAssertNil(store.offline(scope: scope, authorized: true))
    }
    func testFailedMarkerWriteAfterGrantLeavesDurableBarrier() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let markers = Markers(); let now = Date(timeIntervalSince1970: 1_800_000_000); let scope = scope(deadline: now.addingTimeInterval(60))
        let store = JobOfficeColdOfflineStore(directory: directory, markers: markers, clock: { now })
        let ticket = try store.beginLive(scope: scope)
        _ = try store.completeLive(scope: scope, ticket: ticket, job: record(), stillAuthorized: true)
        markers.failWrites = true
        XCTAssertThrowsError(try store.beginLive(scope: scope))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.hasSuffix(".barrier") })
        markers.failWrites = false
        XCTAssertNil(JobOfficeColdOfflineStore(directory: directory, markers: markers, clock: { now }).offline(scope: scope, authorized: true))
    }
    func testLockedScopeFailsClosedWithoutBlockingOtherScope() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let markers = Markers(); let now = Date(timeIntervalSince1970: 1_800_000_000); let scope = scope(deadline: now.addingTimeInterval(60))
        let store = JobOfficeColdOfflineStore(directory: directory, markers: markers, clock: { now })
        _ = try store.beginLive(scope: scope)
        let name = try XCTUnwrap(FileManager.default.contentsOfDirectory(atPath: directory.path).first { $0.hasSuffix(".lock") && $0 != "retire.lock" })
        let descriptor = open(directory.appendingPathComponent(name).path, O_RDWR)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { _ = flock(descriptor, LOCK_UN); close(descriptor) }
        XCTAssertEqual(flock(descriptor, LOCK_EX | LOCK_NB), 0)
        XCTAssertThrowsError(try store.beginLive(scope: scope))
        XCTAssertNil(store.offline(scope: scope, authorized: true))
        let other = JobOfficeColdScope(actor: actor, organization: org, origin: "https://app.thorbis.com", job: job, policyVersion: 3, authorityGeneration: UUID().uuidString, sessionDigest: String(repeating: "a", count: 64), deadline: now.addingTimeInterval(60))
        XCTAssertNoThrow(try store.beginLive(scope: other))
    }
    func testActualKeychainAdapterCanReadAndUpdate() throws {
        let service = "com.thorbis.test.office-\(UUID().uuidString)"
        let otherService = "com.thorbis.test.office-\(UUID().uuidString)"
        let marker = JobOfficeColdKeychain(service: service)
        let other = JobOfficeColdKeychain(service: otherService)
        defer { SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary) }
        defer { SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: otherService] as CFDictionary) }
        XCTAssertNil(try marker.read("key"))
        try marker.write(Data("pending".utf8), key: "key")
        XCTAssertEqual(try marker.read("key"), Data("pending".utf8))
        try marker.write(Data("denied".utf8), key: "key")
        XCTAssertEqual(try marker.read("key"), Data("denied".utf8))
        try other.write(Data("other".utf8), key: "key")
        try marker.removeAll()
        XCTAssertNil(try marker.read("key"))
        XCTAssertEqual(try other.read("key"), Data("other".utf8))
    }
    func testChangedSnapshotAndExpiredAuthorityAreNeverServed() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let markers = Markers(); let now = Date(timeIntervalSince1970: 1_800_000_000); let scope = scope(deadline: now.addingTimeInterval(60))
        let store = JobOfficeColdOfflineStore(directory: directory, markers: markers, clock: { now })
        let ticket = try store.beginLive(scope: scope)
        _ = try store.completeLive(scope: scope, ticket: ticket, job: record(), stillAuthorized: true)
        let saved = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first { $0.pathExtension == "json" })
        try Data("tampered".utf8).write(to: saved)
        XCTAssertNil(store.offline(scope: scope, authorized: true))
        XCTAssertNil(JobOfficeColdOfflineStore(directory: directory, markers: markers, clock: { now.addingTimeInterval(61) }).offline(scope: scope, authorized: true))
    }
    func testSnapshotWriteFailureLeavesPendingAndDoesNotGrant() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let markers = Markers(); let now = Date(timeIntervalSince1970: 1_800_000_000); let scope = scope(deadline: now.addingTimeInterval(60))
        let store = JobOfficeColdOfflineStore(directory: directory, markers: markers, clock: { now }, writeSnapshot: { _, _ in throw CocoaError(.fileWriteNoPermission) })
        let ticket = try store.beginLive(scope: scope)
        XCTAssertThrowsError(try store.completeLive(scope: scope, ticket: ticket, job: record(), stillAuthorized: true))
        XCTAssertNil(JobOfficeColdOfflineStore(directory: directory, markers: markers, clock: { now }).offline(scope: scope, authorized: true))
    }
    func testSnapshotReplacementCleanupFailureLeavesPendingAndNoGrant() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let markers = Markers(); let now = Date(timeIntervalSince1970: 1_800_000_000); let scope = scope(deadline: now.addingTimeInterval(60))
        let store = JobOfficeColdOfflineStore(directory: directory, markers: markers, clock: { now }, removeSnapshot: { _ in throw CocoaError(.fileWriteNoPermission) })
        let first = try store.beginLive(scope: scope)
        _ = try store.completeLive(scope: scope, ticket: first, job: record(), stillAuthorized: true)
        let second = try store.beginLive(scope: scope)
        XCTAssertThrowsError(try store.completeLive(scope: scope, ticket: second, job: record(), stillAuthorized: true))
        XCTAssertNil(store.offline(scope: scope, authorized: true))
    }
    func testLatestAttemptAloneCanRestoreAndDenialWins() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let markers = Markers(); let now = Date(timeIntervalSince1970: 1_800_000_000); let scope = scope(deadline: now.addingTimeInterval(60))
        let store = JobOfficeColdOfflineStore(directory: directory, markers: markers, clock: { now })
        let first = try store.beginLive(scope: scope)
        let saved = try XCTUnwrap(store.completeLive(scope: scope, ticket: first, job: record(), stillAuthorized: true))
        let old = try store.beginLive(scope: scope), current = try store.beginLive(scope: scope)
        XCTAssertNil(try store.restoreAfterConnectivityFailure(scope: scope, ticket: old, stillAuthorized: true))
        XCTAssertEqual(try store.restoreAfterConnectivityFailure(scope: scope, ticket: current, stillAuthorized: true)?.epoch, saved.epoch)
        let pending = try store.beginLive(scope: scope)
        try store.deny(scope: scope)
        XCTAssertNil(try store.restoreAfterConnectivityFailure(scope: scope, ticket: pending, stillAuthorized: true))
        XCTAssertNil(store.offline(scope: scope, authorized: true))
    }
    func testRetirementRevokesGrantsAndPreventsLateCompletion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let markers = Markers(); let now = Date(timeIntervalSince1970: 1_800_000_000); let scope = scope(deadline: now.addingTimeInterval(60))
        let store = JobOfficeColdOfflineStore(directory: directory, markers: markers, clock: { now })
        let first = try store.beginLive(scope: scope)
        _ = try store.completeLive(scope: scope, ticket: first, job: record(), stillAuthorized: true)
        let pending = try store.beginLive(scope: scope)
        try store.retireAll()
        XCTAssertNil(try store.completeLive(scope: scope, ticket: pending, job: record(), stillAuthorized: true))
        XCTAssertNil(JobOfficeColdOfflineStore(directory: directory, markers: markers, clock: { now }).offline(scope: scope, authorized: true))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.hasSuffix(".json") })
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.hasSuffix(".lock") })
    }
    func testFailedRetirementLeavesDurableHoldUntilSuccessfulRetry() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let markers = Markers(); let now = Date(timeIntervalSince1970: 1_800_000_000); let scope = scope(deadline: now.addingTimeInterval(60))
        let store = JobOfficeColdOfflineStore(directory: directory, markers: markers, clock: { now })
        let ticket = try store.beginLive(scope: scope)
        _ = try store.completeLive(scope: scope, ticket: ticket, job: record(), stillAuthorized: true)
        markers.failDeletes = true
        XCTAssertThrowsError(try store.retireAll())
        markers.failDeletes = false
        XCTAssertNil(JobOfficeColdOfflineStore(directory: directory, markers: markers, clock: { now }).offline(scope: scope, authorized: true))
        try store.retireAll()
        XCTAssertNil(JobOfficeColdOfflineStore(directory: directory, markers: markers, clock: { now }).offline(scope: scope, authorized: true))
    }
    func testRetirementWaitsForOtherProcessReaders() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let markers = Markers(); let now = Date(timeIntervalSince1970: 1_800_000_000); let scope = scope(deadline: now.addingTimeInterval(60))
        let store = JobOfficeColdOfflineStore(directory: directory, markers: markers, clock: { now })
        _ = try store.beginLive(scope: scope)
        let fd = open(directory.appendingPathComponent("retire.lock").path, O_RDWR)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { _ = flock(fd, LOCK_UN); close(fd) }
        XCTAssertEqual(flock(fd, LOCK_SH | LOCK_NB), 0)
        XCTAssertThrowsError(try store.retireAll())
    }
}

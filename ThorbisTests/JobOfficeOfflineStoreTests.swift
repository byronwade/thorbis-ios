import XCTest
import Combine
@testable import Thorbis

@MainActor
final class JobOfficeOfflineStoreTests: XCTestCase {
    private let session = UUID()
    private let authority = UUID()
    private let api = UUID()
    private let actor = "018f0000-0000-7000-8000-000000000002"
    private let organization = "018f0000-0000-7000-8000-000000000001"
    private let job = "018f0000-0000-7000-8000-000000000003"
    private func scope(policy: Int = 3) -> JobOfficeOfflineScope {
        .init(actor: actor, organization: organization, origin: "https://app.thorbis.com", job: job, policyVersion: policy, authorityGeneration: "authority", session: session, authority: authority, api: api)
    }
    private func record() throws -> JobRecord {
        let json = """
        {"id":"\(job)","organizationId":"\(organization)","customerId":"018f0000-0000-7000-8000-000000000004","title":"Repair","notes":"Office instructions","status":"scheduled","createdAt":"2026-11-03T00:00:00Z","updatedAt":"2026-11-03T00:00:00Z"}
        """
        return try JSONDecoder().decode(JobRecord.self, from: Data(json.utf8))
    }
    func testScopedSuccessSurvivesRecreationButNotPolicyOrTenantChanges() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = JobOfficeOfflineStore(directory: root)
        let ticket = try store.beginLive(scope: scope())
        let snapshot = try XCTUnwrap(store.completeLive(scope: scope(), ticket: ticket, job: record(), stillAuthorized: true))
        let reopened = JobOfficeOfflineStore(directory: root)
        XCTAssertEqual(reopened.offline(scope: scope(), authorized: true)?.epoch, snapshot.epoch)
        XCTAssertNil(reopened.offline(scope: scope(policy: 4), authorized: true))
        XCTAssertNil(reopened.offline(scope: scope(), authorized: false))
        let foreign = JobOfficeOfflineScope(actor: actor, organization: "018f0000-0000-7000-8000-000000000099", origin: "https://app.thorbis.com", job: job, policyVersion: 3, authorityGeneration: "authority", session: session, authority: authority, api: api)
        XCTAssertNil(reopened.offline(scope: foreign, authorized: true))
        let changedAuthority = JobOfficeOfflineScope(actor: actor, organization: organization, origin: "https://app.thorbis.com", job: job, policyVersion: 3, authorityGeneration: "authority", session: session, authority: UUID(), api: api)
        XCTAssertNil(reopened.offline(scope: changedAuthority, authorized: true))
        let changedAPI = JobOfficeOfflineScope(actor: actor, organization: organization, origin: "https://app.thorbis.com", job: job, policyVersion: 3, authorityGeneration: "authority", session: session, authority: authority, api: UUID())
        XCTAssertNil(reopened.offline(scope: changedAPI, authorized: true))
    }
    func testDenialAndInflightHoldSurviveRecreationAndRejectLateSuccess() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = JobOfficeOfflineStore(directory: root)
        let first = try store.beginLive(scope: scope())
        _ = try store.completeLive(scope: scope(), ticket: first, job: record(), stillAuthorized: true)
        let pending = try store.beginLive(scope: scope())
        XCTAssertNil(JobOfficeOfflineStore(directory: root).offline(scope: scope(), authorized: true))
        try store.deny(scope: scope())
        XCTAssertNil(try store.completeLive(scope: scope(), ticket: pending, job: record(), stillAuthorized: true))
        XCTAssertNil(JobOfficeOfflineStore(directory: root).offline(scope: scope(), authorized: true))
    }
    func testPersistenceFailureDoesNotIssueTicketOrServeCopy() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = JobOfficeOfflineStore(directory: root, write: { _, _ in throw CocoaError(.fileWriteNoPermission) })
        XCTAssertThrowsError(try store.beginLive(scope: scope()))
        XCTAssertNil(store.offline(scope: scope(), authorized: true))
    }
    func testPreflightWriteFailureSuppressesAnExistingGrantAcrossInstances() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let initial = JobOfficeOfflineStore(directory: root)
        let ticket = try initial.beginLive(scope: scope())
        _ = try initial.completeLive(scope: scope(), ticket: ticket, job: record(), stillAuthorized: true)
        let failing = JobOfficeOfflineStore(directory: root, write: { _, _ in throw CocoaError(.fileWriteNoPermission) })
        XCTAssertThrowsError(try failing.beginLive(scope: scope()))
        XCTAssertNil(JobOfficeOfflineStore(directory: root).offline(scope: scope(), authorized: true))
        let newSession = JobOfficeOfflineScope(actor: actor, organization: organization, origin: "https://app.thorbis.com", job: job, policyVersion: 3, authorityGeneration: "authority", session: UUID(), authority: authority, api: api)
        XCTAssertNil(JobOfficeOfflineStore(directory: root).offline(scope: newSession, authorized: true))
    }
    func testConnectivityRestoresOnlyLatestVerifiedSnapshotAndDenialPreventsRestore() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = JobOfficeOfflineStore(directory: root)
        let first = try store.beginLive(scope: scope())
        let saved = try XCTUnwrap(store.completeLive(scope: scope(), ticket: first, job: record(), stillAuthorized: true))
        let pending = try store.beginLive(scope: scope())
        XCTAssertEqual(try store.restoreAfterConnectivityFailure(scope: scope(), ticket: pending, stillAuthorized: true)?.epoch, saved.epoch)
        let next = try store.beginLive(scope: scope())
        try store.deny(scope: scope())
        XCTAssertNil(try store.restoreAfterConnectivityFailure(scope: scope(), ticket: next, stillAuthorized: true))
        let retry = try store.beginLive(scope: scope())
        XCTAssertNil(try store.restoreAfterConnectivityFailure(scope: scope(), ticket: retry, stillAuthorized: true))
    }
    func testMismatchedJobAndOverlappingTicketsCannotGrantAccess() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = JobOfficeOfflineStore(directory: root)
        let old = try store.beginLive(scope: scope())
        let current = try store.beginLive(scope: scope())
        XCTAssertNil(try store.completeLive(scope: scope(), ticket: old, job: record(), stillAuthorized: true))
        XCTAssertNil(try store.completeLive(scope: scope(), ticket: current, job: record(), stillAuthorized: false))
        let foreign = try JSONDecoder().decode(JobRecord.self, from: Data("{\"id\":\"018f0000-0000-7000-8000-000000000099\",\"organizationId\":\"\(organization)\",\"customerId\":\"018f0000-0000-7000-8000-000000000004\",\"title\":\"Repair\",\"status\":\"scheduled\",\"createdAt\":\"2026-11-03T00:00:00Z\",\"updatedAt\":\"2026-11-03T00:00:00Z\"}".utf8))
        XCTAssertThrowsError(try store.completeLive(scope: scope(), ticket: current, job: foreign, stillAuthorized: true))
        XCTAssertNil(store.offline(scope: scope(), authorized: true))
    }
    func testNewestOverlappingConnectivityFailureCanRestorePriorVerifiedSnapshot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = JobOfficeOfflineStore(directory: root)
        let first = try store.beginLive(scope: scope())
        let snapshot = try XCTUnwrap(store.completeLive(scope: scope(), ticket: first, job: record(), stillAuthorized: true))
        let old = try store.beginLive(scope: scope())
        let current = try store.beginLive(scope: scope())
        XCTAssertNil(try store.restoreAfterConnectivityFailure(scope: scope(), ticket: old, stillAuthorized: true))
        XCTAssertEqual(try store.restoreAfterConnectivityFailure(scope: scope(), ticket: current, stillAuthorized: true)?.epoch, snapshot.epoch)
    }
    func testLateDenialWinsUntilAnotherVerifiedLiveRead() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = JobOfficeOfflineStore(directory: root)
        _ = try store.beginLive(scope: scope())
        let newer = try store.beginLive(scope: scope())
        XCTAssertNotNil(try store.completeLive(scope: scope(), ticket: newer, job: record(), stillAuthorized: true))
        try store.deny(scope: scope())
        XCTAssertNil(store.offline(scope: scope(), authorized: true))
        let verification = try store.beginLive(scope: scope())
        XCTAssertNotNil(try store.completeLive(scope: scope(), ticket: verification, job: record(), stillAuthorized: true))
        XCTAssertNotNil(store.offline(scope: scope(), authorized: true))
    }
    func testOldFailureCannotReportUnavailableAfterNewerSuccess() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = JobOfficeOfflineStore(directory: root)
        let old = try store.beginLive(scope: scope())
        let newer = try store.beginLive(scope: scope())
        XCTAssertTrue(store.isPending(scope: scope(), ticket: newer))
        XCTAssertNotNil(try store.completeLive(scope: scope(), ticket: newer, job: record(), stillAuthorized: true))
        XCTAssertFalse(store.isPending(scope: scope(), ticket: old))
        XCTAssertNil(try store.restoreAfterConnectivityFailure(scope: scope(), ticket: old, stillAuthorized: true))
        XCTAssertNotNil(store.offline(scope: scope(), authorized: true))
    }
    func testCorruptPreflightRetiresTwoObserversBeforeFallbackDenial() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = JobOfficeOfflineStore(directory: root)
        let initial = try store.beginLive(scope: scope())
        XCTAssertNotNil(try store.completeLive(scope: scope(), ticket: initial, job: record(), stillAuthorized: true))
        var firstVisible = true
        var secondVisible = true
        let first = store.$revision.dropFirst().sink { _ in
            if store.offline(scope: self.scope(), authorized: true) == nil { firstVisible = false }
        }
        let second = store.$revision.dropFirst().sink { _ in
            if store.offline(scope: self.scope(), authorized: true) == nil { secondVisible = false }
        }
        let path = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first)
        try Data("corrupt".utf8).write(to: path)
        XCTAssertThrowsError(try store.beginLive(scope: scope()))
        XCTAssertFalse(firstVisible)
        XCTAssertFalse(secondVisible)
        try store.deny(scope: scope())
        XCTAssertNil(store.offline(scope: scope(), authorized: true))
        withExtendedLifetime((first, second)) { }
    }
}

import XCTest
@testable import Thorbis

@MainActor
final class InvoiceAccessPreflightTests: XCTestCase {
    private final class Memory: InvoiceAccessMarkerStorage {
        var data: [String: Data] = [:]
        var failWrites = false
        var writes = 0
        func read(_ key: String) throws -> Data? { data[key] }
        func write(_ value: Data, key: String) throws {
            if failWrites { throw CocoaError(.fileWriteUnknown) }
            writes += 1
            data[key] = value
        }
    }
    private func scope() -> InvoiceAccessRegistry.Scope {
        .init(actorWorkspace: UUID().uuidString, origin: "https://app.thorbis.com", invoiceID: UUID().uuidString.lowercased())
    }
    private func owner(_ memory: Memory, directory: URL? = nil) -> InvoiceAccessPreflight {
        InvoiceAccessPreflight(markers: memory, directory: directory ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    func testPreflightWritesBeforeNetworkAndPendingSurvivesOwnerRecreation() throws {
        let memory = Memory(); let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let scope = scope(); let first = owner(memory, directory: directory)
        XCTAssertTrue(try first.canUseOffline(scope))
        let ticket = try first.begin(scope)
        XCTAssertEqual(memory.writes, 1, "The durable hold must be saved before a request starts")
        let relaunched = owner(memory, directory: directory)
        XCTAssertFalse(try relaunched.canUseOffline(scope))
        XCTAssertNil(try relaunched.cacheEpoch(scope))
        XCTAssertTrue(try relaunched.finish(scope, ticket: ticket))
        XCTAssertTrue(try relaunched.canUseOffline(scope))
        XCTAssertNotNil(try relaunched.cacheEpoch(scope))
    }

    func testDenialAndOverlappingLateSuccessNeverReauthorize() throws {
        let memory = Memory(); let scope = scope(); let owner = owner(memory)
        let first = try owner.begin(scope); let second = try owner.begin(scope)
        try owner.deny(scope)
        XCTAssertFalse(try owner.finish(scope, ticket: second))
        XCTAssertFalse(try owner.finish(scope, ticket: first))
        XCTAssertFalse(try owner.canUseOffline(scope))
        XCTAssertNil(try owner.cacheEpoch(scope))
    }

    func testFailedPreflightNeverStartsRequest() throws {
        let memory = Memory(); memory.failWrites = true
        let scope = scope(); let owner = owner(memory)
        var requestStarted = false
        XCTAssertThrowsError(try {
            _ = try owner.begin(scope)
            requestStarted = true
        }())
        XCTAssertFalse(requestStarted)
        XCTAssertThrowsError(try owner.canUseOffline(scope))
    }

    func testEpochBoundCacheRejectsPendingAndDeniedReadsAndLateWrites() throws {
        let memory = Memory(); let scope = scope(); let owner = owner(memory)
        let cache = InvoiceEpochCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), preflight: owner)
        let payload = #"{"id":"\#(scope.invoiceID)","organizationId":"00000000-0000-4000-8000-000000000002","customerId":"00000000-0000-4000-8000-000000000003","createdByUserId":"00000000-0000-4000-8000-000000000004","origin":"job_completion","sourceOperationKey":"fixture","status":"issued","lines":[],"linesRevision":1,"amountPaid":0,"currency":"USD","createdAt":"2026-10-26T11:00:00Z","updatedAt":"2026-10-26T12:00:00Z"}"#
        let invoice = try JSONDecoder().decode(InvoiceRecord.self, from: Data(payload.utf8))
        let first = try owner.begin(scope)
        XCTAssertTrue(try owner.finish(scope, ticket: first))
        try cache.save(invoice, scope: scope)
        XCTAssertEqual(cache.load(scope: scope)?.id, scope.invoiceID)
        let later = try owner.begin(scope)
        XCTAssertNil(cache.load(scope: scope))
        try owner.deny(scope)
        try cache.save(invoice, scope: scope)
        XCTAssertFalse(try owner.finish(scope, ticket: later))
        XCTAssertNil(cache.load(scope: scope))
    }

    func testOtherInvoiceScopeRemainsAvailable() throws {
        let memory = Memory(); let owner = owner(memory)
        let denied = scope(); let other = scope()
        _ = try owner.begin(denied)
        try owner.deny(denied)
        XCTAssertTrue(try owner.canUseOffline(other))
    }
}

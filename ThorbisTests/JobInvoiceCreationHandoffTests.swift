import XCTest
@testable import Thorbis

@MainActor
final class JobInvoiceCreationHandoffTests: XCTestCase {
    @MainActor private final class Gate {
        var continuation: CheckedContinuation<Void, Never>?
        func wait() async { await withCheckedContinuation { continuation = $0 } }
        func release() { continuation?.resume(); continuation = nil }
    }

    func testRevocationDuringCreatePreventsPublishingAndNavigation() async throws {
        let gate = Gate()
        var current = true
        var prepared = false
        var refreshed = false
        let task = Task {
            try await JobInvoiceCreationHandoff.run(
                create: { await gate.wait(); return "invoice" },
                isCurrent: { current }, verify: { _ in }, canView: { true },
                withoutView: {}, prepareRefresh: { _ in prepared = true },
                refresh: { refreshed = true })
        }
        while gate.continuation == nil { await Task.yield() }
        current = false
        gate.release()
        let result = try await task.value
        XCTAssertNil(result)
        XCTAssertFalse(prepared)
        XCTAssertFalse(refreshed)
    }

    func testRevocationDuringRefreshPreventsNavigation() async throws {
        let gate = Gate()
        var current = true
        var prepared = false
        let task = Task {
            try await JobInvoiceCreationHandoff.run(
                create: { "invoice" }, isCurrent: { current }, verify: { _ in },
                canView: { true }, withoutView: {}, prepareRefresh: { _ in prepared = true },
                refresh: { await gate.wait() })
        }
        while gate.continuation == nil { await Task.yield() }
        current = false
        gate.release()
        let result = try await task.value
        XCTAssertTrue(prepared)
        XCTAssertNil(result)
    }

    func testCancellationDuringRefreshPreventsNavigation() async throws {
        let gate = Gate()
        let task = Task {
            try await JobInvoiceCreationHandoff.run(
                create: { "invoice" }, isCurrent: { true }, verify: { _ in },
                canView: { true }, withoutView: {}, prepareRefresh: { _ in },
                refresh: { await gate.wait() })
        }
        while gate.continuation == nil { await Task.yield() }
        task.cancel()
        gate.release()
        let result = try await task.value
        XCTAssertNil(result)
    }

    func testCreateWithoutViewReportsSuccessWithoutOpeningOrRefreshing() async throws {
        var reported = false
        var prepared = false
        var refreshed = false
        let result = try await JobInvoiceCreationHandoff.run(
            create: { "invoice" }, isCurrent: { true }, verify: { _ in }, canView: { false },
            withoutView: { reported = true }, prepareRefresh: { _ in prepared = true },
            refresh: { refreshed = true })
        XCTAssertNil(result)
        XCTAssertTrue(reported)
        XCTAssertFalse(prepared)
        XCTAssertFalse(refreshed)
    }
}

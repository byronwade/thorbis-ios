import XCTest
@testable import Thorbis

@MainActor
final class StoreTests: XCTestCase {
    func testRefreshReportsFailureWhenWorkspaceFetchFails() async {
        let store = Store { _ in throw URLError(.cannotConnectToHost) }

        let refreshed = await store.refresh(APIClient())

        XCTAssertEqual(refreshed, .failed)
        XCTAssertNotNil(store.error)
    }

    func testRefreshReportsSuccessAfterApplyingWorkspaceFetch() async {
        let customer = Customer(id: "current", name: "Current", archived: false, createdAt: nil)
        let store = Store { _ in ([], [customer]) }

        let refreshed = await store.refresh(APIClient())

        XCTAssertEqual(refreshed, .applied)
        XCTAssertEqual(store.customers.map(\.id), ["current"])
    }

    func testInvalidationDiscardsLateWorkspaceResponse() async {
        var resume: CheckedContinuation<([Job], [Customer]), Error>?
        let store = Store { _ in
            try await withCheckedThrowingContinuation { resume = $0 }
        }
        let task = Task { await store.refresh(APIClient()) }
        while resume == nil { await Task.yield() }
        store.invalidate()
        resume?.resume(returning: ([Job(id: "old", customerId: nil, title: "Private", status: "scheduled", createdAt: nil, updatedAt: nil, allowedTransitions: nil)], []))
        let result = await task.value
        XCTAssertEqual(result, .superseded)
        XCTAssertTrue(store.jobs.isEmpty)
        XCTAssertTrue(store.customers.isEmpty)
        XCTAssertFalse(store.loading)
        XCTAssertNil(store.error)
    }

    func testInvalidationClearsAlreadyLoadedWorkspaceData() async {
        let store = Store { _ in ([], [Customer(id: "private", name: "Private", archived: false, createdAt: nil)]) }
        await store.refresh(APIClient())
        XCTAssertEqual(store.customers.count, 1)
        store.invalidate()
        XCTAssertTrue(store.customers.isEmpty)
    }

    func testNewerRefreshWinsWhenOlderRequestFinishesLast() async {
        var replies: [CheckedContinuation<([Job], [Customer]), Error>] = []
        let store = Store { _ in try await withCheckedThrowingContinuation { replies.append($0) } }
        let first = Task { await store.refresh(APIClient()) }
        while replies.count < 1 { await Task.yield() }
        let second = Task { await store.refresh(APIClient()) }
        while replies.count < 2 { await Task.yield() }
        replies[1].resume(returning: ([], [Customer(id: "new", name: "New", archived: false, createdAt: nil)]))
        let secondResult = await second.value
        replies[0].resume(returning: ([], [Customer(id: "old", name: "Old", archived: false, createdAt: nil)]))
        let firstResult = await first.value
        XCTAssertEqual(secondResult, .applied)
        XCTAssertEqual(firstResult, .superseded)
        XCTAssertEqual(store.customers.map(\.id), ["new"])
    }

    func testAuthorizedFetchDoesNotStartSecondResourceAfterSessionInvalidation() async throws {
        let gate = URLProtocolFixture.Gate()
        let actor = "019f0000-0000-7000-8000-000000000011"
        let organization = "019f0000-0000-7000-8000-000000000001"
        let sessionJSON = #"{"user":{"id":"019f0000-0000-7000-8000-000000000011","name":"Fixture technician"},"session":{"userId":"019f0000-0000-7000-8000-000000000011","activeOrganizationId":"019f0000-0000-7000-8000-000000000001","expiresAt":"2099-10-27T12:00:00Z"}}"#
        let membershipJSON = #"[{"id":"019f0000-0000-7000-8000-000000000001","name":"Fixture workspace"}]"#
        let catalogJSON = """
            {"authority":{"actorId":"\(actor)","organizationId":"\(organization)","policyVersion":1,"generation":"fixture"},"capabilities":["job.view","customer.view"],"resources":[],"views":[]}
            """
        let featureJSON = """
            {"organizationId":"\(organization)","evaluatedAt":"2026-10-26T12:00:00Z","features":{"jobs":{"enabled":true,"released":true,"entitled":true},"core_crm":{"enabled":true,"released":true,"entitled":true}}}
            """
        let transport = URLProtocolFixture.session([
            .init(200, sessionJSON), .init(200, membershipJSON), .init(200, catalogJSON),
            .init(200, featureJSON), .init(200, #"{"items":[],"nextCursor":null}"#, gate: gate),
            .init(200, "{}")
        ])
        let api = APIClient(session: transport, baseURL: "https://app.thorbis.com")
        let session = SessionController(api: api, defaults: UserDefaults(suiteName: "thorbis.store.tests.\(UUID().uuidString)")!)
        await session.restore()
        XCTAssertEqual(session.phase, .ready)
        let fetch = Task { try await Store.fetchAuthorized(api: api, session: session) }
        for _ in 0..<100 where URLProtocolFixture.recorded.count < 5 {
            try await Task.sleep(for: .milliseconds(10))
        }

        await session.signOut()
        gate.release()
        do {
            _ = try await fetch.value
            XCTFail("Expected invalidated fetch to stop")
        } catch is CancellationError {}
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertFalse(URLProtocolFixture.recorded.contains { $0.url?.path == "/v1/customers" })
    }
}

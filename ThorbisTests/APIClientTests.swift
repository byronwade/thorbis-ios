import XCTest
@testable import Thorbis

@MainActor
final class APIClientTests: XCTestCase {
    func testDefaultOriginUsesProduction() {
        let previous = UserDefaults.standard.object(forKey: "thorbis.apiBaseURL")
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: "thorbis.apiBaseURL") }
            else { UserDefaults.standard.removeObject(forKey: "thorbis.apiBaseURL") }
        }
        UserDefaults.standard.removeObject(forKey: "thorbis.apiBaseURL")

        let client = APIClient()
        XCTAssertEqual(client.baseURL, "https://app.thorbis.com")
    }

    func testJobsFollowKeysetCursorAndIncludeEveryPage() async throws {
        let session = URLProtocolFixture.session([
            .init(200, #"{"items":[{"id":"j1","title":"First","status":"scheduled"}],"nextCursor":"cursor 1"}"#),
            .init(200, #"{"items":[{"id":"j2","title":"Second","status":"scheduled"}],"nextCursor":null}"#),
        ])
        let client = APIClient(session: session, baseURL: "https://app.thorbis.com")

        let jobs = try await client.jobs()

        XCTAssertEqual(jobs.map(\.id), ["j1", "j2"])
        XCTAssertEqual(URLProtocolFixture.recorded.map { $0.url?.absoluteString }, [
            "https://app.thorbis.com/v1/jobs",
            "https://app.thorbis.com/v1/jobs?cursor=cursor%201",
        ])
    }

    func testCustomersFollowKeysetCursorAndIncludeEveryPage() async throws {
        let session = URLProtocolFixture.session([
            .init(200, #"{"items":[{"id":"c1","name":"Acme"}],"nextCursor":"next"}"#),
            .init(200, #"{"items":[{"id":"c2","name":"Beta"}],"nextCursor":null}"#),
        ])
        let client = APIClient(session: session, baseURL: "https://app.thorbis.com")

        let customers = try await client.customers()

        XCTAssertEqual(customers.map(\.id), ["c1", "c2"])
        XCTAssertEqual(URLProtocolFixture.recorded.map { $0.url?.absoluteString }, [
            "https://app.thorbis.com/v1/customers",
            "https://app.thorbis.com/v1/customers?cursor=next",
        ])
    }

    func testJobListDecodesSchedulingAndAssignmentWithoutBreakingOlderRows() async throws {
        let session = URLProtocolFixture.session([
            .init(200, #"{"items":[{"id":"j1","title":"Planned","status":"scheduled","scheduledFor":"2026-10-27T14:00:00Z","assignedToUserId":"u1","locationId":"l1"},{"id":"j2","title":"Old","status":"draft"}],"nextCursor":null}"#),
        ])
        let client = APIClient(session: session, baseURL: "https://app.thorbis.com")

        let jobs = try await client.jobs()

        XCTAssertEqual(jobs[0].scheduledFor, "2026-10-27T14:00:00Z")
        XCTAssertEqual(jobs[0].assignedToUserId, "u1")
        XCTAssertEqual(jobs[0].locationId, "l1")
        XCTAssertNil(jobs[1].scheduledFor)
        XCTAssertNil(jobs[1].assignedToUserId)
        XCTAssertNil(jobs[1].locationId)
    }

    func testRepeatingCursorFailsBeforeReturningIncompleteList() async {
        let session = URLProtocolFixture.session([
            .init(200, #"{"items":[{"id":"j1","title":"First","status":"scheduled"}],"nextCursor":"same"}"#),
            .init(200, #"{"items":[{"id":"j2","title":"Second","status":"scheduled"}],"nextCursor":"same"}"#),
        ])
        let client = APIClient(session: session, baseURL: "https://app.thorbis.com")

        do {
            _ = try await client.jobs()
            XCTFail("Expected cursor loop rejection")
        } catch let problem as Problem {
            XCTAssertEqual(problem.title, "Pagination cursor loop")
        } catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(URLProtocolFixture.recorded.count, 2)
    }

    func testArrivedProgressIncludesManualEvidence() async throws {
        let session = URLProtocolFixture.session([.init()])
        let client = APIClient(session: session, baseURL: "https://app.thorbis.com")

        try await client.progress("job-1", to: "arrived")

        let request = try XCTUnwrap(URLProtocolFixture.recorded.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url?.path, "/v1/jobs/job-1/progress")
        XCTAssertEqual(request.header("content-type"), "application/json")
        let body = try XCTUnwrap(request.body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["to"] as? String, "arrived")
        XCTAssertEqual((json["arrival"] as? [String: String])?["method"], "manual")
    }

    func testHostileLoopbackLikeHostnameNeverReceivesRequest() async {
        let session = URLProtocolFixture.session([])
        let client = APIClient(session: session, baseURL: "http://127.0.0.1.evil.example:8788")
        XCTAssertFalse(client.isLoopback)
        client.useDevIdentity()
        XCTAssertEqual(client.auth, .none)

        do {
            _ = try await client.jobs()
            XCTFail("Expected invalid origin")
        } catch is Problem {}
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(URLProtocolFixture.recorded.isEmpty)
    }

    func testDevIdentityIsRejectedForProduction() async throws {
        let session = URLProtocolFixture.session([.init(200, #"{"items":[],"nextCursor":null}"#)])
        let client = APIClient(session: session, baseURL: "https://app.thorbis.com")
        client.useDevIdentity()

        XCTAssertEqual(client.auth, .none)
        _ = try await client.jobs()
        XCTAssertNil(URLProtocolFixture.recorded.first?.header("x-thorbis-user"))
    }

    func testExactLoopbackReceivesDebugIdentity() async throws {
        let session = URLProtocolFixture.session([.init(200, #"{"items":[],"nextCursor":null}"#)])
        let client = APIClient(session: session, baseURL: "http://127.0.0.1:8788")
        client.useDevIdentity()

        #if DEBUG
        _ = try await client.jobs()
        XCTAssertNotNil(URLProtocolFixture.recorded.first?.header("x-thorbis-user"))
        #else
        do {
            _ = try await client.jobs()
            XCTFail("Release must reject loopback origin")
        } catch is Problem {}
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(URLProtocolFixture.recorded.isEmpty)
        #endif
    }

    func testIPv6LoopbackIsRecognized() {
        let client = APIClient(baseURL: "http://[::1]:8788")
        #if DEBUG
        XCTAssertTrue(client.isLoopback)
        client.useDevIdentity()
        XCTAssertNotEqual(client.auth, .none)
        #else
        XCTAssertFalse(client.isLoopback)
        #endif
    }

    func testHTTPProblemRetainsStatusAndDetail() async {
        let session = URLProtocolFixture.session([.init(403, #"{"title":"Forbidden","status":403,"detail":"Wrong workspace"}"#)])
        let client = APIClient(session: session, baseURL: "https://app.thorbis.com")

        do {
            _ = try await client.jobs()
            XCTFail("Expected API problem")
        } catch let problem as Problem {
            XCTAssertEqual(problem.status, 403)
            XCTAssertEqual(problem.detail, "Wrong workspace")
        } catch { XCTFail("Unexpected error: \(error)") }
    }

    func testLaterPageHTTPFailureDoesNotReturnPartialJobs() async {
        let session = URLProtocolFixture.session([
            .init(200, #"{"items":[{"id":"j1","title":"First","status":"scheduled"}],"nextCursor":"next"}"#),
            .init(503, #"{"title":"Unavailable","status":503,"detail":"Try again"}"#),
        ])
        let client = APIClient(session: session, baseURL: "https://app.thorbis.com")

        do {
            _ = try await client.jobs()
            XCTFail("Expected later-page failure")
        } catch let problem as Problem {
            XCTAssertEqual(problem.status, 503)
            XCTAssertEqual(problem.detail, "Try again")
        } catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(URLProtocolFixture.recorded.count, 2)
    }

    func testInvalidatedSingleRequestCannotReturnStaleJob() async throws {
        let gate = URLProtocolFixture.Gate()
        let session = URLProtocolFixture.session([
            .init(200, #"{"id":"j1","title":"Old","status":"scheduled"}"#, gate: gate),
        ])
        let client = APIClient(session: session, baseURL: "https://app.thorbis.com")
        let task = Task { try await client.job("j1") }
        try await waitForRequestCount(1)

        client.invalidateRequests()
        gate.release()

        do {
            _ = try await task.value
            XCTFail("Expected stale response cancellation")
        } catch is CancellationError {}
        catch { XCTFail("Unexpected error: \(error)") }
    }

    func testInvalidatedLaterPageCannotReturnPartialJobs() async throws {
        let gate = URLProtocolFixture.Gate()
        let session = URLProtocolFixture.session([
            .init(200, #"{"items":[{"id":"j1","title":"Old","status":"scheduled"}],"nextCursor":"next"}"#),
            .init(200, #"{"items":[{"id":"j2","title":"Still old","status":"scheduled"}],"nextCursor":null}"#, gate: gate),
        ])
        let client = APIClient(session: session, baseURL: "https://app.thorbis.com")
        let task = Task { try await client.jobs() }
        try await waitForRequestCount(2)

        client.invalidateRequests()
        gate.release()

        do {
            _ = try await task.value
            XCTFail("Expected stale page cancellation")
        } catch is CancellationError {}
        catch { XCTFail("Unexpected error: \(error)") }
    }

    func testCancelledURLSessionRequestPropagatesCancellation() async throws {
        let gate = URLProtocolFixture.Gate()
        let session = URLProtocolFixture.session([.init(200, #"{"items":[],"nextCursor":null}"#, gate: gate)])
        let client = APIClient(session: session, baseURL: "https://app.thorbis.com")
        let task = Task { try await client.jobs() }
        try await waitForRequestCount(1)

        task.cancel()
        gate.release()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {}
        catch { XCTFail("Unexpected error: \(error)") }
    }

    func testBetterAuthErrorMessageIsPreserved() async {
        struct Body: Encodable { let email = "test@example.invalid"; let password = "wrong" }
        let session = URLProtocolFixture.session([
            .init(401, #"{"code":"INVALID_EMAIL_OR_PASSWORD","message":"Invalid email or password"}"#),
        ])
        let client = APIClient(session: session, baseURL: "https://app.thorbis.com")

        do {
            let _: APIClient.EmptyResponse = try await client.send("POST", "/api/auth/sign-in/email", body: Body(), authed: false)
            XCTFail("Expected authentication failure")
        } catch let problem as Problem {
            XCTAssertEqual(problem.status, 401)
            XCTAssertEqual(problem.title, "INVALID_EMAIL_OR_PASSWORD")
            XCTAssertEqual(problem.detail, "Invalid email or password")
        } catch { XCTFail("Unexpected error: \(error)") }
    }

    func testAuthenticationEndpoint401DoesNotInvokeUnauthorizedCallback() async {
        let client = APIClient(session: URLProtocolFixture.session([
            .init(401, #"{"code":"INVALID_EMAIL_OR_PASSWORD","message":"Invalid credentials"}"#)
        ]), baseURL: "https://app.thorbis.com")
        var invalidations = 0
        client.onUnauthorized = { invalidations += 1 }
        struct Credentials: Encodable { let email = "fixture@example.invalid"; let password = "bad" }

        do {
            let _: APIClient.EmptyResponse = try await client.send("POST", "/api/auth/sign-in/email",
                                                             body: Credentials(), authed: false)
            XCTFail("Expected authentication failure")
        } catch let problem as Problem {
            XCTAssertEqual(problem.status, 401)
        } catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(invalidations, 0)
    }

    func testClearingSessionCookiesAffectsOnlyCurrentAPIOrigin() throws {
        let session = URLProtocolFixture.session([])
        let storage = try XCTUnwrap(session.configuration.httpCookieStorage)
        let current = try XCTUnwrap(HTTPCookie(properties: [
            .domain: "app.thorbis.com", .path: "/", .name: "thorbis.session", .value: "old",
        ]))
        let unrelated = try XCTUnwrap(HTTPCookie(properties: [
            .domain: "other.example", .path: "/", .name: "other.session", .value: "keep",
        ]))
        storage.setCookie(current)
        storage.setCookie(unrelated)
        defer { storage.deleteCookie(current); storage.deleteCookie(unrelated) }
        let client = APIClient(session: session, baseURL: "https://app.thorbis.com")

        client.clearSessionCookies()

        XCTAssertFalse(storage.cookies?.contains(where: { $0.name == "thorbis.session" }) ?? false)
        XCTAssertTrue(storage.cookies?.contains(where: { $0.name == "other.session" }) ?? false)
    }

    private func waitForRequestCount(_ count: Int) async throws {
        for _ in 0..<100 {
            if URLProtocolFixture.recorded.count >= count { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for \(count) request(s)")
    }
}

import Foundation
import XCTest
@testable import ThorbisCore

/// Answers from a script and records what was asked.
actor ScriptedTransport: HTTPTransport {
    var responses: [HTTPResponse]
    private(set) var sent: [HTTPRequest] = []

    init(_ responses: [HTTPResponse]) { self.responses = responses }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        sent.append(request)
        guard !responses.isEmpty else { throw URLError(.notConnectedToInternet) }
        return responses.removeFirst()
    }
}

final class CredentialLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Credentials] = []
    func append(_ value: Credentials) { lock.lock(); values.append(value); lock.unlock() }
    var all: [Credentials] { lock.lock(); defer { lock.unlock() }; return values }
}

final class APIClientTests: XCTestCase {
    private func json(_ text: String, status: Int = 200, cookies: [ResponseCookie] = []) -> HTTPResponse {
        HTTPResponse(status: status, headers: ["Content-Type": "application/json"], cookies: cookies, body: Data(text.utf8))
    }

    func testSignInCapturesTheSessionCookieAndReplaysIt() async throws {
        let transport = ScriptedTransport([
            json(#"{"redirect":false,"token":"t"}"#, cookies: [
                ResponseCookie(name: "__Secure-better-auth.session_token", value: "abc.def"),
                ResponseCookie(name: "unrelated", value: "x"),
            ]),
            json(#"{"user":{"id":"u1","name":"Mike","email":"m@example.com"},"session":{"activeOrganizationId":"o1"}}"#),
            json(#"{"items":[]}"#),
        ])
        let log = CredentialLog()
        let api = ThorbisAPI(environment: .production, transport: transport, onCredentialsChange: { log.append($0) })

        let session = try await api.signIn(email: "m@example.com", password: "pw")
        XCTAssertEqual(session.session.activeOrganizationId, "o1")
        _ = try await api.jobs()

        let sent = await transport.sent
        XCTAssertEqual(sent[0].url.absoluteString, "https://app.thorbis.com/api/auth/sign-in/email")
        XCTAssertEqual(sent[0].headers["origin"], "https://app.thorbis.com", "Better Auth checks Origin on sign-in")
        XCTAssertNil(sent[0].headers["cookie"])
        XCTAssertEqual(sent[1].headers["cookie"], "__Secure-better-auth.session_token=abc.def")
        XCTAssertEqual(sent[2].url.path, "/v1/jobs")
        XCTAssertNil(sent[2].headers["origin"], "only auth routes send Origin")
        XCTAssertEqual(log.all, [.session(["__Secure-better-auth.session_token": "abc.def"])])
    }

    func testExpiredCookieAnd401SignOut() async throws {
        let transport = ScriptedTransport([
            json(#"{"items":[]}"#, cookies: [ResponseCookie(name: "better-auth.session_token", value: "", expired: true)]),
            json(#"{"title":"unauthenticated","status":401}"#, status: 401),
        ])
        let api = ThorbisAPI(environment: .production, credentials: .session(["better-auth.session_token": "old"]), transport: transport)
        _ = try await api.jobs()
        let afterClear = await api.credentials
        XCTAssertEqual(afterClear, .none)

        let api2 = ThorbisAPI(environment: .production, credentials: .session(["better-auth.session_token": "old"]),
                              transport: ScriptedTransport([json(#"{"status":401}"#, status: 401)]))
        do {
            _ = try await api2.customers()
            XCTFail("expected unauthenticated")
        } catch let error as APIError {
            XCTAssertEqual(error, .unauthenticated)
        }
        let after401 = await api2.credentials
        XCTAssertEqual(after401, .none)
    }

    func testPaginationFollowsCursorAndStops() async throws {
        let transport = ScriptedTransport([
            json(#"{"items":[{"id":"1","name":"A"}],"nextCursor":"018f0000-0000-7000-8000-000000000001"}"#),
            json(#"{"items":[{"id":"2","name":"B"}]}"#),
        ])
        let api = ThorbisAPI(environment: .production, credentials: .session(["better-auth.session_token": "s"]), transport: transport)
        let customers = try await api.customers()
        XCTAssertEqual(customers.map(\.id), ["1", "2"])
        let sent = await transport.sent
        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(sent[0].url.query, "limit=200")
        XCTAssertEqual(sent[1].url.query, "cursor=018f0000-0000-7000-8000-000000000001&limit=200")
    }

    func testBasePathIsPreservedForThorbisComApp() async throws {
        let transport = ScriptedTransport([json(#"{"items":[]}"#)])
        let api = ThorbisAPI(environment: APIEnvironment.custom("https://thorbis.com/app")!, transport: transport)
        _ = try await api.staffNotices()
        let url = await transport.sent.first?.url
        XCTAssertEqual(url?.absoluteString, "https://thorbis.com/app/v1/staff/notices?limit=100")
    }

    func testDevHeadersOnlyOnLoopback() async throws {
        let production = ThorbisAPI(environment: .production, transport: ScriptedTransport([]))
        do {
            try await production.useDevIdentity()
            XCTFail("dev identity must be refused off loopback")
        } catch {}

        let transport = ScriptedTransport([json(#"{"items":[]}"#)])
        let local = ThorbisAPI(environment: .local, transport: transport)
        try await local.useDevIdentity()
        _ = try await local.jobs()
        let headers = await transport.sent.first?.headers
        XCTAssertEqual(headers?["x-thorbis-roles"], "owner")
        XCTAssertNil(headers?["cookie"])
    }

    func testProgressBodyCarriesArrivalAndPause() async throws {
        let job = #"{"id":"j","customerId":"c","title":"T","status":"arrived","createdAt":"x","updatedAt":"x"}"#
        let transport = ScriptedTransport([json(job), json(job)])
        let api = ThorbisAPI(environment: .production, credentials: .session(["better-auth.session_token": "s"]), transport: transport)
        _ = try await api.progress("j", to: .arrived)
        _ = try await api.progress("j", to: .paused, pause: PauseDetails(reason: "Part", nextAction: "Order"))
        let sent = await transport.sent
        let first = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(sent[0].body)) as? [String: Any])
        XCTAssertEqual(first["to"] as? String, "arrived")
        XCTAssertEqual((first["arrival"] as? [String: String])?["method"], "manual")
        XCTAssertNil(first["jobId"], "path keys never repeat in the body")
        let second = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(sent[1].body)) as? [String: Any])
        XCTAssertEqual((second["pause"] as? [String: String])?["reason"], "Part")
        XCTAssertNil(second["arrival"])
        XCTAssertEqual(sent[1].url.path, "/v1/jobs/j/progress")
    }

    func testPhotoUploadIsRawBytesWithTypeAndSizeChecks() async throws {
        let transport = ScriptedTransport([json(#"{"id":"p","jobId":"j","authorUserId":"u","contentType":"image/jpeg","byteSize":3,"createdAt":"x"}"#)])
        let api = ThorbisAPI(environment: .production, credentials: .session(["better-auth.session_token": "s"]), transport: transport)
        let photo = try await api.uploadPhoto(job: "j", data: Data([1, 2, 3]), contentType: "image/jpeg")
        XCTAssertEqual(photo.byteSize, 3)
        let sent = await transport.sent
        XCTAssertEqual(sent[0].headers["content-type"], "image/jpeg")
        XCTAssertEqual(sent[0].body, Data([1, 2, 3]))
        do {
            _ = try await api.uploadPhoto(job: "j", data: Data([1]), contentType: "image/gif")
            XCTFail("gif is not accepted")
        } catch {}
    }

    func testOfflineIsRetryable() async {
        let api = ThorbisAPI(environment: .production, transport: ScriptedTransport([]))
        do {
            _ = try await api.jobs()
            XCTFail("expected a transport error")
        } catch let error as APIError {
            XCTAssertTrue(error.isRetryable)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testEnvironmentChangeSignsOut() async {
        let log = CredentialLog()
        let api = ThorbisAPI(environment: .production, credentials: .session(["better-auth.session_token": "s"]),
                             transport: ScriptedTransport([]), onCredentialsChange: { log.append($0) })
        await api.setEnvironment(.local)
        let credentials = await api.credentials
        XCTAssertEqual(credentials, .none)
        XCTAssertEqual(log.all, [.none])
    }

    func testDeletionRequestAbsentIsNil() async throws {
        let api = ThorbisAPI(environment: .production, credentials: .session(["better-auth.session_token": "s"]),
                             transport: ScriptedTransport([json(#"{"status":404,"detail":"not found"}"#, status: 404)]))
        let current = try await api.currentDeletionRequest()
        XCTAssertNil(current)
    }
}

final class FixtureFlowTests: XCTestCase {
    func testFixtureFieldDayEndToEnd() async throws {
        let api = ThorbisAPI(environment: .production, transport: FixtureTransport())
        _ = try await api.signIn(email: "mike@example.com", password: "fixture")
        let jobs = try await api.jobs()
        let driving = try XCTUnwrap(jobs.first { $0.status == .enRoute })

        let detail = try await api.job(driving.id)
        let action = try XCTUnwrap(JobWorkflow.primaryAction(status: detail.status, allowed: detail.allowedTransitions ?? []))
        XCTAssertEqual(action, .progress(.arrived))
        _ = try await api.progress(driving.id, to: .arrived)
        _ = try await api.progress(driving.id, to: .inProgress)
        _ = try await api.addNote(job: driving.id, body: "Replaced valve")
        let completed = try await api.complete(driving.id, notes: nil)
        XCTAssertEqual(completed.status, .completed)
        let invoice = try await api.completionInvoice(job: driving.id)
        XCTAssertEqual(invoice.status, .draft)
        let issued = try await api.issueInvoice(invoice)
        XCTAssertEqual(issued.status, .issued)

        let notes = try await api.notes(job: driving.id)
        XCTAssertEqual(notes.last?.body, "Replaced valve")

        do {
            _ = try await api.progress(driving.id, to: .enRoute)
            XCTFail("a completed job cannot move")
        } catch let error as APIError {
            XCTAssertTrue(error.isConflict)
        }
    }

    func testFixtureSearchAndCustomers() async throws {
        let api = ThorbisAPI(environment: .production, transport: FixtureTransport())
        _ = try await api.signIn(email: "mike@example.com", password: "fixture")
        let results = try await api.search("alvarez")
        XCTAssertEqual(results.first?.destination, .customer(results.first!.entityId))
        let created = try await api.createCustomer(NewCustomer(name: "  New Person ", email: " "))
        XCTAssertEqual(created.name, "New Person")
        XCTAssertNil(created.email, "blank fields are absent, not blank")
    }
}

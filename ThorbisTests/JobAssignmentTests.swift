import XCTest
@testable import Thorbis

@MainActor
final class JobAssignmentTests: XCTestCase {
    private let jobID = "00000000-0000-4000-8000-000000000001"
    private let originalAssignee = "00000000-0000-4000-8000-000000000002"
    private let replacement = "00000000-0000-4000-8000-000000000003"

    func testRosterPaginatesFilteredMembersAndUsesCanonicalIdentityFields() async throws {
        let first = #"{"items":[{"userId":"00000000-0000-4000-8000-000000000003","displayName":"Taylor"}],"nextCursor":"membership-page-2"}"#
        let last = #"{"items":[{"userId":"00000000-0000-4000-8000-000000000004","displayName":"Alex"}]}"#
        let api = APIClient(session: URLProtocolFixture.session([.init(200, first), .init(200, last)]), baseURL: "https://app.thorbis.com")

        let people = try await api.fieldAssignees()

        XCTAssertEqual(people.map(\.userId), [replacement, "00000000-0000-4000-8000-000000000004"])
        XCTAssertEqual(people.map(\.displayName), ["Taylor", "Alex"])
        let calls = URLProtocolFixture.recorded
        XCTAssertEqual(calls.map { $0.url?.path }, ["/v1/organization/assignees", "/v1/organization/assignees"])
        XCTAssertEqual(URLComponents(url: try XCTUnwrap(calls[0].url), resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "limit" })?.value, "200")
        XCTAssertEqual(URLComponents(url: try XCTUnwrap(calls[1].url), resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "cursor" })?.value, "membership-page-2")
    }

    func testRosterRejectsRepeatedCursorInsteadOfReplayingPagesForever() async throws {
        let page = #"{"items":[],"nextCursor":"same"}"#
        let api = APIClient(session: URLProtocolFixture.session([.init(200, page), .init(200, page)]), baseURL: "https://app.thorbis.com")

        do {
            _ = try await api.fieldAssignees()
            XCTFail("Repeated cursor should fail closed")
        } catch {
            XCTAssertEqual(URLProtocolFixture.recorded.count, 2)
        }
    }

    func testRosterContinuesPastFilteredEmptyPages() async throws {
        let pages = (1...4).map { URLProtocolFixture.Reply(200, "{\"items\":[],\"nextCursor\":\"page-\($0)\"}") }
        let last = #"{"items":[{"userId":"00000000-0000-4000-8000-000000000003","displayName":"Taylor"}]}"#
        let api = APIClient(session: URLProtocolFixture.session(pages + [.init(200, last)]), baseURL: "https://app.thorbis.com")
        let people = try await api.fieldAssignees()
        XCTAssertEqual(people.map(\.userId), [replacement])
        XCTAssertEqual(URLProtocolFixture.recorded.count, 5)
    }

    func testAssignmentSendsLoadedAssigneeAsStaleWritePrecondition() async throws {
        let response = #"{"id":"00000000-0000-4000-8000-000000000001","organizationId":"00000000-0000-4000-8000-000000000005","customerId":"00000000-0000-4000-8000-000000000006","title":"Repair","status":"scheduled","assignedToUserId":"00000000-0000-4000-8000-000000000003","createdAt":"2026-10-26T12:00:00Z","updatedAt":"2026-10-26T12:00:00Z"}"#
        let api = APIClient(session: URLProtocolFixture.session([.init(200, response)]), baseURL: "https://app.thorbis.com")

        _ = try await api.assignFieldJob(jobID, request: .init(userId: replacement, expected: .user(originalAssignee)))

        let call = try XCTUnwrap(URLProtocolFixture.recorded.first)
        XCTAssertEqual(call.url?.path, "/v1/jobs/\(jobID)/assign")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(call.body)) as? [String: String])
        XCTAssertEqual(body, ["userId": replacement, "expectedAssigneeId": originalAssignee])
    }
}

import XCTest
@testable import Thorbis

/// Lists the server pages: the app either reads every page or says the list is not the whole set.
@MainActor
final class PartialListTests: XCTestCase {
    private let base = "https://app.thorbis.com"

    private func query(_ request: URLProtocolFixture.RecordedRequest, _ name: String) -> String? {
        request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems?.first { $0.name == name }?.value
    }

    // MARK: Words

    func testPartialNoteSaysHowManyAndThatMoreExist() {
        XCTAssertEqual(PartialList.note(shown: 3, of: "schedules"), "Showing the first 3 schedules. There are more.")
        XCTAssertEqual(PartialList.note(shown: 2_000, of: "schedules"), "Showing the first \(2_000.formatted()) schedules. There are more.")
    }

    func testPriceBookCountIsAFloorWhenMoreRowsExist() {
        XCTAssertEqual(SetupPriceBookCount.total(12, more: false), "12")
        XCTAssertEqual(SetupPriceBookCount.total(50, more: true), "50+")
        XCTAssertNil(SetupPriceBookCount.moreLine(count: 8, shown: 8, more: false))
        XCTAssertEqual(SetupPriceBookCount.moreLine(count: 12, shown: 8, more: false), "+ 4 more in your price book · edit any price")
        XCTAssertEqual(SetupPriceBookCount.moreLine(count: 50, shown: 8, more: true), "+ at least 42 more in your price book · edit any price")
        // Archived rows filtered out of the first page can leave eight or fewer: still say there are more.
        XCTAssertEqual(SetupPriceBookCount.moreLine(count: 5, shown: 8, more: true), "+ more in your price book · edit any price")
    }

    // MARK: Roles read every page

    func testOrganizationRolesFollowEveryPage() async throws {
        let first = #"{"items":[{"role":{"id":"r1","currentRevision":1},"revision":{"name":"Zed","description":null}}],"nextCursor":"page-2"}"#
        let second = #"{"items":[{"role":{"id":"r2","currentRevision":4},"revision":{"name":"Apprentice","description":"Oldest role"}}],"nextCursor":null}"#
        let api = APIClient(session: URLProtocolFixture.session([.init(200, first), .init(200, second)]), baseURL: base)

        let roles = try await api.organizationRoles()

        XCTAssertEqual(roles.map(\.id), ["r2", "r1"], "Both pages, sorted by name")
        let requests = URLProtocolFixture.recorded
        XCTAssertEqual(requests.map { $0.url?.path }, ["/v1/organization/roles", "/v1/organization/roles"])
        XCTAssertNil(query(requests[0], "cursor"))
        XCTAssertEqual(query(requests[1], "cursor"), "page-2")
    }

    // MARK: Billing schedules

    private func schedulePage(_ id: String, next: String?) -> String {
        let cursor = next.map { "\"\($0)\"" } ?? "null"
        return #"{"items":[{"id":"\#(id)","customerId":"c1","jobId":"j1","retainageRateBps":0,"status":"open","lines":[],"createdAt":"2026-11-01T10:00:00Z"}],"nextCursor":\#(cursor)}"#
    }

    func testBillingSchedulesSayWhenTheCapLeavesAPage() async throws {
        let api = APIClient(session: URLProtocolFixture.session([.init(200, schedulePage("s1", next: "page-2")),
                                                                 .init(200, schedulePage("s2", next: nil))]), baseURL: base)

        let read = try await api.billingSchedules(cap: 1)

        XCTAssertEqual(read.items.map(\.id), ["s1"])
        XCTAssertTrue(read.more, "The server still had a page")
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
    }

    func testBillingSchedulesReadToTheEndAreComplete() async throws {
        let api = APIClient(session: URLProtocolFixture.session([.init(200, schedulePage("s1", next: "page-2")),
                                                                 .init(200, schedulePage("s2", next: nil))]), baseURL: base)

        let read = try await api.billingSchedules()

        XCTAssertEqual(read.items.map(\.id), ["s1", "s2"])
        XCTAssertFalse(read.more)
    }

    // MARK: Open invitations

    private func invitationPage(_ id: String, next: String?) -> String {
        let cursor = next.map { "\"\($0)\"" } ?? "null"
        return #"{"items":[{"id":"\#(id)","email":"\#(id)@example.invalid","role":"technician","status":"pending","createdAt":"2026-11-01","expiresAt":"2026-12-01"}],"nextCursor":\#(cursor)}"#
    }

    func testOpenInvitationsSayWhenTheCapLeavesAPage() async throws {
        let api = APIClient(session: URLProtocolFixture.session([.init(200, invitationPage("i1", next: "page-2")),
                                                                 .init(200, invitationPage("i2", next: nil))]), baseURL: base)

        let read = try await api.openInvitations(cap: 1)

        XCTAssertEqual(read.items.map(\.id), ["i1"])
        XCTAssertTrue(read.more)
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
    }

    func testOpenInvitationsReadToTheEndAreComplete() async throws {
        let api = APIClient(session: URLProtocolFixture.session([.init(200, invitationPage("i1", next: "page-2")),
                                                                 .init(200, invitationPage("i2", next: nil))]), baseURL: base)

        let read = try await api.openInvitations()

        XCTAssertEqual(read.items.map(\.id), ["i1", "i2"])
        XCTAssertFalse(read.more)
        XCTAssertEqual(query(URLProtocolFixture.recorded[1], "cursor"), "page-2")
    }

    func testOpenInvitationsStoppedByARepeatedCursorAreNotComplete() async throws {
        let api = APIClient(session: URLProtocolFixture.session([.init(200, invitationPage("i1", next: "loop")),
                                                                 .init(200, invitationPage("i2", next: "loop"))]), baseURL: base)

        let read = try await api.openInvitations()

        XCTAssertEqual(read.items.map(\.id), ["i1", "i2"])
        XCTAssertTrue(read.more)
    }

    // MARK: Job notices

    func testJobNoticesSayWhenOlderNoticesExist() async throws {
        let jobID = "00000000-0000-4000-8000-000000000123"
        let reply = #"{"admission":"recorded","items":[{"id":"n1","role":"customer","channel":"email","status":"sent","scheduledFor":"2026-11-01T10:00:00Z","createdAt":"2026-11-01T09:00:00Z"}],"nextCursor":"older"}"#
        let api = APIClient(session: URLProtocolFixture.session([.init(200, reply)]), baseURL: base)

        let page = try await api.jobNotices(jobID)

        XCTAssertEqual(page.items.map(\.id), ["n1"])
        XCTAssertTrue(page.more)
        XCTAssertEqual(query(try XCTUnwrap(URLProtocolFixture.recorded.first), "limit"), "100")
    }

    func testJobNoticesOnTheLastPageAreComplete() async throws {
        let jobID = "00000000-0000-4000-8000-000000000123"
        let reply = #"{"admission":"recorded","items":[],"nextCursor":null}"#
        let api = APIClient(session: URLProtocolFixture.session([.init(200, reply)]), baseURL: base)

        let page = try await api.jobNotices(jobID)

        XCTAssertFalse(page.more)
    }
}

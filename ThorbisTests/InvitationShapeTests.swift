import XCTest
@testable import Thorbis

/// An invitation the server stores without a role, and where the confirm-email link sends the
/// browser back to (the web app under /app, not the public site at the root).
final class InvitationShapeTests: XCTestCase {
    private let invitationID = "0193a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b"

    // MARK: Confirm-email callback

    func testCallbackIsTheWebInvitationPageUnderTheAppBase() {
        // services/api/test/invitations.test.ts expects callbackURL=%2Fapp%2Faccept-invitation%3Fid%3Dinv_1.
        XCTAssertEqual(InvitationLink.verificationCallback(for: "inv_1234"), "/app/accept-invitation?id=inv_1234")
        XCTAssertEqual(InvitationLink.verificationCallback(for: invitationID), "/app/accept-invitation?id=\(invitationID)")
    }

    func testCallbackWithoutAUsableIdIsTheWebAppNotThePublicSite() {
        XCTAssertEqual(InvitationLink.verificationCallback(for: nil), "/app/")
        XCTAssertEqual(InvitationLink.verificationCallback(for: ""), "/app/")
        XCTAssertEqual(InvitationLink.verificationCallback(for: "../../etc"), "/app/")
    }

    @MainActor
    func testConfirmEmailRequestAlwaysCarriesTheCallback() async throws {
        let client = APIClient(session: URLProtocolFixture.session([.init(200, #"{"status":true}"#)]), baseURL: "https://app.thorbis.com")
        try await client.sendInvitationVerificationEmail(email: "tech@example.invalid", invitationID: nil)
        let request = try XCTUnwrap(URLProtocolFixture.recorded.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url?.path, "/api/auth/send-verification-email")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.body)) as? [String: Any])
        XCTAssertEqual(body["email"] as? String, "tech@example.invalid")
        XCTAssertEqual(body["callbackURL"] as? String, "/app/")
    }

    // MARK: No role

    func testInvitationWithANullRoleDecodes() throws {
        let reply = #"{"id":"\#(invitationID)","organizationId":"org-1","organizationName":"Wade's Plumbing","inviterEmail":"owner@example.invalid","email":"tech@example.invalid","role":null,"status":"pending","expiresAt":"2026-11-23T12:00:00.000Z"}"#
        let invitation = try JSONDecoder().decode(InvitationDetails.self, from: Data(reply.utf8))
        XCTAssertNil(invitation.role)
        XCTAssertEqual(invitation.organizationName, "Wade's Plumbing")
        XCTAssertEqual(InvitationWords.role(invitation.role), "Team member")
    }

    func testInvitationWithNoRoleKeyDecodes() throws {
        let reply = #"{"id":"\#(invitationID)","organizationId":"org-1","organizationName":"Wade's Plumbing","email":"tech@example.invalid"}"#
        let invitation = try JSONDecoder().decode(InvitationDetails.self, from: Data(reply.utf8))
        XCTAssertNil(invitation.role)
    }

    func testOneRowWithoutARoleKeepsTheWholeList() throws {
        let reply = #"[{"id":"\#(invitationID)","email":"tech@example.invalid","role":null,"organizationId":"org-2","organizationName":"Sierra Drain Co.","status":"pending","expiresAt":"2026-11-20T12:00:00.000Z","createdAt":"2026-11-13T12:00:00.000Z"},{"id":"inv_second_1","email":"tech@example.invalid","role":"technician","organizationId":"org-3","organizationName":"Ridge HVAC","status":"pending","expiresAt":"2026-11-20T12:00:00.000Z","createdAt":"2026-11-13T12:00:00.000Z"}]"#
        let invitations = try JSONDecoder().decode([UserInvitation].self, from: Data(reply.utf8))
        XCTAssertEqual(invitations.map(\.organizationName), ["Sierra Drain Co.", "Ridge HVAC"])
        XCTAssertEqual(invitations.map { InvitationWords.role($0.role) }, ["Team member", "Technician"])
    }

    func testBlankRoleReadsAsNoRole() {
        XCTAssertEqual(InvitationWords.role(""), "Team member")
        XCTAssertEqual(InvitationWords.role("  "), "Team member")
        XCTAssertFalse(InvitationWords.hasRole(nil))
        XCTAssertFalse(InvitationWords.hasRole(" "))
        XCTAssertTrue(InvitationWords.hasRole("technician"))
        XCTAssertEqual(InvitationWords.role("technician"), "Technician")
    }
}

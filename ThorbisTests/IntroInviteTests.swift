import XCTest
@testable import Thorbis

/// App intro (Paper 01–03) and joining a team from an invitation (05A–05C, 29B).
final class IntroInviteTests: XCTestCase {
    private let invitationID = "0193a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b"

    private func freshDefaults() -> UserDefaults {
        let name = "IntroInviteTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    // MARK: Intro gate

    func testIntroShowsOnAFreshInstallOnly() {
        let defaults = freshDefaults()
        XCTAssertTrue(AppIntroGate.shouldShow(defaults: defaults))
        AppIntroGate.markSeen(defaults: defaults)
        XCTAssertFalse(AppIntroGate.shouldShow(defaults: defaults))
    }

    func testIntroNeverShowsToSomeoneWhoHasSignedInBefore() {
        let defaults = freshDefaults()
        defaults.set(false, forKey: AppIntroGate.returningUserKey)
        XCTAssertFalse(AppIntroGate.shouldShow(defaults: defaults))
    }

    // MARK: Intro copy

    func testIntroPaymentPageNamesTapToPayOnlyWhenTheBuildAllowsIt() {
        let off = AppIntroCopy.paymentMessage(tapToPayEnabled: false)
        XCTAssertNil(off.range(of: "tap to pay", options: .caseInsensitive), off)
        for way in ["code to scan", "pay link", "cash", "check"] {
            XCTAssertTrue(off.contains(way), "Missing \(way): \(off)")
        }

        let on = AppIntroCopy.paymentMessage(tapToPayEnabled: true)
        XCTAssertTrue(on.hasPrefix("Tap to Pay"), on)
        for way in ["code to scan", "cash", "check"] {
            XCTAssertTrue(on.contains(way), "Missing \(way): \(on)")
        }
    }

    // MARK: Invitation links

    func testReadsTheIdFromTheEmailLink() throws {
        let url = try XCTUnwrap(URL(string: "https://thorbis.com/app/accept-invitation?id=\(invitationID)"))
        XCTAssertEqual(InvitationLink.id(from: url), invitationID)
        let trailing = try XCTUnwrap(URL(string: "https://app.thorbis.com/accept-invitation/?id=\(invitationID)"))
        XCTAssertEqual(InvitationLink.id(from: trailing), invitationID)
    }

    func testReadsTheIdFromTheAppScheme() throws {
        let url = try XCTUnwrap(URL(string: "thorbis://accept-invitation?id=\(invitationID)"))
        XCTAssertEqual(InvitationLink.id(from: url), invitationID)
    }

    func testIgnoresOtherLinks() throws {
        XCTAssertNil(InvitationLink.id(from: try XCTUnwrap(URL(string: "https://thorbis.com/app/jobs?id=\(invitationID)"))))
        XCTAssertNil(InvitationLink.id(from: try XCTUnwrap(URL(string: "http://thorbis.com/accept-invitation?id=\(invitationID)"))))
        XCTAssertNil(InvitationLink.id(from: try XCTUnwrap(URL(string: "javascript://accept-invitation?id=\(invitationID)"))))
        XCTAssertNil(InvitationLink.id(from: try XCTUnwrap(URL(string: "https://thorbis.com/accept-invitation"))))
        XCTAssertNil(InvitationLink.id(from: try XCTUnwrap(URL(string: "thorbis://schedule"))))
    }

    func testPastedTextAcceptsALinkALinkWithoutSchemeOrABareId() {
        XCTAssertEqual(InvitationLink.id(fromPasted: "  https://thorbis.com/app/accept-invitation?id=\(invitationID)\n"), invitationID)
        XCTAssertEqual(InvitationLink.id(fromPasted: "thorbis.com/app/accept-invitation?id=\(invitationID)"), invitationID)
        XCTAssertEqual(InvitationLink.id(fromPasted: invitationID), invitationID)
    }

    func testPastedTextRefusesWhatCannotBeAnId() {
        XCTAssertNil(InvitationLink.id(fromPasted: ""))
        XCTAssertNil(InvitationLink.id(fromPasted: "RVR-48K"))
        XCTAssertNil(InvitationLink.id(fromPasted: "abc def ghi jkl"))
        XCTAssertNil(InvitationLink.id(fromPasted: "../../etc/passwd"))
        XCTAssertNil(InvitationLink.id(fromPasted: String(repeating: "a", count: 129)))
        XCTAssertNil(InvitationLink.id(fromPasted: "aé" + String(repeating: "b", count: 10)))
    }

    func testVerificationReturnsToTheInvitationPage() {
        XCTAssertEqual(InvitationLink.verificationCallback(for: invitationID), "/accept-invitation?id=\(invitationID)")
        XCTAssertNil(InvitationLink.verificationCallback(for: nil))
        XCTAssertNil(InvitationLink.verificationCallback(for: ""))
    }

    // MARK: Refusals

    func testRefusalsReadLikeTheWebInvitationPage() {
        XCTAssertEqual(InvitationRefusal.from(Problem(title: "EMAIL_VERIFICATION_REQUIRED_FOR_INVITATION", status: 403, detail: nil)), .verifyEmail)
        XCTAssertEqual(InvitationRefusal.from(Problem(title: "EMAIL_VERIFICATION_REQUIRED_BEFORE_ACCEPTING_OR_REJECTING_INVITATION", status: 403, detail: nil)), .verifyEmail)
        XCTAssertEqual(InvitationRefusal.from(Problem(title: "YOU_ARE_NOT_THE_RECIPIENT_OF_THE_INVITATION", status: 403, detail: nil)), .wrongAccount)
        XCTAssertEqual(InvitationRefusal.from(Problem(title: "ORGANIZATION_MEMBERSHIP_LIMIT_REACHED", status: 403, detail: nil)), .teamFull)
        XCTAssertEqual(InvitationRefusal.from(Problem(title: "INVITATION_NOT_FOUND", status: 400, detail: nil)), .gone)
        XCTAssertEqual(InvitationRefusal.from(Problem(title: nil, status: 401, detail: nil)), .signedOut)
        XCTAssertEqual(InvitationRefusal.from(Problem(title: "Network error", status: nil, detail: "No connection.")), .unreachable)
        XCTAssertEqual(InvitationRefusal.from(Problem(title: nil, status: 500, detail: nil)), .unreachable)
    }

    // MARK: Words

    func testRoleWordsUseTheTeamRoleLabels() {
        XCTAssertEqual(InvitationWords.role("technician"), "Technician")
        XCTAssertEqual(InvitationWords.role("office_manager"), "Office manager")
        XCTAssertEqual(InvitationWords.role("field_lead"), "Field lead")
    }

    func testExpiryIsSaidOnlyWhileTheLinkWorks() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let later = ISO8601DateFormatter().string(from: now.addingTimeInterval(7 * 86_400))
        let earlier = ISO8601DateFormatter().string(from: now.addingTimeInterval(-60))
        let words = InvitationWords.expires(later, now: now)
        XCTAssertNotNil(words)
        XCTAssertEqual(words?.first.map { String($0) }, words?.first.map { String($0).uppercased() })
        XCTAssertNil(InvitationWords.expires(earlier, now: now))
        XCTAssertNil(InvitationWords.expires(nil, now: now))
        XCTAssertNotNil(InvitationWords.date("2026-11-16T12:00:00.123Z"))
    }

    // MARK: Routes

    @MainActor
    func testLooksUpTheInvitationOnBetterAuthsInviteePath() async throws {
        let reply = #"{"id":"\#(invitationID)","organizationId":"org-1","organizationName":"Wade's Plumbing","organizationSlug":"wades","inviterEmail":"owner@example.invalid","email":"tech@example.invalid","role":"technician","status":"pending","expiresAt":"2026-11-23T12:00:00.000Z"}"#
        let client = APIClient(session: URLProtocolFixture.session([.init(200, reply)]), baseURL: "https://app.thorbis.com")
        let invitation = try await client.invitation(id: invitationID)
        XCTAssertEqual(invitation.organizationName, "Wade's Plumbing")
        XCTAssertEqual(invitation.inviterEmail, "owner@example.invalid")
        let request = try XCTUnwrap(URLProtocolFixture.recorded.first)
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.url?.path, "/api/auth/organization/get-invitation")
        let query = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(query?.first { $0.name == "id" }?.value, invitationID)
    }

    @MainActor
    func testAcceptSendsOnlyTheInvitationId() async throws {
        let client = APIClient(session: URLProtocolFixture.session([.init(200, #"{"invitation":{},"member":{}}"#)]), baseURL: "https://app.thorbis.com")
        try await client.acceptInvitation(id: invitationID)
        let request = try XCTUnwrap(URLProtocolFixture.recorded.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url?.path, "/api/auth/organization/accept-invitation")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.body)) as? [String: Any])
        XCTAssertEqual(Set(body.keys), ["invitationId"])
        XCTAssertEqual(body["invitationId"] as? String, invitationID)
    }

    @MainActor
    func testRefusalFromTheServerKeepsItsCode() async throws {
        let reply = #"{"code":"YOU_ARE_NOT_THE_RECIPIENT_OF_THE_INVITATION","message":"You are not the recipient of the invitation"}"#
        let client = APIClient(session: URLProtocolFixture.session([.init(403, reply)]), baseURL: "https://app.thorbis.com")
        do {
            try await client.acceptInvitation(id: invitationID)
            XCTFail("A refused invitation must throw")
        } catch {
            XCTAssertEqual(InvitationRefusal.from(error), .wrongAccount)
        }
    }

    @MainActor
    func testListsInvitationsSentToThisAccount() async throws {
        let reply = #"[{"id":"\#(invitationID)","email":"tech@example.invalid","role":"technician","organizationId":"org-2","organizationName":"Sierra Drain Co.","inviterId":"u-1","status":"pending","expiresAt":"2026-11-20T12:00:00.000Z","createdAt":"2026-11-13T12:00:00.000Z"}]"#
        let client = APIClient(session: URLProtocolFixture.session([.init(200, reply)]), baseURL: "https://app.thorbis.com")
        let invitations = try await client.userInvitations()
        XCTAssertEqual(invitations.map(\.organizationName), ["Sierra Drain Co."])
        XCTAssertEqual(URLProtocolFixture.recorded.first?.url?.path, "/api/auth/organization/list-user-invitations")
    }
}

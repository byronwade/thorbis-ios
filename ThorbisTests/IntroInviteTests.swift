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

    // MARK: Tap to Pay wording follows the build flag (help, tour, pay screen, intro card)

    private func namesTapToPay(_ text: String) -> Bool {
        text.range(of: "tap to pay", options: .caseInsensitive) != nil
    }

    /// Every field a person can read or search by. HelpArticle's == compares ids only.
    private func readable(_ article: HelpArticle) -> [String] {
        var fields: [String] = [article.id, article.category, article.title, article.summary, article.note ?? ""]
        for step in article.steps { fields.append(step.symbol); fields.append(step.text) }
        fields.append(contentsOf: article.keywords)
        fields.append(contentsOf: article.related)
        return fields
    }

    private func article(_ id: String, tapToPayEnabled: Bool) throws -> HelpArticle {
        try XCTUnwrap(HelpCatalog.allArticles(tapToPayEnabled: tapToPayEnabled).first { $0.id == id })
    }

    func testHelpWithTapToPayOnKeepsTodaysWords() throws {
        let collect = try article("payment-collect", tapToPayEnabled: true)
        XCTAssertEqual(collect.summary, "Tap to Pay, a code to scan, check, cash or a bank transfer.")
        XCTAssertEqual(collect.steps, [
            HelpStep(symbol: "creditcard", text: "Open the invoice and tap Collect payment."),
            HelpStep(symbol: "dollarsign.circle", text: "Check the amount."),
            HelpStep(symbol: "wave.3.right", text: "Choose how: Tap to Pay on iPhone when your business has it set up, Show a code to scan, Check, Cash, or Bank transfer or other."),
            HelpStep(symbol: "checkmark.circle", text: "Finish on the phone. The invoice shows the new balance."),
        ])
        XCTAssertEqual(collect.note, "Cards, payment links and Tap to Pay need signal. Cash and checks can be recorded with no signal and send when you are back online.")
        XCTAssertEqual(collect.keywords, ["pay", "paid", "card", "tap to pay", "cash", "check", "cheque", "ach", "charge", "money"])
        XCTAssertEqual(try article("offline", tapToPayEnabled: true).note, "Cards, payment links and Tap to Pay need signal.")
        XCTAssertTrue(HelpSearch.results("tap to pay", in: HelpCatalog.allArticles(tapToPayEnabled: true)).map(\.id).contains("payment-collect"))
    }

    func testHelpWithTapToPayOffNamesOnlyTheCollectScreensWays() throws {
        let off = HelpCatalog.allArticles(tapToPayEnabled: false)
        for article in off {
            for field in readable(article) {
                XCTAssertFalse(namesTapToPay(field), "\(article.id): \(field)")
            }
            XCTAssertFalse(namesTapToPay(article.shareText), article.id)
        }
        let collect = try article("payment-collect", tapToPayEnabled: false)
        XCTAssertEqual(collect.summary, "A code to scan, check, cash or a bank transfer.")
        XCTAssertEqual(collect.steps[2], HelpStep(symbol: "qrcode", text: "Choose how: Show a code to scan, Check, Cash, or Bank transfer or other."))
        for way in ["Show a code to scan", "Check", "Cash", "Bank transfer or other"] {
            XCTAssertTrue(collect.steps[2].text.contains(way), "Missing \(way): \(collect.steps[2].text)")
        }
        XCTAssertEqual(collect.note, "Cards and payment links need signal. Cash and checks can be recorded with no signal and send when you are back online.")
        XCTAssertEqual(collect.keywords, ["pay", "paid", "card", "cash", "check", "cheque", "ach", "charge", "money"])
        XCTAssertEqual(try article("offline", tapToPayEnabled: false).note, "Cards and payment links need signal.")
        // No keyword says Tap to Pay any more, so it no longer lifts the article in a search for it.
        // Search matches parts of words, so "tap", "to" and "pay" still match the body text.
        for article in off {
            XCTAssertFalse(article.keywords.contains { $0.localizedCaseInsensitiveContains("tap") }, article.id)
        }
        let words = HelpSearch.words("tap to pay")
        let collectOn = try article("payment-collect", tapToPayEnabled: true)
        XCTAssertEqual(HelpSearch.score(collectOn, words: words), 7)
        XCTAssertEqual(HelpSearch.score(collect, words: words), 5)
        XCTAssertTrue(HelpSearch.results("cash signal", in: off).map(\.id).contains("payment-collect"))
    }

    func testHelpArticlesKeepTheirShapeWhicheverTheFlag() throws {
        let on = HelpCatalog.allArticles(tapToPayEnabled: true)
        let off = HelpCatalog.allArticles(tapToPayEnabled: false)
        XCTAssertEqual(on.map(\.id), off.map(\.id))
        for (lhs, rhs) in zip(on, off) {
            XCTAssertEqual(lhs.steps.count, rhs.steps.count, lhs.id)
            XCTAssertEqual(lhs.related, rhs.related, lhs.id)
            XCTAssertEqual(lhs.category, rhs.category, lhs.id)
            XCTAssertEqual(lhs.title, rhs.title, lhs.id)
            // Only the two articles that name Tap to Pay differ at all.
            if !["payment-collect", "offline"].contains(lhs.id) {
                XCTAssertEqual(readable(lhs), readable(rhs), lhs.id)
            }
        }
        let collectOn = try article("payment-collect", tapToPayEnabled: true)
        let collectOff = try article("payment-collect", tapToPayEnabled: false)
        XCTAssertEqual(collectOff.steps.count, 4)
        XCTAssertEqual(collectOff.related, ["payment-link", "offline"])
        XCTAssertEqual(collectOn.related, collectOff.related)
        XCTAssertEqual(try article("offline", tapToPayEnabled: false).related, ["on-this-phone", "payment-collect"])
        // The catalogue the app shows is the one for this build's flag.
        let built = HelpCatalog.allArticles(tapToPayEnabled: TapToPayReadiness.buildEnabled)
        XCTAssertEqual(HelpCatalog.articles.map { readable($0) }, built.map { readable($0) })
    }

    func testGettingPaidTourFollowsTheFlag() {
        let on = HelpTours.gettingPaidTour(tapToPayEnabled: true)
        XCTAssertEqual(on, GuidedTour(name: "Getting paid on site", steps: [
            GuidedTourStep(id: "paid-invoice", target: nil, title: "Start from the invoice",
                           message: "On the job, tap Create invoice, check the lines and tap Issue invoice."),
            GuidedTourStep(id: "paid-collect", target: nil, title: "Tap Collect payment",
                           message: "Check the amount, then choose Tap to Pay on iPhone, a code to scan, Check, Cash or a bank transfer."),
            GuidedTourStep(id: "paid-offline", target: nil, title: "No signal?",
                           message: "Cash and checks can be recorded offline and send later. Cards and payment links need signal."),
        ]))

        let off = HelpTours.gettingPaidTour(tapToPayEnabled: false)
        XCTAssertEqual(off.name, on.name)
        XCTAssertEqual(off.steps.map(\.id), on.steps.map(\.id))
        for step in off.steps {
            XCTAssertFalse(namesTapToPay(step.title), step.id)
            XCTAssertFalse(namesTapToPay(step.message), step.id)
        }
        let collect = off.steps[1].message
        XCTAssertEqual(collect, "Check the amount, then choose Show a code to scan, Check, Cash, or Bank transfer or other.")
        for way in ["Show a code to scan", "Check", "Cash", "Bank transfer or other"] {
            XCTAssertTrue(collect.contains(way), "Missing \(way): \(collect)")
        }
        XCTAssertEqual(HelpTours.gettingPaid, HelpTours.gettingPaidTour(tapToPayEnabled: TapToPayReadiness.buildEnabled))
    }

    func testCustomerPayInFullLineFollowsTheFlag() {
        XCTAssertEqual(CustomerPayWords.payInFullDetail(tapToPayEnabled: true), "Card or Tap to Pay with your technician")
        let off = CustomerPayWords.payInFullDetail(tapToPayEnabled: false)
        XCTAssertFalse(namesTapToPay(off), off)
        XCTAssertEqual(off, "Your technician shows a code to pay by card, or takes cash or check")
        for way in ["code", "card", "cash", "check"] {
            XCTAssertTrue(off.contains(way), "Missing \(way): \(off)")
        }
    }

    func testIntroPaymentCaptionFollowsTheFlag() {
        XCTAssertEqual(AppIntroCopy.paymentCaption(tapToPayEnabled: true), "Hold card near your phone")
        let off = AppIntroCopy.paymentCaption(tapToPayEnabled: false)
        XCTAssertFalse(namesTapToPay(off), off)
        XCTAssertFalse(off.localizedCaseInsensitiveContains("hold card"), off)
        XCTAssertEqual(off, "Show a code to scan")
    }

    func testCollectPaymentReleaseNoteFollowsTheFlag() throws {
        XCTAssertEqual(ReleaseNotes.collectPaymentDetail(tapToPayEnabled: true),
                       "Tap to Pay leads, with a code to scan, check, cash or bank transfer underneath.")
        let off = ReleaseNotes.collectPaymentDetail(tapToPayEnabled: false)
        XCTAssertFalse(namesTapToPay(off), off)
        XCTAssertEqual(off, "Show a code to scan leads, with Text a pay link, Check, Cash and Bank transfer or other underneath.")
        for way in ["Show a code to scan", "Text a pay link", "Check", "Cash", "Bank transfer or other"] {
            XCTAssertTrue(off.contains(way), "Missing \(way): \(off)")
        }
        // The note the app shows is the one for this build's flag.
        let note = try XCTUnwrap(ReleaseNotes.all.first { $0.id == "2026-11-16-settings-team-paper" })
        let collect = try XCTUnwrap(note.highlights.first { $0.title == "A simpler Collect payment" })
        XCTAssertEqual(collect.detail, ReleaseNotes.collectPaymentDetail(tapToPayEnabled: TapToPayReadiness.buildEnabled))
        // With the flag off, no note claims Tap to Pay, except the one that records it is not ready.
        if !TapToPayReadiness.buildEnabled {
            for entry in ReleaseNotes.all where entry.id != "2026-10-28-tap-readiness" {
                for item in entry.highlights {
                    XCTAssertFalse(namesTapToPay(item.title), "\(entry.id): \(item.title)")
                    XCTAssertFalse(namesTapToPay(item.detail), "\(entry.id): \(item.detail)")
                }
            }
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

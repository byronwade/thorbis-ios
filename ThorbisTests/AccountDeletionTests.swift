import XCTest
@testable import Thorbis

/// Paper v2 68 · Delete account — confirm.
final class AccountDeletionTests: XCTestCase {
    func testOnlyTheWordDeleteConfirms() {
        XCTAssertTrue(AccountDeletionOutcome.confirms("DELETE"))
        XCTAssertTrue(AccountDeletionOutcome.confirms(" delete "), "Case and stray spaces don't matter")
        XCTAssertFalse(AccountDeletionOutcome.confirms(""))
        XCTAssertFalse(AccountDeletionOutcome.confirms("DELET"))
        XCTAssertFalse(AccountDeletionOutcome.confirms("DELETE ME"))
    }

    func testServerReasonCodeIsRead() throws {
        let body = Data(#"{"type":"https://thorbis.com/problems/conflict","title":"conflict","status":409,"category":"conflict","detail":"the password could not be verified","code":"reauthentication_rejected"}"#.utf8)
        let problem = try JSONDecoder().decode(Problem.self, from: body)
        XCTAssertEqual(problem.code, "reauthentication_rejected")
        XCTAssertNil(Problem(title: "x", status: nil, detail: nil).code)
    }

    func testEveryRefusalSaysNothingWasDeleted() {
        XCTAssertEqual(AccountDeletionOutcome(signInCheck: 409, code: "reauthentication_rejected"), .wrongPassword)
        XCTAssertEqual(AccountDeletionOutcome(signInCheck: 409, code: "reauthentication_unavailable"), .notAvailable)
        XCTAssertNotEqual(AccountDeletionOutcome(signInCheck: 401), .wrongPassword, "A lapsed sign-in is not a wrong password")
        XCTAssertEqual(AccountDeletionOutcome(status: 409, detail: nil, code: "account_lifecycle_policy_unavailable"), .notAvailable)
        let again = AccountDeletionOutcome(status: 409, detail: "recent reauthentication is required", code: "reauthentication_required")
        XCTAssertEqual(again.message, "Thorbis needs to check your password again. Nothing was deleted. Try again.")
        XCTAssertTrue(AccountDeletionOutcome(signInCheck: 401).message?.contains("Nothing was deleted") == true)
        XCTAssertEqual(AccountDeletionOutcome(signInCheck: 429), .tooManyTries)
        XCTAssertEqual(AccountDeletionOutcome(signInCheck: 404), .notAvailable)
        XCTAssertEqual(AccountDeletionOutcome(status: 409, detail: "account lifecycle retention policy is not configured"), .notAvailable)
        for outcome in [AccountDeletionOutcome.wrongPassword, .tooManyTries, .notAvailable, AccountDeletionOutcome(signInCheck: 500)] {
            XCTAssertTrue(outcome.message?.contains("Nothing was deleted") == true, "\(outcome)")
        }
        XCTAssertEqual(AccountDeletionOutcome(status: 500, detail: nil).message, "Your account wasn't deleted. Try again.")
        XCTAssertNil(AccountDeletionOutcome.requested.message)
    }

    func testRequestBodyCarriesTheSelfServiceReason() throws {
        let data = try JSONEncoder().encode(AccountDeletionRequestBody(reauthenticationId: "proof"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(json["reauthenticationId"], "proof")
        XCTAssertEqual(json["reason"], "self_service_account_deletion")
    }
}

/// Texts and email stay out of the Inbox until the server can deliver them.
final class InboxMessagingGateTests: XCTestCase {
    func testWithoutMessagingTheInboxIsCallsAndNoticesOnly() {
        let access = CommsInboxAccess(workspace: false, notices: true, calls: true)
        XCTAssertEqual(access.sections, [.all, .calls, .voicemail, .notices])
        XCTAssertEqual(CommsInboxFilter.available(access), [.all, .unread, .calls])
        XCTAssertFalse(CommsInboxAccess(workspace: false, notices: false, calls: false).visible)
    }
}

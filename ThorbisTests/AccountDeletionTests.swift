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

    func testEveryRefusalSaysNothingWasDeleted() {
        XCTAssertEqual(AccountDeletionOutcome(signInCheck: 401), .wrongPassword)
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

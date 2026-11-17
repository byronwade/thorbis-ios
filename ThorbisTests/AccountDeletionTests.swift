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

    func testTheServerRefusingTheSignInCheckSaysNothingWasDeleted() {
        let refused = AccountDeletionOutcome(status: 409, detail: "recent reauthentication is required")
        XCTAssertEqual(refused, .needsSignInCheck)
        XCTAssertTrue(refused.message?.contains("Nothing was deleted") == true)
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

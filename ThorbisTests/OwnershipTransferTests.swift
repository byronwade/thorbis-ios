import XCTest
@testable import Thorbis

final class OwnershipTransferTests: XCTestCase {
    func testReasonFallsBackAndIsCapped() {
        XCTAssertEqual(OwnershipTransferRules.reason("  "), OwnershipTransferRules.defaultReason)
        XCTAssertEqual(OwnershipTransferRules.reason(" Selling the business "), "Selling the business")
        XCTAssertEqual(OwnershipTransferRules.reason(String(repeating: "a", count: 900)).count, 500)
    }

    func testRefusalsReadPlainly() {
        XCTAssertEqual(OwnershipTransferRules.message(for: Problem(title: nil, status: 403, detail: nil), name: "Ann"),
                       "Only the owner can hand over ownership.")
        XCTAssertEqual(OwnershipTransferRules.message(for: Problem(title: nil, status: 409, detail: nil), name: "Ann"),
                       "Ann already owns this company.")
        XCTAssertEqual(OwnershipTransferRules.message(for: Problem(title: nil, status: 404, detail: nil), name: "Ann"),
                       "Ann is no longer on the team.")
    }

    func testTransferDecodes() throws {
        let body = #"{"previousOwnerMemberId":"m1","newOwnerMemberId":"m2","newOwnerUserId":"u2","transferredAt":"2026-10-31T21:00:00.000Z"}"#
        XCTAssertEqual(try JSONDecoder().decode(TransferredOwnership.self, from: Data(body.utf8)),
                       TransferredOwnership(previousOwnerMemberId: "m1", newOwnerMemberId: "m2", newOwnerUserId: "u2",
                                            transferredAt: "2026-10-31T21:00:00.000Z"))
    }
}

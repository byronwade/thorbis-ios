import XCTest
@testable import Thorbis

@MainActor
final class MemberRemovalTests: XCTestCase {
    func testReasonFallsBackAndIsBounded() {
        XCTAssertEqual(MemberRemovalRules.reason("  "), MemberRemovalRules.defaultReason)
        XCTAssertEqual(MemberRemovalRules.reason(" Left the company "), "Left the company")
        XCTAssertEqual(MemberRemovalRules.reason(String(repeating: "a", count: 900)).count, 500)
    }

    func testServerRefusalsReadInPlainWords() {
        XCTAssertEqual(MemberRemovalRules.message(for: Problem(title: nil, status: 409, detail: "owner"), name: "Ann"),
                       "Owners and your own account can't be removed.")
        XCTAssertEqual(MemberRemovalRules.message(for: Problem(title: nil, status: 404, detail: nil), name: "Ann"),
                       "Ann is no longer on the team.")
        XCTAssertTrue(MemberRemovalRules.message(for: Problem(title: nil, status: 403, detail: nil), name: "Ann").contains("Ask an owner"))
    }

    func testRemovalDecodes() throws {
        let body = #"{"memberId":"m1","userId":"u1","removedAt":"2026-10-28T14:00:00.000Z"}"#
        XCTAssertEqual(try JSONDecoder().decode(MemberRemoval.self, from: Data(body.utf8)),
                       MemberRemoval(memberId: "m1", userId: "u1", removedAt: "2026-10-28T14:00:00.000Z"))
    }
}

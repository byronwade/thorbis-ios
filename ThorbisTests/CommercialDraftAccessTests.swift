import XCTest
@testable import Thorbis

@MainActor final class CommercialDraftAccessTests: XCTestCase {
    func testDeniedReadCannotRevealDraft() async {
        let result = await CommercialDraftAccess.verify(expectedScope: "scope", currentScope: { "scope" }, read: {
            throw NSError(domain: "denied", code: 403)
        }, matches: { (_: Int) in true })
        XCTAssertFalse(result)
    }

    func testAuthorityChangeDuringReadCannotRevealDraft() async {
        var current = "before"
        let result = await CommercialDraftAccess.verify(expectedScope: "before", currentScope: { current }, read: {
            current = "after"
            return 2
        }, matches: { $0 == 2 })
        XCTAssertFalse(result)
    }

    func testChangedRevisionCannotRevealDraft() async {
        let result = await CommercialDraftAccess.verify(expectedScope: "scope", currentScope: { "scope" }, read: { 3 }, matches: { $0 == 2 })
        XCTAssertFalse(result)
    }

    func testLiveMatchingReadAllowsDraft() async {
        let result = await CommercialDraftAccess.verify(expectedScope: "scope", currentScope: { "scope" }, read: { 2 }, matches: { $0 == 2 })
        XCTAssertTrue(result)
    }
}

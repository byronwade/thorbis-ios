import XCTest
@testable import Thorbis

@MainActor
final class CustomerInvoiceOpenLeaseTests: XCTestCase {
    func testDismissalAllowsNewOpenAndOldCompletionCannotClearIt() throws {
        let navigation = CustomerJobPaperNavigation()
        let old = try XCTUnwrap(navigation.beginOpen("invoice-a"))
        XCTAssertNil(navigation.beginOpen("invoice-b"), "Repeated taps must not start a second open")
        navigation.invalidatePendingOpen()
        XCTAssertNil(navigation.openingID)
        let current = try XCTUnwrap(navigation.beginOpen("invoice-b"))
        navigation.finishOpen(old)
        XCTAssertEqual(navigation.openingID, "invoice-b", "Old completion cannot clear the new request")
        XCTAssertEqual(navigation.requestRevision, current)
        navigation.finishOpen(current)
        XCTAssertNil(navigation.openingID)
    }
}

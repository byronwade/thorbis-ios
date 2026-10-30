import XCTest
@testable import Thorbis

final class CustomerJobDocumentBookTests: XCTestCase {
    func testSelectionKeepsKindAndIdentityWhileMovingWithoutWrapping() {
        let estimate = CustomerJobDocumentID.estimate("same-id")
        let invoice = CustomerJobDocumentID.invoice("same-id")
        var state = CustomerJobDocumentSelection(ids: [estimate, estimate, invoice], selected: estimate)
        XCTAssertEqual(state.ids, [estimate, invoice])
        XCTAssertNil(state.previous)
        XCTAssertEqual(state.next, invoice)
        state.select(invoice)
        XCTAssertEqual(state.position, "2 of 2 documents")
        XCTAssertEqual(state.previous, estimate)
        XCTAssertNil(state.next)
        state.select(.invoice("unrelated"))
        XCTAssertEqual(state.selected, invoice)
    }

    func testRemovingSelectedDocumentNeverReusesItsIndexForAnother() {
        let first = CustomerJobDocumentID.estimate("first")
        let second = CustomerJobDocumentID.estimate("second")
        var state = CustomerJobDocumentSelection(ids: [first, second], selected: second)
        state.reconcile([second, first])
        XCTAssertEqual(state.selected, second)
        XCTAssertEqual(state.position, "1 of 2 documents")
        state.reconcile([first])
        XCTAssertNil(state.selected)
        XCTAssertNil(state.previous)
        XCTAssertNil(state.next)
    }
}

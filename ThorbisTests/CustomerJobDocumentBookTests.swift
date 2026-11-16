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

    func testEachDocumentVisitHasDistinctActivation() {
        let first = CustomerJobDocumentID.estimate("first")
        let second = CustomerJobDocumentID.estimate("second")
        var state = CustomerJobDocumentSelection(ids: [first, second], selected: first)
        let firstVisit = state.activation
        state.select(first)
        XCTAssertEqual(state.activation, firstVisit)
        state.select(second)
        XCTAssertNotEqual(state.activation, firstVisit)
        let secondVisit = state.activation
        state.select(first)
        XCTAssertNotEqual(state.activation, firstVisit)
        XCTAssertNotEqual(state.activation, secondVisit)
        let lastVisit = state.activation
        state.reconcile([second])
        XCTAssertNil(state.selected)
        XCTAssertNotEqual(state.activation, lastVisit)
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

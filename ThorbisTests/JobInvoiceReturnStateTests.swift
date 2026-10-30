import Foundation
import XCTest
@testable import Thorbis

final class JobInvoiceReturnStateTests: XCTestCase {
    private func route(_ invoiceID: String) -> JobInvoiceRoute {
        .init(jobID: "job", invoiceID: invoiceID, organizationID: "org", customerID: "customer",
              actorID: "actor", sessionGeneration: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
              authorityRevision: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!)
    }

    func testOnlyFreshMatchingEligibleInvoiceCanEnableCollection() {
        let first = route("2209")
        var state = JobInvoiceReturnState()
        var token = state.begin(first)
        XCTAssertNil(state.collectibleInvoiceID)
        state.finish(requestID: token, scopeValid: true, fresh: true, actualInvoiceID: "2240", canCollect: true)
        XCTAssertNil(state.collectibleInvoiceID)
        token = state.begin(first)
        state.finish(requestID: token, scopeValid: true, fresh: false, actualInvoiceID: "2209", canCollect: true)
        XCTAssertNil(state.collectibleInvoiceID)
        token = state.begin(first)
        state.finish(requestID: token, scopeValid: false, fresh: true, actualInvoiceID: "2209", canCollect: true)
        XCTAssertNil(state.collectibleInvoiceID)
        token = state.begin(first)
        state.finish(requestID: token, scopeValid: true, fresh: true, actualInvoiceID: "2209", canCollect: false)
        XCTAssertNil(state.collectibleInvoiceID)
        token = state.begin(first)
        state.finish(requestID: token, scopeValid: true, fresh: true, actualInvoiceID: "2209", canCollect: true)
        XCTAssertEqual(state.collectibleInvoiceID, "2209")
    }

    func testLaterReturnOrInvalidationDiscardsEarlierCompletion() {
        let first = route("2209"), second = route("2240")
        var state = JobInvoiceReturnState()
        let firstToken = state.begin(first)
        let secondToken = state.begin(second)
        state.finish(requestID: firstToken, scopeValid: true, fresh: true, actualInvoiceID: "2209", canCollect: true)
        XCTAssertNil(state.collectibleInvoiceID)
        state.finish(requestID: secondToken, scopeValid: true, fresh: true, actualInvoiceID: "2240", canCollect: true)
        XCTAssertEqual(state.collectibleInvoiceID, "2240")
        state.invalidate()
        state.finish(requestID: secondToken, scopeValid: true, fresh: true, actualInvoiceID: "2240", canCollect: true)
        XCTAssertNil(state.collectibleInvoiceID)
    }
}

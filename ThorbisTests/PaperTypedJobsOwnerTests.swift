import Foundation
import XCTest
@testable import Thorbis

@MainActor
final class PaperTypedJobsOwnerTests: XCTestCase {
    func testPendingInvoicePopExpiresWhenPathChangesButNotForNoOp() throws {
        let route = JobInvoiceRoute(jobID: "job", invoiceID: "invoice", organizationID: "org", customerID: "customer", actorID: "actor", sessionGeneration: UUID(), authorityRevision: UUID(), presentationID: UUID(), apiGeneration: UUID(), apiOrigin: "https://app.example.test")
        let root: [PaperTypedJobsRoute] = [.paper(.job("job"))]
        let detail = root + [.invoice(route)]
        let owner = PaperTypedJobsOwner()
        owner.changed(from: root, to: detail)
        XCTAssertNil(owner.pop)
        owner.changed(from: detail, to: root)
        let pop = try XCTUnwrap(owner.pop)
        XCTAssertEqual(pop.route, route)
        owner.changed(from: root, to: root)
        XCTAssertEqual(owner.pop?.id, pop.id)
        owner.changed(from: root, to: root + [.paper(.invoices)])
        XCTAssertNil(owner.pop)
    }
}

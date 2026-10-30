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
        XCTAssertEqual(pop.routes, [route])
        owner.changed(from: root, to: root)
        XCTAssertEqual(owner.pop?.id, pop.id)
        owner.changed(from: root, to: root + [.paper(.invoices)])
        XCTAssertNil(owner.pop)
    }
    func testMultiLevelPopRetainsEachInvoicePresentation() throws {
        let first = JobInvoiceRoute(jobID: "job", invoiceID: "a", organizationID: "org", customerID: "customer", actorID: "actor", sessionGeneration: UUID(), authorityRevision: UUID(), presentationID: UUID(), apiGeneration: UUID(), apiOrigin: "https://app.example.test")
        let second = JobInvoiceRoute(jobID: "job", invoiceID: "b", organizationID: "org", customerID: "customer", actorID: "actor", sessionGeneration: first.sessionGeneration, authorityRevision: first.authorityRevision, presentationID: UUID(), apiGeneration: first.apiGeneration, apiOrigin: first.apiOrigin)
        let root: [PaperTypedJobsRoute] = [.paper(.job("job"))]
        let owner = PaperTypedJobsOwner()
        owner.changed(from: root + [.invoice(first), .paper(.job("job")), .invoice(second)], to: root)
        let event = try XCTUnwrap(owner.pop)
        XCTAssertEqual(event.routes, [first, second])
        XCTAssertEqual(event.routes.last(where: { $0.presentationID == first.presentationID })?.invoiceID, "a")
        XCTAssertEqual(event.routes.last(where: { $0.presentationID == second.presentationID })?.invoiceID, "b")
    }

}

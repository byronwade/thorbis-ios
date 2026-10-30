import Foundation
import XCTest
@testable import Thorbis

final class JobInvoiceRouteTransitionTests: XCTestCase {
    private enum Route: Equatable {
        case job(String)
        case invoice(JobInvoiceRoute)
    }

    private let actor = "actor-a"
    private let organization = "org-a"
    private let customer = "customer-a"
    private let session = UUID()
    private let authority = UUID(), presentation = UUID(), apiGeneration = UUID()
    private let origin = "https://app.example.test"

    private func invoice(_ id: String, job: String = "job-a") -> JobInvoiceRoute {
        .init(jobID: job, invoiceID: id, organizationID: organization, customerID: customer,
              actorID: actor, sessionGeneration: session, authorityRevision: authority, presentationID: presentation, apiGeneration: apiGeneration, apiOrigin: origin)
    }

    private func popped(_ old: [Route], _ new: [Route]) -> JobInvoiceRoute? {
        JobInvoiceRouteTransition.completedPop(from: old, to: new) { route in
            if case let .invoice(value) = route { return value }
            return nil
        }
    }

    func testOnlyAnExactTopInvoicePopReturnsItsIdentity() {
        let root: [Route] = [.job("job-a")]
        let first = invoice("invoice-2209")
        let second = invoice("invoice-2240")
        XCTAssertNil(popped(root, root + [.invoice(first)]))
        XCTAssertNil(popped(root + [.invoice(first)], root + [.invoice(first)]))
        XCTAssertEqual(popped(root + [.invoice(first)], root), first)
        XCTAssertEqual(popped(root + [.invoice(second)], root), second)
        XCTAssertNil(popped(root + [.invoice(first), .invoice(second)], root))
        XCTAssertNil(popped(root + [.invoice(first)], [.job("other-job")]))
        XCTAssertNil(popped(root, []))
    }

    func testRouteScopeMatchesAllCapturedAuthorityAndJobFields() {
        let route = invoice("invoice-2209")
        XCTAssertTrue(route.matches(jobID: "job-a", organizationID: organization, customerID: customer,
                                    actorID: actor, sessionGeneration: session, authorityRevision: authority, presentationID: presentation, apiGeneration: apiGeneration, apiOrigin: origin))
        XCTAssertFalse(route.matches(jobID: "job-b", organizationID: organization, customerID: customer,
                                     actorID: actor, sessionGeneration: session, authorityRevision: authority, presentationID: presentation, apiGeneration: apiGeneration, apiOrigin: origin))
        XCTAssertFalse(route.matches(jobID: "job-a", organizationID: "org-b", customerID: customer,
                                     actorID: actor, sessionGeneration: session, authorityRevision: authority, presentationID: presentation, apiGeneration: apiGeneration, apiOrigin: origin))
        XCTAssertFalse(route.matches(jobID: "job-a", organizationID: organization, customerID: "customer-b",
                                     actorID: actor, sessionGeneration: session, authorityRevision: authority, presentationID: presentation, apiGeneration: apiGeneration, apiOrigin: origin))
        XCTAssertFalse(route.matches(jobID: "job-a", organizationID: organization, customerID: customer,
                                     actorID: "actor-b", sessionGeneration: session, authorityRevision: authority, presentationID: presentation, apiGeneration: apiGeneration, apiOrigin: origin))
        XCTAssertFalse(route.matches(jobID: "job-a", organizationID: organization, customerID: customer,
                                     actorID: actor, sessionGeneration: UUID(), authorityRevision: authority, presentationID: presentation, apiGeneration: apiGeneration, apiOrigin: origin))
        XCTAssertFalse(route.matches(jobID: "job-a", organizationID: organization, customerID: customer,
                                     actorID: actor, sessionGeneration: session, authorityRevision: UUID(), presentationID: presentation, apiGeneration: apiGeneration, apiOrigin: origin))
    }
    func testRouteRejectsDifferentPresentationAndAPIIdentity() {
        let route = invoice("invoice-2209")
        XCTAssertFalse(route.matches(jobID: "job-a", organizationID: organization, customerID: customer, actorID: actor,
            sessionGeneration: session, authorityRevision: authority, presentationID: UUID(), apiGeneration: apiGeneration, apiOrigin: origin))
        XCTAssertFalse(route.matches(jobID: "job-a", organizationID: organization, customerID: customer, actorID: actor,
            sessionGeneration: session, authorityRevision: authority, presentationID: presentation, apiGeneration: UUID(), apiOrigin: origin))
        XCTAssertFalse(route.matches(jobID: "job-a", organizationID: organization, customerID: customer, actorID: actor,
            sessionGeneration: session, authorityRevision: authority, presentationID: presentation, apiGeneration: apiGeneration, apiOrigin: "https://other.example.test"))
    }

}

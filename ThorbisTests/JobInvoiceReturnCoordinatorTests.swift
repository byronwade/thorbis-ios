import Foundation
import XCTest
@testable import Thorbis

final class JobInvoiceReturnCoordinatorTests: XCTestCase {
    private enum Route: Equatable { case job(String), invoice(JobInvoiceRoute) }
    private let generation = UUID(), authority = UUID(), presentation = UUID(), apiGeneration = UUID()
    private let origin = "https://app.example.test"

    private func context(actor: String = "actor", job: String = "job", presentationID: UUID? = nil) -> JobInvoiceReturnContext {
        .init(jobID: job, organizationID: "org", customerID: "customer", actorID: actor,
              sessionGeneration: generation, authorityRevision: authority, presentationID: presentationID ?? presentation, apiGeneration: apiGeneration, apiOrigin: origin)
    }
    private func route(_ invoice: String) -> JobInvoiceRoute {
        .init(jobID: "job", invoiceID: invoice, organizationID: "org", customerID: "customer", actorID: "actor",
              sessionGeneration: generation, authorityRevision: authority, presentationID: presentation, apiGeneration: apiGeneration, apiOrigin: origin)
    }
    private func pop(_ old: [Route], _ new: [Route], _ context: JobInvoiceReturnContext?, _ state: inout JobInvoiceReturnCoordinator) -> UUID? {
        state.completedPop(from: old, to: new, context: context) { route in
            if case let .invoice(value) = route { return value }; return nil
        }
    }

    func testCompletedPopEnablesOnlyExactVerifiedInvoice() throws {
        let job: [Route] = [.job("job")], item = route("2209")
        var state = JobInvoiceReturnCoordinator()
        XCTAssertNil(pop(job + [.invoice(item)], job + [.invoice(item)], context(), &state))
        let token = try XCTUnwrap(pop(job + [.invoice(item)], job, context(), &state))
        XCTAssertNil(state.collectibleInvoiceID(in: context()))
        state.finish(requestID: token, context: context(), fresh: true, actualInvoiceID: "2240", canCollect: true)
        XCTAssertNil(state.collectibleInvoiceID(in: context()))
        let next = try XCTUnwrap(pop(job + [.invoice(item)], job, context(), &state))
        state.finish(requestID: next, context: context(), fresh: true, actualInvoiceID: "2209", canCollect: true)
        XCTAssertEqual(state.collectibleInvoiceID(in: context()), "2209")
    }

    func testChangedAuthorityRetiresSelectionAndLateResponsesCannotRestoreIt() throws {
        let job: [Route] = [.job("job")], item = route("2209")
        var state = JobInvoiceReturnCoordinator()
        let token = try XCTUnwrap(pop(job + [.invoice(item)], job, context(), &state))
        state.finish(requestID: token, context: context(actor: "other"), fresh: true, actualInvoiceID: "2209", canCollect: true)
        state.finish(requestID: token, context: context(), fresh: true, actualInvoiceID: "2209", canCollect: true)
        XCTAssertNil(state.collectibleInvoiceID(in: context()))
        let next = try XCTUnwrap(pop(job + [.invoice(item)], job, context(), &state))
        state.finish(requestID: next, context: context(), fresh: true, actualInvoiceID: "2209", canCollect: true)
        XCTAssertNil(state.collectibleInvoiceID(in: context(job: "different-job")))
        XCTAssertNil(state.collectibleInvoiceID(in: context()))
    }
    func testLateOldCompletionDoesNotReplaceNewInvoice() throws {
        let job: [Route] = [.job("job")], first = route("2209"), second = route("2240")
        var state = JobInvoiceReturnCoordinator()
        let old = try XCTUnwrap(pop(job + [.invoice(first)], job, context(), &state))
        let current = try XCTUnwrap(pop(job + [.invoice(second)], job, context(), &state))
        state.finish(requestID: old, context: context(actor: "other"), fresh: true, actualInvoiceID: "2209", canCollect: true)
        state.finish(requestID: current, context: context(), fresh: true, actualInvoiceID: "2240", canCollect: true)
        XCTAssertEqual(state.collectibleInvoiceID(in: context()), "2240")
    }

    func testSameJobDifferentPresentationCannotConsumeInvoiceReturn() throws {
        let job: [Route] = [.job("job")], item = route("2209")
        var owner = JobInvoiceReturnCoordinator()
        var other = JobInvoiceReturnCoordinator()
        XCTAssertNil(pop(job + [.invoice(item)], job, context(presentationID: UUID()), &other))
        let token = try XCTUnwrap(pop(job + [.invoice(item)], job, context(), &owner))
        owner.finish(requestID: token, context: context(), fresh: true, actualInvoiceID: "2209", canCollect: true)
        XCTAssertEqual(owner.collectibleInvoiceID(in: context()), "2209")
        XCTAssertNil(other.collectibleInvoiceID(in: context()))
    }

    func testReturnedInvoiceCannotFallBackToAnotherOwedInvoice() {
        XCTAssertTrue(JobInvoiceReturnIdentity.permits(returnedID: "2209", selectedID: "2209", modelID: "2209", verifiedID: "2209", recordsMatch: true))
        XCTAssertFalse(JobInvoiceReturnIdentity.permits(returnedID: "2209", selectedID: "2240", modelID: "2240", verifiedID: "2209", recordsMatch: true))
        XCTAssertFalse(JobInvoiceReturnIdentity.permits(returnedID: "2209", selectedID: "2209", modelID: "2240", verifiedID: "2209", recordsMatch: true))
        XCTAssertFalse(JobInvoiceReturnIdentity.permits(returnedID: "2209", selectedID: "2209", modelID: "2209", verifiedID: nil, recordsMatch: true))
        XCTAssertFalse(JobInvoiceReturnIdentity.permits(returnedID: "2209", selectedID: "2209", modelID: "2209", verifiedID: "2209", recordsMatch: false))
    }

}

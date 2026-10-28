import XCTest
@testable import Thorbis

final class TechnicianFlowTests: XCTestCase {
    private func line(_ cents: Int, _ quantity: Int = 1) -> FieldLine {
        FieldLine(id: UUID().uuidString, description: "Line", quantity: quantity, unitPrice: FieldMoney(amount: cents, currency: "USD"), source: nil)
    }

    private func estimate(_ id: String, _ status: String, options: [FieldEstimateOption]? = nil) -> EstimateRecord {
        EstimateRecord(id: id, organizationId: "o", customerId: "c", createdByUserId: "u", locationId: nil, status: status,
                       currentRevisionNumber: 1, title: "AC repair", lines: [line(48_000)], options: options,
                       createdAt: "2026-10-28T00:00:00Z", updatedAt: "2026-10-28T00:00:00Z",
                       sentAt: nil, approvedAt: nil, declinedAt: nil)
    }

    private func invoice(_ id: String, _ status: String, total: Int = 48_000, paid: Int = 0) -> InvoiceRecord {
        InvoiceRecord(id: id, organizationId: "o", customerId: "c", jobId: "j", createdByUserId: "u", locationId: nil, scheduleId: nil,
                      origin: "job_completion", sourceOperationKey: "k", sourceEstimateId: nil, sourceEstimateRevisionNumber: nil,
                      manualPhysicalServiceEvidence: nil, status: status, lines: [line(total)], linesRevision: 1, amountPaid: paid,
                      currency: "USD", issuedAt: nil, paidAt: nil, voidedAt: nil,
                      createdAt: "2026-10-28T00:00:00Z", updatedAt: "2026-10-28T00:00:00Z")
    }

    private func next(_ status: String, _ transitions: [String] = [], estimates: [EstimateRecord]? = [],
                      invoices: [InvoiceRecord]? = [], can: TechJobAbilities = .all) -> TechJobStep? {
        TechJobFlow.nextStep(status: status, transitions: transitions, estimates: estimates, invoices: invoices, can: can)
    }

    func testTheVisitWalksForwardAndNeverOffersPauseAsTheNextStep() {
        XCTAssertEqual(next("scheduled", ["dispatched", "en_route"]), .transition("en_route"))
        XCTAssertEqual(next("en_route", ["arrived", "paused"]), .transition("arrived"))
        XCTAssertEqual(next("arrived", ["paused", "in_progress"]), .transition("in_progress"))
        XCTAssertEqual(next("paused", ["in_progress"]), .transition("in_progress"))
        XCTAssertEqual(next("paused", ["in_progress"])?.title(resuming: true), "Resume work")
        XCTAssertEqual(next("scheduled", ["dispatched"]), .transition("dispatched"))
        XCTAssertNil(next("arrived", ["paused"]))
    }

    func testWorkingOnAJobWithNoPaperStartsTheEstimate() {
        XCTAssertEqual(next("in_progress", ["paused", "completed"]), .buildEstimate)
        XCTAssertEqual(next("in_progress")?.title(), "Build estimate")
    }

    func testWaitsForTheJobsPaperBeforeOfferingAMoneyStep() {
        XCTAssertNil(next("in_progress", estimates: nil))
        XCTAssertNil(next("in_progress", invoices: nil))
    }

    func testAPendingEstimateIsShownToTheCustomerSentBeforeDraft() {
        XCTAssertEqual(next("in_progress", estimates: [estimate("d", "draft")]), .showEstimate(id: "d"))
        XCTAssertEqual(next("in_progress", estimates: [estimate("d", "draft"), estimate("s", "sent")]), .showEstimate(id: "s"))
    }

    func testAnEstimateWithOptionsNeedsSendToBeHandedOver() {
        let options = [FieldEstimateOption(id: "good", title: "Good", description: "", lines: [], totalAmount: 1, currency: "USD")]
        var can = TechJobAbilities.all
        can.sendEstimate = false
        XCTAssertFalse(TechJobFlow.canShow(estimate("s", "sent", options: options), can: can))
        XCTAssertTrue(TechJobFlow.canShow(estimate("s", "sent"), can: can))
        XCTAssertFalse(TechJobFlow.canShow(estimate("d", "draft"), can: can))
        // Unable to hand it over, the tech can still bill the visit.
        XCTAssertEqual(next("in_progress", estimates: [estimate("d", "draft")], can: can), .createInvoice)
    }

    func testApprovedWorkBecomesTheInvoice() {
        XCTAssertEqual(next("in_progress", estimates: [estimate("a", "approved"), estimate("d", "declined")]), .createInvoice)
    }

    func testADeclinedEstimateStillBillsTheTrip() {
        XCTAssertEqual(next("in_progress", estimates: [estimate("d", "declined")]), .createInvoice)
    }

    func testADraftInvoiceIsReviewedThenTheBalanceCollected() {
        XCTAssertEqual(next("in_progress", estimates: [estimate("a", "approved")], invoices: [invoice("i", "draft")]), .reviewInvoice(id: "i"))
        let step = next("in_progress", invoices: [invoice("i", "issued", total: 48_000, paid: 8_000)])
        XCTAssertEqual(step, .collect(invoiceID: "i", due: 40_000, currency: "USD"))
        XCTAssertEqual(step?.title(), "Collect \(money(40_000, currency: "USD"))")
    }

    func testPaidOrVoidedPaperEndsAtWrapUp() {
        XCTAssertEqual(next("in_progress", invoices: [invoice("i", "paid", paid: 48_000)]), .wrapUp)
        XCTAssertEqual(next("in_progress", invoices: [invoice("i", "issued", paid: 48_000)]), .wrapUp)
        XCTAssertEqual(next("in_progress", invoices: [invoice("v", "void")]), .buildEstimate, "a voided invoice is not billing")
    }

    func testAnOwedInvoiceThisRoleCannotCollectGoesToWrapUp() {
        var can = TechJobAbilities.all
        can.collectPayment = false
        XCTAssertEqual(next("in_progress", invoices: [invoice("i", "issued")], can: can), .wrapUp)
    }

    func testACompletedJobOnlyAsksForWhatIsStillOwed() {
        XCTAssertEqual(next("completed", invoices: [invoice("i", "issued")]), .collect(invoiceID: "i", due: 48_000, currency: "USD"))
        XCTAssertNil(next("completed", invoices: [invoice("i", "paid", paid: 48_000)]))
        XCTAssertNil(next("completed"))
        XCTAssertNil(next("canceled", ["scheduled"]))
    }

    func testARoleWithoutEstimatesOrInvoicesStillReachesWrapUp() {
        let can = TechJobAbilities(completeJob: true)
        XCTAssertEqual(next("in_progress", can: can), .wrapUp)
        XCTAssertNil(next("in_progress", can: TechJobAbilities()))
    }
}

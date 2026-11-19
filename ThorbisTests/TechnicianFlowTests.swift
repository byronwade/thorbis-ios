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

    private func invoice(_ id: String, _ status: String, total: Int = 48_000, paid: Int = 0, origin: String = "job_completion") -> InvoiceRecord {
        InvoiceRecord(id: id, organizationId: "o", customerId: "c", jobId: "j", createdByUserId: "u", locationId: nil, scheduleId: nil,
                      origin: origin, sourceOperationKey: "k", sourceEstimateId: nil, sourceEstimateRevisionNumber: nil,
                      manualPhysicalServiceEvidence: nil, status: status, lines: [line(total)], linesRevision: 1, amountPaid: paid,
                      currency: "USD", issuedAt: nil, paidAt: nil, voidedAt: nil,
                      createdAt: "2026-10-28T00:00:00Z", updatedAt: "2026-10-28T00:00:00Z")
    }

    // A saved estimate or invoice is shown before the live read only when it is this document,
    // in this company and (opened from a job) on that job.
    func testSavedPreviewNeedsSameDocumentAndCompany() {
        let saved = estimate("e1", "sent")
        XCTAssertEqual(SavedDocumentPreview.estimate(saved, id: "e1", organization: "o")?.id, "e1")
        XCTAssertNil(SavedDocumentPreview.estimate(saved, id: "e2", organization: "o"))
        XCTAssertNil(SavedDocumentPreview.estimate(saved, id: "e1", organization: "other"))
        XCTAssertNil(SavedDocumentPreview.estimate(saved, id: "e1", organization: nil))
        XCTAssertNil(SavedDocumentPreview.estimate(nil, id: "e1", organization: "o"))

        let bill = invoice("i1", "issued")
        XCTAssertEqual(SavedDocumentPreview.invoice(bill, id: "i1", organization: "o")?.id, "i1")
        XCTAssertNil(SavedDocumentPreview.invoice(bill, id: "i2", organization: "o"))
        XCTAssertNil(SavedDocumentPreview.invoice(bill, id: "i1", organization: "other"))
        XCTAssertNil(SavedDocumentPreview.invoice(bill, id: "i1", organization: nil))
    }

    func testSavedInvoicePreviewStaysInsideItsJob() {
        let bill = invoice("i1", "issued")
        let same = JobDocumentScope(jobID: "j", organizationID: "o", customerID: "c")
        let otherJob = JobDocumentScope(jobID: "j2", organizationID: "o", customerID: "c")
        let otherCustomer = JobDocumentScope(jobID: "j", organizationID: "o", customerID: "c2")
        XCTAssertNotNil(SavedDocumentPreview.invoice(bill, id: "i1", organization: "o", scope: same))
        XCTAssertNil(SavedDocumentPreview.invoice(bill, id: "i1", organization: "o", scope: otherJob))
        XCTAssertNil(SavedDocumentPreview.invoice(bill, id: "i1", organization: "o", scope: otherCustomer))
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
        XCTAssertEqual(next("in_progress", estimates: [estimate("d", "draft"), estimate("s", "sent")]), .presentEstimates)
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

    func testApprovedAndSentStillOffersRemainingCustomerPresentation() {
        XCTAssertEqual(next("in_progress", estimates: [estimate("approved", "approved"), estimate("sent", "sent")]), .presentEstimates)
    }
    func testIneligibleFirstSentDoesNotHideAnotherEligibleEstimate() {
        let option = FieldEstimateOption(id: "option", title: "Package", description: "", lines: [], totalAmount: 100, currency: "USD")
        var can = TechJobAbilities.all; can.sendEstimate = false
        XCTAssertEqual(next("in_progress", estimates: [estimate("options", "sent", options: [option]), estimate("plain", "sent")], can: can), .presentEstimates)
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

    func testAPaidDepositStillLeavesTheJobToInvoice() {
        let deposit = invoice("dep", "paid", total: 10_000, paid: 10_000, origin: "deposit")
        XCTAssertEqual(next("in_progress", estimates: [estimate("a", "approved")], invoices: [deposit]), .createInvoice)
        let owedDeposit = invoice("dep", "issued", total: 10_000, origin: "deposit")
        XCTAssertEqual(next("in_progress", estimates: [estimate("a", "approved")], invoices: [owedDeposit]),
                       .collect(invoiceID: "dep", due: 10_000, currency: "USD"))
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

/// A quantity far past any real job must read as "not yet", never trap the app.
@MainActor
final class LargeQuantityTests: XCTestCase {
    func testMemberTotalIsNilInsteadOfOverflowing() {
        let pricing = MemberPricing(isMember: true, discountPercent: 15, membership: nil)
        let huge = [EstimateRevisionLineDraft(description: "Coil", quantity: "999999999999", unitPrice: "1000000.00")]
        XCTAssertNil(huge.memberTotal(pricing))
        let real = [EstimateRevisionLineDraft(description: "Coil", quantity: "2", unitPrice: "100.00")]
        XCTAssertEqual(real.memberTotal(pricing), 17_000)
    }
}

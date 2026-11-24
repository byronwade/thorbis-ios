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

    /// The real API lists every allowed move, including the step back: an arrived job answers
    /// `["en_route", "in_progress", "completed", "canceled"]` (seen against a local server).
    func testTheNextStepNeverGoesBackWhenTheServerAlsoAllowsIt() {
        XCTAssertEqual(next("scheduled", ["dispatched", "en_route", "arrived", "in_progress", "completed", "canceled"]),
                       .transition("en_route"))
        XCTAssertEqual(next("en_route", ["dispatched", "arrived", "in_progress", "completed", "canceled"]), .transition("arrived"))
        XCTAssertEqual(next("arrived", ["en_route", "in_progress", "completed", "canceled"]), .transition("in_progress"))
        XCTAssertEqual(next("arrived", ["en_route", "in_progress", "completed", "canceled"])?.title(), "Start work")
        XCTAssertEqual(next("paused", ["en_route", "arrived", "in_progress"]), .transition("in_progress"))
        XCTAssertNil(next("arrived", ["en_route", "completed", "canceled"]))
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

    func testAPaidDepositAloneIsNotThePaidStage() {
        let deposit = invoice("dep", "paid", total: 10_000, paid: 10_000, origin: "deposit")
        XCTAssertFalse(TechJobFlow.paidStage(status: "in_progress", completedAt: nil, invoices: [deposit]),
                       "money taken ahead of the work is not the job's bill")
        let bill = invoice("i", "paid", total: 48_000, paid: 48_000)
        XCTAssertTrue(TechJobFlow.paidStage(status: "in_progress", completedAt: nil, invoices: [deposit, bill]))
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
        let huge = [priceBookLine(quantity: "999999999999", price: "1000000.00")]
        XCTAssertNil(huge.memberTotal(pricing))
        let real = [priceBookLine(quantity: "2", price: "100.00")]
        XCTAssertEqual(real.memberTotal(pricing), 17_000)
    }

    /// A price book line still at its list price, the only kind the server member prices.
    private func priceBookLine(quantity: String, price: String) -> EstimateRevisionLineDraft {
        EstimateRevisionLineDraft(description: "Coil", quantity: quantity, unitPrice: price,
                                  source: .priceBookSelection(itemID: "coil", revision: 1),
                                  priceBookOriginal: PriceBookLineOriginal(description: "Coil", unitPrice: price))
    }
}

/// A saved member-priced estimate must not show a second, lower "Member price" under its total.
@MainActor
final class MemberPriceHintTests: XCTestCase {
    private let pricing = MemberPricing(isMember: true, discountPercent: 10, membership: nil)

    /// A saved price book line. `list` is the price book price it came from; it defaults to the
    /// saved price, which is a line still at its list price.
    private func line(_ cents: Int, quantity: Int = 1, list: Int? = nil, overridden: [String]? = nil) -> FieldLine {
        FieldLine(id: UUID().uuidString, description: "Coil", quantity: quantity,
                  unitPrice: FieldMoney(amount: cents, currency: "USD"),
                  source: FieldLineSource(kind: "price_book", priceBookItemId: "coil", priceBookRevision: 1,
                                          originalDescription: "Coil",
                                          originalUnitPrice: FieldMoney(amount: list ?? cents, currency: "USD"),
                                          overriddenFields: overridden))
    }

    private func typedLine(_ cents: Int, quantity: Int = 1) -> FieldLine {
        FieldLine(id: UUID().uuidString, description: "Labor", quantity: quantity,
                  unitPrice: FieldMoney(amount: cents, currency: "USD"), source: FieldLineSource(kind: "manual"))
    }

    private let coil = PriceBookListItem(id: "11111111-1111-4111-8111-111111111111", description: "Coil",
                                         unit: "each", kind: "material", taxClassification: "taxable",
                                         sellPrice: .init(amount: 10_000, currency: "USD"), revision: 3, archivedAt: nil)

    func testListPricedLinesGetTheMemberHint() {
        XCTAssertEqual(pricing.memberTotal(of: [line(10_000, quantity: 2)]), 18_000)
    }

    func testLinesTheServerAlreadyMemberPricedAreNotDiscountedAgain() {
        XCTAssertNil(pricing.memberTotal(of: [line(17_739, list: 19_710, overridden: ["unit_price"])]),
                     "The total already is the member price: no hint")
        XCTAssertEqual(pricing.memberTotal(of: [line(9_000, list: 10_000, overridden: ["unit_price"]), line(10_000)]), 18_000,
                       "Only the list-priced line is discounted")
    }

    func testNoHintForSomeoneWhoIsNotAMember() {
        XCTAssertNil(MemberPricing(isMember: false, discountPercent: 10, membership: nil).memberTotal(of: [line(10_000)]))
    }

    func testEditorDoesNotDiscountAMemberPricedDraftAgain() {
        // As the editor loads a line the server saved at the member price: below its list price.
        let saved = EstimateRevisionLineDraft(description: "Coil", quantity: "1", unitPrice: "90.00",
                                              source: .priceBookSelection(itemID: "coil", revision: 1),
                                              priceBookOriginal: PriceBookLineOriginal(description: "Coil", unitPrice: "100.00"))
        XCTAssertNil([saved].memberTotal(pricing))
        var lines = [saved]
        lines.addPriceBookItem(coil)
        XCTAssertEqual(lines.memberTotal(pricing), 18_000)
    }

    // The server charges a typed line as typed, so no member price is shown for it.
    func testATypedLineGetsNoMemberPrice() throws {
        XCTAssertNil(pricing.memberTotal(of: [typedLine(10_000)]))
        var lines: [EstimateRevisionLineDraft] = []
        let id = lines.addCustomLine("Labor", to: .work)
        let index = try XCTUnwrap(lines.firstIndex { $0.id == id })
        lines[index].unitPrice = "100.00"
        XCTAssertNil(lines.memberTotal(pricing))
    }

    // The server charges an edited price as edited; putting the list price back qualifies again.
    func testAnEditedPriceGetsNoMemberPrice() {
        XCTAssertNil(pricing.memberTotal(of: [line(8_000, list: 10_000, overridden: ["unit_price"])]))
        XCTAssertNil(pricing.memberTotal(of: [line(12_000, list: 10_000)]),
                     "A price that differs from the list price never qualifies, marked or not")
        var lines: [EstimateRevisionLineDraft] = []
        lines.addPriceBookItem(coil)
        lines[0].unitPrice = "80.00"
        XCTAssertNil(lines.memberTotal(pricing))
        lines[0].unitPrice = "100.00"
        XCTAssertEqual(lines.memberTotal(pricing), 9_000)
    }

    // Only the price book line at its list price is discounted; the rest count at their price.
    func testAMixedEstimateDiscountsOnlyTheListPricedLine() throws {
        let saved = [typedLine(5_000), line(8_000, list: 10_000, overridden: ["unit_price"]), line(10_000, quantity: 2)]
        XCTAssertEqual(pricing.memberTotal(of: saved), 5_000 + 8_000 + 18_000)
        var lines: [EstimateRevisionLineDraft] = []
        lines.addPriceBookItem(coil)
        lines.addPriceBookItem(coil)
        let id = lines.addCustomLine("Labor", to: .work)
        let index = try XCTUnwrap(lines.firstIndex { $0.id == id })
        lines[index].unitPrice = "50.00"
        lines.addCreditLine("Courtesy", cents: 1_000)
        XCTAssertEqual(lines.memberTotal(pricing), 18_000 + 5_000 - 1_000)
    }

    // A price book line left at its list price is charged the member price, saved or not.
    func testAnUnchangedPriceBookLineGetsTheMemberPrice() {
        XCTAssertEqual(pricing.memberTotal(of: [line(10_000)]), 9_000)
        var lines: [EstimateRevisionLineDraft] = []
        lines.addPriceBookItem(coil)
        XCTAssertEqual(lines.memberTotal(pricing), 9_000)
        XCTAssertEqual(pricing.secondaryPriceText(coil), "Member \(money(9_000, currency: "USD"))")
    }
}

import XCTest

@MainActor
final class JobDocumentsUITests: XCTestCase {
    private let invoiceA = "00000000-0000-4000-8000-000000002209"
    private let depositA = "00000000-0000-4000-8000-000000002240"
    private let invoiceB = "00000000-0000-4000-8000-000000002241"
    private let estimateA = "00000000-0000-4000-8000-000000002218"
    private let addonA = "00000000-0000-4000-8000-000000002238"

    func testOverviewInvoiceOpensTheExactDocumentInOneTap() {
        continueAfterFailure = false
        let app = preview(extra: ["--paper-preview-job-invoices-equal-balances"])
        let row = app.buttons["job-overview-invoice-\(invoiceA)"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        app.scrollClearOfFoot(row)
        XCTAssertTrue(row.isHittable)
        row.tap()
        let title = app.staticTexts["invoice-detail-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertTrue(title.label.contains("2209"), title.label)
        app.navigationBars.buttons["Back"].firstMatch.tap()
        thorbisStableButton(app, "job-section-money").tap()
        let selected = app.staticTexts["job-collect-selected-invoice"]
        XCTAssertTrue(selected.waitForExistence(timeout: 10))
        XCTAssertTrue(selected.label.contains("2209"), selected.label)
    }

    func testOverviewEstimateOpensTheExactDocumentInOneTap() {
        continueAfterFailure = false
        let app = preview()
        let row = app.buttons["job-overview-estimate-\(estimateA)"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        app.scrollClearOfFoot(row)
        XCTAssertTrue(row.isHittable)
        row.tap()
        XCTAssertTrue(app.staticTexts["Estimate 2218"].waitForExistence(timeout: 10))
    }

    func testOverviewInvoiceRetiresWhenSessionIsReplaced() {
        continueAfterFailure = false
        let app = preview(extra: ["--paper-preview-overview-retire", "--paper-preview-description-replace-session"])
        let row = app.buttons["job-overview-invoice-\(invoiceA)"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        app.scrollClearOfFoot(row)
        row.tap()
        XCTAssertTrue(app.staticTexts["invoice-detail-title"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Document unavailable"].waitForExistence(timeout: 25))
        XCTAssertFalse(app.staticTexts["invoice-detail-title"].exists)
    }

    func testOverviewInvoiceRetiresWhenAuthorityIsRevalidated() {
        continueAfterFailure = false
        let app = preview(extra: ["--paper-preview-overview-revalidate"])
        let row = app.buttons["job-overview-invoice-\(invoiceA)"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        app.scrollClearOfFoot(row)
        row.tap()
        XCTAssertTrue(app.staticTexts["invoice-detail-title"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Document unavailable"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts["invoice-detail-title"].exists)
    }

    func testOverviewInvoiceCannotOpenFromOldReadDuringAuthorityReload() {
        continueAfterFailure = false
        let app = preview(extra: ["--paper-preview-overview-hold-reload"])
        let row = app.buttons["job-overview-invoice-\(invoiceA)"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: row)
        waitForExpectations(timeout: 10)
        let refresh = app.buttons["job-overview-revalidate"]
        app.scrollClearOfFoot(refresh)
        XCTAssertTrue(refresh.isHittable)
        refresh.tap()
        expectation(for: NSPredicate(format: "enabled == false"), evaluatedWith: row)
        waitForExpectations(timeout: 10)
        XCTAssertFalse(app.staticTexts["invoice-detail-title"].exists)
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: row)
        waitForExpectations(timeout: 20)
    }

    func testCreatingFirstInvoiceOpensTheReturnedDraftOnlyOnce() {
        continueAfterFailure = false
        let app = preview(extra: ["--paper-preview-create-invoice"])
        thorbisStableButton(app, "job-section-money").tap()
        let create = app.buttons["job-create-invoice"]
        XCTAssertTrue(create.waitForExistence(timeout: 15))
        app.scrollClearOfFoot(create)
        create.doubleTap()
        let title = app.staticTexts["invoice-detail-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        XCTAssertTrue(title.label.contains("2209"), title.label)
        XCTAssertTrue(app.staticTexts["INV-2209"].exists)
        app.navigationBars.buttons["Back"].firstMatch.tap()
        let count = app.staticTexts["preview-create-invoice-count"]
        XCTAssertTrue(count.waitForExistence(timeout: 10))
        XCTAssertEqual(count.label, "Create requests: 1")
    }

    func testCreatingInvoiceDoesNotOpenAfterRequestAuthorityChangesDuringRefresh() {
        continueAfterFailure = false
        let app = preview(extra: ["--paper-preview-create-invoice", "--paper-preview-create-invalidate-refresh"])
        thorbisStableButton(app, "job-section-money").tap()
        let create = app.buttons["job-create-invoice"]
        XCTAssertTrue(create.waitForExistence(timeout: 15))
        app.scrollClearOfFoot(create)
        create.tap()
        let count = app.staticTexts["preview-create-invoice-count"]
        expectation(for: NSPredicate(format: "label == %@", "Create requests: 1"), evaluatedWith: count)
        waitForExpectations(timeout: 15)
        let state = app.staticTexts["preview-create-invoice-state"]
        expectation(for: NSPredicate(format: "label == %@", "Finished"), evaluatedWith: state)
        waitForExpectations(timeout: 15)
        XCTAssertFalse(app.staticTexts["invoice-detail-title"].exists, "A retired request must not navigate")
        XCTAssertTrue(app.staticTexts["Invoice may have been created. Refresh this job to check."].waitForExistence(timeout: 10))
    }

    func testInterruptedCreateShowsSafeRecoveryWithoutOpeningInvoice() {
        continueAfterFailure = false
        let app = preview(extra: ["--paper-preview-create-invoice", "--paper-preview-create-invalidate-post"])
        thorbisStableButton(app, "job-section-money").tap()
        let create = app.buttons["job-create-invoice"]
        XCTAssertTrue(create.waitForExistence(timeout: 15))
        app.scrollClearOfFoot(create)
        create.tap()
        XCTAssertTrue(app.staticTexts["Invoice may have been created. Refresh this job to check."].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["invoice-detail-title"].exists)
    }

    func testCreatingInvoiceDoesNotOpenWhenInvoiceViewIsRevoked() {
        continueAfterFailure = false
        let app = preview(extra: ["--paper-preview-create-invoice", "--paper-preview-create-revoke-view"])
        thorbisStableButton(app, "job-section-money").tap()
        let create = app.buttons["job-create-invoice"]
        XCTAssertTrue(create.waitForExistence(timeout: 15))
        app.scrollClearOfFoot(create)
        create.tap()
        XCTAssertTrue(app.staticTexts["Invoice access is unavailable."].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["invoice-detail-title"].exists)
    }

    func testCreatingInvoiceNeverOpensForeignOrFailedResponse() {
        for flag in ["--paper-preview-create-invoice-foreign", "--paper-preview-create-invoice-failure"] {
            let app = preview(extra: ["--paper-preview-create-invoice", flag])
            thorbisStableButton(app, "job-section-money").tap()
            let create = app.buttons["job-create-invoice"]
            XCTAssertTrue(create.waitForExistence(timeout: 15))
            app.scrollClearOfFoot(create)
            create.tap()
            let count = app.staticTexts["preview-create-invoice-count"]
            let once = NSPredicate(format: "label == %@", "Create requests: 1")
            expectation(for: once, evaluatedWith: count)
            waitForExpectations(timeout: 10)
            let message = flag.contains("foreign") ? "Invoice could not be verified for this job" : "Sample invoice could not be created"
            XCTAssertTrue(app.staticTexts[message].waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["invoice-detail-title"].exists)
            XCTAssertTrue(create.exists)
            app.terminate()
        }
    }

    func testMoneySectionJumpsReachInvoicesAndEstimates() {
        continueAfterFailure = false
        let app = preview()
        thorbisStableButton(app, "job-section-money").tap()
        let invoices = app.buttons["job-money-jump-invoices"]
        XCTAssertTrue(invoices.waitForExistence(timeout: 15))
        XCTAssertEqual(invoices.label, "Invoices")
        invoices.tap()
        let invoice = app.buttons["job-invoice-\(invoiceA)"]
        XCTAssertTrue(invoice.waitForExistence(timeout: 10))
        XCTAssertTrue(invoice.isHittable)
        app.swipeDown()
        let estimates = app.buttons["job-money-jump-estimates"]
        for _ in 0..<6 where !estimates.isHittable { app.swipeDown() }
        XCTAssertTrue(estimates.isHittable)
        estimates.tap()
        let estimate = app.buttons["job-estimate-\(estimateA)"]
        XCTAssertTrue(estimate.waitForExistence(timeout: 5))
        XCTAssertTrue(estimate.isHittable)
    }

    func testMoneyJumpKeepsTheChosenInvoiceForCollection() {
        continueAfterFailure = false
        let app = preview(extra: ["--paper-preview-job-invoices-equal-balances"])
        thorbisStableButton(app, "job-section-money").tap()
        let jump = app.buttons["job-money-jump-invoices"]
        XCTAssertTrue(jump.waitForExistence(timeout: 15))
        jump.tap()
        let invoice = app.buttons["job-invoice-\(invoiceA)"]
        XCTAssertTrue(invoice.waitForExistence(timeout: 10))
        app.scrollClearOfFoot(invoice)
        invoice.tap()
        XCTAssertTrue(app.staticTexts["INV-2209"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Back"].firstMatch.tap()
        let estimates = app.buttons["job-money-jump-estimates"]
        for _ in 0..<8 where !estimates.isHittable { app.swipeDown() }
        XCTAssertTrue(estimates.isHittable)
        estimates.tap()
        let collect = app.buttons["Collect payment"]
        XCTAssertTrue(collect.waitForExistence(timeout: 10))
        collect.tap()
        let collecting = app.descendants(matching: .any)["collect-payment-invoice"]
        XCTAssertTrue(collecting.waitForExistence(timeout: 5))
        XCTAssertTrue(collecting.label.contains("INV-2209"), collecting.label)
    }

    func testDirectCollectionOpensTheTappedJobInvoice() {
        continueAfterFailure = false
        let app = preview(extra: ["--paper-preview-job-invoices-equal-balances", "--paper-preview-job-invoice-reference-collision"])
        let collisionID = "00000000-0000-4000-8000-000000012209"
        thorbisStableButton(app, "job-section-money").tap()
        let jump = app.buttons["job-money-jump-invoices"]
        XCTAssertTrue(jump.waitForExistence(timeout: 15))
        jump.tap()
        let first = app.buttons["job-invoice-collect-\(invoiceA)"]
        let second = app.buttons["job-invoice-collect-\(collisionID)"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertTrue(second.exists)
        XCTAssertEqual(first.label, "Collect payment for invoice INV-02209")
        XCTAssertEqual(second.label, "Collect payment for invoice INV-12209")
        XCTAssertTrue(app.buttons["job-invoice-\(invoiceA)"].label.contains("INV-02209"))
        XCTAssertTrue(app.buttons["job-invoice-\(collisionID)"].label.contains("INV-12209"))
        let selected = app.staticTexts["job-collect-selected-invoice"]
        XCTAssertTrue(selected.waitForExistence(timeout: 10))
        XCTAssertEqual(selected.label, "For INV-12209")
        app.scrollClearOfFoot(first)
        XCTAssertTrue(first.isHittable)
        capture(app, "Job invoices with direct payment")
        first.tap()
        let identity = app.descendants(matching: .any)["collect-payment-invoice"]
        XCTAssertTrue(identity.waitForExistence(timeout: 10))
        XCTAssertTrue(identity.label.contains("INV-02209"), identity.label)
        app.buttons["Close"].tap()
        XCTAssertTrue(second.waitForExistence(timeout: 10))
        XCTAssertEqual(selected.label, "For INV-02209")
        app.scrollClearOfFoot(second)
        XCTAssertTrue(second.isHittable)
        second.tap()
        XCTAssertTrue(identity.waitForExistence(timeout: 10))
        XCTAssertTrue(identity.label.contains("INV-12209"), identity.label)
        capture(app, "Collecting the second job invoice")
        app.buttons["Close"].tap()
        let detail = app.buttons["job-invoice-\(collisionID)"]
        XCTAssertTrue(detail.waitForExistence(timeout: 10))
        app.scrollClearOfFoot(detail)
        detail.tap()
        let title = app.staticTexts["invoice-detail-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertTrue(title.label.contains("12209"), title.label)
        XCTAssertTrue(app.staticTexts["INV-12209"].exists)
        let detailCollect = app.buttons["Collect payment"]
        XCTAssertTrue(detailCollect.waitForExistence(timeout: 10))
        detailCollect.tap()
        XCTAssertTrue(identity.waitForExistence(timeout: 10))
        XCTAssertTrue(identity.label.contains("INV-12209"), identity.label)
        app.buttons["Close"].tap()
    }

    func testMoneyJumpsRemainReachableAtLargestText() {
        let app = preview(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let chooser = app.buttons["job-section-chooser"]
        XCTAssertTrue(chooser.waitForExistence(timeout: 15))
        chooser.tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND identifier != %@", "Money", "job-section-chooser")).firstMatch.tap()
        let jump = app.buttons["job-money-jump-invoices"]
        for _ in 0..<8 where !jump.isHittable { app.swipeUp() }
        XCTAssertTrue(jump.isHittable)
        XCTAssertGreaterThanOrEqual(jump.frame.height, 44)
        jump.tap()
        let invoice = app.buttons["job-invoice-\(depositA)"]
        XCTAssertTrue(invoice.waitForExistence(timeout: 10))
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Money jump largest text hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        capture(app, "Money jump largest text")
        XCTAssertTrue(invoice.isHittable)
    }

    func testTechnicianEstimateCardsKeepBothDocumentsOpenable() {
        continueAfterFailure = false
        let app = preview()
        let money = thorbisStableButton(app, "job-section-money")
        money.tap()
        let first = app.buttons["job-estimate-\(estimateA)"]
        let second = app.buttons["job-estimate-\(addonA)"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertTrue(second.exists)
        XCTAssertTrue(first.label.contains("Awaiting approval"), "Sent work needs a clear next step")
        XCTAssertTrue(second.label.contains("Not sent yet"), "Drafts must not look sent")
        XCTAssertTrue(first.label.contains("EST-2218"))
        XCTAssertTrue(second.label.contains("EST-2238"))
        XCTAssertFalse(app.buttons["job-estimate-00000000-0000-4000-8000-000000002239"].exists, "Other jobs' estimates must not appear")
        // The $340 owed takes Money's bar; the estimates' Customer view stays beneath them, quieter.
        let collect = app.buttons["Collect payment"]
        XCTAssertTrue(collect.waitForExistence(timeout: 10))
        let present = app.buttons["job-money-customer-view"]
        XCTAssertTrue(present.waitForExistence(timeout: 5))
        XCTAssertEqual(present.label, "Show customer")
        XCTAssertTrue(present.isHittable)
        XCTAssertLessThanOrEqual(second.frame.maxY, present.frame.minY, "Both estimates should be visible above the presentation action")
        XCTAssertLessThanOrEqual(present.frame.maxY, collect.frame.minY, "The estimates' door must not sit under the bar")
        for _ in 0..<5 where !first.isHittable { app.swipeUp() }
        XCTAssertTrue(first.isHittable)
        capture(app, "Job estimate cards")
        first.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "EST-2218")).firstMatch.waitForExistence(timeout: 10))
    }

    func testEstimateCardsKeepApprovedDeclinedAndUnknownAmountHonest() {
        continueAfterFailure = false
        let app = preview(extra: ["--paper-preview-job-estimate-review-states"])
        thorbisStableButton(app, "job-section-money").tap()
        let declined = app.buttons["job-estimate-\(estimateA)"]
        let approved = app.buttons["job-estimate-\(addonA)"]
        XCTAssertTrue(declined.waitForExistence(timeout: 10))
        XCTAssertTrue(approved.exists)
        XCTAssertTrue(declined.label.contains("Declined"))
        XCTAssertFalse(declined.label.contains("Awaiting approval"))
        XCTAssertTrue(approved.label.contains("Approved"))
        XCTAssertTrue(approved.label.contains("View estimate details"))
        XCTAssertFalse(approved.label.contains("$970.00"), "An unknown accepted scope has no invented total")
    }

    func testEstimateCardKeepsCompleteOptionsSeparateFromAnAmount() {
        continueAfterFailure = false
        let app = preview(extra: ["--paper-preview-job-estimate-multiple-options"])
        thorbisStableButton(app, "job-section-money").tap()
        let estimate = app.buttons["job-estimate-\(estimateA)"]
        XCTAssertTrue(estimate.waitForExistence(timeout: 10))
        XCTAssertTrue(estimate.label.contains("2 options"))
        XCTAssertTrue(estimate.label.contains("Awaiting approval"))
        XCTAssertFalse(estimate.label.contains("$970.00"), "Complete alternatives cannot be summed or represented as one amount")
    }

    func testLargestTextKeepsJobEstimateCardsAndCustomerActionReachable() {
        continueAfterFailure = false
        let app = preview(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-thorbis.appearance", "dark"])
        let chooser = app.buttons["job-section-chooser"]
        XCTAssertTrue(chooser.waitForExistence(timeout: 15))
        chooser.tap()
        let money = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND identifier != %@", "Money", "job-section-chooser")).firstMatch
        XCTAssertTrue(money.waitForExistence(timeout: 5))
        money.tap()
        let first = app.buttons["job-estimate-\(estimateA)"]
        let second = app.buttons["job-estimate-\(addonA)"]
        for _ in 0..<8 where !first.exists { app.swipeUp() }
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertTrue(first.label.contains("Awaiting approval"))
        for _ in 0..<8 where !second.exists { app.swipeUp() }
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        XCTAssertTrue(second.label.contains("Not sent yet"))
        revealJobItem(second, in: app)
        XCTAssertGreaterThanOrEqual(second.frame.height, 44)
        capture(app, "Large text job estimates")
        second.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "EST-2238")).firstMatch.waitForExistence(timeout: 10))
        app.navigationBars.buttons["Back"].firstMatch.tap()
        let present = app.buttons["job-money-customer-view"]
        revealJobItem(present, in: app)
        XCTAssertTrue(present.isHittable)
    }

    private func revealJobItem(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        let chooser = app.buttons["job-section-chooser"]
        let moneyTab = app.buttons["job-section-money"]
        let footer = app.buttons["Collect payment"]
        let list = app.scrollViews.firstMatch
        let topBoundary = chooser.exists ? chooser.frame.maxY : (moneyTab.exists ? moneyTab.frame.maxY : app.frame.minY)
        let bottomBoundary = !chooser.exists && footer.exists ? footer.frame.minY : app.frame.maxY
        for _ in 0..<10 {
            let frame = element.frame
            if element.isHittable && frame.minY >= topBoundary && frame.maxY <= bottomBoundary { break }
            let down = frame.minY < topBoundary
            let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.4 : 0.6))
            let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.6 : 0.4))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(element.isHittable)
        XCTAssertGreaterThanOrEqual(element.frame.minY, topBoundary)
        XCTAssertLessThanOrEqual(element.frame.maxY, bottomBoundary)
    }

    func testNarrowJobSectionsCanReachEverySectionWithoutScrollingTabs() {
        continueAfterFailure = false
        let app = preview()
        for section in ["Money", "Activity", "Overview"] {
            let destination = thorbisSection(app, section)
            XCTAssertTrue(destination.waitForExistence(timeout: 10), section)
            XCTAssertTrue(destination.isHittable, "\(section) must be reachable without scrolling the tab row")
            destination.tap()
        }
        capture(app, "Job sections reachable without scrolling")
    }

    func testEstimateTotalsShowSentAmountAndExplainUnknownApprovedAmount() {
        continueAfterFailure = false
        let app = preview(extra: ["--paper-preview-approved-unknown-total"])
        thorbisStableButton(app, "job-section-money").tap()
        let totals = app.buttons["Estimate totals"]
        app.swipeUp()
        XCTAssertTrue(totals.waitForExistence(timeout: 5))
        XCTAssertTrue(totals.isHittable)
        totals.tap()
        XCTAssertTrue(app.staticTexts["Approved total unavailable"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Awaiting approval · USD"].exists)
        XCTAssertTrue(app.staticTexts["$970.00"].exists)
    }

    func testAllJobInvoicesAreVisibleAndOpenTheirOwnDetail() {
        continueAfterFailure = false
        let app = preview()
        XCTAssertTrue(thorbisJobBalanceLoaded(app, "$340.00").waitForExistence(timeout: 15))
        XCTAssertTrue(thorbisSection(app, "Money").waitForExistence(timeout: 15))
        thorbisSection(app, "Money").tap()
        let issued = app.buttons["job-invoice-\(invoiceA)"]
        let deposit = app.buttons["job-invoice-\(depositA)"]
        XCTAssertTrue(issued.waitForExistence(timeout: 10))
        XCTAssertTrue(deposit.exists)
        XCTAssertFalse(app.buttons["job-invoice-\(invoiceB)"].exists)
        capture(app, "Every invoice for this job")
        deposit.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "INV-2240")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "INV-2241")).firstMatch.exists)
    }

    func testInvoiceItemsCanBeOpenedIndependentlyWithoutHidingInvoiceActions() {
        continueAfterFailure = false
        let app = preview()
        thorbisStableButton(app, "job-section-money").tap()
        let first = app.buttons["job-invoice-items-\(invoiceA)"]
        let second = app.buttons["job-invoice-items-\(depositA)"]
        let firstLine = app.descendants(matching: .any)["job-invoice-line-\(invoiceA)-00000000-0000-4000-8000-000000009101"]
        let secondLine = app.descendants(matching: .any)["job-invoice-line-\(depositA)-00000000-0000-4000-8000-000000009101"]
        revealJobItem(first, in: app)
        XCTAssertFalse(firstLine.exists, "Invoice items should start collapsed")
        XCTAssertFalse(secondLine.exists)
        first.tap()
        XCTAssertTrue(firstLine.waitForExistence(timeout: 5))
        XCTAssertTrue(firstLine.label.contains("Compressor diagnostic"))
        XCTAssertTrue(firstLine.label.contains("quantity 1"))
        XCTAssertTrue(firstLine.label.contains("$120.00"))
        XCTAssertFalse(secondLine.exists, "Opening one invoice must not expand another")
        revealJobItem(second, in: app)
        second.tap()
        XCTAssertTrue(secondLine.waitForExistence(timeout: 5))
        revealJobItem(first, in: app)
        first.tap()
        XCTAssertFalse(firstLine.exists)
        XCTAssertTrue(secondLine.exists, "Closing one invoice must not close another")
        let invoice = app.buttons["job-invoice-\(depositA)"]
        revealJobItem(invoice, in: app)
        invoice.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "INV-2240")).firstMatch.waitForExistence(timeout: 5))
    }

    func testLargestTextKeepsInvoiceItemsReachable() {
        continueAfterFailure = false
        let app = preview(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let chooser = app.buttons["job-section-chooser"]
        XCTAssertTrue(chooser.waitForExistence(timeout: 15))
        chooser.tap()
        let money = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND identifier != %@", "Money", "job-section-chooser")).firstMatch
        XCTAssertTrue(money.waitForExistence(timeout: 5))
        money.tap()
        let items = app.buttons["job-invoice-items-\(invoiceA)"]
        revealJobItem(items, in: app)
        XCTAssertGreaterThanOrEqual(items.frame.height, 44)
        XCTAssertTrue(items.label.contains("INV-2209"))
        items.tap()
        let line = app.descendants(matching: .any)["job-invoice-line-\(invoiceA)-00000000-0000-4000-8000-000000009101"]
        XCTAssertTrue(line.waitForExistence(timeout: 5))
        XCTAssertTrue(line.label.contains("Compressor diagnostic"))
        let invoice = app.buttons["job-invoice-\(depositA)"]
        revealJobItem(invoice, in: app)
        invoice.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "INV-2240")).firstMatch.waitForExistence(timeout: 5))
    }

    func testPartlyVisibleInvoiceDisclosureDoesNotOpenPayment() {
        continueAfterFailure = false
        let app = preview()
        thorbisStableButton(app, "job-section-money").tap()
        let disclosure = app.buttons["job-invoice-items-\(invoiceA)"]
        let footer = app.buttons["Collect payment"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: 10))
        XCTAssertTrue(footer.waitForExistence(timeout: 10))
        XCTAssertLessThan(disclosure.frame.minY, footer.frame.minY)
        XCTAssertGreaterThan(disclosure.frame.maxY, footer.frame.minY, "Fixture must exercise a partially obscured control")
        let point = disclosure.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: 40, dy: 8))
        point.tap()
        let line = app.descendants(matching: .any)["job-invoice-line-\(invoiceA)-00000000-0000-4000-8000-000000009101"]
        XCTAssertTrue(line.waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Collect payment"].exists)
    }

    func testCommercialHandoffListsOnlyThisJobsEstimatesAndInvoices() {
        continueAfterFailure = false
        let app = preview()
        let more = app.buttons["Job actions"]
        XCTAssertTrue(more.waitForExistence(timeout: 15))
        more.tap()
        thorbisCustomerViewMenuItem(app).tap()
        XCTAssertTrue(app.staticTexts["Your job documents"].waitForExistence(timeout: 10))
        for identifier in ["customer-estimate-\(estimateA)", "customer-estimate-\(addonA)",
                           "customer-invoice-\(invoiceA)", "customer-invoice-\(depositA)"] {
            XCTAssertTrue(app.buttons[identifier].exists, identifier)
        }
        XCTAssertFalse(app.buttons["customer-invoice-\(invoiceB)"].exists)
        XCTAssertFalse(app.staticTexts["Other job estimate"].exists)
        capture(app, "Customer job documents")
    }

    func testCustomerCanBrowseDraftWithoutIssuingItAndReturnToDocuments() {
        continueAfterFailure = false
        let app = preview()
        handToCustomer(app)
        app.buttons["customer-estimate-\(addonA)"].tap()
        XCTAssertTrue(app.navigationBars["EST-2238"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Water heater add-ons"].exists)
        XCTAssertFalse(app.buttons["Sign to approve"].exists)
        XCTAssertFalse(app.buttons["Send estimate"].exists)
        XCTAssertTrue(app.buttons["Technician: unlock to leave customer mode"].exists)
        // #170: the back control reads "Back" now, not the previous title.
        app.navigationBars["EST-2238"].buttons["Back"].tap()
        XCTAssertTrue(app.buttons["customer-estimate-\(estimateA)"].waitForExistence(timeout: 5))
        app.buttons["customer-estimate-\(estimateA)"].tap()
        XCTAssertTrue(app.navigationBars["EST-2218"].waitForExistence(timeout: 5))
        capture(app, "Customer estimate review")
    }

    func testPartialEstimatesKeepSuccessfulPaperAndUnavailableReference() {
        continueAfterFailure = false
        let app = preview(extra: ["--paper-preview-job-documents-partial"])
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Couldn't load all estimates")).firstMatch.waitForExistence(timeout: 15))
        thorbisStableButton(app, "job-section-money").tap()
        XCTAssertTrue(app.buttons["job-estimate-\(estimateA)"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["job-estimate-unavailable-\(addonA)"].exists)
        XCTAssertFalse(app.staticTexts["No estimates yet"].exists)
        capture(app, "Partial job estimates")
    }

    func testLargestTextAndDarkModeKeepEveryCustomerDocumentReachable() {
        continueAfterFailure = false
        let app = preview(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
                                  "-thorbis.appearance", "dark"])
        handToCustomer(app)
        capture(app, "Accessible customer documents")
        let invoice = app.buttons["customer-invoice-\(invoiceA)"]
        reveal(invoice, in: app)
        invoice.tap()
        XCTAssertTrue(app.navigationBars["INV-2209"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Technician: unlock to leave customer mode"].exists)
        let previous = app.buttons["Previous document"]
        let choose = app.buttons["Choose a job document"]
        let next = app.buttons["Next document"]
        for control in [previous, choose, next] {
            XCTAssertTrue(control.exists)
            XCTAssertGreaterThanOrEqual(control.frame.width, 56)
            XCTAssertGreaterThanOrEqual(control.frame.height, 56)
            XCTAssertGreaterThanOrEqual(control.frame.minX, 0)
            XCTAssertLessThanOrEqual(control.frame.maxX, app.frame.width)
        }
        XCTAssertTrue(previous.frame.intersection(choose.frame).isEmpty)
        XCTAssertTrue(next.frame.intersection(choose.frame).isEmpty)
        XCTAssertLessThanOrEqual(previous.frame.height, 80, "Paging should reflow instead of wrapping a word into pieces")
        XCTAssertLessThanOrEqual(app.staticTexts["customer-document-position"].frame.height, 75)
        let description = app.staticTexts.matching(NSPredicate(format: "label == %@", "Compressor diagnostic")).firstMatch
        XCTAssertTrue(description.exists)
        capture(app, "Accessible customer invoice lines")
        // Either the description has the readable column's width, or it has a line of its own with
        // the price under it (the iPad's 720pt column: the words are shorter than the room).
        let price = app.staticTexts.matching(NSPredicate(format: "label == %@", "$120.00")).firstMatch
        let stacked = price.exists && price.frame.minY >= description.frame.maxY - 1
        XCTAssertTrue(stacked || description.frame.width >= min(app.frame.width, 760) * 0.6,
                      "Large descriptions need a readable column instead of squeezing beside a fixed price: \(description.frame), price \(price.frame)")
        capture(app, "Accessible customer invoice")
    }

    func testCustomerPaymentReturnsToTheSelectedInvoicesStaffCollection() {
        continueAfterFailure = false
        let app = preview(extra: ["--paper-preview-job-invoice-signed", "--paper-preview-owner-auth", "approved"])
        handToCustomer(app)
        let invoice = app.buttons["customer-invoice-\(invoiceA)"]
        reveal(invoice, in: app)
        invoice.tap()
        let pay = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Pay $340.00")).firstMatch
        XCTAssertTrue(pay.waitForExistence(timeout: 5))
        pay.tap()
        let cash = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Cash")).firstMatch
        XCTAssertTrue(cash.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Your job documents"].exists)
        XCTAssertTrue(app.buttons["received-payment-methods"].exists)
        capture(app, "Selected invoice collection after customer handoff")
    }

    func testDeclinedOwnerAuthenticationKeepsCustomerOutOfStaffCollection() {
        continueAfterFailure = false
        let app = preview(extra: ["--paper-preview-job-invoice-signed", "--paper-preview-owner-auth", "denied"])
        handToCustomer(app)
        let invoice = app.buttons["customer-invoice-\(invoiceA)"]
        reveal(invoice, in: app)
        invoice.tap()
        let pay = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Pay $340.00")).firstMatch
        XCTAssertTrue(pay.waitForExistence(timeout: 5))
        pay.tap()
        XCTAssertTrue(app.navigationBars["INV-2209"].exists)
        XCTAssertFalse(app.buttons["received-payment-methods"].exists)
        XCTAssertTrue(pay.isEnabled)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        let list = app.scrollViews["customer-job-documents-list"]
        let top = app.navigationBars["Customer view"].frame.maxY
        let bottom = app.buttons["Hand back to the technician"].frame.minY
        // Large cards can report hittable while their center is still behind the fixed footer.
        for _ in 0..<10 {
            if element.isHittable && element.frame.midY > top && element.frame.midY < bottom { break }
            list.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
        XCTAssertGreaterThan(element.frame.midY, top)
        XCTAssertLessThan(element.frame.midY, bottom)
    }

    private func handToCustomer(_ app: XCUIApplication) {
        let more = app.buttons["Job actions"]
        XCTAssertTrue(more.waitForExistence(timeout: 15))
        more.tap()
        let show = thorbisCustomerViewMenuItem(app)
        // The job menu is a ThorbisMenu sheet (a scroll view); at large text its later rows start below the fold.
        let menu = app.scrollViews.containing(NSPredicate(format: "elementType == %d AND label == %@",
                                                           XCUIElement.ElementType.button.rawValue, "Customer view")).firstMatch
        for _ in 0..<5 where !show.isHittable { menu.swipeUp() }
        XCTAssertTrue(show.isHittable)
        show.tap()
        XCTAssertTrue(app.staticTexts["Your job documents"].waitForExistence(timeout: 10))
    }

    private func preview(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job", "--paper-preview-working-job", "--paper-preview-job-documents"] + extra
        app.launch()
        return app
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor
final class JobDocumentsSafetyUITests: XCTestCase {
    private let invoice = "00000000-0000-4000-8000-000000002209"
    private let second = "00000000-0000-4000-8000-000000002240"

    func testOpenCollectionClosesWhenSavedScopeChangesAwayAndBack() {
        let app = launch(["--paper-preview-job-invoices-equal-balances", "--paper-preview-payment-scope-aba"], screen: "job-invoice")
        let collect = app.buttons["Collect payment"]
        XCTAssertTrue(collect.waitForExistence(timeout: 15))
        collect.tap()
        let sheet = app.navigationBars["Collect payment"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: sheet)
        waitForExpectations(timeout: 15)
    }

    func testUnchangedRevalidationPreservesPaymentAmount() {
        let app = launch(["--paper-preview-job-invoices-equal-balances", "--paper-preview-payment-revalidate"], screen: "job-invoice")
        let collect = app.buttons["Collect payment"]
        XCTAssertTrue(collect.waitForExistence(timeout: 15)); collect.tap()
        let cash = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Cash")).firstMatch
        XCTAssertTrue(cash.waitForExistence(timeout: 10)); cash.tap()
        let amount = app.textFields["Amount to collect in dollars"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5)); amount.tap()
        let current = (amount.value as? String) ?? ""
        amount.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + "12.34")
        if app.buttons["Done"].exists { app.buttons["Done"].tap() }
        let revalidate = app.buttons["preview-payment-revalidate"]
        XCTAssertTrue(revalidate.waitForExistence(timeout: 5)); revalidate.tap()
        XCTAssertTrue(app.buttons["preview-payment-revalidated"].waitForExistence(timeout: 10))
        XCTAssertTrue(amount.exists)
        XCTAssertEqual(amount.value as? String, "12.34")
        XCTAssertTrue(app.navigationBars["Collect payment"].exists)
    }

    func testRevokedPaymentPermissionClosesCollection() {
        let app = launch(["--paper-preview-job-invoices-equal-balances", "--paper-preview-payment-revalidate", "--paper-preview-payment-revoke"], screen: "job-invoice")
        let collect = app.buttons["Collect payment"]
        XCTAssertTrue(collect.waitForExistence(timeout: 15)); collect.tap()
        let sheet = app.navigationBars["Collect payment"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 10))
        let revalidate = app.buttons["preview-payment-revalidate"]
        XCTAssertTrue(revalidate.waitForExistence(timeout: 5)); revalidate.tap()
        // Verify that the job screen is usable and payment controls are no longer reachable
        // after revalidation, independently of the sheet navigation-bar query.
        let handoff = app.buttons["Show customer"]
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: handoff)], timeout: 20)
        if result != .completed {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Payment revocation accessibility hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertEqual(result, .completed)
        XCTAssertFalse(app.buttons["Create payment link"].isHittable)
        XCTAssertFalse(app.buttons["Collect payment"].isHittable)
        XCTAssertFalse(app.buttons["Cash"].isHittable)
        XCTAssertFalse(app.buttons["Check"].isHittable)
        XCTAssertFalse(app.buttons["Other"].isHittable)
        XCTAssertFalse(app.textFields["Amount to collect in dollars"].isHittable)
    }

    func testPartialReadRequiresRefreshBeforeBuildingAnotherEstimate() {
        let app = launch(["--paper-preview-job-documents-partial"])
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Couldn't load all estimates")).firstMatch.waitForExistence(timeout: 15))
        thorbisSection(app, "Money").tap()
        XCTAssertTrue(app.buttons["job-estimate-\(invoice.replacingOccurrences(of: "2209", with: "2218"))"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Build an estimate"].exists)
    }

    func testEqualBalanceCardSelectsTheInvoiceCollectedAfterReturning() {
        let app = launch(["--paper-preview-job-invoices-equal-balances"], screen: "job-invoice")
        let first = app.buttons["job-invoice-\(invoice)"]
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        // Cream sheet: the invoice row can start under the pinned Collect payment commit.
        app.scrollClearOfFoot(first)
        first.tap()
        XCTAssertTrue(app.staticTexts["INV-2209"].waitForExistence(timeout: 5))
        // Since #210 the drawer's menu circle sits beside Back on pushed screens, so take Back by name.
        app.navigationBars.buttons["Back"].firstMatch.tap()
        XCTAssertTrue(app.buttons["job-invoice-\(invoice)"].waitForExistence(timeout: 5))
        let collect = app.buttons["Collect payment"]
        XCTAssertTrue(collect.waitForExistence(timeout: 10))
        collect.tap()
        XCTAssertTrue(app.navigationBars["Collect payment"].waitForExistence(timeout: 5))
        // Since #216 the collection leads with "INV-2209 · customer" over the amount, and the amount
        // field only shows for a custom amount, so the invoice is read from that line.
        let collecting = app.descendants(matching: .any)["collect-payment-invoice"]
        XCTAssertTrue(collecting.waitForExistence(timeout: 5))
        XCTAssertTrue(collecting.label.contains("INV-2209"), collecting.label)
        XCTAssertFalse(collecting.label.contains("INV-2240"), collecting.label)
    }

    func testLegacyCustomerRefreshKeepsBothKnownJobInvoices() {
        let app = launch(["--paper-preview-job-invoices-legacy"])
        ready(app)
        handToCustomer(app)
        XCTAssertTrue(app.buttons["customer-invoice-\(invoice)"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["customer-invoice-\(second)"].exists)
        XCTAssertFalse(app.staticTexts["No invoices for this job yet."].exists)
    }

    func testEstimateTotalsRemainAvailableInADisclosure() {
        let app = launch()
        ready(app)
        let money = thorbisStableButton(app, "job-section-money")
        money.tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: money)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 10), .completed)
        let disclosure = app.buttons["Estimate totals"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5))
        disclosure.tap()
        XCTAssertTrue(app.staticTexts["Awaiting approval · USD"].exists)
        XCTAssertTrue(app.staticTexts["$970.00"].exists)
    }

    func testStaffDetailRejectsSameInvoiceIDReturnedForAnotherJob() {
        let app = launch(["--paper-preview-job-invoice-foreign"])
        XCTAssertTrue(thorbisSection(app, "Money").waitForExistence(timeout: 15))
        thorbisSection(app, "Money").tap()
        let paper = app.buttons["job-invoice-\(invoice)"]
        XCTAssertTrue(paper.waitForExistence(timeout: 10))
        paper.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "This invoice couldn't be verified")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["INV-2209"].exists)
        XCTAssertFalse(app.buttons["Customer view"].exists)
        XCTAssertFalse(app.buttons["Show customer"].exists)
        XCTAssertFalse(app.buttons["Collect payment"].exists)
    }

    func testChangedJobAtFinalHandbackCannotOpenCollection() {
        let app = launch(["--paper-preview-job-invoice-signed", "--paper-preview-owner-auth", "approved",
                          "--paper-preview-job-invoice-foreign-after-auth"])
        ready(app)
        handToCustomer(app)
        let paper = app.buttons["customer-invoice-\(invoice)"]
        thorbisRevealInCustomerView(paper, in: app)
        paper.tap()
        let pay = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Pay $340.00")).firstMatch
        XCTAssertTrue(pay.waitForExistence(timeout: 5))
        pay.tap()
        XCTAssertTrue(app.buttons["Job actions"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars["Collect payment"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["received-payment-methods"].exists)
    }

    private func launch(_ extra: [String] = [], screen: String = "job") -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", screen, "--paper-preview-working-job", "--paper-preview-job-documents"] + extra
        app.launch()
        return app
    }
    private func ready(_ app: XCUIApplication) {
        XCTAssertTrue(thorbisJobBalanceLoaded(app, "$340.00").waitForExistence(timeout: 15))
    }
    private func handToCustomer(_ app: XCUIApplication) {
        app.buttons["Job actions"].tap()
        thorbisCustomerViewMenuItem(app).tap()
        XCTAssertTrue(app.staticTexts["Your job documents"].waitForExistence(timeout: 10))
    }
}

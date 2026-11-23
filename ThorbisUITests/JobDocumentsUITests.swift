import XCTest

@MainActor
final class JobDocumentsUITests: XCTestCase {
    private let invoiceA = "00000000-0000-4000-8000-000000002209"
    private let depositA = "00000000-0000-4000-8000-000000002240"
    private let invoiceB = "00000000-0000-4000-8000-000000002241"
    private let estimateA = "00000000-0000-4000-8000-000000002218"
    private let addonA = "00000000-0000-4000-8000-000000002238"

    /// Paper 24: at the largest text the one payable invoice is still collected from its card on Money.
    func testMoneyCollectPillAtLargestText() {
        continueAfterFailure = false
        let app = preview(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        openMoneyFromChooser(app)
        let collect = app.buttons["job-invoice-collect-\(invoiceA)"]
        for _ in 0..<10 where !collect.exists { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(collect.waitForExistence(timeout: 15))
        app.scrollClearOfFoot(collect)
        XCTAssertTrue(collect.isHittable)
        XCTAssertGreaterThanOrEqual(collect.frame.height, 44)
        collect.tap()
        XCTAssertTrue(app.navigationBars["Collect payment"].waitForExistence(timeout: 15))
        let identity = app.descendants(matching: .any)["collect-payment-invoice"]
        XCTAssertTrue(identity.waitForExistence(timeout: 10))
        XCTAssertTrue(identity.label.contains("2209"), identity.label)
    }

    func testMoneyCollectsTheOnlyPayableInvoiceFromItsCard() {
        continueAfterFailure = false
        let app = preview()
        // Paper 24: the one payable invoice is collected from its card on Money.
        XCTAssertTrue(thorbisSection(app, "Money").waitForExistence(timeout: 30))
        thorbisSection(app, "Money").tap()
        let collect = app.buttons["job-invoice-collect-\(invoiceA)"]
        for _ in 0..<10 where !collect.exists { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(collect.waitForExistence(timeout: 15))
        app.scrollClearOfFoot(collect)
        XCTAssertTrue(collect.isHittable)
        XCTAssertGreaterThanOrEqual(collect.frame.height, 44)
        collect.tap()
        XCTAssertTrue(app.navigationBars["Collect payment"].waitForExistence(timeout: 15))
        let identity = app.descendants(matching: .any)["collect-payment-invoice"]
        XCTAssertTrue(identity.waitForExistence(timeout: 10))
        XCTAssertTrue(identity.label.contains("2209"), identity.label)
    }

    /// Collect payment loads the invoice's payment details before its sheet opens. Leaving Money
    /// while they load must not open collection over another section, and the pill stays busy
    /// meanwhile. (It was Overview's shortcut; Paper 24 collects from the invoice's card on Money.)
    func testLeavingMoneyDuringPaymentLoadDoesNotOpenCollection() {
        continueAfterFailure = false
        let app = preview(extra: ["--paper-preview-overview-payment-hold"])
        thorbisTapStableButton(app, "job-section-money")
        let collect = app.buttons["job-invoice-collect-\(invoiceA)"]
        // The invoice's card sits below the fold in Money's lazy stack, as in the test above.
        for _ in 0..<10 where !collect.exists { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(collect.waitForExistence(timeout: 15))
        app.scrollClearOfFoot(collect)
        XCTAssertTrue(collect.isHittable)
        collect.tap()
        XCTAssertTrue(app.staticTexts["job-overview-payment-hold"].waitForExistence(timeout: 20))
        XCTAssertFalse(collect.isEnabled, "Collection stays busy until payment details finish loading")
        // The sections pin under the bar once Money is scrolled; leave at once, while the details load.
        app.buttons["job-section-activity"].firstMatch.tap()
        XCTAssertTrue(app.buttons["job-section-activity"].firstMatch.isSelected)
        let sheet = app.navigationBars["Collect payment"]
        let noSheet = expectation(for: NSPredicate(format: "exists == true"), evaluatedWith: sheet)
        noSheet.isInverted = true
        waitForExpectations(timeout: 9)
        XCTAssertFalse(sheet.exists)
        // Back on Money the pill is free again and collects.
        thorbisTapStableButton(app, "job-section-money")
        XCTAssertTrue(collect.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: collect)
        waitForExpectations(timeout: 10)
    }

    /// An invoice opened from its card on Money retires when the session is replaced under it.
    func testMoneyInvoiceRetiresWhenSessionIsReplaced() {
        continueAfterFailure = false
        let app = preview(extra: ["--paper-preview-overview-retire", "--paper-preview-description-replace-session"])
        thorbisTapStableButton(app, "job-section-money")
        let row = app.buttons["job-invoice-\(invoiceA)"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        revealJobItem(row, in: app)
        row.tap()
        let detail = app.staticTexts["invoice-detail-title"]
        XCTAssertTrue(detail.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: detail)
        waitForExpectations(timeout: 25)
        let unavailable = app.staticTexts["Document unavailable"]
        if !unavailable.waitForExistence(timeout: 15) {
            XCTAssertTrue(app.buttons["job-section-money"].waitForExistence(timeout: 15))
        }
    }

    /// An invoice opened from its card on Money retires when a revalidation finds changed authority
    /// (the sample server revises it, same access); an identical check would keep it open.
    func testMoneyInvoiceRetiresWhenAuthorityIsRevalidated() {
        continueAfterFailure = false
        let app = preview(extra: ["--paper-preview-overview-revalidate"])
        thorbisTapStableButton(app, "job-section-money")
        let row = app.buttons["job-invoice-\(invoiceA)"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        revealJobItem(row, in: app)
        row.tap()
        XCTAssertTrue(app.staticTexts["invoice-detail-title"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Document unavailable"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts["invoice-detail-title"].exists)
    }

    /// A foreground or reconnect check that finds the same authority leaves an invoice opened from
    /// Money open (BYR-1833).
    func testMoneyInvoiceStaysOpenWhenAnIdenticalCheckAnswers() {
        continueAfterFailure = false
        let app = preview(extra: ["--paper-preview-overview-recheck"])
        thorbisTapStableButton(app, "job-section-money")
        let row = app.buttons["job-invoice-\(invoiceA)"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        revealJobItem(row, in: app)
        row.tap()
        XCTAssertTrue(app.staticTexts["invoice-detail-title"].waitForExistence(timeout: 10))
        // The check lands five seconds after the invoice opens; the marker says the server answered it.
        XCTAssertTrue(app.staticTexts["preview-overview-rechecked"].waitForExistence(timeout: 20), "The sample check must be answered")
        XCTAssertTrue(app.staticTexts["invoice-detail-title"].exists, "An identical check must keep the opened invoice")
        XCTAssertFalse(app.staticTexts["Document unavailable"].exists)
    }

    /// While the job's paper reloads under a new authority, the invoice card read under the old
    /// one can't open its document.
    func testMoneyInvoiceCannotOpenFromOldReadDuringAuthorityReload() {
        continueAfterFailure = false
        let app = preview(extra: ["--paper-preview-overview-hold-reload"])
        thorbisTapStableButton(app, "job-section-money")
        let row = app.buttons["job-invoice-\(invoiceA)"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: row)
        waitForExpectations(timeout: 10)
        // Money is a lazy page: the invoices (and this fixture's control above them) follow the estimates.
        let refresh = app.buttons["job-overview-revalidate"]
        for _ in 0..<6 where !(refresh.exists && refresh.isHittable && row.isHittable) { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(refresh.isHittable)
        XCTAssertTrue(row.isHittable)
        refresh.tap()
        expectation(for: NSPredicate(format: "enabled == false"), evaluatedWith: row)
        waitForExpectations(timeout: 10)
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertFalse(app.staticTexts["invoice-detail-title"].waitForExistence(timeout: 2))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: row)
        waitForExpectations(timeout: 20)
    }

    func testCreatingFirstInvoiceOpensTheReturnedDraftOnlyOnce() {
        continueAfterFailure = false
        let app = preview(extra: ["--paper-preview-create-invoice"])
        thorbisTapStableButton(app, "job-section-money")
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
        thorbisTapStableButton(app, "job-section-money")
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
        thorbisTapStableButton(app, "job-section-money")
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
        thorbisTapStableButton(app, "job-section-money")
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
            thorbisTapStableButton(app, "job-section-money")
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

    /// Paper 23: Money is one page (the estimates' card, then the invoices), with no jump chips.
    /// Every estimate and invoice is reached by scrolling it.
    func testMoneySectionReachesEstimatesAndInvoicesOnOnePage() {
        continueAfterFailure = false
        let app = preview()
        thorbisTapStableButton(app, "job-section-money")
        XCTAssertFalse(app.buttons["job-money-jump-invoices"].exists, "Paper's Money has no jump chips")
        let estimate = app.buttons["job-estimate-\(estimateA)"]
        XCTAssertTrue(estimate.waitForExistence(timeout: 15))
        revealJobItem(estimate, in: app)
        XCTAssertTrue(estimate.label.contains("Waiting on customer"), estimate.label)
        // Owner 2026-11-21: one inline add on Money, the Estimates label's + (the card's last
        // row "Add an estimate" and the big "Build an estimate" button repeated it).
        let addEstimate = app.buttons["job-add-estimate"]
        XCTAssertTrue(addEstimate.exists, "The Estimates label carries the one inline add")
        XCTAssertEqual(addEstimate.label, "Add estimate")
        XCTAssertFalse(app.buttons["job-add-estimate-row"].exists, "The card no longer repeats the add")
        XCTAssertFalse(app.buttons["job-estimates-build"].exists, "The totals card no longer repeats the add")
        let invoice = app.buttons["job-invoice-\(invoiceA)"]
        XCTAssertTrue(invoice.waitForExistence(timeout: 10))
        revealJobItem(invoice, in: app)
        XCTAssertGreaterThan(invoice.frame.minY, estimate.frame.minY, "Invoices follow the estimates")
        XCTAssertTrue(invoice.label.contains("INV-2209"), invoice.label)
        XCTAssertTrue(invoice.label.contains("$340.00"), invoice.label)
        XCTAssertTrue(invoice.label.contains("Unpaid"), invoice.label)
        let collect = app.buttons["job-invoice-collect-\(invoiceA)"]
        XCTAssertTrue(collect.exists, "The balance card carries Collect payment")
    }

    func testOpenedInvoiceStaysTheChosenInvoiceForCollection() {
        continueAfterFailure = false
        let app = preview(extra: ["--paper-preview-job-invoices-equal-balances"])
        thorbisTapStableButton(app, "job-section-money")
        let invoice = app.buttons["job-invoice-\(invoiceA)"]
        XCTAssertTrue(invoice.waitForExistence(timeout: 15))
        revealJobItem(invoice, in: app)
        invoice.tap()
        XCTAssertTrue(app.staticTexts["INV-2209"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Back"].firstMatch.tap()
        // The invoice's page has its own Collect payment and stays in the tree while it slides away.
        XCTAssertTrue(app.staticTexts["invoice-detail-title"].waitForNonExistence(timeout: 10))
        // Paper 24: the invoice's own card collects it; with two payable invoices no pill is unnamed.
        XCTAssertFalse(app.buttons["Collect payment"].exists, "Two payable invoices: every Collect payment names its invoice")
        let collect = app.buttons["job-invoice-collect-\(invoiceA)"]
        XCTAssertTrue(collect.waitForExistence(timeout: 10))
        app.scrollClearOfFoot(collect)
        XCTAssertEqual(collect.label, "Collect payment for invoice INV-2209")
        collect.tap()
        let collecting = app.descendants(matching: .any)["collect-payment-invoice"]
        XCTAssertTrue(collecting.waitForExistence(timeout: 5))
        XCTAssertTrue(collecting.label.contains("INV-2209"), collecting.label)
    }

    func testDirectCollectionOpensTheTappedJobInvoice() {
        continueAfterFailure = false
        let app = preview(extra: ["--paper-preview-job-invoices-equal-balances", "--paper-preview-job-invoice-reference-collision"])
        let collisionID = "00000000-0000-4000-8000-000000012209"
        thorbisTapStableButton(app, "job-section-money")
        let first = app.buttons["job-invoice-collect-\(invoiceA)"]
        let second = app.buttons["job-invoice-collect-\(collisionID)"]
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        XCTAssertTrue(second.exists)
        XCTAssertEqual(first.label, "Collect payment for invoice INV-02209")
        XCTAssertEqual(second.label, "Collect payment for invoice INV-12209")
        XCTAssertTrue(app.buttons["job-invoice-\(invoiceA)"].label.contains("INV-02209"))
        XCTAssertTrue(app.buttons["job-invoice-\(collisionID)"].label.contains("INV-12209"))
        // Paper 24: Money has no shared collection bar, so no "For INV-…" line can name the wrong invoice.
        XCTAssertFalse(app.staticTexts["job-collect-selected-invoice"].exists)
        XCTAssertFalse(app.buttons["Collect payment"].exists, "Every Collect payment names its invoice")
        app.scrollClearOfFoot(first)
        XCTAssertTrue(first.isHittable)
        capture(app, "Job invoices with direct payment")
        first.tap()
        let identity = app.descendants(matching: .any)["collect-payment-invoice"]
        XCTAssertTrue(identity.waitForExistence(timeout: 10))
        XCTAssertTrue(identity.label.contains("INV-02209"), identity.label)
        app.buttons["Close"].tap()
        XCTAssertTrue(second.waitForExistence(timeout: 10))
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

    /// Paper 23 has no jump chips, so at the largest text every invoice is reached by scrolling.
    func testInvoicesRemainReachableAtLargestText() {
        let app = preview(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let chooser = app.buttons["job-section-chooser"]
        XCTAssertTrue(chooser.waitForExistence(timeout: 15))
        chooser.tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND identifier != %@", "Money", "job-section-chooser")).firstMatch.tap()
        let invoice = app.buttons["job-invoice-\(depositA)"]
        for _ in 0..<12 where !invoice.exists { app.swipeUp() }
        XCTAssertTrue(invoice.waitForExistence(timeout: 10))
        revealJobItem(invoice, in: app)
        XCTAssertGreaterThanOrEqual(invoice.frame.height, 44)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Money invoices largest text hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        capture(app, "Money invoices largest text")
        XCTAssertTrue(invoice.isHittable)
    }

    func testTechnicianEstimateCardsKeepBothDocumentsOpenable() {
        continueAfterFailure = false
        let app = preview()
        thorbisTapStableButton(app, "job-section-money")
        let first = app.buttons["job-estimate-\(estimateA)"]
        let second = app.buttons["job-estimate-\(addonA)"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertTrue(second.exists)
        XCTAssertTrue(first.label.contains("Waiting on customer"), "Sent work needs a clear next step")
        XCTAssertTrue(second.label.contains("Not sent yet"), "Drafts must not look sent")
        XCTAssertTrue(first.label.contains("EST-2218"))
        XCTAssertTrue(second.label.contains("EST-2238"))
        XCTAssertFalse(app.buttons["job-estimate-00000000-0000-4000-8000-000000002239"].exists, "Other jobs' estimates must not appear")
        // Paper 24: the $340 owed is collected from the invoice's own card.
        let collect = app.buttons["job-invoice-collect-\(invoiceA)"]
        XCTAssertTrue(collect.waitForExistence(timeout: 10))
        // Paper 23: the estimates' customer door is Money › Show estimates (checked in JobEstimateHandoffUITests).
        for _ in 0..<5 where !first.isHittable { app.swipeUp() }
        XCTAssertTrue(first.isHittable)
        capture(app, "Job estimate cards")
        first.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "EST-2218")).firstMatch.waitForExistence(timeout: 10))
    }

    func testEstimateCardsKeepApprovedDeclinedAndUnknownAmountHonest() {
        continueAfterFailure = false
        let app = preview(extra: ["--paper-preview-job-estimate-review-states"])
        thorbisTapStableButton(app, "job-section-money")
        let declined = app.buttons["job-estimate-\(estimateA)"]
        let approved = app.buttons["job-estimate-\(addonA)"]
        XCTAssertTrue(declined.waitForExistence(timeout: 10))
        XCTAssertTrue(approved.exists)
        XCTAssertTrue(declined.label.contains("Declined"))
        XCTAssertFalse(declined.label.contains("Waiting on customer"))
        XCTAssertTrue(approved.label.contains("Approved"))
        XCTAssertTrue(approved.label.contains("View estimate details"))
        XCTAssertFalse(approved.label.contains("$970.00"), "An unknown accepted scope has no invented total")
    }

    func testEstimateCardKeepsCompleteOptionsSeparateFromAnAmount() {
        continueAfterFailure = false
        let app = preview(extra: ["--paper-preview-job-estimate-multiple-options"])
        thorbisTapStableButton(app, "job-section-money")
        let estimate = app.buttons["job-estimate-\(estimateA)"]
        XCTAssertTrue(estimate.waitForExistence(timeout: 10))
        XCTAssertTrue(estimate.label.contains("2 options"))
        XCTAssertTrue(estimate.label.contains("Waiting on customer"))
        XCTAssertFalse(estimate.label.contains("$970.00"), "Complete alternatives cannot be summed or represented as one amount")
    }

    func testLargestTextKeepsJobEstimateCardsAndCustomerActionReachable() {
        continueAfterFailure = false
        let app = preview(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-thorbis.appearance", "dark"])
        openMoneyFromChooser(app)
        let first = app.buttons["job-estimate-\(estimateA)"]
        let second = app.buttons["job-estimate-\(addonA)"]
        for _ in 0..<8 where !first.exists { app.swipeUp() }
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertTrue(first.label.contains("Waiting on customer"))
        for _ in 0..<8 where !second.exists { app.swipeUp() }
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        XCTAssertTrue(second.label.contains("Not sent yet"))
        revealJobItem(second, in: app)
        XCTAssertGreaterThanOrEqual(second.frame.height, 44)
        capture(app, "Large text job estimates")
        second.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "EST-2238")).firstMatch.waitForExistence(timeout: 10))
        app.navigationBars.buttons["Back"].firstMatch.tap()
        // Back on Money, the estimates' customer door is still one menu away (Money › Show estimates).
        let present = thorbisShowCustomerDoor(app)
        XCTAssertTrue(present.waitForExistence(timeout: 10))
        XCTAssertTrue(present.isHittable)
    }

    private func revealJobItem(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        let chooser = app.buttons["job-section-chooser"]
        let moneyTab = app.buttons["job-section-money"]
        // Paper 21: Money keeps the job's bar (its commit) over the page.
        let footer = app.buttons["job-commit"]
        let list = app.scrollViews.firstMatch
        let menu = app.buttons["job-money-jump-menu"]
        func topBoundary() -> CGFloat {
            let section = chooser.exists ? chooser.frame.maxY : (moneyTab.exists ? moneyTab.frame.maxY : app.frame.minY)
            return menu.exists ? max(section, menu.frame.maxY) : section
        }
        func bottomBoundary() -> CGFloat { !chooser.exists && footer.exists ? footer.frame.minY : app.frame.maxY }
        // The menu itself moves until pinned. Re-read its frame after each small drag so we
        // neither use its stale position nor bounce past a card that just fits the viewport.
        for _ in 0..<24 {
            let frame = element.frame, top = topBoundary(), bottom = bottomBoundary()
            if element.isHittable && frame.minY >= top && frame.maxY <= bottom { break }
            let down = frame.minY < top
            let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.4 : 0.6))
            let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.6 : 0.4))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        let top = topBoundary(), bottom = bottomBoundary()
        let context = "\(element.identifier), frame: \(element.frame), visible range: \(top)...\(bottom)"
        XCTAssertTrue(element.isHittable, context)
        XCTAssertGreaterThanOrEqual(element.frame.minY, top, context)
        XCTAssertLessThanOrEqual(element.frame.maxY, bottom, context)
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

    /// Paper 23: the estimates' totals lead Money in one card ("Awaiting approval", "Approved"),
    /// always open. An approved total that can't be known says so instead of showing a number.
    func testEstimateTotalsShowSentAmountAndExplainUnknownApprovedAmount() {
        continueAfterFailure = false
        let app = preview(extra: ["--paper-preview-approved-unknown-total"])
        thorbisTapStableButton(app, "job-section-money")
        XCTAssertFalse(app.buttons["Estimate totals"].exists, "The totals are a card, not a disclosure")
        let awaiting = app.descendants(matching: .any)["job-estimates-awaiting"]
        XCTAssertTrue(awaiting.waitForExistence(timeout: 10))
        XCTAssertTrue(awaiting.label.contains("Awaiting approval"), awaiting.label)
        XCTAssertTrue(awaiting.label.contains("$970.00"), awaiting.label)
        XCTAssertTrue(app.staticTexts["Approved total unavailable"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["job-estimates-approved"].exists,
                       "An unknown approved total shows no amount")
    }

    func testAllJobInvoicesAreVisibleAndOpenTheirOwnDetail() {
        continueAfterFailure = false
        let app = preview()
        XCTAssertTrue(thorbisJobBalanceLoaded(app, "$340.00").waitForExistence(timeout: 15))
        XCTAssertTrue(thorbisSection(app, "Money").waitForExistence(timeout: 15))
        thorbisTapStableButton(app, "job-section-money")
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
        thorbisTapStableButton(app, "job-section-money")
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
        openMoneyFromChooser(app)
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
        thorbisTapStableButton(app, "job-section-money")
        let disclosure = app.buttons["job-invoice-items-\(invoiceA)"]
        // Paper 21: Money keeps the job's bar, floating over the page. Its commit covers what
        // scrolls under it, so the covered edge is the commit's top.
        let footer = app.buttons["job-commit"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: 10))
        XCTAssertTrue(footer.waitForExistence(timeout: 10))
        func coverEdge() -> CGFloat { footer.frame.minY }
        // Where the disclosure lands depends on what sits above it (job tabs flow onto a second line
        // since #403), so slide Money until the disclosure's top 20pt show above the footer and the
        // rest of it runs under the footer. A held, slow drag leaves no momentum to overshoot.
        for _ in 0..<6 {
            let edge = coverEdge()
            // Settled when the tap point (8pt in) shows above the edge and the rest runs under it.
            if disclosure.frame.minY >= edge - 34, disclosure.frame.minY <= edge - 14 { break }
            let offset = disclosure.frame.minY - (edge - 24)
            // Scrolling only follows the finger past iOS's ~10pt touch slop, so add it to each drag
            // (which also keeps every drag long enough never to be read as a tap).
            let distance = max(-250, min(250, offset + (offset > 0 ? 10 : -10)))
            // Start mid-content: the footer takes no scrolls.
            let start = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: app.frame.midX, dy: app.frame.height * 0.5 + distance / 2))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -distance)),
                        withVelocity: .slow, thenHoldForDuration: 0.5)
        }
        XCTAssertLessThan(disclosure.frame.minY + 8, coverEdge(), "The tap point must be on the visible part")
        XCTAssertGreaterThan(disclosure.frame.maxY, coverEdge(), "Fixture must exercise a partially obscured control")
        let point = disclosure.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: 40, dy: 8))
        point.tap()
        let line = app.descendants(matching: .any)["job-invoice-line-\(invoiceA)-00000000-0000-4000-8000-000000009101"]
        XCTAssertTrue(line.waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Collect payment"].exists)
        // Nor did the tap reach the bar's commit under it: the job is still on Money.
        XCTAssertTrue(footer.exists)
        XCTAssertTrue(app.buttons["job-section-money"].firstMatch.isSelected)
    }

    func testCommercialHandoffListsOnlyThisJobsEstimatesAndInvoices() {
        continueAfterFailure = false
        let app = preview()
        let more = app.buttons["Job actions"]
        XCTAssertTrue(more.waitForExistence(timeout: 15))
        app.buttons["Job actions"].tap()
        thorbisCustomerViewMenuItem(app).tap()
        XCTAssertTrue(app.staticTexts["customer-view-title"].waitForExistence(timeout: 10))
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
        thorbisTapStableButton(app, "job-section-money")
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
        // The staff job screen stays in the tree under Customer view and lists the same line, so
        // the words are read from the customer's own pages.
        let pages = app.collectionViews["customer-document-pages"]
        let description = pages.staticTexts.matching(NSPredicate(format: "label == %@", "Compressor diagnostic")).firstMatch
        XCTAssertTrue(description.exists)
        capture(app, "Accessible customer invoice lines")
        // Either the description has the readable column's width, or it has a line of its own with
        // the price under it (the iPad's 720pt column: the words are shorter than the room).
        let price = pages.staticTexts.matching(NSPredicate(format: "label == %@", "$120.00")).firstMatch
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
        XCTAssertFalse(app.staticTexts["customer-view-title"].exists)
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
        // Paper 38B: Customer view's home has no bar; the list starts under the status bar.
        let bar = app.navigationBars["Customer view"]
        let top = bar.exists ? bar.frame.maxY : 0
        let bottom = app.buttons["Hand back to technician"].frame.minY
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
        XCTAssertTrue(app.buttons["Job actions"].waitForExistence(timeout: 15))
        // The job menu is a ThorbisMenu sheet; at large text its later rows start below the fold.
        let show = thorbisCustomerViewDoor(app)
        XCTAssertTrue(show.waitForExistence(timeout: 5))
        thorbisRevealJobMenuRow(show, in: app)
        XCTAssertTrue(show.isHittable)
        show.tap()
        XCTAssertTrue(app.staticTexts["customer-view-title"].waitForExistence(timeout: 10))
    }

    /// At accessibility sizes the job's sections are one chooser; pick Money from it.
    private func openMoneyFromChooser(_ app: XCUIApplication) {
        let chooser = app.buttons["job-section-chooser"]
        XCTAssertTrue(chooser.waitForExistence(timeout: 15))
        for _ in 0..<5 where !chooser.isHittable { app.swipeUp(velocity: .slow) }
        chooser.tap()
        let money = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND identifier != %@", "Money", "job-section-chooser")).firstMatch
        XCTAssertTrue(money.waitForExistence(timeout: 5))
        money.tap()
    }

    private func preview(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job", "--paper-preview-working-job", "--paper-preview-job-documents"] + extra
        app.launch()
        XCTAssertTrue(app.staticTexts["job-title"].waitForExistence(timeout: 20))
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
        let collect = collectPill(app, invoice)
        collect.tap()
        let sheet = app.navigationBars["Collect payment"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: sheet)
        waitForExpectations(timeout: 15)
    }

    func testUnchangedRevalidationPreservesPaymentAmount() {
        let app = launch(["--paper-preview-job-invoices-equal-balances", "--paper-preview-payment-revalidate"], screen: "job-invoice")
        let collect = collectPill(app, invoice); collect.tap()
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
        let collect = collectPill(app, invoice); collect.tap()
        let sheet = app.navigationBars["Collect payment"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 10))
        let revalidate = app.buttons["preview-payment-revalidate"]
        XCTAssertTrue(revalidate.waitForExistence(timeout: 5)); revalidate.tap()
        // Verify that the job screen is usable and payment controls are no longer reachable
        // after revalidation, independently of the sheet navigation-bar query.
        // The job's own controls (its More circle) are back in reach.
        let handoff = app.buttons["Job actions"]
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: handoff)], timeout: 20)
        if result != .completed {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Payment revocation accessibility hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertEqual(result, .completed)
        XCTAssertFalse(app.buttons["Create payment link"].isHittable)
        // Paper 24: with the permission gone, no invoice card offers Collect payment.
        XCTAssertFalse(app.buttons["job-invoice-collect-\(invoice)"].exists)
        XCTAssertFalse(app.buttons["job-invoice-collect-\(second)"].exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Collect payment")).firstMatch.exists)
        XCTAssertFalse(app.buttons["Cash"].isHittable)
        XCTAssertFalse(app.buttons["Check"].isHittable)
        XCTAssertFalse(app.buttons["Other payment received"].isHittable)
        XCTAssertFalse(app.textFields["Amount to collect in dollars"].isHittable)
    }

    func testPartialReadRequiresRefreshBeforeBuildingAnotherEstimate() {
        let app = launch(["--paper-preview-job-documents-partial"])
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Couldn't load all estimates")).firstMatch.waitForExistence(timeout: 15))
        thorbisTapStableButton(app, "job-section-money")
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
        // Paper 24: each invoice's card carries its own Collect payment, so the card tapped is the
        // invoice collected: the one just opened, then the other one (never the one last opened).
        let collecting = app.descendants(matching: .any)["collect-payment-invoice"]
        collectPill(app, invoice).tap()
        XCTAssertTrue(app.navigationBars["Collect payment"].waitForExistence(timeout: 5))
        // Since #216 the collection leads with "INV-2209 · customer" over the amount, and the amount
        // field only shows for a custom amount, so the invoice is read from that line.
        XCTAssertTrue(collecting.waitForExistence(timeout: 5))
        XCTAssertTrue(collecting.label.contains("INV-2209"), collecting.label)
        XCTAssertFalse(collecting.label.contains("INV-2240"), collecting.label)
        app.buttons["Close"].tap()
        collectPill(app, second).tap()
        XCTAssertTrue(app.navigationBars["Collect payment"].waitForExistence(timeout: 5))
        XCTAssertTrue(collecting.waitForExistence(timeout: 5))
        XCTAssertTrue(collecting.label.contains("INV-2240"), collecting.label)
        XCTAssertFalse(collecting.label.contains("INV-2209"), collecting.label)
    }

    func testLegacyCustomerRefreshKeepsBothKnownJobInvoices() {
        let app = launch(["--paper-preview-job-invoices-legacy"])
        ready(app)
        handToCustomer(app)
        XCTAssertTrue(app.buttons["customer-invoice-\(invoice)"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["customer-invoice-\(second)"].exists)
        XCTAssertFalse(app.staticTexts["No invoices for this job yet."].exists)
    }

    /// Paper 23: the estimates' totals are the card that leads Money, open without a tap.
    func testEstimateTotalsLeadMoneyInTheirCard() {
        let app = launch()
        ready(app)
        let money = thorbisTapStableButton(app, "job-section-money")
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: money)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 10), .completed)
        let awaiting = app.descendants(matching: .any)["job-estimates-awaiting"]
        XCTAssertTrue(awaiting.waitForExistence(timeout: 5))
        XCTAssertTrue(awaiting.label.contains("Awaiting approval"), awaiting.label)
        XCTAssertTrue(awaiting.label.contains("$970.00"), awaiting.label)
    }

    func testStaffDetailRejectsSameInvoiceIDReturnedForAnotherJob() {
        let app = launch(["--paper-preview-job-invoice-foreign"])
        XCTAssertTrue(thorbisSection(app, "Money").waitForExistence(timeout: 15))
        thorbisTapStableButton(app, "job-section-money")
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
    /// Paper 24: an invoice's own Collect payment pill, in its card on Money, brought clear of the job's bar.
    private func collectPill(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        let pill = app.buttons["job-invoice-collect-\(id)"]
        XCTAssertTrue(pill.waitForExistence(timeout: 15))
        app.scrollClearOfFoot(pill)
        XCTAssertTrue(pill.isHittable)
        return pill
    }
    private func ready(_ app: XCUIApplication) {
        XCTAssertTrue(thorbisJobBalanceLoaded(app, "$340.00").waitForExistence(timeout: 15))
    }
    private func handToCustomer(_ app: XCUIApplication) {
        app.buttons["Job actions"].tap()
        thorbisCustomerViewMenuItem(app).tap()
        XCTAssertTrue(app.staticTexts["customer-view-title"].waitForExistence(timeout: 10))
    }
}

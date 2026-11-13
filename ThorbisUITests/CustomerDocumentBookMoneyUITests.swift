import XCTest

@MainActor
final class CustomerDocumentBookMoneyUITests: XCTestCase {
    func testInvoiceBookShowsOnlyVerifiedCustomerSummary() {
        let app = openPrimary(extra: ["--paper-preview-customer-safe-invoice"])
        XCTAssertTrue(text("Customer safe service", in: app).waitForExistence(timeout: 15))
        XCTAssertFalse(text("Water heater", in: app).exists)
    }

    func testVerifiedSignedInvoiceKeepsPaymentAction() {
        let app = openPrimary(extra: ["--paper-preview-customer-safe-invoice", "--paper-preview-job-invoice-signed"])
        XCTAssertTrue(text("Customer safe service", in: app).waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Pay $")).firstMatch.waitForExistence(timeout: 15))
    }

    func testVerifiedSummaryHandsBackToCorrectInvoicePayment() {
        let app = openPrimary(extra: ["--paper-preview-customer-safe-invoice", "--paper-preview-job-invoice-signed", "--paper-preview-owner-auth", "approved"])
        let pay = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Pay $340.00")).firstMatch
        XCTAssertTrue(pay.waitForExistence(timeout: 15)); pay.tap()
        let collecting = app.descendants(matching: .any)["collect-payment-invoice"]
        XCTAssertTrue(collecting.waitForExistence(timeout: 15))
        XCTAssertTrue(collecting.label.contains("INV-2209"), collecting.label)
        XCTAssertFalse(collecting.label.contains("INV-2240"), collecting.label)
    }

    func testVerifiedSummaryRefusesPaymentWhenRecheckFails() {
        let app = openPrimary(extra: ["--paper-preview-customer-safe-invoice", "--paper-preview-job-invoice-signed", "--paper-preview-payment-recheck-fails"])
        let pay = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Pay $")).firstMatch
        XCTAssertTrue(pay.waitForExistence(timeout: 15)); pay.tap()
        XCTAssertTrue(app.staticTexts["Payment isn't ready. Ask your technician to check this invoice."].waitForExistence(timeout: 15))
        XCTAssertFalse(app.navigationBars["Collect payment"].exists)
    }

    func testInvoiceBookWithoutSummaryDoesNotShowRawDescriptions() {
        let app = openPrimary(extra: ["--paper-preview-long-document-description"])
        XCTAssertTrue(text("Invoice details aren't available", in: app).waitForExistence(timeout: 15))
        XCTAssertFalse(text("Invoice first paragraph", in: app).exists)
        XCTAssertFalse(app.buttons["Sign for the work"].exists)
    }

    func testVerifiedDraftAndVoidInvoiceBooksUseSafeLines() {
        for flag in ["--paper-preview-job-invoice-draft", "--paper-preview-job-invoice-void"] {
            let app = openPrimary(extra: ["--paper-preview-customer-safe-invoice", flag])
            XCTAssertTrue(text("Customer safe service", in: app).waitForExistence(timeout: 15))
            XCTAssertTrue(text(flag.hasSuffix("draft") ? "Draft total" : "Voided", in: app).exists)
            XCTAssertFalse(app.buttons["Sign for the work"].exists)
            app.terminate()
        }
    }

    func testStandaloneCustomerInvoiceUsesVerifiedSummaryAndCanHandBack() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "present-invoice", "--paper-preview-legacy-handoff-test", "--paper-preview-customer-safe-invoice"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Customer safe service"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Customer summary · not the signed invoice"].exists)
        XCTAssertTrue(app.buttons["Done"].exists)
        XCTAssertFalse(app.buttons["Sign for the work"].exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Technician: unlock"].waitForExistence(timeout: 10))
    }

    func testStandaloneLongSummaryOpensReadingDrawer() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "present-invoice", "--paper-preview-legacy-handoff-test", "--paper-preview-customer-safe-invoice", "--paper-preview-customer-summary-long"]
        app.launch()
        let more = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Show more")).firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 15)); more.tap()
        XCTAssertTrue(app.navigationBars["Description"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Final summary detail: leave the work area clean.")).firstMatch.exists)
        XCTAssertFalse(app.textViews.firstMatch.exists)
        app.navigationBars["Description"].buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Customer summary · not the signed invoice"].waitForExistence(timeout: 10))
    }

    func testStandaloneCustomerInvoiceWithoutSummaryDoesNotShowRawLines() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "present-invoice", "--paper-preview-legacy-handoff-test"]
        app.launch()
        let unavailable = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Invoice details aren't available")).firstMatch
        XCTAssertTrue(unavailable.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["Sign for the work"].exists)
    }

    func testOverviewOnlyShowsAmountFromVerifiedSummary() {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job", "--paper-preview-working-job", "--paper-preview-job-documents", "--paper-preview-customer-safe-invoice"]
        app.launch()
        XCTAssertTrue(app.buttons["Job actions"].waitForExistence(timeout: 20)); app.buttons["Job actions"].tap()
        let door = thorbisCustomerViewMenuItem(app); XCTAssertTrue(door.waitForExistence(timeout: 10)); door.tap()
        let invoice = app.buttons["customer-invoice-00000000-0000-4000-8000-000000002209"]
        thorbisRevealInCustomerView(invoice, in: app); XCTAssertTrue(invoice.exists)
        let verified = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "$340.00"), object: invoice)
        XCTAssertEqual(XCTWaiter.wait(for: [verified], timeout: 15), .completed)
    }

    func testOverviewWithNoSummaryDoesNotExposeRawAmount() {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job", "--paper-preview-working-job", "--paper-preview-job-documents"]
        app.launch()
        XCTAssertTrue(app.buttons["Job actions"].waitForExistence(timeout: 20)); app.buttons["Job actions"].tap()
        let door = thorbisCustomerViewMenuItem(app); XCTAssertTrue(door.waitForExistence(timeout: 10)); door.tap()
        let invoice = app.buttons["customer-invoice-00000000-0000-4000-8000-000000002209"]
        thorbisRevealInCustomerView(invoice, in: app); XCTAssertTrue(invoice.exists)
        XCTAssertTrue(invoice.label.contains("Open to check amount"))
        XCTAssertFalse(invoice.label.contains("$340.00"))
    }

    func testMixedCurrencyInvoiceDoesNotShowMisleadingOverviewAmount() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job", "--paper-preview-working-job", "--paper-preview-job-documents", "--paper-preview-job-documents-money", "--paper-preview-job-invoice-mixed-currency"]
        app.launch()
        let actions = app.buttons["Job actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 20)); actions.tap()
        let door = thorbisCustomerViewMenuItem(app)
        XCTAssertTrue(door.waitForExistence(timeout: 10)); door.tap()
        let invoice = app.buttons["customer-invoice-00000000-0000-4000-8000-000000002209"]
        XCTAssertTrue(invoice.waitForExistence(timeout: 20)); thorbisRevealInCustomerView(invoice, in: app)
        XCTAssertTrue(invoice.label.contains("Amount needs verification"))
        XCTAssertFalse(invoice.label.contains("$300.00"))
        invoice.tap()
        XCTAssertTrue(app.staticTexts["These amounts couldn't be verified. Hand the device back to your technician."].waitForExistence(timeout: 20))
    }

    func testPartPaidInvoiceOverviewDoesNotSayUnpaid() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job", "--paper-preview-working-job", "--paper-preview-job-documents", "--paper-preview-job-documents-money"]
        app.launch()
        XCTAssertTrue(app.buttons["Job actions"].waitForExistence(timeout: 20)); app.buttons["Job actions"].tap()
        let door = thorbisCustomerViewMenuItem(app); XCTAssertTrue(door.waitForExistence(timeout: 10)); door.tap()
        let invoice = app.buttons["customer-invoice-00000000-0000-4000-8000-000000002209"]
        XCTAssertTrue(invoice.waitForExistence(timeout: 20)); thorbisRevealInCustomerView(invoice, in: app)
        XCTAssertTrue(invoice.label.contains("$150.00"))
        XCTAssertTrue(invoice.label.contains("Issued"), invoice.label)
        XCTAssertFalse(invoice.label.contains("Unpaid"), invoice.label)
        invoice.tap()
        XCTAssertTrue(app.staticTexts["customer-invoice-summary"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Issued")).firstMatch.exists)
    }
    func testInvoiceOverviewAtNormalText() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job", "--paper-preview-working-job", "--paper-preview-job-documents", "--paper-preview-job-documents-money"]
        app.launch()
        XCTAssertTrue(app.buttons["Job actions"].waitForExistence(timeout: 20)); app.buttons["Job actions"].tap()
        let door = thorbisCustomerViewMenuItem(app); XCTAssertTrue(door.waitForExistence(timeout: 10)); door.tap()
        let invoice = app.buttons["customer-invoice-00000000-0000-4000-8000-000000002209"]
        XCTAssertTrue(invoice.waitForExistence(timeout: 20)); thorbisRevealInCustomerView(invoice, in: app)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Invoice overview normal text"; shot.lifetime = .keepAlways; add(shot)
        XCTAssertTrue(invoice.isHittable); invoice.tap()
        XCTAssertTrue(app.staticTexts["customer-invoice-summary"].waitForExistence(timeout: 20))
    }
    func testInvoiceOverviewAtLargestText() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job", "--paper-preview-working-job", "--paper-preview-job-documents", "--paper-preview-job-documents-money", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["Job actions"].waitForExistence(timeout: 20)); app.buttons["Job actions"].tap()
        let door = thorbisCustomerViewMenuItem(app); XCTAssertTrue(door.waitForExistence(timeout: 10)); door.tap()
        let invoice = app.buttons["customer-invoice-00000000-0000-4000-8000-000000002209"]
        XCTAssertTrue(invoice.waitForExistence(timeout: 20)); thorbisRevealInCustomerView(invoice, in: app)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Invoice overview largest text"; shot.lifetime = .keepAlways; add(shot)
        XCTAssertTrue(invoice.isHittable); invoice.tap()
        XCTAssertTrue(app.staticTexts["customer-invoice-summary"].waitForExistence(timeout: 20))
    }
    func testPayExplainsWhenFreshPaymentHistoryCannotBeVerified() {
        let app = openPrimary(extra: ["--paper-preview-job-documents-money", "--paper-preview-job-invoice-signed", "--paper-preview-payment-recheck-fails"])
        let pay = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Pay $")).firstMatch
        XCTAssertTrue(pay.waitForExistence(timeout: 20)); pay.tap()
        let message = app.staticTexts["Payment isn't ready. Ask your technician to check this invoice."]
        XCTAssertTrue(message.waitForExistence(timeout: 20))
        XCTAssertFalse(app.navigationBars["Collect payment"].exists)
        app.buttons["Choose a job document"].tap()
        app.buttons["INV-2240"].tap()
        XCTAssertTrue(app.navigationBars["INV-2240"].waitForExistence(timeout: 10))
        XCTAssertFalse(message.exists, "A payment warning must not follow the customer to another invoice")
    }

    func testPayCannotLeaveCustomerViewAfterAuthorityIsRetiredDuringUnlock() {
        let app = openPrimary(extra: ["--paper-preview-job-invoice-signed", "--paper-preview-owner-auth", "approved", "--paper-preview-payment-retire-on-unlock"])
        let pay = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Pay $")).firstMatch
        XCTAssertTrue(pay.waitForExistence(timeout: 20)); pay.tap()
        XCTAssertTrue(app.staticTexts["This document isn’t available any more"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.navigationBars["Collect payment"].exists)
        XCTAssertFalse(app.buttons["Job actions"].isHittable)
    }
    func testLongInvoiceDescriptionOpensReadOnlyAndReturnsToInvoice() {
        let app = openPrimary(extra: ["--paper-preview-long-document-description", "--paper-preview-job-invoice-signed"])
        let more = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Show more")).firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5)); more.tap()
        XCTAssertTrue(app.navigationBars["Description"].waitForExistence(timeout: 5))
        XCTAssertTrue(text("Final invoice detail: leave the site clean.", in: app).exists)
        XCTAssertFalse(app.textViews.firstMatch.exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["customer-invoice-summary"].waitForExistence(timeout: 5))
        assertMoneyRow("Total", "$340.00", in: app)
    }

    func testDiscountRefundAndCashStayWithTheirInvoiceWhenPaging() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job", "--paper-preview-working-job",
                               "--paper-preview-job-documents", "--paper-preview-job-documents-money", "--paper-preview-job-invoice-signed"]
        app.launch()
        XCTAssertTrue(app.buttons["Job actions"].waitForExistence(timeout: 15))
        app.buttons["Job actions"].tap()
        thorbisCustomerViewMenuItem(app).tap()
        let primary = app.buttons["customer-invoice-00000000-0000-4000-8000-000000002209"]
        XCTAssertTrue(primary.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["customer-invoice-00000000-0000-4000-8000-000000002241"].exists)
        thorbisRevealInCustomerView(primary, in: app)
        primary.tap()
        XCTAssertTrue(app.staticTexts["customer-invoice-summary"].waitForExistence(timeout: 10))
        assertText("Member discount", in: app)
        assertMoneyRow("Subtotal", "$340.00", in: app)
        assertMoneyRow("Discounts and credits", "$40.00", in: app)
        assertMoneyRow("Total", "$300.00", in: app)
        assertMoneyRow("Paid", "$150.00", in: app)
        assertMoneyRow("Amount due", "$150.00", in: app)
        XCTAssertFalse(text("Paid in full", in: app).exists)
        // A short payment history is visible without requiring a second tap.
        assertText("Card", in: app)
        let expanded = XCTAttachment(screenshot: app.screenshot())
        expanded.name = "Payment history visible by default"
        expanded.lifetime = .keepAlways
        add(expanded)
        let history = app.buttons["customer-payment-history"]
        reveal(history, in: app)
        XCTAssertTrue(history.isHittable)
        history.tap()
        XCTAssertFalse(text("Card", in: app).exists)
        let collapsed = XCTAttachment(screenshot: app.screenshot())
        collapsed.name = "Payment history collapsed by customer"
        collapsed.lifetime = .keepAlways
        add(collapsed)
        history.tap()
        assertText("Card", in: app)
        assertText("Refunded $50.00", in: app)
        assertText("Received after refund $100.00", in: app)
        assertText("Oct 27, 2026", in: app)
        assertText("Oct 28, 2026", in: app)
        assertText("Cash", in: app)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Job invoice discount and dated refund history"
        shot.lifetime = .keepAlways
        add(shot)

        app.buttons["Choose a job document"].tap()
        app.buttons["INV-2240"].tap()
        XCTAssertTrue(app.staticTexts["Deposit invoice"].waitForExistence(timeout: 10))
        assertText("Paid in full", in: app)
        assertMoneyRow("Total", "$340.00", in: app)
        assertMoneyRow("Paid", "$340.00", in: app)
        assertMoneyRow("Amount due", "$0.00", in: app)
        openHistory(in: app)
        assertText("Card", in: app)
        XCTAssertFalse(text("Member discount", in: app).exists)
        XCTAssertFalse(text("Refunded $50.00", in: app).exists)
        XCTAssertFalse(text("Received after refund $100.00", in: app).exists)
        XCTAssertFalse(text("Cash", in: app).exists)
        XCTAssertFalse(text("INV-2241", in: app).exists)

        app.buttons["Choose a job document"].tap()
        app.buttons["INV-2209"].tap()
        XCTAssertEqual(app.staticTexts["customer-document-position"].label, "4 of 4 documents")
        openHistory(in: app)
        assertText("Refunded $50.00", in: app)
        assertText("Cash", in: app)
    }

    func testDocumentPickerKeepsInvoiceIdentityAndAmountInSync() {
        let app = openPrimary(extra: ["--paper-preview-job-documents-money", "--paper-preview-job-invoice-signed"])
        for _ in 0..<3 {
            app.buttons["Choose a job document"].tap()
            app.buttons["INV-2240"].tap()
            XCTAssertTrue(app.navigationBars["INV-2240"].waitForExistence(timeout: 10))
            assertText("Deposit invoice", in: app)
            assertMoneyRow("Amount due", "$0.00", in: app)
            XCTAssertEqual(app.staticTexts["customer-document-position"].label, "3 of 4 documents")
            app.buttons["Choose a job document"].tap()
            app.buttons["INV-2209"].tap()
            XCTAssertTrue(app.navigationBars["INV-2209"].waitForExistence(timeout: 10))
            assertText("Member discount", in: app)
            assertMoneyRow("Amount due", "$150.00", in: app)
            XCTAssertEqual(app.staticTexts["customer-document-position"].label, "4 of 4 documents")
        }
    }

    func testLongPaymentHistoryStartsCollapsedAndCanBeOpened() {
        let app = openPrimary(extra: ["--paper-preview-job-documents-money", "--paper-preview-job-payments-many", "--paper-preview-job-invoice-signed"])
        let history = app.buttons["customer-payment-history"]
        reveal(history, in: app)
        XCTAssertTrue(history.isHittable)
        XCTAssertFalse(text("Card", in: app).exists)
        history.tap()
        assertText("Card", in: app)
        assertText("Refunded $50.00", in: app)
    }

    func testFailedPaymentHistoryCanRetryAndShowShortHistory() {
        let app = openPrimary(extra: ["--paper-preview-job-documents-money", "--paper-preview-job-history-fail-once", "--paper-preview-job-invoice-signed"])
        app.buttons["Choose a job document"].tap()
        app.buttons["INV-2240"].tap()
        XCTAssertTrue(app.navigationBars["INV-2240"].waitForExistence(timeout: 10))
        assertText("Payments couldn't be loaded", in: app)
        let retry = pages(app).buttons["Try again"]
        reveal(retry, in: app)
        XCTAssertTrue(retry.isHittable)
        retry.tap()
        assertText("Card", in: app)
        assertMoneyRow("Paid", "$340.00", in: app)
    }

    func testCollapsedHistoryStaysCollapsedAfterRefresh() {
        let app = openPrimary(extra: ["--paper-preview-job-documents-money", "--paper-preview-job-history-mismatch-once", "--paper-preview-job-invoice-signed"])
        app.buttons["Choose a job document"].tap()
        app.buttons["INV-2240"].tap()
        XCTAssertTrue(app.navigationBars["INV-2240"].waitForExistence(timeout: 10))
        assertText("Payments are still updating", in: app)
        let history = app.buttons["customer-payment-history"]
        reveal(history, in: app)
        XCTAssertTrue(history.isHittable)
        XCTAssertTrue(text("Card", in: app).exists)
        history.tap()
        XCTAssertFalse(text("Card", in: app).exists)
        let refresh = pages(app).buttons["Refresh payments"]
        reveal(refresh, in: app)
        XCTAssertTrue(refresh.isHittable)
        refresh.tap()
        let cleared = NSPredicate(format: "exists == false")
        expectation(for: cleared, evaluatedWith: refresh)
        waitForExpectations(timeout: 10)
        reveal(history, in: app)
        XCTAssertFalse(text("Card", in: app).exists)
        history.tap()
        assertText("Card", in: app)
    }

    func testDraftInvoiceShowsDraftTotalRatherThanAClaimOfPayment() {
        let app = openPrimary(extra: ["--paper-preview-job-invoice-draft"])
        assertText("Draft total", in: app)
        XCTAssertFalse(text("Paid in full", in: app).exists)
        assertMoneyRow("Total", "$340.00", in: app)
    }

    func testZeroDollarInvoiceDoesNotClaimPayment() {
        let app = openPrimary(extra: ["--paper-preview-job-invoice-zero"])
        assertText("No balance due", in: app)
        XCTAssertFalse(text("Paid in full", in: app).exists)
        assertMoneyRow("Total", "$0.00", in: app)
        assertMoneyRow("Amount due", "$0.00", in: app)
    }

    func testUnavailablePaymentHistoryDoesNotClaimPaidInFull() {
        let app = openPrimary(extra: ["--paper-preview-deposit-history-failure"])
        app.buttons["Choose a job document"].tap(); app.buttons["INV-2240"].tap()
        XCTAssertTrue(app.staticTexts["Deposit invoice"].waitForExistence(timeout: 10))
        assertText("Payments couldn't be loaded", in: app)
        assertText("Try again to see payment history", in: app)
        XCTAssertFalse(text("The invoice's paid amount is shown above", in: app).exists)
        assertText("No balance due", in: app)
        XCTAssertFalse(text("Paid in full", in: app).exists)
        assertMoneyRow("Paid", "$340.00", in: app)
    }

    private func openPrimary(extra: [String]) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job", "--paper-preview-working-job", "--paper-preview-job-documents"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["Job actions"].waitForExistence(timeout: 15))
        app.buttons["Job actions"].tap()
        let customerView = thorbisCustomerViewMenuItem(app)
        XCTAssertTrue(customerView.waitForExistence(timeout: 10))
        customerView.tap()
        let invoice = app.buttons["customer-invoice-00000000-0000-4000-8000-000000002209"]
        thorbisRevealInCustomerView(invoice, in: app); invoice.tap()
        XCTAssertTrue(app.staticTexts["customer-invoice-summary"].waitForExistence(timeout: 10))
        return app
    }

    /// The customer's document pages. The staff job screen stays in the accessibility tree under
    /// Customer view, and since #189 it lists the invoice's lines ("On the invoice"), so every check
    /// here reads the document being shown, not the screen behind it.
    private func pages(_ app: XCUIApplication) -> XCUIElement {
        app.collectionViews["customer-document-pages"]
    }

    private func text(_ value: String, in app: XCUIApplication) -> XCUIElement {
        pages(app).staticTexts.matching(NSPredicate(format: "label CONTAINS %@", value)).firstMatch
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists, "Expected accessible content", file: file, line: line)
    }

    private func assertText(_ value: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let element = text(value, in: app)
        reveal(element, in: app, file: file, line: line)
        XCTAssertTrue(element.exists, "Missing \(value)", file: file, line: line)
    }

    private func assertMoneyRow(_ title: String, _ amount: String, in app: XCUIApplication,
                                file: StaticString = #filePath, line: UInt = #line) {
        let row = pages(app).staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", title, amount)).firstMatch
        reveal(row, in: app, file: file, line: line)
        XCTAssertTrue(row.exists, "Missing \(title) \(amount)", file: file, line: line)
    }

    private func openHistory(in app: XCUIApplication) {
        let history = app.buttons["customer-payment-history"]
        reveal(history, in: app)
        if !text("Card", in: app).exists { history.tap() }
    }
}

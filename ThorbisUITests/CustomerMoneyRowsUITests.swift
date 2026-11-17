import XCTest

@MainActor
final class CustomerMoneyRowsUITests: XCTestCase {
    func testPartPaidInvoiceRemainsClearAndOpensAtLargestText() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customer-money",
                               "--paper-preview-customer-money-partial",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let invoice = app.buttons["customer-invoice-00000000-0000-4000-8000-000000002209"]
        XCTAssertTrue(invoice.waitForExistence(timeout: 30))
        for _ in 0..<15 where !invoice.isHittable { app.swipeUp() }
        XCTAssertTrue(invoice.isHittable)
        XCTAssertTrue(invoice.label.contains("Last known: Part paid"))
        XCTAssertTrue(invoice.label.contains("Last known paid $100.00"))
        XCTAssertTrue(invoice.label.contains("$340.00"))
        XCTAssertTrue(invoice.label.contains("Last known total"))
        invoice.tap()
        let title = app.staticTexts["invoice-detail-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertTrue(title.label.contains("2209"))
        let payment = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Card", "$100.00")).firstMatch
        for _ in 0..<10 where !payment.exists { app.swipeUp() }
        XCTAssertTrue(payment.waitForExistence(timeout: 10), "The invoice must show the recorded $100 payment")
        XCTAssertTrue(payment.label.contains("Received"))
        app.navigationBars.buttons["Back"].tap()
        XCTAssertTrue(invoice.waitForExistence(timeout: 10))
    }

    func testMoneyLoadsWhenJobMediaDoesNotRespond() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "--paper-preview", "--paper-preview-screen", "customer-money",
            "--paper-preview-hold-path", "/v1/jobs/00000000-0000-4000-8000-000000002214/media"
        ]
        app.launch()
        let estimate = app.buttons["customer-estimate-00000000-0000-4000-8000-000000002218"]
        XCTAssertTrue(estimate.waitForExistence(timeout: 45),
                      "Customer Money must not wait for unrelated job media")
        let invoice = app.buttons["customer-invoice-00000000-0000-4000-8000-000000002209"]
        for _ in 0..<10 where !invoice.exists { app.swipeUp() }
        XCTAssertTrue(invoice.waitForExistence(timeout: 10),
                      "Invoices remain available while job media is stalled")
    }

    func testMoneyShowsDocumentIdentityStatusAndInvoiceTotal() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customer-money"]
        app.launch()
        let estimate = app.buttons["customer-estimate-00000000-0000-4000-8000-000000002218"]
        XCTAssertTrue(estimate.waitForExistence(timeout: 30))
        XCTAssertTrue(estimate.label.contains("EST-2218"))
        XCTAssertTrue(estimate.label.contains("Sent"))
        XCTAssertTrue(estimate.label.contains("option"))
        let invoice = app.buttons["customer-invoice-00000000-0000-4000-8000-000000002209"]
        for _ in 0..<8 where !invoice.exists { app.swipeUp() }
        XCTAssertTrue(invoice.waitForExistence(timeout: 10))
        XCTAssertTrue(invoice.label.contains("INV-2209"))
        XCTAssertTrue(invoice.label.contains("Last known: Unpaid"))
        XCTAssertTrue(invoice.label.contains("Last known total"))
        XCTAssertTrue(invoice.label.contains("340.00"))

        for _ in 0..<8 where !estimate.isHittable { app.swipeDown() }
        XCTAssertTrue(estimate.isHittable)
        estimate.tap()
        XCTAssertTrue(app.staticTexts["Estimate 2218"].waitForExistence(timeout: 10))
        app.navigationBars.buttons["Back"].tap()
        XCTAssertTrue(invoice.waitForExistence(timeout: 10))
        for _ in 0..<8 where !invoice.isHittable { app.swipeUp() }
        XCTAssertTrue(invoice.isHittable)
        invoice.tap()
        XCTAssertTrue(app.staticTexts["invoice-detail-title"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["invoice-detail-title"].label.contains("2209"))
        app.navigationBars.buttons["Back"].tap()
        XCTAssertTrue(estimate.waitForExistence(timeout: 10))
    }
}

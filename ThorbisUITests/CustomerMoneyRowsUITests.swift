import XCTest

@MainActor
final class CustomerMoneyRowsUITests: XCTestCase {
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
        XCTAssertTrue(invoice.label.contains("Issued"))
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

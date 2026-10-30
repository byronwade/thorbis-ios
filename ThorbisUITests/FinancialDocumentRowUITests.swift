import XCTest

@MainActor
final class FinancialDocumentRowUITests: XCTestCase {
    func testLongCustomerAndLargeInvoiceRemainAccessibleAndOpen() {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoices",
                               "--paper-preview-large-invoice", "--paper-preview-customer-name-long"]
        app.launch()
        let invoice = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@",
            "Birch Community Hall", "$1,234,787.89")).firstMatch
        XCTAssertTrue(invoice.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(invoice.isHittable)
        invoice.tap()
        XCTAssertTrue(app.navigationBars["Invoice"].waitForExistence(timeout: 10), app.debugDescription)
    }
}

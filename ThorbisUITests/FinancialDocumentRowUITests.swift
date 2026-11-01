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
        // Since #216 the invoice is a money room: its title ("Invoice 2209") is in the page, not the bar.
        let title = app.staticTexts["invoice-detail-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(title.label, "Invoice 2209")
    }
}

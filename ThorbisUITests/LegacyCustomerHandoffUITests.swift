import XCTest

@MainActor
final class LegacyCustomerHandoffUITests: XCTestCase {
    func testJobLinkedInvoiceInSheetReturnsToExactInvoicePayment() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-detail", "--paper-preview-working-job", "--paper-preview-legacy-handoff-test", "--paper-preview-job-linked-invoice", "--paper-preview-job-documents", "--paper-preview-job-invoice-signed", "--paper-preview-owner-auth", "approved"]
        app.launch()
        let menu = app.buttons["Customer view, edit or open the PDF"]
        XCTAssertTrue(menu.waitForExistence(timeout: 30)); menu.tap()
        let show = app.buttons["Customer view"].firstMatch
        XCTAssertTrue(show.waitForExistence(timeout: 10)); show.tap()
        XCTAssertTrue(app.staticTexts["4 of 4 documents"].waitForExistence(timeout: 30))
        let pay = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Pay $")).firstMatch
        XCTAssertTrue(pay.waitForExistence(timeout: 20)); pay.tap()
        XCTAssertTrue(app.navigationBars["Collect payment"].waitForExistence(timeout: 30))
        let invoice = app.descendants(matching: .any)["collect-payment-invoice"]
        XCTAssertTrue(invoice.waitForExistence(timeout: 10))
        XCTAssertTrue(invoice.label.contains("INV-2209"), invoice.label)
    }
    func testInvoiceCustomerViewReturnsToItsSourceAfterAuthentication() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-detail", "--paper-preview-working-job", "--paper-preview-legacy-handoff-test", "--paper-preview-owner-auth", "approved"]
        app.launch()
        let menu = app.buttons["Customer view, edit or open the PDF"]
        XCTAssertTrue(menu.waitForExistence(timeout: 30)); menu.tap()
        let show = app.buttons["Customer view"].firstMatch
        XCTAssertTrue(show.waitForExistence(timeout: 10)); show.tap()
        let lock = app.buttons["lock"]
        XCTAssertTrue(lock.waitForExistence(timeout: 20)); lock.tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 20))
        XCTAssertTrue(menu.isHittable, "Authenticated handback should return to the original invoice")
    }
    func testCustomerDetailsRemainProtectedAfterSessionReplacement() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customer", "--paper-preview-legacy-handoff-test"]
        app.launch()
        let menu = app.buttons["Customer actions"]
        XCTAssertTrue(menu.waitForExistence(timeout: 30)); menu.tap()
        let show = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Customer view")).firstMatch
        XCTAssertTrue(show.waitForExistence(timeout: 10)); show.tap()
        XCTAssertTrue(app.buttons["lock"].waitForExistence(timeout: 20))
        let replace = app.buttons["preview-replace-session"]
        XCTAssertTrue(replace.waitForExistence(timeout: 5)); replace.tap()
        XCTAssertTrue(app.staticTexts["Please hand the device back to your technician."].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["Customer actions"].isHittable)
    }
    func testInvoiceCustomerViewRemainsProtectedAfterSessionReplacement() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-detail", "--paper-preview-working-job", "--paper-preview-legacy-handoff-test"]
        app.launch()
        let menu = app.buttons["Customer view, edit or open the PDF"]
        XCTAssertTrue(menu.waitForExistence(timeout: 30)); menu.tap()
        let show = app.buttons["Customer view"].firstMatch
        XCTAssertTrue(show.waitForExistence(timeout: 10)); show.tap()
        XCTAssertTrue(app.buttons["lock"].waitForExistence(timeout: 20))
        let replace = app.buttons["preview-replace-session"]
        XCTAssertTrue(replace.waitForExistence(timeout: 5)); replace.tap()
        XCTAssertTrue(app.staticTexts["Please hand the device back to your technician."].waitForExistence(timeout: 20), "The customer view must remain protected after a session replacement")
        XCTAssertFalse(app.buttons["Collect payment"].isHittable)
    }
}

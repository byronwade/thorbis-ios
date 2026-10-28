import XCTest

@MainActor
final class InvoicePaymentUITests: XCTestCase {
    func testReceivedPaymentMenuKeepsBankAndCardChoicesAndDirectCashCheck() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-payment"]
        app.launch()
        let menu = app.buttons["received-payment-methods"]
        XCTAssertTrue(menu.waitForExistence(timeout: 15))
        XCTAssertTrue(button("Check", in: app).exists)
        XCTAssertTrue(button("Cash", in: app).exists)
        menu.tap()
        let bank = app.buttons["Bank transfer (ACH) received"]
        let card = app.buttons["Card collected elsewhere"]
        XCTAssertTrue(bank.waitForExistence(timeout: 3))
        XCTAssertTrue(card.exists)
        bank.tap()
        let recordBank = button("Record $340.00 bank transfer received", in: app)
        XCTAssertTrue(recordBank.waitForExistence(timeout: 3))
        XCTAssertTrue(recordBank.isEnabled)
        capture(app, "Bank transfer received")
        recordBank.tap()
        XCTAssertTrue(app.staticTexts["Confirm bank transfer received"].waitForExistence(timeout: 3))
        // iOS 26 presents this as a popover; its outside-dismiss region replaces Cancel.
        if app.buttons["Cancel"].exists {
            app.buttons["Cancel"].tap()
        } else {
            app.otherElements["PopoverDismissRegion"].tap()
        }
        menu.tap()
        app.buttons["Card collected elsewhere"].tap()
        XCTAssertTrue(button("Record $340.00 card payment received", in: app).waitForExistence(timeout: 3))
        capture(app, "Card collected elsewhere")
    }

    private func button(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

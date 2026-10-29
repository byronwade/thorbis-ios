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

    func testLargestTextBankConfirmationKeepsActionsReachable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-payment",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let menu = app.buttons["received-payment-methods"]
        XCTAssertTrue(menu.waitForExistence(timeout: 15))
        for _ in 0..<5 where !menu.isHittable { app.swipeUp() }
        XCTAssertTrue(menu.isHittable)
        menu.tap()
        let bank = app.buttons["Bank transfer (ACH) received"]
        XCTAssertTrue(bank.waitForExistence(timeout: 10))
        XCTAssertTrue(bank.isHittable)
        bank.tap()
        let record = button("Record $340.00 bank transfer received", in: app)
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        for _ in 0..<5 where !record.isHittable { app.swipeUp() }
        XCTAssertTrue(record.isHittable)
        record.tap()
        XCTAssertTrue(app.staticTexts["Confirm bank transfer received"].waitForExistence(timeout: 10))
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        XCTAssertTrue(cancel.isHittable)
        let confirm = button("Record $340.00 bank transfer received", in: app)
        XCTAssertTrue(confirm.exists)
        XCTAssertTrue(confirm.isHittable)
        capture(app, "Accessible bank transfer confirmation")
        cancel.tap()
    }

    func testReadyLinkShowsScannableCheckoutAndDoneReturnsToInvoice() {
        continueAfterFailure = false
        let app = linkPreview()
        let code = app.images["invoice-payment-qr"]
        XCTAssertTrue(code.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["share-invoice-payment-link"].exists)
        app.buttons["Copy link"].tap()
        XCTAssertTrue(app.buttons["Link copied"].waitForExistence(timeout: 3))
        app.buttons["check-invoice-payment-status"].tap()
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Invoice paid"].exists)
        capture(app, "Invoice scan to pay")
        app.buttons["Done"].tap()
        XCTAssertTrue(code.waitForNonExistence(timeout: 5))
        XCTAssertTrue(button("Collect payment", in: app).waitForExistence(timeout: 5))
    }

    func testLargestTextAndDarkModeKeepSharingReachable() {
        continueAfterFailure = false
        let app = linkPreview(accessibleText: true)
        let code = app.images["invoice-payment-qr"]
        XCTAssertTrue(code.waitForExistence(timeout: 15))
        capture(app, "Scan to pay with accessible text")
        let share = app.buttons["share-invoice-payment-link"]
        let content = app.scrollViews.containing(.image, identifier: "invoice-payment-qr").firstMatch
        for _ in 0..<5 where !share.isHittable { content.swipeUp() }
        XCTAssertTrue(share.isHittable)
        XCTAssertTrue(app.buttons["Done"].isHittable)
        capture(app, "Accessible payment sharing")
    }

    func testExpiredLinkOffersRecoveryWithoutAnActiveQRCodeOrShare() {
        continueAfterFailure = false
        let app = linkPreview(expired: true)
        XCTAssertTrue(app.staticTexts["Payment link expired"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.images["invoice-payment-qr"].exists)
        XCTAssertFalse(app.buttons["share-invoice-payment-link"].exists)
        XCTAssertTrue(app.buttons["Create new payment link"].isEnabled)
        capture(app, "Expired payment link recovery")
    }

    private func linkPreview(expired: Bool = false, accessibleText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-payment",
                               "--paper-preview-pay-link", expired ? "expired" : "ready"]
        if accessibleText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
                                    "-thorbis.appearance", "dark"]
        }
        app.launch()
        return app
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

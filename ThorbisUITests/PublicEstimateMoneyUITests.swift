import XCTest

final class PublicEstimateMoneyUITests: XCTestCase {
    private func open(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "public-estimate"] + extra
        app.launch()
        return app
    }

    func testIssuedMinorUnitsAreShownAsDollarsInOptionsAndApproval() {
        let app = open()
        let total = app.staticTexts.matching(NSPredicate(format: "identifier == %@ AND label == %@", "public-estimate-total", "$1,575.00")).firstMatch
        XCTAssertTrue(total.waitForExistence(timeout: 15))
        let option = app.buttons["estimate-option-00000000-0000-4000-8000-000000000102"]
        XCTAssertTrue(option.waitForExistence(timeout: 10))
        if !option.isHittable { app.swipeUp() }
        option.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "$4,850.00")).firstMatch.waitForExistence(timeout: 5))
    }

    func testDiscountIsShownInMinorUnits() {
        let app = open(["--paper-preview-public-estimate-discount"])
        let total = app.staticTexts.matching(NSPredicate(format: "identifier == %@ AND label == %@", "public-estimate-total", "$95.00")).firstMatch
        XCTAssertTrue(total.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "-$5.00")).firstMatch.waitForExistence(timeout: 5))
    }
    func testUnsupportedCurrencyBlocksApprovalWithExplanation() {
        let app = open(["--paper-preview-public-estimate-unsupported-currency"])
        let approval = app.buttons.matching(NSPredicate(format: "label == %@", "Amount unavailable")).firstMatch
        XCTAssertTrue(approval.waitForExistence(timeout: 15))
        XCTAssertFalse(approval.isEnabled)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "can’t verify the estimate amount")).firstMatch.exists)
    }

    func testPlainApprovalShowsAmountProblemAndStaysDisabled() {
        let app = open(["--paper-preview-public-estimate-discount", "--paper-preview-public-estimate-unsupported-currency"])
        let approval = app.buttons.matching(NSPredicate(format: "label == %@", "Amount unavailable")).firstMatch
        XCTAssertTrue(approval.waitForExistence(timeout: 15))
        XCTAssertFalse(approval.isEnabled)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "can’t verify the estimate amount")).firstMatch.exists)
    }

}

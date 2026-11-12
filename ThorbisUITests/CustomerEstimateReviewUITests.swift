import XCTest

@MainActor
final class CustomerEstimateReviewUITests: XCTestCase {
    func testLongOptionDescriptionCanBeReadWithoutSelectingIt() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "present-estimate", "--paper-preview-option-long-description"]
        app.launch()
        let choice = app.buttons["Choose Repair"]
        XCTAssertTrue(choice.waitForExistence(timeout: 30))
        let more = app.buttons["Show more, Repair option"]
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(more.frame.height, 56)
        more.tap()
        XCTAssertTrue(app.navigationBars["Description"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Final detail: we will explain the results")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        choice.tap()
        XCTAssertTrue(app.buttons["Repair, selected"].waitForExistence(timeout: 5))
    }

    func testLongOptionReaderAtLargestText() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "present-estimate", "--paper-preview-option-long-description", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let more = app.buttons["Show more, Repair option"]
        for _ in 0..<8 where !more.exists { app.swipeUp() }
        XCTAssertTrue(more.waitForExistence(timeout: 20))
        for _ in 0..<8 where !more.isHittable { app.swipeUp() }
        XCTAssertTrue(more.isHittable)
        XCTAssertGreaterThanOrEqual(more.frame.height, 56)
        more.tap()
        XCTAssertTrue(app.navigationBars["Description"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Final detail: we will explain the results")).firstMatch.waitForExistence(timeout: 5))
    }

    func testOptionDescriptionClosesWhenSessionIsReplaced() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "present-estimate", "--paper-preview-option-long-description", "--paper-preview-description-replace-session"]
        app.launch()
        let more = app.buttons["Show more, Repair option"]
        XCTAssertTrue(more.waitForExistence(timeout: 30))
        more.tap()
        let reader = app.navigationBars["Description"]
        XCTAssertTrue(reader.waitForExistence(timeout: 10))
        XCTAssertTrue(reader.waitForNonExistence(timeout: 30))
    }

    func testOptionDescriptionDisappearsWhenSessionExpires() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "present-estimate", "--paper-preview-option-long-description", "--paper-preview-description-expire-session"]
        app.launch()
        let more = app.buttons["Show more, Repair option"]
        XCTAssertTrue(more.waitForExistence(timeout: 30))
        more.tap()
        let reader = app.navigationBars["Description"]
        XCTAssertTrue(reader.waitForExistence(timeout: 10))
        XCTAssertTrue(reader.waitForNonExistence(timeout: 30))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Final detail: we will explain the results")).firstMatch.exists)
    }

    func testOpeningCannotApproveCallerTermsBeforeServerReadCompletes() {
        let app = preview(extra: ["--paper-preview-review-pending"])
        XCTAssertTrue(app.descendants(matching: .any)["customer-estimate-opening"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Approve")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts["You're approving"].exists)
        XCTAssertTrue(app.buttons["Not today"].exists)
        capture(app, "Opening the canonical estimate")
    }

    func testReviewShowsCanonicalChoiceDescriptionAndPrice() {
        let app = preview(extra: ["--paper-preview-canonical-estimate"])
        XCTAssertTrue(app.staticTexts["Reviewed protection"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Verified surge protection"].exists)
        XCTAssertTrue(approveButton(app, total: "$543.21").exists)
        XCTAssertFalse(app.staticTexts["Surge protector, installed"].exists)
        capture(app, "Canonical customer estimate review")
    }

    func testFailedOpeningCanRetryWithoutApprovingStaleTerms() {
        let app = preview(extra: ["--paper-preview-canonical-estimate", "--paper-preview-review-failure"])
        let retry = app.buttons["Try again"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Approve")).firstMatch.exists)
        XCTAssertTrue(app.buttons["Not today"].exists)
        capture(app, "Estimate opening recovery")
        app.buttons["Restore sample connection"].tap()
        retry.tap()
        XCTAssertTrue(app.staticTexts["Reviewed protection"].waitForExistence(timeout: 10))
        XCTAssertTrue(approveButton(app, total: "$543.21").exists)
    }

    /// #161: the commit names the chosen option ("Approve Reviewed protection · $543.21", or
    /// "Approve · $543.21" when that doesn't fit). The exact total stays required.
    private func approveButton(_ app: XCUIApplication, total: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label ENDSWITH %@", "Approve", "· " + total)).firstMatch
    }

    private func preview(extra: [String]) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "present-estimate-review"] + extra
        app.launch()
        return app
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let proof = XCTAttachment(screenshot: app.screenshot())
        proof.name = name
        proof.lifetime = .keepAlways
        add(proof)
    }
}

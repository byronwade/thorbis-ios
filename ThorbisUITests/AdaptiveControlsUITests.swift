import XCTest

@MainActor
final class AdaptiveControlsUITests: XCTestCase {
    func testLongSegmentedChoicesRemainReadableAndSelectableAtLargestText() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "new-customer",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let residential = app.buttons["Residential"]
        let commercial = app.buttons["Commercial"]
        XCTAssertTrue(residential.waitForExistence(timeout: 30))
        let form = app.scrollViews.containing(.button, identifier: "Residential").firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 10))
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        done.tap()
        XCTAssertFalse(app.keyboards.firstMatch.exists, "Dismiss the keyboard before navigating the form.")
        for _ in 0..<10 where !commercial.isHittable { form.swipeUp() }
        XCTAssertTrue(commercial.isHittable, app.debugDescription)
        capture("New customer choices, large text")
        XCTAssertGreaterThanOrEqual(commercial.frame.width, 44)
        XCTAssertGreaterThanOrEqual(commercial.frame.height, 44)
        XCTAssertGreaterThanOrEqual(commercial.frame.minY, residential.frame.maxY,
                                    "Long choices must have enough room to be read at accessibility sizes.")
        commercial.tap()
        XCTAssertTrue(commercial.isSelected)
        for _ in 0..<6 where !residential.isHittable { form.swipeDown() }
        XCTAssertTrue(residential.isHittable)
        residential.tap()
        XCTAssertTrue(residential.isSelected)
    }

    func testLongSignOutWarningAndCancelRemainReachableAtLargestText() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "settings", "--paper-preview-long-confirmation",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let signOut = app.buttons["Sign out"]
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 30))
        for _ in 0..<8 where !signOut.isHittable { app.swipeUp() }
        XCTAssertTrue(signOut.isHittable)
        signOut.tap()
        let warning = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "older saved photos")).firstMatch
        XCTAssertTrue(warning.waitForExistence(timeout: 10))
        capture("Sign-out warning, large text")
        let cancel = app.buttons["Cancel"]
        for _ in 0..<8 where !cancel.isHittable { app.swipeUp() }
        XCTAssertTrue(cancel.isHittable, app.debugDescription)
        capture("Sign-out actions, large text")
        cancel.tap()
        XCTAssertFalse(warning.exists)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

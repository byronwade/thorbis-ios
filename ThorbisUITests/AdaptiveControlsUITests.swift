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
        let dismissStart = form.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.29))
        let dismissEnd = form.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.46))
        dismissStart.press(forDuration: 0.1, thenDragTo: dismissEnd)
        XCTAssertFalse(app.keyboards.firstMatch.exists, "Dismiss the keyboard before navigating the form.")
        // The pinned Save bar is disabled in the read-only preview, and a disabled bar does not
        // block XCUI's hit test: a choice behind it reports hittable while a tap lands on the bar.
        let save = app.buttons["Save customer"]
        func revealed() -> Bool { commercial.isHittable && (!save.exists || commercial.frame.maxY <= save.frame.minY) }
        for _ in 0..<10 where !revealed() { form.swipeUp() }
        XCTAssertTrue(revealed(), app.debugDescription)
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
        let cancel = app.buttons["Cancel"]
        for _ in 0..<8 where !cancel.isHittable { app.swipeUp() }
        XCTAssertTrue(cancel.isHittable, app.debugDescription)
        cancel.tap()
        XCTAssertFalse(warning.exists)
    }
}


@MainActor
final class SetupRecoveryUITests: XCTestCase {
    func testRetryAtAccessibilityTextSize() {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "onboard-setup", "--paper-preview-setup-retry", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let retry = app.buttons["Try again"]
        XCTAssertTrue(retry.waitForExistence(timeout: 20))
        // At this size the banner sits just above the pinned commit, which covers its Try again. A full
        // swipe overshoots it past the top, so scroll in short drags until it is clear of both edges.
        let top = app.frame.height * 0.12, bottom = app.frame.height * 0.62
        for _ in 0..<12 where !retry.isHittable || retry.frame.maxY > bottom {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42)))
        }
        XCTAssertTrue(retry.isHittable)
        XCTAssertGreaterThan(retry.frame.minY, top)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Setup retry at accessibility text size"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        retry.tap()
        let recovered = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND value == %@", "Get paid by card", "Not done")).firstMatch
        XCTAssertTrue(recovered.waitForExistence(timeout: 15))
    }

    func testUnavailableStatusCanBeRetriedWithoutLosingSetupRoutes() {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "onboard-setup", "--paper-preview-setup-retry", "-thorbis.appearance", "dark"]
        app.launch()
        let retry = app.buttons["Try again"]
        XCTAssertTrue(retry.waitForExistence(timeout: 20))
        // #179 set the banner in typographic quotes: "couldn’t".
        XCTAssertTrue(app.staticTexts["Some steps couldn\u{2019}t be checked."].exists)
        let payment = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Get paid by card")).firstMatch
        XCTAssertTrue(payment.exists)
        XCTAssertTrue(payment.value as? String == "Status unavailable")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Setup status unavailable"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        retry.tap()
        XCTAssertTrue(payment.waitForExistence(timeout: 10))
        let recovered = NSPredicate(format: "value == %@", "Not done")
        expectation(for: recovered, evaluatedWith: payment)
        waitForExpectations(timeout: 15)
        XCTAssertFalse(retry.exists)
        payment.tap()
        XCTAssertTrue(app.staticTexts["Card payments and payouts run through Stripe. Stripe holds your bank and identity details; Thorbis never sees them."].waitForExistence(timeout: 15))
    }
}

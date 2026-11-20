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
        // Name focuses on appear, so the keyboard covers Type at accessibility sizes. Do not drag
        // the form: the empty sheet is still interactively dismissible (#460), and a signed run
        // showed form-to-keyboard pans leave the keyboard up. Done (and Hide keyboard on iPad)
        // puts it away without pulling the sheet.
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 5)
        // With the simulator's hardware keyboard connected, focus alone leaves the software keyboard
        // off screen (the keyboard element exists below the window), so there is nothing to cover
        // the form and no Done to show. Typing brings the software keyboard up, as a phone without
        // a hardware keyboard shows it on focus, so Done is still checked over the real keyboard.
        let name = app.textFields["Name"]
        let up = Date().addingTimeInterval(3)
        while !app.keyboardShowing && Date() < up { usleep(200_000) }
        if !app.keyboardShowing, name.exists {
            name.typeText("A")
            name.typeText(XCUIKeyboardKey.delete.rawValue)
        }
        XCTAssertTrue(app.keyboardShowing, "The software keyboard covers the form at this size: \(app.keyboards.firstMatch.frame)")
        XCTAssertTrue(
            app.buttons["keyboard-done"].waitForExistence(timeout: 5)
                || app.keyboards.buttons["Hide keyboard"].waitForExistence(timeout: 1),
            "Done must appear above the keyboard so the form can be used at this size."
        )
        XCTAssertTrue(app.dismissSoftwareKeyboard(from: form), "Dismiss the keyboard before navigating the form.")
        XCTAssertFalse(app.keyboardShowing, "Dismiss the keyboard before navigating the form.")
        // Paper v2 (47A): Save customer sits in the sheet's header, so nothing pinned at the bottom
        // can cover the choice; it only has to be on screen.
        func revealed() -> Bool { commercial.isHittable && app.windows.firstMatch.frame.contains(commercial.frame) }
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
        // Paper 65: Settings is a page with its own back circle and 34 Bold title; the bar is hidden.
        XCTAssertTrue(app.buttons["settings-account-data"].waitForExistence(timeout: 30))
        for _ in 0..<12 where !signOut.isHittable { app.swipeUp() }
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

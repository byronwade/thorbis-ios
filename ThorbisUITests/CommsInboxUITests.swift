import XCTest

/// The Inbox preview: switch to Calls from the title menu, open a caller's thread; and save a text
/// as a draft (it never sends).
@MainActor
final class CommsInboxUITests: XCTestCase {
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "inbox"] + extra
        app.launch()
        return app
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func choose(_ app: XCUIApplication, menu: String, row: String) {
        let button = app.buttons[menu]
        XCTAssertTrue(button.waitForExistence(timeout: 20), app.debugDescription)
        button.tap()
        let item = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND identifier != %@", row, menu)).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), app.debugDescription)
        expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: item)
        waitForExpectations(timeout: 5)
        item.tap()
        // The popover fades out before the choice lands; under load the first tap can be eaten.
        let chosen = NSPredicate(format: "label BEGINSWITH %@", row)
        if !chosen.evaluate(with: app.buttons[menu]) || item.exists {
            _ = item.waitForNonExistence(timeout: 3)
            if !chosen.evaluate(with: app.buttons[menu]), item.exists, item.isHittable { item.tap() }
        }
        expectation(for: chosen, evaluatedWith: app.buttons[menu])
        waitForExpectations(timeout: 10)
    }

    func testSwitchToCallsAndOpenACallersThread() {
        let app = launch()
        choose(app, menu: "inbox-section-menu", row: "Calls")
        let thread = app.buttons["inbox-call-call-thread-5550100100"]
        XCTAssertTrue(thread.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(thread.label.contains("2 calls"), thread.label)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "inbox-row-")).firstMatch.exists,
                       "Calls shows no job notices")
        attach(app, "Inbox calls")
        thread.tap()
        XCTAssertTrue(app.staticTexts["Incoming call"].firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["inbox-play-00000000-0000-4000-8000-000000009702"].exists, "The answered call has a play control")
        XCTAssertTrue(app.buttons["inbox-link-job-00000000-0000-4000-8000-000000009702"].exists, "Office can change the linked job")
        attach(app, "Call thread")
    }

    func testATextIsSavedAsADraftNotSent() {
        let app = launch(["--paper-preview-inbox-thread", "text"])
        let field = app.textViews["inbox-text-field"].exists ? app.textViews["inbox-text-field"] : app.textFields["inbox-text-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 20), app.debugDescription)
        field.tap()
        field.typeText("Running about ten minutes behind")
        XCTAssertTrue(app.staticTexts["32 characters · 1 SMS"].waitForExistence(timeout: 5))
        app.buttons["inbox-save-draft"].tap()
        XCTAssertTrue(app.staticTexts["Running about ten minutes behind"].waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "Draft")).count, 1)
        XCTAssertFalse(app.staticTexts["Sent"].exists)
        attach(app, "Text draft saved")
    }

    /// New text and New email open with the first field ready to type.
    func testComposeSheetsFocusTheirFirstField() {
        for (section, pencil, field) in [("texts", "New text", "inbox-new-text-phone"), ("email", "New email", "inbox-mail-to")] {
            let app = launch(["--paper-preview-inbox-section", section])
            let button = app.buttons[pencil].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 20), app.debugDescription)
            button.tap()
            let input = app.textFields[field]
            XCTAssertTrue(input.waitForExistence(timeout: 10), app.debugDescription)
            expectation(for: NSPredicate(format: "hasKeyboardFocus == true"), evaluatedWith: input)
            waitForExpectations(timeout: 5)
            app.terminate()
        }
    }
}

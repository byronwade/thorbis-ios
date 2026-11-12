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

    func testEmailCloseProtectsChangesAndSavesDraft() {
        let app = launch(["--paper-preview-inbox-section", "email"])
        let compose = app.buttons["New email"].firstMatch
        XCTAssertTrue(compose.waitForExistence(timeout: 20))
        compose.tap()
        let to = app.textFields["inbox-mail-to"]
        XCTAssertTrue(to.waitForExistence(timeout: 10))
        let body = app.textViews["inbox-mail-body"].exists ? app.textViews["inbox-mail-body"] : app.textFields["inbox-mail-body"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        body.tap()
        body.typeText("Checking your appointment")
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Add a recipient to save this draft, or keep editing."].waitForExistence(timeout: 5))
        app.buttons["Keep editing"].tap()
        to.tap()
        to.typeText("customer@example.com")
        XCTAssertTrue(app.buttons["Queue on device"].exists)
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Keep editing"].waitForExistence(timeout: 5))
        app.buttons["Keep editing"].tap()
        XCTAssertTrue(to.exists)
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Keep editing"].waitForExistence(timeout: 5))
        let saves = app.buttons.matching(NSPredicate(format: "label == %@", "Save draft"))
        let save = saves.element(boundBy: max(0, saves.count - 1))
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        XCTAssertTrue(app.staticTexts["Draft"].firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.staticTexts["Sent"].exists)
    }

    func testReplyDraftSurvivesDragAndDiscardedEdits() {
        let app = launch(["--paper-preview-inbox-thread", "email"])
        let reply = app.buttons["inbox-email-reply"]
        XCTAssertTrue(reply.waitForExistence(timeout: 20), app.debugDescription)
        reply.tap()
        let field = app.textFields["inbox-mail-body"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("Original reply")
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Keep editing"].waitForExistence(timeout: 5))
        app.buttons["Keep editing"].tap()
        let grabber = app.buttons["Sheet Grabber"].firstMatch
        XCTAssertTrue(grabber.waitForExistence(timeout: 5))
        grabber.swipeDown()
        XCTAssertTrue(field.exists, "Dragging must not dismiss unsaved reply")
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Keep editing"].waitForExistence(timeout: 5))
        let saves = app.buttons.matching(NSPredicate(format: "label == %@", "Save draft"))
        saves.element(boundBy: max(0, saves.count - 1)).tap()
        XCTAssertTrue(app.staticTexts["Original reply"].waitForExistence(timeout: 10))
        let options = app.buttons["Options for this email"].firstMatch
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        options.tap()
        let edit = app.buttons["Edit draft"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(" changed")
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Discard changes"].waitForExistence(timeout: 5))
        app.buttons["Discard changes"].tap()
        XCTAssertTrue(app.staticTexts["Original reply"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Original reply changed"].exists)
    }

    func testInvalidatingSessionClosesDirtyComposer() {
        let app = launch(["--paper-preview-inbox-section", "email", "--paper-preview-invalidate-inbox"])
        let compose = app.buttons["New email"].firstMatch
        XCTAssertTrue(compose.waitForExistence(timeout: 20))
        compose.tap()
        let body = app.textFields["inbox-mail-body"]
        XCTAssertTrue(body.waitForExistence(timeout: 10))
        body.tap()
        body.typeText("Private unsaved details")
        let invalidate = app.buttons["inbox-test-invalidate"]
        XCTAssertTrue(invalidate.exists)
        invalidate.tap()
        XCTAssertTrue(body.waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.staticTexts["Private unsaved details"].exists)
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

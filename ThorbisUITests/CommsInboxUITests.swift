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

    func testCustomerEmailOpensPreaddressedThorbisComposer() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customer"]
        app.launch()
        let email = app.buttons["Email"].firstMatch
        XCTAssertTrue(email.waitForExistence(timeout: 20)); email.tap()
        let to = app.textFields["inbox-mail-to"]
        XCTAssertTrue(to.waitForExistence(timeout: 10))
        XCTAssertEqual(to.value as? String, "danielle@example.invalid")
        XCTAssertTrue(app.buttons["Send with Mail"].exists)
        XCTAssertTrue(app.buttons["Save draft"].exists)
    }

    func testJobEmailOpensPreaddressedInboxComposer() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job"]
        app.launch()
        let actions = app.buttons["Job actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 20)); actions.tap()
        let email = app.buttons["Email customer"]
        XCTAssertTrue(email.waitForExistence(timeout: 10)); email.tap()
        let to = app.textFields["inbox-mail-to"]
        XCTAssertTrue(to.waitForExistence(timeout: 10))
        XCTAssertEqual(to.value as? String, "danielle@example.invalid")
        XCTAssertEqual(app.textFields["inbox-mail-subject"].value as? String, "AC not cooling")
    }

    func testContactEmailOpensPreaddressedInboxComposer() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customer", "--paper-preview-scroll", "center"]
        app.launch()
        let actions = app.buttons["Contact actions for Danielle Marlowe"]
        XCTAssertTrue(actions.waitForExistence(timeout: 20))
        for _ in 0..<8 where !actions.isHittable { app.swipeUp() }
        XCTAssertTrue(actions.isHittable); actions.tap()
        let email = app.buttons["Email"].firstMatch
        XCTAssertTrue(email.waitForExistence(timeout: 10)); email.tap()
        let to = app.textFields["inbox-mail-to"]
        XCTAssertTrue(to.waitForExistence(timeout: 10))
        XCTAssertEqual(to.value as? String, "danielle@example.invalid")
    }

    func testReplacingSessionClosesCustomerEmailComposer() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customer", "--paper-preview-email-session-replace"]
        app.launch()
        let email = app.buttons["Email"].firstMatch
        XCTAssertTrue(email.waitForExistence(timeout: 20)); email.tap()
        let body = app.textFields["inbox-mail-body"]
        XCTAssertTrue(body.waitForExistence(timeout: 10)); body.tap(); body.typeText("Private customer details")
        let replace = app.buttons["inbox-mail-replace-session"]
        for _ in 0..<6 where !replace.isHittable { app.swipeDown() }
        XCTAssertTrue(replace.isHittable); replace.tap()
        XCTAssertTrue(body.waitForNonExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["Private customer details"].exists)
        let reopen = app.buttons["Email"].firstMatch
        XCTAssertTrue(reopen.waitForExistence(timeout: 20)); reopen.tap()
        let recover = app.buttons["Restore email draft"]
        XCTAssertTrue(recover.waitForExistence(timeout: 10)); recover.tap()
        let recoveredBody = app.textFields["inbox-mail-body"]
        XCTAssertTrue(recoveredBody.waitForExistence(timeout: 10))
        XCTAssertEqual(recoveredBody.value as? String, "Private customer details")
    }

    func testCustomerEmailDraftSurvivesAppTermination() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customer", "--paper-preview-email-recovery-namespace", UUID().uuidString]
        app.launch()
        let email = app.buttons["Email"].firstMatch
        XCTAssertTrue(email.waitForExistence(timeout: 20)); email.tap()
        let body = app.textFields["inbox-mail-body"]
        XCTAssertTrue(body.waitForExistence(timeout: 10)); body.tap(); body.typeText("Unfinished job note")
        app.terminate(); app.launch()
        XCTAssertTrue(email.waitForExistence(timeout: 20)); email.tap()
        let restore = app.buttons["Restore email draft"]
        XCTAssertTrue(restore.waitForExistence(timeout: 10)); restore.tap()
        XCTAssertTrue(body.waitForExistence(timeout: 10))
        XCTAssertEqual(body.value as? String, "Unfinished job note")
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Discard changes"].waitForExistence(timeout: 5)); app.buttons["Discard changes"].tap()
    }

    func testEmailRecoveryWriteFailureIsVisible() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customer", "--paper-preview-email-recovery-write-fails"]
        app.launch(); let email = app.buttons["Email"].firstMatch
        XCTAssertTrue(email.waitForExistence(timeout: 20)); email.tap()
        let body = app.textFields["inbox-mail-body"]
        XCTAssertTrue(body.waitForExistence(timeout: 10)); body.tap(); body.typeText("Draft")
        XCTAssertTrue(app.staticTexts["This draft could not be protected. Copy it before leaving this screen."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Copy email"].exists)
    }

    func testEmailRecoveryLoadFailureBlocksEditing() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customer", "--paper-preview-email-recovery-load-fails"]
        app.launch(); let email = app.buttons["Email"].firstMatch
        XCTAssertTrue(email.waitForExistence(timeout: 20)); email.tap()
        let to = app.textFields["inbox-mail-to"]
        XCTAssertTrue(to.waitForExistence(timeout: 10)); XCTAssertFalse(to.isEnabled)
        XCTAssertTrue(app.buttons["Retry recovery"].exists)
        XCTAssertFalse(app.buttons["Send with Mail"].isEnabled)
    }

    func testEmailRecoveryCleanupFailurePreventsDuplicateSave() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customer", "--paper-preview-email-recovery-remove-fails"]
        app.launch(); let email = app.buttons["Email"].firstMatch
        XCTAssertTrue(email.waitForExistence(timeout: 20)); email.tap()
        let body = app.textFields["inbox-mail-body"]
        XCTAssertTrue(body.waitForExistence(timeout: 10)); body.tap(); body.typeText("Draft")
        let save = app.buttons["Save draft"]
        for _ in 0..<6 where !save.isHittable { app.swipeUp() }
        XCTAssertTrue(save.isHittable); save.tap()
        XCTAssertTrue(app.buttons["Close saved email"].waitForExistence(timeout: 10))
        XCTAssertFalse(save.isEnabled)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Your email was saved")).firstMatch.exists)
    }

    func testSendWithMailPreservesFieldsAndReturnsToDraft() {
        continueAfterFailure = false
        let app = launch(["--paper-preview-inbox-section", "email", "--paper-preview-mail-handoff-test"])
        app.buttons["New email"].firstMatch.tap()
        let to = app.textFields["inbox-mail-to"]
        XCTAssertTrue(to.waitForExistence(timeout: 10)); to.tap(); to.typeText("customer@example.com")
        app.buttons["Add Cc or Bcc"].tap()
        let cc = app.textFields["inbox-mail-cc"]; XCTAssertTrue(cc.waitForExistence(timeout: 5)); cc.tap(); cc.typeText("copy@example.com")
        let bcc = app.textFields["inbox-mail-bcc"]; bcc.tap(); bcc.typeText("private@example.com")
        let subject = app.textFields["inbox-mail-subject"]; subject.tap(); subject.typeText("Visit")
        let body = app.textFields["inbox-mail-body"]; body.tap(); body.typeText("Please review")
        let send = app.buttons["Send with Mail"]
        for _ in 0..<6 where !send.isHittable { app.swipeUp() }
        XCTAssertTrue(send.isHittable && send.isEnabled); send.tap()
        XCTAssertTrue(app.staticTexts["mail-handoff-preview"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["mail-handoff-to"].label, "customer@example.com")
        XCTAssertEqual(app.staticTexts["mail-handoff-cc"].label, "copy@example.com")
        XCTAssertEqual(app.staticTexts["mail-handoff-bcc"].label, "private@example.com")
        XCTAssertEqual(app.staticTexts["mail-handoff-subject"].label, "Visit")
        XCTAssertEqual(app.staticTexts["mail-handoff-body"].label, "Please review")
        app.buttons["Close Mail preview"].tap()
        XCTAssertTrue(body.waitForExistence(timeout: 10))
        XCTAssertEqual(body.value as? String, "Please review")
        XCTAssertFalse(app.staticTexts["Sent"].exists)
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
        XCTAssertTrue(app.staticTexts["Save this draft on your device or discard your changes."].waitForExistence(timeout: 5))
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
        let save = app.alerts["Keep your changes?"].buttons["Save draft"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        XCTAssertTrue(app.staticTexts["Draft"].firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.staticTexts["Sent"].exists)
    }

    func testSaveEmailDraftBeforeAddingRecipient() {
        let app = launch(["--paper-preview-inbox-section", "email"])
        let compose = app.buttons["New email"].firstMatch
        XCTAssertTrue(compose.waitForExistence(timeout: 20))
        compose.tap()
        let body = app.textFields["inbox-mail-body"]
        XCTAssertTrue(body.waitForExistence(timeout: 10))
        body.tap()
        body.typeText("Scope of work")
        XCTAssertFalse(app.buttons["inbox-mail-send"].isEnabled)
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Keep editing"].waitForExistence(timeout: 5))
        let saves = app.buttons.matching(NSPredicate(format: "label == %@", "Save draft"))
        saves.element(boundBy: max(0, saves.count - 1)).tap()
        XCTAssertTrue(app.staticTexts["Scope of work"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Draft"].firstMatch.exists)
        let options = app.buttons["Options for this email"].firstMatch
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        options.tap()
        let edit = app.buttons["Edit draft"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        let recipient = app.textFields["inbox-mail-to"]
        XCTAssertTrue(recipient.waitForExistence(timeout: 5))
        recipient.tap()
        recipient.typeText("customer@example.com")
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Keep editing"].waitForExistence(timeout: 5))
        let updatedSaves = app.buttons.matching(NSPredicate(format: "label == %@", "Save draft"))
        updatedSaves.element(boundBy: max(0, updatedSaves.count - 1)).tap()
        XCTAssertTrue(app.staticTexts["customer@example.com"].firstMatch.waitForExistence(timeout: 10))
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

    func testDeletedDraftCanBeRecoveredAsNewLocalDraft() {
        let app = launch(["--paper-preview-inbox-section", "email", "--paper-preview-conflict-inbox"])
        let compose = app.buttons["New email"].firstMatch
        XCTAssertTrue(compose.waitForExistence(timeout: 20))
        compose.tap()
        let to = app.textFields["inbox-mail-to"]
        XCTAssertTrue(to.waitForExistence(timeout: 10))
        to.tap()
        to.typeText("customer@example.com")
        let body = app.textFields["inbox-mail-body"]
        body.tap()
        body.typeText("Original")
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Keep editing"].waitForExistence(timeout: 5))
        let saves = app.buttons.matching(NSPredicate(format: "label == %@", "Save draft"))
        saves.element(boundBy: max(0, saves.count - 1)).tap()
        XCTAssertTrue(app.staticTexts["Original"].waitForExistence(timeout: 10))
        app.buttons["Options for this email"].firstMatch.tap()
        let edit = app.buttons["Edit draft"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        body.tap()
        body.typeText(" revised")
        let remove = app.buttons["inbox-test-conflict"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Keep editing"].waitForExistence(timeout: 5))
        let updatedSaves = app.buttons.matching(NSPredicate(format: "label == %@", "Save draft"))
        updatedSaves.element(boundBy: max(0, updatedSaves.count - 1)).tap()
        let copy = app.buttons["inbox-mail-save-copy"]
        XCTAssertTrue(copy.waitForExistence(timeout: 10), app.debugDescription)
        copy.tap()
        let recovered = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Original", "revised")).firstMatch
        XCTAssertTrue(recovered.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.staticTexts["Sent"].exists)
    }

    func testEmailStorageFailureKeepsTextAndPreventsBlindRetry() {
        let app = launch(["--paper-preview-inbox-section", "email", "--paper-preview-inbox-storage-failure"])
        let compose = app.buttons["New email"].firstMatch
        XCTAssertTrue(compose.waitForExistence(timeout: 20))
        compose.tap()
        let to = app.textFields["inbox-mail-to"]
        XCTAssertTrue(to.waitForExistence(timeout: 10))
        to.tap()
        to.typeText("customer@example.com")
        let body = app.textFields["inbox-mail-body"]
        body.tap()
        body.typeText("Keep these details")
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Keep editing"].waitForExistence(timeout: 5))
        let saves = app.buttons.matching(NSPredicate(format: "label == %@", "Save draft"))
        saves.element(boundBy: max(0, saves.count - 1)).tap()
        let copy = app.buttons["inbox-mail-copy-text"]
        XCTAssertTrue(copy.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(body.exists)
        XCTAssertTrue((body.value as? String)?.contains("Keep these details") ?? false)
        XCTAssertFalse(app.buttons["inbox-mail-send"].isEnabled)
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

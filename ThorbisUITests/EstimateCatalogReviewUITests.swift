import XCTest

/// Adding price book items to an estimate. Since #183 the catalog is a cart sheet behind each
/// section's "Add item" (`estimate-add-item`, its value names the section): picks land in the section
/// it was opened from, nothing saves from the sheet, and "Done" returns to the builder for review.
@MainActor
final class EstimateCatalogReviewUITests: XCTestCase {
    func testCustomerMenuKeepsItsVisibleAccessibilityLabelWithoutOverride() {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "new-estimate"]
        app.launch()
        let customer = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Danielle Marlowe")).firstMatch
        XCTAssertTrue(customer.waitForExistence(timeout: 30), "The customer menu must retain its visible label for accessibility")
    }

    func testNewEstimateCanReviewAddedItemsWithoutSavingFromSearch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "new-estimate", "--paper-preview-catalog-pages"]
        app.launch()
        openPicker(app.buttons.matching(identifier: "estimate-add-item").firstMatch, in: app)
        let search = app.textFields["price-book-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("Replace capacitor")
        let item = app.buttons["price-book-item-00000000-0000-4000-8000-000000009201"]
        XCTAssertTrue(item.waitForExistence(timeout: 15))
        item.tap()
        let done = app.buttons["price-book-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertEqual(done.label, "Done · 1 item")
        // Nothing saves from the price book: its only commit returns to the builder.
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Save estimate")).firstMatch.isHittable)
        done.tap()
        XCTAssertTrue(search.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.textFields["Estimate title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Save estimate")).firstMatch.exists)
        // The added line sits collapsed in the builder; tapping it opens its fields for review.
        let added = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Replace capacitor")).firstMatch
        XCTAssertTrue(added.waitForExistence(timeout: 5))
        added.tap()
        let editableLine = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Line description")).firstMatch
        XCTAssertTrue(editableLine.waitForExistence(timeout: 5))
    }

    func testLongCustomDescriptionRemainsEditableAndExplainsSaveLimit() {
        checkLongCustomDescriptionAtKeyboard(largeText: false)
    }

    func testLongCustomDescriptionAndSaveStayReachableAtLargestText() {
        checkLongCustomDescriptionAtKeyboard(largeText: true)
    }

    private func checkLongCustomDescriptionAtKeyboard(largeText: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "new-estimate"]
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        openPicker(app.buttons.matching(identifier: "estimate-add-item").firstMatch, in: app)
        let search = app.textFields["price-book-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        let fullDescription = String(repeating: "scope ", count: 40) + "last words"
        search.typeText(fullDescription)
        let add = app.buttons["price-book-add-custom"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        if largeText { XCTAssertLessThanOrEqual(add.frame.height, app.frame.height / 2, "A long query must not make the custom-item action taller than half the screen") }
        add.tap()
        let description = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Line description")).firstMatch
        XCTAssertTrue(description.waitForExistence(timeout: 10))
        XCTAssertEqual(description.value as? String, fullDescription)
        let save = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Save estimate")).firstMatch
        let keyboardDone = app.buttons["Done"].firstMatch
        XCTAssertTrue(keyboardDone.waitForExistence(timeout: 5))
        XCTAssertFalse(save.frame.intersects(keyboardDone.frame), "The keyboard Done control must not cover any part of Save")
        save.tap()
        let warning = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Error: Item descriptions can be up to 200 characters")).firstMatch
        XCTAssertTrue(warning.waitForExistence(timeout: 5))
        XCTAssertTrue(warning.isHittable, "The warning must remain visible while the keyboard is open")
        XCTAssertTrue(save.isHittable, "Save must remain reachable while the warning is displayed")
        XCTAssertEqual(description.value as? String, fullDescription)
    }

    func testFailedConflictCleanupKeepsRecoveredDraftAndReportsFailure() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "estimate-revision",
            "--commercial-draft-test-id", UUID().uuidString]
        app.launch()
        let title = app.textFields["Estimate title"]
        XCTAssertTrue(title.waitForExistence(timeout: 30))
        let original = title.value as? String ?? ""
        title.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap(); title.typeText(" retained")
        XCTAssertEqual(title.value as? String, original + " retained")
        app.terminate()
        app.launchArguments += ["--paper-preview-estimate-recovery-newer-revision", "--commercial-draft-test-cleanup-fails"]
        app.launch()
        let review = app.buttons["Review latest and discard draft"]
        XCTAssertTrue(review.waitForExistence(timeout: 20))
        review.tap()
        XCTAssertTrue(app.buttons["Check latest before discarding"].waitForExistence(timeout: 15))
        app.buttons["Check latest before discarding"].tap()
        let finalDiscard = app.buttons["Discard draft and reload"]
        XCTAssertTrue(finalDiscard.waitForExistence(timeout: 15)); finalDiscard.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "draft could not be cleared")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(review.exists)
        app.terminate()
        app.launchArguments.removeAll { $0 == "--paper-preview-estimate-recovery-newer-revision" || $0 == "--commercial-draft-test-cleanup-fails" }
        app.launch()
        let reopened = app.textFields["Estimate title"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 20))
        XCTAssertEqual(reopened.value as? String, original + " retained")
    }

    func testLateReloadAfterDismissalKeepsRecoveredDraft() {
        continueAfterFailure = false
        let app = XCUIApplication()
        let traceID = UUID().uuidString
        print("DRAFT_TRACE_ID \(traceID)")
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "estimate-revision",
            "--commercial-draft-test-id", traceID, "--commercial-draft-test-trace"]
        app.launch()
        let title = app.textFields["Estimate title"]
        XCTAssertTrue(title.waitForExistence(timeout: 30))
        let original = title.value as? String ?? ""
        title.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap(); title.typeText("x")
        XCTAssertEqual(title.value as? String, original + "x")
        app.terminate()
        app.launchArguments.append("--paper-preview-estimate-recovery-held-reload")
        app.launch()
        let review = app.buttons["Review latest and discard draft"]
        XCTAssertTrue(review.waitForExistence(timeout: 20))
        review.tap()
        let count = app.staticTexts["estimate-held-reload-count"]
        XCTAssertTrue(count.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "value == %@", "waiting"), evaluatedWith: count)
        waitForExpectations(timeout: 10)
        app.buttons["estimate-held-reload-dismiss"].tap()
        XCTAssertTrue(count.waitForNonExistence(timeout: 10))
        // Let the deliberately delayed server reply arrive after the view is gone.
        let delivered = XCTNSPredicateExpectation(predicate: NSPredicate(value: false), object: nil)
        delivered.isInverted = true
        wait(for: [delivered], timeout: 2)
        app.terminate()
        app.launchArguments.removeAll { $0 == "--paper-preview-estimate-recovery-held-reload" }
        app.launch()
        let reopened = app.textFields["Estimate title"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 20))
        XCTAssertEqual(reopened.value as? String, original + "x")
    }

    func testCancelReloadConfirmationKeepsRecoveredDraft() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "estimate-revision",
            "--commercial-draft-test-id", UUID().uuidString]
        app.launch()
        let title = app.textFields["Estimate title"]
        XCTAssertTrue(title.waitForExistence(timeout: 30))
        let original = title.value as? String ?? ""
        title.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap(); title.typeText("x")
        XCTAssertEqual(title.value as? String, original + "x")
        app.terminate()
        app.launchArguments.append("--paper-preview-estimate-recovery-newer-revision")
        app.launch()
        let review = app.buttons["Review latest and discard draft"]
        XCTAssertTrue(review.waitForExistence(timeout: 20)); review.tap()
        let discard = app.buttons["Check latest before discarding"]
        XCTAssertTrue(discard.waitForExistence(timeout: 15))
        let cancels = app.buttons.matching(identifier: "Cancel")
        XCTAssertGreaterThan(cancels.count, 0)
        cancels.element(boundBy: cancels.count - 1).tap()
        XCTAssertTrue(discard.waitForNonExistence(timeout: 10))
        app.terminate()
        app.launchArguments.removeAll { $0 == "--paper-preview-estimate-recovery-newer-revision" }
        app.launch()
        let reopened = app.textFields["Estimate title"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 20))
        XCTAssertEqual(reopened.value as? String, original + "x")
    }

    func testConfirmReloadDiscardsRecoveredDraftAfterFreshRead() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "estimate-revision",
            "--commercial-draft-test-id", UUID().uuidString]
        app.launch()
        let title = app.textFields["Estimate title"]
        XCTAssertTrue(title.waitForExistence(timeout: 30))
        let original = title.value as? String ?? ""
        title.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap(); title.typeText("x")
        XCTAssertEqual(title.value as? String, original + "x")
        app.terminate()
        app.launchArguments.append("--paper-preview-estimate-recovery-newer-revision")
        app.launch()
        let review = app.buttons["Review latest and discard draft"]
        XCTAssertTrue(review.waitForExistence(timeout: 20)); review.tap()
        let discard = app.buttons["Check latest before discarding"]
        XCTAssertTrue(discard.waitForExistence(timeout: 15)); discard.tap()
        let finalDiscard = app.buttons["Discard draft and reload"]
        XCTAssertTrue(finalDiscard.waitForExistence(timeout: 15)); finalDiscard.tap()
        XCTAssertTrue(app.textFields["Estimate title"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.textFields["Estimate title"].value as? String, original)
        app.terminate()
        app.launchArguments.removeAll { $0 == "--paper-preview-estimate-recovery-newer-revision" }
        app.launch()
        let reopened = app.textFields["Estimate title"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 20))
        XCTAssertEqual(reopened.value as? String, original)
    }

    private func assertEstimateFreshReadProtectsDraft(_ flag: String) {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "estimate-revision",
            "--commercial-draft-test-id", UUID().uuidString]
        app.launch()
        let title = app.textFields["Estimate title"]
        XCTAssertTrue(title.waitForExistence(timeout: 30))
        let original = title.value as? String ?? ""
        title.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap(); title.typeText("x")
        XCTAssertEqual(title.value as? String, original + "x")
        app.terminate()
        app.launchArguments += ["--paper-preview-estimate-recovery-newer-revision", flag]
        app.launch()
        let review = app.buttons["Review latest and discard draft"]
        XCTAssertTrue(review.waitForExistence(timeout: 20)); review.tap()
        let check = app.buttons["Check latest before discarding"]
        XCTAssertTrue(check.waitForExistence(timeout: 15)); check.tap()
        let result = app.staticTexts["estimate-final-read-result"]
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        let expected = flag.hasSuffix("denied") ? "denied or failed" : "changed"
        expectation(for: NSPredicate(format: "value == %@", expected), evaluatedWith: result)
        waitForExpectations(timeout: 15)
        XCTAssertFalse(app.buttons["Discard draft and reload"].exists)
        app.terminate()
        app.launchArguments.removeAll { $0 == "--paper-preview-estimate-recovery-newer-revision" || $0 == flag }
        app.launch()
        let reopened = app.textFields["Estimate title"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 20))
        XCTAssertEqual(reopened.value as? String, original + "x")
    }

    func testEstimateFreshReadDenialKeepsDraft() {
        continueAfterFailure = false
        assertEstimateFreshReadProtectsDraft("--paper-preview-estimate-final-read-denied")
    }

    func testEstimateFreshReadNewRevisionKeepsDraft() {
        continueAfterFailure = false
        assertEstimateFreshReadProtectsDraft("--paper-preview-estimate-final-read-changed")
    }

    func testFailedCleanupAfterUndoStillRequiresDiscardConfirmation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "estimate-revision",
            "--commercial-draft-test-id", UUID().uuidString, "--commercial-draft-test-cleanup-fails"]
        app.launch()
        let title = app.textFields["Estimate title"]
        XCTAssertTrue(title.waitForExistence(timeout: 30))
        let original = title.value as? String ?? ""
        title.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap(); title.typeText("x")
        title.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertEqual(title.value as? String, original)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "undone draft could not be removed")).firstMatch.waitForExistence(timeout: 10))
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Discard changes"].waitForExistence(timeout: 5))
        app.buttons["Discard changes"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "saved draft could not be removed")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(title.exists, "The editor must remain available while cleanup is unresolved")
    }

    func testWhitespaceOnlyTitleEditRequiresDiscardConfirmation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "estimate-revision",
            "--commercial-draft-test-id", UUID().uuidString]
        app.launch()
        let title = app.textFields["Estimate title"]
        XCTAssertTrue(title.waitForExistence(timeout: 30))
        let original = title.value as? String ?? ""
        title.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        title.typeText(" ")
        XCTAssertEqual(title.value as? String, original + " ")
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Discard changes"].waitForExistence(timeout: 5))
    }

    func testUndoToOriginalTitleDoesNotResurrectAnOldLocalDraft() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "estimate-revision",
            "--commercial-draft-test-id", UUID().uuidString]
        app.launch()
        let title = app.textFields["Estimate title"]
        XCTAssertTrue(title.waitForExistence(timeout: 30))
        let original = title.value as? String ?? ""
        XCTAssertFalse(original.isEmpty)
        title.tap(); title.typeText("x")
        XCTAssertNotEqual(title.value as? String, original)
        title.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertEqual(title.value as? String, original)
        app.terminate()
        app.launch()
        let reopened = app.textFields["Estimate title"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 30))
        XCTAssertEqual(reopened.value as? String, original)
    }

    func testRevisionShowsLengthWarningWhenSavingWithNumberKeyboardOpen() {
        continueAfterFailure = false
        let app = XCUIApplication()
        // This preview has a sent revision and valid manual/Price Book source identities.
        // The builder-line showcase intentionally includes incomplete Price Book provenance,
        // which correctly disables editing and is not a suitable editor fixture.
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "estimate-revision"]
        app.launch()
        let line = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Compressor diagnostic")).firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 30))
        line.tap()
        let description = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Line description")).firstMatch
        XCTAssertTrue(description.waitForExistence(timeout: 30))
        XCTAssertTrue(description.isEnabled, "The revision fixture must be editable with supported provenance")
        description.tap()
        description.typeText(String(repeating: "x", count: 201))
        let price = app.textFields["Price each in dollars"]
        XCTAssertTrue(price.waitForExistence(timeout: 5))
        price.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let save = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Save revised draft")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isHittable)
        let keyboardDone = app.buttons["Done"].firstMatch
        XCTAssertTrue(keyboardDone.waitForExistence(timeout: 5))
        XCTAssertFalse(save.frame.intersects(keyboardDone.frame), "The keyboard Done control must not cover any part of Save")
        save.tap()
        let warning = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Error: Item descriptions can be up to 200 characters")).firstMatch
        XCTAssertTrue(warning.waitForExistence(timeout: 5))
    }

    func testReviewKeepsCatalogItemInItsChosenOption() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "estimate-revision"]
        app.launch()
        let optionTitle = app.textFields["Option package title"]
        XCTAssertTrue(optionTitle.waitForExistence(timeout: 30))
        let optionAdd = app.buttons.matching(identifier: "estimate-add-item")
            .matching(NSPredicate(format: "value CONTAINS %@", "Full system replacement")).firstMatch
        XCTAssertTrue(optionAdd.waitForExistence(timeout: 10), "Each option has its own Add item")
        openPicker(optionAdd, in: app)
        let destination = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "To ", "Full system replacement")).firstMatch
        XCTAssertTrue(destination.exists, "The picker names the option it adds to")
        let search = app.textFields["price-book-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("Replace capacitor")
        let item = app.buttons["price-book-item-00000000-0000-4000-8000-000000009201"]
        XCTAssertTrue(item.waitForExistence(timeout: 10))
        item.tap()
        app.buttons["price-book-done"].tap()
        XCTAssertTrue(search.waitForNonExistence(timeout: 5))
        XCTAssertTrue(optionTitle.waitForExistence(timeout: 5))
        openPicker(optionAdd, in: app)
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("Replace capacitor")
        let added = app.buttons.matching(identifier: "price-book-item-00000000-0000-4000-8000-000000009201")
            .matching(NSPredicate(format: "value == %@", "1 in draft")).firstMatch
        XCTAssertTrue(added.waitForExistence(timeout: 10), "The added line must remain in the selected option")
    }

    func testDraftEstimateKeepsSaveUnavailableDuringCatalogReview() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "estimate-draft", "--paper-preview-catalog-pages"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Draft changes can't be saved yet."].waitForExistence(timeout: 30))
        openPicker(app.buttons.matching(identifier: "estimate-add-item").firstMatch, in: app)
        let search = app.textFields["price-book-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        XCTAssertTrue(app.staticTexts["Draft changes can't be saved yet."].exists, "The draft limit stays in view while adding")
        app.buttons["price-book-done"].tap()
        XCTAssertTrue(search.waitForNonExistence(timeout: 5))
        let save = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Save draft")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled)
    }

    private func openPicker(_ add: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(add.waitForExistence(timeout: 30))
        // Clear of the pinned total and commit at the bottom, which cover the lower part of the page.
        let clear = app.frame.height * 0.7
        for _ in 0..<10 where !add.isHittable || add.frame.maxY > clear {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)))
        }
        XCTAssertTrue(add.isHittable)
        add.tap()
        XCTAssertTrue(app.buttons["price-book-done"].waitForExistence(timeout: 5), "Add item opens the price book")
    }
}

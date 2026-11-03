import XCTest

/// The invoice editor's price book (since #183 a cart sheet behind "Add item"): search the price
/// book or type a custom line, add an item as many times as needed with the keyboard up, then
/// "Done" returns to the invoice with the last added line open for its quantity and price.
@MainActor
final class InvoiceCatalogQuickEditUITests: XCTestCase {
    private let itemID = "price-book-item-00000000-0000-4000-8000-000000009999"

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-editor", "--paper-preview-catalog-pages"] + extra
        app.launch()
        XCTAssertTrue(app.navigationBars["Edit invoice"].waitForExistence(timeout: 20))
        return app
    }

    /// "Line items · N" read from its identifier, so additions are counted, not guessed.
    private func lineCount(_ app: XCUIApplication) -> Int {
        let header = app.staticTexts["invoice-line-count"]
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        return Int(header.label.components(separatedBy: "·").last?.trimmingCharacters(in: .whitespaces) ?? "") ?? 0
    }

    /// Opens the price book from "Add item" and types into its search.
    private func openCatalog(_ app: XCUIApplication, typing text: String) -> XCUIElement {
        let add = app.buttons["invoice-add-item"]
        reveal(add, in: app)
        add.tap()
        let search = app.textFields["invoice-catalog-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10), "Add item must open the price book search")
        search.tap()
        search.typeText(text)
        return search
    }

    /// The one line the editor opened: only an open line carries its description field.
    private func openLineIdentity(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> String {
        let fields = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "invoice-line-description-"))
        XCTAssertTrue(fields.firstMatch.waitForExistence(timeout: 5), "The last added line must open for editing", file: file, line: line)
        XCTAssertEqual(fields.count, 1, "Exactly one line opens", file: file, line: line)
        return String(fields.firstMatch.identifier.dropFirst("invoice-line-description-".count))
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        for _ in 0..<8 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }

    func testFailedInvoiceUndoCleanupStillRequiresDiscardConfirmation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-editor-line",
            "--commercial-draft-test-id", UUID().uuidString, "--commercial-draft-test-cleanup-fails"]
        app.launch()
        let identity = openLineIdentity(app)
        let quantity = app.textFields["invoice-line-quantity-" + identity]
        XCTAssertTrue(quantity.waitForExistence(timeout: 10))
        app.buttons["One more"].firstMatch.tap(); XCTAssertEqual(quantity.value as? String, "2")
        app.buttons["One fewer"].firstMatch.tap(); XCTAssertEqual(quantity.value as? String, "1")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "undone draft could not be removed")).firstMatch.waitForExistence(timeout: 10))
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Discard changes"].waitForExistence(timeout: 5))
        app.buttons["Discard changes"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "saved draft could not be removed")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(quantity.exists)
    }

    func testSameSessionInvoiceRevalidationHidesAndRestoresEdits() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-editor-line",
            "--paper-preview-invoice-toggle-access", "--commercial-draft-test-id", UUID().uuidString]
        app.launch()
        let identity = openLineIdentity(app)
        let quantity = app.textFields["invoice-line-quantity-" + identity]
        XCTAssertTrue(quantity.waitForExistence(timeout: 10))
        app.buttons["One more"].firstMatch.tap()
        XCTAssertEqual(quantity.value as? String, "2")
        let toggle = app.buttons["invoice-toggle-sample-access"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10)); toggle.tap()
        XCTAssertTrue(app.staticTexts["Document unavailable"].waitForExistence(timeout: 15))
        XCTAssertFalse(quantity.exists)
        toggle.tap()
        XCTAssertTrue(quantity.waitForExistence(timeout: 15))
        XCTAssertEqual(quantity.value as? String, "2")
    }

    private func saveSampleInvoiceDraft(_ app: XCUIApplication) {
        app.launch()
        let quantity = app.textFields["invoice-line-quantity-" + openLineIdentity(app)]
        XCTAssertTrue(quantity.waitForExistence(timeout: 10))
        app.buttons["One more"].firstMatch.tap()
        XCTAssertEqual(quantity.value as? String, "2")
        app.terminate()
    }

    private func assertSampleInvoiceQuantity(_ app: XCUIApplication, _ expected: String) {
        let fields = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "invoice-line-description-"))
        if !fields.firstMatch.waitForExistence(timeout: 5) {
            let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Compressor diagnostic")).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()
        }
        let quantity = app.textFields["invoice-line-quantity-" + openLineIdentity(app)]
        XCTAssertTrue(quantity.waitForExistence(timeout: 15))
        XCTAssertEqual(quantity.value as? String, expected)
    }

    func testInvoiceDelayedReloadAfterDismissalKeepsDraft() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-editor-line",
            "--commercial-draft-test-id", UUID().uuidString, "--paper-preview-invoice-toggle-access"]
        saveSampleInvoiceDraft(app)
        app.launchArguments.append("--paper-preview-invoice-recovery-held-reload")
        app.launch()
        let review = app.buttons["Review latest and discard draft"]
        XCTAssertTrue(review.waitForExistence(timeout: 20)); review.tap()
        let state = app.staticTexts["invoice-held-reload-count"]
        XCTAssertTrue(state.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "value == %@", "waiting"), evaluatedWith: state)
        waitForExpectations(timeout: 10)
        app.buttons["invoice-held-reload-dismiss"].tap()
        XCTAssertTrue(state.waitForNonExistence(timeout: 10))
        let delivered = XCTNSPredicateExpectation(predicate: NSPredicate(value: false), object: nil)
        delivered.isInverted = true; wait(for: [delivered], timeout: 2)
        app.terminate()
        app.launchArguments.removeAll { $0 == "--paper-preview-invoice-recovery-held-reload" }
        app.launchArguments.append("--paper-preview-invoice-check-delivery")
        app.launch(); assertSampleInvoiceQuantity(app, "2")
        let delivery = app.staticTexts["invoice-reload-delivery"]
        XCTAssertTrue(delivery.waitForExistence(timeout: 10))
        XCTAssertEqual(delivery.value as? String, "delivered")
    }

    func testInvoiceDelayedFinalReadAfterDismissalKeepsDraft() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-editor-line",
            "--commercial-draft-test-id", UUID().uuidString, "--paper-preview-invoice-toggle-access"]
        saveSampleInvoiceDraft(app)
        app.launchArguments += ["--paper-preview-invoice-recovery-newer-revision", "--paper-preview-invoice-final-read-held"]
        app.launch()
        let review = app.buttons["Review latest and discard draft"]
        XCTAssertTrue(review.waitForExistence(timeout: 20)); review.tap()
        let check = app.buttons["Check latest before discarding"]
        XCTAssertTrue(check.waitForExistence(timeout: 15)); check.tap()
        let state = app.staticTexts["invoice-held-reload-count"]
        XCTAssertTrue(state.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "value == %@", "waiting"), evaluatedWith: state)
        waitForExpectations(timeout: 10)
        app.buttons["invoice-held-reload-dismiss"].tap()
        XCTAssertTrue(state.waitForNonExistence(timeout: 10))
        let delivered = XCTNSPredicateExpectation(predicate: NSPredicate(value: false), object: nil)
        delivered.isInverted = true; wait(for: [delivered], timeout: 2)
        app.terminate()
        app.launchArguments.removeAll { $0 == "--paper-preview-invoice-recovery-newer-revision" || $0 == "--paper-preview-invoice-final-read-held" }
        app.launchArguments.append("--paper-preview-invoice-check-delivery")
        app.launch(); assertSampleInvoiceQuantity(app, "2")
        let delivery = app.staticTexts["invoice-reload-delivery"]
        XCTAssertTrue(delivery.waitForExistence(timeout: 10))
        XCTAssertEqual(delivery.value as? String, "delivered")
    }

    func testInvoiceConfirmedReloadDiscardsDraft() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-editor-line",
            "--commercial-draft-test-id", UUID().uuidString, "--paper-preview-invoice-toggle-access"]
        saveSampleInvoiceDraft(app)
        app.launchArguments.append("--paper-preview-invoice-recovery-newer-revision")
        app.launch()
        let review = app.buttons["Review latest and discard draft"]
        XCTAssertTrue(review.waitForExistence(timeout: 20)); review.tap()
        let discard = app.buttons["Check latest before discarding"]
        XCTAssertTrue(discard.waitForExistence(timeout: 15)); discard.tap()
        let finalDiscard = app.buttons["Discard draft and reload"]
        XCTAssertTrue(finalDiscard.waitForExistence(timeout: 15)); finalDiscard.tap()
        XCTAssertTrue(app.buttons["Save draft"].waitForExistence(timeout: 15))
        app.terminate()
        app.launchArguments.removeAll { $0 == "--paper-preview-invoice-recovery-newer-revision" }
        app.launch(); assertSampleInvoiceQuantity(app, "1")
    }

    func testInvoiceCancelFinalConfirmationKeepsDraft() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-editor-line",
            "--commercial-draft-test-id", UUID().uuidString, "--paper-preview-invoice-toggle-access"]
        saveSampleInvoiceDraft(app)
        app.launchArguments.append("--paper-preview-invoice-recovery-newer-revision")
        app.launch()
        let review = app.buttons["Review latest and discard draft"]
        XCTAssertTrue(review.waitForExistence(timeout: 20)); review.tap()
        let check = app.buttons["Check latest before discarding"]
        XCTAssertTrue(check.waitForExistence(timeout: 15)); check.tap()
        let discard = app.buttons["Discard draft and reload"]
        XCTAssertTrue(discard.waitForExistence(timeout: 15))
        let cancels = app.buttons.matching(identifier: "Cancel")
        XCTAssertGreaterThan(cancels.count, 0); cancels.element(boundBy: cancels.count - 1).tap()
        XCTAssertTrue(discard.waitForNonExistence(timeout: 10))
        app.terminate()
        app.launchArguments.removeAll { $0 == "--paper-preview-invoice-recovery-newer-revision" }
        app.launch(); assertSampleInvoiceQuantity(app, "2")
    }

    func testInvoiceFailedReloadCleanupKeepsDraft() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-editor-line",
            "--commercial-draft-test-id", UUID().uuidString, "--paper-preview-invoice-toggle-access"]
        saveSampleInvoiceDraft(app)
        app.launchArguments += ["--paper-preview-invoice-recovery-newer-revision", "--commercial-draft-test-cleanup-fails"]
        app.launch()
        let review = app.buttons["Review latest and discard draft"]
        XCTAssertTrue(review.waitForExistence(timeout: 20)); review.tap()
        let discard = app.buttons["Check latest before discarding"]
        XCTAssertTrue(discard.waitForExistence(timeout: 15)); discard.tap()
        let finalDiscard = app.buttons["Discard draft and reload"]
        XCTAssertTrue(finalDiscard.waitForExistence(timeout: 15)); finalDiscard.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "draft could not be cleared")).firstMatch.waitForExistence(timeout: 10))
        app.terminate()
        app.launchArguments.removeAll { $0 == "--paper-preview-invoice-recovery-newer-revision" || $0 == "--commercial-draft-test-cleanup-fails" }
        app.launch(); assertSampleInvoiceQuantity(app, "2")
    }

    func testInvoiceConfirmationIsRetiredAfterNetworkInterruption() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-editor-line",
            "--commercial-draft-test-id", UUID().uuidString, "--paper-preview-invoice-toggle-access"]
        saveSampleInvoiceDraft(app)
        app.launchArguments += ["--paper-preview-invoice-recovery-newer-revision", "--paper-preview-invoice-confirm-network-interruption"]
        app.launch()
        let review = app.buttons["Review latest and discard draft"]
        XCTAssertTrue(review.waitForExistence(timeout: 20)); review.tap()
        let discard = app.buttons["Check latest before discarding"]
        XCTAssertTrue(discard.waitForExistence(timeout: 15))
        XCTAssertTrue(discard.waitForNonExistence(timeout: 20), "The stale confirmation must close when connectivity changes")
        let network = app.staticTexts["invoice-confirm-network-state"]
        XCTAssertTrue(network.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "value == %@", "offline"), evaluatedWith: network)
        waitForExpectations(timeout: 15)
        app.buttons["invoice-confirm-network-restore"].tap()
        expectation(for: NSPredicate(format: "value == %@", "online"), evaluatedWith: network)
        waitForExpectations(timeout: 15)
        XCTAssertFalse(discard.exists)
        app.terminate()
        app.launchArguments.removeAll { $0 == "--paper-preview-invoice-recovery-newer-revision" || $0 == "--paper-preview-invoice-confirm-network-interruption" }
        app.launch(); assertSampleInvoiceQuantity(app, "2")
    }

    func testInvoiceConfirmationIsRetiredAfterNewerRevision() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-editor-line",
            "--commercial-draft-test-id", UUID().uuidString, "--paper-preview-invoice-toggle-access"]
        saveSampleInvoiceDraft(app)
        app.launchArguments += ["--paper-preview-invoice-recovery-newer-revision", "--paper-preview-invoice-confirm-revision-change"]
        app.launch()
        let review = app.buttons["Review latest and discard draft"]
        XCTAssertTrue(review.waitForExistence(timeout: 20)); review.tap()
        let discard = app.buttons["Check latest before discarding"]
        XCTAssertTrue(discard.waitForExistence(timeout: 15))
        XCTAssertTrue(discard.waitForNonExistence(timeout: 20), "A later authority refresh must retire the old confirmation")
        app.terminate()
        app.launchArguments.removeAll { $0 == "--paper-preview-invoice-recovery-newer-revision" || $0 == "--paper-preview-invoice-confirm-revision-change" }
        app.launch(); assertSampleInvoiceQuantity(app, "2")
    }

    func testInvoiceConfirmationIsRetiredAfterPermissionLossAndRestoration() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-editor-line",
            "--commercial-draft-test-id", UUID().uuidString, "--paper-preview-invoice-toggle-access"]
        saveSampleInvoiceDraft(app)
        app.launchArguments += ["--paper-preview-invoice-recovery-newer-revision", "--paper-preview-invoice-confirm-permission-interruption"]
        app.launch()
        let review = app.buttons["Review latest and discard draft"]
        XCTAssertTrue(review.waitForExistence(timeout: 20)); review.tap()
        let check = app.buttons["Check latest before discarding"]
        XCTAssertTrue(check.waitForExistence(timeout: 15))
        XCTAssertTrue(check.waitForNonExistence(timeout: 20))
        let access = app.staticTexts["invoice-confirm-permission-state"]
        XCTAssertTrue(access.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "value == %@", "denied"), evaluatedWith: access)
        waitForExpectations(timeout: 15)
        app.buttons["invoice-confirm-permission-restore"].tap()
        expectation(for: NSPredicate(format: "value == %@", "allowed"), evaluatedWith: access)
        waitForExpectations(timeout: 15)
        XCTAssertFalse(check.exists)
        app.terminate()
        app.launchArguments.removeAll { $0 == "--paper-preview-invoice-recovery-newer-revision" || $0 == "--paper-preview-invoice-confirm-permission-interruption" }
        app.launch(); assertSampleInvoiceQuantity(app, "2")
    }

    private func assertInvoiceFreshReadProtectsDraft(_ flag: String) {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-editor-line",
            "--commercial-draft-test-id", UUID().uuidString, "--paper-preview-invoice-toggle-access"]
        saveSampleInvoiceDraft(app)
        app.launchArguments += ["--paper-preview-invoice-recovery-newer-revision", flag]
        app.launch()
        let review = app.buttons["Review latest and discard draft"]
        XCTAssertTrue(review.waitForExistence(timeout: 20)); review.tap()
        let check = app.buttons["Check latest before discarding"]
        XCTAssertTrue(check.waitForExistence(timeout: 15)); check.tap()
        XCTAssertTrue(check.waitForNonExistence(timeout: 10))
        let result = app.staticTexts["invoice-final-read-result"]
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        let expected = flag.hasSuffix("denied") ? "denied or failed" : "changed"
        expectation(for: NSPredicate(format: "value == %@", expected), evaluatedWith: result)
        waitForExpectations(timeout: 15)
        XCTAssertTrue(review.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["Discard draft and reload"].exists)
        app.terminate()
        app.launchArguments.removeAll { $0 == "--paper-preview-invoice-recovery-newer-revision" || $0 == flag }
        app.launch(); assertSampleInvoiceQuantity(app, "2")
    }

    func testInvoiceFreshReadDenialKeepsDraft() {
        continueAfterFailure = false
        assertInvoiceFreshReadProtectsDraft("--paper-preview-invoice-final-read-denied")
    }

    func testInvoiceFreshReadNewRevisionKeepsDraft() {
        continueAfterFailure = false
        assertInvoiceFreshReadProtectsDraft("--paper-preview-invoice-final-read-changed")
    }

    func testNumericFormattingOnlyEditRequiresDiscardConfirmation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-editor-line",
            "--commercial-draft-test-id", UUID().uuidString]
        app.launch()
        let identity = openLineIdentity(app)
        let quantity = app.textFields["invoice-line-quantity-" + identity]
        XCTAssertTrue(quantity.waitForExistence(timeout: 10))
        quantity.tap(); replaceQuantity(quantity, with: "01", in: app)
        XCTAssertEqual(quantity.value as? String, "01")
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Discard changes"].waitForExistence(timeout: 5))
    }

    func testUndoToOriginalQuantityDoesNotResurrectAnOldLocalDraft() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-editor-line",
            "--commercial-draft-test-id", UUID().uuidString]
        app.launch()
        XCTAssertTrue(app.navigationBars["Edit invoice"].waitForExistence(timeout: 20))
        let identity = openLineIdentity(app)
        let quantity = app.textFields["invoice-line-quantity-" + identity]
        XCTAssertTrue(quantity.waitForExistence(timeout: 10))
        XCTAssertEqual(quantity.value as? String, "1")
        quantity.tap()
        replaceQuantity(quantity, with: "2", in: app)
        XCTAssertEqual(quantity.value as? String, "2")
        replaceQuantity(quantity, with: "1", in: app)
        XCTAssertEqual(quantity.value as? String, "1")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.navigationBars["Edit invoice"].waitForExistence(timeout: 20))
        let reopenedID = openLineIdentity(app)
        XCTAssertEqual(app.textFields["invoice-line-quantity-" + reopenedID].value as? String, "1")
    }

    func testCatalogAddsDistinctLinesAndOpensTheLastForEditing() {
        let app = launch()
        let before = lineCount(app)
        let search = openCatalog(app, typing: "Camera sewer inspection")
        let item = app.buttons[itemID]
        XCTAssertTrue(item.waitForExistence(timeout: 10))
        item.tap()
        XCTAssertTrue(app.buttons.matching(identifier: itemID).matching(NSPredicate(format: "value == %@", "1 in draft")).firstMatch.waitForExistence(timeout: 5))

        // A new search keeps the cart; the same item again adds a second, distinct line.
        app.buttons["Clear search"].tap()
        XCTAssertNotEqual(search.value as? String, "Camera sewer inspection")
        search.typeText("Camera sewer inspection")
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()
        XCTAssertTrue(app.buttons.matching(identifier: itemID).matching(NSPredicate(format: "value == %@", "2 in draft")).firstMatch.waitForExistence(timeout: 5))
        let done = app.buttons["price-book-done"]
        XCTAssertEqual(done.label, "Done · 2 items")
        done.tap()
        XCTAssertTrue(search.waitForNonExistence(timeout: 5))
        XCTAssertEqual(lineCount(app), before + 2, "Repeating a selection must add a distinct line")

        let identity = openLineIdentity(app)
        let quantity = app.textFields["invoice-line-quantity-" + identity]
        let price = app.textFields["invoice-line-price-" + identity]
        XCTAssertEqual(quantity.value as? String, "1")
        XCTAssertEqual(price.value as? String, "245.00")
        reveal(quantity, in: app)
        quantity.tap()
        XCTAssertTrue(app.keyboards.keys["0"].waitForExistence(timeout: 5), "The quantity field must take its numeric keyboard")
        replaceQuantity(quantity, with: "10", in: app)
        XCTAssertEqual(quantity.value as? String, "10")
        let proof = XCTAttachment(screenshot: app.screenshot())
        proof.name = "Last added line open for quantity after the price book"
        proof.lifetime = .keepAlways
        add(proof)

        app.buttons["Close line"].firstMatch.tap()
        XCTAssertTrue(quantity.waitForNonExistence(timeout: 5))
        let summary = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "10", "245.00")).firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 5), "The closed line keeps the edited quantity")
        XCTAssertTrue(app.buttons["Save draft"].isHittable)
        XCTAssertTrue(app.buttons["Issue invoice"].isHittable)
    }

    func testTypedLineBecomesACustomLineOpenForItsPrice() {
        let app = launch()
        let before = lineCount(app)
        _ = openCatalog(app, typing: "Weekend call-out fee")
        let custom = app.buttons["price-book-add-custom"]
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        XCTAssertTrue(custom.label.contains("Weekend call-out fee"))
        custom.tap()
        XCTAssertTrue(app.textFields["invoice-catalog-search"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(lineCount(app), before + 1)
        let identity = openLineIdentity(app)
        let description = app.descendants(matching: .any)["invoice-line-description-" + identity]
        XCTAssertEqual(description.value as? String, "Weekend call-out fee")
        let price = app.textFields["invoice-line-price-" + identity]
        XCTAssertTrue(price.waitForExistence(timeout: 5))
        let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: price)
        XCTAssertEqual(XCTWaiter.wait(for: [focused], timeout: 5), .completed, "A typed line opens on its price")
    }

    func testRepeatedAddsKeepCatalogReachableWithKeyboard() {
        let app = launch()
        let search = openCatalog(app, typing: "Camera sewer inspection")
        let item = app.buttons[itemID]
        XCTAssertTrue(item.waitForExistence(timeout: 10))
        item.tap()
        XCTAssertTrue(app.buttons.matching(identifier: itemID).matching(NSPredicate(format: "value == %@", "1 in draft")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.exists, "Adding must not close the keyboard")
        XCTAssertTrue(item.isHittable, "Adding another must not require closing the keyboard")
        item.tap()
        XCTAssertTrue(app.buttons.matching(identifier: itemID).matching(NSPredicate(format: "value == %@", "2 in draft")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(item.isHittable)
        XCTAssertEqual(search.value as? String, "Camera sewer inspection")
        XCTAssertEqual(app.buttons["price-book-done"].label, "Done · 2 items")
        let proof = XCTAttachment(screenshot: app.screenshot())
        proof.name = "Repeated adds keep the invoice price book reachable"
        proof.lifetime = .keepAlways
        add(proof)
    }

    func testLargestTextKeepsCatalogEditingAndInvoiceReviewReachable() {
        let app = launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let search = openCatalog(app, typing: "Camera sewer inspection")
        let item = app.buttons[itemID]
        XCTAssertTrue(item.waitForExistence(timeout: 10))
        // At this size the row can sit under the keyboard; the catalog scrolls it up as a person would.
        for _ in 0..<6 where !item.isHittable {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -80)))
        }
        XCTAssertTrue(item.isHittable)
        item.tap()
        XCTAssertTrue(app.buttons.matching(identifier: itemID).matching(NSPredicate(format: "value == %@", "1 in draft")).firstMatch.waitForExistence(timeout: 5))
        let done = app.buttons["price-book-done"]
        XCTAssertTrue(done.isHittable)
        done.tap()
        XCTAssertTrue(search.waitForNonExistence(timeout: 5))

        let identity = openLineIdentity(app)
        let price = app.textFields["invoice-line-price-" + identity]
        reveal(price, in: app)
        XCTAssertEqual(price.value as? String, "245.00")
        XCTAssertGreaterThan(price.frame.width, 200, "The full unit price must fit without a clipped money well")
        let more = app.buttons["One more"].firstMatch
        reveal(more, in: app)
        more.tap()
        XCTAssertEqual(app.textFields["invoice-line-quantity-" + identity].value as? String, "2")
        let editingProof = XCTAttachment(screenshot: app.screenshot())
        editingProof.name = "Largest text added line open for quantity and price"
        editingProof.lifetime = .keepAlways
        add(editingProof)

        let close = app.buttons["Close line"].firstMatch
        reveal(close, in: app)
        close.tap()
        let save = app.buttons["Save draft"], issue = app.buttons["Issue invoice"]
        XCTAssertTrue(save.isHittable)
        XCTAssertTrue(issue.isHittable)
        XCTAssertGreaterThan(save.frame.width, 300, "Save draft must have room for its full label")
        XCTAssertLessThanOrEqual(save.frame.maxY, issue.frame.minY, "The commits stack at accessibility sizes")
        let reviewProof = XCTAttachment(screenshot: app.screenshot())
        reviewProof.name = "Largest text return to invoice review actions"
        reviewProof.lifetime = .keepAlways
        add(reviewProof)
    }

    private func replaceQuantity(_ quantity: XCUIElement, with text: String, in app: XCUIApplication) {
        // Select the existing digits with the native touch interaction, then type through the app
        // so XCTest does not move the caret.
        quantity.doubleTap()
        app.typeText(text)
    }
}

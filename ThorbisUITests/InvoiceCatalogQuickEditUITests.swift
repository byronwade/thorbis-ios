import XCTest

/// The invoice editor's price book (since #183 a cart sheet behind "Add item"): search the price
/// book or type a custom line, add an item as many times as needed with the keyboard up, then
/// "Done" returns to the invoice with the last added line open for its quantity and price.
@MainActor
final class InvoiceCatalogQuickEditUITests: XCTestCase {
    private let itemID = "price-book-item-00000000-0000-4000-8000-000000009999"

    func testDraftInvoiceOffersDirectLineItemEditing() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-detail", "--paper-preview-invoice-detail-draft"]
        app.launch()
        XCTAssertTrue(app.staticTexts["invoice-detail-title"].waitForExistence(timeout: 20))
        let edit = app.buttons["invoice-detail-edit-items"]
        for _ in 0..<8 where !edit.isHittable { app.swipeUp() }
        XCTAssertTrue(edit.waitForExistence(timeout: 20))
        XCTAssertTrue(edit.isHittable)
        XCTAssertGreaterThanOrEqual(edit.frame.height, 44)
        edit.tap()
        XCTAssertTrue(app.staticTexts["Edit invoice"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["invoice-add-item"].exists)
    }

    func testDirectLineEditingAtLargestText() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-detail", "--paper-preview-invoice-detail-draft", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.staticTexts["invoice-detail-title"].waitForExistence(timeout: 20))
        let edit = app.buttons["invoice-detail-edit-items"]
        for _ in 0..<20 where !edit.isHittable { app.swipeUp() }
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        // At this size Edit can sit half under the pinned Issue invoice bar: it still reports hittable,
        // but a tap at its centre lands on Issue. Bring it clear of the bar first, as a person would.
        app.scrollClearOfFoot(edit)
        XCTAssertTrue(edit.isHittable)
        XCTAssertGreaterThanOrEqual(edit.frame.height, 44)
        edit.tap()
        XCTAssertTrue(app.staticTexts["Edit invoice"].waitForExistence(timeout: 10))
    }

    func testDirectLineEditingRequiresDraftAndPermission() {
        for arguments in [["--paper-preview-invoice-detail-draft", "--paper-preview-deny-document-edit"], []] {
            let app = XCUIApplication()
            app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-detail"] + arguments
            app.launch()
            XCTAssertTrue(app.staticTexts["invoice-detail-title"].waitForExistence(timeout: 20))
            // The title can be drawn from the copy saved on this phone, which never offers Edit. The
            // page's menu exists only once the live invoice has answered, and Edit is decided from it.
            XCTAssertTrue(app.buttons["Customer view, edit or open the PDF"].waitForExistence(timeout: 20))
            XCTAssertFalse(app.buttons["invoice-detail-edit-items"].exists)
            app.terminate()
        }
    }

    func testInvalidDraftStillAllowsEditingForCorrection() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-detail", "--paper-preview-invoice-detail-draft", "--paper-preview-invoice-overflow"]
        app.launch()
        XCTAssertTrue(app.staticTexts["invoice-invalid-total"].waitForExistence(timeout: 30))
        let edit = app.buttons["invoice-detail-edit-items"]
        for _ in 0..<8 where !edit.isHittable { app.swipeUp() }
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        XCTAssertTrue(edit.isHittable)
        edit.tap()
        XCTAssertTrue(app.staticTexts["Edit invoice"].waitForExistence(timeout: 10))
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-editor", "--paper-preview-catalog-pages"] + extra
        app.launch()
        XCTAssertTrue(app.staticTexts["Edit invoice"].waitForExistence(timeout: 20))
        return app
    }

    func testLongInvoiceCanAddFromTheSectionHeading() {
        let app = launch(["--paper-preview-long-catalog-sections"])
        let add = app.buttons["invoice-add-item"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        XCTAssertTrue(add.isHittable, "The catalog should be reachable before scrolling through the lines")
        XCTAssertGreaterThanOrEqual(add.frame.height, 44)
        XCTAssertEqual(lineCount(app), 12)
        add.tap()
        let search = app.textFields["invoice-catalog-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap(); search.typeText("Camera sewer inspection")
        let item = app.buttons[itemID]
        XCTAssertTrue(item.waitForExistence(timeout: 10)); item.tap()
        app.buttons["price-book-done"].tap()
        XCTAssertTrue(search.waitForNonExistence(timeout: 10))
        XCTAssertEqual(lineCount(app), 13)
        _ = openLineIdentity(app)
    }

    func testHeadingCatalogKeepsAnUnsavedLineEdit() {
        let app = launch(["--paper-preview-long-catalog-sections"])
        let first = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Sample work item 1")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        first.tap()
        let identity = openLineIdentity(app)
        let quantity = app.textFields["invoice-line-quantity-" + identity]
        XCTAssertTrue(quantity.waitForExistence(timeout: 10))
        reveal(quantity, in: app); quantity.tap()
        replaceQuantity(quantity, with: "2", in: app)
        XCTAssertEqual(quantity.value as? String, "2")
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(app.waitForKeyboardToHide())
        // Paper 40: Add item is a field above "Line items", and opening a line scrolls it under the
        // page's pinned circle row, where it still reports hittable. Scroll back until it is clear.
        let add = app.buttons["invoice-add-item"]
        let bar = app.buttons["invoice-more"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        func reachable() -> Bool { add.isHittable && add.frame.minY >= bar.frame.maxY }
        for _ in 0..<8 where !reachable() {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)))
        }
        XCTAssertTrue(reachable(), "Add item must be reachable above the lines"); add.tap()
        let search = app.textFields["invoice-catalog-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap(); search.typeText("Camera sewer inspection")
        let done = app.buttons["price-book-done"]
        // The commit rides up with the keyboard; on a slow run it is still moving when typing ends.
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: done)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed, "The catalog action must be reachable after the keyboard settles")
        XCTAssertLessThanOrEqual(done.frame.maxY, app.keyboards.firstMatch.frame.minY, "The keyboard must not cover the catalog action")
        done.tap()
        XCTAssertTrue(app.textFields["invoice-catalog-search"].waitForNonExistence(timeout: 10))
        if !quantity.exists { first.tap() }
        XCTAssertTrue(quantity.waitForExistence(timeout: 10))
        XCTAssertEqual(quantity.value as? String, "2", "Opening the catalog must keep the unsaved edit")
    }

    func testLongInvoiceHeadingActionAtLargestText() {
        let app = launch(["--paper-preview-long-catalog-sections", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let add = app.buttons["invoice-add-item"]
        reveal(add, in: app)
        XCTAssertGreaterThanOrEqual(add.frame.height, 44)
        add.tap()
        XCTAssertTrue(app.textFields["invoice-catalog-search"].waitForExistence(timeout: 10))
    }

    func testHeadingActionRespectsInvoiceEditPermission() {
        let app = launch(["--paper-preview-long-catalog-sections", "--paper-preview-deny-document-edit"])
        let add = app.buttons["invoice-add-item"]
        XCTAssertTrue(add.waitForExistence(timeout: 20))
        XCTAssertFalse(add.isEnabled)
    }

    func testHeadingActionRespectsInvoiceLineLimit() {
        let app = launch(["--paper-preview-max-catalog-sections"])
        let add = app.buttons["invoice-add-item"]
        XCTAssertTrue(add.waitForExistence(timeout: 20))
        XCTAssertFalse(add.isEnabled, "The heading action must respect the same 500-line limit")
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

    /// The one line the editor opened: only an open line carries its description field. Straight
    /// after launch the editor sheet is still on its way, so a launch passes the 20 s that
    /// `launch()` gives the editor to appear.
    private func openLineIdentity(_ app: XCUIApplication, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) -> String {
        let fields = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "invoice-line-description-"))
        XCTAssertTrue(fields.firstMatch.waitForExistence(timeout: timeout), "The last added line must open for editing", file: file, line: line)
        XCTAssertEqual(fields.count, 1, "Exactly one line opens", file: file, line: line)
        return String(fields.firstMatch.identifier.dropFirst("invoice-line-description-".count))
    }

    /// Scrolls `element` clear of the pinned Save draft / Issue invoice bar. At accessibility sizes
    /// that bar covers the lower third of the sheet, and a control under it still reports hittable.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        let bar = app.buttons["Save draft"]
        func clear() -> Bool {
            guard element.isHittable else { return false }
            return !bar.exists || element.frame.maxY <= bar.frame.minY - 4
        }
        for _ in 0..<14 where !clear() {
            // A held drag has no momentum, so the control cannot be flung past the viewport.
            let below = !bar.exists || element.frame.maxY > bar.frame.minY - 4
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: below ? 0.55 : 0.35))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: below ? 0.35 : 0.55)))
        }
        XCTAssertTrue(clear(), app.debugDescription)
    }

    func testCatalogAddsDistinctLinesAndOpensTheLastForEditing() {
        let app = launch()
        let before = lineCount(app)
        let search = openCatalog(app, typing: "Camera sewer inspection")
        let item = app.buttons[itemID]
        XCTAssertTrue(item.waitForExistence(timeout: 10))
        // The item's text remains a direct add target at the standard text size.
        item.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
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

        let close = app.buttons["Close line"].firstMatch
        XCTAssertTrue(close.isHittable, "The line's Done control should be directly reachable while editing")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertFalse(close.frame.intersects(app.keyboards.firstMatch.frame), "The keyboard must not cover the line's Done control")
        let keyboardDone = app.buttons["Done"].firstMatch
        XCTAssertTrue(keyboardDone.exists)
        XCTAssertFalse(close.frame.intersects(keyboardDone.frame), "Keyboard Done must not cover the line's Done control")
        // The keyboard's Done bar takes taps across its whole width, not only on its pill, so the
        // line's own actions have to sit above it.
        XCTAssertLessThanOrEqual(close.frame.maxY, keyboardDone.frame.minY, "The line's Done control must sit above the keyboard's Done bar")
        let remove = app.buttons["Remove"].firstMatch
        XCTAssertTrue(remove.isHittable, "Remove remains available while editing")
        XCTAssertGreaterThanOrEqual(remove.frame.minX - close.frame.maxX, 20, "Separate the destructive action from Done")
        XCTAssertFalse(remove.frame.intersects(keyboardDone.frame), "Keyboard Done must not cover Remove")
        XCTAssertLessThanOrEqual(remove.frame.maxY, keyboardDone.frame.minY, "Remove must sit above the keyboard's Done bar")
        XCTAssertFalse(remove.frame.intersects(app.keyboards.firstMatch.frame), "The keyboard must not cover Remove")
        let saveWhileTyping = app.buttons["Save draft"]
        if saveWhileTyping.exists && saveWhileTyping.isHittable {
            XCTAssertFalse(close.frame.intersects(saveWhileTyping.frame), "Invoice actions must not cover the line's Done control")
        }
        close.tap()
        XCTAssertTrue(quantity.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "Closing the line must dismiss the keyboard")
        let summary = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "for 10", "2,450.00")).firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 5), "The closed line keeps the edited quantity")
        XCTAssertTrue(app.buttons["Save draft"].isHittable)
        XCTAssertTrue(app.buttons["Issue invoice"].isHittable)
    }

    func testClosingFocusedPriceKeepsAndFormatsTheEnteredAmount() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-editor-line"]
        app.launch()
        let identity = openLineIdentity(app, timeout: 20)
        let price = app.textFields["invoice-line-price-" + identity]
        XCTAssertTrue(price.waitForExistence(timeout: 10))
        reveal(price, in: app); price.tap()
        // Focus brings the keyboard up and centres the line; a double tap sent while the page is
        // still moving lands on whatever has slid under it (the next line's minus).
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        settle(price)
        // Replace the amount with the keyboard's own delete key, wherever the caret landed.
        price.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let existing = (price.value as? String) ?? ""
        app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        // An empty field reads as its "0.00" placeholder.
        XCTAssertTrue(["", "0.00"].contains(price.value as? String ?? ""), "The old amount is cleared before typing")
        app.typeText("12.5")
        XCTAssertEqual(price.value as? String, "12.5")
        let close = app.buttons["Close line"].firstMatch
        reveal(close, in: app)
        close.tap()
        XCTAssertTrue(price.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Save draft"].isHittable)
        XCTAssertTrue(app.buttons["Issue invoice"].isHittable)
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Compressor diagnostic", "12.50")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertEqual(app.textFields["invoice-line-price-" + identity].value as? String, "12.50")
    }

    func testLargestTextCanCloseFocusedInvoiceLineAboveKeyboardDone() {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-editor-line",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let identity = openLineIdentity(app, timeout: 20)
        let price = app.textFields["invoice-line-price-" + identity]
        reveal(price, in: app)
        price.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let close = app.buttons["Close line"].firstMatch
        let keyboardDone = app.buttons["Done"].firstMatch
        XCTAssertTrue(keyboardDone.waitForExistence(timeout: 5))
        reveal(close, in: app)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertFalse(close.frame.intersects(keyboardDone.frame))
        XCTAssertFalse(close.frame.intersects(app.keyboards.firstMatch.frame))
        let remove = app.buttons["Remove"].firstMatch
        reveal(remove, in: app)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertFalse(remove.frame.intersects(keyboardDone.frame), "Remove must clear keyboard Done at large text")
        XCTAssertFalse(remove.frame.intersects(app.keyboards.firstMatch.frame), "Remove must clear the keyboard at large text")
        XCTAssertGreaterThanOrEqual(remove.frame.minY - close.frame.maxY, 12, "Separate Remove from line Done at large text")
        reveal(close, in: app)
        XCTAssertFalse(close.frame.intersects(keyboardDone.frame))
        close.tap()
        XCTAssertTrue(price.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Compressor diagnostic")).firstMatch.waitForExistence(timeout: 5))
    }

    func testKeyboardDoneDismissesKeyboardWithoutClosingTheLine() {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-editor-line"]
        app.launch()
        let identity = openLineIdentity(app, timeout: 20)
        let price = app.textFields["invoice-line-price-" + identity]
        reveal(price, in: app)
        price.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let keyboardDone = app.buttons["Done"].firstMatch
        XCTAssertTrue(keyboardDone.waitForExistence(timeout: 5))
        keyboardDone.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(price.exists, "Dismissing the keyboard must keep the item open")
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
        // One read of this screen can take several seconds on a CI simulator (BYR-1836). A wait
        // shorter than a read gets no answer at all: with 5 s the only read was cut off while the
        // app's own log showed the field focused. The condition is the same; the deadline covers
        // more than one read, as openLineIdentity(app, timeout: 20) does on this screen.
        XCTAssertEqual(XCTWaiter.wait(for: [focused], timeout: 20), .completed,
                       "A typed line opens on its price. \(app.debugDescription)")
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

    func testLargeTextCatalogAddControlIsVisibleAndAddsTwiceWithKeyboard() {
        let app = launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "--paper-preview-long-catalog-title"])
        let search = openCatalog(app, typing: "Camera sewer inspection")
        let item = app.buttons[itemID]
        let done = app.buttons["price-book-done"]
        XCTAssertTrue(item.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(item.frame.height, 44, "The add target must remain easy to touch")
        XCTAssertLessThanOrEqual(item.frame.height, 64, "The add control must stay compact even when the item description is long")
        let scroll = app.scrollViews.containing(NSPredicate(format: "identifier == %@", itemID)).firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        // Where the item starts depends on what else the search matches (restored Price Book pages
        // can add results above it), so each drag heads toward the item and covers only the distance
        // left. A slow, held drag leaves no momentum: a fling could carry the item past the viewport,
        // and further drags the same way would only push it further off.
        for _ in 0..<8 {
            if item.isHittable && item.frame.minY >= search.frame.maxY && item.frame.maxY < done.frame.minY { break }
            let upper = search.frame.maxY + 12
            let lower = done.frame.minY - 12
            XCTAssertGreaterThan(lower - upper, 70, "The visible results viewport needs room to scroll above the Done bar")
            let room = lower - upper
            // Positive: the item is below the viewport, so content moves up; negative: it moves down.
            let wanted = item.frame.maxY > lower ? item.frame.maxY - lower + 8 : -(upper - item.frame.minY + 8)
            let distance = max(-room, min(room, wanted))
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = distance > 0 ? lower : upper
            origin.withOffset(CGVector(dx: scroll.frame.midX, dy: start))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: scroll.frame.midX, dy: start - distance)),
                       withVelocity: .slow, thenHoldForDuration: 0.4)
        }
        XCTAssertTrue(item.isHittable)
        XCTAssertGreaterThanOrEqual(item.frame.minY, search.frame.maxY)
        XCTAssertLessThan(item.frame.maxY, done.frame.minY)
        XCTAssertTrue(item.label.contains("Camera sewer inspection"), "The accessibility label identifies the item")
        XCTAssertTrue(item.label.contains("written repair recommendation"), "The accessibility label retains the full long item name")
        XCTAssertTrue(item.label.contains("245"), "The accessibility label includes the price")
        let proof = XCTAttachment(screenshot: app.screenshot())
        proof.name = "Large text price book with separate add target"
        proof.lifetime = .keepAlways
        add(proof)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        item.tap()
        XCTAssertTrue(app.buttons.matching(identifier: itemID).matching(NSPredicate(format: "value == %@", "1 in draft")).firstMatch.waitForExistence(timeout: 5))
        item.tap()
        XCTAssertTrue(app.buttons.matching(identifier: itemID).matching(NSPredicate(format: "value == %@", "2 in draft")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertEqual(search.value as? String, "Camera sewer inspection")
        XCTAssertEqual(done.label, "Done · 2 items")
    }

    func testLargestTextKeepsCatalogEditingAndInvoiceReviewReachable() {
        let app = launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let search = openCatalog(app, typing: "Camera sewer inspection")
        let item = app.buttons[itemID]
        XCTAssertTrue(item.waitForExistence(timeout: 10))
        // A partly visible accessibility row can report hittable while its tap point is
        // covered by the fixed Done bar. Scroll until the center is visibly above it.
        let done = app.buttons["price-book-done"]
        for _ in 0..<10 where !item.isHittable || item.frame.midY >= done.frame.minY {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -50)))
        }
        XCTAssertTrue(item.isHittable)
        XCTAssertLessThan(item.frame.midY, done.frame.minY, "The catalog item's tap point must clear the Done bar")
        item.tap()
        XCTAssertTrue(app.buttons.matching(identifier: itemID).matching(NSPredicate(format: "value == %@", "1 in draft")).firstMatch.waitForExistence(timeout: 5))
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

    /// Waits until `element` has stopped moving (keyboard avoidance and the scroll to the open line).
    private func settle(_ element: XCUIElement, timeout: TimeInterval = 4) {
        let deadline = Date().addingTimeInterval(timeout)
        var last = element.frame
        while Date() < deadline {
            usleep(300_000)
            let now = element.frame
            if now == last { return }
            last = now
        }
    }

    private func replaceQuantity(_ quantity: XCUIElement, with text: String, in app: XCUIApplication) {
        // Select the existing digits with the native touch interaction, then type through the app
        // so XCTest does not move the caret.
        // The editor centres the open line again once the keyboard is up. Select only when the
        // field has stopped moving, or the double tap lands where the field was.
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        var last = quantity.frame
        for _ in 0..<10 {
            usleep(250_000)
            let now = quantity.frame
            if now == last { break }
            last = now
        }
        quantity.doubleTap()
        app.typeText(text)
    }
}

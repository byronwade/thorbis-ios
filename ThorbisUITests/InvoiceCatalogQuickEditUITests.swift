import XCTest

@MainActor
final class InvoiceCatalogQuickEditUITests: XCTestCase {
    func testMatchingCatalogItemPrecedesCustomLineAndCustomLineStillWorksWithoutMatches() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-editor", "--paper-preview-catalog-pages"]
        app.launch()
        let search = app.textFields["Search price book or type a line"]
        XCTAssertTrue(search.waitForExistence(timeout: 20))
        search.tap()
        let category = app.buttons["Category: All"]
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        category.tap()
        app.buttons["Materials"].tap()
        let materials = app.buttons["Category: Materials"]
        XCTAssertTrue(materials.waitForExistence(timeout: 5))
        materials.tap()
        app.buttons["All"].tap()
        search.typeText("Camera sewer inspection")
        let item = app.buttons["price-book-item-00000000-0000-4000-8000-000000009999"]
        let custom = app.buttons["price-book-add-custom"]
        XCTAssertTrue(item.waitForExistence(timeout: 10))
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        XCTAssertLessThan(item.frame.minY, custom.frame.minY)
        app.buttons["Clear search"].tap()
        search.typeText("Unique custom work")
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        XCTAssertTrue(custom.isHittable)
        custom.tap()
        let description = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Line item description"))
            .matching(NSPredicate(format: "value == %@", "Unique custom work")).firstMatch
        XCTAssertTrue(description.waitForExistence(timeout: 5), "The unmatched search must become an editable custom invoice line")
    }

    func testManyMatchesShowAnItemBeforePageNavigation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-editor", "--paper-preview-catalog-many"]
        app.launch()
        let search = app.textFields["Search price book or type a line"]
        XCTAssertTrue(search.waitForExistence(timeout: 20))
        search.tap()
        search.typeText("plumbing")
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "price-book-item-")).firstMatch
        let next = app.buttons["price-book-show-more"]
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        XCTAssertTrue(next.waitForExistence(timeout: 15))
        XCTAssertLessThan(first.frame.minY, next.frame.minY, "An item should appear before page navigation")
        XCTAssertTrue(first.isHittable)
        let proof = XCTAttachment(screenshot: app.screenshot())
        proof.name = "Many matches show an item before navigation"
        proof.lifetime = .keepAlways
        add(proof)
    }

    func testLongDescriptionKeepsPriceAndCompleteDetailsAvailable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-editor", "--paper-preview-catalog-many"]
        app.launch()
        let search = app.textFields["Search price book or type a line"]
        XCTAssertTrue(search.waitForExistence(timeout: 20))
        search.tap()
        search.typeText("Detailed scope")
        let item = app.buttons["price-book-item-00000000-0000-4000-8000-000000009773"]
        XCTAssertTrue(item.waitForExistence(timeout: 15))
        XCTAssertTrue(item.label.contains("$245.00"), "The price must remain in the result")
        XCTAssertTrue(item.label.contains("Finish by testing for leaks"), "The full description must remain accessible")
        let proof = XCTAttachment(screenshot: app.screenshot())
        proof.name = "Long catalog description with price before details"
        proof.lifetime = .keepAlways
        add(proof)
    }

    func testLastAddedLineCanBeEditedWithoutLeavingCatalog() {
        assertLastAddedLineCanBeEdited(extraArguments: [])
    }

    func testLargestTextKeepsQuickEditingAndInvoiceReviewReachable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-editor", "--paper-preview-catalog-pages",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Edit invoice"].waitForExistence(timeout: 20))
        let search = app.textFields["Search price book or type a line"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        let category = app.buttons["Category: All"]
        let searchDone = app.otherElements["invoice-catalog-search"].buttons["Done"]
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        XCTAssertTrue(searchDone.waitForExistence(timeout: 5))
        XCTAssertFalse(search.frame.intersects(category.frame), "Search and category controls must not overlap")
        XCTAssertFalse(search.frame.intersects(searchDone.frame), "Search and Done must not overlap")
        XCTAssertFalse(category.frame.intersects(searchDone.frame), "Category and Done must not overlap")
        search.typeText("Camera sewer inspection")
        let item = app.buttons["price-book-item-00000000-0000-4000-8000-000000009999"]
        XCTAssertTrue(item.waitForExistence(timeout: 10))
        XCTAssertTrue(item.label.contains("Add"), "Catalog results should make the one-tap add action clear")
        item.tap()
        let added = app.otherElements["invoice-added-line-editor"]
        XCTAssertTrue(added.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertFalse(app.buttons["Save draft"].exists)
        XCTAssertFalse(app.buttons["Issue invoice"].exists)
        added.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Edit added line")).firstMatch.tap()
        let description = added.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "invoice-line-description-")).firstMatch
        XCTAssertTrue(description.waitForExistence(timeout: 5))
        let identity = String(description.identifier.dropFirst("invoice-line-description-".count))
        let quantity = added.otherElements["invoice-line-quantity-" + identity].textFields.firstMatch
        let searchBar = app.otherElements["invoice-catalog-search"]
        revealControl(quantity, below: searchBar, in: app)
        XCTAssertGreaterThan(quantity.frame.width, 200, "Accessibility quantity editing must have room for the full value")
        let price = added.textFields["Unit price in dollars"]
        XCTAssertEqual(price.value as? String, "245.00")
        XCTAssertGreaterThan(price.frame.width, 200, "The full unit price must fit without a clipped money well")
        quantity.tap()
        XCTAssertTrue(app.keyboards.keys["0"].waitForExistence(timeout: 5))
        // Keyboard presentation can move the field; reveal it again before editing.
        revealControl(quantity, below: searchBar, in: app)
        XCTAssertEqual(quantity.value as? String, "1")
        replaceQuantityWithTen(quantity, in: app)
        XCTAssertEqual(quantity.value as? String, "10")
        let editingProof = XCTAttachment(screenshot: app.screenshot())
        editingProof.name = "Largest text quantity editing above the keyboard after scrolling"
        editingProof.lifetime = .keepAlways
        add(editingProof)
        revealControl(price, below: searchBar, in: app)
        XCTAssertEqual(price.value as? String, "245.00")
        price.tap()
        XCTAssertTrue(app.keyboards.keys["0"].waitForExistence(timeout: 5))
        revealControl(price, below: searchBar, in: app)
        XCTAssertEqual(price.value as? String, "245.00")
        price.doubleTap()
        app.typeText("275.00")
        XCTAssertEqual(price.value as? String, "275.00", "The unit price must be editable at the largest text size")
        let priceProof = XCTAttachment(screenshot: app.screenshot())
        priceProof.name = "Largest text full unit price above the decimal keyboard"
        priceProof.lifetime = .keepAlways
        add(priceProof)
        searchBar.buttons["Back to results"].tap()
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertEqual(search.value as? String, "Camera sewer inspection")
        searchBar.buttons["Done"].tap()
        XCTAssertFalse(added.exists)
        XCTAssertTrue(app.buttons["Save draft"].isHittable)
        XCTAssertTrue(app.buttons["Issue invoice"].isHittable)
        XCTAssertGreaterThan(app.buttons["Save draft"].frame.width, 300, "Save draft must have room for its full label")
        XCTAssertLessThanOrEqual(app.buttons["Save draft"].frame.maxY, app.buttons["Issue invoice"].frame.minY)
        XCTAssertEqual(app.otherElements["invoice-line-quantity-" + identity].textFields.firstMatch.value as? String, "10")
        let reviewProof = XCTAttachment(screenshot: app.screenshot())
        reviewProof.name = "Largest text return to invoice review actions"
        reviewProof.lifetime = .keepAlways
        add(reviewProof)
    }

    private func assertLastAddedLineCanBeEdited(extraArguments: [String]) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-editor", "--paper-preview-catalog-pages"] + extraArguments
        app.launch()
        XCTAssertTrue(app.navigationBars["Edit invoice"].waitForExistence(timeout: 20))
        let search = app.textFields["Search price book or type a line"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("Camera sewer inspection")
        let item = app.buttons["price-book-item-00000000-0000-4000-8000-000000009999"]
        XCTAssertTrue(item.waitForExistence(timeout: 10))
        item.tap()

        let added = app.otherElements["invoice-added-line-editor"]
        XCTAssertTrue(added.waitForExistence(timeout: 5), "The exact added line must be editable beside catalog results")
        XCTAssertTrue(item.isHittable, "The compact addition summary must leave the catalog reachable with the keyboard visible")
        added.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Edit added line")).firstMatch.tap()
        let description = added.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "invoice-line-description-")).firstMatch
        XCTAssertTrue(description.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Save draft"].exists, "Commit actions must not cover quick-edit fields")
        XCTAssertFalse(app.buttons["Issue invoice"].exists)
        let firstIdentity = String(description.identifier.dropFirst("invoice-line-description-".count))
        XCTAssertFalse(firstIdentity.isEmpty)
        let quantity = added.otherElements["invoice-line-quantity-" + firstIdentity].textFields.firstMatch
        XCTAssertEqual(quantity.value as? String, "1")
        XCTAssertTrue(quantity.isHittable, app.debugDescription)
        quantity.tap()
        XCTAssertTrue(app.keyboards.keys["0"].waitForExistence(timeout: 5), "The quantity field must acquire its numeric keyboard before editing")
        replaceQuantityWithTen(quantity, in: app)
        XCTAssertEqual(quantity.value as? String, "10")
        XCTAssertEqual(search.value as? String, "Camera sewer inspection")
        XCTAssertTrue(app.buttons.matching(identifier: item.identifier).matching(NSPredicate(format: "value == %@", "10 in draft")).firstMatch.waitForExistence(timeout: 5))

        search.tap()
        app.buttons["Clear search"].tap()
        XCTAssertTrue(added.waitForNonExistence(timeout: 5), "A new search must not leave the previous line selected")
        search.typeText("Camera sewer inspection")
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()
        XCTAssertTrue(added.waitForExistence(timeout: 5))
        added.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Edit added line")).firstMatch.tap()
        let secondDescription = added.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "invoice-line-description-")).firstMatch
        XCTAssertTrue(secondDescription.waitForExistence(timeout: 5))
        let secondIdentity = String(secondDescription.identifier.dropFirst("invoice-line-description-".count))
        XCTAssertNotEqual(firstIdentity, secondIdentity, "Repeating an invoice selection must add a distinct line")
        XCTAssertEqual(added.otherElements["invoice-line-quantity-" + secondIdentity].textFields.firstMatch.value as? String, "1")
        XCTAssertTrue(app.buttons.matching(identifier: item.identifier).matching(NSPredicate(format: "value == %@", "11 in draft")).firstMatch.waitForExistence(timeout: 5))
        app.otherElements["invoice-catalog-search"].buttons["Done"].tap()
        XCTAssertFalse(added.exists)
        XCTAssertTrue(app.buttons["Save draft"].isHittable)
        XCTAssertTrue(app.buttons["Issue invoice"].isHittable)
        XCTAssertEqual(app.otherElements["invoice-line-quantity-" + firstIdentity].textFields.firstMatch.value as? String, "10")
        XCTAssertEqual(app.otherElements["invoice-line-quantity-" + secondIdentity].textFields.firstMatch.value as? String, "1")
        XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ AND value == %@", "invoice-line-description-", "Camera sewer inspection")).count, 2)
    }

    private func revealControl(_ control: XCUIElement, below searchBar: XCUIElement, in app: XCUIApplication) {
        // The keyboard's AX frame omits its prediction and accessory bars on this simulator.
        // Scroll in the direction needed; a control above the viewport needs a downward drag.
        for _ in 0..<8 {
            let visibleTop = searchBar.frame.maxY + 8
            let keyboard = app.keyboards.firstMatch
            let accessoryHeight: CGFloat = keyboard.keys["Q"].exists ? 88 : 44
            let visibleBottom = keyboard.exists ? keyboard.frame.minY - accessoryHeight : app.frame.maxY - 16
            let frame = control.frame
            if frame.minY >= visibleTop && frame.maxY <= visibleBottom { break }
            let space = visibleBottom - visibleTop
            XCTAssertGreaterThan(space, 44, "The editor must have a usable scrolling area")
            let startY = (visibleTop + visibleBottom) / 2
            let required = frame.minY < visibleTop ? visibleTop - frame.minY : frame.maxY - visibleBottom
            let distance = max(40, min(required + 12, space / 2))
            let direction: CGFloat = frame.minY < visibleTop ? 1 : -1
            let start = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: app.frame.maxX - 10, dy: startY))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: direction * distance)))
        }
        let keyboard = app.keyboards.firstMatch
        let accessoryHeight: CGFloat = keyboard.keys["Q"].exists ? 88 : 44
        let visibleBottom = keyboard.exists ? keyboard.frame.minY - accessoryHeight : app.frame.maxY - 16
        XCTAssertGreaterThanOrEqual(control.frame.minY, searchBar.frame.maxY)
        XCTAssertLessThanOrEqual(control.frame.maxY, visibleBottom)
        XCTAssertTrue(control.isHittable, app.debugDescription)
    }

    private func replaceQuantityWithTen(_ quantity: XCUIElement, in app: XCUIApplication) {
        // Select the existing single digit using the native touch interaction.
        // Type through the application so XCTest does not reposition the field caret.
        quantity.doubleTap()
        app.typeText("10")
    }

    func testRepeatedInlineAddsKeepCatalogReachableWithKeyboard() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-editor", "--paper-preview-catalog-pages"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Edit invoice"].waitForExistence(timeout: 20))
        let search = app.textFields["Search price book or type a line"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("Camera sewer inspection")
        let item = app.buttons["price-book-item-00000000-0000-4000-8000-000000009999"]
        XCTAssertTrue(item.waitForExistence(timeout: 10))
        item.tap()
        XCTAssertTrue(app.otherElements["invoice-added-line-editor"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertTrue(item.isHittable, "Adding another item must not require closing the keyboard or editor")
        // The screenshot for this simulator places the toolbar and keyboard prediction
        // area above the keyboard AX frame. Check this short fixture, not arbitrary long rows.
        XCTAssertLessThanOrEqual(item.frame.maxY, app.keyboards.firstMatch.frame.minY - 88,
                                 "The result, including its price and Add cue, must remain above the keyboard accessory")
        item.tap()
        XCTAssertTrue(app.buttons.matching(identifier: item.identifier).matching(NSPredicate(format: "value == %@", "2 in draft")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(item.label.contains("Add"), "Adding once must not make the row look unavailable for another addition")
        XCTAssertTrue(item.isHittable)
        XCTAssertEqual(search.value as? String, "Camera sewer inspection")
        let proof = XCTAttachment(screenshot: app.screenshot())
        proof.name = "Compact last-added line keeps invoice catalog reachable"
        proof.lifetime = .keepAlways
        add(proof)
    }

}

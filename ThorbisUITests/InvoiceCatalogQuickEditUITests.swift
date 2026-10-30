import XCTest

@MainActor
final class InvoiceCatalogQuickEditUITests: XCTestCase {
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
        replaceQuantityWithTen(quantity, in: app)
        XCTAssertEqual(quantity.value as? String, "10")
        XCTAssertEqual(search.value as? String, "Camera sewer inspection")
        let editingProof = XCTAttachment(screenshot: app.screenshot())
        editingProof.name = "Largest text quantity editing above the keyboard after scrolling"
        editingProof.lifetime = .keepAlways
        add(editingProof)
        revealControl(price, below: searchBar, in: app)
        XCTAssertEqual(price.value as? String, "245.00")
        price.tap()
        XCTAssertTrue(app.keyboards.keys["0"].waitForExistence(timeout: 5))
        XCTAssertEqual(price.value as? String, "245.00")
        let priceProof = XCTAttachment(screenshot: app.screenshot())
        priceProof.name = "Largest text full unit price above the decimal keyboard"
        priceProof.lifetime = .keepAlways
        add(priceProof)
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
        // Large text requires normal content scrolling; interactive dismissal may hide the keyboard.
        for _ in 0..<8 {
            let visibleTop = searchBar.frame.maxY + 8
            // The keyboard AX frame starts below its predictive/accessory surfaces.
            // Keep the gesture in the upper half of the header-to-keyboard interval.
            let keyboard = app.keyboards.firstMatch
            let visibleBottom = keyboard.exists
                ? (searchBar.frame.maxY + keyboard.frame.minY) / 2
                : app.frame.maxY - 16
            if control.frame.minY >= visibleTop && control.frame.maxY <= visibleBottom { break }
            let distance = min(control.frame.maxY - visibleBottom + 8, visibleBottom - visibleTop - 16)
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.midX, dy: visibleBottom - 8))
            let end = start.withOffset(CGVector(dx: 0, dy: -distance))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertGreaterThanOrEqual(control.frame.minY, searchBar.frame.maxY)
        XCTAssertLessThan(control.frame.maxY, app.frame.maxY - 16)
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

import XCTest

@MainActor
final class InvoiceCatalogQuickEditUITests: XCTestCase {
    func testLastAddedLineCanBeEditedWithoutLeavingCatalog() {
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

        let added = app.otherElements["invoice-added-line-editor"]
        XCTAssertTrue(added.waitForExistence(timeout: 5), "The exact added line must be editable beside catalog results")
        XCTAssertTrue(item.isHittable, "The compact addition summary must leave the catalog reachable with the keyboard visible")
        added.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Edit added line")).firstMatch.tap()
        let description = added.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "invoice-line-description-")).firstMatch
        XCTAssertTrue(description.waitForExistence(timeout: 5))
        let firstIdentity = String(description.identifier.dropFirst("invoice-line-description-".count))
        XCTAssertFalse(firstIdentity.isEmpty)
        let quantity = added.otherElements["invoice-line-quantity-" + firstIdentity].textFields.firstMatch
        XCTAssertEqual(quantity.value as? String, "1")
        XCTAssertTrue(quantity.isHittable, app.debugDescription)
        quantity.tap()
        XCTAssertTrue(app.keyboards.keys["0"].waitForExistence(timeout: 5), "The quantity field must acquire its numeric keyboard before editing")
        quantity.typeKey(XCUIKeyboardKey.rightArrow.rawValue, modifierFlags: .command)
        quantity.typeText("0")
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
        XCTAssertEqual(app.otherElements["invoice-line-quantity-" + firstIdentity].textFields.firstMatch.value as? String, "10")
        XCTAssertEqual(app.otherElements["invoice-line-quantity-" + secondIdentity].textFields.firstMatch.value as? String, "1")
        XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ AND value == %@", "invoice-line-description-", "Camera sewer inspection")).count, 2)
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
        XCTAssertTrue(item.isHittable)
        XCTAssertEqual(search.value as? String, "Camera sewer inspection")
        let proof = XCTAttachment(screenshot: app.screenshot())
        proof.name = "Compact last-added line keeps invoice catalog reachable"
        proof.lifetime = .keepAlways
        add(proof)
    }

}

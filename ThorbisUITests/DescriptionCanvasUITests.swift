import XCTest

@MainActor
final class DescriptionCanvasUITests: XCTestCase {
    private func makeDescriptionLong(_ app: XCUIApplication, label: String) {
        let field = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
        for _ in 0..<6 where !field.isHittable { app.swipeUp() }
        XCTAssertTrue(field.isHittable)
        field.tap()
        field.typeText(String(repeating: "x", count: 105))
        let done = app.toolbars.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
    }
    func testEstimateDescriptionCanvasAppliesWithoutSavingAndCancelKeepsOriginal() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "estimate-revision"]
        app.launch()
        XCTAssertTrue(app.textFields["Option package title"].waitForExistence(timeout: 30))
        makeDescriptionLong(app, label: "Line description")
        let expand = app.buttons.matching(identifier: "estimate-line-description-more").firstMatch
        XCTAssertTrue(expand.exists)
        for _ in 0..<6 where !expand.isHittable { app.swipeUp() }
        XCTAssertTrue(expand.isHittable)
        expand.tap()
        let editor = app.textViews["description-canvas-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Estimate description canvas"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let original = editor.value as? String ?? ""
        editor.tap()
        editor.typeText(" appended")
        app.navigationBars["Line description"].buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Discard changes"].waitForExistence(timeout: 5))
        app.buttons["Discard changes"].tap()
        expand.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, original)
        editor.tap()
        editor.typeText(" revised")
        app.navigationBars["Line description"].buttons["Apply to estimate"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "revised")).firstMatch.waitForExistence(timeout: 5) || app.textViews.matching(NSPredicate(format: "value CONTAINS %@", "revised")).firstMatch.exists || app.textFields.matching(NSPredicate(format: "value CONTAINS %@", "revised")).firstMatch.exists)
    }
    func testReplacingEstimateRetiresOpenOptionCanvasEvenIfOptionIDIsReused() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "estimate-revision", "--canvas-test-replacement"]
        app.launch()
        XCTAssertTrue(app.textFields["Option package title"].waitForExistence(timeout: 30))
        let open = app.buttons.matching(identifier: "estimate-option-description-more").firstMatch
        for _ in 0..<8 where !open.isHittable { app.swipeUp() }
        XCTAssertTrue(open.isHittable)
        open.tap()
        let editor = app.textViews["description-canvas-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        editor.typeText(" unsaved")
        app.buttons["Test replace"].tap()
        XCTAssertTrue(app.staticTexts["Editor unavailable"].waitForExistence(timeout: 5))
        XCTAssertFalse(editor.exists)
        XCTAssertFalse(app.buttons["Apply to estimate"].isEnabled)
        app.navigationBars["Description"].buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Discard changes"].waitForExistence(timeout: 5))
        app.buttons["Discard changes"].tap()
    }

    func testRevokedAuthorityRetiresUnappliedCanvasEvenAfterRestore() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "estimate-revision", "--canvas-test-authority"]
        app.launch()
        XCTAssertTrue(app.textFields["Option package title"].waitForExistence(timeout: 30))
        let open = app.buttons.matching(identifier: "estimate-line-description-more").firstMatch
        for _ in 0..<6 where !open.isHittable { app.swipeUp() }
        XCTAssertTrue(open.isHittable)
        open.tap()
        let editor = app.textViews["description-canvas-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        editor.typeText(" unsaved")
        app.buttons["Test revoke"].tap()
        XCTAssertTrue(app.staticTexts["Editor unavailable"].waitForExistence(timeout: 5))
        XCTAssertFalse(editor.exists)
        app.buttons["Test restore"].tap()
        XCTAssertTrue(app.staticTexts["Editor unavailable"].exists)
        XCTAssertFalse(editor.exists)
        XCTAssertFalse(app.buttons["Apply to estimate"].isEnabled)
        app.navigationBars["Description"].buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Discard changes"].waitForExistence(timeout: 5))
        app.buttons["Discard changes"].tap()
    }

    func testNewEstimateCanvasAppliesToLiveLine() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "new-estimate", "--paper-preview-catalog-pages"]
        app.launch()
        let search = app.textFields["Search price book or type a line"]
        XCTAssertTrue(search.waitForExistence(timeout: 30))
        search.tap()
        search.typeText("Replace capacitor")
        let item = app.buttons["price-book-item-00000000-0000-4000-8000-000000009201"]
        XCTAssertTrue(item.waitForExistence(timeout: 15))
        item.tap()
        app.buttons["Review estimate · 1 item"].tap()
        makeDescriptionLong(app, label: "Line description")
        let more = app.buttons.matching(identifier: "estimate-line-description-more").firstMatch
        for _ in 0..<6 where !more.isHittable { app.swipeUp() }
        XCTAssertTrue(more.isHittable)
        more.tap()
        let editor = app.textViews["description-canvas-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        editor.typeText(" revised")
        app.navigationBars["Line description"].buttons["Apply to estimate"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "revised", "revised")).firstMatch.waitForExistence(timeout: 5))
    }

    func testRemovingInvoiceLineRetiresOpenCanvasWithoutApplying() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-editor", "--paper-preview-catalog-pages", "--canvas-test-removal"]
        app.launch()
        let search = app.textFields["Search price book or type a line"]
        XCTAssertTrue(search.waitForExistence(timeout: 30))
        search.tap()
        search.typeText("Camera sewer inspection")
        let item = app.buttons["price-book-item-00000000-0000-4000-8000-000000009999"]
        XCTAssertTrue(item.waitForExistence(timeout: 15))
        item.tap()
        let added = app.otherElements["invoice-added-line-editor"]
        XCTAssertTrue(added.waitForExistence(timeout: 10))
        added.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Edit added line")).firstMatch.tap()
        let open = added.buttons["invoice-line-description-more"]
        for _ in 0..<5 where !open.isHittable { app.swipeUp() }
        XCTAssertTrue(open.isHittable)
        open.tap()
        let editor = app.textViews["description-canvas-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        editor.typeText(" unsaved")
        app.buttons["Test remove"].tap()
        XCTAssertTrue(app.staticTexts["Editor unavailable"].waitForExistence(timeout: 5))
        XCTAssertFalse(editor.exists)
        XCTAssertFalse(app.buttons["Apply to invoice"].isEnabled)
        app.navigationBars["Description"].buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Discard changes"].waitForExistence(timeout: 5))
        app.buttons["Discard changes"].tap()
        XCTAssertFalse(added.exists)
    }

    func testInvoiceCanvasEditsAnAddedLineAndReturnsToCatalog() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-editor", "--paper-preview-catalog-pages"]
        app.launch()
        let search = app.textFields["Search price book or type a line"]
        XCTAssertTrue(search.waitForExistence(timeout: 30))
        search.tap()
        search.typeText("Camera sewer inspection")
        let item = app.buttons["price-book-item-00000000-0000-4000-8000-000000009999"]
        XCTAssertTrue(item.waitForExistence(timeout: 15))
        item.tap()
        let added = app.otherElements["invoice-added-line-editor"]
        XCTAssertTrue(added.waitForExistence(timeout: 10))
        added.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Edit added line")).firstMatch.tap()
        makeDescriptionLong(app, label: "Line item description")
        let more = added.buttons["invoice-line-description-more"]
        for _ in 0..<5 where !more.isHittable { app.swipeUp() }
        XCTAssertTrue(more.isHittable)
        more.tap()
        let editor = app.textViews["description-canvas-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        editor.typeText(" revised")
        app.navigationBars["Line item description"].buttons["Apply to invoice"].tap()
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        let updated = added.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "revised", "revised")).firstMatch
        XCTAssertTrue(updated.waitForExistence(timeout: 5))
    }

    func testLargestTextCanvasKeepsOverLimitTextWithoutApplying() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "estimate-revision", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.textFields["Estimate title"].waitForExistence(timeout: 30))
        makeDescriptionLong(app, label: "Line description")
        let more = app.buttons.matching(identifier: "estimate-line-description-more").firstMatch
        for _ in 0..<8 where !more.isHittable { app.swipeUp() }
        XCTAssertTrue(more.isHittable)
        more.tap()
        let editor = app.textViews["description-canvas-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        editor.typeText(String(repeating: "x", count: 205))
        let apply = app.navigationBars["Line description"].buttons["Apply to estimate"]
        XCTAssertFalse(apply.isEnabled)
        XCTAssertTrue((editor.value as? String ?? "").contains(String(repeating: "x", count: 205)))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Description canvas at largest text"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.navigationBars["Line description"].buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Discard changes"].waitForExistence(timeout: 5))
        app.buttons["Discard changes"].tap()
    }

}

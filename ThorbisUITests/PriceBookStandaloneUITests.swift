import XCTest

@MainActor
final class PriceBookStandaloneUITests: XCTestCase {
    func testLongItemAndHighPriceRemainVisibleInNarrowList() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "price-book", "--paper-preview-pricebook-long", "--paper-preview-pricebook-extreme", "-thorbis.appearance", "dark"]
        app.launch()
        let title = app.staticTexts["Commercial plumbing system inspection and complete replacement."]
        XCTAssertTrue(title.waitForExistence(timeout: 30))
        let price = app.staticTexts["$1,234,567.89"]
        XCTAssertTrue(price.exists)
        XCTAssertGreaterThan(title.frame.width, 240, "The amount must not crowd a long item name into an unreadably narrow column.")
        XCTAssertGreaterThan(price.frame.width, 0)
        capture("Price book narrow long title and high price")
    }

    func testStaleLongDescriptionRemainsReadableAtLargestText() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "price-book", "--paper-preview-pricebook-long", "--paper-preview-pricebook-extreme", "--paper-preview-pricebook-authority", "--paper-preview-pricebook-renew", "--paper-preview-pricebook-stable", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["Change sample access shortly"].waitForExistence(timeout: 30))
        app.buttons["Change sample access shortly"].tap()
        XCTAssertTrue(app.staticTexts["Showing previously loaded items. Refresh to update."].waitForExistence(timeout: 20))
        let description = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Final paragraph of the complete description.")).firstMatch
        XCTAssertTrue(description.exists)
        XCTAssertGreaterThan(description.frame.height, 200)
        capture("Stale description before scrolling")
        for index in 0..<30 {
            if app.staticTexts["$1,234,567.89"].isHittable { break }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.80))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.66))
            start.press(forDuration: 0.1, thenDragTo: end)
            capture("Stale description scroll \(index + 1)")
        }
        XCTAssertTrue(app.staticTexts["$1,234,567.89"].isHittable)
        capture("Price book stale long description and high price, largest text")
    }

    func testLargeTextKeepsItemAndPriceReadableAndOpensFullDescription() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "price-book", "--paper-preview-pricebook-long", "-thorbis.appearance", "dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let title = app.staticTexts["PEX copper crimp ring pack: 1-in."]
        XCTAssertTrue(title.waitForExistence(timeout: 30))
        for _ in 0..<8 where !title.isHittable { app.swipeUp() }
        XCTAssertTrue(title.isHittable)
        let price = app.staticTexts["$15.13"]
        XCTAssertTrue(price.exists)
        // The amount is one line of the same 15pt size (#212's compact ramp shrank both, so a fixed
        // 110pt floor no longer meant "wraps"): the name must take clearly more than one line.
        XCTAssertGreaterThan(title.frame.height, price.frame.height * 1.5, "The complete item name must wrap at the largest text size.")
        XCTAssertGreaterThanOrEqual(price.frame.minY, title.frame.maxY, "At the largest text size, the amount should have room below the item name.")
        capture("Price book largest text title")
        for _ in 0..<8 where !price.isHittable { app.swipeUp() }
        XCTAssertTrue(price.isHittable)
        capture("Price book largest text amount")
        for _ in 0..<8 where !title.isHittable { app.swipeDown() }
        XCTAssertTrue(title.isHittable)
        title.tap()
        let details = app.staticTexts["PEX copper crimp ring pack: 1-in. Ten rings for matching-size PEX; tool calibration remains required."]
        XCTAssertTrue(details.waitForExistence(timeout: 10))
    }

    private func launch(admin: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "price-book", "--paper-preview-pricebook-long"]
        if admin { app.launchArguments.append("--paper-preview-pricebook-admin") }
        app.launch()
        return app
    }

    /// Since the 2026-10-30 design pass the category chips live behind the header's filter circle
    /// (one selector per screen): open it and choose the category there.
    private func chooseCategory(_ name: String, in app: XCUIApplication) {
        let filter = app.buttons["header-filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5))
        filter.tap()
        let choice = app.buttons[name]
        XCTAssertTrue(choice.waitForExistence(timeout: 5), app.debugDescription)
        choice.tap()
        XCTAssertTrue(choice.waitForNonExistence(timeout: 5))
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testReadableListAndFullDetailsWithoutAdministrativeAccess() {
        continueAfterFailure = false
        let app = launch()
        let title = app.staticTexts["PEX copper crimp ring pack: 1-in."]
        XCTAssertTrue(title.waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["$15.13"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "thorbis-plumbing-demo-v1")).firstMatch.exists)
        capture("Price book with compact item")
        title.tap()
        let details = app.staticTexts["PEX copper crimp ring pack: 1-in. Ten rings for matching-size PEX; tool calibration remains required."]
        XCTAssertTrue(details.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "thorbis-plumbing-demo-v1")).firstMatch.exists)
        capture("Price book full description")
    }

    func testAdministrativeDetailAndGroupDisclosure() {
        continueAfterFailure = false
        let app = launch(admin: true)
        let title = app.staticTexts["PEX copper crimp ring pack: 1-in."]
        XCTAssertTrue(title.waitForExistence(timeout: 30))
        let group = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Material, 1")).firstMatch
        XCTAssertTrue(group.exists)
        group.tap()
        XCTAssertFalse(title.exists)
        group.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Add price book item"].exists)
        capture("Price book admin grouped list")
        title.tap()
        let details = app.staticTexts["PEX copper crimp ring pack: 1-in. Ten rings for matching-size PEX; tool calibration remains required."]
        XCTAssertTrue(details.waitForExistence(timeout: 10))
        capture("Price book admin item detail")
        XCTAssertTrue(app.buttons["Edit"].exists)
        app.buttons["Edit"].tap()
        XCTAssertTrue(app.textFields.matching(NSPredicate(format: "value CONTAINS %@", "[thorbis-plumbing-demo-v1:material-049]")).firstMatch.waitForExistence(timeout: 10))
    }

    func testMixedCatalogInDarkModeShowsReadableGroupedRows() {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "price-book", "--paper-preview-pricebook-long", "--paper-preview-pricebook-many", "--paper-preview-pricebook-admin", "-thorbis.appearance", "dark"]
        app.launch()
        XCTAssertTrue(app.staticTexts["PEX copper crimp ring pack: 1-in."].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Copper reducer: 1-1/4 × 1-in."].exists)
        XCTAssertTrue(app.buttons["Add price book item"].exists)
        capture("Price book grouped dark catalog")
    }

    func testIncompleteListClearlyIdentifiesLoadedScope() {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "price-book", "--paper-preview-pricebook-long", "--paper-preview-pricebook-partial"]
        app.launch()
        XCTAssertTrue(app.staticTexts["1 item loaded"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Material, 1 loaded")).firstMatch.exists)
        // The category choices sit behind the header's filter circle; All says the count is partial.
        app.buttons["header-filter"].tap()
        let all = app.buttons["All · 1 loaded"]
        XCTAssertTrue(all.waitForExistence(timeout: 5))
        all.tap()
        XCTAssertTrue(all.waitForNonExistence(timeout: 5))
        let search = app.textFields["Search price book"]
        search.tap()
        search.typeText("not in loaded items")
        XCTAssertTrue(app.staticTexts["No loaded items match. Load more items to search the rest."].waitForExistence(timeout: 10))
    }

    func testSearchRevealsMatchingItemsAfterGroupIsCollapsed() {
        let app = launch()
        let title = app.staticTexts["PEX copper crimp ring pack: 1-in."]
        XCTAssertTrue(title.waitForExistence(timeout: 30))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Material, 1")).firstMatch.tap()
        XCTAssertFalse(title.exists)
        let search = app.textFields["Search price book"]
        search.tap()
        search.typeText("PEX")
        XCTAssertTrue(title.waitForExistence(timeout: 10))
    }

    func testChoosingCollapsedCategoryRevealsItsItems() {
        let app = launch()
        let title = app.staticTexts["PEX copper crimp ring pack: 1-in."]
        XCTAssertTrue(title.waitForExistence(timeout: 30))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Material, 1")).firstMatch.tap()
        XCTAssertFalse(title.exists)
        chooseCategory("Material", in: app)
        XCTAssertTrue(title.waitForExistence(timeout: 5))
    }

    func testChoosingAllRevealsPreviouslyCollapsedGroups() {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "price-book", "--paper-preview-pricebook-long", "--paper-preview-pricebook-many"]
        app.launch()
        let title = app.staticTexts["PEX copper crimp ring pack: 1-in."]
        XCTAssertTrue(title.waitForExistence(timeout: 30))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Material, 4")).firstMatch.tap()
        XCTAssertFalse(title.exists)
        chooseCategory("Service", in: app)
        chooseCategory("All · 6", in: app)
        XCTAssertTrue(title.waitForExistence(timeout: 5))
    }

    func testCopyNameAction() {
        let app = launch()
        let title = app.staticTexts["PEX copper crimp ring pack: 1-in."]
        XCTAssertTrue(title.waitForExistence(timeout: 30))
        title.press(forDuration: 1.0)
        app.buttons["Copy name"].tap()
    }

    func testCopyFullDescriptionAction() {
        let app = launch()
        let title = app.staticTexts["PEX copper crimp ring pack: 1-in."]
        XCTAssertTrue(title.waitForExistence(timeout: 30))
        title.press(forDuration: 1.0)
        app.buttons["Copy full description"].tap()
    }

    func testCopyStoredTextAction() {
        let app = launch()
        let title = app.staticTexts["PEX copper crimp ring pack: 1-in."]
        XCTAssertTrue(title.waitForExistence(timeout: 30))
        title.press(forDuration: 1.0)
        app.buttons["Copy stored text"].tap()
    }

    func testPermissionRevocationRetiresOpenLocalDetail() {
        assertAuthorityChangeRetiresDetail(switchWorkspace: false)
    }

    func testAuthorityRenewalReloadsListWithoutReusingOldItems() {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "price-book", "--paper-preview-pricebook-long", "--paper-preview-pricebook-authority", "--paper-preview-pricebook-renew", "--paper-preview-pricebook-cache-test"]
        app.launch()
        let old = app.staticTexts["PEX copper crimp ring pack: 1-in."]
        XCTAssertTrue(old.waitForExistence(timeout: 30))
        app.buttons["Change sample access shortly"].tap()
        XCTAssertTrue(app.staticTexts["Showing previously loaded items. Refresh to update."].waitForExistence(timeout: 20))
        app.buttons["Refresh"].tap()
        XCTAssertTrue(app.staticTexts["Updated PEX rings."].waitForExistence(timeout: 20), "A new authority revision must fetch a new authorized list")
        XCTAssertFalse(old.exists)
    }

    func testUnchangedAuthorityAndFailedRefreshKeepsPreviouslyLoadedPages() {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "price-book", "--paper-preview-pricebook-long", "--paper-preview-pricebook-authority", "--paper-preview-pricebook-renew", "--paper-preview-pricebook-stable", "--paper-preview-pricebook-pages", "--paper-preview-pricebook-refresh-failure"]
        app.launch()
        let first = app.staticTexts["PEX copper crimp ring pack: 1-in."]
        XCTAssertTrue(first.waitForExistence(timeout: 30))
        app.buttons["Material, 50 loaded"].tap()
        app.buttons["Load more items"].tap()
        XCTAssertTrue(app.staticTexts["51 items"].waitForExistence(timeout: 10))
        app.buttons["Change sample access shortly"].tap()
        XCTAssertTrue(app.staticTexts["Showing previously loaded items. Refresh to update."].waitForExistence(timeout: 20))
        app.buttons["Refresh"].tap()
        XCTAssertTrue(app.staticTexts["The price book couldn't be loaded."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["51 items"].exists)
        app.buttons["Material, 51"].tap()
        XCTAssertTrue(app.staticTexts["PEX copper crimp ring pack: 1-in. Ten rings for matching-size PEX; tool calibration remains required."].exists)
    }

    func testLoadMoreAfterAuthorityRenewalPreservesLoadedPage() {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "price-book", "--paper-preview-pricebook-long", "--paper-preview-pricebook-authority", "--paper-preview-pricebook-renew", "--paper-preview-pricebook-stable", "--paper-preview-pricebook-pages"]
        app.launch()
        XCTAssertTrue(app.buttons["Material, 50 loaded"].waitForExistence(timeout: 30))
        app.buttons["Material, 50 loaded"].tap()
        app.buttons["Change sample access shortly"].tap()
        XCTAssertTrue(app.staticTexts["Showing previously loaded items. Refresh to update."].waitForExistence(timeout: 20))
        app.buttons["Load more items"].tap()
        XCTAssertTrue(app.staticTexts["51 items"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Showing previously loaded items. Refresh to update."].exists)
    }

    func testDelayedListCanBeRefreshedAfterAuthorityRenewal() {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "price-book", "--paper-preview-pricebook-long", "--paper-preview-pricebook-authority", "--paper-preview-pricebook-renew", "--paper-preview-pricebook-delayed"]
        app.launch()
        let change = app.buttons["Change sample access shortly"]
        XCTAssertTrue(change.waitForExistence(timeout: 30))
        change.tap()
        let stale = app.staticTexts["Showing previously loaded items. Refresh to update."]
        if stale.waitForExistence(timeout: 12) { app.buttons["Refresh"].tap() }
        let updated = app.staticTexts["Updated PEX rings."]
        XCTAssertTrue(updated.waitForExistence(timeout: 25))
        sleep(5) // Let the deliberately delayed old response complete.
        XCTAssertTrue(updated.exists)
        XCTAssertFalse(app.staticTexts["PEX copper crimp ring pack: 1-in."].exists)
    }

    func testWorkspaceSwitchRetiresOpenLocalDetail() {
        assertAuthorityChangeRetiresDetail(switchWorkspace: true)
    }

    private func assertAuthorityChangeRetiresDetail(switchWorkspace: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "price-book", "--paper-preview-pricebook-long", "--paper-preview-pricebook-authority"]
        if switchWorkspace { app.launchArguments.append("--paper-preview-pricebook-switch") }
        app.launch()
        let title = app.staticTexts["PEX copper crimp ring pack: 1-in."]
        XCTAssertTrue(title.waitForExistence(timeout: 30))
        app.buttons["Change sample access shortly"].tap()
        title.tap()
        let details = app.staticTexts["PEX copper crimp ring pack: 1-in. Ten rings for matching-size PEX; tool calibration remains required."]
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        XCTAssertTrue(details.waitForNonExistence(timeout: 20))
        XCTAssertFalse(app.buttons["Done"].exists, "The old detail sheet must not remain blocking")
        if !switchWorkspace { XCTAssertFalse(title.exists, "A revoked list must not keep showing prior items") }
    }
}

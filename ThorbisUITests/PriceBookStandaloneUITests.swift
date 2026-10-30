import XCTest

@MainActor
final class PriceBookStandaloneUITests: XCTestCase {
    private func launch(admin: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "price-book", "--paper-preview-pricebook-long"]
        if admin { app.launchArguments.append("--paper-preview-pricebook-admin") }
        app.launch()
        return app
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
        XCTAssertTrue(app.buttons["All · 1 loaded"].exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Material, 1 loaded")).firstMatch.exists)
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
        app.buttons["Material"].tap()
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
        app.buttons["Service"].tap()
        app.buttons["All · 6"].tap()
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

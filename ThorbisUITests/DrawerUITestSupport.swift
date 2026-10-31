import XCTest

/// The phone drawer (2026-10-31): a place root's menu circle opens it, and every row carries a
/// `drawer-<id>` identifier (`drawer-jobs`, `drawer-inbox`, `drawer-search`, `drawer-saved-work`).
extension XCUIApplication {
    /// The menu circle at the top left of the place showing.
    var drawerMenu: XCUIElement { buttons["drawer-menu"] }

    /// Opens the drawer from the menu circle and waits for it to show.
    @discardableResult
    func openDrawer(timeout: TimeInterval = 30, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let menu = drawerMenu
        XCTAssertTrue(menu.waitForExistence(timeout: timeout), "No menu circle on this screen", file: file, line: line)
        menu.tap()
        let shown = buttons["drawer-search"].waitForExistence(timeout: 5)
        XCTAssertTrue(shown, "The drawer did not open", file: file, line: line)
        return shown
    }

    /// A drawer row: a place (`jobs`, `inbox`), `search`, `new`, `settings`, `saved-work` or `now`.
    func drawerRow(_ id: String) -> XCUIElement { buttons["drawer-\(id)"] }

    /// Opens the drawer and picks a row in it.
    func openFromDrawer(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        openDrawer(file: file, line: line)
        let row = drawerRow(id)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "No drawer row \(id)", file: file, line: line)
        row.tap()
    }
}

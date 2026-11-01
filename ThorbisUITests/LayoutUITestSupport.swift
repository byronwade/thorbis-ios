import XCTest

/// Layout-aware navigation, so one test reads the same on iPhone and iPad.
///
/// The phone shows the drawer (`drawer-menu`, `drawer-<place>`, the header's `header-create`).
/// An iPad at regular width shows `TabletRoot`: a sidebar (`sidebar-<place>`, `sidebar-search`,
/// `sidebar-create`) that sits beside the columns from 1100pt wide and slides over them below,
/// where a top bar carries `sidebar-show`, `tablet-search` and `tablet-create`. Lists sit beside a
/// detail column, so picking a row selects into the detail rather than pushing.
extension XCUIApplication {
    /// iPad layout. The simulators run the app full screen, which is always regular width on iPad, so
    /// the idiom decides before anything is on screen (skips, launch arguments); the helpers below
    /// still find their controls by identifier, portrait or landscape.
    var usesTabletLayout: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    /// The place's create +: the header's on the phone, the top bar's or sidebar's on iPad.
    var createButton: XCUIElement {
        buttons.matching(NSPredicate(format: "identifier IN %@", ["header-create", "tablet-create", "sidebar-create"])).firstMatch
    }

    /// The search field on either layout (the phone's pushed Search, the iPad's search sheet).
    var searchField: XCUIElement { textFields["search-field"] }

    /// Whether a keyboard is on screen. On iPad a put-away keyboard can stay in the tree as a
    /// zero-height element at the screen's foot, so existence alone is not enough.
    var keyboardShowing: Bool {
        let keyboard = keyboards.firstMatch
        return keyboard.exists && keyboard.frame.height > 1 && keyboard.frame.minY < frame.maxY - 1
    }

    /// Waits for the keyboard to be put away (gone, or zero-height at the foot on iPad).
    func waitForKeyboardToHide(timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while keyboardShowing && Date() < deadline { usleep(200_000) }
        return !keyboardShowing
    }

    /// Shows the iPad sidebar when it is hidden (portrait, or folded in landscape).
    func showSidebar(file: StaticString = #filePath, line: UInt = #line) {
        if buttons["sidebar-search"].waitForExistence(timeout: 2), buttons["sidebar-search"].isHittable { return }
        let show = buttons["sidebar-show"]
        XCTAssertTrue(show.waitForExistence(timeout: 30), "No Show sidebar button", file: file, line: line)
        show.tap()
        XCTAssertTrue(buttons["sidebar-search"].waitForExistence(timeout: 5), "The sidebar did not show", file: file, line: line)
    }

    /// Opens a place (`jobs`, `inbox`, `priceBook`…) from the phone drawer or the iPad sidebar.
    func openPlace(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        guard usesTabletLayout else { return openFromDrawer(id, file: file, line: line) }
        let row = buttons["sidebar-\(id)"]
        if !(row.exists && row.isHittable) { showSidebar(file: file, line: line) }
        XCTAssertTrue(row.waitForExistence(timeout: 5), "No sidebar row \(id)", file: file, line: line)
        row.tap()
    }

    /// Opens search: the drawer's Search on the phone, the top bar's (or sidebar's) field on iPad.
    func openSearch(file: StaticString = #filePath, line: UInt = #line) {
        guard usesTabletLayout else { return openFromDrawer("search", file: file, line: line) }
        let field = buttons.matching(NSPredicate(format: "identifier IN %@", ["tablet-search", "sidebar-search"])).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 30), "No search field in the iPad bar", file: file, line: line)
        field.tap()
    }

    /// Waits for the shell to be up: the drawer's menu circle on the phone, the sidebar or its
    /// Show button on iPad.
    @discardableResult
    func waitForShell(timeout: TimeInterval = 30, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let ids = usesTabletLayout ? ["sidebar-show", "sidebar-search"] : ["drawer-menu"]
        let shell = buttons.matching(NSPredicate(format: "identifier IN %@", ids)).firstMatch
        let up = shell.waitForExistence(timeout: timeout)
        XCTAssertTrue(up, "The app's navigation did not appear", file: file, line: line)
        return up
    }

    /// Presses a hardware-keyboard shortcut and waits for `expected`, pressing once more if nothing
    /// answered. The retry covers XCUITest's simulated keyboard, not the app. After each launch the
    /// first chord's modifier never reaches the app. backboardd (BackBoard EventDelivery log) posts
    /// the first ⌘ key-down only to SpringBoard's `systemKeyCommandOverlay`, so the letter lands
    /// without ⌘. From the second chord on, ⌘ goes to the app too. The checks behind this (#139):
    /// - Stock Safari's first ⌘T routes the same way.
    /// - UIKit's own ⌘A (select all) in the search field fails on the first chord in 3 of 3 runs
    ///   ("Kitchen" + ⌘A + x gives "Kitchenx") and works on the second.
    /// - ⌘N failed its first press 3 of 3 times, like ⌘F, ⌘K, ⇧⌘N and ⌃⌘S.
    /// - The app's command never fired. Nothing app-side helped: a static Go menu without
    ///   `@FocusedValue`, waiting 8s, tapping first.
    /// - An unrelated chord first (⌘J) made the next shortcut work on its first press.
    @discardableResult
    func pressShortcut(_ key: String, _ modifiers: XCUIElement.KeyModifierFlags, expecting expected: XCUIElement,
                       timeout: TimeInterval = 4) -> Bool {
        typeKey(key, modifierFlags: modifiers)
        if expected.waitForExistence(timeout: timeout) { return true }
        typeKey(key, modifierFlags: modifiers)
        return expected.waitForExistence(timeout: timeout)
    }

    /// A swipe in from the screen's left edge at `y` (normalized), the phone drawer's and the iPad
    /// sidebar's gesture.
    func swipeInFromLeftEdge(atY y: CGFloat = 0.5) {
        let start = coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: y))
        start.press(forDuration: 0.05, thenDragTo: coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: y)))
    }
}

extension XCTestCase {
    /// Skips a test of a phone-only control, saying why it has no iPad counterpart.
    /// Callable from `setUpWithError`, which XCTest runs on the main thread.
    nonisolated func skipOnTablet(because reason: String) throws {
        let pad = MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .pad }
        if pad { throw XCTSkip("Phone layout only: \(reason)") }
    }
}

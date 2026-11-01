import XCTest

/// Hardware-keyboard commands (`KeyboardCommands`), pressed for real on iPhone and iPad: ⌘F and ⌘K
/// open Search with the field ready, ⇧⌘N opens the create menu. On the iPad layout, ⌃⌘S shows the
/// sidebar and ⌘1…⌘9 open its places. They are scene commands, so no hidden button sits in the tree.
@MainActor
final class KeyboardShortcutUITests: XCTestCase {
    private func launch(_ screen: String = "jobs") -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", screen]
        app.launch()
        XCTAssertTrue(app.staticTexts["5 active"].waitForExistence(timeout: 30), "The Jobs list has loaded")
        app.waitForShell()
        return app
    }

    private func assertSearchOpens(with key: String) {
        let app = launch()
        XCTAssertFalse(app.searchField.exists, "Search starts closed")
        XCTAssertTrue(app.pressShortcut(key, .command, expecting: app.searchField), "⌘\(key.uppercased()) opens Search")
        // The field has the keyboard focus: typing lands in it straight away.
        app.typeText("Kitchen")
        let typed = NSPredicate(format: "value == %@", "Kitchen")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: typed, object: app.searchField)], timeout: 5), .completed,
                       "Typing after ⌘\(key.uppercased()) goes into the search field")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Kitchen sink backup")).firstMatch.waitForExistence(timeout: 10))
    }

    func testCommandFOpensSearch() { assertSearchOpens(with: "f") }

    func testCommandKOpensSearch() { assertSearchOpens(with: "k") }

    func testShiftCommandNOpensTheCreateMenu() {
        let app = launch()
        XCTAssertFalse(app.buttons["New estimate"].exists, "The create menu starts closed")
        // The iPad's menu names New job's shortcut after it ("New job, ⌘N").
        let newJob = app.buttons.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", "New job", "New job,")).firstMatch
        XCTAssertTrue(app.pressShortcut("n", [.command, .shift], expecting: newJob), "⇧⌘N opens the create menu")
        XCTAssertTrue(app.buttons["New estimate"].exists)
        XCTAssertTrue(app.buttons["New customer"].exists)
        newJob.tap()
        XCTAssertTrue(app.descendants(matching: .any)["book-job-caller"].waitForExistence(timeout: 10), "New job starts from the menu")
    }

    /// iPad only: the sidebar and place shortcuts live in the scene's Go menu, not in hidden buttons.
    func testTabletSidebarAndPlaceShortcuts() throws {
        guard XCUIApplication().usesTabletLayout else {
            throw XCTSkip("iPad layout only: the phone has no sidebar; its places live in the drawer.")
        }
        let app = launch()
        XCTAssertFalse(app.buttons["Toggle sidebar"].exists, "No hidden shortcut button may be in the tree")
        XCTAssertFalse(app.buttons["sidebar-search"].exists, "Portrait starts with the sidebar hidden")
        XCTAssertTrue(app.pressShortcut("s", [.command, .control], expecting: app.buttons["sidebar-search"]), "⌃⌘S shows the sidebar")
        app.typeKey("s", modifierFlags: [.command, .control])
        XCTAssertTrue(app.buttons["sidebar-search"].waitForNonExistence(timeout: 5), "⌃⌘S hides it again")
        // ⌘1 is the first place in the sidebar (Schedule for this role).
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["schedule-title"].waitForExistence(timeout: 10), "⌘1 opens the sidebar's first place")
    }
}

import XCTest

/// End-to-end smoke test on the fixture workspace: launch signed in, walk the
/// tabs, open the job underway and mark arrival.
final class ThorbisUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testTabsAndArriveOnNextUpJob() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset"]
        app.launch()

        let nextUp = app.descendants(matching: .any)["next-up"]
        XCTAssertTrue(nextUp.waitForExistence(timeout: 10))

        for tab in ["Jobs", "Customers", "Money", "Today"] {
            app.tabBars.buttons[tab].tap()
        }

        // The inbox is a toolbar destination, so the tab bar never folds into More.
        app.buttons["inbox"].tap()
        XCTAssertTrue(app.navigationBars["Inbox"].waitForExistence(timeout: 5))
        let inboxBar = app.navigationBars["Inbox"]
        let back = inboxBar.buttons["Today"].exists ? inboxBar.buttons["Today"] : inboxBar.buttons["Back"]
        back.tap()

        let action = app.buttons["next-up-action"]
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        XCTAssertEqual(action.label, "Arrive")
        action.tap()

        nextUp.tap()
        let primary = app.buttons["primary-action"]
        XCTAssertTrue(primary.waitForExistence(timeout: 5))
        XCTAssertEqual(primary.label, "Start work")
    }

    @MainActor
    func testSignInScreenWithoutSession() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset"]
        app.launch()
        XCTAssertTrue(app.buttons["sign-in"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["email"].exists)
    }
}

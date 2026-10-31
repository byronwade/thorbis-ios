import XCTest

/// Today's stop cards: a swipe moves between stops, the view bar's circle switches to the list, and
/// the drawer's left-edge swipe still opens the drawer above the pager.
@MainActor
final class TodayStopCardsUITests: XCTestCase {
    private let dispatched = "today-stop-card-00000000-0000-4000-8000-000000002214"
    private let nextStop = "today-stop-card-00000000-0000-4000-8000-000000002212"
    private let done = "today-stop-card-00000000-0000-4000-8000-000000002209"

    /// The card's body is adjustable for VoiceOver, so it is not typed as a plain button.
    private func stopCard(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "next-stop", "--paper-preview-role", "tech",
                               "--paper-preview-today-cards"] + extra
        app.launch()
        return app
    }

    func testOpensOnTheNextStopAndSwipesBothWays() {
        let app = launch()
        let card = stopCard(app, dispatched)
        XCTAssertTrue(card.waitForExistence(timeout: 30), "Today should open on the dispatched 10:30 stop")
        XCTAssertTrue(card.label.hasPrefix("Stop 3 of 6"), card.label)
        app.descendants(matching: .any).matching(identifier: "today-stop-cards").firstMatch.swipeLeft()
        XCTAssertTrue(stopCard(app, nextStop).waitForExistence(timeout: 5), "Swiping left shows the next stop")
        app.descendants(matching: .any).matching(identifier: "today-stop-cards").firstMatch.swipeRight()
        app.descendants(matching: .any).matching(identifier: "today-stop-cards").firstMatch.swipeRight()
        XCTAssertTrue(stopCard(app, done).waitForExistence(timeout: 5), "Swiping right goes back to a finished stop")
    }

    func testDrawerEdgeSwipeStillOpensOverThePager() {
        let app = launch()
        let card = stopCard(app, dispatched)
        XCTAssertTrue(card.waitForExistence(timeout: 30))
        // Start at the screen's very edge, level with the card.
        let y = card.frame.midY / app.frame.height
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: y))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: y)))
        XCTAssertTrue(app.buttons["drawer-search"].waitForExistence(timeout: 5), "The edge swipe should open the drawer")
    }

    /// The phone's saved copy opens first, then the server's answer: when the saved copy had another
    /// stop under way (here 2209, in progress on the Jobs preview), the answer finishes it and the
    /// stops reorder. The pager must then open on the stop under way by the server's word, with that
    /// card on screen, not a different card under the focus (the order-dependent failure, #131).
    func testOpensOnTheRightStopWhenTheSavedCopyWasStale() {
        let seed = XCUIApplication()
        seed.launchArguments = ["--paper-preview", "--paper-preview-screen", "jobs", "--paper-preview-role", "tech"]
        seed.launch()
        XCTAssertTrue(seed.buttons["drawer-menu"].waitForExistence(timeout: 30))
        sleep(2)
        seed.terminate()
        let app = launch()
        let card = stopCard(app, dispatched)
        XCTAssertTrue(card.waitForExistence(timeout: 30), "Today should open on the dispatched 10:30 stop")
        XCTAssertTrue(card.label.hasPrefix("Stop 3 of 6"), card.label)
        let pager = app.descendants(matching: .any).matching(identifier: "today-stop-cards").firstMatch
        XCTAssertGreaterThanOrEqual(card.frame.minX, pager.frame.minX - 1, "The focused card is the one on screen")
        XCTAssertLessThanOrEqual(card.frame.maxX, app.frame.maxX + 1, "The focused card is the one on screen")
    }

    func testToggleSwitchesToTheListAndBack() {
        let app = launch()
        XCTAssertTrue(stopCard(app, dispatched).waitForExistence(timeout: 30))
        app.buttons["today-layout-toggle"].tap()
        XCTAssertTrue(app.buttons["next-stop-card"].waitForExistence(timeout: 5), "List mode shows the Now panel again")
        XCTAssertFalse(stopCard(app, dispatched).exists)
        app.buttons["today-layout-toggle"].tap()
        XCTAssertTrue(stopCard(app, dispatched).waitForExistence(timeout: 5))
    }
}

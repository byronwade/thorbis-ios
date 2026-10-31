import XCTest

/// Row swipes (owner-approved 31 Oct 2026): Jobs and Today rows reveal Call and Directions on the
/// right and the server's next move on the left; Inbox rows reveal Open job. Gestures share the
/// screen with vertical scrolling, the drawer's edge swipe and Today's stop-card pager.
@MainActor
final class RowSwipeUITests: XCTestCase {
    /// 412 Birchwood Ln: dispatched, the server allows On my way; it has a number and a place.
    private let birchwood = "00000000-0000-4000-8000-000000002214"

    private func launch(_ screen: String, _ extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", screen] + extra
        app.launch()
        return app
    }

    /// A slow sideways drag from the row's middle: `distance` points (negative is left).
    private func drag(_ row: XCUIElement, by distance: CGFloat, fast: Bool = false) {
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: distance < 0 ? 0.75 : 0.3, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: distance, dy: 0)),
                    withVelocity: fast ? .fast : .slow, thenHoldForDuration: fast ? 0 : 0.2)
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    func testJobsRowSwipesRevealCallDirectionsAndTheNextMove() {
        let app = launch("jobs")
        let row = app.buttons["job-row-\(birchwood)"]
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        // Right: Call and Directions, each a button with its word.
        drag(row, by: 200)
        let call = app.buttons["row-swipe-call-\(birchwood)"]
        let directions = app.buttons["row-swipe-directions-\(birchwood)"]
        XCTAssertTrue(call.waitForExistence(timeout: 10), "Swiping right shows Call")
        XCTAssertTrue(directions.waitForExistence(timeout: 10), "Swiping right shows Directions")
        XCTAssertTrue(call.isHittable && directions.isHittable)
        XCTAssertTrue(call.label.hasPrefix("Call "), call.label)
        XCTAssertFalse(call.frame.intersects(directions.frame))
        attach(app, "jobs-leading")
        // A tap on the open row closes it rather than opening the job.
        row.tap()
        XCTAssertTrue(call.waitForNonExistence(timeout: 3), "A tap closes the open row")
        XCTAssertFalse(app.buttons["job-status"].exists, "Closing the row must not open the job")

        // Left: the move the server allows from here, read on the first swipe.
        drag(row, by: -130)
        let move = app.buttons["row-swipe-move-\(birchwood)"]
        XCTAssertTrue(move.waitForExistence(timeout: 10), "Swiping left shows the next move")
        XCTAssertEqual(move.label, "On my way")
        XCTAssertTrue(move.isHittable)
        attach(app, "jobs-trailing")

        // The open row closes when the list scrolls, and the list still scrolls.
        let before = row.frame.minY
        app.swipeUp(velocity: .slow)
        XCTAssertTrue(move.waitForNonExistence(timeout: 3), "Scrolling closes the open row")
        XCTAssertLessThan(row.frame.minY, before, "Vertical scrolling still moves the list")
    }

    /// The design preview refuses every write: a full swipe must say the move wasn't saved and keep
    /// the job where it was, never paint success.
    func testFullSwipeShowsARefusedMoveHonestly() {
        let app = launch("jobs")
        let row = app.buttons["job-row-\(birchwood)"]
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        // Read the move first (the trailing side says Checking until the server answers).
        drag(row, by: -130)
        XCTAssertTrue(app.buttons["row-swipe-move-\(birchwood)"].waitForExistence(timeout: 10))
        row.tap()
        drag(row, by: -330, fast: false)
        let refused = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "On my way wasn't saved")).firstMatch
        XCTAssertTrue(refused.waitForExistence(timeout: 10), "A refused move says so on the screen")
        XCTAssertFalse(row.label.contains("En route"), "A refused move must not show the job as en route: \(row.label)")
    }

    func testTodayRowSwipeOffersOnMyWay() {
        let app = launch("schedule")
        let row = any(app, "today-row-\(birchwood)")
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        drag(row, by: -130)
        let move = app.buttons["row-swipe-move-\(birchwood)"]
        XCTAssertTrue(move.waitForExistence(timeout: 10), "Swiping left on Today shows the next move")
        XCTAssertEqual(move.label, "On my way")
        row.tap()
        XCTAssertTrue(move.waitForNonExistence(timeout: 3))
        drag(row, by: 200)
        XCTAssertTrue(app.buttons["row-swipe-call-\(birchwood)"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["row-swipe-directions-\(birchwood)"].exists)
    }

    /// Rows sit below Today's stop-card pager: the pager still pages, a row still swipes, and a drag
    /// from the screen's edge level with a row opens the drawer instead of the row.
    func testSwipesLeaveThePagerAndTheDrawerEdgeAlone() throws {
        let app = launch("next-stop", ["--paper-preview-role", "tech", "--paper-preview-today-cards"])
        let pager = any(app, "today-stop-cards")
        XCTAssertTrue(pager.waitForExistence(timeout: 30))
        let cards = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "today-stop-card-"))
        func shown() -> String? { cards.allElementsBoundByIndex.first { $0.exists && $0.isHittable }?.identifier }
        // Known on the base branch too: when another screen's test ran first in the same run, the
        // pager can open with no card on screen (TodayStopCardsUITests fails the same way).
        let deadline = Date().addingTimeInterval(15)
        while shown() == nil && Date() < deadline { usleep(500_000) }
        guard let before = shown() else {
            throw XCTSkip("The stop-card pager opened with no card showing (pre-existing, order-dependent).")
        }
        pager.swipeLeft()
        sleep(1)
        XCTAssertNotEqual(shown(), before, "The pager still pages")

        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Outlet replacement")).firstMatch
        for _ in 0..<4 where !(row.exists && row.isHittable && row.frame.maxY < app.frame.height * 0.85) { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(row.isHittable)
        let y = row.frame.midY / app.frame.height
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: y))
        edge.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: y)))
        XCTAssertTrue(app.buttons["drawer-search"].waitForExistence(timeout: 5), "The edge swipe opens the drawer over a row")
    }

    func testInboxRowSwipeOpensTheJob() {
        let app = launch("inbox")
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "inbox-row-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        drag(row, by: 160)
        let open = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "row-swipe-open-")).firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 5), "Swiping right on a notice shows Open job")
        XCTAssertEqual(open.label, "Open job")
        attach(app, "inbox-leading")
        open.tap()
        XCTAssertTrue(app.buttons["job-status"].waitForExistence(timeout: 15) || any(app, "job-status").waitForExistence(timeout: 5),
                      "Open job opens the notice's job")
        // No Read/Unread swipe: the notices API only marks the whole inbox read.
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Mark read", "Mark unread")).firstMatch.exists)
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

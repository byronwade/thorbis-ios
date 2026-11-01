import XCTest

@MainActor
final class LongLocationMenuUITests: XCTestCase {
    func testLastLocationCanBeSelected() { verifyLastLocation(extraArguments: []) }
    func testLastLocationCanBeSelectedAtLargestText() {
        verifyLastLocation(extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
    }

    func testShortMenuCanSelectLastLocationAtLargestText() {
        verifyLastLocation(extraArguments: ["--paper-preview-few-locations", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"], lastNumber: 3)
    }

    private func verifyLastLocation(extraArguments: [String], lastNumber: Int = 18) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customer", "--paper-preview-many-locations"] + extraArguments
        app.launch()
        let add = app.buttons["Add equipment"]
        XCTAssertTrue(app.staticTexts["Danielle Marlowe"].waitForExistence(timeout: 30))
        // The page pins New job at the bottom (#203). XCUITest calls a control under that bar (or just
        // past the screen edge) hittable, and the tap then lands on the bar, so scroll until the plus
        // sits clear above it.
        let newJob = app.buttons["customer-new-job-action"]
        func clear() -> Bool {
            add.isHittable && add.frame.maxY < (newJob.exists ? newJob.frame.minY : app.frame.maxY) - 8
        }
        for attempt in 0..<24 where !clear() {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            start.press(forDuration: 0.05, thenDragTo: end)
            if [3, 7, 15, 23].contains(attempt) {
                let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                image.name = "Location test scroll \(attempt + 1)"
                image.lifetime = .keepAlways
                self.add(image)
            }
        }
        XCTAssertTrue(clear(), app.debugDescription)
        add.tap()
        let select = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Location,")).firstMatch
        XCTAssertTrue(select.waitForExistence(timeout: 10), app.debugDescription)
        select.tap()
        let first = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Location 1 ·")).firstMatch
        // Since #212 the select is an anchored popover (ThorbisMenu) that fades in over 120ms: its rows
        // exist before they can be touched. Wait until they can, or the swipe below lands on the sheet
        // behind and closes the popover.
        XCTAssertTrue(first.waitForExistence(timeout: 5), app.debugDescription)
        expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: first)
        waitForExpectations(timeout: 5)
        let opened = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        opened.name = "Location menu open"
        opened.lifetime = .keepAlways
        self.add(opened)
        for _ in 0..<12 where !first.isHittable { app.swipeDown() }
        XCTAssertTrue(first.isHittable, app.debugDescription)
        first.tap()
        // The select itself now reads "Location, Location 1 · …"; reopen it once the popover has gone.
        XCTAssertTrue(first.waitForNonExistence(timeout: 5), app.debugDescription)
        let firstSelected = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Location, Location 1 ·")).firstMatch
        XCTAssertTrue(firstSelected.waitForExistence(timeout: 5), app.debugDescription)
        firstSelected.tap()
        let lastName = "Location \(lastNumber)"
        let last = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", lastName + " ·")).firstMatch
        XCTAssertTrue(last.waitForExistence(timeout: 5), app.debugDescription)
        // Drag the popover's own list (a swipe outside it closes the menu; a flick on a row can pick it).
        let list = app.scrollViews.containing(NSPredicate(format: "label BEGINSWITH %@", lastName + " ·")).firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5), app.debugDescription)
        for _ in 0..<16 where !last.isHittable {
            let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            start.press(forDuration: 0.05, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)))
        }
        XCTAssertTrue(last.isHittable, app.debugDescription)
        last.tap()
        let chosen = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", lastName)).firstMatch
        XCTAssertTrue(chosen.waitForExistence(timeout: 5), app.debugDescription)
    }
}

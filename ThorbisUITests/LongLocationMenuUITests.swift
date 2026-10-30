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
        for _ in 0..<40 where !add.isHittable { app.swipeUp() }
        XCTAssertTrue(add.isHittable, app.debugDescription)
        add.tap()
        let select = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Location,")).firstMatch
        XCTAssertTrue(select.waitForExistence(timeout: 10), app.debugDescription)
        select.tap()
        let first = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Location 1 ·")).firstMatch
        for _ in 0..<12 where !first.isHittable { app.swipeDown() }
        XCTAssertTrue(first.isHittable, app.debugDescription)
        first.tap()
        let firstSelected = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Location 1 ·")).firstMatch
        XCTAssertTrue(firstSelected.waitForExistence(timeout: 5), app.debugDescription)
        firstSelected.tap()
        let lastName = "Location \(lastNumber)"
        let last = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", lastName)).firstMatch
        for _ in 0..<12 where !last.isHittable { app.swipeUp() }
        XCTAssertTrue(last.isHittable, app.debugDescription)
        last.tap()
        let chosen = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", lastName)).firstMatch
        XCTAssertTrue(chosen.waitForExistence(timeout: 5), app.debugDescription)
    }
}

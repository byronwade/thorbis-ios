import XCTest

@MainActor
final class CustomerPhotoRollupUITests: XCTestCase {
    func testCustomerPhotosShowBothJobsAndOpenTheCorrectJobPhoto() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customer-records",
                               "--paper-preview-customer-photo-rollup"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Photos"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["35"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["AC not cooling"].exists)
        let first = app.buttons["customer-photo-00000000-0000-4000-8000-000000031000"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        first.tap()
        XCTAssertTrue(app.navigationBars["Photo"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["AC photo 1"].waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Customer job photo detail"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.navigationBars.buttons.firstMatch.tap()
        let second = app.buttons["customer-photo-00000000-0000-4000-8000-000000032000"]
        for _ in 0..<15 where !second.isHittable { app.swipeUp() }
        XCTAssertTrue(second.isHittable, "The second job's photos remain reachable")
        XCTAssertTrue(app.staticTexts["Drain cleaning"].exists)
        second.tap()
        XCTAssertTrue(app.navigationBars["Photo"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Drain photo 1"].waitForExistence(timeout: 10))
    }
    func testMixedHistoricalPhotosCountOnceAndOpenAuthorizedLegacyPhoto() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customer-records",
                               "--paper-preview-mixed-photo-rollup"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Photos"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["35"].waitForExistence(timeout: 10))
        let historical = app.buttons["customer-legacy-photo-00000000-0000-4000-8000-000000033001"]
        for _ in 0..<30 where !historical.isHittable { app.swipeUp() }
        XCTAssertTrue(historical.isHittable, "The second job's historical photo is reachable")
        historical.tap()
        XCTAssertTrue(app.navigationBars["Photo"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.images["customer-legacy-image-loaded"].waitForExistence(timeout: 15),
                      "The historical photo must load through its authorized job route")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Historical customer job photo"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}

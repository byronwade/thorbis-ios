import XCTest

@MainActor
final class CustomerPhotoRollupUITests: XCTestCase {
    /// The customer page pins its New job commit at the bottom (#203). A photo partly under it still
    /// reads as hittable, but a tap at its centre lands on the bar, so scroll in short drags until the
    /// photo sits between the header and the bar, then let the scroll settle.
    private func bringClearOfNewJob(_ photo: XCUIElement, in app: XCUIApplication) {
        let newJob = app.buttons["customer-new-job-action"]
        for _ in 0..<40 where !photo.isHittable || (newJob.exists && photo.frame.maxY > newJob.frame.minY - 8) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
        }
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "scroll settles")], timeout: 1)
    }

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
        bringClearOfNewJob(first, in: app)
        XCTAssertTrue(first.isHittable)
        first.tap()
        XCTAssertTrue(app.navigationBars["Photo"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["AC photo 1"].waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Customer job photo detail"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        // Pushed screens show the drawer's menu circle before Back (#210): go back by name.
        app.navigationBars["Photo"].buttons["Back"].tap()
        let second = app.buttons["customer-photo-00000000-0000-4000-8000-000000032000"]
        bringClearOfNewJob(second, in: app)
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
        bringClearOfNewJob(historical, in: app)
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

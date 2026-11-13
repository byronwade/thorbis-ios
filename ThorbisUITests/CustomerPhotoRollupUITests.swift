import XCTest

@MainActor
final class CustomerPhotoRollupUITests: XCTestCase {
    func testPhotoGroupJobLinkAtLargestText() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customer-records", "--paper-preview-customer-photo-rollup", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let chooser = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Showing ")).firstMatch
        for _ in 0..<20 where !chooser.isHittable { app.swipeUp() }
        XCTAssertTrue(chooser.waitForExistence(timeout: 20)); chooser.tap()
        let photos = app.buttons["Photos"].firstMatch
        XCTAssertTrue(photos.waitForExistence(timeout: 10)); photos.tap()
        let job = app.buttons["customer-records-job-00000000-0000-4000-8000-000000002214"]
        for _ in 0..<20 where !job.isHittable { app.swipeUp() }
        XCTAssertTrue(job.waitForExistence(timeout: 20))
        XCTAssertTrue(job.isHittable)
        XCTAssertGreaterThanOrEqual(job.frame.height, 44)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Customer photo group job navigation largest text"; screenshot.lifetime = .keepAlways; add(screenshot)
        job.tap()
        XCTAssertTrue(app.buttons["job-section-chooser"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["AC not cooling"].waitForExistence(timeout: 10))
    }
    func testSecondPhotoGroupOpensItsOwnJob() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customer-records", "--paper-preview-customer-photo-rollup"]
        app.launch()
        let photos = app.buttons["Photos"].firstMatch
        XCTAssertTrue(photos.waitForExistence(timeout: 20)); photos.tap()
        let job = app.buttons["customer-records-job-00000000-0000-4000-8000-000000002201"]
        for _ in 0..<30 where !job.isHittable { app.swipeUp() }
        XCTAssertTrue(job.exists && job.isHittable)
        XCTAssertTrue(job.label.contains("Drain cleaning"), job.label)
        job.tap()
        XCTAssertTrue(app.buttons["job-section-money"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Drain cleaning"].waitForExistence(timeout: 10))
    }
    func testPhotoGroupClearlyOpensItsJob() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customer-records", "--paper-preview-customer-photo-rollup"]
        app.launch()
        let photos = app.buttons["Photos"].firstMatch
        XCTAssertTrue(photos.waitForExistence(timeout: 20)); photos.tap()
        let job = app.buttons["customer-records-job-00000000-0000-4000-8000-000000002214"]
        XCTAssertTrue(job.waitForExistence(timeout: 20))
        XCTAssertTrue(job.label.contains("AC not cooling"), job.label)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Customer photo group job navigation"; screenshot.lifetime = .keepAlways; add(screenshot)
        job.tap()
        XCTAssertTrue(app.buttons["job-section-money"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["AC not cooling"].waitForExistence(timeout: 10))
    }
    func testCustomerPhotosAreReachableDirectlyFromOverview() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customer-records",
                               "--paper-preview-customer-photo-rollup"]
        app.launch()
        let overview = app.buttons["Overview"].firstMatch
        XCTAssertTrue(overview.waitForExistence(timeout: 20))
        overview.tap()
        let photosTab = app.buttons["Photos"].firstMatch
        XCTAssertTrue(photosTab.waitForExistence(timeout: 5), "Photos should be reachable without scrolling past job history")
        XCTAssertTrue(photosTab.isHittable)
        photosTab.tap()
        XCTAssertTrue(app.staticTexts["35"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["AC not cooling"].waitForExistence(timeout: 10))
        let first = app.buttons["customer-photo-00000000-0000-4000-8000-000000031000"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        bringClearOfNewJob(first, in: app)
        XCTAssertTrue(first.isHittable)
        first.tap()
        XCTAssertTrue(app.navigationBars["Photo"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["AC photo 1"].waitForExistence(timeout: 10))
    }
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

import XCTest

@MainActor
final class CustomerPhotoRollupUITests: XCTestCase {
    func testCustomerRecordsFindDocumentsAndSeparateCustomerActivityWithoutScrollingPastJobs() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customer-records", "--paper-preview-customer-document-rollup"]
        app.launch()
        let records = app.buttons["Records"].firstMatch
        XCTAssertTrue(records.waitForExistence(timeout: 20), "Customer records must be reachable from the customer section selector")
        XCTAssertTrue(records.isHittable)
        records.tap()
        let documents = app.buttons["Documents"].firstMatch
        XCTAssertTrue(documents.waitForExistence(timeout: 10))
        documents.tap()
        let file = app.buttons["customer-document-00000000-0000-4000-8000-000000031777"]
        for _ in 0..<12 where !file.exists { app.swipeUp() }
        XCTAssertTrue(file.waitForExistence(timeout: 20))
        let customerActivity = app.buttons["Customer activity"].firstMatch
        for _ in 0..<12 where !customerActivity.isHittable { app.swipeDown() }
        XCTAssertTrue(customerActivity.waitForExistence(timeout: 10))
        customerActivity.tap()
        XCTAssertTrue(app.descendants(matching: .any)["customer-activity"].waitForExistence(timeout: 10))
    }

    func testRecordsLoadDocumentAfterPhotoOnlyMediaPage() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customer-records",
                               "--paper-preview-customer-document-rollup", "--paper-preview-customer-document-pages"]
        app.launch()
        let records = app.buttons["Records"].firstMatch
        XCTAssertTrue(records.waitForExistence(timeout: 20)); records.tap()
        app.buttons["Documents"].firstMatch.tap()
        let more = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Load more documents for AC not cooling")).firstMatch
        for _ in 0..<10 where !more.isHittable { app.swipeUp() }
        XCTAssertTrue(more.waitForExistence(timeout: 20))
        XCTAssertTrue(more.isHittable)
        app.scrollClearOfFoot(more)
        more.tap()
        let document = app.buttons["customer-document-00000000-0000-4000-8000-000000031777"]
        XCTAssertTrue(document.waitForExistence(timeout: 15))
        XCTAssertTrue(document.label.contains("Service report"))
    }

    func testPullToRefreshReloadsTheVisibleRecordsSection() {
        let app = openPagedCustomerRecords("--paper-preview-customer-records-refresh")
        let file = app.buttons["customer-document-00000000-0000-4000-8000-000000031777"]
        XCTAssertTrue(file.waitForExistence(timeout: 20))
        XCTAssertTrue(file.label.contains("Service report"), file.label)
        for _ in 0..<6 { app.swipeDown() }
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Updated service report"), object: file)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 20), .completed, "Pull-to-refresh must reload the selected section")
    }

    func testDelayedJobDenialAfterRefreshStillPurgesRecords() {
        let app = openPagedCustomerRecords("--paper-preview-customer-deny-after-refresh")
        let file = app.buttons["customer-document-00000000-0000-4000-8000-000000031777"]
        XCTAssertTrue(file.waitForExistence(timeout: 20))
        let more = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Load more documents for AC not cooling")).firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 10)); app.scrollClearOfFoot(more); more.tap()
        for _ in 0..<6 { app.swipeDown() }
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Updated service report"), object: file)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 15), .completed, "The refresh must finish before the delayed denial")
        XCTAssertTrue(app.staticTexts["You no longer have access to this job."].waitForExistence(timeout: 15))
        XCTAssertFalse(file.exists, "A later same-owner denial must purge the refreshed job")
    }

    func testRecordsPurgeJobDocumentsAfterAccessDenial() {
        let app = openPagedCustomerRecords("--paper-preview-customer-records-deny-group")
        let file = app.buttons["customer-document-00000000-0000-4000-8000-000000031777"]
        XCTAssertTrue(file.waitForExistence(timeout: 20))
        let more = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Load more documents for AC not cooling")).firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 10)); app.scrollClearOfFoot(more); more.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "access")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(file.exists, "Denied job content must be purged immediately")
        let retry = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Retry records for AC not cooling")).firstMatch
        XCTAssertTrue(retry.waitForExistence(timeout: 10)); app.scrollClearOfFoot(retry); retry.tap()
        XCTAssertTrue(file.waitForExistence(timeout: 15), "A fresh authorized retry can restore the job's records")
    }

    func testRecordsPurgeMissingJobDocuments() {
        let app = openPagedCustomerRecords("--paper-preview-customer-records-missing-group")
        let file = app.buttons["customer-document-00000000-0000-4000-8000-000000031777"]
        XCTAssertTrue(file.waitForExistence(timeout: 20))
        let more = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Load more documents for AC not cooling")).firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 10)); app.scrollClearOfFoot(more); more.tap()
        XCTAssertTrue(app.staticTexts["This job is no longer available."].waitForExistence(timeout: 10))
        XCTAssertFalse(file.exists)
    }

    func testRecordsPurgeAllDocumentsAfterSessionDenial() {
        let app = openPagedCustomerRecords("--paper-preview-customer-records-unauthorized-jobs")
        let file = app.buttons["customer-document-00000000-0000-4000-8000-000000031777"]
        XCTAssertTrue(file.waitForExistence(timeout: 20))
        let more = app.buttons["customer-records-load-more-jobs"]
        for _ in 0..<15 where !more.isHittable { app.swipeUp() }
        XCTAssertTrue(more.waitForExistence(timeout: 10)); app.scrollClearOfFoot(more); more.tap()
        XCTAssertTrue(app.descendants(matching: .any)["customer-section-retry"].waitForExistence(timeout: 10))
        XCTAssertFalse(file.exists)
    }

    func testRecordsPurgeAllDocumentsAfterCustomerJobsDenial() {
        let app = openPagedCustomerRecords("--paper-preview-customer-records-deny-jobs")
        let file = app.buttons["customer-document-00000000-0000-4000-8000-000000031777"]
        XCTAssertTrue(file.waitForExistence(timeout: 20))
        let more = app.buttons["customer-records-load-more-jobs"]
        for _ in 0..<15 where !more.isHittable { app.swipeUp() }
        XCTAssertTrue(more.waitForExistence(timeout: 10)); app.scrollClearOfFoot(more); more.tap()
        XCTAssertTrue(app.descendants(matching: .any)["customer-section-retry"].waitForExistence(timeout: 10))
        XCTAssertFalse(file.exists, "A fresh customer-jobs denial must purge the entire section")
    }

    func testRecordsStopRepeatedMediaCursorWithoutDuplicateDocuments() {
        let app = openPagedCustomerRecords("--paper-preview-customer-records-cursor-cycle")
        let file = app.buttons["customer-document-00000000-0000-4000-8000-000000031777"]
        XCTAssertTrue(file.waitForExistence(timeout: 20))
        let more = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Load more documents for AC not cooling")).firstMatch
        for _ in 0..<2 {
            XCTAssertTrue(more.waitForExistence(timeout: 10)); app.scrollClearOfFoot(more); more.tap()
        }
        XCTAssertTrue(app.staticTexts["Some records may be missing."].firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(identifier: "customer-document-00000000-0000-4000-8000-000000031777").count, 1)
        XCTAssertFalse(more.exists, "A repeated cursor must stop further loading")
    }

    private func openPagedCustomerRecords(_ flag: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customer-records",
                               "--paper-preview-customer-document-rollup", flag]
        app.launch()
        let records = app.buttons["Records"].firstMatch
        XCTAssertTrue(records.waitForExistence(timeout: 20)); records.tap()
        let documents = app.buttons["Documents"].firstMatch
        XCTAssertTrue(documents.waitForExistence(timeout: 10)); documents.tap()
        return app
    }

    func testRecordsRemainReachableAtLargestText() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customer-records", "--paper-preview-customer-document-rollup",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let outer = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Showing Jobs")).firstMatch
        XCTAssertTrue(outer.waitForExistence(timeout: 20)); outer.tap()
        app.buttons["Records"].firstMatch.tap()
        let inner = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Showing Notes")).firstMatch
        XCTAssertTrue(inner.waitForExistence(timeout: 10)); inner.tap()
        app.buttons["Documents"].firstMatch.tap()
        let file = app.buttons["customer-document-00000000-0000-4000-8000-000000031777"]
        for _ in 0..<15 where !file.isHittable { app.swipeUp() }
        XCTAssertTrue(file.waitForExistence(timeout: 20)); XCTAssertTrue(file.isHittable)
        XCTAssertGreaterThanOrEqual(file.frame.height, 44)
    }

    func testCustomerDocumentsKeepJobIdentityAndUnavailableFilesClosed() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customer-records", "--paper-preview-customer-document-rollup"]
        app.launch()
        let pending = app.buttons["customer-document-00000000-0000-4000-8000-000000031779"]
        for _ in 0..<25 where !pending.exists { app.swipeUp() }
        XCTAssertTrue(pending.waitForExistence(timeout: 20))
        XCTAssertFalse(pending.isEnabled)
        XCTAssertTrue(pending.label.contains("File is not ready yet"))
        let failed = app.buttons["customer-document-00000000-0000-4000-8000-000000031780"]
        XCTAssertTrue(failed.waitForExistence(timeout: 10))
        XCTAssertFalse(failed.isEnabled)
        XCTAssertTrue(failed.label.contains("File is not ready yet"))
        let other = app.buttons["customer-document-00000000-0000-4000-8000-000000031778"]
        for _ in 0..<25 where !other.isHittable { app.swipeUp() }
        XCTAssertTrue(other.waitForExistence(timeout: 20))
        app.scrollClearOfFoot(other)
        XCTAssertTrue(other.isHittable)
        XCTAssertLessThanOrEqual(other.frame.maxY, app.buttons["customer-new-job-action"].frame.minY,
                                 "The document must be clear of the fixed New job action")
        other.tap()
        XCTAssertTrue(app.navigationBars["File"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Drain report"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Service report"].exists)
    }
    func testCustomerDocumentOpensItsJobFile() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customer-records", "--paper-preview-customer-document-rollup"]
        app.launch()
        let file = app.buttons["customer-document-00000000-0000-4000-8000-000000031777"]
        for _ in 0..<25 where !file.isHittable { app.swipeUp() }
        XCTAssertTrue(file.waitForExistence(timeout: 20))
        XCTAssertTrue(file.isHittable)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Customer document link"; shot.lifetime = .keepAlways; add(shot)
        file.tap()
        XCTAssertTrue(app.navigationBars["File"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Service report"].waitForExistence(timeout: 10))
    }
    func testCustomerDocumentOpensAtLargestText() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customer-records", "--paper-preview-customer-document-rollup", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let file = app.buttons["customer-document-00000000-0000-4000-8000-000000031777"]
        for _ in 0..<25 where !file.isHittable { app.swipeUp() }
        XCTAssertTrue(file.waitForExistence(timeout: 20))
        XCTAssertTrue(file.isHittable)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Customer document link largest text"; shot.lifetime = .keepAlways; add(shot)
        file.tap()
        XCTAssertTrue(app.navigationBars["File"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Service report"].waitForExistence(timeout: 10))
    }
    func testLongJobTitleWrapsAndOpensItsJob() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customer-records", "--paper-preview-customer-photo-rollup", "--paper-preview-customer-long-job"]
        app.launch()
        let photos = app.buttons["Photos"].firstMatch
        XCTAssertTrue(photos.waitForExistence(timeout: 20)); photos.tap()
        let job = app.buttons["customer-records-job-00000000-0000-4000-8000-000000002214"]
        XCTAssertTrue(job.waitForExistence(timeout: 20))
        XCTAssertTrue(job.label.contains("Air conditioning is not cooling the upstairs rooms after several hours of running"))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Long customer record job title"; screenshot.lifetime = .keepAlways; add(screenshot)
        XCTAssertGreaterThan(job.frame.height, 44, "Long job titles need room to wrap")
        job.tap()
        XCTAssertTrue(app.buttons["job-section-money"].waitForExistence(timeout: 15))
    }
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
        for _ in 0..<10 where job.frame.minY < app.frame.height * 0.2 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)))
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Customer photo group job navigation largest text"; screenshot.lifetime = .keepAlways; add(screenshot)
        XCTAssertGreaterThanOrEqual(job.frame.minY, app.frame.height * 0.2)
        XCTAssertLessThanOrEqual(job.frame.maxY, app.frame.height * 0.95)
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

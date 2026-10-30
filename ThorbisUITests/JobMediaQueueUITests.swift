import XCTest

@MainActor
final class JobMediaQueueUITests: XCTestCase {
    func testLaterFilteredPhotosAndDocumentsRemainReachable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job-media", "--paper-preview-media-pages"]
        app.launch()
        XCTAssertTrue(app.buttons["Photo, Outdoor unit"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Counts show loaded photos"].exists)
        app.buttons["After · 0"].tap()
        XCTAssertTrue(app.staticTexts["No matches in loaded photos. More may be available."].exists)
        let more = app.buttons["job-media-load-more-matches"]
        XCTAssertTrue(more.waitForExistence(timeout: 5)); more.tap()
        XCTAssertTrue(app.buttons["Photo, Later repair"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["After · 1"].exists)
        XCTAssertTrue(app.staticTexts["Later document.pdf"].exists)
        XCTAssertFalse(app.buttons["job-media-load-more"].exists)
    }

    func testLateMediaPageDoesNotAppearAfterJobAccessIsRevoked() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job-media", "--paper-preview-media-pages", "--paper-preview-media-revoke-late-page"]
        app.launch()
        let first = app.buttons["Photo, Outdoor unit"]
        XCTAssertTrue(first.waitForExistence(timeout: 20))
        let more = app.buttons["job-media-load-more"]
        XCTAssertTrue(more.waitForExistence(timeout: 5)); more.tap()
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: first)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 15), .completed)
        XCTAssertFalse(app.buttons["Photo, Later repair"].exists)
        XCTAssertFalse(app.staticTexts["Later document.pdf"].exists)
    }

    func testOpenMediaPreviewClosesAfterJobAccessIsRevoked() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job-media", "--paper-preview-media-revoke-preview"]
        app.launch()
        let photo = app.buttons["Photo, Outdoor unit"]
        XCTAssertTrue(photo.waitForExistence(timeout: 20)); photo.tap()
        let preview = app.descendants(matching: .any)["job-media-preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: preview)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 15), .completed)
        XCTAssertFalse(photo.exists)
    }

    func testDatedPhotosRemainReachableWhenScrolledOnNarrowPhone() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job-media", "--paper-preview-media-dates"]
        app.launch()
        XCTAssertTrue(app.buttons["Photo, Outdoor unit"].waitForExistence(timeout: 20))
        let later = app.buttons["Photo, Finished unit"]
        for _ in 0..<5 where !later.isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.37)))
        }
        XCTAssertTrue(later.isHittable)
        let undated = app.buttons["Photo, Uncertain date"]
        for _ in 0..<5 where !undated.isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.37)))
        }
        XCTAssertTrue(undated.isHittable)
    }

    func testUndatedPhotosStayVisibleAndFilterableInTheirOwnGroup() {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job-media"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Date unavailable"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["Photo, Outdoor unit"].exists)
        app.buttons["Before · 1"].tap()
        XCTAssertTrue(app.staticTexts["Date unavailable"].exists)
        XCTAssertTrue(app.buttons["Photo, Outdoor unit"].exists)
        XCTAssertTrue(app.buttons["Change photo stage, currently Before"].exists)
    }

    func testDatedPhotosAreGroupedAndFilterKeepsCorrectPhotoActions() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job-media", "--paper-preview-media-dates", "-thorbis.appearance", "dark"]
        app.launch()
        let newest = app.staticTexts["Oct 27, 2026"]
        let older = app.staticTexts["Oct 26, 2026"]
        let unknown = app.staticTexts["Date unavailable"]
        XCTAssertTrue(newest.waitForExistence(timeout: 20))
        XCTAssertTrue(older.exists)
        XCTAssertTrue(unknown.exists)
        XCTAssertLessThan(newest.frame.minY, older.frame.minY)
        XCTAssertLessThan(older.frame.minY, unknown.frame.minY)
        XCTAssertTrue(app.buttons["Photo, Outdoor unit"].exists)
        XCTAssertTrue(app.buttons["Photo, Finished unit"].exists)
        let top = XCTAttachment(screenshot: app.screenshot())
        top.name = "Job photo dates at top"
        top.lifetime = .keepAlways
        add(top)
        app.swipeUp()
        XCTAssertTrue(app.buttons["Photo, Uncertain date"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Job photos grouped by capture date"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.swipeDown()
        app.buttons["After · 1"].tap()
        XCTAssertTrue(older.exists)
        XCTAssertTrue(app.buttons["Photo, Finished unit"].exists)
        XCTAssertFalse(newest.exists)
        XCTAssertFalse(unknown.exists)
        XCTAssertTrue(app.buttons["Change photo stage, currently After"].exists)
    }

    func testPhotoDateHeadingAtLargestText() {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job-media", "--paper-preview-media-dates", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let heading = app.staticTexts["Oct 27, 2026"]
        XCTAssertTrue(heading.waitForExistence(timeout: 20))
        for _ in 0..<6 where !heading.isHittable { app.swipeUp() }
        XCTAssertTrue(heading.isHittable)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Job photo date at largest text"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testLargestTextPhotoFilterAndCaptureControlsRemainUsable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job-media", "--paper-preview-media-dates", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let filter = app.buttons["photo-filter-menu"]
        XCTAssertTrue(filter.waitForExistence(timeout: 20))
        for _ in 0..<6 where !filter.isHittable { app.swipeUp() }
        XCTAssertTrue(filter.isHittable)
        filter.tap()
        XCTAssertTrue(app.buttons["After · 1"].waitForExistence(timeout: 5))
        app.buttons["After · 1"].tap()
        let photo = app.buttons["Photo, Finished unit"]
        let library = app.buttons["Choose from library"]
        XCTAssertTrue(library.exists)
        let date = app.staticTexts["Oct 26, 2026"]
        XCTAssertTrue(date.exists)
        XCTAssertLessThan(library.frame.minY, date.frame.minY, "Capture is available before a long photo collection")
        let stageAfter = app.buttons["After"]
        for _ in 0..<8 where !stageAfter.isHittable {
            if stageAfter.frame.midY < app.frame.midY { app.swipeDown() } else { app.swipeUp() }
        }
        XCTAssertTrue(stageAfter.isHittable)
        app.buttons["After"].tap()
        XCTAssertTrue(app.buttons["Take after photo"].exists)
        for _ in 0..<8 where !photo.isHittable { app.swipeUp() }
        XCTAssertTrue(photo.isHittable)
        XCTAssertGreaterThan(photo.frame.width, app.frame.width * 0.75)
        XCTAssertGreaterThan(photo.frame.height, 100)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Largest text photo remains usable"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let libraryButton = app.buttons["Choose from library"]
        for _ in 0..<12 where !libraryButton.isHittable {
            let down = libraryButton.frame.midY < app.frame.midY
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.40 : 0.60))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.60 : 0.40))
            start.press(forDuration: 0.2, thenDragTo: end)
        }
        XCTAssertTrue(libraryButton.isHittable)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Library and document controls at largest text on narrow iPhone"
        capture.lifetime = .keepAlways
        add(capture)
        libraryButton.tap()
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        let documentButton = app.buttons["Add a document"]
        XCTAssertTrue(documentButton.isHittable)
        documentButton.tap()
        XCTAssertTrue(app.buttons["Choose a PDF"].waitForExistence(timeout: 5))
    }

    func testCaptureControlsPrecedeManyPendingUploadsAtLargestText() {
        continueAfterFailure = false
        let app = XCUIApplication()
        let base = ["--paper-preview", "--paper-preview-screen", "job-media", "--paper-preview-reset-media"]
        app.launchArguments = base + ["--paper-preview-many-pending", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        defer { app.terminate(); app.launchArguments = base; app.launch(); app.terminate() }
        let firstPending = app.descendants(matching: .any).matching(identifier: "pending-media-00000000-0000-4000-8000-000000009800").firstMatch
        XCTAssertTrue(firstPending.waitForExistence(timeout: 20))
        let library = app.buttons["Choose from library"]
        XCTAssertTrue(library.exists)
        XCTAssertLessThan(library.frame.minY, firstPending.frame.minY, "Capture should precede the pending queue")
        XCTAssertTrue(app.staticTexts["Waiting to upload"].exists)
        XCTAssertTrue(app.buttons["Retry"].exists)
    }

    func testEmptyPhotoFilterOffersReturnToAllPhotos() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job-media"]
        app.launch()
        XCTAssertTrue(app.buttons["After · 0"].waitForExistence(timeout: 20))
        app.buttons["After · 0"].tap()
        XCTAssertTrue(app.staticTexts["No matching photos"].exists)
        XCTAssertFalse(app.staticTexts["No photos yet"].exists)
        let showAll = app.buttons["Show all photos"]
        XCTAssertTrue(showAll.isHittable)
        XCTAssertLessThan(showAll.frame.maxY, app.buttons["Before"].frame.minY)
        let recovery = XCTAttachment(screenshot: app.screenshot())
        recovery.name = "Empty photo filter recovery above capture"
        recovery.lifetime = .keepAlways
        add(recovery)
        showAll.tap()
        let all = app.buttons["All · 1"]
        XCTAssertTrue(all.isSelected)
        let photo = app.buttons["Photo, Outdoor unit"]
        for _ in 0..<8 where !photo.isHittable { app.swipeUp() }
        XCTAssertTrue(photo.isHittable)
    }

    func testSavedScanRemainsJobBoundAfterNavigationAndRelaunch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        let base = ["--paper-preview", "--paper-preview-screen", "job-media", "-thorbis.appearance", "light"]
        app.launchArguments = base + ["--paper-preview-reset-media", "--paper-preview-seed-media"]
        app.launch()
        defer {
            app.terminate()
            app.launchArguments = base + ["--paper-preview-reset-media"]
            app.launch()
            app.terminate()
        }
        let scan = app.descendants(matching: .any).matching(identifier: "pending-media-00000000-0000-4000-8000-000000009701").firstMatch
        let expectedCapture = "Captured " + Date(timeIntervalSince1970: 1_700_000_000).formatted(date: .abbreviated, time: .shortened)
        XCTAssertTrue(scan.waitForExistence(timeout: 20))
        XCTAssertEqual(scan.value as? String, expectedCapture)
        XCTAssertTrue(scan.label.contains("Field scan.pdf"))
        XCTAssertFalse(app.staticTexts["No photos yet"].exists)
        XCTAssertTrue(app.buttons["Add a document"].exists)
        XCTAssertTrue(app.buttons["Choose from library"].exists)
        app.buttons["Overview"].tap()
        app.buttons["Photos"].tap()
        XCTAssertTrue(scan.waitForExistence(timeout: 10))
        XCTAssertEqual(scan.value as? String, expectedCapture)
        app.terminate()
        app.launchArguments = base
        app.launch()
        XCTAssertTrue(scan.waitForExistence(timeout: 20))
        XCTAssertEqual(scan.value as? String, expectedCapture)
        XCTAssertTrue(scan.label.contains("Field scan.pdf"))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "pending-media-00000000-0000-4000-8000-000000009702").firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Other job scan.pdf"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Durable scanned PDF after relaunch"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    func testOlderPhotoRequiresNamedDestinationConfirmationAndSurvivesRelaunch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        let base = ["--paper-preview", "--paper-preview-screen", "job-media", "-thorbis.appearance", "light"]
        app.launchArguments = base + ["--paper-preview-reset-media", "--paper-preview-seed-legacy"]
        app.launch()
        let recover = app.buttons["Recover older photos"]
        XCTAssertTrue(recover.waitForExistence(timeout: 20)); recover.tap()
        let candidate = app.buttons["legacy-recover-00000000-0000-4000-8000-000000009703"]
        XCTAssertTrue(candidate.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["legacy-recover-00000000-0000-4000-8000-000000009704"].exists)
        let destinationImage = XCTAttachment(screenshot: app.screenshot())
        destinationImage.name = "Verified legacy recovery destination"; destinationImage.lifetime = .keepAlways; add(destinationImage)
        candidate.tap()
        let confirm = app.buttons["Recover to this job"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "original account is unknown")).firstMatch.exists)
        let confirmationImage = XCTAttachment(screenshot: app.screenshot())
        confirmationImage.name = "Explicit legacy adoption confirmation"; confirmationImage.lifetime = .keepAlways; add(confirmationImage)
        confirm.tap()
        XCTAssertTrue(app.staticTexts.matching(identifier: "Recovered to this job").firstMatch.waitForExistence(timeout: 10))
        app.buttons["Done"].tap()
        let row = app.descendants(matching: .any).matching(identifier: "pending-media-00000000-0000-4000-8000-000000009703").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let expected = "Captured " + Date(timeIntervalSince1970: 1_700_000_000).formatted(date: .abbreviated, time: .shortened)
        XCTAssertEqual(row.value as? String, expected)
        app.terminate(); app.launchArguments = base; app.launch()
        XCTAssertTrue(row.waitForExistence(timeout: 20)); XCTAssertEqual(row.value as? String, expected)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Explicitly recovered older photo after relaunch"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.terminate(); app.launchArguments = base + ["--paper-preview-reset-media"]; app.launch(); app.terminate()
    }

    func testCleanupFailureNoticeRemainsOnSignedOutScreen() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job-media", "--paper-preview-reset-media", "--paper-preview-media-cleanup-failure"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Welcome back"].waitForExistence(timeout: 20))
        let warning = app.descendants(matching: .any).matching(identifier: "login-media-cleanup-warning").firstMatch
        XCTAssertTrue(warning.exists); XCTAssertTrue(warning.label.contains("could not be removed"))
        XCTAssertFalse(warning.label.contains("actor")); XCTAssertFalse(warning.label.contains(".jpg"))
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Signed-out cleanup failure notice"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.terminate(); app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job-media", "--paper-preview-reset-media"]; app.launch(); app.terminate()
    }

}

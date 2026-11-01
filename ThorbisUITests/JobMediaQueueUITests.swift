import XCTest

@MainActor
final class JobMediaQueueUITests: XCTestCase {
    // Since #184 the Photos screen has one selector (All · Before · After · Documents) with the
    // counts on each date heading ("Oct 27, 2026 · 1"), Import holds library photos and PDFs, and a
    // photo's stage is changed in the viewer. Since #221 stamps read "Nov 14, 2023, 5:13 p.m.".

    /// One of the selector's four choices (every segment carries `job-media-selector`).
    private func selector(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == %@ AND label == %@", "job-media-selector", title)).firstMatch
    }

    /// A date heading, "Oct 27, 2026 · 1": the day, then how many loaded photos it holds.
    private func dayHeading(_ day: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", day + " · ")).firstMatch
    }

    private func photoTiles(in app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "job-media-photo-"))
    }

    /// The app's stamp (#221): "Nov 14, 2023, 5:13 p.m." (the time never reads "5:13 PM").
    private func stamp(_ date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let minute = Calendar.current.component(.minute, from: date)
        let clock = "\(hour % 12 == 0 ? 12 : hour % 12):\(String(format: "%02d", minute)) \(hour < 12 ? "a.m." : "p.m.")"
        return "\(date.formatted(.dateTime.month(.abbreviated).day().year())), \(clock)"
    }

    /// Opens a photo in the full-screen viewer and checks the stage it offers to change.
    private func assertViewerStage(_ photo: XCUIElement, _ stage: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        photo.tap()
        let done = app.buttons["media-viewer-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "The photo must open in the viewer", file: file, line: line)
        XCTAssertTrue(app.buttons["Change stage, currently \(stage)"].waitForExistence(timeout: 5), "The viewer must offer the photo's own stage", file: file, line: line)
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5), file: file, line: line)
    }

    func testLaterFilteredPhotosAndDocumentsRemainReachable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job-media", "--paper-preview-media-pages"]
        app.launch()
        XCTAssertTrue(app.buttons["Photo, Outdoor unit"].waitForExistence(timeout: 20))
        // Counts and filters say they cover what is loaded so far.
        let loadedNote = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Counts and filters apply to loaded items")).firstMatch
        for _ in 0..<4 where !loadedNote.exists { app.swipeUp() }
        XCTAssertTrue(loadedNote.exists)
        for _ in 0..<4 where !selector("After", in: app).isHittable { app.swipeDown() }
        selector("After", in: app).tap()
        XCTAssertTrue(app.staticTexts["No matches in loaded photos. More may be available."].waitForExistence(timeout: 5))
        let more = app.buttons["job-media-load-more-matches"]
        XCTAssertTrue(more.waitForExistence(timeout: 5)); more.tap()
        XCTAssertTrue(app.buttons["Photo, Later repair"].waitForExistence(timeout: 10))
        XCTAssertEqual(photoTiles(in: app).count, 1, "After shows the one After photo from the later page")
        // Documents sit under their own choice; the later page's document arrived too.
        selector("Documents", in: app).tap()
        XCTAssertTrue(app.staticTexts["Later document.pdf"].waitForExistence(timeout: 5))
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
        // #184: photos open the full-screen viewer (documents keep the system preview).
        let preview = app.buttons["media-viewer-done"]
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
        let undated = dayHeading("Date unavailable", in: app)
        XCTAssertTrue(undated.waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["Photo, Outdoor unit"].exists)
        selector("Before", in: app).tap()
        XCTAssertTrue(selector("Before", in: app).isSelected)
        XCTAssertTrue(undated.exists)
        XCTAssertTrue(app.buttons["Photo, Outdoor unit"].exists)
        assertViewerStage(app.buttons["Photo, Outdoor unit"], "Before", in: app)
    }

    func testDatedPhotosAreGroupedAndFilterKeepsCorrectPhotoActions() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job-media", "--paper-preview-media-dates", "-thorbis.appearance", "dark"]
        app.launch()
        let newest = dayHeading("Oct 27, 2026", in: app)
        let older = dayHeading("Oct 26, 2026", in: app)
        let unknown = dayHeading("Date unavailable", in: app)
        XCTAssertTrue(newest.waitForExistence(timeout: 20))
        XCTAssertTrue(older.exists)
        XCTAssertTrue(unknown.exists)
        XCTAssertLessThan(newest.frame.minY, older.frame.minY)
        XCTAssertLessThan(older.frame.minY, unknown.frame.minY)
        XCTAssertTrue(app.buttons["Photo, Outdoor unit"].isHittable)
        let top = XCTAttachment(screenshot: app.screenshot())
        top.name = "Job photo dates at top"
        top.lifetime = .keepAlways
        add(top)
        let finished = app.buttons["Photo, Finished unit"]
        for _ in 0..<5 where !finished.isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.37)))
        }
        XCTAssertTrue(finished.isHittable)
        let undated = app.buttons["Photo, Uncertain date"]
        for _ in 0..<5 where !undated.isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.37)))
        }
        XCTAssertTrue(undated.isHittable)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Job photos grouped by capture date"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let afterFilter = selector("After", in: app)
        for _ in 0..<5 where !afterFilter.isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78)))
        }
        XCTAssertTrue(afterFilter.isHittable)
        afterFilter.tap()
        XCTAssertTrue(older.exists)
        XCTAssertTrue(finished.exists)
        XCTAssertFalse(newest.exists)
        XCTAssertFalse(unknown.exists)
        assertViewerStage(finished, "After", in: app)
    }

    func testPhotoDateHeadingAtLargestText() {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job-media", "--paper-preview-media-dates", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let heading = dayHeading("Oct 27, 2026", in: app)
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
        // At accessibility sizes the selector folds into one "Show · All" menu.
        let filter = app.buttons["photo-filter-menu"]
        XCTAssertTrue(filter.waitForExistence(timeout: 20))
        for _ in 0..<6 where !filter.isHittable { app.swipeUp() }
        XCTAssertTrue(filter.isHittable)
        filter.tap()
        let after = app.buttons["After"]
        XCTAssertTrue(after.waitForExistence(timeout: 5))
        after.tap()
        XCTAssertTrue(after.waitForNonExistence(timeout: 5))
        XCTAssertTrue(filter.label.contains("After"), filter.label)
        let photo = app.buttons["Photo, Finished unit"]
        // Capture comes before the photos at this size (Import holds the library and PDFs).
        let library = app.buttons["job-media-import"]
        XCTAssertTrue(library.exists)
        let date = dayHeading("Oct 26, 2026", in: app)
        XCTAssertTrue(date.exists)
        XCTAssertLessThan(library.frame.minY, date.frame.minY, "Capture is available before a long photo collection")
        // Take photo stays on the screen; without a camera it says why (the stage is chosen after each shot since #184).
        XCTAssertTrue(app.buttons["job-media-take-photo"].exists)
        for _ in 0..<8 where !photo.isHittable { app.swipeUp() }
        XCTAssertTrue(photo.isHittable)
        // Two across at accessibility sizes (#184); each tile stays large enough to read and tap.
        XCTAssertGreaterThan(photo.frame.width, app.frame.width * 0.4)
        XCTAssertGreaterThan(photo.frame.height, 100)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Largest text photo remains usable"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        for _ in 0..<12 where !library.isHittable {
            let down = library.frame.midY < app.frame.midY
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.40 : 0.60))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.60 : 0.40))
            start.press(forDuration: 0.2, thenDragTo: end)
        }
        XCTAssertTrue(library.isHittable)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Library and document controls at largest text on narrow iPhone"
        capture.lifetime = .keepAlways
        add(capture)
        library.tap()
        let choosePhoto = app.buttons["Choose a photo"]
        XCTAssertTrue(choosePhoto.waitForExistence(timeout: 5))
        choosePhoto.tap()
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        cancel.tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 5))
        XCTAssertTrue(library.isHittable)
        library.tap()
        XCTAssertTrue(app.buttons["Choose a PDF"].waitForExistence(timeout: 5))
    }

    func testCaptureControlsPrecedeManyPendingUploadsAtLargestText() {
        continueAfterFailure = false
        let app = XCUIApplication()
        let base = ["--paper-preview", "--paper-preview-screen", "job-media", "--paper-preview-reset-media"]
        app.launchArguments = base + ["--paper-preview-many-pending", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        // A teardown block runs even after a failure stops the test, so no queue is left for later tests.
        addTeardownBlock { @MainActor in app.terminate(); app.launchArguments = base; app.launch(); app.terminate() }
        let firstPending = app.descendants(matching: .any).matching(identifier: "pending-media-00000000-0000-4000-8000-000000009800").firstMatch
        XCTAssertTrue(firstPending.waitForExistence(timeout: 20))
        let library = app.buttons["job-media-import"]
        XCTAssertTrue(library.exists)
        XCTAssertLessThan(library.frame.minY, firstPending.frame.minY, "Capture should precede the pending queue")
        // Since #184 the queue is one summary ("N saved on this phone") with Send now, and each row says its state.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", "saved on this phone")).firstMatch.exists)
        // Without a server the preview's sends fail, so a row may already say Failed; either way its state is a word.
        XCTAssertTrue(["Waiting", "Sending", "Failed"].contains { firstPending.label.hasSuffix(", \($0)") }, firstPending.label)
        // Send now (the retry) shows once the phone isn't mid-send.
        XCTAssertTrue(app.buttons["job-media-send-now"].waitForExistence(timeout: 30))
    }

    func testEmptyPhotoFilterOffersReturnToAllPhotos() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job-media"]
        app.launch()
        let afterFilter = selector("After", in: app)
        XCTAssertTrue(afterFilter.waitForExistence(timeout: 20))
        afterFilter.tap()
        XCTAssertTrue(app.staticTexts["No matching photos"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["No photos yet"].exists)
        let showAll = app.buttons["Show all photos"]
        XCTAssertTrue(showAll.isHittable)
        XCTAssertLessThan(showAll.frame.maxY, app.buttons["job-media-take-photo"].frame.minY, "The way back sits above the capture bar")
        let recovery = XCTAttachment(screenshot: app.screenshot())
        recovery.name = "Empty photo filter recovery above capture"
        recovery.lifetime = .keepAlways
        add(recovery)
        showAll.tap()
        let all = selector("All", in: app)
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
        // A teardown block runs even after a failure stops the test, so no scan is left for later tests.
        addTeardownBlock { @MainActor in
            app.terminate()
            app.launchArguments = base + ["--paper-preview-reset-media"]
            app.launch()
            app.terminate()
        }
        let scan = app.descendants(matching: .any).matching(identifier: "pending-media-00000000-0000-4000-8000-000000009701").firstMatch
        // #184: pending items read "<upload state> · captured <date>"; the capture date must survive.
        let expectedCapture = "captured " + stamp(Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertTrue(scan.waitForExistence(timeout: 20))
        XCTAssertTrue((scan.value as? String)?.lowercased().hasSuffix(expectedCapture.lowercased()) == true, String(describing: scan.value))
        XCTAssertTrue(scan.label.contains("Field scan.pdf"))
        XCTAssertFalse(app.staticTexts["No photos yet"].exists)
        // #184: Scan and Import are quiet circles beside Take photo.
        XCTAssertTrue(app.buttons["job-media-scan"].exists)
        XCTAssertTrue(app.buttons["Import a photo or PDF"].exists)
        thorbisSection(app, "Overview").tap()
        // Photos live under Activity; the Photos filter is remembered.
        thorbisSection(app, "Activity").tap()
        XCTAssertTrue(scan.waitForExistence(timeout: 10))
        XCTAssertTrue((scan.value as? String)?.lowercased().hasSuffix(expectedCapture.lowercased()) == true, String(describing: scan.value))
        app.terminate()
        app.launchArguments = base
        app.launch()
        XCTAssertTrue(scan.waitForExistence(timeout: 20))
        XCTAssertTrue((scan.value as? String)?.lowercased().hasSuffix(expectedCapture.lowercased()) == true, String(describing: scan.value))
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
        addTeardownBlock { @MainActor in app.terminate(); app.launchArguments = base + ["--paper-preview-reset-media"]; app.launch(); app.terminate() }
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
        // #184: the tile reads "<upload state> · captured <date>"; the original capture date must survive.
        let expected = "captured " + stamp(Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertTrue((row.value as? String)?.hasSuffix(expected) == true, String(describing: row.value))
        app.terminate(); app.launchArguments = base; app.launch()
        XCTAssertTrue(row.waitForExistence(timeout: 20)); XCTAssertTrue((row.value as? String)?.hasSuffix(expected) == true, String(describing: row.value))
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Explicitly recovered older photo after relaunch"; screenshot.lifetime = .keepAlways; add(screenshot)
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

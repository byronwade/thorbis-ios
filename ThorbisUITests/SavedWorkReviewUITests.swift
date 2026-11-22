import XCTest

@MainActor
final class SavedWorkReviewUITests: XCTestCase {
    private var cleanupArguments: [String]?
    override func tearDown() {
        if let base = cleanupArguments {
            let app = XCUIApplication(); app.terminate()
            app.launchArguments = base + ["--paper-preview-reset-saved-work"]
            app.launch(); app.terminate()
        }
        super.tearDown()
    }
    private func arguments(_ id: String) -> [String] {
        ["--paper-preview", "--paper-preview-screen", "schedule", "--paper-preview-saved-work-session", id, "-thorbis.appearance", "light"]
    }
    private func open(_ extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication(), id = UUID().uuidString
        let base = arguments(id) + extra
        cleanupArguments = base
        print("Owned saved-work fixture: \(id)")
        app.launchArguments = base + ["--paper-preview-reset-saved-work", "--paper-preview-seed-saved-work"]
        app.launch()
        XCTAssertTrue(app.buttons["saved-work-summary"].waitForExistence(timeout: 20))
        app.buttons["saved-work-summary"].tap()
        XCTAssertTrue(app.savedWorkReview.waitForExistence(timeout: 5))
        return app
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name
        image.lifetime = .keepAlways; add(image)
        let screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); screen.name = "Full screen " + name
        screen.lifetime = .keepAlways; add(screen)
    }
    /// Brings `element` above the pinned Send now / Keep working bar (Paper 73B). A row under that
    /// bar still reports hittable, and a tap on it lands on Send now.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let bar = app.buttons["saved-work-sync"]
        func clear() -> Bool {
            guard element.exists, element.isHittable else { return false }
            return !bar.exists || element.frame.maxY <= bar.frame.minY - 4 || element.frame.minY >= bar.frame.maxY
        }
        for _ in 0..<10 where !clear() {
            // A held drag has no momentum, so the row cannot be flung past the viewport.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)))
        }
        XCTAssertTrue(clear(), app.debugDescription)
    }
    func testDrawerOpensScopedSavedWorkWithCommandsAndMedia() {
        continueAfterFailure = false
        let app = XCUIApplication(), id = UUID().uuidString
        let base = arguments(id)
        cleanupArguments = base
        app.launchArguments = base + ["--paper-preview-reset-saved-work", "--paper-preview-seed-saved-work"]
        app.launch()
        // The menu circle says what is still on the phone; the drawer's gear opens the review. On
        // iPad the sidebar's "Saved on this iPad" row says it and opens the same review.
        let status = NSPredicate(format: "value CONTAINS %@", "saved item")
        if app.usesTabletLayout {
            app.showSidebar()
            let row = app.buttons["sidebar-saved-work"]
            XCTAssertTrue(row.waitForExistence(timeout: 20))
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: status, object: row)], timeout: 15), .completed)
            row.tap()
        } else {
            let menu = app.drawerMenu
            XCTAssertTrue(menu.waitForExistence(timeout: 20))
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: status, object: menu)], timeout: 15), .completed)
            app.openSavedWorkFromDrawer()
        }
        XCTAssertTrue(app.savedWorkReview.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "saved-work-command:00000000-0000-4000-8000-000000009711").firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Foreign actor scan.pdf"].exists)
    }
    func testDoneReturnsToOriginalScheduleAndForeignMediaIsHidden() {
        let app = open()
        XCTAssertFalse(app.staticTexts["Foreign actor scan.pdf"].exists)
        XCTAssertTrue(app.buttons["saved-work-done"].isHittable)
        capture(app, "Mixed saved work with native Done")
        app.buttons["saved-work-done"].tap()
        XCTAssertTrue(app.waitForSchedule(), "Leaving the review returns to Schedule")
        XCTAssertFalse(app.savedWorkReview.exists)
    }
    func testUncachedJobBackAndNestedBannerReturnUseSameSheet() {
        let app = open()
        let uncached = app.buttons["saved-work-open-00000000-0000-4000-8000-000000009951"]
        reveal(uncached, in: app); uncached.tap()
        XCTAssertTrue(app.staticTexts["Uncached drain visit"].waitForExistence(timeout: 10))
        capture(app, "Uncached job opened inside review")
        app.navigationBars.buttons["Back"].firstMatch.tap()
        XCTAssertTrue(app.savedWorkReview.waitForExistence(timeout: 5))
        let cached = app.buttons["saved-work-open-00000000-0000-4000-8000-000000002214"]
        app.scrollViews["saved-work-review"].swipeDown()
        reveal(cached, in: app); cached.tap()
        XCTAssertTrue(app.buttons["saved-work-summary"].firstMatch.waitForExistence(timeout: 10))
        let visibleBanners = app.buttons.matching(identifier: "saved-work-summary").allElementsBoundByIndex.filter { $0.isHittable }
        XCTAssertEqual(visibleBanners.count, 1, "Only the pushed job's banner is actionable")
        visibleBanners[0].tap()
        XCTAssertTrue(app.savedWorkReview.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["saved-work-done"].isHittable)
        capture(app, "Nested job banner returns to same review")
        app.buttons["saved-work-done"].tap()
        XCTAssertTrue(app.waitForSchedule(), "Leaving the review returns to Schedule")
    }
    func testOfflineReviewKeepsSyncDisabledAndDiscardNeedsConfirmation() {
        let app = open(["--paper-preview-saved-work-offline"])
        XCTAssertTrue(app.staticTexts["Offline · work stays saved on this phone"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["saved-work-sync"].isEnabled)
        let dismiss = app.buttons["saved-work-dismiss-00000000-0000-4000-8000-000000009711"]
        reveal(dismiss, in: app); dismiss.tap()
        XCTAssertTrue(app.discardQuestion.waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.discardQuestion.waitForNonExistence(timeout: 5))
        XCTAssertTrue(dismiss.exists)
        dismiss.tap()
        XCTAssertTrue(app.buttons["Discard"].waitForExistence(timeout: 5))
        app.buttons["Discard"].tap()
        XCTAssertTrue(dismiss.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["On hold"].exists)
        capture(app, "Offline discard keeps media and releases later change")
    }
    func testDirectRequestInvalidationRetiresReview() {
        let app = open(["--paper-preview-saved-work-controls"])
        app.buttons["Sample controls"].tap()
        app.buttons["Retire sample requests"].tap()
        XCTAssertTrue(app.savedWorkReview.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.waitForSchedule(), "Leaving the review returns to Schedule")
        app.buttons["saved-work-summary"].tap()
        XCTAssertTrue(app.savedWorkReview.waitForExistence(timeout: 5))
    }
    func testOutboxOnlyRoundTripRetiresReviewAndKeepsOriginalChanges() {
        let app = open(["--paper-preview-saved-work-controls"])
        app.buttons["Sample controls"].tap()
        app.buttons["Rebind sample commands"].tap()
        XCTAssertTrue(app.savedWorkReview.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.waitForSchedule(), "Leaving the review returns to Schedule")
        app.buttons["saved-work-summary"].tap()
        XCTAssertTrue(app.savedWorkReview.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["saved-work-dismiss-00000000-0000-4000-8000-000000009711"].exists)
        capture(app, "Outbox binding round trip retires old review and preserves work")
    }
    func testEditOnlyRevocationCancelsAlertAndRetainsReadOnlyReviewWithoutMutation() throws {
        let app = open(["--paper-preview-saved-work-controls"])
        app.buttons["Sample controls"].tap()
        // The sample revocation lands five seconds after its tap, and bringing the row above the
        // pinned bar can take most of that, so the row is found first and the question is opened
        // straight after the revoke tap (as the workspace-change test does).
        let dismiss = app.buttons["saved-work-dismiss-00000000-0000-4000-8000-000000009711"]
        reveal(dismiss, in: app)
        app.buttons["Revoke sample editing shortly"].tap()
        dismiss.tap()
        XCTAssertTrue(app.discardQuestion.waitForExistence(timeout: 5))
        XCTAssertTrue(app.discardQuestion.waitForNonExistence(timeout: 12))
        XCTAssertTrue(app.savedWorkReview.exists)
        XCTAssertFalse(app.buttons["saved-work-sync"].isEnabled)
        XCTAssertFalse(dismiss.isEnabled)
        XCTAssertFalse(app.buttons["saved-work-retry-00000000-0000-4000-8000-000000009711"].isEnabled)
        let proof = app.staticTexts["saved-work-edit-revocation-proof"]
        for _ in 0..<5 {
            if proof.exists && proof.isHittable { break }
            app.scrollViews["saved-work-review"].swipeDown()
        }
        XCTAssertTrue(proof.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["You can review saved work. Your current access doesn't allow retrying or discarding changes."].exists)
        let text = try XCTUnwrap(proof.value as? String)
        let receipt = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let before = try XCTUnwrap(receipt["filesBefore"] as? [String: String])
        XCTAssertEqual(before.count, 7, "Original command file and all three media metadata/payload pairs")
        XCTAssertEqual(before, receipt["filesAfter"] as? [String: String])
        XCTAssertEqual(receipt["mutationsBefore"] as? Int, receipt["mutationsAfter"] as? Int)
        XCTAssertEqual(receipt["sameActor"] as? Bool, true); XCTAssertEqual(receipt["sameWorkspace"] as? Bool, true)
        XCTAssertEqual(receipt["viewScopeStillCurrent"] as? Bool, true); XCTAssertEqual(receipt["canEdit"] as? Bool, false)
        let attachment = XCTAttachment(string: text); attachment.name = "Edit revocation actual file hashes and request receipt"
        attachment.lifetime = .keepAlways; add(attachment)
        capture(app, "Edit-only revocation retains read-only review and cancels stale alert")
    }
    func testWorkspaceChangeRetiresOpenDiscardConfirmation() {
        let app = open(["--paper-preview-saved-work-controls"])
        app.buttons["Sample controls"].tap()
        // The sample switch fires five seconds after its tap, so the row is found first and the
        // question is opened straight after.
        let dismiss = app.buttons["saved-work-dismiss-00000000-0000-4000-8000-000000009711"]
        reveal(dismiss, in: app)
        app.buttons["Switch sample workspace shortly"].tap()
        dismiss.tap()
        // The question is up when the switch lands about a second later; asking whether Discard can
        // be tapped in that second races the sheet leaving.
        XCTAssertTrue(app.discardQuestion.waitForExistence(timeout: 5))
        XCTAssertTrue(app.savedWorkReview.waitForNonExistence(timeout: 15))
        // The question is its own sheet over the review: it leaves with the review, one sheet
        // animation later, so it is waited out rather than read in the same instant.
        XCTAssertTrue(app.buttons["Discard"].waitForNonExistence(timeout: 3), "The stale question must retire with the review")
        XCTAssertTrue(app.discardQuestion.waitForNonExistence(timeout: 1))
        XCTAssertFalse(app.buttons["saved-work-summary"].exists)
        let originalScreen = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: app.scheduleTitle)
        XCTAssertEqual(XCTWaiter.wait(for: [originalScreen], timeout: 5), .completed, "The entire modal must retire, not leave a blank blocking sheet")
        capture(app, "Workspace change retires review and stale confirmation")
    }
    func testExistingAuthorityDeadlineRetiresReview() {
        let app = open(["--paper-preview-saved-work-expiry"])
        XCTAssertTrue(app.savedWorkReview.waitForNonExistence(timeout: 20))
        XCTAssertFalse(app.buttons["saved-work-done"].exists)
        capture(app, "Expired authority retires saved-work review")
    }
    func testLandscapeReviewHasNativeCancelAndKeepsAllRecoveryActions() {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = open()
        XCTAssertGreaterThan(app.frame.width, app.frame.height, "Landscape must be exercised, not merely requested")
        let dismiss = app.buttons["saved-work-dismiss-00000000-0000-4000-8000-000000009711"]
        reveal(dismiss, in: app); dismiss.tap()
        XCTAssertTrue(app.discardQuestion.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Cancel"].isHittable)
        XCTAssertTrue(app.buttons["Discard"].isHittable)
        capture(app, "Landscape explicit Cancel and Discard")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.discardQuestion.waitForNonExistence(timeout: 5))
        XCTAssertTrue(dismiss.isHittable)
        capture(app, "Landscape review after cancel")
        app.buttons["saved-work-done"].tap()
        XCTAssertFalse(app.savedWorkReview.exists)
    }
    func testLargeTextDarkReviewHasReachableRecoveryAndDone() {
        let app = open(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-thorbis.appearance", "dark"])
        capture(app, "Large text dark review top")
        let dismiss = app.buttons["saved-work-dismiss-00000000-0000-4000-8000-000000009711"]
        reveal(dismiss, in: app)
        XCTAssertGreaterThanOrEqual(dismiss.frame.height, 44)
        capture(app, "Large text dark recovery actions")
        XCTAssertTrue(app.buttons["saved-work-done"].isHittable)
        app.buttons["saved-work-done"].tap()
        XCTAssertTrue(app.waitForSchedule(), "Leaving the review returns to Schedule")
    }
    func testMixedSavedWorkOpensAndSurvivesRelaunch() {
        continueAfterFailure = false
        let app = XCUIApplication(), id = UUID().uuidString
        let base = arguments(id)
        cleanupArguments = base
        print("Owned saved-work fixture: \(id)")
        app.launchArguments = base + ["--paper-preview-reset-saved-work", "--paper-preview-seed-saved-work"]
        app.launch()
        let summary = app.buttons["saved-work-summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 20), "Both queues need one reachable review")
        summary.tap()
        XCTAssertTrue(app.savedWorkReview.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "saved-work-command:00000000-0000-4000-8000-000000009711").firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Before photo"].exists)
        reveal(app.staticTexts["Field scan.pdf"], in: app)
        app.terminate(); app.launchArguments = base; app.launch()
        XCTAssertTrue(summary.waitForExistence(timeout: 20)); summary.tap()
        XCTAssertTrue(app.savedWorkReview.waitForExistence(timeout: 5))
        reveal(app.staticTexts["Field scan.pdf"], in: app)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "Saved work after real queue relaunch"
        attachment.lifetime = .keepAlways; add(attachment)
    }
}

private extension XCUIApplication {
    /// The schedule place's title. It reads "Today", "This week" or "Board" with the range, so the
    /// review's return is checked by identifier, not by the words.
    var scheduleTitle: XCUIElement { staticTexts["schedule-title"] }
    /// Schedule is reachable again. The review sheet slides away after Done or a retirement, so a
    /// single read can land mid-slide (CI 41ac2c7, shard 3); wait for it, as the workspace-change test does.
    func waitForSchedule(timeout: TimeInterval = 5) -> Bool {
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: scheduleTitle)
        return XCTWaiter.wait(for: [shown], timeout: timeout) == .completed
    }
    /// The discard confirmation is a Thorbis confirm sheet (not a system alert): its question is
    /// the sheet's title, and its choices are the "Cancel" and "Discard" buttons.
    var discardQuestion: XCUIElement { staticTexts["Discard saved change?"] }
    /// The review's root. Its bar is titled "Saved on this phone" (the title view itself is empty, the
    /// heading sits in the content); where a bar with a custom title view reports no title, the
    /// review's own list stands in. Either one is on screen only while the review's root shows.
    var savedWorkReview: XCUIElement {
        let bar = navigationBars["Saved on this phone"]
        return bar.exists ? bar : scrollViews["saved-work-review"]
    }
}

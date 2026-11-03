import XCTest

@MainActor
final class EstimateCreationRecoveryUITests: XCTestCase {
    func testCancelCustomerOnlyEditRequiresConfirmationAndDoesNotRestoreCanceledCustomer() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "new-estimate",
            "--paper-preview-estimate-create-recovery", "--paper-preview-estimate-recovery-standalone",
            "--commercial-draft-test-id", UUID().uuidString]
        app.launch()
        let original = app.buttons.matching(NSPredicate(format: "label == %@", "Danielle Marlowe")).firstMatch
        XCTAssertTrue(original.waitForExistence(timeout: 30)); original.tap()
        let alternate = app.buttons["Alex Petrov"]
        XCTAssertTrue(alternate.waitForExistence(timeout: 10)); alternate.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Alex Petrov")).firstMatch.waitForExistence(timeout: 10))
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Discard changes"].waitForExistence(timeout: 5))
        app.buttons["Discard changes"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Danielle Marlowe")).firstMatch.waitForExistence(timeout: 20))
    }

    func testCancelTitleOnlyEditRequiresConfirmationAndDoesNotRestoreCanceledText() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "new-estimate",
            "--paper-preview-estimate-create-recovery", "--commercial-draft-test-id", UUID().uuidString]
        app.launch()
        let title = app.textFields["Estimate title"]
        XCTAssertTrue(title.waitForExistence(timeout: 30))
        let original = title.value as? String ?? ""
        title.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap(); title.typeText(" canceled")
        XCTAssertEqual(title.value as? String, original + " canceled")
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Discard changes"].waitForExistence(timeout: 5))
        app.buttons["Discard changes"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 10))
        app.terminate(); app.launch()
        let reopened = app.textFields["Estimate title"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 20))
        XCTAssertEqual(reopened.value as? String, original)
    }

    func testExistingEditorRetainsEditsThroughOfflineAndReconnect() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "new-estimate",
            "--paper-preview-estimate-create-recovery", "--paper-preview-catalog-pages",
            "--paper-preview-estimate-recovery-toggle-offline", "--commercial-draft-test-id", UUID().uuidString]
        app.launch()
        let title = app.textFields["Estimate title"]
        XCTAssertTrue(title.waitForExistence(timeout: 30))
        let original = title.value as? String ?? ""
        let toggle = app.buttons["estimate-recovery-toggle-network"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10)); toggle.tap()
        XCTAssertTrue(app.staticTexts["Sample offline"].waitForExistence(timeout: 15))
        XCTAssertTrue(title.exists); XCTAssertTrue(title.isEnabled)
        title.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap(); title.typeText(" offline")
        XCTAssertEqual(title.value as? String, original + " offline")
        toggle.tap()
        XCTAssertTrue(app.staticTexts["Sample online"].waitForExistence(timeout: 15))
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        XCTAssertEqual(title.value as? String, original + " offline")
    }

    func testSameSessionRevalidationHidesDraftUntilJobAccessReturns() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "new-estimate",
            "--paper-preview-estimate-create-recovery", "--paper-preview-catalog-pages",
            "--paper-preview-estimate-recovery-toggle-job", "--commercial-draft-test-id", UUID().uuidString]
        app.launch()
        addSampleItem(in: app)
        let toggle = app.buttons["estimate-recovery-toggle-job"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        toggle.tap()
        XCTAssertTrue(app.staticTexts["Document unavailable"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.textFields["Estimate title"].exists)
        toggle.tap()
        XCTAssertTrue(app.textFields["Estimate title"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Replace capacitor")).firstMatch.waitForExistence(timeout: 10))
    }

    func testSavedDraftRemainsAvailableAfterOfflineResourceCheckAndReconnect() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "new-estimate",
            "--paper-preview-estimate-create-recovery", "--paper-preview-catalog-pages",
            "--commercial-draft-test-id", UUID().uuidString]
        app.launch()
        addSampleItem(in: app)
        app.terminate()
        app.launchArguments.append("--paper-preview-estimate-recovery-offline-job")
        app.launch()
        XCTAssertTrue(app.staticTexts["Document unavailable"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.textFields["Estimate title"].exists)
        app.terminate()
        app.launchArguments.removeAll { $0 == "--paper-preview-estimate-recovery-offline-job" }
        app.launch()
        XCTAssertTrue(app.textFields["Estimate title"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Replace capacitor")).firstMatch.waitForExistence(timeout: 10))
    }

    func testSavedDraftIsHiddenWhenJobAccessIsRevoked() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "new-estimate",
            "--paper-preview-estimate-create-recovery", "--paper-preview-catalog-pages",
            "--commercial-draft-test-id", UUID().uuidString]
        app.launch()
        addSampleItem(in: app)
        app.terminate()
        app.launchArguments.append("--paper-preview-estimate-recovery-deny-job")
        app.launch()
        XCTAssertTrue(app.staticTexts["Document unavailable"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.textFields["Estimate title"].exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Save estimate")).firstMatch.exists)
        app.terminate()
        app.launchArguments.removeAll { $0 == "--paper-preview-estimate-recovery-deny-job" }
        app.launch()
        XCTAssertTrue(app.textFields["Estimate title"].waitForExistence(timeout: 15), "The preserved draft should reopen after access returns")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Replace capacitor")).firstMatch.waitForExistence(timeout: 10))
    }

    func testRelaunchAfterInterruptedCreateKeepsUncertainDraftAndDoesNotCreateAgain() {
        checkInterruptedRequest(extra: "--paper-preview-estimate-create-hold", expected: "creates=1,links=0,estimateReads=0,jobReads=0", hasSavedID: false)
    }

    func testRelaunchAfterInterruptedLinkKeepsKnownEstimateWithoutAutomaticRetry() {
        checkInterruptedRequest(extra: "--paper-preview-estimate-link-hold", expected: "creates=1,links=1,estimateReads=0,jobReads=0", hasSavedID: true)
    }

    private func checkInterruptedRequest(extra: String, expected: String, hasSavedID: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "new-estimate",
            "--paper-preview-estimate-create-recovery", "--paper-preview-catalog-pages",
            "--commercial-draft-test-id", UUID().uuidString, extra]
        app.launch()
        addSampleItem(in: app)
        let save = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Save estimate")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        save.tap()
        let counts = app.staticTexts["estimate-recovery-request-counts"]
        XCTAssertTrue(counts.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "value == %@", expected), evaluatedWith: counts)
        waitForExpectations(timeout: 10)
        app.terminate()
        if hasSavedID {
            app.launchArguments.removeAll { $0 == "--paper-preview-estimate-link-hold" }
            app.launchArguments.append("--paper-preview-estimate-recovery-link-success")
        }
        app.launch()
        let recoveredCounts = app.staticTexts["estimate-recovery-request-counts"]
        XCTAssertTrue(recoveredCounts.waitForExistence(timeout: 15))
        let warning = hasSavedID ? "job link could not be confirmed" : "previous save could not be confirmed"
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", warning)).firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(recoveredCounts.value as? String, "creates=0,links=0,estimateReads=0,jobReads=0")
        let unexpectedRequest = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", "creates=0,links=0,estimateReads=0,jobReads=0"), object: recoveredCounts)
        unexpectedRequest.isInverted = true
        wait(for: [unexpectedRequest], timeout: 2)
        if !hasSavedID {
            let action = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Save estimate")).firstMatch
            XCTAssertFalse(action.isEnabled)
        } else {
            let retry = app.buttons["Retry adding to job"]
            XCTAssertTrue(retry.waitForExistence(timeout: 10))
            XCTAssertTrue(retry.isEnabled)
            retry.tap()
            assertOpenedSavedEstimate(in: app, counts: "creates=0,links=1,estimateReads=1,jobReads=1")
        }
    }

    func testSuccessfulLinkWithFailedDraftCleanupReportsSavedAndRelaunchDoesNotWrite() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "new-estimate",
            "--paper-preview-estimate-create-recovery", "--paper-preview-catalog-pages",
            "--paper-preview-estimate-recovery-link-success", "--commercial-draft-test-cleanup-fails",
            "--commercial-draft-test-id", UUID().uuidString]
        app.launch()
        addSampleItem(in: app)
        let save = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Save estimate")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        save.tap()
        let failure = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "estimate was saved, but its local draft could not be removed")).firstMatch
        XCTAssertTrue(failure.waitForExistence(timeout: 10))
        let counts = app.staticTexts["estimate-recovery-request-counts"]
        XCTAssertEqual(counts.value as? String, "creates=1,links=1,estimateReads=0,jobReads=0")
        app.terminate()
        app.launch()
        let recoveredCounts = app.staticTexts["estimate-recovery-request-counts"]
        XCTAssertTrue(recoveredCounts.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "job link could not be confirmed")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(recoveredCounts.value as? String, "creates=0,links=0,estimateReads=1,jobReads=1")
        let unexpectedRequest = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", "creates=0,links=0,estimateReads=1,jobReads=1"), object: recoveredCounts)
        unexpectedRequest.isInverted = true
        wait(for: [unexpectedRequest], timeout: 2)
    }
    func testAuthorityChangeDuringCreateDoesNotLinkBeforeFreshVerification() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "new-estimate",
                               "--paper-preview-estimate-create-recovery", "--paper-preview-estimate-create-hold",
                               "--paper-preview-estimate-recovery-normalized-dates", "--paper-preview-catalog-pages"]
        app.launch()
        addSampleItem(in: app)
        let save = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Save estimate")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        save.tap()
        let counts = app.staticTexts["estimate-recovery-request-counts"]
        XCTAssertTrue(counts.waitForExistence(timeout: 10))
        let firstCreate = NSPredicate(format: "value == %@", "creates=1,links=0,estimateReads=0,jobReads=0")
        expectation(for: firstCreate, evaluatedWith: counts)
        waitForExpectations(timeout: 10)
        let revalidate = app.buttons["Revalidate sample"]
        XCTAssertTrue(revalidate.waitForExistence(timeout: 5))
        revalidate.tap()
        let retry = app.buttons["Retry adding to job"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        XCTAssertEqual(counts.value as? String, "creates=1,links=0,estimateReads=0,jobReads=0", "The old authority must not issue a link")
        XCTAssertFalse(app.textFields["Estimate title"].isEnabled, "The known saved estimate stays locked")
        retry.tap()
        let firstLink = NSPredicate(format: "value == %@", "creates=1,links=1,estimateReads=1,jobReads=1")
        expectation(for: firstLink, evaluatedWith: counts)
        waitForExpectations(timeout: 10)
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: retry)
        waitForExpectations(timeout: 10)
        retry.tap()
        assertOpenedSavedEstimate(in: app, counts: "creates=1,links=2,estimateReads=2,jobReads=2")
    }

    func testAuthorityRefreshRejectsChangedEstimateBeforeLink() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "new-estimate",
                               "--paper-preview-estimate-create-recovery", "--paper-preview-estimate-create-hold",
                               "--paper-preview-estimate-recovery-changed", "--paper-preview-catalog-pages"]
        app.launch()
        addSampleItem(in: app)
        let save = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Save estimate")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        save.tap()
        let counts = app.staticTexts["estimate-recovery-request-counts"]
        XCTAssertTrue(counts.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "value == %@", "creates=1,links=0,estimateReads=0,jobReads=0"), evaluatedWith: counts)
        waitForExpectations(timeout: 10)
        app.buttons["Revalidate sample"].tap()
        let retry = app.buttons["Retry adding to job"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        retry.tap()
        expectation(for: NSPredicate(format: "value == %@", "creates=1,links=0,estimateReads=1,jobReads=0"), evaluatedWith: counts)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "saved estimate or your access changed")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["Estimate title"].isEnabled)
    }

    func testDifferentCreatedLocationIsRetainedAndOnlyLinkedAfterFreshJobMatch() {
        checkDifferentCreatedLocation(jobMatches: true)
    }

    func testDifferentCreatedLocationIsNotLinkedToMismatchedJob() {
        checkDifferentCreatedLocation(jobMatches: false)
    }

    private func checkDifferentCreatedLocation(jobMatches: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "new-estimate",
                               "--paper-preview-estimate-create-recovery", "--paper-preview-estimate-recovery-other-location",
                               "--paper-preview-catalog-pages"]
        if jobMatches { app.launchArguments.append("--paper-preview-estimate-recovery-matching-location") }
        app.launch()
        addSampleItem(in: app)
        let save = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Save estimate")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        save.tap()
        let retry = app.buttons["Retry adding to job"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        let counts = app.staticTexts["estimate-recovery-request-counts"]
        XCTAssertTrue(counts.waitForExistence(timeout: 5))
        XCTAssertEqual(counts.value as? String, "creates=1,links=0,estimateReads=0,jobReads=0")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "saved with a different location")).firstMatch.exists)
        retry.tap()
        let expected = jobMatches ? "creates=1,links=1,estimateReads=1,jobReads=1" : "creates=1,links=0,estimateReads=1,jobReads=1"
        expectation(for: NSPredicate(format: "value == %@", expected), evaluatedWith: counts)
        waitForExpectations(timeout: 10)
        if jobMatches {
            expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: retry)
            waitForExpectations(timeout: 10)
            retry.tap()
            assertOpenedSavedEstimate(in: app, counts: "creates=1,links=2,estimateReads=2,jobReads=2")
        } else {
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "job or your access changed")).firstMatch.waitForExistence(timeout: 5))
            XCTAssertFalse(app.textFields["Estimate title"].isEnabled)
        }
    }

    func testSameAuthorityRetryRejectsAnEstimateChangedAfterLinkFailure() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "new-estimate",
                               "--paper-preview-estimate-create-recovery", "--paper-preview-catalog-pages",
                               "--paper-preview-estimate-recovery-changed-after-link"]
        app.launch()
        addSampleItem(in: app)
        let save = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Save estimate")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        save.tap()
        let retry = app.buttons["Retry adding to job"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: retry)
        waitForExpectations(timeout: 10)
        retry.tap()
        let counts = app.staticTexts["estimate-recovery-request-counts"]
        expectation(for: NSPredicate(format: "value == %@", "creates=1,links=1,estimateReads=1,jobReads=0"), evaluatedWith: counts)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "saved estimate or your access changed")).firstMatch.waitForExistence(timeout: 5))
    }

    func testCreatedEstimateWithChangedTermsRequiresReviewWithoutLinking() {
        checkUnexpectedCreatedResult(extra: "--paper-preview-estimate-recovery-changed-terms", standalone: false)
    }

    func testStandaloneEstimateWithUnexpectedLocationRequiresReview() {
        checkUnexpectedCreatedResult(extra: "--paper-preview-estimate-recovery-other-location", standalone: true)
    }

    private func checkUnexpectedCreatedResult(extra: String, standalone: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "new-estimate",
                               "--paper-preview-estimate-create-recovery", "--paper-preview-catalog-pages", extra]
        if standalone { app.launchArguments.append("--paper-preview-estimate-recovery-standalone") }
        app.launch()
        addSampleItem(in: app)
        let save = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Save estimate")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        save.tap()
        let title = standalone ? "Open saved estimate" : "Retry adding to job"
        let action = app.buttons[title]
        XCTAssertTrue(action.waitForExistence(timeout: 10))
        XCTAssertFalse(action.isEnabled)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "details differ from your submission")).firstMatch.waitForExistence(timeout: 5))
        let counts = app.staticTexts["estimate-recovery-request-counts"]
        XCTAssertTrue(counts.waitForExistence(timeout: 5))
        XCTAssertEqual(counts.value as? String, "creates=1,links=0,estimateReads=0,jobReads=0")
    }

    func testLostGroupsRequireExplicitChoiceBeforeLinking() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "new-estimate",
                               "--paper-preview-estimate-create-recovery", "--paper-preview-catalog-pages",
                               "--paper-preview-estimate-group-feature", "--paper-preview-estimate-drop-groups"]
        app.launch()
        addSampleItem(in: app)
        let save = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Save estimate")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        save.tap()
        let continueButton = app.buttons["Continue without groups"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 10))
        let counts = app.staticTexts["estimate-recovery-request-counts"]
        XCTAssertTrue(counts.waitForExistence(timeout: 5))
        XCTAssertEqual(counts.value as? String, "creates=1,links=0,estimateReads=0,jobReads=0")
        continueButton.tap()
        XCTAssertTrue(app.staticTexts["Continue without item groups?"].waitForExistence(timeout: 5))
        let confirmation = app.buttons.matching(identifier: "Continue without groups").allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(confirmation, "The confirmation action must be reachable")
        confirmation?.tap()
        let retry = app.buttons["Retry adding to job"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        retry.tap()
        assertOpenedSavedEstimate(in: app, counts: "creates=1,links=2,estimateReads=2,jobReads=2")
    }

    func testDroppedHiddenLineVisibilityBlocksLink() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "new-estimate",
                               "--paper-preview-estimate-create-recovery", "--paper-preview-catalog-pages",
                               "--paper-preview-estimate-group-feature", "--paper-preview-estimate-drop-visibility"]
        app.launch()
        addSampleItem(in: app)
        let visibility = app.switches["Show on estimate"]
        XCTAssertTrue(visibility.waitForExistence(timeout: 10))
        visibility.tap()
        let save = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Save estimate")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        save.tap()
        let retry = app.buttons["Retry adding to job"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        XCTAssertFalse(retry.isEnabled)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "details differ from your submission")).firstMatch.waitForExistence(timeout: 5))
        let counts = app.staticTexts["estimate-recovery-request-counts"]
        XCTAssertEqual(counts.value as? String, "creates=1,links=0,estimateReads=0,jobReads=0")
    }

    private func addSampleItem(in app: XCUIApplication) {
        let add = app.buttons.matching(identifier: "estimate-add-item").firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 30))
        let clear = app.frame.height * 0.7
        for _ in 0..<10 where !add.isHittable || add.frame.maxY > clear {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)))
        }
        XCTAssertTrue(add.isHittable)
        add.tap()
        let search = app.textFields["price-book-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("Replace capacitor")
        let item = app.buttons["price-book-item-00000000-0000-4000-8000-000000009201"]
        XCTAssertTrue(item.waitForExistence(timeout: 15))
        item.tap()
        app.buttons["price-book-done"].tap()
    }

    func testFailedLinkKeepsSavedEstimateLockedAndRetriesWithoutCreatingAgain() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "new-estimate",
                               "--paper-preview-estimate-create-recovery", "--paper-preview-catalog-pages"]
        app.launch()
        addSampleItem(in: app)
        let line = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Replace capacitor")).firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 10))
        line.tap()
        let description = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Line description")).firstMatch
        let quantity = app.textFields["Quantity"]
        let price = app.textFields.matching(NSPredicate(format: "label BEGINSWITH %@", "Price ")).firstMatch
        XCTAssertTrue(description.waitForExistence(timeout: 5))
        XCTAssertTrue(quantity.waitForExistence(timeout: 5))
        XCTAssertTrue(price.waitForExistence(timeout: 5))
        let originalDescription = description.value as? String
        let originalQuantity = quantity.value as? String
        let originalPrice = price.value as? String
        let save = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Save estimate")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        save.tap()
        let retry = app.buttons["Retry adding to job"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "adding it to this job could not be confirmed")).firstMatch.exists)
        XCTAssertFalse(app.textFields["Estimate title"].isEnabled)
        XCTAssertFalse(app.buttons.matching(identifier: "estimate-add-item").firstMatch.isEnabled)
        XCTAssertTrue(description.exists)
        XCTAssertTrue(quantity.exists)
        XCTAssertTrue(price.exists)
        XCTAssertEqual(description.value as? String, originalDescription)
        XCTAssertEqual(quantity.value as? String, originalQuantity)
        XCTAssertEqual(price.value as? String, originalPrice)
        XCTAssertFalse(description.isEnabled)
        XCTAssertFalse(quantity.isEnabled)
        XCTAssertFalse(price.isEnabled)
        let counts = app.staticTexts["estimate-recovery-request-counts"]
        XCTAssertTrue(counts.waitForExistence(timeout: 5))
        XCTAssertEqual(counts.value as? String, "creates=1,links=1,estimateReads=0,jobReads=0")
        retry.tap()
        assertOpenedSavedEstimate(in: app, counts: "creates=1,links=2,estimateReads=1,jobReads=1")
    }

    private func assertOpenedSavedEstimate(in app: XCUIApplication, counts expected: String) {
        let detailCounts = app.staticTexts["estimate-recovery-detail-counts"]
        XCTAssertTrue(detailCounts.waitForExistence(timeout: 10), "The saved estimate detail must open")
        XCTAssertEqual(detailCounts.value as? String, expected)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "EST-8901")).firstMatch.waitForExistence(timeout: 10))
    }
}

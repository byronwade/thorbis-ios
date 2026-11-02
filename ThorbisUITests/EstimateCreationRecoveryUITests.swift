import XCTest

@MainActor
final class EstimateCreationRecoveryUITests: XCTestCase {
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
        assertOpenedSavedEstimate(in: app, counts: "creates=1,links=2,estimateReads=1,jobReads=1")
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
            assertOpenedSavedEstimate(in: app, counts: "creates=1,links=2,estimateReads=1,jobReads=1")
        } else {
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "job or your access changed")).firstMatch.waitForExistence(timeout: 5))
            XCTAssertFalse(app.textFields["Estimate title"].isEnabled)
        }
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
        app.buttons.matching(identifier: "Continue without groups").lastMatch.tap()
        let retry = app.buttons["Retry adding to job"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        retry.tap()
        assertOpenedSavedEstimate(in: app, counts: "creates=1,links=2,estimateReads=0,jobReads=0")
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
        for _ in 0..<5 where !add.isHittable { app.swipeUp() }
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
        assertOpenedSavedEstimate(in: app, counts: "creates=1,links=2,estimateReads=0,jobReads=0")
    }

    private func assertOpenedSavedEstimate(in app: XCUIApplication, counts expected: String) {
        let detailCounts = app.staticTexts["estimate-recovery-detail-counts"]
        XCTAssertTrue(detailCounts.waitForExistence(timeout: 10), "The saved estimate detail must open")
        XCTAssertEqual(detailCounts.value as? String, expected)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "EST-8901")).firstMatch.waitForExistence(timeout: 10))
    }
}

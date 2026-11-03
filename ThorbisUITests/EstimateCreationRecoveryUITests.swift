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
        let verifiedReads = hasSavedID ? "creates=0,links=0,estimateReads=1,jobReads=1" : "creates=0,links=0,estimateReads=0,jobReads=1"
        expectation(for: NSPredicate(format: "value == %@", verifiedReads), evaluatedWith: recoveredCounts)
        waitForExpectations(timeout: 10)
        let unexpectedRequest = XCTNSPredicateExpectation(predicate: NSPredicate(format: "NOT (value BEGINSWITH %@)", "creates=0,links=0,"), object: recoveredCounts)
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
            assertOpenedSavedEstimate(in: app, counts: "creates=0,links=1,estimateReads=2,jobReads=2")
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
        expectation(for: NSPredicate(format: "value == %@", "creates=1,links=0,estimateReads=1,jobReads=1"), evaluatedWith: counts)
        waitForExpectations(timeout: 10)
        XCTAssertFalse(app.textFields["Estimate title"].isEnabled, "The known saved estimate stays locked")
        retry.tap()
        let firstLink = NSPredicate(format: "value == %@", "creates=1,links=1,estimateReads=2,jobReads=2")
        expectation(for: firstLink, evaluatedWith: counts)
        waitForExpectations(timeout: 10)
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: retry)
        waitForExpectations(timeout: 10)
        retry.tap()
        assertOpenedSavedEstimate(in: app, counts: "creates=1,links=2,estimateReads=3,jobReads=3")
    }

    func testCatalogTapActuallyAddsItemWithKeyboardOpen() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "new-estimate",
            "--paper-preview-estimate-create-recovery", "--paper-preview-catalog-pages", "--paper-preview-estimate-recovery-trace",
            "--paper-preview-estimate-wait-presentation", "--paper-preview-estimate-window-tap-probe"]
        app.launch()
        XCTAssertTrue(app.staticTexts["estimate-presentation-ready"].waitForExistence(timeout: 30), "The editor presentation must finish before tapping")
        let add = app.buttons["estimate-add-item"]
        XCTAssertTrue(add.waitForExistence(timeout: 30)); add.tap()
        let search = app.textFields["price-book-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("Replace capacitor")
        let item = app.buttons["price-book-item-00000000-0000-4000-8000-000000009201"]
        XCTAssertTrue(item.waitForExistence(timeout: 15)); XCTAssertTrue(item.isHittable); item.tap()
        let added = app.buttons.matching(identifier: "price-book-item-00000000-0000-4000-8000-000000009201")
            .matching(NSPredicate(format: "value == %@", "1 in draft")).firstMatch
        let found = added.waitForExistence(timeout: 5)
        let trace = app.staticTexts["estimate-picker-event-trace"].value as? String ?? "missing"
        print("PICKER_ADD_TRACE: \(trace)")
        XCTAssertTrue(found, "The selected item must enter the draft. Trace: \(trace)")
        app.buttons["price-book-done"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Replace capacitor")).firstMatch.waitForExistence(timeout: 10))
    }

    func testPickerCenterTapWithKeyboard() { checkPickerTap(position: 0.5, hideKeyboard: false) }
    func testPickerCenterTapWithoutKeyboard() { checkPickerTap(position: 0.5, hideKeyboard: true) }
    func testPickerTextTapWithKeyboard() { checkPickerTap(position: 0.25, hideKeyboard: false) }
    func testPickerPlusTapWithKeyboard() { checkPickerTap(position: 0.9, hideKeyboard: false) }
    func testPickerTextTapWithoutKeyboard() { checkPickerTap(position: 0.25, hideKeyboard: true) }
    func testPickerPlusTapWithoutKeyboard() { checkPickerTap(position: 0.9, hideKeyboard: true) }

    private func checkPickerTap(position: CGFloat, hideKeyboard: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "new-estimate",
            "--paper-preview-estimate-create-recovery", "--paper-preview-catalog-pages", "--paper-preview-estimate-recovery-trace",
            "--paper-preview-estimate-wait-presentation", "--paper-preview-estimate-trace-taps"]
        app.launch()
        XCTAssertTrue(app.staticTexts["estimate-presentation-ready"].waitForExistence(timeout: 30))
        let open = app.buttons["estimate-add-item"]
        XCTAssertTrue(open.waitForExistence(timeout: 10)); open.tap()
        let search = app.textFields["price-book-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("Replace capacitor")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        if hideKeyboard {
            app.buttons["estimate-picker-hide-keyboard"].tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 10))
        }
        let item = app.buttons["price-book-item-00000000-0000-4000-8000-000000009201"]
        XCTAssertTrue(item.waitForExistence(timeout: 15)); XCTAssertTrue(item.isHittable)
        let frame = item.frame
        let point = CGPoint(x: frame.minX + frame.width * position, y: frame.midY)
        print("PICKER_PROBE_GEOMETRY: frame=\(frame) point=\(point) keyboard=\(app.keyboards.firstMatch.exists)")
        XCTAssertTrue(app.frame.contains(point))
        item.coordinate(withNormalizedOffset: CGVector(dx: position, dy: 0.5)).tap()
        let added = app.buttons.matching(identifier: "price-book-item-00000000-0000-4000-8000-000000009201")
            .matching(NSPredicate(format: "value == %@", "1 in draft")).firstMatch
        let found = added.waitForExistence(timeout: 5)
        let trace = app.staticTexts["estimate-picker-event-trace"].value as? String ?? "missing"
        print("PICKER_PROBE_TRACE: \(trace)")
        XCTAssertTrue(found, "Exactly one item should be added. Trace: \(trace)")
    }

    func testDismissalDuringInitialEstimateReadDoesNotLink() {
        checkDismissalDuringInitialRead(holdJob: false)
    }

    func testDismissalDuringInitialJobReadDoesNotLink() {
        checkDismissalDuringInitialRead(holdJob: true)
    }

    private func checkDismissalDuringInitialRead(holdJob: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication()
        let flag = holdJob ? "--paper-preview-estimate-hold-initial-job" : "--paper-preview-estimate-hold-initial-estimate"
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "new-estimate",
            "--paper-preview-estimate-create-recovery", "--paper-preview-catalog-pages", flag,
            "--paper-preview-estimate-recovery-trace", "--paper-preview-estimate-dismiss-held",
            "--commercial-draft-test-id", UUID().uuidString]
        app.launch(); addSampleItem(in: app)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Replace capacitor")).firstMatch.waitForExistence(timeout: 10))
        let save = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Save estimate")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10)); XCTAssertTrue(save.isEnabled); save.tap()
        let hold = app.staticTexts["estimate-recovery-hold-state"]
        XCTAssertTrue(hold.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "value == %@", "waiting"), evaluatedWith: hold)
        waitForExpectations(timeout: 15)
        let trace = app.staticTexts["estimate-recovery-event-trace"]
        XCTAssertTrue((trace.value as? String ?? "").contains(holdJob ? "hold-initial-job" : "hold-initial-estimate"))
        let close = app.buttons["estimate-dismiss-while-held"]
        XCTAssertTrue(close.waitForExistence(timeout: 10)); close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 10))
        let delay = expectation(description: "Allow held response delivery after dismissal")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { delay.fulfill() }
        waitForExpectations(timeout: 5)
        app.terminate(); app.launch()
        let evidence = app.staticTexts["estimate-dismissal-evidence"]
        XCTAssertTrue(evidence.waitForExistence(timeout: 15))
        XCTAssertEqual(evidence.value as? String, "released=true,linked=false")
    }

    func testInitialLocalSaveFailureKeepsDraftAndDoesNotLink() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "new-estimate",
            "--paper-preview-estimate-create-recovery", "--paper-preview-catalog-pages",
            "--paper-preview-estimate-initial-save-fails", "--paper-preview-estimate-recovery-trace",
            "--commercial-draft-test-id", UUID().uuidString]
        app.launch(); addSampleItem(in: app)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Replace capacitor")).firstMatch.waitForExistence(timeout: 10))
        let save = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Save estimate")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10)); XCTAssertTrue(save.isEnabled); save.tap()
        let trace = app.staticTexts["estimate-recovery-event-trace"]
        XCTAssertTrue(trace.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "value CONTAINS %@", "initial-local-save-failed"), evaluatedWith: trace)
        waitForExpectations(timeout: 10)
        let counts = app.staticTexts["estimate-recovery-request-counts"]
        XCTAssertTrue((counts.value as? String ?? "").hasPrefix("creates=1,links=0,"))
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "previous save could not be confirmed")).firstMatch.waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Replace capacitor")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Retry adding to job"].exists)
    }

    func testAuthorityChangeDuringInitialEstimateReadDoesNotLink() {
        checkAuthorityChangeDuringInitialRead(holdJob: false)
    }

    func testAuthorityChangeDuringInitialJobReadDoesNotLink() {
        checkAuthorityChangeDuringInitialRead(holdJob: true)
    }

    private func checkAuthorityChangeDuringInitialRead(holdJob: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication()
        let holdFlag = holdJob ? "--paper-preview-estimate-hold-initial-job" : "--paper-preview-estimate-hold-initial-estimate"
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "new-estimate",
            "--paper-preview-estimate-create-recovery", "--paper-preview-catalog-pages", holdFlag,
            "--paper-preview-estimate-recovery-trace", "--commercial-draft-test-id", UUID().uuidString]
        app.launch(); addSampleItem(in: app)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Replace capacitor")).firstMatch.waitForExistence(timeout: 10))
        let save = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Save estimate")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10)); XCTAssertTrue(save.isEnabled); save.tap()
        let hold = app.staticTexts["estimate-recovery-hold-state"]
        XCTAssertTrue(hold.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "value == %@", "waiting"), evaluatedWith: hold)
        waitForExpectations(timeout: 15)
        let trace = app.staticTexts["estimate-recovery-event-trace"]
        let required = holdJob ? "hold-initial-job" : "hold-initial-estimate"
        XCTAssertTrue((trace.value as? String ?? "").contains(required))
        app.buttons["estimate-release-initial-read"].tap()
        let delivered = holdJob ? "initial-job-delivered" : "initial-estimate-delivered"
        expectation(for: NSPredicate(format: "value CONTAINS %@ OR value CONTAINS %@", delivered, "initial-prelink-failed"), evaluatedWith: trace)
        waitForExpectations(timeout: 15)
        XCTAssertTrue((trace.value as? String ?? "").contains("held-released"))
        let counts = app.staticTexts["estimate-recovery-request-counts"]
        XCTAssertTrue((counts.value as? String ?? "").hasPrefix("creates=1,links=0,"))
    }

    func testDeniedInitialEstimateReadDoesNotLinkOrLoseDraft() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "new-estimate",
            "--paper-preview-estimate-create-recovery", "--paper-preview-catalog-pages",
            "--paper-preview-estimate-recovery-deny-saved-read", "--paper-preview-estimate-recovery-delay-initial-link",
            "--paper-preview-estimate-recovery-trace", "--commercial-draft-test-id", UUID().uuidString]
        app.launch(); addSampleItem(in: app)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Replace capacitor")).firstMatch.waitForExistence(timeout: 10))
        let save = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Save estimate")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10)); XCTAssertTrue(save.isEnabled); save.tap()
        let trace = app.staticTexts["estimate-recovery-event-trace"]
        XCTAssertTrue(trace.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "value CONTAINS %@", "initial-link-resumed"), evaluatedWith: trace)
        waitForExpectations(timeout: 15)
        expectation(for: NSPredicate(format: "value CONTAINS %@", "initial-prelink-failed"), evaluatedWith: trace)
        waitForExpectations(timeout: 15)
        let counts = app.staticTexts["estimate-recovery-request-counts"]
        XCTAssertTrue(counts.waitForExistence(timeout: 10))
        XCTAssertTrue((counts.value as? String ?? "").hasPrefix("creates=1,links=0,"))
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "draft stays on this phone")).firstMatch.waitForExistence(timeout: 20))
    }

    func testChangedEstimateBeforeInitialLinkRequiresReview() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "new-estimate",
            "--paper-preview-estimate-create-recovery", "--paper-preview-catalog-pages",
            "--paper-preview-estimate-recovery-changed", "--paper-preview-estimate-recovery-delay-initial-link",
            "--paper-preview-estimate-recovery-trace"]
        app.launch(); addSampleItem(in: app)
        let addedLine = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Replace capacitor")).firstMatch
        XCTAssertTrue(addedLine.waitForExistence(timeout: 10), "The catalog item must be added before testing initial link")
        let save = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Save estimate")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        XCTAssertTrue(save.isEnabled, "Save must be available after adding an item")
        save.tap()
        let trace = app.staticTexts["estimate-recovery-event-trace"]
        XCTAssertTrue(trace.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "value CONTAINS %@", "initial-link-resumed"), evaluatedWith: trace)
        waitForExpectations(timeout: 15)
        let review = app.buttons["Review saved estimate"]
        XCTAssertTrue(review.waitForExistence(timeout: 10))
        let counts = app.staticTexts["estimate-recovery-request-counts"]
        XCTAssertTrue(counts.waitForExistence(timeout: 10))
        XCTAssertTrue((counts.value as? String ?? "").hasPrefix("creates=1,links=0,"))
        XCTAssertTrue((trace.value as? String ?? "").contains("verify-saved,job,estimate"))
    }

    func testAuthorityRefreshRejectsChangedEstimateBeforeLink() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "new-estimate",
                               "--paper-preview-estimate-create-recovery", "--paper-preview-estimate-create-hold",
                               "--paper-preview-estimate-recovery-changed", "--paper-preview-catalog-pages",
                               "--paper-preview-estimate-recovery-toggle-job", "--paper-preview-estimate-recovery-delay-release"]
        app.launch()
        addSampleItem(in: app)
        let save = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Save estimate")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        save.tap()
        let counts = app.staticTexts["estimate-recovery-request-counts"]
        XCTAssertTrue(counts.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "value == %@", "creates=1,links=0,estimateReads=0,jobReads=0"), evaluatedWith: counts)
        waitForExpectations(timeout: 10)
        let hold = app.staticTexts["estimate-recovery-hold-state"]
        XCTAssertTrue(hold.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "value == %@", "waiting"), evaluatedWith: hold)
        waitForExpectations(timeout: 10)
        app.buttons["Revalidate sample"].tap()
        let trace = app.staticTexts["estimate-recovery-event-trace"]
        XCTAssertTrue(trace.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "value CONTAINS %@", "verify-new,job"), evaluatedWith: trace)
        waitForExpectations(timeout: 10)
        expectation(for: NSPredicate(format: "value == %@", "idle"), evaluatedWith: hold)
        waitForExpectations(timeout: 10)
        let review = app.buttons["Review saved estimate"]
        XCTAssertTrue(review.waitForExistence(timeout: 6))
        print("SAMPLE_RECOVERY_TRACE: \(app.staticTexts["estimate-recovery-event-trace"].value ?? "missing")")
        expectation(for: NSPredicate(format: "value == %@", "creates=1,links=0,estimateReads=1,jobReads=2"), evaluatedWith: counts)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(app.staticTexts["The saved estimate changed"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Retry adding to job"].exists)
        review.tap()
        XCTAssertTrue(app.staticTexts["Changed sample estimate"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Check whether this estimate is linked to the job before continuing."].exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(review.waitForExistence(timeout: 10))
        XCTAssertEqual(counts.value as? String, "creates=1,links=0,estimateReads=1,jobReads=2")
        app.buttons["estimate-recovery-toggle-job"].tap()
        XCTAssertTrue(review.waitForNonExistence(timeout: 15))
        XCTAssertFalse(app.buttons["Retry adding to job"].exists)
    }

    func testReviewedChangedEstimateRequiresExplicitRetryBeforeLink() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "new-estimate",
            "--paper-preview-estimate-create-recovery", "--paper-preview-estimate-create-hold",
            "--paper-preview-estimate-recovery-changed", "--paper-preview-estimate-recovery-link-success",
            "--paper-preview-catalog-pages", "--commercial-draft-test-id", UUID().uuidString]
        app.launch(); addSampleItem(in: app)
        let save = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Save estimate")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10)); save.tap()
        let counts = app.staticTexts["estimate-recovery-request-counts"]
        XCTAssertTrue(counts.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "value == %@", "creates=1,links=0,estimateReads=0,jobReads=0"), evaluatedWith: counts)
        waitForExpectations(timeout: 10)
        let hold = app.staticTexts["estimate-recovery-hold-state"]
        XCTAssertTrue(hold.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "value == %@", "waiting"), evaluatedWith: hold)
        waitForExpectations(timeout: 10)
        app.buttons["Revalidate sample"].tap()
        let review = app.buttons["Review saved estimate"]
        XCTAssertTrue(review.waitForExistence(timeout: 15)); review.tap()
        XCTAssertTrue(app.staticTexts["Changed sample estimate"].waitForExistence(timeout: 10))
        let use = app.buttons["Use this saved estimate"]
        XCTAssertTrue(use.waitForExistence(timeout: 10)); use.tap()
        let confirm = app.buttons["Use saved estimate"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10)); confirm.tap()
        let retry = app.buttons["Retry adding to job"]
        XCTAssertTrue(retry.waitForExistence(timeout: 15))
        let before = counts.value as? String ?? ""
        XCTAssertTrue(before.hasPrefix("creates=1,links=0,estimateReads="))
        XCTAssertTrue((app.staticTexts["estimate-recovery-event-trace"].value as? String ?? "").contains("verify-saved,job,estimate"))
        retry.tap()
        let detail = app.staticTexts["estimate-recovery-detail-counts"]
        XCTAssertTrue(detail.waitForExistence(timeout: 10))
        let parts = (detail.value as? String ?? "").split(separator: ",").compactMap { Int($0.split(separator: "=").last ?? "") }
        XCTAssertEqual(parts.count, 4)
        XCTAssertEqual(parts[0], 1); XCTAssertEqual(parts[1], 1)
        XCTAssertGreaterThanOrEqual(parts[2], 2); XCTAssertGreaterThanOrEqual(parts[3], 2)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "EST-8901")).firstMatch.waitForExistence(timeout: 10))
    }

    func testChangedEstimateSaveFailurePreservesOriginalDraft() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "new-estimate",
            "--paper-preview-estimate-create-recovery", "--paper-preview-estimate-create-hold",
            "--paper-preview-estimate-recovery-changed", "--paper-preview-estimate-recovery-review-save-fails",
            "--paper-preview-catalog-pages", "--commercial-draft-test-id", UUID().uuidString]
        app.launch(); addSampleItem(in: app)
        let save = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Save estimate")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10)); save.tap()
        let counts = app.staticTexts["estimate-recovery-request-counts"]
        XCTAssertTrue(counts.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "value == %@", "creates=1,links=0,estimateReads=0,jobReads=0"), evaluatedWith: counts)
        waitForExpectations(timeout: 10)
        let hold = app.staticTexts["estimate-recovery-hold-state"]
        XCTAssertTrue(hold.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "value == %@", "waiting"), evaluatedWith: hold)
        waitForExpectations(timeout: 10)
        app.buttons["Revalidate sample"].tap()
        let review = app.buttons["Review saved estimate"]
        XCTAssertTrue(review.waitForExistence(timeout: 15)); review.tap()
        XCTAssertTrue(app.buttons["Use this saved estimate"].waitForExistence(timeout: 10))
        app.buttons["Use this saved estimate"].tap()
        XCTAssertTrue(app.buttons["Use saved estimate"].waitForExistence(timeout: 10))
        app.buttons["Use saved estimate"].tap()
        XCTAssertTrue(app.staticTexts["The reviewed estimate could not be saved on this phone. Your original draft is still here."].waitForExistence(timeout: 10))
        XCTAssertTrue((counts.value as? String ?? "").contains("links=0"))
        app.terminate(); app.launch()
        XCTAssertTrue(review.waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["Retry adding to job"].exists)
    }

    func testChangedEstimateCanBeReviewedAgainWithoutLinking() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "new-estimate",
            "--paper-preview-estimate-create-recovery", "--paper-preview-estimate-create-hold",
            "--paper-preview-estimate-recovery-changed", "--paper-preview-estimate-recovery-change-again",
            "--paper-preview-estimate-recovery-link-success", "--paper-preview-catalog-pages",
            "--commercial-draft-test-id", UUID().uuidString]
        app.launch(); addSampleItem(in: app)
        let save = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Save estimate")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10)); save.tap()
        let counts = app.staticTexts["estimate-recovery-request-counts"]
        XCTAssertTrue(counts.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "value == %@", "creates=1,links=0,estimateReads=0,jobReads=0"), evaluatedWith: counts)
        waitForExpectations(timeout: 10)
        let hold = app.staticTexts["estimate-recovery-hold-state"]
        XCTAssertTrue(hold.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "value == %@", "waiting"), evaluatedWith: hold)
        waitForExpectations(timeout: 10)
        app.buttons["Revalidate sample"].tap()
        let review = app.buttons["Review saved estimate"]
        XCTAssertTrue(review.waitForExistence(timeout: 15)); review.tap()
        XCTAssertTrue(app.staticTexts["Changed sample estimate"].waitForExistence(timeout: 10))
        app.buttons["Use this saved estimate"].tap()
        XCTAssertTrue(app.buttons["Use saved estimate"].waitForExistence(timeout: 10))
        app.buttons["Use saved estimate"].tap()
        let retry = app.buttons["Retry adding to job"]
        XCTAssertTrue(retry.waitForExistence(timeout: 15))
        app.buttons["estimate-recovery-change-again"].tap()
        retry.tap()
        XCTAssertTrue(review.waitForExistence(timeout: 15))
        XCTAssertTrue((counts.value as? String ?? "").contains("links=0"))
        review.tap()
        XCTAssertTrue(app.staticTexts["Changed again sample estimate"].waitForExistence(timeout: 10))
        app.buttons["Use this saved estimate"].tap()
        XCTAssertTrue(app.buttons["Use saved estimate"].waitForExistence(timeout: 10))
        app.buttons["Use saved estimate"].tap()
        XCTAssertTrue(retry.waitForExistence(timeout: 15))
        XCTAssertTrue((counts.value as? String ?? "").hasPrefix("creates=1,links=0,"))
        retry.tap()
        let detail = app.staticTexts["estimate-recovery-detail-counts"]
        XCTAssertTrue(detail.waitForExistence(timeout: 10))
        let parts = (detail.value as? String ?? "").split(separator: ",").compactMap { Int($0.split(separator: "=").last ?? "") }
        XCTAssertEqual(parts.count, 4)
        XCTAssertEqual(parts[0], 1); XCTAssertEqual(parts[1], 1)
        XCTAssertGreaterThanOrEqual(parts[2], 3); XCTAssertGreaterThanOrEqual(parts[3], 3)
    }

    func testChangedEstimateReviewClosesWhenJobAccessIsRevoked() {
        checkChangedReviewRetiresOnAuthorityChange(offline: false)
    }

    func testChangedEstimateReviewClosesWhenOffline() {
        checkChangedReviewRetiresOnAuthorityChange(offline: true)
    }

    private func checkChangedReviewRetiresOnAuthorityChange(offline: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication()
        let scenario = offline ? "--paper-preview-estimate-recovery-review-offline" : "--paper-preview-estimate-recovery-review-scope"
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "new-estimate",
            "--paper-preview-estimate-create-recovery", "--paper-preview-estimate-create-hold",
            "--paper-preview-estimate-recovery-changed", scenario, "--paper-preview-catalog-pages",
            "--commercial-draft-test-id", UUID().uuidString]
        app.launch(); addSampleItem(in: app)
        let save = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Save estimate")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10)); save.tap()
        let hold = app.staticTexts["estimate-recovery-hold-state"]
        XCTAssertTrue(hold.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "value == %@", "waiting"), evaluatedWith: hold)
        waitForExpectations(timeout: 10)
        app.buttons["Revalidate sample"].tap()
        let review = app.buttons["Review saved estimate"]
        XCTAssertTrue(review.waitForExistence(timeout: 15)); review.tap()
        XCTAssertTrue(app.buttons["Use this saved estimate"].waitForExistence(timeout: 10))
        app.buttons[offline ? "Disconnect sample" : "Revoke sample job"].tap()
        XCTAssertTrue(app.buttons["Use this saved estimate"].waitForNonExistence(timeout: 15))
        XCTAssertFalse(app.buttons["Retry adding to job"].exists)
        let counts = app.staticTexts["estimate-recovery-request-counts"]
        XCTAssertTrue(counts.waitForExistence(timeout: 10))
        XCTAssertTrue((counts.value as? String ?? "").contains("links=0"))
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
                               "--paper-preview-estimate-recovery-change-on-command", "--paper-preview-estimate-recovery-change-again",
                               "--paper-preview-estimate-recovery-trace"]
        app.launch()
        addSampleItem(in: app)
        let save = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Save estimate")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        save.tap()
        let retry = app.buttons["Retry adding to job"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: retry)
        waitForExpectations(timeout: 10)
        let trace = app.staticTexts["estimate-recovery-event-trace"]
        XCTAssertTrue(trace.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "value CONTAINS %@", "verify-saved"), evaluatedWith: trace)
        waitForExpectations(timeout: 10)
        app.buttons["estimate-recovery-change-again"].tap()
        retry.tap()
        let counts = app.staticTexts["estimate-recovery-request-counts"]
        let review = app.buttons["Review saved estimate"]
        XCTAssertTrue(review.waitForExistence(timeout: 15))
        XCTAssertTrue((counts.value as? String ?? "").hasPrefix("creates=1,links=1,"))
        review.tap()
        XCTAssertTrue(app.staticTexts["Changed again sample estimate"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Use this saved estimate"].exists)
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
                               "--paper-preview-estimate-create-recovery", "--paper-preview-catalog-pages",
                               "--paper-preview-estimate-recovery-trace"]
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
        let before = (counts.value as? String ?? "").split(separator: ",").compactMap { Int($0.split(separator: "=").last ?? "") }
        XCTAssertEqual(before.count, 4)
        XCTAssertEqual(before[0], 1); XCTAssertEqual(before[1], 1)
        let trace = app.staticTexts["estimate-recovery-event-trace"]
        XCTAssertTrue(trace.waitForExistence(timeout: 10))
        print("SAMPLE_NORMAL_TRACE_BEFORE: \(trace.value ?? "missing")")
        retry.tap()
        let detail = app.staticTexts["estimate-recovery-detail-counts"]
        XCTAssertTrue(detail.waitForExistence(timeout: 10))
        let after = (detail.value as? String ?? "").split(separator: ",").compactMap { Int($0.split(separator: "=").last ?? "") }
        XCTAssertEqual(after.count, 4)
        XCTAssertEqual(after[0], 1); XCTAssertEqual(after[1], 2)
        XCTAssertGreaterThan(after[2], before[2]); XCTAssertGreaterThan(after[3], before[3])
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "EST-8901")).firstMatch.waitForExistence(timeout: 10))
    }

    private func assertOpenedSavedEstimate(in app: XCUIApplication, counts expected: String) {
        let detailCounts = app.staticTexts["estimate-recovery-detail-counts"]
        XCTAssertTrue(detailCounts.waitForExistence(timeout: 10), "The saved estimate detail must open")
        XCTAssertEqual(detailCounts.value as? String, expected)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "EST-8901")).firstMatch.waitForExistence(timeout: 10))
    }
}

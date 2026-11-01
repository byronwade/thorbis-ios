import XCTest

@MainActor
/// The job's ••• door to Customer view. The header or bar door has the same name, so this picks the menu row.
func thorbisCustomerViewMenuItem(_ app: XCUIApplication) -> XCUIElement {
    app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@ AND identifier != %@ AND identifier != %@",
                                     "Customer view", "job-customer-view", "job-customer-view-bar", "job-money-customer-view")).firstMatch
}

/// The Money door into Customer view. #170 renamed it "Show customer" (identifiers unchanged); the
/// header circle has the same words, so this excludes it.
func thorbisShowCustomerDoor(_ app: XCUIApplication) -> XCUIElement {
    app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Show customer", "job-customer-view")).firstMatch
}

/// A job section in the segmented row. #163 added the balance/count to its spoken label
/// ("Money, $340.00 due"); its identifier stays "job-section-<name>".
func thorbisSection(_ app: XCUIApplication, _ name: String) -> XCUIElement {
    app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", "job-section-" + name.lowercased(), name)).firstMatch
}

/// The job has loaded with its balance. Since #189 an in-progress job's bar reads "Wrap up · N left"
/// (collecting is a wrap-up row and Money's bar), so the balance is read from the Money section,
/// whose spoken label carries it ("Money, $340.00 due"; identifier "job-section-money").
func thorbisJobBalanceLoaded(_ app: XCUIApplication, _ amount: String) -> XCUIElement {
    app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "job-section-money", amount)).firstMatch
}

/// Customer view's home: bring a document card fully above the fixed hand-back footer before tapping it.
func thorbisRevealInCustomerView(_ element: XCUIElement, in app: XCUIApplication) {
    XCTAssertTrue(element.waitForExistence(timeout: 10))
    let list = app.scrollViews["customer-job-documents-list"]
    let footer = app.buttons["Hand back to the technician"].firstMatch
    for _ in 0..<8 where !(element.isHittable && (!footer.exists || element.frame.maxY <= footer.frame.minY)) {
        list.swipeUp(velocity: .slow)
    }
}

func thorbisStableButton(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
    let query = app.buttons.matching(identifier: identifier)
    var previous: CGRect?
    let stable = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
        let matches = query.allElementsBoundByIndex.filter { $0.isHittable && $0.isEnabled }
        guard matches.count == 1 else { previous = nil; return false }
        let frame = matches[0].frame
        guard frame.width > 0, frame.height > 0, app.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) else { previous = nil; return false }
        defer { previous = frame }
        return previous == frame
    }, object: app)
    XCTAssertEqual(XCTWaiter.wait(for: [stable], timeout: 10), .completed, "One enabled, unobscured control must have stable geometry before a tap")
    let matches = query.allElementsBoundByIndex.filter { $0.isHittable && $0.isEnabled }
    XCTAssertEqual(matches.count, 1)
    return matches.first ?? query.element(boundBy: 0)
}

@MainActor
final class JobEstimateHandoffUITests: XCTestCase {
    override func tearDown() { XCUIApplication().terminate(); super.tearDown() }
    private func open(_ extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job-estimates", "--paper-preview-job-estimate-handoff", "--paper-preview-owner-auth", "approved"] + extra
        app.launch()
        return app
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = name
        shot.lifetime = .keepAlways; add(shot)
    }
    private func visible(_ app: XCUIApplication, _ element: XCUIElement) {
        for _ in 0..<8 {
            let actions = ["handoff-review-selected", "handoff-submit-approval", "handoff-continue-signatures"].flatMap {
                app.buttons.matching(identifier: $0).allElementsBoundByIndex.filter { $0.isHittable }
            }
            let bottom = actions.map { $0.frame.minY }.min() ?? app.frame.maxY - 40
            let top = app.navigationBars.allElementsBoundByIndex.filter { $0.isHittable }.map { $0.frame.maxY }.max() ?? app.frame.minY + 70
            if element.isHittable && element.frame.midY > top && element.frame.midY < bottom { return }
            if element.frame.midY <= top { app.swipeDown() } else { app.swipeUp() }
        }
        XCTFail("The intended control's tap point must be unobscured, not merely partially present")
    }
    private func waitHittable(_ element: XCUIElement, timeout: TimeInterval = 10) {
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: timeout), .completed)
    }
    private func toggleSampleControls(_ app: XCUIApplication) {
        let actions = ["Change sample workspace shortly", "End sample session shortly", "Choose sample workspace shortly", "Interrupt next membership read", "Interrupt next signature upload", "Allow sample unlock", "Refresh sample receipt"]
        let wasExpanded = app.buttons[actions[0]].exists
        let disclosure = thorbisStableButton(app, "Sample testing controls")
        // iPadOS multitasking owns the top-center point of this DEBUG disclosure.
        disclosure.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap()
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            actions.allSatisfy { app.buttons[$0].exists == !wasExpanded }
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 10), .completed, "Fixture actions must appear or fully disappear before continuing")
    }
    private func ownerExit(_ app: XCUIApplication) -> XCUIElement {
        // The DEBUG sample controls are stacked above the protected navigation stack, so they no
        // longer cover the Hand back pill when expanded; the real exit is tapped as it is.
        return thorbisStableButton(app, "customer-mode-owner-exit")
    }
    private func draw(_ app: XCUIApplication) {
        let pad = app.descendants(matching: .any)["customer-estimate-signature-pad"]
        XCTAssertTrue(pad.waitForExistence(timeout: 10)); visible(app, pad)
        pad.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).press(forDuration: 0.05, thenDragTo: pad.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.3)))
        XCTAssertEqual(pad.value as? String, "Signature entered", "Approval cannot continue unless the actual pad registered fresh ink")
    }
    private func receipt(_ app: XCUIApplication) throws -> [String: Any] {
        let query = app.descendants(matching: .any).matching(identifier: "handoff-canonical-receipt")
        XCTAssertTrue(query.element(boundBy: 0).waitForExistence(timeout: 5))
        XCTAssertEqual(query.count, 1)
        let value = try XCTUnwrap(query.element(boundBy: 0).value as? String)
        let data = try XCTUnwrap(value.data(using: .utf8))
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "Anonymized canonical approval receipt"; attachment.lifetime = .keepAlways; add(attachment)
        return result
    }
    private func selectEstimate(_ app: XCUIApplication, _ element: XCUIElement) {
        visible(app, element)
        thorbisStableButton(app, element.identifier).tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (element.value as? String)?.hasPrefix("Selected,") == true
        }, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 10), .completed, "Each real selection must stick before the next tap")
    }
    func testTwoSameTitleEstimatesApproveIndependentlyInOneProtectedHandoff() throws {
        let app = open(["--paper-preview-handoff-duplicate-titles", "--paper-preview-handoff-hide-controls"])
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 10)); thorbisShowCustomerDoor(app).tap()
        let first = app.buttons["handoff-select-00000000-0000-4000-8000-000000008101"]
        XCTAssertTrue(first.waitForExistence(timeout: 10)); selectEstimate(app, first)
        let second = app.buttons["handoff-select-00000000-0000-4000-8000-000000008102"]
        visible(app, second)
        XCTAssertLessThanOrEqual(second.frame.maxY, app.buttons["Review selected (1)"].frame.minY)
        selectEstimate(app, second)
        XCTAssertTrue(app.buttons["Review selected (2)"].waitForExistence(timeout: 5)); thorbisStableButton(app, "handoff-review-selected").tap()
        XCTAssertTrue(app.buttons["Continue to signatures"].waitForExistence(timeout: 10))
        capture(app, "Both same-title estimates reviewed by distinct reference")
        thorbisStableButton(app, "handoff-continue-signatures").tap()
        XCTAssertTrue(app.textFields["Your full name"].waitForExistence(timeout: 10))
        draw(app); thorbisStableButton(app, "handoff-submit-approval").tap()
        XCTAssertTrue(app.buttons["Next estimate"].waitForExistence(timeout: 15))
        XCTAssertFalse(thorbisShowCustomerDoor(app).isHittable)
        app.buttons["Next estimate"].tap()
        XCTAssertTrue(app.textFields["Your full name"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.descendants(matching: .any)["customer-estimate-signature-pad"].value as? String, "Signature required", "The second estimate needs fresh ink")
        capture(app, "Second estimate requires its own fresh signature")
        draw(app); thorbisStableButton(app, "handoff-submit-approval").tap()
        XCTAssertTrue(app.buttons["See approvals"].waitForExistence(timeout: 15)); app.buttons["See approvals"].tap()
        XCTAssertTrue(app.staticTexts["handoff-results-summary"].waitForExistence(timeout: 10))
        let proof = try receipt(app)
        let approvals = try XCTUnwrap(proof["approvals"] as? [[String: Any]])
        XCTAssertEqual(approvals.count, 2)
        XCTAssertEqual(Set(approvals.compactMap { $0["estimateID"] as? String }).count, 2)
        XCTAssertEqual(Set(approvals.compactMap { $0["mediaID"] as? String }).count, 2)
        XCTAssertEqual(proof["ownerAuthenticationAttempts"] as? Int, 0)
        XCTAssertFalse(thorbisShowCustomerDoor(app).isHittable)
        capture(app, "Two independent approvals before one technician handback")
        ownerExit(app).tap()
        waitHittable(thorbisShowCustomerDoor(app))
    }
    private func reachSecondSignature(_ app: XCUIApplication, optionID: String? = nil, firstPrice: String = "$190.00") {
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 10)); thorbisShowCustomerDoor(app).tap()
        let first = app.buttons["handoff-select-00000000-0000-4000-8000-000000008101"]
        XCTAssertTrue(first.waitForExistence(timeout: 10)); selectEstimate(app, first)
        if let optionID { app.buttons[optionID].tap() }
        let second = app.buttons["handoff-select-00000000-0000-4000-8000-000000008102"]
        visible(app, second); selectEstimate(app, second)
        XCTAssertTrue(app.buttons["Review selected (2)"].waitForExistence(timeout: 5)); thorbisStableButton(app, "handoff-review-selected").tap()
        guard app.buttons["Continue to signatures"].waitForExistence(timeout: 10) else {
            capture(app, "Selected review did not open — diagnostic evidence")
            _ = try? receipt(app); XCTFail("The exact selected set must open its review"); return
        }
        thorbisStableButton(app, "handoff-continue-signatures").tap()
        XCTAssertTrue(app.scrollViews["customer-estimate-presentation-00000000-0000-4000-8000-000000008101"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["Your full name"].waitForExistence(timeout: 10)); draw(app)
        XCTAssertTrue(app.buttons["Approve \(firstPrice)"].exists)
        thorbisStableButton(app, "handoff-submit-approval").tap()
        guard app.buttons["Next estimate"].waitForExistence(timeout: 15) else {
            capture(app, "First approval did not confirm — diagnostic evidence")
            _ = try? receipt(app); XCTFail("The first canonical approval must confirm before continuing"); return
        }
        app.buttons["Next estimate"].tap()
        XCTAssertTrue(app.textFields["Your full name"].waitForExistence(timeout: 10))
    }
    func testChangingThirdEstimateDoesNotStrandTheExactUnknownRetry() throws {
        let app = open(["--paper-preview-handoff-third-sent", "--paper-preview-handoff-fail-before-second", "--paper-preview-handoff-hide-controls"])
        reachSecondSignature(app); draw(app); thorbisStableButton(app, "handoff-submit-approval").tap()
        XCTAssertTrue(app.buttons["Check approval"].waitForExistence(timeout: 15))
        let before = try receipt(app)
        app.buttons["Back to selected work"].tap(); app.buttons["Back to estimates"].tap()
        let third = app.buttons["handoff-select-00000000-0000-4000-8000-000000008103"]
        for _ in 0..<8 {
            if third.isHittable && third.frame.midY < app.buttons["Review selected (2)"].frame.minY { break }
            app.swipeUp()
        }
        XCTAssertTrue(third.isHittable); selectEstimate(app, third)
        XCTAssertTrue(app.buttons["Review selected (3)"].exists)
        for _ in 0..<8 { if app.buttons["Check approval"].isHittable { break }; app.swipeDown() }
        app.buttons["Check approval"].tap()
        XCTAssertTrue(app.buttons["Retry exact approval"].waitForExistence(timeout: 10)); app.buttons["Retry exact approval"].tap()
        XCTAssertTrue(app.navigationBars["EST-8102"].waitForExistence(timeout: 10), "Retry resolves retained exact context, not the cleared current selection")
        let retry = app.buttons.matching(identifier: "Retry exact approval").allElementsBoundByIndex.filter { $0.isHittable }
        XCTAssertEqual(retry.count, 1); try XCTUnwrap(retry.first).tap()
        XCTAssertTrue(app.buttons["See approvals"].waitForExistence(timeout: 15)); app.buttons["See approvals"].tap()
        let after = try receipt(app)
        let old = try XCTUnwrap(before["approvals"] as? [[String: Any]]), new = try XCTUnwrap(after["approvals"] as? [[String: Any]])
        XCTAssertEqual(old.count, 2); XCTAssertEqual(new.count, 3)
        XCTAssertTrue(NSDictionary(dictionary: old[1]["body"] as! [String: Any]).isEqual(to: new[2]["body"] as! [String: Any]))
        XCTAssertEqual(new.filter { $0["estimateID"] as? String == "00000000-0000-4000-8000-000000008103" }.count, 0)
        XCTAssertEqual((after["registrationClientIDs"] as? [String])?.count, 2)
        capture(app, "Third selection preserves the original unknown approval retry")
    }
    func testCommitSurfaceRespondsToTapAwayFromTheTitle() {
        let app = open(["--paper-preview-handoff-hide-controls"])
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 10)); thorbisShowCustomerDoor(app).tap()
        let select = app.buttons["handoff-select-00000000-0000-4000-8000-000000008101"]
        XCTAssertTrue(select.waitForExistence(timeout: 10)); selectEstimate(app, select)
        let review = app.buttons["Review selected (1)"]
        XCTAssertTrue(review.isEnabled)
        review.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["Continue to signatures"].waitForExistence(timeout: 10), "The whole visible commit surface must respond")
    }
    private func interruptPreparation(_ label: String) throws {
        let app = open()
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 10)); thorbisShowCustomerDoor(app).tap()
        let select = app.buttons["handoff-select-00000000-0000-4000-8000-000000008101"]
        XCTAssertTrue(select.waitForExistence(timeout: 10)); selectEstimate(app, select); thorbisStableButton(app, "handoff-review-selected").tap()
        XCTAssertTrue(app.buttons["Continue to signatures"].waitForExistence(timeout: 10)); thorbisStableButton(app, "handoff-continue-signatures").tap()
        XCTAssertTrue(app.textFields["Your full name"].waitForExistence(timeout: 10)); draw(app)
        toggleSampleControls(app); app.buttons[label].tap(); toggleSampleControls(app)
        thorbisStableButton(app, "handoff-submit-approval").tap()
        XCTAssertTrue(app.buttons["Try again"].waitForExistence(timeout: 15), "A transient error before submission must recover without a staff restart")
        let before = try receipt(app)
        XCTAssertEqual((before["approvals"] as? [[String: Any]])?.count, 0)
        app.buttons["Try again"].tap()
        XCTAssertTrue(app.buttons["See approvals"].waitForExistence(timeout: 15)); app.buttons["See approvals"].tap()
        let after = try receipt(app)
        XCTAssertEqual((after["approvals"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual((after["confirmedMediaIDs"] as? [String])?.count, 1)
        XCTAssertEqual((after["registrationClientIDs"] as? [String])?.count, 1)
        if label == "Interrupt next signature upload" {
            XCTAssertEqual((before["registrationClientIDs"] as? [String])?.count, 1)
            XCTAssertEqual(before["registrationClientIDs"] as? [String], after["registrationClientIDs"] as? [String], "Interrupted PUT must resume the same registered client asset")
        }
        XCTAssertEqual(after["ownerAuthenticationAttempts"] as? Int, 0)
        capture(app, "Preparation interruption recovered inside the same protected handoff")
    }
    func testMembershipInterruptionCanRecoverBeforeSubmissionWithoutNewSignature() throws { try interruptPreparation("Interrupt next membership read") }
    func testUploadInterruptionCanRecoverWithoutReplacingTheRegisteredAsset() throws { try interruptPreparation("Interrupt next signature upload") }
    func testPushedCheckpointDenialThenAuthenticatedExitUsesTheSameProtectedOwner() throws {
        let app = open(["--paper-preview-handoff-denied-unlock"])
        reachSecondSignature(app)
        ownerExit(app).tap()
        XCTAssertTrue(app.textFields["Your full name"].exists)
        XCTAssertFalse(thorbisShowCustomerDoor(app).isHittable)
        XCTAssertEqual(try receipt(app)["ownerAuthenticationAttempts"] as? Int, 1)
        toggleSampleControls(app); app.buttons["Allow sample unlock"].tap(); toggleSampleControls(app)
        ownerExit(app).tap(); waitHittable(thorbisShowCustomerDoor(app))
        thorbisShowCustomerDoor(app).tap()
        XCTAssertTrue(app.navigationBars["Estimates"].waitForExistence(timeout: 10))
        XCTAssertEqual(try receipt(app)["ownerAuthenticationAttempts"] as? Int, 2)
        XCTAssertFalse(app.buttons["handoff-select-00000000-0000-4000-8000-000000008101"].exists)
        XCTAssertTrue(app.buttons["handoff-select-00000000-0000-4000-8000-000000008102"].exists)
        capture(app, "Authenticated checkpoint exit retires old handoff before a fresh review")
    }
    func testProductionLookTwoSignaturesAndCompletedCardsStayClearWithoutDiagnosticControls() {
        let app = open(["--paper-preview-handoff-hide-controls", "--paper-preview-handoff-duplicate-titles"])
        reachSecondSignature(app)
        let pad = app.descendants(matching: .any)["customer-estimate-signature-pad"]
        XCTAssertTrue(pad.waitForExistence(timeout: 10))
        XCTAssertEqual(pad.value as? String, "Signature required")
        capture(app, "Production layout second independent signature checkpoint")
        draw(app); thorbisStableButton(app, "handoff-submit-approval").tap()
        XCTAssertTrue(app.buttons["See approvals"].waitForExistence(timeout: 15)); app.buttons["See approvals"].tap()
        XCTAssertTrue(app.staticTexts["handoff-results-summary"].waitForExistence(timeout: 10))
        capture(app, "Production layout two completed estimates and one handback")
        ownerExit(app).tap(); waitHittable(thorbisShowCustomerDoor(app))
    }
    func testPackageChoiceKeepsItsCanonicalConsentWhileAnotherEstimateApprovesIndependently() throws {
        let app = open(["--paper-preview-handoff-options", "--paper-preview-handoff-public-patch-no-acceptance", "--paper-preview-handoff-hide-controls"])
        reachSecondSignature(app, optionID: "handoff-option-00000000-0000-4000-8000-000000008101-00000000-0000-4000-8000-000000008201", firstPrice: "$250.00")
        draw(app); thorbisStableButton(app, "handoff-submit-approval").tap()
        XCTAssertTrue(app.buttons["See approvals"].waitForExistence(timeout: 15)); app.buttons["See approvals"].tap()
        let proof = try receipt(app), approvals = try XCTUnwrap(proof["approvals"] as? [[String: Any]])
        XCTAssertEqual(approvals.count, 2)
        let option = try XCTUnwrap(approvals.first { $0["estimateID"] as? String == "00000000-0000-4000-8000-000000008101" })
        XCTAssertEqual(option["endpoint"] as? String, "/v1/public/document-actions/sample-00000000-0000-4000-8000-000000008101/approve")
        let decision = try XCTUnwrap(option["body"] as? [String: Any])
        XCTAssertEqual(decision["optionId"] as? String, "00000000-0000-4000-8000-000000008201")
        XCTAssertEqual(decision["revisionNumber"] as? Int, 1); XCTAssertEqual(decision["consent"] as? Bool, true)
        XCTAssertEqual(decision["consentVersion"] as? String, "estimate-approval-v1")
        XCTAssertEqual(decision["contentHash"] as? String, String(repeating: "a", count: 64))
        XCTAssertEqual(decision["nonce"] as? String, "sample-nonce-00000000-0000-4000-8000-000000008101")
        let reads = (proof["requests"] as? [[String: String]])?.filter { $0["method"] == "GET" && $0["path"] == "/v1/public/document-actions/sample-00000000-0000-4000-8000-000000008101" }
        XCTAssertEqual(reads?.count, 2, "Missing patch acceptance reads the same token; it must not mint a replacement")
        XCTAssertEqual((proof["confirmedMediaIDs"] as? [String])?.count, 2)
        XCTAssertTrue(app.staticTexts["$250.00"].firstMatch.exists, "Accepted package price must not revert to the $190 aggregate lines")
        capture(app, "Separate package consent and plain estimate both approved")
    }
    func testLostSecondApprovalReconcilesWithoutResendingConfirmedEstimates() throws {
        let app = open(["--paper-preview-handoff-lose-second", "--paper-preview-handoff-hide-controls"])
        reachSecondSignature(app); draw(app); thorbisStableButton(app, "handoff-submit-approval").tap()
        XCTAssertTrue(app.buttons["Check approval"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["See approvals"].exists)
        capture(app, "Lost response stays unconfirmed after first approval")
        app.buttons["Back to selected work"].tap(); app.buttons["Back to estimates"].tap()
        XCTAssertTrue(app.staticTexts["handoff-results-summary"].label.contains("1 approved · 1 needs confirmation"))
        app.buttons["Check approval"].tap()
        let resolved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "2 approved"), object: app.staticTexts["handoff-results-summary"])
        XCTAssertEqual(XCTWaiter.wait(for: [resolved], timeout: 10), .completed)
        let proof = try receipt(app)
        XCTAssertEqual((proof["approvals"] as? [[String: Any]])?.count, 2, "Read reconciliation must never resend either approval")
        XCTAssertEqual((proof["confirmedMediaIDs"] as? [String])?.count, 2)
        XCTAssertEqual(proof["ownerAuthenticationAttempts"] as? Int, 0)
        capture(app, "Both approvals reconciled with exactly two original commands")
    }
    func testUnconfirmedRetryRetainsExactSignatureAcrossBackAndDeniedOwnerUnlock() throws {
        let app = open(["--paper-preview-handoff-fail-before-second", "--paper-preview-handoff-denied-unlock", "--paper-preview-handoff-hide-controls"])
        reachSecondSignature(app); draw(app); thorbisStableButton(app, "handoff-submit-approval").tap()
        XCTAssertTrue(app.buttons["Check approval"].waitForExistence(timeout: 15))
        let before = try receipt(app)
        ownerExit(app).tap()
        XCTAssertTrue(app.buttons["Check approval"].exists)
        XCTAssertEqual(try receipt(app)["ownerAuthenticationAttempts"] as? Int, 1, "A visible protected child exit must invoke the real owner boundary, not no-op")
        XCTAssertFalse(thorbisShowCustomerDoor(app).isHittable)
        app.buttons["Back to selected work"].tap()
        XCTAssertFalse(app.buttons["Continue to signatures"].exists, "There is no new signature checkpoint when every selected item is confirmed or unconfirmed")
        app.buttons["Back to estimates"].tap(); app.buttons["Check approval"].tap()
        XCTAssertTrue(app.buttons["Retry exact approval"].waitForExistence(timeout: 10)); app.buttons["Retry exact approval"].tap()
        let retry = app.buttons.matching(identifier: "Retry exact approval").allElementsBoundByIndex.first { $0.isHittable }
        try XCTUnwrap(retry).tap()
        XCTAssertTrue(app.buttons["See approvals"].waitForExistence(timeout: 15)); app.buttons["See approvals"].tap()
        let after = try receipt(app)
        let old = try XCTUnwrap(before["approvals"] as? [[String: Any]]), new = try XCTUnwrap(after["approvals"] as? [[String: Any]])
        XCTAssertEqual(old.count, 2); XCTAssertEqual(new.count, 3)
        XCTAssertEqual(new.filter { $0["estimateID"] as? String == "00000000-0000-4000-8000-000000008101" }.count, 1)
        XCTAssertTrue(NSDictionary(dictionary: old[1]["body"] as! [String: Any]).isEqual(to: new[2]["body"] as! [String: Any]))
        XCTAssertEqual((after["confirmedMediaIDs"] as? [String])?.count, 2, "Retry must not upload replacement ink")
        capture(app, "Only unconfirmed estimate retried with identical signature payload")
    }
    func testLargestTextDarkModeKeepsBothEstimatesAndProtectedNavigationReachable() {
        let app = open(["--paper-preview-handoff-hide-controls", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-thorbis.appearance", "dark"])
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 10)); thorbisShowCustomerDoor(app).tap()
        XCTAssertTrue(app.navigationBars["Estimates"].waitForExistence(timeout: 10))
        _ = ownerExit(app)
        capture(app, "Largest text dark estimate overview top")
        let first = app.buttons["handoff-select-00000000-0000-4000-8000-000000008101"]
        visible(app, first); selectEstimate(app, first)
        let second = app.buttons["handoff-select-00000000-0000-4000-8000-000000008102"]
        visible(app, second); selectEstimate(app, second)
        XCTAssertTrue(app.buttons["Review selected (2)"].waitForExistence(timeout: 5))
        capture(app, "Largest text dark second estimate and review action")
        thorbisStableButton(app, "handoff-review-selected").tap()
        XCTAssertTrue(app.buttons["Continue to signatures"].waitForExistence(timeout: 10)); thorbisStableButton(app, "handoff-continue-signatures").tap()
        XCTAssertTrue(app.textFields["Your full name"].waitForExistence(timeout: 10))
        _ = ownerExit(app)
        capture(app, "Largest text dark required signature and protected exit")
        let back = app.buttons.matching(identifier: "Back").allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(back); back?.tap()
        XCTAssertTrue(app.buttons["Continue to signatures"].waitForExistence(timeout: 10))
        ownerExit(app).tap()
        waitHittable(thorbisShowCustomerDoor(app))
    }
    func testSelectedReviewShowsCanonicalDiscountBreakdown() {
        let app = open(["--paper-preview-handoff-discount", "--paper-preview-handoff-hide-controls"])
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 10)); thorbisShowCustomerDoor(app).tap()
        let select = app.buttons["handoff-select-00000000-0000-4000-8000-000000008101"]
        XCTAssertTrue(select.waitForExistence(timeout: 10)); selectEstimate(app, select); thorbisStableButton(app, "handoff-review-selected").tap()
        XCTAssertTrue(app.buttons["Continue to signatures"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Discounts and credits"].exists)
        XCTAssertTrue(app.staticTexts["-$30.00"].firstMatch.exists)
        capture(app, "Selected estimate preserves canonical discount and total")
    }
    func testApprovedSameTitleEstimateStaysVisibleBesideSentZeroWithoutReapproval() {
        let app = open(["--paper-preview-handoff-duplicate-titles", "--paper-preview-handoff-mixed", "--paper-preview-handoff-hide-controls"])
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 10)); thorbisShowCustomerDoor(app).tap()
        let select = app.buttons["handoff-select-00000000-0000-4000-8000-000000008102"]
        XCTAssertTrue(select.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["handoff-select-00000000-0000-4000-8000-000000008101"].exists)
        XCTAssertTrue(app.staticTexts["$190.00"].firstMatch.exists); XCTAssertTrue(app.staticTexts["$0.00"].firstMatch.exists)
        capture(app, "Same-title approved and zero-dollar sent estimates together")
        selectEstimate(app, select); thorbisStableButton(app, "handoff-review-selected").tap()
        XCTAssertTrue(app.buttons["Continue to signatures"].waitForExistence(timeout: 10)); thorbisStableButton(app, "handoff-continue-signatures").tap()
        XCTAssertTrue(app.textFields["Your full name"].waitForExistence(timeout: 10)); draw(app)
        thorbisStableButton(app, "handoff-submit-approval").tap()
        XCTAssertTrue(app.buttons["See approvals"].waitForExistence(timeout: 15)); app.buttons["See approvals"].tap()
        XCTAssertTrue(app.staticTexts["handoff-results-summary"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["handoff-results-summary"].label.contains("1 approved"))
    }
    func testActualSignedOutBranchAndDeniedUnlockKeepProtectedOwner() {
        let app = open(["--paper-preview-handoff-denied-unlock"])
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 10)); thorbisShowCustomerDoor(app).tap()
        XCTAssertTrue(app.navigationBars["Estimates"].waitForExistence(timeout: 10))
        toggleSampleControls(app); app.buttons["End sample session shortly"].tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "signedOut"), object: app.staticTexts["handoff-sample-session"])
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 12), .completed)
        XCTAssertTrue(app.navigationBars["Estimates"].exists)
        XCTAssertFalse(app.staticTexts["Welcome back"].isHittable)
        ownerExit(app).tap()
        XCTAssertTrue(app.navigationBars["Estimates"].exists, "Denied owner authentication must never reveal login or staff content")
        XCTAssertFalse(app.staticTexts["Welcome back"].isHittable)
        capture(app, "Actual signed-out branch stays protected after denied owner authentication")
        app.buttons["Allow sample unlock"].tap(); ownerExit(app).tap()
        waitHittable(app.staticTexts["Welcome back"])
    }
    func testActualWorkspaceSelectionBranchKeepsProtectedOwner() {
        let app = open()
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 10)); thorbisShowCustomerDoor(app).tap()
        XCTAssertTrue(app.navigationBars["Estimates"].waitForExistence(timeout: 10))
        toggleSampleControls(app); app.buttons["Choose sample workspace shortly"].tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "choosingWorkspace"), object: app.staticTexts["handoff-sample-session"])
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 12), .completed)
        XCTAssertTrue(app.navigationBars["Estimates"].exists)
        XCTAssertFalse(app.navigationBars["Choose company"].isHittable)
        XCTAssertFalse(app.buttons["handoff-select-00000000-0000-4000-8000-000000008101"].exists)
        capture(app, "Actual workspace-selection branch stays protected until owner authentication")
        ownerExit(app).tap()
        waitHittable(app.navigationBars["Choose company"])
    }
    func testActualWorkspaceBranchRetirementKeepsProtectedOwner() {
        let app = open()
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 10)); thorbisShowCustomerDoor(app).tap()
        XCTAssertTrue(app.navigationBars["Estimates"].waitForExistence(timeout: 10))
        toggleSampleControls(app)
        app.buttons["Change sample workspace shortly"].tap()
        let state = app.staticTexts["handoff-sample-session"]
        let switched = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "00000000-0000-4000-8000-000000000003"), object: state)
        XCTAssertEqual(XCTWaiter.wait(for: [switched], timeout: 12), .completed, "The actual App generation replacement must retain the protected owner")
        XCTAssertFalse(app.buttons["handoff-select-00000000-0000-4000-8000-000000008101"].exists)
        XCTAssertFalse(app.staticTexts["Schedule"].firstMatch.isHittable)
        capture(app, "Actual workspace replacement stays inside protected customer owner")
    }
    func testJobEstimatesRemainReadableAtLargestText() {
        let app = open(["--paper-preview-handoff-hide-controls",
                        "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let first = app.buttons["job-estimate-00000000-0000-4000-8000-000000008101"]
        let second = app.buttons["job-estimate-00000000-0000-4000-8000-000000008102"]
        XCTAssertTrue(first.waitForExistence(timeout: 30))
        XCTAssertTrue(second.exists)
        XCTAssertTrue(first.label.contains("Sample repair") && first.label.contains("$190.00") && first.label.contains("Sent"))
        XCTAssertTrue(second.label.contains("Sample additional work") && second.label.contains("$320.00") && second.label.contains("Sent"))
        XCTAssertTrue(app.buttons["Add estimate"].exists)
        let present = thorbisShowCustomerDoor(app)
        XCTAssertTrue(present.exists)
        // At accessibility sizes the section row is one pinned chooser (a40f825), not tabs.
        let tabs = app.buttons["job-section-chooser"]
        XCTAssertTrue(tabs.exists)
        XCTAssertTrue(tabs.label.contains("Money"))
        // At accessibility sizes Present scrolls with the content (a40f825) instead of pinning
        // above the bottom edge, so the card must fit between the pinned chooser and the screen's
        // bottom; while Present is still pinned below the card, it must clear that too.
        func bottom() -> CGFloat {
            present.frame.minY > tabs.frame.maxY && present.frame.minY >= first.frame.minY ? min(present.frame.minY, app.frame.maxY) : app.frame.maxY
        }
        for _ in 0..<8 {
            let frame = first.frame
            if first.isHittable && frame.minY >= tabs.frame.maxY && frame.maxY <= bottom() { break }
            let upward = frame.maxY > bottom()
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: upward ? 0.7 : 0.4))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: upward ? 0.5 : 0.6))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        XCTAssertTrue(first.isHittable, app.debugDescription)
        XCTAssertGreaterThanOrEqual(first.frame.minY, tabs.frame.maxY)
        XCTAssertLessThanOrEqual(first.frame.maxY, bottom())
        capture(app, "Job estimates at largest text")
    }

    func testAllEstimatesUseOnePrimaryEntryAndKeepAddVisible() {
        let app = open(["--paper-preview-handoff-hide-controls"])
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 30), "Existing estimates need one obvious customer presentation action")
        let present = thorbisStableButton(app, "job-customer-view-bar")
        capture(app, "Job estimates before entering customer handoff")
        XCTAssertTrue(app.buttons["Add estimate"].exists)
        present.tap()
        XCTAssertTrue(app.navigationBars["Estimates"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["handoff-select-00000000-0000-4000-8000-000000008101"].exists)
        XCTAssertTrue(app.buttons["handoff-select-00000000-0000-4000-8000-000000008102"].exists)
        let second = app.buttons["handoff-select-00000000-0000-4000-8000-000000008102"]
        XCTAssertLessThanOrEqual(second.frame.maxY, app.buttons["Review selected (0)"].frame.minY, "Both ordinary cards and prices fit above the primary action")
        let spoken = app.buttons["handoff-select-00000000-0000-4000-8000-000000008101"].value as? String
        XCTAssertTrue(spoken?.contains("Sent") == true)
        XCTAssertTrue(spoken?.contains("$190.00") == true, "Integrated selection must expose price and status to VoiceOver")
        capture(app, "All current-job estimates together")
    }
}

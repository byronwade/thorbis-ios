import XCTest

@MainActor
final class CustomerDocumentBookUITests: XCTestCase {
    func testLongEstimateDescriptionOpensReadOnlyAndReturnsToSameJobDocument() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job", "--paper-preview-working-job", "--paper-preview-job-documents", "--paper-preview-long-document-description"]
        app.launch()
        XCTAssertTrue(app.buttons["Job actions"].waitForExistence(timeout: 15))
        app.buttons["Job actions"].tap()
        thorbisCustomerViewMenuItem(app).tap()
        let estimate = app.buttons["customer-estimate-00000000-0000-4000-8000-000000002238"]
        XCTAssertTrue(estimate.waitForExistence(timeout: 10)); estimate.tap()
        let more = app.buttons["Show more"]
        XCTAssertTrue(more.waitForExistence(timeout: 10)); more.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Final detail: return the work area to its original condition.")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.textViews.firstMatch.exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Water heater add-ons"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["customer-book-review-sign"].exists)
    }

    func testDescriptionClosesOnSameOrganizationSessionReplacement() {
        assertDescriptionClosesOnAuthorityChange("--paper-preview-description-replace-session")
    }

    func testDescriptionClosesWhenEstimatePermissionIsRevokedInSameSession() {
        assertDescriptionClosesOnAuthorityChange("--paper-preview-description-revoke-permission")
    }

    func testDescriptionClosesWhenSessionAuthorityIsRevoked() {
        assertDescriptionClosesOnAuthorityChange("--paper-preview-description-expire-session")
    }

    private func assertDescriptionClosesOnAuthorityChange(_ flag: String) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job", "--paper-preview-working-job", "--paper-preview-job-documents", "--paper-preview-long-document-description", flag]
        app.launch()
        XCTAssertTrue(app.buttons["Job actions"].waitForExistence(timeout: 15)); app.buttons["Job actions"].tap()
        thorbisCustomerViewMenuItem(app).tap()
        let estimate = app.buttons["customer-estimate-00000000-0000-4000-8000-000000002238"]
        XCTAssertTrue(estimate.waitForExistence(timeout: 10)); estimate.tap()
        XCTAssertTrue(app.buttons["Show more"].waitForExistence(timeout: 5)); app.buttons["Show more"].tap()
        XCTAssertTrue(app.navigationBars["Description"].waitForExistence(timeout: 5))
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.navigationBars["Description"])
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 20), .completed)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Final detail: return the work area to its original condition.")).firstMatch.exists)
    }

    func testDescriptionClosesWhenDocumentBecomesStale() {
        assertDescriptionClosesAfterChange("--paper-preview-description-stale", canReopen: false)
    }

    func testDescriptionClosesWhenSameTextBelongsToNewRevision() {
        assertDescriptionClosesAfterChange("--paper-preview-description-replaced", canReopen: true)
    }

    private func assertDescriptionClosesAfterChange(_ flag: String, canReopen: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job", "--paper-preview-working-job", "--paper-preview-job-documents", "--paper-preview-long-document-description", flag]
        app.launch()
        XCTAssertTrue(app.buttons["Job actions"].waitForExistence(timeout: 15)); app.buttons["Job actions"].tap()
        thorbisCustomerViewMenuItem(app).tap()
        let estimate = app.buttons["customer-estimate-00000000-0000-4000-8000-000000002238"]
        XCTAssertTrue(estimate.waitForExistence(timeout: 10)); estimate.tap()
        XCTAssertTrue(app.buttons["Show more"].waitForExistence(timeout: 5)); app.buttons["Show more"].tap()
        XCTAssertTrue(app.navigationBars["Description"].waitForExistence(timeout: 5))
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.navigationBars["Description"])
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 20), .completed)
        if canReopen {
            XCTAssertTrue(app.buttons["Show more"].waitForExistence(timeout: 5))
        } else {
            XCTAssertFalse(app.buttons["Show more"].exists)
        }
    }

    func testEstimateReviewAndInvoiceSignatureLeaveTheSwipeSurface() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job", "--paper-preview-working-job", "--paper-preview-job-documents"]
        app.launch()
        XCTAssertTrue(app.buttons["Job actions"].waitForExistence(timeout: 15))
        app.buttons["Job actions"].tap()
        thorbisCustomerViewMenuItem(app).tap()
        let estimate = app.buttons["customer-estimate-00000000-0000-4000-8000-000000002218"]
        XCTAssertTrue(estimate.waitForExistence(timeout: 10))
        estimate.tap()
        let review = app.buttons["customer-book-review-sign"]
        XCTAssertTrue(review.waitForExistence(timeout: 10))
        thorbisStableButton(app, "customer-book-review-sign").tap()
        XCTAssertTrue(app.scrollViews["customer-estimate-presentation-00000000-0000-4000-8000-000000002218"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Approve and sign")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.collectionViews["customer-document-pages"].exists)
        XCTAssertTrue(app.buttons["Not today"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["customer-document-position"].waitForExistence(timeout: 5))
        app.buttons["Choose a job document"].tap()
        app.buttons["INV-2209"].tap()
        let sign = app.buttons["Sign for the work"]
        XCTAssertTrue(sign.waitForExistence(timeout: 10))
        sign.tap()
        XCTAssertTrue(app.textFields["Your full name"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.collectionViews["customer-document-pages"].exists)
        XCTAssertTrue(app.navigationBars["INV-2209"].exists)
    }

    func testEstimateReviewCanReturnToJobDocumentsAndChooseAnotherEstimate() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job", "--paper-preview-working-job", "--paper-preview-job-documents"]
        app.launch()
        XCTAssertTrue(app.buttons["Job actions"].waitForExistence(timeout: 15))
        app.buttons["Job actions"].tap()
        thorbisCustomerViewMenuItem(app).tap()
        let first = app.buttons["customer-estimate-00000000-0000-4000-8000-000000002218"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        first.tap()
        XCTAssertTrue(app.buttons["customer-book-review-sign"].waitForExistence(timeout: 10))
        thorbisStableButton(app, "customer-book-review-sign").tap()
        let back = app.buttons["Back to job documents"]
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        back.tap()
        XCTAssertTrue(app.staticTexts["customer-document-position"].waitForExistence(timeout: 10))
        app.buttons["Next document"].tap()
        XCTAssertTrue(app.staticTexts["Water heater add-ons"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Technician: unlock to leave customer mode"].exists)
    }

    func testApprovedEstimateReturnsToRefreshedDocumentsAndCanOpenAnotherEstimate() {
        let app = jobEstimateFixture()
        signFirstEstimate(app)
        XCTAssertTrue(app.buttons["Back to job documents"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Hand back to the technician"].exists)
        app.buttons["Back to job documents"].tap()
        XCTAssertTrue(app.staticTexts["customer-document-position"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Approved"].waitForExistence(timeout: 10))
        app.buttons["Next document"].tap()
        XCTAssertTrue(app.staticTexts["Sample additional work"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["customer-book-review-sign"].waitForExistence(timeout: 10))
    }

    func testFailedRefreshDoesNotPresentStaleEstimateAsReadyToSign() {
        let app = jobEstimateFixture(failRefresh: true)
        signFirstEstimate(app)
        XCTAssertTrue(app.buttons["Back to job documents"].waitForExistence(timeout: 10))
        app.buttons["Back to job documents"].tap()
        XCTAssertTrue(app.staticTexts["This copy needs a refresh before you can decide."].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["customer-book-review-sign"].exists)
        XCTAssertTrue(app.buttons["Refresh documents"].exists)
    }

    func testOptionApprovalWithNoReturnedEstimateDoesNotShowStaleSentStatus() {
        let app = jobEstimateFixture(failRefresh: true, withOptions: true)
        let choose = app.buttons["Choose Sample package"]
        XCTAssertTrue(choose.waitForExistence(timeout: 10)); choose.tap()
        let review = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Review Sample package")).firstMatch
        XCTAssertTrue(review.waitForExistence(timeout: 10)); review.tap()
        signFirstEstimate(app)
        XCTAssertTrue(app.buttons["Back to job documents"].waitForExistence(timeout: 10))
        app.buttons["Back to job documents"].tap()
        // The staff job screen stays in the tree under Customer view and lists the estimate as "Sent"
        // in its Money section, so the status is read from the customer's own page.
        let pages = app.collectionViews["customer-document-pages"]
        XCTAssertTrue(pages.staticTexts["Status needs refresh"].waitForExistence(timeout: 15))
        XCTAssertFalse(pages.staticTexts["Sent"].exists)
        XCTAssertFalse(app.buttons["customer-book-review-sign"].exists)
    }

    func testHandBackAfterApprovalKeepsRefreshAndOwnerExitAvailable() {
        let app = jobEstimateFixture()
        let receipt = app.descendants(matching: .any)["handoff-canonical-receipt"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 10))
        func membershipReads() -> Int {
            guard let value = receipt.value as? String,
                  let data = value.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let requests = json["requests"] as? [[String: Any]] else { return 0 }
            return requests.filter { ($0["path"] as? String)?.hasSuffix("/estimates") == true }.count
        }
        let before = membershipReads()
        XCTAssertGreaterThan(before, 0)
        signFirstEstimate(app)
        let handBack = app.buttons["Hand back to the technician"]
        XCTAssertTrue(handBack.waitForExistence(timeout: 10)); handBack.tap()
        XCTAssertTrue(app.buttons["Technician: unlock"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Go back"].exists)
        let refreshed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in membershipReads() > before }, object: receipt)
        XCTAssertEqual(XCTWaiter.wait(for: [refreshed], timeout: 15), .completed)
    }

    private func jobEstimateFixture(failRefresh: Bool = false, withOptions: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job", "--paper-preview-working-job", "--paper-preview-job-estimate-handoff"]
        app.launchArguments.append("--paper-preview-handoff-hide-controls")
        if failRefresh { app.launchArguments.append("--paper-preview-handoff-membership-fails-after-approval") }
        if withOptions { app.launchArguments.append("--paper-preview-handoff-options") }
        app.launch()
        XCTAssertTrue(app.buttons["Job actions"].waitForExistence(timeout: 15))
        app.buttons["Job actions"].tap()
        thorbisCustomerViewMenuItem(app).tap()
        let first = app.buttons["customer-estimate-00000000-0000-4000-8000-000000008101"]
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        first.tap()
        XCTAssertTrue(app.buttons["customer-book-review-sign"].waitForExistence(timeout: 15))
        thorbisStableButton(app, "customer-book-review-sign").tap()
        return app
    }

    private func signFirstEstimate(_ app: XCUIApplication) {
        // The commit reads "Approve and sign · $190.00", or for a chosen package "Approve Sample package ·
        // $250.00" / "Approve · $250.00" (#170), so it is found by identifier.
        let review = app.buttons["customer-estimate-approve"]
        XCTAssertTrue(review.waitForExistence(timeout: 10))
        review.tap()
        let pad = app.descendants(matching: .any)["customer-estimate-signature-pad"]
        XCTAssertTrue(pad.waitForExistence(timeout: 10))
        for _ in 0..<6 where !pad.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(pad.isHittable)
        pad.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).press(forDuration: 0.05, thenDragTo: pad.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.3)))
        XCTAssertEqual(pad.value as? String, "Signature entered")
        let submit = app.buttons["customer-estimate-submit-approval"]
        XCTAssertTrue(submit.waitForExistence(timeout: 10))
        submit.tap()
        XCTAssertTrue(app.staticTexts["Approved"].waitForExistence(timeout: 20))
    }

    func testInvoicePresentationCanHandBackToTechnician() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job", "--paper-preview-working-job", "--paper-preview-job-documents"]
        app.launch()
        XCTAssertTrue(app.buttons["Job actions"].waitForExistence(timeout: 15))
        app.buttons["Job actions"].tap(); thorbisCustomerViewMenuItem(app).tap()
        let estimate = app.buttons["customer-estimate-00000000-0000-4000-8000-000000002218"]
        XCTAssertTrue(estimate.waitForExistence(timeout: 10)); estimate.tap()
        XCTAssertTrue(app.buttons["Choose a job document"].waitForExistence(timeout: 10))
        app.buttons["Choose a job document"].tap(); app.buttons["INV-2209"].tap()
        let sign = app.buttons["Sign for the work"]
        XCTAssertTrue(sign.waitForExistence(timeout: 10)); sign.tap()
        XCTAssertTrue(app.textFields["Your full name"].waitForExistence(timeout: 10))
        let back = app.buttons.matching(identifier: "Back").allElementsBoundByIndex.max { $0.frame.midY < $1.frame.midY }
        XCTAssertNotNil(back); back?.tap()
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10)); done.tap()
        XCTAssertTrue(app.buttons["Technician: unlock"].waitForExistence(timeout: 10))
    }

    func testReadOnlyEstimateCanHandBackAfterStatusChanges() {
        let app = readonlyStatusChangeFixture()
        let estimate = app.buttons["customer-estimate-00000000-0000-4000-8000-000000002218"]
        XCTAssertTrue(estimate.waitForExistence(timeout: 10)); estimate.tap()
        let review = app.buttons["customer-book-review-sign"]
        XCTAssertTrue(review.waitForExistence(timeout: 10))
        changeSampleStatuses(app)
        thorbisStableButton(app, "customer-book-review-sign").tap()
        XCTAssertTrue(app.collectionViews["customer-document-pages"].waitForNonExistence(timeout: 5), "The review must replace the document pages")
        let handBack = app.buttons["Hand back to the technician"]
        XCTAssertTrue(handBack.waitForExistence(timeout: 10)); handBack.tap()
        XCTAssertTrue(app.buttons["Technician: unlock"].waitForExistence(timeout: 10))
    }

    func testReadOnlyInvoiceCanHandBackAfterStatusChanges() {
        let app = readonlyStatusChangeFixture()
        let estimate = app.buttons["customer-estimate-00000000-0000-4000-8000-000000002218"]
        XCTAssertTrue(estimate.waitForExistence(timeout: 10)); estimate.tap()
        XCTAssertTrue(app.buttons["Choose a job document"].waitForExistence(timeout: 10))
        app.buttons["Choose a job document"].tap(); app.buttons["INV-2209"].tap()
        let sign = app.buttons["Sign for the work"]
        XCTAssertTrue(sign.waitForExistence(timeout: 10))
        changeSampleStatuses(app)
        sign.tap()
        XCTAssertTrue(app.collectionViews["customer-document-pages"].waitForNonExistence(timeout: 5), "The review must replace the document pages")
        let handBack = app.buttons["Hand back to the technician"]
        XCTAssertTrue(handBack.waitForExistence(timeout: 10)); handBack.tap()
        XCTAssertTrue(app.buttons["Technician: unlock"].waitForExistence(timeout: 10))
    }

    private func readonlyStatusChangeFixture() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job", "--paper-preview-working-job", "--paper-preview-job-documents", "--paper-preview-documents-status-change"]
        app.launch()
        XCTAssertTrue(app.buttons["Job actions"].waitForExistence(timeout: 15))
        app.buttons["Job actions"].tap(); thorbisCustomerViewMenuItem(app).tap()
        XCTAssertTrue(app.staticTexts["Your job documents"].waitForExistence(timeout: 10))
        return app
    }

    private func changeSampleStatuses(_ app: XCUIApplication) {
        app.buttons["Sample connection"].tap()
        let change = app.buttons["Change sample document statuses"]
        XCTAssertTrue(change.waitForExistence(timeout: 5)); change.tap()
    }

    func testSwipesAndButtonsBrowseEveryDocumentForOnlyThisJob() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job", "--paper-preview-working-job", "--paper-preview-job-documents"]
        app.launch()
        let actions = app.buttons["Job actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 15))
        actions.tap()
        thorbisCustomerViewMenuItem(app).tap()
        let first = app.buttons["customer-estimate-00000000-0000-4000-8000-000000002218"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        first.tap()
        let position = app.staticTexts["customer-document-position"]
        XCTAssertTrue(position.waitForExistence(timeout: 10))
        XCTAssertEqual(position.label, "1 of 4 documents")
        XCTAssertFalse(app.buttons["Previous document"].isEnabled)
        app.buttons["Next document"].tap()
        XCTAssertEqual(position.label, "2 of 4 documents")
        XCTAssertTrue(app.staticTexts["Water heater add-ons"].exists)
        app.collectionViews["customer-document-pages"].swipeLeft()
        XCTAssertTrue(app.staticTexts["customer-invoice-summary"].waitForExistence(timeout: 10))
        XCTAssertEqual(position.label, "3 of 4 documents")
        app.buttons["Next document"].tap()
        XCTAssertEqual(position.label, "4 of 4 documents")
        XCTAssertFalse(app.buttons["Next document"].isEnabled)
        XCTAssertFalse(app.staticTexts["INV-2241"].exists)
        XCTAssertFalse(app.staticTexts["Other job estimate"].exists)
        app.buttons["Previous document"].tap()
        XCTAssertEqual(position.label, "3 of 4 documents")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Job document paging"
        shot.lifetime = .keepAlways
        add(shot)
    }
}

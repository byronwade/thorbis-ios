import XCTest

/// The job's More sheet (Paper 21K, F8), opened when it isn't already. Since the 21K trim the
/// customer doors are the Share circle's sheet and Money's estimates card; field mode (F8) keeps
/// them in More, so the helpers below fall back to it.
@MainActor
func thorbisOpenJobMore(_ app: XCUIApplication, unless row: XCUIElement) {
    guard !row.exists else { return }
    let more = app.buttons["Job actions"]
    guard more.waitForExistence(timeout: 30) else { return }
    // The circle can exist a moment before it answers (the job still loading, a cover leaving).
    // Under Customer view it never answers, so the wait is short.
    let reachable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: more)
    guard XCTWaiter.wait(for: [reachable], timeout: 3) == .completed else { return }
    more.tap()
    // The menu is a bottom sheet: a long one opens at half height, its later rows below the fold.
    if row.waitForExistence(timeout: 5) { thorbisRevealJobMenuRow(row, in: app) }
}

/// Brings a row of the open job menu (a `ThorbisMenu` sheet) into reach. Short, slow drags inside
/// the sheet, up for a row below the fold and down for one scrolled past the top, so no row is
/// stepped over and the sheet is never flung away. The first drag up also grows a half-height sheet.
@MainActor
func thorbisRevealJobMenuRow(_ row: XCUIElement, in app: XCUIApplication) {
    for _ in 0..<16 where row.exists && !row.isHittable {
        let up = row.frame.midY > app.frame.height * 0.3
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: up ? 0.7 : 0.4))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: up ? -220 : 220)),
                    withVelocity: .slow, thenHoldForDuration: 0.3)
    }
}

/// After a hand-back the staff job takes a moment to answer again (the protected window leaves,
/// the job's paper reloads). Waits for the job's More circle to be in reach.
@MainActor
@discardableResult
func thorbisWaitForStaffJob(_ app: XCUIApplication, timeout: TimeInterval = 20) -> Bool {
    let reachable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"),
                                              object: app.buttons["Job actions"])
    return XCTWaiter.wait(for: [reachable], timeout: timeout) == .completed
}

/// Customer view's row, found once its sheet is open (the Share circle's sheet; More in field mode).
@MainActor
func thorbisCustomerViewMenuItem(_ app: XCUIApplication) -> XCUIElement {
    app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Customer view")).firstMatch
}

/// Opens the header's Share circle sheet (Paper 21), unless `row` is already there. In field mode
/// (Paper F2 to F8) the bar has no Share circle and the field menu keeps these rows: opens More.
@MainActor
func thorbisOpenJobShare(_ app: XCUIApplication, unless row: XCUIElement) {
    guard !row.exists else { return }
    let more = app.buttons["Job actions"]
    guard more.waitForExistence(timeout: 30) else { return }
    // Owner 2026-11-21: the Share circle's rows moved into More (the bar keeps + and More only).
    thorbisOpenJobMore(app, unless: row)
}

/// Share › Customer view (More › Customer view in field mode), opening the sheet first when closed.
@MainActor
func thorbisCustomerViewDoor(_ app: XCUIApplication) -> XCUIElement {
    let row = thorbisCustomerViewMenuItem(app)
    thorbisOpenJobShare(app, unless: row)
    return row
}

/// Money › Show estimates, the estimates card's row (it was Money › Show estimates; field mode's
/// menu still carries it). Opens Money and scrolls the row into reach.
@MainActor
func thorbisShowCustomerDoor(_ app: XCUIApplication) -> XCUIElement {
    // Owner 2026-11-21: Money's two customer rows are one, "Show to customer" (field mode's menu too).
    let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Show to customer")).firstMatch
    // A usable frame first: `isHittable` throws on iOS 26 when the activation point is invalid.
    if app.thorbisUsableFrame(of: row) != nil, row.isHittable { return row }
    guard app.buttons["Job actions"].waitForExistence(timeout: 30) else { return row }
    // Job details has its sections; field mode has none and keeps the row in More.
    guard app.buttons["job-section-money"].exists || app.buttons["job-section-chooser"].exists else {
        thorbisOpenJobMore(app, unless: row)
        return row
    }
    if !row.waitForExistence(timeout: 3) {
        let chooser = app.buttons["job-section-chooser"]
        if chooser.exists {
            if !chooser.label.contains("Money") {
                for _ in 0..<5 where !chooser.isHittable { app.swipeDown(velocity: .slow) }
                chooser.tap()
                let money = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND identifier != %@", "Money", "job-section-chooser")).firstMatch
                if money.waitForExistence(timeout: 5) { money.tap() }
            }
        } else if app.buttons["job-section-money"].exists {
            thorbisTapStableButton(app, "job-section-money")
        }
        _ = row.waitForExistence(timeout: 30)
    }
    thorbisRevealOnJobPage(row, in: app)
    return row
}

/// Customer view covers the staff job page: the page is still there underneath, and none of its
/// controls can be reached. Reads the navigation bar's Job actions, which is on screen without
/// scrolling. Scrolling the job page while Customer view is up would drag the customer's screen
/// instead, which once stretched a test long enough for a session check to retire the handoff.
@MainActor
func thorbisAssertStaffPageCovered(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
    let staff = app.buttons["Job actions"]
    XCTAssertTrue(staff.waitForExistence(timeout: 10), "The staff job page stays under Customer view", file: file, line: line)
    // A usable frame first: `isHittable` throws on iOS 26 when the activation point is invalid.
    XCTAssertFalse(app.thorbisUsableFrame(of: staff) != nil && staff.isHittable,
                   "Customer view covers the staff job page", file: file, line: line)
}

/// Scrolls the job page with short held drags until `element` sits clear of the bars, either way.
@MainActor
func thorbisRevealOnJobPage(_ element: XCUIElement, in app: XCUIApplication) {
    for _ in 0..<12 where element.exists {
        let frame = element.frame
        let top = app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.maxY : app.frame.minY + 100
        if element.isHittable && frame.minY > top && frame.maxY < app.frame.height - 130 { return }
        let up = frame.midY > app.frame.height * 0.5
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.64 : 0.38))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.40 : 0.62))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
    }
}

/// Share › Add to favorites / Remove from favorites (it was the bar's star, then More's row).
@MainActor
func thorbisJobFavoriteRow(_ app: XCUIApplication) -> XCUIElement {
    let row = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Add to favorites", "Remove from favorites")).firstMatch
    thorbisOpenJobShare(app, unless: row)
    return row
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
    let footer = app.buttons["Hand back to technician"].firstMatch
    for _ in 0..<8 where !(element.isHittable && (!footer.exists || element.frame.maxY <= footer.frame.minY)) {
        list.swipeUp(velocity: .slow)
    }
}

func thorbisStableButton(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
    let query = app.buttons.matching(identifier: identifier)
    let element = query.firstMatch
    XCTAssertTrue(element.waitForExistence(timeout: 15), "Missing \(identifier)")
    func onScreenHittable() -> [XCUIElement] {
        let bounds = app.windows.firstMatch.exists ? app.windows.firstMatch.frame : app.frame
        let foot: CGFloat = identifier.hasPrefix("job-section-") ? bounds.height - 150 : .greatestFiniteMagnitude
        return query.allElementsBoundByIndex.filter { button in
            guard button.exists, button.isEnabled else { return false }
            guard let frame = app.thorbisUsableFrame(of: button) else { return false }
            return frame.maxY <= foot
        }
    }
    // Job tabs start under Overview's map and pin once scrolled; other screens can still be
    // settling. Look both ways with short held drags so momentum does not throw the control away.
    func nudge(down: Bool) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.38 : 0.64))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.56 : 0.46))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
    }
    // `where` runs on every pass, and each query is slow: ask once per nudge, not once per pass.
    var found = !onScreenHittable().isEmpty
    for _ in 0..<10 where !found {
        let frame = element.frame
        let tooHigh = frame.height.isFinite && frame.height > 1 && frame.midY.isFinite && frame.midY < app.frame.minY + 80
        nudge(down: tooHigh); found = !onScreenHittable().isEmpty
    }
    for _ in 0..<8 where !found { nudge(down: true); found = !onScreenHittable().isEmpty }
    var previous: CGRect?
    let stable = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
        guard let frame = onScreenHittable().first?.frame else { previous = nil; return false }
        defer { previous = frame }
        return previous == frame
    }, object: app)
    XCTAssertEqual(XCTWaiter.wait(for: [stable], timeout: 10), .completed,
                   "An enabled, unobscured \(identifier) must have stable geometry before a tap")
    let matches = onScreenHittable()
    XCTAssertFalse(matches.isEmpty, "\(identifier) is not hittable")
    return matches[0]
}

/// Taps a stable control at its centre. XCTest's `.tap()` can still report "not hittable" when the
/// hierarchy shifts between the wait and the tap (pinned job tabs, Overview's map finishing).
@discardableResult
func thorbisTapStableButton(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
    let button = thorbisStableButton(app, identifier)
    button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    return button
}

@MainActor
final class JobEstimateHandoffUITests: XCTestCase {
    /// How long the first wait after "Show to customer" may take, whatever it waits for.
    ///
    /// The first time Customer view opens on Estimates in a launch, the app's main thread is held
    /// while that page is pushed. Measured over 309 openings in five CI runs: median 3.7 s, one in
    /// twenty over 11 s, the longest 29.8 s. Nothing in the app's own code accounts for it, and it
    /// is not yet known what the thread waits for (BYR-1841). Until then every first wait after
    /// the door uses this one limit; shorter ones failed about one opening in fifteen.
    private let customerViewFirstEstimate: TimeInterval = 45
    func testLongEstimateTitleAndStatusAtNormalText() {
        let app = open(["--paper-preview-handoff-long-title", "--paper-preview-handoff-hide-controls"])
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 30)); thorbisShowCustomerDoor(app).tap()
        let card = app.buttons["handoff-select-00000000-0000-4000-8000-000000008101"]
        XCTAssertTrue(card.waitForExistence(timeout: customerViewFirstEstimate)); visible(app, card)
        XCTAssertTrue(card.label.contains("Replace the water heater and restore the service area"))
        XCTAssertTrue((card.value as? String)?.contains("Sent") == true)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Long estimate title and status, normal text"; shot.lifetime = .keepAlways; add(shot)
        card.tap()
        XCTAssertTrue((card.value as? String)?.hasPrefix("Selected,") == true)

    }
    func testLongEstimateTitleAndStatusAtLargestText() {
        let app = open(["--paper-preview-handoff-long-title", "--paper-preview-handoff-hide-controls", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 30)); thorbisShowCustomerDoor(app).tap()
        let card = app.buttons["handoff-select-00000000-0000-4000-8000-000000008101"]
        XCTAssertTrue(card.waitForExistence(timeout: customerViewFirstEstimate)); visible(app, card)
        XCTAssertTrue(card.label.contains("Replace the water heater and restore the service area"))
        XCTAssertTrue((card.value as? String)?.contains("Sent") == true)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Long estimate title and status, largest text"; shot.lifetime = .keepAlways; add(shot)
        card.tap()
        XCTAssertTrue((card.value as? String)?.hasPrefix("Selected,") == true)
        let review = app.buttons["handoff-review-selected"]
        XCTAssertTrue(review.waitForExistence(timeout: 10)); XCTAssertTrue(review.isEnabled)
        XCTAssertTrue(review.label.contains("Review selected (1)"))
        XCTAssertLessThan(review.frame.height, 100, "The review action should leave space for reading estimates")
        let selectedShot = XCTAttachment(screenshot: app.screenshot()); selectedShot.name = "Selected estimate review action, largest text"; selectedShot.lifetime = .keepAlways; add(selectedShot)
        review.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "separate estimates. You'll approve and sign each one.")).firstMatch.waitForExistence(timeout: 20))
    }
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
            let actions = ["handoff-review-selected", "handoff-submit-approval", "handoff-continue-signatures", "handoff-approve-selected", "handoff-batch-retry", "handoff-batch-done"].flatMap {
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
    /// After the authenticated hand-back the staff job is back in reach: its More circle answers
    /// and Money › Show estimates can be used again (the door was Money's pinned "Show customer").
    private func waitForStaffDoor(_ app: XCUIApplication, timeout: TimeInterval = 20) {
        XCTAssertTrue(thorbisWaitForStaffJob(app, timeout: timeout), "The staff job must answer again after the hand-back")
        waitHittable(thorbisShowCustomerDoor(app))
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
        // Paper 38B: Customer view's home has no bar, so no pill. From there the technician hands
        // back with the pill at the foot and unlocks on the hand-back screen.
        if !app.buttons.matching(identifier: "customer-mode-owner-exit").firstMatch.waitForExistence(timeout: 5),
           app.staticTexts["customer-view-title"].exists {
            app.buttons["Hand back to technician"].tap()
            let unlock = app.buttons["Technician: unlock"]
            XCTAssertTrue(unlock.waitForExistence(timeout: 10))
            return unlock
        }
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
    /// Waits until the sample owner authentication has answered `attempts` times. The sample counts an
    /// attempt in the same step that answers it, so a read after this one sees what that answer did.
    private func waitForOwnerAuthentication(_ app: XCUIApplication, attempts: Int) {
        let ledger = app.descendants(matching: .any).matching(identifier: "handoff-canonical-receipt").firstMatch
        let answered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let data = (ledger.value as? String)?.data(using: .utf8),
                  let proof = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            return proof["ownerAuthenticationAttempts"] as? Int == attempts
        }, object: ledger)
        XCTAssertEqual(XCTWaiter.wait(for: [answered], timeout: 10), .completed, "The owner authentication must be answered before the screen is read")
    }
    private func selectEstimate(_ app: XCUIApplication, _ element: XCUIElement) {
        visible(app, element)
        thorbisStableButton(app, element.identifier).tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (element.value as? String)?.hasPrefix("Selected,") == true
        }, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 10), .completed, "Each real selection must stick before the next tap")
    }
    private func revealPrecisely(_ element: XCUIElement, in app: XCUIApplication, scrollID: String) {
        let scroll = app.scrollViews[scrollID]
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))
        for _ in 0..<24 {
            let footerIDs = ["handoff-review-selected", "handoff-previous-estimate", "handoff-next-estimate"]
            let footerTop = footerIDs.flatMap { app.buttons.matching(identifier: $0).allElementsBoundByIndex }
                .filter { $0.exists && $0.frame.intersects(app.frame) }.map { $0.frame.minY }.min() ?? app.frame.maxY
            let top = app.frame.minY + 105
            let point = element.frame.midY
            if element.isHittable && point > top && point < footerTop { return }
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: point <= top ? 0.68 : 0.42))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTFail("The customer control must have an unobscured tap point")
    }

    func testEstimateBrowseKeepsLongDescriptionReadOnlyAndEdgeBackWorks() {
        let app = open(["--paper-preview-handoff-long-description", "--paper-preview-handoff-hide-controls",
                        "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 30)); thorbisShowCustomerDoor(app).tap()
        let first = app.buttons["handoff-details-00000000-0000-4000-8000-000000008101"]
        XCTAssertTrue(first.waitForExistence(timeout: customerViewFirstEstimate)); revealPrecisely(first, in: app, scrollID: "job-estimate-handoff")
        capture(app, "Largest text estimate detail action")
        first.tap()
        let more = app.buttons["Show more, Estimate EST-8101, item 1"]
        XCTAssertTrue(more.waitForExistence(timeout: 30)); revealPrecisely(more, in: app, scrollID: "handoff-estimate-details"); more.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Final sample detail: return the area to its original condition.")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.textViews.firstMatch.exists)
        capture(app, "Largest text read-only estimate description")
        app.buttons["Done"].tap()
        let details = app.scrollViews["handoff-estimate-details"]
        XCTAssertTrue(details.waitForExistence(timeout: 10))
        details.swipeLeft()
        XCTAssertTrue(app.navigationBars["EST-8102"].waitForExistence(timeout: 15))
        capture(app, "Largest text second estimate before edge back")
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(app.scrollViews["job-estimate-handoff"].waitForExistence(timeout: 15), "The system edge-back gesture must return to the estimate overview")
    }

    /// A swipe back let go a fifth of the way across, after a hold, must roll back (BYR-1842).
    /// The finger stops for half a second before it lifts, far short of half way. In CI the pop
    /// probe still logged about 130 pt/s at the lift, and the system rolled the swipe back at 18%
    /// of the way (run 45148171838). The estimate stays open, and Back still reaches a loaded
    /// overview. The test cannot see the swipe begin: the app log's "[pop-gesture] began" line
    /// for this test shows that it did.
    func testAbandonedEdgeBackKeepsTheEstimateOpen() {
        let app = open(["--paper-preview-handoff-hide-controls"])
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 30)); thorbisShowCustomerDoor(app).tap()
        let first = app.buttons["handoff-details-00000000-0000-4000-8000-000000008101"]
        XCTAssertTrue(first.waitForExistence(timeout: customerViewFirstEstimate)); visible(app, first); first.tap()
        XCTAssertTrue(app.staticTexts["Sample repair"].waitForExistence(timeout: 30), "The estimate must finish loading before the swipe")
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.21, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.5)
        // The overview is in the hierarchy only while the swipe shows it; it leaves when the pop rolls back.
        let rolledBack = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.scrollViews["job-estimate-handoff"])
        XCTAssertEqual(XCTWaiter.wait(for: [rolledBack], timeout: 15), .completed, "A swipe let go short of half way must not go back")
        XCTAssertTrue(app.navigationBars["EST-8101"].exists); XCTAssertTrue(app.staticTexts["Sample repair"].exists)
        waitHittable(app.scrollViews["handoff-estimate-details"])
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let firstPrice = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "$190.00"), object: app.buttons["handoff-select-00000000-0000-4000-8000-000000008101"])
        let secondPrice = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "$320.00"), object: app.buttons["handoff-select-00000000-0000-4000-8000-000000008102"])
        XCTAssertEqual(XCTWaiter.wait(for: [firstPrice, secondPrice], timeout: 45), .completed, "Back after an abandoned swipe must reach an overview that has loaded both prices")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Couldn't finish loading estimates")).firstMatch.exists)
    }

    func testOverviewLoadsBothVerifiedPricesBeforeSelection() {
        let app = open(["--paper-preview-handoff-hide-controls"])
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 30)); thorbisShowCustomerDoor(app).tap()
        let first = app.buttons["handoff-select-00000000-0000-4000-8000-000000008101"]
        let second = app.buttons["handoff-select-00000000-0000-4000-8000-000000008102"]
        XCTAssertTrue(first.waitForExistence(timeout: customerViewFirstEstimate)); XCTAssertTrue(second.waitForExistence(timeout: 30))
        let firstPrice = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "$190.00"), object: first)
        let secondPrice = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "$320.00"), object: second)
        XCTAssertEqual(XCTWaiter.wait(for: [firstPrice, secondPrice], timeout: 45), .completed, "Both verified prices should be available without selecting either estimate")
        XCTAssertTrue((first.value as? String ?? "").contains("Not selected"))
        XCTAssertTrue((second.value as? String ?? "").contains("Not selected"))
    }

    func testOverviewCanRetryAnUnavailablePrice() {
        let app = open(["--paper-preview-handoff-hide-controls", "--handoff-test-second-price-fails-once"])
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 30)); thorbisShowCustomerDoor(app).tap()
        let retry = app.buttons["handoff-retry-price-00000000-0000-4000-8000-000000008102"]
        XCTAssertTrue(retry.waitForExistence(timeout: 45), "A failed issued read must have a retry")
        visible(app, retry); retry.tap()
        let second = app.buttons["handoff-select-00000000-0000-4000-8000-000000008102"]
        let price = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "$320.00"), object: second)
        XCTAssertEqual(XCTWaiter.wait(for: [price], timeout: 45), .completed)
        XCTAssertFalse(retry.exists)
    }

    func testApprovedOverviewShowsMatchingVerifiedReceipt() {
        let app = open(["--paper-preview-handoff-hide-controls", "--handoff-test-second-approved", "--handoff-test-approved-receipt"])
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 30)); thorbisShowCustomerDoor(app).tap()
        let approvedCard = app.otherElements["handoff-card-00000000-0000-4000-8000-000000008102"]
        XCTAssertTrue(approvedCard.staticTexts["$320.00"].waitForExistence(timeout: 45), "The accepted receipt's verified total should be visible in its own card")
        XCTAssertFalse(app.buttons["handoff-retry-price-00000000-0000-4000-8000-000000008102"].exists)
    }

    func testApprovedOverviewRejectsReceiptForDifferentRevision() {
        let app = open(["--paper-preview-handoff-hide-controls", "--handoff-test-second-approved", "--handoff-test-approved-receipt", "--handoff-test-approved-receipt-wrong-revision"])
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 30)); thorbisShowCustomerDoor(app).tap()
        let retry = app.buttons["handoff-retry-price-00000000-0000-4000-8000-000000008102"]
        XCTAssertTrue(retry.waitForExistence(timeout: 45), "A receipt for another revision must fail validation")
        XCTAssertFalse(app.otherElements["handoff-card-00000000-0000-4000-8000-000000008102"].staticTexts["$320.00"].exists)
    }

    func testLoadingNextPageReusesVerifiedPrices() throws {
        let app = open(["--paper-preview-handoff-hide-controls", "--paper-preview-handoff-many-estimates"])
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 45)); thorbisShowCustomerDoor(app).tap()
        let first = app.buttons["handoff-select-00000000-0000-4000-8000-000000008101"]
        XCTAssertTrue(first.waitForExistence(timeout: 45))
        let firstPrice = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "$190.00"), object: first)
        XCTAssertEqual(XCTWaiter.wait(for: [firstPrice], timeout: 45), .completed)
        let path = "/v1/estimates/00000000-0000-4000-8000-000000008101/revisions/1"
        func firstReadCount() throws -> Int {
            let proof = try receipt(app)
            let requests = try XCTUnwrap(proof["requests"] as? [[String: String]])
            return requests.filter { $0["method"] == "GET" && $0["path"] == path }.count
        }
        XCTAssertEqual(try firstReadCount(), 1)
        let more = app.buttons["handoff-load-more-estimates"]
        let list = app.scrollViews["job-estimate-handoff"]
        // The page's last control: it must clear the pinned Review bar before the tap. (It counts as
        // hittable while it still peeks out under that bar, where a tap lands on the bar instead.)
        for _ in 0..<30 where !more.exists { list.swipeUp() }
        XCTAssertTrue(more.waitForExistence(timeout: 10)); visible(app, more)
        XCTAssertTrue(more.isEnabled, "Load more answers once the first page's prices are in")
        more.tap()
        let next = app.buttons["handoff-select-00000000-0000-4000-8000-000000082018"]
        for _ in 0..<30 where !next.exists { list.swipeUp() }
        XCTAssertTrue(next.waitForExistence(timeout: 45))
        let nextPrice = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "$320.00"), object: next)
        XCTAssertEqual(XCTWaiter.wait(for: [nextPrice], timeout: 45), .completed)
        XCTAssertEqual(try firstReadCount(), 1, "Loading another page must reuse the first fresh validated revision")
    }

    func testFailedRefreshShowsUnavailablePriceThenRecovers() {
        let app = open(["--paper-preview-handoff-hide-controls", "--handoff-test-failed-refresh"])
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 30)); thorbisShowCustomerDoor(app).tap()
        let first = app.buttons["handoff-select-00000000-0000-4000-8000-000000008101"]
        XCTAssertTrue(first.waitForExistence(timeout: customerViewFirstEstimate))
        let initialPrice = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "$190.00"), object: first)
        XCTAssertEqual(XCTWaiter.wait(for: [initialPrice], timeout: 45), .completed)
        let second = app.buttons["handoff-select-00000000-0000-4000-8000-000000008102"]
        let secondPrice = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "$320.00"), object: second)
        XCTAssertEqual(XCTWaiter.wait(for: [secondPrice], timeout: 45), .completed, "Finish both initial prefetches before injecting the refresh failure")
        let fail = app.buttons["Fail sample refresh"]
        XCTAssertTrue(fail.waitForExistence(timeout: 30)); visible(app, fail); fail.tap()
        XCTAssertTrue(app.buttons["Try again"].waitForExistence(timeout: 30), "The forced refresh must finish with an error")
        let unavailable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "Refresh to check price"), object: first)
        XCTAssertEqual(XCTWaiter.wait(for: [unavailable], timeout: 30), .completed)
        XCTAssertFalse((first.value as? String ?? "").contains("$190.00"))
        let retry = app.buttons["Try again"]
        XCTAssertTrue(retry.waitForExistence(timeout: 30)); visible(app, retry); retry.tap()
        let recovered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "$190.00"), object: first)
        XCTAssertEqual(XCTWaiter.wait(for: [recovered], timeout: 45), .completed)
    }

    private func openSecondEstimateForValidation(_ flag: String, extraArgs: [String] = []) -> XCUIApplication {
        let app = open(["--paper-preview-handoff-hide-controls", flag] + extraArgs)
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 30))
        thorbisShowCustomerDoor(app).tap()
        let first = app.buttons["handoff-details-00000000-0000-4000-8000-000000008101"]
        XCTAssertTrue(first.waitForExistence(timeout: customerViewFirstEstimate)); visible(app, first); first.tap()
        XCTAssertTrue(app.staticTexts["Sample repair"].waitForExistence(timeout: 30))
        let next = app.buttons["handoff-next-estimate"]
        XCTAssertTrue(next.waitForExistence(timeout: 15)); next.tap()
        XCTAssertTrue(app.navigationBars["EST-8102"].waitForExistence(timeout: 15))
        return app
    }

    private func assertInvalidSecondEstimate(_ flag: String) {
        let app = openSecondEstimateForValidation(flag)
        XCTAssertTrue(app.buttons["Try again"].waitForExistence(timeout: 30))
        let details = app.scrollViews["handoff-estimate-details"]
        XCTAssertFalse(details.staticTexts["Sample additional work"].exists)
        XCTAssertFalse(details.staticTexts["Anonymized service scope"].exists)
    }

    private func returnFromRejectedSecondEstimate(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["Try again"].waitForExistence(timeout: 30), "The issued-revision read must finish and reject these terms")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["handoff-review-selected"].waitForExistence(timeout: 15))
    }

    func testUnverifiedSentAmountIsHiddenAndCannotAdvanceReview() {
        let app = openSecondEstimateForValidation("--handoff-test-empty-base")
        returnFromRejectedSecondEstimate(app)
        let second = app.buttons["handoff-select-00000000-0000-4000-8000-000000008102"]
        XCTAssertTrue(second.waitForExistence(timeout: 30))
        // Back reads the overview's prices again. Its retry says this estimate's issued read was refused.
        XCTAssertTrue(app.buttons["handoff-retry-price-00000000-0000-4000-8000-000000008102"].waitForExistence(timeout: 45),
                      "The overview's issued read must finish and reject these terms")
        XCTAssertFalse((second.value as? String ?? "").contains("$320.00"), "The accessible selection must not describe the unverified record amount")
        capture(app, "Unverified sent estimate price is withheld")
        let card = app.otherElements["handoff-card-00000000-0000-4000-8000-000000008102"]
        XCTAssertFalse(card.staticTexts["$320.00"].exists, "The customer estimate card must not show an unverified issued total")
        visible(app, second); selectEstimate(app, second)
        thorbisStableButton(app, "handoff-review-selected").tap()
        XCTAssertTrue(app.buttons["Try again"].waitForExistence(timeout: 30), "Review must finish with a validation failure")
        XCTAssertFalse(app.buttons["Continue to signatures"].exists)
        XCTAssertFalse(app.textFields["Your full name"].exists)
    }

    func testUnverifiedPackagePriceIsHidden() {
        let app = openSecondEstimateForValidation("--handoff-test-empty-option")
        returnFromRejectedSecondEstimate(app)
        let second = app.buttons["handoff-select-00000000-0000-4000-8000-000000008102"]
        XCTAssertTrue(second.waitForExistence(timeout: 30)); visible(app, second); selectEstimate(app, second)
        let option = app.buttons["handoff-option-00000000-0000-4000-8000-000000008102-00000000-0000-4000-8000-000000008202"]
        XCTAssertTrue(option.waitForExistence(timeout: 15)); visible(app, option); option.tap()
        XCTAssertFalse(app.staticTexts["$250.00"].exists, "Unverified package totals must not be presented as issued prices")
        let value = second.value as? String ?? ""
        XCTAssertTrue(value.contains("Empty package"), "Accessibility should identify the selected package")
        XCTAssertFalse(value.contains("$250.00"), "Accessibility must not announce an unverified package price")
    }

    func testUnverifiedApprovedAmountIsHidden() {
        let app = openSecondEstimateForValidation("--handoff-test-empty-base", extraArgs: ["--handoff-test-second-approved"])
        returnFromRejectedSecondEstimate(app)
        XCTAssertTrue(app.staticTexts["Sample additional work"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.otherElements["handoff-card-00000000-0000-4000-8000-000000008102"].staticTexts["$320.00"].exists, "An approved record amount is not a verified issued receipt")
    }

    func testBrowserRejectsEmptyIssuedBase() { assertInvalidSecondEstimate("--handoff-test-empty-base") }
    func testBrowserRejectsEmptyIssuedOption() { assertInvalidSecondEstimate("--handoff-test-empty-option") }
    func testBrowserRejectsNonUSDRevision() { assertInvalidSecondEstimate("--handoff-test-non-usd") }
    func testBrowserRejectsMismatchedRevisionTotal() { assertInvalidSecondEstimate("--handoff-test-mismatch") }

    func testBrowserAllowsNonemptyZeroPricedScope() {
        let app = openSecondEstimateForValidation("--handoff-test-zero-line")
        let details = app.scrollViews["handoff-estimate-details"]
        XCTAssertTrue(details.staticTexts["Included sample service"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.buttons["Try again"].exists)
    }

    func testEstimateBrowsingDoesNotShowPriorTermsWhenNextReadFails() {
        let app = open(["--paper-preview-handoff-hide-controls", "--paper-preview-handoff-second-details-fail"])
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 30)); thorbisShowCustomerDoor(app).tap()
        let first = app.buttons["handoff-details-00000000-0000-4000-8000-000000008101"]
        XCTAssertTrue(first.waitForExistence(timeout: customerViewFirstEstimate)); visible(app, first); first.tap()
        XCTAssertTrue(app.staticTexts["Sample repair"].waitForExistence(timeout: 30))
        app.buttons["handoff-next-estimate"].tap()
        XCTAssertTrue(app.navigationBars["EST-8102"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Try again"].waitForExistence(timeout: 30))
        capture(app, "Second estimate failed without prior terms")
        XCTAssertFalse(app.scrollViews["handoff-estimate-details"].staticTexts["Sample repair"].exists, "The prior estimate's terms must not remain inside the new estimate")
        app.buttons["handoff-previous-estimate"].tap()
        XCTAssertTrue(app.staticTexts["Sample repair"].waitForExistence(timeout: 30))
    }

    func testEstimateBrowsingRetiresAfterSessionEndsOnSecondEstimate() {
        let app = open(["--paper-preview-handoff-slow-invalidation"])
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 30)); thorbisShowCustomerDoor(app).tap()
        let first = app.buttons["handoff-details-00000000-0000-4000-8000-000000008101"]
        XCTAssertTrue(first.waitForExistence(timeout: customerViewFirstEstimate))
        toggleSampleControls(app); app.buttons["End sample session shortly"].tap(); toggleSampleControls(app)
        visible(app, first); first.tap()
        XCTAssertTrue(app.staticTexts["Sample repair"].waitForExistence(timeout: 30))
        app.buttons["handoff-next-estimate"].tap()
        XCTAssertTrue(app.staticTexts["Sample additional work"].waitForExistence(timeout: 15))
        let detail = app.staticTexts["Sample additional work"]
        let retired = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: detail)
        XCTAssertEqual(XCTWaiter.wait(for: [retired], timeout: 30), .completed)
        XCTAssertFalse(app.buttons["handoff-next-estimate"].exists)
        XCTAssertFalse(app.buttons["handoff-previous-estimate"].exists)
    }

    func testCustomerCanBrowseJobEstimatesUsingAccessibleControls() {
        let app = open(["--paper-preview-handoff-hide-controls"])
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 30))
        thorbisShowCustomerDoor(app).tap()
        let first = app.buttons["handoff-details-00000000-0000-4000-8000-000000008101"]
        XCTAssertTrue(first.waitForExistence(timeout: customerViewFirstEstimate)); visible(app, first); first.tap()
        XCTAssertTrue(app.staticTexts["Sample repair"].waitForExistence(timeout: 30))
        let previous = app.buttons["handoff-previous-estimate"]
        let next = app.buttons["handoff-next-estimate"]
        XCTAssertTrue(previous.exists); XCTAssertFalse(previous.isEnabled)
        XCTAssertTrue(next.exists); XCTAssertTrue(next.isEnabled); next.tap()
        XCTAssertTrue(app.navigationBars["EST-8102"].waitForExistence(timeout: 15))
        XCTAssertTrue(previous.isEnabled); previous.tap()
        XCTAssertTrue(app.navigationBars["EST-8101"].waitForExistence(timeout: 15))
    }

    func testCustomerSwipesBetweenJobEstimateDetailsWithoutChangingSelection() {
        let app = open(["--paper-preview-handoff-hide-controls"])
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 30))
        thorbisShowCustomerDoor(app).tap()
        let first = app.buttons["handoff-details-00000000-0000-4000-8000-000000008101"]
        XCTAssertTrue(first.waitForExistence(timeout: customerViewFirstEstimate))
        visible(app, first)
        first.tap()
        let details = app.scrollViews["handoff-estimate-details"]
        XCTAssertTrue(details.waitForExistence(timeout: 30))
        XCTAssertTrue(app.navigationBars["EST-8101"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Sample repair"].waitForExistence(timeout: 30), "The current estimate must finish loading before swiping")
        details.swipeLeft()
        XCTAssertTrue(app.navigationBars["EST-8102"].waitForExistence(timeout: 10),
                      "Swiping should open the next estimate for this job")
        details.swipeRight()
        XCTAssertTrue(app.navigationBars["EST-8101"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let select = app.buttons["handoff-select-00000000-0000-4000-8000-000000008101"]
        XCTAssertTrue(select.waitForExistence(timeout: 10))
        XCTAssertTrue((select.value as? String)?.hasPrefix("Not selected,") == true)
    }

    func testLongEstimateListKeepsSelectionsFromBothEnds() {
        let app = open(["--paper-preview-handoff-many-estimates", "--paper-preview-handoff-hide-controls", "--paper-preview-handoff-paging-diagnostic"])
        let door = thorbisShowCustomerDoor(app)
        XCTAssertTrue(door.waitForExistence(timeout: 45)); door.tap()
        let first = app.buttons["handoff-select-00000000-0000-4000-8000-000000008101"]
        XCTAssertTrue(first.waitForExistence(timeout: 45)); selectEstimate(app, first)
        let details = app.buttons["handoff-details-00000000-0000-4000-8000-000000008101"]
        XCTAssertTrue(details.exists, "A loaded estimate can be read before loading every page")
        visible(app, details); details.tap()
        XCTAssertTrue(app.scrollViews["handoff-estimate-details"].waitForExistence(timeout: 45))
        XCTAssertTrue(app.staticTexts["Sample repair"].waitForExistence(timeout: 45), "Issued terms must open while other pages remain unloaded")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertFalse(app.buttons["handoff-review-selected"].isEnabled, "Partial membership must not authorize approval")
        let more = app.buttons["handoff-load-more-estimates"]
        let list = app.scrollViews["job-estimate-handoff"]
        for suffix in ["082018", "082028", "082038"] {
            // The lazy stack may not instantiate the footer while it is offscreen.
            for _ in 0..<30 where !more.exists { list.swipeUp() }
            XCTAssertTrue(more.exists, "The next-page action must be reachable in the list")
            let pageReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                more.exists && more.isEnabled
            }, object: more)
            XCTAssertEqual(XCTWaiter.wait(for: [pageReady], timeout: 45), .completed,
                           "The previous page must finish before requesting another")
            for _ in 0..<30 where !more.isHittable { list.swipeUp() }
            XCTAssertTrue(more.isHittable && more.isEnabled, "The next page action must be visible and enabled")
            let review = app.buttons["handoff-review-selected"]
            for _ in 0..<8 where more.frame.maxY > review.frame.minY { list.swipeUp() }
            XCTAssertLessThanOrEqual(more.frame.maxY, review.frame.minY, "The full Load more control must be clear of the fixed review bar")
            more.tap()
            if suffix == "082028" {
                let diagnostic = app.staticTexts["handoff-paging-diagnostic"]
                let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    (diagnostic.value as? String)?.contains("count=30;") == true
                }, object: diagnostic)
                _ = XCTWaiter.wait(for: [loaded], timeout: 5)
                print("PAGING DIAGNOSTIC: \(diagnostic.value ?? "missing")")
                print("PAGING HIERARCHY: \(app.debugDescription)")
            }
            let nextPageEnd = app.buttons["handoff-select-00000000-0000-4000-8000-000000\(suffix)"]
            for _ in 0..<30 where !nextPageEnd.isHittable { list.swipeUp() }
            let markerReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                nextPageEnd.exists && nextPageEnd.isHittable
            }, object: nextPageEnd)
            XCTAssertEqual(XCTWaiter.wait(for: [markerReady], timeout: 45), .completed,
                           "Each requested page must load before requesting the next one")
        }
        let last = app.buttons["handoff-select-00000000-0000-4000-8000-000000082038"]
        for _ in 0..<60 where !last.isHittable { list.swipeUp() }
        XCTAssertTrue(last.isHittable, "The last estimate must remain reachable without obscuring its control")
        selectEstimate(app, last)
        XCTAssertTrue(app.buttons["Review selected (2)"].waitForExistence(timeout: 10))
        for _ in 0..<60 where !first.isHittable { list.swipeDown() }
        XCTAssertTrue(first.isHittable)
        XCTAssertTrue((first.value as? String)?.hasPrefix("Selected,") == true)
    }
    func testLoadMoreIsClearOfReviewBarAtLargestText() {
        let app = open(["--paper-preview-handoff-many-estimates", "--paper-preview-handoff-hide-controls",
                        "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let door = thorbisShowCustomerDoor(app)
        XCTAssertTrue(door.waitForExistence(timeout: 45)); door.tap()
        XCTAssertTrue(app.buttons["handoff-select-00000000-0000-4000-8000-000000008101"].waitForExistence(timeout: customerViewFirstEstimate))
        let list = app.scrollViews["job-estimate-handoff"], more = app.buttons["handoff-load-more-estimates"]
        let review = app.buttons["handoff-review-selected"]
        for _ in 0..<50 where !more.exists || !more.isHittable || more.frame.maxY > review.frame.minY { list.swipeUp() }
        XCTAssertTrue(more.exists && more.isHittable && more.isEnabled)
        XCTAssertLessThanOrEqual(more.frame.maxY, review.frame.minY, "Load more must be fully above the fixed review bar at accessibility sizes")
        more.tap()
        let nextPage = app.buttons["handoff-select-00000000-0000-4000-8000-000000082018"]
        for _ in 0..<50 where !nextPage.isHittable { list.swipeUp() }
        XCTAssertTrue(nextPage.isHittable, "The unobscured action must actually load the next page")
    }
    func testSelectedReviewFoldsHiddenMaterialsWithoutExposingTheirDescription() {
        let app = open(["--paper-preview-handoff-hidden-material", "--paper-preview-handoff-hide-controls"])
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 45))
        thorbisShowCustomerDoor(app).tap()
        let estimate = app.buttons["handoff-select-00000000-0000-4000-8000-000000008101"]
        XCTAssertTrue(estimate.waitForExistence(timeout: 45))
        selectEstimate(app, estimate)
        thorbisStableButton(app, "handoff-review-selected").tap()
        XCTAssertTrue(app.buttons["Continue to signatures"].waitForExistence(timeout: 45))
        XCTAssertFalse(app.staticTexts["Private material detail"].exists)
        XCTAssertTrue(app.staticTexts["Materials"].exists)
        XCTAssertTrue(app.staticTexts["$190.00"].exists)
        thorbisStableButton(app, "handoff-continue-signatures").tap()
        XCTAssertTrue(app.textFields["Your full name"].waitForExistence(timeout: 45))
        XCTAssertFalse(app.staticTexts["Private material detail"].exists)
        draw(app)
        thorbisStableButton(app, "handoff-submit-approval").tap()
        XCTAssertTrue(app.buttons["See approvals"].waitForExistence(timeout: 15))
    }
    func testCustomerCanReadApprovedAndSentEstimatesForTheSameJob() {
        let app = open(["--paper-preview-handoff-mixed", "--paper-preview-handoff-options", "--paper-preview-handoff-hide-controls"])
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 45))
        thorbisShowCustomerDoor(app).tap()
        let approved = app.buttons["handoff-details-00000000-0000-4000-8000-000000008101"]
        XCTAssertTrue(approved.waitForExistence(timeout: 45))
        visible(app, approved); approved.tap()
        XCTAssertTrue(app.scrollViews["handoff-estimate-details"].waitForExistence(timeout: 10))
        // With no signed receipt to verify, the approved estimate says so and shows no package scope.
        XCTAssertTrue(app.staticTexts["No signed customer receipt is available for this approval. Ask your technician for details."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Selected package scope"].exists)
        app.navigationBars.buttons["Back"].firstMatch.tap()
        XCTAssertFalse(app.buttons["handoff-select-00000000-0000-4000-8000-000000008101"].exists)
        let sent = app.buttons["handoff-select-00000000-0000-4000-8000-000000008102"]
        XCTAssertTrue(sent.waitForExistence(timeout: 10))
        visible(app, sent); sent.tap()
        XCTAssertTrue(app.buttons["Review selected (1)"].exists)
    }
    func testCustomerCanReadEstimateBeforeSelectingIt() {
        let app = open(["--paper-preview-handoff-long-description", "--paper-preview-handoff-hide-controls"])
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 10))
        thorbisShowCustomerDoor(app).tap()
        let selected = app.buttons["handoff-select-00000000-0000-4000-8000-000000008101"]
        let loaded = selected.waitForExistence(timeout: 45)
        if !loaded {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Customer estimate handoff hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
            let ledger = app.descendants(matching: .any).matching(identifier: "handoff-canonical-receipt").firstMatch
            if let value = ledger.value as? String {
                let attachment = XCTAttachment(string: value)
                attachment.name = "Anonymized handoff request ledger"; attachment.lifetime = .keepAlways; add(attachment)
            }
        }
        XCTAssertTrue(loaded)
        let details = app.buttons["handoff-details-00000000-0000-4000-8000-000000008101"]
        XCTAssertTrue(details.waitForExistence(timeout: 10))
        visible(app, details)
        details.tap()
        let more = app.buttons["Show more, Estimate EST-8101, item 1"]
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        visible(app, more)
        more.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Final sample detail: return the area to its original condition.")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.textViews.firstMatch.exists)
        app.buttons["Done"].tap()
        app.navigationBars.buttons["Back"].firstMatch.tap()
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        XCTAssertTrue((selected.value as? String)?.hasPrefix("Not selected,") == true)
        XCTAssertTrue(app.buttons["Review selected (0)"].exists)
    }
    func testPreselectionDetailsHidePrivateMaterialsWithoutSelecting() {
        let app = open(["--paper-preview-handoff-hidden-material", "--paper-preview-handoff-hide-controls"])
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 45))
        thorbisShowCustomerDoor(app).tap()
        let selected = app.buttons["handoff-select-00000000-0000-4000-8000-000000008101"]
        let details = app.buttons["handoff-details-00000000-0000-4000-8000-000000008101"]
        XCTAssertTrue(details.waitForExistence(timeout: 45))
        visible(app, details)
        details.tap()
        XCTAssertTrue(app.staticTexts["Materials"].waitForExistence(timeout: 45))
        XCTAssertFalse(app.staticTexts["Private material detail"].exists)
        XCTAssertTrue(app.staticTexts["$190.00"].exists)
        app.navigationBars.buttons["Back"].firstMatch.tap()
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        XCTAssertTrue((selected.value as? String)?.hasPrefix("Not selected,") == true)
    }
    func testDetailsReaderClosesWhenSameEstimateGetsNewRevision() {
        exerciseDetailsMutation("Replace sample revision shortly")
    }
    func testDetailsReaderClosesWhenEstimateLeavesJob() {
        exerciseDetailsMutation("Remove sample estimate shortly")
    }
    private func exerciseDetailsMutation(_ control: String) {
        let app = open(["--paper-preview-handoff-long-description", "--paper-preview-handoff-hide-controls", "--paper-preview-handoff-details-mutation"])
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 45))
        thorbisShowCustomerDoor(app).tap()
        let details = app.buttons["handoff-details-00000000-0000-4000-8000-000000008101"]
        XCTAssertTrue(details.waitForExistence(timeout: 45))
        visible(app, details)
        details.tap()
        let mutation = app.buttons[control]
        XCTAssertTrue(mutation.waitForExistence(timeout: 45))
        mutation.tap()
        let more = app.buttons["Show more, Estimate EST-8101, item 1"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        visible(app, more)
        more.tap()
        let drawer = app.navigationBars["Description"]
        XCTAssertTrue(drawer.waitForExistence(timeout: 5))
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: drawer)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 30), .completed)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Final sample detail: return the area to its original condition.")).firstMatch.exists)
        if control == "Replace sample revision shortly" {
            XCTAssertTrue(app.staticTexts["Updated sample revision scope"].waitForExistence(timeout: 10))
        }
    }
    func testPreselectionDetailsAndDescriptionCloseOnSessionLoss() {
        let app = open(["--paper-preview-handoff-long-description", "--paper-preview-handoff-slow-invalidation"])
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 45))
        thorbisShowCustomerDoor(app).tap()
        let details = app.buttons["handoff-details-00000000-0000-4000-8000-000000008101"]
        XCTAssertTrue(details.waitForExistence(timeout: 45))
        toggleSampleControls(app)
        app.buttons["End sample session shortly"].tap()
        toggleSampleControls(app)
        visible(app, details)
        details.tap()
        let more = app.buttons["Show more, Estimate EST-8101, item 1"]
        XCTAssertTrue(more.waitForExistence(timeout: 45))
        visible(app, more)
        more.tap()
        XCTAssertTrue(app.navigationBars["Description"].waitForExistence(timeout: 5))
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.navigationBars["Description"])
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 30), .completed)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Final sample detail: return the area to its original condition.")).firstMatch.exists)
    }
    func testSelectedEstimateLongDescriptionOpensReadOnlyAndReturnsToReview() {
        let app = open(["--paper-preview-handoff-long-description", "--paper-preview-handoff-hide-controls"])
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 10))
        thorbisShowCustomerDoor(app).tap()
        let first = app.buttons["handoff-select-00000000-0000-4000-8000-000000008101"]
        XCTAssertTrue(first.waitForExistence(timeout: customerViewFirstEstimate))
        selectEstimate(app, first)
        thorbisStableButton(app, "handoff-review-selected").tap()
        XCTAssertTrue(app.buttons["Continue to signatures"].waitForExistence(timeout: 10))
        let more = app.buttons["Show more, Estimate 1, EST-8101, item 1"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        visible(app, more)
        more.tap()
        XCTAssertTrue(app.navigationBars["Description"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Final sample detail: return the area to its original condition.")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.textViews.firstMatch.exists, "Customer description is read-only")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Continue to signatures"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "$190.00")).firstMatch.exists)
    }

    func testSelectedReviewDescriptionClosesWhenSessionIsRetired() {
        let app = open(["--paper-preview-handoff-long-description", "--paper-preview-handoff-slow-invalidation"])
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 10))
        thorbisShowCustomerDoor(app).tap()
        let first = app.buttons["handoff-select-00000000-0000-4000-8000-000000008101"]
        XCTAssertTrue(first.waitForExistence(timeout: customerViewFirstEstimate))
        selectEstimate(app, first)
        toggleSampleControls(app)
        app.buttons["End sample session shortly"].tap()
        toggleSampleControls(app)
        thorbisStableButton(app, "handoff-review-selected").tap()
        XCTAssertTrue(app.buttons["Continue to signatures"].waitForExistence(timeout: 10))
        let more = app.buttons["Show more, Estimate 1, EST-8101, item 1"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        visible(app, more)
        more.tap()
        XCTAssertTrue(app.navigationBars["Description"].waitForExistence(timeout: 5))
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.navigationBars["Description"])
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 30), .completed)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Final sample detail: return the area to its original condition.")).firstMatch.exists)
    }

    func testSelectedReviewDescriptionClosesWhenAPIGenerationIsRetired() {
        let app = open(["--paper-preview-handoff-long-description", "--paper-preview-handoff-retire-api"])
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 10)); thorbisShowCustomerDoor(app).tap()
        let first = app.buttons["handoff-select-00000000-0000-4000-8000-000000008101"]
        XCTAssertTrue(first.waitForExistence(timeout: customerViewFirstEstimate)); selectEstimate(app, first)
        toggleSampleControls(app)
        XCTAssertTrue(app.buttons["Retire sample API shortly"].waitForExistence(timeout: 5))
        app.buttons["Retire sample API shortly"].tap()
        toggleSampleControls(app)
        thorbisStableButton(app, "handoff-review-selected").tap()
        XCTAssertTrue(app.buttons["Continue to signatures"].waitForExistence(timeout: 10))
        let more = app.buttons["Show more, Estimate 1, EST-8101, item 1"]
        XCTAssertTrue(more.waitForExistence(timeout: 5)); visible(app, more); more.tap()
        XCTAssertTrue(app.navigationBars["Description"].waitForExistence(timeout: 5))
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.navigationBars["Description"])
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 30), .completed)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Final sample detail: return the area to its original condition.")).firstMatch.exists)
    }

    func testSelectedPackageDescriptionCanBeReadDuringCombinedReview() {
        let app = open(["--paper-preview-handoff-long-description", "--paper-preview-handoff-options", "--paper-preview-handoff-hide-controls"])
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 10))
        thorbisShowCustomerDoor(app).tap()
        let first = app.buttons["handoff-select-00000000-0000-4000-8000-000000008101"]
        XCTAssertTrue(first.waitForExistence(timeout: customerViewFirstEstimate))
        selectEstimate(app, first)
        let package = app.buttons["handoff-option-00000000-0000-4000-8000-000000008101-00000000-0000-4000-8000-000000008201"]
        XCTAssertTrue(package.waitForExistence(timeout: 5))
        let selectionMore = app.buttons["Show more, Estimate 1, EST-8101, package 1"]
        XCTAssertTrue(selectionMore.waitForExistence(timeout: 5)); visible(app, selectionMore); selectionMore.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Final package detail: test all equipment and explain the finished work.")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        visible(app, package)
        package.tap()
        thorbisStableButton(app, "handoff-review-selected").tap()
        XCTAssertTrue(app.buttons["Continue to signatures"].waitForExistence(timeout: 10))
        let more = app.buttons["Show more, Estimate 1, EST-8101, package 1"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        visible(app, more)
        more.tap()
        XCTAssertTrue(app.navigationBars["Description"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Final package detail: test all equipment and explain the finished work.")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Continue to signatures"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "$250.00")).firstMatch.exists)
    }

    func testSameTitleEstimatesOpenTheirOwnLongDescriptions() {
        let app = open(["--paper-preview-handoff-long-description", "--paper-preview-handoff-duplicate-titles", "--paper-preview-handoff-hide-controls"])
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 10))
        thorbisShowCustomerDoor(app).tap()
        let first = app.buttons["handoff-select-00000000-0000-4000-8000-000000008101"]
        XCTAssertTrue(first.waitForExistence(timeout: customerViewFirstEstimate)); selectEstimate(app, first)
        let second = app.buttons["handoff-select-00000000-0000-4000-8000-000000008102"]
        XCTAssertTrue(second.waitForExistence(timeout: 10)); selectEstimate(app, second)
        thorbisStableButton(app, "handoff-review-selected").tap()
        XCTAssertTrue(app.buttons["handoff-approve-selected"].waitForExistence(timeout: 15))
        // Before the one signature, each estimate's own full terms open from its row.
        thorbisStableButton(app, "handoff-batch-details-00000000-0000-4000-8000-000000008101").tap()
        let firstMore = app.buttons["Show more, Estimate EST-8101, item 1"]
        XCTAssertTrue(firstMore.waitForExistence(timeout: 10)); visible(app, firstMore); firstMore.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Final sample detail: return the area to its original condition.")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.navigationBars.buttons["Back"].firstMatch.tap()
        XCTAssertTrue(app.buttons["handoff-approve-selected"].waitForExistence(timeout: 10))
        thorbisStableButton(app, "handoff-batch-details-00000000-0000-4000-8000-000000008102").tap()
        let secondMore = app.buttons["Show more, Estimate EST-8102, item 1"]
        XCTAssertTrue(secondMore.waitForExistence(timeout: 10)); visible(app, secondMore); secondMore.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Final second estimate detail: verify the separate work.")).firstMatch.waitForExistence(timeout: 5))
    }

    func testLongReviewDescriptionRemainsReadableAtLargestText() {
        let app = open(["--paper-preview-handoff-long-description", "--paper-preview-handoff-hide-controls",
                        "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        // Largest text, two windows: one existence check took 9 s on CI. Every step waits as long
        // as testEstimateBrowseKeepsLongDescriptionReadOnlyAndEdgeBackWorks does for the same
        // hierarchy: 30 s for each control, 10 s for the description.
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 30)); thorbisShowCustomerDoor(app).tap()
        let first = app.buttons["handoff-select-00000000-0000-4000-8000-000000008101"]
        XCTAssertTrue(first.waitForExistence(timeout: customerViewFirstEstimate)); selectEstimate(app, first)
        thorbisStableButton(app, "handoff-review-selected").tap()
        XCTAssertTrue(app.buttons["Continue to signatures"].waitForExistence(timeout: 30))
        let more = app.buttons["Show more, Estimate 1, EST-8101, item 1"]
        XCTAssertTrue(more.waitForExistence(timeout: 30)); visible(app, more); more.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Final sample detail: return the area to its original condition.")).firstMatch.waitForExistence(timeout: 10))
    }

    func testTwoSameTitleEstimatesApproveWithOneSignatureInOneProtectedHandoff() throws {
        let app = open(["--paper-preview-handoff-duplicate-titles", "--paper-preview-handoff-hide-controls"])
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 10)); thorbisShowCustomerDoor(app).tap()
        let first = app.buttons["handoff-select-00000000-0000-4000-8000-000000008101"]
        XCTAssertTrue(first.waitForExistence(timeout: customerViewFirstEstimate)); selectEstimate(app, first)
        let second = app.buttons["handoff-select-00000000-0000-4000-8000-000000008102"]
        visible(app, second)
        XCTAssertLessThanOrEqual(second.frame.maxY, app.buttons["Review selected (1)"].frame.minY)
        selectEstimate(app, second)
        XCTAssertTrue(app.buttons["Review selected (2)"].waitForExistence(timeout: 5)); thorbisStableButton(app, "handoff-review-selected").tap()
        // Paper 38C: both rows, the total and one signature box before anything is signed.
        XCTAssertTrue(app.buttons["handoff-approve-selected"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["handoff-approve-selected"].label.contains("Approve 2"))
        XCTAssertTrue(app.descendants(matching: .any)["handoff-batch-row-00000000-0000-4000-8000-000000008101"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["handoff-batch-row-00000000-0000-4000-8000-000000008102"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["handoff-batch-totals"].exists)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "customer-estimate-signature-pad").count, 1)
        capture(app, "Both same-title estimates with one signature box")
        try approveTogether(app)
        XCTAssertTrue(app.buttons["handoff-batch-done"].waitForExistence(timeout: 20))
        for id in ["00000000-0000-4000-8000-000000008101", "00000000-0000-4000-8000-000000008102"] {
            XCTAssertTrue(app.descendants(matching: .any)["handoff-batch-row-\(id)"].label.contains("Approved"))
        }
        let proof = try receipt(app)
        let approvals = try XCTUnwrap(proof["approvals"] as? [[String: Any]])
        XCTAssertEqual(approvals.count, 2)
        XCTAssertEqual(Set(approvals.compactMap { $0["estimateID"] as? String }).count, 2)
        XCTAssertEqual(Set(approvals.compactMap { $0["mediaID"] as? String }).count, 2, "Each estimate keeps its own signature asset")
        XCTAssertEqual(proof["ownerAuthenticationAttempts"] as? Int, 0)
        thorbisAssertStaffPageCovered(app)
        capture(app, "Two approvals from one signature before one technician handback")
        app.buttons["handoff-batch-done"].tap()
        XCTAssertTrue(app.staticTexts["handoff-results-summary"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["handoff-results-summary"].label.contains("2 approved"))
        ownerExit(app).tap()
        waitForStaffDoor(app)
    }
    /// Selects the first two (choosing a package first when asked), opens 38C's signing screen and signs once.
    private func reachSignTogether(_ app: XCUIApplication, optionID: String? = nil, third: Bool = false) {
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 10)); thorbisShowCustomerDoor(app).tap()
        let first = app.buttons["handoff-select-00000000-0000-4000-8000-000000008101"]
        XCTAssertTrue(first.waitForExistence(timeout: customerViewFirstEstimate)); selectEstimate(app, first)
        if let optionID { app.buttons[optionID].tap() }
        let second = app.buttons["handoff-select-00000000-0000-4000-8000-000000008102"]
        visible(app, second); selectEstimate(app, second)
        if third {
            let next = app.buttons["handoff-select-00000000-0000-4000-8000-000000008103"]
            visible(app, next); selectEstimate(app, next)
        }
        let count = third ? 3 : 2
        XCTAssertTrue(app.buttons["Review selected (\(count))"].waitForExistence(timeout: 5)); thorbisStableButton(app, "handoff-review-selected").tap()
        guard app.buttons["handoff-approve-selected"].waitForExistence(timeout: 15) else {
            capture(app, "Signing screen did not open — diagnostic evidence")
            _ = try? receipt(app); XCTFail("The exact selected set must open its one signature"); return
        }
        XCTAssertTrue(app.textFields["Your full name"].exists)
        if optionID != nil {
            // The server's own consent words for the package (not the app's sentence) are on screen before any ink.
            XCTAssertEqual(app.descendants(matching: .any)["customer-estimate-signature-pad"].value as? String, "Signature required")
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "my typed name is my electronic signature")).firstMatch.exists)
        }
        draw(app)
    }
    private func approveTogether(_ app: XCUIApplication) throws {
        if app.descendants(matching: .any)["customer-estimate-signature-pad"].value as? String != "Signature entered" { draw(app) }
        thorbisStableButton(app, "handoff-approve-selected").tap()
    }
    private func waitForBatchStop(_ app: XCUIApplication) -> XCUIElement {
        let summary = app.descendants(matching: .any)["handoff-batch-summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 20), "A stopped run must say what was and wasn't approved")
        return summary
    }
    func testChangingThirdEstimateDoesNotStrandTheExactUnknownRetry() throws {
        let app = open(["--paper-preview-handoff-third-sent", "--paper-preview-handoff-fail-before-second", "--paper-preview-handoff-hide-controls"])
        reachSignTogether(app); try approveTogether(app)
        XCTAssertTrue(waitForBatchStop(app).label.contains("1 of 2 approved"))
        let before = try receipt(app)
        app.buttons["Back to estimates"].tap()
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
        // The bar takes the estimate's title as the push starts, while the list's own "Retry exact
        // approval" is still on screen. The list leaves the tree once the estimate's page is in place.
        _ = app.scrollViews["job-estimate-handoff"].waitForNonExistence(timeout: 10)
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
    func testSecondFailureShowsWhichApprovedAndRetryApprovesOnlyTheRest() throws {
        let app = open(["--paper-preview-handoff-third-sent", "--paper-preview-handoff-fail-before-second", "--paper-preview-handoff-hide-controls"])
        reachSignTogether(app, third: true); try approveTogether(app)
        let summary = waitForBatchStop(app)
        XCTAssertTrue(summary.label.contains("1 of 3 approved"), summary.label)
        let rowA = app.descendants(matching: .any)["handoff-batch-row-00000000-0000-4000-8000-000000008101"]
        let rowB = app.descendants(matching: .any)["handoff-batch-row-00000000-0000-4000-8000-000000008102"]
        let rowC = app.descendants(matching: .any)["handoff-batch-row-00000000-0000-4000-8000-000000008103"]
        XCTAssertTrue(rowA.label.contains("Approved"))
        XCTAssertFalse(rowB.label.contains("· Approved"))
        XCTAssertTrue(rowC.label.contains("Not approved yet"))
        let before = try receipt(app), old = try XCTUnwrap(before["approvals"] as? [[String: Any]])
        XCTAssertEqual(old.count, 2, "The third is never attempted after the second stops")
        XCTAssertEqual(old.filter { $0["estimateID"] as? String == "00000000-0000-4000-8000-000000008103" }.count, 0)
        capture(app, "Second estimate stopped: first approved, third not attempted")
        thorbisStableButton(app, "handoff-batch-retry").tap()
        XCTAssertTrue(app.buttons["handoff-batch-done"].waitForExistence(timeout: 25))
        let after = try receipt(app), new = try XCTUnwrap(after["approvals"] as? [[String: Any]])
        XCTAssertEqual(new.filter { $0["estimateID"] as? String == "00000000-0000-4000-8000-000000008101" }.count, 1, "The approved estimate is never sent again")
        XCTAssertEqual(new.filter { $0["estimateID"] as? String == "00000000-0000-4000-8000-000000008103" }.count, 1)
        XCTAssertTrue(NSDictionary(dictionary: old[1]["body"] as! [String: Any]).isEqual(to: new[2]["body"] as! [String: Any]), "The unconfirmed one is resent exactly")
        XCTAssertEqual(Set(new.compactMap { $0["mediaID"] as? String }).count, 3)
        capture(app, "Retry approved only the remaining estimates")
    }
    func testLeavingAfterAnInterruptedRunForgetsTheUnsentSignature() throws {
        let app = open()
        reachSignTogether(app)
        toggleSampleControls(app); app.buttons["Interrupt next signature upload"].tap(); toggleSampleControls(app)
        try approveTogether(app)
        XCTAssertTrue(waitForBatchStop(app).label.contains("0 of 2 approved"))
        XCTAssertEqual((try receipt(app)["approvals"] as? [[String: Any]])?.count, 0)
        app.buttons["Back to estimates"].tap()
        thorbisStableButton(app, "handoff-review-selected").tap()
        let pad = app.descendants(matching: .any)["customer-estimate-signature-pad"]
        XCTAssertTrue(pad.waitForExistence(timeout: 15))
        XCTAssertEqual(pad.value as? String, "Signature required", "Ink is never reused after leaving the signing screen")
        try approveTogether(app)
        XCTAssertTrue(app.buttons["handoff-batch-done"].waitForExistence(timeout: 25))
        XCTAssertEqual((try receipt(app)["approvals"] as? [[String: Any]])?.count, 2)
    }
    func testEarlierFrozenUnsentSignatureIsReplacedByTheOneSignature() throws {
        let app = open()
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 10)); thorbisShowCustomerDoor(app).tap()
        let first = app.buttons["handoff-select-00000000-0000-4000-8000-000000008101"]
        XCTAssertTrue(first.waitForExistence(timeout: customerViewFirstEstimate)); selectEstimate(app, first)
        thorbisStableButton(app, "handoff-review-selected").tap()
        XCTAssertTrue(app.buttons["Continue to signatures"].waitForExistence(timeout: 10)); thorbisStableButton(app, "handoff-continue-signatures").tap()
        XCTAssertTrue(app.textFields["Your full name"].waitForExistence(timeout: 10)); draw(app)
        toggleSampleControls(app); app.buttons["Interrupt next signature upload"].tap(); toggleSampleControls(app)
        thorbisStableButton(app, "handoff-submit-approval").tap()
        XCTAssertTrue(app.buttons["Try again"].waitForExistence(timeout: 15), "The single approval froze its ink, then stopped before sending")
        XCTAssertEqual((try receipt(app)["registrationClientIDs"] as? [String])?.count, 1)
        app.buttons["Back to selected work"].tap(); app.buttons["Back to estimates"].tap()
        let second = app.buttons["handoff-select-00000000-0000-4000-8000-000000008102"]
        visible(app, second); selectEstimate(app, second)
        thorbisStableButton(app, "handoff-review-selected").tap()
        XCTAssertTrue(app.buttons["handoff-approve-selected"].waitForExistence(timeout: 15))
        draw(app); try approveTogether(app)
        XCTAssertTrue(app.buttons["handoff-batch-done"].waitForExistence(timeout: 25))
        let proof = try receipt(app)
        XCTAssertEqual((proof["approvals"] as? [[String: Any]])?.count, 2)
        XCTAssertEqual((proof["registrationClientIDs"] as? [String])?.count, 3, "The first estimate is sent with the new signature's own asset, never the earlier frozen one")
        XCTAssertEqual((proof["confirmedMediaIDs"] as? [String])?.count, 2)
    }
    func testLeavingDuringARunSendsNothingAfterwards() throws {
        let app = open(["--paper-preview-handoff-slow-after-first-approval", "--paper-preview-handoff-hide-controls"])
        reachSignTogether(app); try approveTogether(app)
        let firstApproved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Approved"),
                                                      object: app.descendants(matching: .any)["handoff-batch-row-00000000-0000-4000-8000-000000008101"])
        XCTAssertEqual(XCTWaiter.wait(for: [firstApproved], timeout: 20), .completed)
        // The second estimate's checks are now waiting on a slow read: the technician takes the device back.
        ownerExit(app).tap(); waitForStaffDoor(app)
        // The fixture holds that read 20 s after the first approval; wait long enough for it to land.
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "Let the slow read land")], timeout: 20)
        thorbisShowCustomerDoor(app).tap()
        XCTAssertTrue(app.navigationBars["Estimates"].waitForExistence(timeout: customerViewFirstEstimate))
        let proof = try receipt(app)
        let approvals = try XCTUnwrap(proof["approvals"] as? [[String: Any]])
        XCTAssertEqual(approvals.compactMap { $0["estimateID"] as? String }, ["00000000-0000-4000-8000-000000008101"], "Nothing is sent after leaving")
        XCTAssertEqual((proof["registrationClientIDs"] as? [String])?.count, 1, "No signature upload after leaving")
    }
    func testDoubleTapApprovesEachEstimateOnce() throws {
        let app = open(["--paper-preview-handoff-hide-controls"])
        reachSignTogether(app)
        thorbisStableButton(app, "handoff-approve-selected").doubleTap()
        XCTAssertTrue(app.buttons["handoff-batch-done"].waitForExistence(timeout: 25))
        let proof = try receipt(app)
        let ids = try XCTUnwrap(proof["approvals"] as? [[String: Any]]).compactMap { $0["estimateID"] as? String }
        XCTAssertEqual(ids.sorted(), ["00000000-0000-4000-8000-000000008101", "00000000-0000-4000-8000-000000008102"])
        XCTAssertEqual((proof["registrationClientIDs"] as? [String])?.count, 2)
    }
    func testPackageChangedAfterFailedLinkIsRefused() throws {
        let app = open(["--paper-preview-handoff-options", "--paper-preview-handoff-receipt"])
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 10)); thorbisShowCustomerDoor(app).tap()
        let first = app.buttons["handoff-select-00000000-0000-4000-8000-000000008101"]
        XCTAssertTrue(first.waitForExistence(timeout: customerViewFirstEstimate)); selectEstimate(app, first)
        let package = app.buttons["handoff-option-00000000-0000-4000-8000-000000008101-00000000-0000-4000-8000-000000008201"]
        visible(app, package); package.tap()
        thorbisStableButton(app, "handoff-review-selected").tap()
        XCTAssertTrue(app.buttons["Continue to signatures"].waitForExistence(timeout: 10))
        // The checkpoint opens its link on arrival; that link fails.
        toggleSampleControls(app); app.buttons["Fail next approval link"].tap(); toggleSampleControls(app)
        thorbisStableButton(app, "handoff-continue-signatures").tap()
        // The link fails, so the screen stays on the review, where the package can be changed.
        let change = app.buttons["Change option"]
        let shown = change.waitForExistence(timeout: 15)
        capture(app, "After the failed link")
        XCTAssertTrue(shown); change.tap()
        let other = app.buttons["Choose Other package"]
        XCTAssertTrue(other.waitForExistence(timeout: 10)); other.tap()
        let review = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Review Other package")).firstMatch
        XCTAssertTrue(review.waitForExistence(timeout: 10)); review.tap()
        thorbisStableButton(app, "customer-estimate-approve").tap()
        XCTAssertTrue(app.textFields["Your full name"].waitForExistence(timeout: 15)); draw(app)
        thorbisStableButton(app, "handoff-submit-approval").tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "isn't the one you reviewed")).firstMatch.waitForExistence(timeout: 15))
        XCTAssertEqual((try receipt(app)["approvals"] as? [[String: Any]])?.count, 0, "Another package than the one on screen is never sent")
        // Nothing sticks: the reviewed package is back on screen and approves normally.
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "$250.00")).firstMatch.waitForExistence(timeout: 10))
        thorbisStableButton(app, "customer-estimate-approve").tap()
        XCTAssertTrue(app.textFields["Your full name"].waitForExistence(timeout: 15)); draw(app)
        thorbisStableButton(app, "handoff-submit-approval").tap()
        XCTAssertTrue(app.buttons["See approvals"].waitForExistence(timeout: 20))
        let approvals = try XCTUnwrap(try receipt(app)["approvals"] as? [[String: Any]])
        XCTAssertEqual(approvals.count, 1)
        XCTAssertEqual((approvals.first?["body"] as? [String: Any])?["optionId"] as? String, "00000000-0000-4000-8000-000000008201")
    }
    func testLeavingByNavBackDuringASendLeavesItVisibleAndSendsNothingMore() throws {
        let app = open(["--paper-preview-handoff-slow-first-approval-post", "--paper-preview-handoff-hide-controls"])
        reachSignTogether(app); try approveTogether(app)
        // The first approval is on its way (its answer is slow): the customer goes Back in the bar.
        // The running commit has no identifier; the first estimate's own row says it is being approved.
        let firstRow = app.descendants(matching: .any)["handoff-batch-row-00000000-0000-4000-8000-000000008101"]
        let inFlight = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Approving"), object: firstRow)
        XCTAssertEqual(XCTWaiter.wait(for: [inFlight], timeout: 5), .completed, "The first approval must be running")
        var sent = false
        for _ in 0..<20 where !sent {
            sent = ((try? receipt(app))?["approvals"] as? [[String: Any]])?.count == 1
            if !sent { _ = XCTWaiter.wait(for: [XCTestExpectation(description: "Wait for the approval to go out")], timeout: 0.5) }
        }
        XCTAssertTrue(sent, "The first approval must be in flight before leaving")
        XCTAssertTrue(firstRow.label.contains("Approving"), "The first approval's answer must not have landed before leaving")
        app.navigationBars.buttons["Back"].firstMatch.tap()
        let again = app.buttons["customer-view-approve-estimates"]
        XCTAssertTrue(again.waitForExistence(timeout: 15))
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "Let the slow answer land")], timeout: 9)
        again.tap()
        let summary = app.staticTexts["handoff-results-summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 15), "A sent approval must end in a visible state")
        XCTAssertTrue(summary.label.contains("needs confirmation") || summary.label.contains("1 approved"), summary.label)
        XCTAssertFalse(app.buttons["handoff-select-00000000-0000-4000-8000-000000008101"].exists, "Never offered for a fresh blind resend")
        let proof = try receipt(app)
        let posts = (proof["requests"] as? [[String: String]] ?? []).filter { $0["method"] == "POST" && ($0["path"] ?? "").hasSuffix("/approve") }
        XCTAssertEqual(posts.map { $0["path"] ?? "" }, ["/v1/estimates/00000000-0000-4000-8000-000000008101/approve"], "Nothing is sent for estimate 2 after leaving")
        // The existing check confirms it without sending again.
        if summary.label.contains("needs confirmation") {
            app.buttons["Check approval"].firstMatch.tap()
            let resolved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "1 approved"), object: summary)
            XCTAssertEqual(XCTWaiter.wait(for: [resolved], timeout: 15), .completed)
        }
        XCTAssertEqual((try receipt(app)["approvals"] as? [[String: Any]])?.count, 1)
    }
    /// BYR-1844: the first approval's answer is held until Back is tapped, so it lands during the slide.
    /// The run ended at the tap: no signature is registered and nothing is approved for estimate 2 after it.
    func testAnswerLandingDuringTheBackSlideSendsNothingMore() throws {
        let app = open(["--paper-preview-handoff-hold-first-approval-post", "--paper-preview-handoff-hide-controls"])
        reachSignTogether(app); try approveTogether(app)
        let firstRow = app.descendants(matching: .any)["handoff-batch-row-00000000-0000-4000-8000-000000008101"]
        let inFlight = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Approving"), object: firstRow)
        XCTAssertEqual(XCTWaiter.wait(for: [inFlight], timeout: 5), .completed, "The first approval must be running")
        var sent = false
        for _ in 0..<20 where !sent {
            sent = ((try? receipt(app))?["approvals"] as? [[String: Any]])?.count == 1
            if !sent { _ = XCTWaiter.wait(for: [XCTestExpectation(description: "Wait for the approval to go out")], timeout: 0.5) }
        }
        XCTAssertTrue(sent, "The first approval must be in flight before leaving")
        XCTAssertTrue(firstRow.label.contains("Approving"), "The held answer must not have landed before leaving")
        app.navigationBars.buttons["Back"].firstMatch.tap()
        let again = app.buttons["customer-view-approve-estimates"]
        XCTAssertTrue(again.waitForExistence(timeout: 15))
        let requests = try receipt(app)["requests"] as? [[String: String]] ?? []
        let released = try XCTUnwrap(requests.firstIndex { $0["method"] == "RELEASE" }, "The Back tap must let the held answer go")
        XCTAssertEqual(requests[released]["query"], "run-stopped", "Back must stop the run before the held answer lands")
        let after = requests[(released + 1)...].filter {
            $0["method"] == "POST" && (($0["path"] ?? "").hasSuffix("/media") || ($0["path"] ?? "").hasSuffix("/approve"))
        }
        XCTAssertEqual(after.map { $0["path"] ?? "" }, [], "No signature registration and no approval after Back")
        again.tap()
        let summary = app.staticTexts["handoff-results-summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 15), "A sent approval must end in a visible state")
        XCTAssertTrue(summary.label.contains("1 approved") || summary.label.contains("needs confirmation"), summary.label)
        XCTAssertFalse(app.buttons["handoff-select-00000000-0000-4000-8000-000000008101"].exists, "Never offered for a fresh blind resend")
        let proof = try receipt(app)
        let posts = (proof["requests"] as? [[String: String]] ?? []).filter { $0["method"] == "POST" && ($0["path"] ?? "").hasSuffix("/approve") }
        XCTAssertEqual(posts.map { $0["path"] ?? "" }, ["/v1/estimates/00000000-0000-4000-8000-000000008101/approve"])
        XCTAssertEqual((proof["registrationClientIDs"] as? [String])?.count, 1, "Only the first estimate's signature was registered")
        XCTAssertEqual((proof["approvals"] as? [[String: Any]])?.count, 1)
    }
    func testOneSignatureAtLargestTextKeepsShortCommit() throws {
        let app = open(["--paper-preview-handoff-hide-controls", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        reachSignTogether(app)
        let commit = app.buttons["handoff-approve-selected"]
        XCTAssertLessThan(commit.frame.height, 120, "The commit stays one short line at the largest size")
        capture(app, "One signature for two estimates, largest text")
        try approveTogether(app)
        XCTAssertTrue(app.buttons["handoff-batch-done"].waitForExistence(timeout: 25))
        XCTAssertEqual((try receipt(app)["approvals"] as? [[String: Any]])?.count, 2)
    }
    func testCommitSurfaceRespondsToTapAwayFromTheTitle() {
        let app = open(["--paper-preview-handoff-hide-controls"])
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 10)); thorbisShowCustomerDoor(app).tap()
        let select = app.buttons["handoff-select-00000000-0000-4000-8000-000000008101"]
        XCTAssertTrue(select.waitForExistence(timeout: customerViewFirstEstimate)); selectEstimate(app, select)
        let review = app.buttons["Review selected (1)"]
        XCTAssertTrue(review.isEnabled)
        review.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["Continue to signatures"].waitForExistence(timeout: 10), "The whole visible commit surface must respond")
    }
    private func interruptPreparation(_ label: String) throws {
        let app = open()
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 10)); thorbisShowCustomerDoor(app).tap()
        let select = app.buttons["handoff-select-00000000-0000-4000-8000-000000008101"]
        XCTAssertTrue(select.waitForExistence(timeout: customerViewFirstEstimate)); selectEstimate(app, select); thorbisStableButton(app, "handoff-review-selected").tap()
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
    func testDeniedUnlockOnSigningScreenKeepsLockThenHandBackForgetsTheSignature() throws {
        let app = open(["--paper-preview-handoff-denied-unlock"])
        reachSignTogether(app)
        ownerExit(app).tap()
        waitForOwnerAuthentication(app, attempts: 1)
        XCTAssertTrue(app.textFields["Your full name"].exists, "Staff screens stay locked until Technician: unlock succeeds")
        thorbisAssertStaffPageCovered(app)
        XCTAssertEqual(try receipt(app)["ownerAuthenticationAttempts"] as? Int, 1)
        toggleSampleControls(app); app.buttons["Allow sample unlock"].tap(); toggleSampleControls(app)
        ownerExit(app).tap(); waitForStaffDoor(app)
        thorbisShowCustomerDoor(app).tap()
        XCTAssertTrue(app.navigationBars["Estimates"].waitForExistence(timeout: customerViewFirstEstimate))
        XCTAssertEqual(try receipt(app)["ownerAuthenticationAttempts"] as? Int, 2)
        XCTAssertEqual((try receipt(app)["approvals"] as? [[String: Any]])?.count, 0, "Nothing is approved before the customer commits")
        let first = app.buttons["handoff-select-00000000-0000-4000-8000-000000008101"]
        XCTAssertTrue(first.waitForExistence(timeout: customerViewFirstEstimate)); selectEstimate(app, first)
        let second = app.buttons["handoff-select-00000000-0000-4000-8000-000000008102"]
        visible(app, second); selectEstimate(app, second)
        thorbisStableButton(app, "handoff-review-selected").tap()
        let pad = app.descendants(matching: .any)["customer-estimate-signature-pad"]
        XCTAssertTrue(pad.waitForExistence(timeout: 15))
        XCTAssertEqual(pad.value as? String, "Signature required", "The earlier signature is never reused after a hand-back")
        capture(app, "Authenticated exit forgot the captured signature")
    }
    func testProductionLookTwoSignaturesAndCompletedCardsStayClearWithoutDiagnosticControls() {
        let app = open(["--paper-preview-handoff-hide-controls", "--paper-preview-handoff-duplicate-titles"])
        reachSignTogether(app)
        capture(app, "Production layout one signature for two estimates")
        try? approveTogether(app)
        XCTAssertTrue(app.buttons["handoff-batch-done"].waitForExistence(timeout: 20))
        capture(app, "Production layout both approved")
        app.buttons["handoff-batch-done"].tap()
        XCTAssertTrue(app.staticTexts["handoff-results-summary"].waitForExistence(timeout: 10))
        capture(app, "Production layout two completed estimates and one handback")
        ownerExit(app).tap(); waitForStaffDoor(app)
    }
    func testPackageChoiceKeepsItsCanonicalConsentWhileAnotherEstimateApprovesIndependently() throws {
        let app = open(["--paper-preview-handoff-options", "--paper-preview-handoff-public-patch-no-acceptance", "--paper-preview-handoff-hide-controls"])
        reachSignTogether(app, optionID: "handoff-option-00000000-0000-4000-8000-000000008101-00000000-0000-4000-8000-000000008201")
        XCTAssertTrue(app.descendants(matching: .any)["handoff-batch-row-00000000-0000-4000-8000-000000008101"].label.contains("$250.00"))
        try approveTogether(app)
        XCTAssertTrue(app.buttons["handoff-batch-done"].waitForExistence(timeout: 20))
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
        reachSignTogether(app); try approveTogether(app)
        let summary = waitForBatchStop(app)
        XCTAssertTrue(summary.label.contains("1 of 2 approved · 1 needs confirmation"), summary.label)
        XCTAssertTrue(app.descendants(matching: .any)["handoff-batch-row-00000000-0000-4000-8000-000000008101"].label.contains("Approved"))
        XCTAssertFalse(app.descendants(matching: .any)["handoff-batch-row-00000000-0000-4000-8000-000000008102"].label.contains("Approved"))
        capture(app, "Lost response stays unconfirmed after first approval")
        // The retry reads first; the lost approval is confirmed without sending it again.
        thorbisStableButton(app, "handoff-batch-retry").tap()
        XCTAssertTrue(app.buttons["handoff-batch-done"].waitForExistence(timeout: 20))
        let proof = try receipt(app)
        XCTAssertEqual((proof["approvals"] as? [[String: Any]])?.count, 2, "Read reconciliation must never resend either approval")
        XCTAssertEqual((proof["confirmedMediaIDs"] as? [String])?.count, 2)
        XCTAssertEqual(proof["ownerAuthenticationAttempts"] as? Int, 0)
        capture(app, "Both approvals reconciled with exactly two original commands")
    }
    func testUnconfirmedRetryRetainsExactSignatureAcrossBackAndDeniedOwnerUnlock() throws {
        let app = open(["--paper-preview-handoff-fail-before-second", "--paper-preview-handoff-denied-unlock", "--paper-preview-handoff-hide-controls"])
        reachSignTogether(app); try approveTogether(app)
        _ = waitForBatchStop(app)
        let before = try receipt(app)
        ownerExit(app).tap()
        waitForOwnerAuthentication(app, attempts: 1)
        XCTAssertTrue(app.buttons["handoff-batch-retry"].exists)
        XCTAssertEqual(try receipt(app)["ownerAuthenticationAttempts"] as? Int, 1, "A visible protected child exit must invoke the real owner boundary, not no-op")
        thorbisAssertStaffPageCovered(app)
        thorbisStableButton(app, "handoff-batch-retry").tap()
        XCTAssertTrue(app.buttons["handoff-batch-done"].waitForExistence(timeout: 20))
        let after = try receipt(app)
        let old = try XCTUnwrap(before["approvals"] as? [[String: Any]]), new = try XCTUnwrap(after["approvals"] as? [[String: Any]])
        XCTAssertEqual(old.count, 2); XCTAssertEqual(new.count, 3)
        XCTAssertEqual(new.filter { $0["estimateID"] as? String == "00000000-0000-4000-8000-000000008101" }.count, 1)
        XCTAssertTrue(NSDictionary(dictionary: old[1]["body"] as! [String: Any]).isEqual(to: new[2]["body"] as! [String: Any]))
        XCTAssertEqual((after["confirmedMediaIDs"] as? [String])?.count, 2, "Retry must not upload replacement ink")
        // The unknown outcome is checked (a live read of that estimate) before anything is sent again.
        let requests = try XCTUnwrap(after["requests"] as? [[String: String]])
        let approvePath = "/v1/estimates/00000000-0000-4000-8000-000000008102/approve"
        let posts = requests.indices.filter { requests[$0]["method"] == "POST" && requests[$0]["path"] == approvePath }
        XCTAssertEqual(posts.count, 2)
        let check = requests.indices.first { $0 > posts[0] && $0 < posts[1] && requests[$0]["method"] == "GET" && requests[$0]["path"] == "/v1/estimates/00000000-0000-4000-8000-000000008102" }
        XCTAssertNotNil(check, "No resend before the check read")
        capture(app, "Only unconfirmed estimate retried with identical signature payload")
    }
    func testLargestTextDarkModeKeepsBothEstimatesAndProtectedNavigationReachable() {
        let app = open(["--paper-preview-handoff-hide-controls", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-thorbis.appearance", "dark"])
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 10)); thorbisShowCustomerDoor(app).tap()
        XCTAssertTrue(app.navigationBars["Estimates"].waitForExistence(timeout: customerViewFirstEstimate))
        _ = ownerExit(app)
        capture(app, "Largest text dark estimate overview top")
        let first = app.buttons["handoff-select-00000000-0000-4000-8000-000000008101"]
        XCTAssertTrue(first.waitForExistence(timeout: customerViewFirstEstimate))
        visible(app, first); selectEstimate(app, first)
        let second = app.buttons["handoff-select-00000000-0000-4000-8000-000000008102"]
        visible(app, second); selectEstimate(app, second)
        XCTAssertTrue(app.buttons["Review selected (2)"].waitForExistence(timeout: 5))
        capture(app, "Largest text dark second estimate and review action")
        thorbisStableButton(app, "handoff-review-selected").tap()
        XCTAssertTrue(app.buttons["handoff-approve-selected"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.textFields["Your full name"].waitForExistence(timeout: 10))
        _ = ownerExit(app)
        capture(app, "Largest text dark one signature and protected exit")
        let back = app.buttons.matching(NSPredicate(format: "label == %@", "Back to estimates")).allElementsBoundByIndex.first { $0.isHittable }
        if back == nil { for _ in 0..<6 { app.swipeUp() } }
        let backAgain = back ?? app.buttons.matching(NSPredicate(format: "label == %@", "Back to estimates")).allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(backAgain); backAgain?.tap()
        XCTAssertTrue(app.buttons["Review selected (2)"].waitForExistence(timeout: 10))
        ownerExit(app).tap()
        // At this size the door scrolls with the page, and both estimates sit above it again.
        let door = thorbisShowCustomerDoor(app)
        XCTAssertTrue(door.waitForExistence(timeout: 10))
        for _ in 0..<6 where !door.isHittable { app.swipeUp() }
        XCTAssertTrue(door.isHittable)
    }
    func testSelectedReviewShowsCanonicalDiscountBreakdown() {
        let app = open(["--paper-preview-handoff-discount", "--paper-preview-handoff-hide-controls"])
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 10)); thorbisShowCustomerDoor(app).tap()
        let select = app.buttons["handoff-select-00000000-0000-4000-8000-000000008101"]
        XCTAssertTrue(select.waitForExistence(timeout: customerViewFirstEstimate)); selectEstimate(app, select); thorbisStableButton(app, "handoff-review-selected").tap()
        XCTAssertTrue(app.buttons["Continue to signatures"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Discounts and credits"].exists)
        XCTAssertTrue(app.staticTexts["-$30.00"].firstMatch.exists)
        capture(app, "Selected estimate preserves canonical discount and total")
    }
    func testApprovedSameTitleEstimateStaysVisibleBesideSentZeroWithoutReapproval() {
        let app = open(["--paper-preview-handoff-duplicate-titles", "--paper-preview-handoff-mixed", "--paper-preview-handoff-hide-controls"])
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 10)); thorbisShowCustomerDoor(app).tap()
        let select = app.buttons["handoff-select-00000000-0000-4000-8000-000000008102"]
        XCTAssertTrue(select.waitForExistence(timeout: customerViewFirstEstimate))
        XCTAssertFalse(app.buttons["handoff-select-00000000-0000-4000-8000-000000008101"].exists)
        // The approved one has no verified receipt, so it offers a price retry and shows no amount.
        XCTAssertTrue(app.buttons["handoff-retry-price-00000000-0000-4000-8000-000000008101"].waitForExistence(timeout: 15))
        XCTAssertTrue((select.value as? String)?.contains("$0.00") == true, select.value as? String ?? "")
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
        XCTAssertTrue(app.navigationBars["Estimates"].waitForExistence(timeout: customerViewFirstEstimate))
        toggleSampleControls(app); app.buttons["End sample session shortly"].tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "signedOut"), object: app.staticTexts["handoff-sample-session"])
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 12), .completed)
        XCTAssertTrue(app.navigationBars["Estimates"].exists)
        XCTAssertFalse(app.staticTexts["Welcome back"].isHittable)
        ownerExit(app).tap()
        waitForOwnerAuthentication(app, attempts: 1)
        XCTAssertTrue(app.navigationBars["Estimates"].exists, "Denied owner authentication must never reveal login or staff content")
        XCTAssertFalse(app.staticTexts["Welcome back"].isHittable)
        capture(app, "Actual signed-out branch stays protected after denied owner authentication")
        app.buttons["Allow sample unlock"].tap(); ownerExit(app).tap()
        waitHittable(app.staticTexts["Welcome back"])
    }
    func testActualWorkspaceSelectionBranchKeepsProtectedOwner() {
        let app = open()
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 10)); thorbisShowCustomerDoor(app).tap()
        XCTAssertTrue(app.navigationBars["Estimates"].waitForExistence(timeout: customerViewFirstEstimate))
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
    /// A foreground or reconnect check that finds the same authority leaves Customer view as it was:
    /// the customer's selection stays and they can still review it (BYR-1833).
    func testIdenticalSessionCheckKeepsCustomerViewAndSelection() {
        let app = open()
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 10)); thorbisShowCustomerDoor(app).tap()
        let first = app.buttons["handoff-select-00000000-0000-4000-8000-000000008101"]
        XCTAssertTrue(first.waitForExistence(timeout: customerViewFirstEstimate)); selectEstimate(app, first)
        toggleSampleControls(app)
        let checks = app.staticTexts["handoff-sample-checked"]
        XCTAssertTrue(checks.waitForExistence(timeout: 5))
        let before = (checks.value as? String) ?? ""
        app.buttons["Check sample session shortly"].tap()
        let answered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", before), object: checks)
        XCTAssertEqual(XCTWaiter.wait(for: [answered], timeout: 15), .completed, "The sample check must be answered")
        XCTAssertFalse(app.staticTexts["This workspace or your access changed. Your technician needs to unlock and reopen the job."].exists,
                       "An identical check must not end Customer view")
        XCTAssertTrue(first.exists)
        XCTAssertTrue((first.value as? String)?.hasPrefix("Selected,") == true, "The customer's selection survives the check")
        XCTAssertTrue(app.buttons["handoff-review-selected"].isEnabled)
        capture(app, "Customer view after an identical session check")
    }
    func testActualWorkspaceBranchRetirementKeepsProtectedOwner() {
        let app = open()
        XCTAssertTrue(thorbisShowCustomerDoor(app).waitForExistence(timeout: 10)); thorbisShowCustomerDoor(app).tap()
        XCTAssertTrue(app.navigationBars["Estimates"].waitForExistence(timeout: customerViewFirstEstimate))
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
        // At accessibility sizes the section row is one pinned chooser (a40f825), not tabs.
        let tabs = app.buttons["job-section-chooser"]
        XCTAssertTrue(tabs.exists)
        XCTAssertTrue(tabs.label.contains("Money"))
        // Paper 23: nothing is pinned under Money at accessibility sizes (the bar scrolls with the
        // content), so the card must fit between the pinned chooser and the screen's bottom.
        for _ in 0..<8 {
            let frame = first.frame
            if first.isHittable && frame.minY >= tabs.frame.maxY && frame.maxY <= app.frame.maxY { break }
            let upward = frame.maxY > app.frame.maxY
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: upward ? 0.7 : 0.4))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: upward ? 0.5 : 0.6))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        XCTAssertTrue(first.isHittable, app.debugDescription)
        XCTAssertGreaterThanOrEqual(first.frame.minY, tabs.frame.maxY)
        XCTAssertLessThanOrEqual(first.frame.maxY, app.frame.maxY)
        capture(app, "Job estimates at largest text")
        // Paper 23: the estimates' customer door is Money › Show estimates, in reach at this size too.
        let present = thorbisShowCustomerDoor(app)
        XCTAssertTrue(present.waitForExistence(timeout: 10))
        XCTAssertTrue(present.isHittable)
        XCTAssertGreaterThanOrEqual(present.frame.height, 44)
    }

    func testLargestTextCanReturnToCustomerPresentationFromInvoices() {
        let app = open(["--paper-preview-handoff-hide-controls", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        // Paper's Money is one page with no jump chips: scroll down to the invoices and back.
        // At accessibility sizes the sections are one chooser, which names the open section.
        let chooser = app.buttons["job-section-chooser"]
        XCTAssertTrue(chooser.waitForExistence(timeout: 30))
        XCTAssertTrue(chooser.label.contains("Money"), chooser.label)
        for _ in 0..<6 { app.swipeUp() }
        // Paper 23: the estimates' customer door is Money › Show estimates, wherever Money is scrolled to.
        let present = thorbisShowCustomerDoor(app)
        XCTAssertTrue(present.waitForExistence(timeout: 30), "The estimate presentation action must stay reachable at large text")
        XCTAssertTrue(present.isHittable)
        present.tap()
        XCTAssertTrue(app.navigationBars["Estimates"].waitForExistence(timeout: 15))
    }

    /// A press that rests on a row of the job's More sheet and then drags must not choose that row
    /// when the finger lifts (Paper 21K's rows; the sheet scrolls when it cannot fit).
    func testScrollingTheJobMenuFromARowDoesNotChooseIt() {
        let app = open(["--paper-preview-handoff-hide-controls"])
        XCTAssertTrue(app.buttons["Add estimate"].waitForExistence(timeout: 30))
        let more = app.buttons["Job actions"]
        XCTAssertTrue(more.waitForExistence(timeout: 30)); more.tap()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Time and profit")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.5, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -220)),
                    withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertFalse(app.staticTexts["Time and profit"].firstMatch.waitForExistence(timeout: 2) && !row.exists,
                       "Scrolling the menu must not open the row under the finger")
        XCTAssertTrue(row.exists, "The menu stays open after a scroll")
        // A plain tap still chooses a row.
        thorbisRevealJobMenuRow(row, in: app)
        row.tap()
        XCTAssertFalse(row.waitForExistence(timeout: 3) && row.isHittable, "The menu closes on a tap")
        XCTAssertTrue(app.staticTexts["Time and profit"].firstMatch.waitForExistence(timeout: 10))
    }

    func testAllEstimatesUseOnePrimaryEntryAndKeepAddVisible() {
        let app = open(["--paper-preview-handoff-hide-controls"])
        XCTAssertTrue(app.buttons["Add estimate"].waitForExistence(timeout: 30))
        capture(app, "Job estimates before entering customer handoff")
        let present = thorbisShowCustomerDoor(app)
        present.tap()
        XCTAssertTrue(app.navigationBars["Estimates"].waitForExistence(timeout: 10))
        // The rows replace the opening skeleton once the job's estimates load, like the tests above.
        XCTAssertTrue(app.buttons["handoff-select-00000000-0000-4000-8000-000000008101"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["handoff-select-00000000-0000-4000-8000-000000008102"].exists)
        let second = app.buttons["handoff-select-00000000-0000-4000-8000-000000008102"]
        let firstPrice = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "$190.00"), object: app.buttons["handoff-select-00000000-0000-4000-8000-000000008101"])
        let secondPrice = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "$320.00"), object: second)
        XCTAssertEqual(XCTWaiter.wait(for: [firstPrice, secondPrice], timeout: 45), .completed, "Both verified prices must load before the cards are measured and read")
        XCTAssertLessThanOrEqual(second.frame.maxY, app.buttons["Review selected (0)"].frame.minY, "Both ordinary cards and prices fit above the primary action")
        let spoken = app.buttons["handoff-select-00000000-0000-4000-8000-000000008101"].value as? String
        XCTAssertTrue(spoken?.contains("Sent") == true)
        XCTAssertTrue(spoken?.contains("$190.00") == true, "Integrated selection must expose price and status to VoiceOver")
        capture(app, "All current-job estimates together")
    }

    func testTechnicianCanPrepareNewEstimateFromPagedJob() {
        let app = open(["--paper-preview-handoff-many-estimates", "--paper-preview-handoff-hide-controls"])
        XCTAssertTrue(app.buttons["job-estimate-00000000-0000-4000-8000-000000008101"].waitForExistence(timeout: 45))
        let add = app.buttons["job-add-estimate"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["job-load-more-estimates"].exists, "The job remains paged before creation is requested")
        add.tap()
        XCTAssertTrue(app.staticTexts["New estimate"].waitForExistence(timeout: 45), "Creation opens only after the scoped complete read")
    }
}

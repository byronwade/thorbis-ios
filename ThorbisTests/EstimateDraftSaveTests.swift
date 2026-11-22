import XCTest
@testable import Thorbis

/// Saving edits to an estimate that is still a draft: the request body the server's draft-edit
/// contract needs, and what each answer means for the person editing.
final class EstimateDraftSaveTests: XCTestCase {
    private func estimate(status: String, revision: Int?, updatedAt: String = "2026-11-20T15:04:05.123Z") -> EstimateRecord {
        let line = FieldLine(id: UUID().uuidString, description: "Capacitor", quantity: 1,
                             unitPrice: FieldMoney(amount: 12_000, currency: "USD"), source: nil)
        return EstimateRecord(id: "00000000-0000-4000-8000-000000000008", organizationId: "o", customerId: "c", createdByUserId: "u",
                              locationId: nil, status: status, currentRevisionNumber: revision, title: "AC repair", lines: [line],
                              options: nil, createdAt: "2026-11-19T00:00:00Z", updatedAt: updatedAt,
                              sentAt: nil, approvedAt: nil, declinedAt: nil)
    }

    private func body(_ request: FieldEstimateReviseRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
    }

    func testNeverSentDraftSendsRevisionZeroAndItsUpdatedAt() throws {
        var state = EstimateRevisionEditorState(estimate: estimate(status: "draft", revision: nil))
        state.title = "AC repair, new capacitor"
        let request = try state.makeRequest(optionsFeatureEnabled: false, canDiscount: false)
        XCTAssertEqual(request.expectedRevisionNumber, 0)
        let json = try body(request)
        XCTAssertEqual(json["expectedRevisionNumber"] as? Int, 0, "Zero is sent as a number, never left out")
        XCTAssertEqual(json["expectedUpdatedAt"] as? String, "2026-11-20T15:04:05.123Z", "The token is the estimate's updatedAt, untouched")
        XCTAssertEqual(json["title"] as? String, "AC repair, new capacitor")
        XCTAssertEqual((json["lines"] as? [Any])?.count, 1)
        XCTAssertNil(json["options"])
    }

    func testRevisedDraftSendsItsRevisionAndUpdatedAt() throws {
        let state = EstimateRevisionEditorState(estimate: estimate(status: "draft", revision: 3, updatedAt: "2026-11-20T09:00:00Z"))
        let json = try body(state.makeRequest(optionsFeatureEnabled: false, canDiscount: false))
        XCTAssertEqual(json["expectedRevisionNumber"] as? Int, 3)
        XCTAssertEqual(json["expectedUpdatedAt"] as? String, "2026-11-20T09:00:00Z")
    }

    func testSentEstimateStillSendsTheTokenTheServerIgnores() throws {
        let state = EstimateRevisionEditorState(estimate: estimate(status: "sent", revision: 2))
        let json = try body(state.makeRequest(optionsFeatureEnabled: false, canDiscount: false))
        XCTAssertEqual(json["expectedRevisionNumber"] as? Int, 2)
        XCTAssertEqual(json["expectedUpdatedAt"] as? String, "2026-11-20T15:04:05.123Z")
    }

    func testRequestWithoutATokenLeavesTheFieldOut() throws {
        let json = try body(FieldEstimateReviseRequest(expectedRevisionNumber: 1, title: "Quote", lines: []))
        XCTAssertFalse(json.keys.contains("expectedUpdatedAt"))
    }

    func testRebaseKeepsTheEditsAndTakesTheLatestToken() throws {
        var state = EstimateRevisionEditorState(estimate: estimate(status: "draft", revision: nil))
        state.title = "My edit"
        XCTAssertTrue(state.rebase(onto: estimate(status: "draft", revision: 1, updatedAt: "2026-11-20T16:00:00Z")))
        XCTAssertEqual(state.title, "My edit")
        let request = try state.makeRequest(optionsFeatureEnabled: false, canDiscount: false)
        XCTAssertEqual(request.expectedRevisionNumber, 1)
        XCTAssertEqual(request.expectedUpdatedAt, "2026-11-20T16:00:00Z")
        // An estimate that was approved meanwhile is not rebased onto: it can't be edited in place.
        var other = EstimateRevisionEditorState(estimate: estimate(status: "draft", revision: nil))
        other.title = "My edit"
        XCTAssertFalse(other.rebase(onto: estimate(status: "approved", revision: 1)))
        XCTAssertEqual(other.estimate.status, "draft")
    }

    private func problem(_ status: Int, code: String? = nil, detail: String? = nil) -> Problem {
        var problem = Problem(title: "Problem", status: status, detail: detail)
        problem.code = code
        return problem
    }

    func testStaleDraftAsksToReload() {
        let failure = EstimateSaveFailure.of(problem(409, code: "stale_draft"), wasDraft: true, sentRevision: 0)
        XCTAssertEqual(failure, .stale)
        XCTAssertEqual(failure.message, "Someone else changed this estimate. Reload it and try again.")
        XCTAssertTrue(failure.offersLatest)
    }

    func testMissingTokenReloadsAndRetries() {
        let failure = EstimateSaveFailure.of(problem(409, code: "draft_token_required"), wasDraft: true, sentRevision: 0)
        XCTAssertEqual(failure, .reloadAndRetry)
        XCTAssertTrue(failure.offersLatest, "If the one retry can't happen, the latest estimate is offered")
    }

    func testForbiddenUsesThePermissionWords() {
        let failure = EstimateSaveFailure.of(problem(403, detail: "estimate.create"), wasDraft: true, sentRevision: 0)
        XCTAssertEqual(failure, .noPermission)
        XCTAssertEqual(failure.message, "You no longer have permission to revise this estimate.")
        XCTAssertFalse(failure.offersLatest)
    }

    func testADiscountOverTheRoleLimitSaysSoInsteadOfLostPermission() {
        var refused = problem(403, detail: "not permitted: estimate.discount (out_of_scope)")
        refused.category = "authorization"
        let failure = EstimateSaveFailure.of(refused, wasDraft: true, sentRevision: 0)
        XCTAssertEqual(failure, .discountOverLimit)
        XCTAssertEqual(failure.message, "That discount is more than your role allows. Lower it, or ask your office.")
        XCTAssertFalse(failure.offersLatest)
    }

    func testEstimatesSwitchedOffForTheWorkspaceSaySo() {
        var off = problem(403, detail: "estimates is not enabled")
        off.category = "feature_unavailable"
        let failure = EstimateSaveFailure.of(off, wasDraft: false, sentRevision: 1)
        XCTAssertEqual(failure, .featureOff)
        XCTAssertEqual(failure.message, "Estimates aren\u{2019}t turned on for this workspace.")
        XCTAssertFalse(failure.offersLatest)
    }

    func testServerWithoutDraftEditsFailsHonestly() {
        // Today's server: a never-sent draft's revision 0 is invalid (400)…
        let neverSent = EstimateSaveFailure.of(problem(400, detail: "expectedRevisionNumber"), wasDraft: true, sentRevision: 0)
        XCTAssertEqual(neverSent, .draftsNotEditableYet)
        XCTAssertEqual(neverSent.message, "This draft can\u{2019}t be changed yet. Send it, then edit it.")
        XCTAssertFalse(neverSent.offersLatest, "Reloading would throw the edits away for nothing")
        // …and a revised draft is answered with a replacement-draft conflict.
        let replaced = EstimateSaveFailure.of(problem(409, detail: "a replacement draft already exists for this estimate revision"),
                                              wasDraft: true, sentRevision: 2)
        XCTAssertEqual(replaced, .draftsNotEditableYet)
    }

    func testOtherAnswersKeepTheirOwnWords() {
        // An approved estimate still needs a change order.
        let approved = problem(409, detail: "an approved estimate requires a change order; it cannot be revised in place")
        let failure = EstimateSaveFailure.of(approved, wasDraft: false, sentRevision: 2)
        XCTAssertEqual(failure, .other(message: approved.localizedDescription, conflict: true))
        XCTAssertTrue(failure.offersLatest)
        // A revision that moved on under a sent estimate is a plain conflict, as before.
        let moved = problem(409, detail: "estimate revision changed: expected 1, current 2")
        XCTAssertEqual(EstimateSaveFailure.of(moved, wasDraft: true, sentRevision: 1), .other(message: moved.localizedDescription, conflict: true))
        // A bad line on a server that does edit drafts is not mistaken for the old limit.
        let invalid = problem(400, detail: "lines: at least one line")
        XCTAssertEqual(EstimateSaveFailure.of(invalid, wasDraft: true, sentRevision: 2), .other(message: invalid.localizedDescription, conflict: false))
        XCTAssertEqual(EstimateSaveFailure.of(invalid, wasDraft: false, sentRevision: 0), .other(message: invalid.localizedDescription, conflict: false))
        let offline = URLError(.notConnectedToInternet)
        XCTAssertEqual(EstimateSaveFailure.of(offline, wasDraft: true, sentRevision: 0), .other(message: offline.localizedDescription, conflict: false))
    }
}

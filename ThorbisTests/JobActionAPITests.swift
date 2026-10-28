import XCTest
@testable import Thorbis

@MainActor
final class JobActionAPITests: XCTestCase {
    private let jobID = "00000000-0000-4000-8000-000000000001"
    private let userID = "00000000-0000-4000-8000-000000000004"
    private let jobJSON = #"{"id":"00000000-0000-4000-8000-000000000001","organizationId":"00000000-0000-4000-8000-000000000002","customerId":"00000000-0000-4000-8000-000000000003","title":"Repair","status":"scheduled","createdAt":"2026-10-26T12:00:00Z","updatedAt":"2026-10-26T12:00:00Z"}"#

    func testCloseoutReadsBlockedRequirementsWithoutInvoiceEvidence() async throws {
        let response = #"{"policy":{"requireNotes":true,"requiredPhotoCount":1,"requiredChecks":[]},"facts":{"noteCount":0,"photoCount":0,"acknowledgedCheckKeys":[],"authorizationTarget":{"id":"00000000-0000-4000-8000-000000000001","organizationId":"00000000-0000-4000-8000-000000000002","customerId":"00000000-0000-4000-8000-000000000003"}},"acknowledged":[],"requirements":[{"requirement":"notes","kind":"notes","outcome":"blocked","detail":"Add a note","nextAction":"add_job_note"}],"unmet":[{"requirement":"notes","kind":"notes","outcome":"blocked","detail":"Add a note","nextAction":"add_job_note"}],"completable":false}"#
        let client = APIClient(session: URLProtocolFixture.session([.init(200, response)]), baseURL: "https://app.thorbis.com")

        let closeout = try await client.fieldCloseout(jobID)

        XCTAssertFalse(closeout.completable)
        XCTAssertEqual(closeout.policy.requiredPhotoCount, 1)
        XCTAssertEqual(closeout.unmet.first?.nextAction, "add_job_note")
        XCTAssertEqual(URLProtocolFixture.recorded.first?.url?.path, "/v1/jobs/\(jobID)/closeout")
    }

    func testCompletionWithUnpaidDispositionSendsExactEvidence() async throws {
        let client = APIClient(session: URLProtocolFixture.session([.init(200, jobJSON)]), baseURL: "https://app.thorbis.com")
        let disposition = FieldUnpaidDisposition(reasonCode: "customer_will_pay_later", reason: "Customer requested Friday", followUpNextAction: "Call Friday")

        _ = try await client.completeFieldJob(jobID, request: .init(unpaidDisposition: disposition))

        let sent = try XCTUnwrap(URLProtocolFixture.recorded.first)
        XCTAssertEqual(sent.url?.path, "/v1/jobs/\(jobID)/complete")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(sent.body)) as? [String: Any])
        let unpaid = try XCTUnwrap(body["unpaidDisposition"] as? [String: String])
        XCTAssertEqual(unpaid["reasonCode"], "customer_will_pay_later")
        XCTAssertEqual(unpaid["followUpNextAction"], "Call Friday")
        XCTAssertNil(body["jobId"])
    }

    func testAssignAndSchedulePreserveExplicitUnassignedAndPointTimePreconditions() async throws {
        let client = APIClient(session: URLProtocolFixture.session([.init(200, jobJSON), .init(200, jobJSON)]), baseURL: "https://app.thorbis.com")

        _ = try await client.assignFieldJob(jobID, request: .init(userId: userID, expected: .unassigned))
        _ = try await client.scheduleFieldJob(jobID, request: .init(scheduledFor: "2026-10-27T13:00:00Z", arrivalWindow: .pointTime, expectedPrior: .unscheduled))

        let sent = URLProtocolFixture.recorded
        let assign = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(sent[0].body)) as? [String: Any])
        XCTAssertEqual(assign["userId"] as? String, userID)
        XCTAssertTrue(assign["expectedAssigneeId"] is NSNull)
        let schedule = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(sent[1].body)) as? [String: Any])
        XCTAssertEqual(schedule["scheduledFor"] as? String, "2026-10-27T13:00:00Z")
        XCTAssertTrue(schedule["arrivalWindowEndsAt"] is NSNull)
        XCTAssertTrue(schedule["expectedPriorScheduledFor"] is NSNull)
    }

    func testFollowUpRequestAndResolutionKeepBookingSeparate() async throws {
        let followUp = #"{"id":"00000000-0000-4000-8000-000000000005","organizationId":"00000000-0000-4000-8000-000000000002","jobId":"00000000-0000-4000-8000-000000000001","kind":"office_scheduling","reason":"Needs return visit","nextAction":"Call customer","ownerUserId":"00000000-0000-4000-8000-000000000004","status":"open","createdByUserId":"00000000-0000-4000-8000-000000000004","createdAt":"2026-10-26T12:00:00Z"}"#
        let client = APIClient(session: URLProtocolFixture.session([.init(201, followUp), .init(200, followUp)]), baseURL: "https://app.thorbis.com")

        let created = try await client.requestFieldFollowUp(jobID, request: .init(kind: .officeScheduling, reason: "Needs return visit", nextAction: "Call customer"))
        _ = try await client.resolveFieldFollowUp(jobID, followUpID: created.id)

        let sent = URLProtocolFixture.recorded
        XCTAssertEqual(sent[0].url?.path, "/v1/jobs/\(jobID)/followups")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(sent[0].body)) as? [String: Any])
        XCTAssertEqual(body["kind"] as? String, "office_scheduling")
        XCTAssertNil(body["requestedFor"])
        XCTAssertEqual(sent[1].url?.path, "/v1/jobs/\(jobID)/followups/\(created.id)/resolve")
    }

    func testCancelAndCheckAcknowledgmentUseTheirDistinctEndpoints() async throws {
        let check = #"{"id":"00000000-0000-4000-8000-000000000006","organizationId":"00000000-0000-4000-8000-000000000002","jobId":"00000000-0000-4000-8000-000000000001","checkKey":"swept_area","acknowledgedByUserId":"00000000-0000-4000-8000-000000000004","acknowledgedAt":"2026-10-26T12:00:00Z"}"#
        let client = APIClient(session: URLProtocolFixture.session([.init(201, check), .init(200, jobJSON)]), baseURL: "https://app.thorbis.com")

        let acknowledged = try await client.acknowledgeFieldCheck(jobID, checkKey: "swept_area")
        _ = try await client.cancelFieldJob(jobID)

        XCTAssertEqual(acknowledged.checkKey, "swept_area")
        let sent = URLProtocolFixture.recorded
        XCTAssertEqual(sent[0].url?.path, "/v1/jobs/\(jobID)/checks")
        XCTAssertEqual(sent[1].url?.path, "/v1/jobs/\(jobID)/cancel")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(sent[0].body)) as? [String: String])
        XCTAssertEqual(body, ["checkKey": "swept_area"])
    }

    func testFollowUpBookingMayReturnOfficeReviewInsteadOfAppointment() async throws {
        let response = #"{"outcome":"office_review_required","decision":{},"officeReview":{"id":"00000000-0000-4000-8000-000000000009","status":"open","reasonCode":"no_capacity","requestedWindow":{"startsAt":"2026-10-27T13:00:00Z","endsAt":"2026-10-27T15:00:00Z"},"timeZone":"America/New_York"}}"#
        let client = APIClient(session: URLProtocolFixture.session([.init(201, response)]), baseURL: "https://app.thorbis.com")
        let followUpID = "00000000-0000-4000-8000-000000000005"
        let intentID = "00000000-0000-4000-8000-00000000000a"
        let request = FieldFollowUpBookingRequest(intentId: intentID,
            requestedWindow: .init(startsAt: "2026-10-27T13:00:00Z", endsAt: "2026-10-27T15:00:00Z"),
            timeZone: "America/New_York", serviceNeed: "Return with valve", requiredTraitIds: [])

        let result = try await client.bookFieldFollowUp(jobID, followUpID: followUpID, request: request)

        XCTAssertEqual(result.outcome, "office_review_required")
        XCTAssertNil(result.appointment)
        XCTAssertEqual(result.officeReview?.status, "open")
        let sent = try XCTUnwrap(URLProtocolFixture.recorded.first)
        XCTAssertEqual(sent.url?.path, "/v1/jobs/\(jobID)/followups/\(followUpID)/book")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(sent.body)) as? [String: Any])
        XCTAssertEqual(body["intentId"] as? String, intentID)
        XCTAssertNil(body["jobId"])
        XCTAssertNil(body["sourceFollowUpIntentId"])
    }

    func testBookingResponseRequiresEvidenceForItsOutcome() throws {
        let decoder = JSONDecoder()
        XCTAssertThrowsError(try decoder.decode(FieldFollowUpBookingResult.self, from: Data(#"{"outcome":"booked"}"#.utf8)))
        XCTAssertThrowsError(try decoder.decode(FieldFollowUpBookingResult.self, from: Data(#"{"outcome":"office_review_required"}"#.utf8)))
        XCTAssertThrowsError(try decoder.decode(FieldFollowUpBookingResult.self, from: Data(#"{"outcome":"unknown","appointment":{}}"#.utf8)))
    }
}

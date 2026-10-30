import XCTest
@testable import Thorbis

@MainActor
final class CallLogTests: XCTestCase {
    private let callID = "00000000-0000-4000-8000-000000009601"
    private let jobID = "00000000-0000-4000-8000-000000002214"

    private var listJSON: String {
        #"{"items":[{"id":"\#(callID)","direction":"inbound","status":"missed","lineId":"l1","callerNumber":"+15555550100","startedAt":"2026-10-30T15:00:00Z","recording":{"status":"none"},"transcriptStatus":"none"},{"id":"00000000-0000-4000-8000-000000009602","direction":"inbound","status":"completed","lineId":"l1","callerName":"Dana Ruiz","jobId":"\#(jobID)","startedAt":"2026-10-30T14:00:00Z","durationSeconds":192,"recording":{"status":"available","contentPath":"/v1/calls/00000000-0000-4000-8000-000000009602/recording"},"summary":{"text":"Leak at the base.","source":"model"},"transcriptStatus":"available"}],"nextCursor":"2026-10-30T14:00:00Z_00000000-0000-4000-8000-000000009602"}"#
    }

    func testTheLogDecodesListRowsWithoutTranscripts() async throws {
        let client = APIClient(session: URLProtocolFixture.session([.init(200, listJSON)]), baseURL: "https://app.thorbis.com")
        let page = try await client.callLog()
        let request = try XCTUnwrap(URLProtocolFixture.recorded.first)
        XCTAssertEqual(request.url?.path, "/v1/calls")
        XCTAssertTrue(request.url?.query?.contains("limit=50") ?? false)
        XCTAssertEqual(page.items.count, 2)
        XCTAssertNotNil(page.nextCursor)
        let missed = page.items[0]
        XCTAssertEqual(missed.caller, "+15555550100")
        XCTAssertEqual(missed.recordingNote, "Missed call. Nothing was recorded.")
        XCTAssertTrue(missed.transcript.isEmpty)
        XCTAssertTrue(CallLogRules.detail(missed).contains("Missed"))
        let booked = page.items[1]
        XCTAssertEqual(booked.jobId, jobID)
        XCTAssertNotNil(booked.playablePath)
        XCTAssertTrue(CallLogRules.detail(booked).hasSuffix("3:12 · Linked to a job"))
    }

    func testUnlinkSendsAnExplicitNull() async throws {
        let reply = #"{"id":"\#(callID)","status":"completed","startedAt":"2026-10-30T15:00:00Z","recording":{"status":"none"}}"#
        let client = APIClient(session: URLProtocolFixture.session([.init(200, reply)]), baseURL: "https://app.thorbis.com")
        _ = try await client.linkCall(callID, jobID: nil)
        let request = try XCTUnwrap(URLProtocolFixture.recorded.first)
        XCTAssertEqual(request.url?.path, "/v1/calls/\(callID)/link")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.body)) as? [String: Any])
        XCTAssertTrue(body["jobId"] is NSNull)
    }

    func testLinkSendsTheJob() async throws {
        let reply = #"{"id":"\#(callID)","status":"completed","jobId":"\#(jobID)","startedAt":"2026-10-30T15:00:00Z","recording":{"status":"none"}}"#
        let client = APIClient(session: URLProtocolFixture.session([.init(200, reply)]), baseURL: "https://app.thorbis.com")
        let linked = try await client.linkCall(callID, jobID: jobID)
        XCTAssertEqual(linked.jobId, jobID)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(URLProtocolFixture.recorded.first?.body)) as? [String: Any])
        XCTAssertEqual(body["jobId"] as? String, jobID)
    }

    func testLinkOffersTheNewestJobs() {
        let jobs = (1...25).map { day in
            Job(id: "j\(day)", customerId: nil, title: "Job \(day)", status: "scheduled",
                createdAt: String(format: "2026-10-%02dT12:00:00Z", day), updatedAt: nil, allowedTransitions: nil)
        }
        let offered = CallLogRules.linkableJobs(jobs)
        XCTAssertEqual(offered.count, 20)
        XCTAssertEqual(offered.first?.id, "j25")
        XCTAssertEqual(offered.last?.id, "j6")
    }

    func testABadCallIDNeverReachesTheServer() async {
        let client = APIClient(session: URLProtocolFixture.session([]), baseURL: "https://app.thorbis.com")
        do {
            _ = try await client.call("../jobs")
            XCTFail("expected a refusal")
        } catch {
            XCTAssertTrue(URLProtocolFixture.recorded.isEmpty)
        }
    }
}

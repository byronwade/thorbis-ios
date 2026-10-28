import XCTest
@testable import Thorbis

final class JobLiveActivityTests: XCTestCase {
    func testJobLinkRoundTrips() throws {
        let url = try XCTUnwrap(JobActivityLink.url(jobID: "00000000-0000-4000-8000-000000002214"))
        XCTAssertEqual(url.absoluteString, "thorbis://job/00000000-0000-4000-8000-000000002214")
        XCTAssertEqual(JobActivityLink.jobID(from: url), "00000000-0000-4000-8000-000000002214")
    }

    func testOtherLinksAreNotJobs() {
        XCTAssertNil(JobActivityLink.jobID(from: URL(string: "thorbis://document/abc")!))
        XCTAssertNil(JobActivityLink.jobID(from: URL(string: "thorbis://job/")!))
        XCTAssertNil(JobActivityLink.jobID(from: URL(string: "https://job/123")!))
        // A job link must not be mistaken for a public estimate token.
        XCTAssertNil(PublicEstimateActionLink.token(from: URL(string: "thorbis://job/123")!))
    }

    func testFieldStepsAndLabels() {
        func state(_ status: String) -> JobActivityAttributes.ContentState {
            .init(status: status, since: .now, waitingToSync: false)
        }
        XCTAssertEqual(state("en_route").label, "On my way")
        XCTAssertEqual(state("en_route").step, 0)
        XCTAssertEqual(state("arrived").label, "On site")
        XCTAssertEqual(state("arrived").step, 1)
        XCTAssertEqual(state("in_progress").step, 2)
        XCTAssertEqual(state("paused").label, "Paused")
        XCTAssertEqual(JobLiveActivity.liveStatuses, ["en_route", "arrived", "in_progress", "paused"])
    }

    func testNextJobPrefersTheJobUnderWayThenTheEarliestBooking() {
        func job(_ id: String, _ status: String, _ at: String?) -> Job {
            var job = Job(id: id, customerId: nil, title: id, status: status, createdAt: nil, updatedAt: nil, allowedTransitions: nil)
            job.scheduledFor = at
            return job
        }
        let later = job("later", "scheduled", "2026-10-27T18:00:00Z")
        let sooner = job("sooner", "dispatched", "2026-10-27T14:30:00Z")
        let done = job("done", "completed", "2026-10-27T12:00:00Z")
        XCTAssertEqual(PaperWorkGroups.next([later, done, sooner])?.id, "sooner")
        XCTAssertEqual(PaperWorkGroups.next([later, job("working", "in_progress", nil), sooner])?.id, "working")
        XCTAssertNil(PaperWorkGroups.next([done]))
        XCTAssertEqual(JobActivityLink.jobID(from: URL(string: "thorbis://job/next")!), JobActivityLink.nextJob)
    }
}

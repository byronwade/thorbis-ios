import XCTest
@testable import Thorbis

@MainActor
final class EstimateJobLookupTests: XCTestCase {
    private func job(_ id: String, customer: String? = "c1", status: String = "scheduled", day: Int) -> Job {
        Job(id: id, customerId: customer, title: id, status: status,
            createdAt: String(format: "2026-10-%02dT12:00:00Z", day), updatedAt: nil, allowedTransitions: nil)
    }

    func testOpenJobsComeFirstThenTheRestEachMostRecentFirst() {
        let jobs = [job("old-open", day: 1), job("done-new", status: "completed", day: 20), job("other", customer: "c2", day: 25),
                    job("new-open", day: 9), job("canceled", status: "canceled", day: 15), job("nobody", customer: nil, day: 26)]
        XCTAssertEqual(EstimateJobLookup.candidates(jobs, customerID: "C1").map(\.id), ["new-open", "old-open", "done-new", "canceled"])
    }

    func testNeverAsksMoreThanTheCap() async {
        let jobs = (1...20).map { job("j\($0)", day: $0) }
        XCTAssertEqual(EstimateJobLookup.candidates(jobs, customerID: "c1").count, 8)
        var asked: [String] = []
        let found = await EstimateJobLookup.jobID(for: "e1", customerID: "c1", jobs: jobs) { id in asked.append(id); return [] }
        XCTAssertNil(found)
        XCTAssertEqual(asked, (13...20).reversed().map { "j\($0)" })
    }

    func testStopsAtTheFirstJobThatListsTheEstimate() async {
        let jobs = (1...5).map { job("j\($0)", day: $0) }
        var asked: [String] = []
        let found = await EstimateJobLookup.jobID(for: "E1", customerID: "c1", jobs: jobs) { id in
            asked.append(id); return id == "j4" ? ["x", "e1"] : ["x"]
        }
        XCTAssertEqual(found, "j4")
        XCTAssertEqual(asked, ["j5", "j4"])
    }

    func testAFailedReadOrALostScreenGivesNoJob() async {
        let jobs = (1...3).map { job("j\($0)", day: $0) }
        var asked = 0
        let failed = await EstimateJobLookup.jobID(for: "e1", customerID: "c1", jobs: jobs) { _ in asked += 1; throw URLError(.notConnectedToInternet) }
        XCTAssertNil(failed); XCTAssertEqual(asked, 1)
        var current = true
        let left = await EstimateJobLookup.jobID(for: "e1", customerID: "c1", jobs: jobs, isCurrent: { current }) { _ in current = false; return ["e1"] }
        XCTAssertNil(left)
        let none = await EstimateJobLookup.jobID(for: "e1", customerID: "c9", jobs: jobs) { _ in XCTFail("no jobs to ask"); return [] }
        XCTAssertNil(none)
    }
}

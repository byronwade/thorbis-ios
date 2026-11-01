import XCTest
@testable import Thorbis

@MainActor
final class ListRowsTests: XCTestCase {
    private func job(_ id: String, _ status: String, time: String? = "2026-10-31T16:00:00Z") -> Job {
        Job(id: id, customerId: "c", title: id, status: status, createdAt: nil, updatedAt: nil,
            allowedTransitions: nil, scheduledFor: time)
    }

    func testJobsTabGroupsEveryJobOnceByWhereItStands() {
        let jobs = [job("a", "in_progress"), job("b", "scheduled"), job("c", "scheduled", time: nil),
                    job("d", "draft", time: nil), job("e", "completed"), job("f", "canceled"), job("g", "dispatched")]
        let groups = JobsListGroups.groups(jobs)
        XCTAssertEqual(groups.map(\.title), ["In progress", "Scheduled", "Unscheduled", "Done", "Cancelled"])
        XCTAssertEqual(groups[1].jobs.map(\.id), ["b", "g"])
        XCTAssertEqual(groups[2].jobs.map(\.id), ["c", "d"])
        XCTAssertEqual(groups.flatMap(\.jobs).map(\.id).sorted(), jobs.map(\.id).sorted(), "no job is dropped or doubled")
    }

    func testOtherStatusesKeepAnOtherSection() {
        let groups = JobsListGroups.groups([job("x", "on_hold"), job("y", "canceled")])
        XCTAssertEqual(groups.last?.title, "Other")
        XCTAssertEqual(groups.last?.jobs.map(\.id), ["x", "y"])
    }

    func testSearchRowsLeadWithTheirKindsGlyph() {
        let builder = SearchResultsBuilder(terms: SearchTerms(""), jobs: [], customers: [], customerRecords: [], estimates: [],
                                           invoices: [], street: { _ in nil }, server: nil, phoneMatch: nil, actions: [],
                                           canJobs: true, canCustomers: true, canEstimates: true, canInvoices: true)
        let hit = builder.jobHit(job("j", "in_progress"))
        guard case .job(let status, _) = hit.glyph else { return XCTFail("a job leads with its status glyph") }
        XCTAssertEqual(status, "in_progress")
        XCTAssertNil(hit.status, "the glyph carries a job's status; no second word")
        let customer = builder.customerHit(Customer(id: "c1", name: "Dana Ortiz", archived: nil, createdAt: nil))
        guard case .customer(let name) = customer.glyph else { return XCTFail("a customer leads with initials") }
        XCTAssertEqual(name, "Dana Ortiz")
        guard case .place = SearchGlyph.document("invoice") else { return XCTFail("documents lead with a place mark") }
    }
}

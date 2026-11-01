import XCTest
@testable import Thorbis

final class SpotlightIndexTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let us = Locale(identifier: "en_US")

    private func job(_ id: String, customer: String? = "c1", status: String = "in_progress", at: String? = "2026-10-31T09:00:00Z") -> Job {
        Job(id: id, customerId: customer, title: "Replace water heater", status: status, createdAt: nil, updatedAt: nil,
            allowedTransitions: nil, scheduledFor: at)
    }

    func testScopeIsPerPersonAndWorkspaceAndCaseInsensitive() {
        let a = SpotlightCatalog.scope(actorID: "User-1", organizationID: "Org-A")
        XCTAssertEqual(a, SpotlightCatalog.scope(actorID: "user-1", organizationID: "org-a"))
        XCTAssertNotEqual(a, SpotlightCatalog.scope(actorID: "user-1", organizationID: "org-b"))
        XCTAssertNotEqual(a, SpotlightCatalog.scope(actorID: "user-2", organizationID: "org-a"))
        XCTAssertNil(SpotlightCatalog.scope(actorID: nil, organizationID: "org-a"))
        XCTAssertNil(SpotlightCatalog.scope(actorID: "user-1", organizationID: ""))
    }

    func testTappedResultOpensOnlyInItsOwnWorkspace() throws {
        let scope = try XCTUnwrap(SpotlightCatalog.scope(actorID: "u", organizationID: "a"))
        let other = try XCTUnwrap(SpotlightCatalog.scope(actorID: "u", organizationID: "b"))
        let jobID = SpotlightCatalog.identifier(.job("j1"), scope: scope)
        let customerID = SpotlightCatalog.identifier(.customer("c1"), scope: scope)
        XCTAssertEqual(SpotlightCatalog.target(identifier: jobID, scope: scope), .job("j1"))
        XCTAssertEqual(SpotlightCatalog.target(identifier: customerID, scope: scope), .customer("c1"))
        XCTAssertNil(SpotlightCatalog.target(identifier: jobID, scope: other))
        XCTAssertNil(SpotlightCatalog.target(identifier: jobID, scope: nil))
        XCTAssertNil(SpotlightCatalog.target(identifier: "\(scope)#invoice#i1", scope: scope))
        XCTAssertNil(SpotlightCatalog.target(identifier: "j1", scope: scope))
    }

    func testEntriesCarryOnlyTitleCustomerStatusAndTime() throws {
        let scope = try XCTUnwrap(SpotlightCatalog.scope(actorID: "u", organizationID: "a"))
        let customers = [Customer(id: "c1", name: "Dana Ortiz", archived: false, createdAt: nil),
                         Customer(id: "c2", name: "Old Account", archived: true, createdAt: nil)]
        let entries = SpotlightCatalog.entries(jobs: [job("j1")], customers: customers, scope: scope,
                                               includeJobs: true, includeCustomers: true, timeZone: utc, locale: us)
        XCTAssertEqual(entries.map(\.identifier), [SpotlightCatalog.identifier(.job("j1"), scope: scope),
                                                   SpotlightCatalog.identifier(.customer("c1"), scope: scope)],
                       "archived customers stay out")
        let jobEntry = entries[0]
        XCTAssertEqual(jobEntry.title, "Replace water heater")
        // An absolute date and time in the person's locale; the exact separator is the system's.
        XCTAssertTrue(jobEntry.detail.hasPrefix("Dana Ortiz · In progress · Oct 31"), jobEntry.detail)
        XCTAssertTrue(jobEntry.detail.contains("9:00"), jobEntry.detail)
        XCTAssertFalse(jobEntry.detail.contains("Today"), "the index is not rebuilt at midnight")
        XCTAssertEqual(entries[1].title, "Dana Ortiz")
        XCTAssertEqual(entries[1].detail, "Customer")
    }

    func testUnscheduledOrUnknownCustomerJobsStillIndexWithoutBlanks() throws {
        let scope = try XCTUnwrap(SpotlightCatalog.scope(actorID: "u", organizationID: "a"))
        let entry = try XCTUnwrap(SpotlightCatalog.entries(jobs: [job("j2", customer: "missing", status: "scheduled", at: nil)],
                                                           customers: [], scope: scope, includeJobs: true,
                                                           includeCustomers: true, timeZone: utc, locale: us).first)
        XCTAssertEqual(entry.detail, "Scheduled")
    }

    func testNothingIsIndexedWithoutIdentityOrPermission() throws {
        let customers = [Customer(id: "c1", name: "Dana Ortiz", archived: nil, createdAt: nil)]
        XCTAssertTrue(SpotlightCatalog.entries(jobs: [job("j1")], customers: customers, scope: nil,
                                               includeJobs: true, includeCustomers: true).isEmpty)
        let scope = try XCTUnwrap(SpotlightCatalog.scope(actorID: "u", organizationID: "a"))
        let jobsOnly = SpotlightCatalog.entries(jobs: [job("j1")], customers: customers, scope: scope,
                                                includeJobs: true, includeCustomers: false)
        XCTAssertEqual(jobsOnly.count, 1)
        XCTAssertTrue(SpotlightCatalog.entries(jobs: [job("j1")], customers: customers, scope: scope,
                                               includeJobs: false, includeCustomers: false).isEmpty)
    }

    func testSearchLinkRoundTripsWords() throws {
        XCTAssertEqual(SearchLink.query(from: SearchLink.url(query: "water heater & co")), "water heater & co")
        XCTAssertEqual(SearchLink.query(from: try XCTUnwrap(URL(string: "thorbis://search"))), "")
        XCTAssertNil(SearchLink.query(from: try XCTUnwrap(URL(string: "thorbis://schedule"))))
        XCTAssertNil(SearchLink.query(from: try XCTUnwrap(URL(string: "https://search?q=x"))))
    }
}

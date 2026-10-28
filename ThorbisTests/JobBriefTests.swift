import XCTest
@testable import Thorbis

final class JobBriefTests: XCTestCase {
    private func customer(phone: String? = "555-0100", email: String? = "dana@example.com", preferred: String? = nil) -> CustomerRecord {
        CustomerRecord(id: "00000000-0000-4000-8000-000000000001", organizationId: "org", name: "Dana Ruiz", locationId: nil,
                       email: email, phone: phone, address: nil, accountType: nil, industry: nil,
                       referralSource: nil, website: nil, preferredContact: preferred, billingTerms: nil,
                       creditLimit: nil, taxExempt: nil, taxExemptId: nil, archived: false,
                       archiveCycleAuditId: nil, createdAt: "2026-10-01T00:00:00Z", updatedAt: "2026-10-01T00:00:00Z")
    }

    private func contact(_ id: String, _ name: String, role: String? = nil, phone: String? = nil, email: String? = nil,
                         primary: Bool = false) -> CustomerContactRecord {
        CustomerContactRecord(id: id, organizationId: "org", customerId: "cust", name: name, role: role, email: email,
                              phone: phone, primary: primary, createdAt: "2026-10-01T00:00:00Z", updatedAt: "2026-10-01T00:00:00Z")
    }

    // MARK: JS-02 / JS-03 menu

    func testTheMenuGroupsVisitMoneyFinishRecordWithPauseLastInItsGroup() {
        let groups = JobMenu.groups(.init(transitions: ["paused", "dispatched"], canSchedule: true, canAssign: true,
                                          canBillWithoutEstimate: true, canRequestDeposit: true, canShowToCustomer: true))
        XCTAssertEqual(groups, [
            [.transition("dispatched"), .transition("paused"), .schedule, .assign],
            [.billWithoutEstimate, .deposit],
            [.wrapUp, .followUps],
            [.showToCustomer, .copyID],
        ])
    }

    func testATechWithNothingExtraSeesOnlyWhatTheyCanDoAndNoEmptyGroups() {
        let groups = JobMenu.groups(.init(transitions: ["paused"]))
        XCTAssertEqual(groups, [[.transition("paused")], [.wrapUp, .followUps], [.copyID]])
    }

    func testWrapUpLeavesTheMenuWhenTheBarCarriesIt() {
        let groups = JobMenu.groups(.init(barIsWrapUp: true))
        XCTAssertEqual(groups, [[.followUps], [.copyID]])
        XCTAssertFalse(groups.flatMap { $0 }.contains(.wrapUp))
    }

    // MARK: JS-06 contacts

    func testEveryContactIsListedPrimaryFirstThenByName() {
        let people = JobContacts.people(contacts: [
            contact("b", "Zoe Tenant", role: "Tenant", phone: "555-0102"),
            contact("a", "Ann Manager", role: "Property manager", email: "ann@example.com"),
            contact("p", "Dana Ruiz", phone: "(555) 010-0100", primary: true),
        ], customer: customer())
        XCTAssertEqual(people.map(\.name), ["Dana Ruiz", "Ann Manager", "Zoe Tenant"])
        XCTAssertEqual(people.map(\.detail), ["Primary", "Property manager", "Tenant"])
        XCTAssertEqual(people[0].reach.call, URL(string: "tel:5550100100"))
        XCTAssertEqual(people[0].reach.text, URL(string: "sms:5550100100"))
        XCTAssertNil(people[1].reach.call)
        XCTAssertEqual(people[1].reach.email, URL(string: "mailto:ann@example.com"))
    }

    func testTheAccountIsTheFallbackOnlyWhenNoContactCanBeReached() {
        let fallback = JobContacts.people(contacts: [contact("x", "Old contact")], customer: customer())
        XCTAssertEqual(fallback.map(\.name), ["Dana Ruiz", "Old contact"])
        XCTAssertEqual(fallback.first?.detail, "Account")

        let reachable = JobContacts.people(contacts: [contact("x", "Sam", phone: "555-0101")], customer: customer())
        XCTAssertEqual(reachable.map(\.name), ["Sam"])

        XCTAssertTrue(JobContacts.people(contacts: [], customer: customer(phone: nil, email: nil)).isEmpty)
    }

    func testThePreferredChannelIsNamed() {
        XCTAssertEqual(JobContacts.preference(customer(preferred: "sms")), "Prefers text")
        XCTAssertEqual(JobContacts.preference(customer(preferred: "phone")), "Prefers a call")
        XCTAssertEqual(JobContacts.preference(customer(preferred: "email")), "Prefers email")
        XCTAssertNil(JobContacts.preference(customer()))
        XCTAssertNil(JobContacts.preference(nil))
    }

    func testAShortOrEmptyNumberIsNotDialable() {
        XCTAssertTrue(JobReach(phone: "123", email: nil).isEmpty)
        XCTAssertTrue(JobReach(phone: nil, email: "not an address").isEmpty)
    }

    // MARK: JS-10 past visits

    func testPastVisitsDecodeAndDateByFinishThenBooking() throws {
        let json = """
        {"items":[
          {"id":"j1","title":"Furnace tune-up","status":"completed","notes":"Flame sensor dirty.","assignedToUserId":"u2",
           "scheduledFor":"2026-03-02T15:00:00.000Z","completedAt":"2026-03-02T17:30:00.000Z","createdAt":"2026-02-20T10:00:00.000Z"},
          {"id":"j2","title":"AC not cooling","status":"scheduled","scheduledFor":"2026-07-14T15:00:00.000Z","createdAt":"2026-07-01T10:00:00.000Z"}
        ]}
        """
        struct Page: Decodable { let items: [JobVisitRecord] }
        let visits = try JSONDecoder().decode(Page.self, from: Data(json.utf8)).items
        XCTAssertEqual(visits.map(\.title), ["Furnace tune-up", "AC not cooling"])
        XCTAssertEqual(visits[0].when, JobFiltering.date("2026-03-02T17:30:00.000Z"))
        XCTAssertEqual(visits[1].when, JobFiltering.date("2026-07-14T15:00:00.000Z"))
        XCTAssertNil(visits[1].notes)
    }
}

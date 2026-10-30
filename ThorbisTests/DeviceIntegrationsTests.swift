import XCTest
@testable import Thorbis

final class DeviceIntegrationsTests: XCTestCase {
    private func job(scheduledFor: String? = "2026-10-30T15:00:00Z", locationId: String? = "loc-1") -> JobRecord {
        JobRecord(id: "00000000-0000-4000-8000-00000000ab12", organizationId: "org", customerId: "cust", estimateId: nil,
                  estimateRevisionNumber: nil, locationId: locationId, teamId: nil, title: "Water heater", notes: nil,
                  status: "scheduled", assignedToUserId: nil, scheduledFor: scheduledFor, createdAt: "2026-10-27T10:00:00Z",
                  updatedAt: "2026-10-28T15:00:00Z", dispatchedAt: nil, enRouteAt: nil, arrivedAt: nil,
                  arrivalMethod: nil, startedAt: nil, pausedAt: nil, pauseReason: nil, pauseNextAction: nil,
                  pauseOwnerUserId: nil, pauseCycleAuditId: nil, lastResumeAuditId: nil,
                  scheduleCycleAuditId: nil, completedAt: nil, canceledAt: nil, allowedTransitions: nil)
    }

    private func location(_ id: String, customer: String = "cust", address: String = "12 Oak St, Austin TX") -> ServiceLocationRecord {
        ServiceLocationRecord(id: id, organizationId: "org", customerId: customer, label: "Home", kind: "service",
                              address: address, notes: nil, coordinates: nil, gateCode: nil, alarmCode: nil,
                              dogOnSite: nil, parking: nil, createdAt: "2026-10-27T12:00:00Z", updatedAt: "2026-10-27T12:00:00Z")
    }

    private func customer(name: String = "Dana Ruiz", type: String? = nil) -> CustomerRecord {
        CustomerRecord(id: "cust", organizationId: "org", name: name, locationId: nil,
                       email: " dana@example.com ", phone: "555-0100", address: "12 Oak St", accountType: type, industry: nil,
                       referralSource: nil, website: nil, preferredContact: nil, billingTerms: nil,
                       creditLimit: nil, taxExempt: nil, taxExemptId: nil, archived: false,
                       archiveCycleAuditId: nil, createdAt: "2026-10-01T00:00:00Z", updatedAt: "2026-10-01T00:00:00Z")
    }

    // MARK: Calendar

    func testAScheduledVisitBecomesAOneHourEventAtTheJobsOwnSite() throws {
        let draft = try XCTUnwrap(JobCalendarDraft.make(job: job(), customerName: "Dana Ruiz",
                                                        locations: [location("loc-2", address: "Other"), location("loc-1")]))
        XCTAssertEqual(draft.title, "Water heater")
        XCTAssertEqual(draft.location, "12 Oak St, Austin TX")
        XCTAssertEqual(draft.start, JobFiltering.date("2026-10-30T15:00:00Z"))
        XCTAssertEqual(draft.end.timeIntervalSince(draft.start), 3600)
        XCTAssertEqual(draft.notes, "Dana Ruiz\nJOB-AB12")
    }

    func testNoSiteIsInferredWhenTheJobHasNoVerifiedLocation() throws {
        let unset = try XCTUnwrap(JobCalendarDraft.make(job: job(locationId: nil), customerName: nil, locations: [location("loc-1")]))
        XCTAssertNil(unset.location)
        XCTAssertEqual(unset.notes, "JOB-AB12")
        let foreign = try XCTUnwrap(JobCalendarDraft.make(job: job(), customerName: nil, locations: [location("loc-1", customer: "other")]))
        XCTAssertNil(foreign.location)
    }

    func testAnUnscheduledJobCannotGoOnTheCalendar() {
        XCTAssertNil(JobCalendarDraft.make(job: job(scheduledFor: nil), customerName: "Dana", locations: []))
        XCTAssertNil(JobCalendarDraft.make(job: job(scheduledFor: "soon"), customerName: "Dana", locations: []))
    }

    // MARK: Contacts

    func testAResidentialCustomerCardSplitsTheNameAndTrimsFields() {
        let card = ContactCardDraft.make(customer: customer())
        XCTAssertEqual(card.givenName, "Dana")
        XCTAssertEqual(card.familyName, "Ruiz")
        XCTAssertNil(card.organization)
        XCTAssertEqual(card.email, "dana@example.com")
        XCTAssertEqual(card.phone, "555-0100")
        XCTAssertEqual(card.address, "12 Oak St")
        let contact = card.contact()
        XCTAssertEqual(contact.phoneNumbers.first?.value.stringValue, "555-0100")
        XCTAssertEqual(contact.postalAddresses.first?.value.street, "12 Oak St")
    }

    func testACommercialCustomerIsSavedAsACompany() {
        let card = ContactCardDraft.make(customer: customer(name: "Acme Property Group", type: "commercial"))
        XCTAssertEqual(card.organization, "Acme Property Group")
        XCTAssertEqual(card.fullName, "")
    }

    func testAContactCardCarriesTheCustomerAsCompanyAndSkipsEmptyFields() {
        let person = CustomerContactRecord(id: "c1", organizationId: "org", customerId: "cust", name: "Sam Lee", role: "Property manager",
                                           email: nil, phone: "  ", primary: false, createdAt: "", updatedAt: "")
        let card = ContactCardDraft.make(contact: person, customerName: "Acme Property Group", address: nil)
        XCTAssertEqual(card.fullName, "Sam Lee")
        XCTAssertEqual(card.organization, "Acme Property Group")
        XCTAssertEqual(card.jobTitle, "Property manager")
        XCTAssertNil(card.phone)
        XCTAssertNil(card.email)
        XCTAssertTrue(card.contact().phoneNumbers.isEmpty)
    }

    // MARK: Mail

    func testTheMailFallbackKeepsTheRecipientAndSubject() throws {
        let draft = try XCTUnwrap(MailDraft(recipient: " dana@example.com", subject: "Water heater & flue"))
        let url = try XCTUnwrap(draft.mailtoURL)
        XCTAssertEqual(url.scheme, "mailto")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "dana@example.com")
        XCTAssertEqual(components.queryItems?.first?.value, "Water heater & flue")
        XCTAssertNil(MailDraft(recipient: "not an email"))
        XCTAssertNil(MailDraft(recipient: nil))
    }

    func testCalendarAndEmailJoinTheJobMenuOnlyWhenAvailable() {
        XCTAssertEqual(JobMenu.groups(.init(canSchedule: true, canAddToCalendar: true, canEmail: true)),
                       [[.schedule, .addToCalendar], [.wrapUp, .followUps], [.email, .copyID]])
        XCTAssertEqual(JobMenu.groups(.init()), [[.wrapUp, .followUps], [.copyID]])
    }
}

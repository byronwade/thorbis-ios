import XCTest
@testable import Thorbis

final class JobLocationPolicyTests: XCTestCase {
    private func location(_ id: String, customer: String = "customer", org: String = "org", kind: String = "service") -> ServiceLocationRecord {
        ServiceLocationRecord(id: id, organizationId: org, customerId: customer, label: id, kind: kind,
                              address: "\(id) Main Street", notes: nil, coordinates: nil, gateCode: nil,
                              alarmCode: nil, dogOnSite: nil, parking: nil, createdAt: "", updatedAt: "")
    }

    func testOnlyCurrentCustomerLocationsAreChoicesAndNoneIsImplicitlySelected() {
        let places = [location("one"), location("two"), location("other", customer: "another"), location("foreign", org: "foreign")]
        let choices = JobLocationPolicy.accountLocations(places, customerID: "customer", organizationID: "org")
        XCTAssertEqual(choices.map(\.id), ["one", "two"])
        XCTAssertNil(JobLocationPolicy.directions(for: nil, in: choices))
        XCTAssertNotNil(JobLocationPolicy.directions(for: "two", in: choices))
        XCTAssertNil(JobLocationPolicy.directions(for: "foreign", in: choices))
    }

    func testAccountDataExpiresWhenGenerationOrIdentityChanges() {
        let generation = UUID()
        let authority = UUID()
        let original = JobLocationPolicy.context(generation: generation, authorityRevision: authority, policyVersion: 4, canView: true, organizationID: "org", customerID: "customer")
        XCTAssertEqual(original, JobLocationPolicy.context(generation: generation, authorityRevision: authority, policyVersion: 4, canView: true, organizationID: "org", customerID: "customer"))
        XCTAssertNotEqual(original, JobLocationPolicy.context(generation: UUID(), authorityRevision: authority, policyVersion: 4, canView: true, organizationID: "org", customerID: "customer"))
        XCTAssertNotEqual(original, JobLocationPolicy.context(generation: generation, authorityRevision: authority, policyVersion: 5, canView: true, organizationID: "org", customerID: "customer"))
        // A pre-revocation request remains stale even if the policy/version is later re-granted.
        XCTAssertNotEqual(original, JobLocationPolicy.context(generation: generation, authorityRevision: UUID(), policyVersion: 4, canView: true, organizationID: "org", customerID: "customer"))
        XCTAssertNotEqual(original, JobLocationPolicy.context(generation: generation, authorityRevision: authority, policyVersion: 4, canView: false, organizationID: "org", customerID: "customer"))
        XCTAssertNotEqual(original, JobLocationPolicy.context(generation: generation, authorityRevision: authority, policyVersion: 4, canView: true, organizationID: "other", customerID: "customer"))
        XCTAssertNotEqual(original, JobLocationPolicy.context(generation: generation, authorityRevision: authority, policyVersion: 4, canView: true, organizationID: "org", customerID: "other"))
    }

    func testLiveActivityReplacesGuessedAddressButKeepsMatchingAttributes() {
        XCTAssertTrue(JobLiveActivity.addressNeedsReplacement(existing: "1 Main Street", desired: nil))
        XCTAssertFalse(JobLiveActivity.addressNeedsReplacement(existing: nil, desired: nil))
        XCTAssertFalse(JobLiveActivity.addressNeedsReplacement(existing: "1 Main Street", desired: "1 Main Street"))
        XCTAssertTrue(JobLiveActivity.addressNeedsReplacement(existing: "1 Main Street", desired: "2 Main Street"))
    }
}

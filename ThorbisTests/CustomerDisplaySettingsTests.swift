import XCTest
@testable import Thorbis

final class CustomerDisplaySettingsTests: XCTestCase {
    private func profile(_ facts: [String: String]) throws -> OrganizationProfile {
        let items = facts.map { ["factKey": $0.key, "label": $0.key, "value": $0.value] }
        let object: [String: Any] = ["organizationId": "00000000-0000-4000-8000-000000000003", "facts": items,
                                     "catalog": [[String: Any]](), "coreReady": true, "missingCore": [String]()]
        return try JSONDecoder().decode(OrganizationProfile.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testPreviewUsesTheSavedNameContactAndAddress() throws {
        let facts = CustomerDisplayFacts(profile: try profile([
            "legal_name": "Wade Plumbing & Heating LLC", "primary_phone": "(555) 555-0123",
            "website": "wadeplumbing.com", "business_address": " 12 Main St, Springfield ",
        ]), organizationName: "Wade's Plumbing")
        XCTAssertEqual(facts.name, "Wade Plumbing & Heating LLC")
        XCTAssertEqual(facts.contactLine, "(555) 555-0123 \u{00B7} wadeplumbing.com")
        XCTAssertEqual(facts.address, "12 Main St, Springfield")
    }

    func testPreviewFallsBackToTheWorkspaceNameAndShowsNoEmptyLines() throws {
        let facts = CustomerDisplayFacts(profile: try profile(["legal_name": "  ", "primary_email": ""]), organizationName: "Wade's Plumbing")
        XCTAssertEqual(facts.name, "Wade's Plumbing")
        XCTAssertNil(facts.contactLine)
        XCTAssertNil(facts.address)
        XCTAssertEqual(CustomerDisplayFacts(profile: nil, organizationName: nil).name, "Your company")
    }

    func testReviewSummaryFollowsTheSwitchAndTheLink() throws {
        XCTAssertEqual(CustomerDisplayFacts.reviews(profile: try profile(["review_requests": "off", "review_link": "https://g.page/r/wade/review"])), "Off")
        XCTAssertEqual(CustomerDisplayFacts.reviews(profile: try profile([:])), "On once you add your review link")
        XCTAssertEqual(CustomerDisplayFacts.reviews(profile: try profile(["review_link": "https://g.page/r/wade/review"])),
                       "On \u{00B7} one text after an invoice is paid")
        // Unknown until the profile is read: no On or Off is claimed.
        XCTAssertEqual(CustomerDisplayFacts.reviews(profile: nil), "One text after an invoice is paid")
    }
}

final class WorkflowsTests: XCTestCase {
    func testReviewRequestIsOnlyOnWithTheSwitchAndAUsableLink() {
        var inputs = WorkflowAutomations.Inputs()
        XCTAssertNil(WorkflowAutomations.reviewState(inputs))
        inputs.profileLoaded = true
        XCTAssertEqual(WorkflowAutomations.reviewState(inputs)?.word, "No link")
        inputs.reviewLink = "https://g.page/r/wade/review"
        XCTAssertEqual(WorkflowAutomations.reviewState(inputs)?.word, "On")
        XCTAssertEqual(WorkflowAutomations.reviewState(inputs)?.on, true)
        inputs.reviewRequests = "off"
        XCTAssertEqual(WorkflowAutomations.reviewState(inputs)?.word, "Off")
        XCTAssertEqual(WorkflowAutomations.reviewState(inputs)?.on, false)
    }

    func testRowsOpenOnlyWhatThisPersonMayChange() {
        let plain = WorkflowAutomations.items(.init())
        XCTAssertEqual(plain.map(\.id), ["review-request", "booking-notices", "visit-updates"])
        XCTAssertTrue(plain.allSatisfy { $0.destination == nil && $0.state == nil })

        let owner = WorkflowAutomations.items(.init(canEditSettings: true, canManageNotices: true, receivesDigest: true, digestOn: false,
                                                    reviewLink: "https://g.page/r/wade/review", profileLoaded: true))
        XCTAssertEqual(owner.map(\.id), ["review-request", "booking-notices", "visit-updates", "morning-digest"])
        XCTAssertEqual(owner[0].destination, .reviewRequests)
        XCTAssertEqual(owner[0].state, "On")
        XCTAssertEqual(owner[1].destination, .notices)
        XCTAssertNil(owner[2].destination)
        XCTAssertEqual(owner[3].state, "Off")
        XCTAssertFalse(owner[3].isOn)
    }
}

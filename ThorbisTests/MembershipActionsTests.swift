import XCTest
@testable import Thorbis

/// Paper 85B · Cancel membership.
final class MembershipActionsTests: XCTestCase {
    private func record(status: String = "active", discount: Int = 15, planName: String? = "Comfort Club \u{00B7} Gold") -> MembershipRecord {
        MembershipRecord(id: "6f1c2a9e-1b7d-4f53-9a0e-2c3d4e5f6a7b", customerId: "0b8f3c1d-2e4a-4c6b-8d9e-1f2a3b4c5d6e",
                         planId: nil, name: "Gold", kind: "membership", cadence: nil, startsOn: nil,
                         renewsOn: "2027-03-01", status: status, discountPercent: discount, notes: nil,
                         customerName: nil, planName: planName)
    }

    func testSubtitleIsThePlanThenTheCustomer() {
        XCTAssertEqual(MembershipCancellation.subtitle(record(), customerName: "Danielle Marlowe"),
                       "Comfort Club \u{00B7} Gold \u{00B7} Danielle Marlowe")
        XCTAssertEqual(MembershipCancellation.subtitle(record(planName: nil), customerName: nil), "Gold",
                       "Without a plan name the membership's own name shows, and no trailing dot")
        XCTAssertEqual(MembershipCancellation.subtitle(record(), customerName: "  "), "Comfort Club \u{00B7} Gold")
    }

    func testChangesSayOnlyWhatTheServerDoes() {
        XCTAssertEqual(MembershipCancellation.changes(record()), ["This plan's 15% member pricing ends today"])
        XCTAssertEqual(MembershipCancellation.changes(record(discount: 0)), ["This plan's member pricing ends today"])
    }

    func testCommitIsBlockedWhenCancelledOrNotAllowed() {
        XCTAssertNil(MembershipCancellation.blockedReason(record(), canEdit: true))
        XCTAssertEqual(MembershipCancellation.blockedReason(record(), canEdit: false),
                       "You don't have permission to cancel memberships.")
        XCTAssertEqual(MembershipCancellation.blockedReason(record(status: "cancelled"), canEdit: true),
                       "This membership is already cancelled.")
    }
}

import XCTest
@testable import Thorbis

@MainActor final class VolatileDraftRecoveryTests: XCTestCase {
    func testDraftSurvivesOwnerReleaseOnlyInItsOriginalScope() throws {
        let actor = UUID().uuidString, organization = UUID().uuidString, job = UUID().uuidString
        let scope = CommercialDraftScope(actor: actor, organization: organization, origin: "https://example.test", kind: "new-estimate", document: "job:\(job)")
        let other = CommercialDraftScope(actor: actor, organization: UUID().uuidString, origin: scope.origin, kind: scope.kind, document: scope.document)
        let buffer = VolatileDraftRecovery<CommercialDraftScope, CommercialNewEstimateDraft>()
        let draft = CommercialNewEstimateDraft(customerID: UUID().uuidString, title: "unsaved", lines: [
            .init(description: "Valve and long details", quantity: "2", unitPrice: "42.50", source: .manual)
        ], uncertain: true, created: nil, requiresLocationVerification: false, requiresManualReview: false,
            requiresGroupDisclosure: false, acceptedGroupLoss: false)
        buffer.hold(draft, for: scope)
        XCTAssertNil(buffer.read(for: other))
        buffer.clear(for: other)
        let recovered = try XCTUnwrap(buffer.read(for: scope))
        XCTAssertEqual(recovered.title, "unsaved")
        XCTAssertTrue(recovered.uncertain)
        let line = try XCTUnwrap(recovered.lines().first)
        XCTAssertEqual(line.description, "Valve and long details")
        XCTAssertEqual(line.quantity, "2")
        XCTAssertEqual(line.unitPrice, "42.50")
    }
}

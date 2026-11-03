import XCTest
@testable import Thorbis

final class InvoiceCatalogLineSelectionTests: XCTestCase {
    private let org = "00000000-0000-4000-8000-000000000002"
    private let generation = UUID()

    func testSelectionTracksOnlyItsExactLineThroughReordering() {
        let first = line(), second = line()
        let context = PriceBookCatalogContext(organizationID: org, sessionGeneration: generation)
        let selection = InvoiceCatalogLineSelection(lineID: second.id, context: context)
        XCTAssertEqual(selection.resolvedLineID(in: [first, second], context: context), second.id)
        XCTAssertEqual(selection.resolvedLineID(in: [second, first], context: context), second.id)
        XCTAssertNil(selection.resolvedLineID(in: [first], context: context))
        XCTAssertNil(selection.resolvedLineID(in: [second, second], context: context))
    }

    func testSameVerifiedAuthorityRevisionKeepsAddedLineSelected() {
        let added = line()
        let authority = PriceBookAuthority(actorID: "technician", policyVersion: 4, generation: "scope-a", revision: UUID())
        let refreshed = PriceBookAuthority(actorID: "technician", policyVersion: 4, generation: "scope-a", revision: UUID())
        let previous = PriceBookCatalogContext(organizationID: org, sessionGeneration: generation, authority: authority)
        let current = PriceBookCatalogContext(organizationID: org, sessionGeneration: generation, authority: refreshed)
        let selection = InvoiceCatalogLineSelection(lineID: added.id, context: previous)
        XCTAssertEqual(selection.resolvedLineID(in: [added], context: current), added.id)
    }

    func testChangedPolicyOrScopeCannotResolvePriorSelection() {
        let added = line()
        let authority = PriceBookAuthority(actorID: "technician", policyVersion: 4, generation: "scope-a", revision: UUID())
        let old = PriceBookCatalogContext(organizationID: org, sessionGeneration: generation, authority: authority)
        let selection = InvoiceCatalogLineSelection(lineID: added.id, context: old)
        let changed = [
            PriceBookAuthority(actorID: "other", policyVersion: 4, generation: "scope-a", revision: UUID()),
            PriceBookAuthority(actorID: "technician", policyVersion: 5, generation: "scope-a", revision: UUID()),
            PriceBookAuthority(actorID: "technician", policyVersion: 4, generation: "scope-b", revision: UUID()),
        ]
        for authority in changed {
            XCTAssertNil(selection.resolvedLineID(in: [added], context: .init(organizationID: org, sessionGeneration: generation, authority: authority)))
        }
        XCTAssertNil(selection.resolvedLineID(in: [added], context: .init(organizationID: org, sessionGeneration: generation, authority: nil)))
    }

    func testChangedOrganizationOrGenerationCannotResolvePriorSelection() {
        let added = line()
        let context = PriceBookCatalogContext(organizationID: org, sessionGeneration: generation)
        let selection = InvoiceCatalogLineSelection(lineID: added.id, context: context)
        XCTAssertNil(selection.resolvedLineID(in: [added], context: .init(organizationID: nil, sessionGeneration: generation)))
        XCTAssertNil(selection.resolvedLineID(in: [added], context: .init(organizationID: "00000000-0000-4000-8000-000000000003", sessionGeneration: generation)))
        XCTAssertNil(selection.resolvedLineID(in: [added], context: .init(organizationID: org, sessionGeneration: UUID())))
    }

    private func line() -> InvoiceLineDraft {
        InvoiceLineDraft(description: "Same catalog wording", quantity: "1", unitPrice: "12.50")
    }
}

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

import XCTest
@testable import Thorbis

final class InvoiceLineEditorTests: XCTestCase {
    private let invoiceJSON = #"{"id":"00000000-0000-4000-8000-00000000000a","organizationId":"00000000-0000-4000-8000-000000000002","customerId":"00000000-0000-4000-8000-000000000003","createdByUserId":"00000000-0000-4000-8000-000000000004","origin":"job_completion","sourceOperationKey":"completion:test","status":"draft","linesRevision":3,"amountPaid":0,"currency":"USD","lines":[{"id":"00000000-0000-4000-8000-00000000000b","description":"Repair","quantity":2,"unitPrice":{"amount":1250,"currency":"USD"},"source":{"kind":"manual"}}],"createdAt":"2026-10-26T12:00:00Z","updatedAt":"2026-10-26T12:00:00Z"}"#

    private func makeInvoice(_ lines: String? = nil, status: String = "draft") throws -> InvoiceRecord {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(invoiceJSON.utf8)) as? [String: Any])
        object["status"] = status
        if let lines {
            object["lines"] = try JSONSerialization.jsonObject(with: Data("[\(lines)]".utf8))
        }
        let payload = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(InvoiceRecord.self, from: payload)
    }

    private func capacitor() -> PriceBookListItem {
        PriceBookListItem(
            id: "11111111-1111-4111-8111-111111111111", description: "Replace capacitor",
            unit: "each", kind: "material", taxClassification: "taxable",
            sellPrice: .init(amount: 12500, currency: "USD"), revision: 7, archivedAt: nil
        )
    }

    func testEditorUsesObservedRevisionAndConvertsDecimalPriceToExactCents() throws {
        let invoice = try makeInvoice()
        var state = InvoiceLineEditorState(invoice: invoice)
        XCTAssertFalse(state.hasChanges)
        state.lines[0].unitPrice = "12.35"
        state.lines[0].quantity = "4"
        XCTAssertTrue(state.hasChanges)

        let request = try state.makeRequest()

        XCTAssertEqual(request.expectedLinesRevision, 3)
        XCTAssertEqual(request.lines.first?.quantity, 4)
        XCTAssertEqual(request.lines.first?.unitPrice.amount, 1235)
        XCTAssertEqual(request.lines.first?.description, "Repair")
    }

    func testEditorReorderingIsAChangeAndPreservesLineOrderInRequest() throws {
        let first = #"{"id":"00000000-0000-4000-8000-00000000000b","description":"Repair","quantity":2,"unitPrice":{"amount":1250,"currency":"USD"},"source":{"kind":"manual"}}"#
        let second = #"{"id":"00000000-0000-4000-8000-00000000000c","description":"Inspection","quantity":1,"unitPrice":{"amount":500,"currency":"USD"},"source":{"kind":"manual"}}"#
        var state = InvoiceLineEditorState(invoice: try makeInvoice("\(first),\(second)"))
        let firstID = try XCTUnwrap(state.lines.first?.id)

        state.moveLine(id: firstID, to: 1)

        XCTAssertTrue(state.hasChanges)
        XCTAssertEqual(try state.makeRequest().lines.map(\.description), ["Inspection", "Repair"])
    }

    func testEditorRejectsEmptyLinesInvalidQuantityAndMoreThanTwoDecimalPlaces() throws {
        var state = InvoiceLineEditorState(invoice: try makeInvoice())
        state.lines.removeAll()
        XCTAssertThrowsError(try state.makeRequest()) { XCTAssertEqual($0 as? InvoiceLineEditorError, .noLines) }

        state.addManualLine()
        state.lines[0].description = "Repair"
        state.lines[0].quantity = "0"
        state.lines[0].unitPrice = "12.00"
        XCTAssertThrowsError(try state.makeRequest()) { XCTAssertEqual($0 as? InvoiceLineEditorError, .invalidQuantity) }

        state.lines[0].quantity = "1"
        state.lines[0].unitPrice = "12.345"
        XCTAssertThrowsError(try state.makeRequest()) { XCTAssertEqual($0 as? InvoiceLineEditorError, .invalidPrice) }
    }

    func testEditorRequiresReasonWhenRetainedPriceBookEvidenceIsChanged() throws {
        let source = #"{"kind":"price_book","priceBookItemId":"11111111-1111-4111-8111-111111111111","priceBookRevision":3,"originalDescription":"Capacitor","originalUnit":"each","originalUnitPrice":{"amount":12500,"currency":"USD"},"originalTaxClassification":"taxable","originalItemKind":"material","addedByUserId":"00000000-0000-4000-8000-000000000004","capturedAt":"2026-10-26T12:00:00Z","overriddenFields":[]}"#
        let line = #"{"id":"00000000-0000-4000-8000-00000000000b","description":"Capacitor","quantity":1,"unitPrice":{"amount":12500,"currency":"USD"},"source":\#(source)}"#
        let invoice = try makeInvoice(line)
        var state = InvoiceLineEditorState(invoice: invoice)
        state.lines[0].description = "After-hours capacitor"

        XCTAssertThrowsError(try state.makeRequest()) {
            XCTAssertEqual($0 as? InvoiceLineEditorError, .priceBookOverrideReasonRequired)
        }

        state.priceBookOverrideReason = "Customer approved after-hours scope change"
        let request = try state.makeRequest()
        XCTAssertEqual(request.priceBookOverrideReason, "Customer approved after-hours scope change")
    }

    func testEditorAddsOnlyActivePriceBookItemWithServerRevision() throws {
        let invoice = try makeInvoice()
        var state = InvoiceLineEditorState(invoice: invoice)
        let item = PriceBookListItem(
            id: "11111111-1111-4111-8111-111111111111", description: "Replace capacitor",
            unit: "each", kind: "material", taxClassification: "taxable",
            sellPrice: .init(amount: 12500, currency: "USD"), revision: 7, archivedAt: nil
        )

        try state.addPriceBookItem(item)
        let selected = try XCTUnwrap(state.makeRequest().lines.last)

        XCTAssertEqual(selected.description, "Replace capacitor")
        XCTAssertEqual(selected.unitPrice.amount, 12500)
        guard case .priceBookSelection(let id, let revision)? = selected.source else {
            return XCTFail("Expected exact Price Book selection intent")
        }
        XCTAssertEqual(id, item.id)
        XCTAssertEqual(revision, 7)
    }

    func testEditorRefusesUnknownLineProvenanceInsteadOfDroppingIt() throws {
        let line = #"{"id":"00000000-0000-4000-8000-00000000000c","description":"Protected line","quantity":1,"unitPrice":{"amount":1000,"currency":"USD"},"source":{"kind":"future_source"}}"#
        let state = InvoiceLineEditorState(invoice: try makeInvoice(line))

        XCTAssertTrue(state.hasUnsupportedLineSources)
        XCTAssertThrowsError(try state.makeRequest()) {
            XCTAssertEqual($0 as? InvoiceLineEditorError, .unsupportedLineSource)
        }
    }

    func testDraftInvoiceAddsAdjustsAndRemovesAPriceBookLineInOneSession() throws {
        var state = InvoiceLineEditorState(invoice: try makeInvoice())
        let before = state.lines.count

        try state.addPriceBookItem(capacitor())
        let added = try XCTUnwrap(state.lines.last)
        try state.setQuantity(added.id, 4)
        try state.setUnitPrice(added.id, cents: 9900)
        state.priceBookOverrideReason = "Customer approved the adjusted price"

        let editedRequest = try state.makeRequest()
        let edited = try XCTUnwrap(editedRequest.lines.last)
        XCTAssertEqual(edited.description, "Replace capacitor")
        XCTAssertEqual(edited.quantity, 4)
        XCTAssertEqual(edited.unitPrice.amount, 9900)
        XCTAssertEqual(editedRequest.priceBookOverrideReason, "Customer approved the adjusted price")

        try state.removeLine(id: added.id)
        let saved = try state.makeRequest()
        XCTAssertEqual(saved.lines.count, before)
        XCTAssertFalse(saved.lines.contains { $0.description == "Replace capacitor" })
    }

    func testCatalogQuantityCountsRetainedLinesAndANewSelection() throws {
        let source = #"{"kind":"price_book","priceBookItemId":"11111111-1111-4111-8111-111111111111","priceBookRevision":3,"originalDescription":"Capacitor","originalUnit":"each","originalUnitPrice":{"amount":12500,"currency":"USD"},"originalTaxClassification":"taxable","originalItemKind":"material","addedByUserId":"00000000-0000-4000-8000-000000000004","capturedAt":"2026-10-26T12:00:00Z","overriddenFields":[]}"#
        let line = #"{"id":"00000000-0000-4000-8000-00000000000b","description":"Capacitor","quantity":2,"unitPrice":{"amount":12500,"currency":"USD"},"source":\#(source)}"#
        var state = InvoiceLineEditorState(invoice: try makeInvoice(line))

        XCTAssertEqual(state.catalogQuantity(for: capacitor().id), 2)
        XCTAssertNil(state.catalogQuantity(for: "22222222-2222-4222-8222-222222222222"))

        try state.addPriceBookItem(capacitor())
        XCTAssertEqual(state.catalogQuantity(for: capacitor().id), 3)
    }

    func testIssuedPaidAndVoidInvoicesRefusePriceBookEdits() throws {
        let item = capacitor()
        for status in ["issued", "paid", "void"] {
            var state = InvoiceLineEditorState(invoice: try makeInvoice(status: status))
            let lineID = try XCTUnwrap(state.lines.first?.id)
            let quantity = state.lines[0].quantity
            let price = state.lines[0].unitPrice

            XCTAssertThrowsError(try state.addPriceBookItem(item)) {
                XCTAssertEqual($0 as? InvoiceLineEditorError, .notDraft)
            }
            XCTAssertThrowsError(try state.setQuantity(lineID, 4)) {
                XCTAssertEqual($0 as? InvoiceLineEditorError, .notDraft)
            }
            XCTAssertThrowsError(try state.setUnitPrice(lineID, cents: 9900)) {
                XCTAssertEqual($0 as? InvoiceLineEditorError, .notDraft)
            }
            XCTAssertThrowsError(try state.removeLine(id: lineID)) {
                XCTAssertEqual($0 as? InvoiceLineEditorError, .notDraft)
            }
            XCTAssertThrowsError(try state.makeRequest()) {
                XCTAssertEqual($0 as? InvoiceLineEditorError, .notDraft)
            }
            XCTAssertEqual(state.lines.count, 1)
            XCTAssertEqual(state.lines[0].quantity, quantity)
            XCTAssertEqual(state.lines[0].unitPrice, price)
        }
    }
}

import XCTest
@testable import Thorbis

final class EstimateRevisionEditorTests: XCTestCase {
    private let estimateID = "00000000-0000-4000-8000-000000000008"
    private let optionID = "00000000-0000-4000-8000-000000000010"

    private func makeEstimate(status: String = "sent", lines: String? = nil,
                              options: String? = nil, revision: Int? = 2) throws -> EstimateRecord {
        let lineJSON = lines ?? #"[{"id":"00000000-0000-4000-8000-000000000009","description":"Repair","quantity":2,"unitPrice":{"amount":1250,"currency":"USD"},"source":{"kind":"manual","addedByUserId":"00000000-0000-4000-8000-000000000004","capturedAt":"2026-10-26T12:00:00Z"}}]"#
        let revisionJSON = revision.map(String.init) ?? "null"
        let optionsJSON = options.map { ",\"options\":\($0)" } ?? ""
        let json = #"{"id":"\#(estimateID)","organizationId":"00000000-0000-4000-8000-000000000002","customerId":"00000000-0000-4000-8000-000000000003","createdByUserId":"00000000-0000-4000-8000-000000000004","status":"\#(status)","currentRevisionNumber":\#(revisionJSON),"title":"Repair quote","lines":\#(lineJSON)\#(optionsJSON),"createdAt":"2026-10-26T12:00:00Z","updatedAt":"2026-10-26T12:00:00Z"}"#
        return try JSONDecoder().decode(EstimateRecord.self, from: Data(json.utf8))
    }

    func testRevisionBuildsRequestWithCurrentRevisionAndOptionPackages() throws {
        let option = #"[{"id":"\#(optionID)","title":"Premium","description":"Higher efficiency","lines":[{"id":"00000000-0000-4000-8000-000000000011","description":"Premium repair","quantity":1,"unitPrice":{"amount":5000,"currency":"USD"},"source":{"kind":"manual","addedByUserId":"00000000-0000-4000-8000-000000000004","capturedAt":"2026-10-26T12:00:00Z"}}],"totalAmount":5000,"currency":"USD"}]"#
        var state = EstimateRevisionEditorState(estimate: try makeEstimate(options: option))
        state.title = "Updated repair quote"
        state.lines[0].unitPrice = "15.75"

        let request = try state.makeRequest(optionsFeatureEnabled: true, canDiscount: true)

        XCTAssertEqual(request.expectedRevisionNumber, 2)
        XCTAssertEqual(request.title, "Updated repair quote")
        XCTAssertEqual(request.lines.first?.unitPrice.amount, 1575)
        XCTAssertEqual(request.options?.first?.id, optionID)
        XCTAssertEqual(request.options?.first?.title, "Premium")
        XCTAssertEqual(request.options?.first?.lines.first?.description, "Premium repair")
    }

    func testRevisionPreservesExactPriceBookIdentityInMainAndOptionLines() throws {
        let source = #"{"kind":"price_book","priceBookItemId":"11111111-1111-4111-8111-111111111111","priceBookRevision":7,"originalDescription":"Capacitor","originalUnitPrice":{"amount":12500,"currency":"USD"},"addedByUserId":"00000000-0000-4000-8000-000000000004","capturedAt":"2026-10-26T12:00:00Z","overriddenFields":[]}"#
        let line = #"[{"id":"00000000-0000-4000-8000-000000000009","description":"Capacitor","quantity":1,"unitPrice":{"amount":12500,"currency":"USD"},"source":\#(source)}]"#
        let state = EstimateRevisionEditorState(estimate: try makeEstimate(lines: line))

        XCTAssertFalse(state.hasChanges)
        let request = try state.makeRequest(optionsFeatureEnabled: true, canDiscount: true)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        let encoded = try XCTUnwrap((body["lines"] as? [[String: Any]])?.first?["source"] as? [String: Any])

        XCTAssertEqual(encoded["kind"] as? String, "price_book")
        XCTAssertEqual(encoded["priceBookItemId"] as? String, "11111111-1111-4111-8111-111111111111")
        XCTAssertEqual(encoded["priceBookRevision"] as? Int, 7)
        XCTAssertEqual(Set(encoded.keys), Set(["kind", "priceBookItemId", "priceBookRevision"]))
    }

    func testRevisionAddsCurrentPriceBookSelectionWithExactRevision() throws {
        var state = EstimateRevisionEditorState(estimate: try makeEstimate())
        let item = PriceBookListItem(
            id: "11111111-1111-4111-8111-111111111111", description: "Replace capacitor",
            unit: "each", kind: "material", taxClassification: "taxable",
            sellPrice: .init(amount: 12500, currency: "USD"), revision: 7, archivedAt: nil
        )

        try state.addPriceBookItem(item)

        let selected = try XCTUnwrap(state.makeRequest(optionsFeatureEnabled: true, canDiscount: true).lines.last)
        XCTAssertEqual(selected.description, "Replace capacitor")
        XCTAssertEqual(selected.unitPrice.amount, 12500)
        XCTAssertEqual(selected.source, .priceBookSelection(itemID: item.id, revision: 7))
    }

    func testRevisionRejectsUnsupportedStatusesAndInvalidOptionCounts() throws {
        let approved = EstimateRevisionEditorState(estimate: try makeEstimate(status: "approved"))
        XCTAssertThrowsError(try approved.makeRequest(optionsFeatureEnabled: true, canDiscount: true)) {
            XCTAssertEqual($0 as? EstimateRevisionEditorError, .unsupportedStatus)
        }

        let noRevision = EstimateRevisionEditorState(estimate: try makeEstimate(revision: nil))
        XCTAssertTrue(noRevision.canRevise)
        XCTAssertThrowsError(try noRevision.makeRequest(optionsFeatureEnabled: true, canDiscount: true)) {
            XCTAssertEqual($0 as? EstimateRevisionEditorError, .missingRevision)
        }

        var state = EstimateRevisionEditorState(estimate: try makeEstimate())
        for index in 1...9 {
            state.options.append(.init(
                id: UUID().uuidString.lowercased(), title: "Option \(index)", description: "",
                lines: [.init(description: "Line", quantity: "1", unitPrice: "1.00", source: .manual)]
            ))
        }
        XCTAssertThrowsError(try state.makeRequest(optionsFeatureEnabled: true, canDiscount: true)) {
            XCTAssertEqual($0 as? EstimateRevisionEditorError, .tooManyOptions)
        }

        var capped = EstimateRevisionEditorState(estimate: try makeEstimate())
        for _ in 0..<9 { capped.addOption() }
        XCTAssertEqual(capped.options.count, 8)
    }

    func testRevisionRejectsInvalidMoneyQuantityAndEmptyLines() throws {
        var state = EstimateRevisionEditorState(estimate: try makeEstimate())
        state.lines[0].quantity = "0"
        XCTAssertThrowsError(try state.makeRequest(optionsFeatureEnabled: true, canDiscount: true)) {
            XCTAssertEqual($0 as? EstimateRevisionEditorError, .invalidQuantity)
        }

        state.lines[0].quantity = "1"
        state.lines[0].unitPrice = "12.345"
        XCTAssertThrowsError(try state.makeRequest(optionsFeatureEnabled: true, canDiscount: true)) {
            XCTAssertEqual($0 as? EstimateRevisionEditorError, .invalidPrice)
        }

        state.lines.removeAll()
        XCTAssertThrowsError(try state.makeRequest(optionsFeatureEnabled: true, canDiscount: true)) {
            XCTAssertEqual($0 as? EstimateRevisionEditorError, .noLines)
        }
    }

    func testRevisionRefusesUnknownProvenanceRatherThanDroppingIt() throws {
        let line = #"[{"id":"00000000-0000-4000-8000-000000000009","description":"Protected line","quantity":1,"unitPrice":{"amount":1000,"currency":"USD"},"source":{"kind":"future_source"}}]"#
        let state = EstimateRevisionEditorState(estimate: try makeEstimate(lines: line))

        XCTAssertTrue(state.hasUnsupportedLineSources)
        XCTAssertThrowsError(try state.makeRequest(optionsFeatureEnabled: true, canDiscount: true)) {
            XCTAssertEqual($0 as? EstimateRevisionEditorError, .unsupportedLineSource)
        }
    }

    func testOptionsRequireFeatureAndExistingOptionsCannotBeSilentlyDropped() throws {
        let option = #"[{"id":"\#(optionID)","title":"Premium","description":"Higher efficiency","lines":[{"id":"00000000-0000-4000-8000-000000000011","description":"Premium repair","quantity":1,"unitPrice":{"amount":5000,"currency":"USD"}}],"totalAmount":5000,"currency":"USD"}]"#
        let withOptions = EstimateRevisionEditorState(estimate: try makeEstimate(options: option))
        XCTAssertThrowsError(try withOptions.makeRequest(optionsFeatureEnabled: false, canDiscount: true)) {
            XCTAssertEqual($0 as? EstimateRevisionEditorError, .optionFeatureRequired)
        }

        let withoutOptions = EstimateRevisionEditorState(estimate: try makeEstimate())
        let request = try withoutOptions.makeRequest(optionsFeatureEnabled: false, canDiscount: true)
        XCTAssertNil(request.options)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        XCTAssertNil(body["options"])
    }

    func testCreditLinesRequireDiscountCapability() throws {
        var state = EstimateRevisionEditorState(estimate: try makeEstimate())
        state.lines[0].unitPrice = "-1.00"

        XCTAssertThrowsError(try state.makeRequest(optionsFeatureEnabled: true, canDiscount: false)) {
            XCTAssertEqual($0 as? EstimateRevisionEditorError, .discountCapabilityRequired)
        }
        XCTAssertEqual(try state.makeRequest(optionsFeatureEnabled: true, canDiscount: true).lines[0].unitPrice.amount, -100)
    }

    func testWhitespaceOnlyOptionEditsDoNotCreateARevision() throws {
        let option = #"[{"id":"\#(optionID)","title":"Premium","description":"Higher efficiency","lines":[{"id":"00000000-0000-4000-8000-000000000011","description":"Premium repair","quantity":1,"unitPrice":{"amount":5000,"currency":"USD"}}],"totalAmount":5000,"currency":"USD"}]"#
        var state = EstimateRevisionEditorState(estimate: try makeEstimate(options: option))
        state.options[0].title = "  Premium\n"
        state.options[0].description = "Higher efficiency  "

        XCTAssertFalse(state.hasChanges)
    }

    func testDuplicateOptionIDsAreRejected() throws {
        var state = EstimateRevisionEditorState(estimate: try makeEstimate())
        let duplicate = EstimateRevisionOptionDraft(
            id: optionID, title: "First", description: "",
            lines: [.init(description: "Part", quantity: "1", unitPrice: "1.00", source: .manual)]
        )
        state.options = [duplicate, duplicate]

        XCTAssertThrowsError(try state.makeRequest(optionsFeatureEnabled: true, canDiscount: true)) {
            XCTAssertEqual($0 as? EstimateRevisionEditorError, .duplicateOptionID)
        }
    }

    func testDraftEstimateAddsAdjustsAndRemovesAPriceBookLineInOneSession() throws {
        var state = EstimateRevisionEditorState(estimate: try makeEstimate(status: "draft", revision: nil))
        XCTAssertTrue(state.canRevise)
        let before = state.lines.count
        let item = PriceBookListItem(
            id: "11111111-1111-4111-8111-111111111111", description: "Replace capacitor",
            unit: "each", kind: "material", taxClassification: "taxable",
            sellPrice: .init(amount: 12500, currency: "USD"), revision: 7, archivedAt: nil
        )

        try state.addPriceBookItem(item)
        let added = try XCTUnwrap(state.lines.last)
        try state.setQuantity(added.id, 4)
        try state.setUnitPrice(added.id, cents: 9900)

        let edited = try state.makeRequest(optionsFeatureEnabled: true, canDiscount: true)
        XCTAssertEqual(edited.expectedRevisionNumber, 0)
        XCTAssertEqual(edited.lines.last?.description, "Replace capacitor")
        XCTAssertEqual(edited.lines.last?.quantity, 4)
        XCTAssertEqual(edited.lines.last?.unitPrice.amount, 9900)

        try state.removeLine(id: added.id)
        let saved = try state.makeRequest(optionsFeatureEnabled: true, canDiscount: true)
        XCTAssertEqual(saved.expectedRevisionNumber, 0)
        XCTAssertEqual(saved.lines.count, before)
        XCTAssertFalse(saved.lines.contains { $0.description == "Replace capacitor" })
    }

    func testDraftEstimateKeepsAnExistingRevisionNumber() throws {
        let state = EstimateRevisionEditorState(estimate: try makeEstimate(status: "draft", revision: 5))
        let request = try state.makeRequest(optionsFeatureEnabled: true, canDiscount: true)
        XCTAssertEqual(request.expectedRevisionNumber, 5)
    }

    func testApprovedEstimateRefusesPriceBookEdits() throws {
        var state = EstimateRevisionEditorState(estimate: try makeEstimate(status: "approved"))
        XCTAssertFalse(state.canRevise)
        let item = PriceBookListItem(
            id: "11111111-1111-4111-8111-111111111111", description: "Replace capacitor",
            unit: "each", kind: "material", taxClassification: "taxable",
            sellPrice: .init(amount: 12500, currency: "USD"), revision: 7, archivedAt: nil
        )
        let lineID = try XCTUnwrap(state.lines.first?.id)
        let quantity = state.lines[0].quantity
        let price = state.lines[0].unitPrice

        XCTAssertThrowsError(try state.addPriceBookItem(item)) {
            XCTAssertEqual($0 as? EstimateRevisionEditorError, .unsupportedStatus)
        }
        XCTAssertThrowsError(try state.setQuantity(lineID, 4)) {
            XCTAssertEqual($0 as? EstimateRevisionEditorError, .unsupportedStatus)
        }
        XCTAssertThrowsError(try state.setUnitPrice(lineID, cents: 9900)) {
            XCTAssertEqual($0 as? EstimateRevisionEditorError, .unsupportedStatus)
        }
        XCTAssertThrowsError(try state.removeLine(id: lineID)) {
            XCTAssertEqual($0 as? EstimateRevisionEditorError, .unsupportedStatus)
        }
        XCTAssertThrowsError(try state.makeRequest(optionsFeatureEnabled: true, canDiscount: true)) {
            XCTAssertEqual($0 as? EstimateRevisionEditorError, .unsupportedStatus)
        }
        XCTAssertEqual(state.lines.count, 1)
        XCTAssertEqual(state.lines[0].quantity, quantity)
        XCTAssertEqual(state.lines[0].unitPrice, price)
    }
}

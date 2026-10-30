import XCTest
@testable import Thorbis

final class EstimateBuilderTests: XCTestCase {
    private func item(_ id: Int, _ description: String, kind: String, cents: Int) -> PriceBookListItem {
        PriceBookListItem(id: String(format: "00000000-0000-4000-8000-%012d", id), description: description,
                          unit: "each", kind: kind, taxClassification: "taxable",
                          sellPrice: FieldMoney(amount: cents, currency: "USD"), revision: 3, archivedAt: nil)
    }

    func testPriceBookItemsLandInTheirGroupWithWorkFirst() {
        var lines: [EstimateRevisionLineDraft] = []
        lines.addPriceBookItem(item(1, "Capacitor", kind: "material", cents: 14_500))
        lines.addPriceBookItem(item(2, "Diagnostic visit", kind: "service", cents: 8_900))
        lines.addPriceBookItem(item(3, "Labor", kind: "labor", cents: 14_000))

        XCTAssertEqual(lines.map(\.description), ["Diagnostic visit", "Labor", "Capacitor"])
        XCTAssertEqual(lines.map(\.group), [.work, .work, .material])
        XCTAssertEqual(lines.subtotal(.work), 22_900)
        XCTAssertEqual(lines.subtotal(.material), 14_500)
        XCTAssertEqual(lines.subtotal(), 37_400)
    }

    func testSecondTapAddsOneMoreInsteadOfADuplicate() {
        var lines: [EstimateRevisionLineDraft] = []
        let capacitor = item(1, "Capacitor", kind: "material", cents: 14_500)
        let first = lines.addPriceBookItem(capacitor)
        let second = lines.addPriceBookItem(capacitor)

        XCTAssertEqual(first, second)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].quantity, "2")
        XCTAssertEqual(lines.quantity(ofPriceBookItem: capacitor.id), 2)
    }

    func testAnEditedLineIsNotBumpedAndCanResetToThePriceBook() throws {
        var lines: [EstimateRevisionLineDraft] = []
        let capacitor = item(1, "Capacitor", kind: "material", cents: 14_500)
        lines.addPriceBookItem(capacitor)
        lines[0].unitPrice = "130.00"
        lines[0].description = "Capacitor, customer supplied mount"
        XCTAssertTrue(lines[0].isEditedPriceBookLine)

        lines.addPriceBookItem(capacitor)
        XCTAssertEqual(lines.count, 2, "an edited line keeps its own price")

        lines.resetToPriceBook(id: lines[0].id)
        XCTAssertEqual(lines[0].description, "Capacitor")
        XCTAssertEqual(lines[0].unitPrice, "145.00")
        XCTAssertFalse(lines[0].isEditedPriceBookLine)
    }

    func testCustomLineTakesTheTypedWordsAndAskedGroup() throws {
        var lines: [EstimateRevisionLineDraft] = []
        lines.addPriceBookItem(item(1, "Capacitor", kind: "material", cents: 14_500))
        let id = try XCTUnwrap(lines.addCustomLine("  Haul away old unit ", to: .work))

        XCTAssertEqual(lines.first?.id, id)
        XCTAssertEqual(lines.first?.description, "Haul away old unit")
        XCTAssertEqual(lines.first?.unitPrice, "")
        XCTAssertNil(lines.subtotal(), "a line without a price has no total yet")
    }

    func testDragMovesWithinAndAcrossGroups() {
        var lines: [EstimateRevisionLineDraft] = []
        let a = lines.addCustomLine("A", to: .work)!
        let b = lines.addCustomLine("B", to: .work)!
        let c = lines.addCustomLine("C", to: .material)!

        lines.moveLine(id: b, before: a, group: .work)
        XCTAssertEqual(lines.map(\.description), ["B", "A", "C"])

        lines.moveLine(id: a, before: c, group: .material)
        XCTAssertEqual(lines.map(\.description), ["B", "A", "C"])
        XCTAssertEqual(lines.map(\.group), [.work, .material, .material])

        lines.moveLine(id: c, before: nil, group: .work)
        XCTAssertEqual(lines.map(\.description), ["B", "C", "A"])
        XCTAssertEqual(lines.map(\.group), [.work, .work, .material])
    }

    func testMoveUpAndDownStayInsideTheGroup() {
        var lines: [EstimateRevisionLineDraft] = []
        let a = lines.addCustomLine("A", to: .work)!
        _ = lines.addCustomLine("B", to: .work)
        let m = lines.addCustomLine("M", to: .material)!

        lines.moveLine(id: a, by: 1)
        XCTAssertEqual(lines.map(\.description), ["B", "A", "M"])
        lines.moveLine(id: a, by: 1)
        XCTAssertEqual(lines.map(\.description), ["B", "A", "M"], "the last Work line doesn't fall into Materials")
        lines.moveLine(id: m, by: -1)
        XCTAssertEqual(lines.map(\.description), ["B", "A", "M"])
        lines.moveLine(id: a, by: -1)
        XCTAssertEqual(lines.map(\.description), ["A", "B", "M"])
    }

    func testRemoveAndUndoRestoresThePosition() throws {
        var lines: [EstimateRevisionLineDraft] = []
        _ = lines.addCustomLine("A", to: .work)
        let b = lines.addCustomLine("B", to: .work)!
        _ = lines.addCustomLine("C", to: .work)

        let removed = try XCTUnwrap(lines.removeLine(id: b))
        XCTAssertEqual(lines.map(\.description), ["A", "C"])
        lines.restoreLine(removed.line, at: removed.index)
        XCTAssertEqual(lines.map(\.description), ["A", "B", "C"])
        lines.restoreLine(removed.line, at: removed.index)
        XCTAssertEqual(lines.count, 3, "undo twice doesn't duplicate")
    }

    func testDuplicateMakesANewLineBelow() throws {
        var lines: [EstimateRevisionLineDraft] = []
        let a = lines.addCustomLine("A", to: .work)!
        let copy = try XCTUnwrap(lines.duplicateLine(id: a))
        XCTAssertNotEqual(copy, a)
        XCTAssertEqual(lines.map(\.description), ["A", "A"])
    }

    func testLoadedPriceBookMaterialsMoveToMaterialsByCatalogKind() throws {
        let estimateJSON = #"{"id":"00000000-0000-4000-8000-000000000008","organizationId":"00000000-0000-4000-8000-000000000002","customerId":"00000000-0000-4000-8000-000000000003","createdByUserId":"00000000-0000-4000-8000-000000000004","status":"sent","currentRevisionNumber":2,"title":"Repair","lines":[{"id":"00000000-0000-4000-8000-000000000011","description":"Capacitor","quantity":1,"unitPrice":{"amount":14500,"currency":"USD"},"source":{"kind":"price_book","priceBookItemId":"00000000-0000-4000-8000-000000000001","priceBookRevision":3,"originalDescription":"Capacitor","originalUnitPrice":{"amount":15000,"currency":"USD"},"addedByUserId":"00000000-0000-4000-8000-000000000004","capturedAt":"2026-10-26T12:00:00Z","overriddenFields":["unit_price"]}},{"id":"00000000-0000-4000-8000-000000000012","description":"Repair","quantity":1,"unitPrice":{"amount":9000,"currency":"USD"},"source":{"kind":"manual","addedByUserId":"00000000-0000-4000-8000-000000000004","capturedAt":"2026-10-26T12:00:00Z"}}],"createdAt":"2026-10-26T12:00:00Z","updatedAt":"2026-10-26T12:00:00Z"}"#
        let estimate = try JSONDecoder().decode(EstimateRecord.self, from: Data(estimateJSON.utf8))
        var state = EstimateRevisionEditorState(estimate: estimate)
        XCTAssertTrue(state.lines[0].isEditedPriceBookLine, "the stored original price shows the edit")

        state.classify(kinds: ["00000000-0000-4000-8000-000000000001": "material"])
        XCTAssertEqual(state.lines.map(\.description), ["Repair", "Capacitor"])
        XCTAssertEqual(state.lines.map(\.group), [.work, .material])

        let request = try state.makeRequest(optionsFeatureEnabled: true, canDiscount: true)
        XCTAssertEqual(request.lines.map(\.description), ["Repair", "Capacitor"], "saved order is the order on screen")
    }

    func testACatalogRefreshNeverUndoesAGroupThePersonChose() throws {
        let estimateJSON = #"{"id":"00000000-0000-4000-8000-000000000008","organizationId":"00000000-0000-4000-8000-000000000002","customerId":"00000000-0000-4000-8000-000000000003","createdByUserId":"00000000-0000-4000-8000-000000000004","status":"sent","currentRevisionNumber":2,"title":"Repair","lines":[{"id":"00000000-0000-4000-8000-000000000011","description":"Capacitor","quantity":1,"unitPrice":{"amount":14500,"currency":"USD"},"source":{"kind":"price_book","priceBookItemId":"00000000-0000-4000-8000-000000000001","priceBookRevision":3,"addedByUserId":"00000000-0000-4000-8000-000000000004","capturedAt":"2026-10-26T12:00:00Z"}},{"id":"00000000-0000-4000-8000-000000000012","description":"Repair","quantity":1,"unitPrice":{"amount":9000,"currency":"USD"},"source":{"kind":"manual","addedByUserId":"00000000-0000-4000-8000-000000000004","capturedAt":"2026-10-26T12:00:00Z"}}],"createdAt":"2026-10-26T12:00:00Z","updatedAt":"2026-10-26T12:00:00Z"}"#
        let estimate = try JSONDecoder().decode(EstimateRecord.self, from: Data(estimateJSON.utf8))
        var state = EstimateRevisionEditorState(estimate: estimate)
        let kinds = ["00000000-0000-4000-8000-000000000001": "material"]

        // The person drags the capacitor ahead of Repair in Work before the catalog arrives.
        let capacitor = state.lines[0].id, repair = state.lines[1].id
        state.lines.moveLine(id: capacitor, before: repair, group: .work)
        state.classify(kinds: kinds)
        XCTAssertEqual(state.lines.map(\.description), ["Capacitor", "Repair"])
        XCTAssertEqual(state.lines.map(\.group), [.work, .work])

        // A line the catalog already sorted keeps the person's later move too.
        var loaded = EstimateRevisionEditorState(estimate: estimate)
        loaded.classify(kinds: kinds)
        loaded.lines.setGroup(id: loaded.lines[1].id, .work)
        loaded.classify(kinds: kinds)
        XCTAssertEqual(loaded.lines.map(\.group), [.work, .work])
    }

    // MARK: Materials switch (EB-13)

    private let groupedEstimateJSON = #"{"id":"00000000-0000-4000-8000-000000000008","organizationId":"00000000-0000-4000-8000-000000000002","customerId":"00000000-0000-4000-8000-000000000003","createdByUserId":"00000000-0000-4000-8000-000000000004","status":"sent","currentRevisionNumber":2,"title":"Repair","lines":[{"id":"00000000-0000-4000-8000-000000000012","description":"Repair","quantity":1,"unitPrice":{"amount":9000,"currency":"USD"},"group":"work"},{"id":"00000000-0000-4000-8000-000000000011","description":"Capacitor","quantity":1,"unitPrice":{"amount":14500,"currency":"USD"},"group":"material","showToCustomer":false}],"createdAt":"2026-10-26T12:00:00Z","updatedAt":"2026-10-26T12:00:00Z"}"#

    func testStoredGroupsAndTheSwitchLoadAsSaved() throws {
        let estimate = try JSONDecoder().decode(EstimateRecord.self, from: Data(groupedEstimateJSON.utf8))
        var state = EstimateRevisionEditorState(estimate: estimate)
        state.storesLineGroups = true
        XCTAssertEqual(state.lines.map(\.group), [.work, .material])
        XCTAssertFalse(state.lines.showsMaterials)
        XCTAssertFalse(state.hasChanges, "the saved group and switch are not an edit")

        // The catalog never re-sorts a group the server stored.
        state.classify(kinds: [:])
        XCTAssertEqual(state.lines.map(\.group), [.work, .material])

        state.lines.setShowsMaterials(true)
        XCTAssertTrue(state.hasChanges, "turning the switch on is a change to save")
        let request = try state.makeRequest(optionsFeatureEnabled: true, canDiscount: true)
        XCTAssertEqual(request.lines.map(\.group), ["work", "material"])
        XCTAssertEqual(request.lines.map(\.showToCustomer), [nil, nil], "shown is the default and is not sent")
    }

    func testTheSwitchHidesEveryMaterialIncludingOnesAddedLater() throws {
        var lines: [EstimateRevisionLineDraft] = []
        lines.addPriceBookItem(item(1, "Capacitor", kind: "material", cents: 14_500), to: .material)
        _ = lines.addCustomLine("Labor", to: .work)
        lines.setShowsMaterials(false)
        lines.addPriceBookItem(item(2, "Contactor", kind: "material", cents: 4_000), to: .material)
        XCTAssertFalse(lines.showsMaterials)
        let stored = lines.map { lines.storedPresentation(of: $0, storesGroups: true) }
        XCTAssertEqual(stored.map(\.group), ["work", "material", "material"])
        XCTAssertEqual(stored.map(\.showToCustomer), [nil, false, false])
    }

    func testAMaterialAddedWhileHiddenStaysHiddenAfterTheOthersGo() throws {
        var lines: [EstimateRevisionLineDraft] = []
        let first = lines.addPriceBookItem(item(1, "Capacitor", kind: "material", cents: 14_500), to: .material)
        lines.setShowsMaterials(false)
        let later = lines.addCustomLine("Fuse", to: .material)
        let copy = lines.duplicateLine(id: try XCTUnwrap(later))
        _ = lines.removeLine(id: try XCTUnwrap(first))
        XCTAssertNotNil(copy)
        XCTAssertFalse(lines.showsMaterials, "removing the first hidden material keeps the switch off")

        // Moving the only material keeps it hidden too.
        _ = lines.removeLine(id: try XCTUnwrap(copy))
        lines.setGroup(id: try XCTUnwrap(later), .material)
        XCTAssertFalse(lines.showsMaterials)
    }

    func testMovingALineSavedBeforeGroupsIsAChange() throws {
        let json = groupedEstimateJSON.replacingOccurrences(of: #","group":"work""#, with: "")
            .replacingOccurrences(of: #","group":"material","showToCustomer":false"#, with: "")
        let estimate = try JSONDecoder().decode(EstimateRecord.self, from: Data(json.utf8))
        var state = EstimateRevisionEditorState(estimate: estimate)
        state.storesLineGroups = true
        XCTAssertFalse(state.hasChanges)
        state.lines.setGroup(id: state.lines[1].id, .material)
        XCTAssertTrue(state.hasChanges, "dragging into Materials must be saved")
    }

    func testNothingNewIsSentUntilTheWorkspaceStoresGroups() throws {
        let estimate = try JSONDecoder().decode(EstimateRecord.self, from: Data(groupedEstimateJSON.utf8))
        var state = EstimateRevisionEditorState(estimate: estimate)
        state.lines.setShowsMaterials(true)
        XCTAssertFalse(state.hasChanges, "without the feature the switch is not shown or saved")
        state.title = "Repair visit"
        let request = try state.makeRequest(optionsFeatureEnabled: true, canDiscount: true)
        XCTAssertEqual(request.lines.map(\.group), [nil, nil])
        XCTAssertEqual(request.lines.map(\.showToCustomer), [nil, nil])
        let body = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        XCTAssertFalse(body.contains("showToCustomer"))
        XCTAssertFalse(body.contains("\"group\""))
    }

    func testTheCustomerSeesHiddenMaterialsAsOneLineWithTheSameTotal() throws {
        let estimate = try JSONDecoder().decode(EstimateRecord.self, from: Data(groupedEstimateJSON.utf8))
        let shown = customerEstimateLines(estimate.lines)
        XCTAssertEqual(shown.map(\.description), ["Repair", "Materials"])
        XCTAssertEqual(shown.last?.unitPrice.amount, 14_500)
        XCTAssertEqual(paperLinesTotal(shown), paperLinesTotal(estimate.lines))
    }
}

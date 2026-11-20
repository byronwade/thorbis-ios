import XCTest
@testable import Thorbis

@MainActor
final class VendorsRecordsTests: XCTestCase {
    private let orgA = "00000000-0000-4000-8000-000000000003"
    private let orgB = "00000000-0000-4000-8000-000000000004"

    private func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    func testLineAndOrderTotals() {
        let lines = [PurchaseOrderLine(description: "Refrigerant", quantity: 2, unitCostCents: 8_200),
                     PurchaseOrderLine(description: "Relay", quantity: 1, unitCostCents: 2_800)]
        XCTAssertEqual(lines[0].totalCents, 16_400)
        XCTAssertEqual(PurchaseOrderMath.total(lines), 19_200)
        XCTAssertEqual(PurchaseOrderMath.orderedUnits(lines), 3)
        XCTAssertEqual(PurchaseOrderMath.total([]), 0)
        XCTAssertEqual(PurchaseOrderMath.money(19_200, alwaysCents: true), "$192.00")
        XCTAssertEqual(PurchaseOrderMath.money(124_000), "$1,240")
        XCTAssertEqual(PurchaseOrderMath.money(61_840), "$618.40")
    }

    func testLineClampsQuantityCostAndReceived() {
        let line = PurchaseOrderLine(description: "Pump", quantity: 0, unitCostCents: -5, received: 9)
        XCTAssertEqual(line.quantity, 1)
        XCTAssertEqual(line.unitCostCents, 0)
        XCTAssertEqual(line.received, 1)
    }

    func testNumbersIncrementPerWorkspaceAndAreNotReused() throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let records = try VendorsRecords(organizationID: orgA, directory: directory)
        let vendor = VendorRecord(name: "Ferguson Supply")
        try records.save(vendor)
        let first = try records.createOrder(vendorID: vendor.id)
        let second = try records.createOrder(vendorID: vendor.id)
        XCTAssertEqual(first.numberLabel, "PO-0001")
        XCTAssertEqual(second.numberLabel, "PO-0002")
        try records.removeOrder(second.id)
        XCTAssertEqual(try records.createOrder(vendorID: vendor.id).number, 3)

        // The count survives a relaunch, and another workspace starts from 1 with nothing in it.
        let reopened = try VendorsRecords(organizationID: orgA, directory: directory)
        XCTAssertEqual(reopened.nextOrderNumber, 4)
        XCTAssertEqual(reopened.orders.map(\.number), [3, 1])
        let other = try VendorsRecords(organizationID: orgB, directory: directory)
        XCTAssertTrue(other.vendors.isEmpty)
        XCTAssertTrue(other.orders.isEmpty)
        XCTAssertEqual(other.nextOrderNumber, 1)
        XCTAssertFalse(reopened.fileURL.lastPathComponent.contains(orgA))
        XCTAssertEqual(PurchaseOrderMath.numberLabel(12_345), "PO-12345")
    }

    func testOrderNeedsAKnownVendorAndAVendorNeedsAName() throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let records = try VendorsRecords(organizationID: orgA, directory: directory)
        XCTAssertThrowsError(try records.createOrder(vendorID: "missing"))
        XCTAssertThrowsError(try records.save(VendorRecord(name: "  ")))
        XCTAssertEqual(records.nextOrderNumber, 1)
        XCTAssertThrowsError(try VendorsRecords(organizationID: " ", directory: directory))
    }

    func testStatusGoesDraftOrderedReceivedWithPartialReceipt() throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let records = try VendorsRecords(organizationID: orgA, directory: directory)
        let vendor = VendorRecord(name: "CoolAir Supply Co.")
        try records.save(vendor)
        let capacitor = PurchaseOrderLine(description: "Run capacitor", quantity: 1, unitCostCents: 1_500)
        let contactor = PurchaseOrderLine(description: "Contactor 40A", quantity: 2, unitCostCents: 2_800)
        let order = try records.createOrder(vendorID: vendor.id, lines: [capacitor, contactor])
        XCTAssertEqual(records.order(order.id)?.status, .draft)

        // Nothing is checked in on a draft, and an empty draft cannot be ordered.
        XCTAssertThrowsError(try records.receive(order.id, counts: [capacitor.id: 1]))
        let empty = try records.createOrder(vendorID: vendor.id)
        XCTAssertThrowsError(try records.markOrdered(empty.id))

        try records.markOrdered(order.id)
        XCTAssertEqual(records.order(order.id)?.status, .ordered)
        XCTAssertEqual(records.order(order.id)?.isPartlyReceived, false)

        // One contactor is back-ordered: the order stays open.
        try records.receive(order.id, counts: [capacitor.id: 1, contactor.id: 1])
        var saved = try XCTUnwrap(records.order(order.id))
        XCTAssertEqual(saved.status, .ordered)
        XCTAssertTrue(saved.isPartlyReceived)
        XCTAssertEqual(saved.receivedUnits, 2)
        XCTAssertEqual(saved.orderedUnits, 3)
        XCTAssertNil(saved.receivedAt)
        XCTAssertEqual(PurchaseOrderMath.onOrder(records.orders, vendorID: vendor.id), 2_800)
        XCTAssertThrowsError(try records.backToDraft(order.id))

        // Counts never go down and never pass what was ordered.
        try records.receive(order.id, counts: [capacitor.id: 0, contactor.id: 7])
        saved = try XCTUnwrap(records.order(order.id))
        XCTAssertEqual(saved.lines.map(\.received), [1, 2])
        XCTAssertEqual(saved.status, .received)
        XCTAssertNotNil(saved.receivedAt)
        XCTAssertEqual(PurchaseOrderMath.onOrder(records.orders, vendorID: vendor.id), 0)
        XCTAssertEqual(try VendorsRecords(organizationID: orgA, directory: directory).order(order.id)?.status, .received)
    }

    func testReceivingLeavesUnlistedLinesAlone() {
        let first = PurchaseOrderLine(description: "A", quantity: 3, unitCostCents: 100, received: 1)
        let second = PurchaseOrderLine(description: "B", quantity: 2, unitCostCents: 100)
        let result = PurchaseOrderMath.receiving([first, second], counts: [second.id: 2])
        XCTAssertEqual(result.map(\.received), [1, 2])
        XCTAssertEqual(PurchaseOrderMath.status(lines: result, orderedAt: Date()), .ordered)
        XCTAssertEqual(PurchaseOrderMath.status(lines: result, orderedAt: nil), .draft)
        XCTAssertEqual(PurchaseOrderMath.status(lines: [], orderedAt: Date()), .ordered)
    }

    func testBackToDraftBeforeAnythingArrives() throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let records = try VendorsRecords(organizationID: orgA, directory: directory)
        let vendor = VendorRecord(name: "Valley Electric")
        try records.save(vendor)
        let order = try records.createOrder(vendorID: vendor.id, lines: [PurchaseOrderLine(description: "Breaker", quantity: 1, unitCostCents: 900)])
        try records.markOrdered(order.id)
        try records.backToDraft(order.id)
        XCTAssertEqual(records.order(order.id)?.status, .draft)
    }

    func testSpendCountsOrdersMarkedOrderedInThatYear() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let thisYear = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 20)))
        let lastYear = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 7, day: 20)))
        let line = PurchaseOrderLine(description: "Pipe", quantity: 2, unitCostCents: 5_000)
        let orders = [
            PurchaseOrderRecord(number: 1, vendorID: "v", vendorName: "V", lines: [line], orderedAt: thisYear),
            PurchaseOrderRecord(number: 2, vendorID: "v", vendorName: "V", lines: [line], orderedAt: lastYear),
            PurchaseOrderRecord(number: 3, vendorID: "v", vendorName: "V", lines: [line]),
            PurchaseOrderRecord(number: 4, vendorID: "other", vendorName: "O", lines: [line], orderedAt: thisYear),
        ]
        XCTAssertEqual(PurchaseOrderMath.spend(orders, vendorID: "v", year: 2026, calendar: calendar), 10_000)
        XCTAssertEqual(PurchaseOrderMath.spend(orders, vendorID: "v", year: 2024, calendar: calendar), 0)
    }

    func testVendorEditRenamesItsOrdersAndRemovalKeepsThem() throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let records = try VendorsRecords(organizationID: orgA, directory: directory)
        var vendor = VendorRecord(name: "Ferguson", phone: "(555) 010-0172", email: "po@vendor.example", accountNumber: "48299034", terms: "Net 30")
        try records.save(vendor)
        let order = try records.createOrder(vendorID: vendor.id, note: "Truck restock")
        vendor.name = "Ferguson Supply"
        try records.save(vendor)
        XCTAssertEqual(records.vendors.count, 1)
        XCTAssertEqual(records.order(order.id)?.vendorName, "Ferguson Supply")
        XCTAssertEqual(vendor.maskedAccount, "\u{2022}\u{2022}\u{2022}\u{2022} 9034")
        XCTAssertEqual(vendor.accountLine, "#9034 \u{00B7} Net 30")
        XCTAssertEqual(vendor.callURL?.absoluteString, "tel:5550100172")
        XCTAssertEqual(vendor.mailURL?.absoluteString, "mailto:po@vendor.example")
        XCTAssertNil(VendorRecord(name: "No phone", phone: "12").callURL)
        try records.removeVendor(vendor.id)
        XCTAssertTrue(records.vendors.isEmpty)
        XCTAssertEqual(records.orders(for: vendor.id).first?.vendorName, "Ferguson Supply")
    }

    func testSharedTextListsItemsAndTotal() {
        let order = PurchaseOrderRecord(number: 7, vendorID: "v", vendorName: "Ferguson Supply", note: "Truck restock", lines: [
            PurchaseOrderLine(description: "Contactor relay, 24V", quantity: 2, unitCostCents: 2_800),
        ])
        let text = PurchaseOrderDocument.text(order, vendor: nil, company: "Northside HVAC")
        XCTAssertTrue(text.contains("Purchase order PO-0007"))
        XCTAssertTrue(text.contains("From: Northside HVAC"))
        XCTAssertTrue(text.contains("To: Ferguson Supply"))
        XCTAssertTrue(text.contains("2 x Contactor relay, 24V at $28.00 = $56.00"))
        XCTAssertTrue(text.hasSuffix("Total: $56.00"))
        XCTAssertEqual(PurchaseOrderDocument.fileName(order), "PO-0007.pdf")
    }
}

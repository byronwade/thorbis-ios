import XCTest
@testable import Thorbis

/// The equipment form and the invoice discount sheet catch text the server would refuse as too
/// long before anything is sent. The server trims, then counts UTF-16 units.
final class FieldLengthLimitTests: XCTestCase {
    func testEquipmentLimitsMatchTheServer() {
        XCTAssertEqual(EquipmentTextField.name.limit, 200)
        XCTAssertEqual(EquipmentTextField.notes.limit, 2000)
        for field in [EquipmentTextField.kind, .brand, .model, .serialNumber] {
            XCTAssertEqual(field.limit, 120)
        }
    }

    func testA121CharacterBrandIsCaughtAnd120IsNot() {
        var input = EquipmentInput(name: "Condenser", brand: String(repeating: "b", count: 121))
        XCTAssertTrue(input.isTooLong(.brand))
        XCTAssertEqual(input.tooLongFields, [.brand])
        input.brand = String(repeating: "b", count: 120)
        XCTAssertFalse(input.isTooLong(.brand))
        XCTAssertEqual(input.tooLongFields, [])
    }

    func testEquipmentCountsAfterTrimmingLikeTheServer() {
        let input = EquipmentInput(name: "  " + String(repeating: "n", count: 200) + "\n",
                                   serialNumber: " " + String(repeating: "s", count: 120) + " ")
        XCTAssertEqual(input.tooLongFields, [])
    }

    func testEquipmentCountsUTF16UnitsNotCharacters() {
        // 61 thumbs up are 61 characters but 122 UTF-16 units.
        let input = EquipmentInput(name: "Condenser", model: String(repeating: "\u{1F44D}", count: 61))
        XCTAssertEqual(input.model?.count, 61)
        XCTAssertTrue(input.isTooLong(.model))
    }

    func testEveryLongEquipmentFieldIsListedInFormOrder() {
        let input = EquipmentInput(name: String(repeating: "n", count: 201), kind: String(repeating: "k", count: 121),
                                   brand: "Trane", model: String(repeating: "m", count: 121),
                                   serialNumber: String(repeating: "s", count: 121), notes: String(repeating: "x", count: 2001))
        XCTAssertEqual(input.tooLongFields, [.name, .kind, .model, .serialNumber, .notes])
        XCTAssertFalse(input.isTooLong(.brand))
    }

    func testEquipmentLeavesTheTypedTextAlone() throws {
        let long = String(repeating: "b", count: 121)
        let input = EquipmentInput(name: "Condenser", brand: long)
        XCTAssertTrue(input.isTooLong(.brand))
        XCTAssertEqual(input.brand, long)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) as? [String: Any]
        XCTAssertEqual(json?["brand"] as? String, long)
    }

    func testA201CharacterDiscountReasonIsCaughtAnd200IsNot() {
        XCTAssertTrue(InvoiceDiscountReason.isTooLong(String(repeating: "r", count: 201)))
        XCTAssertFalse(InvoiceDiscountReason.isTooLong(String(repeating: "r", count: 200)))
        XCTAssertFalse(InvoiceDiscountReason.isTooLong("  " + String(repeating: "r", count: 200) + "  "))
    }

    func testDiscountReasonCountsUTF16Units() {
        // 101 thumbs up are 101 characters but 202 UTF-16 units.
        XCTAssertTrue(InvoiceDiscountReason.isTooLong(String(repeating: "\u{1F44D}", count: 101)))
        XCTAssertFalse(InvoiceDiscountReason.isTooLong(String(repeating: "\u{1F44D}", count: 100)))
    }
}

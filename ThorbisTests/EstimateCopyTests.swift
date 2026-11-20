import XCTest
@testable import Thorbis

final class EstimateCopyTests: XCTestCase {
    private let customer = "00000000-0000-4000-8000-000000000003"
    private let other = "00000000-0000-4000-8000-0000000000c2"
    private let me = "00000000-0000-4000-8000-000000000004"

    private func line(_ description: String = "Capacitor", quantity: Int = 1, amount: Int = 12_500, currency: String = "USD",
                      source: String = #"{"kind":"manual"}"#, extra: String = "") -> String {
        #"{"id":"\#(UUID().uuidString)","description":"\#(description)","quantity":\#(quantity),"unitPrice":{"amount":\#(amount),"currency":"\#(currency)"},"source":\#(source)\#(extra)}"#
    }

    private func estimate(_ id: String = UUID().uuidString, customer: String? = nil, by: String? = nil, title: String = "Furnace tune-up",
                          status: String = "approved", updated: String = "2026-11-03T12:00:00Z", lines: [String]? = nil,
                          extra: String = "") throws -> EstimateRecord {
        let json = #"{"id":"\#(id)","organizationId":"00000000-0000-4000-8000-000000000002","customerId":"\#(customer ?? self.customer)","createdByUserId":"\#(by ?? me)","status":"\#(status)","currentRevisionNumber":2,"title":"\#(title)","lines":[\#((lines ?? [line()]).joined(separator: ","))],"createdAt":"2026-10-26T12:00:00Z","updatedAt":"\#(updated)"\#(extra)}"#
        return try JSONDecoder().decode(EstimateRecord.self, from: Data(json.utf8))
    }

    func testThisCustomersEstimatesComeFirstNewestFirst() throws {
        let old = try estimate("a", updated: "2026-10-01T12:00:00Z")
        let new = try estimate("b", updated: "2026-11-10T12:00:00Z")
        let elsewhere = try estimate("c", customer: other)
        let empty = try estimate("d", lines: [])
        XCTAssertEqual(EstimateCopy.forCustomer([old, elsewhere, new, empty], customerID: customer).map(\.id), ["b", "a"])
        XCTAssertEqual(EstimateCopy.forCustomer([old, new], customerID: ""), [], "No customer chosen yet")
        XCTAssertEqual(EstimateCopy.forCustomer([old, new], customerID: customer, limit: 1).map(\.id), ["b"])
    }

    func testThenThePersonsOwnForOtherCustomers() throws {
        let mine = try estimate("a", customer: other, updated: "2026-11-01T12:00:00Z")
        let mineNewer = try estimate("b", customer: other, updated: "2026-11-05T12:00:00Z")
        let theirs = try estimate("c", customer: other, by: "00000000-0000-4000-8000-0000000000aa")
        let sameCustomer = try estimate("d")
        XCTAssertEqual(EstimateCopy.ownOthers([mine, theirs, sameCustomer, mineNewer], actorID: me, customerID: customer).map(\.id), ["b", "a"],
                       "Never repeats the customer's own list, never someone else's work")
        XCTAssertEqual(EstimateCopy.ownOthers([mine], actorID: nil, customerID: customer), [])
    }

    func testOnlyEstimatesWithTheirOwnDollarLinesAreOffered() throws {
        XCTAssertTrue(EstimateCopy.isCopyable(try estimate()))
        XCTAssertFalse(EstimateCopy.isCopyable(try estimate(lines: [])), "Option packages alone are not copied")
        XCTAssertFalse(EstimateCopy.isCopyable(try estimate(lines: [line(currency: "EUR")])))
    }

    func testLinesComeAcrossAsNewTypedLinesAtTheirOldPrices() throws {
        let priceBook = #"{"kind":"price_book","priceBookItemId":"11111111-1111-4111-8111-111111111111","priceBookRevision":7}"#
        let source = try estimate(lines: [line("Replace capacitor", quantity: 2, amount: 12_550, source: priceBook, extra: #","group":"material","showToCustomer":false"#),
                                          line("Labor", amount: 9_900)])
        let copied = EstimateCopy.lines(from: source)
        XCTAssertEqual(copied.map(\.description), ["Replace capacitor", "Labor"])
        XCTAssertEqual(copied.map(\.quantity), ["2", "1"])
        XCTAssertEqual(copied.map(\.unitPrice), ["125.50", "99.00"], "Prices as they were")
        XCTAssertEqual(MoneyInput.cents(copied[0].unitPrice), 12_550)
        XCTAssertTrue(copied.allSatisfy { $0.originalLineID == nil }, "New lines, not the old estimate's")
        XCTAssertTrue(copied.allSatisfy { $0.source == .manual }, "No price book or estimate link is carried")
        XCTAssertTrue(copied.allSatisfy { $0.priceBookOriginal == nil })
        XCTAssertEqual(copied.map(\.group), [.material, .work])
        XCTAssertEqual(copied.map(\.showToCustomer), [false, true])
        XCTAssertNotEqual(copied[0].id, copied[1].id)
    }

    func testDiscountsCreditsAndUnusableLinesStayBehind() throws {
        let source = try estimate(lines: [line("Repair", amount: 20_000), line("Member discount", amount: -2_000),
                                          line("Huge", amount: 100_000_001), line("  ", amount: 100), line("None", quantity: 0)])
        XCTAssertEqual(EstimateCopy.lines(from: source).map(\.description), ["Repair"])
        XCTAssertEqual(EstimateCopy.leftOut(source), 4)
        XCTAssertEqual(EstimateCopy.note(leftOut: 4), "Check prices before sending. Discounts and credits weren\u{2019}t copied.")
        XCTAssertEqual(EstimateCopy.note(leftOut: 0), "Check prices before sending.")
    }

    func testApprovalSignatureAndOptionsAreNotCarried() throws {
        let signed = try estimate(extra: #","approvedAt":"2026-11-02T12:00:00Z","approvalSignature":{"id":"s","signerName":"Dana","signedAt":"2026-11-02T12:00:00Z","imageMediaId":"m"},"options":[{"id":"o","title":"Best","description":"","lines":[],"totalAmount":0,"currency":"USD"}]"#)
        XCTAssertNotNil(signed.approvalSignature)
        let copied = EstimateCopy.lines(from: signed)
        XCTAssertEqual(copied.count, 1)
        XCTAssertEqual(copied[0].source, .manual)
    }

    func testTheCopiedNameFillsOnlyAnEmptyName() {
        XCTAssertEqual(EstimateCopy.title(current: "  ", copied: "Furnace tune-up"), "Furnace tune-up")
        XCTAssertEqual(EstimateCopy.title(current: "Water heater", copied: "Furnace tune-up"), "Water heater")
    }

    func testPriceTextAndRowDetail() throws {
        XCTAssertEqual(EstimateCopy.priceText(0), "0.00")
        XCTAssertEqual(EstimateCopy.priceText(5), "0.05")
        XCTAssertEqual(EstimateCopy.priceText(1_250), "12.50")
        let zone = try XCTUnwrap(TimeZone(identifier: "America/Chicago"))
        let detail = EstimateCopy.detail(try estimate(updated: "2025-03-09T18:00:00Z", lines: [line(quantity: 2, amount: 17_000)]),
                                         customerName: "Danielle Marlowe", timeZone: zone)
        XCTAssertEqual(detail, "Danielle Marlowe \u{00B7} $340.00 \u{00B7} Mar 9, 2025")
    }
}

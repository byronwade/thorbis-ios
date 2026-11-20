import XCTest
@testable import Thorbis

@MainActor
final class ReceiptsTests: XCTestCase {
    private let userA = "00000000-0000-4000-8000-000000000001"
    private let userB = "00000000-0000-4000-8000-000000000002"
    private let orgA = "00000000-0000-4000-8000-000000000003"
    private let orgB = "00000000-0000-4000-8000-000000000004"

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago") ?? .gmt
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        var parts = DateComponents()
        parts.year = year; parts.month = month; parts.day = day; parts.hour = hour
        return calendar.date(from: parts) ?? Date(timeIntervalSince1970: 0)
    }

    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    // MARK: Store

    func testReceiptsRoundTripAndPartitionByPersonAndWorkspace() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ReceiptsStore(organizationID: orgA, userID: userA, directory: directory)
        XCTAssertTrue(store.receipts.isEmpty)
        let receipt = ReceiptRecord(merchant: "Ferguson Supply", date: day(2026, 11, 12), totalCents: 4680,
                                    category: .parts, jobReference: "JOB-2214", note: "Capacitor")
        try store.save(receipt)

        let reopened = try ReceiptsStore(organizationID: orgA, userID: userA, directory: directory)
        XCTAssertEqual(reopened.receipts, [receipt])
        XCTAssertTrue(try ReceiptsStore(organizationID: orgA, userID: userB, directory: directory).receipts.isEmpty)
        XCTAssertTrue(try ReceiptsStore(organizationID: orgB, userID: userA, directory: directory).receipts.isEmpty)
        XCTAssertFalse(store.fileURL.lastPathComponent.contains(userA))
        XCTAssertFalse(store.fileURL.lastPathComponent.contains(orgA))
        XCTAssertThrowsError(try ReceiptsStore(organizationID: "", userID: userA, directory: directory))
    }

    func testEditKeepsOneRecordAndDeleteRemovesIt() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ReceiptsStore(organizationID: orgA, userID: userA, directory: directory)
        var receipt = ReceiptRecord(merchant: "Shell", date: day(2026, 11, 11), totalCents: 5810, category: .fuel)
        try store.save(receipt)
        receipt.totalCents = 6000
        receipt.merchant = "Shell #4482"
        try store.save(receipt)
        XCTAssertEqual(store.receipts.count, 1)
        XCTAssertEqual(store.receipts.first?.totalCents, 6000)
        try store.remove(receipt.id)
        XCTAssertTrue(try ReceiptsStore(organizationID: orgA, userID: userA, directory: directory).receipts.isEmpty)
    }

    func testPhotoIsStoredBesideTheBookAndFollowsTheReceipt() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ReceiptsStore(organizationID: orgA, userID: userA, directory: directory)
        let receipt = ReceiptRecord(merchant: "Home Depot", date: day(2026, 11, 2), totalCents: 12460, category: .tools)
        let first = try store.save(receipt, image: .replace(Data([1, 2, 3])))
        let firstURL = try XCTUnwrap(store.imageURL(for: first))
        XCTAssertEqual(firstURL.deletingLastPathComponent(), store.imagesURL)
        XCTAssertEqual(store.imagesURL.deletingLastPathComponent(), store.fileURL.deletingLastPathComponent())
        XCTAssertEqual(try Data(contentsOf: firstURL), Data([1, 2, 3]))

        // An edit that doesn't touch the photo keeps it, whatever the caller's copy says.
        var edited = receipt
        edited.note = "Drill bits"
        edited.imageFile = nil
        let kept = try store.save(edited, image: .keep)
        XCTAssertEqual(kept.imageFile, first.imageFile)

        let second = try store.save(edited, image: .replace(Data([9])))
        XCTAssertNotEqual(second.imageFile, first.imageFile)
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstURL.path))
        let secondURL = try XCTUnwrap(store.imageURL(for: second))

        let reopened = try ReceiptsStore(organizationID: orgA, userID: userA, directory: directory)
        XCTAssertEqual(try reopened.receipts.first.flatMap { reopened.imageURL(for: $0) }.map { try Data(contentsOf: $0) }, Data([9]))

        let cleared = try store.save(edited, image: .remove)
        XCTAssertNil(cleared.imageFile)
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondURL.path))

        let again = try store.save(edited, image: .replace(Data([7])))
        let againURL = try XCTUnwrap(store.imageURL(for: again))
        try store.remove(edited.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: againURL.path))
    }

    func testModelBindsSavesAndClearsWhenSignedOut() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = ReceiptsModel()
        model.bind(organizationID: orgA, userID: userA, directory: directory)
        XCTAssertTrue(model.bound)
        try model.save(ReceiptRecord(merchant: "NAPA", date: day(2026, 11, 8), totalCents: 6735), image: .keep)
        XCTAssertEqual(model.receipts.count, 1)
        model.bind(organizationID: nil, userID: nil, directory: directory)
        XCTAssertFalse(model.bound)
        XCTAssertTrue(model.receipts.isEmpty)
        XCTAssertThrowsError(try model.remove("x"))
        model.bind(organizationID: orgA, userID: userA, directory: directory)
        XCTAssertEqual(model.receipts.first?.merchant, "NAPA")
    }

    // MARK: Totals and months

    func testTotalsAndMonthGrouping() {
        let receipts = [
            ReceiptRecord(merchant: "A", date: day(2026, 11, 12), totalCents: 4680),
            ReceiptRecord(merchant: "B", date: day(2026, 11, 1, hour: 0), totalCents: 5810),
            ReceiptRecord(merchant: "C", date: day(2026, 10, 31, hour: 23), totalCents: 1820),
            ReceiptRecord(merchant: "D", date: day(2025, 12, 9), totalCents: 100),
        ]
        XCTAssertEqual(ReceiptMath.total(receipts), 12410)
        XCTAssertEqual(ReceiptMath.total([]), 0)

        let months = ReceiptMath.months(receipts, calendar: calendar)
        XCTAssertEqual(months.map(\.id), ["2026-11", "2026-10", "2025-12"])
        XCTAssertEqual(months.map(\.totalCents), [10490, 1820, 100])
        XCTAssertEqual(months[0].receipts.map(\.merchant), ["A", "B"])
        XCTAssertEqual(months[0].start, day(2026, 11, 1, hour: 0))

        XCTAssertEqual(ReceiptMath.monthTotal(receipts, containing: day(2026, 11, 30), calendar: calendar), 10490)
        XCTAssertEqual(ReceiptMath.monthTotal(receipts, containing: day(2026, 9, 1), calendar: calendar), 0)
        XCTAssertTrue(ReceiptMath.months([], calendar: calendar).isEmpty)
    }

    func testCSVIsOldestFirstAndEscapesCells() {
        let receipts = [
            ReceiptRecord(merchant: "Denny's, \"The Diner\"", date: day(2026, 11, 17), totalCents: 1820,
                          category: .meals, note: "Lunch\nwith crew"),
            ReceiptRecord(merchant: "=SUM(A1)", date: day(2026, 11, 3), totalCents: 500, category: .other, jobReference: "JOB-2214"),
        ]
        let csv = ReceiptMath.csv(receipts, calendar: calendar)
        let lines = csv.components(separatedBy: "\r\n")
        XCTAssertEqual(lines[0], "Date,Merchant,Category,Total,Job,Note")
        XCTAssertEqual(lines[1], "2026-11-03,'=SUM(A1),Other,5.00,JOB-2214,")
        XCTAssertTrue(csv.contains("2026-11-17,\"Denny's, \"\"The Diner\"\"\",Meals,18.20,,\"Lunch\nwith crew\""))
        XCTAssertTrue(csv.hasSuffix("\r\n"))
        XCTAssertEqual(ReceiptMath.plainAmount(5), "0.05")
        XCTAssertEqual(ReceiptMath.plainAmount(120000), "1200.00")
    }

    func testTypedTotals() {
        XCTAssertEqual(ReceiptFormat.cents("46.80"), 4680)
        XCTAssertEqual(ReceiptFormat.cents(" $1,204.5 "), 120450)
        XCTAssertEqual(ReceiptFormat.cents("46,80"), 4680)
        XCTAssertEqual(ReceiptFormat.cents("1,204"), 120400)
        XCTAssertEqual(ReceiptFormat.cents("12"), 1200)
        XCTAssertNil(ReceiptFormat.cents(""))
        XCTAssertNil(ReceiptFormat.cents("0"))
        XCTAssertNil(ReceiptFormat.cents("abc"))
        XCTAssertNil(ReceiptFormat.cents("-5"))
    }

    // MARK: Reading a photo's text

    func testParserReadsMerchantDateAndTotal() {
        let lines = [
            "FERGUSON SUPPLY", "1420 Industrial Blvd", "Austin TX 78701", "Tel 512-555-0100",
            "11/12/2026 9:20 AM", "Run capacitor 45/5   24.60", "Contactor 30A   18.90",
            "SUBTOTAL 43.50", "TAX 3.30", "TOTAL $46.80", "VISA ****7731 46.80", "CHANGE 0.00",
        ]
        let read = ReceiptTextParser.parse(lines: lines, now: day(2026, 11, 17), calendar: calendar)
        XCTAssertEqual(read.merchant, "Ferguson Supply")
        XCTAssertEqual(read.totalCents, 4680)
        XCTAssertEqual(read.date, day(2026, 11, 12))
        XCTAssertFalse(read.isEmpty)
    }

    func testParserPrefersTheStrongestTotalAndReadsALabelOnItsOwnLine() {
        let now = day(2026, 11, 17)
        let fuel = ReceiptTextParser.parse(lines: ["Shell #4482", "Nov 16, 2026", "Total 58.10", "Total savings 2.00",
                                                   "Cash 60.00", "Change 1.90"], now: now, calendar: calendar)
        XCTAssertEqual(fuel.merchant, "Shell #4482")
        XCTAssertEqual(fuel.totalCents, 5810)
        XCTAssertEqual(fuel.date, day(2026, 11, 16))

        let split = ReceiptTextParser.parse(lines: ["Welcome to", "Home Depot", "2026-11-02", "Subtotal", "115.00",
                                                    "Amount due", "$1,124.60", "Total 115.00"], now: now, calendar: calendar)
        XCTAssertEqual(split.merchant, "Home Depot")
        XCTAssertEqual(split.totalCents, 112460)
        XCTAssertEqual(split.date, day(2026, 11, 2))

        let noLabel = ReceiptTextParser.parse(lines: ["Coffee 4.50", "Bagel 3.25", "Tax 0.62", "8.37", "Cash 10.00"],
                                              now: now, calendar: calendar)
        XCTAssertEqual(noLabel.totalCents, 837)
        XCTAssertNil(noLabel.merchant)
    }

    func testParserLeavesWhatItCannotReadEmpty() {
        let now = day(2026, 11, 17)
        XCTAssertTrue(ReceiptTextParser.parse(lines: [], now: now, calendar: calendar).isEmpty)
        XCTAssertTrue(ReceiptTextParser.parse(lines: ["   ", "12345", "###"], now: now, calendar: calendar).isEmpty)
        // A date in the future, a day that doesn't exist and a year long gone are not dates to trust.
        XCTAssertNil(ReceiptTextParser.parse(lines: ["12/25/2026"], now: now, calendar: calendar).date)
        XCTAssertNil(ReceiptTextParser.parse(lines: ["02/31/2026"], now: now, calendar: calendar).date)
        XCTAssertNil(ReceiptTextParser.parse(lines: ["01/05/1999"], now: now, calendar: calendar).date)
        XCTAssertEqual(ReceiptTextParser.parse(lines: ["7/9/26"], now: now, calendar: calendar).date, day(2026, 7, 9))
        XCTAssertEqual(ReceiptTextParser.parse(lines: ["17 Jul 2026"], now: now, calendar: calendar).date, day(2026, 7, 17))
        // An amount needs its two decimals; a phone number or a quantity is not money.
        XCTAssertEqual(ReceiptTextParser.amounts(in: "512-555-0100 x2 1,204.50 $3.3"), [120450])
    }
}

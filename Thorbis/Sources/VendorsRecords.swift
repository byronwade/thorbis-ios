import CryptoKit
import Foundation

/// Vendors and purchase orders are company records, but no server route holds them yet.
/// They are kept in one file on this phone for each workspace, and the screens say so.
struct VendorRecord: Codable, Identifiable, Equatable, Hashable {
    let id: String
    var name: String
    var contact: String?
    var phone: String?
    var email: String?
    var accountNumber: String?
    var terms: String?
    var notes: String?
    let createdAt: Date

    init(id: String = UUID().uuidString, name: String, contact: String? = nil, phone: String? = nil,
         email: String? = nil, accountNumber: String? = nil, terms: String? = nil, notes: String? = nil,
         createdAt: Date = Date()) {
        self.id = id; self.name = name; self.contact = contact; self.phone = phone; self.email = email
        self.accountNumber = accountNumber; self.terms = terms; self.notes = notes; self.createdAt = createdAt
    }

    /// "•••• 9034": the account number never shows whole once it is saved.
    var maskedAccount: String? {
        guard let accountNumber, !accountNumber.isEmpty else { return nil }
        return accountNumber.count > 4 ? "\u{2022}\u{2022}\u{2022}\u{2022} \(accountNumber.suffix(4))" : accountNumber
    }

    /// "#9034 · Net 30": the list row's second line.
    var accountLine: String {
        var parts: [String] = []
        if let accountNumber, !accountNumber.isEmpty { parts.append("#\(accountNumber.suffix(4))") }
        if let terms, !terms.isEmpty { parts.append(terms) }
        return parts.joined(separator: " \u{00B7} ")
    }

    var callURL: URL? {
        let digits = (phone ?? "").filter { $0.isNumber || $0 == "+" }
        return digits.count >= 7 ? URL(string: "tel:\(digits)") : nil
    }

    var mailURL: URL? {
        let address = (email ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard address.contains("@"), !address.contains(" "),
              let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "mailto:\(encoded)")
    }
}

struct PurchaseOrderLine: Codable, Identifiable, Equatable, Hashable {
    let id: String
    var description: String
    var quantity: Int
    var unitCostCents: Int
    /// Units checked in so far; never more than `quantity`.
    var received: Int

    init(id: String = UUID().uuidString, description: String, quantity: Int, unitCostCents: Int, received: Int = 0) {
        self.id = id; self.description = description
        self.quantity = max(1, quantity); self.unitCostCents = max(0, unitCostCents)
        self.received = min(max(0, received), max(1, quantity))
    }

    var totalCents: Int { quantity * unitCostCents }
    var outstanding: Int { max(0, quantity - received) }
}

enum PurchaseOrderStatus: String, Codable, CaseIterable {
    case draft, ordered, received

    var label: String {
        switch self {
        case .draft: "Draft"
        case .ordered: "Ordered"
        case .received: "Received"
        }
    }
}

struct PurchaseOrderRecord: Codable, Identifiable, Equatable, Hashable {
    let id: String
    /// 1, 2, 3… in the order this workspace made them on this phone. Never reused.
    let number: Int
    var vendorID: String
    /// The vendor's name when the order was made, so the order still reads if the vendor is removed.
    var vendorName: String
    /// What the order is for ("Truck restock", a job's name). Free text.
    var note: String?
    var lines: [PurchaseOrderLine]
    let createdAt: Date
    var orderedAt: Date?
    var receivedAt: Date?

    init(id: String = UUID().uuidString, number: Int, vendorID: String, vendorName: String, note: String? = nil,
         lines: [PurchaseOrderLine] = [], createdAt: Date = Date(), orderedAt: Date? = nil, receivedAt: Date? = nil) {
        self.id = id; self.number = number; self.vendorID = vendorID; self.vendorName = vendorName
        self.note = note; self.lines = lines; self.createdAt = createdAt
        self.orderedAt = orderedAt; self.receivedAt = receivedAt
    }

    /// "PO-0007"
    var numberLabel: String { PurchaseOrderMath.numberLabel(number) }
    var totalCents: Int { PurchaseOrderMath.total(lines) }
    var status: PurchaseOrderStatus { PurchaseOrderMath.status(lines: lines, orderedAt: orderedAt) }
    var isOpen: Bool { status != .received }
    var orderedUnits: Int { PurchaseOrderMath.orderedUnits(lines) }
    var receivedUnits: Int { PurchaseOrderMath.receivedUnits(lines) }
    /// Ordered, with some but not all of it checked in.
    var isPartlyReceived: Bool { status == .ordered && receivedUnits > 0 }
}

/// The arithmetic behind a purchase order, kept apart from the screens so it can be tested.
enum PurchaseOrderMath {
    static func numberLabel(_ number: Int) -> String { "PO-" + String(format: "%04d", max(0, number)) }

    static func total(_ lines: [PurchaseOrderLine]) -> Int { lines.reduce(0) { $0 + $1.totalCents } }
    static func orderedUnits(_ lines: [PurchaseOrderLine]) -> Int { lines.reduce(0) { $0 + $1.quantity } }
    static func receivedUnits(_ lines: [PurchaseOrderLine]) -> Int { lines.reduce(0) { $0 + min($1.received, $1.quantity) } }

    /// Draft until it is marked ordered; Received once every line is fully checked in.
    static func status(lines: [PurchaseOrderLine], orderedAt: Date?) -> PurchaseOrderStatus {
        guard orderedAt != nil else { return .draft }
        guard !lines.isEmpty, lines.allSatisfy({ $0.received >= $0.quantity }) else { return .ordered }
        return .received
    }

    /// Checks items in. `counts` is each line's total received so far, by line id. A count is held
    /// between what was already received (nothing is un-received here) and what was ordered.
    /// Lines left out keep their count.
    static func receiving(_ lines: [PurchaseOrderLine], counts: [String: Int]) -> [PurchaseOrderLine] {
        lines.map { line in
            guard let wanted = counts[line.id] else { return line }
            var next = line
            next.received = min(max(wanted, line.received), line.quantity)
            return next
        }
    }

    /// What this workspace ordered from a vendor in a calendar year: orders marked ordered in it.
    static func spend(_ orders: [PurchaseOrderRecord], vendorID: String, year: Int, calendar: Calendar = .current) -> Int {
        orders.reduce(0) { sum, order in
            guard order.vendorID == vendorID, let orderedAt = order.orderedAt,
                  calendar.component(.year, from: orderedAt) == year else { return sum }
            return sum + order.totalCents
        }
    }

    /// The cost of what is ordered and not yet checked in.
    static func onOrder(_ orders: [PurchaseOrderRecord], vendorID: String) -> Int {
        orders.reduce(0) { sum, order in
            guard order.vendorID == vendorID, order.status == .ordered else { return sum }
            return sum + order.lines.reduce(0) { $0 + $1.outstanding * $1.unitCostCents }
        }
    }

    /// "$1,240" for whole dollars, "$618.40" otherwise, as Paper writes amounts in lists.
    static func money(_ cents: Int, alwaysCents: Bool = false) -> String {
        let amount = Decimal(cents) / 100
        let whole = cents % 100 == 0 && !alwaysCents
        return amount.formatted(.currency(code: "USD").precision(.fractionLength(whole ? 0 : 2)))
    }
}

private struct VendorsBookContents: Codable {
    var vendors: [VendorRecord] = []
    var orders: [PurchaseOrderRecord] = []
    /// The number the next purchase order takes.
    var nextOrderNumber = 1
}

/// One protected JSON file for each workspace, in Application Support on this phone.
@MainActor
final class VendorsRecords {
    let organizationID: String
    let fileURL: URL
    private var book: VendorsBookContents

    var vendors: [VendorRecord] {
        book.vendors.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    /// Newest first.
    var orders: [PurchaseOrderRecord] { book.orders.sorted { $0.number > $1.number } }
    var nextOrderNumber: Int { book.nextOrderNumber }

    private static func partitionURL(organizationID: String, directory: URL?) throws -> URL {
        let key = organizationID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { throw Problem(title: "No workspace is open", status: nil, detail: nil) }
        let root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VendorBooks", isDirectory: true)
        let digest = SHA256.hash(data: Data("v1|\(key)".utf8)).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent("\(digest).json")
    }

    private static func encoder() -> JSONEncoder { let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; return encoder }
    private static func decoder() -> JSONDecoder { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder }

    init(organizationID: String, directory: URL? = nil) throws {
        self.organizationID = organizationID.lowercased()
        self.fileURL = try Self.partitionURL(organizationID: organizationID, directory: directory)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            self.book = try Self.decoder().decode(VendorsBookContents.self, from: Data(contentsOf: fileURL))
        } else {
            self.book = VendorsBookContents()
        }
    }

    private func commit(_ next: VendorsBookContents) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                    attributes: [.protectionKey: FileProtectionType.complete])
        try Self.encoder().encode(next).write(to: fileURL, options: .atomic)
        try manager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: fileURL.path)
        book = next
    }

    func vendor(_ id: String) -> VendorRecord? { book.vendors.first { $0.id == id } }
    func order(_ id: String) -> PurchaseOrderRecord? { book.orders.first { $0.id == id } }
    func orders(for vendorID: String) -> [PurchaseOrderRecord] { orders.filter { $0.vendorID == vendorID } }

    func save(_ vendor: VendorRecord) throws {
        guard !vendor.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Problem(title: "A vendor needs a name", status: nil, detail: nil)
        }
        var next = book
        next.vendors.removeAll { $0.id == vendor.id }
        next.vendors.append(vendor)
        // Orders carry the vendor's name; keep it current while the vendor exists.
        for index in next.orders.indices where next.orders[index].vendorID == vendor.id {
            next.orders[index].vendorName = vendor.name
        }
        try commit(next)
    }

    /// Removes the vendor. Its purchase orders stay, under the name they were made with.
    func removeVendor(_ id: String) throws {
        var next = book
        next.vendors.removeAll { $0.id == id }
        try commit(next)
    }

    /// Makes a draft for a vendor and takes the next number.
    @discardableResult
    func createOrder(vendorID: String, note: String? = nil, lines: [PurchaseOrderLine] = [],
                     now: Date = Date()) throws -> PurchaseOrderRecord {
        guard let vendor = vendor(vendorID) else { throw Problem(title: "Choose a vendor", status: nil, detail: nil) }
        var next = book
        let order = PurchaseOrderRecord(number: next.nextOrderNumber, vendorID: vendor.id, vendorName: vendor.name,
                                        note: note, lines: lines, createdAt: now)
        next.nextOrderNumber += 1
        next.orders.append(order)
        try commit(next)
        return order
    }

    /// Saves changes to an order. Its number and the day it was made never change.
    func save(_ order: PurchaseOrderRecord) throws {
        guard let index = book.orders.firstIndex(where: { $0.id == order.id }) else {
            throw Problem(title: "This purchase order is no longer on this phone", status: nil, detail: nil)
        }
        var next = book
        var saved = order
        if let vendor = vendor(order.vendorID) { saved.vendorName = vendor.name }
        next.orders[index] = saved
        try commit(next)
    }

    /// Draft to Ordered. An order with no items cannot be ordered.
    func markOrdered(_ id: String, now: Date = Date()) throws {
        guard var order = order(id) else { throw Problem(title: "This purchase order is no longer on this phone", status: nil, detail: nil) }
        guard !order.lines.isEmpty else { throw Problem(title: "Add an item before ordering", status: nil, detail: nil) }
        guard order.orderedAt == nil else { return }
        order.orderedAt = now
        try save(order)
    }

    /// Ordered back to Draft, only while nothing has been checked in.
    func backToDraft(_ id: String) throws {
        guard var order = order(id) else { return }
        guard order.receivedUnits == 0 else {
            throw Problem(title: "Items were already received on this order", status: nil, detail: nil)
        }
        order.orderedAt = nil
        order.receivedAt = nil
        try save(order)
    }

    /// Checks items in, line by line. The order becomes Received when every line is complete.
    func receive(_ id: String, counts: [String: Int], now: Date = Date()) throws {
        guard var order = order(id) else { throw Problem(title: "This purchase order is no longer on this phone", status: nil, detail: nil) }
        guard order.orderedAt != nil else { throw Problem(title: "Mark the order as ordered first", status: nil, detail: nil) }
        order.lines = PurchaseOrderMath.receiving(order.lines, counts: counts)
        order.receivedAt = order.status == .received ? (order.receivedAt ?? now) : nil
        try save(order)
    }

    func removeOrder(_ id: String) throws {
        var next = book
        next.orders.removeAll { $0.id == id }
        try commit(next)
    }
}

/// The purchase order as words and as a one-page PDF, for the share sheet.
enum PurchaseOrderDocument {
    static func text(_ order: PurchaseOrderRecord, vendor: VendorRecord?, company: String?) -> String {
        var rows: [String] = []
        rows.append("Purchase order \(order.numberLabel)")
        if let company, !company.isEmpty { rows.append("From: \(company)") }
        rows.append("To: \(vendor?.name ?? order.vendorName)")
        if let account = vendor?.accountNumber, !account.isEmpty { rows.append("Account: \(account)") }
        rows.append("Date: \((order.orderedAt ?? order.createdAt).formatted(date: .abbreviated, time: .omitted))")
        if let note = order.note, !note.isEmpty { rows.append("For: \(note)") }
        rows.append("")
        for line in order.lines {
            rows.append("\(line.quantity) x \(line.description) at \(PurchaseOrderMath.money(line.unitCostCents, alwaysCents: true)) = \(PurchaseOrderMath.money(line.totalCents, alwaysCents: true))")
        }
        if order.lines.isEmpty { rows.append("No items yet.") }
        rows.append("")
        rows.append("Total: \(PurchaseOrderMath.money(order.totalCents, alwaysCents: true))")
        return rows.joined(separator: "\n")
    }

    static func fileName(_ order: PurchaseOrderRecord) -> String { "\(order.numberLabel).pdf" }
}

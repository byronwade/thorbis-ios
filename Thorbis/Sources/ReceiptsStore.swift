import CryptoKit
import Foundation

/// What a receipt was for. Paper 44's category chips, in their order.
enum ReceiptCategory: String, Codable, CaseIterable, Hashable {
    case parts, fuel, tools, meals, other

    var label: String {
        switch self {
        case .parts: "Parts"
        case .fuel: "Fuel"
        case .tools: "Tools"
        case .meals: "Meals"
        case .other: "Other"
        }
    }
}

/// One receipt kept on this phone. There is no receipts route on the server, so nothing here is
/// submitted, approved or reimbursed by anyone; it is the person's own record.
struct ReceiptRecord: Codable, Identifiable, Equatable, Hashable {
    let id: String
    var merchant: String
    var date: Date
    var totalCents: Int
    var category: ReceiptCategory
    /// Free text: a job number or name as the person wrote it. Not linked to a job record.
    var jobReference: String?
    var note: String?
    /// The photo's file name inside this store's image folder; nil when there is no photo.
    var imageFile: String?
    let createdAt: Date

    init(id: String = UUID().uuidString, merchant: String, date: Date, totalCents: Int,
         category: ReceiptCategory = .other, jobReference: String? = nil, note: String? = nil,
         imageFile: String? = nil, createdAt: Date = Date()) {
        self.id = id; self.merchant = merchant; self.date = date; self.totalCents = totalCents
        self.category = category; self.jobReference = jobReference; self.note = note
        self.imageFile = imageFile; self.createdAt = createdAt
    }
}

/// What to do with a receipt's photo on save.
enum ReceiptImageChange: Equatable {
    case keep
    case replace(Data)
    case remove
}

/// One calendar month of receipts, newest first, with its total.
struct ReceiptMonth: Identifiable, Equatable {
    /// "2026-11"
    let id: String
    let start: Date
    let receipts: [ReceiptRecord]
    let totalCents: Int
}

/// Totals, month grouping and the CSV. Pure, so the arithmetic is unit-tested.
enum ReceiptMath {
    static func total(_ receipts: [ReceiptRecord]) -> Int {
        receipts.reduce(0) { $0 + $1.totalCents }
    }

    static func monthKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    /// Receipts by calendar month, newest month first; inside a month, newest receipt first.
    static func months(_ receipts: [ReceiptRecord], calendar: Calendar = .current) -> [ReceiptMonth] {
        var groups: [String: [ReceiptRecord]] = [:]
        for receipt in receipts { groups[monthKey(receipt.date, calendar: calendar), default: []].append(receipt) }
        return groups.keys.sorted(by: >).compactMap { key in
            guard let list = groups[key], let first = list.first else { return nil }
            let sorted = list.sorted { lhs, rhs in
                lhs.date == rhs.date ? lhs.createdAt > rhs.createdAt : lhs.date > rhs.date
            }
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: first.date)) ?? first.date
            return ReceiptMonth(id: key, start: start, receipts: sorted, totalCents: total(list))
        }
    }

    /// The total of the month `now` falls in.
    static func monthTotal(_ receipts: [ReceiptRecord], containing now: Date, calendar: Calendar = .current) -> Int {
        let key = monthKey(now, calendar: calendar)
        return total(receipts.filter { monthKey($0.date, calendar: calendar) == key })
    }

    /// "46.80": plain decimal for a spreadsheet, no currency sign or grouping.
    static func plainAmount(_ cents: Int) -> String {
        let sign = cents < 0 ? "-" : ""
        let value = abs(cents)
        return "\(sign)\(value / 100).\(String(format: "%02d", value % 100))"
    }

    /// One CSV document: a header row, then a row per receipt, oldest first.
    static func csv(_ receipts: [ReceiptRecord], calendar: Calendar = .current) -> String {
        var rows = ["Date,Merchant,Category,Total,Job,Note"]
        let ordered = receipts.sorted { $0.date == $1.date ? $0.createdAt < $1.createdAt : $0.date < $1.date }
        for receipt in ordered {
            let day = calendar.dateComponents([.year, .month, .day], from: receipt.date)
            let date = String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
            rows.append([date, cell(receipt.merchant), receipt.category.label, plainAmount(receipt.totalCents),
                         cell(receipt.jobReference ?? ""), cell(receipt.note ?? "")].joined(separator: ","))
        }
        return rows.joined(separator: "\r\n") + "\r\n"
    }

    /// Quotes a cell when it needs it, and stops a spreadsheet from running typed text as a formula.
    static func cell(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = text.first, "=+-@".contains(first) { text = "'" + text }
        guard text.contains(where: { ",\"\n\r".contains($0) }) else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

private struct ReceiptsBook: Codable {
    var receipts: [ReceiptRecord] = []
}

/// Receipts for one person in one workspace, in a protected JSON file in Application Support with
/// the photos in a folder beside it. Written atomically; the file name does not carry either ID.
@MainActor
final class ReceiptsStore {
    let organizationID: String
    let userID: String
    let fileURL: URL
    let imagesURL: URL
    private var book: ReceiptsBook

    var receipts: [ReceiptRecord] { book.receipts }

    private static func partition(organizationID: String, userID: String, directory: URL?) throws -> (file: URL, images: URL) {
        let organization = organizationID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let user = userID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !organization.isEmpty, !user.isEmpty else {
            throw Problem(title: "Receipts need a signed-in workspace", status: nil, detail: nil)
        }
        let root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Receipts", isDirectory: true)
        let digest = SHA256.hash(data: Data("receipts-v1|\(user)|\(organization)".utf8))
            .map { String(format: "%02x", $0) }.joined()
        return (root.appendingPathComponent("\(digest).json"),
                root.appendingPathComponent("\(digest)-photos", isDirectory: true))
    }

    init(organizationID: String, userID: String, directory: URL? = nil) throws {
        let urls = try Self.partition(organizationID: organizationID, userID: userID, directory: directory)
        self.organizationID = organizationID.lowercased()
        self.userID = userID.lowercased()
        self.fileURL = urls.file
        self.imagesURL = urls.images
        if FileManager.default.fileExists(atPath: urls.file.path) {
            self.book = try JSONDecoder().decode(ReceiptsBook.self, from: Data(contentsOf: urls.file))
        } else {
            self.book = ReceiptsBook()
        }
    }

    private func commit(_ next: ReceiptsBook) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                    attributes: [.protectionKey: FileProtectionType.complete])
        try JSONEncoder().encode(next).write(to: fileURL, options: .atomic)
        try manager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: fileURL.path)
        book = next
    }

    /// Where a receipt's photo is, when it has one and the file is still there.
    func imageURL(for receipt: ReceiptRecord) -> URL? {
        guard let name = receipt.imageFile else { return nil }
        let url = imagesURL.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Adds or replaces a receipt. The photo is written first, so a saved record never names a
    /// photo that is not on disk. Returns the record as stored.
    @discardableResult
    func save(_ record: ReceiptRecord, image: ReceiptImageChange = .keep) throws -> ReceiptRecord {
        let manager = FileManager.default
        var stored = record
        let previous = book.receipts.first { $0.id == record.id }?.imageFile
        var stale: String?
        switch image {
        case .keep:
            stored.imageFile = previous
        case .replace(let data):
            try manager.createDirectory(at: imagesURL, withIntermediateDirectories: true,
                                        attributes: [.protectionKey: FileProtectionType.complete])
            // A new name each time, so a failed commit leaves the old photo untouched.
            let name = "\(UUID().uuidString.lowercased()).jpg"
            let url = imagesURL.appendingPathComponent(name)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            stored.imageFile = name
            stale = previous
        case .remove:
            stored.imageFile = nil
            stale = previous
        }
        var next = book
        next.receipts.removeAll { $0.id == stored.id }
        next.receipts.append(stored)
        do {
            try commit(next)
        } catch {
            if case .replace = image, let name = stored.imageFile {
                try? manager.removeItem(at: imagesURL.appendingPathComponent(name))
            }
            throw error
        }
        if let stale { try? manager.removeItem(at: imagesURL.appendingPathComponent(stale)) }
        return stored
    }

    /// Removes a receipt and its photo.
    func remove(_ id: String) throws {
        let photo = book.receipts.first { $0.id == id }?.imageFile
        var next = book
        next.receipts.removeAll { $0.id == id }
        try commit(next)
        if let photo { try? FileManager.default.removeItem(at: imagesURL.appendingPathComponent(photo)) }
    }

    /// Removes this person's receipts and photos for this workspace from the phone.
    func erasePartition() throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: fileURL.path) { try manager.removeItem(at: fileURL) }
        if manager.fileExists(atPath: imagesURL.path) { try manager.removeItem(at: imagesURL) }
        book = ReceiptsBook()
    }
}

/// What could be read from a receipt's text. Every field is a guess for the person to check.
struct ReceiptReading: Equatable {
    var merchant: String?
    var date: Date?
    var totalCents: Int?

    var isEmpty: Bool { merchant == nil && date == nil && totalCents == nil }
}

/// Turns the lines Vision read from a receipt photo into a merchant, a date and a total.
/// Deliberately conservative: a field it is not sure of stays empty rather than wrong.
enum ReceiptTextParser {
    private static let amountPattern = #"(?<![\d.,])\$?\s?(\d{1,3}(?:,\d{3})+|\d+)\.(\d{2})(?!\d)"#
    private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
    /// Lines that carry an amount which is not what was paid for the goods.
    private static let notTotals = ["subtotal", "sub total", "sub-total", "tax", "savings", "saved", "discount",
                                    "change", "cash", "tender", "points", "items", "tip suggest"]
    /// Strongest first.
    private static let totalWords = ["grand total", "total due", "amount due", "balance due", "amount paid", "total"]
    private static let notMerchants = ["receipt", "invoice", "welcome", "thank", "customer copy", "merchant copy",
                                       "order", "store #", "tel", "phone", "www.", "http", ".com", "cashier", "register"]

    static func parse(lines raw: [String], now: Date = Date(), calendar: Calendar = .current) -> ReceiptReading {
        let lines = raw.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return ReceiptReading(merchant: merchant(lines), date: date(lines, now: now, calendar: calendar),
                              totalCents: total(lines))
    }

    private static func groups(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let source = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length)).map { match in
            (0..<match.numberOfRanges).map { index in
                let range = match.range(at: index)
                return range.location == NSNotFound ? "" : source.substring(with: range)
            }
        }
    }

    /// Every "12.34" on a line, in cents.
    static func amounts(in line: String) -> [Int] {
        groups(amountPattern, in: line).compactMap { match in
            guard match.count == 3, let whole = Int(match[1].replacingOccurrences(of: ",", with: "")),
                  let cents = Int(match[2]), whole <= 1_000_000 else { return nil }
            return whole * 100 + cents
        }
    }

    private static func total(_ lines: [String]) -> Int? {
        let lowered = lines.map { $0.lowercased() }
        for word in totalWords {
            var found: [Int] = []
            for (index, line) in lowered.enumerated() where line.contains(word) {
                // "Total" alone must not match "Subtotal" or "Total tax".
                if word == "total", notTotals.contains(where: { line.contains($0) }) { continue }
                if let amount = amounts(in: lines[index]).last {
                    found.append(amount)
                } else if index + 1 < lines.count, amounts(in: lines[index]).isEmpty,
                          let below = amounts(in: lines[index + 1]).last,
                          !notTotals.contains(where: { lowered[index + 1].contains($0) }) {
                    // The label and its amount were read as two lines.
                    found.append(below)
                }
            }
            if let best = found.max() { return best }
        }
        // No "total" anywhere: the largest amount that is not tax, change or cash handed over.
        let rest = lowered.enumerated().filter { _, line in !notTotals.contains(where: { line.contains($0) }) }
            .flatMap { index, _ in amounts(in: lines[index]) }
        return rest.max()
    }

    private static func merchant(_ lines: [String]) -> String? {
        for line in lines.prefix(6) {
            let lower = line.lowercased()
            let letters = line.filter(\.isLetter).count
            let digits = line.filter(\.isNumber).count
            guard letters >= 3, letters > digits, line.count <= 40 else { continue }
            if notMerchants.contains(where: { lower.contains($0) }) { continue }
            if !amounts(in: line).isEmpty { continue }
            // All capitals read as shouting in a list; keep mixed case as written.
            return line == line.uppercased() ? line.capitalized : line
        }
        return nil
    }

    private static func date(_ lines: [String], now: Date, calendar: Calendar) -> Date? {
        for line in lines {
            for candidate in dates(in: line, calendar: calendar) {
                // A receipt is not from the future, and a year far back is a misread.
                guard candidate <= now.addingTimeInterval(36 * 3600),
                      let floor = calendar.date(byAdding: .year, value: -10, to: now), candidate >= floor else { continue }
                return candidate
            }
        }
        return nil
    }

    private static func dates(in line: String, calendar: Calendar) -> [Date] {
        var found: [Date] = []
        func add(year: Int, month: Int, day: Int) {
            let full = year < 100 ? 2000 + year : year
            guard (1...12).contains(month), (1...31).contains(day) else { return }
            var parts = DateComponents()
            parts.year = full; parts.month = month; parts.day = day; parts.hour = 12
            // `date(from:)` rolls 31 February into March; only keep a day that exists.
            if let date = calendar.date(from: parts), calendar.component(.day, from: date) == day { found.append(date) }
        }
        for match in groups(#"(?<!\d)(\d{4})-(\d{1,2})-(\d{1,2})(?!\d)"#, in: line) {
            if let year = Int(match[1]), let month = Int(match[2]), let day = Int(match[3]) { add(year: year, month: month, day: day) }
        }
        // Month first, as US receipts print it.
        for match in groups(#"(?<![\d/.-])(\d{1,2})[/.-](\d{1,2})[/.-](\d{4}|\d{2})(?![\d/.-])"#, in: line) {
            if let month = Int(match[1]), let day = Int(match[2]), let year = Int(match[3]) { add(year: year, month: month, day: day) }
        }
        let names = months.joined(separator: "|")
        for match in groups("(?<![a-z])(\(names))[a-z]*\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?,?\\s+(\\d{4})", in: line) {
            if let month = months.firstIndex(of: match[1].lowercased()), let day = Int(match[2]), let year = Int(match[3]) {
                add(year: year, month: month + 1, day: day)
            }
        }
        for match in groups("(?<!\\d)(\\d{1,2})\\s+(\(names))[a-z]*\\.?,?\\s+(\\d{4})", in: line) {
            if let day = Int(match[1]), let month = months.firstIndex(of: match[2].lowercased()), let year = Int(match[3]) {
                add(year: year, month: month + 1, day: day)
            }
        }
        return found
    }
}

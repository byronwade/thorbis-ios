import CryptoKit
import Foundation

/// One thing carried on the truck, counted by hand on this phone. Nothing counts it down: there is
/// no stock route on the server, so a job's parts do not change these numbers.
struct TruckStockItem: Codable, Identifiable, Equatable, Hashable {
    let id: String
    var name: String
    var partNumber: String?
    /// How many are on the truck now.
    var quantity: Int
    /// The level it should not fall below. Zero means no minimum is kept.
    var minimum: Int
    /// "each", "ft", "box": written as entered.
    var unit: String
    let createdAt: Date

    init(id: String = UUID().uuidString, name: String, partNumber: String? = nil, quantity: Int = 0,
         minimum: Int = 0, unit: String = TruckStockRules.defaultUnit, createdAt: Date = Date()) {
        self.id = id; self.name = name; self.partNumber = partNumber
        self.quantity = max(0, quantity); self.minimum = max(0, minimum)
        self.unit = unit; self.createdAt = createdAt
    }
}

/// One line of the restock list: what is low and how many bring it back over its minimum.
struct TruckRestockLine: Identifiable, Equatable {
    let item: TruckStockItem
    let needed: Int
    var id: String { item.id }
}

/// The low rule and the restock list. Pure, so they are unit-tested.
enum TruckStockRules {
    static let defaultUnit = "each"
    static let maximumCount = 9_999

    /// Low when a minimum is kept and the count is at or under it.
    static func isLow(_ item: TruckStockItem) -> Bool {
        item.minimum > 0 && item.quantity <= item.minimum
    }

    static func lowCount(_ items: [TruckStockItem]) -> Int { items.filter(isLow).count }

    /// How many to pick up: the gap to the minimum, and at least one when it sits exactly on it.
    static func needed(_ item: TruckStockItem) -> Int {
        guard isLow(item) else { return 0 }
        return max(1, item.minimum - item.quantity)
    }

    /// A count after a + or − press, kept between zero and `maximumCount`.
    static func stepped(_ value: Int, by delta: Int) -> Int {
        min(maximumCount, max(0, value + delta))
    }

    static func sorted(_ items: [TruckStockItem]) -> [TruckStockItem] {
        items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Everything low, emptiest first, then by name.
    static func restockList(_ items: [TruckStockItem]) -> [TruckRestockLine] {
        items.filter(isLow)
            .sorted { lhs, rhs in
                lhs.quantity == rhs.quantity
                    ? lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    : lhs.quantity < rhs.quantity
            }
            .map { TruckRestockLine(item: $0, needed: needed($0)) }
    }

    /// "2 each", "1 box": the count with its unit.
    static func amount(_ count: Int, unit: String) -> String {
        let word = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        return word.isEmpty ? "\(count)" : "\(count) \(word)"
    }

    /// The restock list as plain text for the share sheet. Nil when nothing is low.
    static func restockText(_ items: [TruckStockItem], heading: String = "Truck restock list") -> String? {
        let lines = restockList(items)
        guard !lines.isEmpty else { return nil }
        var text = [heading]
        for line in lines {
            let part = (line.item.partNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let name = part.isEmpty ? line.item.name : "\(line.item.name) (\(part))"
            text.append("- \(name): get \(amount(line.needed, unit: line.item.unit)). Have \(line.item.quantity), keep \(line.item.minimum).")
        }
        return text.joined(separator: "\n")
    }
}

private struct TruckStockBook: Codable {
    var items: [TruckStockItem] = []
}

/// One person's truck stock in one workspace: a protected JSON file in Application Support,
/// written atomically. The file name does not carry either ID.
@MainActor
final class TruckStockStore {
    let organizationID: String
    let userID: String
    let fileURL: URL
    private var book: TruckStockBook

    var items: [TruckStockItem] { book.items }

    private nonisolated static func partitionURL(organizationID: String, userID: String, directory: URL?) throws -> URL {
        let organization = organizationID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let user = userID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !organization.isEmpty, !user.isEmpty else {
            throw Problem(title: "Truck stock needs a signed-in workspace", status: nil, detail: nil)
        }
        let root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TruckStock", isDirectory: true)
        let digest = SHA256.hash(data: Data("truck-stock-v1|\(user)|\(organization)".utf8))
            .map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent("\(digest).json")
    }

    init(organizationID: String, userID: String, directory: URL? = nil) throws {
        self.organizationID = organizationID.lowercased()
        self.userID = userID.lowercased()
        self.fileURL = try Self.partitionURL(organizationID: organizationID, userID: userID, directory: directory)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            self.book = try JSONDecoder().decode(TruckStockBook.self, from: Data(contentsOf: fileURL))
        } else {
            self.book = TruckStockBook()
        }
    }

    private func commit(_ next: TruckStockBook) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                    attributes: [.protectionKey: FileProtectionType.complete])
        try JSONEncoder().encode(next).write(to: fileURL, options: .atomic)
        try manager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: fileURL.path)
        book = next
    }

    func save(_ item: TruckStockItem) throws {
        var next = book
        if let index = next.items.firstIndex(where: { $0.id == item.id }) {
            next.items[index] = item
        } else {
            next.items.append(item)
        }
        try commit(next)
    }

    /// The quick + and −: moves one item's count and saves it. Returns the new count.
    @discardableResult
    func adjust(_ id: String, by delta: Int) throws -> Int {
        guard let index = book.items.firstIndex(where: { $0.id == id }) else {
            throw Problem(title: "That item is no longer on this phone", status: nil, detail: nil)
        }
        var next = book
        next.items[index].quantity = TruckStockRules.stepped(next.items[index].quantity, by: delta)
        try commit(next)
        return next.items[index].quantity
    }

    func remove(_ id: String) throws {
        var next = book
        next.items.removeAll { $0.id == id }
        try commit(next)
    }

    func erasePartition() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) { try FileManager.default.removeItem(at: fileURL) }
        book = TruckStockBook()
    }

    /// How many items are low for this person in this workspace, for the menu's "2 low".
    /// Zero when there is no file yet or it cannot be read. Safe to call from any actor.
    nonisolated static func lowCount(organizationID: String, userID: String, directory: URL? = nil) -> Int {
        guard let url = try? partitionURL(organizationID: organizationID, userID: userID, directory: directory),
              let data = try? Data(contentsOf: url),
              let book = try? JSONDecoder().decode(TruckStockBook.self, from: data) else { return 0 }
        return TruckStockRules.lowCount(book.items)
    }

    /// The same count read off the main thread.
    nonisolated static func loadLowCount(organizationID: String, userID: String) async -> Int {
        await Task.detached(priority: .utility) {
            lowCount(organizationID: organizationID, userID: userID, directory: nil)
        }.value
    }
}

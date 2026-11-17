import Foundation

// Marketing (Paper 92A, 92C "Campaign", 92D "Lead sources"). The server has no review feed and
// no campaign sender, so this place shows what is true on one phone: where customers say they
// came from (the "How they found us" answer on each customer), the company's own review link,
// and campaign notes kept on this phone. Nothing is sent to customers from here.

// MARK: - Lead sources

/// One customer as the tally sees it.
struct LeadSourceEntry: Equatable {
    let source: String?
    let createdAt: Date?
}

struct LeadSourceCount: Identifiable, Equatable {
    /// The spelling most customers were saved with ("Google", not "google").
    let name: String
    let count: Int
    /// Part of the customers that have a source, 0...1.
    let share: Double
    var id: String { name.lowercased() }
    var percent: Int { Int((share * 100).rounded()) }
}

/// Paper 92D's ranges. A customer counts in the range they were added in.
enum LeadSourcePeriod: String, CaseIterable, Identifiable {
    case days30, days90, year, all
    var id: String { rawValue }

    var label: String {
        switch self {
        case .days30: "30 days"
        case .days90: "90 days"
        case .year: "This year"
        case .all: "All"
        }
    }

    /// For the subtitle: "Last 90 days", "This year", "All time".
    var title: String {
        switch self {
        case .days30: "Last 30 days"
        case .days90: "Last 90 days"
        case .year: "This year"
        case .all: "All time"
        }
    }

    /// The first moment that counts; nil counts everyone.
    func start(now: Date, calendar: Calendar = .current) -> Date? {
        let today = calendar.startOfDay(for: now)
        switch self {
        case .days30: return calendar.date(byAdding: .day, value: -30, to: today)
        case .days90: return calendar.date(byAdding: .day, value: -90, to: today)
        case .year: return calendar.date(from: calendar.dateComponents([.year], from: now))
        case .all: return nil
        }
    }
}

/// How many customers named each source. Spelling differences in case and spacing fold together.
struct LeadSourceTally: Equatable {
    /// Most customers first; ties by name.
    let sources: [LeadSourceCount]
    /// Customers with a source written down.
    let recorded: Int
    /// Customers with no source yet.
    let unrecorded: Int
    var total: Int { recorded + unrecorded }

    static let empty = LeadSourceTally(sources: [], recorded: 0, unrecorded: 0)

    static func clean(_ source: String?) -> String {
        (source ?? "").split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    /// `since` leaves out customers added before it, and customers with no added date.
    static func make(_ entries: [LeadSourceEntry], since: Date? = nil) -> LeadSourceTally {
        var counts: [String: Int] = [:]
        var spellings: [String: [String: Int]] = [:]
        var firstSeen: [String: Int] = [:]
        var unrecorded = 0
        for (index, entry) in entries.enumerated() {
            if let since {
                guard let created = entry.createdAt, created >= since else { continue }
            }
            let name = clean(entry.source)
            guard !name.isEmpty else { unrecorded += 1; continue }
            let key = name.lowercased()
            counts[key, default: 0] += 1
            spellings[key, default: [:]][name, default: 0] += 1
            if firstSeen[name] == nil { firstSeen[name] = index }
        }
        let recorded = counts.values.reduce(0, +)
        let rows: [LeadSourceCount] = counts.map { key, count in
            // The spelling used most; the one seen first settles a tie.
            let spelling = (spellings[key] ?? [:]).max { lhs, rhs in
                lhs.value != rhs.value ? lhs.value < rhs.value
                    : (firstSeen[lhs.key] ?? 0) > (firstSeen[rhs.key] ?? 0)
            }?.key ?? key
            return LeadSourceCount(name: spelling, count: count, share: Double(count) / Double(max(recorded, 1)))
        }
        .sorted { lhs, rhs in
            lhs.count != rhs.count ? lhs.count > rhs.count
                : lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return LeadSourceTally(sources: rows, recorded: recorded, unrecorded: unrecorded)
    }

    /// Paper 92A's row line: "Google 46% · Referral 31% · Yard sign 23%" (the top three).
    var summary: String {
        sources.prefix(3).map { "\($0.name) \($0.percent)%" }.joined(separator: " \u{00B7} ")
    }

    /// The bar and list show this many sources by name; the rest fold into "Other".
    static let namedLimit = 5

    /// The first sources by name and, when there are more, one "Other" row holding the rest.
    var grouped: [LeadSourceCount] {
        guard sources.count > Self.namedLimit else { return sources }
        let rest = sources.dropFirst(Self.namedLimit)
        let count = rest.reduce(0) { $0 + $1.count }
        return Array(sources.prefix(Self.namedLimit))
            + [LeadSourceCount(name: "Other", count: count, share: Double(count) / Double(max(recorded, 1)))]
    }
}

// MARK: - Campaign notes

/// A note about a campaign the business ran or plans. Written by hand; nothing sends from it.
struct MarketingCampaignNote: Codable, Identifiable, Equatable, Hashable {
    let id: String
    var name: String
    var channel: String
    /// "yyyy-MM-dd" days, as `LearnDay` writes them.
    var startsOn: String?
    var endsOn: String?
    var costCents: Int?
    var note: String?
    let createdAt: String

    static let channels = ["Text", "Email", "Mail", "Door hangers", "Social", "Online ad", "Other"]

    init(id: String = UUID().uuidString, name: String, channel: String = "Text", startsOn: String? = nil,
         endsOn: String? = nil, costCents: Int? = nil, note: String? = nil,
         createdAt: String = ISO8601DateFormatter().string(from: Date())) {
        self.id = id; self.name = name; self.channel = channel; self.startsOn = startsOn
        self.endsOn = endsOn; self.costCents = costCents; self.note = note; self.createdAt = createdAt
    }
}

enum MarketingCampaigns {
    /// "1,250.50" or "$1250" as cents. Nil for nothing, a negative, or anything that is not money.
    static func cents(from text: String) -> Int? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
        guard cleaned.contains(where: { $0.isNumber }),
              cleaned.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }) else { return nil }
        let parts = cleaned.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, let dollars = Int(parts[0].isEmpty ? "0" : parts[0]), dollars <= 100_000_000 else { return nil }
        var cents = 0
        if parts.count == 2 {
            let fraction = parts[1]
            guard fraction.count <= 2, let value = Int(fraction.isEmpty ? "0" : fraction) else { return nil }
            cents = fraction.count == 1 ? value * 10 : value
        }
        return dollars * 100 + cents
    }

    /// The cost as it is typed back into the field: "1250.50", "300".
    static func text(cents: Int?) -> String {
        guard let cents else { return "" }
        return cents % 100 == 0 ? "\(cents / 100)" : String(format: "%d.%02d", cents / 100, cents % 100)
    }

    static func totalCents(_ notes: [MarketingCampaignNote]) -> Int {
        notes.reduce(0) { $0 + ($1.costCents ?? 0) }
    }

    /// "Sep 1, 2026", "Sep 1, 2026 to Sep 30, 2026", or nil with no dates.
    static func dates(_ note: MarketingCampaignNote, calendar: Calendar = .current, locale: Locale = .current) -> String? {
        let start = LearnDay.date(from: note.startsOn, calendar: calendar).map { LearnDay.label($0, calendar: calendar, locale: locale) }
        let end = LearnDay.date(from: note.endsOn, calendar: calendar).map { LearnDay.label($0, calendar: calendar, locale: locale) }
        switch (start, end) {
        case let (start?, end?): return start == end ? start : "\(start) to \(end)"
        case let (start?, nil): return start
        case let (nil, end?): return "Until \(end)"
        default: return nil
        }
    }

    /// Newest start first; notes with no start date after them, newest written first.
    static func sorted(_ notes: [MarketingCampaignNote]) -> [MarketingCampaignNote] {
        notes.sorted { lhs, rhs in
            switch (lhs.startsOn, rhs.startsOn) {
            case let (a?, b?) where a != b: return a > b
            case (.some, .none): return true
            case (.none, .some): return false
            default: return lhs.createdAt > rhs.createdAt
            }
        }
    }
}

private struct MarketingBook: Codable {
    var campaigns: [MarketingCampaignNote] = []
}

/// One workspace's campaign notes on this phone. Every sign-in to that workspace on this phone
/// sees the same notes; they are the business's, not one person's.
@MainActor
final class MarketingRecords {
    let fileURL: URL
    private var book: MarketingBook

    var campaigns: [MarketingCampaignNote] { book.campaigns }

    init(organizationID: String, directory: URL? = nil) throws {
        let name = try LearnPartition.name(kind: "marketing", actorID: nil, organizationID: organizationID)
        fileURL = LearnPartition.root(directory).appendingPathComponent("\(name).json")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            book = try JSONDecoder().decode(MarketingBook.self, from: Data(contentsOf: fileURL))
        } else {
            book = MarketingBook()
        }
    }

    private func commit(_ next: MarketingBook) throws {
        try LearnPartition.write(JSONEncoder().encode(next), to: fileURL)
        book = next
    }

    func save(_ note: MarketingCampaignNote) throws {
        var next = book
        if let index = next.campaigns.firstIndex(where: { $0.id == note.id }) {
            next.campaigns[index] = note
        } else {
            next.campaigns.append(note)
        }
        try commit(next)
    }

    func removeCampaign(_ id: String) throws {
        var next = book
        next.campaigns.removeAll { $0.id == id }
        try commit(next)
    }

    func erasePartition() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) { try FileManager.default.removeItem(at: fileURL) }
        book = MarketingBook()
    }
}

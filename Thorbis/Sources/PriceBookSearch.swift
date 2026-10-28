import Foundation

/// EB-01..EB-05: the estimate builder's price book search. It runs on the device over the whole
/// cached catalog on every keystroke, so it never waits on the network and works offline.
enum PriceBookKindFilter: String, CaseIterable, Identifiable {
    case all, service, material, labor, assembly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .service: "Services"
        case .material: "Materials"
        case .labor: "Labor"
        case .assembly: "Assemblies"
        }
    }

    func includes(_ item: PriceBookListItem) -> Bool {
        self == .all || item.kind == rawValue
    }
}

struct PriceBookSearchResult: Identifiable, Equatable {
    let item: PriceBookListItem
    /// Ranges of `item.description` that matched a typed word, for weight-500 emphasis (EB-03).
    let highlights: [Range<String.Index>]
    var id: String { item.id }

    static func == (lhs: PriceBookSearchResult, rhs: PriceBookSearchResult) -> Bool {
        lhs.item.id == rhs.item.id && lhs.highlights == rhs.highlights
    }
}

struct PriceBookSearchIndex {
    private struct Entry {
        let item: PriceBookListItem
        let normalizedDescription: String
        /// Searchable words: description, unit and kind (with its plural), normalized.
        let words: [String]
    }

    /// Quality of one typed word against one item word. Higher is better.
    private enum WordMatch: Int, Comparable {
        case typo = 1, contains = 2, prefix = 3, exact = 4
        static func < (lhs: WordMatch, rhs: WordMatch) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    static let resultLimit = 50
    static let recentLimit = 12

    private let entries: [Entry]

    /// Archived items and other currencies never appear (EB-08).
    init(items: [PriceBookListItem], currency: String = "USD") {
        entries = items.compactMap { item in
            guard item.archivedAt == nil, item.sellPrice.currency == currency else { return nil }
            let kindWords = item.kind.isEmpty ? [] : [item.kind, item.kind + "s"]
            let words = Self.words(item.description) + Self.words(item.unit) + kindWords.map(Self.normalize)
            return Entry(item: item, normalizedDescription: Self.normalize(item.description), words: words)
        }
    }

    var count: Int { entries.count }

    /// Ranked results for `query` (EB-02, EB-03). An empty query lists the filter's items A to Z.
    func search(_ query: String, kind: PriceBookKindFilter = .all,
                usage: [String: PriceBookUsage] = [:], now: Date = Date()) -> [PriceBookSearchResult] {
        let queryWords = Self.words(query)
        let candidates = entries.filter { kind.includes($0.item) }
        guard !queryWords.isEmpty else {
            return candidates
                .sorted { $0.item.description.localizedStandardCompare($1.item.description) == .orderedAscending }
                .prefix(Self.resultLimit)
                .map { PriceBookSearchResult(item: $0.item, highlights: []) }
        }
        let normalizedQuery = queryWords.joined(separator: " ")
        var scored: [(entry: Entry, tier: Int, frecency: Double)] = []
        for entry in candidates {
            guard let tier = Self.tier(of: entry, queryWords: queryWords, normalizedQuery: normalizedQuery) else { continue }
            scored.append((entry, tier, usage[entry.item.id]?.frecency(now: now) ?? 0))
        }
        scored.sort { lhs, rhs in
            if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
            if lhs.frecency != rhs.frecency { return lhs.frecency > rhs.frecency }
            let lhsLength = lhs.entry.item.description.count, rhsLength = rhs.entry.item.description.count
            if lhsLength != rhsLength { return lhsLength < rhsLength }
            return lhs.entry.item.description.localizedStandardCompare(rhs.entry.item.description) == .orderedAscending
        }
        return scored.prefix(Self.resultLimit).map {
            PriceBookSearchResult(item: $0.entry.item, highlights: Self.highlights(in: $0.entry.item.description, words: queryWords))
        }
    }

    /// EB-04: the items this device adds most often and most recently.
    func recent(kind: PriceBookKindFilter = .all, usage: [String: PriceBookUsage], now: Date = Date()) -> [PriceBookListItem] {
        entries
            .filter { kind.includes($0.item) && usage[$0.item.id] != nil }
            .map { ($0.item, usage[$0.item.id]!) }
            .sorted { lhs, rhs in
                let left = lhs.1.frecency(now: now), right = rhs.1.frecency(now: now)
                if left != right { return left > right }
                return lhs.1.lastUsed > rhs.1.lastUsed
            }
            .prefix(Self.recentLimit)
            .map(\.0)
    }

    // MARK: Matching

    /// 0 whole description, 1 description starts with the query, 2 every word a word start,
    /// 3 some word only contained, 4 some word only within one typo. Nil when any word misses.
    private static func tier(of entry: Entry, queryWords: [String], normalizedQuery: String) -> Int? {
        var worst = WordMatch.exact
        for (index, word) in queryWords.enumerated() {
            let typing = index == queryWords.count - 1
            guard let match = entry.words.compactMap({ match(word, against: $0, typing: typing) }).max() else { return nil }
            worst = min(worst, match)
        }
        if entry.normalizedDescription == normalizedQuery { return 0 }
        if entry.normalizedDescription.hasPrefix(normalizedQuery) { return 1 }
        switch worst {
        case .exact, .prefix: return 2
        case .contains: return 3
        case .typo: return 4
        }
    }

    /// Numbers never take a typo or a contains match, and only the word still being typed may
    /// match a longer number as a prefix ("12" must not find "120" once the next word is typed).
    private static func match(_ query: String, against word: String, typing: Bool) -> WordMatch? {
        if word == query { return .exact }
        let numeric = query.allSatisfy(\.isNumber)
        if numeric { return typing && word.hasPrefix(query) ? .prefix : nil }
        if word.hasPrefix(query) { return .prefix }
        if query.count >= 3, word.contains(query) { return .contains }
        guard query.count >= 4 else { return nil }
        if abs(word.count - query.count) <= 1, editDistanceAtMostOne(query, word) { return .typo }
        // While typing, a typo inside the part typed so far still counts ("capicit" → "capacitor").
        if typing, word.count > query.count, editDistanceAtMostOne(query, String(word.prefix(query.count))) { return .typo }
        return nil
    }

    /// Damerau-Levenshtein distance ≤ 1: one insertion, deletion, substitution or swap of neighbours.
    static func editDistanceAtMostOne(_ a: String, _ b: String) -> Bool {
        let x = Array(a), y = Array(b)
        if x == y { return true }
        if abs(x.count - y.count) > 1 { return false }
        var i = 0
        while i < min(x.count, y.count), x[i] == y[i] { i += 1 }
        if x.count == y.count {
            if Array(x[(i + 1)...]) == Array(y[(i + 1)...]) { return true }
            return i + 1 < x.count && x[i] == y[i + 1] && x[i + 1] == y[i] && Array(x[(i + 2)...]) == Array(y[(i + 2)...])
        }
        let (short, long) = x.count < y.count ? (x, y) : (y, x)
        return Array(short[i...]) == Array(long[(i + 1)...])
    }

    // MARK: Text

    static func normalize(_ text: String) -> String {
        words(text).joined(separator: " ")
    }

    /// Lowercased, accent-folded runs of letters and digits ("45/5 MFD" → ["45", "5", "mfd"]).
    static func words(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    /// Word-start matches of typed words in the original description, for emphasis only.
    private static func highlights(in description: String, words queryWords: [String]) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        for word in queryWords {
            var searchStart = description.startIndex
            while let range = description.range(of: word, options: options, range: searchStart..<description.endIndex) {
                let atWordStart = range.lowerBound == description.startIndex ||
                    !(description[description.index(before: range.lowerBound)].isLetter || description[description.index(before: range.lowerBound)].isNumber)
                if atWordStart { ranges.append(range); break }
                searchStart = range.upperBound
            }
        }
        return ranges.sorted { $0.lowerBound < $1.lowerBound }
    }
}

/// How often and how lately this device added one price book item. Never leaves the device (EB-04).
struct PriceBookUsage: Codable, Equatable {
    var count: Int
    var lastUsed: Date

    /// Uses fade by half every 30 days so last month's habit outranks last year's.
    func frecency(now: Date) -> Double {
        let days = max(0, now.timeIntervalSince(lastUsed)) / 86_400
        return Double(count) * pow(0.5, days / 30)
    }
}

/// Per-organization usage counts in UserDefaults, capped so the record stays small.
struct PriceBookUsageStore {
    static let maximumEntries = 400
    private let defaults: UserDefaults
    private let key: String

    init(organizationID: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        key = "priceBookUsage.\(organizationID)"
    }

    func load() -> [String: PriceBookUsage] {
        guard let data = defaults.data(forKey: key),
              let usage = try? JSONDecoder().decode([String: PriceBookUsage].self, from: data) else { return [:] }
        return usage
    }

    @discardableResult
    func record(_ itemID: String, now: Date = Date()) -> [String: PriceBookUsage] {
        var usage = load()
        usage[itemID] = PriceBookUsage(count: (usage[itemID]?.count ?? 0) + 1, lastUsed: now)
        if usage.count > Self.maximumEntries {
            let keep = usage.sorted { $0.value.frecency(now: now) > $1.value.frecency(now: now) }.prefix(Self.maximumEntries)
            usage = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        if let data = try? JSONEncoder().encode(usage) { defaults.set(data, forKey: key) }
        return usage
    }
}

/// The whole active price book for the signed-in organization, kept on the device so search is
/// instant and works offline (EB-01). Opening a builder shows the cached copy at once and
/// refreshes it in the background.
@MainActor
final class PriceBookCatalog: ObservableObject {
    static let shared = PriceBookCatalog()
    /// 50 pages of 200 is far beyond any real price book; the cap only bounds a runaway cursor.
    static let maximumPages = 50

    @Published private(set) var items: [PriceBookListItem] = []
    @Published private(set) var index = PriceBookSearchIndex(items: [])
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published private(set) var usage: [String: PriceBookUsage] = [:]
    private(set) var organizationID: String?
    private var lastRefresh: Date?
    private var loadingOrganizationID: String?

    /// Shows the cached catalog for `organizationID` right away, then reloads every page.
    func refresh(api: APIClient, organizationID: String?, force: Bool = false) async {
        guard let organizationID else { return }
        if self.organizationID != organizationID {
            self.organizationID = organizationID
            apply(Self.readCache(organizationID) ?? [])
            usage = PriceBookUsageStore(organizationID: organizationID).load()
            lastRefresh = nil
        }
        if !force, let lastRefresh, Date().timeIntervalSince(lastRefresh) < 60 { return }
        // One load per organization: switching workspaces starts the new one's load, and the
        // old load's result is dropped below because the organization no longer matches.
        guard loadingOrganizationID != organizationID else { return }
        loadingOrganizationID = organizationID
        loading = true
        defer {
            if loadingOrganizationID == organizationID {
                loadingOrganizationID = nil
                loading = false
            }
        }
        do {
            var all: [PriceBookListItem] = []
            var seen = Set<String>()
            var cursor: String?
            var pages = 0
            repeat {
                let page = try await api.priceBookItems(limit: 200, cursor: cursor)
                for item in page.items where seen.insert(item.id).inserted { all.append(item) }
                cursor = page.nextCursor
                pages += 1
            } while cursor != nil && pages < Self.maximumPages
            guard self.organizationID == organizationID else { return }
            apply(all)
            lastRefresh = Date()
            error = nil
            Self.writeCache(all, organizationID: organizationID)
        } catch is CancellationError {
        } catch {
            guard self.organizationID == organizationID else { return }
            self.error = error.localizedDescription
        }
    }

    func recordUse(_ itemID: String) {
        guard let organizationID else { return }
        usage = PriceBookUsageStore(organizationID: organizationID).record(itemID)
    }

    func item(id: String) -> PriceBookListItem? {
        items.first { $0.id == id }
    }

    private func apply(_ items: [PriceBookListItem]) {
        self.items = items
        index = PriceBookSearchIndex(items: items)
    }

    // MARK: Disk cache

    private struct CachedItem: Codable {
        let id, description, unit, kind, taxClassification: String
        let sellPrice: FieldMoney
        let revision: Int
    }

    private static var directory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("PriceBook", isDirectory: true)
    }

    private static func cacheURL(_ organizationID: String) -> URL? {
        guard UUID(uuidString: organizationID) != nil else { return nil }
        return directory?.appendingPathComponent("\(organizationID.lowercased()).json")
    }

    private static func readCache(_ organizationID: String) -> [PriceBookListItem]? {
        guard let url = cacheURL(organizationID), let data = try? Data(contentsOf: url),
              let cached = try? JSONDecoder().decode([CachedItem].self, from: data) else { return nil }
        return cached.map {
            PriceBookListItem(id: $0.id, description: $0.description, unit: $0.unit, kind: $0.kind,
                              taxClassification: $0.taxClassification, sellPrice: $0.sellPrice,
                              revision: $0.revision, archivedAt: nil)
        }
    }

    private static func writeCache(_ items: [PriceBookListItem], organizationID: String) {
        guard let url = cacheURL(organizationID), let directory else { return }
        let active = items.filter { $0.archivedAt == nil }.map {
            CachedItem(id: $0.id, description: $0.description, unit: $0.unit, kind: $0.kind,
                       taxClassification: $0.taxClassification, sellPrice: $0.sellPrice, revision: $0.revision)
        }
        guard let data = try? JSONEncoder().encode(active) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    /// Sign-out forgets every organization's cached price book and this session's copy.
    func clear() {
        organizationID = nil
        lastRefresh = nil
        loadingOrganizationID = nil
        loading = false
        usage = [:]
        apply([])
        if let directory = Self.directory { try? FileManager.default.removeItem(at: directory) }
    }
}

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

struct PriceBookSearchPage {
    let results: [PriceBookSearchResult]
    let total: Int
    let offset: Int
}

struct PriceBookSearchIndex {
    private struct Entry {
        let item: PriceBookListItem
        let normalizedDescription: String
        /// Searchable words: description, unit and kind (with its plural), normalized.
        let words: [String]
    }

    // Each immutable index owns a single bounded result cache. Catalog refreshes build a
    // new index, so cached prices and revisions cannot outlive the snapshot they came from.
    private struct CacheKey: Equatable {
        let query: String
        let kind: PriceBookKindFilter
        let usage: [String: PriceBookUsage]
        let now: Date
        let excluded: Set<String>
    }

    private final class Cache {
        private let lock = NSLock()
        private var value: (CacheKey, [Entry])?

        func get(_ key: CacheKey) -> [Entry]? {
            lock.withLock { value?.0 == key ? value?.1 : nil }
        }

        func put(_ key: CacheKey, entries: [Entry]) {
            lock.withLock { value = (key, entries) }
        }
    }

    /// Quality of one typed word against one item word. Higher is better.
    private enum WordMatch: Int, Comparable {
        case typo = 1, contains = 2, prefix = 3, exact = 4
        static func < (lhs: WordMatch, rhs: WordMatch) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    static let resultLimit = 50
    static let recentLimit = 12

    private let entries: [Entry]
    private let cache = Cache()

    /// Archived items and other currencies never appear (EB-08).
    init(items: [PriceBookListItem], currency: String = "USD") {
        entries = items.compactMap { item in
            guard item.archivedAt == nil, item.sellPrice.currency == currency else { return nil }
            let kindWords = item.kind.isEmpty ? [] : [item.kind, item.kind + "s"]
            let nameWords = Self.words(item.description)
            // A letter word joined to its neighbouring number, so "R410A" finds "R-410A" exactly
            // instead of by a typo. Two numbers never join: "45/5" is not "455".
            let joined = zip(nameWords, nameWords.dropFirst())
                .filter { $0.contains(where: \.isNumber) != $1.contains(where: \.isNumber) }
                .map { $0 + $1 }
            let words = nameWords + joined + Self.words(item.unit) + kindWords.map(Self.normalize)
            return Entry(item: item, normalizedDescription: Self.normalize(item.description), words: words)
        }
    }

    var count: Int { entries.count }

    /// Ranked results for `query` (EB-02, EB-03). An empty query lists the filter's items A to Z.
    func search(_ query: String, kind: PriceBookKindFilter = .all,
                usage: [String: PriceBookUsage] = [:], now: Date = Date()) -> [PriceBookSearchResult] {
        page(query, kind: kind, usage: usage, now: now).results
    }

    /// Counts all locally loaded matches while only formatting the requested visible prefix.
    func page(_ query: String, kind: PriceBookKindFilter = .all,
              usage: [String: PriceBookUsage] = [:], now: Date = Date(),
              excludingIDs: Set<String> = [], limit: Int? = nil, offset: Int = 0) -> PriceBookSearchPage {
        let queryWords = Self.words(query)
        let key = CacheKey(query: query, kind: kind, usage: usage, now: now, excluded: excludingIDs)
        let ordered: [Entry]
        if let cached = cache.get(key) {
            ordered = cached
        } else {
            ordered = orderedEntries(queryWords: queryWords, kind: kind, usage: usage, now: now, excludingIDs: excludingIDs)
            cache.put(key, entries: ordered)
        }
        let pageSize = max(1, limit ?? max(1, ordered.count))
        let start = min(max(0, offset), ordered.isEmpty ? 0 : ((ordered.count - 1) / pageSize) * pageSize)
        let results = ordered.dropFirst(start).prefix(pageSize).map {
            PriceBookSearchResult(item: $0.item, highlights: Self.highlights(in: $0.item.description, words: queryWords))
        }
        return PriceBookSearchPage(results: results, total: ordered.count, offset: start)
    }

    private func orderedEntries(queryWords: [String], kind: PriceBookKindFilter,
                                usage: [String: PriceBookUsage], now: Date,
                                excludingIDs: Set<String>) -> [Entry] {
        let candidates = entries.filter { kind.includes($0.item) && !excludingIDs.contains($0.item.id) }
        guard !queryWords.isEmpty else {
            return candidates.sorted { $0.item.description.localizedStandardCompare($1.item.description) == .orderedAscending }
        }
        // "R-410A" typed against a book that writes "R410A": try the query with each letter word
        // joined to its neighbouring number too, the same join the index makes.
        let spellings = Set([queryWords, Self.joinedModelWords(queryWords)]).map { ($0, $0.joined(separator: " ")) }
        var scored: [(entry: Entry, tier: Int, frecency: Double)] = []
        for entry in candidates {
            guard let tier = spellings.compactMap({ Self.tier(of: entry, queryWords: $0.0, normalizedQuery: $0.1) }).min()
            else { continue }
            scored.append((entry, tier, usage[entry.item.id]?.frecency(now: now) ?? 0))
        }
        scored.sort { lhs, rhs in
            if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
            if lhs.frecency != rhs.frecency { return lhs.frecency > rhs.frecency }
            let lhsLength = lhs.entry.item.description.count, rhsLength = rhs.entry.item.description.count
            if lhsLength != rhsLength { return lhsLength < rhsLength }
            return lhs.entry.item.description.localizedStandardCompare(rhs.entry.item.description) == .orderedAscending
        }
        return scored.map(\.entry)
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

    /// Each letter word joined to the number next to it ("r", "410a" → "r410a"); two numbers never
    /// join. The index adds the same joins for descriptions.
    static func joinedModelWords(_ words: [String]) -> [String] {
        var joined: [String] = []
        var index = words.startIndex
        while index < words.endIndex {
            let word = words[index]
            let next = words.index(after: index)
            if next < words.endIndex,
               word.contains(where: \.isNumber) != words[next].contains(where: \.isNumber) {
                joined.append(word + words[next])
                index = words.index(after: next)
            } else {
                joined.append(word)
                index = next
            }
        }
        return joined
    }

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

    /// A word with any digit in it is a number, model or size ("12", "R410A", "10mm"): it never
    /// takes a typo or a contains match, and only the word still being typed may match a longer
    /// one as a prefix. So "R420A" never finds "R410A", "10mm" never finds "110mm", and "12"
    /// stops finding "120" once the next word is typed.
    private static func match(_ query: String, against word: String, typing: Bool) -> WordMatch? {
        if word == query { return .exact }
        if query.contains(where: \.isNumber) { return typing && word.hasPrefix(query) ? .prefix : nil }
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
struct PriceBookCatalogContext: Hashable {
    let organizationID: String?
    let sessionGeneration: UUID
}

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
    private(set) var context: PriceBookCatalogContext?
    private var loadingRequest: (context: PriceBookCatalogContext, apiGeneration: UUID, id: UUID, task: Task<Void, Never>)?

    /// Shows the cached catalog for `organizationID` right away, then reloads every page.
    func refresh(api: APIClient, organizationID: String?, sessionGeneration: UUID, force: Bool = false) async {
        guard !Task.isCancelled else { return }
        let apiGeneration = api.requestGeneration
        let requested = PriceBookCatalogContext(organizationID: organizationID, sessionGeneration: sessionGeneration)
        if context != requested {
            context = requested
            self.organizationID = organizationID
            apply(organizationID.flatMap(Self.readCache) ?? [])
            usage = organizationID.map { PriceBookUsageStore(organizationID: $0).load() } ?? [:]
            lastRefresh = nil
            error = nil
        }
        guard let organizationID else {
            loadingRequest?.task.cancel()
            loadingRequest = nil
            loading = false
            return
        }
        if !force, let lastRefresh, Date().timeIntervalSince(lastRefresh) < 60 { return }
        if let pending = loadingRequest, pending.context == requested, pending.apiGeneration == apiGeneration {
            await pending.task.value
            return
        }
        loadingRequest?.task.cancel()
        let request = UUID()
        loading = true
        // The catalog owns this work so closing its initiating view cannot strand other callers.
        let task = Task {
            await self.load(api: api, organizationID: organizationID, context: requested,
                            apiGeneration: apiGeneration, request: request)
        }
        loadingRequest = (requested, apiGeneration, request, task)
        await task.value
    }

    private func load(api: APIClient, organizationID: String, context requested: PriceBookCatalogContext,
                      apiGeneration: UUID, request: UUID) async {
        let current: @MainActor () -> Bool = {
            self.context == requested && self.loadingRequest?.id == request &&
                api.requestGeneration == apiGeneration && !Task.isCancelled
        }
        defer {
            if loadingRequest?.id == request {
                loadingRequest = nil
                loading = false
            }
        }
        do {
            var all: [PriceBookListItem] = []
            var seen = Set<String>()
            var cursor: String?
            var pages = 0
            repeat {
                guard current() else { return }
                let page = try await api.priceBookItems(limit: 200, cursor: cursor)
                guard current() else { return }
                for item in page.items where seen.insert(item.id).inserted { all.append(item) }
                cursor = page.nextCursor
                pages += 1
            } while cursor != nil && pages < Self.maximumPages
            guard current() else { return }
            guard cursor == nil else {
                throw Problem(title: "Couldn't load the whole price book", status: nil,
                              detail: "Refresh the catalog before using items that are missing.")
            }
            apply(all)
            lastRefresh = Date()
            error = nil
            Self.writeCache(all, organizationID: organizationID)
        } catch is CancellationError {
        } catch {
            guard current() else { return }
            self.error = PriceBookLoadError.message(for: error)
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
        context = nil
        loadingRequest?.task.cancel()
        loadingRequest = nil
        error = nil
        loading = false
        usage = [:]
        apply([])
        if let directory = Self.directory { try? FileManager.default.removeItem(at: directory) }
    }
}

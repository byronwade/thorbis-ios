import SwiftUI
import UniformTypeIdentifiers

/// Work or Materials (EB-09). Every line sits in exactly one; Work lines always come first.
enum EstimateLineGroup: String, CaseIterable, Identifiable {
    case work, material

    var id: String { rawValue }
    var title: String { self == .work ? "Work" : "Materials" }
    var other: EstimateLineGroup { self == .work ? .material : .work }

    static func forKind(_ kind: String) -> EstimateLineGroup { kind == "material" ? .material : .work }
}

struct PriceBookLineOriginal: Equatable {
    let description: String
    let unitPrice: String
}

/// Line operations the estimate builder shares between a new estimate, a revision and each
/// option package. The array always keeps Work lines before Materials, so the saved order is
/// the order on screen.
extension Array where Element == EstimateRevisionLineDraft {
    static var maximumLines: Int { 500 }

    func lines(in group: EstimateLineGroup) -> [EstimateRevisionLineDraft] {
        filter { $0.group == group }
    }

    /// EB-13: whether the customer sees each material line. One hidden material hides them all,
    /// so a material added while the switch is off is folded in too.
    var showsMaterials: Bool { !contains { $0.group == .material && !$0.showToCustomer } }

    mutating func setShowsMaterials(_ shown: Bool) {
        for index in indices where self[index].group == .material { self[index].showToCustomer = shown }
    }

    /// Puts a line in at `index` following the switch, so a material added while it is off stays
    /// hidden even after the other hidden materials are removed.
    private mutating func insertFollowingSwitch(_ line: EstimateRevisionLineDraft, at index: Int, shown: Bool? = nil) {
        var line = line
        line.showToCustomer = shown ?? showsMaterials
        insert(line, at: index)
    }

    /// The saved `group` and `showToCustomer` of one line, or nil for both while the workspace
    /// doesn't store groups yet (`estimate_line_groups`).
    func storedPresentation(of line: EstimateRevisionLineDraft, storesGroups: Bool) -> (group: String?, showToCustomer: Bool?) {
        guard storesGroups else { return (nil, nil) }
        return (line.group.rawValue, line.group == .material && !showsMaterials ? false : nil)
    }

    /// Sum of qty × each in cents, or nil while any line's price or quantity is unreadable.
    func subtotal(_ group: EstimateLineGroup? = nil) -> Int? {
        var sum = 0
        for line in self where group == nil || line.group == group {
            guard let cents = EstimateRevisionEditorState.parsePrice(line.unitPrice),
                  let quantity = Int(line.quantity.trimmingCharacters(in: .whitespacesAndNewlines)),
                  (1...100_000).contains(quantity) else { return nil }
            let (amount, overflow) = cents.multipliedReportingOverflow(by: quantity)
            let (next, overflowSum) = sum.addingReportingOverflow(amount)
            guard !overflow, !overflowSum else { return nil }
            sum = next
        }
        return sum
    }

    /// The quantity already on the estimate for one price book item, for "× 2" in results (EB-06).
    func quantity(ofPriceBookItem itemID: String) -> Int? {
        let matches = filter {
            if case .priceBookSelection(let id, _) = $0.source { return id == itemID }
            return false
        }
        guard !matches.isEmpty else { return nil }
        return matches.reduce(0) { $0 + (Int($1.quantity) ?? 0) }
    }

    /// Adds one of a price book item, or one more to the line that already holds it untouched
    /// (EB-06). Returns the line's id, or nil at the 500-line limit.
    @discardableResult
    mutating func addPriceBookItem(_ item: PriceBookListItem, to group: EstimateLineGroup? = nil) -> UUID? {
        let price = EstimateRevisionEditorState.priceText(item.sellPrice.amount)
        let targetGroup = group ?? .forKind(item.kind)
        if let index = firstIndex(where: { line in
            guard case .priceBookSelection(let id, let revision) = line.source else { return false }
            return id == item.id && revision == item.revision && line.group == targetGroup &&
                line.description == item.description && line.unitPrice == price
        }), let quantity = Int(self[index].quantity), quantity < 100_000 {
            self[index].quantity = String(quantity + 1)
            return self[index].id
        }
        guard count < Self.maximumLines else { return nil }
        let line = EstimateRevisionLineDraft(
            description: item.description, quantity: "1", unitPrice: price,
            source: .priceBookSelection(itemID: item.id, revision: item.revision),
            group: targetGroup,
            priceBookOriginal: PriceBookLineOriginal(description: item.description, unitPrice: price)
        )
        insertFollowingSwitch(line, at: insertionIndex(for: line.group))
        return line.id
    }

    /// EB-07: what was typed becomes a line; the price is left for the person to enter.
    @discardableResult
    mutating func addCustomLine(_ description: String = "", to group: EstimateLineGroup) -> UUID? {
        guard count < Self.maximumLines else { return nil }
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let line = EstimateRevisionLineDraft(description: trimmed, quantity: "1", unitPrice: "", source: .manual, group: group)
        insertFollowingSwitch(line, at: insertionIndex(for: group))
        return line.id
    }

    @discardableResult
    mutating func duplicateLine(id: UUID) -> UUID? {
        guard count < Self.maximumLines, let index = firstIndex(where: { $0.id == id }) else { return nil }
        let line = self[index]
        let copy = EstimateRevisionLineDraft(description: line.description, quantity: line.quantity,
                                             unitPrice: line.unitPrice, source: line.source, group: line.group,
                                             priceBookOriginal: line.priceBookOriginal)
        insertFollowingSwitch(copy, at: index + 1)
        return copy.id
    }

    /// Removes a line and returns it with its position, so Undo can put it back (EB-12).
    mutating func removeLine(id: UUID) -> (line: EstimateRevisionLineDraft, index: Int)? {
        guard let index = firstIndex(where: { $0.id == id }) else { return nil }
        return (remove(at: index), index)
    }

    mutating func restoreLine(_ line: EstimateRevisionLineDraft, at index: Int) {
        guard count < Self.maximumLines, !contains(where: { $0.id == line.id }) else { return }
        insertFollowingSwitch(line, at: Swift.min(Swift.max(0, index), count))
        normalizeGroups()
    }

    /// Moves a line one place within its group (VoiceOver, menus).
    mutating func moveLine(id: UUID, by offset: Int) {
        guard let line = first(where: { $0.id == id }) else { return }
        let ids = lines(in: line.group).map(\.id)
        guard let position = ids.firstIndex(of: id), ids.indices.contains(position + offset) else { return }
        moveLine(id: id, before: offset < 0 ? ids[position + offset] : (ids.indices.contains(position + offset + 1) ? ids[position + offset + 1] : nil),
                 group: line.group)
    }

    /// Drag and drop (EB-11): put a line just before `target`, or at the end of `group` when
    /// `target` is nil. Dropping into the other group moves the line to that group.
    mutating func moveLine(id: UUID, before target: UUID?, group: EstimateLineGroup) {
        guard id != target, let index = firstIndex(where: { $0.id == id }) else { return }
        let shown = showsMaterials
        var line = remove(at: index)
        line.group = group
        line.groupSettled = true
        line.movedByPerson = true
        if let target, let targetIndex = firstIndex(where: { $0.id == target }), self[targetIndex].group == group {
            insertFollowingSwitch(line, at: targetIndex, shown: shown)
        } else {
            insertFollowingSwitch(line, at: insertionIndex(for: group), shown: shown)
        }
    }

    mutating func setGroup(id: UUID, _ group: EstimateLineGroup) {
        moveLine(id: id, before: nil, group: group)
    }

    /// Puts the price book wording and price back on an edited line (EB-10).
    mutating func resetToPriceBook(id: UUID) {
        guard let index = firstIndex(where: { $0.id == id }), let original = self[index].priceBookOriginal else { return }
        self[index].description = original.description
        self[index].unitPrice = original.unitPrice
    }

    /// Lines loaded from the server don't carry their group yet; price book materials go to
    /// Materials by the catalog's kind, everything else stays in Work. Each line is sorted once,
    /// so a later catalog refresh never undoes a group or order the person chose.
    mutating func classifyGroups(kinds: [String: String]) {
        var changed = false
        for index in indices where !self[index].groupSettled {
            guard case .priceBookSelection(let itemID, _) = self[index].source, let kind = kinds[itemID] else { continue }
            self[index].group = .forKind(kind)
            self[index].groupSettled = true
            changed = true
        }
        if changed { normalizeGroups() }
    }

    /// Stable: Work lines first, then Materials, each in its current order.
    mutating func normalizeGroups() {
        let work = lines(in: .work), materials = lines(in: .material)
        let ordered = work + materials
        if ordered.map(\.id) != map(\.id) { self = ordered }
    }

    private func insertionIndex(for group: EstimateLineGroup) -> Int {
        group == .work ? (firstIndex { $0.group == .material } ?? count) : count
    }
}

enum EstimateDescriptionProblem {
    case empty, tooLong, priceBookOriginalTooLong
}

extension EstimateRevisionLineDraft {
    /// Price Book sources are snapshotted by the server, so changing the displayed line
    /// cannot repair an overlong original revision.
    var estimateDescriptionProblem: EstimateDescriptionProblem? {
        if case .priceBookSelection = source,
           let original = priceBookOriginal?.description.trimmingCharacters(in: .whitespacesAndNewlines),
           original.utf16.count > 200 { return .priceBookOriginalTooLong }
        let value = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return .empty }
        if value.utf16.count > 200 { return .tooLong }
        return nil
    }

    var isEditedPriceBookLine: Bool {
        guard let original = priceBookOriginal, case .priceBookSelection = source else { return false }
        return description.trimmingCharacters(in: .whitespacesAndNewlines) != original.description ||
            EstimateRevisionEditorState.parsePrice(unitPrice) != EstimateRevisionEditorState.parsePrice(original.unitPrice)
    }

    var lineTotal: Int? {
        guard let cents = EstimateRevisionEditorState.parsePrice(unitPrice),
              let quantity = Int(quantity.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...100_000).contains(quantity) else { return nil }
        let (amount, overflow) = cents.multipliedReportingOverflow(by: quantity)
        return overflow ? nil : amount
    }
}


extension Array where Element == EstimateRevisionLineDraft {
    /// A discount as a credit line at the end of the lines: one, at a negative fixed price.
    /// Only a revision with the discount capability can save it (the server checks too).
    @discardableResult
    mutating func addCreditLine(_ description: String, cents: Int) -> UUID? {
        guard count < Self.maximumLines, cents > 0 else { return nil }
        let line = EstimateRevisionLineDraft(description: description, quantity: "1",
                                             unitPrice: EstimateRevisionEditorState.priceText(-cents),
                                             source: .manual, group: last?.group ?? .work)
        append(line)
        return line.id
    }

    /// The same lines with fresh identities, for "Copy option": nothing points at the original
    /// server lines, while the price book source and wording stay.
    func copiedForNewOption() -> [EstimateRevisionLineDraft] {
        map { line in
            EstimateRevisionLineDraft(description: line.description, quantity: line.quantity, unitPrice: line.unitPrice,
                                      source: line.source, group: line.group, priceBookOriginal: line.priceBookOriginal)
        }
    }

    /// What a member would pay for these lines (MF-05), or nil while a line is unreadable.
    func memberTotal(_ pricing: MemberPricing?) -> Int? {
        guard let pricing, pricing.isMember, pricing.discountPercent > 0, !isEmpty else { return nil }
        var sum = 0
        for line in self {
            guard let cents = EstimateRevisionEditorState.parsePrice(line.unitPrice),
                  let quantity = Int(line.quantity.trimmingCharacters(in: .whitespacesAndNewlines)),
                  (1...100_000).contains(quantity) else { return nil }
            // Same bounds as `subtotal`: a long quantity must read as "not yet", never trap.
            let (amount, overflow) = quantity.multipliedReportingOverflow(by: cents > 0 ? pricing.memberPrice(cents) : cents)
            let (next, overflowSum) = sum.addingReportingOverflow(amount)
            guard !overflow, !overflowSum else { return nil }
            sum = next
        }
        return sum
    }
}

// MARK: - Focus and targets

enum EstimateBuilderFocus: Hashable {
    case search
    case description(UUID)
    case quantity(UUID)
    case price(UUID)

    var lineID: UUID? {
        switch self {
        case .search: nil
        case .description(let id), .quantity(let id), .price(let id): id
        }
    }
}

/// Where the next price book pick goes: the estimate's own lines or one option package, and
/// optionally a group.
struct EstimateBuilderTarget: Equatable, Identifiable {
    var optionID: String?
    var group: EstimateLineGroup?
    var id: String { "\(optionID ?? "main")|\(group?.rawValue ?? "any")" }
}

/// The keyboard is up: the builder hides its totals so the commit and the edited field stay visible.
private struct KeyboardVisibility: ViewModifier {
    @Binding var visible: Bool

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in visible = true }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in visible = false }
    }
}

extension View {
    func trackKeyboard(_ visible: Binding<Bool>) -> some View { modifier(KeyboardVisibility(visible: visible)) }
}

// MARK: - Price book results (EB-03..EB-07)

/// The price book list inside the cart picker: a custom item first, then this device's
/// favourites and recent items when nothing is typed, then the ranked catalog in pages.
struct PriceBookResultsList: View {
    @ObservedObject var catalog: PriceBookCatalog
    @EnvironmentObject private var api: APIClient
    let context: PriceBookCatalogContext
    let query: String
    let kind: PriceBookKindFilter
    let canUsePriceBook: Bool
    let quantityInCurrentDraft: (String) -> Int?
    let secondaryPriceText: (PriceBookListItem) -> String?
    let addItem: (PriceBookListItem) -> Void
    let addCustomLine: ((String) -> Void)?
    let retry: () -> Void
    var showFavorites = true

    @State private var pageOffset = 0
    @State private var partialPageAnchorID: String?
    @State private var usageSnapshot: [String: PriceBookUsage] = [:]
    @State private var rankingTime = Date()

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        let current = catalog.isCurrent(context, api: api)
        let browsing = canUsePriceBook && current && trimmedQuery.isEmpty
        let favorites = browsing && showFavorites ? catalog.index.favorites(kind: kind, ids: catalog.favorites) : []
        let favoriteIDs = Set(favorites.map(\.id))
        let recent = browsing
            ? catalog.index.recent(kind: kind, usage: usageSnapshot, now: rankingTime).filter { !favoriteIDs.contains($0.id) }
            : []
        let page = canUsePriceBook && current
            ? catalog.index.page(query, kind: kind, usage: usageSnapshot, now: rankingTime,
                                 excludingIDs: favoriteIDs.union(recent.map(\.id)),
                                 limit: PriceBookSearchIndex.resultLimit, offset: pageOffset)
            : PriceBookSearchPage(results: [], total: 0, offset: 0)
        let remaining = max(0, page.total - page.offset - page.results.count)
        VStack(alignment: .leading, spacing: 14) {
            if let addCustomLine {
                PaperCard {
                    Button { addCustomLine(trimmedQuery) } label: {
                        HStack(spacing: 12) {
                            PaperCircleLabel(symbol: "plus", size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Add a custom item")
                                    .font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                                if !trimmedQuery.isEmpty {
                                    Text(trimmedQuery)
                                        .font(Theme.font(14)).foregroundStyle(Theme.muted)
                                        .lineLimit(2)
                                }
                            }
                            .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10).frame(minHeight: 56).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("price-book-add-custom")
                }
            }
            if canUsePriceBook, catalog.context == context, catalog.denialPersistenceFailure, !catalog.accessDenied {
                ErrorBanner(message: "The saved price book could not be secured. Connect and finish refreshing it.") { retry() }
            }
            if canUsePriceBook, catalog.context == context, catalog.accessDenied {
                ErrorBanner(message: catalog.denialPersistenceFailure
                    ? "Price book access could not be verified, and its saved copy could not be secured. Connect and try again."
                    : "Price book access could not be verified. \(catalog.error ?? "Try again when you have access.")") { retry() }
            } else if canUsePriceBook, context.authority == nil {
                Text("Connect once to verify your price book access on this device.")
                    .font(Theme.font(15)).foregroundStyle(Theme.muted)
            } else if canUsePriceBook, !current || catalog.items.isEmpty {
                if !current || catalog.loading {
                    PaperCard { ForEach(0..<6, id: \.self) { _ in skeletonRow } }
                } else if let error = catalog.error, !catalog.isPartial {
                    ErrorBanner(message: catalog.needsScopedRefresh
                                    ? "The saved price book needs one online refresh after this update. \(error)"
                                    : "The price book didn’t load. \(error)",
                                retry: { retry() }).flush()
                }
            }
            if canUsePriceBook, current, catalog.isPartial {
                if let error = catalog.error {
                    ErrorBanner(message: "Only some price book items loaded. Search covers loaded items only. \(error)") { retry() }
                } else if catalog.loading {
                    Text("Loading more price book items. Search covers loaded items only.")
                        .font(Theme.font(14)).foregroundStyle(Theme.muted)
                        .accessibilityIdentifier("price-book-partial")
                } else {
                    ErrorBanner(message: "Only some price book items loaded. Search covers loaded items only. Refresh to load more.") { retry() }
                }
            } else if canUsePriceBook, current, !catalog.items.isEmpty, let error = catalog.error {
                ErrorBanner(message: "Couldn't refresh the price book. Showing saved items. \(error)") { retry() }
            }
            if !favorites.isEmpty {
                section("Favourites") { ForEach(favorites) { row(PriceBookSearchResult(item: $0, highlights: [])) } }
            }
            if !recent.isEmpty {
                section("Recent") { ForEach(recent) { row(PriceBookSearchResult(item: $0, highlights: [])) } }
            }
            if !page.results.isEmpty {
                section(trimmedQuery.isEmpty ? (favorites.isEmpty && recent.isEmpty ? nil : "Price book") : "Matches",
                        trailing: page.total > PriceBookSearchIndex.resultLimit
                            ? "\(page.offset + 1)–\(page.offset + page.results.count) of \(page.total)\(catalog.isPartial ? " loaded" : "")" : nil) {
                    if page.offset > 0 {
                        pageButton("Previous items", detail: nil, identifier: "price-book-previous") {
                            goToPage(max(0, page.offset - PriceBookSearchIndex.resultLimit), excluding: favoriteIDs.union(recent.map(\.id)))
                        }
                    }
                    ForEach(page.results, content: row)
                    if remaining > 0 {
                        pageButton("Next items", detail: "\(remaining)\(catalog.isPartial ? " loaded" : " remaining")", identifier: "price-book-show-more") {
                            goToPage(page.offset + PriceBookSearchIndex.resultLimit, excluding: favoriteIDs.union(recent.map(\.id)))
                        }
                    }
                }
            }
            if canUsePriceBook, current, !catalog.loading, !catalog.isPartial, catalog.error == nil,
               page.results.isEmpty, recent.isEmpty, favorites.isEmpty {
                if addCustomLine == nil {
                    PaperEmptyState(
                        symbol: catalog.items.isEmpty ? "book.closed" : "magnifyingglass",
                        title: catalog.items.isEmpty ? "No active Price Book items" : "No matching items",
                        message: catalog.items.isEmpty
                            ? "Add items to your Price Book to use them here."
                            : "Try another search or choose a different category.")
                } else if !trimmedQuery.isEmpty || !catalog.items.isEmpty {
                    Text("No price book items match. Add it as a custom item above, or try another word.")
                        .font(Theme.font(14)).foregroundStyle(Theme.muted)
                }
            }
            if !canUsePriceBook, addCustomLine != nil {
                Text("Type a line and add it. This account can't use the price book.")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, PaperCardMetrics.margin).padding(.bottom, 24)
        .onAppear { resetPage() }
        .onChange(of: query) { _, _ in resetPage() }
        .onChange(of: kind) { _, _ in resetPage() }
        .onChange(of: context) { previous, current in
            if !previous.hasSameVerifiedScope(as: current) ||
                !(catalog.isCurrent(previous, api: api) || catalog.isCurrent(current, api: api)) || catalog.isPartial || catalog.loading {
                resetPage()
            }
        }
        .onChange(of: api.requestGeneration) { _, _ in resetPage() }
        .onChange(of: catalog.context) { previous, current in
            guard let current, current == context else { return }
            if previous?.hasSameVerifiedScope(as: current) != true || !catalog.isCurrent(current, api: api) || catalog.isPartial || catalog.loading {
                resetPage()
            }
        }
        .onChange(of: catalog.isPartial) { wasPartial, isPartial in
            if isPartial {
                partialPageAnchorID = page.results.first?.id
            } else if wasPartial, let anchor = partialPageAnchorID {
                // Keep the item at the start of the prior page visible after the full
                // ranked catalog arrives; never alter the query or draft selection.
                pageOffset = catalog.index.pageOffset(containing: anchor, query: query, kind: kind,
                    usage: usageSnapshot, now: rankingTime,
                    excludingIDs: favoriteIDs.union(recent.map(\.id))) ?? pageOffset
                partialPageAnchorID = nil
            }
        }
    }

    private func resetPage() {
        pageOffset = 0
        usageSnapshot = catalog.usage
        rankingTime = Date()
        partialPageAnchorID = nil
        if catalog.isPartial, catalog.isCurrent(context, api: api) {
            let browsing = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let favorites = browsing && showFavorites ? catalog.index.favorites(kind: kind, ids: catalog.favorites) : []
            let favoriteIDs = Set(favorites.map(\.id))
            let recent = browsing ? catalog.index.recent(kind: kind, usage: usageSnapshot, now: rankingTime)
                .filter { !favoriteIDs.contains($0.id) } : []
            partialPageAnchorID = catalog.index.page(query, kind: kind, usage: usageSnapshot, now: rankingTime,
                excludingIDs: favoriteIDs.union(recent.map(\.id)), limit: PriceBookSearchIndex.resultLimit).results.first?.id
        }
    }

    private func goToPage(_ offset: Int, excluding: Set<String>) {
        pageOffset = offset
        if catalog.isPartial {
            partialPageAnchorID = catalog.index.page(query, kind: kind, usage: usageSnapshot,
                now: rankingTime, excludingIDs: excluding, limit: PriceBookSearchIndex.resultLimit,
                offset: offset).results.first?.id
        }
    }

    private func section<Content: View>(_ title: String?, trailing: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                HStack {
                    Text(title).font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    if let trailing {
                        Text(trailing).font(Theme.font(13)).monospacedDigit().foregroundStyle(Theme.muted)
                            .accessibilityIdentifier("price-book-page-range")
                    }
                }
                .padding(.horizontal, 4)
            }
            PaperCard { VStack(spacing: 0) { content() }.padding(.vertical, 4) }
        }
    }

    private func pageButton(_ title: String, detail: String?, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if let detail { Text(detail).foregroundStyle(Theme.muted) }
            }
            .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
            .padding(.horizontal, 14).frame(minHeight: 52).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private func row(_ result: PriceBookSearchResult) -> some View {
        PriceBookCatalogResultRow(result: result, quantity: quantityInCurrentDraft(result.id),
                                  secondaryPrice: secondaryPriceText(result.item),
                                  favorite: catalog.favorites.contains(result.id),
                                  toggleFavorite: showFavorites ? { catalog.toggleFavorite(result.id) } : nil) { addItem(result.item) }
    }

    private var skeletonRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(Theme.fill).frame(width: 190, height: 15)
                RoundedRectangle(cornerRadius: 4).fill(Theme.fill).frame(width: 90, height: 11)
            }
            Spacer()
            RoundedRectangle(cornerRadius: 4).fill(Theme.fill).frame(width: 70, height: 15)
        }
        .padding(.horizontal, 14).frame(minHeight: 60)
        .accessibilityHidden(true)
    }

    static func highlighted(_ text: String, _ ranges: [Range<String.Index>]) -> AttributedString {
        var attributed = AttributedString(text)
        for range in ranges {
            guard let attributedRange = Range(range, in: attributed) else { continue }
            attributed[attributedRange].font = Theme.font(16, weight: .medium)
        }
        return attributed
    }
}

/// One price book item: name and kind on the left, price (and the member price) on the right,
/// a "+" that adds one more each tap with a count of how many are already on this draft.
private struct PriceBookCatalogResultRow: View {
    let result: PriceBookSearchResult
    let quantity: Int?
    let secondaryPrice: String?
    let favorite: Bool
    let toggleFavorite: (() -> Void)?
    let addItem: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    @ViewBuilder var body: some View {
        if typeSize.isAccessibilitySize {
            accessibilityRow
        } else {
            standardRow
        }
    }

    /// Keep the add action reachable even when the item's full description grows
    /// taller than the space between the keyboard and the Done bar.
    @ViewBuilder private var accessibilityRow: some View {
        let item = result.item
        HStack(alignment: .top, spacing: 4) {
            if let toggleFavorite {
                Button(action: toggleFavorite) {
                    Image(systemName: favorite ? "star.fill" : "star")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(favorite ? Theme.foreground : Theme.muted)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(favorite ? "Remove \(item.description) from favourites" : "Add \(item.description) to favourites")
            }
            Button(action: addItem) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(PriceBookResultsList.highlighted(item.description, result.highlights))
                        .font(Theme.font(16)).foregroundStyle(Theme.foreground)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(PriceBookKindFilter(rawValue: item.kind)?.singular ?? item.kind.capitalized) · \(item.unit)")
                        .font(Theme.font(14)).foregroundStyle(Theme.muted)
                    Text(money(item.sellPrice.amount, currency: item.sellPrice.currency))
                        .font(Theme.monoFont(16, weight: .medium)).foregroundStyle(Theme.foreground)
                    if let secondary = secondaryPrice {
                        Text(secondary).font(Theme.font(13)).monospacedDigit().foregroundStyle(Theme.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, toggleFavorite == nil ? 14 : 0)
                .padding(.vertical, 8).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // The compact add button below exposes the same complete information to VoiceOver.
            .accessibilityHidden(true)
            Button(action: addItem) {
                ZStack(alignment: .topTrailing) {
                    PaperCircleLabel(symbol: "plus", size: 36, fill: quantity == nil ? Theme.fill : Theme.brandSurface)
                    if let quantity {
                        Text("\(quantity)")
                            .font(Theme.monoFont(12, weight: .medium)).foregroundStyle(Theme.onInk)
                            .padding(.horizontal, 5).frame(minWidth: 20, minHeight: 20)
                            .background(Theme.ink, in: Capsule()).offset(x: 2, y: -2)
                    }
                }
                .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add \(item.description), \(PriceBookKindFilter(rawValue: item.kind)?.singular ?? item.kind.capitalized), \(item.unit), \(money(item.sellPrice.amount, currency: item.sellPrice.currency))\(secondaryPrice.map { ", \($0)" } ?? "")")
            .accessibilityIdentifier("price-book-item-\(item.id)")
            .accessibilityValue(quantity.map { "\($0) in draft" } ?? "Not added")
            .accessibilityHint("Adds one to the current draft")
            .padding(.trailing, 6).padding(.top, 8)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: quantity ?? 0)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: quantity)
    }

    @ViewBuilder private var standardRow: some View {
        let item = result.item
        HStack(alignment: .center, spacing: 4) {
            if let toggleFavorite {
                Button(action: toggleFavorite) {
                    Image(systemName: favorite ? "star.fill" : "star")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(favorite ? Theme.foreground : Theme.muted)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(favorite ? "Remove \(item.description) from favourites" : "Add \(item.description) to favourites")
            }
            Button(action: addItem) {
                HStack(alignment: .center, spacing: 10) {
                    // Paper 33: the name (16 Medium) over "kind · unit · price" (14 muted), the "+" circle trailing.
                    VStack(alignment: .leading, spacing: 1) {
                        Text(PriceBookResultsList.highlighted(item.description, result.highlights))
                            .font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(PriceBookKindFilter(rawValue: item.kind)?.singular ?? item.kind.capitalized) · \(item.unit) · \(money(item.sellPrice.amount, currency: item.sellPrice.currency))")
                            .font(Theme.font(14)).monospacedDigit().foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        if let secondary = secondaryPrice {
                            Text(secondary).font(Theme.font(13)).monospacedDigit().foregroundStyle(Theme.muted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ZStack(alignment: .topTrailing) {
                        PaperCircleLabel(symbol: "plus", size: 44, fill: quantity == nil ? Theme.fill : Theme.brandSurface)
                        if let quantity {
                            Text("\(quantity)")
                                .font(Theme.monoFont(12, weight: .medium)).foregroundStyle(Theme.onInk)
                                .padding(.horizontal, 5).frame(minWidth: 20, minHeight: 20)
                                .background(Theme.ink, in: Capsule())
                                .offset(x: 2, y: -2)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
                .padding(.leading, toggleFavorite == nil ? 16 : 0).padding(.trailing, 6).padding(.vertical, 8)
                .frame(minHeight: 64).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("price-book-item-\(item.id)")
            .accessibilityValue(quantity.map { "\($0) in draft" } ?? "Not added")
            .accessibilityHint("Adds one to the current draft")
        }
        .sensoryFeedback(.impact(weight: .light), trigger: quantity ?? 0)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: quantity)
    }
}

extension PriceBookKindFilter {
    var singular: String {
        switch self {
        case .all: "Item"
        case .service: "Service"
        case .material: "Material"
        case .labor: "Labor"
        case .assembly: "Assembly"
        }
    }
}

// MARK: - Lines (EB-09..EB-12)

private struct BuilderDocumentLabelKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// The document a builder's lines belong to ("EST-1058", "INV-2209"), for the full editor's
    /// subtitle (Paper TE1). Set by the builder screen; nil when the screen names none.
    var builderDocumentLabel: String? {
        get { self[BuilderDocumentLabelKey.self] }
        set { self[BuilderDocumentLabelKey.self] = newValue }
    }
}

/// One editable line on any builder (estimate, option, invoice). Collapsed it reads like the
/// customer's paper: the full description, quantity × price and the line total. A tap opens it in
/// place with a big stepper, a price field and the description; ••• holds every other action.
struct BuilderLineRow: View {
    @Binding var description: String
    @Binding var quantity: String
    @Binding var unitPrice: String
    let lineID: UUID
    var currency = "USD"
    let lineTotal: Int?
    var unitLabel: String? = nil
    /// A muted line under the details, e.g. "Edited · price book $145.00".
    var note: String? = nil
    var noteAction: (title: String, hint: String, action: () -> Void)? = nil
    let menuItems: [ThorbisMenuItem]
    let expanded: Bool
    let toggle: () -> Void
    let remove: () -> Void
    let focus: FocusState<EstimateBuilderFocus?>.Binding
    var dragPayload: String? = nil
    var descriptionIdentifier: String? = nil
    var quantityIdentifier: String? = nil
    var priceIdentifier: String? = nil
    /// Keep both row actions clear of the keyboard's trailing Done control.
    var lineActionsLeading = false
    /// Paper 35/35A: where the line came from ("Price book", "Custom"), shown before its price.
    /// Without it the row reads "1 × $120.00".
    var sourceLabel: String? = nil

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.builderDocumentLabel) private var documentLabel
    @State private var fullEditor = false

    /// Paper TE1's subtitle: what the line is and the document it is on.
    private var editorSubtitle: String? {
        var parts: [String] = []
        if let sourceLabel { parts.append(sourceLabel == "Custom" ? "Custom item" : "\(sourceLabel) item") }
        if let documentLabel { parts.append(documentLabel) }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    private var removeLineButton: some View {
        Button(role: .destructive, action: remove) {
            Text("Remove").font(Theme.font(14, weight: .semibold)).foregroundStyle(Theme.destructive)
                .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var closeLineButton: some View {
        Button(action: toggle) {
            // Paper 35A: Done on the brand surface.
            Text("Done").paperButton(.secondary, tone: .tinted)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Close line")
        .accessibilityIdentifier("close-line")
    }

    private var quantityValue: Int { Int(quantity.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0 }
    private var stacked: Bool { typeSize.isAccessibilitySize }
    private var name: String { description.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Group {
            if expanded { editor } else { summary }
        }
        .padding(.horizontal, 16)
        .id(lineID)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Remove line", remove)
    }

    // MARK: Collapsed

    /// Paper 35/35A: the name (16 Medium) over where it came from and its price (14 muted; the
    /// line's total "for N" once there is more than one); on the trailing side the quantity pill,
    /// where minus becomes remove at quantity 1 (Paper says so under the card, and the builder
    /// offers Undo). A tap on the words opens the line; its other actions (move, duplicate, reset)
    /// sit behind ••• once open. Paper draws no total column and no ••• on a closed row.
    private var summary: some View {
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                             : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        return layout {
            Button(action: toggle) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(name.isEmpty ? "Describe this item" : name)
                        .font(Theme.font(16, weight: .medium)).tracking(-0.16)
                        .foregroundStyle(name.isEmpty ? Theme.muted : Theme.foreground)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detailText).font(Theme.font(14)).monospacedDigit()
                        .foregroundStyle(priceText == nil ? Theme.warning : Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if let note {
                        Text(note).font(Theme.font(13)).monospacedDigit().foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(summaryLabel)
            .accessibilityHint("Opens quantity, price and description")
            .modifier(OptionalDraggable(payload: dragPayload, title: name))
            quantityPill
                .padding(.bottom, stacked ? 11 : 0)
        }
    }

    /// The row's spoken summary: name, where it came from and price, quantity and line total.
    private var summaryLabel: String {
        [name.isEmpty ? "Describe this item" : name, detailText, note,
         "quantity \(quantityValue)", "total \(totalText)"].compactMap { $0 }.joined(separator: ", ")
    }

    /// Paper 35's quantity pill on the foreground-9% fill: trash (or minus), the count, plus.
    private var quantityPill: some View {
        let atOne = quantityValue <= 1
        return HStack(spacing: 0) {
            Button {
                if atOne { remove() } else { quantity = String(quantityValue - 1) }
            } label: {
                PaperIcon(atOne ? .trash : .stepMinus, size: atOne ? 16 : 14, color: atOne ? Theme.destructive : Theme.foreground)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel(atOne ? "Remove line" : "Decrease quantity")
            if expanded {
                // Open, the count is typed here (250 ft of pipe is not 250 taps).
                TextField("1", text: $quantity, prompt: .placeholder("1"))
                    .keyboardType(.numberPad)
                    .font(Theme.font(15, weight: .semibold)).monospacedDigit()
                    .multilineTextAlignment(.center)
                    .focused(focus, equals: .quantity(lineID))
                    .frame(minWidth: 24, maxWidth: 64, minHeight: 44)
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityLabel("Quantity")
                    .modifier(OptionalIdentifier(identifier: quantityIdentifier))
            } else {
                Text("\(quantityValue)").font(Theme.font(15, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(Theme.foreground)
                    .frame(minWidth: 18)
                    .accessibilityHidden(true)
            }
            Button {
                quantity = String(min(100_000, quantityValue + 1))
            } label: {
                PaperIcon(.stepPlus, size: 14, color: quantityValue < 100_000 && isEnabled ? Theme.foreground : Theme.muted)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .disabled(quantityValue >= 100_000)
            .accessibilityLabel(expanded ? "One more" : "Increase quantity")
            .accessibilityValue("\(quantityValue)")
        }
        .background(Theme.quietFill, in: Capsule())
        .fixedSize()
        .sensoryFeedback(.selection, trigger: quantity)
    }

    private var priceText: String? {
        EstimateRevisionEditorState.parsePrice(unitPrice).map { money($0, currency: currency) }
    }

    private var detailText: String {
        let unit = unitLabel.flatMap { $0.isEmpty ? nil : " \($0)" } ?? ""
        if let sourceLabel {
            guard let priceText else { return "\(sourceLabel) · add a price" }
            // Paper 40: more than one reads as the line's total, "Custom · $180.00 for 2".
            if quantityValue > 1, let lineTotal {
                return "\(sourceLabel) · \(money(lineTotal, currency: currency)) for \(quantityValue)"
            }
            let per = unitLabel.flatMap { $0.isEmpty || $0.lowercased() == "each" ? nil : " per \($0)" } ?? ""
            return "\(sourceLabel) · \(priceText)\(per)"
        }
        guard let priceText else { return "\(quantityValue)\(unit) · add a price" }
        return "\(quantityValue)\(unit) × \(priceText)"
    }

    private var totalText: String { lineTotal.map { money($0, currency: currency) } ?? "—" }

    // MARK: Expanded

    /// Paper 35A's open line: the row stays as it reads closed (name, where it came from and its
    /// price, the quantity pill), and an inline panel on the 6% fill opens under it with the Name
    /// and Price wells side by side, then the row's quiet actions and "Done" on the brand tint.
    private var editor: some View {
        VStack(alignment: .leading, spacing: 0) {
            summary
            VStack(alignment: .leading, spacing: 8) {
                let wells = stacked || typeSize >= .xxLarge ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                                                            : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
                wells {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Name").font(Theme.font(13)).foregroundStyle(Theme.muted).accessibilityHidden(true)
                        HStack(alignment: .top, spacing: 0) {
                            // The customer reads this line in full, so it's edited in full: it grows with the text.
                            TextField("", text: $description, prompt: .placeholder("Run capacitor, 45/5 µF"), axis: .vertical)
                                .font(Theme.font(15, weight: .medium)).lineLimit(1...8)
                                .focused(focus, equals: .description(lineID))
                                .frame(minHeight: 20)
                                .accessibilityLabel("Line description")
                                .modifier(OptionalIdentifier(identifier: descriptionIdentifier))
                            // Paper TE1: long wording opens in the full editor.
                            Button {
                                focus.wrappedValue = nil
                                fullEditor = true
                            } label: {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted)
                                    .frame(width: 44, height: 44).contentShape(Rectangle())
                            }
                            .buttonStyle(PressStyle())
                            .padding(.vertical, -12).padding(.trailing, -12).padding(.leading, -8)
                            .accessibilityLabel("Open full editor")
                            .accessibilityIdentifier("line-description-expand")
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.brand, lineWidth: focus.wrappedValue == .description(lineID) ? 1.5 : 0))
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Price").font(Theme.font(13)).foregroundStyle(Theme.muted).accessibilityHidden(true)
                        HStack(spacing: 1) {
                            Text("$").font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                                .accessibilityHidden(true)
                            TextField("0.00", text: $unitPrice, prompt: .placeholder("0.00"))
                                .keyboardType(.decimalPad)
                                .font(Theme.font(15, weight: .medium)).monospacedDigit()
                                .focused(focus, equals: .price(lineID))
                                .frame(minHeight: 20)
                                .accessibilityLabel(unitLabel.flatMap { $0.isEmpty ? nil : "Price per \($0) in dollars" } ?? "Price each in dollars")
                                .modifier(OptionalIdentifier(identifier: priceIdentifier))
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .frame(width: stacked || typeSize >= .xxLarge ? nil : 104, alignment: .leading)
                    .frame(maxWidth: stacked || typeSize >= .xxLarge ? .infinity : nil, minHeight: 50, alignment: .leading)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.brand, lineWidth: focus.wrappedValue == .price(lineID) ? 1.5 : 0))
                }
                if let note {
                    HStack(spacing: 8) {
                        Text(note).font(Theme.font(13)).monospacedDigit().foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        if let noteAction {
                            Button(noteAction.title, action: noteAction.action)
                                .font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.brandText)
                                .frame(minHeight: 44)
                                .accessibilityHint(noteAction.hint)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                if lineActionsLeading {
                    // Keyboard up: Done leads, with Remove a clear gap away (24 across, 16 when
                    // stacked) so a thumb aiming at Done never lands on the destructive action.
                    let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                                         : AnyLayout(HStackLayout(spacing: 24))
                    layout {
                        closeLineButton
                        removeLineButton
                        menu
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4).padding(.top, 2)
                } else {
                    HStack(spacing: 4) {
                        removeLineButton
                        menu
                        Spacer(minLength: 8)
                        closeLineButton
                    }
                    .padding(.leading, 4).padding(.top, 2)
                }
            }
            .padding(10)
            .background(Theme.foreground.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.bottom, 12)
            #if DEBUG
            .task {
                // `builder-text` (Paper TE1): the open line's wording in the full editor.
                if PaperPreview.enabled, PaperPreview.screen == "builder-text" { fullEditor = true }
            }
            #endif
            .fullScreenCover(isPresented: $fullEditor) {
                LineDescriptionEditor(text: $description, subtitle: editorSubtitle,
                                      totalText: lineTotal == nil ? nil : totalText,
                                      note: note, resetTitle: noteAction?.title, resetHint: noteAction?.hint,
                                      reset: noteAction?.action)
            }
        }
        .onChange(of: focus.wrappedValue) { old, _ in
            // Currency format once the person leaves the price ("12.5" → "12.50").
            if old == .price(lineID), let cents = EstimateRevisionEditorState.parsePrice(unitPrice) {
                let canonical = EstimateRevisionEditorState.priceText(cents)
                if canonical != unitPrice { unitPrice = canonical }
            }
        }
    }

    private var menu: some View {
        ThorbisMenu(items: menuItems,
                    accessibilityLabel: "Actions for \(name.isEmpty ? "line" : name)") {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.muted)
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
    }
}

struct OptionalIdentifier: ViewModifier {
    let identifier: String?
    func body(content: Content) -> some View {
        if let identifier { content.accessibilityIdentifier(identifier) } else { content }
    }
}

private struct OptionalDraggable: ViewModifier {
    let payload: String?
    let title: String
    func body(content: Content) -> some View {
        if let payload {
            content.draggable(payload) {
                Text(title.isEmpty ? "Line" : title)
                    .font(Theme.font(15, weight: .medium)).padding(10)
                    .panelBackground(cornerRadius: Theme.controlRadius)
            }
        } else {
            content
        }
    }
}

/// One estimate's (or one option's) lines: Work first, then Materials (labelled once both
/// exist), each line edited where it sits and arranged with ••• or by dragging.
struct EstimateLineGroupsEditor: View {
    @Binding var lines: [EstimateRevisionLineDraft]
    let disabled: Bool
    let focus: FocusState<EstimateBuilderFocus?>.Binding
    @Binding var expandedLine: UUID?
    /// EB-13: "Show on estimate" on Materials, once the workspace stores it.
    var materialsSwitch = false
    /// Keep Close line and Remove clear of the keyboard's trailing Done and of Save.
    var lineActionsLeading = false
    let removed: (EstimateRevisionLineDraft, Int) -> Void

    var body: some View {
        let labelled = !lines.lines(in: .material).isEmpty
        VStack(alignment: .leading, spacing: 0) {
            ForEach(EstimateLineGroup.allCases) { group in
                let groupLines = lines.lines(in: group)
                if labelled, !groupLines.isEmpty {
                    HStack(alignment: .firstTextBaseline) {
                        Text(group.title).font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                        Spacer(minLength: 8)
                        Text(lines.subtotal(group).map { money($0, currency: "USD") } ?? "—")
                            .font(Theme.monoFont(13, weight: .medium)).foregroundStyle(Theme.muted)
                            .contentTransition(.numericText())
                    }
                    .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    .dropDestination(for: String.self) { ids, _ in drop(ids, before: groupLines.first?.id, group: group) }
                }
                if group == .material && materialsSwitch && !groupLines.isEmpty { materialsVisibility }
                ForEach(groupLines) { line in
                    lineRow(line, groupLines: groupLines)
                        // Paper 35: a hairline between lines of one card.
                        .overlay(alignment: .top) {
                            if line.id != groupLines.first?.id { WellDivider(leading: 16) }
                        }
                        .dropDestination(for: String.self) { ids, _ in drop(ids, before: line.id, group: group) }
                }
            }
        }
        .disabled(disabled)
    }

    private func lineRow(_ line: EstimateRevisionLineDraft, groupLines: [EstimateRevisionLineDraft]) -> some View {
        let binding = binding(line.id)
        let canMoveUp = line.id != groupLines.first?.id
        let canMoveDown = line.id != groupLines.last?.id
        var items: [ThorbisMenuItem] = []
        if canMoveUp { items.append(ThorbisMenuItem("Move up", icon: "arrow.up") { withAnimation(Self.spring) { lines.moveLine(id: line.id, by: -1) } }) }
        if canMoveDown { items.append(ThorbisMenuItem("Move down", icon: "arrow.down") { withAnimation(Self.spring) { lines.moveLine(id: line.id, by: 1) } }) }
        items.append(ThorbisMenuItem("Move to \(line.group.other.title)", icon: line.group == .work ? "shippingbox" : "wrench.and.screwdriver") {
            withAnimation(Self.spring) { lines.setGroup(id: line.id, line.group.other) }
        })
        items.append(ThorbisMenuItem("Duplicate", icon: "plus.square.on.square") { withAnimation(Self.spring) { _ = lines.duplicateLine(id: line.id) } })
        if line.isEditedPriceBookLine {
            items.append(ThorbisMenuItem("Reset to price book", icon: "arrow.uturn.backward") { lines.resetToPriceBook(id: line.id) })
        }
        items.append(ThorbisMenuItem("Remove line", icon: "trash", role: .destructive) { remove(line.id) })
        var note: String?
        if line.isEditedPriceBookLine, let original = line.priceBookOriginal {
            note = "Edited · price book \(EstimateRevisionEditorState.parsePrice(original.unitPrice).map { money($0, currency: "USD") } ?? original.unitPrice)"
        } else if (EstimateRevisionEditorState.parsePrice(line.unitPrice) ?? 0) < 0 {
            note = "Credit"
        }
        return BuilderLineRow(
            description: binding.description, quantity: binding.quantity, unitPrice: binding.unitPrice,
            lineID: line.id, lineTotal: line.lineTotal, note: note,
            noteAction: line.isEditedPriceBookLine ? (title: "Reset", hint: "Puts back the price book wording and price",
                                                      action: { lines.resetToPriceBook(id: line.id) }) : nil,
            menuItems: items, expanded: expandedLine == line.id,
            toggle: { withAnimation(Self.spring) { expandedLine = expandedLine == line.id ? nil : line.id } },
            remove: { remove(line.id) }, focus: focus, dragPayload: line.id.uuidString,
            descriptionIdentifier: "line-description",
            lineActionsLeading: lineActionsLeading,
            sourceLabel: Self.sourceLabel(line)
        )
        .accessibilityAction(named: "Move up") { if canMoveUp { withAnimation(Self.spring) { lines.moveLine(id: line.id, by: -1) } } }
        .accessibilityAction(named: "Move down") { if canMoveDown { withAnimation(Self.spring) { lines.moveLine(id: line.id, by: 1) } } }
    }

    private func remove(_ id: UUID) {
        guard let removedLine = withAnimation(Self.spring, { lines.removeLine(id: id) }) else { return }
        if expandedLine == id { expandedLine = nil }
        removed(removedLine.line, removedLine.index)
    }

    /// EB-13: on by default; off, the customer sees one "Materials" line with the same sum.
    private var materialsVisibility: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(isOn: Binding(get: { lines.showsMaterials },
                                 set: { shown in withAnimation(Self.spring) { lines.setShowsMaterials(shown) } })) {
                Text("Show on estimate").font(Theme.font(15)).foregroundStyle(Theme.foreground)
            }
            .tint(Theme.brand)
            .frame(minHeight: 44)
            if !lines.showsMaterials {
                Text("The customer sees one Materials line\(lines.subtotal(.material).map { " · " + money($0, currency: "USD") } ?? "").")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 4)
    }

    static let spring = Animation.spring(response: 0.3, dampingFraction: 1)

    /// Paper 35: "Price book" for a line picked from the price book, "Custom" for one typed here.
    static func sourceLabel(_ line: EstimateRevisionLineDraft) -> String {
        if case .priceBookSelection(_, _)? = line.source { return "Price book" }
        return "Custom"
    }

    private func drop(_ ids: [String], before target: UUID?, group: EstimateLineGroup) -> Bool {
        guard let raw = ids.first, let id = UUID(uuidString: raw), lines.contains(where: { $0.id == id }) else { return false }
        withAnimation(Self.spring) { lines.moveLine(id: id, before: target, group: group) }
        return true
    }

    /// A binding by identity, so a row never writes through a stale index after a move or delete.
    private func binding(_ id: UUID) -> Binding<EstimateRevisionLineDraft> {
        Binding(
            get: { lines.first { $0.id == id } ?? EstimateRevisionLineDraft(id: id, description: "", quantity: "1", unitPrice: "") },
            set: { value in if let index = lines.firstIndex(where: { $0.id == id }) { lines[index] = value } }
        )
    }
}

// MARK: - Sections

/// One section of the builder: its label ("Option 1 · Repair") above one panel that holds the
/// option's own fields, its lines, "Add item", the section total and, where the account may,
/// "Add discount" under that total.
struct EstimateBuilderSection<Header: View>: View {
    let label: String
    var caption: String? = nil
    @Binding var lines: [EstimateRevisionLineDraft]
    let disabled: Bool
    let focus: FocusState<EstimateBuilderFocus?>.Binding
    @Binding var expandedLine: UUID?
    var totalLabel = "Total"
    var showTotal = true
    var memberPricing: MemberPricing? = nil
    var materialsSwitch = false
    var lineActionsLeading = false
    var menuItems: [ThorbisMenuItem] = []
    let addItem: () -> Void
    var addDiscount: (() -> Void)? = nil
    let removed: (EstimateRevisionLineDraft, Int) -> Void
    /// Paper 35: "Add item" is its own field above the label and the lines card, with this note
    /// on its trailing side ("Price book or custom"). Off, it is the last row inside the card.
    var addItemAbove = false
    var addItemNote: String? = nil
    /// Paper 30/32: "Scan or paste materials" under the add field; nil leaves it out.
    var addMaterials: (() -> Void)? = nil
    @ViewBuilder var header: Header

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var headingAddItem: some View {
        Button(action: addItem) {
            // The heading's own ink and size, like the menu beside it; the tap target stays 44.
            Label("Add item", systemImage: "plus")
                .font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(disabled || lines.count >= [EstimateRevisionLineDraft].maximumLines)
        .accessibilityValue(label)
        .accessibilityHint("Opens the price book")
        .accessibilityIdentifier("estimate-add-item-heading")
    }

    var body: some View {
        if addItemAbove {
            VStack(alignment: .leading, spacing: 10) {
                addItemField
                if let addMaterials {
                    Button(action: addMaterials) {
                        HStack(spacing: 6) {
                            Image(systemName: "barcode.viewfinder").font(.system(size: 15, weight: .medium))
                            Text("Scan or paste materials").font(Theme.font(14, weight: .semibold))
                        }
                        .foregroundStyle(Theme.brandText)
                        .frame(minHeight: 44).padding(.horizontal, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .disabled(disabled || lines.count >= [EstimateRevisionLineDraft].maximumLines)
                    .accessibilityIdentifier("estimate-add-materials")
                }
                if !lines.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(label).font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 0)
                        Text("\(lines.count) item\(lines.count == 1 ? "" : "s")").font(Theme.font(13)).monospacedDigit()
                            .foregroundStyle(Theme.muted)
                        if !menuItems.isEmpty {
                            ThorbisMenu(items: menuItems, title: label, accessibilityLabel: "Actions for \(label)") {
                                Image(systemName: "ellipsis").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.muted)
                                    .frame(width: 44, height: 32).contentShape(Rectangle())
                            }
                            .disabled(disabled)
                        }
                    }
                    .padding(.horizontal, 4)
                    if let caption {
                        Text(caption).font(Theme.font(13)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }
                    PaperCard {
                        VStack(alignment: .leading, spacing: 0) {
                            header
                            EstimateLineGroupsEditor(lines: $lines, disabled: disabled, focus: focus,
                                                     expandedLine: $expandedLine, materialsSwitch: materialsSwitch,
                                                     lineActionsLeading: lineActionsLeading, removed: removed)
                            sectionTotal
                            discountRow
                        }
                    }
                }
            }
        } else {
            stackedSection
        }
    }

    /// Paper 35's add field: a 48-tall card (radius 14), the brand plus, "Add item" and the note.
    private var addItemField: some View {
        Button(action: addItem) {
            HStack(spacing: 8) {
                PaperIcon(.plusLight, size: 18, color: Theme.brandText)
                Text("Add item").font(Theme.font(16)).foregroundStyle(Theme.muted)
                Spacer(minLength: 8)
                if let addItemNote {
                    Text(addItemNote).font(Theme.font(13)).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            .padding(.horizontal, 12).frame(minHeight: 48)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .disabled(disabled || lines.count >= [EstimateRevisionLineDraft].maximumLines)
        .accessibilityLabel("Add item")
        .accessibilityValue(label)
        .accessibilityHint("Opens the price book")
        .accessibilityIdentifier("estimate-add-item")
    }

    @ViewBuilder private var sectionTotal: some View {
        if showTotal, !lines.isEmpty {
            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(totalLabel).font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.muted)
                    Spacer(minLength: 8)
                    Text(lines.subtotal().map { money($0, currency: "USD") } ?? "—")
                        .font(Theme.monoFont(20, weight: .medium)).foregroundStyle(Theme.foreground)
                        .contentTransition(.numericText())
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                if let member = lines.memberTotal(memberPricing), let memberPricing {
                    Text("Member \(money(member, currency: "USD")) · \(memberPricing.discountPercent)% off")
                        .font(Theme.font(14)).monospacedDigit().foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Theme.fill.opacity(0.45))
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private var discountRow: some View {
        if let addDiscount, !lines.isEmpty {
            Button(action: addDiscount) {
                HStack(spacing: 10) {
                    Image(systemName: "tag").font(.system(size: 15, weight: .medium))
                    Text("Add discount").font(Theme.font(15, weight: .medium))
                    Spacer(minLength: 0)
                    Text("$ or %").font(Theme.font(14)).foregroundStyle(Theme.muted)
                }
                .foregroundStyle(Theme.foreground)
                .padding(.horizontal, 16).frame(minHeight: 48).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(disabled)
            .accessibilityHint("Adds a credit line with a fixed amount")
        }
    }

    /// The label (and its ••• menu) above one card holding the fields, lines, Add item, the total
    /// and Add discount: an option package in the revision editor.
    private var stackedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(label).font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                    .accessibilityAddTraits(.isHeader)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                // 44 to tap, 32 in the row, so the heading keeps Paper's height.
                if lines.count > 3 && !dynamicTypeSize.isAccessibilitySize { headingAddItem.padding(.vertical, -6) }
                if !menuItems.isEmpty {
                    ThorbisMenu(items: menuItems, title: label, accessibilityLabel: "Actions for \(label)") {
                        Image(systemName: "ellipsis").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.muted)
                            .frame(width: 44, height: 32).contentShape(Rectangle())
                    }
                    .disabled(disabled)
                }
            }
            // Flush with the card and the fields above it, so every left edge on the sheet lines up.
            .frame(minHeight: 32)
            .padding(.horizontal, 4)
            if lines.count > 3 && dynamicTypeSize.isAccessibilitySize { headingAddItem }
            if let caption {
                Text(caption).font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4).padding(.bottom, 2)
            }
            PaperCard {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    EstimateLineGroupsEditor(lines: $lines, disabled: disabled, focus: focus,
                                             expandedLine: $expandedLine, materialsSwitch: materialsSwitch,
                                             lineActionsLeading: lineActionsLeading, removed: removed)
                    Button(action: addItem) {
                        HStack(spacing: 10) {
                            Image(systemName: "plus").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.brandText)
                            Text("Add item").font(Theme.font(16, weight: .medium))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(Theme.foreground)
                        .padding(.horizontal, 16).frame(minHeight: 52).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(disabled || lines.count >= [EstimateRevisionLineDraft].maximumLines)
                    .accessibilityValue(label)
                    .accessibilityHint("Opens the price book")
                    .accessibilityIdentifier("estimate-add-item")
                    sectionTotal
                    discountRow
                }
            }
        }
    }
}

extension EstimateBuilderSection where Header == EmptyView {
    init(label: String, caption: String? = nil, lines: Binding<[EstimateRevisionLineDraft]>, disabled: Bool,
         focus: FocusState<EstimateBuilderFocus?>.Binding, expandedLine: Binding<UUID?>, totalLabel: String = "Total",
         showTotal: Bool = true, memberPricing: MemberPricing? = nil, materialsSwitch: Bool = false,
         lineActionsLeading: Bool = false, menuItems: [ThorbisMenuItem] = [],
         addItem: @escaping () -> Void, addDiscount: (() -> Void)? = nil,
         removed: @escaping (EstimateRevisionLineDraft, Int) -> Void,
         addItemAbove: Bool = false, addItemNote: String? = nil, addMaterials: (() -> Void)? = nil) {
        self.init(label: label, caption: caption, lines: lines, disabled: disabled, focus: focus, expandedLine: expandedLine,
                  totalLabel: totalLabel, showTotal: showTotal, memberPricing: memberPricing,
                  materialsSwitch: materialsSwitch, lineActionsLeading: lineActionsLeading, menuItems: menuItems,
                  addItem: addItem, addDiscount: addDiscount, removed: removed,
                  addItemAbove: addItemAbove, addItemNote: addItemNote, addMaterials: addMaterials) { EmptyView() }
    }
}

// MARK: - Member pricing

extension MemberPricing {
    /// "Member $123.00" beside a price book result, as the invoice editor shows it. Informational:
    /// the line keeps the price book price; the server owns what a member is charged.
    func secondaryPriceText(_ item: PriceBookListItem) -> String? {
        guard isMember, discountPercent > 0 else { return nil }
        return "Member \(money(memberPrice(item.sellPrice.amount), currency: item.sellPrice.currency))"
    }
}

// MARK: - Undo (EB-12)

struct RemovedLine: Equatable {
    let line: EstimateRevisionLineDraft
    let index: Int
    /// nil for the estimate's own lines, otherwise the option package it came from.
    let optionID: String?
}

/// "Line removed · Undo" for five seconds, above the commit, as a `ThorbisToast`.
struct LineRemovedToast: View {
    let removed: RemovedLine
    let undo: () -> Void
    let expire: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ThorbisToast(symbol: "trash", message: String(localized: "Line removed"),
                     actionTitle: String(localized: "Undo"), action: undo)
        .padding(.horizontal, Theme.gutter).padding(.bottom, 8)
        .transition(ThorbisToast.transition(reduceMotion: reduceMotion))
        .task(id: removed.line.id) {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            expire()
        }
        .accessibilityAction(named: "Undo", undo)
    }
}

/// The running total pinned above the commit (MF-04, EB-14), with the member price under it.
struct EstimateBuilderTotal: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    var label = "Total"
    let value: String
    var detail: String? = nil

    init(label: String = "Total", total: Int?, detail: String? = nil) {
        self.label = label
        value = total.map { money($0, currency: "USD") } ?? "—"
        self.detail = detail
    }

    init(label: String, value: String, detail: String? = nil) {
        self.label = label
        self.value = value
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(label).font(Theme.font(17, weight: .medium)).foregroundStyle(Theme.muted)
                    ForEach(Array(value.components(separatedBy: "–").enumerated()), id: \.offset) { index, part in
                        let text = index == 0 ? part : "– " + part
                        ViewThatFits(in: .horizontal) {
                            Text(text).font(Theme.monoFont(24, weight: .medium)).fixedSize()
                            Text(text).font(.system(size: 24, weight: .medium, design: .monospaced)).fixedSize()
                            Text(text).font(Theme.monoFont(24, weight: .medium))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundStyle(Theme.foreground)
                        .accessibilityIdentifier("estimate-total-value-\(index)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(Theme.font(17, weight: .medium)).foregroundStyle(Theme.muted)
                Spacer(minLength: 12)
                Text(value)
                    .font(Theme.monoFont(value.contains("–") ? 24 : 34, weight: .medium))
                    .foregroundStyle(Theme.foreground)
                    .contentTransition(.numericText())
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            }
            if let detail {
                Text(detail).font(Theme.font(14)).monospacedDigit().foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.horizontal, Theme.gutter).padding(.top, 10)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .background(Theme.canvas)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Discount (credit line)

/// "Add discount": an amount or a percent of the section, written as one fixed credit line.
struct EstimateDiscountSheet: View {
    let target: String
    let subtotal: Int?
    let apply: (_ description: String, _ cents: Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var percent = false
    @State private var text = ""
    @State private var reason = ""
    @State private var problem: String?
    @FocusState private var focused: Bool

    private var cents: Int? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if percent {
            guard let rate = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")),
                  rate > 0, rate <= 100, let subtotal, subtotal > 0 else { return nil }
            let amount = NSDecimalNumber(decimal: Decimal(subtotal) * rate / 100)
                .rounding(accordingToBehavior: NSDecimalNumberHandler(roundingMode: .plain, scale: 0, raiseOnExactness: false,
                                                                      raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false))
            return amount.intValue > 0 ? amount.intValue : nil
        }
        guard let amount = MoneyInput.cents(value), amount > 0 else { return nil }
        if let subtotal, amount > subtotal { return nil }
        return amount
    }

    private var label: String {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return percent ? "Discount · \(value)%" : "Discount"
    }

    /// The credit line's wording: the label, then the reason when one was typed ("Discount — Loyalty").
    private var creditDescription: String {
        let why = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return why.isEmpty ? label : "\(label) \u{2014} \(why)"
    }

    var body: some View {
        // Paper 40D: "Discount or credit", its Type, the amount off, then the new total.
        ThorbisSheetScaffold(title: "Discount or credit", onClose: { dismiss() }, detents: [.medium, .large]) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Type").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, 4)
                    .accessibilityHidden(true)
                ThorbisSegmented(options: [(true, "Percent"), (false, "Amount")], selection: $percent)
            }
            // Paper 40D: "Amount off" over the field; the affix sits inside the sunk well and the
            // problem shows under it after Add is pressed.
            FormField(label: percent ? "Percent off" : "Amount off",
                      help: "Goes on \(target) as a credit line the customer sees. It's a fixed amount: it won't change if you change the items later.",
                      error: problem) {
                HStack(spacing: 6) {
                    if !percent { Text("$").font(Theme.monoFont(22)).foregroundStyle(Theme.muted) }
                    TextField(percent ? "10" : "0.00", text: $text, prompt: .placeholder(percent ? "10" : "0.00"))
                        .keyboardType(.decimalPad)
                        .font(Theme.monoFont(22, weight: .medium))
                        .focused($focused)
                        .accessibilityLabel(percent ? "Discount percent" : "Discount amount in dollars")
                    if percent { Text("%").font(Theme.monoFont(22)).foregroundStyle(Theme.muted) }
                }
                .fieldWell()
                .onChange(of: text) { _, _ in problem = nil }
            }
            // Paper 40D: the reason the customer reads, as the invoice discount writes it.
            FormField(label: "Reason \u{00B7} shown to customer", optional: true,
                      help: "Shown as \u{201C}\(creditDescription)\u{201D}.") {
                TextField("", text: $reason, prompt: .placeholder("Loyalty"))
                    .font(Theme.font(16))
                    .textInputAutocapitalization(.sentences)
                    .accessibilityLabel("Reason")
                    .fieldWell()
                    .onChange(of: reason) { _, value in
                        if value.count > 80 { reason = String(value.prefix(80)) }
                    }
            }
            if let subtotal, let off = cents {
                newTotalCard(subtotal: subtotal, off: off)
            }
            Button {
                guard let cents else {
                    problem = percent ? "Enter a percent from 1 to 100, like 10." : "Enter an amount up to the subtotal, like 25.00."
                    return
                }
                apply(creditDescription, cents)
                dismiss()
            } label: {
                Text(cents.map { "Add \(label.lowercased()) · −\(money($0, currency: "USD"))" } ?? "Add")
                    .inkCommit()
            }
            .buttonStyle(PressStyle())
        }
        .onChange(of: percent) { _, _ in text = "" }
        .task { focused = true }
    }

    /// Paper 40D: what the section comes to with this discount, and what it was.
    private func newTotalCard(subtotal: Int, off: Int) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text("New total").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.success)
                Text("Was \(money(subtotal, currency: "USD"))").font(Theme.font(14)).monospacedDigit()
                    .foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(money(subtotal - off, currency: "USD"))
                .font(Theme.font(24, weight: .bold)).monospacedDigit().tracking(-0.4)
                .foregroundStyle(Theme.foreground)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Theme.successSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

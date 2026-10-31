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
        insert(line, at: insertionIndex(for: line.group))
        return line.id
    }

    /// EB-07: what was typed becomes a line; the price is left for the person to enter.
    @discardableResult
    mutating func addCustomLine(_ description: String = "", to group: EstimateLineGroup) -> UUID? {
        guard count < Self.maximumLines else { return nil }
        let trimmed = String(description.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        let line = EstimateRevisionLineDraft(description: trimmed, quantity: "1", unitPrice: "", source: .manual, group: group)
        insert(line, at: insertionIndex(for: group))
        return line.id
    }

    @discardableResult
    mutating func duplicateLine(id: UUID) -> UUID? {
        guard count < Self.maximumLines, let index = firstIndex(where: { $0.id == id }) else { return nil }
        let line = self[index]
        let copy = EstimateRevisionLineDraft(description: line.description, quantity: line.quantity,
                                             unitPrice: line.unitPrice, source: line.source, group: line.group,
                                             priceBookOriginal: line.priceBookOriginal)
        insert(copy, at: index + 1)
        return copy.id
    }

    /// Removes a line and returns it with its position, so Undo can put it back (EB-12).
    mutating func removeLine(id: UUID) -> (line: EstimateRevisionLineDraft, index: Int)? {
        guard let index = firstIndex(where: { $0.id == id }) else { return nil }
        return (remove(at: index), index)
    }

    mutating func restoreLine(_ line: EstimateRevisionLineDraft, at index: Int) {
        guard count < Self.maximumLines, !contains(where: { $0.id == line.id }) else { return }
        insert(line, at: Swift.min(Swift.max(0, index), count))
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
        var line = remove(at: index)
        line.group = group
        line.groupSettled = true
        if let target, let targetIndex = firstIndex(where: { $0.id == target }), self[targetIndex].group == group {
            insert(line, at: targetIndex)
        } else {
            insert(line, at: insertionIndex(for: group))
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

extension EstimateRevisionLineDraft {
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
        let line = EstimateRevisionLineDraft(description: String(description.prefix(200)), quantity: "1",
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
                  let quantity = Int(line.quantity.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
            sum += quantity * (cents > 0 ? pricing.memberPrice(cents) : cents)
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
    @State private var usageSnapshot: [String: PriceBookUsage] = [:]
    @State private var rankingTime = Date()

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        let current = catalog.context == context
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
                            Text(trimmedQuery.isEmpty ? "Add a custom item" : "Add \u{201C}\(trimmedQuery)\u{201D} as a custom item")
                                .font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10).frame(minHeight: 56).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("price-book-add-custom")
                }
            }
            if canUsePriceBook, !current || catalog.items.isEmpty {
                if !current || catalog.loading {
                    PaperCard { ForEach(0..<6, id: \.self) { _ in skeletonRow } }
                } else if let error = catalog.error {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("The price book didn't load. \(error)").font(Theme.font(15)).foregroundStyle(Theme.foreground)
                        Button("Try again", action: retry).font(Theme.font(15, weight: .medium)).frame(minHeight: 44)
                    }
                }
            }
            if canUsePriceBook, current, !catalog.items.isEmpty, let error = catalog.error {
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
                            ? "\(page.offset + 1)–\(page.offset + page.results.count) of \(page.total)" : nil) {
                    if page.offset > 0 {
                        pageButton("Previous items", detail: nil, identifier: "price-book-previous") {
                            pageOffset = max(0, page.offset - PriceBookSearchIndex.resultLimit)
                        }
                    }
                    ForEach(page.results, content: row)
                    if remaining > 0 {
                        pageButton("Next items", detail: "\(remaining) remaining", identifier: "price-book-show-more") {
                            pageOffset = page.offset + PriceBookSearchIndex.resultLimit
                        }
                    }
                }
            }
            if canUsePriceBook, current, !catalog.loading, catalog.error == nil,
               page.results.isEmpty, recent.isEmpty, favorites.isEmpty {
                if addCustomLine == nil {
                    ContentUnavailableView(
                        catalog.items.isEmpty ? "No active Price Book items" : "No matching items",
                        systemImage: "book.closed",
                        description: Text(catalog.items.isEmpty
                            ? "Add items to your Price Book to use them here."
                            : "Try another search or choose a different category."))
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
        .padding(.horizontal, Theme.gutter).padding(.bottom, 24)
        .onAppear { resetPage() }
        .onChange(of: query) { _, _ in resetPage() }
        .onChange(of: kind) { _, _ in resetPage() }
        .onChange(of: context) { _, _ in resetPage() }
        .onChange(of: catalog.context) { _, newContext in
            if newContext == context { resetPage() }
        }
    }

    private func resetPage() {
        pageOffset = 0
        usageSnapshot = catalog.usage
        rankingTime = Date()
    }

    private func section<Content: View>(_ title: String?, trailing: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                HStack {
                    Text(title).font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
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

    var body: some View {
        let item = result.item
        let stacked = typeSize.isAccessibilitySize
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
                    let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                                         : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 10))
                    layout {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(PriceBookResultsList.highlighted(item.description, result.highlights))
                                .font(Theme.font(16)).foregroundStyle(Theme.foreground)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(PriceBookKindFilter(rawValue: item.kind)?.singular ?? item.kind.capitalized) · \(item.unit)")
                                .font(Theme.font(14)).foregroundStyle(Theme.muted)
                        }
                        if !stacked { Spacer(minLength: 8) }
                        VStack(alignment: stacked ? .leading : .trailing, spacing: 3) {
                            Text(money(item.sellPrice.amount, currency: item.sellPrice.currency))
                                .font(Theme.monoFont(16, weight: .medium)).foregroundStyle(Theme.foreground)
                                .lineLimit(1).minimumScaleFactor(0.7)
                            if let secondary = secondaryPrice {
                                Text(secondary).font(Theme.font(13)).monospacedDigit().foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ZStack(alignment: .topTrailing) {
                        PaperCircleLabel(symbol: "plus", size: 36, fill: quantity == nil ? Theme.fill : Theme.brandSurface)
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
                .padding(.leading, toggleFavorite == nil ? 14 : 0).padding(.trailing, 6).padding(.vertical, 8)
                .frame(minHeight: 60).contentShape(Rectangle())
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

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.dynamicTypeSize) private var typeSize

    private var quantityValue: Int { Int(quantity.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0 }
    private var stacked: Bool { typeSize.isAccessibilitySize }
    private var name: String { description.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Group {
            if expanded { editor } else { summary }
        }
        .padding(.horizontal, 14)
        .id(lineID)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Remove line", remove)
    }

    // MARK: Collapsed

    private var summary: some View {
        HStack(alignment: .top, spacing: 0) {
            Button(action: toggle) {
                let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                                     : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 10))
                layout {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name.isEmpty ? "Describe this item" : name)
                            .font(Theme.font(16, weight: .medium))
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
                    if !stacked { Spacer(minLength: 8) }
                    Text(totalText)
                        .font(Theme.monoFont(16, weight: .medium)).foregroundStyle(Theme.foreground)
                        .contentTransition(.numericText())
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .fixedSize(horizontal: !stacked, vertical: false)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens quantity, price and description")
            .modifier(OptionalDraggable(payload: dragPayload, title: name))
            menu.padding(.trailing, -10)
        }
    }

    private var priceText: String? {
        EstimateRevisionEditorState.parsePrice(unitPrice).map { money($0, currency: currency) }
    }

    private var detailText: String {
        let unit = unitLabel.flatMap { $0.isEmpty ? nil : " \($0)" } ?? ""
        guard let priceText else { return "\(quantityValue)\(unit) · add a price" }
        return "\(quantityValue)\(unit) × \(priceText)"
    }

    private var totalText: String { lineTotal.map { money($0, currency: currency) } ?? "—" }

    // MARK: Expanded

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 0) {
                // The customer reads this line in full, so it's edited in full: it grows with the text.
                TextField("", text: $description, prompt: Text("Run capacitor, 45/5 µF").foregroundStyle(Theme.subtle), axis: .vertical)
                    .font(Theme.font(16, weight: .medium)).lineLimit(1...8)
                    .focused(focus, equals: .description(lineID))
                    .padding(.horizontal, 12).padding(.vertical, 12)
                    .frame(minHeight: 48)
                    .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                    .accessibilityLabel("Line description")
                    .modifier(OptionalIdentifier(identifier: descriptionIdentifier))
                menu.padding(.trailing, -10)
            }
            let layout = stacked || typeSize >= .xxLarge ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                                                         : AnyLayout(HStackLayout(spacing: 10))
            layout {
                HStack(spacing: 6) {
                    stepButton("minus", label: "One fewer", enabled: quantityValue > 1) { quantity = String(max(1, quantityValue - 1)) }
                    TextField("1", text: $quantity)
                        .keyboardType(.numberPad)
                        .font(Theme.monoFont(17, weight: .medium))
                        .multilineTextAlignment(.center)
                        .focused(focus, equals: .quantity(lineID))
                        .frame(width: 58, height: 52)
                        .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                        .accessibilityLabel("Quantity")
                        .modifier(OptionalIdentifier(identifier: quantityIdentifier))
                    stepButton("plus", label: "One more", enabled: quantityValue < 100_000) { quantity = String(min(100_000, quantityValue + 1)) }
                }
                HStack(spacing: 4) {
                    Text("$").font(Theme.monoFont(17)).foregroundStyle(Theme.muted)
                    TextField("0.00", text: $unitPrice)
                        .keyboardType(.decimalPad)
                        .font(Theme.monoFont(17, weight: .medium))
                        .multilineTextAlignment(.trailing)
                        .focused(focus, equals: .price(lineID))
                        .accessibilityLabel(unitLabel.flatMap { $0.isEmpty ? nil : "Price per \($0) in dollars" } ?? "Price each in dollars")
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            }
            HStack(alignment: .firstTextBaseline) {
                Text(unitLabel.flatMap { $0.isEmpty ? nil : "Line total · per \($0)" } ?? "Line total")
                    .font(Theme.font(14)).foregroundStyle(Theme.muted)
                Spacer(minLength: 8)
                Text(totalText).font(Theme.monoFont(17, weight: .medium))
                    .contentTransition(.numericText())
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            if let note {
                HStack(spacing: 8) {
                    Text(note).font(Theme.font(14)).monospacedDigit().foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if let noteAction {
                        Button(noteAction.title, action: noteAction.action)
                            .font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.foreground)
                            .frame(minHeight: 44)
                            .accessibilityHint(noteAction.hint)
                    }
                }
            }
            HStack {
                Button(role: .destructive, action: remove) {
                    Text("Remove").font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.destructive)
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                Button(action: toggle) {
                    Text("Done").font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                        .padding(.horizontal, 16).frame(minHeight: 44)
                        .background(Theme.fill, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Close line")
            }
        }
        .padding(.vertical, 12)
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

    private func stepButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 18, weight: .medium))
                .foregroundStyle(enabled && isEnabled ? Theme.foreground : Theme.muted)
                .frame(width: 52, height: 52)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .accessibilityLabel(label)
        .sensoryFeedback(.selection, trigger: quantity)
    }
}

private struct OptionalIdentifier: ViewModifier {
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
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
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
                    .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    .dropDestination(for: String.self) { ids, _ in drop(ids, before: groupLines.first?.id, group: group) }
                }
                ForEach(groupLines) { line in
                    lineRow(line, groupLines: groupLines)
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
            remove: { remove(line.id) }, focus: focus, dragPayload: line.id.uuidString
        )
        .accessibilityAction(named: "Move up") { if canMoveUp { withAnimation(Self.spring) { lines.moveLine(id: line.id, by: -1) } } }
        .accessibilityAction(named: "Move down") { if canMoveDown { withAnimation(Self.spring) { lines.moveLine(id: line.id, by: 1) } } }
    }

    private func remove(_ id: UUID) {
        guard let removedLine = withAnimation(Self.spring, { lines.removeLine(id: id) }) else { return }
        if expandedLine == id { expandedLine = nil }
        removed(removedLine.line, removedLine.index)
    }

    static let spring = Animation.spring(response: 0.3, dampingFraction: 1)

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
    var menuItems: [ThorbisMenuItem] = []
    let addItem: () -> Void
    var addDiscount: (() -> Void)? = nil
    let removed: (EstimateRevisionLineDraft, Int) -> Void
    @ViewBuilder var header: Header

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Text(label).font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                    .accessibilityAddTraits(.isHeader)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if !menuItems.isEmpty {
                    ThorbisMenu(items: menuItems, title: label, accessibilityLabel: "Actions for \(label)") {
                        Image(systemName: "ellipsis").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.muted)
                            .frame(width: 44, height: 32).contentShape(Rectangle())
                    }
                    .disabled(disabled)
                }
            }
            .padding(.horizontal, 4)
            .frame(minHeight: 32)
            if let caption {
                Text(caption).font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4).padding(.bottom, 2)
            }
            PaperCard {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    EstimateLineGroupsEditor(lines: $lines, disabled: disabled, focus: focus,
                                             expandedLine: $expandedLine, removed: removed)
                    Button(action: addItem) {
                        HStack(spacing: 10) {
                            Image(systemName: "plus").font(.system(size: 15, weight: .medium))
                            Text("Add item").font(Theme.font(16, weight: .medium))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(Theme.foreground)
                        .padding(.horizontal, 14).frame(minHeight: 52).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(disabled || lines.count >= [EstimateRevisionLineDraft].maximumLines)
                    .accessibilityHint("Opens the price book")
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
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(Theme.fill.opacity(0.45))
                        .accessibilityElement(children: .combine)
                    }
                    if let addDiscount, !lines.isEmpty {
                        Button(action: addDiscount) {
                            HStack(spacing: 10) {
                                Image(systemName: "tag").font(.system(size: 15, weight: .medium))
                                Text("Add discount").font(Theme.font(15, weight: .medium))
                                Spacer(minLength: 0)
                                Text("$ or %").font(Theme.font(14)).foregroundStyle(Theme.muted)
                            }
                            .foregroundStyle(Theme.foreground)
                            .padding(.horizontal, 14).frame(minHeight: 48).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(disabled)
                        .accessibilityHint("Adds a credit line with a fixed amount")
                    }
                }
            }
        }
    }
}

extension EstimateBuilderSection where Header == EmptyView {
    init(label: String, caption: String? = nil, lines: Binding<[EstimateRevisionLineDraft]>, disabled: Bool,
         focus: FocusState<EstimateBuilderFocus?>.Binding, expandedLine: Binding<UUID?>, totalLabel: String = "Total",
         showTotal: Bool = true, memberPricing: MemberPricing? = nil, menuItems: [ThorbisMenuItem] = [],
         addItem: @escaping () -> Void, addDiscount: (() -> Void)? = nil,
         removed: @escaping (EstimateRevisionLineDraft, Int) -> Void) {
        self.init(label: label, caption: caption, lines: lines, disabled: disabled, focus: focus, expandedLine: expandedLine,
                  totalLabel: totalLabel, showTotal: showTotal, memberPricing: memberPricing, menuItems: menuItems,
                  addItem: addItem, addDiscount: addDiscount, removed: removed) { EmptyView() }
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
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(Theme.font(17, weight: .medium)).foregroundStyle(Theme.muted)
                Spacer(minLength: 12)
                Text(value)
                    .font(Theme.monoFont(value.contains("–") ? 24 : 34, weight: .medium))
                    .foregroundStyle(Theme.foreground)
                    .contentTransition(.numericText())
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            if let detail {
                Text(detail).font(Theme.font(14)).monospacedDigit().foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.horizontal, Theme.gutter).padding(.top, 10)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .background(Theme.background)
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

    var body: some View {
        ThorbisSheetScaffold(title: "Add discount", onClose: { dismiss() }, detents: [.medium, .large]) {
            Text("Goes on \(target) as a credit line the customer sees. It's a fixed amount: it won't change if you change the items later.")
                .font(Theme.font(15)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            ThorbisSegmented(options: [(false, "Amount ($)"), (true, "Percent (%)")], selection: $percent)
            // v2: the affix sits inside the sunk well; the problem shows under it after Add is pressed.
            HStack(spacing: 6) {
                if !percent { Text("$").font(Theme.monoFont(22)).foregroundStyle(Theme.muted) }
                TextField(percent ? "10" : "0.00", text: $text)
                    .keyboardType(.decimalPad)
                    .font(Theme.monoFont(22, weight: .medium))
                    .focused($focused)
                    .accessibilityLabel(percent ? "Discount percent" : "Discount amount in dollars")
                if percent { Text("%").font(Theme.monoFont(22)).foregroundStyle(Theme.muted) }
            }
            .fieldWell()
            .onChange(of: text) { _, _ in problem = nil }
            if let problem {
                FieldProblem(message: problem)
            } else if let subtotal {
                Text("Before discount \(money(subtotal, currency: "USD"))")
                    .font(Theme.font(14)).monospacedDigit().foregroundStyle(Theme.muted)
            }
            Button {
                guard let cents else {
                    problem = percent ? "Enter a percent from 1 to 100, like 10." : "Enter an amount up to the subtotal, like 25.00."
                    return
                }
                apply(label, cents)
                dismiss()
            } label: {
                Text(cents.map { "Add \(label.lowercased()) · −\(money($0, currency: "USD"))" } ?? "Add discount")
                    .inkCommit()
            }
            .buttonStyle(PressStyle())
        }
        .onChange(of: percent) { _, _ in text = "" }
        .task { focused = true }
    }
}

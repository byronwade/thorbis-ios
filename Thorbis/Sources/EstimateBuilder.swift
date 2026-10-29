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

// MARK: - Focus and search state

enum EstimateBuilderFocus: Hashable {
    case search
    case description(UUID)
    case price(UUID)
}

/// Where the next search pick goes: the estimate's own lines or one option package, and
/// optionally a group chosen with an "Add to" row.
struct EstimateBuilderTarget: Equatable {
    var optionID: String?
    var group: EstimateLineGroup?
}

// MARK: - Search field (EB-01)

/// The builder's one search field, pinned at the top of the screen so focus never moves.
struct EstimateSearchBar: View {
    @Binding var query: String
    @Binding var kind: PriceBookKindFilter
    let focus: FocusState<EstimateBuilderFocus?>.Binding
    let searching: Bool
    let prompt: String
    var keepFiltersVisible = false
    let finish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted).accessibilityHidden(true)
                    TextField(prompt, text: $query)
                        .font(Theme.font(17))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused(focus, equals: .search)
                        .onSubmit(finish)
                        .accessibilityLabel(prompt)
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted)
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.leading, 14)
                .frame(minHeight: 50)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                if searching {
                    Button("Done", action: finish)
                        .font(Theme.font(17, weight: .medium))
                        .foregroundStyle(Theme.foreground)
                        .frame(minWidth: 44, minHeight: 44)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            if searching || keepFiltersVisible {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(PriceBookKindFilter.allCases) { filter in
                            Button { kind = filter } label: {
                                Text(filter.title)
                                    .font(Theme.font(13, weight: .medium))
                                    .foregroundStyle(kind == filter ? Theme.onInk : Theme.foreground)
                                    .padding(.horizontal, 12).frame(minHeight: Theme.chipHeight)
                                    .background(kind == filter ? Theme.ink : Theme.fill, in: Capsule())
                                    .frame(minHeight: 44).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(kind == filter ? .isSelected : [])
                        }
                    }
                }
                .sensoryFeedback(.selection, trigger: kind)
            }
        }
        .padding(.horizontal, Theme.gutter).padding(.top, 8).padding(.bottom, 10)
        .background(Theme.background)
        .animation(.spring(response: 0.3, dampingFraction: 1), value: searching)
    }
}

// MARK: - Results (EB-03..EB-07)

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

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        let current = catalog.context == context
        let results = canUsePriceBook && current ? catalog.index.search(query, kind: kind, usage: catalog.usage) : []
        let recent = canUsePriceBook && current && trimmedQuery.isEmpty ? catalog.index.recent(kind: kind, usage: catalog.usage) : []
        VStack(alignment: .leading, spacing: 0) {
            if canUsePriceBook, !current || catalog.items.isEmpty {
                if !current || catalog.loading {
                    ForEach(0..<6, id: \.self) { _ in skeletonRow }
                } else if let error = catalog.error {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("The price book didn't load. \(error)").font(Theme.font(15)).foregroundStyle(Theme.foreground)
                        Button("Try again", action: retry).font(Theme.font(15, weight: .medium)).frame(minHeight: 44)
                    }
                    .padding(.horizontal, Theme.gutter).padding(.vertical, 12)
                }
            }
            if canUsePriceBook, current, !catalog.items.isEmpty, let error = catalog.error {
                ErrorBanner(message: "Couldn't refresh the price book. Showing saved items. \(error)") { retry() }
                    .padding(.horizontal, Theme.gutter)
            }
            if !recent.isEmpty {
                header("Recent")
                ForEach(recent) { item in row(PriceBookSearchResult(item: item, highlights: [])) }
                header("Price book")
            }
            ForEach(results.filter { result in !recent.contains { $0.id == result.id } }, content: row)
            if canUsePriceBook, current, !catalog.loading, catalog.error == nil,
               results.isEmpty, recent.isEmpty, addCustomLine == nil {
                ContentUnavailableView(
                    catalog.items.isEmpty ? "No active Price Book items" : "No matching items",
                    systemImage: "book.closed",
                    description: Text(catalog.items.isEmpty
                        ? "Add items to your Price Book to use them here."
                        : "Try another search or choose a different category."))
            }
            if !trimmedQuery.isEmpty, let addCustomLine {
                Button { addCustomLine(trimmedQuery) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.muted)
                            .frame(width: 24)
                        Text("Add \u{201C}\(trimmedQuery)\u{201D} as a line")
                            .font(Theme.font(17)).foregroundStyle(Theme.foreground)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Theme.gutter).frame(minHeight: 56).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if canUsePriceBook, trimmedQuery.isEmpty, catalog.index.count > PriceBookSearchIndex.resultLimit {
                Text("Type to search all \(catalog.index.count) items")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, Theme.gutter).padding(.vertical, 14)
            } else if !canUsePriceBook, addCustomLine != nil {
                Text("Type a line and add it. This account can't use the price book.")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, Theme.gutter).padding(.vertical, 14)
            }
        }
        .padding(.bottom, 24)
    }

    private func header(_ title: String) -> some View {
        Text(title).font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
            .padding(.horizontal, Theme.gutter).padding(.top, 14).padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }

    private func row(_ result: PriceBookSearchResult) -> some View {
        PriceBookCatalogResultRow(result: result, quantity: quantityInCurrentDraft(result.id),
                                  secondaryPrice: secondaryPriceText(result.item)) { addItem(result.item) }
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
        .padding(.horizontal, Theme.gutter).frame(minHeight: 56)
        .accessibilityHidden(true)
    }

    static func highlighted(_ text: String, _ ranges: [Range<String.Index>]) -> AttributedString {
        var attributed = AttributedString(text)
        for range in ranges {
            guard let attributedRange = Range(range, in: attributed) else { continue }
            attributed[attributedRange].font = Theme.font(17, weight: .medium)
        }
        return attributed
    }
}

private struct PriceBookCatalogResultRow: View {
    let result: PriceBookSearchResult
    let quantity: Int?
    let secondaryPrice: String?
    let addItem: () -> Void

    var body: some View {
        let item = result.item
        let added = quantity
        Button(action: addItem) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(PriceBookResultsList.highlighted(item.description, result.highlights))
                        .font(Theme.font(17)).foregroundStyle(Theme.foreground)
                        .multilineTextAlignment(.leading)
                    Text("\(PriceBookKindFilter(rawValue: item.kind)?.singular ?? item.kind.capitalized) · \(item.unit)")
                        .font(Theme.font(13)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(money(item.sellPrice.amount, currency: item.sellPrice.currency))
                        .font(Theme.monoFont(17, weight: .medium)).foregroundStyle(Theme.foreground)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    if let secondary = secondaryPrice {
                        Text(secondary).font(Theme.moneyFont(.line)).foregroundStyle(Theme.muted)
                    }
                    if let added {
                        Label("× \(added)", systemImage: "checkmark")
                            .font(Theme.monoFont(13, weight: .medium)).foregroundStyle(Theme.foreground)
                            .labelStyle(.titleAndIcon)
                    }
                }
            }
            .padding(.horizontal, Theme.gutter).padding(.vertical, 10)
            .frame(minHeight: 56).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("price-book-item-\(item.id)")
        .accessibilityValue(added.map { "\($0) in draft" } ?? "Not added")
        .accessibilityHint("Adds one to the current draft")
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

// MARK: - Groups and lines (EB-09..EB-12)

/// One estimate's (or one option's) lines as Work and Materials, edited in place and arranged by
/// dragging the handle.
struct EstimateLineGroupsEditor: View {
    @Binding var lines: [EstimateRevisionLineDraft]
    let disabled: Bool
    let focus: FocusState<EstimateBuilderFocus?>.Binding
    let addTo: (EstimateLineGroup) -> Void
    let removed: (EstimateRevisionLineDraft, Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(EstimateLineGroup.allCases) { group in groupSection(group) }
        }
    }

    private func groupSection(_ group: EstimateLineGroup) -> some View {
        let groupLines = lines.lines(in: group)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(group.title).font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                if !groupLines.isEmpty { Text("\(groupLines.count)").font(Theme.monoFont(13)).foregroundStyle(Theme.muted) }
                Spacer(minLength: 8)
                if !groupLines.isEmpty {
                    Text(lines.subtotal(group).map { money($0, currency: "USD") } ?? "—")
                        .font(Theme.monoFont(17, weight: .medium)).foregroundStyle(Theme.foreground)
                        .contentTransition(.numericText())
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .dropDestination(for: String.self) { ids, _ in drop(ids, before: groupLines.first?.id, group: group) }

            VStack(spacing: 0) {
                ForEach(groupLines) { line in
                    EstimateBuilderLineRow(
                        line: binding(line.id),
                        focus: focus,
                        canMoveUp: line.id != groupLines.first?.id,
                        canMoveDown: line.id != groupLines.last?.id,
                        moveUp: { withAnimation(Self.spring) { lines.moveLine(id: line.id, by: -1) } },
                        moveDown: { withAnimation(Self.spring) { lines.moveLine(id: line.id, by: 1) } },
                        moveToOtherGroup: { withAnimation(Self.spring) { lines.setGroup(id: line.id, group.other) } },
                        duplicate: { withAnimation(Self.spring) { _ = lines.duplicateLine(id: line.id) } },
                        reset: { lines.resetToPriceBook(id: line.id) },
                        remove: {
                            guard let removedLine = withAnimation(Self.spring, { lines.removeLine(id: line.id) }) else { return }
                            removed(removedLine.line, removedLine.index)
                        }
                    )
                    .dropDestination(for: String.self) { ids, _ in drop(ids, before: line.id, group: group) }
                    Rectangle().fill(Theme.border).frame(height: 1).padding(.leading, 44)
                }
                Button { addTo(group) } label: {
                    Label("Add to \(group.title)", systemImage: "plus")
                        .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                        .padding(.horizontal, 14).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(lines.count >= [EstimateRevisionLineDraft].maximumLines)
                .dropDestination(for: String.self) { ids, _ in drop(ids, before: nil, group: group) }
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).stroke(Theme.border))
        }
        .disabled(disabled)
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

struct EstimateBuilderLineRow: View {
    @Binding var line: EstimateRevisionLineDraft
    let focus: FocusState<EstimateBuilderFocus?>.Binding
    let canMoveUp: Bool
    let canMoveDown: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let moveToOtherGroup: () -> Void
    let duplicate: () -> Void
    let reset: () -> Void
    let remove: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    private var quantity: Int { Int(line.quantity.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0 }
    private var moveLabel: String { "Move to \(line.group.other.title)" }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.muted)
                .frame(width: 44, height: 50).contentShape(Rectangle())
                .draggable(line.id.uuidString) {
                    Text(line.description.isEmpty ? "Line" : line.description)
                        .font(Theme.font(15, weight: .medium)).padding(10)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    TextField("Description", text: $line.description, axis: .vertical)
                        .font(Theme.font(17)).lineLimit(1...4)
                        .focused(focus, equals: .description(line.id))
                        .accessibilityLabel("Line description")
                    Text(line.lineTotal.map { money($0, currency: "USD") } ?? "—")
                        .font(Theme.monoFont(15, weight: .medium))
                        .contentTransition(.numericText())
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .fixedSize(horizontal: true, vertical: false)
                    menu
                }
                HStack(spacing: 6) {
                    stepButton("minus", label: "One fewer", enabled: quantity > 1) { line.quantity = String(max(1, quantity - 1)) }
                    TextField("1", text: $line.quantity)
                        .keyboardType(.numberPad)
                        .font(Theme.monoFont(15, weight: .medium))
                        .multilineTextAlignment(.center)
                        .frame(width: 52, height: 44)
                        .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                        .accessibilityLabel("Quantity")
                    stepButton("plus", label: "One more", enabled: quantity < 100_000) { line.quantity = String(min(100_000, quantity + 1)) }
                    Text("×").font(Theme.font(15)).foregroundStyle(Theme.muted).padding(.horizontal, 2).accessibilityHidden(true)
                    HStack(spacing: 4) {
                        Text("$").font(Theme.monoFont(15)).foregroundStyle(Theme.muted)
                        TextField("0.00", text: $line.unitPrice)
                            .keyboardType(.decimalPad)
                            .font(Theme.monoFont(15, weight: .medium))
                            .multilineTextAlignment(.trailing)
                            .focused(focus, equals: .price(line.id))
                            .accessibilityLabel("Price each in dollars")
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: 140, minHeight: 44)
                    .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                }
                if line.isEditedPriceBookLine, let original = line.priceBookOriginal {
                    HStack(spacing: 8) {
                        Text("Edited · price book \(EstimateRevisionEditorState.parsePrice(original.unitPrice).map { money($0, currency: "USD") } ?? original.unitPrice)")
                            .font(Theme.font(15)).monospacedDigit().foregroundStyle(Theme.muted)
                        Button("Reset", action: reset)
                            .font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.foreground)
                            .frame(minHeight: 44)
                            .accessibilityHint("Puts back the price book wording and price")
                    }
                }
            }
            .padding(.trailing, 4).padding(.vertical, 10)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Move up") { if canMoveUp { moveUp() } }
        .accessibilityAction(named: "Move down") { if canMoveDown { moveDown() } }
        .accessibilityAction(named: Text(moveLabel), moveToOtherGroup)
        .accessibilityAction(named: "Remove line", remove)
    }

    private var menu: some View {
        var items: [ThorbisMenuItem] = []
        if canMoveUp { items.append(ThorbisMenuItem("Move up", icon: "arrow.up") { moveUp() }) }
        if canMoveDown { items.append(ThorbisMenuItem("Move down", icon: "arrow.down") { moveDown() }) }
        items.append(ThorbisMenuItem(moveLabel, icon: line.group == .work ? "shippingbox" : "wrench.and.screwdriver") { moveToOtherGroup() })
        items.append(ThorbisMenuItem("Duplicate", icon: "plus.square.on.square") { duplicate() })
        if line.isEditedPriceBookLine { items.append(ThorbisMenuItem("Reset to price book", icon: "arrow.uturn.backward") { reset() }) }
        items.append(ThorbisMenuItem("Remove line", icon: "trash", role: .destructive) { remove() })
        return ThorbisMenu(items: items,
                           accessibilityLabel: "Actions for \(line.description.isEmpty ? "line" : line.description)") {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.muted)
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
    }

    private func stepButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .medium))
                .foregroundStyle(enabled && isEnabled ? Theme.foreground : Theme.muted)
                .frame(width: 44, height: 44)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

// MARK: - Undo (EB-12)

struct RemovedLine: Equatable {
    let line: EstimateRevisionLineDraft
    let index: Int
    /// nil for the estimate's own lines, otherwise the option package it came from.
    let optionID: String?
}

/// "Line removed · Undo" for five seconds, above the commit.
struct LineRemovedToast: View {
    let removed: RemovedLine
    let undo: () -> Void
    let expire: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("Line removed").font(Theme.font(15)).foregroundStyle(Theme.onInk)
            Spacer(minLength: 8)
            Button("Undo", action: undo)
                .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.onInk)
                .frame(minWidth: 44, minHeight: 44)
        }
        .padding(.horizontal, 16)
        .background(Theme.ink, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        .padding(.horizontal, Theme.gutter).padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .task(id: removed.line.id) {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            expire()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Undo", undo)
    }
}

/// The estimate's total as the hero above the commit (MF-04, EB-14).
struct EstimateBuilderTotal: View {
    let total: Int?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Total").font(Theme.font(17, weight: .medium)).foregroundStyle(Theme.muted)
            Spacer(minLength: 12)
            Text(total.map { money($0, currency: "USD") } ?? "—")
                .moneyStyle(.hero).foregroundStyle(Theme.foreground)
                .contentTransition(.numericText())
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, Theme.gutter).padding(.top, 10)
        .background(Theme.background)
        .accessibilityElement(children: .combine)
    }
}

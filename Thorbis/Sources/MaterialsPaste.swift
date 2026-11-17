import SwiftUI

// Paper 32 "Add materials · Paste": a pasted list ("2 x 45/5 capacitor", one item per line) is read
// on this phone into a quantity and a name, each name is looked up in the cached price book (the same
// on-device search the price book picker uses), and the clear matches are staged as lines. Anything
// with several close items, or none, waits under "Needs review" until it is chosen or skipped.
// The parser and the matcher are pure so they are unit-tested (MaterialsTests).

// MARK: - Parsing

/// One pasted line, read as "how many" and "what".
struct MaterialsListLine: Equatable {
    /// The line as typed, trimmed.
    let text: String
    let quantity: Int
    /// What to look up in the price book, without the quantity.
    let name: String
}

enum MaterialsListParser {
    static let maximumQuantity = 999
    /// A unit word right after the quantity is not part of the name ("3 hrs labor" looks up "labor").
    static let unitWords: Set<String> = ["h", "hr", "hrs", "hour", "hours", "ea", "each", "pc", "pcs",
                                         "piece", "pieces", "unit", "units"]

    /// Every non-blank line, in order.
    static func parse(_ text: String) -> [MaterialsListLine] {
        text.split(whereSeparator: { $0.isNewline }).compactMap { parseLine(String($0)) }
    }

    /// "2x R-410A" / "2 x 45/5 capacitor" / "3 hrs labor" / "capacitor x3" / "45/5 capacitor" (one of it).
    static func parseLine(_ raw: String) -> MaterialsListLine? {
        var line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for bullet in ["- ", "* ", "\u{2022} ", "\u{2013} "] where line.hasPrefix(bullet) {
            line = String(line.dropFirst(bullet.count)).trimmingCharacters(in: .whitespaces)
        }
        guard !line.isEmpty else { return nil }

        // A leading count: digits, then "x"/"×" and a space, or a space, or a unit word and a space.
        // "45/5 capacitor" and "2x4 lumber" keep their numbers: they are part of the name.
        let digits = line.prefix(while: { $0.isASCII && $0.isNumber })
        if !digits.isEmpty, digits.count <= 4, let count = Int(digits) {
            let rest = line.dropFirst(digits.count)
            let afterSpaces = rest.drop(while: { $0 == " " || $0 == "\t" })
            if let first = afterSpaces.first, first == "x" || first == "X" || first == "\u{00D7}" {
                let afterX = afterSpaces.dropFirst()
                if let next = afterX.first, next.isWhitespace {
                    let name = clean(String(afterX))
                    if !name.isEmpty { return make(line, count, name) }
                }
            }
            if let first = rest.first, first.isWhitespace {
                let name = stripUnit(clean(String(rest)))
                if !name.isEmpty { return make(line, count, name) }
            } else {
                // "3hrs labor"
                let word = rest.prefix(while: { $0.isLetter })
                let after = rest.dropFirst(word.count)
                if !word.isEmpty, unitWords.contains(word.lowercased()), let next = after.first, next.isWhitespace {
                    let name = clean(String(after))
                    if !name.isEmpty { return make(line, count, name) }
                }
            }
        }

        // A trailing count: "capacitor x3", "capacitor × 3".
        let tokens = line.split(whereSeparator: { $0.isWhitespace }).map { String($0) }
        if tokens.count >= 2, let last = tokens.last {
            let lower = last.lowercased()
            if lower.hasPrefix("x") || lower.hasPrefix("\u{00D7}"), lower.count <= 5, let count = Int(lower.dropFirst()) {
                let name = clean(tokens.dropLast().joined(separator: " "))
                if !name.isEmpty { return make(line, count, name) }
            }
            let marker = tokens[tokens.count - 2].lowercased()
            if tokens.count >= 3, marker == "x" || marker == "\u{00D7}", last.count <= 4, let count = Int(last) {
                let name = clean(tokens.dropLast(2).joined(separator: " "))
                if !name.isEmpty { return make(line, count, name) }
            }
        }
        return make(line, 1, clean(line))
    }

    private static func make(_ line: String, _ count: Int, _ name: String) -> MaterialsListLine {
        MaterialsListLine(text: line, quantity: min(maximumQuantity, max(1, count)), name: name)
    }

    private static func clean(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;:")))
    }

    private static func stripUnit(_ name: String) -> String {
        let parts = name.split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else { return name }
        let word = parts[0].lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard unitWords.contains(word) else { return name }
        return clean(String(parts[1]))
    }
}

// MARK: - Matching

enum MaterialsMatchStatus: Equatable {
    /// One price book item fits; it is staged as a line.
    case matched
    /// Several items fit, or only loosely; the person chooses.
    case similar
    /// Nothing in the price book fits.
    case notFound
}

struct MaterialsMatch {
    let status: MaterialsMatchStatus
    let item: PriceBookListItem?
    let candidates: [PriceBookListItem]
}

enum MaterialsMatcher {
    static let candidateLimit = 12

    /// Looks `name` up with the price book's own search. A line is added automatically only when
    /// exactly one item has the same description, or exactly one item has every typed word as a
    /// whole word; typo and partial-word hits always go to review.
    static func classify(_ name: String, index: PriceBookSearchIndex) -> MaterialsMatch {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return MaterialsMatch(status: .notFound, item: nil, candidates: []) }
        let hits = index.search(trimmed).map { $0.item }
        guard !hits.isEmpty else { return MaterialsMatch(status: .notFound, item: nil, candidates: []) }
        let normalized = PriceBookSearchIndex.normalize(trimmed)
        let whole = hits.filter { PriceBookSearchIndex.normalize($0.description) == normalized }
        if whole.count == 1 { return MaterialsMatch(status: .matched, item: whole[0], candidates: whole) }
        let exact = hits.filter { isExact(trimmed, $0) }
        if exact.count == 1 { return MaterialsMatch(status: .matched, item: exact[0], candidates: exact) }
        let choices = exact.count > 1 ? exact : hits
        return MaterialsMatch(status: .similar, item: nil, candidates: Array(choices.prefix(candidateLimit)))
    }

    /// Lines that still need review are looked up again (the price book finished loading); chosen
    /// lines and quantities stay as they are.
    static func reclassifyUnresolved(_ lines: [StagedMaterial], index: PriceBookSearchIndex) -> [StagedMaterial] {
        lines.map { line in
            guard !line.isResolved else { return line }
            return StagedMaterial(source: line.source, quantity: line.quantity,
                                  match: classify(line.source, index: index), id: line.id)
        }
    }

    /// Every typed word is a whole word of the item (its description, unit or kind), allowing the
    /// letter/number joins the search index makes ("25lb" for "25 lb", "R410A" for "R-410A").
    static func isExact(_ name: String, _ item: PriceBookListItem) -> Bool {
        let words = PriceBookSearchIndex.words(name)
        guard !words.isEmpty else { return false }
        let known = wordSet(item)
        let spellings = [words,
                         PriceBookSearchIndex.joinedModelWords(words, after: false),
                         PriceBookSearchIndex.joinedModelWords(words, after: true)]
        return spellings.contains { spelling in spelling.allSatisfy { known.contains($0) } }
    }

    private static func wordSet(_ item: PriceBookListItem) -> Set<String> {
        let nameWords = PriceBookSearchIndex.words(item.description)
        var known = Set(nameWords)
        for (left, right) in zip(nameWords, nameWords.dropFirst()) {
            let leftNumber = left.contains(where: { $0.isNumber })
            let rightNumber = right.contains(where: { $0.isNumber })
            if leftNumber != rightNumber { known.insert(left + right) }
        }
        for word in PriceBookSearchIndex.words(item.unit) { known.insert(word) }
        if !item.kind.isEmpty {
            known.insert(PriceBookSearchIndex.normalize(item.kind))
            known.insert(PriceBookSearchIndex.normalize(item.kind + "s"))
        }
        return known
    }
}

// MARK: - Staged lines (shared by Scan and Paste)

/// A line waiting in the Add materials sheet: what was scanned or pasted, how many, and the price
/// book item it resolved to (nil while it needs review).
struct StagedMaterial: Identifiable {
    let id: UUID
    /// The pasted name or the scanned code.
    let source: String
    var quantity: Int
    var item: PriceBookListItem?
    var candidates: [PriceBookListItem]
    let status: MaterialsMatchStatus

    init(source: String, quantity: Int, match: MaterialsMatch, id: UUID = UUID()) {
        self.id = id
        self.source = source
        self.quantity = min(MaterialsListParser.maximumQuantity, max(1, quantity))
        self.item = match.item
        self.candidates = match.candidates
        self.status = match.status
    }

    var isResolved: Bool { item != nil }
}

struct MaterialsCommitResult {
    /// Lines still waiting: unresolved ones, and whatever was left when the builder refused.
    var remaining: [StagedMaterial]
    var unitsAdded: Int
    /// The builder's reason for refusing, if it did; adding stops there.
    var refusal: String?
}

enum MaterialsCart {
    /// Hands every resolved line to the builder one unit at a time, the way the price book
    /// picker's "+" does, and stops at the first refusal.
    static func commit(_ lines: [StagedMaterial], add: (PriceBookListItem) -> String?) -> MaterialsCommitResult {
        var remaining: [StagedMaterial] = []
        var added = 0
        var refusal: String?
        for line in lines {
            guard refusal == nil, let item = line.item else {
                remaining.append(line)
                continue
            }
            var left = line.quantity
            while left > 0 {
                if let message = add(item) {
                    refusal = message
                    break
                }
                left -= 1
                added += 1
            }
            if left > 0 {
                var rest = line
                rest.quantity = left
                remaining.append(rest)
            }
        }
        return MaterialsCommitResult(remaining: remaining, unitsAdded: added, refusal: refusal)
    }

    /// Paper 30/32: "Add 2 items · $110.00", or "Add 3 · resolve 2 to continue" while lines need review.
    static func commitTitle(_ lines: [StagedMaterial]) -> String {
        let resolved = lines.filter { $0.isResolved }
        let unresolved = lines.count - resolved.count
        if unresolved > 0 { return "Add \(resolved.count) · resolve \(unresolved) to continue" }
        guard let first = resolved.first?.item else { return "Add items" }
        var total = 0
        for line in resolved {
            if let item = line.item { total += item.sellPrice.amount * line.quantity }
        }
        let noun = resolved.count == 1 ? "item" : "items"
        return "Add \(resolved.count) \(noun) · \(money(total, currency: first.sellPrice.currency))"
    }
}

// MARK: - Shared rows

/// A staged line with its price book item: green tick, name, "Price book · $164.00 for 2", and the
/// stepper (the bin at one).
struct MaterialAddedRow: View {
    let item: PriceBookListItem
    let quantity: Int
    let decrease: () -> Void
    let increase: () -> Void

    private var priceLine: String {
        let each = item.sellPrice.amount
        if quantity > 1 {
            return "Price book · \(money(each * quantity, currency: item.sellPrice.currency)) for \(quantity)"
        }
        return "Price book · \(money(each, currency: item.sellPrice.currency))"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.white, Theme.statusDone)
                .font(.system(size: 20))
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.description).font(Theme.font(16, weight: .medium)).tracking(-0.16)
                    .foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Text(priceLine).font(Theme.font(14)).monospacedDigit().foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            HStack(spacing: 0) {
                Button(action: decrease) {
                    Image(systemName: quantity <= 1 ? "trash" : "minus")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(quantity <= 1 ? Theme.destructive : Theme.foreground)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(quantity <= 1 ? "Remove \(item.description)" : "One fewer \(item.description)")
                Text("\(quantity)").font(Theme.font(15, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(Theme.foreground)
                    .frame(minWidth: 14)
                    .accessibilityLabel("Quantity \(quantity)")
                Button(action: increase) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.foreground)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .disabled(quantity >= MaterialsListParser.maximumQuantity)
                .accessibilityLabel("One more \(item.description)")
            }
            .background(Theme.fill, in: Capsule())
        }
        .padding(.leading, PaperCardMetrics.inset).padding(.trailing, 12).padding(.vertical, 11)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("materials-line-added")
    }
}

/// A line that needs a choice: amber mark, the words as typed in quotes, and why.
struct MaterialReviewRow: View {
    let line: StagedMaterial
    let action: () -> Void

    private var reason: String {
        line.status == .notFound || line.candidates.isEmpty
            ? "Not in price book \u{2014} add manually"
            : "\(line.candidates.count) similar SKUs \u{2014} tap to choose"
    }

    var body: some View {
        Button(action: action) {
            // Paper 32: 12 between the mark, the words and the chevron (the added rows use 8).
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.white, Theme.statusInProgress)
                    .font(.system(size: 20))
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\u{201C}\(line.source)\u{201D}").font(Theme.font(16, weight: .medium)).tracking(-0.16)
                        .foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(reason).font(Theme.font(14)).foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.muted).accessibilityHidden(true)
            }
            .padding(.leading, PaperCardMetrics.inset).padding(.trailing, 16).padding(.vertical, 11)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Choose the price book item")
        .accessibilityIdentifier("materials-line-review")
    }
}

/// Choose the price book item for one line, or skip the line. Opens on the close matches; typing
/// searches the whole cached price book.
struct MaterialsChooseSheet: View {
    let line: StagedMaterial
    let index: PriceBookSearchIndex
    let choose: (PriceBookListItem) -> Void
    let skip: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query: String

    init(line: StagedMaterial, index: PriceBookSearchIndex,
         choose: @escaping (PriceBookListItem) -> Void, skip: @escaping () -> Void) {
        self.line = line
        self.index = index
        self.choose = choose
        self.skip = skip
        _query = State(initialValue: line.source)
    }

    private var results: [PriceBookListItem] {
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed == line.source.trimmingCharacters(in: .whitespacesAndNewlines), !line.candidates.isEmpty {
            return line.candidates
        }
        return Array(index.search(typed).prefix(30).map { $0.item })
    }

    var body: some View {
        ThorbisModalSheet(title: "Choose an item", closeLabel: "Close", onClose: { dismiss() }, detents: [.large]) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted).accessibilityHidden(true)
                TextField("Search price book", text: $query, prompt: .placeholder("Search price book"))
                    .font(Theme.font(17))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .accessibilityLabel("Search price book")
                    .accessibilityIdentifier("materials-choose-search")
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            let found = results
            if found.isEmpty {
                Text("Nothing in the price book matches. Try other words, or skip this line.")
                    .font(Theme.font(15)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Well {
                    ForEach(found) { item in
                        if item.id != found.first?.id { WellDivider() }
                        Button {
                            choose(item)
                            dismiss()
                        } label: {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(item.description).font(Theme.font(16, weight: .medium)).tracking(-0.16)
                                        .foregroundStyle(Theme.foreground)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text("\(item.unit) · \(money(item.sellPrice.amount, currency: item.sellPrice.currency))")
                                        .font(Theme.font(14)).monospacedDigit().foregroundStyle(Theme.muted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "plus").font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Theme.brandText).accessibilityHidden(true)
                            }
                            .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 11)
                            .frame(minHeight: 56)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RowPressStyle())
                        .accessibilityLabel("Use \(item.description), \(money(item.sellPrice.amount, currency: item.sellPrice.currency))")
                    }
                }
            }

            Button {
                skip()
                dismiss()
            } label: {
                Text("Skip this line").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.destructive)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityIdentifier("materials-skip-line")
        }
    }
}

/// The square beside the commit (Paper 30/32): a 50pt circle with the keyboard glyph.
struct MaterialsKeyboardButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "keyboard").font(.system(size: 17)).foregroundStyle(Theme.foreground)
                .frame(width: Theme.commitHeight, height: Theme.commitHeight)
                .background(Theme.fill, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }
}

// MARK: - Paste

private struct MaterialsPasteParseKey: Hashable {
    let text: String
    let catalogSize: Int
}

/// Paper 32's body under the "Add materials" header: the list, what was added, what needs review.
/// `add` hands one unit to the builder (nil when added, else the reason); `finish` closes the sheet.
struct MaterialsPasteView: View {
    let canAdd: Bool
    @Binding var text: String
    @Binding var rows: [StagedMaterial]
    /// Once a quantity is changed or a line chosen, typing no longer re-reads the list; Re-parse does.
    @Binding var edited: Bool
    let add: (PriceBookListItem) -> String?
    let finish: () -> Void

    @ObservedObject private var catalog = PriceBookCatalog.shared
    @State private var reviewing: StagedMaterial?
    @State private var problem: String?
    @State private var addedUnits = 0
    @FocusState private var editorFocused: Bool

    init(canAdd: Bool, text: Binding<String>, rows: Binding<[StagedMaterial]>, edited: Binding<Bool>,
         add: @escaping (PriceBookListItem) -> String?, finish: @escaping () -> Void) {
        self.canAdd = canAdd
        _text = text
        _rows = rows
        _edited = edited
        self.add = add
        self.finish = finish
    }

    private var resolvedRows: [StagedMaterial] { rows.filter { $0.isResolved } }
    private var reviewRows: [StagedMaterial] { rows.filter { !$0.isResolved } }
    private var waitingForCatalog: Bool { catalog.loading && catalog.index.count == 0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                listHeader
                editor
                if let problem {
                    ErrorBanner(message: problem, outer: PaperCardMetrics.margin)
                }
                if waitingForCatalog, !text.isEmpty {
                    Text("Loading the price book\u{2026}").font(Theme.font(14)).foregroundStyle(Theme.muted)
                        .padding(.horizontal, Theme.gutter).padding(.top, 12)
                }
                if !resolvedRows.isEmpty {
                    PaperSection("Added automatically", count: resolvedRows.count) {
                        let added = resolvedRows
                        ForEach(added) { row in
                            if row.id != added.first?.id { WellDivider(leading: 48) }
                            if let item = row.item {
                                MaterialAddedRow(item: item, quantity: row.quantity,
                                                 decrease: { change(row.id, by: -1) },
                                                 increase: { change(row.id, by: 1) })
                            }
                        }
                    }
                    .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 22)
                    .accessibilityIdentifier("materials-paste-added")
                }
                if !reviewRows.isEmpty {
                    reviewSection
                }
            }
            .padding(.bottom, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) { commitBar }
        .sensoryFeedback(.success, trigger: addedUnits)
        .onChange(of: catalog.index.count) { _, _ in
            // After a manual edit the list isn't re-read, but lines still waiting are looked up again.
            if edited { rows = MaterialsMatcher.reclassifyUnresolved(rows, index: catalog.index) }
        }
        .task(id: MaterialsPasteParseKey(text: text, catalogSize: catalog.index.count)) {
            guard !edited else { return }
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            parse()
        }
        .sheet(item: $reviewing) { line in
            MaterialsChooseSheet(line: line, index: catalog.index,
                                 choose: { item in resolve(line.id, with: item) },
                                 skip: { remove(line.id) })
        }
    }

    /// "Paste your list" with Re-parse at the trailing edge (Paper 32).
    private var listHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Paste your list").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    edited = false
                    parse()
                } label: {
                    Text("Re-parse").font(Theme.font(15, weight: .semibold)).foregroundStyle(Theme.brandText)
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityIdentifier("materials-reparse")
            }
        }
        // The 44pt Re-parse target stands in for Paper's 22 above and 8 below the 18pt label.
        .frame(minHeight: 44)
        .padding(.horizontal, Theme.gutter).padding(.top, 8)
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("One item per line, like \u{201C}2 x 45/5 capacitor\u{201D}")
                    .font(Theme.font(16)).foregroundStyle(Theme.muted)
                    .padding(16)
                    .accessibilityHidden(true)
            }
            TextEditor(text: $text)
                .font(Theme.font(16))
                .foregroundStyle(Theme.foreground)
                .lineSpacing(12)
                .scrollContentBackground(.hidden)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($editorFocused)
                // Paper 32: 16 inside the card. The text view adds 5 at the sides and 8 above and below.
                .padding(.horizontal, 11).padding(.vertical, 8)
                .frame(minHeight: 170)
                .accessibilityLabel("Your list")
                .accessibilityIdentifier("materials-paste-list")
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .padding(.horizontal, PaperCardMetrics.margin)
    }

    private var reviewSection: some View {
        let review = reviewRows
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Needs review").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(review.count)").font(Theme.font(13, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(Theme.warning)
            }
            .accessibilityElement(children: .combine)
            .frame(minHeight: 26)
            .padding(.horizontal, 4).padding(.bottom, 8)
            PaperCard {
                ForEach(review) { row in
                    if row.id != review.first?.id { WellDivider(leading: 52) }
                    MaterialReviewRow(line: row) { reviewing = row }
                }
            }
        }
        .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 22)
        .accessibilityIdentifier("materials-paste-review")
    }

    private var commitBar: some View {
        let unresolved = reviewRows.count
        return PaperActionBar(title: MaterialsCart.commitTitle(rows),
                              disabled: unresolved > 0 || !canAdd,
                              identifier: "materials-paste-commit",
                              action: commit) {
            MaterialsKeyboardButton(label: editorFocused ? "Hide keyboard" : "Type your list") {
                editorFocused = !editorFocused
            }
        }
    }

    // MARK: Actions

    private func parse() {
        guard !waitingForCatalog else { return }
        let index = catalog.index
        rows = MaterialsListParser.parse(text).map { line in
            StagedMaterial(source: line.name, quantity: line.quantity,
                           match: MaterialsMatcher.classify(line.name, index: index))
        }
        problem = nil
    }

    private func change(_ id: UUID, by step: Int) {
        guard let position = rows.firstIndex(where: { $0.id == id }) else { return }
        edited = true
        let next = rows[position].quantity + step
        if next < 1 {
            rows.remove(at: position)
        } else {
            rows[position].quantity = min(MaterialsListParser.maximumQuantity, next)
        }
    }

    private func resolve(_ id: UUID, with item: PriceBookListItem) {
        guard let position = rows.firstIndex(where: { $0.id == id }) else { return }
        edited = true
        rows[position].item = item
    }

    private func remove(_ id: UUID) {
        edited = true
        rows.removeAll { $0.id == id }
    }

    private func commit() {
        guard canAdd else { return }
        guard !rows.isEmpty else {
            problem = "Paste or type your list first, one item per line."
            return
        }
        let result = MaterialsCart.commit(rows, add: add)
        rows = result.remaining
        addedUnits += result.unitsAdded
        edited = true
        if let refusal = result.refusal {
            problem = refusal
            return
        }
        problem = nil
        finish()
    }
}

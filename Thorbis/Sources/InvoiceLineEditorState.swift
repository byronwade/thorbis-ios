import Foundation

enum InvoiceLineEditorError: Error, LocalizedError, Equatable {
    case notDraft
    case noLines
    case tooManyLines
    case missingLine
    case descriptionRequired
    case descriptionTooLong
    case invalidQuantity
    case invalidPrice
    case priceBookOverrideReasonRequired
    case archivedPriceBookItem
    case invalidPriceBookSelection
    case unsupportedLineSource
    case unsupportedCurrency

    var errorDescription: String? {
        switch self {
        case .notDraft: "Only a draft invoice can change line items."
        case .noLines: "An invoice needs at least one line item."
        case .tooManyLines: "An invoice can contain up to 500 line items."
        case .missingLine: "That line is no longer on this invoice."
        case .descriptionRequired: "Enter a description for each line item."
        case .descriptionTooLong: "Line item descriptions can contain up to 211 characters."
        case .invalidQuantity: "Quantity must be a whole number from 1 to 100,000."
        case .invalidPrice: "Enter a price with no more than two decimal places."
        case .priceBookOverrideReasonRequired: "Explain the Price Book change before saving."
        case .archivedPriceBookItem: "Archived Price Book items cannot be added to an invoice."
        case .invalidPriceBookSelection: "The Price Book item has no valid current revision or currency."
        case .unsupportedLineSource: "This line has provenance the editor cannot safely preserve."
        case .unsupportedCurrency: "Invoice line edits currently require USD pricing."
        }
    }
}

struct InvoiceLineDraft: Identifiable, Equatable {
    let id: UUID
    let originalLineID: String?
    var description: String
    var quantity: String
    var unitPrice: String
    var unitLabel: String?
    var source: FieldInvoiceLineSourceInput?
    var priceBookBaselineDescription: String?
    var priceBookBaselinePrice: FieldMoney?

    init(id: UUID = UUID(), originalLineID: String? = nil, description: String,
         quantity: String, unitPrice: String, unitLabel: String? = nil,
         source: FieldInvoiceLineSourceInput? = nil, priceBookBaselineDescription: String? = nil,
         priceBookBaselinePrice: FieldMoney? = nil) {
        self.id = id
        self.originalLineID = originalLineID
        self.description = description
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.unitLabel = unitLabel
        self.source = source
        self.priceBookBaselineDescription = priceBookBaselineDescription
        self.priceBookBaselinePrice = priceBookBaselinePrice
    }
}

struct InvoiceLineEditorState: Equatable {
    /// Applies an expanded description only to the same live, unchanged draft line.
    /// The caller must re-check the current session and document before authorizing.
    @discardableResult
    mutating func applyDescription(id: UUID, original: String, value: String, authorized: Bool) -> Bool {
        guard authorized, invoice.status == "draft", !hasUnsupportedLineSources,
              DescriptionCanvasLimit.unicodeScalars(211).count(value) <= 211,
              let index = lines.firstIndex(where: { $0.id == id }), lines[index].description == original else { return false }
        lines[index].description = value
        return true
    }

    let invoice: InvoiceRecord
    var lines: [InvoiceLineDraft]
    var priceBookOverrideReason = ""

    init(invoice: InvoiceRecord) {
        self.invoice = invoice
        self.lines = invoice.lines.map { line in
            let source: FieldInvoiceLineSourceInput?
            let unitLabel: String?
            switch line.source?.kind {
            case "manual":
                source = .manual
                unitLabel = nil
            case "price_book":
                guard let snapshot = line.source else {
                    source = .unsupported("price_book")
                    unitLabel = nil
                    return InvoiceLineDraft(originalLineID: line.id, description: line.description,
                        quantity: String(line.quantity), unitPrice: Self.priceText(line.unitPrice.amount),
                        source: source)
                }
                source = .retainedPriceBook(snapshot)
                unitLabel = snapshot.originalUnit
            case "estimate":
                guard let snapshot = line.source,
                      let estimateID = snapshot.estimateId,
                      let lineID = snapshot.estimateLineId else {
                    source = .unsupported(line.source?.kind ?? "estimate")
                    unitLabel = nil
                    return InvoiceLineDraft(originalLineID: line.id, description: line.description,
                        quantity: String(line.quantity), unitPrice: Self.priceText(line.unitPrice.amount),
                        source: source)
                }
                source = .estimate(id: estimateID, revision: snapshot.estimateRevisionNumber,
                                   lineID: lineID, snapshot: snapshot.estimateLineSource)
                unitLabel = nil
            case nil:
                source = .manual
                unitLabel = nil
            default:
                source = .unsupported(line.source?.kind ?? "unknown")
                unitLabel = nil
            }
            return InvoiceLineDraft(originalLineID: line.id, description: line.description,
                quantity: String(line.quantity), unitPrice: Self.priceText(line.unitPrice.amount),
                unitLabel: unitLabel, source: source)
        }
    }

    var needsPriceBookOverrideReason: Bool {
        for original in invoice.lines {
            guard let source = original.source, source.kind == "price_book" else { continue }
            guard let draft = lines.first(where: { $0.originalLineID == original.id }) else { return true }
            guard case .retainedPriceBook(let retained)? = draft.source,
                  Self.samePriceBookEvidence(source, retained) else { return true }
            if draft.description.trimmingCharacters(in: .whitespacesAndNewlines) != original.description {
                return true
            }
            if (try? Self.parsePrice(draft.unitPrice)) != original.unitPrice.amount { return true }
        }

        for draft in lines {
            guard case .priceBookSelection = draft.source else { continue }
            if draft.description.trimmingCharacters(in: .whitespacesAndNewlines) != draft.priceBookBaselineDescription {
                return true
            }
            if let baseline = draft.priceBookBaselinePrice,
               (try? Self.parsePrice(draft.unitPrice)) != baseline.amount {
                return true
            }
        }
        return false
    }

    var hasUnsupportedLineSources: Bool {
        lines.contains { line in
            guard let source = line.source, case .unsupported = source else { return false }
            return true
        }
    }

    var hasChanges: Bool {
        guard lines.count == invoice.lines.count else { return true }
        for (draft, original) in zip(lines, invoice.lines) {
            guard draft.originalLineID == original.id,
                  draft.description.trimmingCharacters(in: .whitespacesAndNewlines) == original.description,
                  Int(draft.quantity) == original.quantity,
                  (try? Self.parsePrice(draft.unitPrice)) == original.unitPrice.amount,
                  sourceMatches(draft.source, original: original) else { return true }
        }
        return false
    }

    mutating func addManualLine() {
        guard invoice.status == "draft", lines.count < 500 else { return }
        lines.append(InvoiceLineDraft(description: "", quantity: "1", unitPrice: "",
                                      source: .manual))
    }

    mutating func removeLine(id: UUID) throws {
        try requireDraft()
        guard let index = lines.firstIndex(where: { $0.id == id }) else {
            throw InvoiceLineEditorError.missingLine
        }
        lines.remove(at: index)
    }

    mutating func moveLine(id: UUID, to destinationIndex: Int) {
        guard invoice.status == "draft",
              let sourceIndex = lines.firstIndex(where: { $0.id == id }),
              lines.indices.contains(destinationIndex), sourceIndex != destinationIndex else { return }
        let line = lines.remove(at: sourceIndex)
        lines.insert(line, at: destinationIndex)
    }

    mutating func setQuantity(_ id: UUID, _ quantity: Int) throws {
        try requireDraft()
        guard (1...100_000).contains(quantity) else { throw InvoiceLineEditorError.invalidQuantity }
        guard let index = lines.firstIndex(where: { $0.id == id }) else {
            throw InvoiceLineEditorError.missingLine
        }
        lines[index].quantity = String(quantity)
    }

    mutating func setUnitPrice(_ id: UUID, cents: Int) throws {
        try requireDraft()
        guard cents.magnitude <= 100_000_000 else { throw InvoiceLineEditorError.invalidPrice }
        guard let index = lines.firstIndex(where: { $0.id == id }) else {
            throw InvoiceLineEditorError.missingLine
        }
        lines[index].unitPrice = Self.priceText(cents)
    }

    /// Quantity already on the invoice for one price book item, including lines loaded from the server.
    func catalogQuantity(for itemID: String) -> Int? {
        let matches = lines.filter { line in
            switch line.source {
            case .priceBookSelection(let id, _):
                return id == itemID
            case .retainedPriceBook(let source):
                return source.priceBookItemId == itemID
            default:
                return false
            }
        }
        guard !matches.isEmpty else { return nil }
        return matches.reduce(0) { $0 + (Int($1.quantity) ?? 0) }
    }

    mutating func addPriceBookItem(_ item: PriceBookListItem) throws {
        try requireDraft()
        guard item.archivedAt == nil else { throw InvoiceLineEditorError.archivedPriceBookItem }
        guard UUID(uuidString: item.id) != nil, (1...Int(Int32.max)).contains(item.revision),
              invoice.currency == "USD", item.sellPrice.currency == "USD",
              item.sellPrice.amount.magnitude <= 100_000_000 else {
            throw InvoiceLineEditorError.invalidPriceBookSelection
        }
        guard lines.count < 500 else { throw InvoiceLineEditorError.tooManyLines }
        lines.append(InvoiceLineDraft(
            description: item.description, quantity: "1", unitPrice: Self.priceText(item.sellPrice.amount),
            unitLabel: item.unit,
            source: .priceBookSelection(itemID: item.id, revision: item.revision),
            priceBookBaselineDescription: item.description, priceBookBaselinePrice: item.sellPrice
        ))
    }

    func quantity(ofPriceBookItem itemID: String) -> Int? {
        var total = 0
        for line in lines {
            let sourceItemID: String?
            let sourceRevision: Int?
            switch line.source {
            case .priceBookSelection(let id, let revision):
                sourceItemID = id
                sourceRevision = revision
            case .retainedPriceBook(let source) where source.kind == "price_book":
                sourceItemID = source.priceBookItemId
                sourceRevision = source.priceBookRevision
            default: continue
            }
            guard sourceItemID == itemID, let sourceRevision, (1...Int(Int32.max)).contains(sourceRevision),
                  let quantity = Int(line.quantity.trimmingCharacters(in: .whitespacesAndNewlines)),
                  (1...100_000).contains(quantity) else { continue }
            let sum = total.addingReportingOverflow(quantity)
            guard !sum.overflow else { return nil }
            total = sum.partialValue
        }
        return total > 0 ? total : nil
    }

    func makeRequest() throws -> FieldInvoiceLinesRequest {
        try requireDraft()
        guard invoice.currency == "USD" else { throw InvoiceLineEditorError.unsupportedCurrency }
        guard !lines.isEmpty else { throw InvoiceLineEditorError.noLines }
        guard lines.count <= 500 else { throw InvoiceLineEditorError.tooManyLines }

        let encodedLines = try lines.map { draft -> FieldInvoiceLineInput in
            let description = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !description.isEmpty else { throw InvoiceLineEditorError.descriptionRequired }
            guard description.unicodeScalars.count <= 211 else { throw InvoiceLineEditorError.descriptionTooLong }
            guard let quantity = Int(draft.quantity.trimmingCharacters(in: .whitespacesAndNewlines)),
                  (1...100_000).contains(quantity) else { throw InvoiceLineEditorError.invalidQuantity }
            let unitPrice = try Self.parsePrice(draft.unitPrice)
            guard unitPrice.magnitude <= 100_000_000 else { throw InvoiceLineEditorError.invalidPrice }
            if let source = draft.source, case .unsupported = source {
                throw InvoiceLineEditorError.unsupportedLineSource
            }
            return FieldInvoiceLineInput(description: description, quantity: quantity,
                unitPrice: FieldMoney(amount: unitPrice, currency: invoice.currency), source: draft.source ?? .manual)
        }

        let overrideReason: String?
        if needsPriceBookOverrideReason {
            let cleaned = priceBookOverrideReason.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (3...2000).contains(cleaned.utf16.count) else {
                throw InvoiceLineEditorError.priceBookOverrideReasonRequired
            }
            overrideReason = cleaned
        } else {
            overrideReason = nil
        }
        return FieldInvoiceLinesRequest(expectedLinesRevision: invoice.linesRevision,
                                        lines: encodedLines, priceBookOverrideReason: overrideReason)
    }

    private func requireDraft() throws {
        guard invoice.status == "draft" else { throw InvoiceLineEditorError.notDraft }
    }

    /// Cents for a finished price. Incomplete text such as "4." or "" returns nil so a field can keep it.
    static func priceCents(_ text: String) -> Int? {
        try? parsePrice(text)
    }

    private static func parsePrice(_ rawValue: String) throws -> Int {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.range(of: #"^-?\d+(?:\.\d{1,2})?$"#, options: .regularExpression) != nil,
              let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) else {
            throw InvoiceLineEditorError.invalidPrice
        }
        let cents = decimal * 100
        let number = NSDecimalNumber(decimal: cents)
        guard number != .notANumber,
              number.compare(NSDecimalNumber(value: Int.min)) != .orderedAscending,
              number.compare(NSDecimalNumber(value: Int.max)) != .orderedDescending else {
            throw InvoiceLineEditorError.invalidPrice
        }
        let amount = number.intValue
        guard NSDecimalNumber(value: amount).compare(number) == .orderedSame else {
            throw InvoiceLineEditorError.invalidPrice
        }
        return amount
    }

    private static func priceText(_ amount: Int) -> String {
        let magnitude = amount.magnitude
        let cents = magnitude % 100
        let fraction = cents < 10 ? "0\(cents)" : String(cents)
        return "\(amount < 0 ? "-" : "")\(magnitude / 100).\(fraction)"
    }

    private static func samePriceBookEvidence(_ left: FieldLineSource, _ right: FieldLineSource) -> Bool {
        left.kind == right.kind && left.priceBookItemId == right.priceBookItemId &&
        left.priceBookRevision == right.priceBookRevision && left.originalDescription == right.originalDescription &&
        left.originalUnitPrice == right.originalUnitPrice && left.addedByUserId == right.addedByUserId &&
        left.capturedAt == right.capturedAt && left.originalUnit == right.originalUnit &&
        left.originalTaxClassification == right.originalTaxClassification && left.originalItemKind == right.originalItemKind
    }

    private func sourceMatches(_ source: FieldInvoiceLineSourceInput?, original: FieldLine) -> Bool {
        switch source {
        case .manual, nil:
            return original.source == nil || original.source?.kind == "manual"
        case .retainedPriceBook(let retained):
            return original.source == retained
        case .estimate(let id, let revision, let lineID, let snapshot):
            guard let originalSource = original.source else { return false }
            return originalSource.kind == "estimate" && originalSource.estimateId == id &&
                originalSource.estimateRevisionNumber == revision && originalSource.estimateLineId == lineID &&
                originalSource.estimateLineSource == snapshot
        case .priceBookSelection, .unsupported:
            return false
        }
    }
}

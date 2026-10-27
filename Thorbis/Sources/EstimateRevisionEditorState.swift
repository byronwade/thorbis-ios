import Foundation

enum EstimateRevisionEditorError: Error, LocalizedError, Equatable {
    case unsupportedStatus
    case missingRevision
    case titleRequired
    case titleTooLong
    case noLines
    case tooManyLines
    case descriptionRequired
    case descriptionTooLong
    case invalidQuantity
    case invalidPrice
    case archivedPriceBookItem
    case invalidPriceBookSelection
    case tooManyOptions
    case invalidOptionID
    case duplicateOptionID
    case optionTitleRequired
    case optionTitleTooLong
    case optionDescriptionTooLong
    case unsupportedLineSource

    var errorDescription: String? {
        switch self {
        case .unsupportedStatus: "Only sent or declined estimates can be revised here."
        case .missingRevision: "This estimate has no current revision to revise. Refresh it and try again."
        case .titleRequired: "Enter a title for the estimate."
        case .titleTooLong: "Estimate titles can contain up to 200 characters."
        case .noLines: "An estimate needs at least one line item."
        case .tooManyLines: "An estimate can contain up to 500 line items."
        case .descriptionRequired: "Enter a description for each line item."
        case .descriptionTooLong: "Line item descriptions can contain up to 200 characters."
        case .invalidQuantity: "Quantity must be a whole number from 1 to 100,000."
        case .invalidPrice: "Enter a USD price with no more than two decimal places and no more than $1,000,000 per unit."
        case .archivedPriceBookItem: "Archived Price Book items cannot be added to an estimate."
        case .invalidPriceBookSelection: "The Price Book item has no valid current revision or USD price."
        case .tooManyOptions: "An estimate can contain up to eight option packages."
        case .invalidOptionID: "An option package has an invalid identity. Remove it and add it again."
        case .duplicateOptionID: "Option package identities must be unique."
        case .optionTitleRequired: "Enter a title for each option package."
        case .optionTitleTooLong: "Option package titles can contain up to 200 characters."
        case .optionDescriptionTooLong: "Option descriptions can contain up to 500 characters."
        case .unsupportedLineSource: "This estimate contains line provenance this app cannot safely preserve. Review it in Thorbis web before revising."
        }
    }
}

struct EstimateRevisionLineDraft: Identifiable, Equatable {
    let id: UUID
    let originalLineID: String?
    var description: String
    var quantity: String
    var unitPrice: String
    var source: FieldEstimateLineSourceInput?

    init(id: UUID = UUID(), originalLineID: String? = nil, description: String,
         quantity: String, unitPrice: String, source: FieldEstimateLineSourceInput? = nil) {
        self.id = id
        self.originalLineID = originalLineID
        self.description = description
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.source = source
    }
}

struct EstimateRevisionOptionDraft: Identifiable, Equatable {
    var id: String
    var title: String
    var description: String
    var lines: [EstimateRevisionLineDraft]
}

struct EstimateRevisionEditorState: Equatable {
    let estimate: EstimateRecord
    var title: String
    var lines: [EstimateRevisionLineDraft]
    var options: [EstimateRevisionOptionDraft]

    init(estimate: EstimateRecord) {
        self.estimate = estimate
        title = estimate.title
        lines = estimate.lines.map(Self.draftLine)
        options = (estimate.options ?? []).map { option in
            EstimateRevisionOptionDraft(
                id: option.id,
                title: option.title,
                description: option.description,
                lines: option.lines.map(Self.draftLine)
            )
        }
    }

    var canRevise: Bool {
        estimate.status == "sent" || estimate.status == "declined"
    }

    var hasUnsupportedLineSources: Bool {
        (lines + options.flatMap(\.lines)).contains { draft in
            if case .some(.unsupported) = draft.source { return true }
            return false
        }
    }

    var hasChanges: Bool {
        guard Self.cleaned(title) == estimate.title,
              Self.linesMatch(lines, originals: estimate.lines),
              options.count == (estimate.options?.count ?? 0) else { return true }
        for (draft, original) in zip(options, estimate.options ?? []) {
            guard draft.id == original.id, draft.title == original.title,
                  draft.description == original.description,
                  Self.linesMatch(draft.lines, originals: original.lines) else { return true }
        }
        return false
    }

    mutating func addManualLine() {
        guard lines.count < 500 else { return }
        lines.append(Self.blankLine())
    }

    mutating func removeLine(id: UUID) {
        lines.removeAll { $0.id == id }
    }

    mutating func moveLine(id: UUID, to destinationIndex: Int) {
        guard let sourceIndex = lines.firstIndex(where: { $0.id == id }),
              lines.indices.contains(destinationIndex), sourceIndex != destinationIndex else { return }
        let line = lines.remove(at: sourceIndex)
        lines.insert(line, at: destinationIndex)
    }

    mutating func addManualLine(optionID: String) {
        guard let index = options.firstIndex(where: { $0.id == optionID }),
              options[index].lines.count < 500 else { return }
        options[index].lines.append(Self.blankLine())
    }

    mutating func addOption() {
        guard options.count < 8 else { return }
        options.append(EstimateRevisionOptionDraft(
            id: UUID().uuidString.lowercased(), title: "", description: "", lines: [Self.blankLine()]
        ))
    }

    mutating func removeOption(id: String) {
        options.removeAll { $0.id == id }
    }

    mutating func addOptionLine(optionID: String) {
        guard let index = options.firstIndex(where: { $0.id == optionID }),
              options[index].lines.count < 500 else { return }
        options[index].lines.append(Self.blankLine())
    }

    mutating func removeOptionLine(optionID: String, lineID: UUID) {
        guard let index = options.firstIndex(where: { $0.id == optionID }) else { return }
        options[index].lines.removeAll { $0.id == lineID }
    }

    mutating func addPriceBookItem(_ item: PriceBookListItem, optionID: String? = nil) throws {
        guard item.archivedAt == nil else { throw EstimateRevisionEditorError.archivedPriceBookItem }
        guard UUID(uuidString: item.id) != nil, (1...Int(Int32.max)).contains(item.revision),
              item.sellPrice.currency == "USD", item.sellPrice.amount.magnitude <= 100_000_000 else {
            throw EstimateRevisionEditorError.invalidPriceBookSelection
        }
        let line = EstimateRevisionLineDraft(
            description: item.description,
            quantity: "1",
            unitPrice: Self.priceText(item.sellPrice.amount),
            source: .priceBookSelection(itemID: item.id, revision: item.revision)
        )
        if let optionID {
            guard let index = options.firstIndex(where: { $0.id == optionID }), options[index].lines.count < 500 else {
                throw EstimateRevisionEditorError.tooManyLines
            }
            options[index].lines.append(line)
        } else {
            guard lines.count < 500 else { throw EstimateRevisionEditorError.tooManyLines }
            lines.append(line)
        }
    }

    func makeRequest() throws -> FieldEstimateReviseRequest {
        guard canRevise else { throw EstimateRevisionEditorError.unsupportedStatus }
        guard let revision = estimate.currentRevisionNumber, revision > 0 else {
            throw EstimateRevisionEditorError.missingRevision
        }
        guard !hasUnsupportedLineSources else { throw EstimateRevisionEditorError.unsupportedLineSource }
        let cleanedTitle = Self.cleaned(title)
        guard !cleanedTitle.isEmpty else { throw EstimateRevisionEditorError.titleRequired }
        guard cleanedTitle.utf16.count <= 200 else { throw EstimateRevisionEditorError.titleTooLong }
        let requestLines = try Self.makeLines(lines)
        guard options.count <= 8 else { throw EstimateRevisionEditorError.tooManyOptions }
        var identities = Set<String>()
        let requestOptions = try options.map { option -> FieldEstimateOptionRequest in
            guard UUID(uuidString: option.id) != nil else { throw EstimateRevisionEditorError.invalidOptionID }
            let identity = option.id.lowercased()
            guard identities.insert(identity).inserted else { throw EstimateRevisionEditorError.duplicateOptionID }
            let optionTitle = Self.cleaned(option.title)
            guard !optionTitle.isEmpty else { throw EstimateRevisionEditorError.optionTitleRequired }
            guard optionTitle.utf16.count <= 200 else { throw EstimateRevisionEditorError.optionTitleTooLong }
            guard option.description.utf16.count <= 500 else { throw EstimateRevisionEditorError.optionDescriptionTooLong }
            return FieldEstimateOptionRequest(
                id: identity,
                title: optionTitle,
                description: Self.cleaned(option.description),
                lines: try Self.makeLines(option.lines)
            )
        }
        return FieldEstimateReviseRequest(
            expectedRevisionNumber: revision,
            title: cleanedTitle,
            lines: requestLines,
            options: requestOptions.isEmpty ? nil : requestOptions
        )
    }

    private static func draftLine(_ line: FieldLine) -> EstimateRevisionLineDraft {
        let source: FieldEstimateLineSourceInput?
        switch line.source?.kind {
        case nil, "manual":
            source = .manual
        case "price_book":
            if let itemID = line.source?.priceBookItemId,
               UUID(uuidString: itemID) != nil,
               let revision = line.source?.priceBookRevision, revision > 0, revision <= Int(Int32.max) {
                source = .priceBookSelection(itemID: itemID, revision: revision)
            } else {
                source = .unsupported("price_book")
            }
        case let kind?:
            source = .unsupported(kind)
        }
        return EstimateRevisionLineDraft(
            originalLineID: line.id,
            description: line.description,
            quantity: String(line.quantity),
            unitPrice: priceText(line.unitPrice.amount),
            source: source
        )
    }

    private static func blankLine() -> EstimateRevisionLineDraft {
        EstimateRevisionLineDraft(description: "", quantity: "1", unitPrice: "", source: .manual)
    }

    private static func makeLines(_ drafts: [EstimateRevisionLineDraft]) throws -> [FieldEstimateLineInput] {
        guard !drafts.isEmpty else { throw EstimateRevisionEditorError.noLines }
        guard drafts.count <= 500 else { throw EstimateRevisionEditorError.tooManyLines }
        return try drafts.map { draft in
            let description = cleaned(draft.description)
            guard !description.isEmpty else { throw EstimateRevisionEditorError.descriptionRequired }
            guard description.utf16.count <= 200,
                  !description.unicodeScalars.contains(where: { $0.value == 0 }) else {
                throw EstimateRevisionEditorError.descriptionTooLong
            }
            guard let quantity = Int(draft.quantity.trimmingCharacters(in: .whitespacesAndNewlines)),
                  (1...100_000).contains(quantity) else { throw EstimateRevisionEditorError.invalidQuantity }
            guard let amount = parsePrice(draft.unitPrice) else { throw EstimateRevisionEditorError.invalidPrice }
            if let source = draft.source, case .unsupported = source {
                throw EstimateRevisionEditorError.unsupportedLineSource
            }
            return FieldEstimateLineInput(
                description: description,
                quantity: quantity,
                unitPrice: FieldMoney(amount: amount, currency: "USD"),
                source: draft.source ?? .manual
            )
        }
    }

    private static func linesMatch(_ drafts: [EstimateRevisionLineDraft], originals: [FieldLine]) -> Bool {
        guard drafts.count == originals.count else { return false }
        for (draft, original) in zip(drafts, originals) {
            guard draft.originalLineID == original.id,
                  cleaned(draft.description) == original.description,
                  Int(draft.quantity) == original.quantity,
                  parsePrice(draft.unitPrice) == original.unitPrice.amount,
                  sourceMatches(draft.source, original: original) else { return false }
        }
        return true
    }

    private static func sourceMatches(_ source: FieldEstimateLineSourceInput?, original: FieldLine) -> Bool {
        switch source {
        case .some(.manual), nil:
            return original.source == nil || original.source?.kind == "manual"
        case .some(.priceBookSelection(let itemID, let revision)):
            return original.source?.kind == "price_book" &&
                original.source?.priceBookItemId == itemID && original.source?.priceBookRevision == revision
        case .some(.unsupported):
            return false
        }
    }

    private static func parsePrice(_ text: String) -> Int? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.range(of: #"^-?\d+(?:\.\d{1,2})?$"#, options: .regularExpression) != nil,
              let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        let minor = decimal * 100
        guard minor >= Decimal(-100_000_000), minor <= Decimal(100_000_000) else { return nil }
        let number = NSDecimalNumber(decimal: minor)
        guard number != .notANumber, number.compare(NSDecimalNumber(value: number.intValue)) == .orderedSame else { return nil }
        return number.intValue
    }

    private static func priceText(_ amount: Int) -> String {
        let magnitude = amount.magnitude
        let cents = magnitude % 100
        return "\(amount < 0 ? "-" : "")\(magnitude / 100).\(cents < 10 ? "0" : "")\(cents)"
    }

    private static func cleaned(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

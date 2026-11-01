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
    case missingLine
    case unsupportedLineSource
    case optionFeatureRequired
    case discountCapabilityRequired

    var errorDescription: String? {
        switch self {
        case .unsupportedStatus: "Only a draft, sent, or declined estimate can be edited here."
        case .missingRevision: "This estimate has no current revision to revise. Refresh it and try again."
        case .missingLine: "That line is no longer on this estimate."
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
        case .optionFeatureRequired: "This estimate includes option packages. Your account needs estimate option signing access to create a replacement draft without dropping them."
        case .discountCapabilityRequired: "Your account cannot add credit lines to estimate revisions."
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
    /// Work or Materials in the builder (EB-09). Display only until the server stores it.
    var group: EstimateLineGroup
    /// The price book wording and price this line started from, for "Edited" and Reset (EB-10).
    var priceBookOriginal: PriceBookLineOriginal?
    /// False only for a line loaded from the server until the catalog sorts it once; a group the
    /// person picks is never overwritten by a later catalog refresh.
    var groupSettled: Bool
    /// EB-13: false when this material is folded into one "Materials" line for the customer.
    var showToCustomer: Bool
    /// True once the person drags or moves this line to a group, so a move on a line saved
    /// before groups were stored still counts as a change to save.
    var movedByPerson = false

    init(id: UUID = UUID(), originalLineID: String? = nil, description: String,
         quantity: String, unitPrice: String, source: FieldEstimateLineSourceInput? = nil,
         group: EstimateLineGroup = .work, priceBookOriginal: PriceBookLineOriginal? = nil,
         groupSettled: Bool = true, showToCustomer: Bool = true) {
        self.id = id
        self.originalLineID = originalLineID
        self.description = description
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.source = source
        self.group = group
        self.priceBookOriginal = priceBookOriginal
        self.groupSettled = groupSettled
        self.showToCustomer = showToCustomer
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
    /// The workspace stores each line's group and the materials switch (`estimate_line_groups`).
    var storesLineGroups = false

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
        estimate.status == "draft" || estimate.status == "sent" || estimate.status == "declined"
    }

    var hasUnsupportedLineSources: Bool {
        (lines + options.flatMap(\.lines)).contains { draft in
            if case .some(.unsupported) = draft.source { return true }
            return false
        }
    }

    var hasCreditLines: Bool {
        (lines + options.flatMap(\.lines)).contains { (Self.parsePrice($0.unitPrice) ?? 0) < 0 }
    }

    var hasChanges: Bool {
        guard Self.cleaned(title) == estimate.title,
              Self.linesMatch(lines, originals: estimate.lines, storesGroups: storesLineGroups),
              options.count == (estimate.options?.count ?? 0) else { return true }
        for (draft, original) in zip(options, estimate.options ?? []) {
            guard draft.id == original.id, Self.cleaned(draft.title) == Self.cleaned(original.title),
                  Self.cleaned(draft.description) == Self.cleaned(original.description),
                  Self.linesMatch(draft.lines, originals: original.lines, storesGroups: storesLineGroups)
            else { return true }
        }
        return false
    }

    mutating func addManualLine() {
        guard lines.count < 500 else { return }
        lines.append(Self.blankLine())
    }

    mutating func removeLine(id: UUID) throws {
        guard canRevise else { throw EstimateRevisionEditorError.unsupportedStatus }
        guard let index = lines.firstIndex(where: { $0.id == id }) else {
            throw EstimateRevisionEditorError.missingLine
        }
        lines.remove(at: index)
    }

    mutating func setQuantity(_ id: UUID, _ quantity: Int) throws {
        guard canRevise else { throw EstimateRevisionEditorError.unsupportedStatus }
        guard (1...100_000).contains(quantity) else { throw EstimateRevisionEditorError.invalidQuantity }
        guard let index = lines.firstIndex(where: { $0.id == id }) else {
            throw EstimateRevisionEditorError.missingLine
        }
        lines[index].quantity = String(quantity)
    }

    mutating func setUnitPrice(_ id: UUID, cents: Int) throws {
        guard canRevise else { throw EstimateRevisionEditorError.unsupportedStatus }
        guard cents.magnitude <= 100_000_000 else { throw EstimateRevisionEditorError.invalidPrice }
        guard let index = lines.firstIndex(where: { $0.id == id }) else {
            throw EstimateRevisionEditorError.missingLine
        }
        lines[index].unitPrice = Self.priceText(cents)
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
        guard canRevise else { throw EstimateRevisionEditorError.unsupportedStatus }
        guard item.archivedAt == nil else { throw EstimateRevisionEditorError.archivedPriceBookItem }
        guard UUID(uuidString: item.id) != nil, (1...Int(Int32.max)).contains(item.revision),
              item.sellPrice.currency == "USD", item.sellPrice.amount.magnitude <= 100_000_000 else {
            throw EstimateRevisionEditorError.invalidPriceBookSelection
        }
        if let optionID {
            guard let index = options.firstIndex(where: { $0.id == optionID }),
                  options[index].lines.addPriceBookItem(item) != nil else {
                throw EstimateRevisionEditorError.tooManyLines
            }
        } else {
            guard lines.addPriceBookItem(item) != nil else { throw EstimateRevisionEditorError.tooManyLines }
        }
    }

    /// Price book materials move to Materials once the catalog says which items they are (EB-09).
    mutating func classify(kinds: [String: String]) {
        lines.classifyGroups(kinds: kinds)
        for index in options.indices { options[index].lines.classifyGroups(kinds: kinds) }
    }

    func makeRequest(optionsFeatureEnabled: Bool, canDiscount: Bool) throws -> FieldEstimateReviseRequest {
        guard canRevise else { throw EstimateRevisionEditorError.unsupportedStatus }
        let revision: Int
        if estimate.status == "draft" {
            revision = estimate.currentRevisionNumber ?? 0
        } else if let current = estimate.currentRevisionNumber, current > 0 {
            revision = current
        } else {
            throw EstimateRevisionEditorError.missingRevision
        }
        guard !hasUnsupportedLineSources else { throw EstimateRevisionEditorError.unsupportedLineSource }
        guard optionsFeatureEnabled || options.isEmpty else {
            throw EstimateRevisionEditorError.optionFeatureRequired
        }
        let cleanedTitle = Self.cleaned(title)
        guard !cleanedTitle.isEmpty else { throw EstimateRevisionEditorError.titleRequired }
        guard cleanedTitle.utf16.count <= 200 else { throw EstimateRevisionEditorError.titleTooLong }
        let requestLines = try Self.makeLines(lines, storesGroups: storesLineGroups)
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
                lines: try Self.makeLines(option.lines, storesGroups: storesLineGroups)
            )
        }
        if !canDiscount,
           (requestLines + requestOptions.flatMap(\.lines)).contains(where: { $0.unitPrice.amount < 0 }) {
            throw EstimateRevisionEditorError.discountCapabilityRequired
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
        var original: PriceBookLineOriginal?
        if case .priceBookSelection = source, let description = line.source?.originalDescription,
           let price = line.source?.originalUnitPrice, price.currency == "USD" {
            original = PriceBookLineOriginal(description: description, unitPrice: priceText(price.amount))
        }
        let storedGroup = line.group.flatMap(EstimateLineGroup.init(rawValue:))
        return EstimateRevisionLineDraft(
            originalLineID: line.id,
            description: line.description,
            quantity: String(line.quantity),
            unitPrice: priceText(line.unitPrice.amount),
            source: source,
            group: storedGroup ?? .work,
            priceBookOriginal: original,
            // A stored group is the person's choice; only lines saved before groups get sorted.
            groupSettled: storedGroup != nil,
            showToCustomer: line.showToCustomer ?? true
        )
    }

    private static func blankLine() -> EstimateRevisionLineDraft {
        EstimateRevisionLineDraft(description: "", quantity: "1", unitPrice: "", source: .manual)
    }

    private static func makeLines(_ drafts: [EstimateRevisionLineDraft], storesGroups: Bool) throws -> [FieldEstimateLineInput] {
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
            let presentation = drafts.storedPresentation(of: draft, storesGroups: storesGroups)
            return FieldEstimateLineInput(
                description: description,
                quantity: quantity,
                unitPrice: FieldMoney(amount: amount, currency: "USD"),
                source: draft.source ?? .manual,
                group: presentation.group,
                showToCustomer: presentation.showToCustomer
            )
        }
    }

    private static func linesMatch(_ drafts: [EstimateRevisionLineDraft], originals: [FieldLine],
                                   storesGroups: Bool) -> Bool {
        guard drafts.count == originals.count else { return false }
        for (draft, original) in zip(drafts, originals) {
            let presentation = drafts.storedPresentation(of: draft, storesGroups: storesGroups)
            guard draft.originalLineID == original.id,
                  cleaned(draft.description) == original.description,
                  Int(draft.quantity) == original.quantity,
                  parsePrice(draft.unitPrice) == original.unitPrice.amount,
                  sourceMatches(draft.source, original: original),
                  // A line saved before groups were stored has no group to compare, only a move.
                  !storesGroups || ((original.group == nil ? !draft.movedByPerson : presentation.group == original.group)
                      && (presentation.showToCustomer ?? true) == (original.showToCustomer ?? true))
            else { return false }
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

    static func parsePrice(_ text: String) -> Int? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.range(of: #"^-?\d+(?:\.\d{1,2})?$"#, options: .regularExpression) != nil,
              let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        let minor = decimal * 100
        guard minor >= Decimal(-100_000_000), minor <= Decimal(100_000_000) else { return nil }
        let number = NSDecimalNumber(decimal: minor)
        guard number != .notANumber, number.compare(NSDecimalNumber(value: number.intValue)) == .orderedSame else { return nil }
        return number.intValue
    }

    static func priceText(_ amount: Int) -> String {
        let magnitude = amount.magnitude
        let cents = magnitude % 100
        return "\(amount < 0 ? "-" : "")\(magnitude / 100).\(cents < 10 ? "0" : "")\(cents)"
    }

    private static func cleaned(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

import Foundation

enum CommercialDraftRecoveryError: Error, LocalizedError {
    case differentRevision
    var errorDescription: String? { "This document changed since the draft was saved. Your draft is still on this phone; ask your office to review it before replacing anything." }
}

private enum EstimateDraftSource: Codable {
    case manual
    case priceBookSelection(String, Int)
    case unsupported(String)

    init(_ source: FieldEstimateLineSourceInput) {
        switch source {
        case .manual: self = .manual
        case let .priceBookSelection(id, revision): self = .priceBookSelection(id, revision)
        case let .unsupported(kind): self = .unsupported(kind)
        }
    }
    var source: FieldEstimateLineSourceInput {
        switch self {
        case .manual: .manual
        case let .priceBookSelection(id, revision): .priceBookSelection(itemID: id, revision: revision)
        case let .unsupported(kind): .unsupported(kind)
        }
    }
}

private struct EstimateDraftLine: Codable {
    let id: UUID
    let originalLineID: String?
    let description: String
    let quantity: String
    let unitPrice: String
    let source: EstimateDraftSource?
    let group: String
    let originalDescription: String?
    let originalPrice: String?
    let groupSettled: Bool
    let showToCustomer: Bool
    let movedByPerson: Bool

    init(_ line: EstimateRevisionLineDraft) {
        id = line.id; originalLineID = line.originalLineID; description = line.description
        quantity = line.quantity; unitPrice = line.unitPrice; source = line.source.map(EstimateDraftSource.init)
        group = line.group.rawValue; originalDescription = line.priceBookOriginal?.description
        originalPrice = line.priceBookOriginal?.unitPrice; groupSettled = line.groupSettled
        showToCustomer = line.showToCustomer; movedByPerson = line.movedByPerson
    }
    func line() throws -> EstimateRevisionLineDraft {
        guard let group = EstimateLineGroup(rawValue: group) else { throw CocoaError(.fileReadCorruptFile) }
        guard (originalDescription == nil) == (originalPrice == nil) else { throw CocoaError(.fileReadCorruptFile) }
        let original = originalDescription.flatMap { description in originalPrice.map { PriceBookLineOriginal(description: description, unitPrice: $0) } }
        var line = EstimateRevisionLineDraft(id: id, originalLineID: originalLineID, description: description,
            quantity: quantity, unitPrice: unitPrice, source: source?.source, group: group,
            priceBookOriginal: original, groupSettled: groupSettled, showToCustomer: showToCustomer)
        line.movedByPerson = movedByPerson
        return line
    }
}

private struct EstimateDraftOption: Codable {
    let id: String
    let title: String
    let description: String
    let lines: [EstimateDraftLine]
    init(_ option: EstimateRevisionOptionDraft) {
        id = option.id; title = option.title; description = option.description; lines = option.lines.map(EstimateDraftLine.init)
    }
    func option() throws -> EstimateRevisionOptionDraft {
        try .init(id: id, title: title, description: description, lines: lines.map { try $0.line() })
    }
}

struct CommercialEstimateDraft: Codable {
    private let estimateID: String
    private let revision: Int?
    private let title: String
    private let lines: [EstimateDraftLine]
    private let options: [EstimateDraftOption]
    init(state: EstimateRevisionEditorState) {
        estimateID = state.estimate.id; revision = state.estimate.currentRevisionNumber
        title = state.title; lines = state.lines.map(EstimateDraftLine.init); options = state.options.map(EstimateDraftOption.init)
    }
    func apply(to state: inout EstimateRevisionEditorState, requireMatchingRevision: Bool = true) throws {
        guard state.estimate.id == estimateID, !requireMatchingRevision || state.estimate.currentRevisionNumber == revision else { throw CommercialDraftRecoveryError.differentRevision }
        let restoredLines = try lines.map { try $0.line() }
        let restoredOptions = try options.map { try $0.option() }
        state.title = title; state.lines = restoredLines; state.options = restoredOptions
    }
}

/// New estimates have no server id until the create returns. `uncertain` is written before
/// making that request, so a terminated app cannot silently send a second create on recovery.
struct CommercialNewEstimateDraft: Codable {
    let customerID: String
    let title: String
    private let draftLines: [EstimateDraftLine]
    let uncertain: Bool
    let created: EstimateRecord?
    let requiresLocationVerification: Bool
    let requiresManualReview: Bool
    let requiresGroupDisclosure: Bool
    let acceptedGroupLoss: Bool
    /// Reserved for the gated atomic path; old drafts decode with no operation.
    let atomicOperation: AtomicEstimateCommand?
    init(customerID: String, title: String, lines: [EstimateRevisionLineDraft], uncertain: Bool,
         created: EstimateRecord?, requiresLocationVerification: Bool, requiresManualReview: Bool,
         requiresGroupDisclosure: Bool, acceptedGroupLoss: Bool, atomicOperation: AtomicEstimateCommand? = nil) {
        self.customerID = customerID; self.title = title; draftLines = lines.map(EstimateDraftLine.init)
        self.uncertain = uncertain; self.created = created
        self.requiresLocationVerification = requiresLocationVerification; self.requiresManualReview = requiresManualReview
        self.requiresGroupDisclosure = requiresGroupDisclosure; self.acceptedGroupLoss = acceptedGroupLoss
        self.atomicOperation = atomicOperation
    }
    func lines() throws -> [EstimateRevisionLineDraft] { try draftLines.map { try $0.line() } }
}

private enum InvoiceDraftSource: Codable {
    case manual
    case priceBookSelection(String, Int)
    case retainedPriceBook(FieldLineSource)
    case estimate(String, Int?, String, FieldEstimateLineSourceSnapshot?)
    case unsupported(String)
    init(_ source: FieldInvoiceLineSourceInput) {
        switch source {
        case .manual: self = .manual
        case let .priceBookSelection(id, revision): self = .priceBookSelection(id, revision)
        case let .retainedPriceBook(source): self = .retainedPriceBook(source)
        case let .estimate(id, revision, lineID, snapshot): self = .estimate(id, revision, lineID, snapshot)
        case let .unsupported(kind): self = .unsupported(kind)
        }
    }
    var source: FieldInvoiceLineSourceInput {
        switch self {
        case .manual: .manual
        case let .priceBookSelection(id, revision): .priceBookSelection(itemID: id, revision: revision)
        case let .retainedPriceBook(source): .retainedPriceBook(source)
        case let .estimate(id, revision, lineID, snapshot): .estimate(id: id, revision: revision, lineID: lineID, snapshot: snapshot)
        case let .unsupported(kind): .unsupported(kind)
        }
    }
}

private struct InvoiceDraftLine: Codable {
    let id: UUID
    let originalLineID: String?
    let description: String
    let quantity: String
    let unitPrice: String
    let unitLabel: String?
    let source: InvoiceDraftSource?
    let baselineDescription: String?
    let baselinePrice: FieldMoney?
    init(_ line: InvoiceLineDraft) {
        id = line.id; originalLineID = line.originalLineID; description = line.description
        quantity = line.quantity; unitPrice = line.unitPrice; unitLabel = line.unitLabel
        source = line.source.map(InvoiceDraftSource.init); baselineDescription = line.priceBookBaselineDescription
        baselinePrice = line.priceBookBaselinePrice
    }
    var line: InvoiceLineDraft {
        .init(id: id, originalLineID: originalLineID, description: description, quantity: quantity,
              unitPrice: unitPrice, unitLabel: unitLabel, source: source?.source,
              priceBookBaselineDescription: baselineDescription, priceBookBaselinePrice: baselinePrice)
    }
}

struct CommercialInvoiceDraft: Codable {
    private let invoiceID: String
    private let revision: Int
    private let lines: [InvoiceDraftLine]
    private let overrideReason: String
    init(state: InvoiceLineEditorState) {
        invoiceID = state.invoice.id; revision = state.invoice.linesRevision
        lines = state.lines.map(InvoiceDraftLine.init); overrideReason = state.priceBookOverrideReason
    }
    func apply(to state: inout InvoiceLineEditorState, requireMatchingRevision: Bool = true) throws {
        guard state.invoice.id == invoiceID, !requireMatchingRevision || state.invoice.linesRevision == revision else { throw CommercialDraftRecoveryError.differentRevision }
        state.lines = lines.map(\.line); state.priceBookOverrideReason = overrideReason
    }
}

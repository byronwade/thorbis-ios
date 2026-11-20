import Foundation

/// These preconditions bind a financial transition to the version the operator reviewed.
struct FieldEstimateReviseRequest: Encodable {
    /// The estimate's `currentRevisionNumber`, or 0 for a draft that was never sent.
    let expectedRevisionNumber: Int
    /// The estimate's `updatedAt` exactly as last read. The server needs it to change a draft (so
    /// two people never write over each other) and ignores it otherwise. Left out when nil.
    let expectedUpdatedAt: String?
    let title: String
    let lines: [FieldEstimateLineInput]
    let options: [FieldEstimateOptionRequest]?

    init(expectedRevisionNumber: Int, expectedUpdatedAt: String? = nil, title: String, lines: [FieldEstimateLineInput],
         options: [FieldEstimateOptionRequest]? = nil) {
        self.expectedRevisionNumber = expectedRevisionNumber
        self.expectedUpdatedAt = expectedUpdatedAt
        self.title = title
        self.lines = lines
        self.options = options
    }
}

/// What a failed save of an estimate's edits means for the person editing, from the server's answer.
enum EstimateSaveFailure: Equatable {
    /// Someone else changed the draft: say so and offer the latest (the edits stay until they take it).
    case stale
    /// The server wants the draft's token: read the estimate again and try once more.
    case reloadAndRetry
    case noPermission
    /// A server that can't change a draft yet. The edits stay on screen.
    case draftsNotEditableYet
    /// Anything else, in the server's own words; `conflict` offers the latest estimate.
    case other(message: String, conflict: Bool)

    static let staleMessage = "Someone else changed this estimate. Reload it and try again."
    static let noPermissionMessage = "You no longer have permission to revise this estimate."
    static let draftsNotEditableMessage = "This draft can\u{2019}t be changed yet. Send it, then edit it."

    /// - Parameters:
    ///   - wasDraft: the estimate being saved was a draft.
    ///   - sentRevision: the `expectedRevisionNumber` that was sent.
    static func of(_ error: Error, wasDraft: Bool, sentRevision: Int) -> EstimateSaveFailure {
        guard let problem = error as? Problem else { return .other(message: error.localizedDescription, conflict: false) }
        switch (problem.status, problem.code) {
        case (409, "stale_draft"): return .stale
        case (409, "draft_token_required"): return .reloadAndRetry
        case (403, _): return .noPermission
        default: break
        }
        if wasDraft {
            // Before draft edits: revision 0 is refused as invalid, and any other draft save is
            // answered "a replacement draft already exists". An approved estimate's 409 is not this.
            if problem.status == 400, sentRevision == 0 { return .draftsNotEditableYet }
            if problem.status == 409, problem.code == nil,
               (problem.detail ?? problem.title ?? "").localizedCaseInsensitiveContains("replacement draft") {
                return .draftsNotEditableYet
            }
        }
        return .other(message: problem.localizedDescription, conflict: problem.status == 409)
    }

    var message: String {
        switch self {
        case .stale, .reloadAndRetry: Self.staleMessage
        case .noPermission: Self.noPermissionMessage
        case .draftsNotEditableYet: Self.draftsNotEditableMessage
        case .other(let message, _): message
        }
    }

    /// Whether to offer "Review latest estimate" (which replaces the edits when taken).
    var offersLatest: Bool {
        switch self {
        case .stale, .reloadAndRetry: true
        case .other(_, let conflict): conflict
        default: false
        }
    }
}

struct FieldEstimateOptionRequest: Encodable {
    let id: String
    let title: String
    let description: String
    let lines: [FieldEstimateLineInput]
}

/// One sent version of an estimate, as the server froze it when it went out
/// (`GET /v1/estimates/{id}/revisions/{revisionNumber}`). Read-only history (Paper 35B, 35E):
/// `status` is "issued", "approved" or "declined"; `supersededAt` is set once a later one replaced it.
struct EstimateRevisionRecord: Decodable, Identifiable, Hashable {
    let id: String
    let estimateId: String
    let revisionNumber: Int
    let status: String
    let title: String
    let lines: [FieldLine]
    let options: [FieldEstimateOption]?
    let totalAmount: Int
    let currency: String
    let issuedAt: String?
    let approvedAt: String?
    let declinedAt: String?
    let supersededAt: String?
    let supersededByRevisionNumber: Int?
}

struct FieldInvoiceLinesRequest: Encodable {
    let expectedLinesRevision: Int
    let lines: [FieldInvoiceLineInput]
    let priceBookOverrideReason: String?

    init(expectedLinesRevision: Int, lines: [FieldInvoiceLineInput],
         priceBookOverrideReason: String? = nil) {
        self.expectedLinesRevision = expectedLinesRevision
        self.lines = lines
        self.priceBookOverrideReason = priceBookOverrideReason
    }
}

struct FieldInvoicePayLink: Decodable, Equatable {
    let url: String
    let expiresAt: String

    var shareURL: URL? {
        guard let components = URLComponents(string: url),
              components.scheme?.lowercased() == "https",
              components.host != nil,
              components.user == nil,
              components.password == nil,
              components.port == nil else { return nil }
        return components.url
    }
}

enum FieldInvoiceLineSourceInput: Hashable, Encodable {
    case manual
    case priceBookSelection(itemID: String, revision: Int)
    case retainedPriceBook(FieldLineSource)
    case estimate(id: String, revision: Int?, lineID: String, snapshot: FieldEstimateLineSourceSnapshot?)
    case unsupported(String)

    private enum CodingKeys: String, CodingKey {
        case kind, priceBookItemId, priceBookRevision, estimateId
        case estimateRevisionNumber, estimateLineId, estimateLineSource
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .manual:
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode("manual", forKey: .kind)
        case .priceBookSelection(let itemID, let revision):
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode("price_book", forKey: .kind)
            try values.encode(itemID, forKey: .priceBookItemId)
            try values.encode(revision, forKey: .priceBookRevision)
        case .retainedPriceBook(let source):
            guard source.kind == "price_book" else {
                throw EncodingError.invalidValue(source, .init(codingPath: encoder.codingPath,
                    debugDescription: "Only retained Price Book evidence can be encoded here"))
            }
            try source.encode(to: encoder)
        case .estimate(let id, let revision, let lineID, let snapshot):
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode("estimate", forKey: .kind)
            try values.encode(id, forKey: .estimateId)
            try values.encodeIfPresent(revision, forKey: .estimateRevisionNumber)
            try values.encode(lineID, forKey: .estimateLineId)
            try values.encodeIfPresent(snapshot, forKey: .estimateLineSource)
        case .unsupported(let kind):
            throw EncodingError.invalidValue(kind, .init(codingPath: encoder.codingPath,
                debugDescription: "Unsupported invoice line provenance"))
        }
    }
}

struct FieldInvoiceLineInput: Encodable, Hashable {
    let description: String
    let quantity: Int
    let unitPrice: FieldMoney
    let source: FieldInvoiceLineSourceInput?

    init(description: String, quantity: Int, unitPrice: FieldMoney,
         source: FieldInvoiceLineSourceInput? = nil) {
        self.description = description
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.source = source
    }
}

/// Tender already collected from the customer. Card/ACH here record the
/// tender type; processor-backed collection uses separate endpoints.
enum FieldPaymentMethod: String, Codable, CaseIterable, Hashable {
    case card, ach, cash, check

    var displayName: String {
        switch self {
        case .card: "Card"
        case .ach: "Bank transfer (ACH)"
        case .cash: "Cash"
        case .check: "Check"
        }
    }
}
enum FieldPaymentStatus: String, Codable { case recorded, refunded }

enum FieldPaymentRefundOutcome: String, Decodable, Equatable {
    case pending
    case reconciliationRequired = "reconciliation_required"
}

enum FieldPaymentRefundResponse: Decodable {
    case completed(FieldPaymentRecord)
    case accepted(outcome: FieldPaymentRefundOutcome, paymentID: String)

    private enum CodingKeys: String, CodingKey { case outcome, paymentId }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if values.contains(.outcome) {
            self = .accepted(
                outcome: try values.decode(FieldPaymentRefundOutcome.self, forKey: .outcome),
                paymentID: try values.decode(String.self, forKey: .paymentId)
            )
        } else {
            self = .completed(try FieldPaymentRecord(from: decoder))
        }
    }
}

struct FieldPhysicalServiceSource: Codable {
    enum Kind: String, Codable { case job, billingSchedule = "billing_schedule", manualPhysicalServiceEvidence = "manual_physical_service_evidence" }
    let kind: Kind
    let id: String
}

enum FieldPaymentCollectionEvidence: Codable {
    case physicalService(FieldPhysicalServiceSource)
    case unclassifiedLegacy

    var source: FieldPhysicalServiceSource? {
        if case .physicalService(let source) = self { return source }
        return nil
    }

    private enum CodingKeys: String, CodingKey { case purpose, source }
    private enum Purpose: String, Codable { case physicalService = "physical_service", unclassifiedLegacy = "unclassified_legacy" }

    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        switch try fields.decode(Purpose.self, forKey: .purpose) {
        case .physicalService: self = .physicalService(try fields.decode(FieldPhysicalServiceSource.self, forKey: .source))
        case .unclassifiedLegacy: self = .unclassifiedLegacy
        }
    }

    func encode(to encoder: Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .physicalService(let source):
            try fields.encode(Purpose.physicalService, forKey: .purpose)
            try fields.encode(source, forKey: .source)
        case .unclassifiedLegacy:
            try fields.encode(Purpose.unclassifiedLegacy, forKey: .purpose)
        }
    }
}

struct FieldPaymentRecord: Codable, Identifiable {
    let id: String
    let organizationId: String
    let invoiceId: String
    let amount: FieldMoney
    let method: String
    let status: FieldPaymentStatus
    let collectionEvidence: FieldPaymentCollectionEvidence
    let idempotencyKey: String
    let recordedAt: String
    let refundedAmount: Int?
    let netAmount: FieldMoney?
    let refundedAt: String?
}

struct FieldRecordPaymentRequest: Codable {
    let amount: FieldMoney
    let method: FieldPaymentMethod
    /// Mint once for the observed collection; retain unchanged through every retry.
    let idempotencyKey: String
}

private struct FinancialItems<T: Decodable>: Decodable {
    let items: [T]
    let nextCursor: String?
}

struct FieldPaymentHistoryRead {
    let payments: [FieldPaymentRecord]
    let pages: [APIReadProvenance]
}

@MainActor
extension APIClient {
    func financialPath(_ base: String, id: String, suffix: String) throws -> String {
        guard UUID(uuidString: id) != nil else {
            throw Problem(title: "Invalid financial record ID", status: nil, detail: id)
        }
        return "\(base)/\(id)\(suffix)"
    }

    func sendFieldEstimate(_ id: String, expectedRevisionNumber: Int) async throws -> EstimateRecord {
        struct Body: Encodable { let expectedRevisionNumber: Int }
        return try await send("POST", financialPath("/v1/estimates", id: id, suffix: "/send"),
                              body: Body(expectedRevisionNumber: expectedRevisionNumber))
    }

    func approveFieldEstimate(_ id: String, revisionNumber: Int, depositRequired: FieldMoney? = nil,
                              signature: FieldSignatureInput? = nil) async throws -> EstimateRecord {
        struct Body: Encodable { let revisionNumber: Int; let depositRequired: FieldMoney?; let signature: FieldSignatureInput? }
        return try await send("POST", financialPath("/v1/estimates", id: id, suffix: "/approve"),
                              body: Body(revisionNumber: revisionNumber, depositRequired: depositRequired, signature: signature))
    }

    /// The customer signs the invoice's current lines on the technician's phone (online only).
    func authorizeFieldInvoice(_ id: String, expectedLinesRevision: Int, signature: FieldSignatureInput) async throws -> InvoiceRecord {
        struct Body: Encodable { let expectedLinesRevision: Int; let signerName: String; let signedAt: String; let imageMediaId: String }
        return try await send("POST", financialPath("/v1/invoices", id: id, suffix: "/authorizations"),
                              body: Body(expectedLinesRevision: expectedLinesRevision, signerName: signature.signerName,
                                         signedAt: signature.signedAt, imageMediaId: signature.imageMediaId))
    }

    func declineFieldEstimate(_ id: String, revisionNumber: Int) async throws -> EstimateRecord {
        struct Body: Encodable { let revisionNumber: Int }
        return try await send("POST", financialPath("/v1/estimates", id: id, suffix: "/decline"),
                              body: Body(revisionNumber: revisionNumber))
    }

    func reviseFieldEstimate(_ id: String, request: FieldEstimateReviseRequest) async throws -> EstimateRecord {
        try await send("POST", financialPath("/v1/estimates", id: id, suffix: "/revise"), body: request)
    }

    /// One sent version of an estimate, exactly as it went out. Versions are numbered from 1 up to
    /// the estimate's `currentRevisionNumber`; the server has no list route, so each is read alone.
    func fieldEstimateRevision(_ id: String, number: Int) async throws -> EstimateRevisionRecord {
        guard number > 0 else {
            throw Problem(title: "Invalid estimate revision", status: nil, detail: "\(number)")
        }
        return try await send("GET", financialPath("/v1/estimates", id: id, suffix: "/revisions/\(number)"))
    }

    func replaceFieldInvoiceLines(_ id: String, request: FieldInvoiceLinesRequest) async throws -> InvoiceRecord {
        try await send("POST", financialPath("/v2/invoices", id: id, suffix: "/lines"), body: request)
    }

    func issueFieldInvoice(_ id: String, expectedLinesRevision: Int) async throws -> InvoiceRecord {
        struct Body: Encodable { let expectedLinesRevision: Int }
        return try await send("POST", financialPath("/v1/invoices", id: id, suffix: "/issue"),
                              body: Body(expectedLinesRevision: expectedLinesRevision))
    }

    /// Web parity (invoice-detail): a draft takes a discount as one negative "Discount — reason" line.
    /// The server refuses a sent invoice, a discount above the total, or one past the role's limit.
    func discountFieldInvoice(_ id: String, amountCents: Int, reason: String) async throws -> InvoiceRecord {
        struct Body: Encodable { let description: String; let amount: FieldMoney }
        return try await send("POST", financialPath("/v1/invoices", id: id, suffix: "/discount"),
                              body: Body(description: reason, amount: FieldMoney(amount: amountCents, currency: "USD")))
    }

    func fieldPayments(_ invoiceID: String) async throws -> [FieldPaymentRecord] {
        try await fieldPaymentsWithProvenance(invoiceID).payments
    }

    func fieldPaymentsWithProvenance(_ invoiceID: String) async throws -> FieldPaymentHistoryRead {
        let path = try financialPath("/v1/invoices", id: invoiceID, suffix: "/payments")
        let generation = requestGeneration
        let scope = savedCopyScope
        let scopeRevision = savedCopyScopeRevision
        let origin = normalizedOrigin
        var payments: [FieldPaymentRecord] = []
        var pages: [APIReadProvenance] = []
        var cursor: String?
        var seen = Set<String>()
        repeat {
            try Task.checkCancellation()
            guard generation == requestGeneration, scope == savedCopyScope, scopeRevision == savedCopyScopeRevision,
                  origin == normalizedOrigin else { throw CancellationError() }
            let page: APIRead<FinancialItems<FieldPaymentRecord>> = try await sendWithProvenance(path, cursor: cursor)
            try Task.checkCancellation()
            guard generation == requestGeneration, scope == savedCopyScope, scopeRevision == savedCopyScopeRevision, origin == normalizedOrigin,
                  page.provenance.generation == generation, page.provenance.savedCopyScope == scope,
                  page.provenance.savedCopyScopeRevision == scopeRevision,
                  Self.normalizedOrigin(page.provenance.origin) == origin else { throw CancellationError() }
            payments.append(contentsOf: page.value.items)
            pages.append(page.provenance)
            cursor = page.value.nextCursor
            if let cursor, cursor.isEmpty || !seen.insert(cursor).inserted {
                throw Problem(title: "Pagination cursor loop", status: nil, detail: "Repeated or empty cursor")
            }
        } while cursor != nil
        return FieldPaymentHistoryRead(payments: payments, pages: pages)
    }

    func openFieldPayLink(_ invoiceID: String) async throws -> FieldInvoicePayLink {
        let path = try financialPath("/v1/invoices", id: invoiceID, suffix: "/pay-link")
        let payLink: FieldInvoicePayLink = try await send("POST", path)
        guard payLink.shareURL != nil else {
            throw Problem(title: "Invalid payment link", status: nil,
                          detail: "The server returned a payment link that is not a secure HTTPS URL")
        }
        return payLink
    }

    func recordFieldPayment(_ invoiceID: String, request: FieldRecordPaymentRequest) async throws -> FieldPaymentRecord {
        guard request.amount.amount > 0, request.amount.currency == "USD",
              (1...200).contains(request.idempotencyKey.count) else {
            throw Problem(title: "Invalid payment intent", status: nil,
                          detail: "Use positive USD cents and a stable 1–200 character idempotency key")
        }
        return try await send("POST", financialPath("/v1/invoices", id: invoiceID, suffix: "/payments"), body: request)
    }

    func refundFieldPayment(_ paymentID: String, reason: String) async throws -> FieldPaymentRefundResponse {
        struct Body: Encodable { let reason: String }

        let normalizedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (3...2_000).contains(normalizedReason.utf16.count) else {
            throw Problem(title: "Invalid refund reason", status: nil,
                          detail: "Enter a reason between 3 and 2,000 characters.")
        }
        let path = try financialPath("/v1/payments", id: paymentID, suffix: "/refund")
        let (response, status) = try await sendWithStatus(
            "POST", path, body: Body(reason: normalizedReason)
        ) as (value: FieldPaymentRefundResponse, status: Int)

        switch status {
        case 200:
            guard case let .completed(payment) = response,
                  payment.id == paymentID,
                  case .refunded = payment.status else {
                throw Problem(title: "Invalid refund response", status: status,
                              detail: "The server did not return the refunded payment.")
            }
        case 202:
            guard case let .accepted(_, responsePaymentID) = response,
                  responsePaymentID == paymentID else {
                throw Problem(title: "Invalid refund response", status: status,
                              detail: "The accepted refund did not match the requested payment.")
            }
        default:
            throw Problem(title: "Invalid refund response", status: status,
                          detail: "The server returned an unsupported refund response status.")
        }
        return response
    }
}

struct FieldSignatureInput: Encodable, Hashable {
    let signerName: String
    let signedAt: String
    let imageMediaId: String
}

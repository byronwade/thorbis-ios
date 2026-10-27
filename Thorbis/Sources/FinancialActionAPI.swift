import Foundation

/// These preconditions bind a financial transition to the version the operator reviewed.
struct FieldEstimateReviseRequest: Encodable {
    let expectedRevisionNumber: Int
    let title: String
    let lines: [FieldEstimateLineInput]
    let options: [FieldEstimateOptionRequest]?

    init(expectedRevisionNumber: Int, title: String, lines: [FieldEstimateLineInput],
         options: [FieldEstimateOptionRequest]? = nil) {
        self.expectedRevisionNumber = expectedRevisionNumber
        self.title = title
        self.lines = lines
        self.options = options
    }
}

struct FieldEstimateOptionRequest: Encodable {
    let id: String
    let title: String
    let description: String
    let lines: [FieldEstimateLineInput]
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
enum FieldPaymentMethod: String, Codable, CaseIterable, Hashable { case card, ach, cash, check }
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

@MainActor
extension APIClient {
    private func financialPath(_ base: String, id: String, suffix: String) throws -> String {
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

    func approveFieldEstimate(_ id: String, revisionNumber: Int, depositRequired: FieldMoney? = nil) async throws -> EstimateRecord {
        struct Body: Encodable { let revisionNumber: Int; let depositRequired: FieldMoney? }
        return try await send("POST", financialPath("/v1/estimates", id: id, suffix: "/approve"),
                              body: Body(revisionNumber: revisionNumber, depositRequired: depositRequired))
    }

    func declineFieldEstimate(_ id: String, revisionNumber: Int) async throws -> EstimateRecord {
        struct Body: Encodable { let revisionNumber: Int }
        return try await send("POST", financialPath("/v1/estimates", id: id, suffix: "/decline"),
                              body: Body(revisionNumber: revisionNumber))
    }

    func reviseFieldEstimate(_ id: String, request: FieldEstimateReviseRequest) async throws -> EstimateRecord {
        try await send("POST", financialPath("/v1/estimates", id: id, suffix: "/revise"), body: request)
    }

    func replaceFieldInvoiceLines(_ id: String, request: FieldInvoiceLinesRequest) async throws -> InvoiceRecord {
        try await send("POST", financialPath("/v2/invoices", id: id, suffix: "/lines"), body: request)
    }

    func issueFieldInvoice(_ id: String, expectedLinesRevision: Int) async throws -> InvoiceRecord {
        struct Body: Encodable { let expectedLinesRevision: Int }
        return try await send("POST", financialPath("/v1/invoices", id: id, suffix: "/issue"),
                              body: Body(expectedLinesRevision: expectedLinesRevision))
    }

    func fieldPayments(_ invoiceID: String) async throws -> [FieldPaymentRecord] {
        let path = try financialPath("/v1/invoices", id: invoiceID, suffix: "/payments")
        let generation = requestGeneration
        var payments: [FieldPaymentRecord] = []
        var cursor: String?
        var seen = Set<String>()
        repeat {
            try Task.checkCancellation()
            guard generation == requestGeneration else { throw CancellationError() }
            let page: FinancialItems<FieldPaymentRecord> = try await send("GET", path, cursor: cursor)
            payments.append(contentsOf: page.items)
            cursor = page.nextCursor
            if let cursor, cursor.isEmpty || !seen.insert(cursor).inserted {
                throw Problem(title: "Pagination cursor loop", status: nil, detail: "Repeated or empty cursor")
            }
        } while cursor != nil
        return payments
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

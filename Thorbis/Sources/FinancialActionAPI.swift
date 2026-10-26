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
    let lines: [FieldEstimateLineInput]
    let priceBookOverrideReason: String?

    init(expectedLinesRevision: Int, lines: [FieldEstimateLineInput],
         priceBookOverrideReason: String? = nil) {
        self.expectedLinesRevision = expectedLinesRevision
        self.lines = lines
        self.priceBookOverrideReason = priceBookOverrideReason
    }
}

enum FieldPaymentMethod: String, Codable { case cash, check }
enum FieldPaymentStatus: String, Codable { case recorded, refunded }

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

struct FieldRecordPaymentRequest: Encodable {
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

    func recordFieldPayment(_ invoiceID: String, request: FieldRecordPaymentRequest) async throws -> FieldPaymentRecord {
        guard request.amount.amount > 0, request.amount.currency == "USD",
              (1...200).contains(request.idempotencyKey.count) else {
            throw Problem(title: "Invalid payment intent", status: nil,
                          detail: "Use positive USD cents and a stable 1–200 character idempotency key")
        }
        return try await send("POST", financialPath("/v1/invoices", id: invoiceID, suffix: "/payments"), body: request)
    }
}

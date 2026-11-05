import Foundation

/// Collection methods include financed payments; this does not enable recording a new method.
enum PaymentsCollectionMethod: String, Decodable { case card, ach, cash, check, financing }

/// A page of server-authorized payments. Amounts are cents; this projection is online-only.
struct PaymentsCollectionItem: Identifiable, Equatable {
    let id: String
    let invoiceID: String
    let status: FieldPaymentStatus
    let method: PaymentsCollectionMethod
    let recordedAt: String
    let amount: Int
    let refundedAmount: Int
    let netAmount: Int
}

struct PaymentsCollectionPage: Equatable {
    let items: [PaymentsCollectionItem]
    /// Opaque server cursor; a non-nil value means this is not the entire result.
    let nextCursor: String?
}

private struct PaymentsQueryInteger: Decodable {
    let value: Int
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) { self.value = value; return }
        let string = try container.decode(String.self)
        guard let value = Int(string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected an integer amount")
        }
        self.value = value
    }
}

private struct PaymentsQueryResponse: Decodable {
    struct Item: Decodable {
        struct Fields: Decodable {
            let id: String
            let invoiceID: String
            let status: FieldPaymentStatus
            let method: PaymentsCollectionMethod
            let recordedAt: String
            let amount: PaymentsQueryInteger
            let refundedAmount: PaymentsQueryInteger
            let netAmount: PaymentsQueryInteger
            enum CodingKeys: String, CodingKey {
                case id = "payments.id", invoiceID = "payments.invoice_id", status = "payments.status"
                case method = "payments.method", recordedAt = "payments.recorded_at", amount = "payments.amount"
                case refundedAmount = "payments.refunded_amount", netAmount = "payments.net_amount"
            }
        }
        let id: String
        let resourceId: String
        let fields: Fields
    }
    let schemaVersion: Int
    let resourceId: String
    let purpose: String
    let localMode: String
    let items: [Item]
    let nextCursor: String?
}

@MainActor
extension APIClient {
    /// A single fresh page of the same `payments.all` view used by the web. Callers must pass a
    /// predicate covering the verified actor, workspace, permission and feature state, and clear
    /// already displayed rows whenever that state changes.
    func paymentsCollectionPage(limit: Int = 50, cursor: String? = nil,
                                isCurrent: @escaping @MainActor () -> Bool) async throws -> PaymentsCollectionPage {
        guard isCurrent(), !Task.isCancelled else { throw CancellationError() }
        guard (1...200).contains(limit), cursor.map({ UUID(uuidString: $0) != nil }) ?? true else {
            throw Problem(title: "Invalid payments page", status: nil, detail: "Use a valid cursor and page size.")
        }
        let generation = requestGeneration
        let copyRevision = savedCopyScopeRevision
        let origin = normalizedOrigin
        let response: PaymentsQueryResponse
        do {
            response = try await send("GET", "/v1/query", queryItems: [
            URLQueryItem(name: "resourceId", value: "payments"),
            URLQueryItem(name: "viewId", value: "payments.all"),
            URLQueryItem(name: "purpose", value: "collection"),
            URLQueryItem(name: "limit", value: String(limit)),
        ], cursor: cursor, requireFresh: true)
        } catch {
            guard !Task.isCancelled, isCurrent(), requestGeneration == generation,
                  savedCopyScopeRevision == copyRevision, normalizedOrigin == origin else { throw CancellationError() }
            throw error
        }
        guard !Task.isCancelled, isCurrent(), requestGeneration == generation,
              savedCopyScopeRevision == copyRevision, normalizedOrigin == origin else { throw CancellationError() }
        guard response.schemaVersion == 1, response.resourceId == "payments", response.purpose == "collection",
              response.localMode == "online_required", response.items.count <= limit,
              response.nextCursor.map({ next in
                  UUID(uuidString: next) != nil &&
                  response.items.last.map { $0.id.caseInsensitiveCompare(next) == .orderedSame } == true &&
                  cursor.map { $0.caseInsensitiveCompare(next) != .orderedSame } != false
              }) ?? true else {
            throw Problem(title: "Invalid payments response", status: nil, detail: "Unexpected collection projection.")
        }
        var seen = Set<String>()
        let items: [PaymentsCollectionItem] = try response.items.map { item in
            let fields = item.fields
            let (net, overflow) = fields.amount.value.subtractingReportingOverflow(fields.refundedAmount.value)
            guard item.resourceId == "payments", UUID(uuidString: item.id) != nil,
                  item.id.caseInsensitiveCompare(fields.id) == .orderedSame,
                  UUID(uuidString: fields.invoiceID) != nil, !fields.recordedAt.isEmpty,
                  seen.insert(item.id.lowercased()).inserted,
                  fields.amount.value >= 0, fields.refundedAmount.value >= 0, !overflow,
                  net >= 0, net == fields.netAmount.value else {
                throw Problem(title: "Invalid payments response", status: nil, detail: "A payment could not be verified.")
            }
            return PaymentsCollectionItem(id: item.id, invoiceID: fields.invoiceID, status: fields.status,
                method: fields.method, recordedAt: fields.recordedAt, amount: fields.amount.value,
                refundedAmount: fields.refundedAmount.value, netAmount: fields.netAmount.value)
        }
        return PaymentsCollectionPage(items: items, nextCursor: response.nextCursor)
    }
}

import Foundation

struct StaffNotice: Decodable, Identifiable {
    let id: String
    let jobId: String
    let title: String
    let meta: String
    let at: String
    let read: Bool
}

enum StaffUnreadState: String, Decodable { case present, none, unknown }

struct StaffNoticesPage: Decodable {
    let items: [StaffNotice]
    let unreadState: StaffUnreadState
    let nextCursor: String?
}

struct StaffNoticesReadResult: Decodable {
    let marked: Int
    let nextCursor: String?
}

struct RevenueReport: Decodable {
    struct Month: Decodable, Identifiable {
        let month: String
        let revenue: Int
        let collected: Int
        var id: String { month }
    }

    struct Receivable: Decodable {
        let openInvoices: Int
        let balance: Int
        let overdueInvoices: Int
        let overdueBalance: Int
    }

    let freshness: String
    let generatedAt: String
    let periodBasis: String
    let reportVersion: Int
    let months: [Month]
    let receivable: Receivable
    let truncated: Bool
}

struct PriceBookListItem: Identifiable {
    let id: String
    let description: String
    let unit: String
    let kind: String
    let taxClassification: String
    let sellPrice: FieldMoney
    let revision: Int
    let archivedAt: String?
}

struct PriceBookPage {
    let items: [PriceBookListItem]
    let nextCursor: String?
}

/// What the price book screen says when a load fails. A decode mismatch used to surface
/// Foundation's "isn't in the correct format" sentence; people get one plain line instead.
enum PriceBookLoadError {
    static let friendly = "The price book couldn't be loaded."

    static func message(for error: Error) -> String {
        if let problem = error as? Problem {
            if problem.title == "Invalid API response" || problem.title == "Invalid Price Book response" {
                return friendly
            }
            if let detail = problem.detail, !detail.isEmpty { return detail }
            if let title = problem.title, !title.isEmpty { return title }
        }
        let raw = error.localizedDescription
        if raw.contains("correct format") || raw.contains("couldn’t be read") || raw.contains("couldn't be read") {
            return friendly
        }
        return raw
    }
}

/// `price_book.item_revisions.sell_price_amount` is `bigint`. node-pg's default int8 parser
/// puts that on the wire as a JSON string. The in-memory API and older fixtures send a number.
private struct PostgresBigint: Decodable {
    let value: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Int.self) {
            value = number
            return
        }
        let text = try container.decode(String.self)
        guard let number = Int(text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected a bigint")
        }
        value = number
    }
}

struct PriceBookItem: Decodable {
    let id: String
    let organizationId: String
    let status: String
    let currentRevision: Int
    let createdAt: String
    let updatedAt: String
    let archivedAt: String?
}

struct PriceBookRevision: Decodable {
    let organizationId: String
    let itemId: String
    let revision: Int
    let description: String
    let unit: String
    let sellPrice: FieldMoney
    let taxClassification: String
    let kind: String
    let createdAt: String
}

struct PriceBookDetail: Decodable {
    let item: PriceBookItem
    let revision: PriceBookRevision
}

private struct PriceBookQueryResponse: Decodable {
    struct Entry: Decodable {
        struct Fields: Decodable {
            let id: String
            let revision: Int
            let description: String
            let unit: String
            /// Postgres `bigint`. node-pg sends int8 as a JSON string; a JSON number still decodes.
            let sellPriceAmount: PostgresBigint
            let currency: String
            let taxClassification: String
            let kind: String
            let archivedAt: String?

            enum CodingKeys: String, CodingKey {
                case id = "price_book_items.id"
                case revision = "price_book_items.current_revision"
                case description = "price_book_items.description"
                case unit = "price_book_items.unit"
                case sellPriceAmount = "price_book_items.sell_price_amount"
                case currency = "price_book_items.currency"
                case taxClassification = "price_book_items.tax_classification"
                case kind = "price_book_items.kind"
                case archivedAt = "price_book_items.archived_at"
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
    let items: [Entry]
    let nextCursor: String?
}

@MainActor
extension APIClient {
    func staffNotices(limit: Int = 50, cursor: String? = nil) async throws -> StaffNoticesPage {
        guard (1...200).contains(limit), cursor.map({ UUID(uuidString: $0) != nil }) ?? true else {
            throw Problem(title: "Invalid notice page", status: nil, detail: "Use a UUID cursor and 1–200 items.")
        }
        return try await send("GET", "/v1/staff/notices",
                              queryItems: [URLQueryItem(name: "limit", value: String(limit))], cursor: cursor)
    }

    func markStaffNoticesRead(limit: Int = 50, cursor: String? = nil) async throws -> StaffNoticesReadResult {
        guard (1...200).contains(limit), cursor == nil || !(cursor?.isEmpty ?? true) else {
            throw Problem(title: "Invalid notice sweep", status: nil, detail: "Use 1–200 items and a nonempty continuation.")
        }
        struct Body: Encodable { let limit: Int; let cursor: String? }
        return try await send("POST", "/v1/staff/notices/read", body: Body(limit: limit, cursor: cursor))
    }

    func revenueReport() async throws -> RevenueReport {
        try await send("GET", "/v1/reports/revenue")
    }

    func priceBookItems(limit: Int = 50, cursor: String? = nil) async throws -> PriceBookPage {
        guard (1...200).contains(limit), cursor.map({ UUID(uuidString: $0) != nil }) ?? true else {
            throw Problem(title: "Invalid Price Book page", status: nil, detail: "Use a UUID cursor and 1–200 items.")
        }
        let response: PriceBookQueryResponse = try await send("GET", "/v1/query", queryItems: [
            URLQueryItem(name: "resourceId", value: "price_book_items"),
            URLQueryItem(name: "purpose", value: "collection"),
            URLQueryItem(name: "limit", value: String(limit)),
        ], cursor: cursor)
        guard response.schemaVersion == 1, response.resourceId == "price_book_items",
              response.purpose == "collection", response.localMode == "complete",
              response.items.allSatisfy({ $0.resourceId == "price_book_items" && $0.id == $0.fields.id }) else {
            throw Problem(title: "Invalid Price Book response", status: nil, detail: "Unexpected collection projection.")
        }
        return PriceBookPage(items: response.items.map { entry in
            PriceBookListItem(id: entry.id, description: entry.fields.description,
                              unit: entry.fields.unit, kind: entry.fields.kind,
                              taxClassification: entry.fields.taxClassification,
                              sellPrice: FieldMoney(amount: entry.fields.sellPriceAmount.value,
                                                    currency: entry.fields.currency),
                              revision: entry.fields.revision, archivedAt: entry.fields.archivedAt)
        }, nextCursor: response.nextCursor)
    }

    func priceBookItem(_ id: String) async throws -> PriceBookDetail {
        guard UUID(uuidString: id) != nil else {
            throw Problem(title: "Invalid Price Book item ID", status: nil, detail: id)
        }
        let detail: PriceBookDetail = try await send("GET", "/v1/price-book/items/\(id)")
        guard detail.item.id == id, detail.revision.itemId == id,
              detail.item.currentRevision == detail.revision.revision else {
            throw Problem(title: "Invalid Price Book detail", status: nil, detail: "Current revision does not match the item.")
        }
        return detail
    }
}

/// The editable content of a Price Book item; every save writes a new revision.
struct PriceBookContent: Encodable, Equatable {
    var description: String
    var unit: String
    var sellPrice: FieldMoney
    var taxClassification: String
    var kind: String

    static let kinds = ["service", "labor", "material", "assembly"]
    static let taxClassifications = ["taxable", "non_taxable"]
}

extension APIClient {
    func createPriceBookItem(_ content: PriceBookContent, idempotencyKey: String) async throws -> PriceBookItem {
        struct Body: Encodable {
            let idempotencyKey: String
            let content: PriceBookContent
            func encode(to encoder: Encoder) throws {
                try content.encode(to: encoder)
                var c = encoder.container(keyedBy: Key.self)
                try c.encode(idempotencyKey, forKey: .idempotencyKey)
            }
            enum Key: String, CodingKey { case idempotencyKey }
        }
        return try await send("POST", "/v1/price-book/items", body: Body(idempotencyKey: idempotencyKey, content: content))
    }

    /// The item id comes from the route only; the server refuses it in the body.
    func revisePriceBookItem(_ id: String, expectedRevision: Int, content: PriceBookContent) async throws -> PriceBookItem {
        struct Body: Encodable {
            let expectedRevision: Int
            let content: PriceBookContent
            func encode(to encoder: Encoder) throws {
                try content.encode(to: encoder)
                var c = encoder.container(keyedBy: Key.self)
                try c.encode(expectedRevision, forKey: .expectedRevision)
            }
            enum Key: String, CodingKey { case expectedRevision }
        }
        guard UUID(uuidString: id) != nil else { throw Problem(title: "Invalid Price Book item ID", status: nil, detail: id) }
        return try await send("POST", "/v1/price-book/items/\(id)/revise", body: Body(expectedRevision: expectedRevision, content: content))
    }

    func archivePriceBookItem(_ id: String, expectedRevision: Int) async throws -> PriceBookItem {
        struct Body: Encodable { let expectedRevision: Int }
        guard UUID(uuidString: id) != nil else { throw Problem(title: "Invalid Price Book item ID", status: nil, detail: id) }
        return try await send("POST", "/v1/price-book/items/\(id)/archive", body: Body(expectedRevision: expectedRevision))
    }
}

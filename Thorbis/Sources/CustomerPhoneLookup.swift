import Foundation

/// The exact-phone duplicate check at customer intake (web customer-phone-lookup.ts).
///
/// `customers.phone` only offers `contains`, so the server page is a superset of the exact match;
/// only exact digit equality counts as found, and an incomplete page without a match stays
/// unknown rather than "no such customer".
enum CustomerPhoneLookup: Equatable {
    case notApplicable
    case found(Customer)
    case notFound
    case unknown

    static let limit = 25

    static func digits(_ phone: String) -> String { phone.filter(\.isNumber) }

    static func classify(rows: [(id: String, name: String, phone: String)], complete: Bool, phone: String) -> CustomerPhoneLookup {
        let wanted = digits(phone)
        guard wanted.count >= 7 else { return .notApplicable }
        if let row = rows.first(where: { digits($0.phone) == wanted }) {
            return .found(Customer(id: row.id, name: row.name, archived: nil, createdAt: nil))
        }
        return complete ? .notFound : .unknown
    }
}

private struct CustomerPhoneQueryResponse: Decodable {
    struct Entry: Decodable {
        struct Fields: Decodable {
            let name: String?
            let phone: String?
            enum CodingKeys: String, CodingKey {
                case name = "customers.name"
                case phone = "customers.phone"
            }
        }
        let id: String
        let resourceId: String
        let label: String?
        let fields: Fields
    }
    let resourceId: String
    let items: [Entry]
    let nextCursor: String?
}

@MainActor
extension APIClient {
    /// One bounded, server-predicated page through the Query Platform; never a directory read.
    func lookupCustomer(phone: String) async throws -> CustomerPhoneLookup {
        let wanted = CustomerPhoneLookup.digits(phone)
        guard wanted.count >= 7 else { return .notApplicable }
        let filter = #"{"schemaVersion":1,"root":{"type":"condition","field":"customers.phone","operator":"contains","value":"\#(wanted)"}}"#
        let response: CustomerPhoneQueryResponse = try await send("GET", "/v1/query", queryItems: [
            URLQueryItem(name: "resourceId", value: "customers"),
            URLQueryItem(name: "limit", value: String(CustomerPhoneLookup.limit)),
            URLQueryItem(name: "filter", value: filter),
        ])
        guard response.resourceId == "customers", response.items.allSatisfy({ $0.resourceId == "customers" }) else {
            return .unknown
        }
        let rows = response.items.map { item in
            (id: item.id, name: item.label.flatMap { $0.isEmpty ? nil : $0 } ?? item.fields.name ?? "Customer", phone: item.fields.phone ?? "")
        }
        return CustomerPhoneLookup.classify(rows: rows, complete: response.nextCursor == nil, phone: phone)
    }
}

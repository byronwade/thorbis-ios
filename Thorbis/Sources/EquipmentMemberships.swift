import Foundation

// Equipment and memberships (Thorbis-TanStack organization equipment/membership routes).
// Every read degrades quietly: a 403 (technicians, until assigned-scope customer reads exist)
// or a 404 (an older server) hides the section instead of showing an error.

struct EquipmentRecord: Codable, Identifiable, Hashable {
    let id: String
    let customerId: String
    var locationId: String?
    var name: String
    var kind: String?
    var brand: String?
    var model: String?
    var serialNumber: String?
    var installedOn: String?
    var warrantyExpiresOn: String?
    var notes: String?
    let createdAt: String
    let updatedAt: String
    /// Present on the company-wide list only.
    var customerName: String? = nil
    var locationLabel: String? = nil
    var locationAddress: String? = nil

    var detail: String {
        [brand, model, serialNumber.map { "SN \($0)" }].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var warrantyEnd: Date? { warrantyExpiresOn.flatMap(EquipmentRecord.day) }

    static func day(_ raw: String) -> Date? {
        let format = DateFormatter()
        format.calendar = Calendar(identifier: .gregorian)
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd"
        return format.date(from: raw)
    }

    static func dayString(_ date: Date) -> String {
        let format = DateFormatter()
        format.calendar = Calendar(identifier: .gregorian)
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd"
        return format.string(from: date)
    }
}

/// The fields a person edits. Nil means "leave out"; on update the server leaves absent fields alone.
struct EquipmentInput: Encodable, Equatable {
    var name: String
    var locationId: String?
    var kind: String?
    var brand: String?
    var model: String?
    var serialNumber: String?
    var installedOn: String?
    var warrantyExpiresOn: String?
    var notes: String?

    /// Empty strings become null so clearing a field in the form clears it on the server.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        func put(_ value: String?, _ key: CodingKeys) throws {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            try c.encode(trimmed?.isEmpty == false ? trimmed : nil, forKey: key)
        }
        try put(locationId, .locationId)
        try put(kind, .kind)
        try put(brand, .brand)
        try put(model, .model)
        try put(serialNumber, .serialNumber)
        try put(installedOn, .installedOn)
        try put(warrantyExpiresOn, .warrantyExpiresOn)
        try put(notes, .notes)
    }
    private enum CodingKeys: String, CodingKey { case name, locationId, kind, brand, model, serialNumber, installedOn, warrantyExpiresOn, notes }
}

struct MembershipPlan: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let kind: String
    let cadence: String?
    let visitsPerYear: Int?
    let price: Int?
    let billingFrequency: String?
    let discountPercent: Int
    let description: String?
    let archived: Bool
}

struct MembershipRecord: Codable, Identifiable, Hashable {
    let id: String
    let customerId: String
    let planId: String?
    let name: String
    let kind: String
    let cadence: String?
    let startsOn: String?
    let renewsOn: String?
    let status: String
    let discountPercent: Int
    let notes: String?
    var customerName: String? = nil
    var planName: String? = nil
}

struct MemberPricing: Codable, Hashable {
    struct Membership: Codable, Hashable { let id: String; let name: String; let renewsOn: String? }
    let isMember: Bool
    let discountPercent: Int
    let membership: Membership?

    /// The server's rule: round(unitPrice * (100 - discount) / 100).
    func memberPrice(_ cents: Int) -> Int {
        Int((Double(cents) * Double(100 - discountPercent) / 100).rounded())
    }
}

private struct ItemsPage<T: Decodable>: Decodable { let items: [T] }

extension APIClient {
    func customerEquipment(_ customerID: String) async throws -> [EquipmentRecord] {
        let page: ItemsPage<EquipmentRecord> = try await send("GET", "/v1/customers/\(try uuid(customerID))/equipment")
        return page.items
    }

    func allEquipment() async throws -> [EquipmentRecord] {
        let page: ItemsPage<EquipmentRecord> = try await send("GET", "/v1/equipment")
        return page.items
    }

    func addEquipment(_ customerID: String, _ input: EquipmentInput) async throws -> EquipmentRecord {
        try await send("POST", "/v1/customers/\(try uuid(customerID))/equipment", body: input)
    }

    func updateEquipment(_ customerID: String, equipmentID: String, _ input: EquipmentInput) async throws -> EquipmentRecord {
        try await send("POST", "/v1/customers/\(try uuid(customerID))/equipment/\(try uuid(equipmentID))", body: input)
    }

    func removeEquipment(_ customerID: String, equipmentID: String) async throws {
        let _: EmptyResponse = try await send("POST", "/v1/customers/\(try uuid(customerID))/equipment/\(try uuid(equipmentID))/remove")
    }

    func membershipPlans() async throws -> [MembershipPlan] {
        let page: ItemsPage<MembershipPlan> = try await send("GET", "/v1/membership-plans")
        return page.items.filter { !$0.archived }
    }

    func allMemberships() async throws -> [MembershipRecord] {
        let page: ItemsPage<MembershipRecord> = try await send("GET", "/v1/memberships")
        return page.items
    }

    func customerMemberships(_ customerID: String) async throws -> [MembershipRecord] {
        let page: ItemsPage<MembershipRecord> = try await send("GET", "/v1/customers/\(try uuid(customerID))/memberships")
        return page.items
    }

    func enroll(_ customerID: String, planID: String, startsOn: Date) async throws -> MembershipRecord {
        struct Body: Encodable { let planId: String; let startsOn: String }
        return try await send("POST", "/v1/customers/\(try uuid(customerID))/memberships",
                              body: Body(planId: try uuid(planID), startsOn: EquipmentRecord.dayString(startsOn)))
    }

    func cancelMembership(_ customerID: String, membershipID: String) async throws -> MembershipRecord {
        struct Body: Encodable { let status = "cancelled" }
        return try await send("POST", "/v1/customers/\(try uuid(customerID))/memberships/\(try uuid(membershipID))", body: Body())
    }

    func memberPricing(_ customerID: String) async throws -> MemberPricing {
        try await send("GET", "/v1/customers/\(try uuid(customerID))/member-pricing")
    }

    private func uuid(_ id: String) throws -> String {
        guard UUID(uuidString: id) != nil else { throw Problem(title: "Invalid ID", status: nil, detail: id) }
        return id.lowercased()
    }
}

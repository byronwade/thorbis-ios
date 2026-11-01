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
    /// Absent on a job's service context.
    var createdAt: String? = nil
    var updatedAt: String? = nil
    /// Present on the company-wide list only.
    var customerName: String? = nil
    var locationLabel: String? = nil
    var locationAddress: String? = nil

    var detail: String {
        [brand, model, serialNumber.map { "SN \($0)" }].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var warrantyEnd: Date? { warrantyExpiresOn.flatMap(EquipmentRecord.day) }

    static func day(_ raw: String) -> Date? { dayFormat.date(from: raw) }

    static func dayString(_ date: Date) -> String { dayFormat.string(from: date) }

    /// Made once: `warrantyEnd` is read per row on every render.
    private static let dayFormat: DateFormatter = {
        let format = DateFormatter()
        format.calendar = Calendar(identifier: .gregorian)
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd"
        return format
    }()
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

/// `GET /v1/jobs/{id}/service-context` (job.view): the equipment and member pricing a tech needs
/// at the door, readable by anyone assigned to the job. Units at the job's site come first.
struct JobServiceContext: Decodable, Hashable {
    struct Unit: Decodable, Hashable {
        let id: String
        let name: String
        var locationId: String?
        var kind: String?
        var brand: String?
        var model: String?
        var serialNumber: String?
        var installedOn: String?
        var warrantyExpiresOn: String?
        var notes: String?
    }

    let jobId: String
    let customerId: String
    var locationId: String?
    let equipment: [Unit]
    let memberPricing: MemberPricing

    var equipmentRecords: [EquipmentRecord] {
        equipment.map {
            EquipmentRecord(id: $0.id, customerId: customerId, locationId: $0.locationId, name: $0.name, kind: $0.kind,
                            brand: $0.brand, model: $0.model, serialNumber: $0.serialNumber, installedOn: $0.installedOn,
                            warrantyExpiresOn: $0.warrantyExpiresOn, notes: $0.notes)
        }
    }

    /// The active membership in the shape the membership row shows.
    var memberships: [MembershipRecord] {
        guard memberPricing.isMember, let membership = memberPricing.membership else { return [] }
        return [MembershipRecord(id: membership.id, customerId: customerId, planId: nil, name: membership.name, kind: "membership",
                                 cadence: nil, startsOn: nil, renewsOn: membership.renewsOn, status: "active",
                                 discountPercent: memberPricing.discountPercent, notes: nil)]
    }
}

/// The job's equipment and membership sections both read the context; one request serves both.
@MainActor
enum JobServiceContextLoader {
    private static var inFlight: [String: Task<JobServiceContext, Error>] = [:]

    static func load(_ jobID: String, api: APIClient) async throws -> JobServiceContext {
        if let task = inFlight[jobID] { return try await task.value }
        let task = Task { try await api.jobServiceContext(jobID) }
        inFlight[jobID] = task
        defer { inFlight[jobID] = nil }
        return try await task.value
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

    func jobServiceContext(_ jobID: String) async throws -> JobServiceContext {
        try await send("GET", "/v1/jobs/\(try uuid(jobID))/service-context")
    }

    func memberPricing(_ customerID: String) async throws -> MemberPricing {
        try await send("GET", "/v1/customers/\(try uuid(customerID))/member-pricing")
    }

    private func uuid(_ id: String) throws -> String {
        guard UUID(uuidString: id) != nil else { throw Problem(title: "Invalid ID", status: nil, detail: id) }
        return id.lowercased()
    }
}

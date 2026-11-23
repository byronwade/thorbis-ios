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

/// The fields a person edits. Encoded as it stands it is an edit: an emptied field is sent as
/// null, which clears it on the server. A new unit goes out as `NewEquipmentBody` instead.
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
        try encode(to: encoder, emptyFieldsAsNull: true)
    }

    fileprivate func encode(to encoder: Encoder, emptyFieldsAsNull: Bool) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        func put(_ value: String?, _ key: CodingKeys) throws {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty {
                try c.encode(trimmed, forKey: key)
            } else if emptyFieldsAsNull {
                try c.encodeNil(forKey: key)
            }
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

/// A new unit on the wire. The server refuses null when adding equipment, so empty fields are
/// left out; only an edit may send null.
private struct NewEquipmentBody: Encodable {
    let input: EquipmentInput
    func encode(to encoder: Encoder) throws {
        try input.encode(to: encoder, emptyFieldsAsNull: false)
    }
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
    /// The one place the membership covers, when it covers one.
    var locationId: String? = nil
}

/// What a person fills in for a plan the company sells. `price` is cents, like every money value.
struct MembershipPlanInput: Equatable {
    var name: String
    var kind = "maintenance"
    var cadence: String?
    var visitsPerYear: Int?
    var price: Int?
    var billingFrequency: String?
    var discountPercent = 0
    var description: String?
}

/// A plan on the wire. A new plan leaves empty fields out (the server refuses null there); an
/// edit sends null for an emptied field so the server clears it.
struct MembershipPlanRequest: Encodable {
    enum Mode { case create, update }
    let input: MembershipPlanInput
    let mode: Mode

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(input.name.trimmingCharacters(in: .whitespacesAndNewlines), forKey: .name)
        try c.encode(input.kind, forKey: .kind)
        func put<T: Encodable>(_ value: T?, _ key: CodingKeys) throws {
            if let value { try c.encode(value, forKey: key) } else if mode == .update { try c.encodeNil(forKey: key) }
        }
        try put(MembershipInput.text(input.cadence), .cadence)
        try put(input.visitsPerYear, .visitsPerYear)
        try put(input.price, .price)
        try put(MembershipInput.text(input.billingFrequency), .billingFrequency)
        try c.encode(input.discountPercent, forKey: .discountPercent)
        try put(MembershipInput.text(input.description), .description)
    }
    private enum CodingKeys: String, CodingKey { case name, kind, cadence, visitsPerYear, price, billingFrequency, discountPercent, description }
}

/// A customer's membership as edited. Days are "yyyy-MM-dd"; an emptied field is sent as null so
/// the server clears it. Name, kind and status are always sent. The percent off is sent only when
/// it differs from the one the membership was saved with: left out, the server keeps the stored
/// percent, and a new one needs the company settings permission (organization.settings.edit).
struct MembershipInput: Encodable, Equatable {
    var locationId: String?
    var name: String
    var kind: String
    var cadence: String?
    var startsOn: String?
    var renewsOn: String?
    var status: String
    var discountPercent: Int
    /// The percent off the membership was saved with. Never sent.
    var originalDiscountPercent: Int
    var notes: String?

    init(_ record: MembershipRecord) {
        locationId = record.locationId
        name = record.name
        kind = record.kind
        cadence = record.cadence
        startsOn = record.startsOn
        renewsOn = record.renewsOn
        status = record.status
        discountPercent = record.discountPercent
        originalDiscountPercent = record.discountPercent
        notes = record.notes
    }

    /// True when this edit carries a new percent off.
    var discountChanged: Bool { discountPercent != originalDiscountPercent }

    /// Trimmed, or nil when nothing is left.
    static func text(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.text(locationId)?.lowercased(), forKey: .locationId)
        try c.encode(name.trimmingCharacters(in: .whitespacesAndNewlines), forKey: .name)
        try c.encode(kind, forKey: .kind)
        try c.encode(Self.text(cadence), forKey: .cadence)
        try c.encode(Self.text(startsOn), forKey: .startsOn)
        try c.encode(Self.text(renewsOn), forKey: .renewsOn)
        try c.encode(status, forKey: .status)
        if discountChanged { try c.encode(discountPercent, forKey: .discountPercent) }
        try c.encode(Self.text(notes), forKey: .notes)
    }
    private enum CodingKeys: String, CodingKey { case locationId, name, kind, cadence, startsOn, renewsOn, status, discountPercent, notes }
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

    /// The server charges the member price only on an estimate's price book line sent at the list
    /// price it came from. A typed line, a credit and an edited price are charged as saved. A line
    /// the server already charged at the member price is saved below its list price, with
    /// `unit_price` marked overridden, so it is not discounted a second time.
    static func chargesMemberPrice(_ line: FieldLine) -> Bool {
        guard let source = line.source, source.kind == "price_book", line.unitPrice.amount > 0,
              source.overriddenFields?.contains("unit_price") != true,
              let list = source.originalUnitPrice else { return false }
        return list.amount == line.unitPrice.amount && list.currency == line.unitPrice.currency
    }

    /// What a member pays for saved estimate lines, for the hint under a total: nil when this is
    /// not a member, or when no line would be charged the member price.
    func memberTotal(of lines: [FieldLine]) -> Int? {
        guard isMember, discountPercent > 0, lines.contains(where: { Self.chargesMemberPrice($0) }) else { return nil }
        return lines.reduce(0) { sum, line in
            let price = Self.chargesMemberPrice(line) ? memberPrice(line.unitPrice.amount) : line.unitPrice.amount
            return sum.addingClamped(line.quantity, times: price)
        }
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

    /// The job reads its equipment and member pricing from the service context (anyone on the job
    /// may). The customer's own equipment and member-pricing reads are the fallback only for a
    /// server without the route (404) or when nothing answered at all (offline: a saved copy may).
    /// A refusal or any other answer is final: the customer reads would be refused the same way.
    nonisolated static func fallsBackToCustomerReads(after error: Error) -> Bool {
        if error is CancellationError { return false }
        guard let problem = error as? Problem, let status = problem.status else { return true }
        return status == 404
    }
}

private struct ItemsPage<T: Decodable>: Decodable {
    let items: [T]
    /// Set by the company-wide books while more rows remain. A customer's own list arrives whole.
    let nextCursor: String?
}

extension APIClient {
    /// Every page of a company-wide book. The server sends 200 rows a page and a `nextCursor`
    /// while more remain, so one read is not the whole book.
    private func allBookPages<T: Decodable>(_ path: String) async throws -> [T] {
        let generation = requestGeneration
        var items: [T] = []
        var cursor: String?
        var seen = Set<String>()
        repeat {
            try Task.checkCancellation()
            guard generation == requestGeneration else { throw CancellationError() }
            let page: ItemsPage<T> = try await send("GET", path, cursor: cursor)
            items.append(contentsOf: page.items)
            cursor = page.nextCursor
            if let cursor, cursor.isEmpty || !seen.insert(cursor).inserted {
                throw Problem(title: "Pagination cursor loop", status: nil, detail: "Repeated or empty cursor")
            }
        } while cursor != nil
        return items
    }

    func customerEquipment(_ customerID: String) async throws -> [EquipmentRecord] {
        let page: ItemsPage<EquipmentRecord> = try await send("GET", "/v1/customers/\(try uuid(customerID))/equipment")
        return page.items
    }

    func allEquipment() async throws -> [EquipmentRecord] {
        try await allBookPages("/v1/equipment")
    }

    func addEquipment(_ customerID: String, _ input: EquipmentInput) async throws -> EquipmentRecord {
        try await send("POST", "/v1/customers/\(try uuid(customerID))/equipment", body: NewEquipmentBody(input: input))
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

    /// `POST /v1/membership-plans` (organization.settings.edit).
    func createMembershipPlan(_ input: MembershipPlanInput) async throws -> MembershipPlan {
        try await send("POST", "/v1/membership-plans", body: MembershipPlanRequest(input: input, mode: .create))
    }

    /// `POST /v1/membership-plans/{planId}` (organization.settings.edit); null clears a field.
    func updateMembershipPlan(_ planID: String, _ input: MembershipPlanInput) async throws -> MembershipPlan {
        try await send("POST", "/v1/membership-plans/\(try uuid(planID))", body: MembershipPlanRequest(input: input, mode: .update))
    }

    /// An archived plan stays on the memberships already sold and is no longer offered.
    func archiveMembershipPlan(_ planID: String) async throws -> MembershipPlan {
        struct Body: Encodable { let archived = true }
        return try await send("POST", "/v1/membership-plans/\(try uuid(planID))", body: Body())
    }

    func allMemberships() async throws -> [MembershipRecord] {
        try await allBookPages("/v1/memberships")
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

    /// `POST /v1/customers/{id}/memberships/{membershipId}` (customer.edit) with every edited field.
    func updateMembership(_ customerID: String, membershipID: String, _ input: MembershipInput) async throws -> MembershipRecord {
        try await send("POST", "/v1/customers/\(try uuid(customerID))/memberships/\(try uuid(membershipID))", body: input)
    }

    /// Takes a membership off the customer for good. For one added by mistake; Cancel ends a real one.
    func removeMembership(_ customerID: String, membershipID: String) async throws {
        let _: EmptyResponse = try await send("POST", "/v1/customers/\(try uuid(customerID))/memberships/\(try uuid(membershipID))/remove")
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

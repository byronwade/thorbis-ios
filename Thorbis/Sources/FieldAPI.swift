import Foundation

// The API's full field records are separate from the lightweight types used by
// the original schedule prototype. Missing domain fields are omitted in JSON.
struct JobRecord: Codable, Identifiable, Hashable {
    let id: String
    let organizationId: String
    let customerId: String
    let estimateId: String?
    let estimateRevisionNumber: Int?
    let locationId: String?
    let teamId: String?
    let title: String
    let notes: String?
    let status: String
    let assignedToUserId: String?
    let scheduledFor: String?
    let createdAt: String
    let updatedAt: String
    let dispatchedAt: String?
    let enRouteAt: String?
    let arrivedAt: String?
    let arrivalMethod: String?
    let startedAt: String?
    let pausedAt: String?
    let pauseReason: String?
    let pauseNextAction: String?
    let pauseOwnerUserId: String?
    let pauseCycleAuditId: String?
    let lastResumeAuditId: String?
    let scheduleCycleAuditId: String?
    let completedAt: String?
    let canceledAt: String?
    /// Added by GET /v1/jobs/{id}; list items do not include it.
    let allowedTransitions: [String]?
}

struct FieldJobCreate: Encodable {
    let customerId: String
    let title: String
    let locationId: String?
    let teamId: String?
    let notes: String?

    init(customerId: String, title: String, locationId: String? = nil,
         teamId: String? = nil, notes: String? = nil) {
        self.customerId = customerId
        self.title = title
        self.locationId = locationId
        self.teamId = teamId
        self.notes = notes
    }
}

struct CustomerRecord: Codable, Identifiable, Hashable {
    let id: String
    let organizationId: String
    let name: String
    let locationId: String?
    let email: String?
    let phone: String?
    let address: String?
    let accountType: String?
    let industry: String?
    let referralSource: String?
    let website: String?
    let preferredContact: String?
    let billingTerms: String?
    let creditLimit: Int?
    let taxExempt: Bool?
    let taxExemptId: String?
    let archived: Bool
    let archiveCycleAuditId: String?
    let createdAt: String
    let updatedAt: String
}

struct CustomerContactRecord: Codable, Identifiable, Hashable {
    let id: String
    let organizationId: String
    let customerId: String
    let name: String
    let role: String?
    let email: String?
    let phone: String?
    let primary: Bool
    let createdAt: String
    let updatedAt: String
}

struct FieldCoordinates: Codable, Hashable {
    let latitude: Double
    let longitude: Double
}

struct ServiceLocationRecord: Codable, Identifiable, Hashable {
    let id: String
    let organizationId: String
    let customerId: String
    let label: String
    let kind: String
    let address: String
    let notes: String?
    let coordinates: FieldCoordinates?
    let gateCode: String?
    let alarmCode: String?
    let dogOnSite: String?
    let parking: String?
    let createdAt: String
    let updatedAt: String
}

struct ServiceLocationCollectionState {
    private(set) var locations: [ServiceLocationRecord] = []
    private var generation = 0

    mutating func beginLoad() -> Int {
        generation += 1
        return generation
    }

    @discardableResult
    mutating func receive(_ locations: [ServiceLocationRecord], generation: Int) -> Bool {
        guard generation == self.generation else { return false }
        self.locations = locations
        return true
    }

    mutating func save(_ location: ServiceLocationRecord) {
        generation += 1
        if let index = locations.firstIndex(where: { $0.id == location.id }) {
            locations[index] = location
        } else {
            locations.append(location)
        }
    }

    mutating func remove(id: String) {
        generation += 1
        locations.removeAll { $0.id == id }
    }
}

struct JobNoteRecord: Codable, Identifiable, Hashable {
    let id: String
    let organizationId: String
    let jobId: String
    let authorUserId: String
    let body: String
    let createdAt: String
}

/// Legacy photos are raw-byte uploads; this is only the metadata list record.
struct JobPhotoRecord: Codable, Identifiable, Hashable {
    let id: String
    let organizationId: String
    let jobId: String
    let authorUserId: String
    let contentType: String
    let byteSize: Int
    let storageKey: String
    let createdAt: String
}

struct FieldContactCreate: Encodable {
    let name: String
    let role: String?
    let email: String?
    let phone: String?
    let primary: Bool?

    init(name: String, role: String? = nil, email: String? = nil,
         phone: String? = nil, primary: Bool? = nil) {
        self.name = name
        self.role = role
        self.email = email
        self.phone = phone
        self.primary = primary
    }
}

enum FieldContactPatch<Value> {
    case unchanged
    case clear
    case value(Value)
}

struct FieldContactUpdate: Encodable {
    let name: String?
    let role: FieldContactPatch<String>
    let email: FieldContactPatch<String>
    let phone: FieldContactPatch<String>
    let primary: Bool?

    init(
        name: String? = nil,
        role: FieldContactPatch<String> = .unchanged,
        email: FieldContactPatch<String> = .unchanged,
        phone: FieldContactPatch<String> = .unchanged,
        primary: Bool? = nil
    ) {
        self.name = name
        self.role = role
        self.email = email
        self.phone = phone
        self.primary = primary
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try Self.encode(role, forKey: .role, in: &container)
        try Self.encode(email, forKey: .email, in: &container)
        try Self.encode(phone, forKey: .phone, in: &container)
        if let primary { try container.encode(primary, forKey: .primary) }
    }

    private enum CodingKeys: String, CodingKey {
        case name, role, email, phone, primary
    }

    private static func encode<Value: Encodable>(
        _ value: FieldContactPatch<Value>,
        forKey key: CodingKeys,
        in container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        switch value {
        case .unchanged: break
        case .clear: try container.encodeNil(forKey: key)
        case .value(let value): try container.encode(value, forKey: key)
        }
    }
}

struct CustomerContactDraft {
    let name: String
    let role: String?
    let email: String?
    let phone: String?

    func makeRequest() -> FieldContactCreate? {
        guard let name = Self.cleaned(name) else { return nil }
        return FieldContactCreate(
            name: name,
            role: Self.cleaned(role),
            email: Self.cleaned(email),
            phone: Self.cleaned(phone)
        )
    }

    func makeUpdateRequest() -> FieldContactUpdate? {
        guard let name = Self.cleaned(name) else { return nil }
        return FieldContactUpdate(
            name: name,
            role: Self.updateValue(role),
            email: Self.updateValue(email),
            phone: Self.updateValue(phone)
        )
    }

    private static func updateValue(_ value: String?) -> FieldContactPatch<String> {
        guard let cleaned = cleaned(value) else { return .clear }
        return .value(cleaned)
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

struct CustomerContactCollectionState {
    private(set) var contacts: [CustomerContactRecord] = []
    private(set) var isLoaded = false
    private var generation = 0

    mutating func beginLoading() -> Int {
        generation += 1
        isLoaded = false
        return generation
    }

    @discardableResult
    mutating func receive(_ contacts: [CustomerContactRecord], generation: Int) -> Bool {
        guard generation == self.generation else { return false }
        self.contacts = contacts
        isLoaded = true
        return true
    }

    mutating func save(_ contact: CustomerContactRecord) {
        generation += 1
        if contact.primary {
            for index in contacts.indices where contacts[index].id != contact.id {
                contacts[index] = Self.withPrimary(contacts[index], false)
            }
        }
        if let index = contacts.firstIndex(where: { $0.id == contact.id }) {
            contacts[index] = contact
        } else {
            contacts.append(contact)
        }
        isLoaded = true
    }

    mutating func remove(id: String) {
        generation += 1
        let removedPrimary = contacts.first(where: { $0.id == id })?.primary == true
        let promotedID = removedPrimary
            ? contacts.filter { $0.id != id }.min {
                (JobFiltering.date($0.createdAt) ?? .distantFuture) < (JobFiltering.date($1.createdAt) ?? .distantFuture)
            }?.id
            : nil
        contacts.removeAll { $0.id == id }
        if let promotedID {
            for index in contacts.indices {
                contacts[index] = Self.withPrimary(contacts[index], contacts[index].id == promotedID)
            }
        }
        isLoaded = true
    }

    private static func withPrimary(_ contact: CustomerContactRecord, _ primary: Bool) -> CustomerContactRecord {
        CustomerContactRecord(
            id: contact.id,
            organizationId: contact.organizationId,
            customerId: contact.customerId,
            name: contact.name,
            role: contact.role,
            email: contact.email,
            phone: contact.phone,
            primary: primary,
            createdAt: contact.createdAt,
            updatedAt: contact.updatedAt
        )
    }
}

struct FieldLocationCreate: Encodable {
    let label: String
    let kind: String
    let address: String
    let notes: String?
    let coordinates: FieldCoordinates?
    let gateCode: String?
    let alarmCode: String?
    let dogOnSite: String?
    let parking: String?

    init(label: String, kind: String, address: String, notes: String? = nil,
         coordinates: FieldCoordinates? = nil, gateCode: String? = nil,
         alarmCode: String? = nil, dogOnSite: String? = nil, parking: String? = nil) {
        self.label = label
        self.kind = kind
        self.address = address
        self.notes = notes
        self.coordinates = coordinates
        self.gateCode = gateCode
        self.alarmCode = alarmCode
        self.dogOnSite = dogOnSite
        self.parking = parking
    }
}

struct FieldLocationUpdate: Encodable {
    let label: String
    let kind: String
    let address: String
    let notes: String?
    let coordinates: FieldCoordinates?
    let gateCode: String?
    let alarmCode: String?
    let dogOnSite: String?
    let parking: String?

    private enum CodingKeys: String, CodingKey {
        case label, kind, address, notes, coordinates, gateCode, alarmCode, dogOnSite, parking
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(label, forKey: .label)
        try values.encode(kind, forKey: .kind)
        try values.encode(address, forKey: .address)
        try values.encode(notes, forKey: .notes)
        try values.encode(coordinates, forKey: .coordinates)
        try values.encode(gateCode, forKey: .gateCode)
        try values.encode(alarmCode, forKey: .alarmCode)
        try values.encode(dogOnSite, forKey: .dogOnSite)
        try values.encode(parking, forKey: .parking)
    }
}

enum ServiceLocationDraftError: LocalizedError, Equatable {
    case missingLabel
    case missingAddress
    case incompleteCoordinates
    case invalidCoordinates

    var errorDescription: String? {
        switch self {
        case .missingLabel: "Enter a location label."
        case .missingAddress: "Enter a location address."
        case .incompleteCoordinates: "Enter both latitude and longitude, or clear both."
        case .invalidCoordinates: "Enter valid coordinates (latitude −90 to 90, longitude −180 to 180)."
        }
    }
}

struct ServiceLocationDraft {
    var label: String
    var kind: String
    var address: String
    var notes: String
    var latitude: String
    var longitude: String
    var gateCode: String
    var alarmCode: String
    var dogOnSite: String
    var parking: String

    init(label: String = "", kind: String = "service", address: String = "", notes: String = "",
         latitude: String = "", longitude: String = "", gateCode: String = "", alarmCode: String = "",
         dogOnSite: String = "", parking: String = "") {
        self.label = label
        self.kind = kind
        self.address = address
        self.notes = notes
        self.latitude = latitude
        self.longitude = longitude
        self.gateCode = gateCode
        self.alarmCode = alarmCode
        self.dogOnSite = dogOnSite
        self.parking = parking
    }

    func makeCreateRequest() throws -> FieldLocationCreate {
        let values = try cleanedValues()
        return FieldLocationCreate(
            label: values.label, kind: values.kind, address: values.address, notes: values.notes,
            coordinates: values.coordinates, gateCode: values.gateCode, alarmCode: values.alarmCode,
            dogOnSite: values.dogOnSite, parking: values.parking
        )
    }

    func makeUpdateRequest() throws -> FieldLocationUpdate {
        let values = try cleanedValues()
        return FieldLocationUpdate(
            label: values.label, kind: values.kind, address: values.address, notes: values.notes,
            coordinates: values.coordinates, gateCode: values.gateCode, alarmCode: values.alarmCode,
            dogOnSite: values.dogOnSite, parking: values.parking
        )
    }

    private func cleanedValues() throws -> (
        label: String, kind: String, address: String, notes: String?, coordinates: FieldCoordinates?,
        gateCode: String?, alarmCode: String?, dogOnSite: String?, parking: String?
    ) {
        guard let label = Self.cleaned(label) else { throw ServiceLocationDraftError.missingLabel }
        guard let address = Self.cleaned(address) else { throw ServiceLocationDraftError.missingAddress }
        return (
            label: label,
            kind: Self.cleaned(kind) ?? "service",
            address: address,
            notes: Self.cleaned(notes),
            coordinates: try parsedCoordinates(),
            gateCode: Self.cleaned(gateCode),
            alarmCode: Self.cleaned(alarmCode),
            dogOnSite: Self.cleaned(dogOnSite),
            parking: Self.cleaned(parking)
        )
    }

    private func parsedCoordinates() throws -> FieldCoordinates? {
        let latitudeValue = latitude.trimmingCharacters(in: .whitespacesAndNewlines)
        let longitudeValue = longitude.trimmingCharacters(in: .whitespacesAndNewlines)
        if latitudeValue.isEmpty && longitudeValue.isEmpty { return nil }
        guard !latitudeValue.isEmpty, !longitudeValue.isEmpty else {
            throw ServiceLocationDraftError.incompleteCoordinates
        }
        guard let latitude = Double(latitudeValue), let longitude = Double(longitudeValue),
              latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            throw ServiceLocationDraftError.invalidCoordinates
        }
        return FieldCoordinates(latitude: latitude, longitude: longitude)
    }

    private static func cleaned(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

struct FieldMoney: Codable, Hashable {
    let amount: Int
    let currency: String
}

/// Stored line provenance may contain additional server-derived fields.
struct FieldLineSource: Codable, Hashable {
    let kind: String
    let priceBookItemId: String?
    let priceBookRevision: Int?
    let originalDescription: String?
    let originalUnitPrice: FieldMoney?
    let addedByUserId: String?
    let capturedAt: String?
    let overriddenFields: [String]?
    let estimateId: String?
    let estimateRevisionNumber: Int?
    let estimateLineId: String?
}

struct FieldLine: Codable, Identifiable, Hashable {
    let id: String
    let description: String
    let quantity: Int
    let unitPrice: FieldMoney
    let source: FieldLineSource?
}

struct FieldEstimateOption: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let description: String
    let lines: [FieldLine]
    let totalAmount: Int
    let currency: String
}

struct EstimateRecord: Codable, Identifiable, Hashable {
    let id: String
    let organizationId: String
    let customerId: String
    let createdByUserId: String
    let locationId: String?
    let status: String
    let currentRevisionNumber: Int?
    let title: String
    let lines: [FieldLine]
    let options: [FieldEstimateOption]?
    let createdAt: String
    let updatedAt: String
    let sentAt: String?
    let approvedAt: String?
    let declinedAt: String?
}

struct FieldPhysicalServiceEvidence: Codable, Hashable {
    let id: String
    let performedAt: String
    let description: String
}

struct InvoiceRecord: Codable, Identifiable, Hashable {
    let id: String
    let organizationId: String
    let customerId: String
    let jobId: String?
    let createdByUserId: String
    let locationId: String?
    let scheduleId: String?
    let origin: String
    let sourceOperationKey: String
    let sourceEstimateId: String?
    let sourceEstimateRevisionNumber: Int?
    let manualPhysicalServiceEvidence: FieldPhysicalServiceEvidence?
    let status: String
    let lines: [FieldLine]
    let linesRevision: Int
    let amountPaid: Int
    let currency: String
    let issuedAt: String?
    let paidAt: String?
    let voidedAt: String?
    let createdAt: String
    let updatedAt: String
}

struct FieldEstimateLineInput: Encodable {
    let description: String
    let quantity: Int
    let unitPrice: FieldMoney

    init(description: String, quantity: Int, unitPrice: FieldMoney) {
        self.description = description
        self.quantity = quantity
        self.unitPrice = unitPrice
    }
}

struct FieldEstimateCreate: Encodable {
    let customerId: String
    let title: String
    let lines: [FieldEstimateLineInput]
    let locationId: String?

    init(customerId: String, title: String, lines: [FieldEstimateLineInput], locationId: String? = nil) {
        self.customerId = customerId
        self.title = title
        self.lines = lines
        self.locationId = locationId
    }
}

/// These cases produce only request shapes accepted by jobs.progress.
enum FieldProgressRequest: Encodable {
    enum ArrivalMethod: String, Encodable { case manual, geofence }
    case scheduled
    case dispatched
    case enRoute(etaMinutes: Int? = nil)
    case arrived(method: ArrivalMethod = .manual)
    case start
    case pause(reason: String, nextAction: String, ownerUserId: String? = nil)
    case resume(expectedPauseAuditId: String)

    private enum CodingKeys: String, CodingKey { case to, arrival, pause, expectedPauseAuditId, etaMinutes }
    private struct Arrival: Encodable { let method: ArrivalMethod }
    private struct Pause: Encodable { let reason: String; let nextAction: String; let ownerUserId: String? }

    func encode(to encoder: Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .scheduled: try fields.encode("scheduled", forKey: .to)
        case .dispatched: try fields.encode("dispatched", forKey: .to)
        case .enRoute(let etaMinutes):
            try fields.encode("en_route", forKey: .to)
            try fields.encodeIfPresent(etaMinutes, forKey: .etaMinutes)
        case .arrived(let method):
            try fields.encode("arrived", forKey: .to)
            try fields.encode(Arrival(method: method), forKey: .arrival)
        case .start: try fields.encode("in_progress", forKey: .to)
        case .pause(let reason, let nextAction, let ownerUserId):
            try fields.encode("paused", forKey: .to)
            try fields.encode(Pause(reason: reason, nextAction: nextAction, ownerUserId: ownerUserId), forKey: .pause)
        case .resume(let auditID):
            try fields.encode("in_progress", forKey: .to)
            try fields.encode(auditID, forKey: .expectedPauseAuditId)
        }
    }
}

struct MediaAssetRecord: Codable, Identifiable, Hashable {
    let id: String
    let organizationId: String
    let jobId: String
    let uploaderUserId: String
    let kind: String
    let mime: String
    let sizeBytes: Int
    let originalFilename: String
    let contentHash: String
    let storageKey: String
    let capturedAt: String?
    let uploadState: String
    let tags: [String]
    let caption: String?
    let archived: Bool
    let sourceAssetId: String?
    let createdAt: String
    let updatedAt: String
}

struct FieldMediaRegistrationRequest: Encodable {
    let clientAssetId: String
    let kind: String
    let mime: String
    let sizeBytes: Int
    let originalFilename: String
    let contentHash: String
    let capturedAt: String?
    let tags: [String]?
    let caption: String?

    init(clientAssetId: String, kind: String, mime: String, sizeBytes: Int,
         originalFilename: String, contentHash: String, capturedAt: String? = nil,
         tags: [String]? = nil, caption: String? = nil) {
        self.clientAssetId = clientAssetId
        self.kind = kind
        self.mime = mime
        self.sizeBytes = sizeBytes
        self.originalFilename = originalFilename
        self.contentHash = contentHash
        self.capturedAt = capturedAt
        self.tags = tags
        self.caption = caption
    }
}

struct FieldUploadTarget: Decodable {
    let url: String
    let method: String
    let expiresAt: String
    let headers: [String: String]
}

struct FieldResumablePart: Decodable {
    let partNumber: Int
    let url: String
    let expiresAt: String
}

struct FieldResumableUpload: Decodable {
    let uploadId: String
    let partSize: Int
    let parts: [FieldResumablePart]
    let expiresAt: String
}

struct FieldMediaRegistration: Decodable {
    let asset: MediaAssetRecord
    let uploadTarget: FieldUploadTarget?
    let resumable: FieldResumableUpload?

    private enum CodingKeys: String, CodingKey { case asset, uploadTarget, resumable }

    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        asset = try fields.decode(MediaAssetRecord.self, forKey: .asset)
        uploadTarget = try fields.decodeIfPresent(FieldUploadTarget.self, forKey: .uploadTarget)
        resumable = try fields.decodeIfPresent(FieldResumableUpload.self, forKey: .resumable)
        let targetCount = (uploadTarget == nil ? 0 : 1) + (resumable == nil ? 0 : 1)
        guard targetCount <= 1, asset.uploadState != "pending" || targetCount == 1 else {
            throw DecodingError.dataCorruptedError(forKey: .asset, in: fields,
                debugDescription: "Pending media requires exactly one upload method")
        }
    }
}

private struct FieldPage<T: Decodable>: Decodable {
    let items: [T]
    let nextCursor: String?
}

@MainActor
extension APIClient {
    private func fieldPath(_ base: String, id: String, suffix: String = "") throws -> String {
        guard UUID(uuidString: id) != nil else {
            throw Problem(title: "Invalid record ID", status: nil, detail: id)
        }
        return "\(base)/\(id)\(suffix)"
    }

    private func allFieldPages<T: Decodable>(_ path: String) async throws -> [T] {
        let generation = requestGeneration
        var items: [T] = []
        var cursor: String?
        var seen = Set<String>()
        repeat {
            try Task.checkCancellation()
            guard generation == requestGeneration else { throw CancellationError() }
            let page: FieldPage<T> = try await send("GET", path, cursor: cursor)
            items.append(contentsOf: page.items)
            cursor = page.nextCursor
            if let cursor, cursor.isEmpty || !seen.insert(cursor).inserted {
                throw Problem(title: "Pagination cursor loop", status: nil, detail: "Repeated or empty cursor")
            }
        } while cursor != nil
        return items
    }

    func fieldJobs() async throws -> [JobRecord] { try await allFieldPages("/v1/jobs") }
    func fieldJob(_ id: String) async throws -> JobRecord { try await send("GET", fieldPath("/v1/jobs", id: id)) }
    func createFieldJob(_ request: FieldJobCreate) async throws -> JobRecord {
        try await send("POST", "/v1/jobs", body: request)
    }
    func fieldCustomers() async throws -> [CustomerRecord] { try await allFieldPages("/v1/customers") }
    func fieldCustomer(_ id: String) async throws -> CustomerRecord { try await send("GET", fieldPath("/v1/customers", id: id)) }

    func fieldContacts(_ customerID: String) async throws -> [CustomerContactRecord] {
        let page: FieldPage<CustomerContactRecord> = try await send("GET", fieldPath("/v1/customers", id: customerID, suffix: "/contacts"))
        return page.items
    }

    func createFieldContact(_ customerID: String, request: FieldContactCreate) async throws -> CustomerContactRecord {
        try await send("POST", fieldPath("/v1/customers", id: customerID, suffix: "/contacts"), body: request)
    }

    func updateFieldContact(_ customerID: String, _ contactID: String, request: FieldContactUpdate) async throws -> CustomerContactRecord {
        let path = try fieldContactPath(customerID, contactID)
        return try await send("POST", path, body: request)
    }

    func removeFieldContact(_ customerID: String, _ contactID: String) async throws {
        let path = try fieldContactPath(customerID, contactID)
        let _: EmptyResponse = try await send("POST", "\(path)/remove")
    }

    private func fieldContactPath(_ customerID: String, _ contactID: String) throws -> String {
        let customerPath = try fieldPath("/v1/customers", id: customerID)
        return try fieldPath("\(customerPath)/contacts", id: contactID)
    }

    func fieldLocations(_ customerID: String) async throws -> [ServiceLocationRecord] {
        let page: FieldPage<ServiceLocationRecord> = try await send("GET", fieldPath("/v1/customers", id: customerID, suffix: "/locations"))
        return page.items
    }

    func createFieldLocation(_ customerID: String, request: FieldLocationCreate) async throws -> ServiceLocationRecord {
        try await send("POST", fieldPath("/v1/customers", id: customerID, suffix: "/locations"), body: request)
    }

    func updateFieldLocation(_ customerID: String, _ locationID: String, request: FieldLocationUpdate) async throws -> ServiceLocationRecord {
        let path = try fieldLocationPath(customerID, locationID)
        return try await send("POST", path, body: request)
    }

    func removeFieldLocation(_ customerID: String, _ locationID: String) async throws {
        let path = try fieldLocationPath(customerID, locationID)
        let _: EmptyResponse = try await send("POST", "\(path)/remove")
    }

    private func fieldLocationPath(_ customerID: String, _ locationID: String) throws -> String {
        let customerPath = try fieldPath("/v1/customers", id: customerID)
        return try fieldPath("\(customerPath)/locations", id: locationID)
    }

    func fieldNotes(_ jobID: String) async throws -> [JobNoteRecord] {
        let page: FieldPage<JobNoteRecord> = try await send("GET", fieldPath("/v1/jobs", id: jobID, suffix: "/notes"))
        return page.items
    }

    func fieldPhotos(_ jobID: String) async throws -> [JobPhotoRecord] {
        let page: FieldPage<JobPhotoRecord> = try await send("GET", fieldPath("/v1/jobs", id: jobID, suffix: "/photos"))
        return page.items
    }

    func addFieldNote(_ jobID: String, body: String) async throws -> JobNoteRecord {
        struct Body: Encodable { let body: String }
        return try await send("POST", fieldPath("/v1/jobs", id: jobID, suffix: "/notes"), body: Body(body: body))
    }

    func progressFieldJob(_ jobID: String, request: FieldProgressRequest) async throws -> JobRecord {
        try await send("POST", fieldPath("/v1/jobs", id: jobID, suffix: "/progress"), body: request)
    }

    func fieldEstimates() async throws -> [EstimateRecord] { try await allFieldPages("/v1/estimates") }
    func fieldEstimate(_ id: String) async throws -> EstimateRecord { try await send("GET", fieldPath("/v1/estimates", id: id)) }
    func createFieldEstimate(_ request: FieldEstimateCreate) async throws -> EstimateRecord {
        try await send("POST", "/v1/estimates", body: request)
    }

    func fieldInvoices() async throws -> [InvoiceRecord] { try await allFieldPages("/v1/invoices") }
    func fieldInvoice(_ id: String) async throws -> InvoiceRecord { try await send("GET", fieldPath("/v1/invoices", id: id)) }
    func ensureFieldCompletionInvoice(_ jobID: String) async throws -> InvoiceRecord {
        try await send("POST", fieldPath("/v1/jobs", id: jobID, suffix: "/completion-invoice"), body: EmptyObject())
    }

    func fieldMedia(_ jobID: String) async throws -> [MediaAssetRecord] {
        try await allFieldPages(fieldPath("/v1/jobs", id: jobID, suffix: "/media"))
    }

    func registerFieldMedia(_ jobID: String, request: FieldMediaRegistrationRequest) async throws -> FieldMediaRegistration {
        try await send("POST", fieldPath("/v1/jobs", id: jobID, suffix: "/media"), body: request)
    }

    func confirmFieldMedia(_ mediaID: String) async throws -> MediaAssetRecord {
        try await send("POST", fieldPath("/v1/media", id: mediaID, suffix: "/confirm"), body: EmptyObject())
    }
}

private struct EmptyObject: Encodable {}

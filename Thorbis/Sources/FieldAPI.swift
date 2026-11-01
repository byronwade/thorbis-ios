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

struct FieldJobDraft: Equatable {
    var customerID = ""
    var title = ""
    var notes = ""
    /// The service location the job happens at, when one was picked.
    var locationID: String? = nil

    init(customerID: String = "", title: String = "", notes: String = "") {
        self.customerID = customerID
        self.title = title
        self.notes = notes
    }

    var canCreate: Bool {
        !customerID.isEmpty && !trimmedTitle.isEmpty && !titleIsTooLong && !notesAreTooLong
    }

    var titleIsTooLong: Bool { trimmedTitle.utf16.count > 200 }
    var notesAreTooLong: Bool { trimmedNotes.utf16.count > 10_000 }

    var request: FieldJobCreate? {
        guard canCreate else { return nil }
        return FieldJobCreate(
            customerId: customerID,
            title: trimmedTitle,
            locationId: locationID,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes
        )
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedNotes: String {
        notes.trimmingCharacters(in: .whitespacesAndNewlines)
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

enum CustomerListScope: String, CaseIterable, Identifiable {
    case recent = "Recent"
    case all = "All customers"
    case archived = "Archived"

    var id: String { rawValue }

    func customers(from values: [CustomerRecord]) -> [CustomerRecord] {
        switch self {
        case .recent:
            values.filter { !$0.archived }.sorted { $0.id > $1.id }
        case .all:
            values.sorted {
                let order = $0.name.localizedStandardCompare($1.name)
                return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
            }
        case .archived:
            values.filter(\.archived).sorted {
                let order = $0.name.localizedStandardCompare($1.name)
                return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
            }
        }
    }
}

struct CustomerHistoryPage: Decodable {
    let items: [CustomerHistoryEntry]
    let nextCursor: String?
}

struct CustomerHistoryEntry: Decodable, Identifiable, Hashable {
    let occurredAt: String
    let kind: String
    let subjectId: String
    let summary: String

    var id: String { "\(occurredAt)|\(kind)|\(subjectId)|\(summary)" }
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
struct FieldEstimateLineSourceSnapshot: Codable, Hashable {
    let kind: String
    let priceBookItemId: String?
    let priceBookRevision: Int?
    let originalDescription: String?
    let originalUnitPrice: FieldMoney?
    let addedByUserId: String?
    let capturedAt: String?
    let overriddenFields: [String]?

    private enum CodingKeys: String, CodingKey {
        case kind, priceBookItemId, priceBookRevision, originalDescription
        case originalUnitPrice, addedByUserId, capturedAt, overriddenFields
    }

    init(kind: String, priceBookItemId: String? = nil, priceBookRevision: Int? = nil,
         originalDescription: String? = nil, originalUnitPrice: FieldMoney? = nil,
         addedByUserId: String? = nil, capturedAt: String? = nil, overriddenFields: [String]? = nil) {
        self.kind = kind
        self.priceBookItemId = priceBookItemId
        self.priceBookRevision = priceBookRevision
        self.originalDescription = originalDescription
        self.originalUnitPrice = originalUnitPrice
        self.addedByUserId = addedByUserId
        self.capturedAt = capturedAt
        self.overriddenFields = overriddenFields
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(kind, forKey: .kind)
        try values.encodeIfPresent(priceBookItemId, forKey: .priceBookItemId)
        try values.encodeIfPresent(priceBookRevision, forKey: .priceBookRevision)
        try values.encodeIfPresent(originalDescription, forKey: .originalDescription)
        try values.encodeIfPresent(originalUnitPrice, forKey: .originalUnitPrice)
        try values.encodeIfPresent(addedByUserId, forKey: .addedByUserId)
        try values.encodeIfPresent(capturedAt, forKey: .capturedAt)
        try values.encodeIfPresent(overriddenFields, forKey: .overriddenFields)
    }
}

struct FieldLineSource: Codable, Hashable {
    let kind: String
    let priceBookItemId: String?
    let priceBookRevision: Int?
    let originalDescription: String?
    let originalUnit: String?
    let originalUnitPrice: FieldMoney?
    let originalTaxClassification: String?
    let originalItemKind: String?
    let addedByUserId: String?
    let capturedAt: String?
    let overriddenFields: [String]?
    let estimateId: String?
    let estimateRevisionNumber: Int?
    let estimateLineId: String?
    let estimateLineSource: FieldEstimateLineSourceSnapshot?

    private enum CodingKeys: String, CodingKey {
        case kind, priceBookItemId, priceBookRevision, originalDescription, originalUnit
        case originalUnitPrice, originalTaxClassification, originalItemKind
        case addedByUserId, capturedAt, overriddenFields, estimateId
        case estimateRevisionNumber, estimateLineId, estimateLineSource
    }

    init(kind: String, priceBookItemId: String? = nil, priceBookRevision: Int? = nil,
         originalDescription: String? = nil, originalUnit: String? = nil,
         originalUnitPrice: FieldMoney? = nil, originalTaxClassification: String? = nil,
         originalItemKind: String? = nil, addedByUserId: String? = nil,
         capturedAt: String? = nil, overriddenFields: [String]? = nil,
         estimateId: String? = nil, estimateRevisionNumber: Int? = nil,
         estimateLineId: String? = nil, estimateLineSource: FieldEstimateLineSourceSnapshot? = nil) {
        self.kind = kind
        self.priceBookItemId = priceBookItemId
        self.priceBookRevision = priceBookRevision
        self.originalDescription = originalDescription
        self.originalUnit = originalUnit
        self.originalUnitPrice = originalUnitPrice
        self.originalTaxClassification = originalTaxClassification
        self.originalItemKind = originalItemKind
        self.addedByUserId = addedByUserId
        self.capturedAt = capturedAt
        self.overriddenFields = overriddenFields
        self.estimateId = estimateId
        self.estimateRevisionNumber = estimateRevisionNumber
        self.estimateLineId = estimateLineId
        self.estimateLineSource = estimateLineSource
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(kind, forKey: .kind)
        try values.encodeIfPresent(priceBookItemId, forKey: .priceBookItemId)
        try values.encodeIfPresent(priceBookRevision, forKey: .priceBookRevision)
        try values.encodeIfPresent(originalDescription, forKey: .originalDescription)
        try values.encodeIfPresent(originalUnit, forKey: .originalUnit)
        try values.encodeIfPresent(originalUnitPrice, forKey: .originalUnitPrice)
        try values.encodeIfPresent(originalTaxClassification, forKey: .originalTaxClassification)
        try values.encodeIfPresent(originalItemKind, forKey: .originalItemKind)
        try values.encodeIfPresent(addedByUserId, forKey: .addedByUserId)
        try values.encodeIfPresent(capturedAt, forKey: .capturedAt)
        try values.encodeIfPresent(overriddenFields, forKey: .overriddenFields)
        try values.encodeIfPresent(estimateId, forKey: .estimateId)
        try values.encodeIfPresent(estimateRevisionNumber, forKey: .estimateRevisionNumber)
        try values.encodeIfPresent(estimateLineId, forKey: .estimateLineId)
        try values.encodeIfPresent(estimateLineSource, forKey: .estimateLineSource)
    }
}

struct FieldLine: Codable, Identifiable, Hashable {
    let id: String
    let description: String
    let quantity: Int
    let unitPrice: FieldMoney
    let source: FieldLineSource?
    /// Builder group, "work" or "material" (EB-09); missing on lines saved before groups were stored.
    var group: String? = nil
    /// EB-13: false folds this material into one customer "Materials" line. Missing reads as true.
    var showToCustomer: Bool? = nil
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
    /// Present once the customer signed the approval on a technician's phone.
    var approvalSignature: FieldSignatureRecord? = nil
}

/// A signature recorded with an estimate approval or an invoice authorization.
struct FieldSignatureRecord: Codable, Hashable {
    let id: String
    let signerName: String
    let signedAt: String
    let imageMediaId: String
    /// Invoice authorizations only: the line revision the customer signed.
    var linesRevision: Int? = nil
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
    /// The customer's latest signed authorization; current when its linesRevision matches.
    var customerAuthorization: FieldSignatureRecord? = nil
}

enum FieldEstimateLineSourceInput: Hashable, Encodable {
    case manual
    case priceBookSelection(itemID: String, revision: Int)
    case unsupported(String)

    private enum CodingKeys: String, CodingKey { case kind, priceBookItemId, priceBookRevision }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .manual:
            try values.encode("manual", forKey: .kind)
        case .priceBookSelection(let itemID, let revision):
            try values.encode("price_book", forKey: .kind)
            try values.encode(itemID, forKey: .priceBookItemId)
            try values.encode(revision, forKey: .priceBookRevision)
        case .unsupported(let kind):
            throw EncodingError.invalidValue(kind, .init(codingPath: encoder.codingPath,
                debugDescription: "Unsupported estimate line provenance"))
        }
    }
}

struct FieldEstimateLineInput: Encodable {
    let description: String
    let quantity: Int
    let unitPrice: FieldMoney
    let source: FieldEstimateLineSourceInput?
    /// Sent only when the workspace stores line groups (`estimate_line_groups`).
    let group: String?
    let showToCustomer: Bool?

    init(description: String, quantity: Int, unitPrice: FieldMoney,
         source: FieldEstimateLineSourceInput? = nil, group: String? = nil, showToCustomer: Bool? = nil) {
        self.description = description
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.source = source
        self.group = group
        self.showToCustomer = showToCustomer
    }
}

struct JobEstimateLink: Codable, Identifiable, Hashable {
    let id: String
    let jobId: String
    let estimateId: String
    let linkedAt: String?
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

/// The stage a job photo is filed under. "Other" means it is neither Before nor After.
enum MediaStage: Equatable {
    case before
    case after
    case other
}

/// Before and After are exclusive. Any other tag on the photo stays, in the order the server sent it.
enum MediaStageTags {
    static func applying(_ stage: MediaStage, to tags: [String]) -> [String] {
        var kept: [String] = []
        for tag in tags {
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != "Before", trimmed != "After", !kept.contains(trimmed) else { continue }
            kept.append(trimmed)
        }
        switch stage {
        case .before: kept.append("Before")
        case .after: kept.append("After")
        case .other: break
        }
        return kept
    }
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

struct JobMediaPage: Decodable {
    let items: [MediaAssetRecord]
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

    private func allFieldPages<T: Decodable>(_ path: String, queryItems: [URLQueryItem] = []) async throws -> [T] {
        let generation = requestGeneration
        var items: [T] = []
        var cursor: String?
        var seen = Set<String>()
        repeat {
            try Task.checkCancellation()
            guard generation == requestGeneration else { throw CancellationError() }
            let page: FieldPage<T> = try await send("GET", path, queryItems: queryItems, cursor: cursor)
            items.append(contentsOf: page.items)
            cursor = page.nextCursor
            if let cursor, cursor.isEmpty || !seen.insert(cursor).inserted {
                throw Problem(title: "Pagination cursor loop", status: nil, detail: "Repeated or empty cursor")
            }
        } while cursor != nil
        return items
    }

    func fieldJobs() async throws -> [JobRecord] { try await allFieldPages("/v1/jobs") }
    func fieldJobs(customerID: String) async throws -> [JobRecord] {
        guard UUID(uuidString: customerID) != nil else { throw Problem(title: "Invalid record ID", status: nil, detail: customerID) }
        return try await allFieldPages("/v1/jobs", queryItems: [URLQueryItem(name: "customerId", value: customerID)])
    }
    func fieldJob(_ id: String, requireFresh: Bool = false) async throws -> JobRecord { try await send("GET", fieldPath("/v1/jobs", id: id), requireFresh: requireFresh) }
    func createFieldJob(_ request: FieldJobCreate) async throws -> JobRecord {
        try await send("POST", "/v1/jobs", body: request)
    }
    func fieldCustomers(includeArchived: Bool = false) async throws -> [CustomerRecord] {
        let query = includeArchived ? [URLQueryItem(name: "includeArchived", value: "true")] : []
        return try await allFieldPages("/v1/customers", queryItems: query)
    }
    func fieldCustomer(_ id: String) async throws -> CustomerRecord { try await send("GET", fieldPath("/v1/customers", id: id)) }
    func fieldCustomerHistory(_ id: String, cursor: String? = nil) async throws -> CustomerHistoryPage {
        try await send("GET", fieldPath("/v1/customers", id: id, suffix: "/history"),
                       queryItems: [URLQueryItem(name: "limit", value: "50")], cursor: cursor)
    }

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
    func fieldEstimates(customerID: String) async throws -> [EstimateRecord] {
        guard UUID(uuidString: customerID) != nil else { throw Problem(title: "Invalid record ID", status: nil, detail: customerID) }
        return try await allFieldPages("/v1/estimates", queryItems: [URLQueryItem(name: "customerId", value: customerID)])
    }
    func fieldEstimate(_ id: String) async throws -> EstimateRecord { try await send("GET", fieldPath("/v1/estimates", id: id)) }
    func createFieldEstimate(_ request: FieldEstimateCreate) async throws -> EstimateRecord {
        try await send("POST", "/v1/estimates", body: request)
    }
    /// Estimates related to a job (`GET /v1/jobs/{id}/estimates`), as link records.
    func fieldJobEstimateLinks(_ jobID: String) async throws -> [JobEstimateLink] {
        try await allFieldPages(fieldPath("/v1/jobs", id: jobID, suffix: "/estimates"))
    }
    /// Links an existing estimate to a job without changing the job's origin.
    func linkFieldEstimate(jobID: String, estimateID: String) async throws -> JobEstimateLink {
        guard UUID(uuidString: estimateID) != nil else { throw Problem(title: "Invalid record ID", status: nil, detail: estimateID) }
        return try await send("POST", fieldPath("/v1/jobs", id: jobID, suffix: "/estimates/\(estimateID)/link"), body: [String: String]())
    }

    func fieldInvoices() async throws -> [InvoiceRecord] { try await allFieldPages("/v1/invoices") }
    func fieldInvoices(customerID: String) async throws -> [InvoiceRecord] {
        guard UUID(uuidString: customerID) != nil else { throw Problem(title: "Invalid record ID", status: nil, detail: customerID) }
        return try await allFieldPages("/v1/invoices", queryItems: [URLQueryItem(name: "customerId", value: customerID)])
    }
    func fieldInvoice(_ id: String) async throws -> InvoiceRecord { try await send("GET", fieldPath("/v1/invoices", id: id)) }
    /// A job's invoices, drafts included (`GET /v1/jobs/{id}/invoices`). Unlike the invoice list this
    /// answers for a technician through the assigned job, so a fresh device still sees the job's paper.
    func fieldJobInvoices(_ jobID: String) async throws -> [InvoiceRecord] {
        try await allFieldPages(fieldPath("/v1/jobs", id: jobID, suffix: "/invoices"))
    }
    func ensureFieldCompletionInvoice(_ jobID: String) async throws -> InvoiceRecord {
        try await send("POST", fieldPath("/v1/jobs", id: jobID, suffix: "/completion-invoice"), body: EmptyObject())
    }

    func fieldMedia(_ jobID: String, includeArchived: Bool = false) async throws -> [MediaAssetRecord] {
        try await allFieldPages(fieldPath("/v1/jobs", id: jobID, suffix: "/media"), queryItems: includeArchived ? [URLQueryItem(name: "includeArchived", value: "true")] : [])
    }

    func fieldMediaPage(_ jobID: String, cursor: String? = nil, kind: String? = nil) async throws -> JobMediaPage {
        guard cursor.map({ !$0.isEmpty }) ?? true else {
            throw Problem(title: "Invalid media cursor", status: nil, detail: "The continuation is empty.")
        }
        var query = [URLQueryItem(name: "limit", value: "50")]
        if let kind { query.append(URLQueryItem(name: "kind", value: kind)) }
        return try await send("GET", fieldPath("/v1/jobs", id: jobID, suffix: "/media"), queryItems: query, cursor: cursor)
    }

    func registerFieldMedia(_ jobID: String, request: FieldMediaRegistrationRequest) async throws -> FieldMediaRegistration {
        try await send("POST", fieldPath("/v1/jobs", id: jobID, suffix: "/media"), body: request)
    }

    func confirmFieldMedia(_ mediaID: String) async throws -> MediaAssetRecord {
        try await send("POST", fieldPath("/v1/media", id: mediaID, suffix: "/confirm"), body: EmptyObject())
    }

    /// Archive a stored photo or document (`POST /v1/media/{id}/archive`, no body, `job.edit`).
    /// Field media is archive-only: the server keeps the asset and can unarchive it.
    func archiveFieldMedia(_ mediaID: String) async throws -> MediaAssetRecord {
        guard UUID(uuidString: mediaID) != nil else {
            throw Problem(title: "Invalid media ID", status: nil, detail: mediaID)
        }
        return try await send("POST", fieldPath("/v1/media", id: mediaID, suffix: "/archive"), body: EmptyObject())
    }

    /// Replace the tags on a stored photo (`POST /v1/media/{id}/tags`). A blank caption is omitted.
    func tagFieldMedia(_ mediaID: String, tags: [String], caption: String? = nil) async throws -> MediaAssetRecord {
        guard UUID(uuidString: mediaID) != nil else {
            throw Problem(title: "Invalid media ID", status: nil, detail: mediaID)
        }
        var cleaned: [String] = []
        for tag in tags {
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !cleaned.contains(trimmed) else { continue }
            cleaned.append(trimmed)
        }
        guard cleaned.count <= 20 else {
            throw Problem(title: "Too many photo tags", status: nil, detail: "Use at most 20 tags.")
        }
        let trimmedCaption = caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        let captionToSend = (trimmedCaption?.isEmpty == false) ? trimmedCaption : nil
        return try await send("POST", fieldPath("/v1/media", id: mediaID, suffix: "/tags"),
                              body: FieldMediaTagsRequest(tags: cleaned, caption: captionToSend))
    }
}

private struct FieldMediaTagsRequest: Encodable {
    let tags: [String]
    let caption: String?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tags, forKey: .tags)
        try container.encodeIfPresent(caption, forKey: .caption)
    }

    private enum CodingKeys: String, CodingKey { case tags, caption }
}

private struct EmptyObject: Encodable {}

/// The customer's current decision on transactional job texts (GET /v1/customers/{id}/sms-consent).
struct CustomerSmsConsent: Codable, Hashable {
    let decision: String
    let version: String
    let recordedAt: String
}

extension APIClient {
    /// Nil until a decision has been recorded.
    func customerSmsConsent(_ customerID: String) async throws -> CustomerSmsConsent? {
        try await send("GET", fieldPath("/v1/customers", id: customerID, suffix: "/sms-consent"))
    }

    /// Records an explicit decision the customer gave staff. Online only; the key makes a retry safe.
    func recordCustomerSmsConsent(_ customerID: String, grant: Bool, expectedVersion: String?,
                                  idempotencyKey: String,
                                  evidenceRef: String = "Told staff in person or by phone; recorded in the Thorbis iPhone app") async throws -> CustomerSmsConsent {
        // The customer and purpose come from the route; the server refuses them in the body.
        struct Body: Encodable {
            let decision: String
            let expectedVersion: String?
            let evidenceRef: String
            let idempotencyKey: String
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(decision, forKey: .decision)
                try c.encode(expectedVersion, forKey: .expectedVersion)  // null is meaningful: no prior decision
                try c.encode(evidenceRef, forKey: .evidenceRef)
                try c.encode(idempotencyKey, forKey: .idempotencyKey)
            }
            enum CodingKeys: String, CodingKey { case decision, expectedVersion, evidenceRef, idempotencyKey }
        }
        struct Receipt: Decodable { let version: String; let decision: String; let recordedAt: String }
        let receipt: Receipt = try await send("POST", fieldPath("/v1/customers", id: customerID, suffix: "/sms-consent"),
                                              body: Body(decision: grant ? "grant" : "revoke",
                                                         expectedVersion: expectedVersion, evidenceRef: evidenceRef,
                                                         idempotencyKey: idempotencyKey))
        return CustomerSmsConsent(decision: receipt.decision, version: receipt.version, recordedAt: receipt.recordedAt)
    }
}

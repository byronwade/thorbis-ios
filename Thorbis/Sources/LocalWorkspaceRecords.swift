import CryptoKit
import Foundation

/// These books are notes made on one device. They have no canonical API identity or sync queue.
struct LocalAgreementRecord: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable { case maintenance, membership }
    let id: String
    var kind: Kind
    var name: String
    var customer: String
    var cadence: String
    var renewsOn: String?
    var notes: String?
    let createdAt: String

    init(id: String = UUID().uuidString, kind: Kind, name: String, customer: String,
         cadence: String, renewsOn: String? = nil, notes: String? = nil,
         createdAt: String = ISO8601DateFormatter().string(from: Date())) {
        self.id = id; self.kind = kind; self.name = name; self.customer = customer
        self.cadence = cadence; self.renewsOn = renewsOn; self.notes = notes; self.createdAt = createdAt
    }
}

struct LocalEquipmentRecord: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var brand: String?
    var serial: String?
    var site: String
    var installedYear: String?
    var notes: String?
    let createdAt: String

    init(id: String = UUID().uuidString, name: String, brand: String? = nil,
         serial: String? = nil, site: String, installedYear: String? = nil,
         notes: String? = nil, createdAt: String = ISO8601DateFormatter().string(from: Date())) {
        self.id = id; self.name = name; self.brand = brand; self.serial = serial
        self.site = site; self.installedYear = installedYear; self.notes = notes; self.createdAt = createdAt
    }
}

struct LocalCrewRecord: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var role: String
    var phone: String?
    let createdAt: String

    init(id: String = UUID().uuidString, name: String, role: String,
         phone: String? = nil, createdAt: String = ISO8601DateFormatter().string(from: Date())) {
        self.id = id; self.name = name; self.role = role; self.phone = phone; self.createdAt = createdAt
    }
}

struct LocalVehicleRecord: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var model: String?
    var plate: String?
    var year: String?
    var vin: String?
    var assignedTo: String?
    var mileage: String?
    var purchasePrice: String?
    var marketValue: String?
    var purchaseDate: String?
    var registrationDue: String?
    var lastOilChange: String?
    var nextOilChange: String?
    var lastTireRotation: String?
    var lastNewTires: String?
    var lastRepair: String?
    var notes: String?
    let createdAt: String

    init(id: String = UUID().uuidString, name: String, model: String? = nil, plate: String? = nil,
         year: String? = nil, vin: String? = nil, assignedTo: String? = nil, mileage: String? = nil,
         purchasePrice: String? = nil, marketValue: String? = nil, purchaseDate: String? = nil,
         registrationDue: String? = nil, lastOilChange: String? = nil, nextOilChange: String? = nil,
         lastTireRotation: String? = nil, lastNewTires: String? = nil, lastRepair: String? = nil,
         notes: String? = nil, createdAt: String = ISO8601DateFormatter().string(from: Date())) {
        self.id = id; self.name = name; self.model = model; self.plate = plate
        self.year = year; self.vin = vin; self.assignedTo = assignedTo; self.mileage = mileage
        self.purchasePrice = purchasePrice; self.marketValue = marketValue; self.purchaseDate = purchaseDate
        self.registrationDue = registrationDue; self.lastOilChange = lastOilChange
        self.nextOilChange = nextOilChange; self.lastTireRotation = lastTireRotation
        self.lastNewTires = lastNewTires; self.lastRepair = lastRepair; self.notes = notes
        self.createdAt = createdAt
    }
}

private struct LocalWorkspaceBook: Codable {
    var agreements: [LocalAgreementRecord] = []
    var equipment: [LocalEquipmentRecord] = []
    var crew: [LocalCrewRecord] = []
    var vehicles: [LocalVehicleRecord] = []
}

/// A separate, protected JSON partition for each exact account and workspace pair.
/// The caller must discard its reference on sign-out; `erasePartition` removes local data.
@MainActor
final class LocalWorkspaceRecords {
    let actorID: String
    let organizationID: String
    let fileURL: URL
    private var book: LocalWorkspaceBook

    var agreements: [LocalAgreementRecord] { book.agreements }
    var equipment: [LocalEquipmentRecord] { book.equipment }
    var crew: [LocalCrewRecord] { book.crew }
    var vehicles: [LocalVehicleRecord] { book.vehicles }

    private static func partitionURL(actorID: String, organizationID: String, directory: URL?) throws -> URL {
        guard UUID(uuidString: actorID) != nil, UUID(uuidString: organizationID) != nil else {
            throw Problem(title: "Invalid local book identity", status: nil, detail: nil)
        }
        let root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocalWorkspaceBooks", isDirectory: true)
        let partition = "v1|\(actorID.lowercased())|\(organizationID.lowercased())"
        let digest = SHA256.hash(data: Data(partition.utf8)).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent("\(digest).json")
    }

    init(actorID: String, organizationID: String, directory: URL? = nil) throws {
        self.actorID = actorID.lowercased()
        self.organizationID = organizationID.lowercased()
        self.fileURL = try Self.partitionURL(actorID: actorID, organizationID: organizationID, directory: directory)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            self.book = try JSONDecoder().decode(LocalWorkspaceBook.self, from: data)
        } else {
            self.book = LocalWorkspaceBook()
        }
    }

    private func commit(_ next: LocalWorkspaceBook) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                    attributes: [.protectionKey: FileProtectionType.complete])
        let data = try JSONEncoder().encode(next)
        try data.write(to: fileURL, options: .atomic)
        try manager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: fileURL.path)
        book = next
    }

    func save(_ record: LocalAgreementRecord) throws {
        var next = book
        next.agreements.removeAll { $0.id == record.id }
        next.agreements.append(record)
        try commit(next)
    }
    func save(_ record: LocalEquipmentRecord) throws {
        var next = book
        next.equipment.removeAll { $0.id == record.id }
        next.equipment.append(record)
        try commit(next)
    }
    func save(_ record: LocalCrewRecord) throws {
        var next = book
        next.crew.removeAll { $0.id == record.id }
        next.crew.append(record)
        try commit(next)
    }
    func save(_ record: LocalVehicleRecord) throws {
        var next = book
        next.vehicles.removeAll { $0.id == record.id }
        next.vehicles.append(record)
        try commit(next)
    }

    func removeAgreement(_ id: String) throws { var next = book; next.agreements.removeAll { $0.id == id }; try commit(next) }
    func removeEquipment(_ id: String) throws { var next = book; next.equipment.removeAll { $0.id == id }; try commit(next) }
    func removeCrew(_ id: String) throws { var next = book; next.crew.removeAll { $0.id == id }; try commit(next) }
    func removeVehicle(_ id: String) throws { var next = book; next.vehicles.removeAll { $0.id == id }; try commit(next) }

    /// Invoke on deliberate local deletion or sign-out for the active identity.
    func erasePartition() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        book = LocalWorkspaceBook()
    }

    static func erasePartition(actorID: String, organizationID: String, directory: URL? = nil) throws {
        let url = try partitionURL(actorID: actorID, organizationID: organizationID, directory: directory)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

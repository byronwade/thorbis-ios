import XCTest
@testable import Thorbis

@MainActor
final class LocalWorkspaceRecordsTests: XCTestCase {
    private let actorA = "00000000-0000-4000-8000-000000000001"
    private let actorB = "00000000-0000-4000-8000-000000000002"
    private let orgA = "00000000-0000-4000-8000-000000000003"
    private let orgB = "00000000-0000-4000-8000-000000000004"

    func testDeviceBooksRoundTripAndPartitionByActorAndOrganization() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try LocalWorkspaceRecords(actorID: actorA, organizationID: orgA, directory: directory)
        XCTAssertTrue(first.vehicles.isEmpty)
        XCTAssertTrue(first.equipment.isEmpty)
        XCTAssertTrue(first.agreements.isEmpty)
        XCTAssertTrue(first.crew.isEmpty)
        let vehicle = LocalVehicleRecord(name: "Van 1", model: "Ford Transit", plate: "ABC123", mileage: "100 mi")
        try first.save(vehicle)
        try first.save(LocalEquipmentRecord(name: "Water heater", site: "Shop"))
        try first.save(LocalAgreementRecord(kind: .maintenance, name: "Plan", customer: "Alex", cadence: "Yearly"))
        try first.save(LocalCrewRecord(name: "Dana", role: "Technician"))

        let same = try LocalWorkspaceRecords(actorID: actorA, organizationID: orgA, directory: directory)
        XCTAssertEqual(same.vehicles.first?.plate, "ABC123")
        XCTAssertEqual(same.equipment.first?.site, "Shop")
        XCTAssertEqual(same.agreements.first?.kind, .maintenance)
        XCTAssertEqual(same.crew.first?.role, "Technician")
        XCTAssertTrue(try LocalWorkspaceRecords(actorID: actorB, organizationID: orgA, directory: directory).vehicles.isEmpty)
        XCTAssertTrue(try LocalWorkspaceRecords(actorID: actorA, organizationID: orgB, directory: directory).vehicles.isEmpty)
        XCTAssertFalse(same.fileURL.lastPathComponent.contains(actorA))
        XCTAssertFalse(same.fileURL.lastPathComponent.contains(orgA))
    }

    func testEditDeleteAndExplicitEraseDoNotCreateOperationalHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let book = try LocalWorkspaceRecords(actorID: actorA, organizationID: orgA, directory: directory)
        var equipment = LocalEquipmentRecord(name: "Pump", site: "Basement")
        try book.save(equipment)
        equipment.site = "Mechanical room"
        try book.save(equipment)
        XCTAssertEqual(book.equipment.count, 1)
        XCTAssertEqual(book.equipment[0].site, "Mechanical room")
        try book.removeEquipment(equipment.id)
        XCTAssertTrue(book.equipment.isEmpty)
        try book.save(LocalCrewRecord(name: "Dana", role: "Technician"))
        try book.erasePartition()
        XCTAssertTrue(book.crew.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: book.fileURL.path))
        XCTAssertTrue(try LocalWorkspaceRecords(actorID: actorA, organizationID: orgA, directory: directory).crew.isEmpty)
    }

    func testDeliberateEraseCanRemoveCorruptPartitionWithoutDecoding() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let book = try LocalWorkspaceRecords(actorID: actorA, organizationID: orgA, directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("invalid JSON".utf8).write(to: book.fileURL)
        try LocalWorkspaceRecords.erasePartition(actorID: actorA, organizationID: orgA, directory: directory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: book.fileURL.path))
    }
}

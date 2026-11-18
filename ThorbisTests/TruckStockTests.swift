import XCTest
@testable import Thorbis

@MainActor
final class TruckStockTests: XCTestCase {
    private let userA = "00000000-0000-4000-8000-000000000001"
    private let userB = "00000000-0000-4000-8000-000000000002"
    private let orgA = "00000000-0000-4000-8000-000000000003"
    private let orgB = "00000000-0000-4000-8000-000000000004"

    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    // MARK: The low rule

    func testLowIsAtOrUnderAMinimumThatIsKept() {
        XCTAssertTrue(TruckStockRules.isLow(TruckStockItem(name: "Capacitor", quantity: 1, minimum: 6)))
        XCTAssertTrue(TruckStockRules.isLow(TruckStockItem(name: "Coupling", quantity: 4, minimum: 4)))
        XCTAssertTrue(TruckStockRules.isLow(TruckStockItem(name: "Contactor", quantity: 0, minimum: 2)))
        XCTAssertFalse(TruckStockRules.isLow(TruckStockItem(name: "Filter", quantity: 5, minimum: 4)))
        // No minimum kept: never low, even at none.
        XCTAssertFalse(TruckStockRules.isLow(TruckStockItem(name: "Rags", quantity: 0, minimum: 0)))
        // Counts never go below zero.
        XCTAssertEqual(TruckStockItem(name: "Tape", quantity: -3, minimum: -1).quantity, 0)
        XCTAssertEqual(TruckStockItem(name: "Tape", quantity: -3, minimum: -1).minimum, 0)
    }

    func testNeededAndStepping() {
        XCTAssertEqual(TruckStockRules.needed(TruckStockItem(name: "A", quantity: 1, minimum: 4)), 3)
        XCTAssertEqual(TruckStockRules.needed(TruckStockItem(name: "B", quantity: 4, minimum: 4)), 1)
        XCTAssertEqual(TruckStockRules.needed(TruckStockItem(name: "C", quantity: 9, minimum: 4)), 0)
        XCTAssertEqual(TruckStockRules.stepped(0, by: -1), 0)
        XCTAssertEqual(TruckStockRules.stepped(2, by: 1), 3)
        XCTAssertEqual(TruckStockRules.stepped(TruckStockRules.maximumCount, by: 1), TruckStockRules.maximumCount)
    }

    // MARK: The restock list

    func testRestockListIsEverythingLowEmptiestFirst() {
        let items = [
            TruckStockItem(name: "Filter drier 3/8 in", quantity: 1, minimum: 3),
            TruckStockItem(name: "16x25x1 filter", quantity: 14, minimum: 10),
            TruckStockItem(name: "Contactor 40A", partNumber: "C40A", quantity: 0, minimum: 2),
            TruckStockItem(name: "Capacitor 45/5", partNumber: "TRCFD455", quantity: 1, minimum: 4, unit: "each"),
            TruckStockItem(name: "Copper line", quantity: 50, minimum: 50, unit: "ft"),
        ]
        let list = TruckStockRules.restockList(items)
        XCTAssertEqual(list.map(\.item.name), ["Contactor 40A", "Capacitor 45/5", "Filter drier 3/8 in", "Copper line"])
        XCTAssertEqual(list.map(\.needed), [2, 3, 2, 1])
        XCTAssertEqual(TruckStockRules.lowCount(items), 4)
        XCTAssertEqual(TruckStockFormat.summary(items), "5 items \u{00B7} 4 low")
        XCTAssertEqual(TruckStockFormat.rowSubtitle(items[2]), "Out \u{00B7} par 2")
        XCTAssertEqual(TruckStockFormat.rowSubtitle(items[3]), "1 left \u{00B7} par 4")

        let text = TruckStockRules.restockText(items)
        XCTAssertEqual(text, """
        Truck restock list
        - Contactor 40A (C40A): get 2 each. Have 0, keep 2.
        - Capacitor 45/5 (TRCFD455): get 3 each. Have 1, keep 4.
        - Filter drier 3/8 in: get 2 each. Have 1, keep 3.
        - Copper line: get 1 ft. Have 50, keep 50.
        """)
        XCTAssertNil(TruckStockRules.restockText([items[1]]))
        XCTAssertTrue(TruckStockRules.restockList([]).isEmpty)
    }

    // MARK: Store

    func testStockRoundTripsAndPartitionsByPersonAndWorkspace() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try TruckStockStore(organizationID: orgA, userID: userA, directory: directory)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertEqual(TruckStockStore.lowCount(organizationID: orgA, userID: userA, directory: directory), 0)
        var capacitor = TruckStockItem(name: "Capacitor 45/5", partNumber: "TRCFD455", quantity: 1, minimum: 4)
        try store.save(capacitor)
        try store.save(TruckStockItem(name: "Filter", quantity: 14, minimum: 10))

        let reopened = try TruckStockStore(organizationID: orgA, userID: userA, directory: directory)
        XCTAssertEqual(reopened.items.map(\.name), ["Capacitor 45/5", "Filter"])
        XCTAssertEqual(reopened.items.first, capacitor)
        XCTAssertTrue(try TruckStockStore(organizationID: orgA, userID: userB, directory: directory).items.isEmpty)
        XCTAssertTrue(try TruckStockStore(organizationID: orgB, userID: userA, directory: directory).items.isEmpty)
        XCTAssertFalse(store.fileURL.lastPathComponent.contains(userA))
        XCTAssertThrowsError(try TruckStockStore(organizationID: orgA, userID: " ", directory: directory))

        XCTAssertEqual(TruckStockStore.lowCount(organizationID: orgA, userID: userA, directory: directory), 1)
        XCTAssertEqual(TruckStockStore.lowCount(organizationID: orgA, userID: userB, directory: directory), 0)

        // An edit replaces in place; it doesn't add a second item.
        capacitor.minimum = 6
        try store.save(capacitor)
        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(store.items.first?.minimum, 6)
    }

    func testQuickAdjustSavesAndStopsAtZero() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try TruckStockStore(organizationID: orgA, userID: userA, directory: directory)
        let item = TruckStockItem(name: "Coupling", quantity: 5, minimum: 4)
        try store.save(item)
        XCTAssertEqual(TruckStockStore.lowCount(organizationID: orgA, userID: userA, directory: directory), 0)
        XCTAssertEqual(try store.adjust(item.id, by: -1), 4)
        XCTAssertEqual(TruckStockStore.lowCount(organizationID: orgA, userID: userA, directory: directory), 1)
        XCTAssertEqual(try store.adjust(item.id, by: -10), 0)
        XCTAssertEqual(try store.adjust(item.id, by: 1), 1)
        XCTAssertEqual(try TruckStockStore(organizationID: orgA, userID: userA, directory: directory).items.first?.quantity, 1)
        XCTAssertThrowsError(try store.adjust("missing", by: 1))

        try store.remove(item.id)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertEqual(TruckStockStore.lowCount(organizationID: orgA, userID: userA, directory: directory), 0)
    }

    func testModelKeepsItemsByNameAndClearsWhenSignedOut() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = TruckStockModel()
        model.bind(organizationID: orgA, userID: userA, directory: directory)
        XCTAssertTrue(model.bound)
        let wire = TruckStockItem(name: "wire nuts", quantity: 2, minimum: 5, unit: "box")
        try model.save(wire)
        try model.save(TruckStockItem(name: "Capacitor", quantity: 3, minimum: 1))
        XCTAssertEqual(model.items.map(\.name), ["Capacitor", "wire nuts"])
        try model.adjust(wire.id, by: 4)
        XCTAssertEqual(model.item(wire.id)?.quantity, 6)
        XCTAssertEqual(TruckStockRules.lowCount(model.items), 0)
        model.bind(organizationID: nil, userID: nil, directory: directory)
        XCTAssertFalse(model.bound)
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertThrowsError(try model.remove(wire.id))
    }
}

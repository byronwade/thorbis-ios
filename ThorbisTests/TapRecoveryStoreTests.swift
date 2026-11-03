import Foundation
import XCTest
@testable import Thorbis

@MainActor
final class TapRecoveryStoreTests: XCTestCase {
    func testRelaunchKeepsLostPreparationAndScopesOnlyTheInvoice() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("holds.json")
        let scope = TapRecoveryScope(origin: "https://api.example", organization: "org", actor: "one", invoice: "invoice")
        let otherActor = TapRecoveryScope(origin: scope.origin, organization: scope.organization, actor: "two", invoice: scope.invoice)
        let otherInvoice = TapRecoveryScope(origin: scope.origin, organization: scope.organization, actor: scope.actor, invoice: "other")
        let otherOrg = TapRecoveryScope(origin: scope.origin, organization: "other", actor: scope.actor, invoice: scope.invoice)
        try TapRecoveryStore(url: file).begin(scope: scope, amount: 1250, currency: "USD")
        let restarted = TapRecoveryStore(url: file)
        XCTAssertTrue(try restarted.isHeld(scope: scope))
        XCTAssertTrue(try restarted.isHeld(scope: otherActor))
        XCTAssertFalse(try restarted.isHeld(scope: otherInvoice))
        XCTAssertFalse(try restarted.isHeld(scope: otherOrg))
        XCTAssertThrowsError(try restarted.confirmReceipt(scope: scope, attemptID: UUID().uuidString, amount: 1250, currency: "USD"))
    }

    func testOnlyExactBoundReceiptMayClearHold() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TapRecoveryStore(url: dir.appendingPathComponent("holds.json"))
        let scope = TapRecoveryScope(origin: "https://api.example", organization: "org", actor: "one", invoice: "invoice")
        let id = UUID().uuidString
        try store.begin(scope: scope, amount: 1250, currency: "USD")
        try store.bindAttempt(scope: scope, attemptID: id)
        XCTAssertThrowsError(try store.bindAttempt(scope: scope, attemptID: UUID().uuidString))
        XCTAssertThrowsError(try store.confirmReceipt(scope: scope, attemptID: id, amount: 1200, currency: "USD"))
        XCTAssertThrowsError(try store.confirmReceipt(scope: scope, attemptID: UUID().uuidString, amount: 1250, currency: "USD"))
        XCTAssertTrue(try store.isHeld(scope: scope))
        try store.confirmReceipt(scope: scope, attemptID: id, amount: 1250, currency: "USD")
        XCTAssertFalse(try store.isHeld(scope: scope))
    }

    func testWriteFailureAndCorruptStateThrow() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let scope = TapRecoveryScope(origin: "https://api.example", organization: "org", actor: "one", invoice: "invoice")
        XCTAssertThrowsError(try TapRecoveryStore(url: dir.appendingPathComponent("holds.json")).begin(scope: scope, amount: 1, currency: "USD"))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("holds.json")
        try Data("corrupt".utf8).write(to: file)
        XCTAssertThrowsError(try TapRecoveryStore(url: file).isHeld(scope: scope))
    }
}

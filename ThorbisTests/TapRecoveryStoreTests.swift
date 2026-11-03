import Foundation
import XCTest
@testable import Thorbis

@MainActor
final class TapRecoveryStoreTests: XCTestCase {
    func testEquivalentUUIDsAndTrustedOriginCannotBypassOrStrandHold() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TapRecoveryStore(url: dir.appendingPathComponent("holds.json"))
        let original = TapRecoveryScope(origin: "https://app.thorbis.com",
            organization: "018f0000-0000-7000-8000-00000000000a",
            actor: "018f0000-0000-7000-8000-00000000000b",
            invoice: "018f0000-0000-7000-8000-00000000000c")
        let alternate = TapRecoveryScope(origin: "https://APP.THORBIS.COM/",
            organization: original.organization.uppercased(), actor: original.actor.uppercased(),
            invoice: original.invoice.uppercased())
        let attempt = "018f0000-0000-7000-8000-00000000000d"
        let hold = try store.begin(scope: original, jobID: original.invoice, amount: 100, currency: "USD")
        XCTAssertTrue(try store.isHeld(scope: alternate))
        XCTAssertNotNil(try store.pending(scope: alternate))
        XCTAssertThrowsError(try store.begin(scope: alternate, jobID: original.invoice, amount: 100, currency: "USD"))
        try store.bindAttempt(scope: alternate, operationID: hold.operationID, jobID: original.invoice, attemptID: attempt.uppercased())
        try store.bindAttempt(scope: original, operationID: hold.operationID, jobID: original.invoice, attemptID: attempt)
        try store.confirmReceipt(scope: alternate, operationID: hold.operationID, jobID: original.invoice, attemptID: attempt, amount: 100, currency: "USD")
        XCTAssertFalse(try store.isHeld(scope: original))
    }

    func testInvalidOriginsAndMalformedUUIDsFailClosed() throws {
        let store = TapRecoveryStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let id = "018f0000-0000-7000-8000-00000000000a"
        for scope in [
            TapRecoveryScope(origin: "https://app.thorbis.com.evil.example", organization: id, actor: id, invoice: id),
            TapRecoveryScope(origin: "https://app.thorbis.com:443", organization: id, actor: id, invoice: id),
            TapRecoveryScope(origin: "https://app.thorbis.com", organization: "invalid", actor: id, invoice: id),
            TapRecoveryScope(origin: "https://app.thorbis.com", organization: id, actor: "invalid", invoice: id),
            TapRecoveryScope(origin: "https://app.thorbis.com", organization: id, actor: id, invoice: "invalid"),
        ] {
            XCTAssertThrowsError(try store.isHeld(scope: scope))
            XCTAssertThrowsError(try store.begin(scope: scope, jobID: scope.invoice, amount: 1, currency: "USD"))
        }
    }

    func testEquivalentDuplicateSavedHoldsFailClosed() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("holds.json")
        let first = TapRecoveryScope(origin: "https://app.thorbis.com",
            organization: "018f0000-0000-7000-8000-00000000000a",
            actor: "018f0000-0000-7000-8000-00000000000b",
            invoice: "018f0000-0000-7000-8000-00000000000c")
        let duplicate = TapRecoveryScope(origin: "https://APP.THORBIS.COM/",
            organization: first.organization.uppercased(), actor: first.actor.uppercased(),
            invoice: first.invoice.uppercased())
        try JSONEncoder().encode([
            TapRecoveryHold(scope: first, operationID: UUID().uuidString, jobID: first.invoice, amount: 100, currency: "USD", attemptID: nil),
            TapRecoveryHold(scope: duplicate, operationID: UUID().uuidString, jobID: first.invoice, amount: 100, currency: "USD", attemptID: nil),
        ]).write(to: file)
        XCTAssertThrowsError(try TapRecoveryStore(url: file).isHeld(scope: first))
    }

    func testRelaunchKeepsLostPreparationAndScopesOnlyTheInvoice() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("holds.json")
        let scope = TapRecoveryScope(origin: "https://app.thorbis.com", organization: "018f0000-0000-7000-8000-00000000001a", actor: "018f0000-0000-7000-8000-00000000001b", invoice: "018f0000-0000-7000-8000-00000000001c")
        let otherActor = TapRecoveryScope(origin: scope.origin, organization: scope.organization, actor: "018f0000-0000-7000-8000-00000000001d", invoice: scope.invoice)
        let otherInvoice = TapRecoveryScope(origin: scope.origin, organization: scope.organization, actor: scope.actor, invoice: "018f0000-0000-7000-8000-00000000001e")
        let otherOrg = TapRecoveryScope(origin: scope.origin, organization: "018f0000-0000-7000-8000-00000000001e", actor: scope.actor, invoice: scope.invoice)
        let hold = try TapRecoveryStore(url: file).begin(scope: scope, jobID: scope.invoice, amount: 1250, currency: "USD")
        let restarted = TapRecoveryStore(url: file)
        XCTAssertTrue(try restarted.isHeld(scope: scope))
        XCTAssertTrue(try restarted.isHeld(scope: otherActor))
        XCTAssertFalse(try restarted.isHeld(scope: otherInvoice))
        XCTAssertFalse(try restarted.isHeld(scope: otherOrg))
        XCTAssertThrowsError(try restarted.confirmReceipt(scope: scope, operationID: hold.operationID, jobID: scope.invoice, attemptID: UUID().uuidString, amount: 1250, currency: "USD"))
    }

    func testOnlyExactBoundReceiptMayClearHold() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TapRecoveryStore(url: dir.appendingPathComponent("holds.json"))
        let scope = TapRecoveryScope(origin: "https://app.thorbis.com", organization: "018f0000-0000-7000-8000-00000000001a", actor: "018f0000-0000-7000-8000-00000000001b", invoice: "018f0000-0000-7000-8000-00000000001c")
        let id = UUID().uuidString
        let hold = try store.begin(scope: scope, jobID: scope.invoice, amount: 1250, currency: "USD")
        try store.bindAttempt(scope: scope, operationID: hold.operationID, jobID: scope.invoice, attemptID: id)
        XCTAssertThrowsError(try store.bindAttempt(scope: scope, operationID: hold.operationID, jobID: scope.invoice, attemptID: UUID().uuidString))
        XCTAssertThrowsError(try store.confirmReceipt(scope: scope, operationID: hold.operationID, jobID: scope.invoice, attemptID: id, amount: 1200, currency: "USD"))
        XCTAssertThrowsError(try store.confirmReceipt(scope: scope, operationID: hold.operationID, jobID: scope.invoice, attemptID: UUID().uuidString, amount: 1250, currency: "USD"))
        XCTAssertTrue(try store.isHeld(scope: scope))
        try store.confirmReceipt(scope: scope, operationID: hold.operationID, jobID: scope.invoice, attemptID: id, amount: 1250, currency: "USD")
        XCTAssertFalse(try store.isHeld(scope: scope))
    }

    func testWriteFailureAndCorruptStateThrow() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let scope = TapRecoveryScope(origin: "https://app.thorbis.com", organization: "018f0000-0000-7000-8000-00000000001a", actor: "018f0000-0000-7000-8000-00000000001b", invoice: "018f0000-0000-7000-8000-00000000001c")
        XCTAssertThrowsError(try TapRecoveryStore(url: dir.appendingPathComponent("holds.json")).begin(scope: scope, jobID: scope.invoice, amount: 1, currency: "USD"))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("holds.json")
        try Data("corrupt".utf8).write(to: file)
        XCTAssertThrowsError(try TapRecoveryStore(url: file).isHeld(scope: scope))
    }
}

import XCTest
@testable import Thorbis

@MainActor final class EstimateRecoveryCopyStoreTests: XCTestCase {
    private struct Scope: Codable, Equatable, Hashable { let actor, organization, origin, job: String }
    private struct Draft: Codable, Equatable { let title: String; let lines: [String] }

    func testScopedCopyCanReplayWithoutReplacingDifferentContent() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EstimateRecoveryCopyStore<Scope, Draft>(directory: directory)
        let first = Scope(actor: "a", organization: "one", origin: "https://example.test", job: "j")
        let other = Scope(actor: "a", organization: "two", origin: first.origin, job: first.job)
        let draft = Draft(title: "Unfinished", lines: ["Full details", "Additional work"]), id = UUID()
        let canonical = directory.appendingPathComponent("canonical.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("older saved version".utf8).write(to: canonical)
        try store.install(draft, scope: first, id: id)
        XCTAssertEqual(try store.list(scope: first), [id])
        XCTAssertEqual(try store.list(scope: other), [])
        XCTAssertEqual(try Data(contentsOf: canonical), Data("older saved version".utf8))
        XCTAssertEqual(try store.read(scope: first, id: id), draft)
        XCTAssertThrowsError(try store.read(scope: other, id: id))
        try store.install(draft, scope: first, id: id)
        XCTAssertThrowsError(try store.install(.init(title: "Different", lines: []), scope: first, id: id))
        XCTAssertEqual(try store.read(scope: first, id: id), draft)
    }
    func testReadbackFailureKeepsCopyForExactRetry() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scope = Scope(actor: "a", organization: "one", origin: "https://example.test", job: "j")
        let draft = Draft(title: "Unfinished", lines: ["Details"]), id = UUID()
        var fail = true
        let store = EstimateRecoveryCopyStore<Scope, Draft>(directory: directory, inspectRead: { data in
            if fail { throw CocoaError(.fileReadUnknown) }; return data
        })
        XCTAssertThrowsError(try store.install(draft, scope: scope, id: id))
        fail = false
        XCTAssertEqual(try store.read(scope: scope, id: id), draft)
        try store.install(draft, scope: scope, id: id)
    }

    func testUncertainAttemptRetriesSameIDAndRejectsChangedDraft() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scope = Scope(actor: "a", organization: "one", origin: "https://example.test", job: "j")
        let draft = Draft(title: "Unfinished", lines: ["Details"])
        var failRead = true, ids: [UUID] = []
        let store = EstimateRecoveryCopyStore<Scope, Draft>(directory: directory, inspectRead: { data in
            if failRead { throw CocoaError(.fileReadUnknown) }; return data
        })
        let attempts = EstimateRecoveryCopyAttempts<Scope, Draft>()
        XCTAssertThrowsError(try attempts.perform(draft, scope: scope) { id, value in
            ids.append(id); try store.install(value, scope: scope, id: id)
        })
        failRead = false
        XCTAssertThrowsError(try attempts.perform(.init(title: "Changed", lines: []), scope: scope) { id, value in
            ids.append(id); try store.install(value, scope: scope, id: id)
        })
        XCTAssertEqual(ids.count, 1)
        try attempts.perform(draft, scope: scope) { id, value in
            ids.append(id); try store.install(value, scope: scope, id: id)
        }
        XCTAssertEqual(ids.count, 2)
        XCTAssertEqual(ids[0], ids[1])
        XCTAssertEqual(try store.list(scope: scope), [ids[0]])
        XCTAssertEqual(try store.read(scope: scope, id: ids[0]), draft)
    }

    func testEditingSeparateCopyRetainsSourceAndScopesVolatileEdits() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scope = Scope(actor: "a", organization: "one", origin: "https://example.test", job: "j")
        let other = Scope(actor: "a", organization: "two", origin: scope.origin, job: scope.job)
        let source = Draft(title: "Original", lines: ["Long details"]), edited = Draft(title: "Edited", lines: ["Long details", "New item"])
        let sourceID = UUID(), store = EstimateRecoveryCopyStore<Scope, Draft>(directory: directory)
        let edits = VolatileDraftRecovery<RecoveryCopyEditKey<Scope>, Draft>()
        let attempts = EstimateRecoveryCopyAttempts<Scope, Draft>()
        try store.install(source, scope: scope, id: sourceID)
        let key = RecoveryCopyEditKey(scope: scope, sourceID: sourceID)
        edits.hold(edited, for: key)
        XCTAssertNil(edits.read(for: RecoveryCopyEditKey(scope: other, sourceID: sourceID)))
        var editedID: UUID?
        try attempts.perform(edited, scope: scope) { id, draft in
            editedID = id; try store.install(draft, scope: scope, id: id)
        }
        let id = try XCTUnwrap(editedID)
        XCTAssertNotEqual(id, sourceID)
        XCTAssertEqual(try store.read(scope: scope, id: sourceID), source)
        XCTAssertEqual(try store.read(scope: scope, id: id), edited)
        XCTAssertEqual(edits.read(for: key), edited)
    }

    func testUnchangedSeparateEditGetsDistinctIDAndRetryKeepsItsIdentity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scope = Scope(actor: "a", organization: "one", origin: "https://example.test", job: "j")
        let draft = Draft(title: "Unchanged", lines: ["Details"]), session = UUID()
        let attempts = EstimateRecoveryCopyAttempts<Scope, Draft>(), store = EstimateRecoveryCopyStore<Scope, Draft>(directory: directory)
        var source: UUID?, copied: UUID?, retried: UUID?
        try attempts.perform(draft, scope: scope) { id, value in source = id; try store.install(value, scope: scope, id: id) }
        try attempts.perform(draft, scope: scope, intentID: session) { id, value in copied = id; try store.install(value, scope: scope, id: id) }
        XCTAssertNotEqual(source, copied)
        try attempts.perform(draft, scope: scope, intentID: session) { id, value in retried = id; try store.install(value, scope: scope, id: id) }
        XCTAssertEqual(copied, retried)
        XCTAssertEqual(try store.read(scope: scope, id: XCTUnwrap(source)), draft)
        XCTAssertEqual(try store.read(scope: scope, id: XCTUnwrap(copied)), draft)
    }

    func testDiscardRequiresExactContentAndPreventsRetryResurrection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EstimateRecoveryCopyStore<Scope, Draft>(directory: directory)
        let scope = Scope(actor: "a", organization: "one", origin: "https://example.test", job: "j")
        let other = Scope(actor: "a", organization: "two", origin: scope.origin, job: scope.job)
        let draft = Draft(title: "Unfinished", lines: ["Details"]), id = UUID()
        try store.install(draft, scope: scope, id: id)
        XCTAssertThrowsError(try store.discard(.init(title: "Different", lines: []), scope: scope, id: id))
        XCTAssertThrowsError(try store.discard(draft, scope: other, id: id))
        XCTAssertEqual(try store.read(scope: scope, id: id), draft)
        try store.discard(draft, scope: scope, id: id)
        XCTAssertEqual(try store.list(scope: scope), [])
        XCTAssertThrowsError(try store.install(draft, scope: scope, id: id))
        try store.discard(draft, scope: scope, id: id)
    }
    func testUnconfirmedRemovalStaysHeldAndCanRetry() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scope = Scope(actor: "a", organization: "one", origin: "https://example.test", job: "j")
        let draft = Draft(title: "Unfinished", lines: ["Details"]), id = UUID()
        var fail = true
        let store = EstimateRecoveryCopyStore<Scope, Draft>(directory: directory, removeItem: { url in
            if fail { throw CocoaError(.fileWriteNoPermission) }
            try FileManager.default.removeItem(at: url)
        })
        try store.install(draft, scope: scope, id: id)
        XCTAssertThrowsError(try store.discard(draft, scope: scope, id: id))
        XCTAssertThrowsError(try store.install(draft, scope: scope, id: id))
        fail = false
        try store.discard(draft, scope: scope, id: id)
        XCTAssertEqual(try store.list(scope: scope), [])
    }

    func testInterruptedRemovalCanBeDiscoveredOnlyInOriginalScopeAndRetried() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scope = Scope(actor: "a", organization: "one", origin: "https://example.test", job: "j")
        let other = Scope(actor: "a", organization: "two", origin: scope.origin, job: scope.job)
        let draft = Draft(title: "Unfinished", lines: ["Details"]), id = UUID()
        let failing = EstimateRecoveryCopyStore<Scope, Draft>(directory: directory, removeItem: { _ in throw CocoaError(.fileWriteNoPermission) })
        try failing.install(draft, scope: scope, id: id)
        XCTAssertThrowsError(try failing.discard(draft, scope: scope, id: id))
        let reopened = EstimateRecoveryCopyStore<Scope, Draft>(directory: directory)
        let pending = try reopened.pendingDiscards(scope: scope)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.id, id)
        XCTAssertEqual(pending.first?.draft, draft)
        XCTAssertTrue(try reopened.pendingDiscards(scope: other).isEmpty)
        try reopened.discard(draft, scope: scope, id: id)
        XCTAssertTrue(try reopened.pendingDiscards(scope: scope).isEmpty)
        XCTAssertThrowsError(try reopened.install(draft, scope: scope, id: id))
    }

    func testDiscardCoordinatorRetainsIntentAndProtectsUnsavedEdits() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scope = Scope(actor: "a", organization: "one", origin: "https://example.test", job: "j")
        let draft = Draft(title: "Unfinished", lines: ["Details"])
        var fail = true, id: UUID?
        let store = EstimateRecoveryCopyStore<Scope, Draft>(directory: directory, removeItem: { url in
            if fail { throw CocoaError(.fileWriteNoPermission) }
            try FileManager.default.removeItem(at: url)
        })
        let saves = EstimateRecoveryCopyAttempts<Scope, Draft>(), discards = EstimateRecoveryCopyDiscardAttempts<Scope, Draft>()
        try saves.perform(draft, scope: scope) { savedID, value in id = savedID; try store.install(value, scope: scope, id: savedID) }
        let selected = try XCTUnwrap(id)
        XCTAssertThrowsError(try discards.perform(draft, scope: scope, id: selected, hasUnsavedEdits: true, saves: saves) { _, _ in XCTFail("Must protect edits") })
        XCTAssertThrowsError(try discards.perform(draft, scope: scope, id: selected, hasUnsavedEdits: false, saves: saves) { id, value in try store.discard(value, scope: scope, id: id) })
        XCTAssertNotNil(discards.pending(for: scope))
        XCTAssertThrowsError(try saves.perform(draft, scope: scope) { _, _ in XCTFail("Save must wait for the pending discard") })
        XCTAssertThrowsError(try discards.perform(.init(title: "Changed", lines: []), scope: scope, id: selected, hasUnsavedEdits: false, saves: saves) { _, _ in XCTFail("Must reject changed intent") })
        fail = false
        try discards.perform(draft, scope: scope, id: selected, hasUnsavedEdits: false, saves: saves) { id, value in try store.discard(value, scope: scope, id: id) }
        XCTAssertNil(discards.pending(for: scope))
        var replacement: UUID?
        try saves.perform(draft, scope: scope) { id, value in replacement = id; try store.install(value, scope: scope, id: id) }
        XCTAssertNotEqual(replacement, selected)
    }

}

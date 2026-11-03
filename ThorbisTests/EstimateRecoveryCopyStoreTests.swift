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

}

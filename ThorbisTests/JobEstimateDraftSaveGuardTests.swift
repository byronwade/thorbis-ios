import Foundation
import XCTest
@testable import Thorbis

@MainActor final class JobEstimateDraftSaveGuardTests: XCTestCase {
    func testFailedWriteKeepsPriorDraftUntilRetryIsReadable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let scope = CommercialDraftScope(actor: UUID().uuidString, organization: UUID().uuidString,
                                         origin: "https://example.test", kind: "new-estimate", document: "job:test")
        var fail = false
        let store = CommercialDraftStore(directory: root, writeItem: { data, url in
            if fail { throw CocoaError(.fileWriteNoPermission) }
            try data.write(to: url, options: .atomic)
        })
        try store.save("previous", scope: scope)
        var gate = JobEstimateDraftSaveGuard()
        fail = true
        XCTAssertFalse(gate.attempt { try store.save("current edits", scope: scope) })
        XCTAssertTrue(gate.requiresRetry)
        XCTAssertEqual(try store.load(String.self, scope: scope), "previous")
        fail = false
        XCTAssertTrue(gate.attempt { try store.save("current edits", scope: scope) })
        XCTAssertFalse(gate.requiresRetry)
        XCTAssertEqual(try CommercialDraftStore(directory: root).load(String.self, scope: scope), "current edits")
    }
}

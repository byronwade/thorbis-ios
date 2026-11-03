import Foundation
import XCTest
@testable import Thorbis

final class CommercialDraftStoreTests: XCTestCase {
    private struct Unencodable: Codable {
        func encode(to encoder: Encoder) throws { throw CocoaError(.fileWriteUnknown) }
        init(from decoder: Decoder) throws {}
        init() {}
    }
    @MainActor func testDraftSurvivesNewStoreAndIsIsolatedByActorWorkspaceOriginAndDocument() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CommercialDraftStore(directory: root)
        let scope = CommercialDraftScope(actor: "a", organization: "o", origin: "https://one.example", kind: "estimate", document: "e")
        let text = "paragraph one\n\nparagraph two 🛠"
        try store.save(text, scope: scope)
        XCTAssertEqual(try CommercialDraftStore(directory: root).load(String.self, scope: scope), text)
        for other in [
            CommercialDraftScope(actor: "b", organization: "o", origin: scope.origin, kind: "estimate", document: "e"),
            CommercialDraftScope(actor: "a", organization: "p", origin: scope.origin, kind: "estimate", document: "e"),
            CommercialDraftScope(actor: "a", organization: "o", origin: "https://other.example", kind: "estimate", document: "e"),
            CommercialDraftScope(actor: "a", organization: "o", origin: scope.origin, kind: "invoice", document: "e"),
            CommercialDraftScope(actor: "a", organization: "o", origin: scope.origin, kind: "estimate", document: "f")
        ] { XCTAssertNil(try store.load(String.self, scope: other)) }
        try store.remove(scope: scope)
        XCTAssertNil(try store.load(String.self, scope: scope))
    }
    @MainActor func testFailedReplacementLeavesExistingDraftIntact() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CommercialDraftStore(directory: root)
        let scope = CommercialDraftScope(actor: "a", organization: "o", origin: "https://one.example", kind: "invoice", document: "i")
        try store.save("original content", scope: scope)
        XCTAssertThrowsError(try store.save(Unencodable(), scope: scope))
        XCTAssertEqual(try store.load(String.self, scope: scope), "original content")
    }
    @MainActor func testOnlyOneEditorCanOwnTheSameDraftAtOnce() {
        let store = CommercialDraftStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let scope = CommercialDraftScope(actor: "a", organization: "o", origin: "https://one.example", kind: "estimate", document: "e")
        let first = UUID(), other = UUID()
        XCTAssertTrue(store.acquire(scope: scope, owner: first))
        XCTAssertFalse(store.acquire(scope: scope, owner: other))
        store.release(scope: scope, owner: other)
        XCTAssertFalse(store.acquire(scope: scope, owner: other))
        store.release(scope: scope, owner: first)
        XCTAssertTrue(store.acquire(scope: scope, owner: other))
    }
    @MainActor func testCleanupFailureKeepsUnknownCreateMarkerForReopen() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let scope = CommercialDraftScope(actor: "a", organization: "o", origin: "https://one.example", kind: "new-estimate", document: "j")
        let store = CommercialDraftStore(directory: root, removeItem: { _ in throw CocoaError(.fileWriteNoPermission) })
        let draft = CommercialNewEstimateDraft(customerID: "c", title: "Work", lines: [], uncertain: true, created: nil, requiresLocationVerification: false, requiresManualReview: false, requiresGroupDisclosure: false, acceptedGroupLoss: false)
        try store.save(draft, scope: scope)
        XCTAssertThrowsError(try store.remove(scope: scope))
        let reopened = try XCTUnwrap(CommercialDraftStore(directory: root).load(CommercialNewEstimateDraft.self, scope: scope))
        XCTAssertTrue(reopened.uncertain)
        XCTAssertNil(reopened.created)
    }
}

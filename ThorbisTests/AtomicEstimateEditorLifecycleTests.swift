import XCTest
@testable import Thorbis

@MainActor final class AtomicEstimateEditorLifecycleTests: XCTestCase {
    private let actor = "018f0000-0000-7000-8000-000000000002"
    private let org = "018f0000-0000-7000-8000-000000000001"
    private let job = "018f0000-0000-7000-8000-000000000003"
    private let origin = "https://example.test"
    private var scope: CommercialDraftScope { .init(actor: actor, organization: org, origin: origin, kind: "new-estimate", document: "job:\(job)|customer:\(actor)|location:") }
    private var draft: CommercialNewEstimateDraft {
        .init(customerID: actor, title: "Repair", lines: [.init(description: "Valve", quantity: "1", unitPrice: "1.00", source: .manual)],
              uncertain: false, created: nil, requiresLocationVerification: false, requiresManualReview: false,
              requiresGroupDisclosure: false, acceptedGroupLoss: false)
    }
    private func lifecycle(_ store: CommercialDraftStore, owner: UUID = UUID()) -> AtomicEstimateEditorLifecycle {
        .init(store: store, draftScope: scope, owner: owner, actorID: actor, organizationID: org,
              origin: origin, jobID: job, customerID: actor, locationID: nil)
    }
    func testFailedCloseKeepsLeaseAndDraftUntilSuccessfulRetry() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        var fail = false
        let store = CommercialDraftStore(directory: root, writeItem: { data, url in
            if fail { throw CocoaError(.fileWriteNoPermission) }
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        })
        let owner = UUID(), editor = lifecycle(store, owner: owner)
        try editor.open(); try editor.save(draft); fail = true
        XCTAssertThrowsError(try editor.close(preserving: draft))
        XCTAssertEqual(editor.state, .saveFailed)
        XCTAssertTrue(store.isCoordinatedOwner(scope: scope, owner: owner))
        XCTAssertFalse(try CommercialDraftStore(directory: root).acquireCoordinatedDraft(scope: scope, owner: UUID()))
        fail = false; try editor.close(preserving: draft)
        XCTAssertEqual(editor.state, .closed)
        XCTAssertFalse(store.isOwned(scope: scope, owner: owner))
        XCTAssertEqual(try store.load(CommercialNewEstimateDraft.self, scope: scope)?.title, "Repair")
    }
    func testLegacyPendingPreventsRestageAndSurvivesReopen() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let store = CommercialDraftStore(directory: root), editor = lifecycle(store)
        try editor.open(); try editor.stageLegacy(draft: draft, attemptID: UUID())
        XCTAssertEqual(editor.state, .attemptPending)
        XCTAssertThrowsError(try editor.save(draft))
        XCTAssertThrowsError(try editor.stageLegacy(draft: draft, attemptID: UUID()))
        try editor.close(preserving: draft)
        let reopened = lifecycle(store); try reopened.open()
        XCTAssertEqual(reopened.state, .attemptPending)
        try reopened.close(preserving: draft)
    }
    func testAmbiguousMarkerWriteDoesNotPermitRetry() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let store = CommercialDraftStore(directory: root, writeItem: { data, url in
            if url.pathExtension == "tmp" { throw CocoaError(.fileWriteNoPermission) }
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        })
        let editor = lifecycle(store); try editor.open()
        XCTAssertThrowsError(try editor.stageLegacy(draft: draft, attemptID: UUID()))
        XCTAssertEqual(editor.state, .stageUncertain)
        XCTAssertThrowsError(try editor.stageLegacy(draft: draft, attemptID: UUID()))
        XCTAssertThrowsError(try editor.close(preserving: draft))
        XCTAssertEqual(try store.load(CommercialNewEstimateDraft.self, scope: scope)?.title, "Repair")
    }
    func testLegacyUncertainDraftRemainsHeldEvenWhenMarkerIsMissing() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let store = CommercialDraftStore(directory: root)
        let unknown = CommercialNewEstimateDraft(customerID: actor, title: "Previous", lines: [], uncertain: true,
            created: nil, requiresLocationVerification: false, requiresManualReview: false,
            requiresGroupDisclosure: false, acceptedGroupLoss: false)
        try store.save(unknown, scope: scope)
        let editor = lifecycle(store); try editor.open()
        XCTAssertEqual(editor.state, .attemptPending)
        XCTAssertThrowsError(try editor.save(draft))
        XCTAssertThrowsError(try editor.stageLegacy(draft: draft, attemptID: UUID()))
        try editor.close(preserving: draft)
        let restored = try XCTUnwrap(store.load(CommercialNewEstimateDraft.self, scope: scope))
        XCTAssertTrue(restored.uncertain)
        XCTAssertEqual(restored.title, "Previous")
    }
}

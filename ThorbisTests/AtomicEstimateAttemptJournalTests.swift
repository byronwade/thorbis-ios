import XCTest
@testable import Thorbis

@MainActor final class AtomicEstimateAttemptJournalTests: XCTestCase {
    private let actor = "018f0000-0000-7000-8000-000000000002"
    private let org = "018f0000-0000-7000-8000-000000000001"
    private let job = "018f0000-0000-7000-8000-000000000003"
    private let origin = "https://example.test"
    private var sourceScope: CommercialDraftScope { .init(actor: actor, organization: org, origin: origin, kind: "new-estimate", document: "job:\(job)|customer:\(actor)|location:") }
    private func operation(_ id: String = "018f0000-0000-7000-8000-000000000004") throws -> AtomicEstimateCommand {
        try .make(jobID: job, draftCustomerID: actor, draftLocationID: nil, title: "Repair",
                  lines: [.init(description: "Valve", quantity: 1, unitPrice: .init(amount: 100, currency: "USD"), source: .manual, group: nil, showToCustomer: nil)],
                  actorID: actor, organizationID: org, deviceID: actor, policyVersion: 1, origin: origin,
                  createdAt: "2026-11-03T00:00:00Z", commandID: id)
    }
    private func draft(title: String = "Repair", uncertain: Bool = false) -> CommercialNewEstimateDraft {
        .init(customerID: actor, title: title, lines: [.init(description: "Valve", quantity: "1", unitPrice: "1.00", source: .manual)], uncertain: uncertain, created: nil,
              requiresLocationVerification: false, requiresManualReview: false, requiresGroupDisclosure: false, acceptedGroupLoss: false)
    }
    func testPrepareAndReopenPreserveExactOperationAndDraft() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let op = try operation(), store = CommercialDraftStore(directory: root), owner = UUID()
        XCTAssertTrue(try store.acquireCoordinatedDraft(scope: sourceScope, owner: owner)); try store.saveCoordinatedDraft(draft(), scope: sourceScope, owner: owner)
        let journal = AtomicEstimateAttemptJournal(store: store)
        let saved = try journal.prepare(operation: op, draftScope: sourceScope, draftOwner: owner, actorID: actor, organizationID: org, origin: origin, jobID: job, storesLineGroups: false)
        let reopened = AtomicEstimateAttemptJournal(store: CommercialDraftStore(directory: root))
        XCTAssertEqual(try reopened.recover(actorID: actor, organizationID: org, origin: origin, jobID: job), saved)
        XCTAssertEqual(try journal.prepare(operation: op, draftScope: sourceScope, draftOwner: owner, actorID: actor, organizationID: org, origin: origin, jobID: job, storesLineGroups: false), saved)
        XCTAssertThrowsError(try journal.prepare(operation: operation("018f0000-0000-7000-8000-000000000005"), draftScope: sourceScope, draftOwner: owner, actorID: actor, organizationID: org, origin: origin, jobID: job, storesLineGroups: false))
        XCTAssertNil(try reopened.recover(actorID: actor, organizationID: org, origin: "https://other.test", jobID: job))
        XCTAssertEqual(try reopened.recover(actorID: actor, organizationID: org, origin: origin, jobID: job), saved)
        try store.saveCoordinatedDraft(draft(uncertain: true), scope: sourceScope, owner: owner)
        XCTAssertThrowsError(try journal.prepare(operation: op, draftScope: sourceScope, draftOwner: owner, actorID: actor, organizationID: org, origin: origin, jobID: job, storesLineGroups: false))
    }
    func testMissingOwnerOrStoredDraftCannotPrepare() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let store = CommercialDraftStore(directory: root), journal = AtomicEstimateAttemptJournal(store: store), op = try operation(), owner = UUID()
        XCTAssertThrowsError(try journal.prepare(operation: op, draftScope: sourceScope, draftOwner: owner, actorID: actor, organizationID: org, origin: origin, jobID: job, storesLineGroups: false))
        XCTAssertTrue(try store.acquireCoordinatedDraft(scope: sourceScope, owner: owner))
        XCTAssertThrowsError(try journal.prepare(operation: op, draftScope: sourceScope, draftOwner: owner, actorID: actor, organizationID: org, origin: origin, jobID: job, storesLineGroups: false))
        try store.saveCoordinatedDraft(draft(title: "Different"), scope: sourceScope, owner: owner)
        XCTAssertThrowsError(try journal.prepare(operation: op, draftScope: sourceScope, draftOwner: owner, actorID: actor, organizationID: org, origin: origin, jobID: job, storesLineGroups: false))
        XCTAssertNil(try journal.recover(actorID: actor, organizationID: org, origin: origin, jobID: job))
    }
    func testCorruptSavedAttemptNeverBecomesAbsence() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let op = try operation(), store = CommercialDraftStore(directory: root), journal = AtomicEstimateAttemptJournal(store: store), owner = UUID()
        XCTAssertTrue(try store.acquireCoordinatedDraft(scope: sourceScope, owner: owner)); try store.saveCoordinatedDraft(draft(), scope: sourceScope, owner: owner)
        _ = try journal.prepare(operation: op, draftScope: sourceScope, draftOwner: owner, actorID: actor, organizationID: org, origin: origin, jobID: job, storesLineGroups: false)
        let key = CommercialDraftScope(actor: actor, organization: org, origin: origin, kind: "atomic-estimate-attempt", document: job)
        try store.save("wrong record", scope: key)
        XCTAssertThrowsError(try journal.recover(actorID: actor, organizationID: org, origin: origin, jobID: job))
        XCTAssertThrowsError(try journal.prepare(operation: op, draftScope: sourceScope, draftOwner: owner, actorID: actor, organizationID: org, origin: origin, jobID: job, storesLineGroups: false))
    }
    func testFailedAttemptWritePreservesTheSourceDraft() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        var failWrites = false
        let store = CommercialDraftStore(directory: root, writeItem: { data, url in
            if failWrites { throw CocoaError(.fileWriteNoPermission) }
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        })
        let journal = AtomicEstimateAttemptJournal(store: store), owner = UUID(), op = try operation()
        XCTAssertTrue(try store.acquireCoordinatedDraft(scope: sourceScope, owner: owner)); try store.saveCoordinatedDraft(draft(), scope: sourceScope, owner: owner)
        failWrites = true
        XCTAssertThrowsError(try journal.prepare(operation: op, draftScope: sourceScope, draftOwner: owner, actorID: actor, organizationID: org, origin: origin, jobID: job, storesLineGroups: false))
        XCTAssertNil(try journal.recover(actorID: actor, organizationID: org, origin: origin, jobID: job))
        XCTAssertEqual(try store.load(CommercialNewEstimateDraft.self, scope: sourceScope)?.title, "Repair")
    }
    func testRejectsChangedLineTermsAndCatalogProvenanceWithoutWritingAttempt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let store = CommercialDraftStore(directory: root), journal = AtomicEstimateAttemptJournal(store: store), owner = UUID()
        let item = "018f0000-0000-7000-8000-000000000007", otherItem = "018f0000-0000-7000-8000-000000000008"
        let line = EstimateRevisionLineDraft(description: "Valve", quantity: "2", unitPrice: "12.50",
            source: .priceBookSelection(itemID: item, revision: 3), group: .material, showToCustomer: false)
        let savedDraft = CommercialNewEstimateDraft(customerID: actor, title: "Repair", lines: [line], uncertain: false, created: nil,
            requiresLocationVerification: false, requiresManualReview: false, requiresGroupDisclosure: false, acceptedGroupLoss: false)
        XCTAssertTrue(try store.acquireCoordinatedDraft(scope: sourceScope, owner: owner)); try store.saveCoordinatedDraft(savedDraft, scope: sourceScope, owner: owner)
        func make(_ line: AtomicEstimateCommand.Line) throws -> AtomicEstimateCommand {
            try .make(jobID: job, draftCustomerID: actor, draftLocationID: nil, title: "Repair", lines: [line], actorID: actor,
                      organizationID: org, deviceID: actor, policyVersion: 1, origin: origin,
                      createdAt: "2026-11-03T00:00:00Z", commandID: "018f0000-0000-7000-8000-000000000004")
        }
        func itemLine(_ description: String = "Valve", _ quantity: Int = 2, _ cents: Int = 1250,
                      _ source: AtomicEstimateCommand.Source = .priceBook(itemID: item, revision: 3),
                      _ group: String? = "material", _ visible: Bool? = false) -> AtomicEstimateCommand.Line {
            .init(description: description, quantity: quantity, unitPrice: .init(amount: cents, currency: "USD"), source: source, group: group, showToCustomer: visible)
        }
        let mismatches = [itemLine("Other"), itemLine("Valve", 3), itemLine("Valve", 2, 1251),
                          itemLine("Valve", 2, 1250, .manual), itemLine("Valve", 2, 1250, .priceBook(itemID: otherItem, revision: 3)),
                          itemLine("Valve", 2, 1250, .priceBook(itemID: item, revision: 4)),
                          itemLine("Valve", 2, 1250, .priceBook(itemID: item, revision: 3), "work"),
                          itemLine("Valve", 2, 1250, .priceBook(itemID: item, revision: 3), "material", nil)]
        for line in mismatches {
            XCTAssertThrowsError(try journal.prepare(operation: make(line), draftScope: sourceScope, draftOwner: owner,
                actorID: actor, organizationID: org, origin: origin, jobID: job, storesLineGroups: true))
            XCTAssertNil(try journal.recover(actorID: actor, organizationID: org, origin: origin, jobID: job))
        }
        XCTAssertThrowsError(try journal.prepare(operation: make(itemLine()), draftScope: sourceScope, draftOwner: owner,
            actorID: actor, organizationID: org, origin: origin, jobID: job, storesLineGroups: false))
        let good = try journal.prepare(operation: make(itemLine()), draftScope: sourceScope, draftOwner: owner,
            actorID: actor, organizationID: org, origin: origin, jobID: job, storesLineGroups: true)
        XCTAssertEqual(good.operation.payload.lines, [itemLine()])
    }
    func testInvalidOrUnsupportedSavedLineCannotPrepare() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let store = CommercialDraftStore(directory: root), journal = AtomicEstimateAttemptJournal(store: store), owner = UUID(), op = try operation()
        XCTAssertTrue(try store.acquireCoordinatedDraft(scope: sourceScope, owner: owner))
        let invalid = [
            EstimateRevisionLineDraft(description: "Valve", quantity: "0", unitPrice: "1.00", source: .manual),
            EstimateRevisionLineDraft(description: "Valve", quantity: "1", unitPrice: "bad", source: .manual),
            EstimateRevisionLineDraft(description: "Valve", quantity: "1", unitPrice: "-1.00", source: .manual),
            EstimateRevisionLineDraft(description: "Valve", quantity: "1", unitPrice: "1.00", source: .unsupported("future")),
        ]
        for line in invalid {
            try store.saveCoordinatedDraft(CommercialNewEstimateDraft(customerID: actor, title: "Repair", lines: [line], uncertain: false,
                created: nil, requiresLocationVerification: false, requiresManualReview: false,
                requiresGroupDisclosure: false, acceptedGroupLoss: false), scope: sourceScope, owner: owner)
            XCTAssertThrowsError(try journal.prepare(operation: op, draftScope: sourceScope, draftOwner: owner,
                actorID: actor, organizationID: org, origin: origin, jobID: job, storesLineGroups: false))
            XCTAssertNil(try journal.recover(actorID: actor, organizationID: org, origin: origin, jobID: job))
        }
    }
    func testAttemptLockExcludesAnotherStoreAndCreateOnlyNeverReplaces() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let first = CommercialDraftStore(directory: root), second = CommercialDraftStore(directory: root)
        let key = CommercialDraftScope(actor: actor, organization: org, origin: origin, kind: "atomic-estimate-attempt", document: job)
        try first.withAttemptLock(scope: key) {
            XCTAssertThrowsError(try second.withAttemptLock(scope: key) { XCTFail("contending lock entered") })
            try first.createAttempt("first", scope: key)
            XCTAssertThrowsError(try first.createAttempt("second", scope: key))
            XCTAssertEqual(try first.load(String.self, scope: key), "first")
        }
        XCTAssertEqual(try second.withAttemptLock(scope: key) { try second.load(String.self, scope: key) }, "first")
    }
    func testLegacyMarkerBlocksAtomicAttemptAndRemainsUnresolvedAfterReopen() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let store = CommercialDraftStore(directory: root), journal = AtomicEstimateAttemptJournal(store: store), owner = UUID()
        XCTAssertTrue(try store.acquireCoordinatedDraft(scope: sourceScope, owner: owner)); try store.saveCoordinatedDraft(draft(), scope: sourceScope, owner: owner)
        let id = UUID()
        let staged = try journal.stageLegacy(draftScope: sourceScope, draftOwner: owner, actorID: actor,
            organizationID: org, origin: origin, jobID: job, customerID: actor, locationID: nil, attemptID: id)
        XCTAssertEqual(staged.attemptID, id)
        XCTAssertThrowsError(try journal.stageLegacy(draftScope: sourceScope, draftOwner: owner, actorID: actor,
            organizationID: org, origin: origin, jobID: job, customerID: actor, locationID: nil, attemptID: id))
        XCTAssertThrowsError(try journal.prepare(operation: operation(), draftScope: sourceScope, draftOwner: owner,
            actorID: actor, organizationID: org, origin: origin, jobID: job, storesLineGroups: false))
        let reopened = AtomicEstimateAttemptJournal(store: CommercialDraftStore(directory: root))
        guard case .legacyPending(let recovered) = try reopened.status(actorID: actor, organizationID: org, origin: origin, jobID: job) else { return XCTFail("Legacy attempt was lost") }
        XCTAssertEqual(recovered, staged)
        XCTAssertThrowsError(try reopened.recover(actorID: actor, organizationID: org, origin: origin, jobID: job))
        XCTAssertThrowsError(try journal.stageLegacy(draftScope: sourceScope, draftOwner: owner, actorID: actor,
            organizationID: org, origin: origin, jobID: job, customerID: actor, locationID: nil, attemptID: UUID()))
    }
    func testAtomicMarkerBlocksLegacyAndMalformedMarkerDoesNotLookMissing() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let store = CommercialDraftStore(directory: root), journal = AtomicEstimateAttemptJournal(store: store), owner = UUID()
        XCTAssertTrue(try store.acquireCoordinatedDraft(scope: sourceScope, owner: owner)); try store.saveCoordinatedDraft(draft(), scope: sourceScope, owner: owner)
        let saved = try journal.prepare(operation: operation(), draftScope: sourceScope, draftOwner: owner,
            actorID: actor, organizationID: org, origin: origin, jobID: job, storesLineGroups: false)
        XCTAssertThrowsError(try journal.stageLegacy(draftScope: sourceScope, draftOwner: owner, actorID: actor,
            organizationID: org, origin: origin, jobID: job, customerID: actor, locationID: nil, attemptID: UUID()))
        guard case .atomicPending(let current) = try journal.status(actorID: actor, organizationID: org, origin: origin, jobID: job) else { return XCTFail("Atomic attempt was lost") }
        XCTAssertEqual(current, saved)
        let key = CommercialDraftScope(actor: actor, organization: org, origin: origin, kind: "atomic-estimate-attempt", document: job)
        try store.save("invalid marker", scope: key)
        XCTAssertThrowsError(try journal.status(actorID: actor, organizationID: org, origin: origin, jobID: job))
    }
    func testSourceLeaseBlocksCoordinatedWritersWithoutBlockingOtherDrafts() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let first = CommercialDraftStore(directory: root), second = CommercialDraftStore(directory: root), owner = UUID(), secondOwner = UUID()
        try first.save("original", scope: sourceScope)
        XCTAssertTrue(try first.acquireCoordinatedDraft(scope: sourceScope, owner: owner))
        XCTAssertFalse(try second.acquireCoordinatedDraft(scope: sourceScope, owner: secondOwner))
        let caseVariant = CommercialDraftScope(actor: actor.uppercased(), organization: org.uppercased(),
            origin: origin.uppercased(), kind: "new-estimate", document: sourceScope.document.uppercased())
        XCTAssertFalse(try second.acquireCoordinatedDraft(scope: caseVariant, owner: secondOwner))
        XCTAssertThrowsError(try second.saveCoordinatedDraft("overwritten", scope: sourceScope, owner: secondOwner))
        XCTAssertThrowsError(try second.removeCoordinatedDraft(scope: sourceScope, owner: secondOwner))
        let other = CommercialDraftScope(actor: actor, organization: org, origin: origin, kind: "new-estimate", document: "job:other")
        try second.save("other", scope: other)
        XCTAssertEqual(try first.load(String.self, scope: sourceScope), "original")
        first.release(scope: sourceScope, owner: owner)
        XCTAssertTrue(try second.acquireCoordinatedDraft(scope: sourceScope, owner: secondOwner))
        try second.saveCoordinatedDraft("after", scope: sourceScope, owner: secondOwner)
        second.release(scope: sourceScope, owner: secondOwner)
        XCTAssertEqual(try first.load(String.self, scope: sourceScope), "after")
    }
    func testExistingUncoordinatedWriterBehaviorRemainsUnchanged() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let held = CommercialDraftStore(directory: root), legacy = CommercialDraftStore(directory: root), owner = UUID()
        XCTAssertTrue(try held.acquireCoordinatedDraft(scope: sourceScope, owner: owner))
        // This deliberately demonstrates why the prototype is not ready to wire:
        // the existing editor has not adopted the long-lived lease yet.
        try legacy.save("legacy", scope: sourceScope)
        XCTAssertEqual(try held.load(String.self, scope: sourceScope), "legacy")
        try legacy.remove(scope: sourceScope)
        XCTAssertNil(try held.load(String.self, scope: sourceScope))
        held.release(scope: sourceScope, owner: owner)
    }
}

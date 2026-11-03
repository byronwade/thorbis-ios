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
                  lines: [.init(description: "Valve", quantity: 1, unitPrice: .init(amount: 100, currency: "USD"), source: nil, group: nil, showToCustomer: nil)],
                  actorID: actor, organizationID: org, deviceID: actor, policyVersion: 1, origin: origin,
                  createdAt: "2026-11-03T00:00:00Z", commandID: id)
    }
    private func draft(title: String = "Repair", uncertain: Bool = false) -> CommercialNewEstimateDraft {
        .init(customerID: actor, title: title, lines: [], uncertain: uncertain, created: nil,
              requiresLocationVerification: false, requiresManualReview: false, requiresGroupDisclosure: false, acceptedGroupLoss: false)
    }
    func testPrepareAndReopenPreserveExactOperationAndDraft() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let op = try operation(), store = CommercialDraftStore(directory: root), owner = UUID()
        XCTAssertTrue(store.acquire(scope: sourceScope, owner: owner)); try store.save(draft(), scope: sourceScope)
        let journal = AtomicEstimateAttemptJournal(store: store)
        let saved = try journal.prepare(operation: op, draftScope: sourceScope, draftOwner: owner, actorID: actor, organizationID: org, origin: origin, jobID: job)
        let reopened = AtomicEstimateAttemptJournal(store: CommercialDraftStore(directory: root))
        XCTAssertEqual(try reopened.recover(actorID: actor, organizationID: org, origin: origin, jobID: job), saved)
        XCTAssertEqual(try journal.prepare(operation: op, draftScope: sourceScope, draftOwner: owner, actorID: actor, organizationID: org, origin: origin, jobID: job), saved)
        XCTAssertThrowsError(try journal.prepare(operation: operation("018f0000-0000-7000-8000-000000000005"), draftScope: sourceScope, draftOwner: owner, actorID: actor, organizationID: org, origin: origin, jobID: job))
        XCTAssertNil(try reopened.recover(actorID: actor, organizationID: org, origin: "https://other.test", jobID: job))
        XCTAssertEqual(try reopened.recover(actorID: actor, organizationID: org, origin: origin, jobID: job), saved)
        try store.save(draft(uncertain: true), scope: sourceScope)
        XCTAssertThrowsError(try journal.prepare(operation: op, draftScope: sourceScope, draftOwner: owner, actorID: actor, organizationID: org, origin: origin, jobID: job))
    }
    func testMissingOwnerOrStoredDraftCannotPrepare() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let store = CommercialDraftStore(directory: root), journal = AtomicEstimateAttemptJournal(store: store), op = try operation(), owner = UUID()
        XCTAssertThrowsError(try journal.prepare(operation: op, draftScope: sourceScope, draftOwner: owner, actorID: actor, organizationID: org, origin: origin, jobID: job))
        XCTAssertTrue(store.acquire(scope: sourceScope, owner: owner))
        XCTAssertThrowsError(try journal.prepare(operation: op, draftScope: sourceScope, draftOwner: owner, actorID: actor, organizationID: org, origin: origin, jobID: job))
        try store.save(draft(title: "Different"), scope: sourceScope)
        XCTAssertThrowsError(try journal.prepare(operation: op, draftScope: sourceScope, draftOwner: owner, actorID: actor, organizationID: org, origin: origin, jobID: job))
        XCTAssertNil(try journal.recover(actorID: actor, organizationID: org, origin: origin, jobID: job))
    }
    func testCorruptSavedAttemptNeverBecomesAbsence() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let op = try operation(), store = CommercialDraftStore(directory: root), journal = AtomicEstimateAttemptJournal(store: store), owner = UUID()
        XCTAssertTrue(store.acquire(scope: sourceScope, owner: owner)); try store.save(draft(), scope: sourceScope)
        _ = try journal.prepare(operation: op, draftScope: sourceScope, draftOwner: owner, actorID: actor, organizationID: org, origin: origin, jobID: job)
        let key = CommercialDraftScope(actor: actor, organization: org, origin: origin, kind: "atomic-estimate-attempt", document: job)
        try store.save("wrong record", scope: key)
        XCTAssertThrowsError(try journal.recover(actorID: actor, organizationID: org, origin: origin, jobID: job))
        XCTAssertThrowsError(try journal.prepare(operation: op, draftScope: sourceScope, draftOwner: owner, actorID: actor, organizationID: org, origin: origin, jobID: job))
    }
    func testFailedAttemptWritePreservesTheSourceDraft() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        var failWrites = false
        let store = CommercialDraftStore(directory: root, writeItem: { data, url in
            if failWrites { throw CocoaError(.fileWriteNoPermission) }
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        })
        let journal = AtomicEstimateAttemptJournal(store: store), owner = UUID(), op = try operation()
        XCTAssertTrue(store.acquire(scope: sourceScope, owner: owner)); try store.save(draft(), scope: sourceScope)
        failWrites = true
        XCTAssertThrowsError(try journal.prepare(operation: op, draftScope: sourceScope, draftOwner: owner, actorID: actor, organizationID: org, origin: origin, jobID: job))
        XCTAssertNil(try journal.recover(actorID: actor, organizationID: org, origin: origin, jobID: job))
        XCTAssertEqual(try store.load(CommercialNewEstimateDraft.self, scope: sourceScope)?.title, "Repair")
    }
}

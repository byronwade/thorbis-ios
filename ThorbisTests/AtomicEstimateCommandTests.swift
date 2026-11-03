import XCTest
@testable import Thorbis

@MainActor
final class AtomicEstimateCommandTests: XCTestCase {
    private let actor = "018f0000-0000-7000-8000-000000000002"
    private let org = "018f0000-0000-7000-8000-000000000001"
    private let job = "018f0000-0000-7000-8000-000000000003"
    private let command = "018f0000-0000-7000-8000-000000000004"
    private let estimate = "018f0000-0000-7000-8000-000000000005"
    private let link = "018f0000-0000-7000-8000-000000000006"

    private func operation() throws -> AtomicEstimateCommand {
        try .make(jobID: job, title: "Repair", lines: [.init(description: "Valve", quantity: 1,
            unitPrice: .init(amount: 1200, currency: "USD"), source: .manual,
            group: "material", showToCustomer: false)], actorID: actor, organizationID: org,
            deviceID: actor, policyVersion: 1, origin: "https://example.test",
            createdAt: "2026-11-03T00:00:00Z", commandID: command)
    }
    private func jobRecord(id: String? = nil, organization: String? = nil, customer: String? = nil,
                           location: String? = nil, status: String = "scheduled") throws -> JobRecord {
        var data: [String: Any] = ["id": id ?? job, "organizationId": organization ?? org,
                                   "customerId": customer ?? actor, "title": "Repair", "status": status,
                                   "createdAt": "2026-11-03T00:00:00Z", "updatedAt": "2026-11-03T00:00:00Z"]
        if let location { data["locationId"] = location }
        return try JSONDecoder().decode(JobRecord.self, from: JSONSerialization.data(withJSONObject: data))
    }

    func testExactJobCustomerLocationAndStatusRequired() throws {
        let operation = try operation()
        XCTAssertTrue(operation.matchesDraftJob(try jobRecord(location: estimate), customerID: actor, locationID: estimate))
        XCTAssertTrue(operation.matchesDraftJob(try jobRecord(), customerID: actor, locationID: nil))
        XCTAssertFalse(operation.matchesDraftJob(try jobRecord(id: link), customerID: actor, locationID: nil))
        XCTAssertFalse(operation.matchesDraftJob(try jobRecord(organization: link), customerID: actor, locationID: nil))
        XCTAssertFalse(operation.matchesDraftJob(try jobRecord(customer: link), customerID: actor, locationID: nil))
        XCTAssertFalse(operation.matchesDraftJob(try jobRecord(location: estimate), customerID: actor, locationID: nil))
        XCTAssertFalse(operation.matchesDraftJob(try jobRecord(), customerID: actor, locationID: estimate))
        XCTAssertFalse(operation.matchesDraftJob(try jobRecord(status: "canceled"), customerID: actor, locationID: nil))
        XCTAssertFalse(operation.matchesDraftJob(try jobRecord(status: "unknown"), customerID: actor, locationID: nil))
        XCTAssertFalse(operation.matchesDraftJob(try jobRecord(), customerID: "invalid", locationID: nil))
    }

    func testDurableCommandAndWirePreserveExactIntent() throws {
        let operation = try operation()
        XCTAssertEqual(try JSONDecoder().decode(AtomicEstimateCommand.self, from: JSONEncoder().encode(operation)), operation)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(operation.batch)) as? [String: Any])
        let envelope = try XCTUnwrap((object["commands"] as? [[String: Any]])?.first)
        XCTAssertEqual(envelope["command"] as? String, "jobs.createRelatedEstimate")
        XCTAssertEqual(envelope["commandId"] as? String, command)
        XCTAssertNil(envelope["origin"])
        let payload = try XCTUnwrap(envelope["payload"] as? [String: Any])
        XCTAssertEqual(payload["jobId"] as? String, job)
        let line = try XCTUnwrap((payload["lines"] as? [[String: Any]])?.first)
        XCTAssertEqual(line["showToCustomer"] as? Bool, false)
        XCTAssertEqual(line["group"] as? String, "material")
        XCTAssertFalse(AtomicEstimateCommand.productionEnabled)
    }

    func testBuilderAdapterPreservesCatalogAndPresentationFields() throws {
        let request = FieldEstimateCreate(customerId: actor, title: "Repair", lines: [
            .init(description: "Valve", quantity: 2, unitPrice: .init(amount: 1200, currency: "USD"),
                  source: .priceBookSelection(itemID: estimate, revision: 3), group: "material", showToCustomer: false)
        ])
        let command = try AtomicEstimateCommand.fromBuilder(jobID: job, request: request, actorID: actor,
            organizationID: org, deviceID: actor, policyVersion: 1, origin: "https://example.test",
            createdAt: "2026-11-03T00:00:00Z", commandID: self.command)
        XCTAssertEqual(command.payload.lines[0].source, .priceBook(itemID: estimate, revision: 3))
        XCTAssertEqual(command.payload.lines[0].group, "material")
        XCTAssertEqual(command.payload.lines[0].showToCustomer, false)
        let unsupported = FieldEstimateCreate(customerId: actor, title: "Repair", lines: [
            .init(description: "Valve", quantity: 1, unitPrice: .init(amount: 1200, currency: "USD"), source: .unsupported("future"))
        ])
        XCTAssertThrowsError(try AtomicEstimateCommand.fromBuilder(jobID: job, request: unsupported, actorID: actor,
            organizationID: org, deviceID: actor, policyVersion: 1, origin: "https://example.test",
            createdAt: "2026-11-03T00:00:00Z", commandID: self.command))
    }

    func testOnlySameAuthorizedScopeCanAttemptTheSameCommand() throws {
        let operation = try operation()
        XCTAssertTrue(operation.maySend(actorID: actor, organizationID: org, jobID: job, origin: "https://example.test", authorized: true))
        XCTAssertFalse(operation.maySend(actorID: actor, organizationID: org, jobID: job, origin: "https://other.test", authorized: true))
        XCTAssertFalse(operation.maySend(actorID: actor, organizationID: org, jobID: job, origin: "https://example.test", authorized: false))
    }

    func testMalformedRestoredOriginAndTimestampCannotBeSent() throws {
        let operation = try operation()
        let data = try JSONEncoder().encode(operation)
        var saved = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        saved["createdAt"] = "not-a-timestamp"
        var restored = try JSONDecoder().decode(AtomicEstimateCommand.self, from: JSONSerialization.data(withJSONObject: saved))
        XCTAssertFalse(restored.maySend(actorID: actor, organizationID: org, jobID: job, origin: "https://example.test", authorized: true))
        saved["createdAt"] = "2026-11-03T00:00:00Z"
        saved["origin"] = "https://user:password@example.test"
        restored = try JSONDecoder().decode(AtomicEstimateCommand.self, from: JSONSerialization.data(withJSONObject: saved))
        XCTAssertFalse(restored.maySend(actorID: actor, organizationID: org, jobID: job, origin: "https://user:password@example.test", authorized: true))
    }

    func testOnlyAnExactlyBoundAppliedOrDuplicateLinkIsVerified() throws {
        let operation = try operation()
        let good = AtomicEstimateCommand.Response.Outcome(commandId: command, status: "duplicate", category: nil,
            result: .init(id: link, organizationId: org, jobId: job, estimateId: estimate, linkedByUserId: actor))
        XCTAssertEqual(operation.interpret(.init(outcomes: [good])), .linked(estimateID: estimate, linkID: link))
        XCTAssertEqual(operation.interpret(.init(outcomes: [])), .unknown)
        XCTAssertEqual(operation.interpret(.init(outcomes: [.init(commandId: command, status: "rejected", category: "authorization", result: nil)])), .needsReview)
        let wrongJob = AtomicEstimateCommand.Response.Outcome(commandId: command, status: "applied", category: nil,
            result: .init(id: link, organizationId: org, jobId: actor, estimateId: estimate, linkedByUserId: actor))
        XCTAssertEqual(operation.interpret(.init(outcomes: [wrongJob])), .unknown)
    }

    func testTransportCannotSendWhileCapabilityIsHeld() async throws {
        let api = APIClient(baseURL: "https://app.thorbis.com")
        do {
            _ = try await api.sendAtomicEstimate(operation(), actorID: actor, organizationID: org,
                                                 job: jobRecord(), draftCustomerID: actor, draftLocationID: nil, authorized: true)
            XCTFail("The held command must not be sent")
        } catch AtomicEstimateCommand.Invalid.scope {
            // Capability is intentionally unavailable before server qualification.
        }
    }

    func testDraftRetainsOperationAndOldDraftsRemainReadable() throws {
        let operation = try operation()
        let draft = CommercialNewEstimateDraft(customerID: "c", title: "Repair", lines: [], uncertain: true,
            created: nil, requiresLocationVerification: false, requiresManualReview: false,
            requiresGroupDisclosure: false, acceptedGroupLoss: false, atomicOperation: operation)
        let encoded = try JSONEncoder().encode(draft)
        XCTAssertEqual(try JSONDecoder().decode(CommercialNewEstimateDraft.self, from: encoded).atomicOperation, operation)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "atomicOperation")
        XCTAssertNil(try JSONDecoder().decode(CommercialNewEstimateDraft.self, from: JSONSerialization.data(withJSONObject: legacy)).atomicOperation)
    }

    func testPendingCommandSurvivesFailedCleanupAndRemainsScoped() throws {
        let operation = try operation()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CommercialDraftStore(directory: root, removeItem: { _ in throw CocoaError(.fileWriteNoPermission) })
        let scope = CommercialDraftScope(actor: actor, organization: org, origin: "https://example.test", kind: "new-estimate", document: job)
        let draft = CommercialNewEstimateDraft(customerID: "c", title: "Repair", lines: [], uncertain: true,
            created: nil, requiresLocationVerification: false, requiresManualReview: false,
            requiresGroupDisclosure: false, acceptedGroupLoss: false, atomicOperation: operation)
        try store.save(draft, scope: scope)
        XCTAssertThrowsError(try store.remove(scope: scope))
        XCTAssertEqual(try store.load(CommercialNewEstimateDraft.self, scope: scope)?.atomicOperation, operation)
        let other = CommercialDraftScope(actor: actor, organization: org, origin: "https://other.test", kind: "new-estimate", document: job)
        XCTAssertNil(try store.load(CommercialNewEstimateDraft.self, scope: other))
    }
}

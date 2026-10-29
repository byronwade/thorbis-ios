import XCTest
@testable import Thorbis

@MainActor
final class CustomerEstimateReviewTests: XCTestCase {
    private let estimateID = "00000000-0000-4000-8000-000000000101"
    private let organizationID = "00000000-0000-4000-8000-000000000102"
    private let customerID = "00000000-0000-4000-8000-000000000103"
    private let locationID = "00000000-0000-4000-8000-000000000104"
    private let paperHash = String(repeating: "a", count: 64)

    func testReviewReadsCurrentAggregateThenExactImmutableTerms() async throws {
        let api = client([.init(200, try json(aggregate)), .init(200, try json(revision))])
        let review = try await api.customerIssuedEstimateRevision(for: localEstimate())
        XCTAssertEqual(review.title, "Server-priced drain repair")
        XCTAssertEqual(review.lines.first?.description, "Replace cleanout plug")
        XCTAssertEqual(review.lines.first?.quantity, 2)
        XCTAssertEqual(review.totalAmount, 13_200)
        XCTAssertEqual(URLProtocolFixture.recorded.map(\.url?.path), [
            "/v1/estimates/\(estimateID)", "/v1/estimates/\(estimateID)/revisions/2"
        ])
    }

    func testForeignAggregateIdentityCannotStartRevisionRead() async throws {
        for field in ["id", "organizationId", "customerId", "locationId"] {
            var foreign = aggregate
            foreign[field] = "00000000-0000-4000-8000-000000000999"
            let api = client([.init(200, try json(foreign)), .init(200, try json(revision))])
            await rejects { _ = try await api.customerIssuedEstimateRevision(for: self.localEstimate()) }
            XCTAssertEqual(URLProtocolFixture.recorded.count, 1, field)
        }
    }

    func testDraftOrDifferentCurrentRevisionCannotOpenOldIssuedPaper() async throws {
        for mutation: [String: Any] in [["status": "draft"], ["currentRevisionNumber": 3]] {
            var current = aggregate
            current.merge(mutation) { _, new in new }
            let api = client([.init(200, try json(current)), .init(200, try json(revision))])
            await rejects { _ = try await api.customerIssuedEstimateRevision(for: self.localEstimate()) }
            XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
        }
    }

    func testForeignOrSupersededRevisionCannotBecomeReviewedTerms() async throws {
        for mutation: [String: Any] in [
            ["estimateId": "00000000-0000-4000-8000-000000000999"],
            ["organizationId": "00000000-0000-4000-8000-000000000999"],
            ["customerId": "00000000-0000-4000-8000-000000000999"],
            ["locationId": NSNull()], ["revisionNumber": 1], ["status": "superseded"]
        ] {
            var foreign = revision
            foreign.merge(mutation) { _, new in new }
            let api = client([.init(200, try json(aggregate)), .init(200, try json(foreign))])
            await rejects { _ = try await api.customerIssuedEstimateRevision(for: self.localEstimate()) }
        }
    }

    func testChangedAPIContextStopsOpeningBeforeNextRead() async throws {
        let gate = URLProtocolFixture.Gate()
        defer { gate.release() }
        let api = client([.init(200, try json(aggregate), gate: gate), .init(200, try json(revision))])
        let task = Task { try await api.customerIssuedEstimateRevision(for: localEstimate()) }
        try await waitForRequests(1)
        api.invalidateRequests()
        gate.release()
        await rejects { _ = try await task.value }
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
    }

    func testLiveViewRevocationAfterAggregateStopsImmutableRevisionRead() async throws {
        let gate = URLProtocolFixture.Gate(); defer { gate.release() }
        let api = client([.init(200, try json(aggregate), gate: gate), .init(200, try json(revision))])
        var authorized = true
        let task = Task { try await api.customerIssuedEstimateRevision(for: localEstimate(), currentAuthority: { authorized }) }
        try await waitForRequests(1); authorized = false; gate.release()
        await rejects { _ = try await task.value }
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
    }
    func testLiveApprovalRevocationBetweenPaperTokenAndPublicReadStopsNextRequest() async throws {
        for gatedIndex in 0...2 {
            let gate = URLProtocolFixture.Gate(); defer { gate.release() }
            var responses = [URLProtocolFixture.Reply(200, try json(paper)), .init(200, #"{"token":"customer-token"}"#), .init(200, try json(action))]
            responses[gatedIndex] = .init(200, gatedIndex == 0 ? try json(paper) : gatedIndex == 1 ? #"{"token":"customer-token"}"# : try json(action), gate: gate)
            let api = client(responses), review = try decodedRevision()
            var authorized = true
            let task = Task { try await api.openInPersonEstimateApproval(review, currentAuthority: { authorized }) }
            try await waitForRequests(gatedIndex + 1); authorized = false; gate.release()
            await rejects { _ = try await task.value }
            XCTAssertEqual(URLProtocolFixture.recorded.count, gatedIndex + 1)
        }
    }
    func testMatchingPaperAndActionReturnTheExactSigningIdentity() async throws {
        let review = try decodedRevision()
        let api = client([.init(200, try json(paper)), .init(200, #"{"token":"customer-token"}"#), .init(200, try json(action))])
        let opened = try await api.openInPersonEstimateApproval(review)
        XCTAssertEqual(opened.token, "customer-token")
        XCTAssertEqual(opened.action.contentHash, paperHash)
        XCTAssertEqual(opened.action.revisionNumber, 2)
        XCTAssertEqual(URLProtocolFixture.recorded.map(\.url?.path), [
            "/v1/estimates/\(estimateID)/commercial-documents", "/v1/estimates/\(estimateID)/action-tokens",
            "/v1/public/document-actions/customer-token"
        ])
        let mint = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(URLProtocolFixture.recorded[1].body)) as? [String: Any])
        XCTAssertEqual(mint["revisionNumber"] as? Int, 2)
        XCTAssertEqual(mint["contentHash"] as? String, paperHash)
    }

    func testForeignPaperSourceOrRevisionStopsBeforeMinting() async throws {
        let review = try decodedRevision()
        for mutation: [String: Any] in [
            ["source": ["type": "invoice", "id": estimateID]],
            ["source": ["type": "estimate", "id": "00000000-0000-4000-8000-000000000999"]],
            ["snapshot": ["content": ["revision": ["number": 3]]]]
        ] {
            var foreign = paper
            foreign.merge(mutation) { _, new in new }
            let api = client([.init(200, try json(foreign))])
            await rejects { _ = try await api.openInPersonEstimateApproval(review) }
            XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
        }
    }

    func testSigningRejectsChangedPublicTermsAndFractionalMoney() async throws {
        let review = try decodedRevision()
        for mutation: [String: Any] in [
            ["contentHash": String(repeating: "b", count: 64)], ["revisionNumber": 3],
            ["title": "A different repair"], ["currency": "EUR"], ["totalAmount": 13_201],
            ["totalAmount": 13_200.5], ["status": "approved"], ["allowedActions": []],
            ["scopeLines": [["id": "line-1", "description": "Different work", "quantity": 2, "unitPrice": 6600]]]
        ] {
            var changed = action
            changed.merge(mutation) { _, new in new }
            let api = client([.init(200, try json(paper)), .init(200, #"{"token":"customer-token"}"#), .init(200, try json(changed))])
            await rejects { _ = try await api.openInPersonEstimateApproval(review) }
        }
    }

    func testOptionMetadataMustMatchEveryReviewedChoice() async throws {
        var object = revision
        let fullOption: [String: Any] = ["id": "option-1", "title": "Repair and protection", "description": "Includes a new cover",
                                       "lines": revision["lines"]!, "totalAmount": 13_200, "currency": "USD"]
        object["options"] = [fullOption]
        let review = try decodedRevision(object)
        let summary = fullOption.filter { $0.key != "lines" }
        var valid = action
        valid["options"] = [summary]
        valid["scopeLines"] = []
        let api = client([.init(200, try json(paper)), .init(200, #"{"token":"customer-token"}"#), .init(200, try json(valid))])
        _ = try await api.openInPersonEstimateApproval(review)
        for field in ["id", "title", "description", "currency", "totalAmount"] {
            var changed = summary
            changed[field] = field == "totalAmount" ? 13_201 : "Changed"
            var response = valid
            response["options"] = [changed]
            let mismatch = client([.init(200, try json(paper)), .init(200, #"{"token":"customer-token"}"#), .init(200, try json(response))])
            await rejects { _ = try await mismatch.openInPersonEstimateApproval(review) }
        }
    }

    func testChangedAPIContextStopsSigningBeforeMinting() async throws {
        let review = try decodedRevision()
        let gate = URLProtocolFixture.Gate()
        defer { gate.release() }
        let api = client([.init(200, try json(paper), gate: gate)])
        let task = Task { try await api.openInPersonEstimateApproval(review) }
        try await waitForRequests(1)
        api.invalidateRequests()
        gate.release()
        await rejects { _ = try await task.value }
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
    }

    private var aggregate: [String: Any] {
        ["id": estimateID, "organizationId": organizationID, "customerId": customerID, "createdByUserId": organizationID,
         "locationId": locationID, "status": "sent", "currentRevisionNumber": 2, "title": "Aggregate copy",
         "lines": revision["lines"]!, "options": [], "createdAt": "2026-10-28T00:00:00Z", "updatedAt": "2026-10-28T00:00:00Z"]
    }
    private var revision: [String: Any] {
        ["id": "00000000-0000-4000-8000-000000000105", "estimateId": estimateID, "organizationId": organizationID,
         "customerId": customerID, "locationId": locationID, "revisionNumber": 2, "status": "issued",
         "title": "Server-priced drain repair", "lines": [["id": "line-1", "description": "Replace cleanout plug", "quantity": 2,
         "unitPrice": ["amount": 6600, "currency": "USD"]]], "options": [], "totalAmount": 13_200, "currency": "USD",
         "issuedTo": customerID, "provenance": "command", "issuedAt": "2026-10-28T00:00:00Z"]
    }
    private var paper: [String: Any] {
        ["status": "issued", "source": ["type": "estimate", "id": estimateID], "contentHash": paperHash,
         "snapshot": ["content": ["revision": ["number": 2]]], "presentation": [:]]
    }
    private var action: [String: Any] {
        ["kind": "estimate", "title": "Server-priced drain repair", "status": "sent", "revisionNumber": 2,
         "contentHash": paperHash, "allowedActions": ["approve", "decline"], "nonce": "nonce-customer-123", "totalAmount": 13_200,
         "currency": "USD", "html": "<main>Server-priced drain repair</main>", "consentVersion": "estimate-approval-v1",
         "consentText": "I approve the work and total shown.", "options": [],
         "scopeLines": [["id": "line-1", "description": "Replace cleanout plug", "quantity": 2, "unitPrice": 6600]]]
    }
    private func localEstimate() throws -> EstimateRecord {
        var object = aggregate
        object["title"] = "Outdated local repair"
        return try JSONDecoder().decode(EstimateRecord.self, from: Data(json(object).utf8))
    }
    private func decodedRevision(_ object: [String: Any]? = nil) throws -> CustomerIssuedEstimateRevision {
        try JSONDecoder().decode(CustomerIssuedEstimateRevision.self, from: Data(json(object ?? revision).utf8))
    }
    private func json(_ object: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
    }
    private func client(_ replies: [URLProtocolFixture.Reply]) -> APIClient {
        APIClient(session: URLProtocolFixture.session(replies), baseURL: "https://app.thorbis.com")
    }
    private func rejects(_ operation: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do { try await operation(); XCTFail("Contradictory or stale paper must not be usable", file: file, line: line) } catch {}
    }
    private func waitForRequests(_ count: Int) async throws {
        for _ in 0..<100 where URLProtocolFixture.recorded.count < count { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(URLProtocolFixture.recorded.count, count)
    }
}

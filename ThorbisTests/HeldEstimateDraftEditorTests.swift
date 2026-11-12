import XCTest
@testable import Thorbis

@MainActor
final class HeldEstimateDraftEditorTests: XCTestCase {
    private let org = "00000000-0000-4000-8000-000000000001"
    private let customer = "00000000-0000-4000-8000-000000000002"
    private let estimate = "00000000-0000-4000-8000-000000000003"
    private let job = "00000000-0000-4000-8000-000000000004"

    private func response(version: Int = 0, revision: Int = 0, status: String = "draft") -> String {
        """
        {"estimate":{"id":"\(estimate)","organizationId":"\(org)","customerId":"\(customer)","createdByUserId":"\(org)","status":"\(status)","title":"Repair","lines":[],"createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z"},"draftEditVersion":\(version),"expectedRevisionNumber":\(revision)}
        """
    }

    func testResponseRequiresMatchingDraftIdentityAndSafeVersions() throws {
        let scope = JobDocumentScope(jobID: job, organizationID: org, customerID: customer)
        let parsed = try JSONDecoder().decode(HeldEstimateDraftEditorResponse.self, from: Data(response().utf8))
        XCTAssertNoThrow(try parsed.validate(scope: scope, estimateID: estimate))
        XCTAssertThrowsError(try parsed.validate(scope: .init(jobID: job, organizationID: UUID().uuidString, customerID: customer), estimateID: estimate))
        XCTAssertThrowsError(try parsed.validate(scope: scope, estimateID: UUID().uuidString))
        let issued = try JSONDecoder().decode(HeldEstimateDraftEditorResponse.self, from: Data(response(status: "sent").utf8))
        XCTAssertThrowsError(try issued.validate(scope: scope, estimateID: estimate))
        let exhausted = try JSONDecoder().decode(HeldEstimateDraftEditorResponse.self, from: Data(response(version: 9_007_199_254_740_991).utf8))
        XCTAssertThrowsError(try exhausted.validate(scope: scope, estimateID: estimate))
        let mismatch = try JSONDecoder().decode(HeldEstimateDraftEditorResponse.self, from: Data(response(revision: 1).utf8))
        XCTAssertThrowsError(try mismatch.validate(scope: scope, estimateID: estimate))
    }

    func testNestedUnknownFieldsAndInvalidFinancialLinesFailClosed() throws {
        let scope = JobDocumentScope(jobID: job, organizationID: org, customerID: customer)
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(response().utf8)) as? [String: Any])
        var record = try XCTUnwrap(root["estimate"] as? [String: Any])
        let line: [String: Any] = ["id": UUID().uuidString, "description": "Valve", "quantity": 1, "unitPrice": ["amount": 100, "currency": "USD"], "showToCustomer": false]
        record["lines"] = [line]
        root["estimate"] = record
        let good = try JSONDecoder().decode(HeldEstimateDraftEditorResponse.self, from: JSONSerialization.data(withJSONObject: root))
        XCTAssertNoThrow(try good.validate(scope: scope, estimateID: estimate))
        XCTAssertEqual(good.estimate.lines.first?.showToCustomer, false)
        record["lines"] = [line, line]; root["estimate"] = record
        let duplicated = try JSONDecoder().decode(HeldEstimateDraftEditorResponse.self, from: JSONSerialization.data(withJSONObject: root))
        XCTAssertThrowsError(try duplicated.validate(scope: scope, estimateID: estimate))
        var unknown = line; unknown["unsupported"] = true
        record["lines"] = [unknown]; root["estimate"] = record
        XCTAssertThrowsError(try JSONDecoder().decode(HeldEstimateDraftEditorResponse.self, from: JSONSerialization.data(withJSONObject: root)))
        var malformed = line; malformed["unitPrice"] = ["amount": 100, "currency": "EUR"]
        record["lines"] = [malformed]; root["estimate"] = record
        let wrongCurrency = try JSONDecoder().decode(HeldEstimateDraftEditorResponse.self, from: JSONSerialization.data(withJSONObject: root))
        XCTAssertThrowsError(try wrongCurrency.validate(scope: scope, estimateID: estimate))
    }

    func testOptionsAndLegacyCatalogEvidenceRemainIntact() throws {
        let scope = JobDocumentScope(jobID: job, organizationID: org, customerID: customer)
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(response().utf8)) as? [String: Any])
        var record = try XCTUnwrap(root["estimate"] as? [String: Any])
        let source: [String: Any] = ["kind": "price_book", "priceBookItemId": UUID().uuidString, "priceBookRevision": 3_000_000_000, "originalDescription": "Valve", "originalUnitPrice": ["amount": 100, "currency": "USD"], "addedByUserId": org, "capturedAt": "2026-01-01T00:00:00Z", "overriddenFields": []]
        let line: [String: Any] = ["id": UUID().uuidString, "description": "Valve", "quantity": 1, "unitPrice": ["amount": 100, "currency": "USD"], "source": source, "group": "material", "showToCustomer": false]
        let option: [String: Any] = ["id": UUID().uuidString, "title": "Option", "description": "Details", "lines": [line], "totalAmount": 100, "currency": "USD"]
        record["options"] = [option]; root["estimate"] = record
        let parsed = try JSONDecoder().decode(HeldEstimateDraftEditorResponse.self, from: JSONSerialization.data(withJSONObject: root))
        XCTAssertNoThrow(try parsed.validate(scope: scope, estimateID: estimate))
        XCTAssertEqual(parsed.estimate.options?.first?.lines.first?.source?.priceBookRevision, 3_000_000_000)
        XCTAssertEqual(parsed.estimate.options?.first?.lines.first?.showToCustomer, false)
        var bad = option; bad["totalAmount"] = 101; record["options"] = [bad]; root["estimate"] = record
        let mismatch = try JSONDecoder().decode(HeldEstimateDraftEditorResponse.self, from: JSONSerialization.data(withJSONObject: root))
        XCTAssertThrowsError(try mismatch.validate(scope: scope, estimateID: estimate))
    }
    private func ready(enabled: Bool, replies: [URLProtocolFixture.Reply]) async -> (APIClient, SessionController) {
        let sessionJSON = #"{"user":{"id":"\#(org)","name":"Staff"},"session":{"userId":"\#(org)","activeOrganizationId":"\#(org)","expiresAt":"2099-01-01T00:00:00Z"}}"#
        let catalog = #"{"authority":{"actorId":"\#(org)","organizationId":"\#(org)","policyVersion":1,"generation":"sample"},"capabilities":["job.view","estimate.view","estimate.create"],"resources":[],"views":[]}"#
        let features = #"{"organizationId":"\#(org)","evaluatedAt":"2026-01-01T00:00:00Z","features":{"jobs":{"enabled":true,"released":true,"entitled":true},"estimates":{"enabled":true,"released":true,"entitled":true},"estimate_draft_save":{"enabled":\#(enabled),"released":\#(enabled),"entitled":true}}}"#
        let api = APIClient(session: URLProtocolFixture.session([.init(200, sessionJSON), .init(200, #"[{"id":"\#(org)","name":"Sample"}]"#), .init(200, catalog), .init(200, features)] + replies), baseURL: "https://app.thorbis.com")
        let session = SessionController(api: api, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await session.restore()
        return (api, session)
    }
    private var jobJSON: String { #"{"id":"\#(job)","organizationId":"\#(org)","customerId":"\#(customer)","estimateId":"\#(estimate)","title":"Visit","status":"in_progress","createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z"}"# }

    func testTransportUsesFreshJobBeforeAndAfterDraft() async throws {
        let (api, session) = await ready(enabled: true, replies: [.init(200, jobJSON), .init(200, response()), .init(200, jobJSON)])
        let result = try await HeldEstimateDraftEditor.load(scope: .init(jobID: job, organizationID: org, customerID: customer), estimateID: estimate, api: api, session: session, current: { true })
        XCTAssertEqual(result.draftEditVersion, 0)
        XCTAssertEqual(URLProtocolFixture.recorded.suffix(3).map { $0.url?.path }, ["/v1/jobs/\(job)", "/v1/estimates/\(estimate)/draft-editor", "/v1/jobs/\(job)"])
    }

    func testDisabledFeatureDoesNotRequestDraft() async throws {
        let (api, session) = await ready(enabled: false, replies: [])
        do { _ = try await HeldEstimateDraftEditor.load(scope: .init(jobID: job, organizationID: org, customerID: customer), estimateID: estimate, api: api, session: session, current: { true }); XCTFail("feature must be held") } catch {}
        XCTAssertFalse(URLProtocolFixture.recorded.contains { $0.url?.path.contains("draft-editor") == true })
    }

    func testJobLinkMustStillExistAfterDraftRead() async throws {
        let unlinkedJob = jobJSON.replacingOccurrences(of: "\"estimateId\":\"\(estimate)\",", with: "")
        let link = #"{"items":[{"id":"\#(estimate)","jobId":"\#(job)","estimateId":"\#(estimate)"}],"nextCursor":null}"#
        let empty = #"{"items":[],"nextCursor":null}"#
        let (api, session) = await ready(enabled: true, replies: [.init(200, unlinkedJob), .init(200, link), .init(200, response()), .init(200, unlinkedJob), .init(200, empty)])
        do { _ = try await HeldEstimateDraftEditor.load(scope: .init(jobID: job, organizationID: org, customerID: customer), estimateID: estimate, api: api, session: session, current: { true }); XCTFail("removed membership must fail") } catch {}
    }

    func testInvalidScopeDoesNotFetchDraft() async throws {
        let foreignJob = jobJSON.replacingOccurrences(of: customer, with: UUID().uuidString)
        let (api, session) = await ready(enabled: true, replies: [.init(200, foreignJob)])
        do { _ = try await HeldEstimateDraftEditor.load(scope: .init(jobID: job, organizationID: org, customerID: customer), estimateID: estimate, api: api, session: session, current: { true }); XCTFail("foreign job must fail") } catch {}
        XCTAssertFalse(URLProtocolFixture.recorded.contains { $0.url?.path.contains("draft-editor") == true })
    }

    func testPaginationLoopNeverFetchesDraft() async throws {
        let unlinked = jobJSON.replacingOccurrences(of: "\"estimateId\":\"\(estimate)\",", with: "")
        let loop = #"{"items":[],"nextCursor":"repeat"}"#
        let (api, session) = await ready(enabled: true, replies: [.init(200, unlinked), .init(200, loop), .init(200, loop)])
        do { _ = try await HeldEstimateDraftEditor.load(scope: .init(jobID: job, organizationID: org, customerID: customer), estimateID: estimate, api: api, session: session, current: { true }); XCTFail("loop must fail") } catch {}
        XCTAssertFalse(URLProtocolFixture.recorded.contains { $0.url?.path.contains("draft-editor") == true })
    }

    func testSignOutDuringDraftReadNeverReturnsResponse() async throws {
        let gate = URLProtocolFixture.Gate(); defer { gate.release() }
        let (api, session) = await ready(enabled: true, replies: [.init(200, jobJSON), .init(200, response(), gate: gate), .init(200, "{}")])
        let pending = Task { try await HeldEstimateDraftEditor.load(scope: .init(jobID: job, organizationID: org, customerID: customer), estimateID: estimate, api: api, session: session, current: { true }) }
        for _ in 0..<100 where !URLProtocolFixture.recorded.contains(where: { $0.url?.path.contains("draft-editor") == true }) { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(URLProtocolFixture.recorded.contains { $0.url?.path.contains("draft-editor") == true })
        await session.signOut()
        gate.release()
        do { _ = try await pending.value; XCTFail("signed-out response must not be returned") } catch {}
    }

}

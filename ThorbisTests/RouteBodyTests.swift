import XCTest
@testable import Thorbis

/// The API refuses route identifiers in a body ("identifier must come from the route").
@MainActor
final class RouteBodyTests: XCTestCase {
    private let customerID = "00000000-0000-4000-8000-000000000412"
    private let itemID = "00000000-0000-4000-8000-000000009201"

    private func json(_ data: Data?) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(data)) as? [String: Any])
    }

    func testSmsConsentSendsOnlyTheDecision() async throws {
        let reply = #"{"version":"v2","customerId":"c","purpose":"transactional_job_notice","decision":"grant","recordedAt":"2026-10-27T15:00:00Z","isCurrent":true,"replayed":false}"#
        let client = APIClient(session: URLProtocolFixture.session([.init(200, reply)]), baseURL: "https://app.thorbis.com")
        let state = try await client.recordCustomerSmsConsent(customerID, grant: true, expectedVersion: nil, idempotencyKey: "k1")
        XCTAssertEqual(state.version, "v2")
        let request = try XCTUnwrap(URLProtocolFixture.recorded.first)
        XCTAssertEqual(request.url?.path, "/v1/customers/\(customerID)/sms-consent")
        let body = try json(request.body)
        XCTAssertEqual(Set(body.keys), ["decision", "expectedVersion", "evidenceRef", "idempotencyKey"])
        XCTAssertTrue(body["expectedVersion"] is NSNull)
    }

    func testPriceBookReviseKeepsTheItemIdInTheRoute() async throws {
        let reply = #"{"id":"\#(itemID)","organizationId":"00000000-0000-4000-8000-000000000002","status":"active","currentRevision":5,"createdAt":"2026-07-18T12:00:00Z","updatedAt":"2026-10-27T12:00:00Z"}"#
        let client = APIClient(session: URLProtocolFixture.session([.init(200, reply)]), baseURL: "https://app.thorbis.com")
        let content = PriceBookContent(description: "Replace compressor", unit: "each",
                                       sellPrice: FieldMoney(amount: 85_000, currency: "USD"), taxClassification: "taxable", kind: "service")
        let item = try await client.revisePriceBookItem(itemID, expectedRevision: 4, content: content)
        XCTAssertEqual(item.currentRevision, 5)
        let request = try XCTUnwrap(URLProtocolFixture.recorded.first)
        XCTAssertEqual(request.url?.path, "/v1/price-book/items/\(itemID)/revise")
        let body = try json(request.body)
        XCTAssertNil(body["itemId"])
        XCTAssertEqual(body["expectedRevision"] as? Int, 4)
        XCTAssertEqual(body["description"] as? String, "Replace compressor")
        XCTAssertEqual((body["sellPrice"] as? [String: Any])?["amount"] as? Int, 85_000)
    }

    func testRoleChangeNamesTheVersionsAndKeepsTheMemberInTheRoute() async throws {
        let memberJSON = #"{"member":{"memberId":"mem_42","userId":"u","displayName":"Alex","email":"a@example.invalid","isLegalOwner":false,"legalMembershipRoles":[]},"authority":{"kind":"tenant_role","assignmentId":"as1","currentAssignmentVersion":3,"assignedRoleRevision":1,"role":{"roleId":"r1","currentRevision":2,"name":"Tech","description":""}}}"#
        let member = try JSONDecoder().decode(RoleMember.self, from: Data(memberJSON.utf8))
        XCTAssertEqual(member.authority.currentAssignmentVersion, 3)
        let roleJSON = #"{"role":{"id":"00000000-0000-4000-8000-000000000777","currentRevision":5},"revision":{"name":"Dispatcher","description":"Books and assigns"}}"#
        let role = try JSONDecoder().decode(OrganizationRole.self, from: Data(roleJSON.utf8))
        let client = APIClient(session: URLProtocolFixture.session([.init(200, "{}")]), baseURL: "https://app.thorbis.com")
        try await client.changeMemberRole(member, to: role, idempotencyKey: "k")
        let request = try XCTUnwrap(URLProtocolFixture.recorded.first)
        XCTAssertEqual(request.url?.path, "/v1/organization/role-members/mem_42/role")
        let body = try json(request.body)
        XCTAssertNil(body["memberId"])
        XCTAssertEqual(body["expectedVersion"] as? Int, 3)
        XCTAssertEqual(body["expectedRoleRevision"] as? Int, 5)
        XCTAssertEqual(body["desiredRoleId"] as? String, "00000000-0000-4000-8000-000000000777")
    }

    func testRoleReviseSendsGrantsWithoutTheRoleId() async throws {
        let roleID = "00000000-0000-4000-8000-000000000777"
        let reply = #"{"role":{"id":"\#(roleID)","currentRevision":6},"revision":{"name":"Tech","description":"","grants":[]}}"#
        let client = APIClient(session: URLProtocolFixture.session([.init(200, reply)]), baseURL: "https://app.thorbis.com")
        let grants = [RoleGrant(capability: "estimate.discount", scope: "assigned", conditions: ["maxDiscountPercent": 10]),
                      RoleGrant(capability: "invoice.refund", scope: "organization", effect: "deny")]
        let saved = try await client.reviseOrganizationRole(roleID, expectedRevision: 5, name: "Tech", description: "", grants: grants)
        XCTAssertEqual(saved.role.currentRevision, 6)
        let request = try XCTUnwrap(URLProtocolFixture.recorded.first)
        XCTAssertEqual(request.url?.path, "/v1/organization/roles/\(roleID)/revise")
        let body = try json(request.body)
        XCTAssertNil(body["roleId"])
        XCTAssertEqual(body["expectedRevision"] as? Int, 5)
        let sent = try XCTUnwrap(body["grants"] as? [[String: Any]])
        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual((sent[0]["conditions"] as? [String: Int])?["maxDiscountPercent"], 10)
        XCTAssertEqual(sent[1]["effect"] as? String, "deny")
    }
}

import XCTest
@testable import Thorbis

final class JobAddPlanTests: XCTestCase {
    func testThePlanRowNeedsCustomerEditAPlanOnSaleAndANonMember() {
        func offer(edit: Bool = true, plans: Int = 2, member: Bool? = false, offline: Bool = false) -> Bool {
            JobAddPlan.canOffer(canEditCustomer: edit, plans: plans, isMember: member, offline: offline)
        }
        XCTAssertTrue(offer())
        XCTAssertTrue(offer(member: nil), "Member pricing unread: still offered, the plan picker is the same")
        XCTAssertFalse(offer(edit: false), "Needs customer.edit")
        XCTAssertFalse(offer(plans: 0), "The workspace sells no plan")
        XCTAssertFalse(offer(member: true), "Already on a plan")
        XCTAssertFalse(offer(offline: true), "Enrolling needs a connection")
    }

    func testThePlanRowSitsLastUnderBillingAndNeverOnACanceledJob() {
        var inputs = JobAddOffer.Inputs(status: "in_progress", canCreateEstimate: true, canCollect: true, canAddNote: true, canAddPlan: true)
        XCTAssertEqual(JobAddOffer.rows(inputs).billing, [.estimate, .payment, .plan])
        XCTAssertEqual(JobAddOffer.rows(inputs).onTheJob, [.checklist, .note], "A checklist can be started at every open stage")
        inputs.canAddPlan = false
        XCTAssertEqual(JobAddOffer.rows(inputs).billing, [.estimate, .payment])
        inputs.canAddPlan = true
        inputs.status = "canceled"
        XCTAssertEqual(JobAddOffer.rows(inputs).billing, [])
        for status in ["scheduled", "dispatched", "en_route", "arrived", "paused", "completed"] {
            inputs.status = status
            XCTAssertTrue(JobAddOffer.rows(inputs).billing.contains(.plan), status)
        }
    }

    @MainActor
    func testEnrollingSendsOnlyThePlanAndTheStartDay() async throws {
        let customer = "00000000-0000-4000-8000-000000000003"
        let plan = "00000000-0000-4000-8000-0000000000b1"
        let membership = #"{"id":"00000000-0000-4000-8000-0000000000b2","organizationId":"00000000-0000-4000-8000-000000000002","customerId":"\#(customer)","planId":"\#(plan)","name":"Comfort Club","kind":"maintenance","status":"active","discountPercent":10,"createdAt":"2026-11-20T12:00:00Z","updatedAt":"2026-11-20T12:00:00Z"}"#
        let client = APIClient(session: URLProtocolFixture.session([.init(200, membership)]), baseURL: "https://app.thorbis.com")
        do { _ = try await client.enroll(customer, planID: plan, startsOn: .now) } catch { /* The record's shape is the server's; the request is what is checked. */ }
        let sent = try XCTUnwrap(URLProtocolFixture.recorded.first)
        XCTAssertEqual(sent.method, "POST")
        XCTAssertEqual(sent.url?.path, "/v1/customers/\(customer)/memberships")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(sent.body)) as? [String: String])
        XCTAssertEqual(Set(body.keys), ["planId", "startsOn"], "No price, card or billing detail is sent")
        XCTAssertEqual(body["planId"], plan)
    }
}

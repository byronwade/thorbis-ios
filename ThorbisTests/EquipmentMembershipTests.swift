import XCTest
@testable import Thorbis

@MainActor
final class EquipmentMembershipTests: XCTestCase {
    private let customerID = "00000000-0000-4000-8000-000000000412"

    func testMemberPriceMatchesTheServerRounding() {
        let pricing = MemberPricing(isMember: true, discountPercent: 15, membership: nil)
        XCTAssertEqual(pricing.memberPrice(97_000), 82_450)
        XCTAssertEqual(pricing.memberPrice(999), 849)  // 849.15 rounds down
        XCTAssertEqual(MemberPricing(isMember: false, discountPercent: 0, membership: nil).memberPrice(500), 500)
    }

    func testEquipmentBodyClearsEmptyFieldsAndKeepsTheCustomerInTheRoute() async throws {
        let reply = #"{"id":"00000000-0000-4000-8000-000000006101","organizationId":"o","customerId":"\#(customerID)","name":"Condenser","createdAt":"2026-10-27T12:00:00Z","updatedAt":"2026-10-27T12:00:00Z"}"#
        let client = APIClient(session: URLProtocolFixture.session([.init(201, reply)]), baseURL: "https://app.thorbis.com")
        let unit = try await client.addEquipment(customerID, EquipmentInput(name: "Condenser", brand: "  ", serialNumber: " 2419E ",
                                                                            warrantyExpiresOn: "2029-06-12"))
        XCTAssertEqual(unit.name, "Condenser")
        let request = try XCTUnwrap(URLProtocolFixture.recorded.first)
        XCTAssertEqual(request.url?.path, "/v1/customers/\(customerID)/equipment")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.body)) as? [String: Any])
        XCTAssertNil(body["customerId"])
        XCTAssertTrue(body["brand"] is NSNull)
        XCTAssertEqual(body["serialNumber"] as? String, "2419E")
        XCTAssertEqual(body["warrantyExpiresOn"] as? String, "2029-06-12")
    }

    func testDaysRoundTripWithoutTimeZoneDrift() {
        let day = EquipmentRecord.day("2029-06-12")!
        XCTAssertEqual(EquipmentRecord.dayString(day), "2029-06-12")
    }
}

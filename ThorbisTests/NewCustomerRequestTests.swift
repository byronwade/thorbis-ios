import XCTest
@testable import Thorbis

final class NewCustomerRequestTests: XCTestCase {
    func testIntakeEncodesOnlyFilledFieldsForTheStrictServerSchema() throws {
        let minimal = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(NewCustomerRequest(name: "Ray Osei"))) as? [String: String])
        XCTAssertEqual(minimal, ["name": "Ray Osei"])

        let full = NewCustomerRequest(name: "Danielle Marlowe", phone: "(555) 014-2276", email: "d@example.com",
                                      address: "412 Birchwood Ln", accountType: "residential", preferredContact: "sms")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(full)) as? [String: String])
        XCTAssertEqual(Set(json.keys), ["name", "phone", "email", "address", "accountType", "preferredContact"])
        XCTAssertEqual(json["preferredContact"], "sms")
    }
}

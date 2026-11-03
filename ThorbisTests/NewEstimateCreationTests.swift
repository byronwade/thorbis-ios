import XCTest
@testable import Thorbis

@MainActor
final class NewEstimateCreationTests: XCTestCase {
    func testJobEstimateRequestCarriesJobCustomerAndLocation() throws {
        let view = NewEstimateView(customerID: "customer-1", jobID: "job-1", locationID: "location-1", title: " Repair ")
        let request = view.creationRequest()
        XCTAssertEqual(request.customerId, "customer-1")
        XCTAssertEqual(request.locationId, "location-1")
        XCTAssertEqual(request.title, "Repair")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        XCTAssertEqual(json["locationId"] as? String, "location-1")
    }

    func testJobWithoutLocationDoesNotInventOne() throws {
        let request = NewEstimateView(customerID: "customer-1", jobID: "job-1", title: "Repair").creationRequest()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        XCTAssertNil(json["locationId"])
    }

    func testJobDraftKeyIgnoresCustomerAndLocation() {
        XCTAssertEqual(
            NewEstimateView(customerID: "customer-1", jobID: "job-1", locationID: "location-1").draftDocumentKey,
            NewEstimateView(customerID: "customer-2", jobID: "job-1", locationID: "location-2").draftDocumentKey
        )
        XCTAssertEqual(NewEstimateView(customerID: "customer-1", jobID: "job-1").draftDocumentKey, "job:job-1")
    }

    func testStandaloneEstimateDoesNotInheritAJobLocation() throws {
        let request = NewEstimateView(customerID: "customer-1", locationID: "location-1", title: "Repair").creationRequest()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        XCTAssertNil(json["locationId"])
    }
}

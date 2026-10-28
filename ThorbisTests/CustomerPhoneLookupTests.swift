import XCTest
@testable import Thorbis

@MainActor
final class CustomerPhoneLookupTests: XCTestCase {
    func testOnlyExactDigitsCountAndAnIncompletePageStaysUnknown() {
        let rows = [(id: "a", name: "Near Miss", phone: "(555) 010-1234 x9"), (id: "b", name: "Danielle Marlowe", phone: "555-010-1234")]
        XCTAssertEqual(CustomerPhoneLookup.classify(rows: rows, complete: false, phone: "(555) 010 1234"),
                       .found(Customer(id: "b", name: "Danielle Marlowe", archived: nil, createdAt: nil)))
        XCTAssertEqual(CustomerPhoneLookup.classify(rows: [rows[0]], complete: false, phone: "5550101234"), .unknown)
        XCTAssertEqual(CustomerPhoneLookup.classify(rows: [rows[0]], complete: true, phone: "5550101234"), .notFound)
        XCTAssertEqual(CustomerPhoneLookup.classify(rows: [], complete: true, phone: "555-01"), .notApplicable)
    }

    func testLookupSendsOneDigitsOnlyQueryPlatformPredicate() async throws {
        let page = #"{"schemaVersion":1,"resourceId":"customers","purpose":"collection","localMode":"complete","items":[{"id":"c1","resourceId":"customers","label":"Danielle Marlowe","fields":{"customers.name":"Danielle Marlowe","customers.phone":"(555) 014-2276"}}],"nextCursor":null}"#
        let api = APIClient(session: URLProtocolFixture.session([.init(200, page)]), baseURL: "https://app.thorbis.com")

        let result = try await api.lookupCustomer(phone: "(555) 014-2276")

        XCTAssertEqual(result, .found(Customer(id: "c1", name: "Danielle Marlowe", archived: nil, createdAt: nil)))
        let request = try XCTUnwrap(URLProtocolFixture.recorded.first)
        XCTAssertEqual(request.url?.path, "/v1/query")
        let items = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "resourceId" }?.value, "customers")
        let filter = try XCTUnwrap(items.first { $0.name == "filter" }?.value)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(filter.utf8)) as? [String: Any])
        let root = try XCTUnwrap(json["root"] as? [String: Any])
        XCTAssertEqual(root["field"] as? String, "customers.phone")
        XCTAssertEqual(root["operator"] as? String, "contains")
        XCTAssertEqual(root["value"] as? String, "5550142276")
    }

    func testShortNumbersNeverHitTheServer() async throws {
        let api = APIClient(session: URLProtocolFixture.session([]), baseURL: "https://app.thorbis.com")
        let result = try await api.lookupCustomer(phone: "555")
        XCTAssertEqual(result, .notApplicable)
        XCTAssertTrue(URLProtocolFixture.recorded.isEmpty)
    }
}

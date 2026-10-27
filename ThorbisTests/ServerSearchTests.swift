import XCTest
@testable import Thorbis

@MainActor
final class ServerSearchTests: XCTestCase {
    func testSearchSendsTheQueryAndDecodesGatewayResults() async throws {
        let body = #"{"items":[{"schemaVersion":1,"sourceId":"jobs","resultType":"job","icon":"briefcase","entityId":"019f0000-0000-7000-8000-0000000000a1","title":"AC not cooling","subtitle":"Danielle Marlowe","status":"en_route","highlights":[],"score":3.2,"scoreExplanation":[],"freshnessClass":"live","localMode":"online_required","completeness":"complete","route":"/jobs/x","peek":null,"commands":[]}],"nextCursor":null,"facets":[],"completeness":"complete","freshness":{"liveGeneration":1,"asOf":"2026-10-27T12:00:00Z","cache":"miss"}}"#
        let api = APIClient(session: URLProtocolFixture.session([.init(200, body)]), baseURL: "https://app.thorbis.com")
        let page = try await api.search("water heat")
        XCTAssertEqual(page.items.first?.resultType, "job")
        XCTAssertEqual(page.items.first?.subtitle, "Danielle Marlowe")
        let url = try XCTUnwrap(URLProtocolFixture.recorded.first?.url)
        XCTAssertEqual(url.path, "/v1/search")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "q" }?.value, "water heat")
    }
}

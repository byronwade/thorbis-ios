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

    func testSearchFollowsTheNextCursorAndIncludesEveryPage() async throws {
        let first = #"{"items":[{"sourceId":"jobs","resultType":"job","entityId":"job-1","title":"First"}],"nextCursor":"page-2","completeness":"complete"}"#
        let second = #"{"items":[{"sourceId":"invoices","resultType":"invoice","entityId":"inv-2","title":"Second"}],"nextCursor":null,"completeness":"complete"}"#
        let api = APIClient(session: URLProtocolFixture.session([
            .init(200, first), .init(200, second),
        ]), baseURL: "https://app.thorbis.com")

        let page = try await api.search("water heat")

        XCTAssertEqual(page.items.map(\.entityId), ["job-1", "inv-2"])
        XCTAssertEqual(page.items.map(\.resultType), ["job", "invoice"])
        XCTAssertNil(page.nextCursor)
        XCTAssertEqual(URLProtocolFixture.recorded.map { $0.url?.absoluteString }, [
            "https://app.thorbis.com/v1/search?q=water%20heat&limit=25",
            "https://app.thorbis.com/v1/search?q=water%20heat&limit=25&cursor=page-2",
        ])
    }

    func testSearchRejectsARepeatedCursor() async {
        let body = #"{"items":[{"sourceId":"jobs","resultType":"job","entityId":"job-1","title":"First"}],"nextCursor":"same"}"#
        let api = APIClient(session: URLProtocolFixture.session([
            .init(200, body), .init(200, body),
        ]), baseURL: "https://app.thorbis.com")

        do {
            _ = try await api.search("pump")
            XCTFail("Expected cursor loop rejection")
        } catch let problem as Problem {
            XCTAssertEqual(problem.title, "Pagination cursor loop")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(URLProtocolFixture.recorded.count, 2)
    }

    func testSearchRejectsAnEmptyCursor() async {
        let body = #"{"items":[{"sourceId":"jobs","resultType":"job","entityId":"job-1","title":"First"}],"nextCursor":""}"#
        let api = APIClient(session: URLProtocolFixture.session([.init(200, body)]), baseURL: "https://app.thorbis.com")

        do {
            _ = try await api.search("pump")
            XCTFail("Expected cursor loop rejection")
        } catch let problem as Problem {
            XCTAssertEqual(problem.title, "Pagination cursor loop")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
    }
}

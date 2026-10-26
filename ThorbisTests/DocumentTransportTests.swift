import XCTest
@testable import Thorbis

@MainActor
final class DocumentTransportTests: XCTestCase {
    func testAuthenticatedPDFResponsePreservesBytes() async throws {
        let api = APIClient(session: URLProtocolFixture.session([.init(200, "%PDF-1.7\nfixture", contentType: "application/pdf")]), baseURL: "https://app.thorbis.com")
        let data = try await api.documentData("/v1/invoices/018f0000-0000-7000-8000-000000000001/document")
        XCTAssertTrue(data.starts(with: Data("%PDF-".utf8)))
        XCTAssertEqual(URLProtocolFixture.recorded.first?.header("accept"), "application/pdf")
    }

    func testJSONCannotMasqueradeAsPDF() async {
        let api = APIClient(session: URLProtocolFixture.session([.init(200, "{}")]), baseURL: "https://app.thorbis.com")
        do { _ = try await api.documentData("/v1/invoices/018f0000-0000-7000-8000-000000000001/document"); XCTFail("Expected MIME rejection") }
        catch is Problem {} catch { XCTFail("Unexpected error: \(error)") }
    }
}

#if DEBUG
import XCTest
@testable import Thorbis

@MainActor
final class PaperPreviewTests: XCTestCase {
    func testRealSessionRestoreAndDomainDecodersUsePreviewFixtures() async throws {
        let api = PaperPreview.api()
        let session = SessionController(api: api, defaults: PaperPreview.defaults())
        await session.restore()
        XCTAssertEqual(session.phase, .ready, session.error ?? "")
        XCTAssertTrue(session.can("job.view", feature: "jobs"))
        let jobs = try await api.jobs()
        let customers = try await api.customers()
        XCTAssertEqual(jobs.count, 6)
        XCTAssertEqual(customers.count, 5)
        let job = try await api.fieldJob(PaperPreview.jobID)
        XCTAssertEqual(job.title, "AC not cooling")
        let customer = try await api.fieldCustomer(PaperPreview.customerID)
        XCTAssertEqual(customer.name, "Danielle Marlowe")
        let contacts = try await api.fieldContacts(PaperPreview.customerID)
        let locations = try await api.fieldLocations(PaperPreview.customerID)
        XCTAssertEqual(contacts.map(\.name), ["Danielle Marlowe", "Taylor Marlowe"])
        XCTAssertTrue(contacts[0].primary)
        XCTAssertFalse(contacts[1].primary)
        XCTAssertFalse(locations.isEmpty)
    }

    func testEveryRequestIsInterceptedAndUnknownHostsNeverFallThrough() async throws {
        let session = PaperPreview.transport()
        for raw in ["https://example.invalid/unreachable", "https://app.thorbis.com/unknown"] {
            let (_, response) = try await session.data(from: XCTUnwrap(URL(string: raw)))
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 404)
            XCTAssertTrue(PaperPreviewProtocol.canInit(with: URLRequest(url: try XCTUnwrap(URL(string: raw)))))
        }
    }

    func testMutationsAreRejectedEvenForKnownFixtureRoutes() async throws {
        let session = PaperPreview.transport()
        for method in ["POST", "PUT", "PATCH", "DELETE"] {
            var request = URLRequest(url: try XCTUnwrap(URL(string: "https://app.thorbis.com/v1/jobs")))
            request.httpMethod = method
            let (body, response) = try await session.data(for: request)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 405)
            XCTAssertTrue(String(decoding: body, as: UTF8.self).contains("read-only"))
        }
    }

    func testDefaultsAreIsolatedFromOtherPreviewSessions() {
        let first = PaperPreview.defaults()
        let second = PaperPreview.defaults()
        first.set(true, forKey: "thorbis.session.explicitlySignedOut")
        XCTAssertFalse(second.bool(forKey: "thorbis.session.explicitlySignedOut"))
    }
}
#endif

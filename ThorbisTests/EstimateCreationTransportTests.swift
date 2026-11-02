import XCTest
@testable import Thorbis

/// Exercises the actual API transport at delayed-response boundaries. The editor's UI,
/// authorization rebind and relaunch behavior require separate journey tests.
@MainActor
final class EstimateCreationTransportTests: XCTestCase {
    private let jobID = "00000000-0000-4000-8000-000000000001"
    private let estimateID = "00000000-0000-4000-8000-000000000008"
    private let customerID = "00000000-0000-4000-8000-000000000003"
    private let savedEstimate = #"{"id":"00000000-0000-4000-8000-000000000008","organizationId":"00000000-0000-4000-8000-000000000002","customerId":"00000000-0000-4000-8000-000000000003","createdByUserId":"00000000-0000-4000-8000-000000000004","status":"draft","title":"Repair","lines":[],"createdAt":"2026-10-26T12:00:00Z","updatedAt":"2026-10-26T12:00:00Z"}"#
    private let linkReply = #"{"id":"00000000-0000-4000-8000-000000000009","jobId":"00000000-0000-4000-8000-000000000001","estimateId":"00000000-0000-4000-8000-000000000008","linkedAt":"2026-10-26T12:00:00Z"}"#

    func testDelayedCreateResponseIsDiscardedAfterRequestGenerationChanges() async throws {
        let gate = URLProtocolFixture.Gate()
        let client = APIClient(session: URLProtocolFixture.session([.init(201, savedEstimate, gate: gate)]), baseURL: "https://app.thorbis.com")
        let request = FieldEstimateCreate(customerId: customerID, title: "Repair", lines: [
            .init(description: "Valve", quantity: 1, unitPrice: .init(amount: 1200, currency: "USD"))
        ])
        let task = Task { try await client.createFieldEstimate(request) }
        defer { gate.release(); task.cancel() }
        try await waitForRequests(1)
        client.invalidateRequests()
        gate.release()
        do {
            _ = try await task.value
            XCTFail("A create response from a previous request generation must not be used")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected cancellation after invalidation, got \(error)")
        }
        XCTAssertEqual(URLProtocolFixture.recorded.map(\.url?.path), ["/v1/estimates"])
    }

    func testDelayedLinkResponseIsDiscardedAfterRequestGenerationChanges() async throws {
        let gate = URLProtocolFixture.Gate()
        let client = APIClient(session: URLProtocolFixture.session([.init(201, linkReply, gate: gate)]), baseURL: "https://app.thorbis.com")
        let task = Task { try await client.linkFieldEstimate(jobID: jobID, estimateID: estimateID) }
        defer { gate.release(); task.cancel() }
        try await waitForRequests(1)
        client.invalidateRequests()
        gate.release()
        do {
            _ = try await task.value
            XCTFail("A link response from a previous request generation must not be used")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected cancellation after invalidation, got \(error)")
        }
        XCTAssertEqual(URLProtocolFixture.recorded.map(\.url?.path), ["/v1/jobs/\(jobID)/estimates/\(estimateID)/link"])
    }

    func testKnownEstimateLinkCanBeRetriedWithoutAnotherCreateRequest() async throws {
        let client = APIClient(session: URLProtocolFixture.session([
            .init(503, #"{"title":"Connection unavailable","status":503}"#), .init(201, linkReply)
        ]), baseURL: "https://app.thorbis.com")
        do {
            _ = try await client.linkFieldEstimate(jobID: jobID, estimateID: estimateID)
            XCTFail("The first simulated link must fail")
        } catch let error as Problem {
            XCTAssertEqual(error.status, 503)
        }
        let link = try await client.linkFieldEstimate(jobID: jobID, estimateID: estimateID)
        XCTAssertEqual(link.jobId, jobID)
        XCTAssertEqual(link.estimateId, estimateID)
        XCTAssertEqual(URLProtocolFixture.recorded.map(\.url?.path), Array(repeating: "/v1/jobs/\(jobID)/estimates/\(estimateID)/link", count: 2))
    }

    private func waitForRequests(_ count: Int) async throws {
        for _ in 0..<200 {
            if URLProtocolFixture.recorded.count >= count { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for the request to reach the fixture")
        throw CancellationError()
    }
}

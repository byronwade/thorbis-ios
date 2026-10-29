import XCTest
@testable import Thorbis

@MainActor
final class LegacyPhotoPerformanceTests: XCTestCase {
    private final class HeartbeatState {
        var finished = false
        var worstDelay: TimeInterval = 0
    }
    func testMultiMegabytePhotoDownloadKeepsMainActorResponsive() async throws {
        let org = "00000000-0000-4000-8000-000000000001"
        let job = "00000000-0000-4000-8000-000000000002"
        let photoID = "00000000-0000-4000-8000-000000000003"
        let byteCount = 8 * 1024 * 1024
        let body = String(repeating: "a", count: byteCount)
        let photo = JobPhotoRecord(id: photoID, organizationId: org, jobId: job, authorUserId: org,
                                   contentType: "image/jpeg", byteSize: byteCount, storageKey: "key", createdAt: "2026-01-01T00:00:00Z")
        let client = APIClient(session: URLProtocolFixture.session([.init(200, body, contentType: "image/jpeg")]), baseURL: "https://app.thorbis.com")
        let state = HeartbeatState()
        let heartbeat = Task { @MainActor in
            while !state.finished {
                let start = Date()
                try await Task.sleep(for: .milliseconds(20))
                state.worstDelay = max(state.worstDelay, Date().timeIntervalSince(start))
            }
        }
        await Task.yield()
        let data = try await client.legacyJobPhotoData(photo, organizationID: org, jobID: job)
        state.finished = true
        try await heartbeat.value
        XCTAssertEqual(data.count, byteCount)
        XCTAssertLessThan(state.worstDelay, 0.25, "The main actor must remain responsive while photo bytes are buffered")
    }
}

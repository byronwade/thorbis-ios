import XCTest
@testable import Thorbis

@MainActor
final class CustomerPhotoPreparationTests: XCTestCase {
    func testRejectsScopeChangeDuringExactReadWithoutReadingRemainingAssets() async throws {
        let selection = try CustomerPhotoSelection(jobID: "job", organizationID: "org", selectedIDs: ["a", "b"])
        var current = true
        var readIDs: [String] = []
        do {
            _ = try await CustomerPhotoPreparation.prepare(selection: selection, isCurrent: { current },
                loadJob: { ("job", "org") }, loadAsset: { id in
                    readIDs.append(id)
                    current = false
                    return CustomerPhotoMetadata(id: id, jobId: "job", kind: "photo", uploadState: "stored", archived: false)
                })
            XCTFail("A stale handoff must not be presented")
        } catch {}
        XCTAssertEqual(readIDs, ["a"])
    }

    func testRejectsWrongLiveJobBeforeLoadingAnyAssets() async throws {
        let selection = try CustomerPhotoSelection(jobID: "job", organizationID: "org", selectedIDs: ["a"])
        var reads = 0
        do {
            _ = try await CustomerPhotoPreparation.prepare(selection: selection, isCurrent: { true },
                loadJob: { ("job", "other-org") }, loadAsset: { id in
                    reads += 1
                    return CustomerPhotoMetadata(id: id, jobId: "job", kind: "photo", uploadState: "stored", archived: false)
                })
            XCTFail("A different organization must be rejected")
        } catch {}
        XCTAssertEqual(reads, 0)
    }

    func testCancelledPreparationDoesNotStartReads() async throws {
        let selection = try CustomerPhotoSelection(jobID: "job", organizationID: "org", selectedIDs: ["a"])
        var reads = 0
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await CustomerPhotoPreparation.prepare(selection: selection, isCurrent: { true },
                loadJob: { reads += 1; return ("job", "org") }, loadAsset: { id in
                    reads += 1
                    return CustomerPhotoMetadata(id: id, jobId: "job", kind: "photo", uploadState: "stored", archived: false)
                })
        }
        do { _ = try await task.value; XCTFail("Cancelled preparation must not complete") } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(reads, 0)
    }

    func testFreshReadsKeepExplicitSelectionOrder() async throws {
        let selection = try CustomerPhotoSelection(jobID: "job", organizationID: "org", selectedIDs: ["b", "a"])
        var reads: [String] = []
        let result = try await CustomerPhotoPreparation.prepare(selection: selection, isCurrent: { true },
            loadJob: { ("job", "org") }, loadAsset: { id in
                reads.append(id)
                return CustomerPhotoMetadata(id: id, jobId: "job", kind: "photo", uploadState: "stored", archived: false)
            })
        XCTAssertEqual(reads, ["b", "a"])
        XCTAssertEqual(result.map(\.id), ["b", "a"])
    }

    func testFreshReadsMustReturnExactlyRequestedPhotos() async throws {
        let selection = try CustomerPhotoSelection(jobID: "job", organizationID: "org", selectedIDs: ["a", "b"])
        do {
            _ = try await CustomerPhotoPreparation.prepare(selection: selection, isCurrent: { true },
                loadJob: { ("job", "org") }, loadAsset: { id in
                    CustomerPhotoMetadata(id: id == "b" ? "c" : id, jobId: "job", kind: "photo", uploadState: "stored", archived: false)
                })
            XCTFail("An unexpected record must not be presented")
        } catch {}
    }
}

@MainActor
final class CustomerPhotoAPITests: XCTestCase {
    func testExactRecordReadBypassesLocalCacheAndDecodesSafeProjection() async throws {
        let id = "22222222-2222-4222-8222-222222222222"
        let body = #"{"id":"22222222-2222-4222-8222-222222222222","jobId":"11111111-1111-4111-8111-111111111111","kind":"photo","uploadState":"stored","archived":false}"#
        let transport = URLProtocolFixture.session([.init(200, body)])
        let api = APIClient(session: transport, baseURL: "https://app.thorbis.com")
        let record = try await api.customerPhotoMetadata(id)
        XCTAssertEqual(record.id, id)
        XCTAssertEqual(URLProtocolFixture.recorded.last?.url?.path, "/v1/media/\(id)")
        XCTAssertEqual(URLProtocolFixture.recorded.last?.header("Cache-Control"), "no-cache")
    }
}

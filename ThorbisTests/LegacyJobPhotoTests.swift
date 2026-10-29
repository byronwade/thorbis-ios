import XCTest
import UIKit
@testable import Thorbis

@MainActor
final class LegacyJobPhotoTests: XCTestCase {
    private let org = "00000000-0000-4000-8000-000000000001"
    private let job = "00000000-0000-4000-8000-000000000002"
    private let photoID = "00000000-0000-4000-8000-000000000003"
    private func legacy(_ key: String, organization: String? = nil, jobID: String? = nil) -> JobPhotoRecord {
        JobPhotoRecord(id: photoID, organizationId: organization ?? org, jobId: jobID ?? job, authorUserId: org,
                       contentType: "image/jpeg", byteSize: 3, storageKey: key, createdAt: "2026-01-01T00:00:00Z")
    }
    private func modern(_ key: String, organization: String? = nil, jobID: String? = nil,
                        state: String = "stored", archived: Bool = false) -> MediaAssetRecord {
        MediaAssetRecord(id: "00000000-0000-4000-8000-000000000004", organizationId: organization ?? org,
                         jobId: jobID ?? job, uploaderUserId: org, kind: "photo", mime: "image/jpeg", sizeBytes: 3,
                         originalFilename: "image.bin", contentHash: "hash", storageKey: key, capturedAt: nil,
                         uploadState: state, tags: [], caption: nil, archived: archived, sourceAssetId: nil,
                         createdAt: "2026-01-01T00:00:00Z", updatedAt: "2026-01-01T00:00:00Z")
    }

    func testReconciledPhotoRetainsLegacyFallbackAndCountsOnce() {
        let merged = JobPhotoMerge.combine(modern: [modern("key")], legacy: [legacy("key")], organizationID: org, jobID: job)
        XCTAssertEqual(merged.count, 1)
        guard case .some(.modern(_, let fallback)) = merged.first else { return XCTFail("Expected modern asset") }
        XCTAssertEqual(fallback?.id, photoID)
    }
    func testSameKeyMismatchedMetadataCountsOnceWithoutLegacyFallbackAndIsIncomplete() {
        let original = legacy("key")
        let mismatched = JobPhotoRecord(id: original.id, organizationId: org, jobId: job, authorUserId: org,
                                        contentType: "image/png", byteSize: 4, storageKey: "key", createdAt: original.createdAt)
        let merged = JobPhotoMerge.combine(modern: [modern("key")], legacy: [mismatched], organizationID: org, jobID: job)
        XCTAssertEqual(merged.count, 1)
        guard case .some(.modern(_, let fallback)) = merged.first else { return XCTFail("Expected one media record") }
        XCTAssertNil(fallback)
        XCTAssertTrue(JobPhotoMerge.hasConflictingMetadata(modern: [modern("key")], legacy: [mismatched], organizationID: org, jobID: job))
    }

    func testDuplicateSameKeyHasNoGuessedFallbackAndIsIncomplete() {
        let first = legacy("key")
        let other = JobPhotoRecord(id: "00000000-0000-4000-8000-000000000005", organizationId: org, jobId: job,
                                   authorUserId: org, contentType: first.contentType, byteSize: first.byteSize,
                                   storageKey: "key", createdAt: first.createdAt)
        let merged = JobPhotoMerge.combine(modern: [modern("key")], legacy: [first, other], organizationID: org, jobID: job)
        XCTAssertEqual(merged.count, 1)
        guard case .some(.modern(_, let fallback)) = merged.first else { return XCTFail("Expected one media record") }
        XCTAssertNil(fallback)
        XCTAssertTrue(JobPhotoMerge.hasConflictingMetadata(modern: [modern("key")], legacy: [first, other], organizationID: org, jobID: job))
    }

    func testPendingAndForeignMediaCannotHideLegacy() {
        for asset in [modern("key", state: "pending"), modern("key", organization: "foreign"), modern("key", jobID: "foreign")] {
            let merged = JobPhotoMerge.combine(modern: [asset], legacy: [legacy("key")], organizationID: org, jobID: job)
            XCTAssertTrue(merged.contains { if case .legacy = $0 { return true }; return false })
        }
    }
    func testDifferentOrMissingKeysAndForeignLegacyRemainDistinctAndScoped() {
        let merged = JobPhotoMerge.combine(modern: [modern("")], legacy: [legacy(""), legacy("key", organization: "foreign"), legacy("key", jobID: "foreign")], organizationID: org, jobID: job)
        XCTAssertEqual(merged.count, 2)
    }
    func testArchivedModernPhotoDoesNotReappearThroughLegacyRecord() {
        let merged = JobPhotoMerge.combine(modern: [modern("key", archived: true)], legacy: [legacy("key")], organizationID: org, jobID: job)
        XCTAssertTrue(merged.isEmpty)
    }

    func testUnkeyedArchivedPhotoMakesLegacyIdentityUncertain() {
        let assets = [modern("", archived: true)]
        let merged = JobPhotoMerge.combine(modern: assets, legacy: [legacy("key")], organizationID: org, jobID: job)
        XCTAssertTrue(merged.isEmpty, "Unidentified tombstones must not expose a possibly archived legacy photo")
        XCTAssertTrue(JobPhotoMerge.hasConflictingMetadata(modern: assets, legacy: [legacy("key")], organizationID: org, jobID: job))
    }

    func testUnkeyedOrPendingPhotosMakeTotalIncomplete() {
        for assets in [[modern("")], [modern("key", state: "pending")]] {
            XCTAssertTrue(JobPhotoMerge.hasConflictingMetadata(modern: assets, legacy: [], organizationID: org, jobID: job))
        }
        XCTAssertTrue(JobPhotoMerge.hasConflictingMetadata(modern: [], legacy: [legacy("")], organizationID: org, jobID: job))
    }

    func testDecodeRejectsInvalidImageBytes() {
        XCTAssertNil(LegacyPhotoDecode.thumbnail(Data("not an image".utf8), pixelSize: 240))
        let png = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }.pngData()!
        XCTAssertNotNil(LegacyPhotoDecode.thumbnail(png, pixelSize: 240))
    }

    func testLegacyPhotoUsesExactJobAndPhotoRouteAndReturnsOnlyMatchingBytes() async throws {
        let client = APIClient(session: URLProtocolFixture.session([.init(200, "abc", contentType: "image/jpeg")]), baseURL: "https://app.thorbis.com")
        let bytes = try await client.legacyJobPhotoData(legacy("key"), organizationID: org, jobID: job)
        XCTAssertEqual(bytes, Data("abc".utf8))
        XCTAssertEqual(URLProtocolFixture.recorded.first?.url?.path, "/v1/jobs/\(job)/photos/\(photoID)")
    }
    func testLegacyPhotoRejectsUnexpectedContentType() async throws {
        let client = APIClient(session: URLProtocolFixture.session([.init(200, "abc", contentType: "application/pdf")]), baseURL: "https://app.thorbis.com")
        do { _ = try await client.legacyJobPhotoData(legacy("key"), organizationID: org, jobID: job); XCTFail("Wrong content type must be rejected") } catch {}
    }

    func testRetiredRequestCannotReturnPhotoBytes() async throws {
        let gate = URLProtocolFixture.Gate()
        defer { gate.release() }
        let client = APIClient(session: URLProtocolFixture.session([.init(200, "abc", gate: gate, contentType: "image/jpeg")]), baseURL: "https://app.thorbis.com")
        let pending = Task { try await client.legacyJobPhotoData(legacy("key"), organizationID: org, jobID: job) }
        for _ in 0..<100 where URLProtocolFixture.recorded.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
        client.invalidateRequests()
        gate.release()
        do { _ = try await pending.value; XCTFail("Old session must not return bytes") } catch is CancellationError {} catch { XCTFail("Expected cancellation: \(error)") }
    }

    func testLegacyPhotoRejectsCrossScopeAndMismatchedResponse() async throws {
        let client = APIClient(session: URLProtocolFixture.session([.init(200, "abcd", contentType: "image/jpeg")]), baseURL: "https://app.thorbis.com")
        do { _ = try await client.legacyJobPhotoData(legacy("key"), organizationID: org, jobID: photoID); XCTFail("Wrong job must be rejected") } catch {}
        XCTAssertTrue(URLProtocolFixture.recorded.isEmpty)
        do { _ = try await client.legacyJobPhotoData(legacy("key"), organizationID: org, jobID: job); XCTFail("Overlong response must be rejected") } catch {}
    }
}

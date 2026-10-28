import XCTest
@testable import Thorbis

@MainActor
final class MediaTransferTests: XCTestCase {
    private let jobID = "11111111-1111-4111-8111-111111111111"
    private let assetID = "22222222-2222-4222-8222-222222222222"
    private let clientAssetID = "33333333-3333-4333-8333-333333333333"
    private let helloHash = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
    private let helloChecksumHeader = "LPJNul+wow4m6DsqxbninhsWHlwfp0JecwQzYpOLmCQ="

    private var pendingAsset: String {
        #"{"id":"22222222-2222-4222-8222-222222222222","organizationId":"44444444-4444-4444-8444-444444444444","jobId":"11111111-1111-4111-8111-111111111111","uploaderUserId":"55555555-5555-4555-8555-555555555555","kind":"photo","mime":"image/jpeg","sizeBytes":5,"originalFilename":"work.jpg","contentHash":"2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824","storageKey":"tenant/jobs/work.jpg","uploadState":"pending","tags":[],"archived":false,"createdAt":"2026-10-26T00:00:00Z","updatedAt":"2026-10-26T00:00:00Z"}"#
    }

    private var storedAsset: String {
        pendingAsset.replacingOccurrences(of: #""uploadState":"pending""#, with: #""uploadState":"stored""#)
    }

    private func registration(url: String = "https://storage.example/upload?token=abc",
                              method: String = "PUT", expiresAt: String = "2030-12-31T00:00:00Z") -> String {
        #"{"asset":\#(pendingAsset),"uploadTarget":{"url":"\#(url)","method":"\#(method)","expiresAt":"\#(expiresAt)","headers":{"content-type":"image/jpeg","x-amz-checksum-sha256":"\#(helloChecksumHeader)","x-custom":"preserve"}}}"#
    }

    func testSinglePUTPreservesTargetHeadersAndConfirmsMatchingSHA256() async throws {
        let session = URLProtocolFixture.session([
            .init(201, registration()), .init(200, "{}"), .init(200, storedAsset),
        ])
        let storage = try XCTUnwrap(session.configuration.httpCookieStorage)
        let cookie = try XCTUnwrap(HTTPCookie(properties: [
            .domain: "storage.example", .path: "/", .name: "api.session", .value: "secret",
        ]))
        storage.setCookie(cookie)
        defer { storage.deleteCookie(cookie) }
        let api = APIClient(session: session, baseURL: "https://app.thorbis.com")
        let transfer = MediaTransfer(api: api, storageSession: session)

        let asset = try await transfer.upload(jobID: jobID, clientAssetID: clientAssetID,
                                              kind: "photo", mime: "image/jpeg",
                                              originalFilename: "work.jpg", data: Data("hello".utf8))

        XCTAssertEqual(asset.id, assetID)
        XCTAssertEqual(asset.uploadState, "stored")
        let requests = URLProtocolFixture.recorded
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests[0].url?.path, "/v1/jobs/\(jobID)/media")
        XCTAssertEqual(requests[0].method, "POST")
        let body = try XCTUnwrap(requests[0].body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["clientAssetId"] as? String, clientAssetID)
        XCTAssertEqual(json["sizeBytes"] as? Int, 5)
        XCTAssertEqual(json["contentHash"] as? String, helloHash)
        XCTAssertEqual(requests[1].url?.absoluteString, "https://storage.example/upload?token=abc")
        XCTAssertEqual(requests[1].method, "PUT")
        XCTAssertEqual(requests[1].body, Data("hello".utf8))
        XCTAssertEqual(requests[1].header("content-type"), "image/jpeg")
        XCTAssertEqual(requests[1].header("x-amz-checksum-sha256"), helloChecksumHeader)
        XCTAssertEqual(requests[1].header("x-custom"), "preserve")
        XCTAssertNil(requests[1].header("cookie"))
        XCTAssertEqual(requests[2].url?.path, "/v1/media/\(assetID)/confirm")
        XCTAssertEqual(requests[2].method, "POST")
    }

    func testRefusesMediaLargerThanSinglePUTLimitBeforeRegistration() async {
        let session = URLProtocolFixture.session([])
        let api = APIClient(session: session, baseURL: "https://app.thorbis.com")
        let transfer = MediaTransfer(api: api, storageSession: session)

        do {
            _ = try await transfer.upload(jobID: jobID, clientAssetID: clientAssetID,
                                          kind: "photo", mime: "image/jpeg", originalFilename: "big.jpg",
                                          data: Data(repeating: 0, count: 8 * 1024 * 1024 + 1))
            XCTFail("Multipart path is not available")
        } catch is Problem {}
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(URLProtocolFixture.recorded.isEmpty)
    }

    func testRetryWithSameClientAssetIDRejectsDifferentRegisteredBytes() async {
        let previouslyStored = storedAsset.replacingOccurrences(of: helloHash,
            with: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
        let session = URLProtocolFixture.session([.init(201, #"{"asset":\#(previouslyStored)}"#)])
        let api = APIClient(session: session, baseURL: "https://app.thorbis.com")
        let transfer = MediaTransfer(api: api, storageSession: session)

        do {
            _ = try await transfer.upload(jobID: jobID, clientAssetID: clientAssetID,
                                          kind: "photo", mime: "image/jpeg", originalFilename: "work.jpg",
                                          data: Data("hello".utf8))
            XCTFail("Client asset ID collision accepted")
        } catch is Problem {}
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
    }

    func testRejectsInsecureAndUserInfoStorageTargetsBeforePUT() async {
        for url in ["http://storage.example/upload", "https://user:pass@storage.example/upload"] {
            let session = URLProtocolFixture.session([.init(201, registration(url: url))])
            let api = APIClient(session: session, baseURL: "https://app.thorbis.com")
            let transfer = MediaTransfer(api: api, storageSession: session)

            do {
                _ = try await transfer.upload(jobID: jobID, clientAssetID: clientAssetID,
                                              kind: "photo", mime: "image/jpeg", originalFilename: "work.jpg",
                                              data: Data("hello".utf8))
                XCTFail("Invalid target accepted: \(url)")
            } catch is Problem {}
            catch { XCTFail("Unexpected error: \(error)") }
            XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
        }
    }

    func testRejectsExpiredStorageTargetBeforePUT() async {
        let session = URLProtocolFixture.session([.init(201, registration(expiresAt: "2020-01-01T00:00:00Z"))])
        let api = APIClient(session: session, baseURL: "https://app.thorbis.com")
        let transfer = MediaTransfer(api: api, storageSession: session)

        do {
            _ = try await transfer.upload(jobID: jobID, clientAssetID: clientAssetID,
                                          kind: "photo", mime: "image/jpeg", originalFilename: "work.jpg",
                                          data: Data("hello".utf8))
            XCTFail("Expired target accepted")
        } catch is Problem {}
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
    }

    func testIdentityInvalidationDuringPUTPreventsConfirm() async throws {
        let gate = URLProtocolFixture.Gate()
        let session = URLProtocolFixture.session([
            .init(201, registration()), .init(200, "{}", gate: gate),
        ])
        let api = APIClient(session: session, baseURL: "https://app.thorbis.com")
        let transfer = MediaTransfer(api: api, storageSession: session)
        let task = Task {
            try await transfer.upload(jobID: jobID, clientAssetID: clientAssetID,
                                      kind: "photo", mime: "image/jpeg", originalFilename: "work.jpg",
                                      data: Data("hello".utf8))
        }
        try await waitForRequestCount(2)

        api.invalidateRequests()
        gate.release()

        do {
            _ = try await task.value
            XCTFail("Stale transfer should not confirm")
        } catch is CancellationError {}
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(URLProtocolFixture.recorded.count, 2)
    }

    func testMediaDownloadReturnsValidatedExpiringURL() async throws {
        let session = URLProtocolFixture.session([
            .init(200, #"{"url":"https://storage.example/download?token=abc","expiresAt":"2030-12-31T00:00:00Z"}"#),
        ])
        let api = APIClient(session: session, baseURL: "https://app.thorbis.com")

        let target = try await api.mediaDownload(assetID)

        XCTAssertEqual(target.url.absoluteString, "https://storage.example/download?token=abc")
        XCTAssertGreaterThan(target.expiresAt, Date())
        XCTAssertEqual(URLProtocolFixture.recorded.first?.url?.path, "/v1/media/\(assetID)/download")
    }

    func testDownloadWritesNativePreviewFileWithoutStorageCookies() async throws {
        let session = URLProtocolFixture.session([
            .init(200, #"{"url":"https://storage.example/download?token=abc","expiresAt":"2030-12-31T00:00:00Z"}"#),
            .init(200, "preview bytes"),
        ])
        let storage = try XCTUnwrap(session.configuration.httpCookieStorage)
        let cookie = try XCTUnwrap(HTTPCookie(properties: [
            .domain: "storage.example", .path: "/", .name: "api.session", .value: "secret",
        ]))
        storage.setCookie(cookie)
        defer { storage.deleteCookie(cookie) }
        let api = APIClient(session: session, baseURL: "https://app.thorbis.com")
        let transfer = MediaTransfer(api: api, storageSession: session)

        let file = try await transfer.download(mediaID: assetID, filename: "site-photo.jpg")
        defer { try? FileManager.default.removeItem(at: file) }

        XCTAssertTrue(file.isFileURL)
        XCTAssertEqual(file.pathExtension, "jpg")
        XCTAssertEqual(try Data(contentsOf: file), Data("preview bytes".utf8))
        XCTAssertEqual(URLProtocolFixture.recorded.count, 2)
        XCTAssertEqual(URLProtocolFixture.recorded[1].method, "GET")
        XCTAssertNil(URLProtocolFixture.recorded[1].header("cookie"))
    }

    func testConflictingUploadMethodsAreRejectedBeforeStorageRequest() async {
        let both = #"{"asset":\#(pendingAsset),"uploadTarget":{"url":"https://storage.example/upload","method":"PUT","expiresAt":"2030-12-31T00:00:00Z","headers":{}},"resumable":{"uploadId":"u1","partSize":8388608,"parts":[],"expiresAt":"2030-12-31T00:00:00Z"}}"#
        let session = URLProtocolFixture.session([.init(201, both)])
        let api = APIClient(session: session, baseURL: "https://app.thorbis.com")
        let transfer = MediaTransfer(api: api, storageSession: session)

        do {
            _ = try await transfer.upload(jobID: jobID, clientAssetID: clientAssetID,
                                          kind: "photo", mime: "image/jpeg", originalFilename: "work.jpg",
                                          data: Data("hello".utf8))
            XCTFail("Conflicting upload methods accepted")
        } catch is Problem {}
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
    }

    private func waitForRequestCount(_ count: Int) async throws {
        for _ in 0..<100 {
            if URLProtocolFixture.recorded.count >= count { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for \(count) requests")
    }
}

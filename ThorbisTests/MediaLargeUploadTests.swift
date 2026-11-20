import CryptoKit
import XCTest
@testable import Thorbis

/// Files over 8 MiB: how they are cut and hashed, what is sent, how a send carries on, and what a
/// person reads when the server can't take them yet.
@MainActor
final class MediaLargeUploadTests: XCTestCase {
    private let jobID = "11111111-1111-4111-8111-111111111111"
    private let assetID = "22222222-2222-4222-8222-222222222222"
    private let organizationID = "44444444-4444-4444-8444-444444444444"
    private let origin = "https://app.thorbis.com"
    private let part = MediaParts.partSize
    private var root: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        MediaLargeUploads.forget()
    }
    override func tearDown() async throws {
        try FileManager.default.removeItem(at: root)
        MediaLargeUploads.forget()
    }

    private func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    /// A file of `count` bytes that never repeats on a part boundary.
    private func bytes(_ count: Int) -> Data {
        var data = Data(count: count)
        data.withUnsafeMutableBytes { raw in
            let buffer = raw.bindMemory(to: UInt8.self)
            for index in 0..<count { buffer[index] = UInt8(truncatingIfNeeded: index &* 31 &+ index / 251) }
        }
        return data
    }
    private func file(_ data: Data, name: String = "clip.mp4") throws -> URL {
        let url = root.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    // MARK: Cutting and hashing

    func testPartSizesForExactMultipleOneByteOverAndTheLimits() {
        XCTAssertEqual(MediaParts.partSize, 8_388_608)
        XCTAssertEqual(MediaParts.sizes(for: part), [part])
        XCTAssertFalse(MediaParts.isLarge(part), "8 MiB exactly is one upload")
        XCTAssertTrue(MediaParts.isLarge(part + 1))
        XCTAssertEqual(MediaParts.sizes(for: part + 1), [part, 1])
        XCTAssertEqual(MediaParts.sizes(for: part * 2), [part, part], "An exact multiple has no empty last part")
        XCTAssertEqual(MediaParts.sizes(for: part * 2 + 1), [part, part, 1])
        XCTAssertEqual(MediaParts.sizes(for: 50 * 1024 * 1024).count, 7)
        XCTAssertEqual(MediaParts.sizes(for: 50 * 1024 * 1024).last, 2 * 1024 * 1024)
        XCTAssertEqual(MediaParts.sizes(for: 200 * 1024 * 1024).count, MediaParts.maxParts)
        XCTAssertEqual(MediaParts.sizes(for: 0), [])
        for size in [1, part, part + 1, part * 3, 200 * 1024 * 1024] {
            XCTAssertEqual(MediaParts.sizes(for: size).reduce(0, +), size)
        }
    }

    func testDigestHashesEachPartAndTheWholeFileInOnePass() throws {
        // Small parts so every boundary case is cheap: 4-byte parts read 3 bytes at a time.
        for count in [1, 3, 4, 5, 8, 9, 12, 13] {
            let data = bytes(count)
            let digest = try MediaParts.digest(of: try file(data, name: "small-\(count)"), chunk: 3, partSize: 4)
            let expected = stride(from: 0, to: count, by: 4).map { sha(data.subdata(in: $0..<min($0 + 4, count))) }
            XCTAssertEqual(digest.partHashes, expected, "\(count) bytes")
            XCTAssertEqual(digest.partHashes.count, (count + 3) / 4, "\(count) bytes")
            XCTAssertEqual(digest.contentHash, sha(data))
            XCTAssertEqual(digest.sizeBytes, count)
        }
    }

    func testDigestAtTheRealPartSizeForExactMultipleAndOneByteOver() throws {
        let exact = bytes(part * 2)
        let exactDigest = try MediaParts.digest(of: try file(exact, name: "exact"))
        XCTAssertEqual(exactDigest.partHashes, [sha(exact.prefix(part)), sha(exact.suffix(part))])
        XCTAssertEqual(exactDigest.contentHash, sha(exact))

        let over = bytes(part + 1)
        let overDigest = try MediaParts.digest(of: try file(over, name: "over"))
        XCTAssertEqual(overDigest.partHashes, [sha(over.prefix(part)), sha(over.suffix(1))])
        XCTAssertEqual(try MediaParts.read(file(over, name: "over"), partNumber: 2, sizeBytes: 1), over.suffix(1))
        XCTAssertEqual(try MediaParts.read(file(over, name: "over"), partNumber: 1, sizeBytes: part), over.prefix(part))
        XCTAssertThrowsError(try MediaParts.read(file(over, name: "over"), partNumber: 2, sizeBytes: 2), "A short part is never sent")
    }

    // MARK: Request bodies

    private func json(_ value: some Encodable) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }

    func testRegistrationCarriesPartHashesOnlyAboveEightMiB() throws {
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        let big = MediaFileDigest(sizeBytes: part + 1, contentHash: String(repeating: "a", count: 64),
                                  partHashes: [String(repeating: "b", count: 64), String(repeating: "c", count: 64)])
        let large = try json(MediaParts.registration(clientAssetID: "33333333-3333-4333-8333-333333333333", kind: "video", mime: "video/mp4",
                                                     originalFilename: "clip.mp4", digest: big, capturedAt: when, tags: [], caption: "Video clip"))
        XCTAssertEqual(large["partHashes"] as? [String], big.partHashes)
        XCTAssertEqual(large["contentHash"] as? String, big.contentHash, "The whole-file hash is still sent")
        XCTAssertEqual(large["sizeBytes"] as? Int, part + 1)
        XCTAssertEqual(large["capturedAt"] as? String, "2023-11-14T22:13:20Z")
        XCTAssertNil(large["tags"])

        let exactly = MediaFileDigest(sizeBytes: part, contentHash: big.contentHash, partHashes: [big.partHashes[0]])
        let small = try json(MediaParts.registration(clientAssetID: "33333333-3333-4333-8333-333333333333", kind: "photo", mime: "image/jpeg",
                                                     originalFilename: "a.jpg", digest: exactly, capturedAt: when, tags: ["Before"], caption: nil))
        XCTAssertFalse(small.keys.contains("partHashes"), "The server refuses part hashes at or under 8 MiB")
        let plain = try json(FieldMediaRegistrationRequest(clientAssetId: "x", kind: "photo", mime: "image/jpeg", sizeBytes: 4,
                                                           originalFilename: "a.jpg", contentHash: "h"))
        XCTAssertFalse(plain.keys.contains("partHashes"))
    }

    func testConfirmationNamesEveryPartInOrderOrNothing() throws {
        let digest = MediaFileDigest(sizeBytes: part * 2 + 1, contentHash: "w", partHashes: ["h1", "h2", "h3"])
        XCTAssertNil(MediaParts.confirmation(uploadID: "u", digest: digest, etags: [1: "a", 3: "c"]), "A missing part is never confirmed")
        let body = try XCTUnwrap(MediaParts.confirmation(uploadID: "u", digest: digest, etags: [3: "c", 1: "a", 2: "\"b\""]))
        XCTAssertEqual(body.parts.map(\.partNumber), [1, 2, 3])
        XCTAssertEqual(body.parts.map(\.etag), ["a", "\"b\"", "c"], "The tag is kept exactly as storage answered it")
        XCTAssertEqual(body.parts.map(\.contentHash), ["h1", "h2", "h3"])
        XCTAssertEqual(body.uploadId, "u")
    }

    // MARK: Limits, words and what the phone has learned

    func testLimitsPerKindAreTheServersUnlessItSaidNo() {
        let mb = MediaLimits.megabyte
        XCTAssertEqual(MediaLimits.uploadLimit(kind: "photo"), 50 * mb)
        XCTAssertEqual(MediaLimits.uploadLimit(kind: "document"), 50 * mb)
        XCTAssertEqual(MediaLimits.uploadLimit(kind: "video"), 200 * mb)
        for kind in ["photo", "document", "video"] { XCTAssertEqual(MediaLimits.uploadLimit(kind: kind, large: false), 8 * mb) }
        XCTAssertNil(MediaLimits.check(mime: "application/pdf", bytes: 50 * mb))
        XCTAssertEqual(MediaLimits.check(mime: "application/pdf", bytes: 50 * mb + 1), .tooLarge(limitBytes: 50 * mb))
        XCTAssertNil(MediaLimits.check(mime: "image/heic", bytes: 50 * mb))
        XCTAssertEqual(MediaLimits.check(mime: "image/jpeg", bytes: 50 * mb + 1), .tooLarge(limitBytes: 50 * mb))
        XCTAssertNil(MediaLimits.check(mime: "video/mp4", bytes: 200 * mb))
        XCTAssertEqual(MediaLimits.check(mime: "video/quicktime", bytes: 200 * mb + 1), .tooLarge(limitBytes: 200 * mb))
        XCTAssertEqual(MediaLimits.message(.tooLarge(limitBytes: 200 * mb), name: "walk.mp4"), "walk.mp4 is too big. Files can be up to 200 MB.")
        XCTAssertEqual(MediaLimits.check(mime: "video/mp4", bytes: 8 * mb + 1, large: false), .tooLarge(limitBytes: 8 * mb))
    }

    func testTheWordsAPersonReads() {
        XCTAssertEqual(MediaUploadWords.tooBigForNow, "This file is too big to send yet. Files can be up to 8 MB.")
        XCTAssertEqual(MediaUploadWords.storageDown, "Photos can\u{2019}t be saved right now. They\u{2019}re kept on this phone and will send later.")
        XCTAssertEqual(MediaUploadWords.keptFirstPart(seconds: 20.6), "Video clips are limited to 8 MB for now, so the first 20 seconds were kept.")
    }

    func testQueueLineShowsPlaceAndPercentAndStopsForStorage() {
        XCTAssertEqual(MediaQueue.line(waiting: ["a", "b", "c", "d", "e"], sendingID: "b", failed: 0, offline: false, percent: 40), "Sending 2 of 5\u{2026} 40%")
        XCTAssertEqual(MediaQueue.line(waiting: ["a"], sendingID: "a", failed: 0, offline: false, percent: 0), "Sending now\u{2026} 0%")
        XCTAssertEqual(MediaQueue.line(waiting: ["a", "b"], sendingID: "a", failed: 0, offline: false), "Sending 1 of 2\u{2026}", "A small file shows no percent")
        XCTAssertEqual(MediaQueue.line(waiting: ["a"], sendingID: nil, failed: 0, offline: false, storageDown: true), MediaUploadWords.storageDown)
        XCTAssertEqual(MediaQueue.line(waiting: ["a"], sendingID: nil, failed: 1, offline: false, storageDown: true), "1 couldn\u{2019}t send. Tap one to see why.")
        XCTAssertEqual(MediaQueue.afterFailure(cancelled: false, connectivity: false, storageDown: true), .stop)
        XCTAssertEqual(MediaQueue.afterFailure(cancelled: false, connectivity: false), .next)
    }

    func testProgressCountsPartsAndStartsFromWhatTheServerHolds() {
        var far = MediaUploadProgress.starting(uploadID: "u", totalParts: 5, held: [1: "a", 2: "b", 9: "stray"])
        XCTAssertEqual(far.sentParts, 2); XCTAssertEqual(far.percent, 40); XCTAssertEqual(far.missingParts, [3, 4, 5])
        far.etags[3] = "c"; far.etags[4] = "d"; far.etags[5] = "e"
        XCTAssertEqual(far.percent, 99, "Not 100 until the server confirms")
        XCTAssertEqual(MediaUploadProgress.starting(uploadID: "u2", totalParts: 5, held: [1: "a"], sendEveryPart: true).missingParts, [1, 2, 3, 4, 5])
        XCTAssertEqual(try JSONDecoder().decode(MediaUploadProgress.self, from: JSONEncoder().encode(far)), far)
    }

    func testTheServersAnswerIsRememberedForADayWhenItIsNo() {
        let defaults = UserDefaults(suiteName: "large-\(UUID().uuidString)")!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(MediaLargeUploads.answer(origin: origin, now: now, defaults: defaults), .unknown)
        XCTAssertTrue(MediaLargeUploads.allowed(origin: origin, now: now, defaults: defaults), "Unknown: a big file is tried")
        MediaLargeUploads.record(false, origin: origin, now: now, defaults: defaults)
        XCTAssertEqual(MediaLargeUploads.answer(origin: origin, now: now.addingTimeInterval(3600), defaults: defaults), .no)
        XCTAssertFalse(MediaLargeUploads.allowed(origin: origin, now: now.addingTimeInterval(3600), defaults: defaults))
        XCTAssertEqual(MediaLargeUploads.answer(origin: "https://other.example", now: now, defaults: defaults), .unknown, "One server's answer is not another's")
        XCTAssertEqual(MediaLargeUploads.answer(origin: origin, now: now.addingTimeInterval(25 * 3600), defaults: defaults), .unknown, "Asked again after a day")
        MediaLargeUploads.record(true, origin: origin, now: now, defaults: defaults)
        XCTAssertEqual(MediaLargeUploads.answer(origin: origin, now: now.addingTimeInterval(400 * 24 * 3600), defaults: defaults), .yes)
    }

    // MARK: Sending

    private func asset(_ digest: MediaFileDigest, state: String) -> String {
        #"{"id":"\#(assetID)","organizationId":"\#(organizationID)","jobId":"\#(jobID)","uploaderUserId":"55555555-5555-4555-8555-555555555555","kind":"video","mime":"video/mp4","sizeBytes":\#(digest.sizeBytes),"originalFilename":"clip.mp4","contentHash":"\#(digest.contentHash)","storageKey":"tenant/jobs/clip.mp4","uploadState":"\#(state)","tags":[],"archived":false,"createdAt":"2026-11-20T00:00:00Z","updatedAt":"2026-11-20T00:00:00Z"}"#
    }

    /// The new server's answer: one entry per part, with its size and headers, and `etag` on parts it holds.
    private func plan(_ digest: MediaFileDigest, uploadID: String = "upload-1", held: [Int: String] = [:],
                      expiresAt: String = "2030-12-31T00:00:00Z") -> String {
        let parts = MediaParts.sizes(for: digest.sizeBytes).enumerated().map { index, size -> String in
            let etag = held[index + 1].map { #","etag":"\#($0.replacingOccurrences(of: "\"", with: "\\\""))""# } ?? ""
            return #"{"partNumber":\#(index + 1),"url":"https://storage.example/part/\#(index + 1)?sig=\#(uploadID)","expiresAt":"\#(expiresAt)","sizeBytes":\#(size),"headers":{"x-amz-checksum-sha256":"sum-\#(index + 1)"}\#(etag)}"#
        }.joined(separator: ",")
        return #"{"asset":\#(asset(digest, state: "pending")),"resumable":{"uploadId":"\#(uploadID)","partSize":8388608,"expiresAt":"2030-12-31T00:00:00Z","parts":[\#(parts)]}}"#
    }

    /// Today's server: a parts plan with no sizes or headers, which its confirm route cannot finish.
    private func oldPlan(_ digest: MediaFileDigest) -> String {
        let parts = MediaParts.sizes(for: digest.sizeBytes).indices.map {
            #"{"partNumber":\#($0 + 1),"url":"https://storage.example/part/\#($0 + 1)","expiresAt":"2030-12-31T00:00:00Z"}"#
        }.joined(separator: ",")
        return #"{"asset":\#(asset(digest, state: "pending")),"resumable":{"uploadId":"old","partSize":8388608,"expiresAt":"2030-12-31T00:00:00Z","parts":[\#(parts)]}}"#
    }

    private func send(_ replies: [URLProtocolFixture.Reply], file url: URL, digest: MediaFileDigest,
                      progress: @escaping @MainActor (MediaUploadProgress) -> Void = { _ in }) async throws -> MediaAssetRecord {
        let session = URLProtocolFixture.session(replies)
        let api = APIClient(session: session, baseURL: origin)
        return try await MediaTransfer(api: api, storageSession: session).uploadLarge(
            jobID: jobID, clientAssetID: "33333333-3333-4333-8333-333333333333", kind: "video", mime: "video/mp4",
            originalFilename: "clip.mp4", file: url, digest: digest, caption: "Video clip",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000), expectedOrganizationID: organizationID, onProgress: progress)
    }

    func testSendsEachMissingPartWithItsHeadersThenConfirmsEveryPart() async throws {
        let data = bytes(part * 2 + 1)
        let url = try file(data)
        let digest = try MediaParts.digest(of: url)
        var seen: [MediaUploadProgress] = []
        let stored = try await send([
            .init(201, plan(digest, held: [2: "\"held-2\""])),
            .init(200, "", headers: ["ETag": "\"tag-1\""]),
            .init(200, "", headers: ["ETag": "\"tag-3\""]),
            .init(200, asset(digest, state: "stored")),
        ], file: url, digest: digest) { seen.append($0) }
        XCTAssertEqual(stored.uploadState, "stored")
        let requests = URLProtocolFixture.recorded
        XCTAssertEqual(requests.map(\.method), ["POST", "PUT", "PUT", "POST"])
        let register = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(requests[0].body)) as? [String: Any])
        XCTAssertEqual(register["partHashes"] as? [String], digest.partHashes)
        XCTAssertEqual((register["partHashes"] as? [String])?.count, 3)
        // Part 2 is already in storage, so only parts 1 and 3 go, each with exactly its bytes.
        XCTAssertEqual(requests[1].url?.path, "/part/1"); XCTAssertEqual(requests[1].body, data.prefix(part))
        XCTAssertEqual(requests[2].url?.path, "/part/3"); XCTAssertEqual(requests[2].body, data.suffix(1))
        for put in requests[1...2] {
            XCTAssertNotNil(put.header("x-amz-checksum-sha256"))
            XCTAssertNil(put.header("cookie")); XCTAssertNil(put.header("authorization"))
            XCTAssertFalse(put.handlesCookies)
        }
        XCTAssertEqual(requests[1].header("x-amz-checksum-sha256"), "sum-1")
        XCTAssertEqual(requests[3].url?.path, "/v1/media/\(assetID)/confirm")
        let confirm = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(requests[3].body)) as? [String: Any])
        let multipart = try XCTUnwrap(confirm["multipart"] as? [String: Any])
        XCTAssertEqual(multipart["uploadId"] as? String, "upload-1")
        let parts = try XCTUnwrap(multipart["parts"] as? [[String: Any]])
        XCTAssertEqual(parts.map { $0["partNumber"] as? Int }, [1, 2, 3])
        XCTAssertEqual(parts.map { $0["etag"] as? String }, ["\"tag-1\"", "\"held-2\"", "\"tag-3\""])
        XCTAssertEqual(parts.map { $0["contentHash"] as? String }, digest.partHashes)
        XCTAssertEqual(seen.map(\.sentParts), [1, 2, 3], "Progress is reported as each part lands")
        XCTAssertEqual(MediaLargeUploads.answer(origin: origin), .yes)
    }

    func testAnExpiredAddressAsksForFreshOnesAndCarriesOn() async throws {
        let url = try file(bytes(part + 1))
        let digest = try MediaParts.digest(of: url)
        _ = try await send([
            .init(201, plan(digest)),
            .init(200, "", headers: ["ETag": "t1"]),
            .init(403, ""),                                   // part 2's address ran out
            .init(201, plan(digest, held: [1: "t1"])),        // same upload, fresh addresses, part 1 held
            .init(200, "", headers: ["ETag": "t2"]),
            .init(200, asset(digest, state: "stored")),
        ], file: url, digest: digest)
        let requests = URLProtocolFixture.recorded
        XCTAssertEqual(requests.map(\.method), ["POST", "PUT", "PUT", "POST", "PUT", "POST"])
        XCTAssertEqual(try JSONSerialization.jsonObject(with: XCTUnwrap(requests[0].body)) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: XCTUnwrap(requests[3].body)) as? NSDictionary, "The identical registration is sent again")
        XCTAssertEqual(requests[4].url?.path, "/part/2", "Part 1 is not sent twice")
    }

    func testAStoreThatKeepsRefusingNeverLoops() async throws {
        let url = try file(bytes(part + 1))
        let digest = try MediaParts.digest(of: url)
        do {
            _ = try await send(Array(repeating: [.init(201, plan(digest)), .init(403, "")], count: 10).flatMap { $0 }, file: url, digest: digest)
            XCTFail("A store that refuses every part cannot finish")
        } catch {
            let problem = try XCTUnwrap(error as? Problem)
            XCTAssertEqual(problem.title, MediaTransfer.storageUploadFailureTitle)
            XCTAssertEqual(problem.status, 403)
        }
        XCTAssertEqual(URLProtocolFixture.recorded.count, 2 * (MediaTransfer.maxRestartsPerAttempt + 1), "First try plus two restarts, then it stops")
    }

    func testWrongBytesAndAMissingTagFailWithoutConfirming() async throws {
        let url = try file(bytes(part + 1))
        let digest = try MediaParts.digest(of: url)
        for reply in [URLProtocolFixture.Reply(400, ""), .init(200, "")] {
            do {
                _ = try await send([.init(201, plan(digest)), reply], file: url, digest: digest)
                XCTFail("Must not confirm")
            } catch { XCTAssertEqual((error as? Problem)?.title, MediaTransfer.storageUploadFailureTitle) }
            XCTAssertEqual(URLProtocolFixture.recorded.count, 2)
        }
    }

    func testARefusedUploadIDRegistersAgainAndSendsEveryPart() async throws {
        let url = try file(bytes(part + 1))
        let digest = try MediaParts.digest(of: url)
        let refused = #"{"title":"validation","status":400,"category":"validation","detail":"invalid","errors":[{"path":"multipart.uploadId","message":"upload is not open; register the asset again to restart it"}]}"#
        _ = try await send([
            .init(201, plan(digest, held: [1: "t1", 2: "t2"])),
            .init(400, refused),
            .init(201, plan(digest, uploadID: "upload-2", held: [1: "stale"])),
            .init(200, "", headers: ["ETag": "n1"]),
            .init(200, "", headers: ["ETag": "n2"]),
            .init(200, asset(digest, state: "stored")),
        ], file: url, digest: digest)
        let requests = URLProtocolFixture.recorded
        XCTAssertEqual(requests.map(\.method), ["POST", "POST", "POST", "PUT", "PUT", "POST"])
        XCTAssertEqual(requests[3].url?.path, "/part/1"); XCTAssertEqual(requests[4].url?.path, "/part/2")
        let confirm = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(requests[5].body)) as? [String: Any])
        let multipart = try XCTUnwrap(confirm["multipart"] as? [String: Any])
        XCTAssertEqual(multipart["uploadId"] as? String, "upload-2")
        XCTAssertEqual((multipart["parts"] as? [[String: Any]])?.map { $0["etag"] as? String }, ["n1", "n2"])
    }

    func testAnAlreadyStoredFileIsNotSentAgain() async throws {
        let url = try file(bytes(part + 1))
        let digest = try MediaParts.digest(of: url)
        let stored = try await send([.init(200, #"{"asset":\#(asset(digest, state: "stored"))}"#)], file: url, digest: digest)
        XCTAssertEqual(stored.id, assetID)
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
    }

    // MARK: Today's server

    func testAServerThatCannotFinishBigFilesFailsOnceWithPlainWords() async throws {
        let url = try file(bytes(part + 1))
        let digest = try MediaParts.digest(of: url)
        let refusedHashes = #"{"title":"validation","status":400,"category":"validation","detail":"invalid","errors":[{"path":"partHashes","message":"part hashes apply only above 8388608 bytes"}]}"#
        let refusedSize = #"{"title":"validation","status":400,"category":"validation","errors":[{"path":"sizeBytes","message":"video exceeds 8388608 bytes"}]}"#
        let single = #"{"asset":\#(asset(digest, state: "pending")),"uploadTarget":{"url":"https://storage.example/upload","method":"PUT","expiresAt":"2030-12-31T00:00:00Z","headers":{}}}"#
        for reply in [URLProtocolFixture.Reply(201, oldPlan(digest)), .init(201, single), .init(400, refusedHashes), .init(400, refusedSize)] {
            MediaLargeUploads.forget()
            do {
                _ = try await send([reply], file: url, digest: digest)
                XCTFail("Today's server cannot take this file")
            } catch {
                XCTAssertTrue(MediaTransfer.isTooBigForNow(error))
                XCTAssertEqual(error.localizedDescription, "This file is too big to send yet. Files can be up to 8 MB.")
            }
            XCTAssertEqual(URLProtocolFixture.recorded.count, 1, "Nothing is sent to storage and nothing is asked twice")
            XCTAssertEqual(MediaLargeUploads.answer(origin: origin), .no)
        }
    }

    func testStorageNotAnsweringIsSaidPlainlyForBigAndSmallFiles() async throws {
        let down = #"{"title":"dependency","status":502,"category":"dependency","detail":"object storage is not configured"}"#
        let url = try file(bytes(part + 1))
        let digest = try MediaParts.digest(of: url)
        for status in [502, 504] {
            do { _ = try await send([.init(status, down)], file: url, digest: digest); XCTFail("No storage") }
            catch {
                XCTAssertTrue(MediaTransfer.isStorageUnavailable(error))
                XCTAssertEqual(error.localizedDescription, MediaUploadWords.storageDown)
            }
            XCTAssertEqual(MediaLargeUploads.answer(origin: origin), .unknown, "A storage outage says nothing about big files")
        }
        let session = URLProtocolFixture.session([.init(502, down)])
        do {
            _ = try await MediaTransfer(api: APIClient(session: session, baseURL: origin), storageSession: session)
                .upload(jobID: jobID, clientAssetID: "33333333-3333-4333-8333-333333333333", kind: "photo", mime: "image/jpeg",
                        originalFilename: "a.jpg", data: Data("hello".utf8))
            XCTFail("No storage")
        } catch { XCTAssertEqual(error.localizedDescription, MediaUploadWords.storageDown) }
    }

    func testProblemKeepsTheFieldsAValidationRefusalNames() throws {
        let body = #"{"title":"validation","status":400,"detail":"invalid","errors":[{"path":"multipart.parts.3","message":"part is not uploaded"}]}"#
        let problem = try JSONDecoder().decode(Problem.self, from: Data(body.utf8))
        XCTAssertTrue(problem.names("multipart")); XCTAssertTrue(problem.names("multipart.parts")); XCTAssertFalse(problem.names("multipart.uploadId"))
        XCTAssertFalse(problem.names("multi"))
        let odd = try JSONDecoder().decode(Problem.self, from: Data(#"{"title":"validation","detail":"d","errors":"nope"}"#.utf8))
        XCTAssertEqual(odd.detail, "d"); XCTAssertNil(odd.errors)
    }

    // MARK: The queue on the phone

    private let scope = PendingMediaScope(actorID: "actor-a", organizationID: "44444444-4444-4444-8444-444444444444", origin: "https://app.thorbis.com")
    private func clip(_ id: String = "33333333-3333-4333-8333-333333333333") -> PendingMedia {
        PendingMedia(id: id, jobID: jobID, filename: "clip.mp4", tags: [], capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                     kind: "video", mime: "video/mp4", caption: "Video clip")
    }
    private func queue() -> PendingMediaStore {
        let store = PendingMediaStore(directory: root.appendingPathComponent("queue"))
        store.bind(scope)
        return store
    }

    func testABigFileIsSavedFromDiskAndItsProgressSurvivesARestart() async throws {
        let data = bytes(part + 1)
        let url = try file(data)
        let digest = try MediaParts.digest(of: url)
        let first = queue()
        try await first.save(clip(), file: url, context: try XCTUnwrap(first.captureContext))
        XCTAssertEqual(first.items, [clip()])
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(first.payloadURL(clip()))), data)

        // Part 1 lands; storage fails on part 2.
        var network = URLProtocolFixture.session([.init(201, plan(digest)), .init(200, "", headers: ["ETag": "t1"]), .init(500, "")])
        await first.drain(api: APIClient(session: network, baseURL: origin), canUpload: { true }, storageSession: network)
        XCTAssertEqual(first.items, [clip()], "The file stays on the phone")
        XCTAssertEqual(first.progress[clip().id]?.etags, [1: "t1"])
        XCTAssertNotNil(first.errors[clip().id])

        // The app is closed and opened again: the same file, the same client ID, and how far it got.
        let second = queue()
        XCTAssertEqual(second.progress[clip().id], MediaUploadProgress(uploadID: "upload-1", totalParts: 2, etags: [1: "t1"]))
        XCTAssertEqual(second.progress[clip().id]?.percent, 50)
        network = URLProtocolFixture.session([.init(201, plan(digest, held: [1: "t1"])), .init(200, "", headers: ["ETag": "t2"]),
                                              .init(200, asset(digest, state: "stored"))])
        await second.drain(api: APIClient(session: network, baseURL: origin), canUpload: { true }, storageSession: network)
        XCTAssertTrue(second.items.isEmpty)
        XCTAssertNil(second.progress[clip().id])
        let requests = URLProtocolFixture.recorded
        XCTAssertEqual(requests.map(\.method), ["POST", "PUT", "POST"])
        XCTAssertEqual(requests[1].url?.path, "/part/2", "Only the part storage does not hold is sent")
        let register = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(requests[0].body)) as? [String: Any])
        XCTAssertEqual(register["clientAssetId"] as? String, clip().id)
        XCTAssertEqual(register["contentHash"] as? String, digest.contentHash)
    }

    func testOnTodaysServerABigFileFailsOnceAndStaysInTheQueue() async throws {
        let url = try file(bytes(part + 1))
        let digest = try MediaParts.digest(of: url)
        let store = queue()
        try await store.save(clip(), file: url, context: try XCTUnwrap(store.captureContext))
        let network = URLProtocolFixture.session([.init(201, oldPlan(digest))])
        await store.drain(api: APIClient(session: network, baseURL: origin), canUpload: { true }, storageSession: network)
        XCTAssertEqual(store.items, [clip()])
        XCTAssertEqual(store.errors[clip().id], "This file is too big to send yet. Files can be up to 8 MB.")
        XCTAssertEqual(MediaUploadState.of(clip(), in: store), .failed("This file is too big to send yet. Files can be up to 8 MB."))
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1, "One question, no loop")
        XCTAssertNil(store.fallbackNotice)
    }

    func testOnTodaysServerABigClipIsSwappedForItsSmallCopy() async throws {
        let url = try file(bytes(part + 1))
        let small = try file(Data("hello".utf8), name: "small.mp4")
        let digest = try MediaParts.digest(of: url)
        let store = queue()
        try await store.save(clip(), file: url, fallback: .init(file: small, trimmedSeconds: 20), context: try XCTUnwrap(store.captureContext))
        let smallAsset = #"{"id":"\#(assetID)","organizationId":"\#(organizationID)","jobId":"\#(jobID)","uploaderUserId":"actor-a","kind":"video","mime":"video/mp4","sizeBytes":5,"originalFilename":"clip.mp4","contentHash":"2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824","storageKey":"k","uploadState":"STATE","tags":[],"archived":false,"createdAt":"2026-11-20T00:00:00Z","updatedAt":"2026-11-20T00:00:00Z"}"#
        let target = #"{"asset":\#(smallAsset.replacingOccurrences(of: "STATE", with: "pending")),"uploadTarget":{"url":"https://storage.example/upload","method":"PUT","expiresAt":"2030-12-31T00:00:00Z","headers":{}}}"#
        let network = URLProtocolFixture.session([.init(201, oldPlan(digest)), .init(201, target), .init(200, ""),
                                                  .init(200, smallAsset.replacingOccurrences(of: "STATE", with: "stored"))])
        await store.drain(api: APIClient(session: network, baseURL: origin), canUpload: { true }, storageSession: network)
        XCTAssertTrue(store.items.isEmpty, "The small copy went in the big file's place")
        XCTAssertEqual(store.fallbackNotice, "Video clips are limited to 8 MB for now, so the first 20 seconds were kept.")
        let requests = URLProtocolFixture.recorded
        XCTAssertEqual(requests.count, 4)
        let big = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(requests[0].body)) as? [String: Any])
        let little = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(requests[1].body)) as? [String: Any])
        XCTAssertNotEqual(big["clientAssetId"] as? String, little["clientAssetId"] as? String, "Different bytes never reuse a client ID")
        XCTAssertEqual(little["sizeBytes"] as? Int, 5)
        XCTAssertFalse(little.keys.contains("partHashes"))
        XCTAssertEqual(little["caption"] as? String, "Video clip"); XCTAssertEqual(little["capturedAt"] as? String, big["capturedAt"] as? String)
        XCTAssertEqual(requests[2].body, Data("hello".utf8))
    }

    func testStorageNotAnsweringLeavesItemsWaitingAndStopsTheQueue() async throws {
        let store = queue()
        let context = try XCTUnwrap(store.captureContext)
        let one = clip("33333333-3333-4333-8333-000000000001"), two = clip("33333333-3333-4333-8333-000000000002")
        try store.save(one, data: Data("hello".utf8), context: context)
        try store.save(two, data: Data("hello".utf8), context: context)
        let network = URLProtocolFixture.session([.init(502, #"{"title":"dependency","status":502,"detail":"object storage is not configured"}"#)])
        await store.drain(api: APIClient(session: network, baseURL: origin), canUpload: { true }, storageSession: network)
        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1, "The second item is not tried against storage that is down")
        XCTAssertEqual(store.waitingForStorage, [one.id])
        XCTAssertEqual(MediaUploadState.of(one, in: store), .waiting, "Waiting, not failed")
        XCTAssertEqual(store.errors[one.id], MediaUploadWords.storageDown)
    }

    func testSavedSizesFollowTheServersLimitPerKind() async throws {
        let store = queue()
        let context = try XCTUnwrap(store.captureContext)
        let pdf = PendingMedia(id: UUID().uuidString, jobID: jobID, filename: "plans.pdf", tags: [], capturedAt: Date(), kind: "document", mime: "application/pdf")
        try store.save(pdf, data: bytes(part + 1), context: context)
        XCTAssertEqual(store.items, [pdf], "A PDF over 8 MB can be queued now")
        let wrongKind = PendingMedia(id: UUID().uuidString, jobID: jobID, filename: "plans.pdf", tags: [], capturedAt: Date(), kind: "photo", mime: "application/pdf")
        XCTAssertThrowsError(try store.save(wrongKind, data: Data("x".utf8), context: context))
        XCTAssertThrowsError(try store.save(clip(UUID().uuidString), data: Data(), context: context))
    }
}

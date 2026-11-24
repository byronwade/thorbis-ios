import CryptoKit
import Foundation

struct MediaDownloadTarget: Sendable {
    let url: URL
    let expiresAt: Date
}

@MainActor
final class MediaTransfer {
    static let storageUploadFailureTitle = "Storage upload failed"
    static func isRetryableStorageUploadFailure(_ error: Error) -> Bool {
        guard let problem = error as? Problem, problem.title == storageUploadFailureTitle else { return false }
        guard let status = problem.status else { return true }
        return (500...599).contains(status)
    }
    /// A big file on a server that cannot finish large uploads yet. Never retried by itself.
    static let tooBigForNowTitle = "Large upload unavailable"
    /// The server's storage did not answer (502 or 504). Safe to send again later.
    static let storageUnavailableTitle = "Storage unavailable"
    static func isTooBigForNow(_ error: Error) -> Bool { (error as? Problem)?.title == tooBigForNowTitle }
    static func isStorageUnavailable(_ error: Error) -> Bool { (error as? Problem)?.title == storageUnavailableTitle }
    /// How many times one attempt asks for fresh part addresses before giving up, so a server
    /// that keeps refusing can never make the phone go round forever.
    static let maxRestartsPerAttempt = 2
    private static let maxSinglePUTBytes = 8 * 1024 * 1024
    private static let maxPreviewBytes = 50 * 1024 * 1024

    private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    private let api: APIClient
    private let storageSession: URLSession

    init(api: APIClient, storageSession: URLSession? = nil) {
        self.api = api
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = storageSession?.configuration.protocolClasses
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.storageSession = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }

    // A URLSession keeps its delegate until invalidated; one is made per transfer.
    deinit { storageSession.finishTasksAndInvalidate() }

    func upload(jobID: String, clientAssetID: String, kind: String, mime: String,
                originalFilename: String, data: Data, tags: [String] = [], caption: String? = nil, capturedAt: Date? = nil,
                expectedOrganizationID: String? = nil, currentAuthority: @MainActor () -> Bool = { true }) async throws -> MediaAssetRecord {
        guard UUID(uuidString: clientAssetID) != nil else {
            throw Problem(title: "Invalid client asset ID", status: nil, detail: clientAssetID)
        }
        guard !data.isEmpty, data.count <= Self.maxSinglePUTBytes else {
            throw Problem(title: "Single PUT upload unavailable", status: nil,
                          detail: "Media must be between 1 byte and 8 MiB until multipart confirmation is supported.")
        }
        guard currentAuthority() else { throw CancellationError() }
        let generation = api.requestGeneration
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let request = FieldMediaRegistrationRequest(clientAssetId: clientAssetID, kind: kind,
                                                    mime: mime, sizeBytes: data.count,
                                                    originalFilename: originalFilename, contentHash: hash,
                                                    capturedAt: ISO8601DateFormatter().string(from: capturedAt ?? Date()),
                                                    tags: tags.isEmpty ? nil : tags, caption: caption)
        try verify(generation)
        guard currentAuthority() else { throw CancellationError() }
        let registration: FieldMediaRegistration
        do { registration = try await api.registerFieldMedia(jobID, request: request) }
        catch { throw Self.plain(error) }
        try verify(generation)
        guard currentAuthority() else { throw CancellationError() }
        guard registration.asset.contentHash == hash, registration.asset.sizeBytes == data.count,
              registration.asset.mime == mime, registration.asset.kind == kind,
              registration.asset.jobId == jobID, UUID(uuidString: registration.asset.id) != nil,
              expectedOrganizationID.map({ registration.asset.organizationId == $0 }) ?? true else {
            throw Problem(title: "Client asset ID collision", status: nil,
                          detail: "The existing media record belongs to different bytes.")
        }
        if registration.asset.uploadState == "stored" { return registration.asset }
        guard let target = registration.uploadTarget, registration.resumable == nil,
              target.method == "PUT" else {
            throw Problem(title: "Unsupported upload target", status: nil,
                          detail: "The service did not return a single PUT target.")
        }
        let url = try Self.validatedStorageURL(target.url)
        _ = try Self.validatedExpiry(target.expiresAt)
        try Self.checkStorageHeaders(target.headers)
        var upload = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        upload.httpMethod = "PUT"
        upload.httpShouldHandleCookies = false
        upload.httpBody = data
        for (name, value) in target.headers { upload.setValue(value, forHTTPHeaderField: name) }
        try verify(generation)
        guard currentAuthority() else { throw CancellationError() }
        let response: URLResponse
        do {
            (_, response) = try await storageSession.data(for: upload)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw Problem(title: Self.storageUploadFailureTitle, status: nil, detail: error.localizedDescription)
        }
        try verify(generation)
        guard currentAuthority() else { throw CancellationError() }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw Problem(title: Self.storageUploadFailureTitle,
                          status: (response as? HTTPURLResponse)?.statusCode, detail: nil)
        }
        guard currentAuthority() else { throw CancellationError() }
        let confirmed: MediaAssetRecord
        do { confirmed = try await api.confirmFieldMedia(registration.asset.id) }
        catch { throw Self.plain(error) }
        try verify(generation)
        guard currentAuthority() else { throw CancellationError() }
        guard confirmed.id == registration.asset.id, confirmed.jobId == jobID,
              confirmed.organizationId == registration.asset.organizationId,
              expectedOrganizationID.map({ confirmed.organizationId == $0 }) ?? true,
              confirmed.kind == kind, confirmed.mime == mime, confirmed.contentHash == hash,
              confirmed.sizeBytes == data.count, confirmed.uploadState == "stored" else {
            throw Problem(title: "Media not confirmed", status: nil,
                          detail: "The server has not confirmed this exact media. The saved copy remains on this phone.")
        }
        return confirmed
    }

    /// 502 and 504 from the API mean its storage is not answering: said plainly, nothing lost.
    private static func plain(_ error: Error) -> Error {
        guard let problem = error as? Problem, let status = problem.status, status == 502 || status == 504 else { return error }
        return Problem(title: storageUnavailableTitle, status: status, detail: MediaUploadWords.storageDown)
    }

    private func tooBigForNow() -> Problem {
        MediaLargeUploads.record(false, origin: api.normalizedOrigin)
        return Problem(title: Self.tooBigForNowTitle, status: nil, detail: MediaUploadWords.tooBigForNow)
    }

    /// Sends a file over 8 MiB in parts, straight from disk. Registering again with the same
    /// client ID carries on an unfinished send: the server lists the parts storage already holds
    /// and only the rest are sent. `onProgress` is called with what to keep on the phone.
    func uploadLarge(jobID: String, clientAssetID: String, kind: String, mime: String, originalFilename: String,
                     file: URL, digest: MediaFileDigest, tags: [String] = [], caption: String? = nil, capturedAt: Date,
                     expectedOrganizationID: String? = nil, onProgress: @MainActor (MediaUploadProgress) -> Void = { _ in },
                     currentAuthority: @MainActor () -> Bool = { true }) async throws -> MediaAssetRecord {
        guard UUID(uuidString: clientAssetID) != nil else {
            throw Problem(title: "Invalid client asset ID", status: nil, detail: clientAssetID)
        }
        let sizes = MediaParts.sizes(for: digest.sizeBytes)
        guard MediaParts.isLarge(digest.sizeBytes), sizes.count == digest.partHashes.count, sizes.count <= MediaParts.maxParts else {
            throw Problem(title: "Unsupported upload size", status: nil, detail: "This file cannot be sent in parts.")
        }
        guard currentAuthority() else { throw CancellationError() }
        let generation = api.requestGeneration
        let request = MediaParts.registration(clientAssetID: clientAssetID, kind: kind, mime: mime, originalFilename: originalFilename,
                                              digest: digest, capturedAt: capturedAt, tags: tags, caption: caption)
        func matches(_ asset: MediaAssetRecord) -> Bool {
            asset.contentHash == digest.contentHash && asset.sizeBytes == digest.sizeBytes && asset.mime == mime && asset.kind == kind
                && asset.jobId == jobID && UUID(uuidString: asset.id) != nil
                && (expectedOrganizationID.map { asset.organizationId == $0 } ?? true)
        }
        var restarts = 0
        var sendEveryPart = false
        while true {
            try verify(generation)
            guard currentAuthority() else { throw CancellationError() }
            let registration: FieldMediaRegistration
            do { registration = try await api.registerFieldMedia(jobID, request: request) }
            catch let problem as Problem where problem.status == 400 && (problem.names("partHashes") || problem.names("sizeBytes")) {
                throw tooBigForNow()
            }
            catch { throw Self.plain(error) }
            try verify(generation)
            guard currentAuthority() else { throw CancellationError() }
            guard matches(registration.asset) else {
                throw Problem(title: "Client asset ID collision", status: nil,
                              detail: "The existing media record belongs to different bytes.")
            }
            if registration.asset.uploadState == "stored" { return registration.asset }
            // A server that cannot finish large uploads answers with no parts plan, or with one
            // that has no part sizes and headers. Either way this file waits for the server.
            guard let plan = registration.resumable, registration.uploadTarget == nil,
                  plan.parts.contains(where: { $0.sizeBytes != nil && $0.headers != nil }) else { throw tooBigForNow() }
            let parts = plan.parts.sorted { $0.partNumber < $1.partNumber }
            guard plan.partSize == MediaParts.partSize, !plan.uploadId.isEmpty, parts.count == sizes.count,
                  parts.enumerated().allSatisfy({ $1.partNumber == $0 + 1 && $1.sizeBytes == sizes[$0] && $1.headers != nil }) else {
                throw Problem(title: "Unsupported upload target", status: nil,
                              detail: "The service returned parts that do not match this file.")
            }
            MediaLargeUploads.record(true, origin: api.normalizedOrigin)
            let held = Dictionary(uniqueKeysWithValues: parts.compactMap { part in part.etag.map { (part.partNumber, $0) } })
            var progress = MediaUploadProgress.starting(uploadID: plan.uploadId, totalParts: parts.count, held: held, sendEveryPart: sendEveryPart)
            sendEveryPart = false
            onProgress(progress)
            var needsFreshAddresses = false
            for part in parts where progress.etags[part.partNumber] == nil {
                try verify(generation)
                guard currentAuthority() else { throw CancellationError() }
                let headers = part.headers ?? [:]
                try Self.checkStorageHeaders(headers)
                let url = try Self.validatedStorageURL(part.url)
                // An address that ran out while earlier parts were going up: ask for fresh ones.
                guard (try? Self.validatedExpiry(part.expiresAt)) != nil else { needsFreshAddresses = true; break }
                let size = sizes[part.partNumber - 1], number = part.partNumber
                let bytes = try await Task.detached(priority: .utility) { try MediaParts.read(file, partNumber: number, sizeBytes: size) }.value
                var upload = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
                upload.httpMethod = "PUT"
                upload.httpShouldHandleCookies = false
                for (name, value) in headers { upload.setValue(value, forHTTPHeaderField: name) }
                let response: URLResponse
                do {
                    upload.httpBody = bytes
                    (_, response) = try await storageSession.data(for: upload)
                } catch is CancellationError {
                    throw CancellationError()
                } catch let error as URLError where error.code == .cancelled {
                    throw CancellationError()
                } catch {
                    throw Problem(title: Self.storageUploadFailureTitle, status: nil, detail: error.localizedDescription)
                }
                try verify(generation)
                guard currentAuthority() else { throw CancellationError() }
                let http = response as? HTTPURLResponse
                // 403: the address ran out or a header was wrong. Fresh addresses settle the first.
                if http?.statusCode == 403 { needsFreshAddresses = true; break }
                guard let http, (200..<300).contains(http.statusCode),
                      let etag = http.value(forHTTPHeaderField: "ETag"), !etag.isEmpty else {
                    throw Problem(title: Self.storageUploadFailureTitle, status: http?.statusCode, detail: nil)
                }
                progress.etags[part.partNumber] = etag
                onProgress(progress)
            }
            if needsFreshAddresses {
                restarts += 1
                guard restarts <= Self.maxRestartsPerAttempt else {
                    throw Problem(title: Self.storageUploadFailureTitle, status: 403, detail: nil)
                }
                continue
            }
            guard let confirmation = MediaParts.confirmation(uploadID: plan.uploadId, digest: digest, etags: progress.etags) else {
                throw Problem(title: Self.storageUploadFailureTitle, status: nil, detail: nil)
            }
            let confirmed: MediaAssetRecord
            do {
                confirmed = try await api.confirmFieldMedia(registration.asset.id, multipart: confirmation)
            } catch let problem as Problem where problem.status == 400 && problem.names("multipart") && restarts < Self.maxRestartsPerAttempt {
                // The upload is no longer open, or storage holds a different part than was named:
                // register again. A refused upload ID means every part goes again.
                restarts += 1
                sendEveryPart = problem.names("multipart.uploadId")
                continue
            } catch let problem as Problem where problem.status == 400 && problem.names("multipart") {
                throw Problem(title: "Media not confirmed", status: 400,
                              detail: "This file didn\u{2019}t finish sending. It\u{2019}s still on this phone. Try sending it again.")
            } catch { throw Self.plain(error) }
            try verify(generation)
            guard currentAuthority() else { throw CancellationError() }
            guard confirmed.id == registration.asset.id, confirmed.organizationId == registration.asset.organizationId,
                  matches(confirmed), confirmed.uploadState == "stored" else {
                throw Problem(title: "Media not confirmed", status: nil,
                              detail: "The server has not confirmed this exact media. The saved copy remains on this phone.")
            }
            return confirmed
        }
    }

    func download(mediaID: String, filename: String) async throws -> URL {
        let generation = api.requestGeneration
        let target = try await api.mediaDownload(mediaID)
        try verify(generation)
        let allowedExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "heic", "pdf", "mp4", "mov"]
        let ext = (filename as NSString).pathExtension.lowercased()
        guard allowedExtensions.contains(ext) else {
            throw Problem(title: "Unsupported preview file", status: nil, detail: filename)
        }
        var request = URLRequest(url: target.url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        let temporary: URL
        let response: URLResponse
        do {
            (temporary, response) = try await storageSession.download(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw Problem(title: "Media download failed", status: nil, detail: error.localizedDescription)
        }
        try verify(generation)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw Problem(title: "Media download failed",
                          status: (response as? HTTPURLResponse)?.statusCode, detail: nil)
        }
        let fileSize = try FileManager.default.attributesOfItem(atPath: temporary.path)[.size] as? NSNumber
        guard let fileSize, fileSize.intValue <= Self.maxPreviewBytes else {
            throw Problem(title: "Preview too large", status: nil, detail: "The downloaded file exceeds 50 MiB.")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ThorbisMediaPreviews", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.complete])
        let destination = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        try FileManager.default.moveItem(at: temporary, to: destination)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete],
                                              ofItemAtPath: destination.path)
        return destination
    }

    private func verify(_ generation: UUID) throws {
        try Task.checkCancellation()
        guard generation == api.requestGeneration else { throw CancellationError() }
    }

    /// Storage is a different host from the API. Its signed address carries the permission, so a
    /// header that would hand it a cookie or a sign-in is refused on every upload path.
    static func checkStorageHeaders(_ headers: [String: String]) throws {
        let refused = ["cookie", "cookie2", "authorization", "proxy-authorization"]
        guard !headers.keys.contains(where: { name in refused.contains { name.caseInsensitiveCompare($0) == .orderedSame } }) else {
            throw Problem(title: "Unsafe upload target", status: nil, detail: "Storage target supplied a cookie or sign-in header.")
        }
    }

    fileprivate static func validatedStorageURL(_ raw: String) throws -> URL {
        guard let components = URLComponents(string: raw), components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil, components.fragment == nil,
              let url = components.url else {
            throw Problem(title: "Unsafe storage URL", status: nil, detail: "Expected an HTTPS URL without user info.")
        }
        return url
    }

    fileprivate static func validatedExpiry(_ raw: String) throws -> Date {
        guard let expiry = JobFiltering.date(raw), expiry > Date() else {
            throw Problem(title: "Expired storage URL", status: nil, detail: "Request a fresh media URL.")
        }
        return expiry
    }
}

@MainActor
extension APIClient {
    func mediaDownload(_ id: String) async throws -> MediaDownloadTarget {
        guard UUID(uuidString: id) != nil else {
            throw Problem(title: "Invalid media ID", status: nil, detail: id)
        }
        struct Response: Decodable { let url: String; let expiresAt: String }
        let reply: Response = try await send("GET", "/v1/media/\(id)/download")
        return MediaDownloadTarget(url: try MediaTransfer.validatedStorageURL(reply.url),
                                   expiresAt: try MediaTransfer.validatedExpiry(reply.expiresAt))
    }
}

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
        let registration = try await api.registerFieldMedia(jobID, request: request)
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
        guard !target.headers.keys.contains(where: {
            $0.caseInsensitiveCompare("cookie") == .orderedSame ||
            $0.caseInsensitiveCompare("cookie2") == .orderedSame
        }) else {
            throw Problem(title: "Unsafe upload target", status: nil, detail: "Storage target supplied a cookie header.")
        }
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
        let confirmed = try await api.confirmFieldMedia(registration.asset.id)
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
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fractional = formatter.date(from: raw)
        formatter.formatOptions = [.withInternetDateTime]
        guard let expiry = fractional ?? formatter.date(from: raw), expiry > Date() else {
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

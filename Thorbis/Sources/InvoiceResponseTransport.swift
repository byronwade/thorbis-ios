import Foundation

/// Disconnected prototype. Source labels do not establish authorization,
/// invoice membership, trustworthy intermediaries or remote revocation.
enum InvoiceResponseSource: Equatable { case network, savedCopy }
struct InvoiceResponse: Equatable { let data: Data; let source: InvoiceResponseSource }
enum InvoiceResponseFailure: Error, Equatable { case invalidRequest, invalidResponse, httpStatus(Int), noSavedCopy }

struct InvoiceResponseTransport {
    /// Callers must provide the app's authenticated session and the saved copy
    /// for this exact actor, organization, origin, path and cursor. This helper
    /// does not perform those checks or bypass an intermediary's cache.
    static func load(request: URLRequest, knownOffline: Bool,
                     network: @Sendable (URLRequest) async throws -> (Data, URLResponse),
                     saved: @Sendable () async throws -> Data?) async throws -> InvoiceResponse {
        guard let url = request.url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "https", parts.host?.isEmpty == false,
              parts.user == nil, parts.password == nil,
              (request.httpMethod ?? "GET").uppercased() == "GET", request.httpBody == nil,
              request.httpBodyStream == nil else { throw InvoiceResponseFailure.invalidRequest }
        let incompleteHeaders = ["Range", "If-Range", "If-None-Match", "If-Modified-Since", "If-Match", "If-Unmodified-Since"]
        guard incompleteHeaders.allSatisfy({ request.value(forHTTPHeaderField: $0) == nil }) else {
            throw InvoiceResponseFailure.invalidRequest
        }
        try Task.checkCancellation()
        if knownOffline, let data = try await saved() {
            try Task.checkCancellation()
            return InvoiceResponse(data: data, source: .savedCopy)
        }
        var liveRequest = request
        liveRequest.cachePolicy = .reloadIgnoringLocalCacheData
        liveRequest.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await network(liveRequest)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            let offline: Set<URLError.Code> = [.notConnectedToInternet, .networkConnectionLost, .timedOut,
                                                .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
                                                .dataNotAllowed, .internationalRoamingOff]
            if let error = error as? URLError, offline.contains(error.code), let data = try await saved() {
                try Task.checkCancellation()
                return InvoiceResponse(data: data, source: .savedCopy)
            }
            throw error
        }
        // Cancellation is an uncertain outcome, including if a denial arrived.
        // The caller must retain its read barrier until definitive termination.
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.url == url else { throw InvoiceResponseFailure.invalidResponse }
        guard http.statusCode == 200 else { throw InvoiceResponseFailure.httpStatus(http.statusCode) }
        guard http.value(forHTTPHeaderField: "Content-Range") == nil else { throw InvoiceResponseFailure.invalidResponse }
        return InvoiceResponse(data: data, source: .network)
    }
}

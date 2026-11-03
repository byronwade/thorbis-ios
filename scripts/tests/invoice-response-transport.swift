import Foundation

final class InvoiceFixtureProtocol: URLProtocol, @unchecked Sendable {
    final class Storage: @unchecked Sendable {
        let lock = NSLock()
        var requests: [URLRequest] = []
    }
    static let storage = Storage()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.storage.lock.withLock { Self.storage.requests.append(request) }
        let path = request.url!.path
        if path == "/lost" { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return }
        let status = path == "/denied" ? 403 : (path == "/partial" ? 206 : 200)
        let responseURL = path == "/redirected" ? URL(string: "https://other.invalid/redirected")! : request.url!
        let headers = path == "/range-response" ? ["Content-Range": "bytes 0-3/20"] : nil
        let response = HTTPURLResponse(url: responseURL, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("live".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
actor Gate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var waiting = false
    func wait() async { await withCheckedContinuation { continuation = $0; waiting = true } }
    func release() { continuation?.resume(); continuation = nil }
}
@main enum InvoiceResponseChecks {
    static func main() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [InvoiceFixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        let fetch: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { try await session.data(for: $0) }
        let saved: @Sendable () async throws -> Data? = { Data("saved".utf8) }
        func request(_ path: String) -> URLRequest { URLRequest(url: URL(string: "https://app.thorbis.com\(path)")!) }
        var failures = 0
        func expect(_ ok: Bool, _ message: String) { if !ok { print("FAIL: \(message)"); failures += 1 } }
        do {
            let result = try await InvoiceResponseTransport.load(request: request("/live"), knownOffline: false, network: fetch, saved: saved)
            expect(result == .init(data: Data("live".utf8), source: .network), "live response must be labelled network")
            let captured = InvoiceFixtureProtocol.storage.lock.withLock { InvoiceFixtureProtocol.storage.requests.last }
            expect(captured?.cachePolicy == .reloadIgnoringLocalCacheData, "live evidence must bypass local URLCache")
            expect(captured?.value(forHTTPHeaderField: "Cache-Control") == "no-cache", "live evidence must request cache revalidation")
        } catch { print("FAIL: live response \(error)"); failures += 1 }
        do {
            let before = InvoiceFixtureProtocol.storage.lock.withLock { InvoiceFixtureProtocol.storage.requests.count }
            let result = try await InvoiceResponseTransport.load(request: request("/live"), knownOffline: true, network: fetch, saved: saved)
            let after = InvoiceFixtureProtocol.storage.lock.withLock { InvoiceFixtureProtocol.storage.requests.count }
            expect(result == .init(data: Data("saved".utf8), source: .savedCopy), "known-offline copy must retain its source")
            expect(before == after, "known-offline copy must not start a network request")
        } catch { print("FAIL: known offline \(error)"); failures += 1 }
        do {
            let result = try await InvoiceResponseTransport.load(request: request("/lost"), knownOffline: false, network: fetch, saved: saved)
            expect(result == .init(data: Data("saved".utf8), source: .savedCopy), "offline network failure must keep saved data visible")
        } catch { print("FAIL: offline fallback \(error)"); failures += 1 }
        do {
            _ = try await InvoiceResponseTransport.load(request: request("/denied"), knownOffline: false, network: fetch, saved: saved)
            print("FAIL: 403 must not return a saved copy"); failures += 1
        } catch InvoiceResponseFailure.httpStatus(403) {} catch { print("FAIL: wrong denial \(error)"); failures += 1 }
        do {
            _ = try await InvoiceResponseTransport.load(request: request("/redirected"), knownOffline: false, network: fetch, saved: saved)
            print("FAIL: unexpected response URL must not be marked network"); failures += 1
        } catch InvoiceResponseFailure.invalidResponse {} catch { print("FAIL: wrong redirect failure \(error)"); failures += 1 }
        do {
            _ = try await InvoiceResponseTransport.load(request: request("/partial"), knownOffline: false, network: fetch, saved: saved)
            print("FAIL: a partial HTTP response must not qualify"); failures += 1
        } catch InvoiceResponseFailure.httpStatus(206) {} catch { print("FAIL: wrong partial failure \(error)"); failures += 1 }
        do {
            _ = try await InvoiceResponseTransport.load(request: request("/range-response"), knownOffline: false, network: fetch, saved: saved)
            print("FAIL: Content-Range must not qualify as a complete response"); failures += 1
        } catch InvoiceResponseFailure.invalidResponse {} catch { print("FAIL: wrong content-range failure \(error)"); failures += 1 }
        for header in ["Range", "If-Range", "If-None-Match", "If-Modified-Since", "If-Match", "If-Unmodified-Since"] {
            var conditional = request("/live")
            conditional.setValue("fixture", forHTTPHeaderField: header)
            do {
                _ = try await InvoiceResponseTransport.load(request: conditional, knownOffline: false, network: fetch, saved: saved)
                print("FAIL: \(header) must not qualify as a full invoice read"); failures += 1
            } catch InvoiceResponseFailure.invalidRequest {} catch { print("FAIL: wrong \(header) failure \(error)"); failures += 1 }
        }
        let gate = Gate()
        let delayed: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
            await gate.wait()
            return (Data("denied".utf8), HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!)
        }
        let canceled = Task { try await InvoiceResponseTransport.load(request: request("/denied"), knownOffline: false, network: delayed, saved: saved) }
        for _ in 0..<100 {
            if await gate.waiting { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        if await gate.waiting {
            canceled.cancel(); await gate.release()
            do { _ = try await canceled.value; print("FAIL: canceled request must not return data"); failures += 1 }
            catch is CancellationError {} catch { print("FAIL: wrong cancellation \(error)"); failures += 1 }
        } else {
            canceled.cancel()
            _ = await canceled.result
            print("FAIL: cancellation fixture never reached network")
            failures += 1
        }
        session.invalidateAndCancel()
        if failures > 0 { exit(1) }
        print("PASS: per-response invoice transport checks")
    }
}

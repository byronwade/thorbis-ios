import Foundation

/// Isolated macOS reproduction of the transport's ordering; no real network.
final class DeniedProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

actor PostResponseGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var waiting = false
    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            waiting = true
        }
    }
    func release() { continuation?.resume(); continuation = nil }
}

@main enum CancelObservation {
    static func main() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DeniedProtocol.self]
        let session = URLSession(configuration: configuration)
        let gate = PostResponseGate()
        let task = Task { () throws -> Int in
            let (_, response) = try await session.data(for: URLRequest(url: URL(string: "https://preview.invalid/invoices")!))
            await gate.wait()
            // Mirrors APIClient.sendData: cancellation is checked before status.
            try Task.checkCancellation()
            return (response as? HTTPURLResponse)?.statusCode ?? 0
        }
        while !(await gate.waiting) { await Task.yield() }
        task.cancel()
        await gate.release()
        do {
            let status = try await task.value
            print("FAIL: expected cancellation, received status \(status)")
            exit(1)
        } catch is CancellationError {
            print("PASS: cancellation after a received 403 prevented status inspection")
        } catch {
            print("FAIL: unexpected error \(error)")
            exit(1)
        }
        session.invalidateAndCancel()
    }
}

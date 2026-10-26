import Foundation

final class URLProtocolFixture: URLProtocol, @unchecked Sendable {
    final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var released = false
        private var actions: [@Sendable () -> Void] = []

        fileprivate func whenReleased(_ action: @escaping @Sendable () -> Void) {
            let runNow = lock.withLock { () -> Bool in
                if released { return true }
                actions.append(action)
                return false
            }
            if runNow { action() }
        }

        func release() {
            let pending = lock.withLock { () -> [@Sendable () -> Void] in
                guard !released else { return [] }
                released = true
                let pending = actions
                actions = []
                return pending
            }
            pending.forEach { $0() }
        }
    }

    struct Reply: Sendable {
        let status: Int
        let body: String
        let gate: Gate?
        let contentType: String
        init(_ status: Int = 200, _ body: String = "{}", gate: Gate? = nil, contentType: String = "application/json") {
            self.status = status
            self.body = body
            self.gate = gate
            self.contentType = contentType
        }
    }

    struct RecordedRequest: Sendable {
        let url: URL?
        let method: String?
        let headers: [String: String]
        let body: Data?

        func header(_ name: String) -> String? {
            headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
        }
    }

    private final class Storage: @unchecked Sendable {
        let lock = NSLock()
        var replies: [Reply] = []
        var requests: [RecordedRequest] = []
    }

    private static let storage = Storage()
    private let stateLock = NSLock()
    private var stopped = false

    static func session(_ replies: [Reply]) -> URLSession {
        storage.lock.withLock {
            storage.replies = replies
            storage.requests = []
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolFixture.self]
        return URLSession(configuration: config)
    }

    static var recorded: [RecordedRequest] {
        storage.lock.withLock { storage.requests }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body: Data?
        if let data = request.httpBody { body = data }
        else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var collected = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                collected.append(contentsOf: buffer[..<count])
            }
            body = collected
        } else { body = nil }
        let recorded = RecordedRequest(url: request.url,
                                       method: request.httpMethod,
                                       headers: request.allHTTPHeaderFields ?? [:],
                                       body: body)
        let reply = Self.storage.lock.withLock { () -> Reply in
            Self.storage.requests.append(recorded)
            return Self.storage.replies.isEmpty ? Reply(599) : Self.storage.replies.removeFirst()
        }
        if let gate = reply.gate {
            gate.whenReleased { [weak self] in self?.deliver(reply) }
        } else {
            deliver(reply)
        }
    }

    private func deliver(_ reply: Reply) {
        guard stateLock.withLock({ !stopped }) else { return }
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: reply.status,
                                             httpVersion: "HTTP/1.1", headerFields: ["Content-Type": reply.contentType])
        else { client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        stateLock.withLock { stopped = true }
    }
}

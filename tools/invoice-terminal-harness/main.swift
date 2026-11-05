import Foundation

let base = FileManager.default.temporaryDirectory.appendingPathComponent("invoice-terminal-\(UUID().uuidString)")
defer { try? FileManager.default.removeItem(at: base) }
let scope = InvoiceReadFence.Scope(actor: "00000000-0000-4000-8000-000000000001", organization: "00000000-0000-4000-8000-000000000002", origin: "https://app.thorbis.com", invoice: "00000000-0000-4000-8000-000000000003", resource: "invoice")
let expected = URL(string: "https://app.thorbis.com/v1/invoices/00000000-0000-4000-8000-000000000003")!
let payload = Data("invoice".utf8)
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--check-held" {
    let observer = InvoiceReadFence(directory: URL(fileURLWithPath: CommandLine.arguments[2]))
    exit(observer.cacheAllowed(scope, payload: payload) ? 1 : 0)
}
func require(_ condition: @autoclosure () -> Bool, _ message: String) { if !condition() { fatalError(message) } }
func grant(_ fence: InvoiceReadFence) throws { _ = try fence.begin(scope).finish(.liveSuccess(payload)) }

// A status observed by the delegate remains authoritative if cancellation happens before completion.
let first = InvoiceReadFence(directory: base.appendingPathComponent("denial"))
try grant(first)
let denied = InvoiceTerminalOwner(attempt: try first.begin(scope), expected: expected)
denied.received(status: 403, responseURL: expected)
denied.cancelRequested()
try denied.completed()
require(!first.cacheAllowed(scope, payload: payload), "denial must hide prior copy")
let reopened = InvoiceReadFence(directory: base.appendingPathComponent("denial"))
require(!reopened.cacheAllowed(scope, payload: payload), "denial must survive reopen")
let observer = Process()
observer.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
observer.arguments = ["--check-held", base.appendingPathComponent("denial").path]
try observer.run()
observer.waitUntilExit()
require(observer.terminationStatus == 0, "new process must not restore denied copy")

// Cancellation before the response does not discard a scoped denial that arrives
// before the terminal callback.
let third = InvoiceReadFence(directory: base.appendingPathComponent("late-denial"))
try grant(third)
let lateDenial = InvoiceTerminalOwner(attempt: try third.begin(scope), expected: expected)
lateDenial.cancelRequested()
lateDenial.received(status: 403, responseURL: expected)
try lateDenial.completed()
require(!third.cacheAllowed(scope, payload: payload), "late denial must win")

// An unscoped 403 is not evidence about this resource. Once the delegate is terminal,
// the pending hold still blocks the old copy while a subsequent retry may start.
let second = InvoiceReadFence(directory: base.appendingPathComponent("cancel"))
try grant(second)
let cancelled = InvoiceTerminalOwner(attempt: try second.begin(scope), expected: expected)
cancelled.received(status: 403, responseURL: URL(string: "https://other.example/v1/invoices/00000000-0000-4000-8000-000000000003")!)
cancelled.cancelRequested()
try cancelled.completed()
require(!second.cacheAllowed(scope, payload: payload), "uncertain result must not restore copy")
let retry = try second.begin(scope)
_ = try retry.finish(.denied)
require(!InvoiceReadFence(directory: base.appendingPathComponent("cancel")).cacheAllowed(scope, payload: payload), "hold survives reopen")
// A failed denial transition leaves a durable hold that a new process rejects.
var failDenialRename = false
let faultDirectory = base.appendingPathComponent("failed-denial")
let fault = InvoiceReadFence(directory: faultDirectory, injectFailure: { point in
    if case .recordRename = point { return failDenialRename }
    return false
})
try grant(fault)
let failedDenial = InvoiceTerminalOwner(attempt: try fault.begin(scope), expected: expected)
failedDenial.received(status: 403, responseURL: expected)
failDenialRename = true
var failedAsExpected = false
do { try failedDenial.completed() } catch { failedAsExpected = true }
require(failedAsExpected, "injected denial write must fail")
let faultObserver = Process()
faultObserver.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
faultObserver.arguments = ["--check-held", faultDirectory.path]
try faultObserver.run()
faultObserver.waitUntilExit()
require(faultObserver.terminationStatus == 0, "write failure must not restore copy in another process")
print("terminal owner harness passed")

final class DenialProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("denied".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
final class TerminalDelegate: NSObject, URLSessionDataDelegate {
    let owner: InvoiceTerminalOwner
    let done = DispatchSemaphore(value: 0)
    var failure: Error?
    init(_ owner: InvoiceTerminalOwner) { self.owner = owner }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse, let url = response.url else { completionHandler(.cancel); return }
        owner.received(status: response.statusCode, responseURL: url)
        completionHandler(.allow)
        owner.cancelRequested()
        dataTask.cancel()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        do { try owner.completed() } catch { failure = error }
        done.signal()
    }
}
let fourth = InvoiceReadFence(directory: base.appendingPathComponent("urlsession"))
try grant(fourth)
let terminal = InvoiceTerminalOwner(attempt: try fourth.begin(scope), expected: expected)
let delegate = TerminalDelegate(terminal)
let configuration = URLSessionConfiguration.ephemeral
configuration.protocolClasses = [DenialProtocol.self]
let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
session.dataTask(with: expected).resume()
var receivedTerminal = false
let deadline = Date().addingTimeInterval(10)
while Date() < deadline && !receivedTerminal {
    receivedTerminal = delegate.done.wait(timeout: .now()) == .success
    if !receivedTerminal { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
}
require(receivedTerminal, "URLSession terminal callback timed out")
require(delegate.failure == nil, "terminal persistence must succeed")
require(!fourth.cacheAllowed(scope, payload: payload), "URLSession observed denial survives cancellation")
session.invalidateAndCancel()
print("URLSession denial-then-cancel harness passed")

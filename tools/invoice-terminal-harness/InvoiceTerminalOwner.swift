import Foundation

/// Prototype event reducer: only call `completed` from the transport's terminal
/// delegate callback, after all response callbacks are quiescent. No app route
/// uses this type. It does not grant access or decide connectivity fallback.
final class InvoiceTerminalOwner {
    private let attempt: InvoiceReadFence.Attempt
    private let expected: URL
    private let lock = NSLock()
    private var observedDenial = false
    private var finished = false

    init(attempt: InvoiceReadFence.Attempt, expected: URL) {
        self.attempt = attempt
        self.expected = expected
    }

    func received(status: Int, responseURL: URL) {
        lock.lock(); defer { lock.unlock() }
        guard !finished, responseURL == expected, [401, 403, 404].contains(status) else { return }
        observedDenial = true
    }

    // Cancellation is a request, not proof that callbacks are quiescent.
    func cancelRequested() {}

    func completed() throws {
        lock.lock(); defer { lock.unlock() }
        guard !finished else { throw InvoiceReadFence.Failure.alreadyFinished }
        finished = true
        _ = try attempt.finish(observedDenial ? .denied : .terminalUncertain)
    }
}

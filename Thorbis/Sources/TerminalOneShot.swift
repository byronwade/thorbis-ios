import Foundation

/// A callback may arrive from any SDK queue. Exactly one callback gets the
/// value; consuming it happens under a lock and use occurs after unlocking.
final class TerminalOneShot<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value?
    init(_ value: Value? = nil) { self.value = value }
    func install(_ value: Value) {
        lock.lock()
        defer { lock.unlock() }
        precondition(self.value == nil)
        self.value = value
    }
    func take() -> Value? {
        lock.lock()
        defer { lock.unlock() }
        let result = value
        value = nil
        return result
    }
}

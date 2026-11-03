import Foundation

/// Tracks a failed local draft operation until a later operation succeeds.
/// It does not prove cross-process ownership or durability after a crash.
struct JobEstimateDraftSaveGuard {
    static let saveFailedMessage = "This draft could not be saved on this phone. Keep this screen open and try again."
    static let removeFailedMessage = "The undone draft could not be removed from this phone. Try again before closing."

    private(set) var requiresRetry = false

    static func resolvedError(_ message: String?) -> String? {
        message == saveFailedMessage || message == removeFailedMessage ? nil : message
    }

    mutating func markFailed() { requiresRetry = true }

    mutating func perform(_ operation: () throws -> Void) throws {
        do { try operation(); requiresRetry = false }
        catch { requiresRetry = true; throw error }
    }

    @discardableResult mutating func attempt(_ operation: () throws -> Void) -> Bool {
        do { try perform(operation); return true }
        catch { return false }
    }
}

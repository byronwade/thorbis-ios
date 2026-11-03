import Foundation

/// Tracks a failed local draft operation until a later operation succeeds.
/// It does not prove cross-process ownership or durability after a crash.
struct JobEstimateDraftSaveGuard {
    private(set) var requiresRetry = false

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

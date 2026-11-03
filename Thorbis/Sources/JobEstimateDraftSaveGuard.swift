import Foundation

/// Tracks a failed local draft operation until a later operation succeeds.
/// It does not prove cross-process ownership or durability after a crash.
struct JobEstimateDraftSaveGuard {
    private(set) var requiresRetry = false

    @discardableResult mutating func attempt(_ operation: () throws -> Void) -> Bool {
        do { try operation(); requiresRetry = false; return true }
        catch { requiresRetry = true; return false }
    }
}

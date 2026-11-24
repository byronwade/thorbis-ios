import Foundation

/// Keep a bounded number of actor-isolated asynchronous operations in flight.
/// Callers own result ordering, authority checks and error handling.
@MainActor
func runBoundedMainActorOperations(count: Int, limit: Int,
    operation: @escaping @MainActor @Sendable (Int) async -> Void) async {
    guard count > 0, limit > 0, !Task.isCancelled else { return }
    await withTaskGroup(of: Void.self) { group in
        var next = 0
        while next < min(count, limit) {
            let index = next
            group.addTask { await operation(index) }
            next += 1
        }
        while await group.next() != nil {
            guard !Task.isCancelled else { group.cancelAll(); break }
            if next < count {
                let index = next
                group.addTask { await operation(index) }
                next += 1
            }
        }
    }
}

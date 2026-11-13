import Foundation

@MainActor final class Counter {
    var running = 0
    var peak = 0
    var complete: [Int] = []
    func fetch(_ index: Int) async {
        running += 1
        peak = max(peak, running)
        try? await Task.sleep(for: .milliseconds(index == 0 ? 70 : 15))
        running -= 1
        complete.append(index)
    }
}

@main struct Probe {
    @MainActor static func main() async {
        let counter = Counter()
        await runBoundedMainActorOperations(count: 20, limit: 4) { index in
            await counter.fetch(index)
        }
        precondition(counter.peak == 4, "Expected bounded parallel work")
        precondition(Set(counter.complete) == Set(0..<20), "All work must finish exactly once")
        precondition(counter.complete.count == 20)
        let cancelled = Counter()
        let cancelledTask = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            await runBoundedMainActorOperations(count: 20, limit: 4) { index in
                await cancelled.fetch(index)
            }
        }
        await cancelledTask.value
        precondition(cancelled.complete.isEmpty, "A cancelled load must not start detail requests")
        let interrupted = Counter()
        let inFlight = Task { @MainActor in
            await runBoundedMainActorOperations(count: 20, limit: 4) { index in
                await interrupted.fetch(index)
            }
        }
        while interrupted.running < 4 { await Task.yield() }
        inFlight.cancel()
        await inFlight.value
        precondition(interrupted.complete.count == 4, "Cancellation must prevent scheduling further work")
        print("PASS bounded main-actor operation concurrency")
    }
}

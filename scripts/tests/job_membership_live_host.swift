import Foundation

enum SavedCopies { @TaskLocal static var liveOnly = false }
struct JobEstimateLink {}
enum TestError: Error { case offline }

final class APIClient {
    var pageScopes: [Bool] = []
    var fail = false
    func fieldJobEstimateLinks(_ id: String) async throws -> [JobEstimateLink] {
        for _ in 0..<2 {
            pageScopes.append(SavedCopies.liveOnly)
            if fail { throw TestError.offline }
        }
        return [JobEstimateLink()]
    }
    func requireLive(_ path: String) throws {}
    // LIVE_MEMBERSHIP_WRAPPER
}

@main struct Probe {
    static func main() async throws {
        let api = APIClient()
        _ = try await api.liveFieldJobEstimateLinks("job")
        guard api.pageScopes == [true, true] else {
            fputs("FAIL: membership page reads not scoped live: \(api.pageScopes)\n", stderr)
            exit(1)
        }
        api.fail = true
        do { _ = try await api.liveFieldJobEstimateLinks("job"); fatalError("expected offline failure") }
        catch TestError.offline {}
        guard !SavedCopies.liveOnly else { fatalError("task-local leaked after error") }
        print("PASS: every membership page uses live-only scope and unwinds on failure")
    }
}

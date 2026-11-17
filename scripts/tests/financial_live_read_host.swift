import Foundation

enum SavedCopies { @TaskLocal static var liveOnly = false }
struct EstimateRecord {}
struct InvoiceRecord {}
struct JobRecord {}
enum TestError: Error { case unavailable }

final class APIClient {
    var observed: [Bool] = []
    var policies: [(URLRequest.CachePolicy, String?)] = []
    var fail = false
    func capturePolicy() {
        let method = "GET", requireFresh = false
        let url = URL(string: "https://app.thorbis.com/v1/invoices/example")!
        // REQUEST_POLICY
        policies.append((req.cachePolicy, req.value(forHTTPHeaderField: "Cache-Control")))
    }
    func fieldEstimate(_ id: String) async throws -> EstimateRecord {
        observed.append(SavedCopies.liveOnly)
        capturePolicy()
        if fail { throw TestError.unavailable }
        return EstimateRecord()
    }
    func fieldInvoice(_ id: String) async throws -> InvoiceRecord {
        observed.append(SavedCopies.liveOnly)
        capturePolicy()
        if fail { throw TestError.unavailable }
        return InvoiceRecord()
    }
    func fieldJob(_ id: String) async throws -> JobRecord {
        observed.append(SavedCopies.liveOnly)
        capturePolicy()
        return JobRecord()
    }
    func requireLive(_ path: String) throws {}
    // LIVE_READ_WRAPPERS
}

@main struct Probe {
    static func main() async throws {
        let client = APIClient()
        _ = try await client.liveFieldJob("job")
        _ = try await client.liveFieldInvoice("invoice")
        _ = try await client.liveFieldEstimate("estimate")
        guard client.observed == [true, true, true] else {
            fputs("FAIL: live reads did not all enter live-only scope: \(client.observed)\n", stderr)
            exit(1)
        }
        guard client.policies.allSatisfy({ $0.0 == .reloadIgnoringLocalCacheData && $0.1 == "no-cache" }) else {
            fatalError("live reads did not set the fresh request policy")
        }
        client.fail = true
        do { _ = try await client.liveFieldInvoice("invoice"); fatalError("expected error") }
        catch TestError.unavailable {}
        guard !SavedCopies.liveOnly else { fatalError("scope leaked after error") }
        print("PASS: job, invoice and estimate wrappers scope reads and unwind on error")
    }
}

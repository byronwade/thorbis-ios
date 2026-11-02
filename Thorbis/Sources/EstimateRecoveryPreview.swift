#if DEBUG
import Foundation

/// Local-only, deterministic responses for exercising the actual new-estimate editor.
/// Enabled solely by an explicit Paper preview launch argument.
final class EstimateRecoveryPreview: @unchecked Sendable {
    static let shared = EstimateRecoveryPreview()
    static let estimateID = "00000000-0000-4000-8000-000000008901"
    private let lock = NSLock()
    private var creates = 0
    private var links = 0
    private var estimateReads = 0
    private var jobReads = 0
    private var savedEstimate: [String: Any]?
    private var heldReply: (@Sendable () -> Void)?

    static var enabled: Bool {
        PaperPreview.enabled && ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-create-recovery")
    }

    var counts: String { lock.withLock { "creates=\(creates),links=\(links),estimateReads=\(estimateReads),jobReads=\(jobReads)" } }

    func hold(_ action: @escaping @Sendable () -> Void) { lock.withLock { heldReply = action } }
    func release() {
        let action = lock.withLock { let action = heldReply; heldReply = nil; return action }
        action?()
    }

    struct Reply: @unchecked Sendable {
        let status: Int
        let payload: [String: Any]
        var hold = false
    }

    func reply(for request: URLRequest) -> Reply? {
        guard Self.enabled, let path = request.url?.path else { return nil }
        if request.httpMethod == "GET", path == "/v1/estimates/\(Self.estimateID)" {
            return lock.withLock {
                if request.cachePolicy == .reloadIgnoringLocalCacheData { estimateReads += 1 }
                guard var estimate = savedEstimate else { return Reply(status: 404, payload: ["title": "Sample missing", "status": 404]) }
                if ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-recovery-changed") { estimate["title"] = "Changed sample estimate" }
                if ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-recovery-normalized-dates") {
                    estimate["createdAt"] = "2026-10-29T00:00:00.000Z"
                    estimate["updatedAt"] = "2026-10-29T00:00:00.000Z"
                }
                return Reply(status: 200, payload: estimate)
            }
        }
        if request.httpMethod == "GET", path == "/v1/jobs/\(PaperPreview.jobID)" {
            if request.cachePolicy == .reloadIgnoringLocalCacheData { lock.withLock { jobReads += 1 } }
            var job: [String: Any] = ["id": PaperPreview.jobID, "organizationId": PaperPreview.organizationID,
                "customerId": PaperPreview.customerID, "title": "Sample job", "status": "in_progress",
                "createdAt": "2026-10-29T00:00:00Z", "updatedAt": "2026-10-29T00:00:00Z"]
            if ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-recovery-matching-location") {
                job["locationId"] = "00000000-0000-4000-8000-000000009999"
            }
            return Reply(status: 200, payload: job)
        }
        guard request.httpMethod == "POST" else { return nil }
        if path == "/v1/estimates" {
            let attempt = lock.withLock { creates += 1; return creates }
            guard attempt == 1 else {
                return Reply(status: 409, payload: ["title": "Duplicate sample creation", "status": 409])
            }
            let body: Data
            if let data = request.httpBody { body = data }
            else if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var data = Data()
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    data.append(buffer, count: count)
                }
                body = data
            } else { body = Data() }
            guard let input = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let customer = input["customerId"] as? String,
                  let title = input["title"] as? String,
                  let inputs = input["lines"] as? [[String: Any]] else {
                return Reply(status: 400, payload: ["title": "Invalid sample input", "status": 400])
            }
            let lines = inputs.enumerated().map { index, value -> [String: Any] in
                var line = value
                line["id"] = String(format: "00000000-0000-4000-8000-%012d", index + 8902)
                return line
            }
            var estimate: [String: Any] = ["id": Self.estimateID, "organizationId": PaperPreview.organizationID,
                "customerId": customer, "createdByUserId": PaperPreview.actorID, "status": "draft", "title": title,
                "lines": lines, "createdAt": "2026-10-29T00:00:00Z", "updatedAt": "2026-10-29T00:00:00Z"]
            if let location = input["locationId"] { estimate["locationId"] = location }
            if ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-recovery-other-location") {
                estimate["locationId"] = "00000000-0000-4000-8000-000000009999"
            }
            lock.withLock { savedEstimate = estimate }
            return Reply(status: 201, payload: estimate, hold: ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-create-hold"))
        }
        let expected = "/v1/jobs/\(PaperPreview.jobID)/estimates/\(Self.estimateID)/link"
        guard path == expected else { return nil }
        let attempt = lock.withLock { links += 1; return links }
        if attempt == 1 { return Reply(status: 503, payload: ["title": "Sample connection unavailable", "status": 503]) }
        return Reply(status: 201, payload: ["id": "00000000-0000-4000-8000-000000008903", "jobId": PaperPreview.jobID,
                                                  "estimateId": Self.estimateID, "linkedAt": "2026-10-29T00:00:00Z"])
    }
}
#endif

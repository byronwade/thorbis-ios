#if DEBUG
import Foundation

/// Local-only, deterministic responses for exercising the actual new-estimate editor.
/// Enabled solely by an explicit Paper preview launch argument.
final class EstimateRecoveryPreview: @unchecked Sendable {
    static let shared = EstimateRecoveryPreview()
    static let estimateID = "00000000-0000-4000-8000-000000008901"
    private let lock = NSLock()
    private var events: [String] = []
    private var creates = 0
    private var links = 0
    private var estimateReads = 0
    private var jobReads = 0
    private var denyJobAfterRefresh = false
    private var holdNextReload = false
    private var invoiceRevisionIncrement = 1
    private var denyInvoiceRead = false
    private var invoiceVerificationArmed = false
    private var invoiceVerificationReads = 0
    private var estimateRevisionIncrement = 1
    private var denyEstimateRead = false
    private var savedEstimate: [String: Any]?
    private var heldReply: (@Sendable () -> Void)?
    private let savedEstimateKey: String?

    private init() {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--commercial-draft-test-id"),
           arguments.indices.contains(index + 1), let id = UUID(uuidString: arguments[index + 1]) {
            let key = "estimate-recovery-preview-\(id.uuidString)"
            savedEstimateKey = key
            savedEstimate = UserDefaults.standard.dictionary(forKey: key)
        } else { savedEstimateKey = nil }
    }

    static var enabled: Bool {
        PaperPreview.enabled && ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-create-recovery")
    }
    static var heldReloadEnabled: Bool {
        PaperPreview.enabled && ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-recovery-held-reload")
    }
    static var newerRevisionEnabled: Bool {
        PaperPreview.enabled && ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-recovery-newer-revision")
    }
    static var invoiceHeldReloadEnabled: Bool {
        PaperPreview.enabled && ProcessInfo.processInfo.arguments.contains("--paper-preview-invoice-recovery-held-reload")
    }
    static var invoiceNewerRevisionEnabled: Bool {
        PaperPreview.enabled && ProcessInfo.processInfo.arguments.contains("--paper-preview-invoice-recovery-newer-revision")
    }
    static var invoiceFinalReadHeldEnabled: Bool {
        PaperPreview.enabled && ProcessInfo.processInfo.arguments.contains("--paper-preview-invoice-final-read-held")
    }
    static var invoiceVerificationHeldEnabled: Bool {
        PaperPreview.enabled && ProcessInfo.processInfo.arguments.contains("--paper-preview-invoice-verification-held")
    }
    static var invoiceDeliveryKey: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--commercial-draft-test-id"),
              arguments.indices.contains(index + 1), let id = UUID(uuidString: arguments[index + 1]) else { return nil }
        return "invoice-recovery-delivered-\(id.uuidString)"
    }
    static var invoiceWorkspaceKey: String? { invoiceDeliveryKey.map { $0 + "-workspace" } }
    var reloadHoldState: String { lock.withLock { heldReply == nil ? "idle" : "waiting" } }
    func armHeldReload() { lock.withLock { holdNextReload = true } }
    func advanceInvoiceRevision() { lock.withLock { invoiceRevisionIncrement += 1 } }
    func denyNextInvoiceRead() { lock.withLock { denyInvoiceRead = true } }
    func armFirstInvoiceVerification() {
        lock.withLock {
            guard !invoiceVerificationArmed else { return }
            invoiceVerificationArmed = true; holdNextReload = true
        }
    }
    var invoiceVerificationReadCount: Int { lock.withLock { invoiceVerificationReads } }
    func advanceEstimateRevision() { lock.withLock { estimateRevisionIncrement += 1 } }
    func denyNextEstimateRead() { lock.withLock { denyEstimateRead = true } }

    func record(_ event: String) { lock.withLock { events.append(event) } }
    var eventTrace: String { lock.withLock { events.joined(separator: ",") } }

    var counts: String { lock.withLock { "creates=\(creates),links=\(links),estimateReads=\(estimateReads),jobReads=\(jobReads)" } }
    var dismissalEvidence: String {
        guard let savedEstimateKey else { return "unavailable" }
        let released = UserDefaults.standard.bool(forKey: savedEstimateKey + "-released")
        let linked = UserDefaults.standard.bool(forKey: savedEstimateKey + "-linked")
        return "released=\(released),linked=\(linked)"
    }

    func toggleJobAccess() {
        lock.withLock { denyJobAfterRefresh.toggle() }
    }

    func hold(_ action: @escaping @Sendable () -> Void) { lock.withLock { heldReply = action } }
    func release() {
        let action = lock.withLock { let action = heldReply; heldReply = nil; if action != nil { events.append("held-released") }; return action }
        if action != nil, let savedEstimateKey, ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-dismiss-held") {
            UserDefaults.standard.set(true, forKey: savedEstimateKey + "-released")
        }
        action?()
    }

    struct Reply: @unchecked Sendable {
        let status: Int
        let payload: [String: Any]
        var hold = false
    }

    func reply(for request: URLRequest) -> Reply? {
        if (Self.invoiceHeldReloadEnabled || Self.invoiceNewerRevisionEnabled || Self.invoiceVerificationHeldEnabled), request.httpMethod == "GET",
           request.url?.path == "/v1/invoices/\(PaperPreview.invoice.id)" {
            let denied = lock.withLock { invoiceVerificationReads += 1; let value = denyInvoiceRead; denyInvoiceRead = false; return value }
            if denied || (Self.invoiceVerificationHeldEnabled && PaperPreviewProtocol.sampleInvoiceAccessDenied) {
                return Reply(status: 403, payload: ["status": 403, "title": "Sample access denied"])
            }
            let (shouldHold, revisionIncrement) = lock.withLock {
                let value = holdNextReload; holdNextReload = false; return (value, invoiceRevisionIncrement)
            }
            guard let data = try? JSONEncoder().encode(PaperPreview.invoice),
                  var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
            object["linesRevision"] = PaperPreview.invoice.linesRevision + (Self.invoiceVerificationHeldEnabled ? 0 : revisionIncrement)
            return Reply(status: 200, payload: object, hold: (Self.invoiceHeldReloadEnabled || Self.invoiceFinalReadHeldEnabled || Self.invoiceVerificationHeldEnabled) && shouldHold)
        }
        if (Self.heldReloadEnabled || Self.newerRevisionEnabled), request.httpMethod == "GET",
           request.url?.path == "/v1/estimates/\(PaperPreview.estimate.id)" {
            let (shouldHold, revisionIncrement, denied) = lock.withLock {
                let value = holdNextReload
                holdNextReload = false
                let denied = denyEstimateRead; denyEstimateRead = false
                return (value, estimateRevisionIncrement, denied)
            }
            if denied { return Reply(status: 403, payload: ["status": 403, "title": "Sample access denied"]) }
            guard let data = try? JSONEncoder().encode(PaperPreview.estimate),
                  var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
            object["currentRevisionNumber"] = (PaperPreview.estimate.currentRevisionNumber ?? 0) + revisionIncrement
            return Reply(status: 200, payload: object, hold: Self.heldReloadEnabled && shouldHold)
        }
        guard Self.enabled, let path = request.url?.path else { return nil }
        if request.httpMethod == "GET", path == "/v1/estimates/\(Self.estimateID)" {
            return lock.withLock {
                if request.cachePolicy == .reloadIgnoringLocalCacheData { estimateReads += 1; events.append("estimate") }
                guard var estimate = savedEstimate else { return Reply(status: 404, payload: ["title": "Sample missing", "status": 404]) }
                if ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-recovery-deny-saved-read") {
                    events.append("estimate-denied")
                    return Reply(status: 403, payload: ["title": "Sample estimate access denied", "status": 403])
                }
                if ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-recovery-changed") ||
                    (ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-recovery-change-on-command") && estimateRevisionIncrement > 1) ||
                    (ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-recovery-changed-after-link") && links > 0) {
                    estimate["title"] = ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-recovery-change-again") && estimateRevisionIncrement > 1
                        ? "Changed again sample estimate" : "Changed sample estimate"
                }
                if ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-recovery-normalized-dates") {
                    estimate["createdAt"] = "2026-10-29T00:00:00.000Z"
                    estimate["updatedAt"] = "2026-10-29T00:00:00.000Z"
                }
                let held = request.url?.query?.contains("preview_hold_initial=estimate") == true
                if held { events.append("hold-initial-estimate") }
                return Reply(status: 200, payload: estimate, hold: held)
            }
        }
        if request.httpMethod == "GET", path == "/v1/jobs/\(PaperPreview.jobID)" {
            if request.cachePolicy == .reloadIgnoringLocalCacheData { lock.withLock { jobReads += 1; events.append("job") } }
            if ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-recovery-deny-job") ||
                lock.withLock({ denyJobAfterRefresh }) {
                return Reply(status: 403, payload: ["title": "Sample job access denied", "status": 403])
            }
            var job: [String: Any] = ["id": PaperPreview.jobID, "organizationId": PaperPreview.organizationID,
                "customerId": PaperPreview.customerID, "title": "Sample job", "status": "in_progress",
                "createdAt": "2026-10-29T00:00:00Z", "updatedAt": "2026-10-29T00:00:00Z"]
            if ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-recovery-matching-location") {
                job["locationId"] = "00000000-0000-4000-8000-000000009999"
            }
            let held = request.url?.query?.contains("preview_hold_initial=job") == true
            if held { record("hold-initial-job") }
            return Reply(status: 200, payload: job, hold: held)
        }
        guard request.httpMethod == "POST" else { return nil }
        if path == "/v1/estimates" {
            let attempt = lock.withLock { creates += 1; events.append("create"); return creates }
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
                if ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-drop-groups") { line.removeValue(forKey: "group") }
                if ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-drop-visibility") { line.removeValue(forKey: "showToCustomer") }
                line["id"] = String(format: "00000000-0000-4000-8000-%012d", index + 8902)
                return line
            }
            var estimate: [String: Any] = ["id": Self.estimateID, "organizationId": PaperPreview.organizationID,
                "customerId": customer, "createdByUserId": PaperPreview.actorID, "status": "draft", "title": title,
                "lines": lines, "createdAt": "2026-10-29T00:00:00Z", "updatedAt": "2026-10-29T00:00:00Z"]
            if ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-recovery-changed-terms") { estimate["title"] = "Unexpected work" }
            if let location = input["locationId"] { estimate["locationId"] = location }
            if ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-recovery-other-location") {
                estimate["locationId"] = "00000000-0000-4000-8000-000000009999"
            }
            lock.withLock { savedEstimate = estimate }
            // UserDefaults posts SwiftUI notifications synchronously; never post while holding
            // the counter lock, because the UI reads counts under that same lock.
            if let savedEstimateKey { UserDefaults.standard.set(estimate, forKey: savedEstimateKey) }
            return Reply(status: 201, payload: estimate, hold: ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-create-hold"))
        }
        let expected = "/v1/jobs/\(PaperPreview.jobID)/estimates/\(Self.estimateID)/link"
        guard path == expected else { return nil }
        let attempt = lock.withLock { links += 1; events.append("link"); return links }
        if let savedEstimateKey, ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-dismiss-held") {
            UserDefaults.standard.set(true, forKey: savedEstimateKey + "-linked")
        }
        let arguments = ProcessInfo.processInfo.arguments
        if attempt == 1 && !arguments.contains("--paper-preview-estimate-recovery-link-success") && !arguments.contains("--paper-preview-estimate-link-hold") {
            return Reply(status: 503, payload: ["title": "Sample connection unavailable", "status": 503])
        }
        return Reply(status: 201, payload: ["id": "00000000-0000-4000-8000-000000008903", "jobId": PaperPreview.jobID,
                                                  "estimateId": Self.estimateID, "linkedAt": "2026-10-29T00:00:00Z"],
                     hold: arguments.contains("--paper-preview-estimate-link-hold"))
    }
}
#endif

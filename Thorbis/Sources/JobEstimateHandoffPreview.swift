#if DEBUG
import CryptoKit
import Foundation
import SwiftUI
import ImageIO
import UIKit

/// Isolated local protocol fixture. No URL in this scenario is allowed to reach a server.
final class JobEstimateHandoffPreview: @unchecked Sendable {
    static let shared = JobEstimateHandoffPreview()
    static let a = "00000000-0000-4000-8000-000000008101"
    static let b = "00000000-0000-4000-8000-000000008102"
    static let c = "00000000-0000-4000-8000-000000008103"
    static let d = "00000000-0000-4000-8000-000000008104"
    struct Response { let status: Int; let payload: Any; var error: URLError? = nil }
    private let lock = NSRecursiveLock()
    private var approved: [String: [String: Any]] = [:]
    private var acceptances: [String: [String: Any]] = [:]
    private var assets: [String: [String: Any]] = [:]
    private var clients: [String: String] = [:]
    private var bytes: [String: Data] = [:]
    private var attempts: [[String: Any]] = []
    private var requests: [[String: String]] = []
    private var lost = false
    private var workspaceChanged = false
    private var sessionEnded = false
    private var choosingWorkspace = false
    private var unlocks = 0
    private var interruptMembership = false
    private var interruptUpload = false
    private var unlockAllowed = true
    private var changedRevision = false
    private var flags: [String] { ProcessInfo.processInfo.arguments }
    private var org: String { workspaceChanged ? "00000000-0000-4000-8000-000000000003" : PaperPreview.organizationID }
    private var now: String { ISO8601DateFormatter().string(from: Date()) }
    private var ids: [String] { flags.contains("--paper-preview-handoff-third-sent") ? [Self.a, Self.b, Self.c] : flags.contains("--paper-preview-handoff-all-statuses") ? [Self.a, Self.b, Self.c, Self.d] : [Self.a,Self.b] }
    func reset() { lock.withLock { approved = [:]; acceptances = [:]; assets = [:]; clients = [:]; bytes = [:]; attempts = []; requests = []; lost = false; workspaceChanged = false; sessionEnded = false; choosingWorkspace = false; unlocks = 0; interruptMembership = false; interruptUpload = false; changedRevision = false; unlockAllowed = !flags.contains("--paper-preview-handoff-denied-unlock") } }
    func changeWorkspace() { lock.withLock { workspaceChanged = true } }
    func endSession() { lock.withLock { sessionEnded = true } }
    func chooseWorkspace() { lock.withLock { choosingWorkspace = true } }
    func interruptNextMembership() { lock.withLock { interruptMembership = true } }
    func interruptNextUpload() { lock.withLock { interruptUpload = true } }
    func allowUnlock() { lock.withLock { unlockAllowed = true } }
    func authenticate() -> Bool { lock.withLock { unlocks += 1; return unlockAllowed } }
    func reviseSecond() { lock.withLock { changedRevision = true } }
    var receipt: String { lock.withLock {
        let value: [String: Any] = ["requests": requests, "approvals": attempts, "confirmedIDs": approved.keys.sorted(), "registrationClientIDs": clients.keys.sorted(), "confirmedMediaIDs": assets.keys.filter { assets[$0]?["uploadState"] as? String == "stored" }.sorted(), "ownerAuthenticationAttempts": unlocks]
        return String(data: try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), encoding: .utf8)!
    } }
    private func title(_ id: String) -> String {
        if flags.contains("--paper-preview-handoff-duplicate-titles") { return "Sample service" }
        return id == Self.a ? "Sample repair" : id == Self.b ? "Sample additional work" : id == Self.c ? "Previously approved work" : "Draft work"
    }
    private func amount(_ id: String) -> Int { id == Self.a || id == Self.c ? 19000 : id == Self.b && flags.contains("--paper-preview-handoff-mixed") ? 0 : 32000 }
    private func lines(_ id: String) -> [[String: Any]] {
        if id == Self.a, flags.contains("--paper-preview-handoff-discount") {
            return [["id": id, "description": "Anonymized service scope", "quantity": 1, "unitPrice": ["amount": 22000, "currency": "USD"]],
                    ["id": "sample-credit", "description": "Courtesy discount", "quantity": 1, "unitPrice": ["amount": -3000, "currency": "USD"]]]
        }
        return [["id": id, "description": "Anonymized service scope", "quantity": 1, "unitPrice": ["amount": amount(id), "currency": "USD"]]]
    }
    private func status(_ id: String) -> String {
        if id == Self.c, flags.contains("--paper-preview-handoff-third-sent"), approved[id] == nil { return "sent" }
        if approved[id] != nil || id == Self.c || (id == Self.a && flags.contains("--paper-preview-handoff-mixed")) { return "approved" }
        return id == Self.d ? "draft" : "sent"
    }
    private func options(_ id: String) -> [[String: Any]] {
        guard id == Self.a, flags.contains("--paper-preview-handoff-options") else { return [] }
        let scope: [[String: Any]] = [["id": "sample-package-line", "description": "Selected package scope", "quantity": 1, "unitPrice": ["amount": 25000, "currency": "USD"]]]
        return [["id": "00000000-0000-4000-8000-000000008201", "title": "Sample package", "description": "One package within this estimate", "lines": scope, "totalAmount": 25000, "currency": "USD"]]
    }
    private func estimate(_ id: String) -> [String: Any] {
        var value: [String: Any] = ["id": id, "organizationId": org, "customerId": PaperPreview.customerID, "createdByUserId": PaperPreview.actorID, "status": status(id), "currentRevisionNumber": changedRevision && id == Self.b ? 2 : 1, "title": title(id), "lines": lines(id), "createdAt": "2026-10-29T00:00:00Z", "updatedAt": "2026-10-29T00:00:00Z"]
        if !options(id).isEmpty { value["options"] = options(id) }
        if let signature = approved[id] {
            if let image = signature["imageMediaId"] as? String, assets[image] != nil { value["approvalSignature"] = signature }
            value["approvedAt"] = signature["signedAt"]
        }
        return value
    }
    private func revision(_ id: String) -> [String: Any] {
        ["id": id.replacingOccurrences(of: "0081", with: "0091"), "estimateId": id, "organizationId": org, "customerId": PaperPreview.customerID,
         "revisionNumber": 1, "status": "issued", "title": title(id), "lines": lines(id), "options": options(id), "totalAmount": amount(id), "currency": "USD"]
    }
    private func job() -> [String: Any] {
        ["id": PaperPreview.jobID, "organizationId": org, "customerId": PaperPreview.customerID, "title": "Sample service visit", "status": "in_progress", "createdAt": "2026-10-29T00:00:00Z", "updatedAt": "2026-10-29T00:00:00Z", "allowedTransitions": ["completed", "paused"]]
    }
    private func action(_ id: String) -> [String: Any] {
        let scopes = lines(id).map { line -> [String: Any] in ["id": id, "description": line["description"]!, "quantity": 1, "unitPrice": amount(id)] }
        let quoted = options(id).map { option -> [String: Any] in var copy = option; copy.removeValue(forKey: "lines"); return copy }
        var value: [String: Any] = ["kind": "estimate", "title": title(id), "status": status(id), "revisionNumber": 1, "contentHash": String(repeating: id == Self.a ? "a" : "b", count: 64),
                "allowedActions": status(id) == "sent" ? ["approve","decline"] : [], "nonce": "sample-nonce-\(id)", "totalAmount": amount(id), "currency": "USD", "html": "<main>Local sample terms</main>",
                "consentVersion": "estimate-approval-v1", "consentText": "I approve the selected scope and price and agree that my typed name is my electronic signature.", "scopeLines": scopes, "options": quoted]
        if let acceptance = acceptances[id] { value["acceptance"] = acceptance }
        return value
    }
    private func data(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }; var value = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; value.append(buffer, count: count) }
        return value
    }
    func response(_ request: URLRequest) -> Response? { lock.withLock {
        guard let url = request.url else { return .init(status: 400, payload: [:]) }
        let path = url.path, method = request.httpMethod ?? "GET"
        requests.append(["method": method, "path": path])
        let input = data(request)
        let body = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any] ?? [:]
        let expiry = ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600))
        if path == "/api/auth/get-session" {
            if sessionEnded { return .init(status: 200, payload: NSNull()) }
            var session: [String: Any] = ["userId": PaperPreview.actorID, "expiresAt": expiry]
            if !choosingWorkspace { session["activeOrganizationId"] = org }
            return .init(status: 200, payload: ["user": ["id": PaperPreview.actorID, "name": "Sample technician"], "session": session])
        }
        if path == "/api/auth/organization/list" { return .init(status: 200, payload: choosingWorkspace ? [["id": PaperPreview.organizationID,"name":"Sample A"],["id":"00000000-0000-4000-8000-000000000003","name":"Sample B"]] : [["id":org,"name":"Sample workspace"]]) }
        if path == "/v1/query/catalog" { return .init(status: 200, payload: ["authority": ["actorId": PaperPreview.actorID,"organizationId":org,"policyVersion":1,"generation":"sample"], "capabilities": ["job.view","job.edit","estimate.view","estimate.create","estimate.send","estimate.approve","invoice.view","customer.view","pricebook.view"], "resources":[],"views":[]]) }
        if path == "/v1/features" {
            let features = Dictionary(uniqueKeysWithValues: ["jobs","estimates","invoicing","core_crm","price_book"].map { ($0,["enabled":true,"released":true,"entitled":true]) })
            return .init(status:200,payload:["organizationId":org,"evaluatedAt":now,"features":features])
        }
        if method == "GET", path == "/v1/jobs" { return .init(status:200,payload:["items":workspaceChanged ? [] : [job()]]) }
        if method == "GET", path == "/v1/customers" { return .init(status:200,payload:["items":[["id":PaperPreview.customerID,"organizationId":org,"name":"Sample customer","accountType":"residential","archived":false,"createdAt":now,"updatedAt":now]]]) }
        if method == "GET", path == "/v1/jobs/\(PaperPreview.jobID)" { return .init(status:200,payload:job()) }
        if method == "GET", path == "/v1/jobs/\(PaperPreview.jobID)/estimates",
           flags.contains("--paper-preview-handoff-membership-fails-after-approval"), !approved.isEmpty {
            return .init(status: 200, payload: [:], error: URLError(.networkConnectionLost))
        }
        if method == "GET", path == "/v1/jobs/\(PaperPreview.jobID)/estimates", interruptMembership {
            interruptMembership = false; return .init(status: 200, payload: [:], error: URLError(.networkConnectionLost))
        }
        if method == "GET", path == "/v1/jobs/\(PaperPreview.jobID)/estimates" { return .init(status:200,payload:["items":ids.map { ["id":$0,"jobId":PaperPreview.jobID,"estimateId":$0,"linkedAt":now] }]) }
        if method == "GET", path == "/v1/jobs/\(PaperPreview.jobID)/invoices" { return .init(status:200,payload:["items":[]]) }
        for id in ids {
            if method == "GET", path == "/v1/estimates/\(id)" { return .init(status:200,payload:estimate(id)) }
            if method == "GET", path == "/v1/estimates/\(id)/revisions/1" { return .init(status:200,payload:revision(id)) }
            if method == "POST", path == "/v1/estimates/\(id)/commercial-documents" { return .init(status:200,payload:["source":["type":"estimate","id":id],"contentHash":String(repeating:id == Self.a ? "a":"b",count:64),"snapshot":["content":["revision":["number":1]]]]) }
            if method == "POST", path == "/v1/estimates/\(id)/action-tokens" { return .init(status:200,payload:["token":"sample-\(id)"]) }
            if method == "GET", path == "/v1/public/document-actions/sample-\(id)" { return .init(status:200,payload:action(id)) }
            let direct = path == "/v1/estimates/\(id)/approve"
            let publicAction = path == "/v1/public/document-actions/sample-\(id)/approve"
            if method == "POST", direct || publicAction {
                var receipt: [String: Any] = ["estimateID":id,"body":body,"endpoint":path]
                guard (body["revisionNumber"] as? Int) == 1, !changedRevision || id != Self.b else { return .init(status:409,payload:["status":409,"title":"Sample revision changed"]) }
                let signature: [String: Any]
                if direct {
                    guard let incoming = body["signature"] as? [String: Any], let mediaID = incoming["imageMediaId"] as? String,
                          assets[mediaID]?["uploadState"] as? String == "stored", let signer = incoming["signerName"] as? String, !signer.isEmpty,
                          !approved.contains(where: { $0.key != id && $0.value["imageMediaId"] as? String == mediaID }) else { return .init(status:422,payload:["status":422,"title":"Exact fresh signature required"]) }
                    var value = incoming; value["id"] = UUID().uuidString; signature = value; receipt["mediaID"] = mediaID
                } else {
                    guard body["nonce"] as? String == "sample-nonce-\(id)", body["contentHash"] as? String == String(repeating:id == Self.a ? "a":"b",count:64), body["consent"] as? Bool == true,
                          body["consentVersion"] as? String == "estimate-approval-v1", let signer = body["signerName"] as? String, !signer.isEmpty else { return .init(status:422,payload:["status":422,"title":"Exact consent required"]) }
                    signature = ["id":UUID().uuidString,"signerName":signer,"signedAt":now,"imageMediaId":"typed-electronic-signature"]
                }
                if let old = approved[id], direct {
                    guard old["imageMediaId"] as? String == signature["imageMediaId"] as? String,
                          old["signerName"] as? String == signature["signerName"] as? String,
                          old["signedAt"] as? String == signature["signedAt"] as? String else { return .init(status:409,payload:["status":409,"title":"Approval signature is immutable"]) }
                }
                if publicAction, !options(id).isEmpty, !options(id).contains(where: { $0["id"] as? String == body["optionId"] as? String }) { return .init(status:422,payload:["status":422,"title":"Choose one package"]) }
                attempts.append(receipt)
                if id == Self.b, !lost, flags.contains("--paper-preview-handoff-fail-before-second") { lost = true; return .init(status:200,payload:[:],error:URLError(.networkConnectionLost)) }
                approved[id] = signature
                if publicAction {
                    var acceptance: [String: Any] = ["id": UUID().uuidString, "signerName": signature["signerName"]!, "acceptedAt": now, "totalAmount": amount(id)]
                    if let selected = body["optionId"] as? String {
                        acceptance["optionId"] = selected
                        acceptance["totalAmount"] = options(id).first(where: { $0["id"] as? String == selected })?["totalAmount"] ?? amount(id)
                    }
                    acceptances[id] = acceptance
                }
                if id == Self.b, !lost, flags.contains("--paper-preview-handoff-lose-second") { lost = true; return .init(status:200,payload:[:],error:URLError(.networkConnectionLost)) }
                if publicAction, flags.contains("--paper-preview-handoff-public-patch-no-acceptance") {
                    return .init(status:200,payload:["status":"approved"])
                }
                return .init(status:200,payload:direct ? estimate(id) : action(id))
            }
        }
        if method == "POST", path == "/v1/jobs/\(PaperPreview.jobID)/media" {
            guard let client = body["clientAssetId"] as? String, UUID(uuidString: client) != nil, let hash = body["contentHash"] as? String, let count = body["sizeBytes"] as? Int, body["mime"] as? String == "image/png", body["tags"] as? [String] == ["signature"] else { return .init(status:422,payload:["status":422,"title":"Invalid sample signature registration"]) }
            let id = clients[client] ?? UUID().uuidString.lowercased(); clients[client] = id
            if let old = assets[id], old["contentHash"] as? String != hash { return .init(status:409,payload:["status":409,"title":"Client asset collision"]) }
            if assets[id] == nil { assets[id] = ["id":id,"organizationId":org,"jobId":PaperPreview.jobID,"uploaderUserId":PaperPreview.actorID,"kind":"photo","mime":"image/png","sizeBytes":count,"originalFilename":"signature.png","contentHash":hash,"storageKey":"sample/\(id)","uploadState":"registered","tags":["signature"],"archived":false,"createdAt":now,"updatedAt":now] }
            return .init(status:200,payload:["asset":assets[id]!,"uploadTarget":["url":"https://sample-upload.thorbis.invalid/\(id)","method":"PUT","expiresAt":expiry,"headers":["Content-Type":"image/png"]]])
        }
        if method == "PUT", url.host == "sample-upload.thorbis.invalid" {
            if interruptUpload { interruptUpload = false; return .init(status: 200, payload: [:], error: URLError(.networkConnectionLost)) }
            let id = url.lastPathComponent
            guard let asset = assets[id], SHA256.hash(data: input).map({ String(format:"%02x",$0) }).joined() == asset["contentHash"] as? String,
                  input.count == asset["sizeBytes"] as? Int, CGImageSourceCreateWithData(input as CFData, nil).map({ CGImageSourceCreateImageAtIndex($0, 0, nil) != nil }) == true else { return .init(status:422,payload:[:]) }
            bytes[id] = input; return .init(status:200,payload:[:])
        }
        if method == "POST", path.hasPrefix("/v1/media/"), path.hasSuffix("/confirm") {
            let id = String(path.dropFirst("/v1/media/".count).dropLast("/confirm".count))
            guard bytes[id] != nil, assets[id] != nil else { return .init(status:422,payload:["status":422,"title":"Sample bytes not stored"]) }
            assets[id]?["uploadState"] = "stored"; return .init(status:200,payload:assets[id]!)
        }
        return nil
    } }
}

/// Zero-layout, noninteractive observation of the isolated transport ledger only.
struct JobEstimateHandoffReceiptMetadata: UIViewRepresentable {
    final class ReceiptView: UIView {
        override var accessibilityValue: String? {
            get { JobEstimateHandoffPreview.shared.receipt }
            set { }
        }
    }
    func makeUIView(context: Context) -> ReceiptView {
        let view = ReceiptView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = true
        view.accessibilityIdentifier = "handoff-canonical-receipt"
        view.accessibilityLabel = "Anonymized sample approval receipt"
        return view
    }
    func updateUIView(_ view: ReceiptView, context: Context) { }
}

struct JobEstimateHandoffPreviewControls: View {
    @EnvironmentObject private var session: SessionController
    @State private var proof = ""
    var body: some View {
        DisclosureGroup("Sample testing controls") {
            Button("Change sample workspace shortly") { delayed { JobEstimateHandoffPreview.shared.changeWorkspace() } }
            Button("End sample session shortly") { delayed(restore: true) { JobEstimateHandoffPreview.shared.endSession() } }
            Button("Choose sample workspace shortly") { delayed(restore: true) { JobEstimateHandoffPreview.shared.chooseWorkspace() } }
            Button("Interrupt next membership read") { JobEstimateHandoffPreview.shared.interruptNextMembership() }
            Button("Interrupt next signature upload") { JobEstimateHandoffPreview.shared.interruptNextUpload() }
            Button("Allow sample unlock") { JobEstimateHandoffPreview.shared.allowUnlock() }
            Button("Refresh sample receipt") { proof = JobEstimateHandoffPreview.shared.receipt }
            Text("Sample approval receipt").accessibilityIdentifier("handoff-sample-receipt").accessibilityValue(proof)
            Text("Sample live session").accessibilityIdentifier("handoff-sample-session").accessibilityValue("\(session.generation.uuidString) | \(session.activeOrganization?.id ?? "none") | \(session.phase)")
        }.font(Theme.font(13)).padding(.horizontal, Theme.gutter)
    }
    private func delayed(restore: Bool = false, _ change: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4)); change()
            if restore { await session.restore() } else { await session.revalidate() }
        }
    }
}
#endif

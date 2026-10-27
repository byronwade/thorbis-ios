#if DEBUG
import Foundation
import SwiftUI

/// Screenshot fixtures only. This entire file is absent from Release builds.
/// Transport captures every request, including unsupported hosts; it never forwards.
enum PaperPreview {
    static let actorID = "00000000-0000-4000-8000-000000000001"
    static let organizationID = "00000000-0000-4000-8000-000000000002"
    static let jobID = "00000000-0000-4000-8000-000000002214"
    static let customerID = "00000000-0000-4000-8000-000000000412"
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("--paper-preview") }
    static var screen: String {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--paper-preview-screen"), args.indices.contains(index + 1),
              ["schedule", "jobs", "customers", "job", "customer", "menu"].contains(args[index + 1]) else { return "schedule" }
        return args[index + 1]
    }
    @MainActor static func api() -> APIClient {
        let api = APIClient(session: transport(), baseURL: "https://app.thorbis.com")
        // Override any launch-environment dev identity; restore must use fixture authority.
        api.auth = .none
        return api
    }
    static func defaults() -> UserDefaults {
        UserDefaults(suiteName: "thorbis.paper-preview.\(UUID().uuidString)")!
    }
    static func transport() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PaperPreviewProtocol.self]
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }
    @MainActor static var banner: some View {
        Text("DESIGN PREVIEW · SAMPLE DATA · READ ONLY")
            .font(.system(size: 9, weight: .semibold)).tracking(0.4)
            .foregroundStyle(Color.orange).frame(maxWidth: .infinity).padding(.vertical, 3)
            .background(Color.black)
            .accessibilityLabel("Design preview. Sample data. Read only. No network connection.")
    }
}

final class PaperPreviewProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return }
        let status: Int
        let payload: Any
        if request.httpMethod != nil && request.httpMethod != "GET" {
            status = 405
            payload = ["status": 405, "title": "Design preview is read-only", "detail": "Sample data cannot be changed. No request was sent to a server."]
        } else if url.scheme == "https", url.host == "app.thorbis.com", let fixture = Self.fixture(path: url.path) {
            status = 200
            payload = fixture
        } else {
            status = 404
            payload = ["status": 404, "title": "Preview fixture unavailable", "detail": "This request is not part of the design preview. No request was sent to a server."]
        }
        do {
            let body = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json", "X-Thorbis-Design-Preview": "sample-data"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}

    private static func fixture(path: String) -> Any? {
        let actor = PaperPreview.actorID
        let org = PaperPreview.organizationID
        let expiry = ISO8601DateFormatter().string(from: Date().addingTimeInterval(86_400))
        let now = ISO8601DateFormatter().string(from: Date())
        switch path {
        case "/api/auth/get-session":
            return ["user": ["id": actor, "name": "Ramon Marlowe", "email": "preview@example.invalid"], "session": ["userId": actor, "activeOrganizationId": org, "expiresAt": expiry]]
        case "/api/auth/organization/list": return [["id": org, "name": "Wade’s Plumbing · Preview"]]
        case "/v1/query/catalog":
            return ["authority": ["actorId": actor, "organizationId": org, "policyVersion": 1, "generation": "paper-preview", "authorityExpiresAt": expiry],
                    "capabilities": ["job.view", "job.create", "job.edit", "job.note", "job.assign", "customer.view", "customer.create", "customer.edit", "estimate.view", "invoice.view", "pricebook.view"],
                    "resources": [], "views": []] as [String: Any]
        case "/v1/features":
            let decision = ["enabled": true, "released": true, "entitled": true]
            let features = Dictionary(uniqueKeysWithValues: ["jobs", "core_crm", "estimates", "invoicing", "price_book"].map { ($0, decision) })
            return ["organizationId": org, "evaluatedAt": now, "features": features]
        case "/v1/jobs": return ["items": jobs()]
        case "/v1/customers": return ["items": customers()]
        default: break
        }
        for job in jobs() {
            guard let id = job["id"] as? String else { continue }
            if path == "/v1/jobs/\(id)" { return job }
            if path == "/v1/jobs/\(id)/notes" {
                return ["items": [["id": "00000000-0000-4000-8000-000000009001", "organizationId": org, "jobId": id, "authorUserId": actor, "body": "Sample note: Customer confirmed access to the outdoor unit.", "createdAt": today(hour: 9, minute: 15)]]]
            }
            if path == "/v1/jobs/\(id)/photos" || path == "/v1/jobs/\(id)/media" { return ["items": []] }
        }
        for customer in customers() {
            guard let id = customer["id"] as? String, let name = customer["name"] as? String, let address = customer["address"] as? String else { continue }
            if path == "/v1/customers/\(id)" { return customer }
            if path == "/v1/customers/\(id)/contacts" {
                return ["items": [["id": "00000000-0000-4000-8000-000000008001", "organizationId": org, "customerId": id, "name": name, "role": "Homeowner", "primary": true, "createdAt": now, "updatedAt": now] as [String: Any]]]
            }
            if path == "/v1/customers/\(id)/locations" {
                return ["items": [["id": "00000000-0000-4000-8000-000000007001", "organizationId": org, "customerId": id, "label": "Home", "kind": "service", "address": address, "notes": "Sample location for design preview", "createdAt": now, "updatedAt": now]]]
            }
        }
        return nil
    }
    private static func today(hour: Int, minute: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
        return ISO8601DateFormatter().string(from: date)
    }
    private static func jobs() -> [[String: Any]] {
        let rows: [(String, String, String, String, Int, Int)] = [
            ("2214", "0412", "AC not cooling", "en_route", 10, 30),
            ("2212", "0413", "Kitchen sink backup — Petrov", "scheduled", 12, 15),
            ("2209", "0414", "Water heater install — Chen", "in_progress", 13, 0),
            ("2218", "0415", "Outlet replacement — Alvarez", "scheduled", 14, 30),
            ("2224", "0416", "AC recheck — Nakamura", "scheduled", 16, 0),
            ("2201", "0412", "Drain cleaning", "completed", 8, 30)
        ]
        return rows.map { ref, customer, title, status, hour, minute in
            ["id": "00000000-0000-4000-8000-00000000\(ref)", "organizationId": PaperPreview.organizationID,
             "customerId": "00000000-0000-4000-8000-00000000\(customer)", "title": title, "status": status,
             "assignedToUserId": PaperPreview.actorID, "scheduledFor": today(hour: hour, minute: minute),
             "createdAt": "2026-07-20T12:00:00Z", "updatedAt": today(hour: 9, minute: 0),
             "notes": "Sample job: Upstairs zone blowing warm air since Sunday. Customer suspects the capacitor.",
             "allowedTransitions": status == "completed" ? [] : ["arrived", "in_progress", "paused"]] as [String: Any]
        }
    }
    private static func customers() -> [[String: Any]] {
        let rows = [("0412", "Danielle Marlowe", "412 Birchwood Ln"), ("0413", "Alex Petrov", "88 Larch Ave"), ("0414", "David Chen", "245 Rosemont Dr"), ("0415", "Elena Alvarez", "19 Fenwick Ct"), ("0416", "Mei Nakamura", "731 Cassia Way")]
        return rows.map { ref, name, address in
            ["id": "00000000-0000-4000-8000-00000000\(ref)", "organizationId": PaperPreview.organizationID, "name": name, "address": address,
             "accountType": "residential", "archived": false, "createdAt": "2022-03-01T12:00:00Z", "updatedAt": "2026-07-20T12:00:00Z", "billingTerms": "Due on receipt"] as [String: Any]
        }
    }
}
#endif

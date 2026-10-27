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
              ["schedule", "jobs", "my-day", "customers", "job", "job-invoice", "job-estimates", "job-activity", "job-media", "job-closeout", "job-assign", "job-followups", "offline", "offline-job", "customer", "estimates", "invoices", "team", "reports", "billing", "billing-detail", "notices", "new-customer", "job-invoice-empty", "new-estimate", "price-book", "revenue", "menu", "more", "search", "inbox", "invoice-editor", "invoice-detail", "invoice-payment", "invoice-payment-refund", "invoice-payment-refund-form", "invoice-payment-refund-confirmation", "invoice-payment-refund-pending", "invoice-payment-refund-reconciliation", "estimate-revision", "public-estimate"].contains(args[index + 1]) else { return "schedule" }
        return args[index + 1]
    }
    static var isPaymentCollectionPreview: Bool { screen == "invoice-payment" || screen == "job-invoice" }
    static var isPaymentRefundPreview: Bool {
        ["invoice-payment-refund", "invoice-payment-refund-form", "invoice-payment-refund-confirmation", "invoice-payment-refund-pending", "invoice-payment-refund-reconciliation"].contains(screen)
    }
    static var invoiceDetailPreviewID: String {
        isPaymentRefundPreview ? refundInvoice.id : issuedInvoice.id
    }
    static var estimate: EstimateRecord {
        let json = #"{"id":"00000000-0000-4000-8000-000000002218","organizationId":"00000000-0000-4000-8000-000000000002","customerId":"00000000-0000-4000-8000-000000000412","createdByUserId":"00000000-0000-4000-8000-000000000001","status":"sent","currentRevisionNumber":2,"title":"AC repair and compressor replacement","lines":[{"id":"00000000-0000-4000-8000-000000009211","description":"Compressor diagnostic","quantity":1,"unitPrice":{"amount":12000,"currency":"USD"},"source":{"kind":"manual","addedByUserId":"00000000-0000-4000-8000-000000000001","capturedAt":"2026-07-18T12:00:00Z"}},{"id":"00000000-0000-4000-8000-000000009212","description":"Replace compressor","quantity":1,"unitPrice":{"amount":85000,"currency":"USD"},"source":{"kind":"price_book","priceBookItemId":"00000000-0000-4000-8000-000000009201","priceBookRevision":4,"originalDescription":"Replace compressor","originalUnitPrice":{"amount":85000,"currency":"USD"},"addedByUserId":"00000000-0000-4000-8000-000000000001","capturedAt":"2026-07-18T12:00:00Z","overriddenFields":[]}}],"options":[{"id":"00000000-0000-4000-8000-000000009213","title":"Full system replacement","description":"Includes new compressor and efficiency inspection","lines":[{"id":"00000000-0000-4000-8000-000000009214","description":"System replacement","quantity":1,"unitPrice":{"amount":225000,"currency":"USD"},"source":{"kind":"manual","addedByUserId":"00000000-0000-4000-8000-000000000001","capturedAt":"2026-07-18T12:00:00Z"}}],"totalAmount":225000,"currency":"USD"}],"createdAt":"2026-07-18T12:00:00Z","updatedAt":"2026-07-20T12:00:00Z","sentAt":"2026-07-20T12:00:00Z"}"#
        return try! JSONDecoder().decode(EstimateRecord.self, from: Data(json.utf8))
    }
    static var invoice: InvoiceRecord {
        let json = #"{"id":"00000000-0000-4000-8000-000000002209","organizationId":"00000000-0000-4000-8000-000000000002","customerId":"00000000-0000-4000-8000-000000000412","jobId":"00000000-0000-4000-8000-000000002214","createdByUserId":"00000000-0000-4000-8000-000000000001","locationId":null,"scheduleId":null,"origin":"job_completion","sourceOperationKey":"paper-preview-invoice","sourceEstimateId":null,"sourceEstimateRevisionNumber":null,"manualPhysicalServiceEvidence":null,"status":"draft","lines":[{"id":"00000000-0000-4000-8000-000000009101","description":"Compressor diagnostic","quantity":1,"unitPrice":{"amount":12000,"currency":"USD"},"source":{"kind":"manual"}},{"id":"00000000-0000-4000-8000-000000009102","description":"Refrigerant recharge","quantity":2,"unitPrice":{"amount":9000,"currency":"USD"},"source":{"kind":"manual"}},{"id":"00000000-0000-4000-8000-000000009103","description":"Trip fee","quantity":1,"unitPrice":{"amount":4000,"currency":"USD"},"source":{"kind":"manual"}}],"linesRevision":3,"amountPaid":0,"currency":"USD","issuedAt":null,"paidAt":null,"voidedAt":null,"createdAt":"2026-07-18T12:00:00Z","updatedAt":"2026-07-20T12:00:00Z"}"#
        return try! JSONDecoder().decode(InvoiceRecord.self, from: Data(json.utf8))
    }
    static var issuedInvoice: InvoiceRecord {
        let json = #"{"id":"00000000-0000-4000-8000-000000002209","organizationId":"00000000-0000-4000-8000-000000000002","customerId":"00000000-0000-4000-8000-000000000412","jobId":"00000000-0000-4000-8000-000000002214","createdByUserId":"00000000-0000-4000-8000-000000000001","locationId":null,"scheduleId":null,"origin":"job_completion","sourceOperationKey":"paper-preview-invoice","sourceEstimateId":null,"sourceEstimateRevisionNumber":null,"manualPhysicalServiceEvidence":null,"status":"issued","lines":[{"id":"00000000-0000-4000-8000-000000009101","description":"Compressor diagnostic","quantity":1,"unitPrice":{"amount":12000,"currency":"USD"},"source":{"kind":"manual"}},{"id":"00000000-0000-4000-8000-000000009102","description":"Refrigerant recharge","quantity":2,"unitPrice":{"amount":9000,"currency":"USD"},"source":{"kind":"manual"}},{"id":"00000000-0000-4000-8000-000000009103","description":"Trip fee","quantity":1,"unitPrice":{"amount":4000,"currency":"USD"},"source":{"kind":"manual"}}],"linesRevision":3,"amountPaid":0,"currency":"USD","issuedAt":"2026-07-20T12:00:00Z","paidAt":null,"voidedAt":null,"createdAt":"2026-07-20T12:00:00Z","updatedAt":"2026-07-20T12:00:00Z"}"#
        return try! JSONDecoder().decode(InvoiceRecord.self, from: Data(json.utf8))
    }
    static var refundInvoice: InvoiceRecord {
        let json = #"{"id":"00000000-0000-4000-8000-000000002219","organizationId":"00000000-0000-4000-8000-000000000002","customerId":"00000000-0000-4000-8000-000000000412","jobId":"00000000-0000-4000-8000-000000002214","createdByUserId":"00000000-0000-4000-8000-000000000001","locationId":null,"scheduleId":null,"origin":"job_completion","sourceOperationKey":"paper-preview-refund-invoice","sourceEstimateId":null,"sourceEstimateRevisionNumber":null,"manualPhysicalServiceEvidence":null,"status":"paid","lines":[{"id":"00000000-0000-4000-8000-000000009111","description":"Compressor diagnostic","quantity":1,"unitPrice":{"amount":1500,"currency":"USD"},"source":{"kind":"manual"}},{"id":"00000000-0000-4000-8000-000000009112","description":"Refrigerant recharge","quantity":1,"unitPrice":{"amount":1000,"currency":"USD"},"source":{"kind":"manual"}}],"linesRevision":1,"amountPaid":2500,"currency":"USD","issuedAt":"2026-07-20T12:00:00Z","paidAt":"2026-07-20T12:10:00Z","voidedAt":null,"createdAt":"2026-07-20T12:00:00Z","updatedAt":"2026-07-20T12:10:00Z"}"#
        return try! JSONDecoder().decode(InvoiceRecord.self, from: Data(json.utf8))
    }
    static var refundPayment: FieldPaymentRecord {
        let json = #"{"id":"00000000-0000-4000-8000-000000002220","organizationId":"00000000-0000-4000-8000-000000000002","invoiceId":"00000000-0000-4000-8000-000000002219","amount":{"amount":2500,"currency":"USD"},"method":"card","status":"recorded","collectionEvidence":{"purpose":"physical_service","source":{"kind":"job","id":"00000000-0000-4000-8000-000000002214"}},"idempotencyKey":"paper-preview-refund-payment","recordedAt":"2026-07-20T12:10:00Z","refundedAmount":null,"netAmount":{"amount":2500,"currency":"USD"},"refundedAt":null}"#
        return try! JSONDecoder().decode(FieldPaymentRecord.self, from: Data(json.utf8))
    }
    @MainActor static func refundIntentStore(for payment: FieldPaymentRecord) -> PaymentRefundIntentStoring {
        PreviewRefundIntentStore.shared.configure(for: payment, screen: screen)
        return PreviewRefundIntentStore.shared
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

@MainActor
private final class PreviewRefundIntentStore: PaymentRefundIntentStoring {
    static let shared = PreviewRefundIntentStore()

    private var intents: [String: FieldPaymentRefundIntent] = [:]
    private var configuredPreview: String?

    func configure(for payment: FieldPaymentRecord, screen: String) {
        guard configuredPreview != screen else { return }
        configuredPreview = screen
        let state: FieldPaymentRefundIntentState? = switch screen {
        case "invoice-payment-refund-pending": .pending
        case "invoice-payment-refund-reconciliation": .reconciliationRequired
        default: nil
        }
        let key = Self.key(actorID: PaperPreview.actorID, organizationID: payment.organizationId, paymentID: payment.id)
        if let state {
            intents[key] = FieldPaymentRefundIntent(reason: "Customer approved the sample refund.", state: state)
        } else {
            intents.removeValue(forKey: key)
        }
    }

    func load(actorID: String, organizationID: String, paymentID: String) throws -> FieldPaymentRefundIntent? {
        intents[Self.key(actorID: actorID, organizationID: organizationID, paymentID: paymentID)]
    }

    func save(_ intent: FieldPaymentRefundIntent, actorID: String, organizationID: String, paymentID: String) throws {
        intents[Self.key(actorID: actorID, organizationID: organizationID, paymentID: paymentID)] = intent
    }

    func remove(actorID: String, organizationID: String, paymentID: String) throws {
        intents.removeValue(forKey: Self.key(actorID: actorID, organizationID: organizationID, paymentID: paymentID))
    }

    private static func key(actorID: String, organizationID: String, paymentID: String) -> String {
        [actorID, organizationID, paymentID].joined(separator: ":")
    }
}

final class PaperPreviewProtocol: URLProtocol, @unchecked Sendable {
    /// The "offline" preview flips this after sign-in so every later request has no signal.
    nonisolated(unsafe) static var simulateNoSignal = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if Self.simulateNoSignal {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
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
        if path == "/v1/public/document-actions/preview-estimate" {
            return [
                "kind": "estimate",
                "title": "AC not cooling — Compressor replacement",
                "status": "sent",
                "revisionNumber": 2,
                "contentHash": "preview-issued-content-hash-2026",
                "allowedActions": ["approve", "decline", "request_changes"],
                "nonce": "preview-decision-nonce-2026",
                "totalAmount": 1575.00,
                "currency": "USD",
                "html": """
                <!doctype html><html><head><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><style>body{font:15px -apple-system,BlinkMacSystemFont,sans-serif;color:#201b14;background:#fff;margin:22px;line-height:1.5}.eyebrow{font-size:11px;color:#59544d;letter-spacing:.08em;text-transform:uppercase}h1{font-size:24px;margin:6px 0 16px}.line{display:flex;justify-content:space-between;gap:14px;padding:12px 0;border-bottom:1px solid #e5e2dc}.total{display:flex;justify-content:space-between;font-weight:700;padding-top:18px}.note{margin-top:22px;padding:12px;background:#f7f4ee;border-radius:10px}</style></head><body><div class=\"eyebrow\">Estimate · Revision 2</div><h1>AC not cooling — Compressor replacement</h1><p>Prepared for Danielle Marlowe</p><div class=\"line\"><span>Compressor diagnostic</span><span>$120.00</span></div><div class=\"line\"><span>Replace compressor</span><span>$1,455.00</span></div><div class=\"total\"><span>Estimate total</span><span>$1,575.00</span></div><div class=\"note\">This sample estimate is for design review only.</div></body></html>
                """,
                "approvalWithoutSignatureAllowed": false,
                "scopeLines": [],
                "options": [
                    ["id": "00000000-0000-4000-8000-000000000101", "title": "Compressor repair", "description": "Replace the failed compressor and verify system operation.", "totalAmount": 1575.00, "currency": "USD"],
                    ["id": "00000000-0000-4000-8000-000000000102", "title": "Full system replacement", "description": "Install a new high-efficiency system with a two-year labor warranty.", "totalAmount": 4850.00, "currency": "USD"]
                ],
                "consentVersion": "estimate-approval-v1",
                "consentText": "I understand that typing my name records my electronic signature and approval of the selected estimate option."
            ] as [String: Any]
        }
        if path == "/v1/invoices/\(PaperPreview.refundInvoice.id)" {
            return try? JSONSerialization.jsonObject(with: JSONEncoder().encode(PaperPreview.refundInvoice))
        }
        if path == "/v1/invoices/\(PaperPreview.refundInvoice.id)/payments" {
            return ["items": [try! JSONSerialization.jsonObject(with: JSONEncoder().encode(PaperPreview.refundPayment))]]
        }
        if path == "/v1/jobs/\(PaperPreview.jobID)/estimates" {
            return ["items": [["id": "00000000-0000-4000-8000-000000009301", "organizationId": org, "jobId": PaperPreview.jobID,
                               "estimateId": PaperPreview.estimate.id, "linkedAt": now]]]
        }
        if path == "/v1/estimates/\(PaperPreview.estimate.id)" {
            return try? JSONSerialization.jsonObject(with: JSONEncoder().encode(PaperPreview.estimate))
        }
        if path == "/v1/jobs/\(PaperPreview.jobID)/followups" {
            return ["items": [["id": "00000000-0000-4000-8000-000000009401", "organizationId": org, "jobId": PaperPreview.jobID, "kind": "office_scheduling",
                               "reason": "Compressor on backorder", "nextAction": "Book a return visit once the part arrives", "ownerUserId": actor,
                               "status": "open", "createdByUserId": actor, "createdAt": now]]]
        }
        if path == "/v1/organization/assignees" {
            return ["items": [["userId": actor, "displayName": "Ramon Marlowe"], ["userId": "00000000-0000-4000-8000-000000008801", "displayName": "Jorge Alvarez"],
                              ["userId": "00000000-0000-4000-8000-000000008802", "displayName": "Sam Osei"]]]
        }
        if path == "/v1/organization/role-members" {
            let people: [(String, String, Bool, String)] = [("Byron Wade", "byron@acmehvac.com", true, "owner"), ("Maria Chen", "maria@acmehvac.com", false, "Office"),
                ("Jorge Alvarez", "jorge@acmehvac.com", false, "Technician"), ("Dana Whitfield", "dana@acmehvac.com", false, "Office"), ("Sam Osei", "sam@acmehvac.com", false, "Technician")]
            return ["items": people.enumerated().map { index, person in
                ["member": ["memberId": "00000000-0000-4000-8000-00000000770\(index)", "userId": "00000000-0000-4000-8000-00000000880\(index)",
                            "displayName": person.0, "email": person.1, "isLegalOwner": person.2, "legalMembershipRoles": [["id": person.3.lowercased(), "label": person.3]]],
                 "authority": person.2 ? ["kind": "legacy_fallback", "currentAssignmentVersion": 0, "reason": "never_assigned", "roles": [["id": "owner", "label": "Owner"]]] as [String: Any]
                    : ["kind": "tenant_role", "assignmentId": "a\(index)", "currentAssignmentVersion": 1, "assignedRoleRevision": 1,
                       "role": ["roleId": "r\(index)", "currentRevision": 1, "name": person.3, "description": ""]]] as [String: Any]
            }]
        }
        if path == "/v1/notice-preferences" {
            return ["items": [["subjectKind": "role", "subjectKey": "technician", "channel": "email", "enabled": false]]]
        }
        if path == "/v1/billing-schedules/00000000-0000-4000-8000-000000009501",
           let list = fixture(path: "/v1/billing-schedules") as? [String: Any], let schedule = (list["items"] as? [[String: Any]])?.first {
            return ["schedule": schedule,
                    "lines": [["lineId": "00000000-0000-4000-8000-000000009511", "billedToDate": 420_000, "remaining": 0],
                              ["lineId": "00000000-0000-4000-8000-000000009512", "billedToDate": 390_000, "remaining": 390_000],
                              ["lineId": "00000000-0000-4000-8000-000000009513", "billedToDate": 0, "remaining": 150_000]],
                    "invoiceIds": [], "retainedToDate": 81_000, "releasedToDate": 0, "retainageOutstanding": 81_000,
                    "depositsBilled": 200_000, "depositCredited": 200_000, "depositOutstanding": 0] as [String: Any]
        }
        if path == "/v1/billing-schedules" {
            return ["items": [["id": "00000000-0000-4000-8000-000000009501", "organizationId": org, "customerId": PaperPreview.customerID,
                               "jobId": PaperPreview.jobID, "createdByUserId": actor, "retainageRateBps": 1000, "status": "open",
                               "lines": [["id": "00000000-0000-4000-8000-000000009511", "position": 0, "description": "Rough-in", "scheduledAmount": ["amount": 420_000, "currency": "USD"]],
                                         ["id": "00000000-0000-4000-8000-000000009512", "position": 1, "description": "Equipment set", "scheduledAmount": ["amount": 780_000, "currency": "USD"]],
                                         ["id": "00000000-0000-4000-8000-000000009513", "position": 2, "description": "Start-up and balance", "scheduledAmount": ["amount": 150_000, "currency": "USD"]]],
                               "createdAt": "2026-10-01T12:00:00Z", "updatedAt": now]]]
        }
        if path == "/v1/reports/operations" {
            return ["freshness": "live", "generatedAt": now, "periodBasis": "utc-month", "reportVersion": 1, "truncated": false,
                    "estimates": ["drafts": 4, "presented": 31, "approved": 18, "declined": 6, "conversionBps": 5806],
                    "jobs": ["booked": 86, "completed": 71, "canceled": 3, "open": 12],
                    "months": [["month": "2026-08", "booked": 74, "completed": 70], ["month": "2026-09", "booked": 81, "completed": 77], ["month": "2026-10", "booked": 86, "completed": 71]]] as [String: Any]
        }
        if path == "/v1/reports/schedule" {
            return ["freshness": "live", "generatedAt": now, "periodBasis": "utc-day", "reportVersion": 1, "capacityModel": "booked-time-only", "truncated": false,
                    "days": [["day": "2026-10-23", "scheduled": 9, "completed": 9], ["day": "2026-10-24", "scheduled": 11, "completed": 10],
                             ["day": "2026-10-26", "scheduled": 8, "completed": 8], ["day": "2026-10-27", "scheduled": 7, "completed": 2]],
                    "assignees": [], "backlog": ["unscheduledOpenJobs": 3, "overdueScheduledJobs": 1]] as [String: Any]
        }
        if path == "/v1/reports/revenue" {
            let months = [("2026-05", 3_812_000, 3_540_000), ("2026-06", 4_105_000, 3_960_000), ("2026-07", 3_980_000, 4_020_000),
                          ("2026-08", 4_612_000, 4_230_000), ("2026-09", 4_390_000, 4_480_000), ("2026-10", 4_892_000, 4_105_000)]
            return ["freshness": "live", "generatedAt": now, "periodBasis": "utc_month", "reportVersion": 1, "truncated": false,
                    "months": months.map { ["month": $0.0, "revenue": $0.1, "collected": $0.2] },
                    "receivable": ["openInvoices": 9, "balance": 733_000, "overdueInvoices": 2, "overdueBalance": 620_000]] as [String: Any]
        }
        if path == "/v1/invoices" && PaperPreview.screen == "job-invoice-empty" { return ["items": []] }
        if path == "/v1/invoices" { return ["items": [try! JSONSerialization.jsonObject(with: JSONEncoder().encode(PaperPreview.issuedInvoice))]] }
        if path == "/v1/invoices/\(PaperPreview.issuedInvoice.id)" {
            return try? JSONSerialization.jsonObject(with: JSONEncoder().encode(PaperPreview.issuedInvoice))
        }
        if path == "/v1/invoices/\(PaperPreview.issuedInvoice.id)/payments" { return ["items": []] }
        switch path {
        case "/api/auth/get-session":
            return ["user": ["id": actor, "name": "Ramon Marlowe", "email": "preview@example.invalid"], "session": ["userId": actor, "activeOrganizationId": org, "expiresAt": expiry]]
        case "/api/auth/organization/list": return [["id": org, "name": "Wade’s Plumbing · Preview"]]
        case "/v1/query/catalog":
            var capabilities = ["job.view", "job.create", "job.edit", "job.note", "job.assign", "customer.view", "customer.create", "customer.edit", "estimate.view", "estimate.create", "estimate.approve", "estimate.discount", "invoice.view", "invoice.edit", "invoice.issue", "pricebook.view"]
            if PaperPreview.isPaymentCollectionPreview { capabilities.append("invoice.payment.create") }
            if PaperPreview.isPaymentRefundPreview { capabilities.append("invoice.refund") }
            if PaperPreview.screen == "team" { capabilities.append("organization.members.manage") }
            if ["job-invoice-empty", "billing-detail"].contains(PaperPreview.screen) { capabilities.append("invoice.create") }
            if PaperPreview.screen == "notices" { capabilities.append("organization.settings.edit") }
            return ["authority": ["actorId": actor, "organizationId": org, "policyVersion": 1, "generation": "paper-preview", "authorityExpiresAt": expiry],
                    "capabilities": capabilities,
                    "resources": [], "views": []] as [String: Any]
        case "/v1/features":
            let decision = ["enabled": true, "released": true, "entitled": true]
            var enabledFeatures = ["jobs", "core_crm", "estimates", "estimate_option_signing", "invoicing", "price_book"]
            if PaperPreview.isPaymentRefundPreview || PaperPreview.isPaymentCollectionPreview || PaperPreview.screen == "revenue" { enabledFeatures.append("payments") }
            if PaperPreview.screen.hasPrefix("billing") { enabledFeatures.append("progress_billing") }
            if PaperPreview.screen == "notices" { enabledFeatures.append("job_booking_notices") }
            let features = Dictionary(uniqueKeysWithValues: enabledFeatures.map { ($0, decision) })
            return ["organizationId": org, "evaluatedAt": now, "features": features]
        // Like the server, list items carry no allowedTransitions; only GET /v1/jobs/{id} does.
        case "/v1/jobs": return ["items": jobs().map { $0.filter { $0.key != "allowedTransitions" } }]
        case "/v1/customers": return ["items": customers()]
        case "/v1/query":
            let priceBookID = "00000000-0000-4000-8000-000000009201"
            return ["schemaVersion": 1, "resourceId": "price_book_items", "purpose": "collection", "localMode": "complete",
                    "items": [["id": priceBookID, "resourceId": "price_book_items", "label": "Replace capacitor",
                               "subtitle": "Material · each",
                               "fields": ["price_book_items.id": priceBookID,
                                          "price_book_items.current_revision": 4,
                                          "price_book_items.description": "Replace capacitor",
                                          "price_book_items.unit": "each",
                                          "price_book_items.sell_price_amount": 12500,
                                          "price_book_items.currency": "USD",
                                          "price_book_items.tax_classification": "taxable",
                                          "price_book_items.kind": "material"]]],
                    "nextCursor": NSNull(), "planId": "paper-preview", "viewId": NSNull()] as [String: Any]
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
                return ["items": [
                    ["id": "00000000-0000-4000-8000-000000008001", "organizationId": org, "customerId": id,
                     "name": name, "role": "Homeowner", "email": "danielle@example.invalid", "phone": "(415) 555-0142",
                     "primary": true, "createdAt": now, "updatedAt": now] as [String: Any],
                    ["id": "00000000-0000-4000-8000-000000008002", "organizationId": org, "customerId": id,
                     "name": "Taylor Marlowe", "role": "Spouse", "phone": "(415) 555-0177",
                     "primary": false, "createdAt": now, "updatedAt": now] as [String: Any]
                ]]
            }
            if path == "/v1/customers/\(id)/locations" {
                return ["items": [["id": "00000000-0000-4000-8000-000000007001", "organizationId": org, "customerId": id,
                                    "label": "Home", "kind": "service", "address": address,
                                    "notes": "Sample location for design preview",
                                    "coordinates": ["latitude": 37.7749, "longitude": -122.4194],
                                    "gateCode": "4821#", "alarmCode": "7350",
                                    "dogOnSite": "Rusty — friendly, stays in the back yard",
                                    "parking": "Driveway on the left", "createdAt": now, "updatedAt": now]]]
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
            ("2214", "0412", "AC not cooling", "dispatched", 10, 30),
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
             "allowedTransitions": status == "completed" ? [] : (status == "dispatched" ? ["en_route"] : ["arrived", "in_progress", "paused"])] as [String: Any]
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

#if DEBUG
import Foundation
import SwiftUI
import CryptoKit

/// Screenshot fixtures only. This entire file is absent from Release builds.
/// Transport captures every request, including unsupported hosts; it never forwards.
enum PaperPreview {
    static let actorID = "00000000-0000-4000-8000-000000000001"
    static let organizationID = "00000000-0000-4000-8000-000000000002"
    static let jobID = "00000000-0000-4000-8000-000000002214"
    static let customerID = "00000000-0000-4000-8000-000000000412"

    /// The Inbox preview's call log (GET /v1/calls items), newest first, relative to now.
    static func inboxCalls() -> [[String: Any]] {
        func ago(_ minutes: Double) -> String { ISO8601DateFormatter().string(from: Date().addingTimeInterval(-minutes * 60)) }
        let base = "00000000-0000-4000-8000-00000000"
        return [
            ["id": base + "9701", "direction": "inbound", "status": "missed", "lineId": "line-1", "callerNumber": "+15550100142",
             "callerName": "Marcus Bell", "startedAt": ago(18), "endedAt": ago(17.5), "durationSeconds": 0,
             "recording": ["status": "none"], "transcriptStatus": "none"],
            ["id": base + "9702", "direction": "inbound", "status": "completed", "lineId": "line-1", "callerNumber": "+15550100100",
             "callerName": "Dana Ruiz", "customerId": customerID, "jobId": jobID, "linkedAt": ago(170), "startedAt": ago(190), "endedAt": ago(186.8),
             "durationSeconds": 192, "recording": ["status": "available", "durationSeconds": 192, "contentPath": "/v1/calls/\(base)9702/recording"],
             "summary": ["text": "Water heater leaking at the base since this morning. Call 30 minutes ahead; side gate code 4471.", "reason": "Water heater leak", "source": "model"],
             "disclosure": "Thanks for calling. This call may be recorded and transcribed so we can serve you better.",
             "transcriptStatus": "complete"],
            ["id": base + "9703", "direction": "inbound", "status": "missed", "lineId": "line-1", "callerNumber": "+15550100177",
             "callerName": "Priya Shah", "startedAt": ago(26 * 60), "endedAt": ago(26 * 60 - 1), "durationSeconds": 42, "voicemail": true,
             "recording": ["status": "available", "durationSeconds": 42, "contentPath": "/v1/calls/\(base)9703/recording"],
             "summary": ["text": "Wants a quote to replace two upstairs windows before winter. Home after 4.", "source": "model"],
             "transcriptStatus": "complete"],
            ["id": base + "9704", "direction": "inbound", "status": "completed", "lineId": "line-1", "callerNumber": "(555) 010-0100",
             "callerName": "Dana Ruiz", "customerId": customerID, "startedAt": ago(3 * 24 * 60), "endedAt": ago(3 * 24 * 60 - 1),
             "durationSeconds": 64, "recording": ["status": "none"],
             "summary": ["text": "Asked whether we install tankless water heaters.", "source": "deterministic"],
             "transcriptStatus": "none"],
        ]
    }
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("--paper-preview") }
    static var screen: String {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--paper-preview-screen"), args.indices.contains(index + 1),
              ["schedule", "app-menu", "app-menu-edit", "bar-live", "bar-syncing", "search-typed", "ipad-sidebar", "settings", "whats-new", "schedule-week", "new-job", "create-menu", "schedule-unscheduled", "schedule-map", "customize-menu", "signature", "attention", "estimate-detail", "builder-options", "builder-picker", "builder-line", "invoice-editor-line", "jobs", "my-day", "customers", "job", "job-invoice", "job-estimates", "job-activity", "job-notes", "job-media", "job-closeout", "job-assign", "job-followups", "offline", "offline-job", "offline-job-money", "offline-followups", "offline-estimate", "offline-invoice", "offline-customer", "offline-customers", "customer", "customer-activity", "customer-records", "estimates", "invoices", "team", "reports", "billing", "billing-detail", "notices", "new-customer", "job-invoice-empty", "new-estimate", "price-book", "revenue", "menu", "more", "search", "inbox", "invoice-editor", "invoice-detail", "invoice-payment", "invoice-payment-refund", "invoice-payment-refund-form", "invoice-payment-refund-confirmation", "invoice-payment-refund-pending", "invoice-payment-refund-reconciliation", "estimate-revision", "estimate-draft", "estimate-draft-detail", "public-estimate", "present-estimate", "present-estimate-review", "present-invoice", "schedule", "customer-view", "customer-view-estimates", "customer-view-invoice", "customer-view-details", "next-stop", "next-stop-active", "job-history", "job-history-empty", "search-customers", "search-empty", "search-phone", "search-actions", "search-street", "search-offline", "tool-scan", "tool-checklist", "tool-checklist-pick", "present-estimate-detail", "job-onsite", "customer-jobs", "customer-money", "drafts", "local-fleet", "local-equipment", "local-agreements", "job-schedule", "equipment-editor", "jobs-filters", "equipment-sections", "book-job", "book-job-filled", "dispatch-board", "owner-home", "glance-widgets", "glance-lock", "glance-island", "present-estimate-financing", "present-invoice-pay", "properties", "property-detail", "notice-log", "scorecard", "payments"].contains(args[index + 1]) else { return "schedule" }
        return args[index + 1]
    }
    /// Owner registration screens: --paper-preview-screen onboard-signup | onboard-company | onboard-details | onboard-setup | onboard-trade | onboard-wizard.
    static var onboardingScreen: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--paper-preview-screen"), args.indices.contains(index + 1),
              ["onboard-signup", "onboard-company", "onboard-details", "onboard-setup", "onboard-trade", "onboard-wizard"].contains(args[index + 1]) else { return nil }
        return args[index + 1]
    }
    /// First-run and edge-state screens (2026-10-31): --paper-preview-screen state-login | state-login-error |
    /// state-session-expired | state-restore-failed | state-opening | state-signing-out | state-workspaces |
    /// state-empty | state-errors | state-loading. Kept apart from `screen` so the list stays separate.
    static var statesScreen: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--paper-preview-screen"), args.indices.contains(index + 1),
              ["state-login", "state-login-error", "state-session-expired", "state-restore-failed", "state-opening",
               "state-signing-out", "state-workspaces", "state-empty", "state-errors", "state-loading", "state-customer",
               "state-sheets", "state-toasts"].contains(args[index + 1]) else { return nil }
        return args[index + 1]
    }
    /// `--paper-preview-sheet team-invite | price-book-new | saved-work`: opens that sheet over its
    /// screen (team, price-book, schedule with a saved-work session) for sheet screenshots.
    static func opensSheet(_ name: String) -> Bool {
        let args = ProcessInfo.processInfo.arguments
        guard enabled, let index = args.firstIndex(of: "--paper-preview-sheet"), args.indices.contains(index + 1) else { return false }
        return args[index + 1] == name
    }
    /// `--paper-preview-role tech | office | owner`: who the preview session signs in as, for the
    /// drawer's role screenshots. Absent keeps the standard preview session (office capabilities).
    static var role: String? {
        let args = ProcessInfo.processInfo.arguments
        guard enabled, let index = args.firstIndex(of: "--paper-preview-role"), args.indices.contains(index + 1),
              ["tech", "office", "owner"].contains(args[index + 1]) else { return nil }
        return args[index + 1]
    }
    /// `--paper-preview-empty`: the workspace has no jobs, customers, estimates or invoices yet,
    /// so the real list screens show their empty states.
    static var isEmptyWorkspace: Bool { enabled && ProcessInfo.processInfo.arguments.contains("--paper-preview-empty") }
    /// `--paper-preview-hold-lists`: list reads (jobs, customers, estimates, invoices, notices, price
    /// book) never answer, so the real list screens stay on their loading skeletons for a capture.
    static var holdsLists: Bool { enabled && ProcessInfo.processInfo.arguments.contains("--paper-preview-hold-lists") }
    static let heldListPaths: Set<String> = ["/v1/jobs", "/v1/customers", "/v1/invoices", "/v1/estimates", "/v1/staff/notices", "/v1/query", "/v1/search"]
    /// With `--paper-preview-hold-after-first` the first read of each list path is answered (so the
    /// preview reaches its screen) and every later one waits: the screen's own list read stays loading.
    static var holdsAfterFirst: Bool { ProcessInfo.processInfo.arguments.contains("--paper-preview-hold-after-first") }
    /// `--paper-preview-hold-path /v1/estimates`: hold only that list (for screens whose own read is the first).
    static var heldPath: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--paper-preview-hold-path"), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }
    static var isJobEstimateHandoff: Bool { enabled && ProcessInfo.processInfo.arguments.contains("--paper-preview-job-estimate-handoff") }
    /// A data seed (the job's estimates and invoices), not a screen: it still opens the plain job.
    /// To capture the documents themselves use `--paper-preview-screen customer-view`.
    static var isJobDocumentsPreview: Bool { enabled && ProcessInfo.processInfo.arguments.contains("--paper-preview-job-documents") }
    static func replacedDescriptionEstimate(_ estimate: EstimateRecord) -> EstimateRecord {
        changed(estimate, ["currentRevisionNumber": (estimate.currentRevisionNumber ?? 0) + 1])
    }
    /// Set once a document's Description sheet has opened; the preview's document changes wait for it.
    @MainActor static var descriptionOpened = false
    @MainActor static func expireDocumentSessionForTesting(_ session: SessionController) async {
        let args = ProcessInfo.processInfo.arguments
        guard isJobDocumentsPreview || (screen == "present-estimate" && args.contains("--paper-preview-option-long-description")),
              args.contains("--paper-preview-description-expire-session") || args.contains("--paper-preview-description-revoke-permission") || args.contains("--paper-preview-description-replace-session") else { return }
        try? await Task.sleep(for: .seconds(10))
        guard !Task.isCancelled else { return }
        if args.contains("--paper-preview-description-revoke-permission") {
            PaperPreviewProtocol.revokeDocumentEstimateView()
            await session.revalidate()
        } else if args.contains("--paper-preview-description-replace-session") {
            Task { await session.restore() }
        } else {
            await session.signOut()
        }
    }
    static var isJobDocumentsMoneyPreview: Bool {
        isJobDocumentsPreview && ProcessInfo.processInfo.arguments.contains("--paper-preview-job-documents-money")
    }
    static var isJobEstimateRecoveryPreview: Bool {
        isJobDocumentsPreview && ProcessInfo.processInfo.arguments.contains("--paper-preview-job-estimate-recovery")
    }
    /// Deterministic OS-boundary responses for the isolated, read-only design preview only.
    static var ownerAuthentication: (@MainActor (String) async -> Bool)? {
        let args = ProcessInfo.processInfo.arguments
        guard enabled, let index = args.firstIndex(of: "--paper-preview-owner-auth"), args.indices.contains(index + 1),
              ["approved", "denied"].contains(args[index + 1]) else { return nil }
        let approved = args[index + 1] == "approved"
        return { _ in
            if isJobEstimateHandoff { return approved && JobEstimateHandoffPreview.shared.authenticate() }
            if approved, args.contains("--paper-preview-job-invoice-foreign-after-auth") {
                PaperPreviewProtocol.markOwnerAuthenticated()
            }
            return approved
        }
    }
    static var jobDocumentEstimates: [EstimateRecord] {
        var draft = changed(estimate, ["id": "00000000-0000-4000-8000-000000002238", "title": "Water heater add-ons", "status": "draft", "options": NSNull()])
        if isJobDocumentsPreview && ProcessInfo.processInfo.arguments.contains("--paper-preview-long-document-description") {
            let line = FieldLine(id: "00000000-0000-4000-8000-000000009298", description: "First paragraph: inspect the entire installation before beginning work. Confirm all existing connections and document their condition.\n\nSecond paragraph: carefully complete the repair, test the system, and explain the results to the customer. Final detail: return the work area to its original condition.", quantity: 1, unitPrice: FieldMoney(amount: 12000, currency: "USD"), source: nil)
            draft = changed(draft, ["lines": try! JSONSerialization.jsonObject(with: JSONEncoder().encode([line]))])
        }
        if isJobDocumentsPreview && ProcessInfo.processInfo.arguments.contains("--paper-preview-approved-unknown-total") {
            draft = changed(draft, ["status": "approved", "options": NSNull()])
        }
        if isJobDocumentsPreview && ProcessInfo.processInfo.arguments.contains("--paper-preview-job-estimate-empty-draft") {
            draft = changed(draft, ["lines": []])
        }
        if isJobDocumentsPreview && ProcessInfo.processInfo.arguments.contains("--paper-preview-job-estimate-invalid-money") {
            let invalid = FieldLine(id: "00000000-0000-4000-8000-000000009299", description: "Unverifiable sample amount", quantity: 2,
                                    unitPrice: FieldMoney(amount: Int.max, currency: "USD"), source: nil)
            draft = changed(draft, ["lines": try! JSONSerialization.jsonObject(with: JSONEncoder().encode([invalid]))])
        }
        var main = changed(estimate, ["title": "Main drain repair", "options": NSNull()])
        if isJobDocumentsPreview && ProcessInfo.processInfo.arguments.contains("--paper-preview-job-estimate-empty-issued") {
            main = changed(main, ["lines": [], "options": NSNull()])
        }
        if isJobDocumentsPreview && ProcessInfo.processInfo.arguments.contains("--paper-preview-job-estimate-zero-issued"),
           let first = main.lines.first {
            let zero = FieldLine(id: first.id, description: "No charge inspection", quantity: 1,
                                 unitPrice: FieldMoney(amount: 0, currency: "USD"), source: first.source)
            main = changed(main, ["lines": try! JSONSerialization.jsonObject(with: JSONEncoder().encode([zero])), "options": NSNull()])
        }
        if isJobDocumentsPreview && ProcessInfo.processInfo.arguments.contains("--paper-preview-job-estimate-review-states") {
            main = changed(main, ["status": "declined"])
            draft = changed(draft, ["status": "approved"])
        }
        if isJobDocumentsPreview && ProcessInfo.processInfo.arguments.contains("--paper-preview-job-estimate-multiple-options"),
           let original = estimate.options,
           var options = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [[String: Any]],
           var second = options.first {
            second["id"] = "00000000-0000-4000-8000-000000009219"
            second["title"] = "Second complete package"
            options.append(second)
            main = changed(estimate, ["title": "Main drain repair", "options": options])
        }
        return [main, draft,
                changed(estimate, ["id": "00000000-0000-4000-8000-000000002239", "title": "Other job estimate", "options": NSNull()])]
    }
    static var jobDocumentInvoices: [InvoiceRecord] {
        var primary = issuedInvoice
        if isJobDocumentsPreview && ProcessInfo.processInfo.arguments.contains("--paper-preview-long-document-description"), let first = primary.lines.first {
            let longLine = FieldLine(id: first.id, description: "Invoice first paragraph: inspect the installation and document the existing condition before work starts.\n\nInvoice second paragraph: complete the service, test all connections, and explain the outcome. Final invoice detail: leave the site clean.", quantity: first.quantity, unitPrice: first.unitPrice, source: first.source)
            primary = changed(primary, ["lines": try! JSONSerialization.jsonObject(with: JSONEncoder().encode([longLine] + Array(primary.lines.dropFirst())))])
        }
        if ProcessInfo.processInfo.arguments.contains("--paper-preview-job-invoice-signed") {
            primary.customerAuthorization = .init(id: "00000000-0000-4000-8000-000000009501", signerName: "Preview customer",
                signedAt: "2026-10-27T12:00:00Z", imageMediaId: "00000000-0000-4000-8000-000000009502", linesRevision: primary.linesRevision)
        }
        if isJobDocumentsPreview && ProcessInfo.processInfo.arguments.contains("--paper-preview-job-invoice-zero") {
            primary = changed(primary, ["lines": [], "amountPaid": 0])
        }
        if isJobDocumentsPreview && ProcessInfo.processInfo.arguments.contains("--paper-preview-job-invoice-draft") {
            primary = changed(primary, ["status": "draft"])
        }
        if isJobDocumentsPreview && ProcessInfo.processInfo.arguments.contains("--paper-preview-job-invoice-void") {
            primary = changed(primary, ["status": "void"])
        }
        let original = primary
        if isJobDocumentsMoneyPreview {
            let discount = FieldLine(id: "00000000-0000-4000-8000-000000009104", description: "Member discount", quantity: 1,
                                     unitPrice: FieldMoney(amount: -4_000, currency: "USD"), source: nil)
            primary = changed(primary, ["lines": try! JSONSerialization.jsonObject(with: JSONEncoder().encode(primary.lines + [discount])),
                                        "amountPaid": 15_000])
        }
        if isJobDocumentsPreview, ProcessInfo.processInfo.arguments.contains("--paper-preview-job-invoice-mixed-currency"),
           var lines = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(primary.lines)) as? [[String: Any]],
           !lines.isEmpty, var price = lines[0]["unitPrice"] as? [String: Any] {
            price["currency"] = "EUR"
            lines[0]["unitPrice"] = price
            primary = changed(primary, ["lines": lines])
        }
        let equalBalances = ProcessInfo.processInfo.arguments.contains("--paper-preview-job-invoices-equal-balances")
        return [primary,
         changed(original, ["id": ProcessInfo.processInfo.arguments.contains("--paper-preview-job-invoice-reference-collision")
                            ? "00000000-0000-4000-8000-000000012209" : "00000000-0000-4000-8000-000000002240",
                           "status": equalBalances ? "issued" : "paid", "origin": "estimate_deposit",
                           "amountPaid": equalBalances ? 0 : 34000, "createdAt": "2026-10-27T12:00:00Z",
                           "paidAt": equalBalances ? NSNull() : "2026-10-27T12:05:00Z"]),
         changed(issuedInvoice, ["id": "00000000-0000-4000-8000-000000002241", "jobId": "00000000-0000-4000-8000-000000002215"])]
    }
    static var jobDocumentMoneyPayments: [FieldPaymentRecord] {
        let card = changed(refundPayment, ["id": "00000000-0000-4000-8000-000000002250", "invoiceId": issuedInvoice.id,
            "amount": ["amount": 15_000, "currency": "USD"], "status": "recorded",
            "idempotencyKey": "paper-preview-job-card", "recordedAt": "2026-10-27T12:00:00Z",
            "refundedAmount": 5_000, "netAmount": ["amount": 10_000, "currency": "USD"], "refundedAt": "2026-10-28T12:00:00Z"])
        let cash = changed(refundPayment, ["id": "00000000-0000-4000-8000-000000002251", "invoiceId": issuedInvoice.id,
            "amount": ["amount": 5_000, "currency": "USD"], "method": "cash", "status": "recorded",
            "idempotencyKey": "paper-preview-job-cash", "recordedAt": "2026-10-28T13:00:00Z",
            "netAmount": ["amount": 5_000, "currency": "USD"]])
        if ProcessInfo.processInfo.arguments.contains("--paper-preview-job-payments-many") {
            let firstCash = changed(cash, ["amount": ["amount": 2_500, "currency": "USD"],
                                           "netAmount": ["amount": 2_500, "currency": "USD"]])
            let secondCash = changed(firstCash, ["id": "00000000-0000-4000-8000-000000002252",
                                                 "idempotencyKey": "paper-preview-job-cash-second"])
            return [card, firstCash, secondCash]
        }
        return [card, cash]
    }
    private static func changed<T: Codable>(_ value: T, _ fields: [String: Any]) -> T {
        var object = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
        fields.forEach { object[$0.key] = $0.value }
        return try! JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object))
    }
    /// Synthetic long lists for catalog-entry navigation checks; no writes or real records.
    private static func longCatalogLines(offset: Int = 0) -> [FieldLine] {
        let count = ProcessInfo.processInfo.arguments.contains("--paper-preview-max-catalog-sections") ? 500 : 12
        return (0..<count).map { index in
            FieldLine(id: String(format: "00000000-0000-4000-8000-%012d", 88000 + offset + index),
                      description: "Sample work item \(index + 1)", quantity: 1,
                      unitPrice: FieldMoney(amount: offset > 0 && ProcessInfo.processInfo.arguments.contains("--paper-preview-large-option-range") ? 9_999_999 : 1000, currency: "USD"), source: nil)
        }
    }
    /// `job-history`: the job is at the customer's Home, with past visits there and its equipment.
    /// `job-history-empty`: nothing on file for the place, so the section stays hidden.
    static var isPropertyHistoryPreview: Bool { enabled && screen == "job-history" }
    /// The customer page's Jobs / Money segments read the same compiled records as Records did.
    static var isCustomerRecordsPreview: Bool { ["customer-records", "customer-jobs", "customer-money"].contains(screen) }
    static var isEmptyPropertyHistoryPreview: Bool { enabled && screen == "job-history-empty" }
    static let homeLocationID = "00000000-0000-4000-8000-000000007001"
    static var isWorkingJobPreview: Bool { enabled && ProcessInfo.processInfo.arguments.contains("--paper-preview-working-job") }
    /// `job`, `job-onsite`, `job-activity`: the redesigned job screen, at its Home site with photos.
    static var isJobScreenPreview: Bool { enabled && ["job", "job-onsite", "job-activity"].contains(screen) }
    static var isPaymentCollectionPreview: Bool {
        screen == "invoice-payment" || screen == "job-invoice" || isWorkingJobPreview ||
        (enabled && screen == "invoice-detail" && (ProcessInfo.processInfo.arguments.contains("--paper-preview-invoice-overflow") ||
                                        ProcessInfo.processInfo.arguments.contains("--paper-preview-invoice-collection-authorized")))
    }
    static var paymentLinkPreview: FieldInvoicePayLink? {
        let args = ProcessInfo.processInfo.arguments
        guard enabled, screen == "invoice-payment",
              let index = args.firstIndex(of: "--paper-preview-pay-link"), args.indices.contains(index + 1),
              ["ready", "expired"].contains(args[index + 1]) else { return nil }
        let offset: TimeInterval = args[index + 1] == "expired" ? -60 : 86_400
        return .init(url: "https://pay.example.invalid/preview-invoice",
                     expiresAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(offset)))
    }
    static var isPaymentRefundPreview: Bool {
        ["invoice-payment-refund", "invoice-payment-refund-form", "invoice-payment-refund-confirmation", "invoice-payment-refund-pending", "invoice-payment-refund-reconciliation"].contains(screen)
    }
    static var invoiceDetailPreviewID: String {
        isPaymentRefundPreview ? refundInvoice.id : issuedInvoice.id
    }
    static var estimate: EstimateRecord {
        let json = #"{"id":"00000000-0000-4000-8000-000000002218","organizationId":"00000000-0000-4000-8000-000000000002","customerId":"00000000-0000-4000-8000-000000000412","createdByUserId":"00000000-0000-4000-8000-000000000001","status":"sent","currentRevisionNumber":2,"title":"AC repair and compressor replacement","lines":[{"id":"00000000-0000-4000-8000-000000009211","description":"Compressor diagnostic","quantity":1,"unitPrice":{"amount":12000,"currency":"USD"},"source":{"kind":"manual","addedByUserId":"00000000-0000-4000-8000-000000000001","capturedAt":"2026-07-18T12:00:00Z"}},{"id":"00000000-0000-4000-8000-000000009212","description":"Replace compressor","quantity":1,"unitPrice":{"amount":85000,"currency":"USD"},"source":{"kind":"price_book","priceBookItemId":"00000000-0000-4000-8000-000000009201","priceBookRevision":4,"originalDescription":"Replace compressor","originalUnitPrice":{"amount":85000,"currency":"USD"},"addedByUserId":"00000000-0000-4000-8000-000000000001","capturedAt":"2026-07-18T12:00:00Z","overriddenFields":[]}}],"options":[{"id":"00000000-0000-4000-8000-000000009213","title":"Full system replacement","description":"Includes new compressor and efficiency inspection","lines":[{"id":"00000000-0000-4000-8000-000000009214","description":"System replacement","quantity":1,"unitPrice":{"amount":225000,"currency":"USD"},"source":{"kind":"manual","addedByUserId":"00000000-0000-4000-8000-000000000001","capturedAt":"2026-07-18T12:00:00Z"}}],"totalAmount":225000,"currency":"USD"}],"createdAt":"2026-07-18T12:00:00Z","updatedAt":"2026-07-20T12:00:00Z","sentAt":"2026-07-20T12:00:00Z"}"#
        let record = try! JSONDecoder().decode(EstimateRecord.self, from: Data(json.utf8))
        guard (ProcessInfo.processInfo.arguments.contains("--paper-preview-long-catalog-sections") ||
               ProcessInfo.processInfo.arguments.contains("--paper-preview-max-catalog-sections")),
              let option = record.options?.first else { return record }
        let lines = longCatalogLines()
        let extended = FieldEstimateOption(id: option.id, title: option.title, description: option.description,
                                           lines: lines, totalAmount: lines.count * 1000, currency: "USD")
        let otherLines = longCatalogLines(offset: 1000)
        let second = FieldEstimateOption(id: "00000000-0000-4000-8000-000000000103", title: "Second system option",
                                         description: "Another sample option.", lines: otherLines,
                                         totalAmount: otherLines.count * 1000, currency: "USD")
        let options = try! JSONSerialization.jsonObject(with: JSONEncoder().encode([extended, second]))
        return changed(record, ["options": options])
    }
    /// Never-issued draft of the sample estimate, so the editor can be screenshotted before it is sent.
    static var draftEstimate: EstimateRecord {
        EstimateRecord(id: estimate.id, organizationId: estimate.organizationId, customerId: estimate.customerId,
                       createdByUserId: estimate.createdByUserId, locationId: estimate.locationId, status: "draft",
                       currentRevisionNumber: nil, title: estimate.title, lines: estimate.lines, options: estimate.options,
                       createdAt: estimate.createdAt, updatedAt: estimate.updatedAt, sentAt: nil, approvedAt: nil, declinedAt: nil)
    }
    /// Good / better / best for the customer presentation screenshots.
    static var optionsEstimate: EstimateRecord {
        // `list` marks a price book line the server member-priced, so the savings row shows.
        func line(_ id: Int, _ text: String, _ quantity: Int, _ cents: Int, list: Int? = nil) -> FieldLine {
            FieldLine(id: String(format: "00000000-0000-4000-8000-0000000093%02d", id), description: text, quantity: quantity,
                      unitPrice: FieldMoney(amount: cents, currency: "USD"),
                      source: list.map { FieldLineSource(kind: "price_book", originalUnitPrice: FieldMoney(amount: $0, currency: "USD")) })
        }
        func option(_ id: Int, _ title: String, _ text: String, _ lines: [FieldLine]) -> FieldEstimateOption {
            FieldEstimateOption(id: String(format: "00000000-0000-4000-8000-0000000094%02d", id), title: title, description: text, lines: lines,
                                totalAmount: paperLinesTotal(lines) ?? 0, currency: "USD")
        }
        // Each line is one description of up to 200 characters, written the way a tech explains it.
        let repair = [line(1, "Run capacitor, 45/5 µF. The part that helps the compressor and fan start. Yours tested well below its rating.", 1, 14_500),
                      line(2, "Coil cleaning. Clean the outdoor and indoor coils so the system moves heat efficiently.", 2, 12_000),
                      line(3, "Labor, licensed technician. Install, test and clean up, with a one-year labor warranty.", 1, 9_500)]
        let better = repair + [line(4, "Surge protector, installed at the outdoor disconnect so a power spike can't take out the new parts.", 1, 39_500, list: 43_900),
                               line(5, "One-year parts warranty on everything in this visit.", 1, 151_000)]
        let replace = [line(6, "3-ton high-efficiency condenser matched to your existing furnace and coil.", 1, 690_000, list: 766_700),
                       line(7, "Installation and haul-away of the old unit, permit and an efficiency check after install.", 1, 220_000),
                       line(8, "Ten-year warranty registration with the manufacturer.", 1, 75_000)]
        let repairDescription = ProcessInfo.processInfo.arguments.contains("--paper-preview-option-long-description")
            ? "Replace the failed capacitor and clean the coil. We will protect the work area, check the electrical connections, clean both coils and test the system under normal conditions.\n\nFinal detail: we will explain the results and leave the work area clean."
            : "Replace the failed capacitor and clean the coil."
        return EstimateRecord(id: estimate.id, organizationId: estimate.organizationId, customerId: customerID, createdByUserId: estimate.createdByUserId,
                              locationId: nil, status: "sent", currentRevisionNumber: 2, title: "AC not cooling", lines: [],
                              options: [option(1, "Repair", repairDescription, repair),
                                        option(2, "Repair and protect", "The repair plus a surge protector and a one-year parts warranty.", better),
                                        option(3, "Replace", "A new high-efficiency unit with a ten-year warranty.", replace)],
                              createdAt: estimate.createdAt, updatedAt: estimate.updatedAt, sentAt: estimate.sentAt, approvedAt: nil, declinedAt: nil)
    }
    /// `job-onsite --paper-preview-onsite-done`: every wrap-up row met, the server ready to complete.
    static var onSiteDone: Bool { screen == "job-onsite" && ProcessInfo.processInfo.arguments.contains("--paper-preview-onsite-done") }
    /// The on-site visit's approved repair ($340, the same lines as its invoice).
    static var onSiteEstimate: EstimateRecord {
        let record = estimate
        return EstimateRecord(id: record.id, organizationId: record.organizationId, customerId: record.customerId,
                              createdByUserId: record.createdByUserId, locationId: record.locationId, status: "approved",
                              currentRevisionNumber: record.currentRevisionNumber, title: "Repair", lines: issuedInvoice.lines, options: nil,
                              createdAt: record.createdAt, updatedAt: record.updatedAt, sentAt: record.sentAt,
                              approvedAt: record.sentAt, declinedAt: nil)
    }
    /// The on-site visit's completion invoice: issued and unpaid, or signed and paid when done.
    static var onSiteInvoice: InvoiceRecord {
        var record = issuedInvoice
        guard onSiteDone else { return record }
        let json = #"{"id":"00000000-0000-4000-8000-000000009520","signerName":"Danielle Marlowe","signedAt":"2026-10-31T15:20:00Z","imageMediaId":"00000000-0000-4000-8000-000000009521","linesRevision":3}"#
        record.customerAuthorization = try? JSONDecoder().decode(FieldSignatureRecord.self, from: Data(json.utf8))
        let paid = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as! [String: Any]
        var object = paid
        object["status"] = "paid"
        object["amountPaid"] = 34_000
        object["paidAt"] = "2026-10-31T15:22:00Z"
        return try! JSONDecoder().decode(InvoiceRecord.self, from: JSONSerialization.data(withJSONObject: object))
    }
    static var invoice: InvoiceRecord {
        let json = #"{"id":"00000000-0000-4000-8000-000000002209","organizationId":"00000000-0000-4000-8000-000000000002","customerId":"00000000-0000-4000-8000-000000000412","jobId":"00000000-0000-4000-8000-000000002214","createdByUserId":"00000000-0000-4000-8000-000000000001","locationId":null,"scheduleId":null,"origin":"job_completion","sourceOperationKey":"paper-preview-invoice","sourceEstimateId":null,"sourceEstimateRevisionNumber":null,"manualPhysicalServiceEvidence":null,"status":"draft","lines":[{"id":"00000000-0000-4000-8000-000000009101","description":"Compressor diagnostic","quantity":1,"unitPrice":{"amount":12000,"currency":"USD"},"source":{"kind":"manual"}},{"id":"00000000-0000-4000-8000-000000009102","description":"Refrigerant recharge","quantity":2,"unitPrice":{"amount":9000,"currency":"USD"},"source":{"kind":"manual"}},{"id":"00000000-0000-4000-8000-000000009103","description":"Trip fee","quantity":1,"unitPrice":{"amount":4000,"currency":"USD"},"source":{"kind":"manual"}}],"linesRevision":3,"amountPaid":0,"currency":"USD","issuedAt":null,"paidAt":null,"voidedAt":null,"createdAt":"2026-07-18T12:00:00Z","updatedAt":"2026-07-20T12:00:00Z"}"#
        let record = try! JSONDecoder().decode(InvoiceRecord.self, from: Data(json.utf8))
        guard ProcessInfo.processInfo.arguments.contains("--paper-preview-long-catalog-sections") ||
              ProcessInfo.processInfo.arguments.contains("--paper-preview-max-catalog-sections") else { return record }
        let lines = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(longCatalogLines()))
        return changed(record, ["lines": lines])
    }
    static var issuedInvoice: InvoiceRecord {
        if screen == "invoice-detail", ProcessInfo.processInfo.arguments.contains("--paper-preview-invoice-detail-draft") {
            let draft = invoice
            guard ProcessInfo.processInfo.arguments.contains("--paper-preview-invoice-overflow") else { return draft }
            var lines = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(draft.lines)) as! [[String: Any]]
            lines[0]["quantity"] = 2
            lines[0]["unitPrice"] = ["amount": Int.max, "currency": draft.currency]
            return changed(draft, ["lines": lines])
        }
        let json = #"{"id":"00000000-0000-4000-8000-000000002209","organizationId":"00000000-0000-4000-8000-000000000002","customerId":"00000000-0000-4000-8000-000000000412","jobId":"00000000-0000-4000-8000-000000002214","createdByUserId":"00000000-0000-4000-8000-000000000001","locationId":null,"scheduleId":null,"origin":"job_completion","sourceOperationKey":"paper-preview-invoice","sourceEstimateId":null,"sourceEstimateRevisionNumber":null,"manualPhysicalServiceEvidence":null,"status":"issued","lines":[{"id":"00000000-0000-4000-8000-000000009101","description":"Compressor diagnostic","quantity":1,"unitPrice":{"amount":12000,"currency":"USD"},"source":{"kind":"manual"}},{"id":"00000000-0000-4000-8000-000000009102","description":"Refrigerant recharge","quantity":2,"unitPrice":{"amount":9000,"currency":"USD"},"source":{"kind":"manual"}},{"id":"00000000-0000-4000-8000-000000009103","description":"Trip fee","quantity":1,"unitPrice":{"amount":4000,"currency":"USD"},"source":{"kind":"manual"}}],"linesRevision":3,"amountPaid":0,"currency":"USD","issuedAt":"2026-07-20T12:00:00Z","paidAt":null,"voidedAt":null,"createdAt":"2026-07-20T12:00:00Z","updatedAt":"2026-07-20T12:00:00Z"}"#
        let args = ProcessInfo.processInfo.arguments
        var fixture: String
        if args.contains("--paper-preview-invoice-overflow") {
            fixture = json.replacingOccurrences(of: #""quantity":1,"unitPrice":{"amount":12000"#, with: #""quantity":2,"unitPrice":{"amount":9223372036854775807"#)
        } else if args.contains("--paper-preview-extreme-invoice") {
            fixture = json.replacingOccurrences(of: "\"amount\":12000", with: "\"amount\":999999940000")
        } else if args.contains("--paper-preview-large-invoice") {
            fixture = json.replacingOccurrences(of: "\"amount\":12000", with: "\"amount\":123456789")
        } else { fixture = json }
        if args.contains("--paper-preview-legacy-handoff-test") && !args.contains("--paper-preview-job-linked-invoice") {
            fixture = fixture.replacingOccurrences(of: "\"jobId\":\"00000000-0000-4000-8000-000000002214\"", with: "\"jobId\":null")
        }
        return try! JSONDecoder().decode(InvoiceRecord.self, from: Data(fixture.utf8))
    }
    /// The issued invoice with a condenser replacement on it, inside the lender's range.
    static var financingInvoice: InvoiceRecord {
        let json = String(decoding: try! JSONEncoder().encode(issuedInvoice), as: UTF8.self)
            .replacingOccurrences(of: #""amount":12000"#, with: #""amount":948000"#)
            .replacingOccurrences(of: "Compressor diagnostic", with: "Condenser replacement, 3 ton")
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
        if ProcessInfo.processInfo.arguments.contains("--paper-preview-catalog-partial"),
           let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            // Isolate this preview from an earlier preview's complete sample snapshot.
            let sample = cache.appendingPathComponent("PriceBook", isDirectory: true)
                .appendingPathComponent("\(organizationID.lowercased()).json")
            try? FileManager.default.removeItem(at: sample)
        }
        if ProcessInfo.processInfo.arguments.contains("--paper-preview-catalog-many") {
            UserDefaults.standard.removeObject(forKey: "priceBookUsage.\(organizationID)")
        }
        let api = APIClient(session: transport(), baseURL: "https://app.thorbis.com")
        // Override any launch-environment dev identity; restore must use fixture authority.
        api.auth = .none
        return api
    }
    /// Synthetic pending-media journey. The dedicated preview directory never uses
    /// Application Support or customer captures, and fixture transport rejects writes.
    static var savedWorkSessionID: String? {
        let args = ProcessInfo.processInfo.arguments
        guard enabled, let index = args.firstIndex(of: "--paper-preview-saved-work-session"), args.indices.contains(index + 1),
              let id = UUID(uuidString: args[index + 1]) else { return nil }
        return id.uuidString.lowercased()
    }
    static var isSavedWorkPreview: Bool { savedWorkSessionID != nil }
    static let savedWorkUncachedJobID = "00000000-0000-4000-8000-000000009951"
    @MainActor private static var savedWorkDidReset = false
    static let savedWorkDeadline = Date().addingTimeInterval(12)
    static var showSavedWorkControls: Bool { isSavedWorkPreview && ProcessInfo.processInfo.arguments.contains("--paper-preview-saved-work-controls") }
    @MainActor static func activateSavedWorkScenario(session: SessionController) async {
        guard isSavedWorkPreview, ProcessInfo.processInfo.arguments.contains("--paper-preview-saved-work-offline"),
              PaperPreviewProtocol.beginSavedWorkOffline() else { return }
        await session.revalidate()
    }
    @MainActor private static func savedWorkRoot() -> URL? {
        guard let id = savedWorkSessionID else { return nil }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ThorbisSavedWorkPreview", isDirectory: true).appendingPathComponent(id, isDirectory: true)
        if ProcessInfo.processInfo.arguments.contains("--paper-preview-reset-saved-work"), !savedWorkDidReset {
            try? FileManager.default.removeItem(at: root)
            savedWorkDidReset = true
        }
        return root
    }
    @MainActor static func savedWorkFileHashes() throws -> [String: String] {
        guard let root = savedWorkRoot(), let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return [:] }
        var hashes: [String: String] = [:]
        for case let file as URL in files where try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
            let relative = String(file.path.dropFirst(root.path.count + 1))
            hashes[relative] = SHA256.hash(data: try Data(contentsOf: file)).map { String(format: "%02x", $0) }.joined()
        }
        return hashes
    }
    @MainActor static func outbox() -> FieldOutbox {
        guard let root = savedWorkRoot() else {
            return FieldOutbox(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), defaults: defaults())
        }
        if ProcessInfo.processInfo.arguments.contains("--paper-preview-seed-saved-work") {
            do {
                let folder = root.appendingPathComponent("Outbox", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let entries = [
                    OutboxEntry(id: "00000000-0000-4000-8000-000000009711", deviceId: "00000000-0000-4000-8000-000000009700", actorId: actorID, organizationId: organizationID,
                        policyVersion: 1, createdAt: Date(timeIntervalSince1970: 1_700_000_000), action: .progress(.init(jobId: jobID, to: "arrived")), state: .rejected("This sample visit changed while the phone was offline.")),
                    OutboxEntry(id: "00000000-0000-4000-8000-000000009712", deviceId: "00000000-0000-4000-8000-000000009700", actorId: actorID, organizationId: organizationID,
                        policyVersion: 1, createdAt: Date(timeIntervalSince1970: 1_700_000_060), action: .note(.init(jobId: jobID, body: "Synthetic private note body")), state: .held)
                ]
                try JSONEncoder().encode(entries).write(to: folder.appendingPathComponent("\(actorID)_\(organizationID).json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            } catch { assertionFailure("Synthetic saved-work commands failed: \(error)") }
        }
        let box = FieldOutbox(directory: root, defaults: defaults()); box.bind(actorID: actorID, organizationID: organizationID)
        return box
    }

    @MainActor static func mediaStore() -> PendingMediaStore {
        let root = savedWorkRoot() ?? FileManager.default.temporaryDirectory.appendingPathComponent("ThorbisPreviewMedia", isDirectory: true)
        let args = ProcessInfo.processInfo.arguments
        if !isSavedWorkPreview, args.contains("--paper-preview-reset-media") { try? FileManager.default.removeItem(at: root) }
        let store = PendingMediaStore(directory: root)
        if isSavedWorkPreview {
            store.bind(PendingMediaScope(actorID: actorID, organizationID: organizationID, origin: "https://app.thorbis.com"))
            if args.contains("--paper-preview-seed-saved-work") {
                let photo = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).image { context in
                    UIColor.gray.setFill(); context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
                }.jpegData(compressionQuality: 0.8)!
                let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { context in
                    context.beginPage(); ("Synthetic saved-work scan" as NSString).draw(at: CGPoint(x: 30, y: 30), withAttributes: [.font: UIFont.systemFont(ofSize: 18)])
                }
                let samples: [(String, String, String, String, String, Data)] = [
                    ("00000000-0000-4000-8000-000000009701", jobID, "before.jpg", "photo", "image/jpeg", photo),
                    ("00000000-0000-4000-8000-000000009702", savedWorkUncachedJobID, "Field scan.pdf", "document", "application/pdf", pdf)
                ]
                do {
                    guard let context = store.captureContext else { return store }
                    for (id, job, name, kind, mime, data) in samples {
                        try store.save(.init(id: id, jobID: job, filename: name, tags: kind == "photo" ? ["Before"] : [],
                            capturedAt: Date(timeIntervalSince1970: 1_700_000_120), kind: kind, mime: mime), data: data, context: context)
                    }
                    store.bind(.init(actorID: "00000000-0000-4000-8000-000000000099", organizationID: organizationID, origin: "https://app.thorbis.com"))
                    if let foreign = store.captureContext {
                        try store.save(.init(id: "00000000-0000-4000-8000-000000009799", jobID: jobID, filename: "Foreign actor scan.pdf", tags: [],
                            capturedAt: Date(timeIntervalSince1970: 1_700_000_120), kind: "document", mime: "application/pdf"), data: pdf, context: foreign)
                    }
                    store.bind(.init(actorID: actorID, organizationID: organizationID, origin: "https://app.thorbis.com"))
                } catch { assertionFailure("Synthetic saved-work media failed: \(error)") }
            }
        }
        if args.contains("--paper-preview-seed-media") {
            store.bind(PendingMediaScope(actorID: actorID, organizationID: organizationID, origin: "https://app.thorbis.com"))
            let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { context in
                context.beginPage()
                ("Synthetic field scan" as NSString).draw(at: CGPoint(x: 30, y: 30), withAttributes: [.font: UIFont.systemFont(ofSize: 18)])
            }
            for (id, job, filename) in [
                ("00000000-0000-4000-8000-000000009701", jobID, "Field scan.pdf"),
                ("00000000-0000-4000-8000-000000009702", "00000000-0000-4000-8000-000000002215", "Other job scan.pdf")
            ] {
                let media = PendingMedia(id: id, jobID: job, filename: filename, tags: [],
                    capturedAt: Date(timeIntervalSince1970: 1_700_000_000), kind: "document", mime: "application/pdf")
                do {
                    guard let context = store.captureContext else { assertionFailure("Synthetic media context unavailable"); return store }
                    try store.save(media, data: pdf, context: context)
                }
                catch { assertionFailure("Synthetic media fixture could not be saved: \(error)") }
            }
        }
        if args.contains("--paper-preview-media-waiting") {
            // Media redesign screenshots: photos saved on this phone, not yet sent (labelled SAMPLE).
            store.bind(PendingMediaScope(actorID: actorID, organizationID: organizationID, origin: "https://app.thorbis.com"))
            do {
                guard let context = store.captureContext else { return store }
                for (number, sample) in [("New valve, close up", ["After"]), ("Burst shot 1", [String]()), ("Burst shot 2", [String]())].enumerated() {
                    let id = String(format: "00000000-0000-4000-8000-%012d", 9881 + number)
                    if store.items.contains(where: { $0.id == id }) { continue }
                    let data = MediaSample.image(caption: sample.0, tags: sample.1).jpegData(compressionQuality: 0.8)!
                    try store.save(.init(id: id, jobID: jobID, filename: "sample-pending-\(number + 1).jpg", tags: sample.1,
                                         capturedAt: Date().addingTimeInterval(Double(number - 3) * 60), kind: "photo", mime: "image/jpeg",
                                         caption: sample.0), data: data, context: context)
                }
            } catch { assertionFailure("Synthetic waiting media failed: \(error)") }
        }
        if args.contains("--paper-preview-many-pending") {
            store.bind(PendingMediaScope(actorID: actorID, organizationID: organizationID, origin: "https://app.thorbis.com"))
            let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 100, height: 100)).pdfData { $0.beginPage() }
            do {
                guard let context = store.captureContext else { return store }
                for number in 0..<20 {
                    let id = String(format: "00000000-0000-4000-8000-%012d", 9800 + number)
                    try store.save(.init(id: id, jobID: jobID, filename: "Pending scan \(number + 1).pdf", tags: [],
                                         capturedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(number)),
                                         kind: "document", mime: "application/pdf"), data: pdf, context: context)
                }
            } catch { assertionFailure("Synthetic pending media failed: \(error)") }
        }
        if args.contains("--paper-preview-seed-legacy") {
            do {
                let folder = root.appendingPathComponent("PendingPhotos")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let jpeg = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).image { context in
                    UIColor.gray.setFill(); context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
                }.jpegData(compressionQuality: 0.8)!
                for (id, job) in [("00000000-0000-4000-8000-000000009703", jobID), ("00000000-0000-4000-8000-000000009704", "00000000-0000-4000-8000-000000002215")] {
                    let metadata = try JSONSerialization.data(withJSONObject: ["id": id, "jobID": job, "filename": "before-original.jpg", "tags": ["Before"], "takenAt": Date(timeIntervalSince1970: 1_700_000_000).timeIntervalSinceReferenceDate])
                    try metadata.write(to: folder.appendingPathComponent("\(id).json"))
                    try jpeg.write(to: folder.appendingPathComponent("\(id).jpg"))
                }
            } catch { assertionFailure("Synthetic legacy fixture failed: \(error)") }
        }
        if args.contains("--paper-preview-media-cleanup-failure") {
            do {
                store.bind(PendingMediaScope(actorID: actorID, organizationID: organizationID, origin: "https://app.thorbis.com"))
                let item = PendingMedia(id: UUID().uuidString, jobID: jobID, filename: "synthetic.jpg", tags: [], capturedAt: Date(), kind: "photo", mime: "image/jpeg")
                if let context = store.captureContext { try store.save(item, data: Data([1]), context: context) }
                try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
                store.clearAll(); store.bind(nil)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
            } catch { assertionFailure("Synthetic cleanup fixture failed: \(error)") }
        }
        return store
    }

    static func defaults() -> UserDefaults {
        UserDefaults(suiteName: "thorbis.paper-preview.\(UUID().uuidString)")!
    }
    static func handoffStorageTransport() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PaperPreviewProtocol.self]
        return URLSession(configuration: configuration)
    }
    static func transport() -> URLSession {
        PaperPreviewProtocol.resetScenario()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PaperPreviewProtocol.self]
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }
    /// `--paper-preview-scroll center|bottom`: where scroll views open, for capturing a long screen's lower sections.
    static var scrollAnchor: UnitPoint? {
        let args = ProcessInfo.processInfo.arguments
        guard enabled, let index = args.firstIndex(of: "--paper-preview-scroll"), args.indices.contains(index + 1) else { return nil }
        switch args[index + 1] {
        case "center": return .center
        case "bottom": return .bottom
        default: return nil
        }
    }

    @MainActor static var banner: some View {
        Text(isJobEstimateHandoff ? "LOCAL TEST · SAMPLE APPROVALS ONLY" : "DESIGN PREVIEW · SAMPLE DATA · READ ONLY")
            .font(.system(size: 9, weight: .semibold)).tracking(0.4)
            .foregroundStyle(Color.orange).frame(maxWidth: .infinity).padding(.vertical, 3)
            .background(Color.black)
            .accessibilityLabel("Design preview. Sample data. Read only. No network connection.")
    }

    @MainActor static var reviewConnectionControl: some View {
        Button("Restore sample connection") { PaperPreviewProtocol.restoreReviewConnection() }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Color.orange)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Color.black)
            .buttonStyle(.plain)
    }
}

/// Applies `PaperPreview.scrollAnchor` only when asked, so every other preview keeps each screen's own anchor.
struct PaperPreviewScrollAnchor: ViewModifier {
    func body(content: Content) -> some View {
        if let anchor = PaperPreview.scrollAnchor { content.defaultScrollAnchor(anchor) } else { content }
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

struct PaperPreviewConnectionMenu: View {
    var body: some View {
        Menu("Sample connection") {
            Button("Make sample estimate unavailable") { PaperPreviewProtocol.makeSampleEstimateUnavailable() }
            Button("Restore sample connection") { PaperPreviewProtocol.restoreReviewConnection() }
            if ProcessInfo.processInfo.arguments.contains("--paper-preview-documents-status-change") {
                Button("Change sample document statuses") { PaperPreviewProtocol.changeSampleDocumentStatuses() }
            }
        }
        .font(.system(size: 17, weight: .medium))
        .foregroundStyle(Color.orange)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(Color.black)
    }
}

/// Explicit sample-only server/network stimuli; all traffic remains intercepted.
struct SavedWorkPreviewControls: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var outbox: FieldOutbox
    @EnvironmentObject private var media: PendingMediaStore
    @State private var revocationProof: String?
    var body: some View {
        DisclosureGroup("Sample controls") {
            Button("Revoke sample editing shortly") {
                let scope = SavedWorkScope.capture(session: session, api: api, media: media, outbox: outbox)
                let actor = session.user?.id, organization = session.activeOrganization?.id
                let before = try? PaperPreview.savedWorkFileHashes()
                let mutations = PaperPreviewProtocol.savedWorkMutationCount
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { return }
                    PaperPreviewProtocol.revokeSavedWorkEditing()
                    await session.revalidate()
                    let proof: [String: Any] = [
                        "filesBefore": before ?? [:], "filesAfter": (try? PaperPreview.savedWorkFileHashes()) ?? [:],
                        "mutationsBefore": mutations, "mutationsAfter": PaperPreviewProtocol.savedWorkMutationCount,
                        "sameActor": session.user?.id == actor, "sameWorkspace": session.activeOrganization?.id == organization,
                        "viewScopeStillCurrent": scope?.isCurrent(session: session, api: api, media: media, outbox: outbox) == true,
                        "canEdit": scope?.canEdit(session: session, api: api, media: media, outbox: outbox) == true
                    ]
                    revocationProof = (try? JSONSerialization.data(withJSONObject: proof, options: [.sortedKeys])).flatMap { String(data: $0, encoding: .utf8) }
                }
            }.frame(minHeight: 44)
            if let revocationProof {
                Text("Sample revocation evidence").accessibilityIdentifier("saved-work-edit-revocation-proof").accessibilityValue(revocationProof)
            }
            Button("Rebind sample commands") {
                outbox.bind(actorID: "00000000-0000-4000-8000-000000000099", organizationID: PaperPreview.organizationID)
                outbox.bind(actorID: PaperPreview.actorID, organizationID: PaperPreview.organizationID)
            }.frame(minHeight: 44)
            Button("Retire sample requests") { api.invalidateRequests() }.frame(minHeight: 44)
            Button("Switch sample workspace shortly") {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { return }
                    PaperPreviewProtocol.switchSavedWorkWorkspace()
                    await session.revalidate()
                }
            }.frame(minHeight: 44)
        }.font(Theme.font(13))
    }
}

final class PaperPreviewProtocol: URLProtocol, @unchecked Sendable {
    private final class Scenario: @unchecked Sendable {
        let lock = NSLock()
        var setupPaymentReads = 0
        var documentHistoryRestored = false
        var failPaymentRecheck = false
        var paymentPermissionRevoked = false
        var invoiceReads = 0
        var overviewInvoiceListReads = 0
        var reviewConnectionRestored = false
        var ownerAuthenticated = false
        var estimateUnavailable = false
        var documentStatusesChanged = false
        var completionCreates = 0
        var completionCreated = false
        var completionViewRevoked = false
        var savedWorkOffline = false
        var savedWorkWorkspaceChanged = false
        var savedWorkEditingRevoked = false
        var priceBookViewRevoked = false
        var documentEstimateViewRevoked = false
        var invoiceEditRevoked = false
        var jobMediaViewRevoked = false
        var priceBookReads = 0
        var priceBookQueryFailed = false
        var savedWorkMutationCount = 0
        var answeredListPaths: Set<String> = []
    }
    private static let scenario = Scenario()
    static func resetScenario() {
        if PaperPreview.isJobEstimateHandoff { JobEstimateHandoffPreview.shared.reset() }
        scenario.lock.withLock { scenario.setupPaymentReads = 0; scenario.documentHistoryRestored = false; scenario.failPaymentRecheck = false; scenario.paymentPermissionRevoked = false; scenario.invoiceReads = 0; scenario.overviewInvoiceListReads = 0; scenario.reviewConnectionRestored = false; scenario.ownerAuthenticated = false; scenario.estimateUnavailable = false; scenario.documentStatusesChanged = false; scenario.completionCreates = 0; scenario.completionCreated = false; scenario.completionViewRevoked = false; scenario.savedWorkOffline = false; scenario.savedWorkWorkspaceChanged = false; scenario.savedWorkEditingRevoked = false; scenario.priceBookViewRevoked = false; scenario.documentEstimateViewRevoked = false; scenario.invoiceEditRevoked = false; scenario.jobMediaViewRevoked = false; scenario.priceBookReads = 0; scenario.priceBookQueryFailed = false; scenario.savedWorkMutationCount = 0 }
    }
    static var sampleCompletionCreates: Int { scenario.lock.withLock { scenario.completionCreates } }
    static func revokeInvoiceViewForCreate() { scenario.lock.withLock { scenario.completionViewRevoked = true } }
    static func beginSavedWorkOffline() -> Bool {
        scenario.lock.withLock {
            guard !scenario.savedWorkOffline else { return false }
            scenario.savedWorkOffline = true; return true
        }
    }
    static var savedWorkMutationCount: Int { scenario.lock.withLock { scenario.savedWorkMutationCount } }
    static func revokePaymentPermission() { scenario.lock.withLock { scenario.paymentPermissionRevoked = true } }
    static func restoreDocumentHistory() { scenario.lock.withLock { scenario.documentHistoryRestored = true } }
    static func failDocumentPaymentRecheck() { scenario.lock.withLock { scenario.failPaymentRecheck = true } }
    static func revokeSavedWorkEditing() { scenario.lock.withLock { scenario.savedWorkEditingRevoked = true } }
    static func revokeDocumentEstimateView() { scenario.lock.withLock { scenario.documentEstimateViewRevoked = true } }
    static func revokeInvoiceEditForSigning() { scenario.lock.withLock { scenario.invoiceEditRevoked = true } }
    static func revokeJobMediaView() { scenario.lock.withLock { scenario.jobMediaViewRevoked = true } }
    static func revokePriceBookView() { scenario.lock.withLock { scenario.priceBookViewRevoked = true } }
    static func failPriceBookQuery() { scenario.lock.withLock { scenario.priceBookQueryFailed = true } }
    static func switchSavedWorkWorkspace() {
        scenario.lock.withLock { scenario.savedWorkOffline = false; scenario.savedWorkWorkspaceChanged = true }
    }
    static func markOwnerAuthenticated() { scenario.lock.withLock { scenario.ownerAuthenticated = true } }
    static func makeSampleEstimateUnavailable() {
        scenario.lock.withLock { scenario.estimateUnavailable = true }
    }
    static func changeSampleDocumentStatuses() {
        scenario.lock.withLock { scenario.documentStatusesChanged = true }
    }
    static func restoreReviewConnection() {
        scenario.lock.withLock { scenario.reviewConnectionRestored = true; scenario.estimateUnavailable = false }
    }
    private static func legacyInvoiceRead(_ path: String) -> Bool {
        guard PaperPreview.isJobDocumentsPreview,
              ProcessInfo.processInfo.arguments.contains("--paper-preview-job-invoices-legacy"),
              path == "/v1/jobs/\(PaperPreview.jobID)/invoices" else { return false }
        return scenario.lock.withLock { scenario.invoiceReads += 1; return scenario.invoiceReads > 1 }
    }
    /// The "offline" preview flips this after sign-in so every later request has no signal.
    nonisolated(unsafe) static var simulateNoSignal = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if let preview = EstimateRecoveryPreview.shared.reply(for: request), let url = request.url,
           let response = HTTPURLResponse(url: url, statusCode: preview.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]) {
            let deliver: @Sendable () -> Void = { [weak self] in
                guard let self else { return }
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                if let body = try? JSONSerialization.data(withJSONObject: preview.payload) { self.client?.urlProtocol(self, didLoad: body) }
                self.client?.urlProtocolDidFinishLoading(self)
            }
            if preview.hold { EstimateRecoveryPreview.shared.hold(deliver) } else { deliver() }
            return
        }
        if PaperPreview.isJobEstimateHandoff, let response = JobEstimateHandoffPreview.shared.response(request) {
            if let error = response.error { client?.urlProtocol(self, didFailWithError: error); return }
            guard let url = request.url, let http = HTTPURLResponse(url: url, statusCode: response.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type":"application/json"]) else { return }
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            if let body = try? JSONSerialization.data(withJSONObject: response.payload, options: [.sortedKeys, .fragmentsAllowed]) { client?.urlProtocol(self, didLoad: body) }
            client?.urlProtocolDidFinishLoading(self); return
        }
        if PaperPreview.isSavedWorkPreview, !["GET", "HEAD"].contains(request.httpMethod ?? "GET") {
            Self.scenario.lock.withLock { Self.scenario.savedWorkMutationCount += 1 }
        }
        if Self.simulateNoSignal || Self.scenario.lock.withLock({ Self.scenario.savedWorkOffline }) {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        guard let url = request.url else { client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return }
        // Keep the second catalog page pending to exercise honest partial search states.
        if PaperPreview.enabled, PaperPreview.screen == "invoice-editor",
           ProcessInfo.processInfo.arguments.contains("--paper-preview-catalog-partial"), url.path == "/v1/query",
           let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
           query.contains(where: { $0.name == "resourceId" && $0.value == "price_book_items" }),
           query.contains(where: { $0.name == "cursor" }) {
            return
        }
        // Left unanswered on purpose: the screen keeps showing what it draws while it waits.
        if PaperPreview.enabled, let held = PaperPreview.heldPath, url.path == held { return }
        // `--paper-preview-payment-timeout`: recording a payment times out, so Collect payment shows its pending state.
        if PaperPreview.enabled, request.httpMethod == "POST", url.path.hasSuffix("/payments"),
           ProcessInfo.processInfo.arguments.contains("--paper-preview-payment-timeout") {
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut)); return
        }
        if PaperPreview.holdsLists, PaperPreview.heldListPaths.contains(url.path) {
            let firstRead = PaperPreview.holdsAfterFirst && Self.scenario.lock.withLock { Self.scenario.answeredListPaths.insert(url.path).inserted }
            if !firstRead { return }
        }
        if PaperPreview.screen == "customer-records",
           ProcessInfo.processInfo.arguments.contains("--paper-preview-mixed-photo-rollup"),
           request.httpMethod == "GET",
           ["/v1/jobs/00000000-0000-4000-8000-000000002214/photos/00000000-0000-4000-8000-000000033000",
            "/v1/jobs/00000000-0000-4000-8000-000000002201/photos/00000000-0000-4000-8000-000000033001"].contains(url.path),
           let data = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGOwb9kCRAwQCgAnPgXdEEuqSQAAAABJRU5ErkJggg=="),
           let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                          headerFields: ["Content-Type": "image/png", "Content-Length": "\(data.count)"]) {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let status: Int
        let payload: Any
        if PaperPreview.isJobDocumentsPreview,
           ProcessInfo.processInfo.arguments.contains("--paper-preview-create-invoice"),
           request.httpMethod == "POST", url.path == "/v1/jobs/\(PaperPreview.jobID)/completion-invoice" {
            let foreign = ProcessInfo.processInfo.arguments.contains("--paper-preview-create-invoice-foreign")
            let failed = ProcessInfo.processInfo.arguments.contains("--paper-preview-create-invoice-failure")
            Self.scenario.lock.withLock { Self.scenario.completionCreates += 1; Self.scenario.completionCreated = !foreign && !failed }
            if failed {
                status = 503
                payload = ["status": 503, "title": "Sample invoice could not be created"]
            } else {
                var draft = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(PaperPreview.invoice)) as! [String: Any]
                if foreign { draft["jobId"] = "00000000-0000-4000-8000-000000002215" }
                status = 200
                payload = draft
            }
        } else if request.httpMethod != nil && request.httpMethod != "GET" {
            status = 405
            payload = ["status": 405, "title": "Design preview is read-only", "detail": "Sample data cannot be changed. No request was sent to a server."]
        } else if PaperPreview.screen.hasPrefix("present-estimate"),
                  url.path == "/v1/estimates/\(PaperPreview.estimate.id)",
                  ProcessInfo.processInfo.arguments.contains("--paper-preview-review-pending") {
            // A deliberately unresolved read for the native opening-state journey.
            return
        } else if PaperPreview.screen.hasPrefix("present-estimate"),
                  url.path == "/v1/estimates/\(PaperPreview.estimate.id)",
                  ProcessInfo.processInfo.arguments.contains("--paper-preview-review-failure"),
                  Self.scenario.lock.withLock({ !Self.scenario.reviewConnectionRestored }) {
            status = 503
            payload = ["status": 503, "title": "The estimate could not be opened. Try again."]
        } else if PaperPreview.isJobDocumentsPreview,
                  ProcessInfo.processInfo.arguments.contains("--paper-preview-overview-amount-fails-once"),
                  url.path == "/v1/invoices/00000000-0000-4000-8000-000000002209/customer-presentation",
                  Self.scenario.lock.withLock({ !Self.scenario.documentHistoryRestored }) {
            status = 503
            payload = ["status": 503, "title": "Sample invoice amount unavailable"]
        } else if PaperPreview.isJobDocumentsPreview,
                  url.path.hasPrefix("/v1/invoices/"), url.path.hasSuffix("/payments"),
                  Self.scenario.lock.withLock({ Self.scenario.failPaymentRecheck }) {
            status = 503
            payload = ["status": 503, "title": "Sample payment history unavailable"]
        } else if PaperPreview.isJobDocumentsPreview,
                  ProcessInfo.processInfo.arguments.contains("--paper-preview-job-history-fail-once"),
                  url.path == "/v1/invoices/00000000-0000-4000-8000-000000002240/payments",
                  Self.scenario.lock.withLock({ !Self.scenario.documentHistoryRestored }) {
            status = 503
            payload = ["status": 503, "title": "Sample payment history unavailable"]
        } else if PaperPreview.isJobDocumentsPreview,
                  ProcessInfo.processInfo.arguments.contains("--paper-preview-deposit-history-failure"),
                  url.path == "/v1/invoices/00000000-0000-4000-8000-000000002240/payments" {
            status = 503
            payload = ["status": 503, "title": "Sample payment history unavailable"]
        } else if PaperPreview.isJobDocumentsPreview,
                  ProcessInfo.processInfo.arguments.contains("--paper-preview-summary-fails-after-payment-retry"),
                  url.path == "/v1/invoices/00000000-0000-4000-8000-000000002240/customer-presentation",
                  Self.scenario.lock.withLock({ Self.scenario.documentHistoryRestored }) {
            status = 503
            payload = ["status": 503, "title": "Sample invoice amount unavailable"]
        } else if PaperPreview.isJobEstimateRecoveryPreview,
                  url.path == "/v1/estimates/\(PaperPreview.estimate.id)",
                  Self.scenario.lock.withLock({ Self.scenario.estimateUnavailable }) {
            status = 503
            payload = ["status": 503, "title": "Sample estimate connection unavailable"]
        } else if PaperPreview.screen == "price-book", url.path == "/v1/query",
                  Self.scenario.lock.withLock({ Self.scenario.priceBookQueryFailed }) {
            status = 503
            payload = ["status": 503, "title": "The price book couldn't be loaded."]
        } else if PaperPreview.onboardingScreen == "onboard-setup",
                  ProcessInfo.processInfo.arguments.contains("--paper-preview-setup-retry"),
                  url.path == "/v1/organization/merchant-readiness",
                  Self.scenario.lock.withLock({ Self.scenario.setupPaymentReads += 1; return Self.scenario.setupPaymentReads == 1 }) {
            status = 503
            payload = ["status": 503, "title": "Sample setup status unavailable"]
        } else if Self.legacyInvoiceRead(url.path) {
            status = 404
            payload = ["status": 404, "title": "Preview legacy job invoice route"]
        } else if PaperPreview.isJobDocumentsPreview,
                  ProcessInfo.processInfo.arguments.contains("--paper-preview-job-documents-partial"),
                  url.path == "/v1/estimates/00000000-0000-4000-8000-000000002238" {
            status = 503
            payload = ["status": 503, "title": "Preview estimate unavailable"]
        } else if url.scheme == "https", url.host == "app.thorbis.com", url.path == "/v1/financing/offer" {
            status = 200
            payload = Self.financingOffer(url: url)
        } else if url.scheme == "https", url.host == "app.thorbis.com", let fixture = Self.fixture(path: url.path, queryItems: URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [], isFresh: request.cachePolicy == .reloadIgnoringLocalCacheData && request.value(forHTTPHeaderField: "Cache-Control") == "no-cache") {
            status = 200
            payload = fixture
        } else {
            status = 404
            payload = ["status": 404, "title": "Preview fixture unavailable", "detail": "This request is not part of the design preview. No request was sent to a server."]
        }
        do {
            let body = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .fragmentsAllowed])
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json", "X-Thorbis-Design-Preview": "sample-data"])!
            let deliver: @Sendable () -> Void = { [weak self] in
                guard let self else { return }
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: body)
                self.client?.urlProtocolDidFinishLoading(self)
            }
            if PaperPreview.isJobDocumentsPreview,
               ProcessInfo.processInfo.arguments.contains("--paper-preview-create-invoice"),
               request.httpMethod == "POST", url.path == "/v1/jobs/\(PaperPreview.jobID)/completion-invoice" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: deliver)
            } else { deliver() }
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}

    private static func fixture(path: String, queryItems: [URLQueryItem] = [], isFresh: Bool = false) -> Any? {
        let actor = PaperPreview.actorID
        let changedWorkspace = (PaperPreview.isSavedWorkPreview || PaperPreview.screen == "price-book") && scenario.lock.withLock { scenario.savedWorkWorkspaceChanged }
        let org = changedWorkspace ? "00000000-0000-4000-8000-000000000003" : PaperPreview.organizationID
        let expiry = ISO8601DateFormatter().string(from: PaperPreview.isSavedWorkPreview && ProcessInfo.processInfo.arguments.contains("--paper-preview-saved-work-expiry") ? PaperPreview.savedWorkDeadline : Date().addingTimeInterval(86_400))
        let now = ISO8601DateFormatter().string(from: Date())
        // `--paper-preview-empty` answers the list reads before any screen-specific fixture.
        if PaperPreview.isEmptyWorkspace, path == "/v1/invoices" { return ["items": [Any]()] }
        if PaperPreview.isEmptyWorkspace, path == "/v1/staff/notices" {
            return ["items": [Any](), "unreadState": "present", "nextCursor": NSNull()] as [String: Any]
        }
        if PaperPreview.isEmptyWorkspace, path == "/v1/query", queryItems.first(where: { $0.name == "resourceId" })?.value == "price_book_items" {
            return ["schemaVersion": 1, "resourceId": "price_book_items", "purpose": "collection", "localMode": "complete",
                    "items": [Any](), "nextCursor": NSNull(), "planId": "paper-preview", "viewId": NSNull()] as [String: Any]
        }
        if changedWorkspace, path == "/v1/jobs" || path == "/v1/customers" { return ["items": []] }
        if PaperPreview.isSavedWorkPreview, path == "/v1/jobs/\(PaperPreview.savedWorkUncachedJobID)" {
            return ["id": PaperPreview.savedWorkUncachedJobID, "organizationId": org, "customerId": PaperPreview.customerID,
                    "title": "Uncached drain visit", "status": "dispatched", "createdAt": now, "updatedAt": now, "allowedTransitions": ["en_route"]]
        }
        // `job-activity`: every kind of entry on the timeline: a long note (folds with "More"),
        // a short one, the sent estimate, the booking call, status changes and photos.
        if PaperPreview.screen == "job-activity" {
            if path == "/v1/jobs/\(PaperPreview.jobID)/notes" {
                if ProcessInfo.processInfo.arguments.contains("--paper-preview-large-activity") {
                    let notes: [[String: Any]] = (0..<80).map { index in
                        ["id": String(format: "00000000-0000-4000-8001-%012d", index),
                         "organizationId": org, "jobId": PaperPreview.jobID, "authorUserId": actor,
                         "body": "Sample activity note \(index)", "createdAt": today(hour: 9, minute: 15)]
                    }
                    return ["items": notes]
                }
                return ["items": [
                    ["id": "00000000-0000-4000-8000-000000009002", "organizationId": org, "jobId": PaperPreview.jobID, "authorUserId": actor,
                     "body": "Sample note: Outdoor unit is behind the shed; the path floods after rain, so bring boot covers. The dog is friendly but jumps, keep the side gate shut. Customer works from home and asked for a text before anyone rings the bell. Upstairs thermostat was replaced last spring by another company.",
                     "createdAt": today(hour: 9, minute: 40)],
                    ["id": "00000000-0000-4000-8000-000000009001", "organizationId": org, "jobId": PaperPreview.jobID, "authorUserId": actor,
                     "body": "Sample note: Customer confirmed access to the outdoor unit.", "createdAt": today(hour: 9, minute: 15)]
                ]]
            }
            if path == "/v1/jobs/\(PaperPreview.jobID)/estimates" {
                return ["items": [["id": "00000000-0000-4000-8000-000000009301", "organizationId": org, "jobId": PaperPreview.jobID,
                                   "estimateId": PaperPreview.estimate.id, "linkedAt": now]]]
            }
            if path == "/v1/estimates/\(PaperPreview.estimate.id)" { return jsonObject(PaperPreview.estimate) }
        }
        // `job-onsite`: "Before you wrap up · 3 of 6" (before photos, a note and the approved repair
        // done; after photos, signature and payment left). `--paper-preview-onsite-done`: all done.
        if PaperPreview.screen == "job-onsite" {
            let done = PaperPreview.onSiteDone
            if path == "/v1/jobs/\(PaperPreview.jobID)/closeout" {
                let target: [String: Any] = ["id": PaperPreview.jobID, "organizationId": org, "customerId": PaperPreview.customerID,
                                             "locationId": NSNull(), "estimateId": NSNull(), "estimateRevisionNumber": NSNull()]
                func requirement(_ name: String, _ kind: String, _ met: Bool, _ detail: String, _ next: String) -> [String: Any] {
                    ["requirement": name, "kind": kind, "outcome": met ? "satisfied" : "blocked", "detail": detail,
                     "nextAction": met ? NSNull() : next, "commercialSource": met ? NSNull() : "invoice"]
                }
                let requirements = [requirement("photos", "photos", true, "2 of 2 photos added", "add_job_photo"),
                                    requirement("notes", "notes", true, "A note is on the job", "add_job_note"),
                                    requirement("payment", "payment_or_unpaid_disposition", done, done ? "Paid in full" : "$340 still due", "collect_payment")]
                return ["policy": ["organizationId": org, "requireNotes": true, "requiredPhotoCount": 2,
                                   "requiredChecks": done ? [["key": "site-clean", "label": "Work area cleaned up", "kind": "acknowledgement", "allowUnpaidDisposition": NSNull()]] : [],
                                   "updatedByUserId": NSNull(), "updatedAt": NSNull()],
                        "facts": ["noteCount": done ? 2 : 1, "photoCount": 6, "acknowledgedCheckKeys": done ? ["site-clean"] : [], "authorizationTarget": target],
                        "acknowledged": done ? [["checkKey": "site-clean", "acknowledgedByUserId": actor, "acknowledgedAt": now]] : [],
                        "requirements": requirements, "unmet": requirements.filter { ($0["outcome"] as? String) == "blocked" }, "completable": done]
            }
            if path == "/v1/jobs/\(PaperPreview.jobID)/estimates" {
                return ["items": [["id": "00000000-0000-4000-8000-000000009301", "organizationId": org, "jobId": PaperPreview.jobID,
                                   "estimateId": PaperPreview.onSiteEstimate.id, "linkedAt": now]]]
            }
            if path == "/v1/estimates/\(PaperPreview.onSiteEstimate.id)" { return jsonObject(PaperPreview.onSiteEstimate) }
            if path == "/v1/jobs/\(PaperPreview.jobID)/invoices" { return ["items": [jsonObject(PaperPreview.onSiteInvoice)!]] }
            if path == "/v1/invoices/\(PaperPreview.onSiteInvoice.id)" { return jsonObject(PaperPreview.onSiteInvoice) }
        }
        // `job-closeout`: the wrap-up checklist with one met and one open requirement and one check.
        if path == "/v1/jobs/\(PaperPreview.jobID)/closeout" {
            let target: [String: Any] = ["id": PaperPreview.jobID, "organizationId": org, "customerId": PaperPreview.customerID,
                                         "locationId": NSNull(), "estimateId": NSNull(), "estimateRevisionNumber": NSNull()]
            let photos: [String: Any] = ["requirement": "photos", "kind": "photos", "outcome": "satisfied",
                                         "detail": "2 of 2 photos added", "nextAction": NSNull(), "commercialSource": NSNull()]
            let notes: [String: Any] = ["requirement": "notes", "kind": "notes", "outcome": "blocked",
                                        "detail": "Add a note about the work", "nextAction": "Add a note", "commercialSource": NSNull()]
            return ["policy": ["organizationId": org, "requireNotes": true, "requiredPhotoCount": 2,
                               "requiredChecks": [["key": "site-clean", "label": "Work area cleaned up", "kind": "acknowledgement", "allowUnpaidDisposition": NSNull()]],
                               "updatedByUserId": NSNull(), "updatedAt": NSNull()],
                    "facts": ["noteCount": 0, "photoCount": 2, "acknowledgedCheckKeys": [], "authorizationTarget": target],
                    "acknowledged": [], "requirements": [photos, notes], "unmet": [notes], "completable": false]
        }
        if PaperPreview.screen.hasPrefix("present-estimate") || PaperPreview.screen == "estimate-detail" {
            let record = PaperPreview.optionsEstimate
            if path == "/v1/estimates/\(record.id)" { return jsonObject(record) }
            if path == "/v1/estimates/\(record.id)/revisions/2" {
                var object = reviewRevision(record)
                if ProcessInfo.processInfo.arguments.contains("--paper-preview-canonical-estimate"),
                   var options = object["options"] as? [[String: Any]], options.count > 1 {
                    options[1]["title"] = "Reviewed protection"
                    options[1]["description"] = "The current issued repair and protection."
                    options[1]["totalAmount"] = 54_321
                    options[1]["lines"] = [["id": "00000000-0000-4000-8000-000000008500", "description": "Verified surge protection",
                                            "quantity": 1, "unitPrice": ["amount": 54_321, "currency": "USD"]]]
                    object["options"] = options
                }
                return object
            }
        }
        if PaperPreview.isJobDocumentsPreview {
            let estimates = PaperPreview.jobDocumentEstimates
            let invoices = PaperPreview.jobDocumentInvoices
            if path == "/v1/jobs/\(PaperPreview.jobID)/estimates" {
                return ["items": estimates.prefix(2).enumerated().map { index, estimate in
                    ["id": "00000000-0000-4000-8000-0000000093\(String(format: "%02d", index))",
                     "jobId": PaperPreview.jobID, "estimateId": estimate.id, "linkedAt": now]
                }]
            }
            if path == "/v1/jobs/\(PaperPreview.jobID)/invoices" {
                if ProcessInfo.processInfo.arguments.contains("--paper-preview-overview-collect-delayed") {
                    let read = scenario.lock.withLock { scenario.overviewInvoiceListReads += 1; return scenario.overviewInvoiceListReads }
                    if read > 1 { Thread.sleep(forTimeInterval: 6) }
                }
                if ProcessInfo.processInfo.arguments.contains("--paper-preview-create-invoice") {
                    return ["items": scenario.lock.withLock { scenario.completionCreated } ? [jsonObject(PaperPreview.invoice)!] : []]
                }
                return ["items": invoices.filter { $0.jobId == PaperPreview.jobID }.map { jsonObject($0)! }]
            }
            if ProcessInfo.processInfo.arguments.contains("--paper-preview-create-invoice"),
               scenario.lock.withLock({ scenario.completionCreated }), path == "/v1/invoices/\(PaperPreview.invoice.id)" {
                return jsonObject(PaperPreview.invoice)
            }
            if path == "/v1/estimates" { return ["items": estimates.map { jsonObject($0)! }] }
            if path == "/v1/invoices" {
                let legacy = ProcessInfo.processInfo.arguments.contains("--paper-preview-job-invoices-legacy")
                return ["items": legacy ? [] : invoices.map { jsonObject($0)! }]
            }
            if let record = estimates.first(where: { path == "/v1/estimates/\($0.id)" }) {
                var object = jsonObject(record) as! [String: Any]
                if record.id == estimates[0].id, scenario.lock.withLock({ scenario.documentStatusesChanged }) {
                    object["status"] = "approved"
                }
                return object
            }
            if let record = estimates.first(where: { path == "/v1/estimates/\($0.id)/revisions/\($0.currentRevisionNumber ?? 0)" }) {
                var revision = reviewRevision(record)
                if ProcessInfo.processInfo.arguments.contains("--paper-preview-job-estimate-empty-issued-mismatch") {
                    revision["totalAmount"] = 25000
                }
                if ProcessInfo.processInfo.arguments.contains("--paper-preview-job-estimate-option-total-mismatch"),
                   var options = revision["options"] as? [[String: Any]], !options.isEmpty {
                    options[0]["totalAmount"] = 1
                    revision["options"] = options
                }
                if ProcessInfo.processInfo.arguments.contains("--paper-preview-job-estimate-option-empty"),
                   var options = revision["options"] as? [[String: Any]], !options.isEmpty {
                    options[0]["lines"] = []
                    options[0]["totalAmount"] = 0
                    revision["options"] = options
                }
                return revision
            }
            if ProcessInfo.processInfo.arguments.contains("--paper-preview-customer-safe-invoice"),
               let record = invoices.first(where: { path == "/v1/invoices/\($0.id)/customer-presentation" }),
               let total = paperLinesTotal(record.lines) {
                let oldSummary = ProcessInfo.processInfo.arguments.contains("--paper-preview-summary-payment-arrives") &&
                    record.id == invoices[1].id && scenario.lock.withLock { !scenario.documentHistoryRestored }
                let partialPayment = ProcessInfo.processInfo.arguments.contains("--paper-preview-primary-payment-arrives") && record.id == invoices[0].id
                let paid = partialPayment && scenario.lock.withLock({ scenario.documentHistoryRestored }) ? 10000 : (oldSummary ? 33000 : record.amountPaid)
                let summaryStatus = oldSummary ? "issued" : record.status
                return ["kind": "customer_invoice_presentation", "presentationVersion": 1,
                        "presentationScopeId": "invoice:\(record.id):lines:\(record.linesRevision):customer:v1",
                        "isSignedDocument": false, "issuedSnapshotId": record.status == "draft" ? NSNull() : "00000000-0000-4000-8000-000000000001" as Any,
                        "organizationId": record.organizationId, "customerId": record.customerId, "invoiceId": record.id,
                        "jobId": record.jobId ?? "", "linesRevision": record.linesRevision, "status": summaryStatus,
                        "currency": "USD", "totalAmount": total, "amountPaid": paid, "balanceDue": record.status == "void" ? 0 : total - paid,
                        "lines": [["id": "customer-safe-line", "description": ProcessInfo.processInfo.arguments.contains("--paper-preview-customer-summary-long")
                                   ? "This customer-facing service description explains the full work in detail. The technician will complete and test the installation. Final summary detail: leave the work area clean."
                                   : "Customer safe service", "quantity": 1,
                                   "unitPrice": ["amount": total, "currency": "USD"]]]]
            }
            if let record = invoices.first(where: { path == "/v1/invoices/\($0.id)" }) {
                var object = jsonObject(record) as! [String: Any]
                if record.id == invoices[0].id, ProcessInfo.processInfo.arguments.contains("--paper-preview-primary-payment-arrives"), scenario.lock.withLock({ scenario.documentHistoryRestored }) {
                    object["amountPaid"] = 10000
                }
                if record.id == invoices[0].id, scenario.lock.withLock({ scenario.documentStatusesChanged }) {
                    object["status"] = "void"
                }
                if ProcessInfo.processInfo.arguments.contains("--paper-preview-job-invoice-foreign") ||
                    scenario.lock.withLock({ scenario.ownerAuthenticated }) {
                    object["jobId"] = "00000000-0000-4000-8000-000000002215"
                }
                return object
            }
            if ProcessInfo.processInfo.arguments.contains("--paper-preview-primary-payment-arrives"), path == "/v1/invoices/\(invoices[0].id)/payments" {
                var payment = jsonObject(PaperPreview.refundPayment) as! [String: Any]
                payment["invoiceId"] = invoices[0].id
                payment["amount"] = ["amount": 10000, "currency": "USD"]
                payment["netAmount"] = ["amount": 10000, "currency": "USD"]
                payment["refundedAmount"] = 0
                return ["items": [payment]]
            }
            if PaperPreview.isJobDocumentsMoneyPreview, path == "/v1/invoices/\(invoices[0].id)/payments" {
                return ["items": PaperPreview.jobDocumentMoneyPayments.map { jsonObject($0)! }]
            }
            if path == "/v1/invoices/\(invoices[1].id)/payments" {
                if ProcessInfo.processInfo.arguments.contains("--paper-preview-job-invoices-equal-balances") { return ["items": []] }
                var payment = jsonObject(PaperPreview.refundPayment) as! [String: Any]
                payment["invoiceId"] = invoices[1].id
                let staleHistory = ProcessInfo.processInfo.arguments.contains("--paper-preview-job-history-mismatch-once") &&
                    scenario.lock.withLock { !scenario.documentHistoryRestored }
                let received = staleHistory ? 33000 : 34000
                payment["amount"] = ["amount": received, "currency": "USD"]
                payment["netAmount"] = ["amount": received, "currency": "USD"]
                return ["items": [payment]]
            }
        }
        if path == "/v1/public/document-actions/preview-estimate" {
            let discount = ProcessInfo.processInfo.arguments.contains("--paper-preview-public-estimate-discount")
            var sample: [String: Any] = [
                "kind": "estimate",
                "title": "AC not cooling — Compressor replacement",
                "status": "sent",
                "revisionNumber": 2,
                "contentHash": "preview-issued-content-hash-2026",
                "allowedActions": ["approve", "decline", "request_changes"],
                "nonce": "preview-decision-nonce-2026",
                "totalAmount": discount ? 9500 : 157500,
                "currency": "USD",
                "html": """
                <!doctype html><html><head><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><style>body{font:15px -apple-system,BlinkMacSystemFont,sans-serif;color:#201b14;background:#fff;margin:22px;line-height:1.5}.eyebrow{font-size:11px;color:#59544d;letter-spacing:.08em;text-transform:uppercase}h1{font-size:24px;margin:6px 0 16px}.line{display:flex;justify-content:space-between;gap:14px;padding:12px 0;border-bottom:1px solid #e5e2dc}.total{display:flex;justify-content:space-between;font-weight:700;padding-top:18px}.note{margin-top:22px;padding:12px;background:#f7f4ee;border-radius:10px}</style></head><body><div class=\"eyebrow\">Estimate · Revision 2</div><h1>AC not cooling — Compressor replacement</h1><p>Prepared for Danielle Marlowe</p><div class=\"line\"><span>Compressor diagnostic</span><span>$120.00</span></div><div class=\"line\"><span>Replace compressor</span><span>$1,455.00</span></div><div class=\"total\"><span>Estimate total</span><span>$1,575.00</span></div><div class=\"note\">This sample estimate is for design review only.</div></body></html>
                """,
                "approvalWithoutSignatureAllowed": discount,
                "scopeLines": discount ? [["id": "repair", "description": "Repair", "quantity": 1, "unitPrice": 10000], ["id": "discount", "description": "Discount", "quantity": 1, "unitPrice": -500]] : [],
                "options": discount ? [] : [
                    ["id": "00000000-0000-4000-8000-000000000101", "title": "Compressor repair", "description": "Replace the failed compressor and verify system operation.", "totalAmount": 157500, "currency": "USD"],
                    ["id": "00000000-0000-4000-8000-000000000102", "title": "Full system replacement", "description": "Install a new high-efficiency system with a two-year labor warranty.", "totalAmount": 485000, "currency": "USD"]
                ],
                "consentVersion": "estimate-approval-v1",
                "consentText": "I understand that typing my name records my electronic signature and approval of the selected estimate option."
            ]
            if discount { sample.removeValue(forKey: "html") }
            if ProcessInfo.processInfo.arguments.contains("--paper-preview-public-estimate-unsupported-currency") { sample["currency"] = "EUR" }
            return sample
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
            let record = PaperPreview.screen == "estimate-draft-detail" ? PaperPreview.draftEstimate : PaperPreview.estimate
            return try? JSONSerialization.jsonObject(with: JSONEncoder().encode(record))
        }
        if path == "/v1/estimates/\(PaperPreview.estimate.id)/revisions/2" {
            return reviewRevision(PaperPreview.estimate)
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
        // A job's booking notices: the customer's email went out, the tech's in-app one did too.
        if path.hasPrefix("/v1/jobs/"), path.hasSuffix("/notices") {
            let soon = ISO8601DateFormatter().string(from: Date().addingTimeInterval(3_600))
            let ago = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-86_400))
            return ["admission": "recorded", "items": [
                ["id": "n1", "role": "customer", "channel": "email", "status": "sent", "scheduledFor": soon, "currentCycle": true, "createdAt": ago],
                ["id": "n2", "role": "technician", "channel": "in_app", "status": "sent", "scheduledFor": soon, "currentCycle": true, "createdAt": ago],
                ["id": "n3", "role": "customer", "channel": "email", "stage": "en_route", "status": "missing_contact", "scheduledFor": soon, "currentCycle": true,
                 "createdAt": ISO8601DateFormatter().string(from: Date())],
            ] as [[String: Any]]]
        }
        // An estimate's or invoice's audit trail.
        if path.hasPrefix("/v1/activity/") {
            return ["items": [
                ["id": "a3", "action": "invoice.issued", "description": "Ramon Marlowe issued the invoice", "actorType": "user",
                 "occurredAt": ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3_600))],
                ["id": "a2", "action": "invoice.lines_replaced", "description": "Ramon Marlowe changed 2 line items", "actorType": "user",
                 "occurredAt": ISO8601DateFormatter().string(from: Date().addingTimeInterval(-7_200)),
                 "clientOccurredAt": ISO8601DateFormatter().string(from: Date().addingTimeInterval(-9_000))],
                ["id": "a1", "action": "invoice.created", "description": "Invoice created from the job", "actorType": "system",
                 "occurredAt": ISO8601DateFormatter().string(from: Date().addingTimeInterval(-90_000))],
            ] as [[String: Any]]]
        }
        // The company agreements book: one active maintenance plan and one cancelled membership.
        if path == "/v1/memberships" {
            let c = PaperPreview.customerID
            return ["items": [
                ["id": "00000000-0000-4000-8000-000000009101", "customerId": c, "name": "Comfort Club", "kind": "maintenance",
                 "cadence": "Twice a year", "startsOn": "2025-03-01", "renewsOn": "2027-03-01", "status": "active",
                 "discountPercent": 15, "customerName": "Danielle Marlowe", "planName": "Comfort Club"],
                ["id": "00000000-0000-4000-8000-000000009102", "customerId": "00000000-0000-4000-8000-000000000413",
                 "name": "Priority membership", "kind": "membership", "status": "cancelled", "discountPercent": 10,
                 "customerName": "David Chen", "planName": "Priority membership"],
            ] as [[String: Any]]]
        }
        // The company equipment book: Danielle's home units, as the office and her page read them.
        if path == "/v1/equipment" {
            let c = PaperPreview.customerID, loc = PaperPreview.homeLocationID
            return ["items": [
                ["id": "00000000-0000-4000-8000-000000006101", "customerId": c, "locationId": loc, "name": "3-ton condenser",
                 "brand": "Carrier", "model": "24ACC636", "serialNumber": "2419E04117", "installedOn": "2019-06-12",
                 "warrantyExpiresOn": "2029-06-12", "customerName": "Danielle Marlowe", "locationLabel": "Home"],
                ["id": "00000000-0000-4000-8000-000000006102", "customerId": c, "locationId": loc, "name": "50-gal gas water heater",
                 "brand": "Rheem", "model": "XG50T06EC36U1", "installedOn": "2016-02-03", "warrantyExpiresOn": "2022-02-03",
                 "customerName": "Danielle Marlowe", "locationLabel": "Home"],
            ] as [[String: Any]]]
        }
        // Company payments (payments.all): a card payment today, cash yesterday, one refunded.
        if path == "/v1/query", queryItems.contains(where: { $0.name == "resourceId" && $0.value == "payments" }) {
            let day: (Double) -> String = { ISO8601DateFormatter().string(from: Date().addingTimeInterval(-$0 * 86_400)) }
            return ["resourceId": "payments", "items": [
                ["id": "p1", "resourceId": "payments", "fields": ["payments.invoice_id": PaperPreview.invoice.id, "payments.amount": "34000",
                 "payments.method": "card", "payments.status": "succeeded", "payments.refunded_amount": "0", "payments.recorded_at": day(0)]],
                ["id": "p2", "resourceId": "payments", "fields": ["payments.invoice_id": PaperPreview.invoice.id, "payments.amount": 12000,
                 "payments.method": "cash", "payments.status": "succeeded", "payments.refunded_amount": 0, "payments.recorded_at": day(1)]],
                ["id": "p3", "resourceId": "payments", "fields": ["payments.invoice_id": PaperPreview.invoice.id, "payments.amount": "9500",
                 "payments.method": "card", "payments.status": "refunded", "payments.refunded_amount": "9500", "payments.recorded_at": day(6)]],
            ] as [[String: Any]]]
        }
        // A week on the scorecard: most of the way to goal, with a short leaderboard.
        if path == "/v1/reports/scorecard" {
            let now = ISO8601DateFormatter().string(from: Date())
            let me: [String: Any] = ["userId": "preview-user", "sold": 824_000, "collected": 611_500, "invoices": 9,
                                     "averageTicket": 67_900, "jobsDone": 11, "estimatesPresented": 7,
                                     "estimatesApproved": 4, "closeRateBps": 5714, "goal": 1_000_000]
            return ["generatedAt": now, "reportVersion": 1, "from": now, "to": now, "currency": "USD",
                    "me": me, "people": [me], "truncated": false,
                    "leaderboard": [
                        ["rank": 1, "userId": "u2", "displayName": "Dana Ruiz", "percentOfGoalBps": 9600, "me": false],
                        ["rank": 2, "userId": "preview-user", "displayName": "You", "percentOfGoalBps": 8240, "me": true],
                        ["rank": 3, "userId": "u3", "displayName": "Marcus Lee", "percentOfGoalBps": 5100, "me": false],
                    ] as [[String: Any]]]
        }
        // The notice delivery log: a booking email that went out, one held because email is off.
        if path == "/v1/notice-deliveries" {
            let now = ISO8601DateFormatter().string(from: Date())
            return ["items": [
                ["id": "d1", "role": "customer", "channel": "email", "status": "sent", "subject": "Your AC repair is booked for Thursday", "updatedAt": now],
                ["id": "d2", "role": "technician", "channel": "in_app", "status": "sent", "subject": "New job: AC not cooling", "updatedAt": now],
                ["id": "d3", "role": "owner", "channel": "email", "status": "canceled", "reason": "preference_off", "subject": "Job booked: AC not cooling", "updatedAt": now],
            ] as [[String: Any]]]
        }
        if path.hasPrefix("/v1/notice-preferences/customer/") { return ["items": [[String: Any]]()] }
        if path == "/v1/notice-preferences" {
            return ["items": [["subjectKind": "role", "subjectKey": "technician", "channel": "email", "enabled": false]]]
        }
        // The Inbox's call log: a missed call, a caller who rang twice (one answered call with a
        // summary and a recording, one shorter), and a voicemail. The server does not mark
        // voicemail yet (it records from answer); the sample shows how one reads once it does.
        if PaperPreview.screen == "inbox", path == "/v1/calls" || path.hasPrefix("/v1/calls/") {
            let calls = PaperPreview.inboxCalls()
            if path == "/v1/calls" { return ["items": calls, "nextCursor": NSNull()] as [String: Any] }
            let id = path.split(separator: "/").dropFirst(2).first.map(String.init) ?? ""
            if var call = calls.first(where: { $0["id"] as? String == id }) {
                call["transcript"] = id.hasSuffix("9702") ? [
                    ["sequence": 1, "speaker": "business", "text": "Acme HVAC, this is Maria."],
                    ["sequence": 2, "speaker": "caller", "text": "Hi, my water heater is leaking at the bottom. There's a puddle in the garage."],
                    ["sequence": 3, "speaker": "business", "text": "We can be out tomorrow morning. Any gate code or pets?"],
                    ["sequence": 4, "speaker": "caller", "text": "Side gate is 4471. The dog is friendly. Please call half an hour before."],
                ] : [Any]()
                return call
            }
        }
        if path == "/v1/staff/notices", PaperPreview.screen == "inbox" || PaperPreview.role != nil {
            var notices: [[String: Any]] = [
                ["id": "preview-notice-new", "jobId": PaperPreview.jobID, "title": "A visit is ready", "meta": "Water heater install", "at": now, "read": false],
                ["id": "preview-notice-read", "jobId": PaperPreview.jobID, "title": "A visit was updated", "meta": "Water heater install", "at": now, "read": true]
            ]
            if ProcessInfo.processInfo.arguments.contains("--paper-preview-inbox-day-groups") {
                let older = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-172_800))
                notices.append(["id": "preview-notice-older", "jobId": PaperPreview.jobID, "title": "An earlier visit", "meta": "Drain cleaning", "at": older, "read": true])
                notices.append(["id": "preview-notice-unknown", "jobId": PaperPreview.jobID, "title": "A visit without a date", "meta": "Service visit", "read": false])
                notices.append(["id": "preview-notice-invalid", "jobId": PaperPreview.jobID, "title": "A visit with an invalid date", "meta": "Service visit", "at": "not-a-date", "read": true])
            }
            return ["items": notices, "unreadState": "present", "nextCursor": NSNull()] as [String: Any]
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
        if path == "/v1/organization/money-availability" {
            return ["version": 1, "asOf": now, "attention": NSNull(),
                    "balances": [["currency": "USD", "available": 412_000, "pending": 186_500,
                                  "explanation": "Pending is normal card settlement, not a hold. Stripe moves it to available on its own schedule, then pays it out."]],
                    "payouts": [["state": "in_transit", "amount": 298_000, "currency": "USD", "arrivalDate": "2026-10-29", "title": "On its way",
                                 "explanation": "This payout is on its way to your bank, expected on 2026-10-29.", "responsibleActor": "none", "providerCode": NSNull()],
                                ["state": "paid", "amount": 512_250, "currency": "USD", "arrivalDate": "2026-10-24", "title": "Paid out",
                                 "explanation": "Stripe sent this payout for arrival on 2026-10-24. Stripe marking it paid does not confirm your bank has posted it.", "responsibleActor": "none", "providerCode": NSNull()]]] as [String: Any]
        }
        if path == "/v1/organization/merchant-readiness" {
            return ["state": "action_required", "chargesReady": false, "payoutsReady": false, "actionRequired": true,
                    "requirements": ["eventuallyDueCount": 1, "currentlyDueCount": 2, "pastDueCount": 0]] as [String: Any]
        }
        if path == "/v1/reports/operations" {
            return ["freshness": "live", "generatedAt": now, "periodBasis": "utc-month", "reportVersion": 1, "truncated": false,
                    "estimates": ["drafts": 4, "presented": 31, "approved": 18, "declined": 6, "conversionBps": 5806],
                    "jobs": ["booked": 86, "completed": 71, "canceled": 3, "open": 12],
                    "months": [["month": "2026-08", "booked": 74, "completed": 70], ["month": "2026-09", "booked": 81, "completed": 77], ["month": "2026-10", "booked": 86, "completed": 71]]] as [String: Any]
        }
        if path == "/v1/reports/payment-activity" {
            return ["freshness": "live", "generatedAt": now, "periodBasis": "utc-month", "reportVersion": 1, "truncated": false,
                    "months": [["month": "2026-09", "recorded": 4_480_000, "refunded": 32_000, "discounts": 15_000, "depositCredits": 120_000, "retainageWithheld": 0, "otherAdjustments": 0],
                               ["month": "2026-10", "recorded": 4_105_000, "refunded": 0, "discounts": 22_500, "depositCredits": 80_000, "retainageWithheld": 45_000, "otherAdjustments": 0]],
                    "totals": ["recordedCount": 61, "recorded": 8_585_000, "refundedCount": 1, "refunded": 32_000, "discountCount": 4, "discounts": 37_500,
                               "depositCreditCount": 3, "depositCredits": 200_000, "retainageWithheldCount": 1, "retainageWithheld": 45_000,
                               "otherAdjustmentCount": 0, "otherAdjustments": 0]] as [String: Any]
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
        if PaperPreview.screen == "customer-money",
           ProcessInfo.processInfo.arguments.contains("--paper-preview-customer-money-partial") {
            var invoice = (jsonObject(PaperPreview.issuedInvoice) as? [String: Any]) ?? [:]
            invoice["amountPaid"] = 10_000
            if path == "/v1/invoices" { return ["items": matchingCustomer([invoice], queryItems: queryItems)] }
            if path == "/v1/jobs/\(PaperPreview.jobID)/invoices" { return ["items": [invoice]] }
            if path == "/v1/invoices/\(PaperPreview.issuedInvoice.id)" { return invoice }
            if path == "/v1/invoices/\(PaperPreview.issuedInvoice.id)/payments" {
                var payment = (jsonObject(PaperPreview.refundPayment) as? [String: Any]) ?? [:]
                payment["id"] = "00000000-0000-4000-8000-000000002260"
                payment["invoiceId"] = PaperPreview.issuedInvoice.id
                payment["amount"] = ["amount": 10_000, "currency": "USD"]
                payment["netAmount"] = ["amount": 10_000, "currency": "USD"]
                payment["idempotencyKey"] = "paper-preview-customer-partial-payment"
                return ["items": [payment]]
            }
        }
        if path == "/v1/jobs/\(PaperPreview.jobID)/invoices" {
            if PaperPreview.screen == "job-invoice-empty" { return ["items": []] }
            return ["items": [try! JSONSerialization.jsonObject(with: JSONEncoder().encode(PaperPreview.issuedInvoice))]]
        }
        if path == "/v1/invoices" && PaperPreview.screen == "owner-home" { return ["items": ownerHomeInvoices()] }
        if path == "/v1/estimates" && PaperPreview.screen == "owner-home" {
            var waiting = (jsonObject(PaperPreview.estimate) as? [String: Any]) ?? [:]
            waiting["sentAt"] = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-10 * 86_400))
            var fresh = waiting
            fresh["id"] = "00000000-0000-4000-8000-000000002228"
            fresh["customerId"] = "00000000-0000-4000-8000-000000000416"
            fresh["title"] = "Ductless mini-split for the garage"
            fresh["sentAt"] = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-86_400))
            fresh["options"] = NSNull()
            return ["items": [waiting, fresh]]
        }
        if path == "/v1/invoices" && PaperPreview.screen == "job-invoice-empty" { return ["items": []] }
        if path == "/v1/invoices" {
            let item = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(PaperPreview.issuedInvoice)) as? [String: Any]
            return ["items": matchingCustomer(item.map { [$0] } ?? [], queryItems: queryItems)]
        }
        if PaperPreview.screen == "present-invoice", ProcessInfo.processInfo.arguments.contains("--paper-preview-customer-safe-invoice"),
           path == "/v1/invoices/\(PaperPreview.issuedInvoice.id)/customer-presentation" {
            let record = PaperPreview.issuedInvoice
            let total = paperLinesTotal(record.lines) ?? 0
            return ["kind": "customer_invoice_presentation", "presentationVersion": 1,
                    "presentationScopeId": "invoice:\(record.id):lines:\(record.linesRevision):customer:v1",
                    "isSignedDocument": false, "issuedSnapshotId": "00000000-0000-4000-8000-000000000001",
                    "organizationId": record.organizationId, "customerId": record.customerId, "invoiceId": record.id,
                    "jobId": record.jobId as Any? ?? NSNull(), "linesRevision": record.linesRevision,
                    "status": record.status, "currency": "USD", "totalAmount": total,
                    "amountPaid": record.amountPaid, "balanceDue": total - record.amountPaid,
                    "lines": [["id": "customer-safe-line", "description": ProcessInfo.processInfo.arguments.contains("--paper-preview-customer-summary-long")
                                   ? "This customer-facing service description explains the full work in detail. The technician will complete and test the installation. Final summary detail: leave the work area clean."
                                   : "Customer safe service", "quantity": 1,
                               "unitPrice": ["amount": total, "currency": "USD"]]]]
        }
        if path == "/v1/invoices/\(PaperPreview.issuedInvoice.id)" {
            return try? JSONSerialization.jsonObject(with: JSONEncoder().encode(PaperPreview.issuedInvoice))
        }
        if path == "/v1/invoices/\(PaperPreview.issuedInvoice.id)/payments" { return ["items": []] }
        if PaperPreview.screen == "price-book", ProcessInfo.processInfo.arguments.contains("--paper-preview-pricebook-long"),
           path == "/v1/price-book/items/00000000-0000-4000-8000-000000009201" {
            let id = "00000000-0000-4000-8000-000000009201"
            let description = "PEX copper crimp ring pack: 1-in. Ten rings for matching-size PEX; tool calibration remains required. [thorbis-plumbing-demo-v1:material-049]"
            return ["item": ["id": id, "organizationId": org, "status": "active", "currentRevision": 4, "createdAt": now, "updatedAt": now],
                    "revision": ["itemId": id, "organizationId": org, "revision": 4, "description": description, "unit": "10-pack", "kind": "material", "taxClassification": "taxable", "sellPrice": ["amount": 1513, "currency": "USD"], "createdAt": now]] as [String: Any]
        }
        if path == "/v1/organization/profile" {
            let catalog: [(String, String, Int, Bool)] = [
                ("legal_name", "Legal business name", 1, true), ("dba_names", "DBA / trade names", 1, false),
                ("entity_type", "Entity type", 2, false), ("business_address", "Business address", 1, true),
                ("website", "Website", 1, false), ("primary_phone", "Primary phone", 1, true),
                ("primary_email", "Primary email", 1, false), ("industry", "Industry / trades", 1, false),
                ("email_sender_name", "Email sender name", 1, false), ("email_sender_address", "Email reply-to address", 1, false),
            ]
            // `job-onsite`: the workspace has a business phone, so the bar's call-the-office circle shows.
            let phone: [[String: Any]] = PaperPreview.screen == "job-onsite"
                ? [["factKey": "primary_phone", "label": "Primary phone", "tier": 1, "value": "(555) 010-0199", "source": "user_confirmed", "confirmedAt": now, "version": 1]] : []
            return ["organizationId": org, "coreReady": false, "missingCore": ["business_address", "primary_phone"],
                    "facts": [["factKey": "legal_name", "label": "Legal business name", "tier": 1, "value": "Wade’s Plumbing LLC",
                               "source": "user_confirmed", "confirmedAt": now, "version": 1]] + phone,
                    "catalog": catalog.map { ["factKey": $0.0, "label": $0.1, "tier": $0.2, "required": $0.3, "confirmed": $0.0 == "legal_name"] }] as [String: Any]
        }
        if PaperPreview.isEmptyWorkspace, ["/v1/jobs", "/v1/customers", "/v1/estimates"].contains(path) {
            return ["items": [Any]()]
        }
        switch path {
        case "/api/auth/get-session":
            if ProcessInfo.processInfo.arguments.contains("--paper-preview-media-cleanup-failure") { return NSNull() }
            return ["user": ["id": actor, "name": "Ramon Marlowe", "email": "preview@example.invalid"], "session": ["userId": actor, "activeOrganizationId": org, "expiresAt": expiry]]
        case "/api/auth/organization/list": return [["id": org, "name": changedWorkspace ? "Sample workspace B" : "Wade’s Plumbing · Preview"]]
        case "/v1/query/catalog":
            var capabilities = ["job.view", "job.create", "job.edit", "job.note", "job.assign", "customer.view", "customer.create", "customer.edit", "estimate.view", "estimate.create", "estimate.approve", "estimate.discount", "invoice.view", "invoice.edit", "invoice.issue", "pricebook.view"]
            if ProcessInfo.processInfo.arguments.contains("--paper-preview-invoice-discount-authorized") { capabilities.append("invoice.discount") }
            if ProcessInfo.processInfo.arguments.contains("--paper-preview-deny-document-edit") {
                capabilities.removeAll { ["invoice.edit", "estimate.create"].contains($0) }
            }
            if ProcessInfo.processInfo.arguments.contains("--paper-preview-no-customer-handoff") {
                capabilities.removeAll { ["estimate.view", "invoice.view", "customer.edit"].contains($0) }
            }
            if PaperPreview.screen == "job-media", scenario.lock.withLock({ scenario.jobMediaViewRevoked }) { capabilities.removeAll { $0 == "job.view" } }
            if PaperPreview.isSavedWorkPreview, scenario.lock.withLock({ scenario.savedWorkEditingRevoked }) { capabilities.removeAll { $0 == "job.edit" } }
            if PaperPreview.isJobDocumentsPreview, scenario.lock.withLock({ scenario.documentEstimateViewRevoked }) { capabilities.removeAll { $0 == "estimate.view" } }
            if PaperPreview.isJobDocumentsPreview, scenario.lock.withLock({ scenario.invoiceEditRevoked }) { capabilities.removeAll { $0 == "invoice.edit" } }
            if PaperPreview.isJobDocumentsPreview, scenario.lock.withLock({ scenario.completionViewRevoked }) { capabilities.removeAll { $0 == "invoice.view" } }
            if PaperPreview.screen == "price-book", scenario.lock.withLock({ scenario.priceBookViewRevoked }) { capabilities.removeAll { $0 == "pricebook.view" } }
            if PaperPreview.isPaymentCollectionPreview, !scenario.lock.withLock({ scenario.paymentPermissionRevoked }) {
                capabilities.append("invoice.payment.create")
            }
            if PaperPreview.isPaymentRefundPreview { capabilities.append("invoice.refund") }
            if PaperPreview.screen == "team" { capabilities.append("organization.members.manage") }
            if PaperPreview.screen == "job-onsite" { capabilities += ["job.complete", "invoice.create"] }
            if ["job-invoice-empty", "billing-detail"].contains(PaperPreview.screen) { capabilities.append("invoice.create") }
            if PaperPreview.isJobDocumentsPreview, ProcessInfo.processInfo.arguments.contains("--paper-preview-create-invoice") { capabilities.append("invoice.create") }
            if PaperPreview.screen == "notices" { capabilities.append("organization.settings.edit") }
            if PaperPreview.screen == "owner-home" { capabilities.append("organization.settings.edit") }
            if PaperPreview.screen == "price-book", ProcessInfo.processInfo.arguments.contains("--paper-preview-pricebook-admin") { capabilities.append("organization.settings.edit") }
            if PaperPreview.onboardingScreen != nil { capabilities += ["organization.settings.edit", "organization.members.manage", "pricebook.edit"] }
            switch PaperPreview.role {
            case "tech": capabilities.removeAll { $0 == "job.assign" }
            case "owner": capabilities += ["organization.settings.edit", "organization.members.manage"]
            default: break
            }
            return ["authority": ["actorId": actor, "organizationId": org, "policyVersion": 1, "generation": "paper-preview", "authorityExpiresAt": expiry],
                    "capabilities": capabilities,
                    "resources": [], "views": []] as [String: Any]
        case "/v1/features":
            let decision = ["enabled": true, "released": true, "entitled": true]
            var enabledFeatures = ["jobs", "core_crm", "estimates", "estimate_option_signing", "invoicing", "price_book"]
            if ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-group-feature") { enabledFeatures.append("estimate_line_groups") }
            if PaperPreview.isPaymentRefundPreview || PaperPreview.isPaymentCollectionPreview || PaperPreview.screen == "revenue" || PaperPreview.screen == "owner-home" { enabledFeatures.append("payments") }
            if PaperPreview.screen.hasPrefix("billing") { enabledFeatures.append("progress_billing") }
            if ["notices", "inbox"].contains(PaperPreview.screen) { enabledFeatures.append("job_booking_notices") }
            if PaperPreview.screen == "inbox", !ProcessInfo.processInfo.arguments.contains("--paper-preview-inbox-no-calls") { enabledFeatures.append("call_recording") }
            if PaperPreview.role != nil { enabledFeatures.append("job_booking_notices") }
            if ["office", "owner"].contains(PaperPreview.role) { enabledFeatures.append("payments") }
            let features = Dictionary(enabledFeatures.map { ($0, decision) }, uniquingKeysWith: { first, _ in first })
            return ["organizationId": org, "evaluatedAt": now, "features": features]
        // Like the server, list items carry no allowedTransitions; only GET /v1/jobs/{id} does.
        case "/v1/jobs":
            let items = jobs().map { $0.filter { $0.key != "allowedTransitions" } }
            return ["items": matchingCustomer(items, queryItems: queryItems)]
        case "/v1/customers": return ["items": customers()]
        case "/v1/search":
            // The Search Gateway over the sample rows: titles and names, and phone digits.
            let words = (queryItems.first { $0.name == "q" }?.value ?? "").lowercased()
            let digits = words.filter(\.isNumber)
            func hit(_ text: String?) -> Bool { SearchTerms.field(text, has: words) }
            var items: [[String: Any]] = []
            for job in jobs() where hit(job["title"] as? String) {
                items.append(["sourceId": "jobs", "resultType": "job", "entityId": job["id"] ?? "", "title": job["title"] ?? "",
                              "subtitle": "Job", "status": job["status"] ?? NSNull()])
            }
            for customer in customers() {
                let phone = (customer["phone"] as? String)?.filter(\.isNumber) ?? ""
                guard hit(customer["name"] as? String) || hit(customer["address"] as? String) || (digits.count >= 3 && phone.contains(digits)) else { continue }
                items.append(["sourceId": "customers", "resultType": "customer", "entityId": customer["id"] ?? "",
                              "title": customer["name"] ?? "", "subtitle": customer["address"] ?? NSNull()])
            }
            return ["items": items, "nextCursor": NSNull(), "completeness": "complete"]
        case "/v1/membership-plans":
            return ["items": [["id": "00000000-0000-4000-8000-000000006301", "organizationId": PaperPreview.organizationID, "name": "Comfort Club",
                               "kind": "membership", "visitsPerYear": 2, "price": 1900, "billingFrequency": "monthly", "discountPercent": 15,
                               "archived": false, "createdAt": "2026-01-01T00:00:00Z", "updatedAt": "2026-01-01T00:00:00Z"]]]
        case "/v1/invoices": return ["items": [PaperPreview.issuedInvoice, PaperPreview.invoice].compactMap { jsonObject($0) }]
        case "/v1/estimates":
            // Sent ten days ago, so it shows under Needs attention.
            var waiting = (jsonObject(PaperPreview.estimate) as? [String: Any]) ?? [:]
            waiting["sentAt"] = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-10 * 86_400))
            return ["items": matchingCustomer([waiting], queryItems: queryItems)]
        case "/v1/query":
            if PaperPreview.screen == "price-book", ProcessInfo.processInfo.arguments.contains("--paper-preview-pricebook-long"),
               queryItems.first(where: { $0.name == "resourceId" })?.value == "price_book_items" {
                let id = "00000000-0000-4000-8000-000000009201"
                let readNumber = scenario.lock.withLock { scenario.priceBookReads += 1; return scenario.priceBookReads }
                if ProcessInfo.processInfo.arguments.contains("--paper-preview-pricebook-delayed"), readNumber == 1 {
                    Thread.sleep(forTimeInterval: 8)
                }
                let renewed = ProcessInfo.processInfo.arguments.contains("--paper-preview-pricebook-renew") && !ProcessInfo.processInfo.arguments.contains("--paper-preview-pricebook-stable") && readNumber > 1 && (!ProcessInfo.processInfo.arguments.contains("--paper-preview-pricebook-cache-test") || isFresh)
                let extreme = ProcessInfo.processInfo.arguments.contains("--paper-preview-pricebook-extreme")
                let description = extreme ? "Commercial plumbing system inspection and complete replacement.\n\nAssess the existing supply and drainage equipment, document each issue, and explain the recommended work to the customer.\n\nProtect the surrounding area, complete the installation, test all connections, and clean the work area before leaving. Final paragraph of the complete description." : (renewed ? "Updated PEX rings. Latest catalog details. [thorbis-plumbing-demo-v1:material-049]" : "PEX copper crimp ring pack: 1-in. Ten rings for matching-size PEX; tool calibration remains required. [thorbis-plumbing-demo-v1:material-049]")
                let later = queryItems.contains { $0.name == "cursor" }
                let pages = ProcessInfo.processInfo.arguments.contains("--paper-preview-pricebook-pages")
                let firstRow = pages && later ? "Second loaded item. Additional details. [thorbis-plumbing-demo-v1:material-050]" : description
                let rows: [(String, String, String, Int)] = [(firstRow, "10-pack", "material", extreme ? 123456789 : 1513)] +
                    (pages && !later ? (1...49).map { ("Sample material \($0). Details for item \($0).", "each", "material", 1000 + $0) } : []) +
                    (ProcessInfo.processInfo.arguments.contains("--paper-preview-pricebook-many") ? [
                        ("Copper reducer: 1-1/4 × 1-in. Reduces a copper pressure-line diameter. [thorbis-plumbing-demo-v1:material-024]", "each", "material", 1056),
                        ("Thread tape roll. Use with compatible approved materials. [thorbis-plumbing-demo-v1:material-245]", "roll", "material", 2655),
                        ("Copper 90-degree elbow: 1-1/2-in sweat. Turns a copper pressure line. [thorbis-plumbing-demo-v1:material-010]", "each", "material", 1046),
                        ("Inspect a leaking faucet. Diagnose the source of the leak and recommend a repair. [thorbis-plumbing-demo-v1:service-001]", "flat", "service", 8900),
                        ("Clear kitchen drain. Includes an assessment and standard drain clearing. [thorbis-plumbing-demo-v1:service-002]", "flat", "service", 24900)
                    ] : [])
                let items = rows.enumerated().map { offset, entry -> [String: Any] in
                    let entryID = pages && later ? "00000000-0000-4000-8000-000000009251" : (offset == 0 ? id : String(format: "00000000-0000-4000-8000-%012d", 9201 + offset))
                    return ["id": entryID, "resourceId": "price_book_items", "label": entry.0, "subtitle": "\(entry.2.capitalized) · \(entry.1)",
                            "fields": ["price_book_items.id": entryID, "price_book_items.current_revision": 4,
                                       "price_book_items.description": entry.0, "price_book_items.unit": entry.1,
                                       "price_book_items.sell_price_amount": entry.3, "price_book_items.currency": "USD",
                                       "price_book_items.tax_classification": "taxable", "price_book_items.kind": entry.2]]
                }
                return ["schemaVersion": 1, "resourceId": "price_book_items", "purpose": "collection", "localMode": "complete",
                        "items": items,
                        "nextCursor": (ProcessInfo.processInfo.arguments.contains("--paper-preview-pricebook-partial") || (pages && !later)) ? "00000000-0000-4000-8000-000000009988" as Any : NSNull(),
                        "planId": "paper-preview", "viewId": NSNull()] as [String: Any]
            }
            if PaperPreview.enabled, ["invoice-editor", "new-estimate"].contains(PaperPreview.screen),
               ProcessInfo.processInfo.arguments.contains("--paper-preview-catalog-many"),
               queryItems.first(where: { $0.name == "resourceId" })?.value == "price_book_items" {
                let cursor = "00000000-0000-4000-8000-000000009988"
                let later = queryItems.first(where: { $0.name == "cursor" })?.value == cursor
                let numbers = later ? Array(51...73) : Array(1...50)
                let items: [[String: Any]] = numbers.map { number in
                    let id = String(format: "00000000-0000-4000-8000-%012d", 9700 + number)
                    let title = String(format: "Plumbing catalog service %03d", number)
                    return ["id": id, "resourceId": "price_book_items", "label": title, "subtitle": "Service · flat",
                            "fields": ["price_book_items.id": id, "price_book_items.current_revision": 4,
                                       "price_book_items.description": title, "price_book_items.unit": "flat",
                                       "price_book_items.sell_price_amount": 24500, "price_book_items.currency": "USD",
                                       "price_book_items.tax_classification": "taxable", "price_book_items.kind": "service"]]
                }
                return ["schemaVersion": 1, "resourceId": "price_book_items", "purpose": "collection", "localMode": "complete",
                        "items": items, "nextCursor": later ? NSNull() : cursor, "planId": "paper-preview", "viewId": NSNull()] as [String: Any]
            }
            if PaperPreview.enabled, PaperPreview.screen == "invoice-editor",
               (ProcessInfo.processInfo.arguments.contains("--paper-preview-catalog-pages") ||
                ProcessInfo.processInfo.arguments.contains("--paper-preview-catalog-partial")),
               queryItems.first(where: { $0.name == "resourceId" })?.value == "price_book_items" {
                let cursor = "00000000-0000-4000-8000-000000009988"
                let later = queryItems.first(where: { $0.name == "cursor" })?.value == cursor
                let longTitle = "Camera sewer inspection with detailed video documentation, full pipe assessment, and a written repair recommendation"
                let title = ProcessInfo.processInfo.arguments.contains("--paper-preview-long-catalog-title") ? longTitle : "Camera sewer inspection"
                let rows = later ? [(9999, title)] : (1...50).map { (9700 + $0, "Plumbing catalog service \($0)") }
                let items: [[String: Any]] = rows.map { number, title in
                    let id = String(format: "00000000-0000-4000-8000-%012d", number)
                    return ["id": id, "resourceId": "price_book_items", "label": title, "subtitle": "Service · flat",
                            "fields": ["price_book_items.id": id, "price_book_items.current_revision": 4,
                                       "price_book_items.description": title, "price_book_items.unit": "flat",
                                       "price_book_items.sell_price_amount": 24500, "price_book_items.currency": "USD",
                                       "price_book_items.tax_classification": "taxable", "price_book_items.kind": "service"]]
                }
                return ["schemaVersion": 1, "resourceId": "price_book_items", "purpose": "collection", "localMode": "complete",
                        "items": items, "nextCursor": later ? NSNull() : cursor, "planId": "paper-preview", "viewId": NSNull()] as [String: Any]
            }
            // The first item keeps the id the preview estimate's price book line points at.
            let catalog: [(String, String, String, Int)] = [
                ("Replace capacitor", "each", "material", 12500),
                ("Capacitor, 45/5 MFD dual run", "each", "material", 14500),
                ("Capacitor, 35/5 MFD dual run", "each", "material", 13500),
                ("Hard start kit with capacitor", "each", "material", 21000),
                ("Diagnostic visit", "visit", "service", 8900),
                ("Condenser coil cleaning", "each", "service", 12000),
                ("Refrigerant R-410A", "lb", "material", 9500),
                ("Licensed technician labor", "hour", "labor", 14000),
                ("Contactor, 30 amp single pole", "each", "material", 6800),
                ("Surge protector, installed", "each", "assembly", 39500),
            ]
            let items: [[String: Any]] = catalog.enumerated().map { offset, entry in
                let id = String(format: "00000000-0000-4000-8000-%012d", 9201 + offset)
                return ["id": id, "resourceId": "price_book_items", "label": entry.0,
                        "subtitle": "\(entry.2.capitalized) · \(entry.1)",
                        "fields": ["price_book_items.id": id,
                                   "price_book_items.current_revision": 4,
                                   "price_book_items.description": entry.0,
                                   "price_book_items.unit": entry.1,
                                   "price_book_items.sell_price_amount": entry.3,
                                   "price_book_items.currency": "USD",
                                   "price_book_items.tax_classification": "taxable",
                                   "price_book_items.kind": entry.2]]
            }
            return ["schemaVersion": 1, "resourceId": "price_book_items", "purpose": "collection", "localMode": "complete",
                    "items": items, "nextCursor": NSNull(), "planId": "paper-preview", "viewId": NSNull()] as [String: Any]
        default: break
        }
        for job in jobs() {
            guard let id = job["id"] as? String else { continue }
            if path == "/v1/jobs/\(id)" { return job }
            if path == "/v1/jobs/\(id)/notes" {
                return ["items": [["id": "00000000-0000-4000-8000-000000009001", "organizationId": org, "jobId": id, "authorUserId": actor, "body": "Sample note: Customer confirmed access to the outdoor unit.", "createdAt": today(hour: 9, minute: 15)]]]
            }
            if path == "/v1/jobs/\(id)/media", PaperPreview.isCustomerRecordsPreview,
               ProcessInfo.processInfo.arguments.contains("--paper-preview-customer-document-rollup") {
                guard id.hasSuffix("2214") || id.hasSuffix("2201") else { return ["items": []] }
                let first = id.hasSuffix("2214")
                let file: [String: Any] = ["id": first ? "00000000-0000-4000-8000-000000031777" : "00000000-0000-4000-8000-000000031778", "organizationId": org, "jobId": id,
                    "uploaderUserId": actor, "kind": "document", "mime": "application/pdf", "sizeBytes": 128,
                    "originalFilename": first ? "Service report.pdf" : "Drain report.pdf", "contentHash": "preview", "storageKey": "preview/report.pdf",
                    "uploadState": "stored", "tags": [String](), "caption": first ? "Service report" : "Drain report", "archived": false,
                    "createdAt": now, "updatedAt": now]
                if !first { return ["items": [file]] }
                var pending = file
                pending["id"] = "00000000-0000-4000-8000-000000031779"
                pending["caption"] = "Uploading report"
                pending["uploadState"] = "pending"
                var failed = file
                failed["id"] = "00000000-0000-4000-8000-000000031780"
                failed["caption"] = "Failed report"
                failed["uploadState"] = "failed"
                return ["items": [file, pending, failed]]
            }
            if path == "/v1/jobs/\(id)/media", PaperPreview.isCustomerRecordsPreview,
               (ProcessInfo.processInfo.arguments.contains("--paper-preview-customer-photo-rollup") ||
                ProcessInfo.processInfo.arguments.contains("--paper-preview-mixed-photo-rollup")) {
                let mixed = ProcessInfo.processInfo.arguments.contains("--paper-preview-mixed-photo-rollup")
                let count = id.hasSuffix("2214") ? 15 : (id.hasSuffix("2201") ? (mixed ? 19 : 20) : 0)
                let base = id.hasSuffix("2214") ? 31000 : 32000
                let items: [[String: Any]] = (0..<count).map { number in
                    let assetID = String(format: "00000000-0000-4000-8000-%012d", base + number)
                    let reconciled = mixed && id.hasSuffix("2214") && number == 0
                    return ["id": assetID, "organizationId": org, "jobId": id, "uploaderUserId": actor,
                            "kind": "photo", "mime": reconciled ? "image/png" : "image/jpeg", "sizeBytes": reconciled ? 73 : 128,
                            "originalFilename": reconciled ? "reconciled.bin" : "sample-\(base + number).jpg", "contentHash": "preview",
                            "storageKey": "preview/\(assetID)", "uploadState": "stored", "tags": [String](),
                            "caption": "\(id.hasSuffix("2214") ? "AC" : "Drain") photo \(number + 1)", "archived": false,
                            "createdAt": now, "updatedAt": now]
                }
                return ["items": items]
            }
            if path == "/v1/jobs/\(id)/photos", PaperPreview.isCustomerRecordsPreview,
               ProcessInfo.processInfo.arguments.contains("--paper-preview-mixed-photo-rollup") {
                let isFirst = id.hasSuffix("2214")
                let photoID = isFirst ? "00000000-0000-4000-8000-000000033000" : "00000000-0000-4000-8000-000000033001"
                let key = isFirst ? "preview/00000000-0000-4000-8000-000000031000" : "preview/legacy-photo"
                guard isFirst || id.hasSuffix("2201") else { return ["items": []] }
                return ["items": [["id": photoID, "organizationId": org, "jobId": id, "authorUserId": actor,
                                   "contentType": "image/png", "byteSize": 73, "storageKey": key, "createdAt": now]]]
            }
            if path == "/v1/jobs/\(id)/media", PaperPreview.screen == "job-media" {
                var first: [String: Any] = [
                    "id": "00000000-0000-4000-8000-000000009301", "organizationId": org, "jobId": id,
                    "uploaderUserId": actor, "kind": "photo", "mime": "image/jpeg", "sizeBytes": 120_000,
                    "originalFilename": "outdoor-unit.jpg", "contentHash": "preview", "storageKey": "preview/outdoor-unit.jpg",
                    "uploadState": "stored", "tags": ["Before"], "caption": "Outdoor unit", "archived": false,
                    "createdAt": now, "updatedAt": now
                ]
                if ProcessInfo.processInfo.arguments.contains("--paper-preview-media-detail-wrong-job") {
                    first["jobId"] = "00000000-0000-4000-8000-000000009999"
                }
                if ProcessInfo.processInfo.arguments.contains("--paper-preview-media-detail-wrong-org") {
                    first["organizationId"] = "00000000-0000-4000-8000-000000009998"
                }
                // Media redesign screenshots: a visit's worth of sample photos (thumbnails are drawn
                // as labelled SAMPLE tiles in DEBUG), three stages and two documents.
                if ProcessInfo.processInfo.arguments.contains("--paper-preview-media-grid") {
                    let shots: [(String, String, [String])] = [
                        ("Water heater, as found", "08:58", ["Before"]), ("Rusted supply line", "09:01", ["Before"]),
                        ("Leak at the base", "09:02", ["Before"]), ("Anode rod", "09:04", ["Before"]),
                        ("Data plate", "09:05", []), ("Shutoff valve", "09:20", []),
                        ("New supply lines", "11:40", ["After"]), ("Expansion tank fitted", "11:44", ["After"]),
                        ("Water heater, finished", "11:52", ["After"]), ("Dry floor", "11:55", ["After"]),
                        ("Old tank on the truck", "12:05", []),
                    ]
                    var items: [[String: Any]] = shots.enumerated().map { offset, shot in
                        let parts = shot.1.split(separator: ":").compactMap { Int($0) }
                        return ["id": String(format: "00000000-0000-4000-8000-%012d", 9401 + offset), "organizationId": org, "jobId": id,
                                "uploaderUserId": offset == 10 ? "00000000-0000-4000-8000-000000008801" : actor,
                                "kind": "photo", "mime": "image/jpeg", "sizeBytes": 240_000,
                                "originalFilename": "sample-\(offset + 1).jpg", "contentHash": "preview", "storageKey": "preview/\(offset).jpg",
                                "uploadState": "stored", "tags": shot.2, "caption": shot.0, "archived": false,
                                "capturedAt": today(hour: parts[0], minute: parts[1]),
                                "createdAt": today(hour: parts[0], minute: parts[1]), "updatedAt": now] as [String: Any]
                    }
                    for (offset, doc) in [("Sample permit.pdf", "application/pdf", "document"), ("Sample leak clip.mp4", "video/mp4", "video")].enumerated() {
                        items.append(["id": String(format: "00000000-0000-4000-8000-%012d", 9451 + offset), "organizationId": org, "jobId": id,
                                      "uploaderUserId": actor, "kind": doc.2, "mime": doc.1, "sizeBytes": 1_400_000 + offset * 2_600_000,
                                      "originalFilename": doc.0, "contentHash": "preview", "storageKey": "preview/doc-\(offset)",
                                      "uploadState": "stored", "tags": [String](), "caption": NSNull(), "archived": false,
                                      "capturedAt": today(hour: 9, minute: 30 + offset), "createdAt": now, "updatedAt": now])
                    }
                    return ["items": Array(items.reversed())]
                }
                if ProcessInfo.processInfo.arguments.contains("--paper-preview-media-pages") {
                    if queryItems.contains(where: { $0.name == "cursor" && $0.value == "next-media" }) {
                        var later = first
                        later["id"] = "00000000-0000-4000-8000-000000009302"
                        later["caption"] = "Later repair"
                        later["tags"] = ["After"]
                        var document = first
                        document["id"] = "00000000-0000-4000-8000-000000009303"
                        document["kind"] = "document"
                        document["mime"] = "application/pdf"
                        document["originalFilename"] = "Later document.pdf"
                        return ["items": [later, document]]
                    }
                    return ["items": [first], "nextCursor": "next-media"]
                }
                guard ProcessInfo.processInfo.arguments.contains("--paper-preview-media-dates") else { return ["items": [first]] }
                var newest = first
                newest["capturedAt"] = "2026-10-27T12:00:00Z"
                var earlier = first
                earlier["id"] = "00000000-0000-4000-8000-000000009302"
                earlier["caption"] = "Finished unit"
                earlier["capturedAt"] = "2026-10-26T12:00:00.123Z"
                earlier["tags"] = ["After"]
                var invalid = first
                invalid["id"] = "00000000-0000-4000-8000-000000009303"
                invalid["caption"] = "Uncertain date"
                invalid["capturedAt"] = "not-a-date"
                invalid["tags"] = []
                return ["items": [earlier, invalid, newest]]
            }
            if path == "/v1/jobs/\(id)/media", PaperPreview.isJobScreenPreview, id == PaperPreview.jobID {
                // Six photos from this visit: three Before this morning, the rest untagged.
                let shots: [(String, String, [String])] = [("Outdoor unit", "09:12", ["Before"]), ("Coil", "09:13", ["Before"]),
                                                            ("Unit tag", "09:14", ["Before"]), ("Capacitor", "10:05", []),
                                                            ("Breaker panel", "10:20", PaperPreview.onSiteDone ? ["After"] : []),
                                                            ("Thermostat", "10:41", PaperPreview.onSiteDone ? ["After"] : [])]
                return ["items": Array(shots.enumerated().map { offset, shot in
                    let parts = shot.1.split(separator: ":").compactMap { Int($0) }
                    return ["id": String(format: "00000000-0000-4000-8000-%012d", 9311 + offset), "organizationId": org, "jobId": id,
                            "uploaderUserId": actor, "kind": "photo", "mime": "image/jpeg", "sizeBytes": 120_000,
                            "originalFilename": "\(shot.0.lowercased().replacingOccurrences(of: " ", with: "-")).jpg", "contentHash": "preview",
                            "storageKey": "preview/\(offset).jpg", "uploadState": "stored", "tags": shot.2, "caption": shot.0, "archived": false,
                            "capturedAt": today(hour: parts[0], minute: parts[1]),
                            "createdAt": today(hour: parts[0], minute: parts[1]), "updatedAt": now] as [String: Any]
                }.reversed())]
            }
            if path == "/v1/jobs/\(id)/photos" || path == "/v1/jobs/\(id)/media" { return ["items": []] }
            if path == "/v1/jobs/\(id)/estimates" { return ["items": []] }
            if path == "/v1/jobs/\(id)/booking-call" {
                return ["call": [
                    "id": "00000000-0000-4000-8000-000000009601", "status": "completed", "direction": "inbound",
                    "callerNumber": "(555) 010-0100", "callerName": "Dana Ruiz", "jobId": id,
                    "linkedAt": "2026-10-27T15:20:00Z", "startedAt": "2026-10-27T15:12:00Z", "endedAt": "2026-10-27T15:15:12Z",
                    "durationSeconds": 192,
                    "recording": ["status": "available", "durationSeconds": 192,
                                  "contentPath": "/v1/calls/00000000-0000-4000-8000-000000009601/recording"],
                    "summary": ["text": "Water heater leaking at the base since this morning. Works from home; call 30 minutes ahead. Side gate code 4471.",
                                "source": "model"],
                    "transcriptStatus": "available",
                    "transcript": [
                        ["sequence": 1, "speaker": "business", "text": "Thanks for calling, how can we help?"],
                        ["sequence": 2, "speaker": "caller", "text": "My water heater is leaking at the bottom. There's a puddle in the garage."],
                        ["sequence": 3, "speaker": "business", "text": "We can have someone out tomorrow morning. Any gate code or pets?"],
                        ["sequence": 4, "speaker": "caller", "text": "Side gate is 4471. The dog is friendly. Please call half an hour before."],
                    ],
                    "disclosure": "This call may be recorded for quality and training.",
                ]]
            }
            if path == "/v1/jobs/\(id)/visit-history" {
                if PaperPreview.isEmptyPropertyHistoryPreview { return ["items": []] }
                if PaperPreview.isPropertyHistoryPreview {
                    // Past jobs at Home (the list carries their location) and one with no recorded site,
                    // which "At this address" leaves out.
                    return ["items": propertyHistoryJobs().map { row in
                        ["id": row["id"]!, "title": row["title"]!, "status": row["status"]!, "notes": NSNull(),
                         "assignedToUserId": row["assignedToUserId"] ?? NSNull(), "scheduledFor": row["scheduledFor"]!,
                         "completedAt": row["status"] as? String == "completed" ? row["scheduledFor"]! : NSNull(),
                         "canceledAt": row["status"] as? String == "canceled" ? row["scheduledFor"]! : NSNull(),
                         "createdAt": row["createdAt"]!] as [String: Any]
                    }]
                }
                return ["items": [
                    ["id": "00000000-0000-4000-8000-000000009501", "title": "Spring AC tune-up", "status": "completed",
                     "notes": "Coil cleaned, capacitor reading low. Quoted a replacement for next visit.",
                     "assignedToUserId": "00000000-0000-4000-8000-000000008801", "scheduledFor": "2026-04-14T16:00:00Z",
                     "completedAt": "2026-04-14T17:20:00Z", "createdAt": "2026-04-02T10:00:00Z"],
                    ["id": "00000000-0000-4000-8000-000000009502", "title": "Water heater flush", "status": "completed",
                     "notes": "Sediment heavy. Anode rod due next year.", "assignedToUserId": actor,
                     "scheduledFor": "2025-11-03T15:00:00Z", "completedAt": "2025-11-03T16:05:00Z", "createdAt": "2025-10-28T10:00:00Z"]
                ]]
            }
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
            if path == "/v1/customers/\(id)/equipment" {
                if PaperPreview.isEmptyPropertyHistoryPreview { return ["items": []] }
                if PaperPreview.isPropertyHistoryPreview {
                    return ["items": [["id": "00000000-0000-4000-8000-000000006101", "organizationId": org, "customerId": id,
                                       "locationId": PaperPreview.homeLocationID, "name": "3-ton condenser", "kind": "AC",
                                       "brand": "Carrier", "model": "24ACC636", "installedOn": "2019-06-12",
                                       "createdAt": now, "updatedAt": now],
                                      ["id": "00000000-0000-4000-8000-000000006102", "organizationId": org, "customerId": id,
                                       "locationId": PaperPreview.homeLocationID, "name": "50-gal gas water heater",
                                       "brand": "Rheem", "model": "XG50T06EC36U1", "installedOn": "2016-02-03",
                                       "createdAt": now, "updatedAt": now],
                                      ["id": "00000000-0000-4000-8000-000000006103", "organizationId": org, "customerId": id,
                                       "locationId": PaperPreview.homeLocationID, "name": "Gas furnace", "brand": "Lennox",
                                       "model": "ML180", "installedOn": "2021-10-20", "createdAt": now, "updatedAt": now],
                                      ["id": "00000000-0000-4000-8000-000000006104", "organizationId": org, "customerId": id,
                                       "locationId": "00000000-0000-4000-8000-000000007002", "name": "Rental unit boiler",
                                       "createdAt": now, "updatedAt": now]]]
                }
                return ["items": [["id": "00000000-0000-4000-8000-000000006101", "organizationId": org, "customerId": id,
                                   "locationId": "00000000-0000-4000-8000-000000007001", "name": "3-ton condenser", "kind": "AC",
                                   "brand": "Carrier", "model": "24ACC636", "serialNumber": "2419E04117", "installedOn": "2019-06-12",
                                   "warrantyExpiresOn": "2029-06-12", "createdAt": now, "updatedAt": now],
                                  ["id": "00000000-0000-4000-8000-000000006102", "organizationId": org, "customerId": id,
                                   "locationId": "00000000-0000-4000-8000-000000007001", "name": "50-gal gas water heater",
                                   "brand": "Rheem", "model": "XG50T06EC36U1", "warrantyExpiresOn": "2024-03-01",
                                   "createdAt": now, "updatedAt": now]]]
            }
            if path == "/v1/customers/\(id)/memberships" {
                return ["items": [["id": "00000000-0000-4000-8000-000000006201", "organizationId": org, "customerId": id,
                                   "planId": "00000000-0000-4000-8000-000000006301", "name": "Comfort Club", "kind": "membership",
                                   "cadence": "2 tune-ups a year", "startsOn": "2026-01-15", "renewsOn": "2027-01-15", "status": "active",
                                   "discountPercent": 15, "createdAt": now, "updatedAt": now]]]
            }
            if path == "/v1/customers/\(id)/member-pricing" {
                return ["customerId": id, "isMember": true, "discountPercent": 15,
                        "membership": ["id": "00000000-0000-4000-8000-000000006201", "name": "Comfort Club", "renewsOn": "2027-01-15"]]
            }
            if path == "/v1/customers/\(id)/history" {
                return ["items": [
                    ["occurredAt": "2026-10-27T16:10:00Z", "kind": "job", "subjectId": "job-2214", "summary": "Job booked: AC not cooling"],
                    ["occurredAt": "2026-10-20T15:00:00Z", "kind": "contact", "subjectId": "contact-1", "summary": "Agreed to job texts"],
                    ["occurredAt": "2026-10-12T18:30:00Z", "kind": "payment", "subjectId": "pay-1", "summary": "Card payment of $480.00"],
                    ["occurredAt": "2026-10-12T17:55:00Z", "kind": "invoice", "subjectId": "inv-1", "summary": "Invoice sent for drain cleaning"],
                    ["occurredAt": "2026-10-11T14:00:00Z", "kind": "estimate", "subjectId": "est-1", "summary": "Estimate approved: drain cleaning"]
                ], "nextCursor": NSNull()] as [String: Any]
            }
            if path == "/v1/customers/\(id)/sms-consent" {
                return ["decision": "grant", "version": "00000000-0000-4000-8000-000000006001", "recordedAt": "2026-10-20T15:00:00Z"]
            }
            if path == "/v1/customers/\(id)/locations" {
                if ProcessInfo.processInfo.arguments.contains("--paper-preview-many-locations") ||
                    ProcessInfo.processInfo.arguments.contains("--paper-preview-few-locations") {
                    let count = ProcessInfo.processInfo.arguments.contains("--paper-preview-few-locations") ? 3 : 18
                    let locations: [[String: Any]] = (1...count).map { index in
                        ["id": String(format: "00000000-0000-4000-8000-%012d", 7100 + index),
                         "organizationId": org, "customerId": id, "label": "Location \(index)",
                         "kind": "service", "address": "\(index) Test Street", "createdAt": now, "updatedAt": now]
                    }
                    return ["items": locations]
                }
                if PaperPreview.isEmptyPropertyHistoryPreview {
                    return ["items": [["id": PaperPreview.homeLocationID, "organizationId": org, "customerId": id,
                                       "label": "Home", "kind": "service", "address": address, "createdAt": now, "updatedAt": now]]]
                }
                return ["items": [["id": "00000000-0000-4000-8000-000000007001", "organizationId": org, "customerId": id,
                                    "label": ProcessInfo.processInfo.arguments.contains("--paper-preview-long-location-label")
                                        ? "Birch Community Hall North Building Utility Room and Accessible Service Entrance Near the West Courtyard"
                                        : "Home", "kind": "service", "address": address,
                                    "notes": "Sample location for design preview",
                                    "coordinates": previewCoordinates(customerID: id),
                                    "gateCode": "4821#", "alarmCode": "7350",
                                    "dogOnSite": "Rusty — friendly, stays in the back yard",
                                    "parking": "Driveway on the left", "createdAt": now, "updatedAt": now]]]
            }
        }
        return nil
    }
    private static func reviewRevision(_ record: EstimateRecord) -> [String: Any] {
        var object = jsonObject(record) as! [String: Any]
        object["id"] = "10000000" + record.id.dropFirst(8)
        object["estimateId"] = record.id
        object["revisionNumber"] = record.currentRevisionNumber ?? 0
        object["status"] = record.status == "sent" ? "issued" : record.status
        object["totalAmount"] = paperLinesTotal(record.lines) ?? 0
        object["currency"] = record.lines.first?.unitPrice.currency ?? record.options?.first?.currency ?? "USD"
        object["issuedAt"] = record.sentAt ?? record.updatedAt
        object["provenance"] = "command"
        return object
    }
    /// Wisetack's shape for the financing previews: $500 to $25,000, 60 months at 9.99% APR.
    private static func financingOffer(url: URL) -> [String: Any] {
        guard PaperPreview.screen.contains("financing") || PaperPreview.screen == "present-invoice-pay" else { return ["available": false, "examples": []] }
        let amounts = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .filter { $0.name == "amount" }.compactMap { $0.value.flatMap(Int.init) } ?? []
        let rate = 0.0999 / 12
        let examples: [[String: Any]] = amounts.map { cents in
            let inRange = (50_000...2_500_000).contains(cents)
            let monthly = Int((Double(cents) * rate / (1 - pow(1 + rate, -60))).rounded(.up))
            return ["amount": ["amount": cents, "currency": "USD"], "available": inRange,
                    "monthlyAmount": inRange ? ["amount": monthly, "currency": "USD"] as Any : NSNull(),
                    "termMonths": inRange ? 60 as Any : NSNull(), "aprBasisPoints": inRange ? 999 as Any : NSNull(),
                    "terms": inRange ? "60 months at 9.99% APR. Subject to approval." as Any : NSNull()]
        }
        return ["available": true, "provider": "wisetack", "providerName": "Wisetack",
                "minimum": ["amount": 50_000, "currency": "USD"], "maximum": ["amount": 2_500_000, "currency": "USD"],
                "disclosure": "Preview disclosure. The lender's own terms appear here, word for word.",
                "creditCheckNote": "Checking your options will not affect your credit score.",
                "examples": examples]
    }


    /// List routes ignore unknown query keys. A customerId query keeps that customer's rows,
    /// matching the field list the records tab calls.
    private static func matchingCustomer(_ items: [[String: Any]], queryItems: [URLQueryItem]) -> [[String: Any]] {
        guard let id = queryItems.first(where: { $0.name == "customerId" })?.value
        else { return items }
        return items.filter { ($0["customerId"] as? String) == id }
    }
    private static func jsonObject<T: Encodable>(_ value: T) -> Any? {
        (try? JSONEncoder().encode(value)).flatMap { try? JSONSerialization.jsonObject(with: $0) }
    }
    /// Spreads the sample customers across San Francisco so the schedule map has distinct pins.
    private static func previewCoordinates(customerID: String) -> [String: Double] {
        let spots: [String: (Double, Double)] = ["0412": (37.7749, -122.4194), "0413": (37.7599, -122.4148),
                                                "0414": (37.7880, -122.4074), "0415": (37.7680, -122.4400),
                                                "0416": (37.7952, -122.4330)]
        let spot = spots[String(customerID.suffix(4))] ?? (37.7749, -122.4194)
        return ["latitude": spot.0, "longitude": spot.1]
    }
    private static func today(hour: Int, minute: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
        return ISO8601DateFormatter().string(from: date)
    }
    private static func jobs() -> [[String: Any]] {
        let arguments = ProcessInfo.processInfo.arguments
        let longTitle = "Air conditioning is not cooling the upstairs rooms after several hours of running"
        let rows: [(String, String, String, String, Int, Int)] = [
            ("2214", "0412", arguments.contains("--paper-preview-long-job-title")
                ? "Diagnose the upstairs air conditioner and replace the damaged compressor at the back of the property"
                : (arguments.contains("--paper-preview-customer-long-job") ? longTitle : "AC not cooling"),
             PaperPreview.isWorkingJobPreview || PaperPreview.screen == "next-stop-active" || PaperPreview.screen == "job-onsite" ? "in_progress" : "dispatched", 10, 30),
            ("2212", "0413", "Kitchen sink backup — Petrov", "scheduled", 12, 15),
            // Next stop: an earlier visit is finished, so the dispatched 10:30 call leads the day.
            ("2209", "0414", "Water heater install — Chen", PaperPreview.screen.hasPrefix("next-stop") ? "completed" : "in_progress",
             PaperPreview.screen.hasPrefix("next-stop") ? 9 : 13, 0),
            ("2218", "0415", "Outlet replacement — Alvarez", "scheduled", 14, 30),
            ("2224", "0416", "AC recheck — Nakamura", "scheduled", 16, 0),
            ("2201", "0412", "Drain cleaning", "completed", 8, 30)
        ]
        var listed = rows.filter { !arguments.contains("--paper-preview-customer-no-jobs") || $0.1 != "0412" }.map { ref, customer, title, status, hour, minute in
            ["id": "00000000-0000-4000-8000-00000000\(ref)", "organizationId": PaperPreview.organizationID,
             "customerId": "00000000-0000-4000-8000-00000000\(customer)", "title": title, "status": status,
             "assignedToUserId": PaperPreview.actorID, "scheduledFor": today(hour: hour, minute: minute),
             "createdAt": "2026-07-20T12:00:00Z", "updatedAt": today(hour: 9, minute: 0),
             "notes": "Sample job: Upstairs zone blowing warm air since Sunday. Customer suspects the capacitor.",
             "allowedTransitions": status == "completed" ? [] : (status == "dispatched" ? ["en_route"] : ["arrived", "in_progress", "paused"])] as [String: Any]
        }
        if arguments.contains("--paper-preview-customer-two-open-jobs"),
           let original = listed.first(where: { ($0["id"] as? String) == PaperPreview.jobID }) {
            var second = original
            second["id"] = "00000000-0000-4000-8000-000000002299"
            second["title"] = "Water heater service"
            listed.append(second)
        }
        if PaperPreview.isJobScreenPreview || PaperPreview.screen == "customer-jobs",
           let index = listed.firstIndex(where: { ($0["id"] as? String) == PaperPreview.jobID }) {
            listed[index]["locationId"] = PaperPreview.homeLocationID
            // A dispatched job's moves as the live server lists them (build 125's status sheet), so
            // the job screen's status popover and ••• show every allowed move.
            if PaperPreview.isJobScreenPreview, listed[index]["status"] as? String == "dispatched" {
                listed[index]["allowedTransitions"] = ["en_route", "arrived", "in_progress", "paused", "scheduled"]
            }
            if PaperPreview.screen == "job-activity" { listed[index]["dispatchedAt"] = today(hour: 8, minute: 2) }
            if PaperPreview.screen == "job-onsite" {
                // Arrived 42 minutes ago, working since: the on-site clock reads from these taps.
                let arrived = Date().addingTimeInterval(-42 * 60)
                let formatter = ISO8601DateFormatter()
                listed[index]["dispatchedAt"] = formatter.string(from: arrived.addingTimeInterval(-90 * 60))
                listed[index]["enRouteAt"] = formatter.string(from: arrived.addingTimeInterval(-24 * 60))
                listed[index]["arrivedAt"] = formatter.string(from: arrived)
                listed[index]["startedAt"] = formatter.string(from: arrived.addingTimeInterval(3 * 60))
                listed[index]["allowedTransitions"] = PaperPreview.onSiteDone ? ["paused", "completed"] : ["paused"]
            }
        }
        if PaperPreview.screen == "customer-jobs" { listed += propertyHistoryJobs() }
        if PaperPreview.screen == "dispatch-board" {
            // The board needs a team's day: spread the visits across the roster, leave one
            // without a tech and two waiting for a time.
            let jorge = "00000000-0000-4000-8000-000000008801", sam = "00000000-0000-4000-8000-000000008802"
            for index in listed.indices {
                switch listed[index]["id"] as? String {
                case "00000000-0000-4000-8000-000000002212": listed[index]["assignedToUserId"] = jorge
                case "00000000-0000-4000-8000-000000002209": listed[index]["assignedToUserId"] = sam
                case "00000000-0000-4000-8000-000000002218": listed[index].removeValue(forKey: "assignedToUserId")
                case "00000000-0000-4000-8000-000000002224":
                    listed[index].removeValue(forKey: "assignedToUserId")
                    listed[index].removeValue(forKey: "scheduledFor")
                    listed[index]["createdAt"] = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3 * 86_400))
                default: break
                }
            }
            listed.append(["id": "00000000-0000-4000-8000-000000002230", "organizationId": PaperPreview.organizationID,
                           "customerId": "00000000-0000-4000-8000-000000000413", "title": "Garbage disposal jammed", "status": "scheduled",
                           "createdAt": ISO8601DateFormatter().string(from: Date().addingTimeInterval(-86_400)),
                           "updatedAt": ISO8601DateFormatter().string(from: Date().addingTimeInterval(-86_400)), "allowedTransitions": [String]()])
        }
        if PaperPreview.isPropertyHistoryPreview {
            if let index = listed.firstIndex(where: { ($0["id"] as? String) == PaperPreview.jobID }) {
                listed[index]["locationId"] = PaperPreview.homeLocationID
            }
            listed += propertyHistoryJobs()
        }
        // Next stop: each visit is at its customer's "Home" service location, so the card has an address.
        if PaperPreview.screen.hasPrefix("next-stop") {
            listed = listed.map { $0.merging(["locationId": "00000000-0000-4000-8000-000000007001"]) { _, new in new } }
        }
        // Today's and Jobs' rows lead with the street (design 2026-10-30); one visit has no site, so its row
        // shows the fallback to the job title (BYR-1593).
        if ["my-day", "schedule", "schedule-week", "jobs", "jobs-filters"].contains(PaperPreview.screen) || PaperPreview.screen.hasPrefix("search") {
            listed = listed.map { row in
                (row["id"] as? String)?.hasSuffix("2224") == true ? row
                    : row.merging(["locationId": "00000000-0000-4000-8000-000000007001"]) { _, new in new }
            }
        }
        // The owner's Home: three people out on the day, one visit with nobody on it and no site.
        if PaperPreview.screen == "owner-home" {
            let jorge = "00000000-0000-4000-8000-000000008801", sam = "00000000-0000-4000-8000-000000008802"
            let plan: [String: (String, Any)] = ["2214": ("en_route", jorge), "2212": ("in_progress", sam), "2209": ("completed", PaperPreview.actorID),
                                                 "2218": ("scheduled", PaperPreview.actorID), "2224": ("scheduled", NSNull()), "2201": ("completed", jorge)]
            listed = listed.map { row in
                guard let id = row["id"] as? String, let entry = plan[String(id.suffix(4))] else { return row }
                var next = row
                next["status"] = entry.0
                next["assignedToUserId"] = entry.1
                if !id.hasSuffix("2224") { next["locationId"] = "00000000-0000-4000-8000-000000007001" }
                return next
            }
            listed.append(["id": "00000000-0000-4000-8000-000000002231", "organizationId": PaperPreview.organizationID,
                           "customerId": "00000000-0000-4000-8000-000000000414", "title": "Furnace not igniting — Chen", "status": "open",
                           "createdAt": "2026-10-27T15:00:00Z", "updatedAt": "2026-10-27T15:00:00Z", "allowedTransitions": [String]()])
        }
        // Booked work with no time and no tech yet, only where the Unscheduled queue is the subject.
        if PaperPreview.screen == "schedule-unscheduled" {
            listed += [("2231", "0414", "Furnace not igniting — Chen", "2026-10-27T15:00:00Z"),
                       ("2232", "0415", "Garbage disposal jammed — Alvarez", "2026-10-30T09:00:00Z")].map { ref, customer, title, created in
                ["id": "00000000-0000-4000-8000-00000000\(ref)", "organizationId": PaperPreview.organizationID,
                 "customerId": "00000000-0000-4000-8000-00000000\(customer)", "title": title, "status": "open",
                 "createdAt": created, "updatedAt": created, "allowedTransitions": [String]()] as [String: Any]
            }
        }
        // The visit someone is on (Chen's water heater) has its site on every screen, so the iPad
        // sidebar's "On now" card leads with the same street on every place. The sample job keeps
        // its per-screen site: its screens show the title when it has none.
        listed = listed.map { row in
            row["status"] as? String == "in_progress" && row["locationId"] == nil && row["id"] as? String != PaperPreview.jobID
                ? row.merging(["locationId": PaperPreview.homeLocationID]) { _, new in new } : row
        }
        return listed
    }
    /// Owner Home: the July invoice still owed, one sent this morning and one paid off today.
    private static func ownerHomeInvoices() -> [[String: Any]] {
        guard let base = jsonObject(PaperPreview.issuedInvoice) as? [String: Any] else { return [] }
        let morning = today(hour: 9, minute: 40)
        func variant(_ ref: String, customer: String, status: String, cents: Int, paid: Int, paidAt: String?) -> [String: Any] {
            var row = base
            row["id"] = "00000000-0000-4000-8000-00000000\(ref)"
            row["customerId"] = "00000000-0000-4000-8000-00000000\(customer)"
            row["sourceOperationKey"] = "paper-preview-owner-\(ref)"
            row["status"] = status
            row["amountPaid"] = paid
            row["issuedAt"] = morning
            row["paidAt"] = paidAt ?? NSNull()
            row["lines"] = [["id": "00000000-0000-4000-8000-00000000\(ref)1", "description": "Service", "quantity": 1,
                             "unitPrice": ["amount": cents, "currency": "USD"], "source": ["kind": "manual"]]]
            return row
        }
        return [base, variant("2241", customer: "0414", status: "issued", cents: 124_000, paid: 0, paidAt: nil),
                variant("2242", customer: "0412", status: "paid", cents: 18_500, paid: 18_500, paidAt: today(hour: 11, minute: 5))]
    }
    /// Danielle's earlier jobs for `job-history`: four at Home (newest three show) and one with no site.
    private static func propertyHistoryJobs() -> [[String: Any]] {
        let rows: [(String, String, String, String, String?, String?)] = [
            ("2190", "Spring AC tune-up", "completed", "2026-04-14T16:00:00Z", PaperPreview.homeLocationID, PaperPreview.actorID),
            ("2181", "Water heater flush", "completed", "2025-11-03T15:00:00Z", PaperPreview.homeLocationID, "00000000-0000-4000-8000-000000008801"),
            ("2176", "Gutter check at the rental", "completed", "2025-09-02T15:00:00Z", nil, PaperPreview.actorID),
            ("2170", "Furnace install", "completed", "2021-10-20T15:00:00Z", PaperPreview.homeLocationID, "00000000-0000-4000-8000-000000008801"),
            ("2160", "Thermostat swap", "canceled", "2021-03-09T15:00:00Z", PaperPreview.homeLocationID, nil)
        ]
        // `customer-jobs` gets a long note on 2190 so the past row shows "More"; `job-history` keeps the short one.
        let long = PaperPreview.screen == "customer-jobs"
            ? " Condensate line was slow; flushed it and added a tablet. Filter is a 20x25x4, customer keeps spares in the garage. Breaker 14 is the condenser."
            : ""
        let notes = ["2190": "Coil cleaned, capacitor reading low. Quoted a replacement for next visit." + long,
                     "2181": "Sediment heavy. Anode rod due next year.", "2170": "Passed inspection. Replaced filter."]
        return rows.map { ref, title, status, when, location, assignee in
            ["id": "00000000-0000-4000-8000-00000000\(ref)", "organizationId": PaperPreview.organizationID,
             "customerId": PaperPreview.customerID, "title": title, "status": status,
             "assignedToUserId": assignee ?? NSNull(), "scheduledFor": when, "locationId": location ?? NSNull(),
             "notes": notes[ref] ?? NSNull(),
             "createdAt": when, "updatedAt": when, "allowedTransitions": [String]()] as [String: Any]
        }
    }
    private static func customers() -> [[String: Any]] {
        let shortName = ProcessInfo.processInfo.arguments.contains("--paper-preview-short-customer-name")
        let longName = ProcessInfo.processInfo.arguments.contains("--paper-preview-customer-name-long")
        let firstName = shortName ? "I" : (longName ? "Birch Community Hall and Neighborhood Services Center" : "Danielle Marlowe")
        let rows = [("0412", firstName, "412 Birchwood Ln"), ("0413", "Alex Petrov", "88 Larch Ave"), ("0414", "David Chen", "245 Rosemont Dr"), ("0415", "Elena Alvarez", "19 Fenwick Ct"), ("0416", "Mei Nakamura", "731 Cassia Way")]
        return rows.map { ref, name, address in
            ["id": "00000000-0000-4000-8000-00000000\(ref)", "organizationId": PaperPreview.organizationID, "name": name, "address": address,
             "accountType": "residential", "archived": false, "createdAt": "2022-03-01T12:00:00Z", "updatedAt": "2026-07-20T12:00:00Z", "billingTerms": "Due on receipt",
             "phone": PaperPreview.screen.hasPrefix("book-job") || PaperPreview.screen.hasPrefix("search") ? "(916) 555-0\(ref.suffix(3))" : NSNull()] as [String: Any]
        }
    }
}
#endif

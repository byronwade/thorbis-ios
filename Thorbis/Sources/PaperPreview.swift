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
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("--paper-preview") }
    static var screen: String {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--paper-preview-screen"), args.indices.contains(index + 1),
              ["schedule", "app-menu", "app-menu-edit", "bar-live", "bar-syncing", "search-typed", "side-menu", "side-menu-search", "ipad-sidebar", "settings", "whats-new", "schedule-week", "new-job", "create-menu", "schedule-unscheduled", "schedule-map", "customize-menu", "signature", "attention", "estimate-detail", "jobs", "my-day", "customers", "job", "job-invoice", "job-estimates", "job-activity", "job-media", "job-closeout", "job-assign", "job-followups", "offline", "offline-job", "customer", "customer-activity", "customer-records", "estimates", "invoices", "team", "reports", "billing", "billing-detail", "notices", "new-customer", "job-invoice-empty", "new-estimate", "price-book", "revenue", "menu", "more", "search", "inbox", "invoice-editor", "invoice-detail", "invoice-payment", "invoice-payment-refund", "invoice-payment-refund-form", "invoice-payment-refund-confirmation", "invoice-payment-refund-pending", "invoice-payment-refund-reconciliation", "estimate-revision", "estimate-draft", "estimate-draft-detail", "public-estimate", "present-estimate", "present-estimate-review", "present-invoice"].contains(args[index + 1]) else { return "schedule" }
        return args[index + 1]
    }
    /// Owner registration screens: --paper-preview-screen onboard-signup | onboard-company | onboard-details | onboard-setup.
    static var onboardingScreen: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--paper-preview-screen"), args.indices.contains(index + 1),
              ["onboard-signup", "onboard-company", "onboard-details", "onboard-setup"].contains(args[index + 1]) else { return nil }
        return args[index + 1]
    }
    static var isJobEstimateHandoff: Bool { enabled && ProcessInfo.processInfo.arguments.contains("--paper-preview-job-estimate-handoff") }
    static var isJobDocumentsPreview: Bool { enabled && ProcessInfo.processInfo.arguments.contains("--paper-preview-job-documents") }
    static func replacedDescriptionEstimate(_ estimate: EstimateRecord) -> EstimateRecord {
        changed(estimate, ["currentRevisionNumber": (estimate.currentRevisionNumber ?? 0) + 1])
    }
    @MainActor static func expireDocumentSessionForTesting(_ session: SessionController) async {
        let args = ProcessInfo.processInfo.arguments
        guard isJobDocumentsPreview, args.contains("--paper-preview-description-expire-session") || args.contains("--paper-preview-description-revoke-permission") || args.contains("--paper-preview-description-replace-session") else { return }
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
        if isJobDocumentsPreview && ProcessInfo.processInfo.arguments.contains("--paper-preview-job-estimate-invalid-money") {
            let invalid = FieldLine(id: "00000000-0000-4000-8000-000000009299", description: "Unverifiable sample amount", quantity: 2,
                                    unitPrice: FieldMoney(amount: Int.max, currency: "USD"), source: nil)
            draft = changed(draft, ["lines": try! JSONSerialization.jsonObject(with: JSONEncoder().encode([invalid]))])
        }
        return [changed(estimate, ["title": "Main drain repair", "options": NSNull()]), draft,
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
        let original = primary
        if isJobDocumentsMoneyPreview {
            let discount = FieldLine(id: "00000000-0000-4000-8000-000000009104", description: "Member discount", quantity: 1,
                                     unitPrice: FieldMoney(amount: -4_000, currency: "USD"), source: nil)
            primary = changed(primary, ["lines": try! JSONSerialization.jsonObject(with: JSONEncoder().encode(primary.lines + [discount])),
                                        "amountPaid": 15_000])
        }
        let equalBalances = ProcessInfo.processInfo.arguments.contains("--paper-preview-job-invoices-equal-balances")
        return [primary,
         changed(original, ["id": "00000000-0000-4000-8000-000000002240", "status": equalBalances ? "issued" : "paid", "origin": "estimate_deposit",
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
        return [card, cash]
    }
    private static func changed<T: Codable>(_ value: T, _ fields: [String: Any]) -> T {
        var object = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
        fields.forEach { object[$0.key] = $0.value }
        return try! JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object))
    }
    static var isWorkingJobPreview: Bool { enabled && ProcessInfo.processInfo.arguments.contains("--paper-preview-working-job") }
    static var isPaymentCollectionPreview: Bool { screen == "invoice-payment" || screen == "job-invoice" || isWorkingJobPreview }
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
        return try! JSONDecoder().decode(EstimateRecord.self, from: Data(json.utf8))
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
        func line(_ id: Int, _ text: String, _ quantity: Int, _ cents: Int) -> FieldLine {
            FieldLine(id: String(format: "00000000-0000-4000-8000-0000000093%02d", id), description: text, quantity: quantity,
                      unitPrice: FieldMoney(amount: cents, currency: "USD"), source: nil)
        }
        func option(_ id: Int, _ title: String, _ text: String, _ lines: [FieldLine]) -> FieldEstimateOption {
            FieldEstimateOption(id: String(format: "00000000-0000-4000-8000-0000000094%02d", id), title: title, description: text, lines: lines,
                                totalAmount: paperLinesTotal(lines) ?? 0, currency: "USD")
        }
        let repair = [line(1, "Run capacitor, 45/5 µF", 1, 14_500), line(2, "Coil cleaning", 2, 12_000), line(3, "Labor, licensed technician", 1, 9_500)]
        let better = repair + [line(4, "Surge protector, installed", 1, 39_500), line(5, "One-year parts warranty", 1, 151_000)]
        let replace = [line(6, "3-ton high-efficiency condenser", 1, 690_000), line(7, "Installation and haul-away", 1, 220_000), line(8, "Ten-year warranty registration", 1, 75_000)]
        return EstimateRecord(id: estimate.id, organizationId: estimate.organizationId, customerId: customerID, createdByUserId: estimate.createdByUserId,
                              locationId: nil, status: "sent", currentRevisionNumber: 2, title: "AC not cooling", lines: [],
                              options: [option(1, "Repair", "Replace the failed capacitor and clean the coil.", repair),
                                        option(2, "Repair and protect", "The repair plus a surge protector and a one-year parts warranty.", better),
                                        option(3, "Replace", "A new high-efficiency unit with a ten-year warranty.", replace)],
                              createdAt: estimate.createdAt, updatedAt: estimate.updatedAt, sentAt: estimate.sentAt, approvedAt: nil, declinedAt: nil)
    }
    static var invoice: InvoiceRecord {
        let json = #"{"id":"00000000-0000-4000-8000-000000002209","organizationId":"00000000-0000-4000-8000-000000000002","customerId":"00000000-0000-4000-8000-000000000412","jobId":"00000000-0000-4000-8000-000000002214","createdByUserId":"00000000-0000-4000-8000-000000000001","locationId":null,"scheduleId":null,"origin":"job_completion","sourceOperationKey":"paper-preview-invoice","sourceEstimateId":null,"sourceEstimateRevisionNumber":null,"manualPhysicalServiceEvidence":null,"status":"draft","lines":[{"id":"00000000-0000-4000-8000-000000009101","description":"Compressor diagnostic","quantity":1,"unitPrice":{"amount":12000,"currency":"USD"},"source":{"kind":"manual"}},{"id":"00000000-0000-4000-8000-000000009102","description":"Refrigerant recharge","quantity":2,"unitPrice":{"amount":9000,"currency":"USD"},"source":{"kind":"manual"}},{"id":"00000000-0000-4000-8000-000000009103","description":"Trip fee","quantity":1,"unitPrice":{"amount":4000,"currency":"USD"},"source":{"kind":"manual"}}],"linesRevision":3,"amountPaid":0,"currency":"USD","issuedAt":null,"paidAt":null,"voidedAt":null,"createdAt":"2026-07-18T12:00:00Z","updatedAt":"2026-07-20T12:00:00Z"}"#
        return try! JSONDecoder().decode(InvoiceRecord.self, from: Data(json.utf8))
    }
    static var issuedInvoice: InvoiceRecord {
        let json = #"{"id":"00000000-0000-4000-8000-000000002209","organizationId":"00000000-0000-4000-8000-000000000002","customerId":"00000000-0000-4000-8000-000000000412","jobId":"00000000-0000-4000-8000-000000002214","createdByUserId":"00000000-0000-4000-8000-000000000001","locationId":null,"scheduleId":null,"origin":"job_completion","sourceOperationKey":"paper-preview-invoice","sourceEstimateId":null,"sourceEstimateRevisionNumber":null,"manualPhysicalServiceEvidence":null,"status":"issued","lines":[{"id":"00000000-0000-4000-8000-000000009101","description":"Compressor diagnostic","quantity":1,"unitPrice":{"amount":12000,"currency":"USD"},"source":{"kind":"manual"}},{"id":"00000000-0000-4000-8000-000000009102","description":"Refrigerant recharge","quantity":2,"unitPrice":{"amount":9000,"currency":"USD"},"source":{"kind":"manual"}},{"id":"00000000-0000-4000-8000-000000009103","description":"Trip fee","quantity":1,"unitPrice":{"amount":4000,"currency":"USD"},"source":{"kind":"manual"}}],"linesRevision":3,"amountPaid":0,"currency":"USD","issuedAt":"2026-07-20T12:00:00Z","paidAt":null,"voidedAt":null,"createdAt":"2026-07-20T12:00:00Z","updatedAt":"2026-07-20T12:00:00Z"}"#
        let fixture = ProcessInfo.processInfo.arguments.contains("--paper-preview-large-invoice")
            ? json.replacingOccurrences(of: "\"amount\":12000", with: "\"amount\":123456789") : json
        return try! JSONDecoder().decode(InvoiceRecord.self, from: Data(fixture.utf8))
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
        var invoiceReads = 0
        var reviewConnectionRestored = false
        var ownerAuthenticated = false
        var estimateUnavailable = false
        var documentStatusesChanged = false
        var savedWorkOffline = false
        var savedWorkWorkspaceChanged = false
        var savedWorkEditingRevoked = false
        var priceBookViewRevoked = false
        var documentEstimateViewRevoked = false
        var jobMediaViewRevoked = false
        var priceBookReads = 0
        var priceBookQueryFailed = false
        var savedWorkMutationCount = 0
    }
    private static let scenario = Scenario()
    static func resetScenario() {
        if PaperPreview.isJobEstimateHandoff { JobEstimateHandoffPreview.shared.reset() }
        scenario.lock.withLock { scenario.setupPaymentReads = 0; scenario.invoiceReads = 0; scenario.reviewConnectionRestored = false; scenario.ownerAuthenticated = false; scenario.estimateUnavailable = false; scenario.documentStatusesChanged = false; scenario.savedWorkOffline = false; scenario.savedWorkWorkspaceChanged = false; scenario.savedWorkEditingRevoked = false; scenario.priceBookViewRevoked = false; scenario.documentEstimateViewRevoked = false; scenario.jobMediaViewRevoked = false; scenario.priceBookReads = 0; scenario.priceBookQueryFailed = false; scenario.savedWorkMutationCount = 0 }
    }
    static func beginSavedWorkOffline() -> Bool {
        scenario.lock.withLock {
            guard !scenario.savedWorkOffline else { return false }
            scenario.savedWorkOffline = true; return true
        }
    }
    static var savedWorkMutationCount: Int { scenario.lock.withLock { scenario.savedWorkMutationCount } }
    static func revokeSavedWorkEditing() { scenario.lock.withLock { scenario.savedWorkEditingRevoked = true } }
    static func revokeDocumentEstimateView() { scenario.lock.withLock { scenario.documentEstimateViewRevoked = true } }
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
        if request.httpMethod != nil && request.httpMethod != "GET" {
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
                  ProcessInfo.processInfo.arguments.contains("--paper-preview-deposit-history-failure"),
                  url.path == "/v1/invoices/00000000-0000-4000-8000-000000002240/payments" {
            status = 503
            payload = ["status": 503, "title": "Sample payment history unavailable"]
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
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}

    private static func fixture(path: String, queryItems: [URLQueryItem] = [], isFresh: Bool = false) -> Any? {
        let actor = PaperPreview.actorID
        let changedWorkspace = (PaperPreview.isSavedWorkPreview || PaperPreview.screen == "price-book") && scenario.lock.withLock { scenario.savedWorkWorkspaceChanged }
        let org = changedWorkspace ? "00000000-0000-4000-8000-000000000003" : PaperPreview.organizationID
        let expiry = ISO8601DateFormatter().string(from: PaperPreview.isSavedWorkPreview && ProcessInfo.processInfo.arguments.contains("--paper-preview-saved-work-expiry") ? PaperPreview.savedWorkDeadline : Date().addingTimeInterval(86_400))
        let now = ISO8601DateFormatter().string(from: Date())
        if changedWorkspace, path == "/v1/jobs" || path == "/v1/customers" { return ["items": []] }
        if PaperPreview.isSavedWorkPreview, path == "/v1/jobs/\(PaperPreview.savedWorkUncachedJobID)" {
            return ["id": PaperPreview.savedWorkUncachedJobID, "organizationId": org, "customerId": PaperPreview.customerID,
                    "title": "Uncached drain visit", "status": "dispatched", "createdAt": now, "updatedAt": now, "allowedTransitions": ["en_route"]]
        }
        if PaperPreview.screen.hasPrefix("present-estimate") {
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
                return ["items": invoices.filter { $0.jobId == PaperPreview.jobID }.map { jsonObject($0)! }]
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
                return reviewRevision(record)
            }
            if let record = invoices.first(where: { path == "/v1/invoices/\($0.id)" }) {
                var object = jsonObject(record) as! [String: Any]
                if record.id == invoices[0].id, scenario.lock.withLock({ scenario.documentStatusesChanged }) {
                    object["status"] = "void"
                }
                if ProcessInfo.processInfo.arguments.contains("--paper-preview-job-invoice-foreign") ||
                    scenario.lock.withLock({ scenario.ownerAuthenticated }) {
                    object["jobId"] = "00000000-0000-4000-8000-000000002215"
                }
                return object
            }
            if PaperPreview.isJobDocumentsMoneyPreview, path == "/v1/invoices/\(invoices[0].id)/payments" {
                return ["items": PaperPreview.jobDocumentMoneyPayments.map { jsonObject($0)! }]
            }
            if path == "/v1/invoices/\(invoices[1].id)/payments" {
                if ProcessInfo.processInfo.arguments.contains("--paper-preview-job-invoices-equal-balances") { return ["items": []] }
                var payment = jsonObject(PaperPreview.refundPayment) as! [String: Any]
                payment["invoiceId"] = invoices[1].id
                payment["amount"] = ["amount": 34000, "currency": "USD"]
                payment["netAmount"] = ["amount": 34000, "currency": "USD"]
                return ["items": [payment]]
            }
        }
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
        if path == "/v1/notice-preferences" {
            return ["items": [["subjectKind": "role", "subjectKey": "technician", "channel": "email", "enabled": false]]]
        }
        if path == "/v1/staff/notices", PaperPreview.screen == "inbox" {
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
        if path == "/v1/jobs/\(PaperPreview.jobID)/invoices" {
            if PaperPreview.screen == "job-invoice-empty" { return ["items": []] }
            return ["items": [try! JSONSerialization.jsonObject(with: JSONEncoder().encode(PaperPreview.issuedInvoice))]]
        }
        if path == "/v1/invoices" && PaperPreview.screen == "job-invoice-empty" { return ["items": []] }
        if path == "/v1/invoices" {
            let item = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(PaperPreview.issuedInvoice)) as? [String: Any]
            return ["items": matchingCustomer(item.map { [$0] } ?? [], queryItems: queryItems)]
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
            return ["organizationId": org, "coreReady": false, "missingCore": ["business_address", "primary_phone"],
                    "facts": [["factKey": "legal_name", "label": "Legal business name", "tier": 1, "value": "Wade’s Plumbing LLC",
                               "source": "user_confirmed", "confirmedAt": now, "version": 1]],
                    "catalog": catalog.map { ["factKey": $0.0, "label": $0.1, "tier": $0.2, "required": $0.3, "confirmed": $0.0 == "legal_name"] }] as [String: Any]
        }
        switch path {
        case "/api/auth/get-session":
            if ProcessInfo.processInfo.arguments.contains("--paper-preview-media-cleanup-failure") { return NSNull() }
            return ["user": ["id": actor, "name": "Ramon Marlowe", "email": "preview@example.invalid"], "session": ["userId": actor, "activeOrganizationId": org, "expiresAt": expiry]]
        case "/api/auth/organization/list": return [["id": org, "name": changedWorkspace ? "Sample workspace B" : "Wade’s Plumbing · Preview"]]
        case "/v1/query/catalog":
            var capabilities = ["job.view", "job.create", "job.edit", "job.note", "job.assign", "customer.view", "customer.create", "customer.edit", "estimate.view", "estimate.create", "estimate.approve", "estimate.discount", "invoice.view", "invoice.edit", "invoice.issue", "pricebook.view"]
            if PaperPreview.screen == "job-media", scenario.lock.withLock({ scenario.jobMediaViewRevoked }) { capabilities.removeAll { $0 == "job.view" } }
            if PaperPreview.isSavedWorkPreview, scenario.lock.withLock({ scenario.savedWorkEditingRevoked }) { capabilities.removeAll { $0 == "job.edit" } }
            if PaperPreview.isJobDocumentsPreview, scenario.lock.withLock({ scenario.documentEstimateViewRevoked }) { capabilities.removeAll { $0 == "estimate.view" } }
            if PaperPreview.screen == "price-book", scenario.lock.withLock({ scenario.priceBookViewRevoked }) { capabilities.removeAll { $0 == "pricebook.view" } }
            if PaperPreview.isPaymentCollectionPreview { capabilities.append("invoice.payment.create") }
            if PaperPreview.isPaymentRefundPreview { capabilities.append("invoice.refund") }
            if PaperPreview.screen == "team" { capabilities.append("organization.members.manage") }
            if ["job-invoice-empty", "billing-detail"].contains(PaperPreview.screen) { capabilities.append("invoice.create") }
            if PaperPreview.screen == "notices" { capabilities.append("organization.settings.edit") }
            if PaperPreview.screen == "price-book", ProcessInfo.processInfo.arguments.contains("--paper-preview-pricebook-admin") { capabilities.append("organization.settings.edit") }
            if PaperPreview.onboardingScreen != nil { capabilities += ["organization.settings.edit", "organization.members.manage", "pricebook.edit"] }
            return ["authority": ["actorId": actor, "organizationId": org, "policyVersion": 1, "generation": "paper-preview", "authorityExpiresAt": expiry],
                    "capabilities": capabilities,
                    "resources": [], "views": []] as [String: Any]
        case "/v1/features":
            let decision = ["enabled": true, "released": true, "entitled": true]
            var enabledFeatures = ["jobs", "core_crm", "estimates", "estimate_option_signing", "invoicing", "price_book"]
            if PaperPreview.isPaymentRefundPreview || PaperPreview.isPaymentCollectionPreview || PaperPreview.screen == "revenue" { enabledFeatures.append("payments") }
            if PaperPreview.screen.hasPrefix("billing") { enabledFeatures.append("progress_billing") }
            if ["notices", "inbox"].contains(PaperPreview.screen) { enabledFeatures.append("job_booking_notices") }
            let features = Dictionary(uniqueKeysWithValues: enabledFeatures.map { ($0, decision) })
            return ["organizationId": org, "evaluatedAt": now, "features": features]
        // Like the server, list items carry no allowedTransitions; only GET /v1/jobs/{id} does.
        case "/v1/jobs":
            let items = jobs().map { $0.filter { $0.key != "allowedTransitions" } }
            return ["items": matchingCustomer(items, queryItems: queryItems)]
        case "/v1/customers": return ["items": customers()]
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
               ProcessInfo.processInfo.arguments.contains("--paper-preview-catalog-pages"),
               queryItems.first(where: { $0.name == "resourceId" })?.value == "price_book_items" {
                let cursor = "00000000-0000-4000-8000-000000009988"
                let later = queryItems.first(where: { $0.name == "cursor" })?.value == cursor
                let rows = later ? [(9999, "Camera sewer inspection")] : (1...50).map { (9700 + $0, "Plumbing catalog service \($0)") }
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
            if path == "/v1/jobs/\(id)/media", PaperPreview.screen == "customer-records",
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
            if path == "/v1/jobs/\(id)/photos", PaperPreview.screen == "customer-records",
               ProcessInfo.processInfo.arguments.contains("--paper-preview-mixed-photo-rollup") {
                let isFirst = id.hasSuffix("2214")
                let photoID = isFirst ? "00000000-0000-4000-8000-000000033000" : "00000000-0000-4000-8000-000000033001"
                let key = isFirst ? "preview/00000000-0000-4000-8000-000000031000" : "preview/legacy-photo"
                guard isFirst || id.hasSuffix("2201") else { return ["items": []] }
                return ["items": [["id": photoID, "organizationId": org, "jobId": id, "authorUserId": actor,
                                   "contentType": "image/png", "byteSize": 73, "storageKey": key, "createdAt": now]]]
            }
            if path == "/v1/jobs/\(id)/media", PaperPreview.screen == "job-media" {
                let first: [String: Any] = [
                    "id": "00000000-0000-4000-8000-000000009301", "organizationId": org, "jobId": id,
                    "uploaderUserId": actor, "kind": "photo", "mime": "image/jpeg", "sizeBytes": 120_000,
                    "originalFilename": "outdoor-unit.jpg", "contentHash": "preview", "storageKey": "preview/outdoor-unit.jpg",
                    "uploadState": "stored", "tags": ["Before"], "caption": "Outdoor unit", "archived": false,
                    "createdAt": now, "updatedAt": now
                ]
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
                return ["items": [["id": "00000000-0000-4000-8000-000000007001", "organizationId": org, "customerId": id,
                                    "label": "Home", "kind": "service", "address": address,
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
             PaperPreview.isWorkingJobPreview ? "in_progress" : "dispatched", 10, 30),
            ("2212", "0413", "Kitchen sink backup — Petrov", "scheduled", 12, 15),
            ("2209", "0414", "Water heater install — Chen", "in_progress", 13, 0),
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
        // Booked work with no time and no tech yet, only where the Unscheduled queue is the subject.
        if PaperPreview.screen == "schedule-unscheduled" {
            listed += [("2231", "0414", "Furnace not igniting — Chen", "2026-10-27T15:00:00Z"),
                       ("2232", "0415", "Garbage disposal jammed — Alvarez", "2026-10-30T09:00:00Z")].map { ref, customer, title, created in
                ["id": "00000000-0000-4000-8000-00000000\(ref)", "organizationId": PaperPreview.organizationID,
                 "customerId": "00000000-0000-4000-8000-00000000\(customer)", "title": title, "status": "open",
                 "createdAt": created, "updatedAt": created, "allowedTransitions": [String]()] as [String: Any]
            }
        }
        return listed
    }
    private static func customers() -> [[String: Any]] {
        let shortName = ProcessInfo.processInfo.arguments.contains("--paper-preview-short-customer-name")
        let longName = ProcessInfo.processInfo.arguments.contains("--paper-preview-customer-name-long")
        let firstName = shortName ? "I" : (longName ? "Birch Community Hall and Neighborhood Services Center" : "Danielle Marlowe")
        let rows = [("0412", firstName, "412 Birchwood Ln"), ("0413", "Alex Petrov", "88 Larch Ave"), ("0414", "David Chen", "245 Rosemont Dr"), ("0415", "Elena Alvarez", "19 Fenwick Ct"), ("0416", "Mei Nakamura", "731 Cassia Way")]
        return rows.map { ref, name, address in
            ["id": "00000000-0000-4000-8000-00000000\(ref)", "organizationId": PaperPreview.organizationID, "name": name, "address": address,
             "accountType": "residential", "archived": false, "createdAt": "2022-03-01T12:00:00Z", "updatedAt": "2026-07-20T12:00:00Z", "billingTerms": "Due on receipt"] as [String: Any]
        }
    }
}
#endif

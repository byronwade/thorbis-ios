import Foundation
import CryptoKit

/// A server-produced customer presentation. It is not a signed invoice.
struct CustomerInvoiceSummary: Decodable, Sendable {
    struct Consent: Decodable, Sendable {
        let digest: String
        let consentVersion: String
        let consentText: String
    }
    struct Line: Decodable, Equatable, Sendable {
        let id: String
        let description: String
        let quantity: Int
        let unitPrice: FieldMoney
    }

    let kind: String
    let presentationVersion: Int
    let presentationScopeId: String
    let isSignedDocument: Bool
    let issuedSnapshotId: String?
    let organizationId: String
    let customerId: String
    let invoiceId: String
    let jobId: String?
    let linesRevision: Int
    let status: String
    let currency: String
    let lines: [Line]
    let totalAmount: Int
    let amountPaid: Int
    let balanceDue: Int
    let summaryConsent: Consent?

    /// Only the known consent version and exact wording can start a signing attempt.
    var validatedConsent: Consent? {
        guard let jobId, let consent = summaryConsent,
              [organizationId, customerId, jobId, invoiceId].allSatisfy({ UUID(uuidString: $0) != nil }),
              lines.allSatisfy({ UUID(uuidString: $0.id) != nil }),
              matches(organizationID: organizationId, customerID: customerId, jobID: jobId,
                      invoiceID: invoiceId, linesRevision: linesRevision),
              status != "void", consent.consentVersion == "invoice-summary-consent-v1",
              consent.consentText == "I approve the customer invoice summary shown above. Payment status is not part of this authorization.",
              consent.digest.range(of: "^sha256:[0-9a-f]{64}$", options: .regularExpression) != nil else { return nil }
        return consent
    }

    /// Identity and arithmetic only. The caller must also prove current session,
    /// permission, request generation and a fresh server response before display.
    func matches(scope: JobDocumentScope, invoiceID: String, linesRevision expectedRevision: Int) -> Bool {
        matches(organizationID: scope.organizationID, customerID: scope.customerID, jobID: scope.jobID,
                invoiceID: invoiceID, linesRevision: expectedRevision)
    }

    func matches(organizationID: String, customerID: String, jobID: String?, invoiceID: String, linesRevision expectedRevision: Int) -> Bool {
        guard kind == "customer_invoice_presentation", presentationVersion == 1, !isSignedDocument,
              organizationId == organizationID, customerId == customerID,
              jobId == jobID, invoiceId == invoiceID, linesRevision == expectedRevision,
              expectedRevision > 0,
              presentationScopeId == "invoice:\(invoiceID):lines:\(expectedRevision):customer:v1",
              currency == "USD", ["draft", "issued", "paid", "void"].contains(status),
              lines.count <= 500, totalAmount >= 0, amountPaid >= 0, amountPaid <= totalAmount,
              (status == "draft" ? issuedSnapshotId == nil : issuedSnapshotId.flatMap(UUID.init(uuidString:)) != nil) else { return false }
        var total = 0
        var ids = Set<String>()
        for line in lines {
            guard !line.id.isEmpty, ids.insert(line.id).inserted, line.quantity > 0,
                  line.unitPrice.currency == currency else { return false }
            let (extended, overflow) = line.unitPrice.amount.multipliedReportingOverflow(by: line.quantity)
            guard !overflow else { return false }
            let (next, sumOverflow) = total.addingReportingOverflow(extended)
            guard !sumOverflow else { return false }
            total = next
        }
        guard total == totalAmount else { return false }
        if status == "draft" && amountPaid != 0 { return false }
        let expectedDue = status == "void" ? 0 : totalAmount - amountPaid
        let fullyPaid = totalAmount > 0 && amountPaid == totalAmount
        guard status != "paid" || fullyPaid, status != "issued" || !fullyPaid else { return false }
        return balanceDue == expectedDue
    }
}

/// A receipt for the visible summary; this is not an authorization of the raw invoice.
struct CustomerInvoiceSummaryReceipt: Decodable, Sendable {
    let kind: String
    let id: String
    let organizationId: String
    let customerId: String
    let jobId: String
    let invoiceId: String
    let linesRevision: Int
    let issuedSnapshotId: String?
    let digest: String
    let consentVersion: String
    let consentText: String
    let signerName: String
    let signedAt: String
    let recordedAt: String
    let currency: String
    let totalAmount: Int
    let lines: [CustomerInvoiceSummary.Line]

    private func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    func matches(summary: CustomerInvoiceSummary, signerName expectedSigner: String, signedAt expectedSignedAt: String) -> Bool {
        guard let expectedTime = date(expectedSignedAt), let consent = summary.validatedConsent, UUID(uuidString: id) != nil,
              kind == "signed_customer_invoice_summary", organizationId == summary.organizationId,
              customerId == summary.customerId, jobId == summary.jobId, invoiceId == summary.invoiceId,
              linesRevision == summary.linesRevision, issuedSnapshotId == summary.issuedSnapshotId,
              digest == consent.digest, consentVersion == consent.consentVersion, consentText == consent.consentText,
              signerName == expectedSigner, !signerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              date(signedAt) == expectedTime, date(recordedAt) != nil,
              currency == summary.currency, totalAmount == summary.totalAmount, lines == summary.lines else { return false }
        return true
    }
}

/// Only a fresh, explicit server response can establish whether the current terms were signed.
enum CustomerSummaryAuthorizationState {
    case unsigned
    case signed(CustomerInvoiceSummaryReceipt)
}

private struct CustomerSummaryAuthorizationLookup: Decodable {
    let status: String
    let receipt: CustomerInvoiceSummaryReceipt?
}

/// Freeze every field across uncertain network retries so the server can replay one attempt.
struct CustomerSummarySigningAttempt: Encodable, Sendable {
    let expectedLinesRevision: Int
    let presentationScopeId: String
    let consentDigest: String
    let consent = true
    let consentVersion: String
    let signerName: String
    let signedAt: String
    let imageMediaId: String
    let idempotencyKey: String

    init?(summary: CustomerInvoiceSummary, signerName: String, signedAt: String, imageMediaId: String, idempotencyKey: String) {
        guard let consent = summary.validatedConsent, !signerName.isEmpty, signerName.count <= 120,
              signerName == signerName.trimmingCharacters(in: .whitespacesAndNewlines),
              ISO8601DateFormatter().date(from: signedAt) != nil,
              UUID(uuidString: imageMediaId) != nil, UUID(uuidString: idempotencyKey) != nil else { return nil }
        expectedLinesRevision = summary.linesRevision
        presentationScopeId = summary.presentationScopeId
        consentDigest = consent.digest
        consentVersion = consent.consentVersion
        self.signerName = signerName; self.signedAt = signedAt
        self.imageMediaId = imageMediaId; self.idempotencyKey = idempotencyKey
    }
}

/// Owned by the handoff, not a transient screen, while a signing outcome is uncertain.
struct CustomerSummaryFrozenSignature: Equatable {
    let signerName: String
    let signedAt: String
    let png: Data
    let clientAssetID: String
    let idempotencyKey: String
}

@MainActor
final class CustomerSummarySigningContext {
    private let summary: CustomerInvoiceSummary
    private let current: @MainActor () -> Bool
    private let actorID: String
    private var frozen: CustomerSummaryFrozenSignature?
    private var uploadedMediaID: String?
    private var retired = false

    init(summary: CustomerInvoiceSummary, actorID: String, current: @escaping @MainActor () -> Bool) {
        self.summary = summary; self.actorID = actorID; self.current = current
    }
    private func checkCurrent() throws {
        try Task.checkCancellation()
        guard !retired, current(), UUID(uuidString: actorID) != nil, summary.validatedConsent != nil else { throw CancellationError() }
    }
    func freeze(signerName: String, signedAt: String, png: Data) throws -> CustomerSummaryFrozenSignature {
        try checkCurrent()
        let name = signerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 120, !png.isEmpty, png.count <= 8 * 1024 * 1024,
              ISO8601DateFormatter().date(from: signedAt) != nil else {
            throw Problem(title: "Enter your name and signature", status: nil, detail: nil)
        }
        if let frozen {
            guard frozen.signerName == name, frozen.signedAt == signedAt, frozen.png == png else {
                throw Problem(title: "Check the previous signature first", status: 409, detail: "The original summary and signature must be retained.")
            }
            return frozen
        }
        let value = CustomerSummaryFrozenSignature(signerName: name, signedAt: signedAt, png: png,
            clientAssetID: UUID().uuidString.lowercased(), idempotencyKey: UUID().uuidString.lowercased())
        frozen = value
        return value
    }
    func acceptUploadedMedia(_ asset: MediaAssetRecord) throws {
        try checkCurrent()
        guard let frozen, UUID(uuidString: asset.id) != nil,
              asset.organizationId == summary.organizationId, asset.jobId == summary.jobId, asset.uploaderUserId == actorID,
              asset.kind == "photo", asset.mime == "image/png", asset.tags.contains("signature"), asset.uploadState == "stored", !asset.archived,
              asset.sizeBytes == frozen.png.count,
              asset.contentHash == SHA256.hash(data: frozen.png).map({ String(format: "%02x", $0) }).joined() else {
            throw Problem(title: "Signature image couldn't be verified", status: 409, detail: nil)
        }
        guard uploadedMediaID == nil || uploadedMediaID == asset.id else {
            throw Problem(title: "Check the previous signature first", status: 409, detail: nil)
        }
        uploadedMediaID = asset.id
    }
    func attempt() throws -> CustomerSummarySigningAttempt {
        try checkCurrent()
        guard let frozen, let uploadedMediaID,
              let attempt = CustomerSummarySigningAttempt(summary: summary, signerName: frozen.signerName,
                signedAt: frozen.signedAt, imageMediaId: uploadedMediaID, idempotencyKey: frozen.idempotencyKey) else {
            throw Problem(title: "Signature isn't ready", status: nil, detail: nil)
        }
        return attempt
    }
    func retire() { retired = true; frozen = nil; uploadedMediaID = nil }
}

@MainActor
extension APIClient {
    /// A 404, stale digest or offline response is an error, never evidence that the summary is unsigned.
    func currentCustomerSummaryAuthorization(_ summary: CustomerInvoiceSummary,
                                             currentAuthority: @escaping @MainActor () -> Bool) async throws -> CustomerSummaryAuthorizationState {
        let generation = requestGeneration
        let savedScope = savedCopyScopeRevision
        let origin = normalizedOrigin
        func check() throws {
            try Task.checkCancellation()
            guard generation == requestGeneration, savedScope == savedCopyScopeRevision,
                  origin != nil, origin == normalizedOrigin, currentAuthority(), summary.validatedConsent != nil else { throw CancellationError() }
        }
        try check()
        guard let consent = summary.validatedConsent else { throw CancellationError() }
        let path = try financialPath("/v1/invoices", id: summary.invoiceId, suffix: "/customer-presentation/summary-authorization")
        let result: CustomerSummaryAuthorizationLookup = try await send("GET", path,
            queryItems: [URLQueryItem(name: "digest", value: consent.digest)], requireFresh: true)
        try check()
        if result.status == "unsigned", result.receipt == nil { return .unsigned }
        if result.status == "signed", let receipt = result.receipt,
           receipt.matches(summary: summary, signerName: receipt.signerName, signedAt: receipt.signedAt) { return .signed(receipt) }
        throw Problem(title: "This signed summary couldn't be verified", status: 409, detail: "Ask your technician to check the invoice.")
    }

    /// The caller owns a single immutable attempt across retry, and must check current invoice-edit authority.
    func authorizeCustomerInvoiceSummary(_ summary: CustomerInvoiceSummary, attempt: CustomerSummarySigningAttempt,
                                         currentAuthority: @escaping @MainActor () -> Bool) async throws -> CustomerInvoiceSummaryReceipt {
        let generation = requestGeneration
        let savedScope = savedCopyScopeRevision
        let origin = normalizedOrigin
        func check() throws {
            try Task.checkCancellation()
            guard generation == requestGeneration, savedScope == savedCopyScopeRevision,
                  origin != nil, origin == normalizedOrigin, currentAuthority(),
                  let consent = summary.validatedConsent,
                  attempt.expectedLinesRevision == summary.linesRevision, attempt.presentationScopeId == summary.presentationScopeId,
                  attempt.consentDigest == consent.digest, attempt.consentVersion == consent.consentVersion else { throw CancellationError() }
        }
        try check()
        let path = try financialPath("/v1/invoices", id: summary.invoiceId, suffix: "/customer-presentation/summary-authorizations")
        let receipt: CustomerInvoiceSummaryReceipt = try await send("POST", path, body: attempt)
        try check()
        guard receipt.matches(summary: summary, signerName: attempt.signerName, signedAt: attempt.signedAt) else {
            throw Problem(title: "This signed summary couldn't be verified", status: 409, detail: "Ask your technician to check the invoice.")
        }
        return receipt
    }

    /// Fetches the server's separate customer view, never a saved invoice copy.
    func customerInvoiceSummary(scope: JobDocumentScope, invoiceID: String, linesRevision: Int,
                                currentAuthority: @escaping @MainActor () -> Bool) async throws -> CustomerInvoiceSummary {
        try await customerInvoiceSummary(organizationID: scope.organizationID, customerID: scope.customerID,
            jobID: scope.jobID, invoiceID: invoiceID, linesRevision: linesRevision, currentAuthority: currentAuthority)
    }

    func customerInvoiceSummary(organizationID: String, customerID: String, jobID: String?, invoiceID: String,
                                linesRevision: Int, currentAuthority: @escaping @MainActor () -> Bool) async throws -> CustomerInvoiceSummary {
        let generation = requestGeneration
        let savedScope = savedCopyScopeRevision
        let origin = normalizedOrigin
        func check() throws {
            try Task.checkCancellation()
            guard generation == requestGeneration, savedScope == savedCopyScopeRevision,
                  origin != nil, origin == normalizedOrigin, currentAuthority() else { throw CancellationError() }
        }
        try check()
        let path = try financialPath("/v1/invoices", id: invoiceID, suffix: "/customer-presentation")
        let summary: CustomerInvoiceSummary = try await send("GET", path, requireFresh: true)
        try check()
        guard summary.matches(organizationID: organizationID, customerID: customerID, jobID: jobID,
                              invoiceID: invoiceID, linesRevision: linesRevision) else {
            throw Problem(title: "This invoice summary couldn't be verified", status: 409,
                          detail: "Ask your technician to refresh the invoice.")
        }
        return summary
    }
}

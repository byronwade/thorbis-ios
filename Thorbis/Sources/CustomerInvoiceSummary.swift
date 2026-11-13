import Foundation
import CryptoKit
import Combine
import Security

/// A server-produced customer presentation. It is not a signed invoice.
struct CustomerInvoiceSummary: Codable, Sendable {
    struct Consent: Codable, Sendable {
        let digest: String
        let consentVersion: String
        let consentText: String
    }
    struct Line: Codable, Equatable, Sendable {
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
struct CustomerSummarySigningAttempt: Codable, Equatable, Sendable {
    let expectedLinesRevision: Int
    let presentationScopeId: String
    let consentDigest: String
    let consent: Bool
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
        self.consent = true
        expectedLinesRevision = summary.linesRevision
        presentationScopeId = summary.presentationScopeId
        consentDigest = consent.digest
        consentVersion = consent.consentVersion
        self.signerName = signerName; self.signedAt = signedAt
        self.imageMediaId = imageMediaId; self.idempotencyKey = idempotencyKey
    }
}

/// One unresolved submission per invoice and actor, even if the invoice later changes.
struct CustomerSummaryPendingScope: Codable, Equatable {
    let origin: String
    let actorID: String
    let organizationID: String
    let customerID: String
    let jobID: String
    let invoiceID: String

    @MainActor var canonical: CustomerSummaryPendingScope? {
        guard let origin = APIClient.normalizedOrigin(origin),
              let actor = UUID(uuidString: actorID), let organization = UUID(uuidString: organizationID),
              let customer = UUID(uuidString: customerID), let job = UUID(uuidString: jobID),
              let invoice = UUID(uuidString: invoiceID) else { return nil }
        return .init(origin: origin, actorID: actor.uuidString.lowercased(), organizationID: organization.uuidString.lowercased(),
                     customerID: customer.uuidString.lowercased(), jobID: job.uuidString.lowercased(), invoiceID: invoice.uuidString.lowercased())
    }
    @MainActor var isValid: Bool { canonical != nil }
}

/// Contains no signature image or login credential. The exact previously displayed terms
/// allow an old receipt to be checked after the current invoice revision changes.
struct CustomerSummaryPendingAttempt: Codable {
    let scope: CustomerSummaryPendingScope
    let summary: CustomerInvoiceSummary
    let attempt: CustomerSummarySigningAttempt

    @MainActor func isValid(for expected: CustomerSummaryPendingScope) -> Bool {
        guard let canonical = expected.canonical, scope.canonical == canonical, let consent = summary.validatedConsent,
              UUID(uuidString: summary.organizationId) == UUID(uuidString: canonical.organizationID),
              UUID(uuidString: summary.customerId) == UUID(uuidString: canonical.customerID),
              summary.jobId.flatMap(UUID.init(uuidString:)) == UUID(uuidString: canonical.jobID),
              UUID(uuidString: summary.invoiceId) == UUID(uuidString: canonical.invoiceID),
              attempt.consent, attempt.expectedLinesRevision == summary.linesRevision,
              attempt.presentationScopeId == summary.presentationScopeId, attempt.consentDigest == consent.digest,
              attempt.consentVersion == consent.consentVersion,
              !attempt.signerName.isEmpty, attempt.signerName.count <= 120,
              attempt.signerName == attempt.signerName.trimmingCharacters(in: .whitespacesAndNewlines),
              ISO8601DateFormatter().date(from: attempt.signedAt) != nil,
              UUID(uuidString: attempt.imageMediaId) != nil, UUID(uuidString: attempt.idempotencyKey) != nil else { return false }
        return true
    }
    @MainActor func matches(_ receipt: CustomerInvoiceSummaryReceipt) -> Bool {
        isValid(for: scope) && receipt.matches(summary: summary, signerName: attempt.signerName, signedAt: attempt.signedAt)
    }
}

/// Constructed only after the exact actor-bound idempotent POST succeeds and its receipt verifies.
struct CustomerSummaryReplayProof {
    fileprivate let pending: CustomerSummaryPendingAttempt
    let receipt: CustomerInvoiceSummaryReceipt
    fileprivate init(pending: CustomerSummaryPendingAttempt, receipt: CustomerInvoiceSummaryReceipt) {
        self.pending = pending; self.receipt = receipt
    }
}

@MainActor
protocol CustomerSummaryPendingStoring {
    func load(scope: CustomerSummaryPendingScope) throws -> CustomerSummaryPendingAttempt?
    /// Internal recovery only: returns original terms to the authorized reconciliation flow,
    /// never to the customer-facing current-document display.
    func loadForRecovery(scope: CustomerSummaryPendingScope) throws -> CustomerSummaryPendingAttempt?
    /// Atomically insert; never overwrite another uncertain attempt.
    func insert(_ pending: CustomerSummaryPendingAttempt) throws
    /// Caller must also prove current authority before resolving a receipt.
    func complete(scope: CustomerSummaryPendingScope, proof: CustomerSummaryReplayProof, currentAuthority: @MainActor () -> Bool) throws
}

@MainActor
final class KeychainCustomerSummaryPendingStore: CustomerSummaryPendingStoring {
    static let shared = KeychainCustomerSummaryPendingStore()
    private let service = "com.thorbis.field.customer-summary-pending-v1"
    private enum StoreError: Error { case invalid, alreadyPending, keychain(OSStatus) }
    private func query(_ scope: CustomerSummaryPendingScope) throws -> [String: Any] {
        guard let canonical = scope.canonical else { throw StoreError.invalid }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        // One key per invoice: changed job/customer metadata must not hide an unresolved attempt.
        let identity = [canonical.origin, canonical.actorID, canonical.organizationID, canonical.invoiceID]
        let account = SHA256.hash(data: try encoder.encode(identity)).map { String(format: "%02x", $0) }.joined()
        return [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    func load(scope: CustomerSummaryPendingScope) throws -> CustomerSummaryPendingAttempt? {
        guard let pending = try loadForRecovery(scope: scope) else { return nil }
        guard pending.isValid(for: scope) else { throw StoreError.invalid }
        return pending
    }
    func loadForRecovery(scope: CustomerSummaryPendingScope) throws -> CustomerSummaryPendingAttempt? {
        guard let requested = scope.canonical else { throw StoreError.invalid }
        var item = try query(scope); item[kSecReturnData as String] = true; item[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(item as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw StoreError.keychain(status) }
        let pending = try JSONDecoder().decode(CustomerSummaryPendingAttempt.self, from: data)
        guard let original = pending.scope.canonical, pending.isValid(for: pending.scope),
              original.origin == requested.origin, original.actorID == requested.actorID,
              original.organizationID == requested.organizationID, original.invoiceID == requested.invoiceID else { throw StoreError.invalid }
        return pending
    }
    func insert(_ pending: CustomerSummaryPendingAttempt) throws {
        guard pending.isValid(for: pending.scope) else { throw StoreError.invalid }
        var item = try query(pending.scope)
        item[kSecValueData as String] = try JSONEncoder().encode(pending)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecDuplicateItem { throw StoreError.alreadyPending }
        guard status == errSecSuccess else { throw StoreError.keychain(status) }
    }
    func complete(scope: CustomerSummaryPendingScope, proof: CustomerSummaryReplayProof, currentAuthority: @MainActor () -> Bool) throws {
        guard currentAuthority(), let pending = try loadForRecovery(scope: scope),
              proof.pending.isValid(for: pending.scope), pending.attempt == proof.pending.attempt,
              pending.matches(proof.receipt), currentAuthority() else { throw StoreError.invalid }
        let status = SecItemDelete(try query(scope) as CFDictionary)
        guard status == errSecSuccess else { throw StoreError.keychain(status) }
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
        guard png.count <= 512 * 1024 else {
            throw Problem(title: "Signature is too large. Clear it and sign again.", status: nil, detail: nil)
        }
        guard !name.isEmpty, name.count <= 120, !png.isEmpty,
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
    func signature() throws -> CustomerSummaryFrozenSignature {
        try checkCurrent()
        guard let frozen else { throw Problem(title: "Signature isn't ready", status: nil, detail: nil) }
        return frozen
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

/// Handoff-owned signing state. Callers must scope `current` to the actor, job, session,
/// capability, activation and API generation; neither navigation nor a sheet owns this object.
@MainActor
final class CustomerSummarySigningCoordinator: ObservableObject {
    enum Phase: Equatable { case idle, checking, unsigned, submitting, signed, unavailable }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var hasFrozenSignature = false
    @Published private(set) var errorMessage: String?
    private(set) var receipt: CustomerInvoiceSummaryReceipt?
    private let summary: CustomerInvoiceSummary
    private let context: CustomerSummarySigningContext
    private let current: @MainActor () -> Bool
    private let lookup: @MainActor () async throws -> CustomerSummaryAuthorizationState
    private let upload: @MainActor (CustomerSummaryFrozenSignature) async throws -> MediaAssetRecord
    private let submit: @MainActor (CustomerSummarySigningAttempt) async throws -> CustomerInvoiceSummaryReceipt
    private var generation = UUID()
    private var running = false
    private var retired = false

    init(summary: CustomerInvoiceSummary, actorID: String, current: @escaping @MainActor () -> Bool,
         lookup: @escaping @MainActor () async throws -> CustomerSummaryAuthorizationState,
         upload: @escaping @MainActor (CustomerSummaryFrozenSignature) async throws -> MediaAssetRecord,
         submit: @escaping @MainActor (CustomerSummarySigningAttempt) async throws -> CustomerInvoiceSummaryReceipt) {
        self.summary = summary; self.current = current; self.lookup = lookup; self.upload = upload; self.submit = submit
        context = CustomerSummarySigningContext(summary: summary, actorID: actorID, current: current)
    }
    private func valid(_ token: UUID) -> Bool {
        !Task.isCancelled && !retired && generation == token && current()
    }
    func checkStatus() async {
        guard !running, !retired, current() else { return }
        running = true; let token = generation; phase = .checking; receipt = nil; errorMessage = nil
        defer { if generation == token { running = false } }
        do {
            let result = try await lookup()
            guard valid(token) else { return }
            switch result {
            case .unsigned: phase = .unsigned
            case .signed(let value):
                guard value.matches(summary: summary, signerName: value.signerName, signedAt: value.signedAt) else { phase = .unavailable; return }
                receipt = value; phase = .signed
            }
        } catch { if valid(token) { phase = .unavailable } }
    }
    func sign(signerName: String, signedAt: String, png: Data) async {
        guard !running, phase == .unsigned, !retired, current() else { return }
        errorMessage = nil
        do {
            let signature = try context.freeze(signerName: signerName, signedAt: signedAt, png: png)
            hasFrozenSignature = true
            await perform(signature)
        } catch {
            if current(), !retired { errorMessage = (error as? Problem)?.title ?? "Check your signature and try again." }
        }
    }
    func retryFrozen() async {
        guard !running, phase == .unsigned, !retired, current(), let signature = try? context.signature() else { return }
        await perform(signature)
    }
    private func perform(_ signature: CustomerSummaryFrozenSignature) async {
        guard !running, !retired, current() else { return }
        running = true; let token = generation; phase = .submitting
        defer { if generation == token { running = false } }
        do {
            if (try? context.attempt()) == nil {
                let asset = try await upload(signature)
                guard valid(token) else { return }
                try context.acceptUploadedMedia(asset)
            }
            guard valid(token) else { return }
            let attempt = try context.attempt()
            let value = try await submit(attempt)
            guard valid(token) else { return }
            guard value.matches(summary: summary, signerName: attempt.signerName, signedAt: attempt.signedAt) else { phase = .unavailable; return }
            receipt = value; phase = .signed
        } catch { if valid(token) { phase = .unavailable } }
    }
    /// Suspend a departed destination without discarding an uncertain attempt. The next
    /// activation must perform a fresh status check before retrying those same terms.
    func deactivate() {
        generation = UUID(); running = false; receipt = nil; errorMessage = nil; phase = .idle
    }
    func retire() {
        retired = true; generation = UUID(); running = false; receipt = nil; hasFrozenSignature = false; errorMessage = nil
        context.retire(); phase = .idle
    }
}

/// Own this for the whole customer handoff. A persisted attempt blocks all new signing,
/// including when an unsigned lookup races a prior in-flight POST.
@MainActor
final class CustomerSummaryDurableCoordinator: ObservableObject {
    enum Phase: Equatable { case idle, checking, ready, preparing, needsRecovery, recovering, signed, previousResolved, unavailable }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var hasFrozenSignature = false
    @Published private(set) var errorMessage: String?
    private(set) var receipt: CustomerInvoiceSummaryReceipt?
    private let summary: CustomerInvoiceSummary
    private let context: CustomerSummarySigningContext
    private let scope: CustomerSummaryPendingScope
    private let store: any CustomerSummaryPendingStoring
    private let current: @MainActor () -> Bool
    private let lookup: @MainActor () async throws -> CustomerSummaryAuthorizationState
    private let upload: @MainActor (CustomerSummaryFrozenSignature) async throws -> MediaAssetRecord
    private let replay: @MainActor (CustomerSummaryPendingAttempt) async throws -> CustomerSummaryReplayProof
    private var generation = UUID()
    private var running = false
    private var retired = false

    init(summary: CustomerInvoiceSummary, scope: CustomerSummaryPendingScope, store: any CustomerSummaryPendingStoring,
         current: @escaping @MainActor () -> Bool, lookup: @escaping @MainActor () async throws -> CustomerSummaryAuthorizationState,
         upload: @escaping @MainActor (CustomerSummaryFrozenSignature) async throws -> MediaAssetRecord,
         replay: @escaping @MainActor (CustomerSummaryPendingAttempt) async throws -> CustomerSummaryReplayProof) {
        self.summary = summary; self.scope = scope; self.store = store; self.current = current; self.lookup = lookup; self.upload = upload; self.replay = replay
        context = CustomerSummarySigningContext(summary: summary, actorID: scope.actorID, current: current)
    }
    private func valid(_ token: UUID) -> Bool { !Task.isCancelled && !retired && generation == token && current() }
    func inspect() async {
        guard !running, !retired, current() else { return }
        running = true; let token = generation; phase = .checking; receipt = nil; errorMessage = nil
        defer { if generation == token { running = false } }
        do {
            guard let canonical = scope.canonical, summary.validatedConsent != nil,
                  UUID(uuidString: summary.organizationId) == UUID(uuidString: canonical.organizationID),
                  UUID(uuidString: summary.customerId) == UUID(uuidString: canonical.customerID),
                  summary.jobId.flatMap(UUID.init(uuidString:)) == UUID(uuidString: canonical.jobID),
                  UUID(uuidString: summary.invoiceId) == UUID(uuidString: canonical.invoiceID) else { phase = .unavailable; return }
            if try store.load(scope: scope) != nil { phase = .needsRecovery; return }
            let status = try await lookup()
            guard valid(token) else { return }
            // Another activation may have persisted an attempt while the lookup was in flight.
            if try store.load(scope: scope) != nil { phase = .needsRecovery; return }
            switch status {
            case .unsigned: phase = .ready
            case .signed(let value):
                guard value.matches(summary: summary, signerName: value.signerName, signedAt: value.signedAt) else { phase = .unavailable; return }
                receipt = value; phase = .signed
            }
        } catch { if valid(token) { phase = .unavailable } }
    }
    /// Capture and upload retain their original bytes and client asset ID through retries.
    func sign(signerName: String, signedAt: String, png: Data) async {
        guard !running, !retired, current(), phase == .ready else { return }
        errorMessage = nil
        do {
            let signature = try context.freeze(signerName: signerName, signedAt: signedAt, png: png)
            hasFrozenSignature = true
            await prepare(signature)
        } catch { if current(), !retired { errorMessage = (error as? Problem)?.title ?? "Check your signature and try again." } }
    }
    func retryCapture() async {
        guard !running, !retired, current(), phase == .ready, let signature = try? context.signature() else { return }
        await prepare(signature)
    }
    private func prepare(_ signature: CustomerSummaryFrozenSignature) async {
        guard !running, !retired, current(), phase == .ready else { return }
        running = true; let token = generation; phase = .preparing
        defer { if generation == token { running = false } }
        do {
            if (try? context.attempt()) == nil {
                let asset = try await upload(signature)
                guard valid(token) else { return }
                try context.acceptUploadedMedia(asset)
            }
            guard valid(token) else { return }
            let attempt = try context.attempt()
            running = false; phase = .ready
            await stageAndSubmit(attempt)
        } catch {
            if valid(token) { running = false; phase = .ready; errorMessage = "The signature couldn't be uploaded. Try again." }
        }
    }
    /// Keychain insertion must finish before any financial POST is sent.
    private func stageAndSubmit(_ attempt: CustomerSummarySigningAttempt) async {
        guard !running, !retired, current(), phase == .ready else { return }
        let pending = CustomerSummaryPendingAttempt(scope: scope, summary: summary, attempt: attempt)
        guard pending.isValid(for: scope) else { phase = .unavailable; return }
        do { try store.insert(pending) } catch { phase = .unavailable; return }
        guard current(), !retired else { return }
        phase = .needsRecovery
        await recover()
    }
    /// Replay the same actor-bound key, even if a fresh lookup says unsigned. Never issue a new key.
    func recover() async {
        guard !running, !retired, current(), phase == .needsRecovery else { return }
        running = true; let token = generation; phase = .recovering
        defer { if generation == token { running = false } }
        do {
            guard let pending = try store.load(scope: scope) else { phase = .unavailable; return }
            let proof = try await replay(pending)
            guard valid(token), pending.matches(proof.receipt) else { return }
            try store.complete(scope: scope, proof: proof, currentAuthority: { self.valid(token) })
            guard valid(token) else { return }
            if proof.receipt.matches(summary: summary, signerName: pending.attempt.signerName, signedAt: pending.attempt.signedAt) {
                receipt = proof.receipt; phase = .signed
            } else {
                receipt = nil; phase = .previousResolved
            }
        } catch { if valid(token) { phase = .needsRecovery } }
    }
    func deactivate() { generation = UUID(); running = false; receipt = nil; errorMessage = nil; phase = .idle }
    func retire() { retired = true; generation = UUID(); running = false; receipt = nil; errorMessage = nil; hasFrozenSignature = false; context.retire(); phase = .idle }
}

@MainActor
extension APIClient {
    /// Replays a previously persisted request, including old terms, under the same actor.
    /// An unsigned lookup alone cannot prove an earlier in-flight POST has finished.
    func replayCustomerSummaryPending(_ pending: CustomerSummaryPendingAttempt, scope: CustomerSummaryPendingScope,
                                      currentAuthority: @escaping @MainActor () -> Bool) async throws -> CustomerSummaryReplayProof {
        guard currentAuthority(), pending.isValid(for: scope), normalizedOrigin == scope.canonical?.origin else { throw CancellationError() }
        let result = try await authorizeCustomerInvoiceSummary(pending.summary, attempt: pending.attempt, currentAuthority: currentAuthority)
        guard currentAuthority(), normalizedOrigin == scope.canonical?.origin, pending.matches(result) else { throw CancellationError() }
        return CustomerSummaryReplayProof(pending: pending, receipt: result)
    }

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
                  attempt.consent, attempt.expectedLinesRevision == summary.linesRevision, attempt.presentationScopeId == summary.presentationScopeId,
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

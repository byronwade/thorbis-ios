import Foundation
import Security
import CryptoKit

/// Durable identity only. A new session must independently reauthorize before recovery.
struct InvoiceDraftRecoveryScope: Codable, Equatable, Sendable {
    let actorID: String
    let organizationID: String
    let origin: String
    let invoiceID: String
    let customerID: String
    let jobID: String?

    init(actorID: String, organizationID: String, origin: String, invoiceID: String, customerID: String, jobID: String?) {
        self.actorID = Self.canonicalID(actorID); self.organizationID = Self.canonicalID(organizationID)
        self.origin = Self.canonicalOrigin(origin) ?? origin
        self.invoiceID = Self.canonicalID(invoiceID); self.customerID = Self.canonicalID(customerID)
        self.jobID = jobID.map(Self.canonicalID)
    }

    private static func canonicalID(_ id: String) -> String { UUID(uuidString: id)?.uuidString.lowercased() ?? id }
    private static func validID(_ id: String) -> Bool {
        !id.isEmpty && id == id.trimmingCharacters(in: .whitespacesAndNewlines) &&
            id.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) } && canonicalID(id) == id
    }
    private static func canonicalOrigin(_ origin: String) -> String? {
        guard var parts = URLComponents(string: origin), let scheme = parts.scheme?.lowercased(),
              ["http", "https"].contains(scheme), let host = parts.host?.lowercased(), !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/" else { return nil }
        if let port = parts.port, !(1...65535).contains(port) { return nil }
        parts.scheme = scheme; parts.host = host; parts.path = ""
        if (scheme == "https" && parts.port == 443) || (scheme == "http" && parts.port == 80) { parts.port = nil }
        return parts.string
    }

    var isValid: Bool {
        Self.validID(actorID) && Self.validID(organizationID) && Self.validID(invoiceID) && Self.validID(customerID) &&
            (jobID.map(Self.validID) ?? true) && Self.canonicalOrigin(origin) == origin
    }

    func matches(_ invoice: InvoiceRecord) -> Bool {
        isValid && Self.canonicalID(invoice.id) == invoiceID && Self.canonicalID(invoice.organizationId) == organizationID &&
            Self.canonicalID(invoice.customerId) == customerID && invoice.jobId.map(Self.canonicalID) == jobID
    }

    fileprivate var submissionDomain: InvoiceDraftSubmissionDomain {
        .init(organizationID: organizationID, origin: origin, invoiceID: invoiceID)
    }
}

private struct InvoiceDraftSubmissionDomain: Codable, Equatable {
    let organizationID: String
    let origin: String
    let invoiceID: String
}

/// Callers must derive this from a fresh, authorized server read, not cached invoice data.
struct InvoiceDraftRecoveryAccess: Sendable {
    let scope: InvoiceDraftRecoveryScope
    let canEdit: Bool
    let fresh: Bool
    /// Caller must conservatively account for every snapshot of this scope, including uncertain writes.
    let noUnresolvedAttempts: Bool
    let currentInvoice: InvoiceRecord
}

private enum InvoiceDraftRecoverySource: Codable, Equatable, Sendable {
    case manual
    case priceBookSelection(itemID: String, revision: Int)
    case retainedPriceBook(FieldLineSource)
    case estimate(id: String, revision: Int?, lineID: String, snapshot: FieldEstimateLineSourceSnapshot?)
    case unsupported(String)

    init(_ source: FieldInvoiceLineSourceInput) {
        switch source {
        case .manual: self = .manual
        case let .priceBookSelection(id, revision): self = .priceBookSelection(itemID: id, revision: revision)
        case let .retainedPriceBook(source): self = .retainedPriceBook(source)
        case let .estimate(id, revision, lineID, snapshot): self = .estimate(id: id, revision: revision, lineID: lineID, snapshot: snapshot)
        case let .unsupported(kind): self = .unsupported(kind)
        }
    }

    var input: FieldInvoiceLineSourceInput {
        switch self {
        case .manual: return .manual
        case let .priceBookSelection(id, revision): return .priceBookSelection(itemID: id, revision: revision)
        case let .retainedPriceBook(source): return .retainedPriceBook(source)
        case let .estimate(id, revision, lineID, snapshot): return .estimate(id: id, revision: revision, lineID: lineID, snapshot: snapshot)
        case let .unsupported(kind): return .unsupported(kind)
        }
    }
}

private struct InvoiceDraftRecoveryLine: Codable, Equatable, Sendable {
    let id: UUID
    let originalLineID: String?
    let description: String
    let quantity: String
    let unitPrice: String
    let unitLabel: String?
    let source: InvoiceDraftRecoverySource?
    let priceBookBaselineDescription: String?
    let priceBookBaselinePrice: FieldMoney?

    init(_ line: InvoiceLineDraft) {
        id = line.id; originalLineID = line.originalLineID; description = line.description
        quantity = line.quantity; unitPrice = line.unitPrice; unitLabel = line.unitLabel
        source = line.source.map(InvoiceDraftRecoverySource.init)
        priceBookBaselineDescription = line.priceBookBaselineDescription
        priceBookBaselinePrice = line.priceBookBaselinePrice
    }

    var draft: InvoiceLineDraft {
        InvoiceLineDraft(id: id, originalLineID: originalLineID, description: description,
            quantity: quantity, unitPrice: unitPrice, unitLabel: unitLabel, source: source?.input,
            priceBookBaselineDescription: priceBookBaselineDescription, priceBookBaselinePrice: priceBookBaselinePrice)
    }
}

enum InvoiceDraftRecoveryWriteState: Codable, Equatable, Sendable {
    case idle
    case inFlightOrUncertain
}

/// This is an unconnected foundation: it never submits or silently restores a financial draft.
struct InvoiceDraftRecovery: Codable, Equatable, Sendable {
    let snapshotID: UUID
    let scope: InvoiceDraftRecoveryScope
    private let baseline: InvoiceRecord
    private let lines: [InvoiceDraftRecoveryLine]
    private let priceBookOverrideReason: String
    let writeState: InvoiceDraftRecoveryWriteState

    init(scope: InvoiceDraftRecoveryScope, state: InvoiceLineEditorState, writeState: InvoiceDraftRecoveryWriteState, snapshotID: UUID = UUID()) throws {
        guard scope.matches(state.invoice), state.invoice.status == "draft" else { throw InvoiceDraftRecoveryError.invalidScope }
        self.snapshotID = snapshotID; self.scope = scope; baseline = state.invoice
        lines = state.lines.map(InvoiceDraftRecoveryLine.init)
        priceBookOverrideReason = state.priceBookOverrideReason
        self.writeState = writeState
        guard isValid else { throw InvoiceDraftRecoveryError.invalidData }
    }

    fileprivate var isValid: Bool {
        guard scope.matches(baseline), baseline.status == "draft", lines.count <= 500,
              Set(lines.map(\.id)).count == lines.count else { return false }
        let originalIDs = lines.compactMap(\.originalLineID)
        let canonicalOriginalIDs = originalIDs.map { UUID(uuidString: $0)?.uuidString.lowercased() ?? $0 }
        guard originalIDs.allSatisfy({ !$0.isEmpty && $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines) }),
              Set(canonicalOriginalIDs).count == originalIDs.count else { return false }
        for line in lines {
            switch line.source {
            case let .retainedPriceBook(source): if source.kind != "price_book" { return false }
            case let .priceBookSelection(itemID, revision): if UUID(uuidString: itemID) == nil || !(1...Int(Int32.max)).contains(revision) { return false }
            case let .estimate(id, _, lineID, _): if id.isEmpty || lineID.isEmpty { return false }
            default: break
            }
        }
        return true
    }

    /// Exact baseline equality is intentionally conservative: changed server paper needs review.
    fileprivate func restore(access: InvoiceDraftRecoveryAccess) -> InvoiceLineEditorState? {
        guard isValid, writeState == .idle, access.noUnresolvedAttempts, access.fresh, access.canEdit,
              access.scope == scope, scope.matches(access.currentInvoice),
              access.currentInvoice.status == "draft", access.currentInvoice == baseline else { return nil }
        var state = InvoiceLineEditorState(invoice: access.currentInvoice)
        state.lines = lines.map(\.draft)
        state.priceBookOverrideReason = priceBookOverrideReason
        return state
    }

    fileprivate func matchesSubmission(_ marker: InvoiceDraftSubmissionMarker) -> Bool {
        isValid && writeState == .idle && marker.scope == scope && marker.snapshotID == snapshotID &&
            marker.expectedRevision == baseline.linesRevision
    }

    #if INVOICE_RECOVERY_HOST_TEST
    func hostValidate(access: InvoiceDraftRecoveryAccess) -> InvoiceLineEditorState? { restore(access: access) }
    #endif
}

/// Identifies one intended request; it is not authorization or proof a server mutation occurred.
struct InvoiceDraftSubmissionMarker: Codable, Equatable, Sendable {
    let scope: InvoiceDraftRecoveryScope
    let snapshotID: UUID
    let attemptID: UUID
    let expectedRevision: Int
    let requestSHA256: String

    init(scope: InvoiceDraftRecoveryScope, snapshotID: UUID, attemptID: UUID,
         expectedRevision: Int, requestBytes: Data) throws {
        guard scope.isValid, expectedRevision >= 0, !requestBytes.isEmpty else {
            throw InvoiceDraftRecoveryError.invalidData
        }
        self.scope = scope; self.snapshotID = snapshotID; self.attemptID = attemptID
        self.expectedRevision = expectedRevision
        self.requestSHA256 = SHA256.hash(data: requestBytes).map { String(format: "%02x", $0) }.joined()
    }

    fileprivate var isValid: Bool {
        scope.isValid && expectedRevision >= 0 && requestSHA256.count == 64 &&
            requestSHA256.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    func matchesRequest(_ bytes: Data) -> Bool {
        !bytes.isEmpty && SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() == requestSHA256
    }
}

/// A snapshot checked at one point in time, not a lease or permission to submit later.
struct InvoiceDraftRecoveryAuthorized: Sendable {
    fileprivate let snapshot: InvoiceDraftRecovery
    fileprivate let access: InvoiceDraftRecoveryAccess
    func editorState() -> InvoiceLineEditorState? { snapshot.restore(access: access) }
}

enum InvoiceDraftRecoveryError: Error { case invalidScope, keychain(OSStatus), invalidData, unresolvedWrite }

protocol InvoiceDraftRecoveryStoring {
    func list(scope: InvoiceDraftRecoveryScope) async throws -> [UUID]
    func save(_ recovery: InvoiceDraftRecovery) async throws
    func hasPendingSubmission(scope: InvoiceDraftRecoveryScope) async throws -> Bool
    func beginSubmission(_ marker: InvoiceDraftSubmissionMarker, access: InvoiceDraftRecoveryAccess) async throws
    func restore(scope: InvoiceDraftRecoveryScope, snapshotID: UUID, access: InvoiceDraftRecoveryAccess) async throws -> InvoiceDraftRecoveryAuthorized?
}

/// Internal boundary enables deterministic failure and duplicate-ID tests without changing user Keychain.
protocol InvoiceRecoveryKeychainTransport: Sendable {
    func add(_ attributes: [String: Any]) -> OSStatus
    func find(_ attributes: [String: Any]) -> (OSStatus, CFTypeRef?)
}

private struct SystemInvoiceRecoveryKeychain: InvoiceRecoveryKeychainTransport {
    func add(_ attributes: [String: Any]) -> OSStatus { SecItemAdd(attributes as CFDictionary, nil) }
    func find(_ attributes: [String: Any]) -> (OSStatus, CFTypeRef?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &result)
        return (status, result)
    }
}

actor KeychainInvoiceDraftRecoveryStore: InvoiceDraftRecoveryStoring {
    private let service = "com.thorbis.field.invoice-draft-recovery.v1"
    private let transport: any InvoiceRecoveryKeychainTransport

    init() { transport = SystemInvoiceRecoveryKeychain() }
    init(transport: any InvoiceRecoveryKeychainTransport) { self.transport = transport }

    private func prefix(_ scope: InvoiceDraftRecoveryScope) throws -> String {
        guard scope.isValid else { throw InvoiceDraftRecoveryError.invalidScope }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: try encoder.encode(scope)).map { String(format: "%02x", $0) }.joined() + ":"
    }

    private func query(_ scope: InvoiceDraftRecoveryScope, _ snapshotID: UUID) throws -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: try prefix(scope) + snapshotID.uuidString]
    }

    private func markerQuery(_ scope: InvoiceDraftRecoveryScope) throws -> [String: Any] {
        guard scope.isValid else { throw InvoiceDraftRecoveryError.invalidScope }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let digest = SHA256.hash(data: try encoder.encode(scope.submissionDomain)).map { String(format: "%02x", $0) }.joined()
        return [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "submission:" + digest]
    }

    private func pendingMarker(scope: InvoiceDraftRecoveryScope) throws -> InvoiceDraftSubmissionMarker? {
        var lookup = try markerQuery(scope)
        lookup[kSecReturnData as String] = true; lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, result) = transport.find(lookup)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw InvoiceDraftRecoveryError.keychain(status) }
        guard let data = result as? Data else { throw InvoiceDraftRecoveryError.invalidData }
        let marker = try JSONDecoder().decode(InvoiceDraftSubmissionMarker.self, from: data)
        guard marker.isValid, marker.scope.submissionDomain == scope.submissionDomain else { throw InvoiceDraftRecoveryError.invalidData }
        return marker
    }

    /// Does not disclose the prior actor, job, customer, request or attempt.
    func hasPendingSubmission(scope: InvoiceDraftRecoveryScope) throws -> Bool { try pendingMarker(scope: scope) != nil }

    /// Create the fence before any send. An error, including an ambiguous add, must never permit a send.
    func beginSubmission(_ marker: InvoiceDraftSubmissionMarker, access: InvoiceDraftRecoveryAccess) throws {
        guard try pendingMarker(scope: marker.scope) == nil else { throw InvoiceDraftRecoveryError.unresolvedWrite }
        guard marker.isValid, let snapshot = try load(scope: marker.scope, snapshotID: marker.snapshotID),
              snapshot.matchesSubmission(marker), snapshot.restore(access: access) != nil else { throw InvoiceDraftRecoveryError.invalidData }
        for id in try list(scope: marker.scope) {
            guard let entry = try load(scope: marker.scope, snapshotID: id) else { throw InvoiceDraftRecoveryError.invalidData }
            guard entry.writeState == .idle else { throw InvoiceDraftRecoveryError.unresolvedWrite }
        }
        var insert = try markerQuery(marker.scope)
        insert[kSecValueData as String] = try JSONEncoder().encode(marker)
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = transport.add(insert)
        if status == errSecDuplicateItem { throw InvoiceDraftRecoveryError.unresolvedWrite }
        guard status == errSecSuccess else { throw InvoiceDraftRecoveryError.keychain(status) }
    }

    /// A pending marker fences all snapshots. Callers still need a separate cross-process send protocol.
    func restore(scope: InvoiceDraftRecoveryScope, snapshotID: UUID, access: InvoiceDraftRecoveryAccess) throws -> InvoiceDraftRecoveryAuthorized? {
        guard try pendingMarker(scope: scope) == nil else { return nil }
        for id in try list(scope: scope) {
            guard let entry = try load(scope: scope, snapshotID: id) else { throw InvoiceDraftRecoveryError.invalidData }
            guard entry.writeState == .idle else { return nil }
        }
        guard let value = try load(scope: scope, snapshotID: snapshotID) else { return nil }
        guard try pendingMarker(scope: scope) == nil else { return nil }
        guard value.restore(access: access) != nil else { return nil }
        return InvoiceDraftRecoveryAuthorized(snapshot: value, access: access)
    }

    func list(scope: InvoiceDraftRecoveryScope) throws -> [UUID] {
        let expectedPrefix = try prefix(scope)
        let lookup: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll]
        let (status, result) = transport.find(lookup)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw InvoiceDraftRecoveryError.keychain(status) }
        guard let attributes = result as? [[String: Any]] else { throw InvoiceDraftRecoveryError.invalidData }
        var resultIDs: [UUID] = []
        for item in attributes {
            guard let account = item[kSecAttrAccount as String] as? String else { throw InvoiceDraftRecoveryError.invalidData }
            guard account.hasPrefix(expectedPrefix) else { continue }
            guard let id = UUID(uuidString: String(account.dropFirst(expectedPrefix.count))) else { throw InvoiceDraftRecoveryError.invalidData }
            resultIDs.append(id)
        }
        return resultIDs.sorted { $0.uuidString < $1.uuidString }
    }

    private func load(scope: InvoiceDraftRecoveryScope, snapshotID: UUID) throws -> InvoiceDraftRecovery? {
        var lookup = try query(scope, snapshotID)
        lookup[kSecReturnData as String] = true; lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, result) = transport.find(lookup)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw InvoiceDraftRecoveryError.keychain(status) }
        guard let data = result as? Data else { throw InvoiceDraftRecoveryError.invalidData }
        let recovered = try JSONDecoder().decode(InvoiceDraftRecovery.self, from: data)
        guard recovered.scope == scope, recovered.snapshotID == snapshotID else { throw InvoiceDraftRecoveryError.invalidScope }
        guard recovered.isValid else { throw InvoiceDraftRecoveryError.invalidData }
        return recovered
    }

    #if INVOICE_RECOVERY_HOST_TEST
    func hostPendingMarker(scope: InvoiceDraftRecoveryScope) throws -> InvoiceDraftSubmissionMarker? { try pendingMarker(scope: scope) }
    func hostLoad(scope: InvoiceDraftRecoveryScope, snapshotID: UUID) throws -> InvoiceDraftRecovery? {
        try load(scope: scope, snapshotID: snapshotID)
    }
    func hostInject(_ recovery: InvoiceDraftRecovery) throws {
        var insert = try query(recovery.scope, recovery.snapshotID)
        insert[kSecValueData as String] = try JSONEncoder().encode(recovery)
        let status = transport.add(insert)
        guard status == errSecSuccess else { throw InvoiceDraftRecoveryError.keychain(status) }
    }
    #endif

    /// Each snapshot is immutable. A duplicate ID is an error, never an overwrite.
    func save(_ recovery: InvoiceDraftRecovery) throws {
        guard recovery.isValid else { throw InvoiceDraftRecoveryError.invalidData }
        // Unmarked uncertain snapshots cannot be discovered across other actor scopes.
        guard recovery.writeState == .idle else { throw InvoiceDraftRecoveryError.unresolvedWrite }
        guard try pendingMarker(scope: recovery.scope) == nil else { throw InvoiceDraftRecoveryError.unresolvedWrite }
        var insert = try query(recovery.scope, recovery.snapshotID)
        insert[kSecValueData as String] = try JSONEncoder().encode(recovery)
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = transport.add(insert)
        guard status == errSecSuccess else { throw InvoiceDraftRecoveryError.keychain(status) }
    }

    // No deletion or marker clearing until a cross-process-safe reconciliation and retention policy exists.
}

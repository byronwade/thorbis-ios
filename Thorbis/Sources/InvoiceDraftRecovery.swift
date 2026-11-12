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
}

/// Callers must derive this from a fresh, authorized server read, not cached invoice data.
struct InvoiceDraftRecoveryAccess {
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
    func restore(access: InvoiceDraftRecoveryAccess) -> InvoiceLineEditorState? {
        guard isValid, writeState == .idle, access.noUnresolvedAttempts, access.fresh, access.canEdit,
              access.scope == scope, scope.matches(access.currentInvoice),
              access.currentInvoice.status == "draft", access.currentInvoice == baseline else { return nil }
        var state = InvoiceLineEditorState(invoice: access.currentInvoice)
        state.lines = lines.map(\.draft)
        state.priceBookOverrideReason = priceBookOverrideReason
        return state
    }
}

enum InvoiceDraftRecoveryError: Error { case invalidScope, keychain(OSStatus), invalidData, unresolvedWrite }

protocol InvoiceDraftRecoveryStoring {
    func list(scope: InvoiceDraftRecoveryScope) async throws -> [UUID]
    func load(scope: InvoiceDraftRecoveryScope, snapshotID: UUID) async throws -> InvoiceDraftRecovery?
    func save(_ recovery: InvoiceDraftRecovery) async throws
    func removeResolved(scope: InvoiceDraftRecoveryScope, snapshotID: UUID) async throws
}

/// Internal boundary enables deterministic failure and duplicate-ID tests without changing user Keychain.
protocol InvoiceRecoveryKeychainTransport: Sendable {
    func add(_ attributes: [String: Any]) -> OSStatus
    func find(_ attributes: [String: Any]) -> (OSStatus, CFTypeRef?)
    func delete(_ attributes: [String: Any]) -> OSStatus
}

private struct SystemInvoiceRecoveryKeychain: InvoiceRecoveryKeychainTransport {
    func add(_ attributes: [String: Any]) -> OSStatus { SecItemAdd(attributes as CFDictionary, nil) }
    func find(_ attributes: [String: Any]) -> (OSStatus, CFTypeRef?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &result)
        return (status, result)
    }
    func delete(_ attributes: [String: Any]) -> OSStatus { SecItemDelete(attributes as CFDictionary) }
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

    func load(scope: InvoiceDraftRecoveryScope, snapshotID: UUID) throws -> InvoiceDraftRecovery? {
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

    /// Each snapshot is immutable. A duplicate ID is an error, never an overwrite.
    func save(_ recovery: InvoiceDraftRecovery) throws {
        guard recovery.isValid else { throw InvoiceDraftRecoveryError.invalidData }
        var insert = try query(recovery.scope, recovery.snapshotID)
        insert[kSecValueData as String] = try JSONEncoder().encode(recovery)
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = transport.add(insert)
        guard status == errSecSuccess else { throw InvoiceDraftRecoveryError.keychain(status) }
    }

    /// Unknown in-flight outcomes are retained until an explicit reconciliation path exists.
    func removeResolved(scope: InvoiceDraftRecoveryScope, snapshotID: UUID) throws {
        guard let existing = try load(scope: scope, snapshotID: snapshotID) else { return }
        guard existing.writeState == .idle else { throw InvoiceDraftRecoveryError.unresolvedWrite }
        let status = transport.delete(try query(scope, snapshotID))
        guard status == errSecSuccess || status == errSecItemNotFound else { throw InvoiceDraftRecoveryError.keychain(status) }
    }
}

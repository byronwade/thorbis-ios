import Foundation
import Security

final class FakeKeychain: InvoiceRecoveryKeychainTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: Data] = [:]
    var failingAdd = false
    func add(_ attrs: [String: Any]) -> OSStatus {
        lock.lock(); defer { lock.unlock() }
        if failingAdd { return errSecNotAvailable }
        guard let key = attrs[kSecAttrAccount as String] as? String, let data = attrs[kSecValueData as String] as? Data else { return errSecParam }
        guard entries[key] == nil else { return errSecDuplicateItem }
        entries[key] = data; return errSecSuccess
    }
    func find(_ attrs: [String: Any]) -> (OSStatus, CFTypeRef?) {
        lock.lock(); defer { lock.unlock() }
        if attrs[kSecReturnAttributes as String] as? Bool == true {
            guard !entries.isEmpty else { return (errSecItemNotFound, nil) }
            let items = entries.keys.map { [kSecAttrAccount as String: $0] as NSDictionary } as NSArray
            return (errSecSuccess, items)
        }
        guard let key = attrs[kSecAttrAccount as String] as? String, let data = entries[key] else { return (errSecItemNotFound, nil) }
        return (errSecSuccess, data as NSData)
    }
    func delete(_ attrs: [String: Any]) -> OSStatus {
        lock.lock(); defer { lock.unlock() }
        guard let key = attrs[kSecAttrAccount as String] as? String, entries.removeValue(forKey: key) != nil else { return errSecItemNotFound }
        return errSecSuccess
    }
}

// Lightweight host doubles let this probe exercise the production recovery code without an iOS build.
struct FieldMoney: Codable, Hashable, Sendable { let amount: Int; let currency: String }
struct FieldLineSource: Codable, Hashable, Sendable { let kind: String; let evidence: String }
struct FieldEstimateLineSourceSnapshot: Codable, Hashable, Sendable { let kind: String; let evidence: String }
enum FieldInvoiceLineSourceInput: Hashable {
    case manual, priceBookSelection(itemID: String, revision: Int), retainedPriceBook(FieldLineSource)
    case estimate(id: String, revision: Int?, lineID: String, snapshot: FieldEstimateLineSourceSnapshot?)
    case unsupported(String)
}
struct InvoiceRecord: Codable, Equatable, Sendable {
    let id: String, organizationId: String, customerId: String, jobId: String?, status: String
    let linesRevision: Int
}
struct InvoiceLineDraft: Equatable {
    let id: UUID, originalLineID: String?
    var description: String, quantity: String, unitPrice: String, unitLabel: String?
    var source: FieldInvoiceLineSourceInput?
    var priceBookBaselineDescription: String?
    var priceBookBaselinePrice: FieldMoney?
}
struct InvoiceLineEditorState: Equatable {
    let invoice: InvoiceRecord
    var lines: [InvoiceLineDraft]
    var priceBookOverrideReason: String
    init(invoice: InvoiceRecord) { self.invoice = invoice; lines = []; priceBookOverrideReason = "" }
}

@main struct Probe {
    static func attemptSave(_ value: InvoiceDraftRecovery, using store: KeychainInvoiceDraftRecoveryStore) async throws -> Bool {
        do { try await store.save(value); return true }
        catch InvoiceDraftRecoveryError.keychain(let status) where status == errSecDuplicateItem { return false }
    }
    static func main() async throws {
        let scope = InvoiceDraftRecoveryScope(actorID: "a", organizationID: "o", origin: "https://app.thorbis.com", invoiceID: "i", customerID: "c", jobID: "j")
        let invoice = InvoiceRecord(id: "i", organizationId: "o", customerId: "c", jobId: "j", status: "draft", linesRevision: 3)
        var state = InvoiceLineEditorState(invoice: invoice)
        state.priceBookOverrideReason = " raw reason "
        state.lines = [InvoiceLineDraft(id: UUID(), originalLineID: "original", description: "long\ntext", quantity: "00", unitPrice: "3.", unitLabel: "ea", source: .retainedPriceBook(.init(kind: "price_book", evidence: "complete")), priceBookBaselineDescription: "original", priceBookBaselinePrice: .init(amount: 123, currency: "USD")), InvoiceLineDraft(id: UUID(), originalLineID: nil, description: "unsupported", quantity: "", unitPrice: "-", unitLabel: nil, source: .unsupported("future"), priceBookBaselineDescription: nil, priceBookBaselinePrice: nil)]
        for source: FieldInvoiceLineSourceInput? in [nil, .manual, .priceBookSelection(itemID: "00000000-0000-4000-8000-000000000001", revision: 7), .estimate(id: "estimate", revision: 8, lineID: "line", snapshot: .init(kind: "price_book", evidence: "snapshot"))] {
            state.lines.append(InvoiceLineDraft(id: UUID(), originalLineID: nil, description: "line", quantity: "1", unitPrice: "5.00", unitLabel: nil, source: source, priceBookBaselineDescription: nil, priceBookBaselinePrice: nil))
        }
        let saved = try InvoiceDraftRecovery(scope: scope, state: state, writeState: .idle)
        let encoded = try JSONEncoder().encode(saved)
        let decoded = try JSONDecoder().decode(InvoiceDraftRecovery.self, from: encoded)
        let good = InvoiceDraftRecoveryAccess(scope: scope, canEdit: true, fresh: true, noUnresolvedAttempts: true, currentInvoice: invoice)
        precondition(decoded.restore(access: good) == state)
        let uncertain = try InvoiceDraftRecovery(scope: scope, state: state, writeState: .inFlightOrUncertain)
        precondition(uncertain.restore(access: good) == nil)
        precondition(decoded.restore(access: .init(scope: scope, canEdit: false, fresh: true, noUnresolvedAttempts: true, currentInvoice: invoice)) == nil)
        precondition(decoded.restore(access: .init(scope: scope, canEdit: true, fresh: false, noUnresolvedAttempts: true, currentInvoice: invoice)) == nil)
        precondition(decoded.restore(access: .init(scope: scope, canEdit: true, fresh: true, noUnresolvedAttempts: false, currentInvoice: invoice)) == nil)
        let wrong = InvoiceDraftRecoveryScope(actorID: "b", organizationID: "o", origin: scope.origin, invoiceID: "i", customerID: "c", jobID: "j")
        precondition(decoded.restore(access: .init(scope: wrong, canEdit: true, fresh: true, noUnresolvedAttempts: true, currentInvoice: invoice)) == nil)
        let revised = InvoiceRecord(id: "i", organizationId: "o", customerId: "c", jobId: "j", status: "draft", linesRevision: 4)
        precondition(decoded.restore(access: .init(scope: scope, canEdit: true, fresh: true, noUnresolvedAttempts: true, currentInvoice: revised)) == nil)
        let issued = InvoiceRecord(id: "i", organizationId: "o", customerId: "c", jobId: "j", status: "issued", linesRevision: 3)
        precondition(decoded.restore(access: .init(scope: scope, canEdit: true, fresh: true, noUnresolvedAttempts: true, currentInvoice: issued)) == nil)
        let differentOrigin = InvoiceDraftRecoveryScope(actorID: "a", organizationID: "o", origin: "https://other.example", invoiceID: "i", customerID: "c", jobID: "j")
        precondition(decoded.restore(access: .init(scope: differentOrigin, canEdit: true, fresh: true, noUnresolvedAttempts: true, currentInvoice: invoice)) == nil)
        let canonical = InvoiceDraftRecoveryScope(actorID: "a", organizationID: "o", origin: "HTTPS://APP.THORBIS.COM:443/", invoiceID: "i", customerID: "c", jobID: "j")
        precondition(canonical == scope)
        let unsafeOrigin = InvoiceDraftRecoveryScope(actorID: "a", organizationID: "o", origin: "https://user@app.thorbis.com/path", invoiceID: "i", customerID: "c", jobID: "j")
        precondition(!unsafeOrigin.isValid)
        var corrupt = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        var baseline = corrupt["baseline"] as! [String: Any]
        baseline["organizationId"] = "other"; corrupt["baseline"] = baseline
        let corruptBaseline = try JSONDecoder().decode(InvoiceDraftRecovery.self, from: JSONSerialization.data(withJSONObject: corrupt))
        precondition(corruptBaseline.restore(access: good) == nil)
        corrupt = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        var rows = corrupt["lines"] as! [[String: Any]]
        rows.append(rows[0]); corrupt["lines"] = rows
        let duplicate = try JSONDecoder().decode(InvoiceDraftRecovery.self, from: JSONSerialization.data(withJSONObject: corrupt))
        precondition(duplicate.restore(access: good) == nil)
        corrupt = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        rows = corrupt["lines"] as! [[String: Any]]
        rows[0]["originalLineID"] = "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"
        rows[1]["originalLineID"] = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        corrupt["lines"] = rows
        let duplicateOriginal = try JSONDecoder().decode(InvoiceDraftRecovery.self, from: JSONSerialization.data(withJSONObject: corrupt))
        precondition(duplicateOriginal.restore(access: good) == nil)
        let wrongOrganization = InvoiceDraftRecoveryScope(actorID: "a", organizationID: "other", origin: scope.origin, invoiceID: "i", customerID: "c", jobID: "j")
        do { _ = try InvoiceDraftRecovery(scope: wrongOrganization, state: InvoiceLineEditorState(invoice: revised), writeState: .idle); preconditionFailure("mismatched scope accepted") }
        catch InvoiceDraftRecoveryError.invalidScope { }
        let backend = FakeKeychain(), first = KeychainInvoiceDraftRecoveryStore(transport: backend), second = KeychainInvoiceDraftRecoveryStore(transport: backend)
        try await first.save(saved)
        do { try await second.save(saved); preconditionFailure("duplicate overwrote a snapshot") }
        catch InvoiceDraftRecoveryError.keychain(let status) { precondition(status == errSecDuplicateItem) }
        try await second.save(uncertain)
        let listed = try await first.list(scope: scope)
        precondition(Set(listed) == Set([saved.snapshotID, uncertain.snapshotID]))
        let loaded = try await first.load(scope: scope, snapshotID: saved.snapshotID)
        precondition(loaded == saved)
        let outsider = try await first.list(scope: wrong)
        precondition(outsider.isEmpty)
        let raced = try InvoiceDraftRecovery(scope: scope, state: state, writeState: .idle)
        async let resultA = attemptSave(raced, using: first)
        async let resultB = attemptSave(raced, using: second)
        let raceResults = try await [resultA, resultB]
        precondition(raceResults.filter { $0 }.count == 1)
        try await first.removeResolved(scope: scope, snapshotID: raced.snapshotID)
        do { try await first.removeResolved(scope: scope, snapshotID: uncertain.snapshotID); preconditionFailure("uncertain outcome removed") }
        catch InvoiceDraftRecoveryError.unresolvedWrite { }
        try await second.removeResolved(scope: scope, snapshotID: saved.snapshotID)
        let remaining = try await first.list(scope: scope)
        precondition(remaining == [uncertain.snapshotID])
        backend.failingAdd = true
        do { try await first.save(try InvoiceDraftRecovery(scope: scope, state: state, writeState: .idle)); preconditionFailure("keychain failure ignored") }
        catch InvoiceDraftRecoveryError.keychain(let status) { precondition(status == errSecNotAvailable) }
        print("invoice recovery: raw text, provenance, scope and freshness checks passed")
    }
}

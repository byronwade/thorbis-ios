import Foundation
import Security

final class FakeKeychain: InvoiceRecoveryKeychainTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: Data] = [:]
    var failingAdd = false
    var addThenFail = false
    func add(_ attrs: [String: Any]) -> OSStatus {
        lock.lock(); defer { lock.unlock() }
        if failingAdd { return errSecNotAvailable }
        guard let key = attrs[kSecAttrAccount as String] as? String, let data = attrs[kSecValueData as String] as? Data else { return errSecParam }
        guard entries[key] == nil else { return errSecDuplicateItem }
        entries[key] = data
        return addThenFail ? errSecNotAvailable : errSecSuccess
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
struct FieldInvoiceLinesRequest: Encodable { let expectedLinesRevision: Int; let lines: [String]; let priceBookOverrideReason: String? }
struct InvoiceLineEditorState: Equatable {
    let invoice: InvoiceRecord
    var lines: [InvoiceLineDraft]
    var priceBookOverrideReason: String
    init(invoice: InvoiceRecord) { self.invoice = invoice; lines = []; priceBookOverrideReason = "" }
    func makeRequest() throws -> FieldInvoiceLinesRequest { .init(expectedLinesRevision: invoice.linesRevision, lines: lines.map(\.description), priceBookOverrideReason: priceBookOverrideReason) }
}

@main struct Probe {
    static func attemptSave(_ value: InvoiceDraftRecovery, using store: KeychainInvoiceDraftRecoveryStore) async throws -> Bool {
        do { try await store.save(value); return true }
        catch InvoiceDraftRecoveryError.keychain(let status) where status == errSecDuplicateItem { return false }
    }
    static func attemptBegin(_ marker: InvoiceDraftSubmissionMarker, access: InvoiceDraftRecoveryAccess, using store: KeychainInvoiceDraftRecoveryStore) async throws -> Bool {
        do { try await store.beginSubmission(marker, access: access); return true }
        catch InvoiceDraftRecoveryError.unresolvedWrite { return false }
    }
    static func main() async throws {
        let uuid = "00000000-0000-4000-8000-000000000001"
        let scopeUUID = InvoiceDraftRecoveryScope(actorID: uuid, organizationID: uuid, origin: "https://app.thorbis.com", invoiceID: uuid, customerID: uuid, jobID: nil)
        let invoiceUUID = InvoiceRecord(id: uuid, organizationId: uuid, customerId: uuid, jobId: nil, status: "draft", linesRevision: 3)
        var keyedState = InvoiceLineEditorState(invoice: invoiceUUID)
        keyedState.lines = [InvoiceLineDraft(id: UUID(), originalLineID: nil, description: "hello", quantity: "01", unitPrice: "3.00", unitLabel: nil, source: .manual, priceBookBaselineDescription: nil, priceBookBaselinePrice: nil)]
        let keyedSnapshot = try InvoiceDraftRecovery(scope: scopeUUID, state: keyedState, writeState: .idle)
        let key = UUID(), device = UUID()
        let command = try InvoiceKeyedEdit.prepare(snapshot: keyedSnapshot, expectedScope: scopeUUID, expectedSnapshotID: keyedSnapshot.snapshotID, commandID: key, deviceID: device, policyVersion: 2, clientCreatedAt: "2026-11-12T12:00:00Z")
        let again = try InvoiceKeyedEdit.prepare(snapshot: keyedSnapshot, expectedScope: scopeUUID, expectedSnapshotID: keyedSnapshot.snapshotID, commandID: key, deviceID: device, policyVersion: 2, clientCreatedAt: "2026-11-12T12:00:00Z")
        precondition(command.envelopeBytes == again.envelopeBytes && command.snapshot == keyedSnapshot)
        let json = try JSONSerialization.jsonObject(with: command.envelopeBytes) as! [String: Any]
        precondition(json["commandId"] as? String == key.uuidString.lowercased())
        precondition((json["payload"] as? [String: Any])?["invoiceId"] as? String == uuid)
        do { _ = try InvoiceKeyedEdit.prepare(snapshot: keyedSnapshot, expectedScope: InvoiceDraftRecoveryScope(actorID: uuid, organizationID: uuid, origin: "https://other.example", invoiceID: uuid, customerID: uuid, jobID: nil), expectedSnapshotID: keyedSnapshot.snapshotID, commandID: key, deviceID: device, policyVersion: 2, clientCreatedAt: "2026-11-12T12:00:00Z"); preconditionFailure("scope accepted") } catch { }
        do { _ = try InvoiceKeyedEdit.prepare(snapshot: keyedSnapshot, expectedScope: scopeUUID, expectedSnapshotID: UUID(), commandID: key, deviceID: device, policyVersion: 2, clientCreatedAt: "2026-11-12T12:00:00Z"); preconditionFailure("wrong snapshot accepted") } catch { }
        let existingCount = command.envelopeBytes.count
        keyedState.lines[0].description = String(repeating: "x", count: 65_536 - existingCount + 5)
        let limitSnapshot = try InvoiceDraftRecovery(scope: scopeUUID, state: keyedState, writeState: .idle)
        let atLimit = try InvoiceKeyedEdit.prepare(snapshot: limitSnapshot, expectedScope: scopeUUID, expectedSnapshotID: limitSnapshot.snapshotID, commandID: key, deviceID: device, policyVersion: 2, clientCreatedAt: "2026-11-12T12:00:00Z")
        precondition(atLimit.envelopeBytes.count == 65_536)
        keyedState.lines[0].description += "x"
        let overLimit = try InvoiceDraftRecovery(scope: scopeUUID, state: keyedState, writeState: .idle)
        do { _ = try InvoiceKeyedEdit.prepare(snapshot: overLimit, expectedScope: scopeUUID, expectedSnapshotID: overLimit.snapshotID, commandID: key, deviceID: device, policyVersion: 2, clientCreatedAt: "2026-11-12T12:00:00Z"); preconditionFailure("65,537 accepted") } catch { }
        keyedState.lines[0].description = String(repeating: "x", count: 70_000)
        let huge = try InvoiceDraftRecovery(scope: scopeUUID, state: keyedState, writeState: .idle)
        do { _ = try InvoiceKeyedEdit.prepare(snapshot: huge, expectedScope: scopeUUID, expectedSnapshotID: huge.snapshotID, commandID: key, deviceID: device, policyVersion: 2, clientCreatedAt: "2026-11-12T12:00:00Z"); preconditionFailure("oversized accepted") } catch { }
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
        precondition(decoded.hostValidate(access: good) == state)
        let uncertain = try InvoiceDraftRecovery(scope: scope, state: state, writeState: .inFlightOrUncertain)
        precondition(uncertain.hostValidate(access: good) == nil)
        precondition(decoded.hostValidate(access: .init(scope: scope, canEdit: false, fresh: true, noUnresolvedAttempts: true, currentInvoice: invoice)) == nil)
        precondition(decoded.hostValidate(access: .init(scope: scope, canEdit: true, fresh: false, noUnresolvedAttempts: true, currentInvoice: invoice)) == nil)
        precondition(decoded.hostValidate(access: .init(scope: scope, canEdit: true, fresh: true, noUnresolvedAttempts: false, currentInvoice: invoice)) == nil)
        let wrong = InvoiceDraftRecoveryScope(actorID: "b", organizationID: "o", origin: scope.origin, invoiceID: "i", customerID: "c", jobID: "j")
        precondition(decoded.hostValidate(access: .init(scope: wrong, canEdit: true, fresh: true, noUnresolvedAttempts: true, currentInvoice: invoice)) == nil)
        let revised = InvoiceRecord(id: "i", organizationId: "o", customerId: "c", jobId: "j", status: "draft", linesRevision: 4)
        precondition(decoded.hostValidate(access: .init(scope: scope, canEdit: true, fresh: true, noUnresolvedAttempts: true, currentInvoice: revised)) == nil)
        let issued = InvoiceRecord(id: "i", organizationId: "o", customerId: "c", jobId: "j", status: "issued", linesRevision: 3)
        precondition(decoded.hostValidate(access: .init(scope: scope, canEdit: true, fresh: true, noUnresolvedAttempts: true, currentInvoice: issued)) == nil)
        let differentOrigin = InvoiceDraftRecoveryScope(actorID: "a", organizationID: "o", origin: "https://other.example", invoiceID: "i", customerID: "c", jobID: "j")
        precondition(decoded.hostValidate(access: .init(scope: differentOrigin, canEdit: true, fresh: true, noUnresolvedAttempts: true, currentInvoice: invoice)) == nil)
        let canonical = InvoiceDraftRecoveryScope(actorID: "a", organizationID: "o", origin: "HTTPS://APP.THORBIS.COM:443/", invoiceID: "i", customerID: "c", jobID: "j")
        precondition(canonical == scope)
        let unsafeOrigin = InvoiceDraftRecoveryScope(actorID: "a", organizationID: "o", origin: "https://user@app.thorbis.com/path", invoiceID: "i", customerID: "c", jobID: "j")
        precondition(!unsafeOrigin.isValid)
        var corrupt = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        var baseline = corrupt["baseline"] as! [String: Any]
        baseline["organizationId"] = "other"; corrupt["baseline"] = baseline
        let corruptBaseline = try JSONDecoder().decode(InvoiceDraftRecovery.self, from: JSONSerialization.data(withJSONObject: corrupt))
        precondition(corruptBaseline.hostValidate(access: good) == nil)
        corrupt = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        var rows = corrupt["lines"] as! [[String: Any]]
        rows.append(rows[0]); corrupt["lines"] = rows
        let duplicate = try JSONDecoder().decode(InvoiceDraftRecovery.self, from: JSONSerialization.data(withJSONObject: corrupt))
        precondition(duplicate.hostValidate(access: good) == nil)
        corrupt = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        rows = corrupt["lines"] as! [[String: Any]]
        rows[0]["originalLineID"] = "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"
        rows[1]["originalLineID"] = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        corrupt["lines"] = rows
        let duplicateOriginal = try JSONDecoder().decode(InvoiceDraftRecovery.self, from: JSONSerialization.data(withJSONObject: corrupt))
        precondition(duplicateOriginal.hostValidate(access: good) == nil)
        let wrongOrganization = InvoiceDraftRecoveryScope(actorID: "a", organizationID: "other", origin: scope.origin, invoiceID: "i", customerID: "c", jobID: "j")
        do { _ = try InvoiceDraftRecovery(scope: wrongOrganization, state: InvoiceLineEditorState(invoice: revised), writeState: .idle); preconditionFailure("mismatched scope accepted") }
        catch InvoiceDraftRecoveryError.invalidScope { }
        let backend = FakeKeychain(), first = KeychainInvoiceDraftRecoveryStore(transport: backend), second = KeychainInvoiceDraftRecoveryStore(transport: backend)
        try await first.save(saved)
        do { try await second.save(saved); preconditionFailure("duplicate overwrote a snapshot") }
        catch InvoiceDraftRecoveryError.keychain(let status) { precondition(status == errSecDuplicateItem) }
        let otherUncertain = try InvoiceDraftRecovery(scope: differentOrigin, state: state, writeState: .inFlightOrUncertain)
        try await second.hostInject(otherUncertain)
        let listed = try await first.list(scope: scope)
        precondition(listed == [saved.snapshotID])
        let loaded = try await first.hostLoad(scope: scope, snapshotID: saved.snapshotID)
        precondition(loaded == saved)
        let outsider = try await first.list(scope: differentOrigin)
        precondition(outsider == [otherUncertain.snapshotID])
        let otherIdle = try InvoiceDraftRecovery(scope: differentOrigin, state: state, writeState: .idle)
        try await first.save(otherIdle)
        let otherAccess = InvoiceDraftRecoveryAccess(scope: differentOrigin, canEdit: true, fresh: true, noUnresolvedAttempts: true, currentInvoice: invoice)
        let otherBlocked = try await first.restore(scope: differentOrigin, snapshotID: otherIdle.snapshotID, access: otherAccess)
        precondition(otherBlocked == nil, "uncertain snapshot must fence all older idle snapshots")
        let otherMarker = try InvoiceDraftSubmissionMarker(scope: differentOrigin, snapshotID: otherIdle.snapshotID,
            attemptID: UUID(), expectedRevision: invoice.linesRevision, requestBytes: Data("b request".utf8))
        do { try await first.beginSubmission(otherMarker, access: otherAccess); preconditionFailure("uncertain snapshot allowed submission") }
        catch InvoiceDraftRecoveryError.unresolvedWrite { }
        let raced = try InvoiceDraftRecovery(scope: scope, state: state, writeState: .idle)
        async let resultA = attemptSave(raced, using: first)
        async let resultB = attemptSave(raced, using: second)
        let raceResults = try await [resultA, resultB]
        precondition(raceResults.filter { $0 }.count == 1)
        let otherActorSnapshot = try InvoiceDraftRecovery(scope: wrong, state: state, writeState: .idle)
        try await first.save(otherActorSnapshot)
        let marker = try InvoiceDraftSubmissionMarker(scope: scope, snapshotID: saved.snapshotID,
            attemptID: UUID(), expectedRevision: invoice.linesRevision,
            requestBytes: Data("a request".utf8))
        precondition(marker.matchesRequest(Data("a request".utf8)))
        precondition(!marker.matchesRequest(Data("different request".utf8)))
        try await first.beginSubmission(marker, access: good)
        let blocked = try await second.restore(scope: scope, snapshotID: saved.snapshotID, access: good)
        precondition(blocked == nil, "a pending submission must fence an earlier idle snapshot")
        let reopened = KeychainInvoiceDraftRecoveryStore(transport: backend)
        let persistedMarker = try await reopened.hostPendingMarker(scope: scope)
        precondition(persistedMarker == marker)
        let reassigned = InvoiceDraftRecoveryScope(actorID: "a", organizationID: "o", origin: scope.origin, invoiceID: "i", customerID: "different-customer", jobID: "different-job")
        let reassignedPending = try await reopened.hasPendingSubmission(scope: reassigned)
        precondition(reassignedPending, "customer or job reassignment must not evade an unresolved invoice attempt")
        let reassignedAccess = InvoiceDraftRecoveryAccess(scope: reassigned, canEdit: true, fresh: true, noUnresolvedAttempts: true, currentInvoice: invoice)
        let reassignedRestore = try await reopened.restore(scope: reassigned, snapshotID: saved.snapshotID, access: reassignedAccess)
        precondition(reassignedRestore == nil)
        let otherActorAccess = InvoiceDraftRecoveryAccess(scope: wrong, canEdit: true, fresh: true, noUnresolvedAttempts: true, currentInvoice: invoice)
        let otherActorRestore = try await reopened.restore(scope: wrong, snapshotID: otherActorSnapshot.snapshotID, access: otherActorAccess)
        precondition(otherActorRestore == nil, "a different actor must not evade an unresolved invoice attempt")
        let otherActorPending = try await reopened.hasPendingSubmission(scope: wrong)
        precondition(otherActorPending, "a different actor must see a generic unresolved status")
        do { try await second.beginSubmission(marker, access: good); preconditionFailure("second attempt bypassed pending fence") }
        catch InvoiceDraftRecoveryError.unresolvedWrite { }
        let raceScope = InvoiceDraftRecoveryScope(actorID: "race", organizationID: "o", origin: "https://race.example", invoiceID: "i", customerID: "c", jobID: "j")
        let raceSnapshot = try InvoiceDraftRecovery(scope: raceScope, state: state, writeState: .idle)
        let raceAccess = InvoiceDraftRecoveryAccess(scope: raceScope, canEdit: true, fresh: true, noUnresolvedAttempts: true, currentInvoice: invoice)
        try await first.save(raceSnapshot)
        let markerA = try InvoiceDraftSubmissionMarker(scope: raceScope, snapshotID: raceSnapshot.snapshotID, attemptID: UUID(), expectedRevision: 3, requestBytes: Data("c request".utf8))
        let markerB = try InvoiceDraftSubmissionMarker(scope: raceScope, snapshotID: raceSnapshot.snapshotID, attemptID: UUID(), expectedRevision: 3, requestBytes: Data("d request".utf8))
        async let beginA = attemptBegin(markerA, access: raceAccess, using: first)
        async let beginB = attemptBegin(markerB, access: raceAccess, using: second)
        let begins = try await [beginA, beginB]
        precondition(begins.filter { $0 }.count == 1)
        let afterRace = try await first.restore(scope: raceScope, snapshotID: raceSnapshot.snapshotID, access: raceAccess)
        precondition(afterRace == nil)
        let ambiguousScope = InvoiceDraftRecoveryScope(actorID: "ambiguous", organizationID: "o", origin: "https://ambiguous.example", invoiceID: "i", customerID: "c", jobID: "j")
        let ambiguousSnapshot = try InvoiceDraftRecovery(scope: ambiguousScope, state: state, writeState: .idle)
        let ambiguousAccess = InvoiceDraftRecoveryAccess(scope: ambiguousScope, canEdit: true, fresh: true, noUnresolvedAttempts: true, currentInvoice: invoice)
        try await first.save(ambiguousSnapshot)
        let ambiguousMarker = try InvoiceDraftSubmissionMarker(scope: ambiguousScope, snapshotID: ambiguousSnapshot.snapshotID, attemptID: UUID(), expectedRevision: 3, requestBytes: Data("e request".utf8))
        backend.addThenFail = true
        do { try await first.beginSubmission(ambiguousMarker, access: ambiguousAccess); preconditionFailure("ambiguous marker add reported success") }
        catch InvoiceDraftRecoveryError.keychain(let status) { precondition(status == errSecNotAvailable) }
        backend.addThenFail = false
        let afterAmbiguous = try await second.restore(scope: ambiguousScope, snapshotID: ambiguousSnapshot.snapshotID, access: ambiguousAccess)
        precondition(afterAmbiguous == nil)
        do { try await first.save(try InvoiceDraftRecovery(scope: scope, state: state, writeState: .idle)); preconditionFailure("pending outcome allowed a new snapshot") }
        catch InvoiceDraftRecoveryError.unresolvedWrite { }
        let remaining = try await first.list(scope: scope)
        precondition(Set(remaining) == Set([saved.snapshotID, raced.snapshotID]))
        backend.failingAdd = true
        do { try await first.save(try InvoiceDraftRecovery(scope: differentOrigin, state: state, writeState: .idle)); preconditionFailure("keychain failure ignored") }
        catch InvoiceDraftRecoveryError.keychain(let status) { precondition(status == errSecNotAvailable) }
        print("invoice recovery: raw text, provenance, scope and freshness checks passed")
    }
}

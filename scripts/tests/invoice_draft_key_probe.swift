import Foundation
import Security
import CryptoKit

final class FakeDraftKeys: InvoiceDraftKeychainTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    var failRead = false
    var corruptRead = false
    func add(_ attrs: [String: Any]) -> OSStatus {
        lock.lock(); defer { lock.unlock() }
        guard let account = attrs[kSecAttrAccount as String] as? String,
              let data = attrs[kSecValueData as String] as? Data else { return errSecParam }
        guard values[account] == nil else { return errSecDuplicateItem }
        values[account] = data
        return errSecSuccess
    }
    func find(_ attrs: [String: Any]) -> (OSStatus, CFTypeRef?) {
        lock.lock(); defer { lock.unlock() }
        if failRead { return (errSecNotAvailable, nil) }
        guard let account = attrs[kSecAttrAccount as String] as? String, let data = values[account] else { return (errSecItemNotFound, nil) }
        if corruptRead { return (errSecSuccess, Data([1]) as NSData) }
        return (errSecSuccess, data as NSData)
    }
}

@main struct InvoiceDraftKeyProbe {
    static func attemptCreate(_ store: InvoiceDraftKeyStore, scope: InvoiceIdleCaptureIdentity) async throws -> Bool {
        do { _ = try await store.createNew(identity: scope); return true }
        catch InvoiceDraftKeyError.keychain(let code) where code == errSecDuplicateItem { return false }
    }
    static func main() async throws {
        let domain = InvoiceFenceDomain(origin: "https://app.thorbis.com", organizationID: "00000000-0000-4000-8000-000000000001", invoiceID: "00000000-0000-4000-8000-000000000002")
        let scope = InvoiceIdleCaptureIdentity(domain: domain, actorID: "00000000-0000-4000-8000-000000000003", customerID: "00000000-0000-4000-8000-000000000004", jobID: nil)
        let other = InvoiceIdleCaptureIdentity(domain: domain, actorID: "00000000-0000-4000-8000-000000000005", customerID: scope.customerID, jobID: nil)
        let backend = FakeDraftKeys(), first = InvoiceDraftKeyStore(transport: backend), second = InvoiceDraftKeyStore(transport: backend)
        let missing = try await first.load(identity: scope)
        precondition(missing == nil)
        let created = try await first.createNew(identity: scope)
        let loaded = try await second.load(identity: scope)!
        precondition(created.withUnsafeBytes { Data($0) } == loaded.withUnsafeBytes { Data($0) })
        let otherMissing = try await second.load(identity: other)
        precondition(otherMissing == nil)
        do { _ = try await second.createNew(identity: scope); preconditionFailure("duplicate key replaced") }
        catch InvoiceDraftKeyError.keychain(let code) { precondition(code == errSecDuplicateItem) }
        let raceDomain = InvoiceFenceDomain(origin: domain.origin, organizationID: domain.organizationID, invoiceID: "00000000-0000-4000-8000-000000000006")
        let raceScope = InvoiceIdleCaptureIdentity(domain: raceDomain, actorID: scope.actorID, customerID: scope.customerID, jobID: nil)
        async let one = attemptCreate(first, scope: raceScope)
        async let two = attemptCreate(second, scope: raceScope)
        let outcomes = try await [one, two]
        precondition(outcomes.filter { $0 }.count == 1)
        backend.failRead = true
        do { _ = try await first.load(identity: scope); preconditionFailure("read failure hidden") }
        catch InvoiceDraftKeyError.keychain(let code) { precondition(code == errSecNotAvailable) }
        backend.failRead = false
        backend.corruptRead = true
        do { _ = try await first.load(identity: scope); preconditionFailure("corrupt key accepted") }
        catch InvoiceDraftKeyError.invalidData { }
        print("invoice draft key: scope, duplicate and read-failure checks passed")
    }
}

import CryptoKit
import Foundation

/// A scoped invoice copy bound to the preflight epoch. This does not yet
/// replace generic list caches or establish authorization after a denial.
@MainActor final class InvoiceEpochCache {
    struct Entry: Codable {
        let scopeKey: String
        let epoch: UUID
        let invoice: InvoiceRecord
    }
    static let shared = InvoiceEpochCache()
    private let directory: URL
    private let preflight: InvoiceAccessPreflight
    init(directory: URL? = nil, preflight: InvoiceAccessPreflight = .shared) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("InvoiceEpochCache", isDirectory: true)
        self.preflight = preflight
    }
    private func key(_ scope: InvoiceAccessRegistry.Scope) -> String {
        let parts = [scope.actorWorkspace, scope.origin, scope.invoiceID]
        return SHA256.hash(data: Data(parts.map { "\($0.utf8.count):\($0)" }.joined().utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
    func save(_ invoice: InvoiceRecord, scope: InvoiceAccessRegistry.Scope) throws {
        guard invoice.id.lowercased() == scope.invoiceID,
              let epoch = try preflight.cacheEpoch(scope) else { return }
        let key = key(scope)
        let data = try JSONEncoder().encode(Entry(scopeKey: key, epoch: epoch, invoice: invoice))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("\(key).json"),
                       options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func load(scope: InvoiceAccessRegistry.Scope) -> InvoiceRecord? {
        guard let epoch = try? preflight.cacheEpoch(scope) else { return nil }
        let key = key(scope)
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("\(key).json")),
              let entry = try? JSONDecoder().decode(Entry.self, from: data), entry.scopeKey == key,
              entry.epoch == epoch, entry.invoice.id.lowercased() == scope.invoiceID,
              (try? preflight.cacheEpoch(scope)) == epoch else { return nil }
        return entry.invoice
    }
}

import CryptoKit
import Darwin
import Foundation
import Security

/// A write-ahead hold for one invoice identity. A canceled or interrupted read
/// deliberately leaves its ticket pending until a later coordinated recovery.
@MainActor protocol InvoiceAccessMarkerStorage {
    func read(_ key: String) throws -> Data?
    func write(_ data: Data, key: String) throws
}

@MainActor final class InvoiceAccessKeychain: InvoiceAccessMarkerStorage {
    enum Failure: Error { case keychain(OSStatus), invalidData }
    private let service = "com.thorbis.field.invoice-access-holds.v1"
    private func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }
    func read(_ key: String) throws -> Data? {
        var query = query(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Failure.keychain(status) }
        guard let data = value as? Data else { throw Failure.invalidData }
        return data
    }
    func write(_ data: Data, key: String) throws {
        let query = query(key)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let result = SecItemAdd(add as CFDictionary, nil)
            guard result == errSecSuccess else { throw Failure.keychain(result) }
        } else if status != errSecSuccess { throw Failure.keychain(status) }
    }
}

/// Held integration: callers must mediate all reads and cache writes before
/// this can authorize publication or recovery. A new live success does not
/// clear denial; old copies and outstanding requests first need retirement.
@MainActor final class InvoiceAccessPreflight {
    struct Marker: Codable {
        var denied: Bool
        var tickets: Set<UUID>
        var epoch: UUID
    }
    enum Failure: Error { case unavailable, invalidScope, contended }
    static let shared = InvoiceAccessPreflight()
    private static var unsafe: Set<String> = []
    private let markers: any InvoiceAccessMarkerStorage
    private let directory: URL

    init(markers: (any InvoiceAccessMarkerStorage)? = nil, directory: URL? = nil) {
        self.markers = markers ?? InvoiceAccessKeychain()
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("InvoiceAccessHolds", isDirectory: true)
    }
    private func key(_ scope: InvoiceAccessRegistry.Scope) throws -> String {
        guard !scope.actorWorkspace.isEmpty, APIClient.normalizedOrigin(scope.origin) == scope.origin,
              UUID(uuidString: scope.invoiceID) != nil else { throw Failure.invalidScope }
        let parts = [scope.actorWorkspace, scope.origin, scope.invoiceID]
        return SHA256.hash(data: Data(parts.map { "\($0.utf8.count):\($0)" }.joined().utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
    private func locked<T>(_ scope: InvoiceAccessRegistry.Scope, _ action: (String) throws -> T) throws -> T {
        let key = try key(scope)
        let unsafeKey = directory.path + ":" + key
        guard !Self.unsafe.contains(unsafeKey) else { throw Failure.unavailable }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let descriptor = open(directory.appendingPathComponent("\(key).lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
            guard descriptor >= 0 else { throw Failure.unavailable }
            defer { close(descriptor) }
            guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw Failure.contended }
            defer { _ = flock(descriptor, LOCK_UN) }
            return try action(key)
        } catch {
            Self.unsafe.insert(unsafeKey)
            throw error
        }
    }
    private func read(_ key: String) throws -> Marker? {
        guard let data = try markers.read(key) else { return nil }
        return try JSONDecoder().decode(Marker.self, from: data)
    }
    private func write(_ marker: Marker, key: String) throws {
        try markers.write(JSONEncoder().encode(marker), key: key)
    }
    func begin(_ scope: InvoiceAccessRegistry.Scope) throws -> UUID {
        try locked(scope) { key in
            var marker = try read(key) ?? Marker(denied: false, tickets: [], epoch: UUID())
            let ticket = UUID()
            marker.tickets.insert(ticket)
            try write(marker, key: key)
            return ticket
        }
    }
    func deny(_ scope: InvoiceAccessRegistry.Scope) throws {
        try locked(scope) { key in
            var marker = try read(key) ?? Marker(denied: false, tickets: [], epoch: UUID())
            marker.denied = true
            marker.epoch = UUID()
            try write(marker, key: key)
        }
    }
    /// Ends only a definitively successful or connectivity-failed request.
    /// Cancellation or uncertain response must leave the ticket pending.
    func finish(_ scope: InvoiceAccessRegistry.Scope, ticket: UUID) throws -> Bool {
        try locked(scope) { key in
            guard var marker = try read(key), marker.tickets.remove(ticket) != nil else { return false }
            try write(marker, key: key)
            return !marker.denied && marker.tickets.isEmpty
        }
    }
    /// Epochs bind a cached answer to the last denial-free state. Callers must
    /// validate again when consuming or writing, including queued disk writes.
    func cacheEpoch(_ scope: InvoiceAccessRegistry.Scope) throws -> UUID? {
        try locked(scope) { key in
            guard let marker = try read(key), !marker.denied, marker.tickets.isEmpty else { return nil }
            return marker.epoch
        }
    }
    func canUseOffline(_ scope: InvoiceAccessRegistry.Scope) throws -> Bool {
        try locked(scope) { key in
            guard let marker = try read(key) else { return true }
            return !marker.denied && marker.tickets.isEmpty
        }
    }
}

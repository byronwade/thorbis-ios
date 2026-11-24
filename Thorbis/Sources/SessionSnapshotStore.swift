import Foundation
import Security

/// The last server-verified identity and authority, so a technician who opens the app
/// with no signal keeps working instead of landing on the sign-in screen. It never
/// widens access: `SessionController.can` still enforces the same session and authority
/// deadlines, and every write is re-authorized by the server when it syncs.
struct SessionSnapshot: Codable, Equatable {
    let user: SessionUser
    let organization: SessionOrganization
    let organizations: [SessionOrganization]
    let capabilities: [String]
    let features: [String: FeatureDecision]
    let policyVersion: Int
    let sessionDeadline: Date
    let authorityDeadline: Date?
    // Optional for legacy snapshots; missing fields cannot authorize scoped caches.
    var authorityGeneration: String? = nil
    var authorityOrigin: String? = nil
}

protocol SessionSnapshotStoring: AnyObject {
    func load() -> SessionSnapshot?
    func save(_ snapshot: SessionSnapshot)
    func clear()
}

/// Device-only Keychain item; never synced to iCloud or restored to another device.
final class KeychainSessionSnapshotStore: SessionSnapshotStoring, @unchecked Sendable {
    static let shared = KeychainSessionSnapshotStore()
    private let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.thorbis.field.session-snapshot",
        kSecAttrAccount as String: "current"
    ]

    func load() -> SessionSnapshot? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(SessionSnapshot.self, from: data)
    }

    func save(_ snapshot: SessionSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
    }

    func clear() { SecItemDelete(query as CFDictionary) }
}

/// In-memory store for previews and tests.
final class MemorySessionSnapshotStore: SessionSnapshotStoring {
    private(set) var snapshot: SessionSnapshot?
    init(_ snapshot: SessionSnapshot? = nil) { self.snapshot = snapshot }
    func load() -> SessionSnapshot? { snapshot }
    func save(_ snapshot: SessionSnapshot) { self.snapshot = snapshot }
    func clear() { snapshot = nil }
}

extension URLError.Code {
    /// No network, or the server's host could not be found or connected to. These codes are taken
    /// to mean nothing was sent. The host, DNS, connect, data-not-allowed and roaming codes fail
    /// before a connection exists. iOS may also return `.notConnectedToInternet` for a request
    /// already in flight when the network interface goes down. A send that reached the server can
    /// then land here, and its queued copy is sent a second time. That gives a duplicate note or
    /// follow-up, never a lost one.
    var neverLeavesThePhone: Bool {
        switch self {
        case .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
             .dataNotAllowed, .internationalRoamingOff: true
        default: false
        }
    }
}

extension Error {
    /// True when the request never reached a server answer (no signal, DNS, timeout).
    var isConnectivityFailure: Bool {
        if let problem = self as? Problem { return problem.status == nil && problem.title == "Network error" }
        if let urlError = self as? URLError { return urlError.code != .cancelled }
        return false
    }

    /// A connectivity failure taken to mean the request never left the phone (`neverLeavesThePhone`),
    /// so its queued copy is resent without a lookup first. A timeout or a dropped connection is
    /// not this: that request may have arrived. `.notConnectedToInternet` is not certain either;
    /// see `neverLeavesThePhone`.
    var neverReachedServer: Bool {
        if let problem = self as? Problem { return problem.status == nil && problem.neverSent }
        if let urlError = self as? URLError { return urlError.code.neverLeavesThePhone }
        return false
    }

    /// The server could not give an answer about the session: no signal, an outage (5xx)
    /// or rate limiting. Never a 401 or a changed identity, which must sign out.
    var isTransientServerFailure: Bool {
        if isConnectivityFailure { return true }
        if let problem = self as? Problem, let status = problem.status { return status >= 500 || status == 429 }
        return false
    }
}

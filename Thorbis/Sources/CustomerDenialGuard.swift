import Foundation
import Combine
import CryptoKit
import Security
import Darwin

struct CustomerQuarantineScope: Hashable {
    let actorID: String
    let organizationID: String
    let origin: String
    let customerID: String

    init(actorID: String, organizationID: String, origin: String, customerID: String) throws {
        guard let actor = UUID(uuidString: actorID), let organization = UUID(uuidString: organizationID),
              let customer = UUID(uuidString: customerID), var parts = URLComponents(string: origin),
              let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = parts.host?.lowercased(), !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/" else { throw CustomerQuarantineError.invalidScope }
        parts.scheme = scheme
        parts.host = host
        parts.path = ""
        if (scheme == "https" && parts.port == 443) || (scheme == "http" && parts.port == 80) { parts.port = nil }
        guard let canonicalOrigin = parts.string else { throw CustomerQuarantineError.invalidScope }
        self.actorID = actor.uuidString.lowercased()
        self.organizationID = organization.uuidString.lowercased()
        self.origin = canonicalOrigin
        self.customerID = customer.uuidString.lowercased()
    }
}

struct CustomerQuarantineState: Codable {
    var pending: Set<UUID> = []
    var denied = false
    var compilationVerified = false
    var relationshipLiveRequired = false
    var authorityFingerprint: String?
    var denialEpoch = UUID()
    var cacheEpoch = UUID()
}

struct CustomerQuarantineAuthority {
    let actorID: String
    let organizationID: String
    let origin: String
    let policyVersion: Int
    let serverGeneration: String
    let capabilities: [String]
    let features: [String: Bool]
    let deadline: Date

    func fingerprint(for scope: CustomerQuarantineScope, now: Date = Date()) throws -> String {
        guard actorID.lowercased() == scope.actorID, organizationID.lowercased() == scope.organizationID,
              origin == scope.origin, policyVersion > 0, !serverGeneration.isEmpty, now < deadline else {
            throw CustomerQuarantineError.authorityUnavailable
        }
        let grants = Array(Set(capabilities)).sorted()
        let featureKeys = features.keys.sorted()
        let parts = ["v1", String(policyVersion), serverGeneration, "capabilities", String(grants.count)] + grants +
            ["features", String(featureKeys.count)] + featureKeys.flatMap { [$0, features[$0] == true ? "1" : "0"] }
        let canonical = parts.map { "\($0.utf8.count):\($0)" }.joined()
        return SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor protocol CustomerQuarantineStore {
    func read(_ scope: CustomerQuarantineScope) throws -> CustomerQuarantineState?
    func write(_ state: CustomerQuarantineState, for scope: CustomerQuarantineScope) throws
}

@MainActor final class KeychainCustomerQuarantineStore: CustomerQuarantineStore {
    private let service: String
    init(service: String = "com.thorbis.field.customer-quarantine.v1") { self.service = service }

    private func query(_ scope: CustomerQuarantineScope) -> [String: Any] {
        let parts = [scope.actorID.lowercased(), scope.organizationID.lowercased(), scope.origin, scope.customerID.lowercased()]
        let canonical = parts.map { "\($0.utf8.count):\($0)" }.joined()
        let account = SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
        return [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                kSecAttrAccount as String: account]
    }

    func read(_ scope: CustomerQuarantineScope) throws -> CustomerQuarantineState? {
        var attributes = query(scope)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw CustomerQuarantineError.storage }
        do { return try JSONDecoder().decode(CustomerQuarantineState.self, from: data) }
        catch { throw CustomerQuarantineError.storage }
    }

    func write(_ state: CustomerQuarantineState, for scope: CustomerQuarantineScope) throws {
        let data = try JSONEncoder().encode(state)
        let lookup = query(scope)
        let status = SecItemUpdate(lookup as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw CustomerQuarantineError.storage }
        var attributes = lookup
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else { throw CustomerQuarantineError.storage }
    }
}

struct CustomerQuarantineTicket {
    let id: UUID
    let requiresLive: Bool
    let scope: CustomerQuarantineScope
    let denialEpoch: UUID
    let cacheEpoch: UUID
    let authorityFingerprint: String
    let authorityDeadline: Date

    var cacheNamespace: String {
        let parts = [scope.actorID, scope.organizationID, scope.origin, scope.customerID, cacheEpoch.uuidString.lowercased()]
        let canonical = parts.map { "\($0.utf8.count):\($0)" }.joined()
        return SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
enum CustomerQuarantineOutcome: Equatable { case liveCompilation, denied, uncertain, liveActivity, cached }
enum CustomerQuarantineError: Error { case invalidScope, invalidTicket, cachedResultForbidden, storage, leaseUnavailable, authorityUnavailable }

final class CustomerQuarantineLease {
    private let fd: Int32
    init(url: URL) throws {
        let opened = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard opened >= 0 else { throw CustomerQuarantineError.leaseUnavailable }
        guard flock(opened, LOCK_EX | LOCK_NB) == 0 else {
            close(opened)
            throw CustomerQuarantineError.leaseUnavailable
        }
        fd = opened
    }
    deinit {
        flock(fd, LOCK_UN)
        close(fd)
    }
}

@MainActor final class CustomerQuarantineFactory {
    private let store: CustomerQuarantineStore
    private let leaseURL: URL
    private var coordinator: CustomerQuarantine?
    init(store: CustomerQuarantineStore, leaseURL: URL) {
        self.store = store
        self.leaseURL = leaseURL
    }
    func acquire() -> CustomerQuarantine? {
        if let coordinator { return coordinator }
        guard let lease = try? CustomerQuarantineLease(url: leaseURL) else { return nil }
        let result = CustomerQuarantine(store: store, lease: lease)
        coordinator = result
        return result
    }
}

@MainActor final class CustomerQuarantine: ObservableObject {
    @Published private(set) var revision = UUID()
    /// All production access must use this coordinator and the same app-group
    /// lock path. A second process that cannot take the lease fails closed.
    private static var sharedFactory: CustomerQuarantineFactory?
    static func acquireShared() -> CustomerQuarantine? {
        if let sharedFactory { return sharedFactory.acquire() }
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.thorbis.field") else { return nil }
        let directory = base.appendingPathComponent("CustomerQuarantine", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let factory = CustomerQuarantineFactory(store: KeychainCustomerQuarantineStore(),
                                                    leaseURL: directory.appendingPathComponent("coordinator.lock"))
            sharedFactory = factory
            return factory.acquire()
        } catch { return nil }
    }

    private let store: CustomerQuarantineStore
    private let lease: CustomerQuarantineLease?
    private var active: [CustomerQuarantineScope: Set<UUID>] = [:]
    private var storageFailures = Set<CustomerQuarantineScope>()
    fileprivate init(store: CustomerQuarantineStore, lease: CustomerQuarantineLease?) {
        self.store = store
        self.lease = lease
    }
    #if DEBUG
    convenience init(store: CustomerQuarantineStore) { self.init(store: store, lease: nil) }
    #endif
    private func read(_ scope: CustomerQuarantineScope) throws -> CustomerQuarantineState? {
        do { return try store.read(scope) }
        catch {
            if storageFailures.insert(scope).inserted {
                Task { @MainActor [weak self] in self?.revision = UUID() }
            }
            throw error
        }
    }
    private func write(_ state: CustomerQuarantineState, for scope: CustomerQuarantineScope) throws {
        do { try store.write(state, for: scope); revision = UUID() }
        catch { if storageFailures.insert(scope).inserted { revision = UUID() }; throw error }
    }
    // Previously published values must also be retired when another owner
    // records a denial or rotates this customer's cache generation.
    func allowsPublishedValue(_ ticket: CustomerQuarantineTicket) -> Bool {
        guard let state = try? read(ticket.scope), !state.denied,
              state.denialEpoch == ticket.denialEpoch, state.cacheEpoch == ticket.cacheEpoch,
              state.authorityFingerprint == ticket.authorityFingerprint,
              Date() < ticket.authorityDeadline, !storageFailures.contains(ticket.scope) else { return false }
        return true
    }
    #if DEBUG
    func begin(_ scope: CustomerQuarantineScope) throws -> CustomerQuarantineTicket {
        try begin(scope, authority: CustomerQuarantineAuthority(actorID: scope.actorID, organizationID: scope.organizationID,
            origin: scope.origin, policyVersion: 1, serverGeneration: "test", capabilities: [], features: [:], deadline: .distantFuture))
    }
    #endif
    func begin(_ scope: CustomerQuarantineScope, authority: CustomerQuarantineAuthority) throws -> CustomerQuarantineTicket {
        let fingerprint = try authority.fingerprint(for: scope)
        let previous = try read(scope)
        var state = previous ?? CustomerQuarantineState()
        let authorityChanged = state.authorityFingerprint != fingerprint
        if authorityChanged {
            state.authorityFingerprint = fingerprint
            state.compilationVerified = false
            state.cacheEpoch = UUID()
        }
        // An upgrade has no durable proof that legacy unnamespaced copies
        // were not previously denied; first use must verify online.
        // A previously denied or interrupted read must never regain a cache
        // namespace whose entries were saved before the denial was known.
        let orphaned = !state.pending.subtracting(active[scope] ?? []).isEmpty
        if orphaned { state.relationshipLiveRequired = true }
        let requiresLive = previous == nil || authorityChanged || !state.compilationVerified || state.denied ||
                           state.relationshipLiveRequired || !state.pending.isEmpty || storageFailures.contains(scope)
        if state.denied || orphaned || storageFailures.contains(scope) { state.cacheEpoch = UUID() }
        let ticket = CustomerQuarantineTicket(id: UUID(), requiresLive: requiresLive,
                                              scope: scope, denialEpoch: state.denialEpoch, cacheEpoch: state.cacheEpoch,
                                              authorityFingerprint: fingerprint, authorityDeadline: authority.deadline)
        state.pending.insert(ticket.id)
        try write(state, for: scope)
        storageFailures.remove(scope)
        active[scope, default: []].insert(ticket.id)
        return ticket
    }
    func finish(_ ticket: CustomerQuarantineTicket, outcome: CustomerQuarantineOutcome) throws -> Bool {
        guard active[ticket.scope]?.contains(ticket.id) == true,
              var state = try read(ticket.scope), state.pending.contains(ticket.id) else {
            throw CustomerQuarantineError.invalidTicket
        }
        if Date() >= ticket.authorityDeadline && state.authorityFingerprint == ticket.authorityFingerprint &&
            state.cacheEpoch == ticket.cacheEpoch && state.denialEpoch == ticket.denialEpoch {
            state.denied = true
            state.compilationVerified = false
            state.relationshipLiveRequired = true
            state.denialEpoch = UUID()
            state.cacheEpoch = UUID()
            state.pending.remove(ticket.id)
            try write(state, for: ticket.scope)
            storageFailures.remove(ticket.scope)
            active[ticket.scope]?.remove(ticket.id)
            return false
        }
        let unchangedAuthority = state.denialEpoch == ticket.denialEpoch && state.cacheEpoch == ticket.cacheEpoch &&
                                 state.authorityFingerprint == ticket.authorityFingerprint && Date() < ticket.authorityDeadline
        switch outcome {
        case .denied, .uncertain:
            state.denied = true
            state.compilationVerified = false
            state.relationshipLiveRequired = true
            state.denialEpoch = UUID()
            state.cacheEpoch = UUID()
        case .liveCompilation:
            if unchangedAuthority {
                state.denied = false
                state.compilationVerified = true
                // Only this coordinator may own live requests. Markers left by
                // an earlier process can be retired after a complete live read.
                state.pending.formIntersection(active[ticket.scope] ?? [])
            }
        case .cached:
            guard !ticket.requiresLive, !state.denied, unchangedAuthority else {
                state.denied = true
                state.compilationVerified = false
                state.relationshipLiveRequired = true
                state.denialEpoch = UUID()
                state.cacheEpoch = UUID()
                state.pending.remove(ticket.id)
                try write(state, for: ticket.scope)
                storageFailures.remove(ticket.scope)
                active[ticket.scope]?.remove(ticket.id)
                throw CustomerQuarantineError.cachedResultForbidden
            }
        case .liveActivity:
            break
        }
        state.pending.remove(ticket.id)
        try write(state, for: ticket.scope)
        storageFailures.remove(ticket.scope)
        active[ticket.scope]?.remove(ticket.id)
        return outcome != .denied && outcome != .uncertain && unchangedAuthority && state.pending.isEmpty
    }
}

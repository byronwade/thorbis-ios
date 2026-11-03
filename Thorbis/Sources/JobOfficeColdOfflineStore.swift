import CryptoKit
import Darwin
import Foundation
import Security

/// Requires a currently verified persisted authority from the caller. Runtime
/// session/API generations still protect each in-flight request and publication.
struct JobOfficeColdScope: Codable, Hashable {
    let actor, organization, origin, job: String
    let policyVersion: Int
    let authorityGeneration: String
    /// SHA-256 of the verified server session ID; never the session token.
    let sessionDigest: String
    let deadline: Date
    init(actor: String, organization: String, origin: String, job: String, policyVersion: Int,
         authorityGeneration: String, sessionDigest: String, deadline: Date) {
        self.actor = actor.lowercased(); self.organization = organization.lowercased()
        self.origin = origin; self.job = job.lowercased(); self.policyVersion = policyVersion
        self.authorityGeneration = authorityGeneration; self.sessionDigest = sessionDigest; self.deadline = deadline
    }
    var identityIsValid: Bool {
        [actor, organization, job].allSatisfy { UUID(uuidString: $0) != nil && $0 == $0.lowercased() } &&
        policyVersion > 0 && !authorityGeneration.isEmpty && sessionDigest.count == 64 &&
        sessionDigest.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } && deadline.timeIntervalSince1970.isFinite
    }
    func sameAuthority(as other: Self) -> Bool {
        actor == other.actor && organization == other.organization && origin == other.origin && job == other.job &&
        policyVersion == other.policyVersion && authorityGeneration == other.authorityGeneration && sessionDigest == other.sessionDigest
    }
}

@MainActor protocol JobOfficeColdMarkerStorage {
    func read(_ key: String) throws -> Data?
    func write(_ data: Data, key: String) throws
    func removeAll() throws
}

@MainActor final class JobOfficeColdKeychain: JobOfficeColdMarkerStorage {
    private let service: String
    init(service: String = "com.thorbis.field.job-office-offline.v1") { self.service = service }
    enum Failure: Error { case keychain(OSStatus), invalidData }
    private func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }
    func read(_ key: String) throws -> Data? {
        var query = query(key); query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Failure.keychain(status) }
        guard let data = result as? Data else { throw Failure.invalidData }
        return data
    }
    func write(_ data: Data, key: String) throws {
        let query = query(key)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query; add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let inserted = SecItemAdd(add as CFDictionary, nil)
            guard inserted == errSecSuccess else { throw Failure.keychain(inserted) }
        } else if status != errSecSuccess { throw Failure.keychain(status) }
    }
    func removeAll() throws {
        let status = SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure.keychain(status) }
    }
}

/// Held only: no production reader currently calls this store. Every caller must
/// persist the preflight before making a live request and recheck live authority.
@MainActor final class JobOfficeColdOfflineStore {
    struct Snapshot: Codable { let scope: JobOfficeColdScope; let job: JobRecord; let epoch: UUID; let savedAt: Date }
    private struct Marker: Codable {
        enum State: String, Codable { case available, pending, denied }
        let state: State
        let ticket: UUID?
        let digest: String?
        let processEpoch: UUID?
        init(state: State, ticket: UUID?, digest: String?, processEpoch: UUID? = nil) {
            self.state = state; self.ticket = ticket; self.digest = digest; self.processEpoch = processEpoch
        }
    }
    enum Failure: Error { case invalidScope, unavailable, invalidJob, contended, io }
    private static var unsafe: Set<String> = []
    private static var retirementUnsafe: Set<String> = []
    private static let processEpoch = UUID()
    private static var activeAttempts: [String: UUID] = [:]
    private let directory: URL
    private let markers: any JobOfficeColdMarkerStorage
    private let clock: () -> Date
    private let writeSnapshot: (Data, URL) throws -> Void
    private let removeSnapshot: (URL) throws -> Void
    private let writeDenial: (Data, URL) throws -> Void

    init(directory: URL? = nil, markers: (any JobOfficeColdMarkerStorage)? = nil,
         clock: @escaping () -> Date = Date.init, writeSnapshot: ((Data, URL) throws -> Void)? = nil,
         removeSnapshot: ((URL) throws -> Void)? = nil, writeDenial: ((Data, URL) throws -> Void)? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("JobOfficeColdOffline", isDirectory: true)
        self.markers = markers ?? JobOfficeColdKeychain(); self.clock = clock
        self.writeSnapshot = writeSnapshot ?? { data, path in try data.write(to: path, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        self.removeSnapshot = removeSnapshot ?? { try FileManager.default.removeItem(at: $0) }
        self.writeDenial = writeDenial ?? { data, path in try data.write(to: path, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
    }
    private func key(_ scope: JobOfficeColdScope, requireUnexpired: Bool) throws -> String {
        guard scope.identityIsValid, APIClient.normalizedOrigin(scope.origin) == scope.origin,
              !requireUnexpired || clock() < scope.deadline else { throw Failure.invalidScope }
        // Policy, authority and deadline can change and later recur. Denials
        // must cover every variant within the same actor/job/session identity.
        let fields = [scope.actor, scope.organization, scope.origin, scope.job, scope.sessionDigest]
        return SHA256.hash(data: Data(fields.map { "\($0.utf8.count):\($0)" }.joined().utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private func withLifecycleLock<T>(exclusive: Bool, _ action: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var folder = directory; var values = URLResourceValues(); values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        let descriptor = open(directory.appendingPathComponent("retire.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw Failure.io }
        defer { close(descriptor) }
        guard flock(descriptor, (exclusive ? LOCK_EX : LOCK_SH) | LOCK_NB) == 0 else { throw Failure.contended }
        defer { _ = flock(descriptor, LOCK_UN) }
        return try action()
    }
    private func locked<T>(_ scope: JobOfficeColdScope, requireUnexpired: Bool = true, _ action: (String) throws -> T) throws -> T {
        let key = try key(scope, requireUnexpired: requireUnexpired)
        guard !Self.unsafe.contains(key), !Self.retirementUnsafe.contains(directory.path) else { throw Failure.unavailable }
        return try withLifecycleLock(exclusive: false) {
        guard try !pathExists(directory.appendingPathComponent("retire.barrier")) else { throw Failure.unavailable }
        let lockPath = directory.appendingPathComponent("\(key).lock").path
        let descriptor = open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw Failure.io }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw Failure.contended }
        defer { _ = flock(descriptor, LOCK_UN) }
        guard try !pathExists(denialIntent(key)) else { throw Failure.unavailable }
        let result = try action(key)
        // A denial can arrive from another process while this lock is held.
        // Never return a grant if its independent fence appeared meanwhile.
        guard try !pathExists(denialIntent(key)) else { throw Failure.unavailable }
        return result
        }
    }
    private func marker(_ key: String) throws -> Marker? {
        guard let data = try markers.read(key) else { return nil }
        return try JSONDecoder().decode(Marker.self, from: data)
    }
    private func saveMarker(_ value: Marker, key: String) throws {
        do { try markers.write(JSONEncoder().encode(value), key: key) }
        catch { Self.unsafe.insert(key); throw error }
    }
    private func barrier(_ key: String) -> URL { directory.appendingPathComponent("\(key).barrier") }
    private func denialIntent(_ key: String) -> URL { directory.appendingPathComponent("\(key).denied") }
    private func pathExists(_ path: URL) throws -> Bool {
        var info = stat()
        if lstat(path.path, &info) == 0 { return true }
        if errno == ENOENT { return false }
        throw Failure.io
    }
    private func barrierExists(_ key: String) throws -> Bool { try pathExists(barrier(key)) }
    private func establishBarrier(_ key: String) throws {
        do { try Data("pending".utf8).write(to: barrier(key), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        catch { Self.unsafe.insert(key); throw error }
    }
    private func clearBarrier(_ key: String) throws {
        do { try FileManager.default.removeItem(at: barrier(key)) }
        catch { Self.unsafe.insert(key); throw error }
    }
    private func snapshot(_ digest: String, scope: JobOfficeColdScope, key: String) throws -> Snapshot {
        guard digest.count == 64, digest.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else { throw Failure.unavailable }
        let data = try Data(contentsOf: directory.appendingPathComponent("\(key)-\(digest).json"))
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == digest else { throw Failure.unavailable }
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
        guard snapshot.scope.sameAuthority(as: scope), clock() < snapshot.scope.deadline,
              snapshot.job.id.lowercased() == scope.job,
              snapshot.job.organizationId.lowercased() == scope.organization else { throw Failure.unavailable }
        return snapshot
    }
    func beginLive(scope: JobOfficeColdScope) throws -> UUID {
        try locked(scope) { key in
            let interrupted = try barrierExists(key)
            let prior = try marker(key)
            let activePending = prior.map { previous in
                previous.state == .pending && previous.processEpoch == Self.processEpoch &&
                previous.ticket.map { Self.activeAttempts[key] == $0 } == true
            } ?? false
            let retained = !interrupted && (prior?.state == .available || activePending) ? prior?.digest : nil
            let ticket = UUID()
            try establishBarrier(key)
            try saveMarker(.init(state: .pending, ticket: ticket, digest: retained, processEpoch: Self.processEpoch), key: key)
            try clearBarrier(key)
            Self.activeAttempts[key] = ticket
            return ticket
        }
    }
    func completeLive(scope: JobOfficeColdScope, ticket: UUID, job: JobRecord, stillAuthorized: Bool) throws -> Snapshot? {
        try locked(scope) { key in
            guard try !barrierExists(key), let current = try marker(key), current.state == .pending, current.ticket == ticket,
                  current.processEpoch == Self.processEpoch, Self.activeAttempts[key] == ticket, stillAuthorized else { return nil }
            guard job.id.lowercased() == scope.job, job.organizationId.lowercased() == scope.organization else { throw Failure.invalidJob }
            let result = Snapshot(scope: scope, job: job, epoch: UUID(), savedAt: clock())
            let data = try JSONEncoder().encode(result)
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            do { try writeSnapshot(data, directory.appendingPathComponent("\(key)-\(digest).json")) }
            catch { Self.unsafe.insert(key); throw error }
            do {
                let paths = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                for path in paths where path.lastPathComponent.hasPrefix("\(key)-") && path.pathExtension == "json" && path.lastPathComponent != "\(key)-\(digest).json" {
                    try removeSnapshot(path)
                }
            } catch { Self.unsafe.insert(key); throw error }
            guard clock() < scope.deadline else { throw Failure.invalidScope }
            try saveMarker(.init(state: .available, ticket: nil, digest: digest), key: key)
            Self.activeAttempts.removeValue(forKey: key)
            return result
        }
    }
    func restoreAfterConnectivityFailure(scope: JobOfficeColdScope, ticket: UUID, stillAuthorized: Bool) throws -> Snapshot? {
        try locked(scope) { key in
            guard try !barrierExists(key), let current = try marker(key), current.state == .pending, current.ticket == ticket,
                  current.processEpoch == Self.processEpoch, Self.activeAttempts[key] == ticket,
                  stillAuthorized, let digest = current.digest else { return nil }
            let result = try snapshot(digest, scope: scope, key: key)
            guard clock() < scope.deadline else { throw Failure.invalidScope }
            try saveMarker(.init(state: .available, ticket: nil, digest: digest), key: key)
            Self.activeAttempts.removeValue(forKey: key)
            return result
        }
    }
    func deny(scope: JobOfficeColdScope) throws {
        // The fence is independent of the scope lock: a denial must be
        // recorded even when another process currently holds that lock. It is
        // deliberately permanent for this session identity until retirement.
        let key = try key(scope, requireUnexpired: false)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try writeDenial(Data("denied".utf8), denialIntent(key))
            Self.activeAttempts.removeValue(forKey: key)
        } catch { Self.unsafe.insert(key); throw error }
    }
    /// Call when an in-flight task is canceled or retired without a result.
    /// The pending marker remains, but its previous grant cannot be restored.
    func abandon(scope: JobOfficeColdScope, ticket: UUID) throws {
        try locked(scope, requireUnexpired: false) { key in
            if Self.activeAttempts[key] == ticket { Self.activeAttempts.removeValue(forKey: key) }
        }
    }
    func offline(scope: JobOfficeColdScope, authorized: Bool) -> Snapshot? {
        guard authorized else { return nil }
        return try? locked(scope) { key in
            guard try !barrierExists(key), let current = try marker(key), current.state == .available, let digest = current.digest else { return nil }
            let result = try snapshot(digest, scope: scope, key: key)
            guard clock() < scope.deadline else { throw Failure.invalidScope }
            return result
        }
    }
    /// The caller must not complete sign-out on failure. Lock files are never
    /// unlinked: changing their inode while another process holds one would
    /// split the coordination domain. The barrier survives incomplete cleanup.
    func retireAll() throws {
        try withLifecycleLock(exclusive: true) {
            let retired = directory.appendingPathComponent("retire.barrier")
            do {
                try Data("retiring".utf8).write(to: retired, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                Self.activeAttempts.removeAll()
                try markers.removeAll()
                let paths = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                for path in paths where path.standardizedFileURL.path != retired.standardizedFileURL.path && (path.pathExtension == "json" || path.pathExtension == "barrier" || path.pathExtension == "denied") {
                    try FileManager.default.removeItem(at: path)
                }
                // Keep the retirement fence. A stale process must not recreate
                // a grant after sign-out; reactivation needs a separately
                // qualified authority protocol, which this prototype lacks.
                Self.retirementUnsafe.remove(directory.path)
            } catch {
                Self.retirementUnsafe.insert(directory.path)
                throw error
            }
        }
    }
}

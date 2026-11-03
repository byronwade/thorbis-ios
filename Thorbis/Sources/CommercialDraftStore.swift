import CryptoKit
import Darwin
import Foundation

/// A local draft belongs to the authenticated person, workspace, server and paper it came from.
struct CommercialDraftScope: Codable, Hashable {
    let actor: String
    let organization: String
    let origin: String
    let kind: String
    let document: String
}

/// Unsaved work is deliberately independent of the disposable server-response cache. It survives
/// sign-out, but can only be looked up using the original authenticated scope. The file system
/// provides device-bound data protection, and the directory is excluded from backups.
@MainActor final class CommercialDraftStore {
    #if DEBUG
    static func trace(_ message: String) {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--commercial-draft-test-trace"),
              let index = arguments.firstIndex(of: "--commercial-draft-test-id"),
              arguments.indices.contains(index + 1), let id = UUID(uuidString: arguments[index + 1]) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CommercialDraftTrace-\(id.uuidString).log")
        if !FileManager.default.fileExists(atPath: url.path) { _ = FileManager.default.createFile(atPath: url.path, contents: nil) }
        guard let file = try? FileHandle(forWritingTo: url) else { return }
        defer { try? file.close() }
        try? file.seekToEnd()
        try? file.write(contentsOf: Data("\(Date().timeIntervalSince1970) \(message)\n".utf8))
    }
    static let shared: CommercialDraftStore = {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--paper-preview") else { return CommercialDraftStore() }
        let requested = arguments.firstIndex(of: "--commercial-draft-test-id").flatMap { index in
            arguments.indices.contains(index + 1) ? UUID(uuidString: arguments[index + 1]) : nil
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CommercialDraftPreview-\((requested ?? UUID()).uuidString)")
        if arguments.contains("--commercial-draft-test-cleanup-fails") {
            return CommercialDraftStore(directory: directory, removeItem: { _ in throw CocoaError(.fileWriteNoPermission) })
        }
        return CommercialDraftStore(directory: directory)
    }()
    #else
    static let shared = CommercialDraftStore()
    #endif
    private let directory: URL
    private let removeItem: (URL) throws -> Void
    private let writeItem: (Data, URL) throws -> Void
    private var owners: [CommercialDraftScope: UUID] = [:]
    private var coordinatedDrafts: [CommercialDraftScope: (owner: UUID, fd: Int32)] = [:]

    private struct Envelope<Value: Codable>: Codable {
        let version: Int
        let scope: CommercialDraftScope
        let value: Value
    }

    init(directory: URL? = nil, removeItem: ((URL) throws -> Void)? = nil,
         writeItem: ((Data, URL) throws -> Void)? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CommercialDrafts", isDirectory: true)
        self.removeItem = removeItem ?? { try FileManager.default.removeItem(at: $0) }
        self.writeItem = writeItem ?? { data, url in try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
    }

    /// One editor per scope in this app process prevents two windows silently replacing each
    /// other's unfinished work. A different device still relies on the server revision guard.
    func acquire(scope: CommercialDraftScope, owner: UUID) -> Bool {
        guard owners[scope] == nil || owners[scope] == owner else { return false }
        owners[scope] = owner
        return true
    }
    func release(scope: CommercialDraftScope, owner: UUID) {
        if let lease = coordinatedDrafts[scope], lease.owner == owner {
            _ = flock(lease.fd, LOCK_UN); close(lease.fd); coordinatedDrafts.removeValue(forKey: scope)
        }
        if owners[scope] == owner { owners.removeValue(forKey: scope) }
    }
    func isOwned(scope: CommercialDraftScope, owner: UUID) -> Bool { owners[scope] == owner }

    /// Held protocol: acquire this source lease before the job attempt lock.
    /// Lock files are permanent and no blocking lock or await occurs here.
    func acquireCoordinatedDraft(scope: CommercialDraftScope, owner: UUID) throws -> Bool {
        guard scope.kind == "new-estimate" else { throw CocoaError(.fileWriteNoPermission) }
        if let existing = coordinatedDrafts[scope] { return existing.owner == owner }
        let alreadyOwned = owners[scope] == owner
        guard acquire(scope: scope, owner: owner) else { return false }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // Scope identity is UUID-based. Case variants must contend on the
            // same lease even if a legacy draft used different casing.
            let lockScope = CommercialDraftScope(actor: scope.actor.lowercased(), organization: scope.organization.lowercased(),
                                                 origin: scope.origin.lowercased(), kind: scope.kind, document: scope.document.lowercased())
            let lock = try file(for: lockScope).deletingPathExtension().appendingPathExtension("draft.lock")
            let fd = open(lock.path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
            guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
                let error = errno; close(fd)
                if error == EWOULDBLOCK || error == EAGAIN { if !alreadyOwned { release(scope: scope, owner: owner) }; return false }
                throw POSIXError(POSIXErrorCode(rawValue: error) ?? .EIO)
            }
            coordinatedDrafts[scope] = (owner, fd)
            return true
        } catch { if !alreadyOwned { release(scope: scope, owner: owner) }; throw error }
    }
    func isCoordinatedOwner(scope: CommercialDraftScope, owner: UUID) -> Bool {
        owners[scope] == owner && coordinatedDrafts[scope]?.owner == owner
    }
    func saveCoordinatedDraft<Value: Codable>(_ value: Value, scope: CommercialDraftScope, owner: UUID) throws {
        guard isCoordinatedOwner(scope: scope, owner: owner) else { throw CocoaError(.fileWriteNoPermission) }
        try saveRaw(value, scope: scope)
    }
    func removeCoordinatedDraft(scope: CommercialDraftScope, owner: UUID) throws {
        guard isCoordinatedOwner(scope: scope, owner: owner) else { throw CocoaError(.fileWriteNoPermission) }
        try removeRaw(scope: scope)
    }

    deinit { for (_, lease) in coordinatedDrafts { _ = flock(lease.fd, LOCK_UN); close(lease.fd) } }

    private func file(for scope: CommercialDraftScope) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let digest = SHA256.hash(data: try encoder.encode(scope)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest + ".json")
    }

    /// Stable per-attempt lock file. Never unlink it: another process may hold
    /// the inode. Callers may not await or acquire a second lock in `body`.
    func withAttemptLock<T>(scope: CommercialDraftScope, _ body: () throws -> T) throws -> T {
        guard scope.kind == "atomic-estimate-attempt" else { throw CocoaError(.fileWriteNoPermission) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lock = try file(for: scope).deletingPathExtension().appendingPathExtension("lock")
        let fd = open(lock.path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { _ = flock(fd, LOCK_UN) }
        return try body()
    }

    /// Caller holds the attempt lock. A hard-link install refuses to replace
    /// any existing record even if a non-cooperating process races the check.
    func createAttempt<Value: Codable>(_ value: Value, scope: CommercialDraftScope) throws {
        guard scope.kind == "atomic-estimate-attempt" else { throw CocoaError(.fileWriteNoPermission) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var folder = directory; var resources = URLResourceValues(); resources.isExcludedFromBackup = true
        try folder.setResourceValues(resources)
        let data = try JSONEncoder().encode(Envelope(version: 1, scope: scope, value: value))
        let temporary = directory.appendingPathComponent(".attempt-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try writeItem(data, temporary)
        guard link(temporary.path, try file(for: scope).path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    func save<Value: Codable>(_ value: Value, scope: CommercialDraftScope) throws {
        try saveRaw(value, scope: scope)
    }

    private func saveRaw<Value: Codable>(_ value: Value, scope: CommercialDraftScope) throws {
        #if DEBUG
        Self.trace("save \(scope.kind)")
        #endif
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var folder = directory
        var resources = URLResourceValues()
        resources.isExcludedFromBackup = true
        try folder.setResourceValues(resources)
        let data = try JSONEncoder().encode(Envelope(version: 1, scope: scope, value: value))
        try writeItem(data, file(for: scope))
    }

    func load<Value: Codable>(_ type: Value.Type, scope: CommercialDraftScope) throws -> Value? {
        try loadVersioned(type, scope: scope)?.value
    }

    /// Exact encoded bytes and decoded value from one read, for detecting
    /// changes before a held editor writes. This is not a cross-process CAS.
    func loadVersioned<Value: Codable>(_ type: Value.Type, scope: CommercialDraftScope) throws -> (value: Value, bytes: Data)? {
        let url = try file(for: scope)
        #if DEBUG
        Self.trace("load \(scope.kind) exists=\(FileManager.default.fileExists(atPath: url.path))")
        #endif
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let bytes = try Data(contentsOf: url)
        let envelope = try JSONDecoder().decode(Envelope<Value>.self, from: bytes)
        guard envelope.version == 1, envelope.scope == scope else { throw CocoaError(.fileReadCorruptFile) }
        return (envelope.value, bytes)
    }

    func remove(scope: CommercialDraftScope) throws {
        try removeRaw(scope: scope)
    }

    private func removeRaw(scope: CommercialDraftScope) throws {
        let url = try file(for: scope)
        #if DEBUG
        Self.trace("remove \(scope.kind) exists=\(FileManager.default.fileExists(atPath: url.path))")
        #endif
        if FileManager.default.fileExists(atPath: url.path) { try removeItem(url) }
    }
}

import CryptoKit
import Darwin
import Foundation

/// Held local recovery copies. This is not authorization, a replacement for the
/// canonical draft, or proof of power-loss durability. All participating writers
/// must use this protocol; older or noncooperating writers remain a blocker.
@MainActor final class EstimateRecoveryCopyStore<Scope: Codable & Equatable, Draft: Codable> {
    enum Failure: Error { case unavailable, conflict, discarded }
    struct PendingDiscard { let id: UUID; let draft: Draft }
    private struct Envelope: Codable { let version: Int; let id: UUID; let scope: Scope; let draft: Draft }
    private struct Tombstone: Codable { let version: Int; let id: UUID; let scope: Scope; let digest: String }
    private let directory: URL
    private let writeItem: (Data, URL) throws -> Void
    private let inspectRead: (Data) throws -> Data
    private let removeItem: (URL) throws -> Void
    init(directory: URL, writeItem: ((Data, URL) throws -> Void)? = nil, inspectRead: ((Data) throws -> Data)? = nil,
         removeItem: ((URL) throws -> Void)? = nil) {
        self.directory = directory
        self.writeItem = writeItem ?? { data, url in try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        self.inspectRead = inspectRead ?? { $0 }
        self.removeItem = removeItem ?? { url in
            guard unlink(url.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }
    }
    private func folder(scope: Scope) throws -> URL {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let hash = SHA256.hash(data: try encoder.encode(scope)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash, isDirectory: true)
    }
    private func url(_ id: UUID, folder: URL) -> URL { folder.appendingPathComponent(id.uuidString.lowercased() + ".json") }
    private func tombstoneURL(_ id: UUID, folder: URL) -> URL { folder.appendingPathComponent(id.uuidString.lowercased() + ".discarded") }
    /// The lock file is permanent: removing it could split cooperating writers
    /// across different inodes. No suspension occurs while the lock is held.
    private func withScopeLock<T>(_ scope: Scope, _ body: (URL) throws -> T) throws -> T {
        let folder = try folder(scope: scope)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lockURL = directory.appendingPathComponent(folder.lastPathComponent + ".lock")
        let fd = open(lockURL.path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { _ = flock(fd, LOCK_UN) }
        return try body(folder)
    }
    private func exists(_ url: URL) throws -> Bool {
        var info = stat()
        if lstat(url.path, &info) == 0 { return true }
        let failure = errno
        if failure == ENOENT { return false }
        throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EIO)
    }
    func list(scope: Scope) throws -> [UUID] {
        try withScopeLock(scope) { folder in
            guard try exists(folder) else { return [] }
            var info = stat(); guard lstat(folder.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { throw Failure.unavailable }
            let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            guard names.count <= 512 else { throw Failure.unavailable }
            var ids: [UUID] = []
            for name in names {
                if name.hasPrefix(".recovery-") && name.hasSuffix(".tmp") { continue }
                if name.hasSuffix(".discarded") {
                    guard let id = UUID(uuidString: String(name.dropLast(10))), name == id.uuidString.lowercased() + ".discarded" else { throw Failure.unavailable }
                    let marker = try decodeTombstone(scope: scope, id: id, folder: folder)
                    guard marker.id == id else { throw Failure.unavailable }
                    continue
                }
                guard name.hasSuffix(".json"), let id = UUID(uuidString: String(name.dropLast(5))),
                      name == id.uuidString.lowercased() + ".json" else { throw Failure.unavailable }
                if try exists(tombstoneURL(id, folder: folder)) { _ = try decodeTombstone(scope: scope, id: id, folder: folder); continue }
                _ = try readUnlocked(scope: scope, id: id, folder: folder)
                ids.append(id)
            }
            return ids.sorted { $0.uuidString < $1.uuidString }
        }
    }
    /// Discovers interrupted removals only within the supplied scope. The
    /// caller must separately prove current authorization before displaying or
    /// retrying a draft; a scope value alone is not an access grant.
    func pendingDiscards(scope: Scope) throws -> [PendingDiscard] {
        try withScopeLock(scope) { folder in
            guard try exists(folder) else { return [] }
            var info = stat()
            guard lstat(folder.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { throw Failure.unavailable }
            let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            guard names.count <= 512 else { throw Failure.unavailable }
            var result: [PendingDiscard] = []
            for name in names {
                if name.hasPrefix(".recovery-") && name.hasSuffix(".tmp") { continue }
                if name.hasSuffix(".json") {
                    guard let id = UUID(uuidString: String(name.dropLast(5))),
                          name == id.uuidString.lowercased() + ".json" else { throw Failure.unavailable }
                    continue
                }
                guard name.hasSuffix(".discarded"), let id = UUID(uuidString: String(name.dropLast(10))),
                      name == id.uuidString.lowercased() + ".discarded" else { throw Failure.unavailable }
                let marker = try decodeTombstone(scope: scope, id: id, folder: folder)
                let copy = url(id, folder: folder)
                guard try exists(copy) else { continue }
                let raw = try readBytes(copy)
                guard marker.digest == digest(raw) else { throw Failure.conflict }
                let envelope = try JSONDecoder().decode(Envelope.self, from: raw)
                guard envelope.version == 1, envelope.id == id, envelope.scope == scope else { throw Failure.unavailable }
                result.append(PendingDiscard(id: id, draft: envelope.draft))
            }
            return result.sorted { $0.id.uuidString < $1.id.uuidString }
        }
    }
    private func encode<T: Encodable>(_ value: T) throws -> Data { let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys; return try encoder.encode(value) }
    private func bytes(id: UUID, scope: Scope, draft: Draft) throws -> Data { try encode(Envelope(version: 1, id: id, scope: scope, draft: draft)) }
    private func digest(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
    /// Installs by hard link; no existing copy or discard marker is replaced.
    private func installBytes(_ data: Data, at target: URL, folder: URL) throws {
        let temporary = folder.appendingPathComponent(".recovery-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try writeItem(data, temporary)
        if link(temporary.path, target.path) != 0 {
            let code = errno
            guard code == EEXIST else { throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO) }
        }
        guard try readBytes(target) == data else { throw Failure.conflict }
    }
    func install(_ draft: Draft, scope: Scope, id: UUID) throws {
        try withScopeLock(scope) { folder in
            let expected = try bytes(id: id, scope: scope, draft: draft)
            var writableFolder = folder; try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var properties = URLResourceValues(); properties.isExcludedFromBackup = true; try writableFolder.setResourceValues(properties)
            guard try !exists(tombstoneURL(id, folder: folder)) else { throw Failure.discarded }
            try installBytes(expected, at: url(id, folder: folder), folder: folder)
            _ = try readUnlocked(scope: scope, id: id, folder: folder)
        }
    }
    func read(scope: Scope, id: UUID) throws -> Draft { try withScopeLock(scope) { try readUnlocked(scope: scope, id: id, folder: $0) } }
    private func readUnlocked(scope: Scope, id: UUID, folder: URL) throws -> Draft {
        guard try !exists(tombstoneURL(id, folder: folder)) else { throw Failure.discarded }
        let envelope = try JSONDecoder().decode(Envelope.self, from: readBytes(url(id, folder: folder)))
        guard envelope.version == 1, envelope.id == id, envelope.scope == scope else { throw Failure.unavailable }
        return envelope.draft
    }
    private func decodeTombstone(scope: Scope, id: UUID, folder: URL) throws -> Tombstone {
        let marker = try JSONDecoder().decode(Tombstone.self, from: readBytes(tombstoneURL(id, folder: folder)))
        guard marker.version == 1, marker.id == id, marker.scope == scope,
              marker.digest.utf8.count == 64, marker.digest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw Failure.unavailable }
        return marker
    }
    /// Explicit discard validates the exact selected content, installs a marker
    /// before unlinking, and never touches the canonical draft or other IDs.
    /// A thrown error may follow either step; callers must not claim success.
    func discard(_ draft: Draft, scope: Scope, id: UUID) throws {
        try withScopeLock(scope) { folder in
            let expected = try bytes(id: id, scope: scope, draft: draft)
            let markerURL = tombstoneURL(id, folder: folder), copyURL = url(id, folder: folder)
            if try exists(markerURL) {
                let marker = try decodeTombstone(scope: scope, id: id, folder: folder)
                guard marker.digest == digest(expected) else { throw Failure.conflict }
            } else {
                guard try readBytes(copyURL) == expected else { throw Failure.conflict }
                let marker = Tombstone(version: 1, id: id, scope: scope, digest: digest(expected))
                try installBytes(encode(marker), at: markerURL, folder: folder)
                _ = try decodeTombstone(scope: scope, id: id, folder: folder)
            }
            if try exists(copyURL) {
                guard try readBytes(copyURL) == expected else { throw Failure.conflict }
                try removeItem(copyURL)
            }
            guard try !exists(copyURL) else { throw Failure.unavailable }
        }
    }
    private func readBytes(_ url: URL) throws -> Data {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var details = stat()
        guard fstat(fd, &details) == 0, details.st_mode & S_IFMT == S_IFREG else { throw Failure.unavailable }
        guard let content = try handle.readToEnd() else { throw Failure.unavailable }
        return try inspectRead(content)
    }
}

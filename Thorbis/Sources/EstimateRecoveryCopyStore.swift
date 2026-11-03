import CryptoKit
import Darwin
import Foundation

/// Held, disconnected local recovery copies. This is not authorization, a
/// replacement for the canonical draft, or proof of power-loss durability.
@MainActor final class EstimateRecoveryCopyStore<Scope: Codable & Equatable, Draft: Codable> {
    enum Failure: Error { case unavailable, conflict }
    private struct Envelope: Codable { let version: Int; let id: UUID; let scope: Scope; let draft: Draft }
    private let directory: URL
    private let writeItem: (Data, URL) throws -> Void
    private let inspectRead: (Data) throws -> Data
    init(directory: URL, writeItem: ((Data, URL) throws -> Void)? = nil, inspectRead: ((Data) throws -> Data)? = nil) {
        self.directory = directory
        self.writeItem = writeItem ?? { data, url in try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        self.inspectRead = inspectRead ?? { $0 }
    }
    private func folder(scope: Scope) throws -> URL {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let hash = SHA256.hash(data: try encoder.encode(scope)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash, isDirectory: true)
    }
    private func url(_ id: UUID, scope: Scope) throws -> URL {
        try folder(scope: scope).appendingPathComponent(id.uuidString.lowercased() + ".json")
    }
    /// Enumerate only this scope's copy IDs. Corrupt or unexpected records
    /// block discovery rather than being silently treated as absent.
    func list(scope: Scope) throws -> [UUID] {
        let folder = try folder(scope: scope)
        var info = stat()
        guard lstat(folder.path, &info) == 0 else {
            let failure = errno
            if failure == ENOENT { return [] }
            throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EIO)
        }
        guard info.st_mode & S_IFMT == S_IFDIR else { throw Failure.unavailable }
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        guard names.count <= 256 else { throw Failure.unavailable }
        var ids: [UUID] = []
        for name in names {
            if name.hasPrefix(".recovery-") && name.hasSuffix(".tmp") { continue }
            guard name.hasSuffix(".json"), let id = UUID(uuidString: String(name.dropLast(5))),
                  name == id.uuidString.lowercased() + ".json" else { throw Failure.unavailable }
            _ = try read(scope: scope, id: id)
            ids.append(id)
        }
        return ids.sorted { $0.uuidString < $1.uuidString }
    }
    private func bytes(id: UUID, scope: Scope, draft: Draft) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return try encoder.encode(Envelope(version: 1, id: id, scope: scope, draft: draft))
    }
    /// Never replaces a record. A repeated ID succeeds only when it already
    /// contains exactly the same scoped content; errors are not proof of absence.
    func install(_ draft: Draft, scope: Scope, id: UUID) throws {
        let expected = try bytes(id: id, scope: scope, draft: draft)
        var folder = try folder(scope: scope)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
         var properties = URLResourceValues(); properties.isExcludedFromBackup = true
        try folder.setResourceValues(properties)
        let temporary = folder.appendingPathComponent(".recovery-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try writeItem(expected, temporary)
        if link(temporary.path, try url(id, scope: scope).path) != 0 {
            let code = errno
            guard code == EEXIST else { throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO) }
        }
        let actual = try readBytes(id: id, scope: scope)
        guard actual == expected else { throw Failure.conflict }
        let decoded = try JSONDecoder().decode(Envelope.self, from: actual)
        guard decoded.version == 1, decoded.id == id, decoded.scope == scope else { throw Failure.unavailable }
    }
    func read(scope: Scope, id: UUID) throws -> Draft {
        let envelope = try JSONDecoder().decode(Envelope.self, from: readBytes(id: id, scope: scope))
        guard envelope.version == 1, envelope.id == id, envelope.scope == scope else { throw Failure.unavailable }
        return envelope.draft
    }
    private func readBytes(id: UUID, scope: Scope) throws -> Data {
        let fd = open(try url(id, scope: scope).path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var details = stat()
        guard fstat(fd, &details) == 0, details.st_mode & S_IFMT == S_IFREG else { throw Failure.unavailable }
        guard let content = try handle.readToEnd() else { throw Failure.unavailable }
        return try inspectRead(content)
    }
}

import Darwin
import Foundation

/// Held, disconnected local recovery copies. This is not authorization, a
/// replacement for the canonical draft, or proof of power-loss durability.
@MainActor final class EstimateRecoveryCopyStore<Scope: Codable & Equatable, Draft: Codable> {
    enum Failure: Error { case unavailable, conflict }
    private struct Envelope: Codable { let version: Int; let id: UUID; let scope: Scope; let draft: Draft }
    private let directory: URL
    init(directory: URL) { self.directory = directory }
    private func url(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString.lowercased() + ".json") }
    private func bytes(id: UUID, scope: Scope, draft: Draft) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return try encoder.encode(Envelope(version: 1, id: id, scope: scope, draft: draft))
    }
    /// Never replaces a record. A repeated ID succeeds only when it already
    /// contains exactly the same scoped content; errors are not proof of absence.
    func install(_ draft: Draft, scope: Scope, id: UUID) throws {
        let expected = try bytes(id: id, scope: scope, draft: draft)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var folder = directory; var properties = URLResourceValues(); properties.isExcludedFromBackup = true
        try folder.setResourceValues(properties)
        let temporary = directory.appendingPathComponent(".recovery-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try expected.write(to: temporary, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        if link(temporary.path, url(id).path) != 0 {
            let code = errno
            guard code == EEXIST else { throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO) }
        }
        let actual = try readBytes(id: id)
        guard actual == expected else { throw Failure.conflict }
        let decoded = try JSONDecoder().decode(Envelope.self, from: actual)
        guard decoded.version == 1, decoded.id == id, decoded.scope == scope else { throw Failure.unavailable }
    }
    func read(scope: Scope, id: UUID) throws -> Draft {
        let envelope = try JSONDecoder().decode(Envelope.self, from: readBytes(id: id))
        guard envelope.version == 1, envelope.id == id, envelope.scope == scope else { throw Failure.unavailable }
        return envelope.draft
    }
    private func readBytes(id: UUID) throws -> Data {
        let fd = open(url(id).path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var details = stat()
        guard fstat(fd, &details) == 0, details.st_mode & S_IFMT == S_IFREG else { throw Failure.unavailable }
        guard let content = try handle.readToEnd() else { throw Failure.unavailable }
        return content
    }
}

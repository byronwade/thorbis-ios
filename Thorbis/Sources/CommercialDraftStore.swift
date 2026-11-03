import CryptoKit
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
    static var previewFailCreatedWrites = true
    static var previewFailAllWrites = false
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
        if arguments.contains("--commercial-draft-test-switchable-writes") {
            return CommercialDraftStore(directory: directory, writeItem: { data, url in
                if CommercialDraftStore.previewFailAllWrites { throw CocoaError(.fileWriteNoPermission) }
                try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            })
        }
        if arguments.contains("--commercial-draft-test-all-writes-fail") {
            return CommercialDraftStore(directory: directory, writeItem: { _, _ in throw CocoaError(.fileWriteNoPermission) })
        }
        if arguments.contains("--commercial-draft-test-created-write-fails") {
            return CommercialDraftStore(directory: directory, writeItem: { data, url in
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let value = object?["value"] as? [String: Any]
                if CommercialDraftStore.previewFailCreatedWrites, value?["created"] is [String: Any] { throw CocoaError(.fileWriteNoPermission) }
                try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            })
        }
        if arguments.contains("--commercial-draft-test-cleanup-fails") {
            return CommercialDraftStore(directory: directory, removeItem: { _ in throw CocoaError(.fileWriteNoPermission) })
        }
        return CommercialDraftStore(directory: directory)
    }()
    #else
    static let shared = CommercialDraftStore()
    #endif
    /// Retains unsaved work only for this app process after an editor vanishes.
    static let unpersistedEstimates = VolatileDraftRecovery<CommercialDraftScope, CommercialNewEstimateDraft>()
    static let estimateRecoveryCopies: EstimateRecoveryCopyStore<CommercialDraftScope, CommercialNewEstimateDraft> = {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--paper-preview") {
            let requested = arguments.firstIndex(of: "--commercial-draft-test-id").flatMap { index in
                arguments.indices.contains(index + 1) ? UUID(uuidString: arguments[index + 1]) : nil
            }
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("EstimateRecoveryPreview-\((requested ?? UUID()).uuidString)")
            return EstimateRecoveryCopyStore(directory: folder)
        }
        #endif
        return EstimateRecoveryCopyStore(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EstimateRecoveryCopies", isDirectory: true))
    }()
    private let directory: URL
    private let removeItem: (URL) throws -> Void
    private let writeItem: (Data, URL) throws -> Void
    private var owners: [CommercialDraftScope: UUID] = [:]

    private struct Envelope<Value: Codable>: Codable {
        let version: Int
        let scope: CommercialDraftScope
        let value: Value
    }

    init(directory: URL? = nil, removeItem: ((URL) throws -> Void)? = nil, writeItem: ((Data, URL) throws -> Void)? = nil) {
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
        if owners[scope] == owner { owners.removeValue(forKey: scope) }
    }

    private func file(for scope: CommercialDraftScope) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let digest = SHA256.hash(data: try encoder.encode(scope)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest + ".json")
    }

    func save<Value: Codable>(_ value: Value, scope: CommercialDraftScope) throws {
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
        let url = try file(for: scope)
        #if DEBUG
        Self.trace("load \(scope.kind) exists=\(FileManager.default.fileExists(atPath: url.path))")
        #endif
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let envelope = try JSONDecoder().decode(Envelope<Value>.self, from: Data(contentsOf: url))
        guard envelope.version == 1, envelope.scope == scope else { throw CocoaError(.fileReadCorruptFile) }
        return envelope.value
    }

    func remove(scope: CommercialDraftScope) throws {
        let url = try file(for: scope)
        #if DEBUG
        Self.trace("remove \(scope.kind) exists=\(FileManager.default.fileExists(atPath: url.path))")
        #endif
        if FileManager.default.fileExists(atPath: url.path) { try removeItem(url) }
    }
}

import CryptoKit
import Foundation
import Combine

struct PendingMediaScope: Codable, Equatable, Sendable {
    let actorID: String
    let organizationID: String
    let origin: String
}

struct PendingMedia: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let jobID: String
    let filename: String
    let tags: [String]
    let capturedAt: Date
    let kind: String
    let mime: String

    var title: String { kind == "document" ? filename : tags.first.map { "\($0) photo" } ?? "Photo" }
}

/// Metadata is observable; original bytes stay on disk until matching server confirmation.
@MainActor
final class PendingMediaStore: ObservableObject {
    static let shared = PendingMediaStore()
    @Published private(set) var items: [PendingMedia] = []
    @Published private(set) var errors: [String: String] = [:]
    @Published private(set) var storageWarning: String?
    @Published private(set) var uploadingID: String?
    @Published private(set) var legacyCount = 0
    @Published private(set) var totalPendingCount = 0

    struct CaptureContext: Equatable {
        fileprivate let scope: PendingMediaScope
        fileprivate let binding: UUID
    }
    var captureContext: CaptureContext? { scope.map { CaptureContext(scope: $0, binding: binding) } }

    private struct Envelope: Codable {
        let scope: PendingMediaScope
        let media: PendingMedia
        let size: Int
        let hash: String
    }
    private enum StorageError: LocalizedError {
        case unbound, invalid, unreadable, existing
        var errorDescription: String? {
            switch self {
            case .unbound: "Open the original workspace before saving or retrying this media."
            case .invalid: "This media could not be saved. Choose a supported nonempty file up to 8 MB."
            case .unreadable: "This phone cannot read the saved media. Keep it here and retry after unlocking the phone."
            case .existing: "This media is already saved. Retry its existing upload."
            }
        }
    }
    private let directory: URL
    private let legacyDirectory: URL
    private var scope: PendingMediaScope?
    private var binding = UUID()
    private var draining = false

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.directory = base.appendingPathComponent("PendingMedia", isDirectory: true)
        legacyDirectory = base.appendingPathComponent("PendingPhotos", isDirectory: true)
    }

    func bind(_ candidate: PendingMediaScope?) {
        let normalized = candidate.flatMap { value -> PendingMediaScope? in
            guard !value.actorID.isEmpty, !value.organizationID.isEmpty,
                  let origin = APIClient.normalizedOrigin(value.origin) else { return nil }
            return PendingMediaScope(actorID: value.actorID, organizationID: value.organizationID, origin: origin)
        }
        if scope != normalized { binding = UUID(); errors = [:] }
        scope = normalized
        reload()
    }

    private func scopeDirectory(_ scope: PendingMediaScope) throws -> URL {
        // Structured encoding prevents separator collisions and raw identities in filenames.
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return directory.appendingPathComponent(Self.hash(try encoder.encode(scope)), isDirectory: true)
    }
    private func unit(_ media: PendingMedia, scope: PendingMediaScope) throws -> URL {
        guard UUID(uuidString: media.id) != nil else { throw StorageError.invalid }
        return try scopeDirectory(scope).appendingPathComponent(media.id, isDirectory: true)
    }
    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private func protect(_ url: URL) throws {
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        var file = url
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try file.setResourceValues(values)
    }
    private func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                               attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        try protect(url)
    }

    func save(_ media: PendingMedia, data: Data, context: CaptureContext) throws {
        guard let scope else { throw StorageError.unbound }
        guard context.scope == scope, context.binding == binding else { throw StorageError.unbound }
        guard UUID(uuidString: media.jobID) != nil, !data.isEmpty, data.count <= 8 * 1024 * 1024,
              ((media.kind == "photo" && ["image/jpeg", "image/png", "image/heic", "image/webp"].contains(media.mime)) ||
               (media.kind == "document" && media.mime == "application/pdf")) else { throw StorageError.invalid }
        let destination = try unit(media, scope: scope)
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw StorageError.existing }
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        do {
            try createDirectory(directory)
            try createDirectory(destination.deletingLastPathComponent())
            try createDirectory(staging)
            let payload = staging.appendingPathComponent("payload")
            try data.write(to: payload, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]); try protect(payload)
            let metadata = staging.appendingPathComponent("metadata.json")
            let envelope = Envelope(scope: scope, media: media, size: data.count, hash: Self.hash(data))
            try JSONEncoder().encode(envelope).write(to: metadata, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]); try protect(metadata)
            try FileManager.default.moveItem(at: staging, to: destination)
            reload()
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    func read(_ media: PendingMedia) throws -> Data {
        guard let scope, items.contains(media) else { throw StorageError.unbound }
        do {
            let path = try unit(media, scope: scope)
            let envelope = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: path.appendingPathComponent("metadata.json")))
            guard envelope.scope == scope, envelope.media == media, (1...8 * 1024 * 1024).contains(envelope.size) else { throw StorageError.unreadable }
            let payload = path.appendingPathComponent("payload")
            let size = try payload.resourceValues(forKeys: [.fileSizeKey]).fileSize
            guard size == envelope.size else { throw StorageError.unreadable }
            let data = try Data(contentsOf: payload)
            guard Self.hash(data) == envelope.hash else { throw StorageError.unreadable }
            return data
        } catch {
            errors[media.id] = StorageError.unreadable.localizedDescription
            throw StorageError.unreadable
        }
    }

    func reload() {
        storageWarning = nil
        items = []
        if let scope {
            do {
                let folder = try scopeDirectory(scope)
                if FileManager.default.fileExists(atPath: folder.path) {
                    for path in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
                        if path.lastPathComponent.hasPrefix(".staging-") {
                            storageWarning = "An interrupted media save remains on this phone and needs recovery."
                            continue
                        }
                        do {
                            let envelope = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: path.appendingPathComponent("metadata.json")))
                            guard envelope.scope == scope, envelope.media.id == path.lastPathComponent,
                                  UUID(uuidString: envelope.media.id) != nil else { throw StorageError.unreadable }
                            items.append(envelope.media)
                            // A metadata-only listing never loads every photograph to render rows.
                            let payload = path.appendingPathComponent("payload")
                            if !FileManager.default.fileExists(atPath: payload.path) { errors[envelope.media.id] = StorageError.unreadable.localizedDescription }
                        } catch { storageWarning = "Some saved media cannot be read. It remains on this phone and needs recovery." }
                    }
                }
                items.sort { $0.capturedAt == $1.capturedAt ? $0.id < $1.id : $0.capturedAt < $1.capturedAt }
            } catch { storageWarning = "Saved media could not be opened. Unlock the phone and retry." }
        }
        recount()
    }

    private func recount() {
        do {
            legacyCount = 0
            if FileManager.default.fileExists(atPath: legacyDirectory.path) {
                try protect(legacyDirectory)
                let legacy = try FileManager.default.contentsOfDirectory(at: legacyDirectory, includingPropertiesForKeys: nil)
                for file in legacy { try protect(file) }
                legacyCount = Set(legacy.map { $0.deletingPathExtension().lastPathComponent }).count
            }
            var count = legacyCount
            if FileManager.default.fileExists(atPath: directory.path) {
                for folder in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                    count += try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).count
                }
            }
            totalPendingCount = count
        } catch { storageWarning = "Saved media could not be counted. Signing out deletes all saved media on this phone." }
    }

    func signOutWarning(outboxWarning: String) -> String {
        guard totalPendingCount > 0 || storageWarning != nil else { return outboxWarning }
        let media = storageWarning != nil ? "Saved photos and documents may also remain on this phone." : "\(totalPendingCount) saved photo\(totalPendingCount == 1 ? " or document has" : "s or documents have") not uploaded yet."
        return outboxWarning + " " + media + " Signing out deletes all of them, including media in other workspaces and older saved photos."
    }

    func clearAll() {
        binding = UUID(); scope = nil; items = []; errors = [:]
        do {
            for folder in [directory, legacyDirectory] where FileManager.default.fileExists(atPath: folder.path) {
                try FileManager.default.removeItem(at: folder)
            }
            storageWarning = nil
        } catch { storageWarning = "Some saved media could not be removed from this phone." }
        recount()
    }

    /// One foreground drain for both manual retry and reconnect. Every item keeps its
    /// original client asset ID, bytes and capture date, including an uncertain retry.
    func drain(api: APIClient, jobID: String? = nil, canUpload: @MainActor () -> Bool, storageSession: URLSession? = nil) async {
        guard !draining, let owner = scope, owner.origin == api.normalizedOrigin, canUpload() else { return }
        let token = binding, generation = api.requestGeneration
        func current() -> Bool { binding == token && scope == owner && api.requestGeneration == generation && api.normalizedOrigin == owner.origin && canUpload() && !Task.isCancelled }
        draining = true
        defer { draining = false; uploadingID = nil }
        reload()
        let pending = items.filter { jobID == nil || $0.jobID == jobID }
        for item in pending {
            guard current() else { return }
            uploadingID = item.id
            do {
                let data = try read(item)
                _ = try await MediaTransfer(api: api, storageSession: storageSession).upload(jobID: item.jobID, clientAssetID: item.id,
                    kind: item.kind, mime: item.mime, originalFilename: item.filename, data: data, tags: item.tags,
                    capturedAt: item.capturedAt, expectedOrganizationID: owner.organizationID)
                guard current() else { return }
                try FileManager.default.removeItem(at: unit(item, scope: owner))
                errors[item.id] = nil
                reload()
            } catch {
                guard current() else { return }
                if !(error is CancellationError) { errors[item.id] = error.localizedDescription }
                if error is CancellationError || error.isConnectivityFailure { return }
            }
        }
    }
}

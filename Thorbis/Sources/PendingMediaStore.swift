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
    @Published private(set) var unverifiedIDs: Set<String> = []
    @Published private(set) var cleanupWarning: String?
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
        case unbound, invalid, unreadable, existing, recoveryUnavailable, recoveryConflict
        var errorDescription: String? {
            switch self {
            case .unbound: "Open the original workspace before saving or retrying this media."
            case .invalid: "This media could not be saved. Choose a supported nonempty file up to 8 MB."
            case .unreadable: "This phone cannot read the saved media. Keep it here and retry after unlocking the phone."
            case .existing: "This media is already saved. Retry its existing upload."
            case .recoveryUnavailable: "This destination is no longer verified. Reopen recovery from the current job and try again."
            case .recoveryConflict: "A different saved item uses this photo ID. Both copies remain on this phone and need review."
            }
        }
    }
    private let directory: URL
    private let legacyDirectory: URL
    private var scope: PendingMediaScope?
    private var binding = UUID()
    private var draining = false
    private var validated: Set<PendingMedia> = []

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
        if scope != normalized { binding = UUID(); errors = [:]; validated = [] }
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
            validated.insert(media)
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
            validated.insert(media); unverifiedIDs.remove(media.id)
            try? FileManager.default.removeItem(at: path.appendingPathComponent("integrity-failed"))
            if errors[media.id] == StorageError.unreadable.localizedDescription { errors[media.id] = nil }
            return data
        } catch {
            validated.remove(media); unverifiedIDs.insert(media.id)
            errors[media.id] = StorageError.unreadable.localizedDescription
            if let failure = try? unit(media, scope: scope).appendingPathComponent("integrity-failed") {
                try? Data([1]).write(to: failure, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                try? protect(failure)
            }
            throw StorageError.unreadable
        }
    }

    func reload() {
        storageWarning = nil
        items = []; unverifiedIDs = []
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
                            if !validated.contains(envelope.media) { unverifiedIDs.insert(envelope.media.id) }
                            if FileManager.default.fileExists(atPath: path.appendingPathComponent("integrity-failed").path) {
                                errors[envelope.media.id] = StorageError.unreadable.localizedDescription
                                validated.remove(envelope.media); unverifiedIDs.insert(envelope.media.id)
                            }
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
        binding = UUID(); scope = nil; items = []; errors = [:]; validated = []; unverifiedIDs = []
        var failed = false
        for folder in [directory, legacyDirectory] where FileManager.default.fileExists(atPath: folder.path) {
            do { try FileManager.default.removeItem(at: folder) }
            catch { failed = true }
        }
        cleanupWarning = failed ? "Some saved media could not be removed from this phone. Sign in and try signing out again to retry cleanup." : nil
        storageWarning = nil
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
                    capturedAt: item.capturedAt, expectedOrganizationID: owner.organizationID, currentAuthority: current)
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
    struct LegacyCandidate: Identifiable, Equatable {
        let media: PendingMedia
        var id: String { media.id }
    }
    struct LegacyDestination {
        let job: JobRecord
        let candidates: [LegacyCandidate]
        fileprivate let context: CaptureContext
        fileprivate let generation: UUID
    }
    private struct LegacyRecord: Codable {
        let id: String
        let jobID: String
        let filename: String
        let tags: [String]
        let takenAt: Date
        var media: PendingMedia { PendingMedia(id: id, jobID: jobID, filename: filename, tags: tags, capturedAt: takenAt, kind: "photo", mime: "image/jpeg") }
    }
    private struct RecoveryReceipt: Codable {
        let media: PendingMedia
        let hash: String
    }
    private func legacyURL(_ id: String, extension ext: String) throws -> URL {
        guard UUID(uuidString: id) != nil else { throw StorageError.invalid }
        return legacyDirectory.appendingPathComponent(id).appendingPathExtension(ext)
    }
    private func legacyRecord(_ id: String) throws -> LegacyRecord {
        let url = try legacyURL(id, extension: "json")
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard (1...64 * 1024).contains(size) else { throw StorageError.unreadable }
        let record = try JSONDecoder().decode(LegacyRecord.self, from: Data(contentsOf: url))
        guard record.id == id, UUID(uuidString: record.jobID) != nil, record.takenAt.timeIntervalSince1970.isFinite else { throw StorageError.unreadable }
        return record
    }
    private func checkRecovery(_ context: CaptureContext, generation: UUID, api: APIClient, canUpload: @MainActor () -> Bool) throws {
        try Task.checkCancellation()
        guard captureContext == context, api.requestGeneration == generation,
              api.normalizedOrigin == context.scope.origin, canUpload() else { throw StorageError.recoveryUnavailable }
    }
    private func verifyRecoveryJob(_ job: JobRecord, id: String, context: CaptureContext) throws {
        guard job.id == id, job.organizationId == context.scope.organizationID else { throw StorageError.recoveryUnavailable }
    }

    /// Discover metadata only after online proof of the current destination. The
    /// original account/origin remains unknown and is never reconstructed here.
    func prepareLegacyRecovery(api: APIClient, jobID: String, canUpload: @MainActor () -> Bool) async throws -> LegacyDestination {
        guard let context = captureContext else { throw StorageError.recoveryUnavailable }
        let generation = api.requestGeneration
        try checkRecovery(context, generation: generation, api: api, canUpload: canUpload)
        let job = try await api.fieldJob(jobID, requireFresh: true)
        try checkRecovery(context, generation: generation, api: api, canUpload: canUpload)
        try verifyRecoveryJob(job, id: jobID, context: context)
        var candidates: [String: LegacyCandidate] = [:]
        if FileManager.default.fileExists(atPath: legacyDirectory.path) {
            for file in try FileManager.default.contentsOfDirectory(at: legacyDirectory, includingPropertiesForKeys: nil) where file.pathExtension == "json" {
                guard let record = try? legacyRecord(file.deletingPathExtension().lastPathComponent), record.jobID == job.id else { continue }
                candidates[record.id] = LegacyCandidate(media: record.media)
            }
            // An interrupted cleanup may leave only JPEG bytes. A scoped receipt
            // can identify that already adopted copy without guessing an owner.
            for item in items where item.jobID == job.id {
                let receiptURL = try unit(item, scope: context.scope).appendingPathComponent("recovery.json")
                guard let receiptData = try? Data(contentsOf: receiptURL),
                      let receipt = try? JSONDecoder().decode(RecoveryReceipt.self, from: receiptData), receipt.media == item,
                      FileManager.default.fileExists(atPath: try legacyURL(item.id, extension: "jpg").path) else { continue }
                candidates[item.id] = LegacyCandidate(media: item)
            }
        }
        try checkRecovery(context, generation: generation, api: api, canUpload: canUpload)
        return LegacyDestination(job: job, candidates: candidates.values.sorted { $0.id < $1.id }, context: context, generation: generation)
    }

    /// The caller confirms one named destination and one item. First commit and
    /// verify its scoped bytes, then write a durable recovery receipt, then remove
    /// legacy sources. Every interruption retains a complete verified copy.
    func recoverLegacy(_ candidate: LegacyCandidate, destination: LegacyDestination, api: APIClient, canUpload: @MainActor () -> Bool) async throws {
        let context = destination.context, generation = destination.generation
        try checkRecovery(context, generation: generation, api: api, canUpload: canUpload)
        guard destination.candidates.contains(candidate), candidate.media.jobID == destination.job.id else { throw StorageError.invalid }
        let currentJob = try await api.fieldJob(destination.job.id, requireFresh: true)
        try checkRecovery(context, generation: generation, api: api, canUpload: canUpload)
        try verifyRecoveryJob(currentJob, id: destination.job.id, context: context)
        let metadata = try legacyURL(candidate.id, extension: "json")
        let payload = try legacyURL(candidate.id, extension: "jpg")
        let path = try unit(candidate.media, scope: context.scope)
        let receiptURL = path.appendingPathComponent("recovery.json")
        let receipt = (try? Data(contentsOf: receiptURL)).flatMap { try? JSONDecoder().decode(RecoveryReceipt.self, from: $0) }
        let hasMetadata = FileManager.default.fileExists(atPath: metadata.path)
        let hasPayload = FileManager.default.fileExists(atPath: payload.path)
        if hasMetadata { guard try legacyRecord(candidate.id).media == candidate.media else { throw StorageError.unreadable } }
        let legacyBytes: Data?
        if hasPayload {
            let size = try payload.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard (1...8 * 1024 * 1024).contains(size) else { throw StorageError.unreadable }
            legacyBytes = try Data(contentsOf: payload)
        } else { legacyBytes = nil }
        if !hasMetadata || !hasPayload {
            guard let receipt, receipt.media == candidate.media else { throw StorageError.unreadable }
        }
        try checkRecovery(context, generation: generation, api: api, canUpload: canUpload)
        if !FileManager.default.fileExists(atPath: path.path) {
            guard let legacyBytes, hasMetadata else { throw StorageError.unreadable }
            try save(candidate.media, data: legacyBytes, context: context)
        }
        reload()
        let committed = try read(candidate.media)
        if let legacyBytes { guard committed == legacyBytes else { throw StorageError.recoveryConflict } }
        if let receipt { guard receipt.media == candidate.media, receipt.hash == Self.hash(committed) else { throw StorageError.recoveryConflict } }
        try checkRecovery(context, generation: generation, api: api, canUpload: canUpload)
        let proof = RecoveryReceipt(media: candidate.media, hash: Self.hash(committed))
        try JSONEncoder().encode(proof).write(to: receiptURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try protect(receiptURL)
        // Verify durable intent and bytes before touching either older source.
        let storedProof = try JSONDecoder().decode(RecoveryReceipt.self, from: Data(contentsOf: receiptURL))
        guard storedProof.media == candidate.media, storedProof.hash == Self.hash(try read(candidate.media)) else { throw StorageError.unreadable }
        for file in [payload, metadata] where FileManager.default.fileExists(atPath: file.path) {
            try checkRecovery(context, generation: generation, api: api, canUpload: canUpload)
            try FileManager.default.removeItem(at: file)
        }
        reload()
    }
}

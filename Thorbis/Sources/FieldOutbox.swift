import Foundation
import Darwin
import CryptoKit

enum SavedWorkInventory {
    enum Failure: Error { case inaccessible, changed, unsupported }
    private struct Observation {
        let root: URL
        let components: [String]
        let metadata: stat?
    }

    /// A digest only; paths and file contents never leave this helper. This does not
    /// lock the filesystem after return and must not by itself authorize deletion.
    static func snapshot(roots: [URL], onItemScanned: (@Sendable () -> Void)? = nil) async throws -> Data {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .utility) { try scan(roots: roots, onItemScanned: onItemScanned) }
        let digest = try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: { worker.cancel() }
        try Task.checkCancellation()
        return digest
    }

    private static func scan(roots: [URL], onItemScanned: (@Sendable () -> Void)?) throws -> Data {
        var digest = SHA256()
        var observations: [Observation] = []
        for (index, root) in roots.enumerated() {
            try Task.checkCancellation()
            digest.update(data: Data("root:\(index)\0".utf8))
            try scanRoot(root, digest: &digest, onItemScanned: onItemScanned, observations: &observations)
        }
        for observation in observations { try verify(observation) }
        return Data(digest.finalize())
    }

    private static func same(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino && lhs.st_mode == rhs.st_mode &&
        lhs.st_size == rhs.st_size && lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec &&
        lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec && lhs.st_ctimespec.tv_sec == rhs.st_ctimespec.tv_sec &&
        lhs.st_ctimespec.tv_nsec == rhs.st_ctimespec.tv_nsec
    }

    private static func scanRoot(_ url: URL, digest: inout SHA256, onItemScanned: (@Sendable () -> Void)?, observations: inout [Observation]) throws {
        try Task.checkCancellation()
        guard let (descriptor, chain) = try openRoot(url) else {
            if let (unexpectedFD, _) = try openRoot(url) { close(unexpectedFD); throw Failure.changed }
            digest.update(data: Data("missing\0".utf8))
            observations.append(.init(root: url, components: [], metadata: nil))
            return
        }
        defer { close(descriptor) }
        guard let before = chain.last else { throw Failure.unsupported }
        observations.append(.init(root: url, components: [], metadata: before))
        try scanDirectory(descriptor, name: url.lastPathComponent, before: before, digest: &digest,
                          onItemScanned: onItemScanned, root: url, path: [], observations: &observations)
        guard let (checkedFD, checkedChain) = try openRoot(url) else { throw Failure.changed }
        defer { close(checkedFD) }
        guard chain.count == checkedChain.count,
              zip(chain, checkedChain).allSatisfy({ $0.0.st_dev == $0.1.st_dev && $0.0.st_ino == $0.1.st_ino && $0.0.st_mode == $0.1.st_mode }),
              let last = checkedChain.last, same(before, last) else { throw Failure.changed }
    }

    private static func verify(_ observation: Observation) throws {
        try Task.checkCancellation()
        guard let (rootFD, chain) = try openRoot(observation.root) else {
            if case nil = observation.metadata { return }
            throw Failure.changed
        }
        guard let expected = observation.metadata else { close(rootFD); throw Failure.changed }
        var current = rootFD
        defer { close(current) }
        if observation.components.isEmpty {
            guard let root = chain.last, same(expected, root) else { throw Failure.changed }
            return
        }
        for (index, component) in observation.components.enumerated() {
            var info = stat()
            guard fstatat(current, component, &info, AT_SYMLINK_NOFOLLOW) == 0 else { throw Failure.changed }
            if index == observation.components.count - 1 {
                guard same(expected, info) else { throw Failure.changed }
            } else {
                guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else { throw Failure.changed }
                let next = openat(current, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
                guard next >= 0 else { throw Failure.changed }
                var opened = stat()
                guard fstat(next, &opened) == 0, same(info, opened) else { close(next); throw Failure.changed }
                close(current); current = next
            }
        }
    }

    /// Reject symlinks at every ancestor, not only at the root's last component.
    private static func openRoot(_ url: URL) throws -> (Int32, [stat])? {
        guard url.isFileURL, url.path.hasPrefix("/") else { throw Failure.unsupported }
        let components = url.standardizedFileURL.pathComponents.filter { $0 != "/" }
        guard !components.isEmpty else { throw Failure.unsupported }
        var current = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard current >= 0 else { throw Failure.inaccessible }
        var chain: [stat] = []
        do {
            for component in components {
                var before = stat()
                guard fstatat(current, component, &before, AT_SYMLINK_NOFOLLOW) == 0 else {
                    if errno == ENOENT { close(current); return nil }
                    throw Failure.inaccessible
                }
                guard before.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else { throw Failure.unsupported }
                let next = openat(current, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
                guard next >= 0 else { throw Failure.inaccessible }
                var opened = stat()
                guard fstat(next, &opened) == 0, same(before, opened) else { close(next); throw Failure.changed }
                chain.append(opened)
                close(current)
                current = next
            }
            return (current, chain)
        } catch {
            close(current)
            throw error
        }
    }

    private static func scanDirectory(_ descriptor: Int32, name: String, before: stat, digest: inout SHA256,
                                      onItemScanned: (@Sendable () -> Void)?, root: URL, path: [String],
                                      observations: inout [Observation]) throws {
        digest.update(data: Data("directory:\(name)\0\(before.st_dev):\(before.st_ino):\(before.st_mode):\(before.st_size):\(before.st_mtimespec.tv_sec):\(before.st_mtimespec.tv_nsec):\(before.st_ctimespec.tv_sec):\(before.st_ctimespec.tv_nsec)\0".utf8))
        let duplicate = dup(descriptor)
        guard duplicate >= 0 else { throw Failure.inaccessible }
        guard let stream = fdopendir(duplicate) else { close(duplicate); throw Failure.inaccessible }
        defer { closedir(stream) }
        var names: [String] = []
        errno = 0
        while let entry = readdir(stream) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(validatingUTF8: $0) }
            }
            guard let name else { throw Failure.unsupported }
            if name != "." && name != ".." { names.append(name) }
            errno = 0
        }
        guard errno == 0 else { throw Failure.inaccessible }
        for child in names.sorted() {
          do {
            try Task.checkCancellation()
            var initial = stat()
            guard fstatat(descriptor, child, &initial, AT_SYMLINK_NOFOLLOW) == 0 else { throw Failure.changed }
            let childPath = path + [child]
            observations.append(.init(root: root, components: childPath, metadata: initial))
            let kind = initial.st_mode & mode_t(S_IFMT)
            guard kind == mode_t(S_IFDIR) || kind == mode_t(S_IFREG) else { throw Failure.unsupported }
            let flags = O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC | (kind == mode_t(S_IFDIR) ? O_DIRECTORY : 0)
            let openedFD = openat(descriptor, child, flags)
            guard openedFD >= 0 else { throw Failure.inaccessible }
            defer { close(openedFD) }
            var opened = stat()
            guard fstat(openedFD, &opened) == 0, same(initial, opened) else { throw Failure.changed }
            if kind == mode_t(S_IFDIR) {
                try scanDirectory(openedFD, name: child, before: initial, digest: &digest, onItemScanned: onItemScanned,
                                  root: root, path: childPath, observations: &observations)
            } else {
                digest.update(data: Data("file:\(child)\0\(initial.st_dev):\(initial.st_ino):\(initial.st_mode):\(initial.st_size):\(initial.st_mtimespec.tv_sec):\(initial.st_mtimespec.tv_nsec):\(initial.st_ctimespec.tv_sec):\(initial.st_ctimespec.tv_nsec)\0".utf8))
                var content = SHA256()
                var buffer = [UInt8](repeating: 0, count: 64 * 1024)
                while true {
                    try Task.checkCancellation()
                    let count = read(openedFD, &buffer, buffer.count)
                    guard count >= 0 else { throw Failure.inaccessible }
                    if count == 0 { break }
                    content.update(data: Data(buffer.prefix(count)))
                }
                digest.update(data: Data(content.finalize()))
            }
            var afterOpen = stat(), afterPath = stat()
            guard fstat(openedFD, &afterOpen) == 0, same(initial, afterOpen),
                  fstatat(descriptor, child, &afterPath, AT_SYMLINK_NOFOLLOW) == 0, same(initial, afterPath) else { throw Failure.changed }
            onItemScanned?()
          }
        }
        var after = stat()
        guard fstat(descriptor, &after) == 0, same(before, after) else { throw Failure.changed }
        digest.update(data: Data("end\0".utf8))
    }
}

/// A job change made without signal. It is saved to disk before it is ever sent, so a
/// killed app or a dropped connection resends the same `commandId`, which the server
/// answers as `duplicate` instead of applying it twice.
struct OutboxEntry: Codable, Identifiable, Equatable {
    enum Action: Codable, Equatable {
        case progress(ProgressPayload)
        case note(NotePayload)
    }

    /// `jobs.progress` input (domains/jobs progressJobInputSchema, a strict object).
    struct ProgressPayload: Codable, Equatable {
        struct Arrival: Codable, Equatable { let method: String }
        let jobId: String
        let to: String
        var arrival: Arrival? = nil
        var etaMinutes: Int? = nil
    }

    /// `jobs.addNote` input (addJobNoteInputSchema).
    struct NotePayload: Codable, Equatable {
        let jobId: String
        let body: String
    }

    enum State: Codable, Equatable {
        case pending
        /// The server refused it; the reason is shown and nothing is resent.
        case rejected(String)
        /// An earlier change to the same job was refused, so this one waits for review.
        case held
    }

    let id: String
    let deviceId: String
    let actorId: String
    let organizationId: String
    let policyVersion: Int
    let createdAt: Date
    let action: Action
    var state: State = .pending
    /// Set when the command endpoint answered policy_superseded: the change is resent
    /// through the REST route, which authorizes against current policy itself.
    var restOnly: Bool? = nil

    var jobID: String {
        switch action {
        case .progress(let payload): payload.jobId
        case .note(let payload): payload.jobId
        }
    }

    var command: String {
        switch action {
        case .progress: "jobs.progress"
        case .note: "jobs.addNote"
        }
    }

    var summary: String {
        switch action {
        case .progress(let payload):
            switch payload.to {
            case "en_route": "On my way"
            case "arrived": "Arrived"
            case "in_progress": "Started work"
            default: "Status → \(payload.to.statusLabel)"
            }
        case .note: "Note"
        }
    }
}

extension OutboxEntry.ProgressPayload {
    /// Only forward field steps are queued offline; pause and resume need the server's audit state.
    init?(jobID: String, request: FieldProgressRequest) {
        switch request {
        case .enRoute(let eta): self.init(jobId: jobID, to: "en_route", etaMinutes: eta)
        case .arrived(let method): self.init(jobId: jobID, to: "arrived", arrival: .init(method: method.rawValue))
        case .start: self.init(jobId: jobID, to: "in_progress")
        default: return nil
        }
    }
}

/// The server's per-command answer (packages/sync CommandOutcome).
struct OutboxOutcome: Decodable {
    let commandId: String
    let status: String
    let category: String?
    let detail: String?
}

@MainActor
final class FieldOutbox: ObservableObject {
    @Published private(set) var entries: [OutboxEntry] = []
    @Published private(set) var syncing = false
    /// How many changes the last sync sent, for the "back online" banner.
    @Published private(set) var lastSyncSent = 0

    var pending: [OutboxEntry] { entries.filter { $0.state == .pending } }
    var needsReview: [OutboxEntry] { entries.filter { $0.state != .pending } }

    /// design.thorbis.com MA-17: signing out deletes this phone's saved work, so the dialog says
    /// what would be lost.
    var signOutWarning: String {
        let inventory = savedWorkInventory
        if inventory.unreadable {
            return "Some saved work could not be read. Signing out deletes it from this phone, including any unsynced changes."
        }
        let waiting = entries.count + inventory.otherCount
        return waiting == 0
            ? "Jobs and customers saved on this phone are removed. You can sign back in at any time."
            : "\(waiting) change\(waiting == 1 ? "" : "s") on this phone \(waiting == 1 ? "hasn't" : "haven't") synced yet. Signing out deletes \(waiting == 1 ? "it" : "them")."
    }

    private let directory: URL
    private var identity: (actorID: String, organizationID: String)?
    /// Do not replace an existing queue that could not be read or decoded.
    private var queueReadable = false
    private var binding = UUID()
    private var activeDrain: UUID?
    /// Opaque read-only proof of the current verified queue binding.
    struct CaptureContext: Equatable {
        fileprivate let actorID: String
        fileprivate let organizationID: String
        fileprivate let binding: UUID
    }
    func captureContext(matchingActorID actorID: String, organizationID: String) -> CaptureContext? {
        guard identity?.actorID == actorID, identity?.organizationID == organizationID else { return nil }
        return .init(actorID: actorID, organizationID: organizationID, binding: binding)
    }
    private let deviceID: String
    private let defaults: UserDefaults
    /// Server-served legal moves seen per status, so an offline chain (On my way, then
    /// Arrived) only offers steps the server has actually allowed from that status.
    private(set) var learnedTransitions: [String: [String]] = [:]

    init(directory: URL? = nil, defaults: UserDefaults = .standard) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.directory = base.appendingPathComponent("Outbox", isDirectory: true)
        self.defaults = defaults
        learnedTransitions = (defaults.dictionary(forKey: "thorbis.learned-transitions") as? [String: [String]]) ?? [:]
        if let saved = defaults.string(forKey: "thorbis.device-id"), UUID(uuidString: saved) != nil {
            deviceID = saved
        } else {
            deviceID = UUID().uuidString.lowercased()
            defaults.set(deviceID, forKey: "thorbis.device-id")
        }
    }

    private var file: URL? {
        guard let identity else { return nil }
        let safe = "\(identity.actorID)_\(identity.organizationID)".filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return directory.appendingPathComponent("\(safe).json")
    }

    /// Changes queued in other workspaces on this phone; `clearAll()` deletes those too, so the
    /// sign-out warning has to count them.
    private var savedWorkInventory: (otherCount: Int, unreadable: Bool) {
        let current = file?.lastPathComponent
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return (0, false)
        } catch { return (0, true) }
        var count = 0
        var unreadable = identity != nil && !queueReadable
        for item in files {
            guard item.pathExtension == "json" else { unreadable = true; continue }
            do {
                let saved = try JSONDecoder().decode([OutboxEntry].self, from: Data(contentsOf: item))
                if item.lastPathComponent != current { count += saved.count }
            } catch { unreadable = true }
        }
        return (count, unreadable)
    }

    /// Bound to the verified actor and workspace; another identity never sees these changes.
    func bind(actorID: String?, organizationID: String?) {
        guard let actorID, let organizationID else {
            binding = UUID(); activeDrain = nil; syncing = false; lastSyncSent = 0
            identity = nil
            entries = []
            queueReadable = false
            return
        }
        guard identity?.actorID != actorID || identity?.organizationID != organizationID || !queueReadable else { return }
        binding = UUID(); activeDrain = nil; syncing = false; lastSyncSent = 0
        identity = (actorID, organizationID)
        entries = []
        queueReadable = false
        restoreQueueIfReadable()
    }

    /// Sign-out: unsent changes for this phone are deleted with the session.
    func clearAll() {
        binding = UUID(); activeDrain = nil; syncing = false; lastSyncSent = 0
        identity = nil
        entries = []
        queueReadable = false
        try? FileManager.default.removeItem(at: directory)
    }

    private func write(_ entries: [OutboxEntry]) throws {
        guard let file, queueReadable else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(entries).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func persist() { try? write(entries) }

    /// Only a proven absent file is an empty queue. Every other read or ownership
    /// failure preserves the file and blocks writes until a later successful retry.
    private func restoreQueueIfReadable() {
        guard let identity, let file else { return }
        if let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([OutboxEntry].self, from: data),
           saved.allSatisfy({ $0.actorId == identity.actorID && $0.organizationId == identity.organizationID }) {
            entries = saved
            queueReadable = true
            return
        }
        var info = stat()
        let result = lstat(file.path, &info)
        let failure = errno
        if result == -1 && failure == ENOENT {
            entries = []
            queueReadable = true
        }
    }

    @discardableResult
    func enqueue(_ action: OutboxEntry.Action, policyVersion: Int) -> OutboxEntry? {
        guard let identity else { return nil }
        if !queueReadable { restoreQueueIfReadable() }
        let entry = OutboxEntry(id: UUID().uuidString.lowercased(), deviceId: deviceID, actorId: identity.actorID,
                                organizationId: identity.organizationID, policyVersion: policyVersion,
                                createdAt: Date(), action: action)
        let updated = entries + [entry]
        do { try write(updated) } catch { return nil }
        entries = updated
        return entry
    }

    @discardableResult
    func enqueue(_ action: OutboxEntry.Action, policyVersion: Int, matching context: CaptureContext) -> OutboxEntry? {
        guard captureContext(matchingActorID: context.actorID, organizationID: context.organizationID) == context else { return nil }
        return enqueue(action, policyVersion: policyVersion)
    }

    func learn(_ job: JobRecord) {
        guard let allowed = job.allowedTransitions, learnedTransitions[job.status] != allowed else { return }
        learnedTransitions[job.status] = allowed
        defaults.set(learnedTransitions, forKey: "thorbis.learned-transitions")
    }

    /// Steps this phone may queue for a job whose last known status is `status`.
    func offlineSteps(from status: String) -> [String] { learnedTransitions[status] ?? [] }

    /// Drops a refused change; the job's held changes go back in the queue.
    func dismiss(_ entry: OutboxEntry) {
        entries.removeAll { $0.id == entry.id }
        release(jobID: entry.jobID)
        persist()
    }

    /// Sends a refused change again, with the job's held changes after it.
    func retry(_ entry: OutboxEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].state = .pending
        release(jobID: entry.jobID)
        persist()
    }

    private func release(jobID: String) {
        guard !entries.contains(where: { $0.jobID == jobID && { if case .rejected = $0.state { true } else { false } }($0) }) else { return }
        for index in entries.indices where entries[index].jobID == jobID && entries[index].state == .held {
            entries[index].state = .pending
        }
    }

    private static let lifecycleRank = ["scheduled": 0, "dispatched": 1, "en_route": 2, "arrived": 3, "in_progress": 4, "completed": 5]

    /// A step that timed out on the phone may still have reached the server. If the job is
    /// already at or past that step, the change is done, not refused.
    private func alreadyApplied(_ entry: OutboxEntry, api: APIClient, current: @MainActor () -> Bool) async -> Bool {
        guard current(), case .progress(let payload) = entry.action, let target = Self.lifecycleRank[payload.to] else { return false }
        guard let job = try? await api.fieldJob(payload.jobId), current(), let rank = Self.lifecycleRank[job.status] else { return false }
        return rank >= target
    }

    /// The status this phone expects a job to have once its queued changes land.
    func pendingStatus(for jobID: String) -> String? {
        pending.last { $0.jobID == jobID && { if case .progress = $0.action { true } else { false } }($0) }
            .flatMap { if case .progress(let payload) = $0.action { payload.to } else { nil } }
    }

    func pendingNotes(for jobID: String) -> [OutboxEntry] {
        entries.filter { $0.jobID == jobID && { if case .note = $0.action { true } else { false } }($0) }
    }

    /// Local notes belong to the verified queue owner even when server history is unavailable.
    func activityNotes(for jobID: String, actorID: String, organizationID: String) -> [OutboxEntry] {
        guard captureContext(matchingActorID: actorID, organizationID: organizationID) != nil else { return [] }
        return pendingNotes(for: jobID).filter { $0.actorId == actorID && $0.organizationId == organizationID }
    }

    /// Sends queued changes oldest first. Uses the offline command endpoint when the
    /// workspace has it, otherwise the same REST routes the app uses online.
    func drain(api: APIClient, useCommandEndpoint: Bool, canSend: @MainActor () -> Bool = { true }) async {
        guard !syncing, !pending.isEmpty, let owner = identity, let origin = api.normalizedOrigin, canSend(), !Task.isCancelled else { return }
        let token = binding, generation = api.requestGeneration, operation = UUID()
        func current() -> Bool {
            binding == token && identity?.actorID == owner.actorID && identity?.organizationID == owner.organizationID &&
            api.requestGeneration == generation && api.normalizedOrigin == origin && canSend() && !Task.isCancelled
        }
        activeDrain = operation; syncing = true
        defer { if activeDrain == operation { activeDrain = nil; syncing = false } }
        var sent = 0
        if useCommandEndpoint {
            sent = await drainCommands(api: api, current: current)
            guard current() else { return }
            // Only permission-snapshot refusals use the existing REST fallback.
            if pending.contains(where: { $0.restOnly == true }) {
                sent += await drainREST(api: api, onlyRestFallback: true, current: current)
            }
        } else {
            sent = await drainREST(api: api, current: current)
        }
        guard current() else { return }
        lastSyncSent = sent
    }

    private func drainCommands(api: APIClient, current: @MainActor () -> Bool) async -> Int {
        struct Envelope: Encodable {
            let commandId, deviceId, actorId, organizationId: String
            let policyVersion: Int
            let command: String
            let clientCreatedAt: String
            let payload: AnyPayload
        }
        struct AnyPayload: Encodable {
            let action: OutboxEntry.Action
            func encode(to encoder: Encoder) throws {
                switch action {
                case .progress(let payload): try payload.encode(to: encoder)
                case .note(let payload): try payload.encode(to: encoder)
                }
            }
        }
        struct Batch: Encodable { let commands: [Envelope] }
        struct Result: Decodable { let outcomes: [OutboxOutcome] }
        var sent = 0
        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        while current() {
            let batch = Array(pending.filter { $0.restOnly != true }.prefix(50))
            guard !batch.isEmpty else { break }
            let envelopes = batch.map {
                Envelope(commandId: $0.id, deviceId: $0.deviceId, actorId: $0.actorId, organizationId: $0.organizationId,
                         policyVersion: $0.policyVersion, command: $0.command, clientCreatedAt: stamp.string(from: $0.createdAt),
                         payload: AnyPayload(action: $0.action))
            }
            do {
                guard current() else { return sent }
                let result: Result = try await api.send("POST", "/v1/commands", body: Batch(commands: envelopes))
                guard current() else { return sent }
                for outcome in result.outcomes {
                    guard current() else { return sent }
                    if outcome.status == "applied" || outcome.status == "duplicate" {
                        entries.removeAll { $0.id == outcome.commandId }
                        sent += 1
                    } else if outcome.category == "policy_superseded",
                              let index = entries.firstIndex(where: { $0.id == outcome.commandId }) {
                        entries[index].restOnly = true
                    } else if let entry = entries.first(where: { $0.id == outcome.commandId }), outcome.category == "conflict" {
                        let applied = await alreadyApplied(entry, api: api, current: current)
                        guard current() else { return sent }
                        if applied {
                            entries.removeAll { $0.id == outcome.commandId }
                            sent += 1
                        } else {
                            reject(outcome.commandId, reason: outcome.detail ?? outcome.category ?? "The server refused this change.")
                        }
                    } else {
                        reject(outcome.commandId, reason: outcome.detail ?? outcome.category ?? "The server refused this change.")
                    }
                }
                guard current() else { return sent }
                persist()
                // A batch the server did not fully answer stops the loop rather than spinning.
                if result.outcomes.count < batch.count { break }
            } catch {
                break // No signal or a server error: everything stays queued.
            }
        }
        return sent
    }

    private func drainREST(api: APIClient, onlyRestFallback: Bool = false, current: @MainActor () -> Bool) async -> Int {
        var sent = 0
        for entry in pending where !onlyRestFallback || entry.restOnly == true {
            guard current() else { return sent }
            guard entries.first(where: { $0.id == entry.id })?.state == .pending else { continue }
            do {
                switch entry.action {
                case .progress(let payload):
                    let request: FieldProgressRequest = switch payload.to {
                    case "en_route": .enRoute(etaMinutes: payload.etaMinutes)
                    case "arrived": .arrived(method: .manual)
                    case "in_progress": .start
                    case "dispatched": .dispatched
                    default: .scheduled
                    }
                    _ = try await api.progressFieldJob(payload.jobId, request: request)
                case .note(let payload):
                    _ = try await api.addFieldNote(payload.jobId, body: payload.body)
                }
                guard current() else { return sent }
                entries.removeAll { $0.id == entry.id }
                sent += 1
                persist()
            } catch is CancellationError {
                break
            } catch {
                guard current() else { return sent }
                if error.isConnectivityFailure { break }
                if let problem = error as? Problem, let status = problem.status, (400..<500).contains(status), status != 401, status != 429 {
                    let applied = status == 409 ? await alreadyApplied(entry, api: api, current: current) : false
                    guard current() else { return sent }
                    if applied {
                        entries.removeAll { $0.id == entry.id }
                        sent += 1
                    } else {
                        reject(entry.id, reason: problem.errorDescription ?? "The server refused this change.")
                    }
                    persist()
                    continue
                }
                break // 5xx, 401 or rate limit: try again later.
            }
        }
        return sent
    }

    #if DEBUG
    func markRejectedForTesting(_ id: String, reason: String) { reject(id, reason: reason) }
    #endif

    /// A refused change holds every later change to the same job for review.
    private func reject(_ id: String, reason: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].state = .rejected(reason)
        let jobID = entries[index].jobID
        for later in entries.indices where later > index && entries[later].jobID == jobID && entries[later].state == .pending {
            entries[later].state = .held
        }
    }
}

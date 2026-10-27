import Foundation

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

    private let directory: URL
    private var identity: (actorID: String, organizationID: String)?
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

    /// Bound to the verified actor and workspace; another identity never sees these changes.
    func bind(actorID: String?, organizationID: String?) {
        guard let actorID, let organizationID else {
            identity = nil
            entries = []
            return
        }
        guard identity?.actorID != actorID || identity?.organizationID != organizationID else { return }
        identity = (actorID, organizationID)
        entries = file.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode([OutboxEntry].self, from: $0) } ?? []
    }

    /// Sign-out: unsent changes for this phone are deleted with the session.
    func clearAll() {
        identity = nil
        entries = []
        try? FileManager.default.removeItem(at: directory)
    }

    private func persist() {
        guard let file else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(entries).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {}
    }

    @discardableResult
    func enqueue(_ action: OutboxEntry.Action, policyVersion: Int) -> OutboxEntry? {
        guard let identity else { return nil }
        let entry = OutboxEntry(id: UUID().uuidString.lowercased(), deviceId: deviceID, actorId: identity.actorID,
                                organizationId: identity.organizationID, policyVersion: policyVersion,
                                createdAt: Date(), action: action)
        entries.append(entry)
        persist()
        return entry
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
    private func alreadyApplied(_ entry: OutboxEntry, api: APIClient) async -> Bool {
        guard case .progress(let payload) = entry.action, let target = Self.lifecycleRank[payload.to],
              let job = try? await api.fieldJob(payload.jobId), let current = Self.lifecycleRank[job.status] else { return false }
        return current >= target
    }

    /// The status this phone expects a job to have once its queued changes land.
    func pendingStatus(for jobID: String) -> String? {
        pending.last { $0.jobID == jobID && { if case .progress = $0.action { true } else { false } }($0) }
            .flatMap { if case .progress(let payload) = $0.action { payload.to } else { nil } }
    }

    func pendingNotes(for jobID: String) -> [OutboxEntry] {
        entries.filter { $0.jobID == jobID && { if case .note = $0.action { true } else { false } }($0) }
    }

    /// Sends queued changes oldest first. Uses the offline command endpoint when the
    /// workspace has it, otherwise the same REST routes the app uses online.
    func drain(api: APIClient, useCommandEndpoint: Bool) async {
        guard !syncing, !pending.isEmpty else { return }
        syncing = true
        defer { syncing = false }
        var sent = 0
        if useCommandEndpoint {
            sent = await drainCommands(api: api)
        } else {
            sent = await drainREST(api: api)
        }
        lastSyncSent = sent
    }

    private func drainCommands(api: APIClient) async -> Int {
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
        while true {
            let batch = Array(pending.prefix(50))
            guard !batch.isEmpty else { break }
            let envelopes = batch.map {
                Envelope(commandId: $0.id, deviceId: $0.deviceId, actorId: $0.actorId, organizationId: $0.organizationId,
                         policyVersion: $0.policyVersion, command: $0.command, clientCreatedAt: stamp.string(from: $0.createdAt),
                         payload: AnyPayload(action: $0.action))
            }
            do {
                let result: Result = try await api.send("POST", "/v1/commands", body: Batch(commands: envelopes))
                for outcome in result.outcomes {
                    if outcome.status == "applied" || outcome.status == "duplicate" {
                        entries.removeAll { $0.id == outcome.commandId }
                        sent += 1
                    } else if let entry = entries.first(where: { $0.id == outcome.commandId }), outcome.category == "conflict",
                              await alreadyApplied(entry, api: api) {
                        entries.removeAll { $0.id == outcome.commandId }
                        sent += 1
                    } else {
                        reject(outcome.commandId, reason: outcome.detail ?? outcome.category ?? "The server refused this change.")
                    }
                }
                persist()
                // A batch the server did not fully answer stops the loop rather than spinning.
                if result.outcomes.count < batch.count { break }
            } catch {
                break // No signal or a server error: everything stays queued.
            }
        }
        return sent
    }

    private func drainREST(api: APIClient) async -> Int {
        var sent = 0
        for entry in pending {
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
                entries.removeAll { $0.id == entry.id }
                sent += 1
                persist()
            } catch is CancellationError {
                break
            } catch {
                if error.isConnectivityFailure { break }
                if let problem = error as? Problem, let status = problem.status, (400..<500).contains(status), status != 401, status != 429 {
                    if status == 409, await alreadyApplied(entry, api: api) {
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

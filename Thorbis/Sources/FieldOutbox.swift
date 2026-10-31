import Foundation

/// A job change made without signal. It is saved to disk before it is ever sent, so a
/// killed app or a dropped connection resends the same `commandId`, which the server
/// answers as `duplicate` instead of applying it twice.
struct OutboxEntry: Codable, Identifiable, Equatable {
    enum Action: Codable, Equatable {
        case progress(ProgressPayload)
        case note(NotePayload)
        /// A follow-up for the office (`POST /v1/jobs/{id}/followups`). That route takes no
        /// idempotency key and the command endpoint has no such command, so it is sent through
        /// REST only, and any resend first checks the job's follow-ups for one already made.
        case followUp(FollowUpPayload)
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

    /// `POST /v1/jobs/{id}/followups` input (FieldFollowUpRequest), kind as its wire value.
    struct FollowUpPayload: Codable, Equatable {
        let jobId: String
        let kind: String
        let reason: String
        let nextAction: String
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
    /// Set before a send that may have reached the server without an answer; the next send of
    /// a follow-up then checks the server first, since that route cannot dedupe on its own.
    var attempted: Bool? = nil

    var jobID: String {
        switch action {
        case .progress(let payload): payload.jobId
        case .note(let payload): payload.jobId
        case .followUp(let payload): payload.jobId
        }
    }

    var command: String {
        switch action {
        case .progress: "jobs.progress"
        case .note: "jobs.addNote"
        // Never sent to /v1/commands (restOnly); named for the review list only.
        case .followUp: "jobs.requestFollowUp"
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
        case .followUp(let payload): payload.kind == FieldFollowUpRequest.Kind.officeScheduling.rawValue
            ? "Follow-up for scheduling" : "Notify office"
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
        let waiting = entries.count + otherWorkspaceEntryCount
        return waiting == 0
            ? "Jobs and customers saved on this phone are removed. You can sign back in at any time."
            : "\(waiting) change\(waiting == 1 ? "" : "s") on this phone \(waiting == 1 ? "hasn't" : "haven't") synced yet. Signing out deletes \(waiting == 1 ? "it" : "them")."
    }

    private let directory: URL
    private var identity: (actorID: String, organizationID: String)?
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
    private var otherWorkspaceEntryCount: Int {
        let current = file?.lastPathComponent
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" && $0.lastPathComponent != current }
            .compactMap { try? Data(contentsOf: $0) }
            .compactMap { try? JSONDecoder().decode([OutboxEntry].self, from: $0) }
            .reduce(0) { $0 + $1.count }
    }

    /// Bound to the verified actor and workspace; another identity never sees these changes.
    func bind(actorID: String?, organizationID: String?) {
        guard let actorID, let organizationID else {
            binding = UUID(); activeDrain = nil; syncing = false; lastSyncSent = 0
            identity = nil
            entries = []
            return
        }
        guard identity?.actorID != actorID || identity?.organizationID != organizationID else { return }
        binding = UUID(); activeDrain = nil; syncing = false; lastSyncSent = 0
        identity = (actorID, organizationID)
        entries = file.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode([OutboxEntry].self, from: $0) } ?? []
    }

    /// Sign-out: unsent changes for this phone are deleted with the session.
    func clearAll() {
        binding = UUID(); activeDrain = nil; syncing = false; lastSyncSent = 0
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
    func enqueue(_ action: OutboxEntry.Action, policyVersion: Int, attempted: Bool = false) -> OutboxEntry? {
        guard let identity else { return nil }
        var entry = OutboxEntry(id: UUID().uuidString.lowercased(), deviceId: deviceID, actorId: identity.actorID,
                                organizationId: identity.organizationID, policyVersion: policyVersion,
                                createdAt: Date(), action: action)
        if case .followUp = action {
            entry.restOnly = true
            entry.attempted = attempted ? true : nil
        }
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
                case .followUp(let payload): try payload.encode(to: encoder)
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
                case .followUp(let payload):
                    if entry.attempted == true {
                        let earlier = await followUpExists(payload, since: entry.createdAt, actorID: entry.actorId, api: api)
                        guard current() else { return sent }
                        // Unknown (no live answer): keep it queued rather than risk sending it twice.
                        guard let earlier else { return sent }
                        if earlier { break } // An earlier send reached the server; it is done.
                    }
                    guard current() else { return sent }
                    if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                        entries[index].attempted = true
                        persist()
                    }
                    guard let kind = FieldFollowUpRequest.Kind(rawValue: payload.kind) else {
                        reject(entry.id, reason: "This follow-up type is not supported.")
                        persist()
                        continue
                    }
                    _ = try await api.requestFieldFollowUp(payload.jobId, request: .init(kind: kind, reason: payload.reason,
                                                                                       nextAction: payload.nextAction))
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

    /// Whether the job already has this follow-up from this person, made around or after it was
    /// queued (ten minutes of slack for the phone's clock). Nil when there is no live answer:
    /// a failed read, or one answered by the copy saved on this phone.
    private func followUpExists(_ payload: OutboxEntry.FollowUpPayload, since queued: Date, actorID: String, api: APIClient) async -> Bool? {
        guard let records = try? await SavedCopies.$liveOnly.withValue(true, operation: { try await api.fieldFollowUps(payload.jobId) }),
              api.savedCopyDate("/v1/jobs/\(payload.jobId)/followups") == nil
        else { return nil }
        let earliest = queued.addingTimeInterval(-600)
        return records.contains { record in
            record.kind == payload.kind && record.reason == payload.reason && record.nextAction == payload.nextAction &&
                record.createdByUserId == actorID && (JobFiltering.date(record.createdAt).map { $0 >= earliest } ?? true)
        }
    }

    func pendingFollowUps(for jobID: String) -> [OutboxEntry] {
        entries.filter { $0.jobID == jobID && { if case .followUp = $0.action { true } else { false } }($0) }
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

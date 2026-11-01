import Foundation

/// A field change made without signal (design.thorbis.com/offline, OF-01). It is saved to disk
/// before it is ever sent, so a killed app or a dropped connection resends the same id
/// (`commandId`, payment `idempotencyKey`, media `clientAssetId`), which the server answers
/// as a duplicate instead of applying it twice (OF-05).
struct OutboxEntry: Codable, Identifiable, Equatable {
    enum Action: Codable, Equatable {
        case progress(ProgressPayload)
        case note(NotePayload)
        case acknowledgeCheck(CheckPayload)
        case complete(CompletePayload)
        case invoiceSignature(SignaturePayload)
        case payment(PaymentPayload)
        case organizationFact(FactPayload)
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

    /// `jobs.acknowledgeCheck` input (acknowledgeCloseoutCheckInputSchema).
    struct CheckPayload: Codable, Equatable {
        let jobId: String
        let checkKey: String
    }

    /// `jobs.complete` input (completeJobInputSchema); replays are a natural key on the job.
    struct CompletePayload: Codable, Equatable {
        struct Disposition: Codable, Equatable {
            let reasonCode: String
            let reason: String
            let followUpNextAction: String
        }
        let jobId: String
        var unpaidDisposition: Disposition? = nil
    }

    /// A customer's sign-on-glass for an invoice. Not an offline command: the ink stays on the
    /// phone under `clientAssetId`, then uploads and authorizes the exact line revision the
    /// customer saw through the REST routes.
    struct SignaturePayload: Codable, Equatable {
        let jobId: String
        let invoiceId: String
        let expectedLinesRevision: Int
        let signerName: String
        let signedAt: String
        let clientAssetId: String
    }

    /// Cash or check taken without signal (OF-08). Never a `/v1/commands` entry: packages/sync
    /// keeps `payments.record` online-only, so this waits as a record and goes through the normal
    /// payment route once online, where the server checks the balance. The idempotency key is the
    /// one the collect sheet minted, so a retry can never record it twice.
    struct PaymentPayload: Codable, Equatable {
        let invoiceId: String
        var jobId: String? = nil
        let amountCents: Int
        let method: String
        let idempotencyKey: String
    }

    /// A company detail typed in setup or Company details without signal. It goes through the
    /// same `POST /v1/organization/facts` with the identity it was typed under; facts are
    /// append-only versions, so sending the same value twice only adds a matching version.
    struct FactPayload: Codable, Equatable {
        let factKey: String
        let value: String
        let label: String
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
    /// What the person saw when they made it, for Review ("Confirmed: Area cleaned up").
    var label: String? = nil
    /// Set before a send that may have reached the server without an answer; the next send of
    /// a follow-up then checks the server first, since that route cannot dedupe on its own.
    var attempted: Bool? = nil

    /// The record whose changes land in order (OF-06): the job, or the invoice for a payment
    /// on an invoice with no job.
    var jobID: String {
        switch action {
        case .progress(let payload): payload.jobId
        case .note(let payload): payload.jobId
        case .acknowledgeCheck(let payload): payload.jobId
        case .complete(let payload): payload.jobId
        case .invoiceSignature(let payload): payload.jobId
        case .payment(let payload): payload.jobId ?? payload.invoiceId
        case .organizationFact: Self.organizationRecord
        case .followUp(let payload): payload.jobId
        }
    }

    /// The ordering key company details share: they land in the order they were typed.
    static let organizationRecord = "organization"

    /// The registered offline command, or nil for changes that only replay through REST.
    var command: String? {
        switch action {
        case .progress: "jobs.progress"
        case .note: "jobs.addNote"
        case .acknowledgeCheck: "jobs.acknowledgeCheck"
        case .complete: "jobs.complete"
        // Follow-ups are never sent to /v1/commands (restOnly).
        case .invoiceSignature, .payment, .organizationFact, .followUp: nil
        }
    }

    var viaCommand: Bool { command != nil && restOnly != true }

    /// Payments and signatures have no other copy once their sheet closes, so they must reach disk.
    var isDurableOnly: Bool {
        switch action {
        case .invoiceSignature, .payment: true
        default: false
        }
    }

    /// The job status this change moves to, for showing the step as waiting (OF-02).
    var expectedStatus: String? {
        switch action {
        case .progress(let payload): payload.to
        case .complete: "completed"
        default: nil
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
        case .acknowledgeCheck: label.map { "Confirmed: \($0)" } ?? "Checklist item confirmed"
        case .complete: "Completed job"
        case .invoiceSignature(let payload): "Signature from \(payload.signerName)"
        case .payment(let payload): "\(payload.method.capitalized) \(money(payload.amountCents, currency: "USD"))"
        case .organizationFact(let payload): payload.label
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
    /// Photos and files waiting in `PendingMediaStore`, counted in the one sync line (OF-03).
    @Published private(set) var waitingPhotos = 0
    /// Jobs that still have media on this phone; a queued Complete on one of them waits.
    private var photoJobIDs: Set<String> = []
    /// Bumped after a sync sends anything, so open screens reload what the server now has.
    @Published private(set) var syncGeneration = 0
    /// Payments this session recorded from the queue. They keep holding their amount on an
    /// invoice screen until that screen has reloaded and sees them, so the same money can't
    /// look collectable again in between.
    private(set) var recordedPayments: [OutboxEntry.PaymentPayload] = []

    var pending: [OutboxEntry] { entries.filter { $0.state == .pending } }
    /// Everything on this phone that hasn't reached the server yet.
    var waitingCount: Int { pending.count + waitingPhotos }
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

    /// Payments recorded from the queue, kept on disk so a restart offline still holds them
    /// against the older saved invoice copy.
    private var recordedFile: URL? { file?.deletingPathExtension().appendingPathExtension("recorded") }

    private func persistRecorded() {
        guard let recordedFile else { return }
        try? JSONEncoder().encode(recordedPayments)
            .write(to: recordedFile, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// An invoice's history from the server now holds these payments, and that history is
    /// saved on the phone, so they no longer need holding.
    func forgetRecorded(seen keys: Set<String>) {
        let before = recordedPayments.count
        recordedPayments.removeAll { keys.contains($0.idempotencyKey) }
        if recordedPayments.count != before { persistRecorded() }
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
            recordedPayments = []
            return
        }
        guard identity?.actorID != actorID || identity?.organizationID != organizationID else { return }
        binding = UUID(); activeDrain = nil; syncing = false; lastSyncSent = 0
        identity = (actorID, organizationID)
        entries = file.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode([OutboxEntry].self, from: $0) } ?? []
        recordedPayments = recordedFile.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([OutboxEntry.PaymentPayload].self, from: $0) } ?? []
    }

    /// Follows the media waiting on this phone (`PendingMediaStore.items`) after it changes.
    func notePendingMedia(_ items: [PendingMedia]) {
        let jobs = Set(items.map(\.jobID))
        if photoJobIDs != jobs { photoJobIDs = jobs }
        // Photos left the phone: open screens reload, so a closeout sees the server's photo count.
        if items.count < waitingPhotos { syncGeneration += 1 }
        if waitingPhotos != items.count { waitingPhotos = items.count }
    }

    /// Sign-out: unsent changes for this phone are deleted with the session.
    func clearAll() {
        binding = UUID(); activeDrain = nil; syncing = false; lastSyncSent = 0
        identity = nil
        entries = []
        recordedPayments = []
        waitingPhotos = 0
        photoJobIDs = []
        try? FileManager.default.removeItem(at: directory)
    }

    @discardableResult
    private func persist() -> Bool {
        guard let file else { return false }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(entries).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch { return false }
    }

    @discardableResult
    func enqueue(_ action: OutboxEntry.Action, policyVersion: Int, label: String? = nil, attempted: Bool = false) -> OutboxEntry? {
        guard let identity else { return nil }
        // A second tap on the same collected payment is the same payment, not another one.
        if case .payment(let payment) = action,
           let existing = entries.first(where: { if case .payment(let other) = $0.action { other.idempotencyKey == payment.idempotencyKey } else { false } }) {
            return existing
        }
        // A newer value for the same company detail replaces the one still waiting.
        if case .organizationFact(let fact) = action {
            entries.removeAll {
                if case .organizationFact(let other) = $0.action { other.factKey == fact.factKey && $0.state == .pending } else { false }
            }
        }
        var entry = OutboxEntry(id: UUID().uuidString.lowercased(), deviceId: deviceID, actorId: identity.actorID,
                                organizationId: identity.organizationID, policyVersion: policyVersion,
                                createdAt: Date(), action: action)
        entry.label = label
        if case .followUp = action {
            entry.restOnly = true
            entry.attempted = attempted ? true : nil
        }
        entries.append(entry)
        // Money and ink only count as saved once they are on disk; the caller keeps its own copy otherwise.
        if !persist(), entry.isDurableOnly {
            entries.removeAll { $0.id == entry.id }
            return nil
        }
        return entry
    }

    /// A company detail saved online wins over an older value still waiting here.
    func discardPendingFact(_ factKey: String) {
        let before = entries.count
        entries.removeAll {
            if case .organizationFact(let fact) = $0.action { fact.factKey == factKey && $0.state == .pending } else { false }
        }
        if entries.count != before { persist() }
    }

    private var signatureDirectory: URL { directory.appendingPathComponent("Signatures", isDirectory: true) }

    /// Keeps a customer's ink on the phone and queues the invoice authorization that uses it.
    @discardableResult
    func enqueueSignature(_ png: Data, payload: OutboxEntry.SignaturePayload, policyVersion: Int) -> OutboxEntry? {
        guard identity != nil, UUID(uuidString: payload.clientAssetId) != nil else { return nil }
        do {
            try FileManager.default.createDirectory(at: signatureDirectory, withIntermediateDirectories: true)
            try png.write(to: signatureDirectory.appendingPathComponent("\(payload.clientAssetId).png"),
                          options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch { return nil }
        guard let entry = enqueue(.invoiceSignature(payload), policyVersion: policyVersion) else {
            try? FileManager.default.removeItem(at: signatureDirectory.appendingPathComponent("\(payload.clientAssetId).png"))
            return nil
        }
        return entry
    }

    func signatureData(_ clientAssetID: String) -> Data? {
        try? Data(contentsOf: signatureDirectory.appendingPathComponent("\(clientAssetID).png"))
    }

    /// Cash and check waiting to record on an invoice (OF-08). Never counted as paid.
    /// Refused ones still hold their money against the invoice (the cash is in hand), but only
    /// replayable ones count toward a closeout (`replayableOnly`).
    func waitingPayments(invoiceID: String, replayableOnly: Bool = false) -> [OutboxEntry.PaymentPayload] {
        (replayableOnly ? pending : entries).compactMap { if case .payment(let payment) = $0.action, payment.invoiceId == invoiceID { payment } else { nil } }
    }

    func waitingSignature(invoiceID: String) -> OutboxEntry.SignaturePayload? {
        pending.lazy.compactMap { if case .invoiceSignature(let payload) = $0.action, payload.invoiceId == invoiceID { payload } else { nil } }.last
    }

    /// Checklist items confirmed on this phone and not yet on the server.
    func waitingChecks(jobID: String) -> Set<String> {
        Set(pending.compactMap { if case .acknowledgeCheck(let check) = $0.action, check.jobId == jobID { check.checkKey } else { nil } })
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
        finish(entry.id)
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

    /// A change that timed out on the phone may still have reached the server. If the server
    /// already shows it, the change is done, not refused.
    private func alreadyApplied(_ entry: OutboxEntry, api: APIClient, current: @MainActor () -> Bool) async -> Bool {
        guard current() else { return false }
        let applied: Bool
        switch entry.action {
        case .progress(let payload):
            guard let target = Self.lifecycleRank[payload.to], let job = try? await api.fieldJob(payload.jobId),
                  let rank = Self.lifecycleRank[job.status] else { return false }
            applied = rank >= target
        case .complete(let payload):
            applied = (try? await api.fieldJob(payload.jobId))?.status == "completed"
        case .acknowledgeCheck(let payload):
            applied = (try? await api.fieldCloseout(payload.jobId))?.facts.acknowledgedCheckKeys.contains(payload.checkKey) == true
        case .invoiceSignature(let payload):
            applied = (try? await api.fieldInvoice(payload.invoiceId))?.customerAuthorization?.linesRevision == payload.expectedLinesRevision
        case .payment(let payload):
            applied = (try? await api.fieldPayments(payload.invoiceId))?.contains { $0.idempotencyKey == payload.idempotencyKey } == true
        case .organizationFact(let payload):
            applied = (try? await api.organizationProfile())?.value(payload.factKey) == payload.value
        case .note, .followUp:
            return false
        }
        return applied && current()
    }

    /// The status this phone expects a job to have once its queued changes land.
    func pendingStatus(for jobID: String) -> String? {
        pending.last { $0.jobID == jobID && $0.expectedStatus != nil }?.expectedStatus
    }

    func pendingNotes(for jobID: String) -> [OutboxEntry] {
        entries.filter { $0.jobID == jobID && { if case .note = $0.action { true } else { false } }($0) }
    }

    /// Sends queued changes oldest first, in order (OF-06). Runs of offline commands go to the
    /// command endpoint when the workspace has it; signatures, payments and everything on a
    /// workspace without it go through the same REST routes the app uses online.
    func drain(api: APIClient, useCommandEndpoint: Bool, canSend: @MainActor () -> Bool = { true }) async {
        guard !syncing, !pending.isEmpty, let owner = identity, let origin = api.normalizedOrigin, canSend(), !Task.isCancelled else { return }
        let token = binding, generation = api.requestGeneration, operation = UUID()
        func current() -> Bool {
            binding == token && identity?.actorID == owner.actorID && identity?.organizationID == owner.organizationID &&
            api.requestGeneration == generation && api.normalizedOrigin == origin && canSend() && !Task.isCancelled
        }
        activeDrain = operation; syncing = true
        defer {
            if activeDrain == operation {
                activeDrain = nil; syncing = false
                if lastSyncSent > 0 { syncGeneration += 1 }
            }
        }
        var sent = 0
        // A completion waits while its job still has photos on this phone: the closeout may count them.
        let photoJobs = photoJobIDs
        func waitsOnPhotos(_ entry: OutboxEntry) -> Bool {
            if case .complete = entry.action { photoJobs.contains(entry.jobID) } else { false }
        }
        // A job held for its photos keeps its later changes in order; other jobs keep syncing.
        var heldJobs = Set<String>()
        var queue: [OutboxEntry] { pending.filter { !heldJobs.contains($0.jobID) } }
        while current(), let first = queue.first {
            if waitsOnPhotos(first) { heldJobs.insert(first.jobID); continue }
            if useCommandEndpoint && first.viaCommand {
                let run = Array(queue.prefix { $0.viaCommand && !waitsOnPhotos($0) }.prefix(50))
                guard let applied = await sendCommands(run, api: api, current: current) else { break }
                sent += applied
            } else {
                switch await sendREST(first, api: api, current: current) {
                case .sent: sent += 1
                case .refused: continue
                case .stop:
                    if current() { lastSyncSent = sent }
                    return
                }
            }
        }
        guard current() else { return }
        lastSyncSent = sent
    }

    /// Sends one batch; nil means stop (no signal, a server error, or a batch the server did
    /// not fully answer, which stops the loop rather than spinning).
    private func sendCommands(_ batch: [OutboxEntry], api: APIClient, current: @MainActor () -> Bool) async -> Int? {
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
                case .acknowledgeCheck(let payload): try payload.encode(to: encoder)
                case .complete(let payload): try payload.encode(to: encoder)
                case .invoiceSignature, .payment, .organizationFact, .followUp: break // Never batched: `command` is nil.
                }
            }
        }
        struct Batch: Encodable { let commands: [Envelope] }
        struct Result: Decodable { let outcomes: [OutboxOutcome] }
        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let envelopes = batch.compactMap { entry in
            entry.command.map {
                Envelope(commandId: entry.id, deviceId: entry.deviceId, actorId: entry.actorId, organizationId: entry.organizationId,
                         policyVersion: entry.policyVersion, command: $0, clientCreatedAt: stamp.string(from: entry.createdAt),
                         payload: AnyPayload(action: entry.action))
            }
        }
        var sent = 0
        do {
            guard current() else { return nil }
            let result: Result = try await api.send("POST", "/v1/commands", body: Batch(commands: envelopes))
            guard current() else { return nil }
            for outcome in result.outcomes {
                guard current() else { return nil }
                if outcome.status == "applied" || outcome.status == "duplicate" {
                    finish(outcome.commandId)
                    sent += 1
                } else if outcome.category == "policy_superseded",
                          let index = entries.firstIndex(where: { $0.id == outcome.commandId }) {
                    entries[index].restOnly = true
                } else if let entry = entries.first(where: { $0.id == outcome.commandId }), outcome.category == "conflict" {
                    let applied = await alreadyApplied(entry, api: api, current: current)
                    guard current() else { return nil }
                    if applied {
                        finish(outcome.commandId)
                        sent += 1
                    } else {
                        reject(outcome.commandId, reason: outcome.detail ?? outcome.category ?? "The server refused this change.")
                    }
                } else {
                    reject(outcome.commandId, reason: outcome.detail ?? outcome.category ?? "The server refused this change.")
                }
            }
            guard current() else { return nil }
            persist()
            let answered = Set(result.outcomes.map(\.commandId))
            return batch.allSatisfy { answered.contains($0.id) } ? sent : nil
        } catch {
            return nil // No signal or a server error: everything stays queued.
        }
    }

    private enum RESTResult { case sent, refused, stop }

    private func sendREST(_ entry: OutboxEntry, api: APIClient, current: @MainActor () -> Bool) async -> RESTResult {
        guard current() else { return .stop }
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
            case .acknowledgeCheck(let payload):
                _ = try await api.acknowledgeFieldCheck(payload.jobId, checkKey: payload.checkKey)
            case .complete(let payload):
                let disposition = payload.unpaidDisposition.map {
                    FieldUnpaidDisposition(reasonCode: $0.reasonCode, reason: $0.reason, followUpNextAction: $0.followUpNextAction)
                }
                _ = try await api.completeFieldJob(payload.jobId, request: .init(unpaidDisposition: disposition))
            case .invoiceSignature(let payload):
                guard let png = signatureData(payload.clientAssetId) else {
                    reject(entry.id, reason: "The signature is no longer on this phone. Ask the customer to sign again.")
                    persist()
                    return .refused
                }
                let asset = try await MediaTransfer(api: api).upload(jobID: payload.jobId, clientAssetID: payload.clientAssetId,
                                                                     kind: "photo", mime: "image/png", originalFilename: "signature.png",
                                                                     data: png, tags: ["signature"])
                _ = try await api.authorizeFieldInvoice(payload.invoiceId, expectedLinesRevision: payload.expectedLinesRevision,
                                                        signature: .init(signerName: payload.signerName, signedAt: payload.signedAt,
                                                                         imageMediaId: asset.id))
            case .organizationFact(let payload):
                try await api.confirmOrganizationFact(payload.factKey, value: payload.value,
                                                      actorID: entry.actorId, organizationID: entry.organizationId)
            case .followUp(let payload):
                if entry.attempted == true {
                    let earlier = await followUpExists(payload, since: entry.createdAt, actorID: entry.actorId, api: api)
                    guard current() else { return .stop }
                    // Unknown (no live answer): keep it queued rather than risk sending it twice.
                    guard let earlier else { return .stop }
                    if earlier { break } // An earlier send reached the server; it is done.
                }
                if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                    entries[index].attempted = true
                    persist()
                }
                guard let kind = FieldFollowUpRequest.Kind(rawValue: payload.kind) else {
                    reject(entry.id, reason: "This follow-up type is not supported.")
                    persist()
                    return .refused
                }
                _ = try await api.requestFieldFollowUp(payload.jobId, request: .init(kind: kind, reason: payload.reason,
                                                                                   nextAction: payload.nextAction))
            case .payment(let payload):
                guard let method = FieldPaymentMethod(rawValue: payload.method) else {
                    reject(entry.id, reason: "This payment method can't be recorded from the phone.")
                    persist()
                    return .refused
                }
                _ = try await api.recordFieldPayment(payload.invoiceId, request: .init(
                    amount: .init(amount: payload.amountCents, currency: "USD"), method: method, idempotencyKey: payload.idempotencyKey))
            }
            guard current() else { return .stop }
            finish(entry.id)
            persist()
            return .sent
        } catch is CancellationError {
            return .stop
        } catch {
            guard current() else { return .stop }
            if error.isConnectivityFailure { return .stop }
            if let problem = error as? Problem, let status = problem.status, (400..<500).contains(status), status != 401, status != 429 {
                let applied = status == 409 ? await alreadyApplied(entry, api: api, current: current) : false
                guard current() else { return .stop }
                if applied {
                    finish(entry.id)
                    persist()
                    return .sent
                }
                reject(entry.id, reason: problem.errorDescription ?? "The server refused this change.")
                persist()
                return .refused
            }
            return .stop // 5xx, 401, rate limit or a storage hiccup: try again later.
        }
    }

    /// Clears a change the server has, with the ink it no longer needs.
    private func finish(_ id: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        if case .invoiceSignature(let payload) = entries[index].action {
            try? FileManager.default.removeItem(at: signatureDirectory.appendingPathComponent("\(payload.clientAssetId).png"))
        }
        if case .payment(let payment) = entries[index].action, entries[index].state == .pending {
            recordedPayments.append(payment)
            persistRecorded()
        }
        entries.remove(at: index)
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

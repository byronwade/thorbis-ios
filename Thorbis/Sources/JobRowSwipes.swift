import SwiftUI
import UIKit

// Job row swipes on Today and Jobs (owner-approved 31 Oct 2026):
// - Swipe right (leading): Call and Directions, from the number and the job's own service location
//   the screen already has or reads once when the row is first swiped.
// - Swipe left (trailing): the next status move (On my way, Arrive, Start work), from the same
//   allowed moves the job's status popover and Today's Now panel use. List items carry no allowed
//   moves, so the row reads GET /v1/jobs/{id} the first time it is swiped ("Checking"), and shows
//   nothing when the server allows no forward move. Moves are never guessed online.
// - A full swipe left runs that move: all three are forward, non-destructive steps, and only a role
//   with job.edit gets one. Sent and confirmed reads as the new status with a success tap; no
//   signal queues it and the row says "waiting to sync"; a refusal says why on the screen.
// The same Call, Directions and status moves are on the job screen, one tap away.

/// Which status moves a job offers, and which one is next. One source for the job's status popover,
/// Today's Now panel and the rows' swipe.
enum JobMoves {
    /// The field moves the status popover lists (Done and Cancel are their own guarded flows).
    static let fieldMoves: Set<String> = ["scheduled", "dispatched", "en_route", "arrived", "in_progress", "paused"]
    /// The forward steps a row or the Now panel may run in one go.
    static let forwardSteps = ["en_route", "arrived", "in_progress"]

    /// The moves the status popover lists: the server's allowed moves, or, while a step is queued on
    /// this phone, the steps the server has allowed from that status before. Filtered by role.
    static func available(served: [String]?, queued: String?, learned: (String) -> [String],
                          canEdit: Bool, canAssign: Bool) -> [String] {
        let allowed = queued.map { learned($0).filter { forwardSteps.contains($0) } } ?? (served ?? [])
        return allowed.filter {
            fieldMoves.contains($0) && (["scheduled", "dispatched"].contains($0) ? canAssign : canEdit)
        }
    }

    /// The next forward step, or nil: never backwards, never Resume (that needs the pause's own
    /// record), never a move the server has not allowed.
    /// - Parameters:
    ///   - served: the job as GET /v1/jobs/{id} returned it (its status and allowed moves); nil until read.
    ///   - queued: a step already queued on this phone for the job.
    static func next(listedStatus: String, served: (status: String, allowed: [String])?, queued: String?,
                     isOffline: Bool, learned: (String) -> [String], canEdit: Bool) -> String? {
        guard canEdit else { return nil }
        let status: String
        let allowed: [String]
        if let queued {
            status = queued
            allowed = learned(queued)
        } else if let served {
            status = served.status
            allowed = served.allowed
        } else if isOffline {
            status = listedStatus
            allowed = learned(listedStatus)
        } else {
            return nil
        }
        let order = ["scheduled": 0, "dispatched": 0, "en_route": 1, "arrived": 2, "in_progress": 3, "paused": 3]
        let current = order[status] ?? 0
        return forwardSteps.first {
            allowed.contains($0) && (order[$0] ?? 0) > current && !(status == "paused" && $0 == "in_progress")
        }
    }

    /// The step's words, as the job screen says them.
    static func title(_ step: String) -> String {
        switch step {
        case "en_route": "On my way"
        case "arrived": "Arrive"
        case "in_progress": "Start work"
        default: step.statusLabel
        }
    }

    static func request(_ step: String) -> FieldProgressRequest? {
        switch step {
        case "en_route": .enRoute(etaMinutes: nil)
        case "arrived": .arrived()
        case "in_progress": .start
        default: nil
        }
    }
}

/// What a job row's swipe offers. Pure: the row's number, place, next step and role decide it.
struct JobRowSwipePlan: Equatable {
    enum Action: Equatable { case call, directions, move(String) }

    var leading: [Action] = []
    var trailing: [Action] = []
    /// The action a full swipe runs: only a forward, non-destructive move.
    var fullSwipe: Action?

    /// - Parameters:
    ///   - phone: the customer's number as read (nil: none on file, or not read).
    ///   - hasPlace: the job's own service location has an address to drive to.
    ///   - next: `JobMoves.next(...)` (already nil without job.edit or a server-allowed move).
    ///   - canViewCustomer: the role may see the customer's contacts and places.
    static func make(phone: String?, hasPlace: Bool, next: String?, canViewCustomer: Bool) -> JobRowSwipePlan {
        var plan = JobRowSwipePlan()
        if canViewCustomer, JobReach(phone: phone, email: nil).call != nil { plan.leading.append(.call) }
        if canViewCustomer, hasPlace { plan.leading.append(.directions) }
        if let next, JobMoves.forwardSteps.contains(next) {
            plan.trailing = [.move(next)]
            plan.fullSwipe = .move(next)
        }
        return plan
    }
}

/// What the screen's rows have read for their swipes, and the moves they send. One per screen.
@MainActor
final class JobRowSwipeBook: ObservableObject {
    struct Served: Equatable { let status: String; let allowed: [String]; let updatedAt: String? }

    /// Each job as GET /v1/jobs/{id} last answered (its status and allowed moves).
    @Published private(set) var served: [String: Served] = [:]
    /// The number to call per customer, once read; a nil value means read and none on file.
    @Published private(set) var phones: [String: String?] = [:]
    @Published private(set) var reading: Set<String> = []
    /// Rows already read at this version of the job, answered or not (offline, refused), so a row
    /// that could not be read stops saying "Checking".
    @Published private(set) var tried: [String: String] = [:]
    /// A move sent and not yet answered: its cell turns; the row's status stays the server's.
    @Published private(set) var sending: [String: String] = [:]
    /// What a refused move said, shown on the screen beside the list.
    @Published var problem: String?
    /// Haptic triggers: the server confirmed a move; a move was saved on the phone to send later.
    @Published private(set) var confirmed = 0
    @Published private(set) var queued = 0
    let rows = RowSwipeState()
    private var key = ""

    func reset(identity: String) {
        guard identity != key else { return }
        key = identity
        served = [:]; phones = [:]; reading = []; tried = [:]; sending = [:]; problem = nil
        rows.close()
    }

    func isRead(_ job: Job) -> Bool {
        served[job.id].map { $0.updatedAt == job.updatedAt || job.updatedAt == nil } ?? false
    }

    func phoneIsRead(_ job: Job) -> Bool { job.customerId.map { phones.keys.contains($0) } ?? true }

    /// The number, as read for this job's customer.
    func phone(_ job: Job) -> String? { job.customerId.flatMap { phones[$0] ?? nil } }

    /// Reads what the row needs that isn't known yet: the job's allowed moves and the customer's number.
    func read(_ job: Job, api: APIClient, session: SessionController, outbox: FieldOutbox) async {
        guard !reading.contains(job.id) else { return }
        let needsMoves = !isRead(job) && session.can("job.view", feature: "jobs") && session.can("job.edit", feature: "jobs")
        let needsPhone = !phoneIsRead(job) && session.can("customer.view", feature: "core_crm")
        guard needsMoves || needsPhone else { return }
        let identity = key
        let generation = session.generation
        let organizationID = session.activeOrganization?.id
        reading.insert(job.id)
        defer {
            if key == identity {
                reading.remove(job.id)
                tried[job.id] = job.updatedAt ?? ""
            }
        }
        if needsMoves {
            if let saved = JobDetailCache.job(job.id), saved.organizationId == organizationID,
               saved.status == job.status, saved.updatedAt == job.updatedAt, let allowed = saved.allowedTransitions {
                // Read ahead this hour (DayPrefetch) and unchanged since: the same answer.
                served[job.id] = Served(status: saved.status, allowed: allowed, updatedAt: job.updatedAt)
            } else if !session.isOffline, let record = try? await api.fieldJob(job.id) {
                guard key == identity, session.generation == generation, record.organizationId == organizationID else { return }
                served[job.id] = Served(status: record.status, allowed: record.allowedTransitions ?? [],
                                        updatedAt: job.updatedAt)
                outbox.learn(record)
            }
        }
        if needsPhone, let customerID = job.customerId, let organizationID {
            if let stop = JobDetailCache.stop(job.id), stop.organizationID == organizationID,
               stop.customerID == customerID, let phone = stop.phone {
                phones[customerID] = phone
            } else if !session.isOffline, let contacts = try? await api.fieldContacts(customerID) {
                guard key == identity, session.generation == generation else { return }
                let verified = contacts.filter { $0.organizationId == organizationID && $0.customerId == customerID }
                var account: CustomerRecord?
                if NextStopPlace.phone(contacts: verified, account: nil) == nil,
                   let record = try? await api.fieldCustomer(customerID),
                   record.organizationId == organizationID, record.id == customerID {
                    account = record
                }
                guard key == identity else { return }
                phones[customerID] = NextStopPlace.phone(contacts: verified, account: account)
            }
        }
    }

    /// The next step for this row, from what has been read (or what the phone learned, offline).
    func next(_ job: Job, session: SessionController, outbox: FieldOutbox) -> String? {
        guard sending[job.id] == nil else { return nil }
        let read = served[job.id].flatMap { isRead(job) ? $0 : nil }
        return JobMoves.next(listedStatus: job.status, served: read.map { ($0.status, $0.allowed) },
                             queued: outbox.pendingStatus(for: job.id), isOffline: session.isOffline,
                             learned: outbox.offlineSteps(from:), canEdit: session.can("job.edit", feature: "jobs"))
    }

    /// Not read yet at this version of the job, or being read now.
    private func unread(_ job: Job) -> Bool {
        reading.contains(job.id) || tried[job.id] != (job.updatedAt ?? "")
    }

    /// True while the trailing side can't say yet whether there is a move.
    func checkingMove(_ job: Job, session: SessionController, outbox: FieldOutbox) -> Bool {
        guard session.can("job.view", feature: "jobs"), session.can("job.edit", feature: "jobs"),
              sending[job.id] == nil, outbox.pendingStatus(for: job.id) == nil,
              !session.isOffline, !["completed", "canceled"].contains(job.status) else { return false }
        return !isRead(job) && unread(job)
    }

    /// True while the leading side is still reading the customer's number.
    func checkingPhone(_ job: Job, session: SessionController) -> Bool {
        guard session.can("customer.view", feature: "core_crm"), !session.isOffline, !phoneIsRead(job) else { return false }
        return unread(job)
    }

    /// Runs the move: sent and confirmed, queued for later, or refused with the reason.
    func run(_ step: String, for job: Job, api: APIClient, store: Store, session: SessionController, outbox: FieldOutbox) async {
        guard sending[job.id] == nil, let request = JobMoves.request(step) else { return }
        sending[job.id] = step
        problem = nil
        let outcome = await JobProgressRun.run(jobID: job.id, request: request, api: api, store: store,
                                               session: session, outbox: outbox)
        sending[job.id] = nil
        // What the server answered is stale now: read the job again before offering the next step.
        served[job.id] = nil
        switch outcome {
        case .sent(let refreshed):
            confirmed += 1
            if !refreshed { problem = "\(JobMoves.title(step)) saved. The latest list could not be refreshed." }
        case .queued: queued += 1
        case .refused(let message): problem = "\(JobMoves.title(step)) wasn't saved. \(message)"
        case .cancelled: break
        }
    }

    /// The row's swipe actions, built from the plan.
    func actions(for job: Job, customer: String, places: JobAddressBook, session: SessionController,
                 outbox: FieldOutbox, openURL: OpenURLAction, move: @escaping (String) -> Void) -> (leading: [RowSwipeAction], trailing: [RowSwipeAction], full: String?) {
        let directions = places.directions(job)
        let phone = phone(job)
        let plan = JobRowSwipePlan.make(phone: phone, hasPlace: directions != nil,
                                        next: next(job, session: session, outbox: outbox),
                                        canViewCustomer: session.can("customer.view", feature: "core_crm"))
        func action(_ item: JobRowSwipePlan.Action) -> RowSwipeAction? {
            switch item {
            case .call:
                guard let url = JobReach(phone: phone, email: nil).call else { return nil }
                return RowSwipeAction(id: "row-swipe-call-\(job.id)", title: "Call", symbol: "phone", tone: .ink,
                                      spokenName: "Call \(customer)") { openURL(url) }
            case .directions:
                guard let directions else { return nil }
                return RowSwipeAction(id: "row-swipe-directions-\(job.id)", title: "Directions",
                                      symbol: "arrow.triangle.turn.up.right.diamond", tone: .panel,
                                      spokenName: "Directions") { openURL(directions) }
            case .move(let step):
                return RowSwipeAction(id: "row-swipe-move-\(job.id)", title: JobMoves.title(step), symbol: "arrow.right",
                                      tone: .status(StatusTone(jobStatus: step)), spokenName: JobMoves.title(step)) { move(step) }
            }
        }
        // Being sent: the move's cell stays, turning, until the server (or the queue) answers.
        if let step = sending[job.id] {
            let busy = RowSwipeAction(id: "row-swipe-move-\(job.id)", title: JobMoves.title(step), symbol: "arrow.right",
                                      tone: .status(StatusTone(jobStatus: step)), spokenName: JobMoves.title(step),
                                      busy: true) {}
            return (plan.leading.compactMap(action), [busy], busy.id)
        }
        let trailing = plan.trailing.compactMap(action)
        return (plan.leading.compactMap(action), trailing, plan.fullSwipe != nil ? trailing.first?.id : nil)
    }
}

/// Sends a field step the one way the app does it: straight to the server with signal, else saved
/// on the phone (the outbox) and sent in order when signal returns. Today's Now panel and the rows
/// share it.
enum JobProgressRun {
    enum Outcome: Equatable {
        /// The server took it; `refreshed` says whether the list could be read again after.
        case sent(refreshed: Bool)
        /// Saved on this phone; it is sent when there is signal.
        case queued
        case refused(String)
        case cancelled
    }

    @MainActor
    static func run(jobID: String, request: FieldProgressRequest, api: APIClient, store: Store,
                    session: SessionController, outbox: FieldOutbox) async -> Outcome {
        if session.isOffline || !outbox.pending.filter({ $0.jobID == jobID }).isEmpty {
            return queue(jobID: jobID, request: request, api: api, store: store, session: session, outbox: outbox)
        }
        do {
            _ = try await api.progressFieldJob(jobID, request: request)
            return .sent(refreshed: await store.refresh(api) != .failed)
        } catch is CancellationError {
            return .cancelled
        } catch {
            if error.isConnectivityFailure {
                return queue(jobID: jobID, request: request, api: api, store: store, session: session, outbox: outbox)
            }
            return .refused(error.localizedDescription)
        }
    }

    /// No signal: save the step on the phone; it is sent in order when signal returns.
    @MainActor
    static func queue(jobID: String, request: FieldProgressRequest, api: APIClient, store: Store,
                      session: SessionController, outbox: FieldOutbox) -> Outcome {
        guard let payload = OutboxEntry.ProgressPayload(jobID: jobID, request: request) else {
            return .refused("That change needs a connection.")
        }
        outbox.enqueue(.progress(payload), policyVersion: session.policyVersion ?? 0)
        if !session.isOffline {
            Task {
                await outbox.drain(api: api, useCommandEndpoint: session.isFeatureOn("offline_sync"))
                await store.refresh(api)
            }
        }
        return .queued
    }
}

/// A Today or Jobs row with its swipes: reads on the first swipe (or, with VoiceOver on, when the
/// row appears, so its custom actions are there to choose), and sends the move through the book.
struct JobSwipeRow<Content: View>: View {
    let job: Job
    let customer: String
    @ObservedObject var book: JobRowSwipeBook
    @ObservedObject var places: JobAddressBook
    @ViewBuilder var content: (_ actions: [RowSwipeAction]) -> Content
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var outbox: FieldOutbox
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    var body: some View {
        let actions = book.actions(for: job, customer: customer, places: places, session: session, outbox: outbox,
                                   openURL: openURL) { step in
            Task { await book.run(step, for: job, api: api, store: store, session: session, outbox: outbox) }
        }
        RowSwipeContainer(id: job.id, leading: actions.leading, trailing: actions.trailing, fullSwipeID: actions.full,
                          checkingLeading: actions.leading.isEmpty && book.checkingPhone(job, session: session),
                          checkingTrailing: book.checkingMove(job, session: session, outbox: outbox),
                          onReveal: read, state: book.rows) {
            content(actions.leading + actions.trailing)
        }
        .task(id: voiceOver ? "\(job.id)|\(job.updatedAt ?? "")" : "") {
            if voiceOver { await book.read(job, api: api, session: session, outbox: outbox) }
        }
    }

    private func read() {
        Task { await book.read(job, api: api, session: session, outbox: outbox) }
    }
}

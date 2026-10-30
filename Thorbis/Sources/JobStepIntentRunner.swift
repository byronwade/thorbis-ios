import Foundation

/// Runs the Lock Screen / Dynamic Island step button (`AdvanceJobStepIntent`) inside the app.
///
/// It takes the same path as the job screen: the server's progress call when online, the
/// on-phone outbox when there is no signal (or an earlier step for the job is still waiting).
/// The card only changes after the server answers or the outbox has saved the step, and a
/// queued step reads "Waiting to sync" until the outbox sends it.
@MainActor
enum JobStepIntentRunner {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private static weak var api: APIClient?
    private static weak var session: SessionController?
    private static weak var outbox: FieldOutbox?
    private static weak var store: Store?

    /// Called once from the app's launch, before any intent can run.
    static func configure(api: APIClient, session: SessionController, outbox: FieldOutbox, store: Store) {
        self.api = api
        self.session = session
        self.outbox = outbox
        self.store = store
    }

    static func run(jobID: String, target: String) async throws {
        guard let api, let session, let outbox else { throw Failure(message: "Open Thorbis to update this job.") }
        // Read the card first: a cold background launch restores the session, which retires cards.
        let card = JobLiveActivity.card(for: jobID)
        guard await ready(session) else { throw Failure(message: "Open Thorbis to sign in.") }
        guard session.can("job.edit", feature: "jobs") else {
            throw Failure(message: "You don't have permission to update this job.")
        }
        guard let request = request(for: target) else { throw Failure(message: "Open the job to make this change.") }

        let generation = session.generation
        let authority = session.authorityRevision
        let organizationID = session.activeOrganization?.id
        let authorized: @MainActor () -> Bool = {
            session.generation == generation && session.authorityRevision == authority &&
                session.activeOrganization?.id == organizationID && session.can("job.view", feature: "jobs")
        }
        func show(_ status: String, since: Date, waiting: Bool) async {
            guard let attributes = card?.attributes else { return }
            await JobLiveActivity.show(attributes: attributes,
                                       state: .init(status: status, since: since, waitingToSync: waiting),
                                       isAuthorized: authorized)
        }

        if session.isOffline || outbox.pendingStatus(for: jobID) != nil {
            try await queue(jobID: jobID, request: request, target: target, previous: card?.state,
                            api: api, session: session, outbox: outbox, show: show)
            return
        }
        do {
            let record = try await api.progressFieldJob(jobID, request: request)
            outbox.learn(record)
            await show(record.status, since: JobLiveActivity.since(record, record.status) ?? Date(), waiting: false)
            refreshStore(api: api)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard error.isConnectivityFailure else { throw Failure(message: error.localizedDescription) }
            try await queue(jobID: jobID, request: request, target: target, previous: card?.state,
                            api: api, session: session, outbox: outbox, show: show)
        }
    }

    /// The forward steps the card offers; the same requests the job screen sends.
    static func request(for target: String) -> FieldProgressRequest? {
        switch target {
        case "en_route": .enRoute()
        case "arrived": .arrived()
        case "in_progress": .start
        default: nil
        }
    }

    /// No signal: save the step on the phone, show it as waiting, and send it now if signal is back.
    private static func queue(jobID: String, request: FieldProgressRequest, target: String,
                              previous: JobActivityAttributes.ContentState?,
                              api: APIClient, session: SessionController, outbox: FieldOutbox,
                              show: (String, Date, Bool) async -> Void) async throws {
        guard let payload = OutboxEntry.ProgressPayload(jobID: jobID, request: request),
              let entry = outbox.enqueue(.progress(payload), policyVersion: session.policyVersion ?? 0)
        else { throw Failure(message: "Open Thorbis to update this job.") }
        let queuedAt = Date()
        await show(target, queuedAt, true)
        guard !session.isOffline else { return }
        await outbox.drain(api: api, useCommandEndpoint: session.isFeatureOn("offline_sync"))
        switch outbox.entries.first(where: { $0.id == entry.id })?.state {
        case nil:
            // Sent and accepted.
            await show(target, queuedAt, false)
            refreshStore(api: api)
        case .pending?:
            break
        case .rejected?, .held?:
            // The server refused it; the card goes back to the last confirmed step.
            if let previous { await show(previous.status, previous.since, false) }
        }
    }

    /// A background launch has no session yet: give the app's own restore a moment, then restore.
    private static func ready(_ session: SessionController) async -> Bool {
        if session.phase == .ready { return true }
        for tick in 0..<40 {
            if session.phase == .ready { return true }
            if session.phase == .signedOut { return false }
            if tick == 4, session.phase == .restoring || session.phase == .failed {
                await session.revalidate()
                continue
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return session.phase == .ready
    }

    private static func refreshStore(api: APIClient) {
        guard let store else { return }
        Task { await store.refresh(api) }
    }
}

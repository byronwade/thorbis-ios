import Foundation

/// A presentation lease, not a new authorization or persistence owner.
@MainActor
struct SavedWorkScope: Identifiable, Equatable {
    let id: UUID
    let actorID: String
    let organizationID: String
    let normalizedOrigin: String
    let sessionGeneration: UUID
    let requestGeneration: UUID
    let mediaContext: PendingMediaStore.CaptureContext
    let outboxContext: FieldOutbox.CaptureContext

    static func capture(session: SessionController, api: APIClient, media: PendingMediaStore, outbox: FieldOutbox) -> SavedWorkScope? {
        guard session.can("job.view", feature: "jobs"), let actor = session.user?.id,
              let organization = session.activeOrganization?.id, let origin = api.normalizedOrigin,
              let context = media.captureContext(matching: .init(actorID: actor, organizationID: organization, origin: origin)),
              let commands = outbox.captureContext(matchingActorID: actor, organizationID: organization) else { return nil }
        return .init(id: UUID(), actorID: actor, organizationID: organization, normalizedOrigin: origin,
                     sessionGeneration: session.generation, requestGeneration: api.requestGeneration, mediaContext: context, outboxContext: commands)
    }

    func isCurrent(session: SessionController, api: APIClient, media: PendingMediaStore, outbox: FieldOutbox) -> Bool {
        session.can("job.view", feature: "jobs") && session.user?.id == actorID && session.activeOrganization?.id == organizationID &&
        session.generation == sessionGeneration && api.requestGeneration == requestGeneration && api.normalizedOrigin == normalizedOrigin &&
        media.captureContext(matching: .init(actorID: actorID, organizationID: organizationID, origin: normalizedOrigin)) == mediaContext &&
        outbox.captureContext(matchingActorID: actorID, organizationID: organizationID) == outboxContext
    }

    func canEdit(session: SessionController, api: APIClient, media: PendingMediaStore, outbox: FieldOutbox) -> Bool {
        isCurrent(session: session, api: api, media: media, outbox: outbox) && session.can("job.edit", feature: "jobs")
    }

    /// The confirmation retains an ID only; the current refused row is fetched again.
    @discardableResult
    func discardCommand(_ id: String, session: SessionController, api: APIClient, media: PendingMediaStore, outbox: FieldOutbox) -> Bool {
        guard let entry = refusedCommand(id, session: session, api: api, media: media, outbox: outbox) else { return false }
        outbox.dismiss(entry)
        return true
    }

    @discardableResult
    func retryCommand(_ id: String, session: SessionController, api: APIClient, media: PendingMediaStore, outbox: FieldOutbox) -> Bool {
        guard let entry = refusedCommand(id, session: session, api: api, media: media, outbox: outbox) else { return false }
        outbox.retry(entry)
        return true
    }

    private func refusedCommand(_ id: String, session: SessionController, api: APIClient, media: PendingMediaStore, outbox: FieldOutbox) -> OutboxEntry? {
        guard canEdit(session: session, api: api, media: media, outbox: outbox),
              let entry = outbox.entries.first(where: { $0.id == id && $0.actorId == actorID && $0.organizationId == organizationID }),
              case .rejected = entry.state else { return nil }
        return entry
    }
}

enum SavedWorkRowState: Equatable {
    case waitingToSync, waitingToUpload, uploading, held, needsChecking
    case rejected(String), needsAttention(String)

    var needsReview: Bool {
        switch self {
        case .rejected, .held, .needsChecking, .needsAttention: true
        default: false
        }
    }
    var title: String {
        switch self {
        case .waitingToSync: String(localized: "Waiting to sync")
        case .waitingToUpload: String(localized: "Waiting to upload")
        case .uploading: String(localized: "Uploading")
        case .held: String(localized: "On hold")
        case .needsChecking: String(localized: "Needs checking")
        case .rejected, .needsAttention: String(localized: "Needs attention")
        }
    }
    var reason: String? {
        switch self {
        case .rejected(let reason), .needsAttention(let reason): reason
        case .held: String(localized: "Waiting on an earlier refused change to this job.")
        case .needsChecking: String(localized: "This file will be checked before upload.")
        default: nil
        }
    }
}

struct SavedWorkRow: Identifiable, Equatable {
    let id: String
    let originalID: String
    let title: String
    let date: Date
    let state: SavedWorkRowState
    let isMedia: Bool
    let symbol: String
}
struct SavedWorkGroup: Identifiable, Equatable {
    var id: String { jobID }
    let jobID: String
    let title: String
    let shortReference: String
    let rows: [SavedWorkRow]
}

/// Metadata only. No note bodies, file bytes or global-warning text enter the projection.
struct SavedWorkSnapshot: Equatable {
    let groups: [SavedWorkGroup]
    let totalCount: Int
    let attentionCount: Int
    let pendingCount: Int
    let isSending: Bool
    let hasListingWarning: Bool
    var hasPendingWork: Bool { totalCount > 0 || isSending || hasListingWarning }

    @MainActor
    static func make(scope: SavedWorkScope, entries: [OutboxEntry], media: [PendingMedia], mediaErrors: [String: String], unverifiedMediaIDs: Set<String>, uploadingMediaID: String?, commandsSyncing: Bool, jobs: [Job], listingWarning: String?) -> SavedWorkSnapshot {
        var rowsByJob: [String: [SavedWorkRow]] = [:]
        for entry in entries where entry.actorId == scope.actorID && entry.organizationId == scope.organizationID {
            let state: SavedWorkRowState = switch entry.state {
            case .pending: .waitingToSync
            case .rejected(let reason): .rejected(reason)
            case .held: .held
            }
            let symbol: String = if case .note = entry.action { "note.text" } else { "arrow.triangle.2.circlepath" }
            rowsByJob[entry.jobID, default: []].append(.init(id: "command:\(entry.id)", originalID: entry.id,
                title: entry.summary, date: entry.createdAt, state: state, isMedia: false, symbol: symbol))
        }
        for item in media {
            let state: SavedWorkRowState
            if uploadingMediaID == item.id { state = .uploading }
            else if let error = mediaErrors[item.id] { state = .needsAttention(error) }
            else if unverifiedMediaIDs.contains(item.id) { state = .needsChecking }
            else { state = .waitingToUpload }
            rowsByJob[item.jobID, default: []].append(.init(id: "media:\(item.id)", originalID: item.id,
                title: item.title, date: item.capturedAt, state: state, isMedia: true,
                symbol: item.kind == "document" ? "doc" : "photo"))
        }
        let groups = rowsByJob.map { jobID, rows -> SavedWorkGroup in
            let title = jobs.first(where: { $0.id == jobID })?.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return .init(jobID: jobID, title: title.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "Job"),
                         shortReference: "JOB-" + String(jobID.suffix(4)).uppercased(),
                         rows: rows.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date })
        }.sorted { lhs, rhs in
            let first = lhs.rows.first?.date ?? .distantFuture, second = rhs.rows.first?.date ?? .distantFuture
            return first == second ? lhs.jobID < rhs.jobID : first < second
        }
        let rows = groups.flatMap(\.rows), attention = rows.filter { $0.state.needsReview }.count
        return .init(groups: groups, totalCount: rows.count, attentionCount: attention, pendingCount: rows.count - attention,
                     isSending: commandsSyncing || uploadingMediaID != nil, hasListingWarning: listingWarning != nil)
    }
}

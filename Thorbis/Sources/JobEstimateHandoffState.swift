import Foundation
import SwiftUI
import UIKit
import Combine

struct JobEstimateHandoffSelection {
    private(set) var selectedIDs: Set<String> = []
    private(set) var optionIDs: [String: String] = [:]
    private(set) var generation = UUID()
    mutating func setSelected(_ id: String, selected: Bool, eligibleIDs: Set<String>) {
        guard !selected || eligibleIDs.contains(id) else { return }
        let before = selectedIDs
        if selected { selectedIDs.insert(id) } else { selectedIDs.remove(id) }
        if before != selectedIDs { generation = UUID() }
    }
    mutating func chooseOption(estimateID: String, optionID: String, allowedOptionIDs: Set<String>) {
        guard allowedOptionIDs.contains(optionID), optionIDs[estimateID] != optionID else { return }
        optionIDs[estimateID] = optionID; generation = UUID()
    }
    mutating func reconcile(knownIDs: Set<String>, complete: Bool) {
        guard complete else { return }
        let before = selectedIDs
        selectedIDs.formIntersection(knownIDs)
        optionIDs = optionIDs.filter { knownIDs.contains($0.key) }
        if before != selectedIDs { generation = UUID() }
    }
}


struct JobEstimateReviewedItem: Equatable, Identifiable {
    let estimate: EstimateRecord
    let revision: CustomerIssuedEstimateRevision
    let optionID: String?
    var id: String { estimate.id }
    var key: String { "\(id):\(revision.revisionNumber)" }
}

enum JobEstimateHandoffOutcome: Equatable {
    case approved(EstimateRecord)
    case needsReview(String)
    case retryable(String)
    case unknown
}

struct JobEstimateSignatureIntent: Equatable {
    let signerName: String
    let signedAt: String
    let clientAssetID: String
    let png: Data
}

/// Retained by the handoff model, never by an ephemeral signing destination alone.
@MainActor
final class CustomerEstimateHandoffContext: ObservableObject, Identifiable {
    let reviewed: JobEstimateReviewedItem
    var initialSignerName: String
    let current: @MainActor () -> Bool
    let canApprove: @MainActor () -> Bool
    let transfer: MediaTransfer
    nonisolated let id: String
    @Published fileprivate(set) var outcome: JobEstimateHandoffOutcome?
    @Published private(set) var running = false
    private(set) var signature: JobEstimateSignatureIntent?
    var uploadedMediaID: String?
    var link: (token: String, action: PublicEstimateAction)?
    var publicDecision: PublicEstimateActionDecision?
    @Published private(set) var acceptedAction: PublicEstimateAction?
    var continueTitle = "Continue"
    var checkOutcome: @MainActor () async -> Void = {}
    var recoverPreparation: @MainActor () async -> Void = {}
    var backToReview: () -> Void = {}
    func configureNavigation(back: @escaping () -> Void) { backToReview = back }
    var submissionStarted = false
    var retryVerified = false
    var validate: @MainActor () async throws -> Void = {}
    var task: Task<Void, Never>?
    var confirmed: @MainActor (EstimateRecord?) async -> JobEstimateHandoffOutcome = { _ in .unknown }
    var publicConfirmed: @MainActor (PublicEstimateActionPatch) async -> JobEstimateHandoffOutcome = { _ in .unknown }
    var changed: @MainActor () -> Void = {}

    init(reviewed: JobEstimateReviewedItem, initialSignerName: String, current: @escaping @MainActor () -> Bool,
         canApprove: @escaping @MainActor () -> Bool, transfer: MediaTransfer) {
        self.id = reviewed.key; self.reviewed = reviewed; self.initialSignerName = initialSignerName
        self.current = current; self.canApprove = canApprove; self.transfer = transfer
    }
    func freezeSignature(signerName: String, png: Data, signedAt: String) throws -> JobEstimateSignatureIntent {
        guard current(), canApprove() else { throw CancellationError() }
        let name = signerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 120, !png.isEmpty else {
            throw Problem(title: "Enter your name and signature", status: nil, detail: nil)
        }
        if let signature {
            guard signature.signerName == name, signature.png == png, signature.signedAt == signedAt else {
                throw Problem(title: "Check the previous approval first", status: 409, detail: "Its exact signature and terms must be retained.")
            }
            return signature
        }
        let value = JobEstimateSignatureIntent(signerName: name, signedAt: signedAt, clientAssetID: UUID().uuidString.lowercased(), png: png)
        signature = value
        return value
    }
    var approvedSignerName: String? {
        guard case .approved(let record)? = outcome,
              record.id == reviewed.id, record.organizationId == reviewed.estimate.organizationId,
              record.customerId == reviewed.estimate.customerId, record.locationId == reviewed.estimate.locationId,
              record.currentRevisionNumber == reviewed.revision.revisionNumber, record.status == "approved" else { return nil }
        if reviewed.optionID != nil { return acceptedAction?.acceptance?.signerName }
        return record.approvalSignature?.signerName
    }
    /// Acceptance comes from the already bound token, never from the frozen requested choice alone.
    func retainAcceptedAction(_ action: PublicEstimateAction) -> Bool {
        guard current(), let link, let optionID = reviewed.optionID,
              action.kind == "estimate", action.status == .approved,
              action.revisionNumber == reviewed.revision.revisionNumber,
              action.contentHash == link.action.contentHash,
              action.title == reviewed.revision.title, action.currency == reviewed.revision.currency,
              let acceptance = action.acceptance, !acceptance.id.isEmpty,
              !acceptance.signerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              acceptance.optionId == optionID,
              let expected = reviewed.revision.options?.first(where: { $0.id == optionID }),
              let actual = action.options?.first(where: { $0.id == optionID }),
              actual.title == expected.title, actual.description == expected.description,
              actual.currency == expected.currency, Int(exactly: actual.totalAmount) == expected.totalAmount,
              Int(exactly: acceptance.totalAmount) == expected.totalAmount else { return false }
        acceptedAction = action
        return true
    }
    func report(_ outcome: JobEstimateHandoffOutcome) { self.outcome = outcome; changed() }

    enum Submission: Equatable { case submitted, notSubmitted, cannotSign }

    /// This estimate's own in-person approval, exactly as the handoff sends it: the drawn path
    /// (upload this context's signature asset, then POST /v1/estimates/{id}/approve with its revision)
    /// or the package path (this context's minted link, nonce and option, typed-name consent).
    /// Freezes the given ink only when this context has no frozen signature yet; an earlier frozen
    /// signature is always the one sent again. `stillCurrent` is the caller's own screen check.
    func submitApproval(api: APIClient, jobID: String, signer typed: String, png: () -> Data?, drawn: Bool,
                        stillCurrent: @escaping @MainActor () -> Bool) async throws -> Submission {
        let signer = signature?.signerName ?? typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard current(), canApprove() else { return .notSubmitted }
        if signature == nil {
            guard let data = png() else { return .notSubmitted }
            _ = try freezeSignature(signerName: signer, png: data, signedAt: ISO8601DateFormatter().string(from: Date()))
        }
        try await validate()
        if drawn {
            let mediaID = try await uploadFrozenSignature(jobID: jobID, stillCurrent: stillCurrent)
            try Task.checkCancellation()
            guard stillCurrent(), current(), canApprove(), let intent = signature else { return .notSubmitted }
            let input = FieldSignatureInput(signerName: signer, signedAt: intent.signedAt, imageMediaId: mediaID)
            submissionStarted = true; retryVerified = false
            let approved = try await api.approveFieldEstimate(reviewed.id, revisionNumber: reviewed.revision.revisionNumber, signature: input)
            guard stillCurrent(), current() else { return .submitted }
            guard canApprove() else { report(.unknown); return .submitted }
            report(await confirmed(approved))
            return .submitted
        }
        guard let link else { return .notSubmitted }
        let action = link.action
        guard let nonce = action.nonce, let consentVersion = action.consentVersion,
              action.canApprove(signerName: signer, consent: true, selectedOptionID: reviewed.optionID) else { return .cannotSign }
        // The drawing is kept with the job; the server records the typed name and option.
        _ = try? await uploadFrozenSignature(jobID: jobID, stillCurrent: stillCurrent)
        try Task.checkCancellation()
        guard stillCurrent(), current(), canApprove() else { return .notSubmitted }
        let decision = publicDecision ?? PublicEstimateActionDecision.approve(
            revisionNumber: action.revisionNumber, nonce: nonce, contentHash: action.contentHash,
            signerName: signer, consentVersion: consentVersion, consent: true, optionID: reviewed.optionID)
        publicDecision = decision
        submissionStarted = true; retryVerified = false
        let patch = try await api.decidePublicDocumentAction(token: link.token, decision: decision)
        guard stillCurrent(), current() else { return .submitted }
        guard canApprove() else { report(.unknown); return .submitted }
        report(await publicConfirmed(patch))
        return .submitted
    }

    /// The frozen signature's one job media asset for this estimate (stable client asset ID, reused once stored).
    func uploadFrozenSignature(jobID: String, stillCurrent: @escaping @MainActor () -> Bool) async throws -> String {
        guard stillCurrent(), current(), canApprove(), let intent = signature else { throw CancellationError() }
        if let id = uploadedMediaID { return id }
        let asset = try await transfer.upload(jobID: jobID, clientAssetID: intent.clientAssetID, kind: "photo", mime: "image/png",
            originalFilename: "signature.png", data: intent.png, tags: ["signature"],
            expectedOrganizationID: reviewed.estimate.organizationId,
            currentAuthority: { [weak self] in self?.current() == true && self?.canApprove() == true })
        guard current(), canApprove() else { throw CancellationError() }
        uploadedMediaID = asset.id
        return asset.id
    }

    /// What an interrupted approval becomes: unknown once sent, otherwise retryable or for review.
    func reportApprovalFailure(_ error: Error) {
        guard current() else { return }
        report(submissionStarted ? .unknown :
            customerEstimatePreparationCanRetry(error)
            ? .retryable("Preparing this approval was interrupted. Try again when connected.")
            : .needsReview(error.customerSentence(.approve)))
    }

    /// Runs one approval and waits for it, under the same guard as `run`.
    @discardableResult
    func perform(_ operation: @escaping @MainActor () async -> Void) async -> Bool {
        guard !running, current(), canApprove(), !submissionStarted || retryVerified else { return false }
        running = true; changed()
        let work = Task { @MainActor in await operation() }
        task = work
        await work.value
        running = false; task = nil; changed()
        return true
    }
    func run(_ operation: @escaping @MainActor () async -> Void) {
        guard !running, current(), canApprove(), !submissionStarted || retryVerified else { return }
        running = true; changed()
        task = Task { @MainActor in
            await operation()
            self.running = false; self.task = nil; self.changed()
        }
    }
    func retire() {
        task?.cancel(); task = nil; running = false
        signature = nil; uploadedMediaID = nil; link = nil; publicDecision = nil; acceptedAction = nil; initialSignerName = ""
        backToReview = {}; checkOutcome = {}; recoverPreparation = {}; validate = {}; confirmed = { _ in .unknown }; publicConfirmed = { _ in .unknown }; changed = {}
    }
}

@MainActor
final class JobEstimateHandoffModel: ObservableObject {
    let scope: JobDocumentScope
    private let jobLocationID: String?
    @Published private(set) var jobTitle: String
    @Published private(set) var customerName: String
    let documents: JobDocumentCollections
    let api: APIClient
    let session: SessionController
    @Published private(set) var records: [EstimateRecord] = []
    @Published private(set) var unavailableIDs: [String] = []
    @Published private(set) var complete = false
    @Published private(set) var loading = false
    @Published private(set) var canLoadMoreEstimates = false
    @Published private(set) var error: String?
    @Published private(set) var retired = false
    @Published private(set) var selection = JobEstimateHandoffSelection()
    @Published private(set) var reviewed: [JobEstimateReviewedItem] = []
    @Published private(set) var contexts: [String: CustomerEstimateHandoffContext] = [:]
    /// One signature for several estimates, alive only while its screen is open.
    @Published fileprivate(set) var batch: JobEstimateBatchApproval?
    fileprivate var batchSubscription: AnyCancellable?
    var selectedIDs: Set<String> { selection.selectedIDs }
    private let actorID: String
    private let sessionGeneration: UUID
    private let authorityRevision: UUID
    private let savedScopeRevision: UUID
    private let apiGeneration: UUID
    private let origin: String?
    private var freshIDs: Set<String> = []
    @Published private var revisions: [String: CustomerIssuedEstimateRevision] = [:]
    @Published private(set) var overviewPriceFailures: Set<String> = []
    @Published private(set) var overviewPriceGeneration = UUID()
    private var overviewPriceReady = false
    @Published private(set) var overviewPricesNeedRefresh = false
    @Published private var overviewReceipts: [String: CustomerEstimateAcceptanceReceipt] = [:]
    private var overviewRequests: [String: UUID] = [:]
    private var request = UUID()
    private var membershipPager: JobEstimateMembershipPager?
    private var pageRead: JobDocumentRead<EstimateRecord>?
    private var retryingPage = false
    private var reviewedGeneration: UUID?
    private var lastSignerName: String?
    var isCurrent: Bool { isCurrentJob && session.can("estimate.view", feature: "estimates") }
    /// Same person, workspace, session and job access: Customer view stays open on this job. Estimates
    /// additionally need `isCurrent`; invoices and details carry their own permission gates.
    var isCurrentJob: Bool {
        !retired && !actorID.isEmpty && session.user?.id == actorID && session.activeOrganization?.id == scope.organizationID &&
        session.generation == sessionGeneration && session.authorityRevision == authorityRevision &&
        api.requestGeneration == apiGeneration && api.savedCopyScopeRevision == savedScopeRevision && origin != nil && api.normalizedOrigin == origin &&
        session.can("job.view", feature: "jobs")
    }
    var eligibleIDs: Set<String> {
        guard isCurrent else { return [] }
        return Set(records.filter { record in
            record.status == "sent" && freshIDs.contains(record.id) && TechJobFlow.canShow(record, can: abilities) &&
            !contexts.values.contains(where: { $0.reviewed.id == record.id && $0.reviewed.revision.revisionNumber == record.currentRevisionNumber && ($0.submissionStarted || $0.outcome?.isApproved == true) })
        }.map(\.id))
    }
    var approvalAuthority: Bool { isCurrent && session.can("estimate.approve", feature: "estimates") }
    func cancelApprovals() {
        for context in contexts.values where context.running {
            context.task?.cancel()
            context.report(context.submissionStarted ? .unknown : .needsReview("Your access no longer allows approving this estimate."))
        }
        batch?.discard()
        reviewedGeneration = nil
    }
    var abilities: TechJobAbilities {
        .init(sendEstimate: session.can("estimate.send", feature: "estimates"), approveEstimate: session.can("estimate.approve", feature: "estimates"))
    }
    var canReview: Bool {
        isCurrent && !loading && complete && !selectedIDs.isEmpty && selectedIDs.isSubset(of: eligibleIDs) && selectedIDs.allSatisfy { id in
            let offered = options(for: id)
            return offered.isEmpty || offered.contains(where: { $0.id == selection.optionIDs[id] })
        }
    }
    var hasResults: Bool { contexts.values.contains { $0.outcome != nil || $0.running } }
    var approvedCount: Int { contexts.values.filter { $0.outcome?.isApproved == true }.count }
    var unknownCount: Int { contexts.values.filter { $0.outcome == .unknown }.count }
    var resultContexts: [CustomerEstimateHandoffContext] { contexts.values.filter { $0.outcome != nil || $0.running }.sorted { $0.id < $1.id } }

    init(job: JobRecord, customerName: String, documents: JobDocumentCollections, api: APIClient, session: SessionController) {
        self.scope = .init(jobID: job.id, organizationID: job.organizationId, customerID: job.customerId, originEstimateID: job.estimateId)
        self.jobLocationID = job.locationId; self.jobTitle = job.title
        self.customerName = customerName; self.documents = documents; self.api = api; self.session = session
        actorID = session.user?.id ?? ""; sessionGeneration = session.generation; authorityRevision = session.authorityRevision
        apiGeneration = api.requestGeneration; savedScopeRevision = api.savedCopyScopeRevision; origin = api.normalizedOrigin
    }
    func revision(for id: String) -> CustomerIssuedEstimateRevision? {
        guard let current = records.first(where: { $0.id == id }),
              detailsCurrent(current, authority: authorityRevision), let revision = revisions[id],
              (try? revision.validate(for: current)) != nil else { return nil }
        return revision
    }
    func options(for id: String) -> [FieldEstimateOption] {
        if let currentRevision = revision(for: id) { return currentRevision.options ?? [] }
        return records.first(where: { $0.id == id })?.options ?? []
    }
    func context(for id: String) -> CustomerEstimateHandoffContext? {
        guard let revision = records.first(where: { $0.id == id })?.currentRevisionNumber else { return nil }
        return contexts["\(id):\(revision)"]
    }
    func checkpointContext(for key: String) -> CustomerEstimateHandoffContext? {
        guard isCurrent, let context = contexts[key], context.current() else { return nil }
        // Recovery owns its original immutable item, independent of any new mutable selection.
        if context.submissionStarted || context.outcome != nil { return context }
        guard reviewed.contains(context.reviewed), reviewedGeneration == selection.generation,
              selectedIDs.contains(context.reviewed.id) else { return nil }
        return context
    }
    func retryPreparation(_ key: String) async {
        guard isCurrent, let context = contexts[key], !context.submissionStarted,
              case .retryable? = context.outcome, context.canApprove() else { return }
        let item = context.reviewed
        do {
            try await verifyMembership(item)
            guard isCurrent, !context.submissionStarted, case .retryable? = context.outcome, context.canApprove() else { return }
            let revision = try await api.customerIssuedEstimateRevision(for: item.estimate, currentAuthority: { [weak self, weak context] in
                self?.isCurrent == true && context?.canApprove() == true
            })
            try Task.checkCancellation()
            guard isCurrent, !context.submissionStarted, case .retryable? = context.outcome, context.canApprove() else { return }
            guard revision == item.revision else {
                context.report(.needsReview("This estimate changed. Review its current terms with your technician.")); return
            }
            if let link = context.link, let signature = context.signature {
                let action = try await api.publicDocumentAction(token: link.token)
                guard isCurrent, !context.submissionStarted, case .retryable? = context.outcome, context.canApprove() else { return }
                guard action.contentHash == link.action.contentHash, action.nonce == link.action.nonce,
                      action.revisionNumber == link.action.revisionNumber, action.title == link.action.title,
                      action.currency == link.action.currency, action.totalAmount == link.action.totalAmount,
                      action.options == link.action.options, action.scopeLines == link.action.scopeLines,
                      action.consentVersion == link.action.consentVersion, action.consentText == link.action.consentText,
                      action.canApprove(signerName: signature.signerName, consent: true, selectedOptionID: item.optionID) else {
                    context.report(.needsReview("This approval changed. Review its current terms with your technician.")); return
                }
            }
            context.outcome = nil; context.changed()
        } catch is CancellationError {
        } catch {
            guard isCurrent, !context.submissionStarted, case .retryable? = context.outcome else { return }
            context.report(customerEstimatePreparationCanRetry(error)
                ? .retryable("Preparing this approval was interrupted. Try again when connected.")
                : .needsReview(error.customerSentence(.approve)))
        }
    }
    func refresh() async {
        guard isCurrent, !loading else { if !isCurrent { retire() }; return }
        retryingPage = false
        let ticket = UUID(); request = ticket; loading = true; error = nil
        overviewPriceReady = false; overviewPricesNeedRefresh = false; revisions = [:]; overviewReceipts = [:]; overviewPriceFailures = []; overviewPriceGeneration = UUID()
        defer { if request == ticket { loading = false } }
        do {
            let fresh = try await api.liveFieldJob(scope.jobID)
            guard isCurrent, request == ticket, !Task.isCancelled else { return }
            guard sameJob(fresh) else { retire(); return }
            membershipPager = JobEstimateMembershipPager(jobID: scope.jobID)
            pageRead = nil; complete = false; canLoadMoreEstimates = false
            try await loadPage(ticket: ticket)
        } catch is CancellationError {
            if isCurrent, request == ticket { complete = false; overviewPricesNeedRefresh = true; error = "Couldn't finish loading estimates. Your previous selections are still here." }
        } catch {
            guard isCurrent, request == ticket else { return }
            complete = false; overviewPricesNeedRefresh = true; self.error = "Couldn't refresh all estimates. Your previous selections are still here."
        }
    }
    func loadMoreEstimates() async {
        guard isCurrent, !loading, canLoadMoreEstimates else { return }
        retryingPage = false
        let ticket = request
        loading = true; error = nil
        defer { if request == ticket { loading = false } }
        do { try await loadPage(ticket: ticket) }
        catch is CancellationError {
            if isCurrent, request == ticket { complete = false; retryingPage = true; error = "Couldn't load more estimates. Your selections are still here." }
        }
        catch {
            guard isCurrent, request == ticket else { return }
            complete = false; retryingPage = true; self.error = "Couldn't load more estimates. Your selections are still here."
        }
    }
    func retryEstimateLoading() async {
        if retryingPage && canLoadMoreEstimates { await loadMoreEstimates() }
        else { await refresh() }
    }
    private func loadPage(ticket: UUID) async throws {
        guard let pager = membershipPager, isCurrent, request == ticket else { throw CancellationError() }
        var preparedRead: JobDocumentRead<EstimateRecord>?
        try await pager.loadNext(isCurrent: { [weak self] in self?.isCurrent == true && self?.request == ticket }, beforeCommit: { [weak self] candidate in
            guard let self, self.isCurrent, self.request == ticket, !Task.isCancelled else { throw CancellationError() }
            var ids = candidate.estimateIDs
            if let origin = self.scope.originEstimateID, !ids.contains(where: { $0.caseInsensitiveCompare(origin) == .orderedSame }) { ids.insert(origin, at: 0) }
            guard let read = await JobDocumentsLoader.estimatesForPage(scope: self.scope, api: self.api, ids: ids,
                previous: self.pageRead, membershipFresh: candidate.pagesUsedOnlyFreshResponses,
                membershipComplete: candidate.scanReachedEnd && candidate.pagesUsedOnlyFreshResponses,
                isCurrent: { [weak self] in self?.isCurrent == true && self?.request == ticket }, onPartial: { [weak self] partial in
                    guard let self, self.isCurrent, self.request == ticket, self.pageRead == nil else { return }
                    self.records = partial.records; self.freshIDs = partial.freshIDs
                    self.unavailableIDs = partial.unavailableIDs; self.complete = false
                }) else { throw CancellationError() }
            guard self.isCurrent, self.request == ticket, !Task.isCancelled else { throw CancellationError() }
            preparedRead = read
        }, onCommit: { [weak self] candidate in
            guard let self, let read = preparedRead else { return }
            let previousRecords = self.records
            let retainedRevisions = self.revisions.filter { id, revision in
                guard let record = read.records.first(where: { $0.id == id }), previousRecords.contains(record),
                      read.freshIDs.contains(id), self.scope.contains(record, requestedID: id) else { return false }
                return (try? revision.validate(for: record, allowApprovedForReading: true)) != nil
            }
            let retainedReceipts = self.overviewReceipts.filter { id, receipt in
                guard let revision = retainedRevisions[id] else { return false }
                return (try? receipt.validate(for: revision)) != nil
            }
            self.pageRead = read; self.records = read.records; self.freshIDs = read.freshIDs
            self.unavailableIDs = read.unavailableIDs; self.complete = read.isComplete
            self.canLoadMoreEstimates = !candidate.scanReachedEnd
            self.error = (!read.isComplete && !self.canLoadMoreEstimates) ? read.issue : nil
            self.selection.reconcile(knownIDs: Set(read.records.map(\.id)), complete: read.isComplete)
            self.revisions = retainedRevisions; self.overviewReceipts = retainedReceipts
            self.overviewPriceFailures = []
            self.overviewPriceReady = true; self.overviewPricesNeedRefresh = false
            self.overviewPriceGeneration = UUID()
        }) { [weak self] cursor in
            guard let self else { throw CancellationError() }
            let current: @MainActor () -> Bool = { [weak self] in self?.isCurrent == true && self?.request == ticket }
            let page: APIRead<JobEstimateLinkPage>
            do {
                page = try await self.api.fieldJobEstimateLinkPage(self.scope.jobID, cursor: cursor, requireFresh: true, isCurrent: current)
            } catch let problem as Problem where problem.status == nil && problem.title == "Network error" {
                // A scoped saved page is readable but cannot authorize a signature.
                page = try await self.api.fieldJobEstimateLinkPage(self.scope.jobID, cursor: cursor, isCurrent: current)
            }
            return .init(links: page.value.items, nextCursor: page.value.nextCursor,
                         isAuthoritative: page.provenance.source == .urlSession(cacheBypassed: true))
        }
    }
    func setSelected(_ id: String, selected: Bool) {
        guard isCurrent, !contexts.values.contains(where: \.running), batch?.running != true else { return }
        let before = selection.generation
        selection.setSelected(id, selected: selected, eligibleIDs: eligibleIDs)
        if before != selection.generation { reviewed = []; reviewedGeneration = nil }
    }
    func chooseOption(estimateID: String, optionID: String) {
        guard isCurrent, !contexts.values.contains(where: \.running), batch?.running != true else { return }
        let before = selection.generation
        selection.chooseOption(estimateID: estimateID, optionID: optionID, allowedOptionIDs: Set(options(for: estimateID).map(\.id)))
        if before != selection.generation { reviewed = []; reviewedGeneration = nil }
    }
    func reviewSelected() async {
        guard canReview else { error = "Choose eligible estimates and their packages after refreshing the complete list."; return }
        let generation = selection.generation
        let selected = records.filter { selectedIDs.contains($0.id) }
        loading = true; error = nil
        defer { loading = false }
        var next: [JobEstimateReviewedItem] = []
        do {
            for record in selected {
                guard isCurrent, selection.generation == generation, !Task.isCancelled else { return }
                let revision = try await api.customerIssuedEstimateRevision(for: record, currentAuthority: { [weak self] in self?.isCurrent == true })
                guard isCurrent, selection.generation == generation, !Task.isCancelled else { return }
                revisions[record.id] = revision
                let choices = revision.options ?? []
                let option = selection.optionIDs[record.id]
                guard choices.isEmpty || choices.contains(where: { $0.id == option }) else {
                    throw Problem(title: "Choose a package for \(revision.title)", status: nil, detail: nil)
                }
                let chosen = choices.first(where: { $0.id == option })
                guard let amounts = CustomerDocumentAmounts(lines: chosen?.lines ?? revision.lines, currency: chosen?.currency ?? revision.currency),
                      amounts.total == (chosen?.totalAmount ?? revision.totalAmount) else {
                    throw Problem(title: "This estimate's amounts need a refresh", status: nil, detail: nil)
                }
                next.append(.init(estimate: record, revision: revision, optionID: option))
            }
            guard isCurrent, selection.generation == generation else { return }
            reviewed = next; reviewedGeneration = generation
            for item in next {
                if let old = contexts[item.key], old.reviewed == item { continue }
                if let old = contexts[item.key], old.submissionStarted {
                    throw Problem(title: "Check the previous approval before reviewing changed terms", status: 409, detail: nil)
                }
                let transfer: MediaTransfer
                #if DEBUG
                transfer = PaperPreview.enabled ? MediaTransfer(api: api, storageSession: PaperPreview.handoffStorageTransport()) : MediaTransfer(api: api)
                #else
                transfer = MediaTransfer(api: api)
                #endif
                let context = CustomerEstimateHandoffContext(reviewed: item, initialSignerName: lastSignerName ?? customerName,
                    current: { [weak self] in self?.isCurrent == true },
                    canApprove: { [weak self] in self?.approvalAllowed(item) == true }, transfer: transfer)
                context.validate = { [weak self] in guard let self else { throw CancellationError() }; try await self.verifyMembership(item) }
                context.confirmed = { [weak self] record in guard let self else { return .unknown }; return await self.confirm(item, record: record) }
                context.publicConfirmed = { [weak self] patch in guard let self else { return .unknown }; return await self.confirmPublic(item, patch: patch) }
                context.recoverPreparation = { [weak self, weak context] in guard let context else { return }; await self?.retryPreparation(context.id) }
                context.checkOutcome = { [weak self, weak context] in guard let context else { return }; await self?.reconcile(context.id) }
                context.changed = { [weak self, weak context] in
                    if let signer = context?.signature?.signerName, context?.outcome?.isApproved == true, let self {
                        self.lastSignerName = signer
                        for pending in self.contexts.values where pending.signature == nil && !pending.submissionStarted {
                            pending.initialSignerName = signer
                        }
                    }
                    self?.objectWillChange.send()
                }
                contexts[item.key] = context
            }
        } catch is CancellationError {} catch {
            guard isCurrent else { return }
            reviewed = []; reviewedGeneration = nil; self.error = error.customerSentence(.openEstimate)
        }
    }
    private func approvalAllowed(_ item: JobEstimateReviewedItem) -> Bool {
        guard isCurrent, complete, session.can("estimate.approve", feature: "estimates"),
              TechJobFlow.canShow(item.estimate, can: abilities),
              let currentRecord = records.first(where: { $0.id == item.id }), currentRecord.status == "sent",
              currentRecord.currentRevisionNumber == item.revision.revisionNumber,
              currentRecord.locationId == item.estimate.locationId,
              let context = contexts[item.key], context.outcome?.isApproved != true else { return false }
        // An already submitted intent owns its exact prior consent and payload. Changing another
        // card cannot replace it; only explicit reconciliation can authorize an identical retry.
        return context.submissionStarted || (reviewedGeneration == selection.generation && reviewed.contains(item) && selectedIDs.contains(item.id))
    }
    private func sameJob(_ fresh: JobRecord) -> Bool {
        fresh.id == scope.jobID && fresh.organizationId == scope.organizationID && fresh.customerId == scope.customerID && fresh.locationId == jobLocationID && fresh.estimateId == scope.originEstimateID
    }
    /// Reading one estimate never selects it or prepares an approval.
    func detailsCurrent(_ record: EstimateRecord, authority: UUID) -> Bool {
        isCurrent && session.authorityRevision == authority && freshIDs.contains(record.id)
            && (record.status == "sent" || record.status == "approved") && records.contains(record)
            && scope.contains(record, requestedID: record.id)
    }

    func issuedDetails(_ record: EstimateRecord, authority: UUID) async throws -> CustomerIssuedEstimateRevision {
        func current() -> Bool { detailsCurrent(record, authority: authority) && !Task.isCancelled }
        guard current() else { throw CancellationError() }
        let fresh = try await api.liveFieldJob(scope.jobID)
        guard current() else { throw CancellationError() }
        guard sameJob(fresh) else {
            throw Problem(title: "This job changed. Ask your technician to reopen it.", status: 409, detail: nil)
        }
        try await verifyDetailMembership(record, job: fresh, current: current)
        let revision = try await api.customerIssuedEstimateRevision(for: record, allowApprovedForReading: true, currentAuthority: current)
        guard current() else { throw CancellationError() }
        let verifiedJob = try await api.liveFieldJob(scope.jobID)
        guard current() else { throw CancellationError() }
        guard current() else { throw CancellationError() }
        guard sameJob(verifiedJob) else {
            throw Problem(title: "This job's estimates changed. Ask your technician to reopen it.", status: 409, detail: nil)
        }
        try await verifyDetailMembership(record, job: verifiedJob, current: current)
        return revision
    }
    /// Prices are read from issued revisions, in a small bounded batch for the loaded page.
    /// Every request uses the existing live job, membership and authority checks.
    func loadOverviewPrices() async {
        guard overviewPriceReady else { return }
        let generation = overviewPriceGeneration
        let candidates = records.filter { record in
            guard detailsCurrent(record, authority: authorityRevision) else { return false }
            if record.status == "sent" { return revision(for: record.id) == nil }
            if record.status == "approved" { return overviewReceipt(for: record) == nil }
            return false
        }
        await withTaskGroup(of: Void.self) { group in
            var iterator = candidates.makeIterator()
            for _ in 0..<3 {
                if let record = iterator.next() {
                    group.addTask { await self.loadOverviewPrice(record, generation: generation) }
                }
            }
            while await group.next() != nil {
                guard !Task.isCancelled, overviewPriceGeneration == generation else { group.cancelAll(); break }
                if let record = iterator.next() {
                    group.addTask { await self.loadOverviewPrice(record, generation: generation) }
                }
            }
        }
    }

    func retryOverviewPrice(_ record: EstimateRecord) async {
        await loadOverviewPrice(record, generation: overviewPriceGeneration)
    }

    private func loadOverviewPrice(_ record: EstimateRecord, generation: UUID) async {
        guard overviewPriceReady, !Task.isCancelled, generation == overviewPriceGeneration,
              detailsCurrent(record, authority: authorityRevision) else { return }
        let ticket = UUID()
        overviewRequests[record.id] = ticket
        overviewPriceFailures.remove(record.id)
        defer { if overviewRequests[record.id] == ticket { overviewRequests[record.id] = nil } }
        do {
            let issued = try await issuedDetails(record, authority: authorityRevision)
            let receipt: CustomerEstimateAcceptanceReceipt?
            if record.status == "approved" {
                receipt = try await approvedReceipt(record, revision: issued, authority: authorityRevision)
            } else {
                receipt = nil
            }
            guard !Task.isCancelled, generation == overviewPriceGeneration, overviewRequests[record.id] == ticket,
                  detailsCurrent(record, authority: authorityRevision) else { return }
            revisions[record.id] = issued
            if record.status == "approved" {
                if let receipt { overviewReceipts[record.id] = receipt }
                else { overviewReceipts[record.id] = nil; overviewPriceFailures.insert(record.id) }
            }
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled, generation == overviewPriceGeneration, overviewRequests[record.id] == ticket,
                  detailsCurrent(record, authority: authorityRevision) else { return }
            revisions[record.id] = nil
            overviewReceipts[record.id] = nil
            overviewPriceFailures.insert(record.id)
        }
    }

    func overviewReceipt(for record: EstimateRecord) -> CustomerEstimateAcceptanceReceipt? {
        guard record.status == "approved", detailsCurrent(record, authority: authorityRevision),
              let revision = revisions[record.id],
              (try? revision.validate(for: record, allowApprovedForReading: true)) != nil,
              let receipt = overviewReceipts[record.id],
              (try? receipt.validate(for: revision)) != nil else { return nil }
        return receipt
    }

    func approvedReceipt(_ record: EstimateRecord, revision: CustomerIssuedEstimateRevision, authority: UUID) async throws -> CustomerEstimateAcceptanceReceipt? {
        func current() -> Bool { detailsCurrent(record, authority: authority) && !Task.isCancelled }
        guard current(), record.status == "approved" else { throw CancellationError() }
        let receipt = try await api.customerEstimateAcceptanceReceipt(for: revision, currentAuthority: current)
        guard current() else { throw CancellationError() }
        // Recheck job membership and the live revision after the receipt request.
        let checked = try await issuedDetails(record, authority: authority)
        guard current(), checked == revision else { throw CancellationError() }
        return receipt
    }
    private func verifyDetailMembership(_ record: EstimateRecord, job: JobRecord,
                                        current: @MainActor () -> Bool) async throws {
        do {
            try await JobEstimateDetailMembership.verify(jobID: scope.jobID, estimateID: record.id,
                originID: job.estimateId, isCurrent: current,
                read: { try await self.api.liveFieldJobEstimateLink(self.scope.jobID, estimateID: record.id) },
                list: { try await self.api.liveFieldJobEstimateLinks(self.scope.jobID) })
        } catch is JobEstimateDetailMembership.InvalidMembership {
            throw Problem(title: "This estimate is no longer on this job", status: 409, detail: nil)
        }
    }
    func verifyMembership(_ item: JobEstimateReviewedItem) async throws {
        guard isCurrent, approvalAllowed(item) else { throw CancellationError() }
        let fresh = try await api.liveFieldJob(scope.jobID)
        guard isCurrent, sameJob(fresh) else { retire(); throw CancellationError() }
        let links = try await api.liveFieldJobEstimateLinks(scope.jobID)
        guard isCurrent else { throw CancellationError() }
        let valid = links.filter { $0.jobId == scope.jobID }
        let ids = Set(valid.map(\.estimateId) + (fresh.estimateId.map { [$0] } ?? []))
        guard valid.count == links.count, ids.contains(item.id), ids == Set(records.map(\.id) + unavailableIDs) else {
            complete = false
            throw Problem(title: "This job's estimates changed. Refresh and review them again.", status: 409, detail: nil)
        }
    }
    private func confirm(_ item: JobEstimateReviewedItem, record supplied: EstimateRecord?) async -> JobEstimateHandoffOutcome {
        guard isCurrent else { return .unknown }
        do {
            let record: EstimateRecord
            if let supplied { record = supplied } else { record = try await api.liveFieldEstimate(item.id) }
            guard isCurrent else { return .unknown }
            guard scope.contains(record, requestedID: item.id), record.locationId == item.estimate.locationId,
                  record.currentRevisionNumber == item.revision.revisionNumber, record.status == "approved" else { return .unknown }
            if let index = records.firstIndex(where: { $0.id == record.id }) { records[index] = record }
            if item.optionID != nil, contexts[item.key]?.acceptedAction == nil { return .unknown }
            return .approved(record)
        } catch { return .unknown }
    }
    private func confirmPublic(_ item: JobEstimateReviewedItem, patch: PublicEstimateActionPatch? = nil,
                               record supplied: EstimateRecord? = nil) async -> JobEstimateHandoffOutcome {
        guard isCurrent, let context = contexts[item.key], let link = context.link else { return .unknown }
        do {
            let record: EstimateRecord
            if let supplied { record = supplied } else { record = try await api.liveFieldEstimate(item.id) }
            guard isCurrent, scope.contains(record, requestedID: item.id), record.locationId == item.estimate.locationId,
                  record.currentRevisionNumber == item.revision.revisionNumber, record.status == "approved" else { return .unknown }
            // Keep a bare approved aggregate visible even if its selected package cannot yet be proved.
            if let index = records.firstIndex(where: { $0.id == record.id }) { records[index] = record }
            let action: PublicEstimateAction
            if let patch, patch.status == .approved, patch.acceptance != nil, let decision = context.publicDecision {
                action = link.action.applying(patch, after: decision)
            } else {
                action = try await api.publicDocumentAction(token: link.token)
            }
            guard isCurrent else { return .unknown }
            guard context.retainAcceptedAction(action) else {
                if action.status == .approved, action.acceptance == nil { return .unknown }
                return .needsReview("This estimate's accepted package or terms differ. Ask your technician to review its current approval.")
            }
            return await confirm(item, record: record)
        } catch { return .unknown }
    }
    func reconcile(_ id: String) async {
        guard isCurrent, let context = contexts[id], context.outcome == .unknown, !context.running else { return }
        let item = context.reviewed
        do {
            let record = try await api.liveFieldEstimate(item.id)
            guard isCurrent, scope.contains(record, requestedID: item.id), record.locationId == item.estimate.locationId else { return }
            if record.status == "approved" {
                context.report(item.optionID == nil ? await confirm(item, record: record) : await confirmPublic(item, record: record)); return
            }
            guard record.status == "sent", record.currentRevisionNumber == item.revision.revisionNumber else {
                context.report(.needsReview("This estimate changed. Review its current terms with your technician.")); return
            }
            let revision = try await api.customerIssuedEstimateRevision(for: record, currentAuthority: { [weak self] in self?.isCurrent == true })
            guard isCurrent, revision == item.revision else { context.report(.needsReview("This estimate changed. Review it again.")); return }
            if let link = context.link, let signature = context.signature {
                let current = try await api.publicDocumentAction(token: link.token)
                guard isCurrent, current.contentHash == link.action.contentHash, current.nonce == link.action.nonce,
                      current.revisionNumber == link.action.revisionNumber,
                      current.canApprove(signerName: signature.signerName, consent: true, selectedOptionID: item.optionID) else { return }
            }
            try await verifyMembership(item)
            context.retryVerified = true
            context.changed()
        } catch { self.error = "The approval is still unconfirmed. Keep this device with your technician and refresh when connected." }
    }
    func retire(clearDocuments: Bool = true) {
        guard !retired else { return }
        if clearDocuments { documents.reset() }
        retired = true; request = UUID(); loading = false
        membershipPager = nil; pageRead = nil; canLoadMoreEstimates = false
        records = []; freshIDs = []; unavailableIDs = []; reviewed = []; revisions = [:]
        overviewPriceReady = false; overviewPricesNeedRefresh = false; overviewReceipts = [:]; overviewPriceFailures = []; overviewRequests = [:]; overviewPriceGeneration = UUID()
        jobTitle = ""; customerName = ""; lastSignerName = nil; error = nil
        endBatch()
        for context in contexts.values { context.retire() }
        contexts = [:]
    }
}

/// Approving several estimates with one signature (Paper 38C). The customer signs once; each
/// selected estimate is then approved by its own existing per-estimate approval, one at a time, in
/// the order shown. The run stops at the first estimate that is not confirmed approved, or as soon
/// as the session, workspace or approval access changes, and records what each one ended as.
/// The captured ink lives only here, for a retry of the rest while the customer stays on the screen.
@MainActor
final class JobEstimateBatchApproval: ObservableObject {
    enum ItemState: Equatable { case waiting, running, approved, stopped(String), notAttempted }
    enum Step: Equatable { case approved, stopped(String) }
    struct Capture: Equatable { let signerName: String; let png: Data }

    let order: [String]
    @Published private(set) var states: [String: ItemState]
    @Published private(set) var running = false
    @Published private(set) var stopReason: String?
    private(set) var capture: Capture?

    init(order: [String], capture: Capture) {
        self.order = order; self.capture = capture
        states = Dictionary(uniqueKeysWithValues: order.map { ($0, ItemState.waiting) })
    }

    var approvedKeys: [String] { order.filter { states[$0] == .approved } }
    var remainingKeys: [String] { order.filter { states[$0] != .approved } }
    var isComplete: Bool { !order.isEmpty && remainingKeys.isEmpty }
    var started: Bool { states.values.contains { $0 != .waiting } }
    /// A retry of the rest reuses the captured signature, so it exists only while that capture does.
    var canRetry: Bool { !running && capture != nil && started && !isComplete }

    /// Forgets the captured ink. Nothing more can be approved with it afterwards.
    func discard() { capture = nil }

    /// Approves the estimates not yet approved, in order, one at a time.
    func run(stillCurrent: @MainActor () -> Bool, approveOne: @MainActor (String, Capture) async -> Step) async {
        guard !running, capture != nil, !isComplete else { return }
        running = true; stopReason = nil
        defer { running = false }
        for (index, key) in order.enumerated() where states[key] != .approved {
            guard let capture, stillCurrent() else {
                halt(after: index - 1, reason: "Your technician needs to reopen these estimates before anything else is approved.")
                discard(); return
            }
            states[key] = .running
            switch await approveOne(key, capture) {
            case .approved: states[key] = .approved
            case .stopped(let reason):
                states[key] = .stopped(reason)
                halt(after: index, reason: reason); return
            }
            if !stillCurrent() {
                if index + 1 < order.count, order[(index + 1)...].contains(where: { states[$0] != .approved }) {
                    halt(after: index, reason: "Your technician needs to reopen these estimates before anything else is approved.")
                }
                discard(); return
            }
        }
    }

    private func halt(after index: Int, reason: String) {
        stopReason = reason
        for key in order.dropFirst(index + 1) where states[key] != .approved { states[key] = .notAttempted }
    }
}

extension JobEstimateHandoffModel {
    /// Starts one signature for the reviewed estimates. Each still gets its own approval.
    func beginBatch(signerName: String, png: Data) -> JobEstimateBatchApproval? {
        let name = signerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard approvalAuthority, reviewed.count > 1, !name.isEmpty, name.count <= 120, !png.isEmpty,
              !contexts.values.contains(where: \.running) else { return nil }
        let batch = JobEstimateBatchApproval(order: reviewed.map(\.key), capture: .init(signerName: name, png: png))
        self.batch = batch
        batchSubscription = batch.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        return batch
    }

    /// Leaving the screen, a hand-back, a lock or a session change: the captured ink is forgotten.
    func endBatch() {
        batch?.discard(); batch = nil; batchSubscription = nil
    }

    func runBatch() async {
        guard let batch else { return }
        await batch.run(stillCurrent: { [weak self] in self?.approvalAuthority == true }) { [weak self] key, capture in
            guard let self else { return .stopped("Your technician needs to reopen these estimates.") }
            return await self.approveInBatch(key, capture: capture)
        }
        objectWillChange.send()
    }

    /// One estimate of the batch, through the same per-estimate approval and checks as signing it alone.
    private func approveInBatch(_ key: String, capture: JobEstimateBatchApproval.Capture) async -> JobEstimateBatchApproval.Step {
        let changed = "Your technician needs to reopen this estimate before it can be approved."
        guard approvalAuthority, let context = contexts[key], context.current() else { return .stopped(changed) }
        if context.outcome?.isApproved == true { return .approved }
        switch context.outcome {
        case .unknown?:
            // Sent before and unconfirmed: read first, never send again unless the read proves it safe.
            await reconcile(key)
            if context.outcome?.isApproved == true { return .approved }
            guard context.outcome == .unknown, context.retryVerified else { return .stopped(Self.batchReason(context.outcome)) }
        case .retryable?:
            await retryPreparation(key)
            guard context.outcome == nil else { return .stopped(Self.batchReason(context.outcome)) }
        case .needsReview(let reason)?: return .stopped(reason)
        case .approved?, nil: break
        }
        guard approvalAuthority, context.canApprove() else { return .stopped(changed) }
        let drawn = (context.reviewed.revision.options ?? []).isEmpty
        final class Flag { var value = false }
        let cannotSign = Flag()
        let ran = await context.perform { [weak self, weak context] in
            guard let self, let context else { return }
            do {
                let sent = try await context.submitApproval(api: self.api, jobID: self.scope.jobID, signer: capture.signerName,
                                                            png: { capture.png }, drawn: drawn,
                                                            stillCurrent: { [weak self] in self?.approvalAuthority == true })
                cannotSign.value = sent == .cannotSign
            } catch is CancellationError {
            } catch { context.reportApprovalFailure(error) }
        }
        if context.outcome?.isApproved == true { return .approved }
        if cannotSign.value { return .stopped("This estimate can't be signed here. Ask your technician.") }
        return .stopped(ran ? Self.batchReason(context.outcome) : changed)
    }

    static func batchReason(_ outcome: JobEstimateHandoffOutcome?) -> String {
        switch outcome {
        case .unknown?: return "This approval may have been received. It needs to be checked before trying again."
        case .retryable(let reason)?, .needsReview(let reason)?: return reason
        case .approved?: return ""
        case nil: return "This estimate wasn't approved."
        }
    }

    /// Before anyone signs: each package estimate's own customer link, so its consent words, nonce
    /// and content are known. The consent the customer reads is the links' one shared text.
    func prepareBatch() async throws -> String? {
        var consent: String?
        for item in reviewed {
            guard approvalAuthority, let context = contexts[item.key], context.canApprove() else { throw CancellationError() }
            guard !(item.revision.options ?? []).isEmpty else { continue }
            if context.link == nil {
                try await context.validate()
                let opened = try await api.openInPersonEstimateApproval(item.revision, currentAuthority: { [weak self, weak context] in
                    self?.approvalAuthority == true && context?.canApprove() == true
                })
                try Task.checkCancellation()
                guard approvalAuthority, context.canApprove() else { throw CancellationError() }
                context.link = opened
            }
            guard let text = context.link?.action.consentText, consent == nil || consent == text else {
                throw Problem(title: "These estimates can't be signed together. Approve them one at a time.", status: 409, detail: nil)
            }
            consent = text
        }
        return consent
    }
}

extension JobEstimateHandoffOutcome {
    var isApproved: Bool { if case .approved = self { return true }; return false }
}


/// Optional handoff observation without changing the standalone estimate initializer contract.
@MainActor
final class CustomerEstimateHandoffObservation: ObservableObject {
    let context: CustomerEstimateHandoffContext?
    private var subscription: AnyCancellable?
    init(_ context: CustomerEstimateHandoffContext?) {
        self.context = context
        subscription = context?.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }
}

/// Where Customer view opens: its home, or straight on one of its sections or documents.
enum CustomerViewStart: Equatable {
    case home
    /// The job's estimates, ready to select and approve.
    case estimates
    case estimate(String)
    case invoice(String)
    case details
}

/// How the technician left Customer view: back to staff, or straight to collecting an invoice.
enum CustomerViewExit: Equatable {
    case done
    case collect(invoiceID: String)
}

/// Retains this one protected customer handoff ("Customer view") above workspace and authentication
/// branches: the job's estimates, invoices and the customer's own details, with one staff hand-back.
@MainActor
struct CustomerHandoffExitAuthority {
    let actor: String, organization: String, origin: String
    let sessionGeneration: UUID, authorityRevision: UUID, requestGeneration: UUID, scopeRevision: UUID

    @MainActor static func capture(api: APIClient, session: SessionController) -> Self? {
        guard session.phase == .ready, let actor = session.user?.id,
              let organization = session.activeOrganization?.id, let origin = api.normalizedOrigin else { return nil }
        return .init(actor: actor, organization: organization, origin: origin,
                     sessionGeneration: session.generation, authorityRevision: session.authorityRevision,
                     requestGeneration: api.requestGeneration, scopeRevision: api.savedCopyScopeRevision)
    }

    @MainActor func isCurrent(api: APIClient, session: SessionController) -> Bool {
        session.phase == .ready && session.user?.id == actor && session.activeOrganization?.id == organization &&
        session.generation == sessionGeneration && session.authorityRevision == authorityRevision &&
        api.requestGeneration == requestGeneration &&
        api.savedCopyScopeRevision == scopeRevision && api.normalizedOrigin == origin
    }
}

@MainActor
final class JobEstimateHandoffPresenter: ObservableObject {
    private let arbiter: CustomerHandoffArbiter
    private let sceneWindow: CustomerProtectedSceneWindow?
    private var sceneOwnerID: UUID?
    @Published private(set) var usesSceneWindow = false
    init(arbiter: CustomerHandoffArbiter = CustomerHandoffArbiter(), sceneWindow: CustomerProtectedSceneWindow? = nil) {
        self.arbiter = arbiter; self.sceneWindow = sceneWindow
    }
    func claimLegacy() -> LegacyCustomerHandoffLease? {
        let id = UUID()
        guard arbiter.claim(.legacy(id)) else { return nil }
        return LegacyCustomerHandoffLease(arbiter: arbiter, id: id)
    }
    var idleRevision: UUID? { arbiter.owner == nil ? arbiter.revision : nil }
    func isIdleRevision(_ revision: UUID) -> Bool { arbiter.owner == nil && arbiter.revision == revision }
    @Published private(set) var active: JobEstimateHandoffModel?
    private(set) var start: CustomerViewStart = .estimates
    /// The customer's own details, when this person may edit customers.
    private(set) var details: CustomerSelfEditModel?
    /// The session generation the job's documents were read under.
    private(set) var sourceGeneration: UUID?
    private(set) var invoiceUpdated: (InvoiceRecord) -> Void = { _ in }
    private var onAuthenticatedExit: (@MainActor (CustomerViewExit) async -> Void)?
    private var exitAuthority: CustomerHandoffExitAuthority?

    @discardableResult func present(_ model: JobEstimateHandoffModel, onAuthenticatedExit: @escaping @MainActor () async -> Void) -> Bool {
        present(model, start: .estimates) { _ in await onAuthenticatedExit() }
    }

    @discardableResult func present(_ model: JobEstimateHandoffModel, start: CustomerViewStart, details: CustomerSelfEditModel? = nil,
                 sourceGeneration: UUID? = nil, invoiceUpdated: @escaping (InvoiceRecord) -> Void = { _ in },
                 sourceWindow: UIWindow? = nil,
                 onExit: @escaping @MainActor (CustomerViewExit) async -> Void) -> Bool {
        guard active == nil, model.isCurrentJob,
              let authority = CustomerHandoffExitAuthority.capture(api: model.api, session: model.session),
              arbiter.claim(.documents) else { return false }
        exitAuthority = authority
        self.start = start; self.details = details
        self.sourceGeneration = sourceGeneration ?? model.session.generation
        self.invoiceUpdated = invoiceUpdated
        usesSceneWindow = sceneWindow != nil && sourceWindow != nil
        active = model; self.onAuthenticatedExit = onExit
        if usesSceneWindow, let sceneWindow {
            let id = UUID(); sceneOwnerID = id
            let content = AnyView(JobEstimateProtectedOwner(model: model, presenter: self)
                .environmentObject(model.api).environmentObject(model.session))
            guard sceneWindow.present(id: id, source: sourceWindow, content: content, onDisconnect: { [weak self, weak model] in
                guard let self, let model, self.active === model else { return }
                self.finishExit(.done, runCallback: false)
            }) else { finishExit(.done, runCallback: false); return false }
        }
        return true
    }

    func authenticatedExit(from model: JobEstimateHandoffModel, _ exit: CustomerViewExit = .done) {
        guard active === model else { return }
        authenticatedExit(exit)
    }

    func authenticatedExit(_ exit: CustomerViewExit = .done) {
        if let sceneWindow, let sceneOwnerID {
            sceneWindow.dismiss(id: sceneOwnerID) { [weak self] restored in self?.finishExit(exit, runCallback: restored) }
        } else { finishExit(exit, runCallback: true) }
    }

    private func finishExit(_ exit: CustomerViewExit, runCallback: Bool) {
        let refresh = onAuthenticatedExit, model = active, authority = exitAuthority
        let valid = runCallback && (model.map { $0.isCurrentJob && authority?.isCurrent(api: $0.api, session: $0.session) == true } ?? false)
        active?.retire(clearDocuments: false); active = nil; onAuthenticatedExit = nil
        exitAuthority = nil; sceneOwnerID = nil; usesSceneWindow = false
        arbiter.release(.documents)
        let exitRevision = arbiter.revision
        details = nil; invoiceUpdated = { _ in }; start = .estimates
        if valid, let model, let authority {
            Task {
                guard self.isIdleRevision(exitRevision), authority.isCurrent(api: model.api, session: model.session) else { return }
                await refresh?(exit)
            }
        }
    }
}

extension JobEstimateHandoffPresenter {
    enum OpenResult { case presented, unavailable, superseded }
    /// Estimate and invoice detail's "Show to customer": Customer view on the document's own job,
    /// read fresh and checked against this workspace and customer. False when there is no verified
    /// job (the caller keeps its single-document presentation).
    func openCustomerView(jobID: String, customerID: String, customerName: String, start: CustomerViewStart,
                          api: APIClient, session: SessionController,
                          sourceWindow: UIWindow? = nil,
                          sourceStillAttached: @escaping @MainActor () -> Bool = { true },
                          onExit: @escaping @MainActor (CustomerViewExit) async -> Void) async -> OpenResult {
        guard active == nil, arbiter.owner == nil else { return .superseded }
        let handoffRevision = arbiter.revision
        guard let authority = CustomerHandoffExitAuthority.capture(api: api, session: session) else { return .superseded }
        guard session.can("job.view", feature: "jobs") else { return .unavailable }
        let job = try? await api.fieldJob(jobID)
        guard !Task.isCancelled, sourceStillAttached(), active == nil, arbiter.owner == nil, arbiter.revision == handoffRevision,
              authority.isCurrent(api: api, session: session), session.can("job.view", feature: "jobs") else { return .superseded }
        guard let job, job.id == jobID, job.organizationId == session.activeOrganization?.id,
              job.customerId == customerID else { return .unavailable }
        let model = JobEstimateHandoffModel(job: job, customerName: customerName, documents: JobDocumentCollections(), api: api, session: session)
        let details = session.can("customer.edit", feature: "core_crm") ? CustomerSelfEditModel(customerID: job.customerId) : nil
        present(model, start: start, details: details, sourceWindow: sourceWindow, onExit: onExit)
        return active === model ? .presented : .superseded
    }
}

@MainActor
func customerEstimatePreparationCanRetry(_ error: Error) -> Bool {
    if let problem = error as? Problem, problem.title == MediaTransfer.storageUploadFailureTitle {
        return MediaTransfer.isRetryableStorageUploadFailure(error)
    }
    return error.isConnectivityFailure || error.isTransientServerFailure
}

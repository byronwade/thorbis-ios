import SwiftUI

/// The estimate builder for a new estimate (EB-01..EB-14): one search field over the whole
/// price book at the top, tap to add, lines in Work and Materials edited where they sit,
/// optionally for a job, which the estimate is linked to after creation.
struct NewEstimateView: View {
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var store: Store
    @EnvironmentObject var session: SessionController
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var catalog = PriceBookCatalog.shared
    @State private var title: String
    @State private var customerID: String
    @State private var lines: [EstimateRevisionLineDraft] = []
    #if DEBUG
    @State private var previewPresentationReady = false
    #endif
    @State private var busy = false
    @State private var error: String?
    @State private var originalScope: EstimateCreationScope?
    @State private var scopeCaptured = false
    @State private var draftRecoveryBlocked = false
    @State private var createInFlight = false
    @State private var draftOwner = UUID()
    @State private var ownsDraft = false
    @State private var viewVisible = false
    @State private var didRestoreDraft = false
    @State private var didRecoverDraft = false
    @State private var wroteFreshDraft = false
    @State private var verifiedScope: EstimateCreationScope?
    @State private var accessAttempt = UUID()
    @State private var verifiedCustomerID: String?
    @State private var verifiedCreatedID: String?
    @State private var changedSavedEstimate: EstimateRecord?
    @State private var changedSavedEstimateScope: EstimateCreationScope?
    @State private var showChangedSavedEstimate = false
    @State private var confirmUseChangedSavedEstimate = false
    @State private var changedReviewProblem: String?
    @State private var intentionallyDiscarded = false
    @State private var cleanupFailedAfterSave = false
    @State private var picker: EstimateBuilderTarget?
    @State private var expandedLine: UUID?
    @State private var revealProblem = 0
    @State private var keyboardUp = false
    @State private var removed: RemovedLine?
    @State private var confirmDiscard = false
    @FocusState private var focus: EstimateBuilderFocus?
    /// Set once the server created the estimate, so a retry only links it and never creates a duplicate.
    @State private var created: EstimateRecord?
    @State private var createdScope: EstimateCreationScope?
    @State private var requiresLocationVerification = false
    @State private var requiresManualReview = false
    @State private var requiresGroupDisclosure = false
    @State private var acceptedGroupLoss = false
    @State private var confirmGroupLoss = false
    @State private var createOutcomeUncertain = false
    @State private var memberPricing: MemberPricing?
    /// Shown after Save is pressed (validate on commit): what is missing, under its place.
    @State private var titleProblem: String?
    @State private var customerProblem: String?
    @State private var linesProblem: String?
    @State private var descriptionProblem: String?
    private let jobID: String?
    private let jobLocationID: String?
    private let initialCustomerID: String
    private let initialTitle: String
    private let draftDocumentKey: String
    private let onCreated: (EstimateRecord) -> Void

    init(customerID: String = "", jobID: String? = nil, locationID: String? = nil, title: String = "", onCreated: @escaping (EstimateRecord) -> Void = { _ in }) {
        _customerID = State(initialValue: customerID)
        _title = State(initialValue: title)
        self.jobID = jobID
        self.jobLocationID = jobID == nil ? nil : locationID
        self.initialCustomerID = customerID
        self.initialTitle = title
        self.draftDocumentKey = "job:\(jobID ?? "")|customer:\(customerID)|location:\(locationID ?? "")"
        self.onCreated = onCreated
    }

    private var canUsePriceBook: Bool { session.can("pricebook.view", feature: "price_book") }
    /// EB-13: the workspace stores line groups and the materials switch.
    private var storesLineGroups: Bool { session.isFeatureOn("estimate_line_groups") }
    private var total: Int? { lines.isEmpty ? nil : lines.subtotal() }
    private var editableLines: Binding<[EstimateRevisionLineDraft]> {
        Binding(get: { lines }, set: { proposed in
            guard recovery.canEdit else { return }
            lines = proposed
        })
    }
    private var creationScope: EstimateCreationScope? {
        guard session.phase == .ready, let actor = session.user?.id,
              let organization = session.activeOrganization?.id, let origin = api.normalizedOrigin else { return nil }
        return .init(actorID: actor, organizationID: organization, sessionGeneration: session.generation, authorityRevision: session.authorityRevision,
                     requestGeneration: api.requestGeneration, origin: origin)
    }
    private var scopeMatches: Bool {
        guard let originalScope, let creationScope else { return false }
        return originalScope.sameIdentityAndTransport(as: creationScope)
    }
    private struct DraftCheckKey: Equatable {
        let scope: EstimateCreationScope?
        let customer: String
        let created: String?
        let offline: Bool
        let ownsDraft: Bool
    }
    private var draftCheckKey: DraftCheckKey { .init(scope: creationScope, customer: customerID, created: created?.id, offline: session.isOffline, ownsDraft: ownsDraft) }
    private var canOpenDraft: Bool {
        session.can("estimate.create", feature: "estimates") ||
            (session.can("estimate.view", feature: "estimates") &&
             (jobID == nil || (session.can("job.view", feature: "jobs") && session.can("job.edit", feature: "jobs"))))
    }
    private func openDraft() {
        viewVisible = true
        if !scopeCaptured { scopeCaptured = true; originalScope = creationScope }
        guard scopeMatches, canOpenDraft, let draftScope else { return }
        guard CommercialDraftStore.shared.acquire(scope: draftScope, owner: draftOwner) else {
            draftRecoveryBlocked = true; error = "This draft is already open in another window."; return
        }
        ownsDraft = true
        if !didRestoreDraft { didRestoreDraft = true; restoreDraft() }
        if !didRecoverDraft && !draftRecoveryBlocked {
            verifiedScope = creationScope; verifiedCustomerID = customerID; verifiedCreatedID = created?.id
        }
    }
    private var recoveryPermission: Bool {
        if created != nil {
            return session.can("estimate.view", feature: "estimates") &&
                (jobID == nil || (session.can("job.view", feature: "jobs") && session.can("job.edit", feature: "jobs")))
        }
        return session.can("estimate.create", feature: "estimates")
    }
    private var resourceAuthorized: Bool {
        guard let creationScope else { return false }
        return (!didRecoverDraft || !session.isOffline) && scopeMatches && verifiedScope == creationScope &&
            (!didRecoverDraft || (verifiedCustomerID == customerID && verifiedCreatedID == created?.id)) &&
            recoveryPermission && !draftRecoveryBlocked
    }
    private var draftScope: CommercialDraftScope? {
        guard let originalScope else { return nil }
        return .init(actor: originalScope.actorID, organization: originalScope.organizationID,
                     origin: originalScope.origin, kind: "new-estimate", document: draftDocumentKey)
    }
    private func saveDraft(uncertain: Bool? = nil, leavingOriginalScope: Bool = false) throws {
        guard ownsDraft, (scopeMatches || leavingOriginalScope), let draftScope else { throw CancellationError() }
        let draft = CommercialNewEstimateDraft(customerID: customerID, title: title, lines: lines,
            uncertain: uncertain ?? (createInFlight || createOutcomeUncertain), created: created,
            requiresLocationVerification: requiresLocationVerification, requiresManualReview: requiresManualReview,
            requiresGroupDisclosure: requiresGroupDisclosure, acceptedGroupLoss: acceptedGroupLoss)
        try CommercialDraftStore.shared.save(draft, scope: draftScope)
    }
    private var hasDraftChanges: Bool {
        title != initialTitle || customerID != initialCustomerID || !lines.isEmpty
    }
    private var needsDiscardConfirmation: Bool {
        hasDraftChanges || didRecoverDraft || wroteFreshDraft || draftRecoveryBlocked
    }
    private func persistDraft(leavingOriginalScope: Bool = false) {
        guard !intentionallyDiscarded, ownsDraft, didRestoreDraft, (scopeMatches || leavingOriginalScope), !draftRecoveryBlocked else { return }
        if !didRecoverDraft && !hasDraftChanges && created == nil && !createInFlight && !createOutcomeUncertain {
            guard wroteFreshDraft, let draftScope else { return }
            do { try CommercialDraftStore.shared.remove(scope: draftScope); wroteFreshDraft = false }
            catch { self.error = "The undone draft could not be removed from this phone. Try again before closing." }
            return
        }
        do {
            try saveDraft(leavingOriginalScope: leavingOriginalScope)
            if !didRecoverDraft { wroteFreshDraft = true }
        } catch { self.error = "This draft could not be saved on this phone. Keep this screen open and try again." }
    }
    private func restoreDraft() {
        guard scopeMatches, let draftScope else { return }
        do {
            guard let draft = try CommercialDraftStore.shared.load(CommercialNewEstimateDraft.self, scope: draftScope) else { return }
            didRecoverDraft = true
            let recoveredLines = try draft.lines()
            customerID = draft.customerID; title = draft.title; lines = recoveredLines
            created = draft.created; createdScope = draft.created == nil ? nil : originalScope
            createOutcomeUncertain = draft.uncertain
            requiresLocationVerification = draft.requiresLocationVerification; requiresManualReview = draft.requiresManualReview
            requiresGroupDisclosure = draft.requiresGroupDisclosure; acceptedGroupLoss = draft.acceptedGroupLoss
            if draft.uncertain {
                error = draft.created == nil
                    ? "The previous save could not be confirmed. Check Estimates or ask your office before starting another. Your draft is still here."
                    : "The job link could not be confirmed. Retry to check the saved estimate and job."
            }
        } catch { draftRecoveryBlocked = true; self.error = "Your saved draft could not be opened. It is still on this phone." }
    }
    private func verifyDraftAccess() async {
        guard !Task.isCancelled else { return }
        accessAttempt = UUID()
        changedSavedEstimate = nil; changedSavedEstimateScope = nil; showChangedSavedEstimate = false; confirmUseChangedSavedEstimate = false
        guard viewVisible, ownsDraft, scopeMatches, let expected = creationScope, recoveryPermission else { return }
        if !didRecoverDraft && verifiedScope == expected && verifiedCustomerID == customerID && verifiedCreatedID == created?.id { return }
        guard !session.isOffline else { return }
        let attempt = UUID(); accessAttempt = attempt
        let expectedCustomer = customerID
        let expectedCreated = created
        let expectedID = expectedCreated?.id
        #if DEBUG
        if EstimateRecoveryPreview.enabled { EstimateRecoveryPreview.shared.record(expectedID == nil ? "verify-new" : "verify-saved") }
        #endif
        var changedEstimate: EstimateRecord?
        let allowed = await CommercialDraftAccess.verify(expectedScope: expected, currentScope: {
            guard !session.isOffline, customerID == expectedCustomer, created?.id == expectedID, recoveryPermission else { return nil }
            return creationScope
        }, read: {
            let job: JobRecord?
            if let jobID { job = try await api.fieldJob(jobID, requireFresh: true) } else { job = nil }
            let customer = expectedCustomer.isEmpty ? nil : try await api.fieldCustomer(expectedCustomer, requireFresh: true)
            let estimate: EstimateRecord?
            if let expectedCreated { estimate = try await api.fieldEstimate(expectedCreated.id, requireFresh: true) } else { estimate = nil }
            return (job, customer, estimate)
        }, matches: { result in
            let (job, customer, estimate) = result
            if let jobID {
                guard let job, job.id == jobID, job.organizationId == expected.organizationID,
                      (expectedCustomer.isEmpty || job.customerId == expectedCustomer),
                      (jobLocationID == nil || job.locationId == jobLocationID) else { return false }
            }
            if !expectedCustomer.isEmpty {
                guard let customer, customer.id == expectedCustomer, customer.organizationId == expected.organizationID else { return false }
            }
            if let saved = expectedCreated {
                guard let estimate, estimate.id == saved.id, estimate.organizationId == expected.organizationID else { return false }
                guard EstimateCreationRecovery.matchesSavedEstimate(saved, latest: estimate) else {
                    changedEstimate = estimate
                    return false
                }
            }
            return true
        })
        guard !Task.isCancelled, viewVisible, accessAttempt == attempt, !session.isOffline, creationScope == expected,
              customerID == expectedCustomer, created?.id == expectedID else { return }
        guard allowed else {
            verifiedScope = nil
            if let changedEstimate, session.can("estimate.view", feature: "estimates") {
                changedSavedEstimate = changedEstimate
                changedSavedEstimateScope = expected
                error = "The saved estimate changed. Review it before deciding what to do. Your draft stays on this phone."
            } else {
                error = "Could not verify access to this job, customer or estimate. Your draft stays on this phone."
            }
            return
        }
        if error == "Could not verify access to this job, customer or estimate. Your draft stays on this phone." { error = nil }
        verifiedCustomerID = expectedCustomer; verifiedCreatedID = expectedID; verifiedScope = expected
    }
    private func discardDraft() {
        guard ownsDraft, scopeMatches, let draftScope else { dismiss(); return }
        if createOutcomeUncertain || createInFlight { dismiss(); return }
        do { try CommercialDraftStore.shared.remove(scope: draftScope); intentionallyDiscarded = true; dismiss() }
        catch { self.error = "The saved draft could not be removed. Try again." }
    }
    private var canCommit: Bool {
        if !resourceAuthorized || !ownsDraft || cleanupFailedAfterSave { return false }
        if (createOutcomeUncertain && created == nil) || requiresManualReview { return false }
        if created != nil {
            let canView = session.can("estimate.view", feature: "estimates")
            return jobID == nil ? canView : canView && session.can("job.edit", feature: "jobs")
        }
        return session.can("estimate.create", feature: "estimates")
    }
    private var recovery: EstimateCreationRecovery {
        .init(isSaving: busy, savedEstimateID: created?.id, createOutcomeUncertain: createOutcomeUncertain)
    }

    var valid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !customerID.isEmpty && !lines.isEmpty &&
        CommercialDescriptionPolicy.problem(lines.map(\.description), kind: .estimate,
            capabilityVerified: session.isFeatureOn("commercial_extended_descriptions") && !session.isOffline) == nil &&
        lines.allSatisfy { line in
            line.estimateDescriptionProblem(allowExtended: session.isFeatureOn("commercial_extended_descriptions") && !session.isOffline) == nil &&
            (Int(line.quantity.trimmingCharacters(in: .whitespacesAndNewlines)).map { (1...100_000).contains($0) } ?? false) &&
            MoneyInput.cents(line.unitPrice) != nil
        }
    }

    var body: some View {
        NavigationStack { editorContainer }
    }

    private var editorBase: some View {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        if !resourceAuthorized {
                            VStack {
                                if changedSavedEstimate != nil && changedSavedEstimateScope == creationScope && session.can("estimate.view", feature: "estimates") {
                                    ContentUnavailableView("The saved estimate changed", systemImage: "doc.text.magnifyingglass", description: Text("Review the saved estimate before deciding what to do. Your draft stays on this phone."))
                                    Button("Review saved estimate") { showChangedSavedEstimate = true }.buttonStyle(.bordered)
                                } else {
                                    ContentUnavailableView("Document unavailable", systemImage: "lock", description: Text(error ?? "Connect to verify access. Your draft stays on this phone."))
                                }
                                if scopeMatches && ownsDraft && !draftRecoveryBlocked {
                                    Button("Try again") { Task { await verifyDraftAccess() } }.buttonStyle(.bordered)
                                }
                            }
                        } else { builder }
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: focus) { _, value in
                        guard let id = value?.lineID else { return }
                        expandedLine = id
                        withAnimation { proxy.scrollTo(id, anchor: .center) }
                    }
                    .onChange(of: expandedLine) { _, id in
                        guard let id else { return }
                        withAnimation { proxy.scrollTo(id, anchor: .center) }
                    }
                    .onChange(of: revealProblem) { _, _ in
                        guard let id = expandedLine else { return }
                        withAnimation { proxy.scrollTo(id, anchor: .center) }
                    }
                }
                if resourceAuthorized { builderFooter }
            }
            .keyboardDoneButton()
            .onAppear { openDraft() }
            #if DEBUG
            .background {
                if ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-wait-presentation") {
                    EstimatePresentationObserver { previewPresentationReady = true }
                }
            }
            #endif
            .task(id: draftCheckKey) { await verifyDraftAccess() }
            .onChange(of: session.isOffline) { _, offline in
                if offline {
                    accessAttempt = UUID(); changedSavedEstimate = nil; changedSavedEstimateScope = nil; showChangedSavedEstimate = false; confirmUseChangedSavedEstimate = false
                    if didRecoverDraft { verifiedScope = nil }
                }
            }
            .onChange(of: creationScope) { _, scope in
                if changedSavedEstimateScope != scope { changedSavedEstimate = nil; changedSavedEstimateScope = nil; showChangedSavedEstimate = false; confirmUseChangedSavedEstimate = false }
            }
            .onDisappear { viewVisible = false; accessAttempt = UUID(); changedSavedEstimate = nil; changedSavedEstimateScope = nil; showChangedSavedEstimate = false; confirmUseChangedSavedEstimate = false; if !busy { persistDraft(leavingOriginalScope: true); releaseDraft() } }
            .sheet(isPresented: $showChangedSavedEstimate) {
                if let estimate = changedSavedEstimate, changedSavedEstimateScope == creationScope,
                   session.can("estimate.view", feature: "estimates") {
                    changedEstimateReview(estimate)
                } else {
                    ContentUnavailableView("Document unavailable", systemImage: "lock")
                }
            }
            .trackKeyboard($keyboardUp)
            .background(Theme.canvas)
            .foregroundStyle(Theme.foreground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                #if DEBUG
                if EstimateRecoveryPreview.enabled {
                    ThorbisToolbarItem(placement: .principal) {
                        HStack {
                            TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                                VStack {
                                    if ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-wait-presentation"), previewPresentationReady {
                                        Text("Presentation ready").accessibilityIdentifier("estimate-presentation-ready")
                                    }
                                    Text("Sample requests")
                                        .accessibilityIdentifier("estimate-recovery-request-counts")
                                        .accessibilityValue(EstimateRecoveryPreview.shared.counts)
                                    if ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-create-hold") || ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-recovery-trace") {
                                        Text("Sample trace")
                                            .accessibilityIdentifier("estimate-recovery-event-trace")
                                            .accessibilityValue(EstimateRecoveryPreview.shared.eventTrace)
                                    }
                                    if ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-dismiss-held") {
                                        Text("Sample dismissal evidence").accessibilityIdentifier("estimate-dismissal-evidence")
                                            .accessibilityValue(EstimateRecoveryPreview.shared.dismissalEvidence)
                                    }
                                    if ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-create-hold") || ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-hold-initial-estimate") || ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-hold-initial-job") {
                                        Text("Sample hold")
                                            .accessibilityIdentifier("estimate-recovery-hold-state")
                                            .accessibilityValue(EstimateRecoveryPreview.shared.reloadHoldState)
                                    }
                                }
                            }
                            if ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-recovery-toggle-offline") {
                                Text(session.isOffline ? "Sample offline" : "Sample online")
                                    .accessibilityIdentifier("estimate-recovery-network-state")
                                Button("Toggle sample network") {
                                    PaperPreviewProtocol.simulateNoSignal.toggle()
                                    Task { await session.revalidate() }
                                }.accessibilityIdentifier("estimate-recovery-toggle-network")
                            }
                            if ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-recovery-change-again") {
                                Button("Change sample estimate again") { EstimateRecoveryPreview.shared.advanceEstimateRevision() }
                                    .accessibilityIdentifier("estimate-recovery-change-again")
                            }
                            if ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-recovery-toggle-job") {
                                Button("Toggle sample job access") {
                                    EstimateRecoveryPreview.shared.toggleJobAccess()
                                    Task { await session.revalidate() }
                                }
                                .accessibilityIdentifier("estimate-recovery-toggle-job")
                            }
                            if ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-dismiss-held") {
                                Button("Close sample while held") {
                                    dismiss()
                                    Task {
                                        try? await Task.sleep(for: .seconds(1))
                                        EstimateRecoveryPreview.shared.release()
                                    }
                                }.accessibilityIdentifier("estimate-dismiss-while-held")
                            }
                            if !ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-dismiss-held") && (ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-hold-initial-estimate") || ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-hold-initial-job")) {
                                Button("Refresh and release sample") {
                                    Task {
                                        await session.revalidate()
                                        EstimateRecoveryPreview.shared.release()
                                    }
                                }.accessibilityIdentifier("estimate-release-initial-read")
                            }
                            if ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-create-hold") {
                                Button("Revalidate sample") {
                                    Task {
                                        await session.revalidate()
                                        if ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-recovery-delay-release") {
                                            try? await Task.sleep(for: .seconds(3))
                                        }
                                        EstimateRecoveryPreview.shared.release()
                                    }
                                }
                            }
                        }
                    }
                }
                #endif
                ThorbisToolbarItem(placement: .cancellationAction) {
                    Button(created == nil ? "Cancel" : "Close") { if created != nil { dismiss() } else if needsDiscardConfirmation { confirmDiscard = true } else { dismiss() } }.disabled(busy)
                }
            }

    }

    private func changedEstimateReview(_ estimate: EstimateRecord) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(estimate.title).font(Theme.font(22, weight: .medium))
                    if let changedReviewProblem { ErrorBanner(message: changedReviewProblem) }
                    Text("Check whether this estimate is linked to the job before continuing.").foregroundStyle(Theme.subtle)
                    Text("Status: \(estimate.status.statusLabel)").foregroundStyle(Theme.subtle)
                    ForEach(estimate.lines) { line in changedEstimateLine(line) }
                    if let currency = estimate.lines.first?.unitPrice.currency,
                       let amounts = CustomerDocumentAmounts(lines: estimate.lines, currency: currency) {
                        Text("Line subtotal: \(money(amounts.subtotal, currency: currency))")
                        if amounts.credits != 0 {
                            Text("Credits and discounts: \(money(amounts.credits, currency: currency))")
                        }
                        Text("Line total: \(money(amounts.total, currency: currency))").font(Theme.font(17, weight: .medium))
                    } else if !estimate.lines.isEmpty {
                        Text("Line total unavailable. Check the saved estimate for its full breakdown.").foregroundStyle(Theme.subtle)
                    }
                    ForEach(estimate.options ?? []) { option in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(option.title).font(Theme.font(17, weight: .medium))
                            if !option.description.isEmpty { Text(option.description).fixedSize(horizontal: false, vertical: true) }
                            ForEach(option.lines) { line in changedEstimateLine(line) }
                            Text("Option total: \(money(option.totalAmount, currency: option.currency))").foregroundStyle(Theme.subtle)
                        }
                    }
                    if canUseChangedSavedEstimate(estimate) {
                        Button("Use this saved estimate") { confirmUseChangedSavedEstimate = true }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Text("Ask your office to review this estimate before adding it to the job.").foregroundStyle(Theme.subtle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.gutter)
            }
            .navigationTitle("Saved estimate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ThorbisToolbarItem(placement: .cancellationAction) { Button("Done") { showChangedSavedEstimate = false } }
                #if DEBUG
                if EstimateRecoveryPreview.enabled && ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-recovery-review-scope") {
                    ThorbisToolbarItem(placement: .primaryAction) {
                        Button("Revoke sample job") {
                            EstimateRecoveryPreview.shared.toggleJobAccess()
                            Task { await session.revalidate() }
                        }
                    }
                }
                if EstimateRecoveryPreview.enabled && ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-recovery-review-offline") {
                    ThorbisToolbarItem(placement: .primaryAction) {
                        Button("Disconnect sample") {
                            PaperPreviewProtocol.simulateNoSignal = true
                            Task { await session.revalidate() }
                        }
                    }
                }
                #endif
            }
            .thorbisConfirm("Use this saved estimate?", message: "The saved estimate changed. Use its current terms for a later retry?", isPresented: $confirmUseChangedSavedEstimate,
                            actions: [ThorbisConfirmAction("Use saved estimate") { useChangedSavedEstimate(estimate) }])
        }
    }

    private func canUseChangedSavedEstimate(_ latest: EstimateRecord) -> Bool {
        guard let saved = created, let expected = changedSavedEstimateScope,
              viewVisible, !session.isOffline, ownsDraft, creationScope == expected, scopeMatches,
              session.can("estimate.view", feature: "estimates"), recoveryPermission,
              saved.id == latest.id, saved.organizationId == latest.organizationId,
              saved.customerId == latest.customerId, saved.locationId == latest.locationId,
              saved.createdByUserId == latest.createdByUserId else { return false }
        return true
    }

    private func useChangedSavedEstimate(_ latest: EstimateRecord) {
        guard canUseChangedSavedEstimate(latest), changedSavedEstimate == latest,
              let expected = changedSavedEstimateScope else {
            showChangedSavedEstimate = false
            error = "Your access changed. Your draft stays on this phone."
            return
        }
        let previous = created
        created = latest
        do {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-recovery-review-save-fails") {
                throw CocoaError(.fileWriteNoPermission)
            }
            #endif
            try saveDraft()
        } catch {
            created = previous
            changedReviewProblem = "The reviewed estimate could not be saved on this phone. Your original draft is still here."
            return
        }
        changedReviewProblem = nil
        createdScope = expected
        verifiedScope = expected; verifiedCustomerID = customerID; verifiedCreatedID = latest.id
        changedSavedEstimate = nil; changedSavedEstimateScope = nil; showChangedSavedEstimate = false; confirmUseChangedSavedEstimate = false
        error = "Saved estimate reviewed. Retry adding it to the job when ready."
    }

    private func showChangedEstimateFromRetry(_ latest: EstimateRecord, saved: EstimateRecord, scope: EstimateCreationScope) async {
        guard latest.id == saved.id, latest.organizationId == scope.organizationID,
              viewVisible, !session.isOffline, creationScope == scope, recoveryPermission else { return }
        do {
            if let jobID {
                let job = try await api.fieldJob(jobID, requireFresh: true)
                guard job.id == jobID, job.organizationId == scope.organizationID,
                      (customerID.isEmpty || job.customerId == customerID),
                      (jobLocationID == nil || job.locationId == jobLocationID) else { return }
            }
            if !customerID.isEmpty {
                let customer = try await api.fieldCustomer(customerID, requireFresh: true)
                guard customer.id == customerID, customer.organizationId == scope.organizationID else { return }
            }
            guard !Task.isCancelled, viewVisible, !session.isOffline, creationScope == scope,
                  recoveryPermission, session.can("estimate.view", feature: "estimates"), created?.id == saved.id else { return }
            verifiedScope = nil
            changedSavedEstimate = latest; changedSavedEstimateScope = scope
            error = "The saved estimate changed. Review it before deciding what to do. Your draft stays on this phone."
        } catch is CancellationError {
        } catch {
            guard viewVisible, creationScope == scope else { return }
            self.error = "The job, customer or estimate could not be checked. Your draft stays on this phone."
        }
    }

    private func changedEstimateLine(_ line: FieldLine) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(line.description).fixedSize(horizontal: false, vertical: true)
            Text("\(line.quantity) × \(money(line.unitPrice.amount, currency: line.unitPrice.currency))").foregroundStyle(Theme.subtle)
        }
    }

    private var editorContainer: some View {
        editorBase
            .discardChangesGuard(hasChanges: (created == nil && needsDiscardConfirmation) || draftRecoveryBlocked, busy: busy, isPresented: $confirmDiscard) { discardDraft() }
            .onChange(of: title) { _, _ in persistDraft() }
            .onChange(of: customerID) { _, _ in persistDraft() }
            .onChange(of: lines) { _, _ in persistDraft() }
            .onChange(of: scopeMatches) { wasMatching, matches in
                if !matches {
                    if wasMatching { persistDraft(leavingOriginalScope: true) }
                    picker = nil; focus = nil
                }
            }
            .onChange(of: session.can("estimate.create", feature: "estimates")) { _, allowed in
                if !allowed { picker = nil; focus = nil }
            }
            .sheet(item: $picker) { target in SheetSurface {
                PriceBookCartPicker(
                    destination: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "this estimate" : title,
                    canUsePriceBook: canUsePriceBook,
                    quantityInDraft: { lines.quantity(ofPriceBookItem: $0) },
                    secondaryPriceText: { memberPricing?.secondaryPriceText($0) },
                    addItem: { add($0, group: target.group) },
                    addCustomLine: { addCustom($0, group: target.group) },
                    refresh: { await refreshCatalog(force: $0) }
                )
                .environmentObject(session).environmentObject(api)
                .opacity(resourceAuthorized ? 1 : 0)
                .accessibilityHidden(!resourceAuthorized)
                .allowsHitTesting(resourceAuthorized)
                .overlay { if !resourceAuthorized { ContentUnavailableView("Checking access", systemImage: "lock") } }
            } }
            .thorbisConfirm("Continue without item groups?",
                            message: "The saved estimate did not keep the Work and Materials groups. Item descriptions, prices and visibility are unchanged. Continue without those groups, or ask your office for help.",
                            isPresented: $confirmGroupLoss,
                            actions: [ThorbisConfirmAction("Continue without groups") {
                                acceptedGroupLoss = true
                                Task { await save() }
                            }])
            .animation(EstimateLineGroupsEditor.spring, value: keyboardUp)
            .task(id: PriceBookCatalogContext(organizationID: session.activeOrganization?.id, sessionGeneration: session.generation, authority: session.priceBookAuthority)) { await refreshCatalog() }
            .onChange(of: customerID) { _, _ in customerProblem = nil }
            .onChange(of: lines.count) { _, _ in
                linesProblem = nil
                if descriptionProblem != nil { refreshDescriptionProblem() }
            }
            .onChange(of: lines.map(\.description)) { _, _ in
                if descriptionProblem != nil { refreshDescriptionProblem() }
            }
            .task(id: customerID) {
                memberPricing = nil
                guard !customerID.isEmpty else { return }
                let expected = customerID
                let pricing = try? await api.memberPricing(customerID)
                guard !Task.isCancelled, customerID == expected else { return }
                memberPricing = pricing
            }
    }

    private var builderFooter: some View {
        VStack(spacing: 0) {
            if let removed {
                LineRemovedToast(removed: removed, undo: undoRemove, expire: { withAnimation { self.removed = nil } })
            }
            if !keyboardUp { EstimateBuilderTotal(total: total, detail: memberLine) }
            if let descriptionProblem {
                FieldProblem(message: descriptionProblem)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.gutter)
            }
            PaperActionBar(title: commitTitle, symbol: "doc.badge.plus", busy: busy,
                           disabled: !canCommit,
                           disabledReason: canCommit ? nil : (requiresManualReview ? "Ask your office to review the saved estimate." : createOutcomeUncertain ? "Check Estimates or ask your office before starting another." : created == nil ? "Your role can't create estimates. Ask your office." : jobID == nil ? "Your role can't view this estimate. Ask your office." : "Your role can't add this estimate to the job. Ask your office.")) {
                if requiresGroupDisclosure && !acceptedGroupLoss { confirmGroupLoss = true }
                else if showProblems() { Task { await save() } }
            }
        }
        // The floating keyboard accessory is 44pt high and otherwise sits over Save.
        .padding(.bottom, keyboardUp ? 48 : 0)
        .background(Theme.canvas)
    }

    /// MF-05: what a member would pay, under the total. The saved prices stay the price book's.
    private var memberLine: String? {
        guard let memberPricing, let sum = lines.memberTotal(memberPricing) else { return nil }
        return "Member price \(money(sum, currency: "USD")) · \(memberPricing.discountPercent)% off"
    }

    private var commitTitle: String {
        if created != nil {
            if requiresGroupDisclosure && !acceptedGroupLoss { return "Continue without groups" }
            return jobID == nil ? "Open saved estimate" : "Retry adding to job"
        }
        guard let total else { return "Save estimate" }
        return "Save estimate · \(money(total, currency: "USD"))"
    }

    private var builder: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                PaperEyebrow(reference: jobID.map { "JOB-\($0.suffix(4).uppercased())" }, text: "New estimate")
                // The label stays above the field; the placeholder is only an example.
                Text("Title").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                    .padding(.top, 6).accessibilityHidden(true)
                TextField("", text: $title, prompt: .placeholder("Furnace replacement"), axis: .vertical)
                    .font(Theme.font(24, weight: .medium)).tracking(-0.3)
                    .accessibilityLabel("Estimate title")
                    .disabled(!recovery.canEdit)
                    .onChange(of: title) { _, _ in titleProblem = nil }
                if let titleProblem { FieldProblem(message: titleProblem) }
                HStack(spacing: 10) {
                    StatusLabel(tone: .unscheduled, word: "Draft", emphasis: .quiet)
                    ThorbisMenu(items: store.customers.filter { $0.archived != true }.map { customer in
                        ThorbisMenuItem(customer.name, isSelected: customer.id == customerID) { customerID = customer.id }
                    }, title: "Customer") {
                        Chip(text: customerID.isEmpty ? "Choose customer" : store.customerName(customerID), icon: "person",
                             tint: customerID.isEmpty ? Theme.brandText : Theme.muted)
                            .padding(.vertical, 10).contentShape(Rectangle())
                    }
                    .disabled(!recovery.canEdit || (jobID != nil && !customerID.isEmpty))
                }
                if let customerProblem { FieldProblem(message: customerProblem) }
            }

            EstimateBuilderSection(
                label: lines.isEmpty ? "Items" : "Items · \(lines.count)",
                lines: editableLines, disabled: !recovery.canEdit, focus: $focus, expandedLine: $expandedLine,
                showTotal: false, materialsSwitch: storesLineGroups,
                addItem: { picker = EstimateBuilderTarget() },
                removed: { line, index in withAnimation { removed = RemovedLine(line: line, index: index, optionID: nil) } }
            )
            if let linesProblem {
                FieldProblem(message: linesProblem)
            } else if lines.isEmpty {
                Text(canUsePriceBook ? "No items yet. Add one from the price book, or type a custom item."
                                     : "No items yet. Add a custom item: your role can't use the price book.")
                    .font(Theme.font(14)).foregroundStyle(Theme.muted)
            }
            if let error { ErrorBanner(message: error).padding(.horizontal, -Theme.gutter) }
        }
        .padding(.horizontal, Theme.gutter).padding(.top, 4).padding(.bottom, 28)
    }

    // MARK: Actions

    private func refreshCatalog(force: Bool = false) async {
        guard canUsePriceBook else { return }
        let org = session.activeOrganization?.id
        let generation = session.generation
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: generation, authority: session.priceBookAuthority, force: force)
        guard !Task.isCancelled, session.generation == generation, session.activeOrganization?.id == org else { return }
    }

    /// One more of a price book item; returns why it couldn't be added, or nil.
    private func add(_ item: PriceBookListItem, group: EstimateLineGroup?) -> String? {
        guard recovery.canEdit else { return "This estimate is being saved or has already been saved." }
        var addedLine = false
        withAnimation(EstimateLineGroupsEditor.spring) { addedLine = lines.addPriceBookItem(item, to: group) != nil }
        guard addedLine else { return "An estimate can contain up to 500 line items." }
        return nil
    }

    private func addCustom(_ text: String, group: EstimateLineGroup?) {
        guard recovery.canEdit else { return }
        guard let id = lines.addCustomLine(text, to: group ?? .work) else {
            error = "An estimate can contain up to 500 line items."
            return
        }
        expandedLine = id
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            focus = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .description(id) : .price(id)
        }
    }

    private func undoRemove() {
        guard recovery.canEdit, let removed else { return }
        withAnimation(EstimateLineGroupsEditor.spring) {
            lines.restoreLine(removed.line, at: removed.index)
            self.removed = nil
        }
    }

    /// Fills each problem slot; true when the estimate can be saved.
    private func refreshDescriptionProblem() {
        if lines.contains(where: { $0.estimateDescriptionProblem == .priceBookOriginalTooLong }) {
            descriptionProblem = "A price book item's original description is too long for an estimate. Ask your office to update it, then add it again."
        } else if let problem = CommercialDescriptionPolicy.problem(lines.map(\.description), kind: .estimate,
            capabilityVerified: session.isFeatureOn("commercial_extended_descriptions") && !session.isOffline) {
            descriptionProblem = problem.localizedDescription
        } else {
            descriptionProblem = nil
        }
    }

    private func showProblems() -> Bool {
        guard created == nil else { return true }
        titleProblem = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Name the work, like \u{201C}Furnace replacement.\u{201D}" : nil
        customerProblem = customerID.isEmpty ? "Choose the customer this estimate is for." : nil
        descriptionProblem = nil
        if lines.isEmpty {
            linesProblem = "Add at least one item."
        } else if let longLine = lines.first(where: { $0.estimateDescriptionProblem == .priceBookOriginalTooLong }) {
            linesProblem = nil
            refreshDescriptionProblem()
            expandedLine = longLine.id
            revealProblem += 1
        } else if let longLine = lines.first(where: { $0.estimateDescriptionProblem(allowExtended: session.isFeatureOn("commercial_extended_descriptions") && !session.isOffline) == .tooLong }) {
            linesProblem = nil
            refreshDescriptionProblem()
            expandedLine = longLine.id
            revealProblem += 1
        } else if CommercialDescriptionPolicy.problem(lines.map(\.description), kind: .estimate,
            capabilityVerified: session.isFeatureOn("commercial_extended_descriptions") && !session.isOffline) != nil {
            linesProblem = nil
            refreshDescriptionProblem()
            revealProblem += 1
        } else {
            linesProblem = valid || titleProblem != nil || customerProblem != nil ? nil
                : "Each item needs a description, a quantity from 1 to 100,000 and a price like 145.00."
        }
        return valid
    }

    /// Carry the job location into the estimate so the server can link matching records.
    /// The link command remains authoritative if the job has changed since this form opened.
    func creationRequest() -> FieldEstimateCreate {
        FieldEstimateCreate(
            customerId: customerID,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            lines: lines.map { line in
                let presentation = lines.storedPresentation(of: line, storesGroups: storesLineGroups)
                return .init(description: line.description.trimmingCharacters(in: .whitespacesAndNewlines),
                             quantity: Int(line.quantity.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1,
                             unitPrice: .init(amount: MoneyInput.cents(line.unitPrice) ?? 0, currency: "USD"),
                             source: line.source ?? .manual,
                             group: presentation.group, showToCustomer: presentation.showToCustomer)
            },
            locationId: jobLocationID)
    }

    private func save() async {
        guard resourceAuthorized, ownsDraft, !cleanupFailedAfterSave else { error = "Your access changed. Your draft is still on this phone."; return }
        guard !requiresManualReview, (!requiresGroupDisclosure || acceptedGroupLoss) else { return }
        guard recovery.mayProceed(validDraft: valid) else {
            if created == nil && !valid { _ = showProblems() }
            return
        }
        guard let scope = creationScope else {
            error = "Your session changed. Check your workspace before continuing."
            return
        }
        if let savedScope = createdScope, !savedScope.sameIdentityAndTransport(as: scope) {
            error = "Your session or workspace changed. Check the saved estimate in its original workspace before continuing."
            return
        }
        focus = nil
        removed = nil
        busy = true
        defer { busy = false; if !viewVisible { releaseDraft() } }
        var createStarted = false
        var newlyCreated = false
        do {
            let estimate: EstimateRecord
            if let created {
                do {
                    // A retry or consent may follow another actor changing this saved estimate.
                    // Recheck the authorized record and job before every link attempt.
                    guard session.can("estimate.view", feature: "estimates"),
                          jobID == nil || (session.can("job.view", feature: "jobs") && session.can("job.edit", feature: "jobs")) else {
                        error = "Your access changed. Ask your office to check the saved estimate."
                        return
                    }
                    let latest = try await api.fieldEstimate(created.id, requireFresh: true)
                    guard creationScope == scope else { return }
                    guard EstimateCreationRecovery.matchesSavedEstimate(created, latest: latest),
                          latest.organizationId == scope.organizationID else {
                        error = "The saved estimate or your access changed. Check it before continuing."
                        await showChangedEstimateFromRetry(latest, saved: created, scope: scope)
                        return
                    }
                    if let jobID {
                        let job = try await api.fieldJob(jobID, requireFresh: true)
                        guard creationScope == scope else { return }
                        guard job.id == jobID, job.organizationId == scope.organizationID,
                              job.customerId == latest.customerId, job.locationId == latest.locationId,
                              session.can("job.view", feature: "jobs"), session.can("job.edit", feature: "jobs"),
                              session.can("estimate.view", feature: "estimates") else {
                            error = "The job or your access changed. Check the saved estimate before continuing."
                            return
                        }
                    }
                    guard creationScope == scope, session.can("estimate.view", feature: "estimates") else { return }
                    createdScope = scope
                    requiresLocationVerification = false
                }
                estimate = created
            } else {
                guard session.can("estimate.create", feature: "estimates") else {
                    error = "Your role can't create estimates. Ask your office."
                    return
                }
                let descriptions = lines.map { $0.description.trimmingCharacters(in: .whitespacesAndNewlines) }
                if CommercialDescriptionPolicy.isExtended(descriptions, kind: .estimate) {
                    guard await session.verifyExtendedCommercialText(),
                          creationScope?.sameIdentityAndTransport(as: scope) == true else {
                        throw CommercialDescriptionPolicy.Problem.unavailable
                    }
                    let currentDescriptions = lines.map { $0.description.trimmingCharacters(in: .whitespacesAndNewlines) }
                    if let problem = CommercialDescriptionPolicy.problem(currentDescriptions, kind: .estimate, capabilityVerified: true) {
                        throw problem
                    }
                    guard valid, session.can("estimate.create", feature: "estimates") else {
                        throw CommercialDescriptionPolicy.Problem.unavailable
                    }
                }
                let submitted = creationRequest()
                try saveDraft(uncertain: true)
                createInFlight = true
                createStarted = true
                estimate = try await api.createFieldEstimate(submitted)
                createStarted = false
                createInFlight = false
                guard UUID(uuidString: estimate.id) != nil, estimate.organizationId == scope.organizationID,
                      estimate.customerId == customerID,
                      estimate.createdByUserId.lowercased() == scope.actorID.lowercased() else {
                    // The response cannot safely identify the submitted work; do not create again.
                    createOutcomeUncertain = true
                    if creationScope == scope {
                        error = "The saved estimate could not be verified. Ask your office to check before starting another."
                    }
                    return
                }
                // Retain the server identity and its original scope even if the session changes
                // while the response is in flight; never attach it under another identity.
                created = estimate
                newlyCreated = true
                createdScope = scope
                requiresLocationVerification = estimate.locationId != jobLocationID
                let groupResult = EstimateCreationRecovery.groupResult(submitted, created: estimate)
                requiresManualReview = !EstimateCreationRecovery.matchesSubmittedTerms(submitted, created: estimate) ||
                    groupResult == .conflicting || (jobID == nil && requiresLocationVerification)
                // Missing groups are irrelevant for an all-Work estimate unless a person moved
                // a line or a price-book material may be reclassified after reopening.
                let groupsMatter = lines.contains { line in
                    if line.group == .material { return true }
                    if case let .priceBookSelection(id, _) = line.source {
                        guard let kind = catalog.items.first(where: { $0.id == id })?.kind else { return true }
                        return kind == "material"
                    }
                    return false
                }
                requiresGroupDisclosure = groupResult == .missing && groupsMatter
                #if DEBUG
                if EstimateRecoveryPreview.enabled && ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-initial-save-fails") {
                    CommercialDraftStore.previewForceSaveFailure = true
                    EstimateRecoveryPreview.shared.record("initial-local-save-failed")
                }
                #endif
                try saveDraft(leavingOriginalScope: true)
                #if DEBUG
                if EstimateRecoveryPreview.enabled && ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-recovery-delay-initial-link") {
                    try? await Task.sleep(for: .seconds(2))
                    EstimateRecoveryPreview.shared.record("initial-link-resumed")
                }
                #endif
                guard creationScope == scope else { return }
                if requiresManualReview {
                    error = "Estimate EST-\(estimate.id.suffix(4).uppercased()) was saved, but its details differ from your submission. Ask your office to review it."
                    return
                }
                if requiresGroupDisclosure {
                    error = "Estimate EST-\(estimate.id.suffix(4).uppercased()) was saved without its item groups. Review this before continuing."
                    return
                }
                if requiresLocationVerification {
                    error = "Estimate EST-\(estimate.id.suffix(4).uppercased()) was saved with a different location. Retry to verify the job, or ask your office for help."
                    return
                }
            }
            if let jobID {
                guard creationScope == scope else { return }
                if newlyCreated {
                    // The estimate may have changed after creation. Check both exact resources
                    // before the initial link, as we do for a later retry. The server link API
                    // does not yet offer an atomic revision precondition.
                    do {
                        guard viewVisible, !Task.isCancelled, !session.isOffline,
                              session.can("estimate.view", feature: "estimates"),
                              session.can("job.view", feature: "jobs"), session.can("job.edit", feature: "jobs") else {
                            error = "The estimate was saved. Connect and check access before adding it to this job."
                            return
                        }
                        #if DEBUG
                        if EstimateRecoveryPreview.enabled { EstimateRecoveryPreview.shared.record("initial-prelink-estimate") }
                        #endif
                        let latest: EstimateRecord
                        #if DEBUG
                        if EstimateRecoveryPreview.enabled && ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-hold-initial-estimate") {
                            latest = try await api.previewHeldInitialEstimate(estimate.id)
                        } else {
                            latest = try await api.fieldEstimate(estimate.id, requireFresh: true)
                        }
                        #else
                        latest = try await api.fieldEstimate(estimate.id, requireFresh: true)
                        #endif
                        #if DEBUG
                        if EstimateRecoveryPreview.enabled { EstimateRecoveryPreview.shared.record("initial-estimate-delivered") }
                        #endif
                        guard viewVisible, !Task.isCancelled, !session.isOffline, creationScope == scope else { return }
                        guard EstimateCreationRecovery.matchesSavedEstimate(estimate, latest: latest),
                              latest.organizationId == scope.organizationID else {
                            await showChangedEstimateFromRetry(latest, saved: estimate, scope: scope)
                            return
                        }
                        let job: JobRecord
                        #if DEBUG
                        if EstimateRecoveryPreview.enabled && ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-hold-initial-job") {
                            job = try await api.previewHeldInitialJob(jobID)
                        } else {
                            job = try await api.fieldJob(jobID, requireFresh: true)
                        }
                        #else
                        job = try await api.fieldJob(jobID, requireFresh: true)
                        #endif
                        #if DEBUG
                        if EstimateRecoveryPreview.enabled { EstimateRecoveryPreview.shared.record("initial-job-delivered") }
                        #endif
                        guard viewVisible, !Task.isCancelled, !session.isOffline, creationScope == scope,
                              session.can("estimate.view", feature: "estimates"),
                              session.can("job.view", feature: "jobs"), session.can("job.edit", feature: "jobs"),
                              job.id == jobID, job.organizationId == scope.organizationID,
                              job.customerId == latest.customerId, job.locationId == latest.locationId else {
                            error = "The estimate was saved, but the job or your access changed. Check it before continuing."
                            return
                        }
                    } catch {
                        #if DEBUG
                        if EstimateRecoveryPreview.enabled { EstimateRecoveryPreview.shared.record("initial-prelink-failed") }
                        #endif
                        guard viewVisible, creationScope == scope else { return }
                        self.error = "The estimate was saved, but it could not be checked. Retry when connected."
                        return
                    }
                }
                guard viewVisible, !Task.isCancelled, !session.isOffline,
                      creationScope == scope, session.can("job.edit", feature: "jobs"),
                      session.can("estimate.view", feature: "estimates") else {
                    error = "Your session or access changed. Ask your office to check the saved estimate in its original workspace."
                    return
                }
                do {
                    // A lost response can follow a committed link. Keep a durable hold until
                    // success and cleanup are confirmed, so a relaunch cannot blindly retry.
                    try saveDraft(uncertain: true)
                    createOutcomeUncertain = true
                    let link = try await api.linkFieldEstimate(jobID: jobID, estimateID: estimate.id)
                    guard creationScope == scope else { return }
                    guard EstimateCreationRecovery.isExpectedLink(link, jobID: jobID, estimateID: estimate.id) else {
                        self.error = "The job link could not be confirmed. Ask your office to check the saved estimate."
                        return
                    }
                } catch {
                    guard creationScope == scope else { return }
                    self.error = "Estimate EST-\(estimate.id.suffix(4).uppercased()) was saved, but adding it to this job could not be confirmed. Retry to check the saved estimate and job, or ask your office for help."
                    return
                }
                guard creationScope == scope else { return }
                guard session.can("job.edit", feature: "jobs"),
                      session.can("estimate.view", feature: "estimates") else {
                    error = "Your session or access changed. Ask your office to check the saved estimate in its original workspace."
                    return
                }
                onCreated(estimate)
            } else {
                guard creationScope == scope else { return }
                guard session.can("estimate.view", feature: "estimates") else {
                    error = "Your session or access changed. Ask your office to check the saved estimate in its original workspace."
                    return
                }
                onCreated(estimate)
            }
            guard creationScope == scope else { return }
            intentionallyDiscarded = true
            do { if ownsDraft, let draftScope { try CommercialDraftStore.shared.remove(scope: draftScope) } }
            catch {
                cleanupFailedAfterSave = true
                self.error = "The estimate was saved, but its local draft could not be removed. Close this screen and check the saved estimate before continuing."
                return
            }
            dismiss()
        } catch {
            // A timeout, cancellation or malformed success may follow a committed create.
            // Hold this editor from submitting another create; its draft remains in memory.
            let uncertain = createStarted && !EstimateCreationRecovery.isDefinitiveRejection(error)
            createInFlight = false
            if uncertain { createOutcomeUncertain = true }
            if scopeMatches { try? saveDraft() }
            guard creationScope == scope else { return }
            if uncertain {
                self.error = "The save could not be confirmed. Check Estimates or ask your office before starting another. Your text is still here."
            } else if !(error is CancellationError) {
                self.error = error.localizedDescription
            }
        }
    }
    private func releaseDraft() {
        if ownsDraft, let draftScope { CommercialDraftStore.shared.release(scope: draftScope, owner: draftOwner) }
        ownsDraft = false
    }
}

#if DEBUG
/// Test-only signal from UIKit after the editor's presenting transition completes.
private struct EstimatePresentationObserver: UIViewControllerRepresentable {
    var onPresented: () -> Void
    func makeUIViewController(context: Context) -> Controller { Controller(onPresented: onPresented) }
    func updateUIViewController(_ controller: Controller, context: Context) { controller.onPresented = onPresented }
    final class Controller: UIViewController {
        var onPresented: () -> Void
        init(onPresented: @escaping () -> Void) { self.onPresented = onPresented; super.init(nibName: nil, bundle: nil) }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); onPresented() }
    }
}
#endif

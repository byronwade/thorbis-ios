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
    @State private var busy = false
    @State private var error: String?
    @State private var query = ""
    @State private var kind = PriceBookKindFilter.all
    @State private var addGroup: EstimateLineGroup?
    @State private var added = 0
    @State private var removed: RemovedLine?
    @State private var confirmDiscard = false
    @State private var descriptionTarget: NewEstimateDescriptionTarget?
    @State private var descriptionAccessRetired = false
    @State private var descriptionDirty = false
    @State private var descriptionOwnerScope: DescriptionCanvasScope?
    @State private var editorAccessRetired = false
    @FocusState private var focus: EstimateBuilderFocus?
    /// Set once the server created the estimate, so a retry only links it and never creates a duplicate.
    @State private var created: EstimateRecord?
    @State private var uncertainOutcome: String?
    @State private var confirmUncertainExit = false
    @State private var editorPresented = false
    @Binding private var parentJob: JobRecord?
    private let expectedJob: JobRecord?
    #if DEBUG
    @State private var previewCreateResponse = false
    @State private var previewLinkAttempts = 0
    #endif
    private let jobID: String?
    private let onCreated: (EstimateRecord) -> Void

    init(customerID: String = "", jobID: String? = nil, title: String = "", parentJob: Binding<JobRecord?>? = nil,
         expectedJob: JobRecord? = nil, ownerScope: DescriptionCanvasScope? = nil,
         onCreated: @escaping (EstimateRecord) -> Void = { _ in }) {
        _customerID = State(initialValue: customerID)
        _title = State(initialValue: title)
        _parentJob = parentJob ?? .constant(expectedJob)
        _descriptionOwnerScope = State(initialValue: ownerScope)
        self.expectedJob = expectedJob
        self.jobID = jobID
        self.onCreated = onCreated
    }

    private var editorScopeCurrent: Bool {
        guard !editorAccessRetired else { return false }
        guard let scope = descriptionOwnerScope else { return false }
        return session.phase == .ready && scope.matches(actor: session.user?.id, organization: session.activeOrganization?.id,
                                                        generation: session.generation, authority: session.authorityRevision)
    }

    private var jobScopeCurrent: Bool {
        guard let jobID else { return expectedJob == nil }
        guard let expectedJob else {
            #if DEBUG
            return PaperPreview.enabled && PaperPreview.screen == "new-estimate"
            #else
            return false
            #endif
        }
        guard let current = parentJob else { return false }
        return current.id == jobID && current.id == expectedJob.id && current.organizationId == expectedJob.organizationId &&
            current.customerId == expectedJob.customerId && current.organizationId == session.activeOrganization?.id &&
            customerID == expectedJob.customerId && session.can("job.view", feature: "jobs")
    }

    private var hasUnconfirmedServerResult: Bool {
        uncertainOutcome != nil || (created != nil && jobID != nil)
    }

    private var waitingForJob: Bool {
        expectedJob != nil && parentJob == nil && editorScopeCurrent && session.can("estimate.create", feature: "estimates")
    }

    private func ownerStillCurrent(_ owner: DescriptionCanvasScope, apiGeneration: UUID, origin: String?) -> Bool {
        editorPresented && editorScopeCurrent && descriptionOwnerScope == owner &&
            session.can("estimate.create", feature: "estimates") && api.requestGeneration == apiGeneration && api.normalizedOrigin == origin
    }

    private func couldHaveReachedServer(_ error: Error) -> Bool {
        guard let status = (error as? Problem)?.status else { return true }
        return status < 400 || status == 408 || status == 409 || status >= 500
    }

    private var canUsePriceBook: Bool { session.can("pricebook.view", feature: "price_book") }
    private var searching: Bool { focus == .search || !query.isEmpty }
    private var total: Int? { lines.isEmpty ? nil : lines.subtotal() }
    private var displayedTotal: Int? {
        if let created { return paperLinesTotal(created.lines) }
        return total
    }

    var valid: Bool {
        guard editorScopeCurrent, jobScopeCurrent, uncertainOutcome == nil else { return false }
        if let created {
            return UUID(uuidString: created.id) != nil && created.organizationId == session.activeOrganization?.id && created.customerId == customerID
        }
        return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !customerID.isEmpty && !lines.isEmpty &&
            lines.allSatisfy { line in
                !line.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                (Int(line.quantity.trimmingCharacters(in: .whitespacesAndNewlines)).map { (1...100_000).contains($0) } ?? false) &&
                MoneyInput.cents(line.unitPrice) != nil
            }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if !editorScopeCurrent || !jobScopeCurrent {
                    ContentUnavailableView("Estimate unavailable", systemImage: "lock",
                        description: Text(!editorScopeCurrent && uncertainOutcome != nil
                            ? "The estimate may have been created. Check existing estimates before creating another."
                            : (uncertainOutcome ?? (waitingForJob ? "Waiting for the current job. Your edits stay here." : "Access or the job changed. Close this editor to start again."))))
                        .padding(20)
                } else if let created {
                    createdSummary(created)
                } else if searching {
                    PriceBookResultsList(
                        catalog: catalog, context: PriceBookCatalogContext(organizationID: session.activeOrganization?.id, sessionGeneration: session.generation),
                            query: query, kind: kind, canUsePriceBook: canUsePriceBook,
                        quantityInCurrentDraft: { id in
                            (addGroup.map { lines.lines(in: $0) } ?? lines).quantity(ofPriceBookItem: id)
                        },
                        secondaryPriceText: { _ in nil }, addItem: add, addCustomLine: addCustom, retry: { Task { await refreshCatalog(force: true) } }
                    )
                    .disabled(busy)
                } else {
                    builder.disabled(busy)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .keyboardDoneButton()
            .background(Theme.background)
            .foregroundStyle(Theme.foreground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                #if DEBUG
                if PaperPreview.enabled && ProcessInfo.processInfo.arguments.contains("--canvas-test-create-job-loss") {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Test job return") { NotificationCenter.default.post(name: Notification.Name("ThorbisPreviewReturnEstimateJob"), object: nil) }
                    }
                }
                #endif
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasUnconfirmedServerResult { confirmUncertainExit = true }
                        else if lines.isEmpty || created != nil { dismiss() }
                        else { confirmDiscard = true }
                    }.disabled(busy)
                }
            }
            .discardChangesGuard(hasChanges: ((!lines.isEmpty || descriptionDirty) && created == nil) || hasUnconfirmedServerResult,
                                 busy: busy, isPresented: $confirmDiscard) { dismiss() }
            .thorbisConfirm("Leave before checking?",
                            message: "The estimate may already exist or be linked. Check the job and existing estimates before creating another.",
                            isPresented: $confirmUncertainExit,
                            actions: [ThorbisConfirmAction("Leave anyway", role: .destructive) { dismiss() }])
            .sheet(item: $descriptionTarget) { target in
                DescriptionCanvas(
                    text: Binding(get: { lines.first(where: { $0.id == target.id })?.description ?? target.original }, set: { _ in }),
                    title: "Line description", applyTitle: "Apply to estimate", limit: .utf16(200),
                    scope: target.scope, accessRetired: $descriptionAccessRetired, hasUnappliedChanges: $descriptionDirty,
                    targetAvailable: descriptionTargetAvailable(target), temporaryParentUnavailable: waitingForJob && !busy && created == nil,
                    originalText: target.original,
                    apply: { original, value in
                        guard descriptionTargetAvailable(target), !descriptionAccessRetired,
                              target.scope.matches(actor: session.user?.id, organization: session.activeOrganization?.id,
                                                   generation: session.generation, authority: session.authorityRevision),
                              session.phase == .ready else { return false }
                        return lines.applyDescription(id: target.id, original: original, value: value, authorized: true)
                    }
                ).presentationDetents([.large])
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if editorScopeCurrent && jobScopeCurrent && created == nil { VStack(spacing: 0) {
                    EstimateSearchBar(query: $query, kind: $kind, focus: $focus, searching: searching,
                                      prompt: addGroup.map { "Add to \($0.title)" } ?? "Search price book or type a line",
                                      finish: finishSearch)
                        .disabled(busy || !editorScopeCurrent)
                    if searching {
                        PaperActionBar(title: reviewTitle, symbol: "list.bullet", busy: busy) { finishSearch() }
                    }
                } }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if editorScopeCurrent && jobScopeCurrent { VStack(spacing: 0) {
                    if let removed, created == nil {
                        LineRemovedToast(removed: removed, undo: undoRemove, expire: { withAnimation { self.removed = nil } })
                    }
                    if !searching || created != nil {
                        EstimateBuilderTotal(total: displayedTotal)
                        PaperActionBar(title: commitTitle, symbol: "doc.badge.plus", busy: busy,
                                       disabled: !valid || !session.can("estimate.create", feature: "estimates")) { Task { await save() } }
                    }
                } }
            }
            .onAppear {
                editorPresented = true
                if descriptionOwnerScope == nil { descriptionOwnerScope = DescriptionCanvasScope.current(session) }
                if descriptionOwnerScope == nil { editorAccessRetired = true }
            }
            #if DEBUG
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ThorbisPreviewRevokeDuringEstimateCreate"))) { _ in
                if PaperPreview.enabled && ProcessInfo.processInfo.arguments.contains("--canvas-test-create-owner-loss") { session.previewSetEstimateEditing(false) }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ThorbisPreviewEstimateCreateResponse"))) { _ in previewCreateResponse = true }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ThorbisPreviewEstimateLinkAttempt"))) { _ in previewLinkAttempts += 1 }
            .overlay(alignment: .top) {
                if PaperPreview.enabled && (ProcessInfo.processInfo.arguments.contains("--canvas-test-create-owner-loss") || ProcessInfo.processInfo.arguments.contains("--canvas-test-create-link-fail") || ProcessInfo.processInfo.arguments.contains("--canvas-test-create-invalid-response") || ProcessInfo.processInfo.arguments.contains("--canvas-test-create-job-loss")) {
                    Text("Response \(previewCreateResponse ? "delivered" : "pending"); links \(previewLinkAttempts)")
                        .accessibilityIdentifier("preview-estimate-create-receipt")
                }
            }
            #endif
            .onDisappear { editorPresented = false }
            .onChange(of: parentJob) { _, current in
                if expectedJob != nil && current != nil && !jobScopeCurrent { editorAccessRetired = true }
                if jobScopeCurrent && created != nil && uncertainOutcome == nil && error == "The estimate was created. Return to the same job to finish adding it." { error = nil }
            }
            .onChange(of: session.authorityRevision) { _, _ in
                if descriptionOwnerScope != nil && !editorScopeCurrent { editorAccessRetired = true }
            }
            .sensoryFeedback(.success, trigger: added)
            .animation(EstimateLineGroupsEditor.spring, value: searching)
            .task(id: PriceBookCatalogContext(organizationID: session.activeOrganization?.id, sessionGeneration: session.generation)) { await refreshCatalog() }
            .task {
                guard lines.isEmpty else { return }
                try? await Task.sleep(for: .milliseconds(450))
                if lines.isEmpty, !customerID.isEmpty { focus = .search }
            }
        }
    }

    private func descriptionTargetAvailable(_ target: NewEstimateDescriptionTarget) -> Bool {
        !busy && editorScopeCurrent && jobScopeCurrent && created == nil && session.can("estimate.create", feature: "estimates") &&
        lines.contains(where: { $0.id == target.id })
    }

    private func showDescription(_ id: UUID) {
        guard !busy, editorScopeCurrent, jobScopeCurrent, created == nil, session.can("estimate.create", feature: "estimates"),
              let actor = session.user?.id, let organization = session.activeOrganization?.id,
              let line = lines.first(where: { $0.id == id }) else { return }
        let scope = DescriptionCanvasScope(actor: actor, organization: organization, generation: session.generation, authority: session.authorityRevision)
        if descriptionOwnerScope == nil { descriptionOwnerScope = scope }
        guard descriptionOwnerScope == scope, !editorAccessRetired else { return }
        descriptionAccessRetired = false
        descriptionTarget = NewEstimateDescriptionTarget(id: id, original: line.description, scope: scope)
    }

    private var commitTitle: String {
        if created != nil { return "Retry adding to job" }
        guard let total else { return "Save estimate" }
        return "Save estimate · \(money(total, currency: "USD"))"
    }

    private var reviewTitle: String {
        "Review estimate · \(lines.count) \(lines.count == 1 ? "item" : "items")"
    }

    private func createdSummary(_ estimate: EstimateRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Estimate created", systemImage: "checkmark.circle.fill")
                .font(Theme.font(20, weight: .medium)).foregroundStyle(Theme.success)
                .accessibilityAddTraits(.isHeader)
            Text(estimate.title).font(Theme.font(24, weight: .medium)).fixedSize(horizontal: false, vertical: true)
            Text("EST-\(estimate.id.suffix(4).uppercased()) · \(estimate.lines.count) \(estimate.lines.count == 1 ? "item" : "items")")
                .font(Theme.font(14)).foregroundStyle(Theme.muted)
            Text("Your estimate is saved. Finish adding it to this job before making more changes.")
                .font(Theme.font(16)).fixedSize(horizontal: false, vertical: true)
            if let error { ErrorBanner(message: error) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.border))
        .padding(.horizontal, Theme.gutter).padding(.top, 16).padding(.bottom, 28)
    }

    private var builder: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                PaperEyebrow(reference: jobID.map { "JOB-\($0.suffix(4).uppercased())" }, text: "New estimate")
                TextField("Estimate title", text: $title, axis: .vertical)
                    .font(Theme.font(24, weight: .medium)).tracking(-0.36)
                    .accessibilityLabel("Estimate title")
                HStack(spacing: 6) {
                    Chip(text: "Draft", icon: "circle.dashed")
                    ThorbisMenu(items: store.customers.filter { $0.archived != true }.map { customer in
                        ThorbisMenuItem(customer.name, isSelected: customer.id == customerID) { customerID = customer.id }
                    }, title: "Customer") {
                        Chip(text: customerID.isEmpty ? "Choose customer" : store.customerName(customerID), icon: "person",
                             tint: customerID.isEmpty ? Theme.brandText : Theme.muted)
                            .padding(.vertical, 10).contentShape(Rectangle())
                    }
                    .disabled(jobID != nil && !customerID.isEmpty)
                }
            }
            .padding(.bottom, 14)

            EstimateLineGroupsEditor(lines: $lines, disabled: busy, focus: $focus, addTo: startAdding, showDescription: showDescription) { line, index in
                withAnimation { removed = RemovedLine(line: line, index: index, optionID: nil) }
            }
            if lines.isEmpty {
                Text(canUsePriceBook ? "Search above to add from the price book, or type any line."
                                     : "Type a line above and add it.")
                    .font(Theme.font(15)).foregroundStyle(Theme.muted).padding(.top, 12)
            }
            if let error { ErrorBanner(message: error).padding(.horizontal, -Theme.gutter).padding(.top, 8) }
        }
        .padding(.horizontal, Theme.gutter).padding(.top, 4).padding(.bottom, 28)
    }

    // MARK: Actions

    private func refreshCatalog(force: Bool = false) async {
        guard canUsePriceBook else { return }
        let org = session.activeOrganization?.id
        let generation = session.generation
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: generation, force: force)
        guard !Task.isCancelled, session.generation == generation, session.activeOrganization?.id == org else { return }
    }

    private func add(_ item: PriceBookListItem) {
        guard !busy else { return }
        withAnimation(EstimateLineGroupsEditor.spring) {
            guard lines.addPriceBookItem(item, to: addGroup) != nil else {
                error = "An estimate can contain up to 500 line items."
                return
            }
        }
        catalog.recordUse(item.id)
        added += 1
    }

    private func addCustom(_ text: String) {
        guard !busy else { return }
        let group = addGroup ?? (kind == .material ? .material : .work)
        guard let id = lines.addCustomLine(text, to: group) else {
            error = "An estimate can contain up to 500 line items."
            return
        }
        added += 1
        query = ""
        kind = .all
        addGroup = nil
        focus = .price(id)
    }

    private func startAdding(_ group: EstimateLineGroup) {
        addGroup = group
        kind = group == .material ? .material : .all
        focus = .search
    }

    private func finishSearch() {
        query = ""
        kind = .all
        addGroup = nil
        focus = nil
    }

    private func undoRemove() {
        guard let removed else { return }
        withAnimation(EstimateLineGroupsEditor.spring) {
            lines.restoreLine(removed.line, at: removed.index)
            self.removed = nil
        }
    }

    private func save() async {
        guard valid, let owner = descriptionOwnerScope, session.can("estimate.create", feature: "estimates") else { return }
        let apiGeneration = api.requestGeneration
        let origin = api.normalizedOrigin
        guard origin != nil, ownerStillCurrent(owner, apiGeneration: apiGeneration, origin: origin), jobScopeCurrent else { return }
        busy = true
        defer { busy = false }

        let estimate: EstimateRecord
        if let created {
            estimate = created
        } else {
            do {
                estimate = try await api.createFieldEstimate(.init(
                    customerId: customerID,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    lines: lines.map {
                        .init(description: $0.description.trimmingCharacters(in: .whitespacesAndNewlines),
                              quantity: Int($0.quantity.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1,
                              unitPrice: .init(amount: MoneyInput.cents($0.unitPrice) ?? 0, currency: "USD"),
                              source: $0.source ?? .manual)
                    }))
            } catch {
                if couldHaveReachedServer(error) {
                    uncertainOutcome = "The estimate may have been created. Check existing estimates before creating another."
                    self.error = uncertainOutcome
                } else if ownerStillCurrent(owner, apiGeneration: apiGeneration, origin: origin) {
                    self.error = error.localizedDescription
                }
                return
            }
            guard UUID(uuidString: estimate.id) != nil, estimate.organizationId == owner.organization,
                  estimate.customerId == customerID else {
                uncertainOutcome = "The estimate may have been created, but its response could not be verified. Check existing estimates."
                self.error = uncertainOutcome
                return
            }
            // Retain the confirmed ID only in this editor; it is never published under another owner.
            created = estimate
            guard ownerStillCurrent(owner, apiGeneration: apiGeneration, origin: origin) else {
                uncertainOutcome = "The estimate may have been created. Check existing estimates before creating another."
                return
            }
        }

        guard ownerStillCurrent(owner, apiGeneration: apiGeneration, origin: origin) else {
            uncertainOutcome = "The estimate may have been created. Check existing estimates before creating another."
            return
        }
        guard jobScopeCurrent else {
            error = "The estimate was created. Return to the same job to finish adding it."
            return
        }
        if let jobID {
            let link: JobEstimateLink
            do {
                link = try await api.linkFieldEstimate(jobID: jobID, estimateID: estimate.id)
            } catch {
                uncertainOutcome = "Estimate EST-\(estimate.id.suffix(4).uppercased()) was created, but its job link may have succeeded. Check this job before trying again."
                self.error = uncertainOutcome
                return
            }
            guard ownerStillCurrent(owner, apiGeneration: apiGeneration, origin: origin), jobScopeCurrent,
                  link.jobId == jobID, link.estimateId == estimate.id, UUID(uuidString: link.id) != nil else {
                uncertainOutcome = "Estimate EST-\(estimate.id.suffix(4).uppercased()) was created, but its job link could not be verified. Check this job before trying again."
                return
            }
        }
        guard ownerStillCurrent(owner, apiGeneration: apiGeneration, origin: origin), jobScopeCurrent else { return }
        onCreated(estimate)
        dismiss()
    }
}

private struct NewEstimateDescriptionTarget: Identifiable {
    let id: UUID
    let original: String
    let scope: DescriptionCanvasScope
}

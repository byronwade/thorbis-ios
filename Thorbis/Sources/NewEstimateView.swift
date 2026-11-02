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
    @State private var createOutcomeUncertain = false
    @State private var memberPricing: MemberPricing?
    /// Shown after Save is pressed (validate on commit): what is missing, under its place.
    @State private var titleProblem: String?
    @State private var customerProblem: String?
    @State private var linesProblem: String?
    @State private var descriptionProblem: String?
    private let jobID: String?
    private let jobLocationID: String?
    private let onCreated: (EstimateRecord) -> Void

    init(customerID: String = "", jobID: String? = nil, locationID: String? = nil, title: String = "", onCreated: @escaping (EstimateRecord) -> Void = { _ in }) {
        _customerID = State(initialValue: customerID)
        _title = State(initialValue: title)
        self.jobID = jobID
        self.jobLocationID = jobID == nil ? nil : locationID
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
    private var canCommit: Bool {
        if createOutcomeUncertain { return false }
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
        lines.allSatisfy { line in
            line.estimateDescriptionProblem == nil &&
            (Int(line.quantity.trimmingCharacters(in: .whitespacesAndNewlines)).map { (1...100_000).contains($0) } ?? false) &&
            MoneyInput.cents(line.unitPrice) != nil
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView { builder }
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
                builderFooter
            }
            .keyboardDoneButton()
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
                                Text("Sample requests")
                                    .accessibilityIdentifier("estimate-recovery-request-counts")
                                    .accessibilityValue(EstimateRecoveryPreview.shared.counts)
                            }
                            if ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-create-hold") {
                                Button("Revalidate sample") {
                                    Task {
                                        await session.revalidate()
                                        EstimateRecoveryPreview.shared.release()
                                    }
                                }
                            }
                        }
                    }
                }
                #endif
                ThorbisToolbarItem(placement: .cancellationAction) {
                    Button(created == nil ? "Cancel" : "Close") { if lines.isEmpty || created != nil { dismiss() } else { confirmDiscard = true } }.disabled(busy)
                }
            }
            .discardChangesGuard(hasChanges: !lines.isEmpty && created == nil, busy: busy, isPresented: $confirmDiscard) { dismiss() }
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
            } }
            .animation(EstimateLineGroupsEditor.spring, value: keyboardUp)
            .task(id: PriceBookCatalogContext(organizationID: session.activeOrganization?.id, sessionGeneration: session.generation)) { await refreshCatalog() }
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
                           disabledReason: canCommit ? nil : (createOutcomeUncertain ? "Check Estimates or ask your office before starting another." : created == nil ? "Your role can't create estimates. Ask your office." : jobID == nil ? "Your role can't view this estimate. Ask your office." : "Your role can't add this estimate to the job. Ask your office.")) {
                if showProblems() { Task { await save() } }
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
        if created != nil { return jobID == nil ? "Open saved estimate" : "Retry adding to job" }
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
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: generation, force: force)
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
        } else if lines.contains(where: { $0.estimateDescriptionProblem == .tooLong }) {
            descriptionProblem = "Item descriptions can be up to 200 characters; some symbols count as more than one. Your text is still here; shorten it before saving."
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
        } else if let longLine = lines.first(where: { $0.estimateDescriptionProblem == .tooLong }) {
            linesProblem = nil
            refreshDescriptionProblem()
            expandedLine = longLine.id
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
        guard recovery.mayProceed(validDraft: valid) else { return }
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
        defer { busy = false }
        var createStarted = false
        do {
            let estimate: EstimateRecord
            if let created {
                if createdScope != scope || requiresLocationVerification {
                    // Recheck policy refreshes and unexpected saved locations before linking.
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
                createStarted = true
                estimate = try await api.createFieldEstimate(creationRequest())
                createStarted = false
                guard UUID(uuidString: estimate.id) != nil, estimate.organizationId == scope.organizationID,
                      estimate.customerId == customerID else {
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
                createdScope = scope
                requiresLocationVerification = estimate.locationId != jobLocationID
                guard creationScope == scope else { return }
                if requiresLocationVerification {
                    error = "Estimate EST-\(estimate.id.suffix(4).uppercased()) was saved with a different location. Retry to verify the job, or ask your office for help."
                    return
                }
            }
            if let jobID {
                guard creationScope == scope else { return }
                guard session.can("job.edit", feature: "jobs"),
                      session.can("estimate.view", feature: "estimates") else {
                    error = "Your session or access changed. Ask your office to check the saved estimate in its original workspace."
                    return
                }
                do {
                    let link = try await api.linkFieldEstimate(jobID: jobID, estimateID: estimate.id)
                    guard creationScope == scope else { return }
                    guard EstimateCreationRecovery.isExpectedLink(link, jobID: jobID, estimateID: estimate.id) else {
                        self.error = "The job link could not be confirmed. Ask your office to check the saved estimate."
                        return
                    }
                } catch {
                    guard creationScope == scope else { return }
                    self.error = "Estimate EST-\(estimate.id.suffix(4).uppercased()) was saved, but adding it to this job could not be confirmed. Retry or ask your office for help. Edit it after it is linked."
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
            dismiss()
        } catch {
            // A timeout, cancellation or malformed success may follow a committed create.
            // Hold this editor from submitting another create; its draft remains in memory.
            let uncertain = createStarted && !EstimateCreationRecovery.isDefinitiveRejection(error)
            if uncertain { createOutcomeUncertain = true }
            guard creationScope == scope else { return }
            if uncertain {
                self.error = "The save could not be confirmed. Check Estimates or ask your office before starting another. Your text is still here."
            } else if !(error is CancellationError) {
                self.error = error.localizedDescription
            }
        }
    }
}

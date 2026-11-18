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
    /// Paper 30/32/33: Add materials (Scan, Paste) and the price book are one set of segments. Two
    /// sheets can't overlap, so the one being left names the next and it opens after the close.
    @State private var showMaterials = false
    @State private var materialsMode = AddMaterialsMode.scan
    @State private var reopenMaterials = false
    @State private var reopenPicker = false
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
    /// Paper 35: "Present to customer" saves, then opens the saved estimate handing it to the customer.
    @State private var presentAfterSave = false
    @State private var presenting: PresentedEstimate?
    @State private var opened = Date.now
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
        if createOutcomeUncertain || requiresManualReview { return false }
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
                // The shared sheet header (Add equipment, New customer): the title and its close, with
                // the same discard check the toolbar Cancel had.
                // Paper 35: the screen's title is the 34 Bold heading in the builder; the header keeps Cancel.
                HStack {
                    PaperCircleButton(symbol: "chevron.left", label: created == nil ? "Cancel" : "Close", size: 44, fill: Theme.card) {
                        if lines.isEmpty || created != nil { dismiss() } else { confirmDiscard = true }
                    }
                    .disabled(busy)
                    Spacer(minLength: 0)
                    // Paper 35's "…" circle: the ways to add that Paper keeps off the page, and discard.
                    if !moreItems.isEmpty {
                        ThorbisMenu(items: moreItems, title: "New estimate", accessibilityLabel: "More") {
                            PaperCircleLabel(symbol: "ellipsis", size: 44, fill: Theme.card)
                        }
                        .disabled(busy)
                        .accessibilityIdentifier("estimate-more")
                    }
                }
                .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 14)
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
            .environment(\.builderDocumentLabel, created.map { "EST-\($0.id.suffix(4).uppercased())" } ?? "New estimate")
            .background(Theme.canvas)
            .paperPageGround()
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
            }
            // The header above closes the sheet; the bar stays only for the debug recovery sample.
            .toolbar(Self.showsPreviewBar ? .visible : .hidden, for: .navigationBar)
            .discardChangesGuard(hasChanges: !lines.isEmpty && created == nil, busy: busy, isPresented: $confirmDiscard) { dismiss() }
            // The saved estimate, handed to the customer the way the job's next step does it; closing it
            // closes the builder, since the estimate now lives on its own page.
            .thorbisDestination(item: $presenting) { saved in
                EstimateDetailView(id: saved.id, jobID: jobID, presentsOnOpen: true)
                    .onDisappear { dismiss() }
            }
            .sheet(item: $picker, onDismiss: {
                if reopenMaterials { reopenMaterials = false; showMaterials = true }
            }) { target in SheetSurface {
                PriceBookCartPicker(
                    destination: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "this estimate" : title,
                    canUsePriceBook: canUsePriceBook,
                    quantityInDraft: { lines.quantity(ofPriceBookItem: $0) },
                    secondaryPriceText: { memberPricing?.secondaryPriceText($0) },
                    addItem: { add($0, group: target.group) },
                    addCustomLine: { addCustom($0, group: target.group) },
                    refresh: { await refreshCatalog(force: $0) },
                    materialModes: canUsePriceBook ? AddMaterialsMode.allCases.map { $0.title } : [],
                    switchMode: { name in
                        materialsMode = AddMaterialsMode.allCases.first(where: { $0.title == name }) ?? .scan
                        reopenMaterials = true
                    }
                )
                .environmentObject(session).environmentObject(api)
            } }
            .sheet(isPresented: $showMaterials, onDismiss: {
                if reopenPicker { reopenPicker = false; picker = EstimateBuilderTarget() }
            }) { SheetSurface {
                AddMaterialsSheet(initialMode: materialsMode, canUsePriceBook: canUsePriceBook,
                                  addItem: { add($0, group: nil) },
                                  refresh: { await refreshCatalog(force: $0) },
                                  openPriceBook: { reopenPicker = true })
                .environmentObject(session).environmentObject(api)
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
    }

    private static var showsPreviewBar: Bool {
        #if DEBUG
        return EstimateRecoveryPreview.enabled
        #else
        return false
        #endif
    }

    private var builderFooter: some View {
        VStack(spacing: 0) {
            if let removed {
                LineRemovedToast(removed: removed, undo: undoRemove, expire: { withAnimation { self.removed = nil } })
            }
            if let descriptionProblem {
                FieldProblem(message: descriptionProblem)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.gutter)
            }
            commitBar
        }
        // The floating keyboard accessory is ~44pt plus chrome and otherwise sits over Save.
        .padding(.bottom, keyboardUp ? 48 : 0)
        .background(Theme.canvas)
    }

    private var commitDisabledReason: String? {
        canCommit ? nil : (requiresManualReview ? "Ask your office to review the saved estimate." : createOutcomeUncertain ? "Check Estimates or ask your office before starting another." : created == nil ? "Your role can't create estimates. Ask your office." : jobID == nil ? "Your role can't view this estimate. Ask your office." : "Your role can't add this estimate to the job. Ask your office.")
    }

    private func commit(present: Bool) {
        presentAfterSave = present
        if requiresGroupDisclosure && !acceptedGroupLoss { confirmGroupLoss = true }
        else if showProblems() { Task { await save() } }
    }

    /// Paper 35's bar: the 50pt brand pill "Present to customer" with its shield, and the 50pt save
    /// circle on the quiet fill beside it. Presenting saves first; the circle only saves. Once the
    /// estimate is saved and something still needs an answer, the pill says what (retry, continue).
    private var commitBar: some View {
        let recovering = created != nil
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button { commit(present: !recovering) } label: {
                    HStack(spacing: 7) {
                        if busy { ProgressView().tint(.white) }
                        else if !recovering { PaperIcon(.shieldCheck, size: 15, color: .white) }
                        Text(recovering ? commitTitle : "Present to customer").font(Theme.font(16, weight: .semibold))
                    }
                    .inkCommit(enabled: canCommit, height: 50)
                }
                .buttonStyle(PressStyle())
                .disabled(busy || !canCommit)
                .accessibilityHint(commitDisabledReason ?? (recovering ? "" : "Saves the estimate, then hands it to the customer"))
                .accessibilityIdentifier("estimate-present")
                if !recovering {
                    Button { commit(present: false) } label: {
                        PaperIcon(.saveDisk, size: 17, color: Theme.foreground)
                            .frame(width: 50, height: 50)
                            .background(Theme.quietFill, in: Circle())
                            .contentShape(Circle())
                            .opacity(canCommit ? 1 : 0.4)
                    }
                    .buttonStyle(PressStyle())
                    .disabled(busy || !canCommit)
                    .accessibilityLabel(commitTitle)
                    .accessibilityIdentifier("estimate-save")
                }
            }
            if let commitDisabledReason {
                Text(commitDisabledReason).font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 10).padding(.bottom, 8)
        .background(Theme.background)
    }

    /// What Paper keeps behind "…": scanning or pasting a parts list, and leaving without saving.
    private var moreItems: [ThorbisMenuItem] {
        var items: [ThorbisMenuItem] = []
        guard created == nil else { return items }
        if canUsePriceBook, recovery.canEdit {
            items.append(ThorbisMenuItem("Scan materials", icon: "barcode.viewfinder") { materialsMode = .scan; showMaterials = true })
            items.append(ThorbisMenuItem("Paste a parts list", icon: "doc.on.clipboard") { materialsMode = .paste; showMaterials = true })
        }
        if !lines.isEmpty {
            items.append(ThorbisMenuItem("Discard estimate", icon: "trash", role: .destructive) { confirmDiscard = true })
        }
        return items
    }

    /// The line under the heading: the job it's for and who it's for ("JOB-2214 · Danielle Marlowe").
    private var subtitle: String? {
        let parts = [jobID.map { "JOB-\($0.suffix(4).uppercased())" },
                     customerID.isEmpty ? nil : store.customerName(customerID)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
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

    /// Paper 35: "New estimate" at 34 Bold with the job under it, the title field, the Draft and
    /// customer pills, then (16 from the edges) Add item, the line items card, the tip and the totals.
    private var builder: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(created == nil ? "New estimate" : "Estimate saved")
                    .font(Theme.font(34, weight: .bold)).tracking(-0.85)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                // The subtitle names the job it's for.
                if let subtitle {
                    Text(subtitle).font(Theme.font(15)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, Theme.gutter)
            VStack(alignment: .leading, spacing: 6) {
                // The label stays above the field; the placeholder is only an example.
                Text("Title").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, 4).accessibilityHidden(true)
                TextField("", text: $title, prompt: .placeholder("Furnace replacement"), axis: .vertical)
                    .font(Theme.font(17, weight: .medium))
                    .accessibilityLabel("Estimate title")
                    .disabled(!recovery.canEdit)
                    .onChange(of: title) { _, _ in titleProblem = nil }
                    .padding(.horizontal, 12).padding(.vertical, 12)
                    .frame(minHeight: 48)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                if let titleProblem { FieldProblem(message: titleProblem) }
            }
            .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 16)
            VStack(alignment: .leading, spacing: 6) {
                FlowRow(spacing: 8, lineSpacing: 8) {
                    HStack(spacing: 6) {
                        PaperIcon(.statusHalf, size: 14, color: Theme.muted)
                        Text("Draft").font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.subtle)
                    }
                    .padding(.leading, 10).padding(.trailing, 12).frame(minHeight: 40)
                    .background(Theme.card, in: Capsule())
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Status, Draft")
                    HStack(spacing: 6) {
                        PaperIcon(.clockPill, size: 14, color: Theme.muted)
                        Text("Today \u{00B7} \(opened.tradeTime)").font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.subtle)
                    }
                    .padding(.leading, 10).padding(.trailing, 12).frame(minHeight: 40)
                    .background(Theme.card, in: Capsule())
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Started today at \(opened.tradeTime)")
                    ThorbisMenu(items: store.customers.filter { $0.archived != true }.map { customer in
                        ThorbisMenuItem(customer.name, isSelected: customer.id == customerID) { customerID = customer.id }
                    }, title: "Customer") {
                        customerPill
                    }
                    .disabled(!recovery.canEdit || (jobID != nil && !customerID.isEmpty))
                }
                if let customerProblem { FieldProblem(message: customerProblem) }
            }
            .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 12)

            VStack(alignment: .leading, spacing: 10) {
                EstimateBuilderSection(
                    label: "Line items",
                    lines: editableLines, disabled: !recovery.canEdit, focus: $focus, expandedLine: $expandedLine,
                    showTotal: false, materialsSwitch: storesLineGroups, lineActionsLeading: keyboardUp,
                    addItem: { picker = EstimateBuilderTarget() },
                    removed: { line, index in withAnimation { removed = RemovedLine(line: line, index: index, optionID: nil) } },
                    addItemAbove: true, addItemNote: canUsePriceBook ? "Price book or custom" : "Custom item"
                )
                if let linesProblem {
                    FieldProblem(message: linesProblem)
                } else if lines.isEmpty {
                    Text(canUsePriceBook ? "No items yet. Add one from the price book, or type a custom item."
                                         : "No items yet. Add a custom item: your role can't use the price book.")
                        .font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .padding(.horizontal, 4)
                } else {
                    Text("Tap an item to edit its name or price. At quantity 1, minus becomes remove.")
                        .font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4).padding(.top, 8)
                }
                if !lines.isEmpty { totalsCard }
                if let error { ErrorBanner(message: error).padding(.horizontal, -PaperCardMetrics.margin) }
            }
            .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 22)
        }
        .padding(.top, 14).padding(.bottom, 28)
    }

    /// The customer as Paper 35's pill: their initials on the brand surface and the name; before
    /// one is chosen, "Choose customer" in the brand's words.
    private var customerPill: some View {
        HStack(spacing: 6) {
            if customerID.isEmpty {
                Image(systemName: "person").font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.brandText).accessibilityHidden(true)
                    .padding(.leading, 4)
                Text("Choose customer").font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.brandText)
            } else {
                Text(initials(store.customerName(customerID))).font(Theme.font(11, weight: .semibold))
                    .foregroundStyle(Theme.brandText)
                    .frame(width: 22, height: 22)
                    .background(Theme.brandSurface, in: Circle())
                    .dynamicTypeSize(...DynamicTypeSize.large)
                    .accessibilityHidden(true)
                Text(shortCustomer(store.customerName(customerID))).font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.subtle)
                    .lineLimit(1)
            }
        }
        .padding(.leading, 6).padding(.trailing, 12).frame(minHeight: 40)
        .background(Theme.card, in: Capsule())
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    /// Paper 35's pill names the customer "Danielle M.": the first name and the last initial.
    private func shortCustomer(_ name: String) -> String {
        let words = name.split(separator: " ")
        guard words.count > 1, let last = words.last?.first else { return name }
        return "\(words[0]) \(last)."
    }

    /// Paper 35's totals card: the subtotal, then the total at 34 Bold, and a member's price under it.
    private var totalsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Subtotal").font(Theme.font(15)).foregroundStyle(Theme.subtle)
                Spacer(minLength: 8)
                Text(total.map { money($0, currency: "USD") } ?? "\u{2014}").font(Theme.monoFont(15)).foregroundStyle(Theme.subtle)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Total").font(Theme.font(16, weight: .semibold)).foregroundStyle(Theme.foreground)
                Spacer(minLength: 8)
                Text(total.map { money($0, currency: "USD") } ?? "\u{2014}")
                    .font(Theme.font(28, weight: .bold)).monospacedDigit().tracking(-0.56)
                    .foregroundStyle(Theme.foreground)
                    .contentTransition(.numericText())
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .padding(.top, 4)
            if let memberLine {
                Text(memberLine).font(Theme.font(14)).monospacedDigit().foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
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
        guard !requiresManualReview, (!requiresGroupDisclosure || acceptedGroupLoss),
              recovery.mayProceed(validDraft: valid) else { return }
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
                let submitted = creationRequest()
                createStarted = true
                estimate = try await api.createFieldEstimate(submitted)
                createStarted = false
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
            // Present to customer: the saved estimate opens and hands itself over; closing it closes this.
            if presentAfterSave {
                presentAfterSave = false
                presenting = PresentedEstimate(id: estimate.id)
                return
            }
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

/// The saved estimate "Present to customer" opens next.
private struct PresentedEstimate: Identifiable, Hashable {
    let id: String
}

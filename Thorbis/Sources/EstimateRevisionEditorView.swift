import SwiftUI

struct EstimateRevisionEditorView: View {
    let estimate: EstimateRecord
    let onSaved: (EstimateRecord) -> Void

    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var editor: EstimateRevisionEditorState
    @State private var busy = false
    @State private var error: String?
    @State private var staleRevision = false
    @State private var confirmReload = false
    @State private var confirmDiscard = false
    @State private var picker: EstimateBuilderTarget?
    @State private var discountTarget: EstimateBuilderTarget?
    @State private var expandedLine: UUID?
    @State private var keyboardUp = false
    @State private var scrollTarget: String?
    @State private var removed: RemovedLine?
    @State private var memberPricing: MemberPricing?
    @ObservedObject private var catalog = PriceBookCatalog.shared
    @FocusState private var focus: EstimateBuilderFocus?

    init(estimate: EstimateRecord, onSaved: @escaping (EstimateRecord) -> Void) {
        self.estimate = estimate
        self.onSaved = onSaved
        _editor = State(initialValue: EstimateRevisionEditorState(estimate: estimate))
    }

    private var canRevise: Bool {
        editor.canRevise && session.can("estimate.create", feature: "estimates")
    }

    /// Good / better / best stays behind its flag (`estimate_option_signing`).
    private var optionsFeatureEnabled: Bool {
        session.can("estimate.create", feature: "estimate_option_signing")
    }

    private var canEdit: Bool {
        canRevise && (optionsFeatureEnabled || editor.options.isEmpty)
    }

    private var canDiscount: Bool {
        session.can("estimate.discount", feature: "estimates")
    }

    private var canUsePriceBook: Bool {
        session.can("pricebook.view", feature: "price_book")
    }

    private var sectionsDisabled: Bool { busy || !canEdit || editor.hasUnsupportedLineSources }

    private func optionName(_ id: String?) -> String {
        guard let id, let index = editor.options.firstIndex(where: { $0.id == id }) else {
            return editor.options.isEmpty ? "this estimate" : "the main estimate"
        }
        let title = editor.options[index].title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Option \(index + 1)" : "Option \(index + 1) · \(title)"
    }

    private var editingDraft: Bool { editor.estimate.status == "draft" }

    private var revisionReady: Bool {
        !editingDraft && (editor.estimate.currentRevisionNumber ?? 0) > 0
    }

    private var canSave: Bool {
        !busy && canEdit && revisionReady &&
        editor.hasChanges && !editor.hasUnsupportedLineSources && (!editor.hasCreditLines || canDiscount)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView { content }
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
                    .onChange(of: scrollTarget) { _, target in
                        guard let target else { return }
                        withAnimation { proxy.scrollTo(target, anchor: .top) }
                        scrollTarget = nil
                    }
            }
            .background(Theme.background)
            .foregroundStyle(Theme.foreground)
            .navigationTitle(editingDraft ? "Edit estimate" : "Revise estimate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ThorbisToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if editor.hasChanges { confirmDiscard = true } else { dismiss() } }.disabled(busy)
                }
            }
            .keyboardDoneButton()
            .trackKeyboard($keyboardUp)
            .discardChangesGuard(hasChanges: editor.hasChanges, busy: busy, isPresented: $confirmDiscard) { dismiss() }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if let removed {
                        LineRemovedToast(removed: removed, undo: undoRemove, expire: { withAnimation { self.removed = nil } })
                    }
                    if !keyboardUp { footerTotal }
                    PaperActionBar(title: saveTitle, symbol: "doc.badge.plus", busy: busy, disabled: !canSave) {
                        Task { await save() }
                    }
                }
            }
            .sheet(item: $picker) { target in
                PriceBookCartPicker(
                    destination: optionName(target.optionID),
                    canUsePriceBook: canUsePriceBook,
                    quantityInDraft: { id in lines(for: target.optionID).quantity(ofPriceBookItem: id) },
                    secondaryPriceText: { memberPricing?.secondaryPriceText($0) },
                    addItem: { add($0, to: target) },
                    addCustomLine: { addCustom($0, to: target) },
                    refresh: { await refreshCatalog(force: $0) }
                )
                .environmentObject(session).environmentObject(api)
            }
            .sheet(item: $discountTarget) { target in
                EstimateDiscountSheet(target: optionName(target.optionID), subtotal: lines(for: target.optionID).subtotal()) { label, cents in
                    mutateLines(target.optionID) { _ = $0.addCreditLine(label, cents: cents) }
                }
            }
            .animation(EstimateLineGroupsEditor.spring, value: keyboardUp)
            .task(id: PriceBookCatalogContext(organizationID: session.activeOrganization?.id, sessionGeneration: session.generation)) { await refreshCatalog() }
            .task(id: estimate.customerId) { memberPricing = try? await api.memberPricing(estimate.customerId) }
            .onChange(of: catalog.items.map(\.id)) { classifyLines() }
            .thorbisConfirm("Reload the latest estimate?",
                            message: "The estimate changed on the server. Reloading replaces this form with its latest saved lines and options.",
                            isPresented: $confirmReload,
                            actions: [ThorbisConfirmAction("Reload and discard my edits", role: .destructive) { Task { await reloadLatest() } }])
            #if DEBUG
            .task {
                guard PaperPreview.enabled else { return }
                if PaperPreview.screen == "builder-line" { expandedLine = editor.lines.first?.id ?? editor.options.first?.lines.first?.id }
                if PaperPreview.screen == "builder-picker" {
                    try? await Task.sleep(for: .milliseconds(400))
                    picker = EstimateBuilderTarget(optionID: editor.options.first?.id)
                }
            }
            #endif
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let error { ErrorBanner(message: error).padding(.horizontal, -Theme.gutter) }
            if staleRevision {
                Button { confirmReload = true } label: {
                    Label("Review latest estimate", systemImage: "arrow.clockwise")
                        .font(Theme.font(14, weight: .medium))
                        .foregroundStyle(Theme.brandText)
                        .frame(minHeight: 44)
                }
                .accessibilityHint("Loads the current server version and replaces these edits")
            }
            if !editor.canRevise {
                ErrorBanner(message: "This estimate cannot be revised from its current status.")
            } else if !session.can("estimate.create", feature: "estimates") {
                ErrorBanner(message: "Your account cannot create estimate revisions.")
            } else if !editingDraft && (editor.estimate.currentRevisionNumber ?? 0) <= 0 {
                ErrorBanner(message: EstimateRevisionEditorError.missingRevision.localizedDescription)
            }
            if editingDraft && canRevise {
                ErrorBanner(message: "Draft changes can't be saved yet.")
            }
            if editor.hasUnsupportedLineSources {
                ErrorBanner(message: EstimateRevisionEditorError.unsupportedLineSource.localizedDescription)
            }
            if !optionsFeatureEnabled && !editor.options.isEmpty {
                ErrorBanner(message: EstimateRevisionEditorError.optionFeatureRequired.localizedDescription)
            }
            if editor.hasCreditLines && !canDiscount {
                ErrorBanner(message: EstimateRevisionEditorError.discountCapabilityRequired.localizedDescription)
            }

            estimateHeading
            mainSection
            optionSections
            Text(editingDraft
                 ? "Changes aren't saved when you close this screen."
                 : "Saving creates a replacement draft for the current estimate revision. It will not be sent automatically.")
                .font(Theme.font(13)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 8)
        .padding(.bottom, 24)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
    }

    /// The pinned total: the estimate's total, or each option's range once there are options.
    @ViewBuilder private var footerTotal: some View {
        if editor.options.isEmpty {
            let member = editor.lines.memberTotal(memberPricing).map { sum in
                "Member price \(money(sum, currency: "USD")) · \(memberPricing?.discountPercent ?? 0)% off"
            }
            EstimateBuilderTotal(total: editor.lines.subtotal(), detail: member)
        } else {
            let totals = editor.options.map { $0.lines.subtotal() }
            let known = totals.compactMap { $0 }
            let value = known.count == totals.count && !known.isEmpty
                ? (known.min() == known.max() ? money(known[0], currency: "USD")
                   : "\(money(known.min()!, currency: "USD"))–\(money(known.max()!, currency: "USD"))")
                : "—"
            EstimateBuilderTotal(label: "\(editor.options.count) \(editor.options.count == 1 ? "option" : "options")", value: value,
                                 detail: "The customer chooses one")
        }
    }

    private var estimateHeading: some View {
        VStack(alignment: .leading, spacing: 8) {
            PaperEyebrow(reference: "EST-\(editor.estimate.id.suffix(4).uppercased())",
                         text: "Revision \(editor.estimate.currentRevisionNumber ?? 0) · \(editingDraft ? "Edit draft" : "New replacement draft")")
            TextField("Estimate title", text: $editor.title, axis: .vertical)
                .font(Theme.font(24, weight: .medium)).tracking(-0.36)
                .accessibilityLabel("Estimate title")
                .disabled(busy || !canEdit)
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Circle().fill(Theme.warning).frame(width: 7, height: 7)
                    Text(editor.estimate.status.statusLabel).font(Theme.font(14, weight: .medium))
                }
                .accessibilityElement(children: .combine)
                Text(store.customerName(estimate.customerId))
                    .font(Theme.font(14)).foregroundStyle(Theme.muted)
                    .accessibilityLabel("Customer \(store.customerName(estimate.customerId))")
            }
        }
    }

    private var mainSection: some View {
        let hasOptions = !editor.options.isEmpty
        var menu: [ThorbisMenuItem] = []
        if optionsFeatureEnabled, editor.options.count < 8, !editor.lines.isEmpty {
            menu.append(ThorbisMenuItem("Copy to a new option", icon: "plus.square.on.square",
                                        subtitle: "Start an option from these items") {
                if let id = editor.addOption(title: "", lines: editor.lines) { scrollToOption(id) }
            })
        }
        return EstimateBuilderSection(
            label: hasOptions ? "Main estimate" : (editor.lines.isEmpty ? "Items" : "Items · \(editor.lines.count)"),
            caption: hasOptions ? "Saved with every revision. With options, the customer chooses one option." : nil,
            lines: editableLines, disabled: sectionsDisabled, focus: $focus, expandedLine: $expandedLine,
            totalLabel: "Subtotal", showTotal: hasOptions, memberPricing: memberPricing, menuItems: menu,
            addItem: { picker = EstimateBuilderTarget() },
            addDiscount: canDiscount && !hasOptions ? { discountTarget = EstimateBuilderTarget() } : nil,
            removed: { line, index in withAnimation { removed = RemovedLine(line: line, index: index, optionID: nil) } }
        )
    }

    @ViewBuilder private var optionSections: some View {
        ForEach(Array(editor.options.enumerated()), id: \.element.id) { index, option in
            optionSection(index: index, option: option)
        }
        if optionsFeatureEnabled {
            Button(action: addOption) {
                HStack(spacing: 12) {
                    PaperCircleLabel(symbol: "plus", size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add option").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                        Text(editor.options.isEmpty ? "Offer good, better and best" : "Up to 8 options")
                            .font(Theme.font(14)).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 52).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(sectionsDisabled || editor.options.count >= 8)
        } else {
            Text("Option packages require estimate option signing access.")
                .font(Theme.font(13)).foregroundStyle(Theme.muted)
                .padding(.horizontal, 4)
        }
    }

    private func optionSection(index: Int, option: EstimateRevisionOptionDraft) -> some View {
        let binding = optionBinding(option.id)
        let title = option.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = title.isEmpty ? "Option \(index + 1)" : "Option \(index + 1) · \(title)"
        var menu: [ThorbisMenuItem] = []
        if editor.options.count < 8 {
            menu.append(ThorbisMenuItem("Copy option", icon: "plus.square.on.square", subtitle: "Start the next option from this one") {
                if let id = editor.copyOption(id: option.id) { scrollToOption(id) }
            })
        }
        if index > 0 { menu.append(ThorbisMenuItem("Move up", icon: "arrow.up") { withAnimation { editor.moveOption(id: option.id, by: -1) } }) }
        if index < editor.options.count - 1 {
            menu.append(ThorbisMenuItem("Move down", icon: "arrow.down") { withAnimation { editor.moveOption(id: option.id, by: 1) } })
        }
        menu.append(ThorbisMenuItem("Remove option", icon: "trash", role: .destructive) { withAnimation { editor.removeOption(id: option.id) } })
        let disabled = sectionsDisabled || !optionsFeatureEnabled
        return EstimateBuilderSection(
            label: label, lines: binding.lines, disabled: disabled, focus: $focus, expandedLine: $expandedLine,
            totalLabel: "Option total", memberPricing: memberPricing, menuItems: menu,
            addItem: { picker = EstimateBuilderTarget(optionID: option.id) },
            addDiscount: canDiscount ? { discountTarget = EstimateBuilderTarget(optionID: option.id) } : nil,
            removed: { line, lineIndex in withAnimation { removed = RemovedLine(line: line, index: lineIndex, optionID: option.id) } }
        ) {
            VStack(alignment: .leading, spacing: 0) {
                TextField("Option name, like Repair", text: binding.title)
                    .font(Theme.font(17, weight: .medium))
                    .accessibilityLabel("Option package title")
                    .frame(minHeight: 40)
                TextField("What this option includes", text: binding.description, axis: .vertical)
                    .font(Theme.font(15)).lineLimit(1...)
                    .foregroundStyle(Theme.muted)
                    .accessibilityLabel("Option package description")
            }
            .disabled(disabled)
            .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 4)
        }
        .id("option-\(option.id)")
    }

    private func optionBinding(_ id: String) -> Binding<EstimateRevisionOptionDraft> {
        Binding(
            get: { editor.options.first { $0.id == id } ?? EstimateRevisionOptionDraft(id: id, title: "", description: "", lines: []) },
            set: { value in if let index = editor.options.firstIndex(where: { $0.id == id }) { editor.options[index] = value } }
        )
    }

    private func addOption() {
        guard let id = editor.addOption(title: "", lines: []) else { return }
        scrollToOption(id)
        picker = EstimateBuilderTarget(optionID: id)
    }

    private func scrollToOption(_ id: String) {
        expandedLine = nil
        Task { @MainActor in scrollTarget = "option-\(id)" }
    }

    private var editableLines: Binding<[EstimateRevisionLineDraft]> {
        Binding(
            get: { editor.lines },
            set: { proposed in
                guard editor.canRevise else { return }
                editor.lines = proposed
                for line in proposed {
                    let quantityText = line.quantity.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let quantity = Int(quantityText), (1...100_000).contains(quantity), String(quantity) == quantityText {
                        try? editor.setQuantity(line.id, quantity)
                    }
                }
            }
        )
    }

    private var saveTitle: String {
        let verb = editingDraft ? "Save draft" : "Save revised draft"
        guard editor.options.isEmpty, let total = editor.lines.subtotal() else { return verb }
        return "\(verb) · \(money(total, currency: "USD"))"
    }

    private func refreshCatalog(force: Bool = false) async {
        guard canUsePriceBook else { return }
        let org = session.activeOrganization?.id
        let generation = session.generation
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: generation, force: force)
        guard !Task.isCancelled, session.generation == generation, session.activeOrganization?.id == org else { return }
        classifyLines()
    }

    private func classifyLines() {
        editor.classify(kinds: Dictionary(catalog.items.map { ($0.id, $0.kind) }, uniquingKeysWith: { first, _ in first }))
    }

    private func lines(for optionID: String?) -> [EstimateRevisionLineDraft] {
        guard let optionID else { return editor.lines }
        return editor.options.first { $0.id == optionID }?.lines ?? []
    }

    private func mutateLines(_ optionID: String?, _ change: (inout [EstimateRevisionLineDraft]) -> Void) {
        if let optionID {
            guard let index = editor.options.firstIndex(where: { $0.id == optionID }) else { return }
            change(&editor.options[index].lines)
        } else {
            change(&editor.lines)
        }
    }

    /// One more of a price book item; returns why it couldn't be added, or nil.
    private func add(_ item: PriceBookListItem, to target: EstimateBuilderTarget) -> String? {
        guard !busy else { return "Saving. Try again in a moment." }
        var addedLine = false
        withAnimation(EstimateLineGroupsEditor.spring) {
            mutateLines(target.optionID) { addedLine = $0.addPriceBookItem(item, to: target.group) != nil }
        }
        guard addedLine else { return EstimateRevisionEditorError.tooManyLines.localizedDescription }
        error = nil
        return nil
    }

    private func addCustom(_ text: String, to target: EstimateBuilderTarget) {
        guard !busy else { return }
        var lineID: UUID?
        mutateLines(target.optionID) { lineID = $0.addCustomLine(text, to: target.group ?? .work) }
        guard let lineID else {
            error = EstimateRevisionEditorError.tooManyLines.localizedDescription
            return
        }
        expandedLine = lineID
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            focus = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .description(lineID) : .price(lineID)
        }
    }

    private func undoRemove() {
        guard let removed else { return }
        withAnimation(EstimateLineGroupsEditor.spring) {
            if let optionID = removed.optionID {
                if let index = editor.options.firstIndex(where: { $0.id == optionID }) {
                    editor.options[index].lines.restoreLine(removed.line, at: removed.index)
                }
            } else {
                editor.lines.restoreLine(removed.line, at: removed.index)
            }
            self.removed = nil
        }
    }

    /// Canonicalize a finished price at save time. Live keystrokes keep the raw text.
    private func commitPrices() {
        for line in editor.lines {
            guard let cents = EstimateRevisionEditorState.parsePrice(line.unitPrice) else { continue }
            try? editor.setUnitPrice(line.id, cents: cents)
        }
    }

    private func save() async {
        guard !editingDraft else {
            error = "Draft changes can't be saved yet."
            return
        }
        guard canRevise else {
            error = "You no longer have permission to revise this estimate."
            return
        }
        busy = true
        defer { busy = false }
        do {
            commitPrices()
            let revised = try await api.reviseFieldEstimate(
                editor.estimate.id,
                request: editor.makeRequest(optionsFeatureEnabled: optionsFeatureEnabled, canDiscount: canDiscount)
            )
            onSaved(revised)
            dismiss()
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
            staleRevision = (error as? Problem)?.status == 409
        }
    }

    private func reloadLatest() async {
        busy = true
        defer { busy = false }
        do {
            let latest = try await api.liveFieldEstimate(estimate.id)
            editor = EstimateRevisionEditorState(estimate: latest)
            classifyLines()
            staleRevision = false
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }
}

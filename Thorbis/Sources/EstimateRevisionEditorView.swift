import SwiftUI

struct EstimateRevisionEditorView: View {
    let estimate: EstimateRecord
    let onSaved: (EstimateRecord) -> Void
    @Binding private var parentRecord: EstimateRecord?

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
    @State private var descriptionTarget: RevisionDescriptionTarget?
    @State private var descriptionAccessRetired = false
    @State private var descriptionDirty = false
    @State private var descriptionOwnerScope: DescriptionCanvasScope?
    @State private var editorAccessRetired = false
    @State private var documentGeneration = UUID()
    @ObservedObject private var catalog = PriceBookCatalog.shared
    @State private var query = ""
    @State private var kind = PriceBookKindFilter.all
    @State private var target = EstimateBuilderTarget()
    @State private var added = 0
    @State private var removed: RemovedLine?
    @FocusState private var focus: EstimateBuilderFocus?

    init(estimate: EstimateRecord, parentRecord: Binding<EstimateRecord?>? = nil, ownerScope: DescriptionCanvasScope? = nil, onSaved: @escaping (EstimateRecord) -> Void) {
        self.estimate = estimate
        _parentRecord = parentRecord ?? .constant(estimate)
        _descriptionOwnerScope = State(initialValue: ownerScope)
        self.onSaved = onSaved
        _editor = State(initialValue: EstimateRevisionEditorState(estimate: estimate))
    }

    private var editorScopeCurrent: Bool {
        guard !editorAccessRetired else { return false }
        guard let scope = descriptionOwnerScope else { return false }
        return session.phase == .ready && scope.matches(actor: session.user?.id, organization: session.activeOrganization?.id,
                                                        generation: session.generation, authority: session.authorityRevision)
    }

    private var canRevise: Bool {
        editor.canRevise && session.can("estimate.create", feature: "estimates")
    }

    private var optionsFeatureEnabled: Bool {
        session.can("estimate.create", feature: "estimate_option_signing")
    }

    private var canEdit: Bool {
        editorScopeCurrent && parentRecord == estimate && canRevise && (optionsFeatureEnabled || editor.options.isEmpty)
    }

    private var canDiscount: Bool {
        session.can("estimate.discount", feature: "estimates")
    }

    private var canUsePriceBook: Bool {
        session.can("pricebook.view", feature: "price_book")
    }

    private var searching: Bool { focus == .search || !query.isEmpty }

    private var targetLines: [EstimateRevisionLineDraft] {
        guard let optionID = target.optionID else { return editor.lines }
        return editor.options.first { $0.id == optionID }?.lines ?? []
    }

    private var searchPrompt: String {
        let place = target.optionID.flatMap { id in editor.options.first { $0.id == id } }
            .map { $0.title.isEmpty ? "option" : $0.title }
        switch (place, target.group) {
        case let (place?, group?): return "Add to \(place) · \(group.title)"
        case let (place?, nil): return "Add to \(place)"
        case let (nil, group?): return "Add to \(group.title)"
        case (nil, nil): return "Search price book or type a line"
        }
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
            ScrollView {
                if !editorScopeCurrent || parentRecord != estimate || !session.can("estimate.create", feature: "estimates") {
                    ContentUnavailableView("Estimate unavailable", systemImage: "doc.questionmark",
                        description: Text("The current estimate changed or could not be loaded. Your edits stay here until you close this editor."))
                        .padding(20)
                } else {
                if let error {
                    ErrorBanner(message: error)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }
                if staleRevision {
                    Button { confirmReload = true } label: {
                        Label("Review latest estimate", systemImage: "arrow.clockwise")
                            .font(Theme.font(14, weight: .medium))
                            .foregroundStyle(Theme.brandText)
                            .frame(minHeight: 44)
                    }
                    .accessibilityHint("Loads the current server version and replaces these edits")
                    .padding(.horizontal, 20)
                }
                if searching {
                    PriceBookResultsList(
                        catalog: catalog, context: PriceBookCatalogContext(organizationID: session.activeOrganization?.id, sessionGeneration: session.generation),
                            query: query, kind: kind, canUsePriceBook: canUsePriceBook,
                        quantityInCurrentDraft: { id in
                            (target.group.map { targetLines.lines(in: $0) } ?? targetLines).quantity(ofPriceBookItem: id)
                        },
                        secondaryPriceText: { _ in nil }, addItem: add, addCustomLine: addCustom,
                        retry: { Task { await refreshCatalog(force: true) } }
                    )
                    .disabled(busy)
                } else {
                VStack(alignment: .leading, spacing: 18) {
                    if !editor.canRevise {
                        ErrorBanner(message: "This estimate cannot be revised from its current status.")
                    } else if !session.can("estimate.create", feature: "estimates") {
                        ErrorBanner(message: "Your account cannot create estimate revisions.")
                    } else if !editingDraft && (editor.estimate.currentRevisionNumber ?? 0) <= 0 {
                        ErrorBanner(message: EstimateRevisionEditorError.missingRevision.localizedDescription)
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
                    detailsCard.disabled(busy || !canEdit)
                    lineSection
                    optionSection
                    Text(editingDraft
                         ? "Changes aren't saved when you close this screen."
                         : "Saving creates a replacement draft for the current estimate revision. It will not be sent automatically.")
                        .font(Theme.font(12)).foregroundStyle(Theme.muted)
                        .padding(.horizontal, 2)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
                }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .foregroundStyle(Theme.foreground)
            .navigationTitle(editingDraft ? "Edit estimate" : "Revise estimate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if editor.hasChanges || descriptionDirty { confirmDiscard = true } else { dismiss() } }.disabled(busy)
                }
            }
            .keyboardDoneButton()
            .discardChangesGuard(hasChanges: editor.hasChanges || descriptionDirty, busy: busy, isPresented: $confirmDiscard) { dismiss() }
            .sheet(item: $descriptionTarget) { target in
                DescriptionCanvas(
                    text: Binding(get: { descriptionValue(target) ?? target.original }, set: { _ in }),
                    title: target.title, applyTitle: "Apply to estimate", limit: target.limit,
                    scope: target.scope, accessRetired: $descriptionAccessRetired, hasUnappliedChanges: $descriptionDirty,
                    targetAvailable: descriptionTargetAvailable(target),
                    temporaryParentUnavailable: parentRecord == nil && editorScopeCurrent && canRevise && (optionsFeatureEnabled || editor.options.isEmpty) && !busy && !editor.hasUnsupportedLineSources,
                    originalText: target.original,
                    apply: { original, value in
                        guard descriptionTargetAvailable(target), !descriptionAccessRetired, session.phase == .ready,
                              target.scope.matches(actor: session.user?.id, organization: session.activeOrganization?.id,
                                                   generation: session.generation, authority: session.authorityRevision) else { return false }
                        switch target.kind {
                        case .line(let lineID, let optionID):
                            return editor.applyLineDescription(optionID: optionID, id: lineID, original: original, value: value, authorized: true)
                        case .option(let optionID):
                            return editor.applyOptionDescription(id: optionID, original: original, value: value, authorized: true)
                        }
                    }
                ).presentationDetents([.large])
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if editorScopeCurrent && parentRecord == estimate { VStack(spacing: 0) {
                    if canEdit {
                        EstimateSearchBar(query: $query, kind: $kind, focus: $focus, searching: searching,
                                          prompt: searchPrompt, finish: finishSearch)
                            .disabled(busy)
                    }
                    if editingDraft && canRevise {
                        ErrorBanner(message: "Draft changes can't be saved yet.")
                            .padding(.horizontal, 20)
                            .padding(.bottom, 8)
                    }
                    if searching {
                        PaperActionBar(title: reviewTitle, symbol: "list.bullet", busy: busy) { finishSearch() }
                    }
                }
                .background(Theme.background) }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if editorScopeCurrent && parentRecord == estimate {
                VStack(spacing: 0) {
                    if let removed {
                        LineRemovedToast(removed: removed, undo: undoRemove, expire: { withAnimation { self.removed = nil } })
                    }
                    if !searching {
                        if editor.options.isEmpty { EstimateBuilderTotal(total: editor.lines.subtotal()) }
                        PaperActionBar(title: saveTitle, symbol: "doc.badge.plus", busy: busy, disabled: !canSave) {
                            Task { await save() }
                        }
                    }
                }
                }
            }
            .sensoryFeedback(.success, trigger: added)
            .animation(EstimateLineGroupsEditor.spring, value: searching)
            .task(id: PriceBookCatalogContext(organizationID: session.activeOrganization?.id, sessionGeneration: session.generation)) { await refreshCatalog() }
            .onAppear {
                if descriptionOwnerScope == nil { descriptionOwnerScope = DescriptionCanvasScope.current(session) }
                if descriptionOwnerScope == nil { editorAccessRetired = true }
            }
            .onChange(of: session.authorityRevision) { _, _ in
                if descriptionOwnerScope != nil && !editorScopeCurrent { editorAccessRetired = true }
            }
            .onChange(of: catalog.items.map(\.id)) { classifyLines() }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ThorbisPreviewReplaceEstimateDraft"))) { _ in
                #if DEBUG
                if PaperPreview.enabled && ProcessInfo.processInfo.arguments.contains("--canvas-test-replacement") {
                    documentGeneration = UUID()
                    editor = EstimateRevisionEditorState(estimate: editor.estimate)
                }
                #endif
            }
            .thorbisConfirm("Reload the latest estimate?",
                            message: "The estimate changed on the server. Reloading replaces this form with its latest saved lines and options.",
                            isPresented: $confirmReload,
                            actions: [ThorbisConfirmAction("Reload and discard my edits", role: .destructive) { Task { await reloadLatest() } }])
        }
    }

    private var estimateHeading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EST-\(editor.estimate.id.suffix(4).uppercased()) · REVISION \(editor.estimate.currentRevisionNumber ?? 0)")
                .font(Theme.monoFont(11, weight: .medium)).foregroundStyle(Theme.muted)
            Text(editingDraft ? "Edit draft" : "New replacement draft")
                .font(Theme.font(24, weight: .medium)).tracking(-0.36)
            Text(editor.estimate.status.statusLabel)
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.warning)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(Theme.warningSurface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
        }
        .padding(.bottom, 6)
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
            TextField("Estimate title", text: $editor.title)
                .font(Theme.font(15, weight: .semibold))
                .accessibilityLabel("Estimate title")
                .paperField()
            HStack {
                Text("Customer")
                Spacer()
                Text(store.customerName(estimate.customerId))
            }
            .font(Theme.font(12)).foregroundStyle(Theme.muted)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private var lineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            EstimateLineGroupsEditor(
                lines: editableLines,
                disabled: busy || !canEdit || editor.hasUnsupportedLineSources,
                focus: $focus,
                addTo: { group in startAdding(optionID: nil, group: group) },
                showDescription: { showDescription(.line($0, nil)) },
                removed: { line, index in withAnimation { removed = RemovedLine(line: line, index: index, optionID: nil) } }
            )
        }
    }

    private var optionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("Option packages", count: editor.options.count)
                Spacer()
                Button { editor.addOption() } label: {
                    Label("Add option", systemImage: "plus")
                        .font(Theme.font(12, weight: .medium)).frame(minHeight: 44)
                }
                .disabled(busy || !canEdit || !optionsFeatureEnabled || editor.options.count >= 8 || editor.hasUnsupportedLineSources)
            }
            if !optionsFeatureEnabled {
                Text("Option packages require estimate option signing access.")
                    .font(Theme.font(12)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, 2)
            }
            if editor.options.isEmpty {
                Text("No alternate packages")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(15).background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            }
            ForEach(editor.options) { option in
                EstimateRevisionOptionEditor(
                    option: optionBinding(option),
                    showDescription: { showDescription(.option(option.id)) },
                    showLineDescription: { showDescription(.line($0, option.id)) },
                    disabled: busy || !canEdit || !optionsFeatureEnabled || editor.hasUnsupportedLineSources,
                    focus: $focus,
                    addTo: { group in startAdding(optionID: option.id, group: group) },
                    removeOption: { editor.removeOption(id: option.id) },
                    removed: { line, index in
                        withAnimation { removed = RemovedLine(line: line, index: index, optionID: option.id) }
                    }
                )
            }
        }
    }

    private func optionBinding(_ snapshot: EstimateRevisionOptionDraft) -> Binding<EstimateRevisionOptionDraft> {
        Binding(get: { editor.options.first(where: { $0.id == snapshot.id }) ?? snapshot }, set: { value in
            guard value.id == snapshot.id, let index = editor.options.firstIndex(where: { $0.id == snapshot.id }) else { return }
            editor.options[index] = value
        })
    }

    private func descriptionValue(_ target: RevisionDescriptionTarget) -> String? {
        switch target.kind {
        case .line(let lineID, nil): return editor.lines.first(where: { $0.id == lineID })?.description
        case .line(let lineID, let optionID?): return editor.options.first(where: { $0.id == optionID })?.lines.first(where: { $0.id == lineID })?.description
        case .option(let optionID): return editor.options.first(where: { $0.id == optionID })?.description
        }
    }

    private func descriptionTargetAvailable(_ target: RevisionDescriptionTarget) -> Bool {
        guard !busy, canEdit, parentRecord == estimate, !editor.hasUnsupportedLineSources, documentGeneration == target.documentGeneration,
              estimate.id == target.estimateID, estimate.organizationId == session.activeOrganization?.id,
              estimate.status == target.parentStatus, estimate.currentRevisionNumber == target.parentRevision,
              editor.estimate.status == target.editorStatus, editor.estimate.currentRevisionNumber == target.editorRevision,
              descriptionValue(target) != nil else { return false }
        switch target.kind {
        case .line(_, nil): return true
        case .line(_, .some(_)), .option: return optionsFeatureEnabled
        }
    }

    private func showDescription(_ kind: RevisionDescriptionTarget.Kind) {
        guard !busy, canEdit, parentRecord == estimate, !editor.hasUnsupportedLineSources,
              estimate.organizationId == session.activeOrganization?.id,
              let actor = session.user?.id, let organization = session.activeOrganization?.id else { return }
        let scope = DescriptionCanvasScope(actor: actor, organization: organization, generation: session.generation, authority: session.authorityRevision)
        if descriptionOwnerScope == nil { descriptionOwnerScope = scope }
        guard descriptionOwnerScope == scope, !editorAccessRetired else { return }
        let target = RevisionDescriptionTarget(kind: kind, original: "", scope: scope, documentGeneration: documentGeneration,
            estimateID: estimate.id, parentStatus: estimate.status, parentRevision: estimate.currentRevisionNumber,
            editorStatus: editor.estimate.status, editorRevision: editor.estimate.currentRevisionNumber)
        guard let original = descriptionValue(target), descriptionTargetAvailable(target) else { return }
        descriptionAccessRetired = false
        descriptionTarget = RevisionDescriptionTarget(kind: kind, original: original, scope: scope, documentGeneration: documentGeneration,
            estimateID: estimate.id, parentStatus: estimate.status, parentRevision: estimate.currentRevisionNumber,
            editorStatus: editor.estimate.status, editorRevision: editor.estimate.currentRevisionNumber)
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

    private func sectionTitle(_ title: String, count: Int) -> some View {
        HStack(spacing: 7) {
            Text(title).font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
            Text("\(count)").font(Theme.monoFont(12)).foregroundStyle(Theme.muted)
        }
    }

    private var saveTitle: String {
        let verb = editingDraft ? "Save draft" : "Save revised draft"
        guard editor.options.isEmpty, let total = editor.lines.subtotal() else { return verb }
        return "\(verb) · \(money(total, currency: "USD"))"
    }

    private var reviewTitle: String {
        let count = editor.lines.count + editor.options.reduce(0) { $0 + $1.lines.count }
        return "Review estimate · \(count) \(count == 1 ? "item" : "items")"
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

    private func mutateTargetLines(_ change: (inout [EstimateRevisionLineDraft]) -> Void) {
        if let optionID = target.optionID {
            guard let index = editor.options.firstIndex(where: { $0.id == optionID }) else { return }
            change(&editor.options[index].lines)
        } else {
            change(&editor.lines)
        }
    }

    private func add(_ item: PriceBookListItem) {
        guard !busy else { return }
        var addedLine = false
        withAnimation(EstimateLineGroupsEditor.spring) {
            mutateTargetLines { addedLine = $0.addPriceBookItem(item, to: target.group) != nil }
        }
        guard addedLine else {
            error = EstimateRevisionEditorError.tooManyLines.localizedDescription
            return
        }
        error = nil
        catalog.recordUse(item.id)
        added += 1
    }

    private func addCustom(_ text: String) {
        guard !busy else { return }
        let group = target.group ?? (kind == .material ? .material : .work)
        var lineID: UUID?
        mutateTargetLines { lineID = $0.addCustomLine(text, to: group) }
        guard let lineID else {
            error = EstimateRevisionEditorError.tooManyLines.localizedDescription
            return
        }
        added += 1
        query = ""
        kind = .all
        target = EstimateBuilderTarget()
        focus = .price(lineID)
    }

    private func startAdding(optionID: String?, group: EstimateLineGroup) {
        target = EstimateBuilderTarget(optionID: optionID, group: group)
        kind = group == .material ? .material : .all
        focus = .search
    }

    private func finishSearch() {
        query = ""
        kind = .all
        target = EstimateBuilderTarget()
        focus = nil
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
        guard canEdit && editorScopeCurrent && parentRecord == estimate else {
            error = "The estimate or your access changed. Reopen the current estimate to continue."
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
            guard canEdit, editorScopeCurrent, revised.id == estimate.id,
                  revised.organizationId == estimate.organizationId, revised.customerId == estimate.customerId else {
                error = "The estimate or your access changed. Reopen it to verify the saved revision."
                return
            }
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
            let latest = try await api.fieldEstimate(estimate.id)
            documentGeneration = UUID()
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

private struct EstimateRevisionOptionEditor: View {
    @FocusState private var descriptionFocused: Bool
    @Binding var option: EstimateRevisionOptionDraft
    let showDescription: () -> Void
    let showLineDescription: (UUID) -> Void
    let disabled: Bool
    let focus: FocusState<EstimateBuilderFocus?>.Binding
    let addTo: (EstimateLineGroup) -> Void
    let removeOption: () -> Void
    let removed: (EstimateRevisionLineDraft, Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Option title", text: $option.title)
                    .font(Theme.font(17, weight: .medium))
                    .accessibilityLabel("Option package title")
                Text(option.lines.subtotal().map { money($0, currency: "USD") } ?? "—")
                    .font(Theme.monoFont(24, weight: .medium))
                    .contentTransition(.numericText())
                    .lineLimit(1).minimumScaleFactor(0.7)
                Button(action: removeOption) {
                    Image(systemName: "trash").foregroundStyle(Theme.destructive)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Remove \(option.title.isEmpty ? "option package" : option.title)")
            }
            if DescriptionPreview.isLong(option.description) && !descriptionFocused {
                Text(option.description).font(Theme.font(15)).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Option description: \(option.description)")
            } else {
                TextField("What this package includes", text: $option.description, axis: .vertical)
                    .font(Theme.font(15)).lineLimit(1...2).focused($descriptionFocused)
                    .accessibilityLabel("Option package description")
            }
            if !option.description.isEmpty && !descriptionFocused {
                Button(DescriptionPreview.isLong(option.description) ? "Show more" : "Read or edit", action: showDescription)
                    .font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.brandText)
                    .frame(minHeight: 44).accessibilityLabel(DescriptionPreview.isLong(option.description) ? "Show more option description" : "Read or edit option description")
                    .accessibilityIdentifier("estimate-option-description-more")
            }
            EstimateLineGroupsEditor(lines: $option.lines, disabled: disabled, focus: focus, addTo: addTo, showDescription: showLineDescription, removed: removed)
        }
        .disabled(disabled)
        .padding(14)
        .background(Theme.fill.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.border, lineWidth: 1))
    }
}

private extension View {
    func paperField() -> some View {
        font(Theme.font(14))
            .foregroundStyle(Theme.foreground)
            .padding(.horizontal, 13)
            .frame(minHeight: 46)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
    }
}

private struct RevisionDescriptionTarget: Identifiable {
    enum Kind { case line(UUID, String?); case option(String) }
    let id = UUID()
    let kind: Kind
    let original: String
    let scope: DescriptionCanvasScope
    let documentGeneration: UUID
    let estimateID: String
    let parentStatus: String
    let parentRevision: Int?
    let editorStatus: String
    let editorRevision: Int?
    var title: String { if case .option = kind { return "Option description" }; return "Line description" }
    var limit: DescriptionCanvasLimit { if case .option = kind { return .utf16Raw(500) }; return .utf16(200) }
}

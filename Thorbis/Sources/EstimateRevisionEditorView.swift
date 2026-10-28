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
    @ObservedObject private var catalog = PriceBookCatalog.shared
    @State private var query = ""
    @State private var kind = PriceBookKindFilter.all
    @State private var target = EstimateBuilderTarget()
    @State private var added = 0
    @State private var removed: RemovedLine?
    @FocusState private var focus: EstimateBuilderFocus?

    init(estimate: EstimateRecord, onSaved: @escaping (EstimateRecord) -> Void) {
        self.estimate = estimate
        self.onSaved = onSaved
        _editor = State(initialValue: EstimateRevisionEditorState(estimate: estimate))
    }

    private var canRevise: Bool {
        editor.canRevise && session.can("estimate.create", feature: "estimates")
    }

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

    private var canSave: Bool {
        !busy && canEdit && (editor.estimate.currentRevisionNumber ?? 0) > 0 &&
        editor.hasChanges && !editor.hasUnsupportedLineSources && (!editor.hasCreditLines || canDiscount)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if searching {
                    PriceBookResultsList(
                        catalog: catalog, context: PriceBookCatalogContext(organizationID: session.activeOrganization?.id, sessionGeneration: session.generation),
                            query: query, kind: kind, canUsePriceBook: canUsePriceBook,
                        quantityInCurrentDraft: { targetLines.quantity(ofPriceBookItem: $0) },
                        secondaryPriceText: { _ in nil }, addItem: add, addCustomLine: addCustom,
                        retry: { Task { await refreshCatalog(force: true) } }
                    )
                } else {
                VStack(alignment: .leading, spacing: 18) {
                    if let error { ErrorBanner(message: error) }
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
                    } else if (editor.estimate.currentRevisionNumber ?? 0) <= 0 {
                        ErrorBanner(message: EstimateRevisionEditorError.missingRevision.localizedDescription)
                    } else if !session.can("estimate.create", feature: "estimates") {
                        ErrorBanner(message: "Your account cannot create estimate revisions.")
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
                    Text("Saving creates a replacement draft for the current estimate revision. It will not be sent automatically.")
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
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .foregroundStyle(Theme.foreground)
            .navigationTitle("Revise estimate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if editor.hasChanges { confirmDiscard = true } else { dismiss() } }.disabled(busy)
                }
            }
            .keyboardDoneButton()
            .discardChangesGuard(hasChanges: editor.hasChanges, busy: busy, isPresented: $confirmDiscard) { dismiss() }
            .safeAreaInset(edge: .top, spacing: 0) {
                if canEdit {
                    EstimateSearchBar(query: $query, kind: $kind, focus: $focus, searching: searching,
                                      prompt: searchPrompt, finish: finishSearch)
                        .disabled(busy)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if let removed {
                        LineRemovedToast(removed: removed, undo: undoRemove, expire: { withAnimation { self.removed = nil } })
                    }
                    if focus != .search {
                        if editor.options.isEmpty { EstimateBuilderTotal(total: editor.lines.subtotal()) }
                        PaperActionBar(title: saveTitle, symbol: "doc.badge.plus", busy: busy, disabled: !canSave) {
                            Task { await save() }
                        }
                    }
                }
            }
            .sensoryFeedback(.success, trigger: added)
            .animation(EstimateLineGroupsEditor.spring, value: searching)
            .task(id: PriceBookCatalogContext(organizationID: session.activeOrganization?.id, sessionGeneration: session.generation)) { await refreshCatalog() }
            .onChange(of: catalog.items.map(\.id)) { classifyLines() }
            .confirmationDialog("Reload the latest estimate?", isPresented: $confirmReload, titleVisibility: .visible) {
                Button("Reload and discard my edits", role: .destructive) { Task { await reloadLatest() } }
                Button("Keep editing", role: .cancel) {}
            } message: {
                Text("The estimate changed on the server. Reloading replaces this form with its latest saved lines and options.")
            }
        }
    }

    private var estimateHeading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EST-\(editor.estimate.id.suffix(4).uppercased()) · REVISION \(editor.estimate.currentRevisionNumber ?? 0)")
                .font(Theme.monoFont(11, weight: .medium)).foregroundStyle(Theme.muted)
            Text("New replacement draft")
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
                lines: $editor.lines,
                disabled: busy || !canEdit || editor.hasUnsupportedLineSources,
                focus: $focus,
                addTo: { group in startAdding(optionID: nil, group: group) },
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
            ForEach($editor.options) { $option in
                EstimateRevisionOptionEditor(
                    option: $option,
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

    private func sectionTitle(_ title: String, count: Int) -> some View {
        HStack(spacing: 7) {
            Text(title).font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
            Text("\(count)").font(Theme.monoFont(12)).foregroundStyle(Theme.muted)
        }
    }

    private var saveTitle: String {
        guard editor.options.isEmpty, let total = editor.lines.subtotal() else { return "Save revised draft" }
        return "Save revised draft · \(money(total, currency: "USD"))"
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

    private func save() async {
        guard canRevise else {
            error = "You no longer have permission to revise this estimate."
            return
        }
        busy = true
        defer { busy = false }
        do {
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
            let latest = try await api.fieldEstimate(estimate.id)
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
    @Binding var option: EstimateRevisionOptionDraft
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
            TextField("What this package includes", text: $option.description, axis: .vertical)
                .font(Theme.font(15)).lineLimit(2...4)
                .accessibilityLabel("Option package description")
            EstimateLineGroupsEditor(lines: $option.lines, disabled: disabled, focus: focus, addTo: addTo, removed: removed)
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

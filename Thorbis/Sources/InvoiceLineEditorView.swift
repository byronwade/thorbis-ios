import SwiftUI

struct InvoiceLineEditorView: View {
    let invoice: InvoiceRecord
    let onSaved: (InvoiceRecord) -> Void

    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var editor: InvoiceLineEditorState
    @State private var showPriceBook = false
    @State private var confirmReload = false
    @State private var confirmIssue = false
    @State private var confirmDiscard = false
    @State private var busy = false
    @State private var error: String?
    @State private var staleRevision = false
    @ObservedObject private var catalog = PriceBookCatalog.shared
    @State private var addedLineSelection: InvoiceCatalogLineSelection?
    @State private var expandedLine: UUID?
    @FocusState private var focus: EstimateBuilderFocus?

    private var catalogContext: PriceBookCatalogContext {
        .init(organizationID: session.activeOrganization?.id, sessionGeneration: session.generation)
    }

    init(invoice: InvoiceRecord, onSaved: @escaping (InvoiceRecord) -> Void) {
        self.invoice = invoice
        self.onSaved = onSaved
        _editor = State(initialValue: InvoiceLineEditorState(invoice: invoice))
    }

    private var canEdit: Bool {
        editor.invoice.status == "draft" && session.can("invoice.edit", feature: "invoicing")
    }

    private var canUsePriceBook: Bool {
        session.can("pricebook.view", feature: "price_book") && invoice.currency == "USD"
    }

    private var canIssue: Bool {
        editor.invoice.status == "draft" && session.can("invoice.issue", feature: "invoicing")
    }

    private var linesDisabled: Bool { busy || !canEdit || editor.hasUnsupportedLineSources }

    var body: some View {
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
        }
        .background(Theme.canvas)
        .foregroundStyle(Theme.foreground)
        .navigationTitle("Edit invoice")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ThorbisToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { if editor.hasChanges { confirmDiscard = true } else { dismiss() } }.disabled(busy)
            }
        }
        .keyboardDoneButton()
        .task(id: catalogContext) { await refreshCatalog() }
        .onChange(of: catalogContext) { _, _ in addedLineSelection = nil; showPriceBook = false }
        .discardChangesGuard(hasChanges: editor.hasChanges, busy: busy, isPresented: $confirmDiscard) { dismiss() }
        .safeAreaInset(edge: .bottom) { invoiceCommitActions }
        .thorbisConfirm("Issue invoice?",
                        message: "The current lines will be saved first if needed, then locked as issued invoice paper.",
                        isPresented: $confirmIssue,
                        actions: [ThorbisConfirmAction("Issue invoice", role: .destructive) { Task { await issue() } }])
        .sheet(isPresented: $showPriceBook, onDismiss: openAddedLine) { SheetSurface {
            PriceBookCartPicker(
                destination: "INV-\(invoice.id.suffix(4).uppercased())",
                canUsePriceBook: canUsePriceBook,
                unavailableReason: invoice.currency == "USD" ? nil : "Catalog selection requires a USD invoice.",
                searchIdentifier: "invoice-catalog-search",
                quantityInDraft: { editor.quantity(ofPriceBookItem: $0) },
                secondaryPriceText: { memberPricing?.secondaryPriceText($0) },
                addItem: addCatalogItem,
                addCustomLine: addCustomLine,
                refresh: { await refreshCatalog(force: $0) }
            )
            .environmentObject(session).environmentObject(api)
        } }
        .task(id: "\(catalogContext.organizationID ?? "")|\(catalogContext.sessionGeneration)|\(invoice.customerId)") {
            memberPricing = nil
            guard canUsePriceBook else { return }
            let expected = catalogContext
            let pricing = try? await api.memberPricing(invoice.customerId)
            guard !Task.isCancelled, catalogContext == expected else { return }
            memberPricing = pricing
        }
        .thorbisConfirm("Reload the latest invoice?",
                        message: "The invoice changed on the server. Reloading replaces this form with the latest saved lines.",
                        isPresented: $confirmReload,
                        actions: [ThorbisConfirmAction("Reload and discard my edits", role: .destructive) { Task { await reloadLatest() } }])
        #if DEBUG
        .task {
            if PaperPreview.enabled, PaperPreview.screen == "invoice-editor-line" { expandedLine = editor.lines.first?.id }
        }
        #endif
    }

    @State private var memberPricing: MemberPricing?

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let error { ErrorBanner(message: error).padding(.horizontal, -Theme.gutter) }
            if staleRevision {
                Button { confirmReload = true } label: {
                    Label("Review latest invoice", systemImage: "arrow.clockwise")
                        .font(Theme.font(14, weight: .medium))
                        .foregroundStyle(Theme.brandText)
                        .frame(minHeight: 44)
                }
                .accessibilityHint("Reloads the current server version and discards these unsaved edits")
            }
            if editor.invoice.status != "draft" {
                ErrorBanner(message: "This invoice is now \(editor.invoice.status.statusLabel.lowercased()); its line items are final.")
            }
            if editor.hasUnsupportedLineSources {
                ErrorBanner(message: "This invoice has line provenance this app cannot safely retain. Review it in Thorbis web before editing.")
            }

            invoiceEditorHeading

            VStack(alignment: .leading, spacing: 6) {
                Text(editor.lines.isEmpty ? "Line items" : "Line items · \(editor.lines.count)")
                    .font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("invoice-line-count")
                    .padding(.horizontal, 4)
                PaperCard {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(editor.lines) { line in
                            lineRow(line)
                        }
                        Button { showPriceBook = true } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "plus").font(.system(size: 15, weight: .medium))
                                Text("Add item").font(Theme.font(16, weight: .medium))
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(Theme.foreground)
                            .padding(.horizontal, 14).frame(minHeight: 52).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(linesDisabled || editor.lines.count >= 500)
                        .accessibilityHint(canUsePriceBook ? "Opens the price book" : "Adds a custom line item")
                        .accessibilityIdentifier("invoice-add-item")
                    }
                }
            }

            if editor.needsPriceBookOverrideReason {
                priceBookOverrideReasonField
            }

            Text("Line changes are checked against the current invoice revision before saving.")
                .font(Theme.font(13)).foregroundStyle(Theme.muted)
                .padding(.horizontal, 4)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
    }

    /// The shared builder line, over an invoice draft line. Quantities still go through
    /// `committedLine` so the editor's own validation runs.
    private func lineRow(_ line: InvoiceLineDraft) -> some View {
        let binding = committedLine(lineBinding(line.id))
        let canMoveUp = editor.lines.first?.id != line.id
        let canMoveDown = editor.lines.last?.id != line.id
        var items: [ThorbisMenuItem] = []
        if canMoveUp { items.append(ThorbisMenuItem("Move up", icon: "arrow.up") { moveLine(line.id, offset: -1) }) }
        if canMoveDown { items.append(ThorbisMenuItem("Move down", icon: "arrow.down") { moveLine(line.id, offset: 1) }) }
        items.append(ThorbisMenuItem("Remove line", icon: "trash", role: .destructive) { removeLine(line.id) })
        let total: Int? = {
            guard let cents = InvoiceLineEditorState.priceCents(line.unitPrice),
                  let quantity = Int(line.quantity.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
            let (amount, overflow) = cents.multipliedReportingOverflow(by: quantity)
            return overflow ? nil : amount
        }()
        return BuilderLineRow(
            description: binding.description, quantity: binding.quantity, unitPrice: binding.unitPrice,
            lineID: line.id, currency: invoice.currency, lineTotal: total, unitLabel: line.unitLabel,
            note: sourceNote(line), menuItems: items, expanded: expandedLine == line.id,
            toggle: { withAnimation(EstimateLineGroupsEditor.spring) { expandedLine = expandedLine == line.id ? nil : line.id } },
            remove: { removeLine(line.id) }, focus: $focus,
            descriptionIdentifier: "invoice-line-description-\(line.id)",
            quantityIdentifier: "invoice-line-quantity-\(line.id)",
            priceIdentifier: "invoice-line-price-\(line.id)"
        )
        .disabled(linesDisabled)
        .accessibilityAction(named: "Move up") { if canMoveUp { moveLine(line.id, offset: -1) } }
        .accessibilityAction(named: "Move down") { if canMoveDown { moveLine(line.id, offset: 1) } }
    }

    private func sourceNote(_ line: InvoiceLineDraft) -> String? {
        switch line.source {
        case .priceBookSelection: "Price Book selection · server verifies the revision"
        case .retainedPriceBook: "Price Book source retained"
        case .estimate: "Estimate source retained"
        default: nil
        }
    }

    private func lineBinding(_ id: UUID) -> Binding<InvoiceLineDraft> {
        Binding(
            get: { editor.lines.first { $0.id == id } ?? InvoiceLineDraft(id: id, description: "", quantity: "1", unitPrice: "") },
            set: { value in if let index = editor.lines.firstIndex(where: { $0.id == id }) { editor.lines[index] = value } }
        )
    }

    private func removeLine(_ id: UUID) {
        do {
            try editor.removeLine(id: id)
            if expandedLine == id { expandedLine = nil }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// After the picker closes, the last catalog line it added opens for a price or wording check.
    private func openAddedLine() {
        guard canEdit, canUsePriceBook, !editor.hasUnsupportedLineSources,
              invoice.organizationId == catalogContext.organizationID,
              let id = addedLineSelection?.resolvedLineID(in: editor.lines, context: catalogContext) else { return }
        addedLineSelection = nil
        withAnimation(EstimateLineGroupsEditor.spring) { expandedLine = id }
    }

    /// Why the commits are off, in words under them (design.thorbis.com "Disabled needs a reason").
    private var commitBlockedReason: String? {
        guard !busy else { return nil }
        if !canEdit { return "Your role can't change this invoice." }
        if editor.hasUnsupportedLineSources { return "Some lines came from somewhere this phone can't edit. Change them on the web." }
        if !canIssue && !editor.hasChanges { return "No changes to save yet." }
        return nil
    }

    private var invoiceCommitActions: some View {
        VStack(alignment: .leading, spacing: 6) {
            invoiceCommitButtons
            if let reason = commitBlockedReason {
                Text(reason).font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 8)
        .background(Theme.canvas)
    }

    private var invoiceCommitButtons: some View {
        let accessible = dynamicTypeSize.isAccessibilitySize
        let layout = accessible ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            if canIssue {
                Button { Task { await save() } } label: {
                    Text("Save draft")
                    .font(Theme.font(17, weight: .medium))
                    .foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, accessible ? 16 : 0)
                    .padding(.vertical, accessible ? 12 : 0)
                    .frame(width: accessible ? nil : 132, height: accessible ? nil : Theme.commitHeight)
                    .frame(maxWidth: accessible ? .infinity : nil, minHeight: Theme.commitHeight)
                    .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                    .contentShape(RoundedRectangle(cornerRadius: Theme.controlRadius))
                }
                    .buttonStyle(PressStyle())
                    .disabled(busy || !canEdit || !editor.hasChanges || editor.hasUnsupportedLineSources)
                PrimaryButton(title: "Issue invoice", busy: busy) { confirmIssue = true }
                    .disabled(busy || !canEdit || editor.hasUnsupportedLineSources)
            } else {
                PrimaryButton(title: "Save draft", busy: busy) { Task { await save() } }
                    .disabled(busy || !canEdit || !editor.hasChanges || editor.hasUnsupportedLineSources)
            }
        }
    }

    private var priceBookOverrideReasonField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Reason for Price Book change")
                .font(Theme.font(12, weight: .medium)).foregroundStyle(Theme.muted)
            TextField("Describe the approved change", text: $editor.priceBookOverrideReason, axis: .vertical)
                .lineLimit(2...4)
                .font(Theme.font(14))
                .padding(12)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).stroke(Theme.border, lineWidth: 1))
                .disabled(busy || !canEdit || editor.hasUnsupportedLineSources)
                .accessibilityLabel("Reason for Price Book change")
        }
    }

    private func committedLine(_ line: Binding<InvoiceLineDraft>) -> Binding<InvoiceLineDraft> {
        Binding(
            get: { line.wrappedValue },
            set: { proposed in
                guard editor.invoice.status == "draft" else { return }
                var next = proposed
                let quantityText = proposed.quantity.trimmingCharacters(in: .whitespacesAndNewlines)
                if let quantity = Int(quantityText), (1...100_000).contains(quantity), String(quantity) == quantityText {
                    try? editor.setQuantity(proposed.id, quantity)
                    if let stored = editor.lines.first(where: { $0.id == proposed.id })?.quantity {
                        next.quantity = stored
                    }
                }
                line.wrappedValue = next
            }
        )
    }

    private func priceBookQuantity(_ itemID: String) -> Int? {
        editor.quantity(ofPriceBookItem: itemID)
    }

    /// One more of a price book item; returns why it couldn't be added, or nil.
    private func addCatalogItem(_ item: PriceBookListItem) -> String? {
        guard !busy, canEdit, !editor.hasUnsupportedLineSources, canUsePriceBook,
              invoice.organizationId == catalogContext.organizationID,
              catalog.context == catalogContext else { return "This invoice can't take price book items right now." }
        do {
            let before = editor.lines.map(\.id)
            try editor.addPriceBookItem(item)
            if let added = editor.lines.first(where: { !before.contains($0.id) }) ?? editor.lines.last {
                addedLineSelection = InvoiceCatalogLineSelection(lineID: added.id, context: catalogContext)
            }
            error = nil
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func addCustomLine(_ text: String) {
        guard !busy, canEdit, !editor.hasUnsupportedLineSources else { return }
        let before = editor.lines.count
        editor.addManualLine()
        guard editor.lines.count > before, let index = editor.lines.indices.last else {
            error = InvoiceLineEditorError.tooManyLines.localizedDescription
            return
        }
        editor.lines[index].description = text
        let id = editor.lines[index].id
        addedLineSelection = nil
        expandedLine = id
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            focus = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .description(id) : .price(id)
        }
    }

    private func refreshCatalog(force: Bool = false) async {
        guard canUsePriceBook else { return }
        let expected = catalogContext
        await catalog.refresh(api: api, organizationID: expected.organizationID,
                              sessionGeneration: expected.sessionGeneration, force: force)
    }

    private var invoiceEditorHeading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("INV-\(invoice.id.suffix(4).uppercased())")
                .font(Theme.monoFont(12, weight: .medium)).foregroundStyle(Theme.muted)
            HStack(spacing: 8) {
                Text(editor.invoice.status.statusLabel)
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(editor.invoice.status == "draft" ? Theme.warning : Theme.muted)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Theme.warningSurface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                Text("Revision \(editor.invoice.linesRevision)")
                    .font(Theme.font(12)).foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func editorDetail(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label).foregroundStyle(Theme.muted)
            Spacer(minLength: 12)
            Text(value).foregroundStyle(Theme.foreground).multilineTextAlignment(.trailing)
        }
        .font(Theme.font(13)).padding(.vertical, 8)
    }

    private func save() async {
        guard canEdit else {
            error = "You no longer have permission to edit this invoice."
            return
        }
        guard editor.hasChanges else { return }
        busy = true
        defer { busy = false }
        do {
            commitPrices()
            let request = try editor.makeRequest()
            let updated = try await api.replaceFieldInvoiceLines(invoice.id, request: request)
            addedLineSelection = nil
            onSaved(updated)
            dismiss()
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
            staleRevision = (error as? Problem)?.status == 409
        }
    }

    /// Canonicalize a finished price at save time. Live keystrokes keep the raw text.
    private func commitPrices() {
        for line in editor.lines {
            guard let cents = InvoiceLineEditorState.priceCents(line.unitPrice) else { continue }
            try? editor.setUnitPrice(line.id, cents: cents)
        }
    }

    private func moveLine(_ id: UUID, offset: Int) {
        guard let index = editor.lines.firstIndex(where: { $0.id == id }) else { return }
        editor.moveLine(id: id, to: index + offset)
    }

    private func reloadLatest() async {
        busy = true
        defer { busy = false }
        do {
            let current = try await api.liveFieldInvoice(invoice.id)
            addedLineSelection = nil
            editor = InvoiceLineEditorState(invoice: current)
            staleRevision = false
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func issue() async {
        guard canIssue, canEdit else {
            error = "You no longer have permission to issue this invoice."
            return
        }
        busy = true
        defer { busy = false }
        do {
            commitPrices()
            var current = editor.invoice
            if editor.hasChanges {
                current = try await api.replaceFieldInvoiceLines(invoice.id, request: editor.makeRequest())
                addedLineSelection = nil
                editor = InvoiceLineEditorState(invoice: current)
                onSaved(current)
            }
            let issued = try await api.issueFieldInvoice(invoice.id, expectedLinesRevision: current.linesRevision)
            onSaved(issued)
            dismiss()
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
            staleRevision = (error as? Problem)?.status == 409
        }
    }
}

/// A catalogue quick editor never resolves by description, source item, or array position.
struct InvoiceCatalogLineSelection: Equatable {
    let lineID: UUID
    let context: PriceBookCatalogContext

    func resolvedLineID(in lines: [InvoiceLineDraft], context current: PriceBookCatalogContext) -> UUID? {
        guard context == current, current.organizationID?.isEmpty == false,
              lines.filter({ $0.id == lineID }).count == 1 else { return nil }
        return lineID
    }
}

import SwiftUI

struct InvoiceLineEditorView: View {
    let invoice: InvoiceRecord
    let onSaved: (InvoiceRecord) -> Void

    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var editor: InvoiceLineEditorState
    @State private var showPriceBook = false
    @State private var confirmReload = false
    @State private var confirmIssue = false
    @State private var confirmDiscard = false
    @State private var busy = false
    @State private var error: String?
    @State private var staleRevision = false
    @ObservedObject private var catalog = PriceBookCatalog.shared
    @State private var query = ""
    @State private var kind = PriceBookKindFilter.all
    @FocusState private var focus: EstimateBuilderFocus?

    private var searching: Bool { canEdit && (focus == .search || !query.isEmpty) }

    init(invoice: InvoiceRecord, onSaved: @escaping (InvoiceRecord) -> Void) {
        self.invoice = invoice
        self.onSaved = onSaved
        _editor = State(initialValue: InvoiceLineEditorState(invoice: invoice))
    }

    private var canEdit: Bool {
        editor.invoice.status == "draft" && session.can("invoice.edit", feature: "invoicing")
    }

    private var canUsePriceBook: Bool {
        session.can("pricebook.view", feature: "price_book")
    }

    private var canIssue: Bool {
        editor.invoice.status == "draft" && session.can("invoice.issue", feature: "invoicing")
    }

    var body: some View {
        ScrollView {
            if let error {
                ErrorBanner(message: error).padding(.horizontal, 20).padding(.top, 12)
            }
            if staleRevision {
                Button { confirmReload = true } label: {
                    Label("Review latest invoice", systemImage: "arrow.clockwise")
                        .font(Theme.font(14, weight: .medium))
                        .foregroundStyle(Theme.brandText)
                }
                .accessibilityHint("Reloads the current server version and discards these unsaved edits")
                .padding(.horizontal, 20)
            }
            if searching {
                PriceBookResultsList(
                    catalog: catalog, query: query, kind: kind, canUsePriceBook: canUsePriceBook,
                    quantityOnEstimate: priceBookQuantity, addItem: addCatalogItem, addCustom: addCustomLine,
                    retry: { Task { await refreshCatalog(force: true) } }
                )
                .disabled(busy)
            } else {
            VStack(alignment: .leading, spacing: 18) {
                if editor.invoice.status != "draft" {
                    ErrorBanner(message: "This invoice is now \(editor.invoice.status.statusLabel.lowercased()); its line items are final.")
                }
                if editor.hasUnsupportedLineSources {
                    ErrorBanner(message: "This invoice has line provenance this app cannot safely retain. Review it in Thorbis web before editing.")
                }

                invoiceEditorHeading

                VStack(alignment: .leading, spacing: 2) {
                    Text("Details").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                        .padding(.horizontal, 2).padding(.bottom, 4)
                    editorDetail("Customer", store.customerName(invoice.customerId))
                    if let job = store.jobs.first(where: { $0.id == invoice.jobId }) {
                        editorDetail("Job", "\(job.title) · \(job.shortRef)")
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Line items").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                        Spacer()
                        if canUsePriceBook {
                            Button { showPriceBook = true } label: {
                                Label("Add from price book", systemImage: "book.closed")
                                    .font(Theme.font(13, weight: .medium))
                            }
                            .disabled(busy || !canEdit || editor.hasUnsupportedLineSources)
                        }
                    }

                    VStack(spacing: 0) {
                        ForEach($editor.lines) { $line in
                            EditableInvoiceLineRow(
                                line: committedLine($line),
                                canMoveUp: editor.lines.first?.id != line.id,
                                canMoveDown: editor.lines.last?.id != line.id,
                                moveUp: { moveLine(line.id, offset: -1) },
                                moveDown: { moveLine(line.id, offset: 1) },
                                remove: {
                                    do {
                                        try editor.removeLine(id: line.id)
                                        error = nil
                                    } catch {
                                        self.error = error.localizedDescription
                                    }
                                }
                            )
                            .disabled(busy || !canEdit || editor.hasUnsupportedLineSources)
                            if line.id != editor.lines.last?.id {
                                Rectangle().fill(Theme.border).frame(height: 1).padding(.leading, 14)
                            }
                        }
                        Button {
                            editor.addManualLine()
                        } label: {
                            Label("Add line item", systemImage: "plus")
                                .font(Theme.font(13, weight: .medium))
                                .foregroundStyle(Theme.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14).frame(minHeight: 46)
                        }
                        .disabled(busy || !canEdit || editor.hasUnsupportedLineSources || editor.lines.count >= 500)
                    }
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.border, lineWidth: 1))

                    if editor.needsPriceBookOverrideReason {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Reason for Price Book change")
                                .font(Theme.font(12, weight: .medium)).foregroundStyle(Theme.muted)
                            TextField("Describe the approved change", text: $editor.priceBookOverrideReason, axis: .vertical)
                                .lineLimit(2...4)
                                .font(Theme.font(14))
                                .padding(12)
                                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                                .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).stroke(Theme.border, lineWidth: 1))
                                .disabled(busy || !canEdit || editor.hasUnsupportedLineSources)
                                .accessibilityLabel("Reason for Price Book change")
                        }
                    }

                    Text("Line changes are checked against the current invoice revision before saving.")
                        .font(Theme.font(12)).foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .foregroundStyle(Theme.foreground)
        .navigationTitle("Edit invoice")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { if editor.hasChanges { confirmDiscard = true } else { dismiss() } }.disabled(busy)
            }
        }
        .keyboardDoneButton()
        .safeAreaInset(edge: .top, spacing: 0) {
            if canEdit && !editor.hasUnsupportedLineSources {
                EstimateSearchBar(query: $query, kind: $kind, focus: $focus, searching: searching,
                                  prompt: "Search price book or type a line", finish: finishSearch)
                    .disabled(busy)
            }
        }
        .task { await refreshCatalog() }
        .discardChangesGuard(hasChanges: editor.hasChanges, busy: busy, isPresented: $confirmDiscard) { dismiss() }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                if canIssue {
                    Button("Save draft") { Task { await save() } }
                        .font(Theme.font(17, weight: .medium))
                        .foregroundStyle(Theme.foreground)
                        .frame(width: 132, height: Theme.commitHeight)
                        .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                        .buttonStyle(PressStyle())
                        .disabled(busy || !canEdit || !editor.hasChanges || editor.hasUnsupportedLineSources)
                    PrimaryButton(title: "Issue invoice", busy: busy) { confirmIssue = true }
                        .disabled(busy || !canEdit || editor.hasUnsupportedLineSources)
                } else {
                    PrimaryButton(title: "Save draft", busy: busy) { Task { await save() } }
                        .disabled(busy || !canEdit || !editor.hasChanges || editor.hasUnsupportedLineSources)
                }
            }
            .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 8)
            .background(Theme.chrome)
        }
        .confirmationDialog("Issue invoice?", isPresented: $confirmIssue, titleVisibility: .visible) {
            Button("Issue invoice", role: .destructive) { Task { await issue() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The current lines will be saved first if needed, then locked as issued invoice paper.")
        }
        .sheet(isPresented: $showPriceBook) {
            NavigationStack {
                PaperPriceBookPicker(api: api, currency: invoice.currency, customerID: invoice.customerId,
                    draft: $editor) { item in
                    try editor.addPriceBookItem(item)
                    error = nil
                }
                .environmentObject(session)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog("Reload the latest invoice?", isPresented: $confirmReload, titleVisibility: .visible) {
            Button("Reload and discard my edits", role: .destructive) { Task { await reloadLatest() } }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("The invoice changed on the server. Reloading replaces this form with the latest saved lines.")
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
        editor.catalogQuantity(for: itemID)
    }

    private func addCatalogItem(_ item: PriceBookListItem) {
        guard !busy else { return }
        do {
            try editor.addPriceBookItem(item)
            error = nil
            catalog.recordUse(item.id)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func addCustomLine(_ text: String) {
        guard !busy else { return }
        let before = editor.lines.count
        editor.addManualLine()
        guard editor.lines.count > before, let index = editor.lines.indices.last else {
            error = InvoiceLineEditorError.tooManyLines.localizedDescription
            return
        }
        editor.lines[index].description = text
        finishSearch()
    }

    private func finishSearch() {
        query = ""
        kind = .all
        focus = nil
    }

    private func refreshCatalog(force: Bool = false) async {
        guard canUsePriceBook else { return }
        await catalog.refresh(api: api, organizationID: session.activeOrganization?.id, force: force)
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
            let current = try await api.fieldInvoice(invoice.id)
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

private struct EditableInvoiceLineRow: View {
    @Binding var line: InvoiceLineDraft
    let canMoveUp: Bool
    let canMoveDown: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 8) {
                TextField("Line item description", text: $line.description, axis: .vertical)
                    .font(Theme.font(15, weight: .medium))
                    .lineLimit(1...3)
                    .accessibilityLabel("Line item description")
                    .accessibilityIdentifier("invoice-line-description-\(line.id)")
                LineItemActions(name: line.description, canMoveUp: canMoveUp, canMoveDown: canMoveDown,
                                moveUp: moveUp, moveDown: moveDown, remove: remove)
            }
            HStack(spacing: 8) {
                Text("Qty").font(Theme.font(13)).foregroundStyle(Theme.muted)
                LineNumberField(label: "Quantity", placeholder: "1", text: $line.quantity)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("invoice-line-quantity-\(line.id)")
                if let unit = line.unitLabel, !unit.isEmpty {
                    Text("/ \(unit)").font(Theme.font(13)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 8)
                LineNumberField(label: "Unit price in dollars", placeholder: "0.00", text: $line.unitPrice,
                                prefix: "$", decimal: true, width: 128)
            }
            if case .priceBookSelection = line.source {
                Text("Price Book selection · server verifies the revision")
                    .font(Theme.font(12)).foregroundStyle(Theme.muted)
            } else if case .retainedPriceBook = line.source {
                Text("Price Book source retained")
                    .font(Theme.font(12)).foregroundStyle(Theme.muted)
            } else if case .estimate = line.source {
                Text("Estimate source retained")
                    .font(Theme.font(12)).foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

struct PaperPriceBookPicker: View {
    @ObservedObject var api: APIClient
    @EnvironmentObject private var session: SessionController
    @Environment(\.dismiss) private var dismiss
    let currency: String
    var customerID: String? = nil
    @Binding var draft: InvoiceLineEditorState
    let onSelect: (PriceBookListItem) throws -> Void

    @ObservedObject private var catalog = PriceBookCatalog.shared
    @State private var memberPricing: MemberPricing?
    @State private var search = ""
    @State private var kind: PriceBookKindFilter = .all
    @State private var error: String?
    @FocusState private var focus: EstimateBuilderFocus?

    private var context: PriceBookCatalogContext {
        .init(organizationID: session.activeOrganization?.id, sessionGeneration: session.generation)
    }
    private var canUsePriceBook: Bool {
        session.can("pricebook.view", feature: "price_book") && currency == "USD"
    }

    var body: some View {
        let currentDraft = draft
        VStack(spacing: 0) {
            if !canUsePriceBook {
                ContentUnavailableView("Price Book unavailable", systemImage: "book.closed",
                    description: Text(currency == "USD" ? "This account cannot select Price Book items." : "Catalog selection requires a USD invoice."))
            } else {
                EstimateSearchBar(query: $search, kind: $kind, focus: $focus, searching: focus == .search,
                    prompt: "Search price book", keepFiltersVisible: kind != .all, finish: { focus = nil })
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("price-book-search")
                ScrollView {
                    VStack(spacing: 0) {
                        if let error { ErrorBanner(message: error).padding(.horizontal, Theme.gutter) }
                        PriceBookResultsList(catalog: catalog, context: context, query: search, kind: kind,
                            canUsePriceBook: canUsePriceBook,
                            quantityInCurrentDraft: { currentDraft.quantity(ofPriceBookItem: $0) },
                            secondaryPriceText: memberPriceText, addItem: select, addCustomLine: nil,
                            retry: { Task { await refresh(force: true) } })
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .refreshable { await refresh(force: true) }
            }
        }
        .background(Theme.background)
        .navigationTitle("Add from Price Book")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
        }
        .task(id: context) {
            memberPricing = nil
            error = nil
            await refresh()
        }
        .task(id: "\(context.organizationID ?? "")|\(context.sessionGeneration)|\(customerID ?? "")") {
            memberPricing = nil
            guard canUsePriceBook, let customerID else { return }
            let expected = context
            let pricing = try? await api.memberPricing(customerID)
            guard !Task.isCancelled, context == expected else { return }
            memberPricing = pricing
        }
    }

    private func refresh(force: Bool = false) async {
        guard canUsePriceBook else { return }
        let expected = context
        await catalog.refresh(api: api, organizationID: expected.organizationID,
                              sessionGeneration: expected.sessionGeneration, force: force)
    }

    private func select(_ item: PriceBookListItem) {
        guard canUsePriceBook, catalog.context == context else { return }
        do {
            try onSelect(item)
            error = nil
            catalog.recordUse(item.id)
        } catch { self.error = error.localizedDescription }
    }

    private func memberPriceText(_ item: PriceBookListItem) -> String? {
        guard let memberPricing, memberPricing.isMember, memberPricing.discountPercent > 0 else { return nil }
        return "Member \(money(memberPricing.memberPrice(item.sellPrice.amount), currency: item.sellPrice.currency))"
    }
}

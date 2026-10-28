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
    @State private var busy = false
    @State private var error: String?
    @State private var staleRevision = false

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
            VStack(alignment: .leading, spacing: 18) {
                if let error { ErrorBanner(message: error) }
                if staleRevision {
                    Button { confirmReload = true } label: {
                        Label("Review latest invoice", systemImage: "arrow.clockwise")
                            .font(Theme.font(14, weight: .medium))
                            .foregroundStyle(Theme.brandText)
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

                VStack(alignment: .leading, spacing: 2) {
                    Text("Details").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                        .padding(.horizontal, 2).padding(.bottom, 4)
                    editorDetail("Customer", store.customerName(invoice.customerId))
                    if let job = store.jobs.first(where: { $0.id == invoice.jobId }) {
                        editorDetail("Job", "\(job.title) · \(job.shortRef)")
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))

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
                                line: $line,
                                canMoveUp: editor.lines.first?.id != line.id,
                                canMoveDown: editor.lines.last?.id != line.id,
                                moveUp: { moveLine(line.id, offset: -1) },
                                moveDown: { moveLine(line.id, offset: 1) },
                                remove: { editor.removeLine(id: line.id) }
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
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))

                    if editor.needsPriceBookOverrideReason {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Reason for Price Book change")
                                .font(Theme.font(12, weight: .medium)).foregroundStyle(Theme.muted)
                            TextField("Describe the approved change", text: $editor.priceBookOverrideReason, axis: .vertical)
                                .lineLimit(2...4)
                                .font(Theme.font(14))
                                .padding(12)
                                .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
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
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .foregroundStyle(Theme.foreground)
        .navigationTitle("Edit invoice")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }.disabled(busy)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                if canIssue {
                    Button("Save draft") { Task { await save() } }
                        .font(Theme.font(15, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                        .frame(width: 132, height: 46)
                        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12))
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
                PaperPriceBookPicker(api: api, currency: invoice.currency) { item in
                    do {
                        try editor.addPriceBookItem(item)
                        error = nil
                    } catch {
                        self.error = error.localizedDescription
                    }
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

    private var invoiceEditorHeading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("INV-\(invoice.id.suffix(4).uppercased())")
                .font(Theme.monoFont(12, weight: .medium)).foregroundStyle(Theme.muted)
            HStack(spacing: 8) {
                Text(editor.invoice.status.statusLabel)
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(editor.invoice.status == "draft" ? Theme.warning : Theme.muted)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Theme.warningSurface, in: RoundedRectangle(cornerRadius: 8))
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
                    .font(Theme.font(14, weight: .medium))
                    .lineLimit(1...3)
                    .accessibilityLabel("Line item description")
                Button(action: moveUp) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .disabled(!canMoveUp)
                .accessibilityLabel("Move \(line.description.isEmpty ? "line item" : line.description) up")
                Button(action: moveDown) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .disabled(!canMoveDown)
                .accessibilityLabel("Move \(line.description.isEmpty ? "line item" : line.description) down")
                Button(action: remove) {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.destructive)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Remove \(line.description.isEmpty ? "line item" : line.description)")
            }
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Text("Qty").font(Theme.font(12)).foregroundStyle(Theme.muted)
                    TextField("1", text: $line.quantity)
                        .keyboardType(.numberPad)
                        .font(Theme.monoFont(12))
                        .frame(width: 48)
                        .accessibilityLabel("Quantity")
                }
                if let unit = line.unitLabel, !unit.isEmpty {
                    Text("/ \(unit)").font(Theme.font(11)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    Text("$").foregroundStyle(Theme.muted)
                    TextField("0.00", text: $line.unitPrice)
                        .keyboardType(.decimalPad)
                        .font(Theme.monoFont(13, weight: .medium))
                        .multilineTextAlignment(.trailing)
                        .frame(minWidth: 78, maxWidth: 112)
                        .accessibilityLabel("Unit price in dollars")
                }
            }
            if case .priceBookSelection = line.source {
                Text("Price Book selection · server verifies the revision")
                    .font(Theme.font(11)).foregroundStyle(Theme.muted)
            } else if case .retainedPriceBook = line.source {
                Text("Price Book source retained")
                    .font(Theme.font(11)).foregroundStyle(Theme.muted)
            } else if case .estimate = line.source {
                Text("Estimate source retained")
                    .font(Theme.font(11)).foregroundStyle(Theme.muted)
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
    let onSelect: (PriceBookListItem) -> Void

    @State private var items: [PriceBookListItem] = []
    @State private var cursor: String?
    @State private var search = ""
    @State private var loading = false
    @State private var error: String?

    private var visibleItems: [PriceBookListItem] {
        items.filter { item in
            item.archivedAt == nil && item.sellPrice.currency == currency &&
            (search.isEmpty || item.description.localizedCaseInsensitiveContains(search) ||
             item.kind.localizedCaseInsensitiveContains(search) || item.unit.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !session.can("pricebook.view", feature: "price_book") {
                ContentUnavailableView("Price Book unavailable", systemImage: "book.closed",
                    description: Text("This account cannot select Price Book items."))
            } else {
                PaperSearchField(text: $search, prompt: "Search loaded items")
                List {
                    if let error { ErrorBanner(message: error) }
                    ForEach(visibleItems) { item in
                        Button {
                            onSelect(item)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.description).font(Theme.font(14, weight: .medium))
                                        .foregroundStyle(Theme.foreground)
                                    Text("\(item.kind.capitalized) · \(item.unit) · Revision \(item.revision)")
                                        .font(Theme.font(12)).foregroundStyle(Theme.muted)
                                }
                                Spacer(minLength: 8)
                                Text(money(item.sellPrice.amount, currency: item.sellPrice.currency))
                                    .font(Theme.monoFont(13, weight: .medium)).foregroundStyle(Theme.foreground)
                            }
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Theme.card)
                    }
                    if cursor != nil {
                        Button { Task { await loadMore() } } label: {
                            HStack {
                                Spacer()
                                if loading { ProgressView() } else { Text("Load more items") }
                                Spacer()
                            }
                        }
                        .disabled(loading)
                        .listRowBackground(Theme.card)
                    }
                    if visibleItems.isEmpty && !loading && error == nil {
                        ContentUnavailableView(items.isEmpty ? "No active Price Book items" : "No matching items",
                                               systemImage: "book.closed")
                            .listRowBackground(Theme.background)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Theme.background)
                .refreshable { await refresh() }
                .task { await refresh() }
            }
        }
        .background(Theme.background)
        .navigationTitle("Add from Price Book")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
    }

    private func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let page = try await api.priceBookItems(limit: 50)
            items = page.items
            cursor = page.nextCursor
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard !loading, let cursor else { return }
        loading = true
        defer { loading = false }
        do {
            let page = try await api.priceBookItems(limit: 50, cursor: cursor)
            let existing = Set(items.map(\.id))
            items.append(contentsOf: page.items.filter { !existing.contains($0.id) })
            self.cursor = page.nextCursor
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }
}

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
    @State private var showMaterials = false
    @State private var reopenPriceBook = false
    /// Paper 33: the price book is Add materials' third segment; leaving it for Scan or Paste
    /// reopens Add materials in that mode once the picker has closed.
    @State private var materialsMode = AddMaterialsMode.scan
    @State private var reopenMaterials = false
    @State private var confirmReload = false
    @State private var confirmIssue = false
    @State private var confirmDiscard = false
    @State private var busy = false
    @State private var error: String?
    @State private var staleRevision = false
    @ObservedObject private var catalog = PriceBookCatalog.shared
    @State private var addedLineSelection: InvoiceCatalogLineSelection?
    @State private var expandedLine: UUID?
    @State private var keyboardUp = false
    @FocusState private var focus: EstimateBuilderFocus?

    private var catalogContext: PriceBookCatalogContext {
        .init(organizationID: session.activeOrganization?.id, sessionGeneration: session.generation, authority: session.priceBookAuthority)
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
                // The keyboard's floating Done control sits above the keyboard safe area.
                // Reserve room inside the scroll view so line actions can move above it.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if keyboardUp { Color.clear.frame(height: 72).allowsHitTesting(false) }
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
                // Focus centres the line before the keyboard has taken its room. Centre it again
                // in what is left, or the line's Done and Remove can end level with the keyboard's
                // Done bar, which takes every tap across its width.
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                    guard let id = focus?.lineID else { return }
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                }
        }
        .environment(\.builderDocumentLabel, "INV-\(invoice.id.suffix(4).uppercased())")
        .background(Theme.canvas)
        .paperPageGround()
        .foregroundStyle(Theme.foreground)
        // Paper 40: the page draws its own circle row and 34 Bold title; no bar.
        .navigationTitle("Edit invoice")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) { editorTopBar }
        .keyboardDoneButton()
        .trackKeyboard($keyboardUp)
        .task(id: catalogContext) { await refreshCatalog() }
        .onChange(of: catalogContext) { previous, current in
            if !previous.preservesInvoicePickerState(comparedTo: current) {
                addedLineSelection = nil
                showPriceBook = false
            }
        }
        .discardChangesGuard(hasChanges: editor.hasChanges, busy: busy, isPresented: $confirmDiscard) { dismiss() }
        .safeAreaInset(edge: .bottom) { if !keyboardUp { invoiceCommitActions } }
        .thorbisConfirm("Issue invoice?",
                        message: "The current lines will be saved first if needed, then locked as issued invoice paper.",
                        isPresented: $confirmIssue,
                        actions: [ThorbisConfirmAction("Issue invoice") { Task { await issue() } }])
        // The price book opens only once this sheet has finished closing (two sheets can't overlap).
        .sheet(isPresented: $showMaterials, onDismiss: {
            openAddedLine()
            if reopenPriceBook { reopenPriceBook = false; showPriceBook = true }
        }) { SheetSurface {
            AddMaterialsSheet(initialMode: materialsMode, canUsePriceBook: canUsePriceBook,
                              unavailableReason: invoice.currency == "USD" ? nil : "Catalog selection requires a USD invoice.",
                              addItem: addCatalogItem,
                              refresh: { await refreshCatalog(force: $0) },
                              openPriceBook: { reopenPriceBook = true })
            .environmentObject(session).environmentObject(api)
        } }
        .sheet(isPresented: $showPriceBook, onDismiss: {
            openAddedLine()
            if reopenMaterials { reopenMaterials = false; showMaterials = true }
        }) { SheetSurface {
            PriceBookCartPicker(
                destination: "INV-\(invoice.id.suffix(4).uppercased())",
                canUsePriceBook: canUsePriceBook,
                unavailableReason: invoice.currency == "USD" ? nil : "Catalog selection requires a USD invoice.",
                searchIdentifier: "invoice-catalog-search",
                quantityInDraft: { editor.quantity(ofPriceBookItem: $0) },
                secondaryPriceText: { memberPricing?.secondaryPriceText($0) },
                addItem: addCatalogItem,
                addCustomLine: addCustomLine,
                refresh: { await refreshCatalog(force: $0) },
                materialModes: canUsePriceBook ? AddMaterialsMode.allCases.map { $0.title } : [],
                switchMode: { name in
                    materialsMode = AddMaterialsMode.allCases.first(where: { $0.title == name }) ?? .scan
                    reopenMaterials = true
                }
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
                        message: "The invoice changed on the server. Reloading replaces this form with the latest saved lines and discards your edits.",
                        isPresented: $confirmReload,
                        actions: [ThorbisConfirmAction("Reload", role: .destructive) { Task { await reloadLatest() } }])
        #if DEBUG
        .task {
            if PaperPreview.enabled, PaperPreview.screen == "invoice-editor-line" { expandedLine = editor.lines.first?.id }
        }
        #endif
    }

    @State private var memberPricing: MemberPricing?

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let error { ErrorBanner(message: error).padding(.horizontal, -PaperCardMetrics.margin) }
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
                .padding(.bottom, 4)

            detailsCard

            // Paper 40: Add item as its own field, then "Line items" and the lines on one card.
            VStack(alignment: .leading, spacing: 10) {
                Button { showPriceBook = true } label: {
                    HStack(spacing: 8) {
                        PaperIcon(.plusLight, size: 18, color: Theme.brandText)
                        Text("Add item").font(Theme.font(16)).foregroundStyle(Theme.muted)
                        Spacer(minLength: 8)
                        Text(canUsePriceBook ? "Price book or custom" : "Custom item").font(Theme.font(13))
                            .foregroundStyle(Theme.muted).lineLimit(1)
                    }
                    .padding(.horizontal, 12).frame(minHeight: 48)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(PressStyle())
                .disabled(linesDisabled || editor.lines.count >= 500)
                .accessibilityLabel("Add item")
                .accessibilityHint(canUsePriceBook ? "Opens the price book" : "Adds a custom line item")
                .accessibilityIdentifier("invoice-add-item")
                // Tests read the count after the "·", so the label keeps "Line items · N".
                // Paper 40: "Line items" with the count on the trailing side; spoken (and read by tests) as one.
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Line items").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                    Spacer(minLength: 0)
                    if !editor.lines.isEmpty {
                        Text("\(editor.lines.count) item\(editor.lines.count == 1 ? "" : "s")").font(Theme.font(13))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(editor.lines.isEmpty ? "Line items" : "Line items · \(editor.lines.count)")
                .accessibilityAddTraits([.isHeader, .isStaticText])
                .accessibilityIdentifier("invoice-line-count")
                .padding(.horizontal, 4)
                if !editor.lines.isEmpty {
                    PaperCard {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(editor.lines) { line in
                                lineRow(line)
                                    .overlay(alignment: .top) {
                                        if line.id != editor.lines.first?.id { WellDivider(leading: 16) }
                                    }
                            }
                        }
                    }
                    Text("Tap an item to edit its name or price. At quantity 1, minus becomes remove.")
                        .font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4).padding(.top, 8)
                    totalsCard
                }
            }

            if editor.needsPriceBookOverrideReason {
                priceBookOverrideReasonField
            }
        }
        .padding(.horizontal, PaperCardMetrics.margin)
        .padding(.top, 0)
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
            note: nil, menuItems: items, expanded: expandedLine == line.id,
            toggle: {
                if expandedLine == line.id {
                    // The row disappears when closed, so finish its focused price before
                    // removing the field that normally formats it on focus loss.
                    if focus == .price(line.id), let cents = InvoiceLineEditorState.priceCents(line.unitPrice) {
                        try? editor.setUnitPrice(line.id, cents: cents)
                    }
                    focus = nil
                }
                withAnimation(EstimateLineGroupsEditor.spring) { expandedLine = expandedLine == line.id ? nil : line.id }
            },
            remove: { removeLine(line.id) }, focus: $focus,
            descriptionIdentifier: "invoice-line-description-\(line.id)",
            quantityIdentifier: "invoice-line-quantity-\(line.id)",
            priceIdentifier: "invoice-line-price-\(line.id)",
            lineActionsLeading: keyboardUp,
            sourceLabel: sourceLabel(line)
        )
        .disabled(linesDisabled)
        .accessibilityAction(named: "Move up") { if canMoveUp { moveLine(line.id, offset: -1) } }
        .accessibilityAction(named: "Move down") { if canMoveDown { moveLine(line.id, offset: 1) } }
    }

    /// Paper 40: where the line came from, before its price ("Price book · $120.00").
    private func sourceLabel(_ line: InvoiceLineDraft) -> String {
        switch line.source {
        case .priceBookSelection, .retainedPriceBook: return "Price book"
        case .estimate: return "Estimate"
        default: return "Custom"
        }
    }

    /// The lines' sum in cents; nil while a line has no valid price or quantity.
    private var linesTotal: Int? {
        var sum = 0
        for line in editor.lines {
            guard let cents = InvoiceLineEditorState.priceCents(line.unitPrice),
                  let quantity = Int(line.quantity.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
            let (amount, overflow) = cents.multipliedReportingOverflow(by: quantity)
            let (next, overflowSum) = sum.addingReportingOverflow(amount)
            guard !overflow, !overflowSum else { return nil }
            sum = next
        }
        return sum
    }

    /// Paper 40's totals card: the subtotal, then the total at 34 Bold.
    private var totalsCard: some View {
        let value = linesTotal.map { money($0, currency: invoice.currency) } ?? "\u{2014}"
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Subtotal").font(Theme.font(15)).foregroundStyle(Theme.subtle)
                Spacer(minLength: 8)
                Text(value).font(Theme.monoFont(15)).foregroundStyle(Theme.subtle)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Total").font(Theme.font(16, weight: .semibold)).foregroundStyle(Theme.foreground)
                Spacer(minLength: 8)
                Text(value).font(Theme.font(28, weight: .bold)).monospacedDigit().tracking(-0.56)
                    .foregroundStyle(Theme.foreground)
                    .contentTransition(.numericText())
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 16).padding(.vertical, 18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// Paper 40's Details card: who it bills and the job, read only (the server owns both).
    @ViewBuilder private var detailsCard: some View {
        let job = editor.invoice.jobId.flatMap { id in store.jobs.first(where: { $0.id == id }) }
        VStack(alignment: .leading, spacing: 8) {
            PaperSectionLabel(title: "Details", gap: 0)
            VStack(alignment: .leading, spacing: 0) {
                detailRow("Customer", store.customerName(invoice.customerId))
                if let job {
                    detailRow("Job", "\(job.title) \u{00B7} JOB-\(job.id.suffix(4).uppercased())")
                        .overlay(alignment: .top) { WellDivider(leading: 0) }
                }
            }
            .padding(.horizontal, 16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).font(Theme.font(15)).foregroundStyle(Theme.subtle)
            Spacer(minLength: 12)
            Text(value).font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 16)
        .frame(minHeight: 56)
        .accessibilityElement(children: .combine)
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
        .paperActionBarGround(top: commitBlockedReason == nil ? PaperActionBarMetrics.top : PaperActionBarMetrics.topUnderHint)
    }

    private var invoiceCommitButtons: some View {
        let accessible = dynamicTypeSize.isAccessibilitySize
        let layout = accessible ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            if canIssue {
                Button { Task { await save() } } label: {
                    // Paper 40: Save draft is the quiet pill beside the commit.
                    Text("Save draft")
                    .font(Theme.font(15, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, accessible ? 16 : 22)
                    .padding(.vertical, accessible ? 12 : 0)
                    .frame(height: accessible ? nil : 50)
                    .frame(maxWidth: accessible ? .infinity : nil, minHeight: 50)
                    .background(Theme.quietFill, in: Capsule())
                    .contentShape(Capsule())
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
            TextField("Describe the approved change", text: $editor.priceBookOverrideReason, prompt: .placeholder("Describe the approved change"), axis: .vertical)
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
                              sessionGeneration: expected.sessionGeneration, authority: expected.authority, force: force)
    }

    /// Paper 40: "INV-2209 · From EST-1042" (and the revision), then pills for the status, the
    /// customer and the total. The bar keeps "Edit invoice" as the screen's title.
    private var invoiceEditorHeading: some View {
        let status = DocumentStatus(invoice: editor.invoice)
        let customer = store.customerName(invoice.customerId)
        let source: String? = invoice.sourceEstimateId.map { "From EST-\($0.suffix(4).uppercased())" }
        let pieces: [String?] = ["INV-\(invoice.id.suffix(4).uppercased())", source,
                                 "Revision \(editor.invoice.linesRevision)"]
        let parts = pieces.compactMap { $0 }
        return VStack(alignment: .leading, spacing: 16) {
            PaperPageTitle(title: "Edit invoice", subtitle: parts.joined(separator: " \u{00B7} "), columnInset: PaperCardMetrics.margin)
            FlowRow(spacing: 8, lineSpacing: 8) {
                headingPill(symbol: status.word == "Draft" ? "circle.dashed" : "circle", text: status.word)
                    .accessibilityLabel("Status, \(status.word)")
                HStack(spacing: 6) {
                    Text(initials(customer)).font(Theme.font(11, weight: .semibold)).foregroundStyle(Theme.brandText)
                        .frame(width: 22, height: 22)
                        .background(Theme.brandSurface, in: Circle())
                        .dynamicTypeSize(...DynamicTypeSize.large)
                        .accessibilityHidden(true)
                    Text(shortCustomer(customer)).font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.subtle).lineLimit(1)
                }
                .padding(.leading, 6).padding(.trailing, 12).frame(minHeight: 40)
                .background(Theme.card, in: Capsule())
                .accessibilityElement(children: .combine)
                if let total = linesTotal {
                    headingPill(symbol: nil, text: money(total, currency: invoice.currency))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Paper 40's pill names the customer "Danielle M.": the first name and the last initial.
    private func shortCustomer(_ name: String) -> String {
        let words = name.split(separator: " ")
        guard words.count > 1, let last = words.last?.first else { return name }
        return "\(words[0]) \(last)."
    }

    /// Paper 40's top row: the 44 back circle on the card tone, and "…" for what Paper keeps off the
    /// page (scan or paste a parts list, discard). Back asks before dropping edits, as Cancel did.
    private var editorTopBar: some View {
        PaperPageSheetBar {
            PaperCircleButton(symbol: "xmark", label: "Cancel", size: 44, fill: Theme.card) {
                if editor.hasChanges { confirmDiscard = true } else { dismiss() }
            }
            .disabled(busy)
        } trailing: {
            if !moreItems.isEmpty {
                ThorbisMenu(items: moreItems, title: "Edit invoice", accessibilityLabel: "More") {
                    PaperCircleLabel(symbol: "ellipsis", size: 44, fill: Theme.card)
                }
                .disabled(busy)
                .accessibilityIdentifier("invoice-more")
            }
        }
        .background(Theme.background)
    }

    private var moreItems: [ThorbisMenuItem] {
        var items: [ThorbisMenuItem] = []
        if canUsePriceBook, !linesDisabled, editor.lines.count < 500 {
            items.append(ThorbisMenuItem("Scan materials", icon: "barcode.viewfinder") { materialsMode = .scan; showMaterials = true })
            items.append(ThorbisMenuItem("Paste a parts list", icon: "doc.on.clipboard") { materialsMode = .paste; showMaterials = true })
        }
        if editor.hasChanges {
            items.append(ThorbisMenuItem("Discard changes", icon: "trash", role: .destructive) { confirmDiscard = true })
        }
        return items
    }

    private func headingPill(symbol: String?, text: String) -> some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.muted)
                    .accessibilityHidden(true)
            }
            Text(text).font(Theme.font(14, weight: .medium)).monospacedDigit().foregroundStyle(Theme.subtle)
        }
        .padding(.leading, symbol == nil ? 12 : 10).padding(.trailing, 12).frame(minHeight: 40)
        .background(Theme.card, in: Capsule())
        .accessibilityElement(children: .combine)
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
        guard context.preservesInvoicePickerState(comparedTo: current), current.organizationID?.isEmpty == false,
              lines.filter({ $0.id == lineID }).count == 1 else { return nil }
        return lineID
    }
}

private extension PriceBookCatalogContext {
    /// Local revalidation revisions retire requests but do not change a verified invoice draft's identity.
    func preservesInvoicePickerState(comparedTo other: PriceBookCatalogContext) -> Bool {
        guard organizationID == other.organizationID, sessionGeneration == other.sessionGeneration else { return false }
        switch (authority, other.authority) {
        case (nil, nil): return true
        case let (old?, new?):
            return old.actorID == new.actorID && old.policyVersion == new.policyVersion && old.generation == new.generation
        default: return false
        }
    }
}

import SwiftUI

struct EstimateRevisionEditorView: View {
    private struct PriceBookTarget: Identifiable {
        let optionID: String?
        var id: String { optionID ?? "main" }
    }

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
    @State private var priceBookTarget: PriceBookTarget?

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

    private var canSave: Bool {
        !busy && canEdit && (editor.estimate.currentRevisionNumber ?? 0) > 0 &&
        editor.hasChanges && !editor.hasUnsupportedLineSources && (!editor.hasCreditLines || canDiscount)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
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
                .padding(.top, 18)
                .padding(.bottom, 24)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
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
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: "Save revised draft", busy: busy) { Task { await save() } }
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.5)
                    .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 8)
                    .background(Theme.chrome)
            }
            .sheet(item: $priceBookTarget) { target in
                NavigationStack {
                    PaperPriceBookPicker(api: api, currency: "USD", customerID: estimate.customerId) { item in
                        do {
                            try editor.addPriceBookItem(item, optionID: target.optionID)
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
            HStack {
                sectionTitle("Line items", count: editor.lines.count)
                Spacer()
                if canUsePriceBook {
                    Button { priceBookTarget = PriceBookTarget(optionID: nil) } label: {
                        Label("Price Book", systemImage: "book.closed")
                            .font(Theme.font(12, weight: .medium))
                            .frame(minHeight: 44)
                    }
                    .disabled(busy || !canEdit || editor.lines.count >= 500)
                    .accessibilityLabel("Add line from Price Book")
                }
            }
            VStack(spacing: 0) {
                ForEach($editor.lines) { $line in
                    EstimateRevisionLineRow(
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
                Button { editor.addManualLine() } label: {
                    Label("Add line item", systemImage: "plus")
                        .font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14).frame(minHeight: 46)
                }
                .disabled(busy || !canEdit || editor.lines.count >= 500 || editor.hasUnsupportedLineSources)
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.border, lineWidth: 1))
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
                    canUsePriceBook: canUsePriceBook,
                    disabled: busy || !canEdit || !optionsFeatureEnabled || editor.hasUnsupportedLineSources,
                    addPriceBook: { priceBookTarget = PriceBookTarget(optionID: option.id) },
                    addLine: { editor.addManualLine(optionID: option.id) },
                    removeOption: { editor.removeOption(id: option.id) },
                    removeLine: { lineID in editor.removeOptionLine(optionID: option.id, lineID: lineID) }
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

    private func moveLine(_ id: UUID, offset: Int) {
        guard let index = editor.lines.firstIndex(where: { $0.id == id }) else { return }
        editor.moveLine(id: id, to: index + offset)
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
    let canUsePriceBook: Bool
    let disabled: Bool
    let addPriceBook: () -> Void
    let addLine: () -> Void
    let removeOption: () -> Void
    let removeLine: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Option title", text: $option.title)
                    .font(Theme.font(15, weight: .semibold))
                    .accessibilityLabel("Option package title")
                    .disabled(disabled)
                Button(action: removeOption) {
                    Image(systemName: "trash").foregroundStyle(Theme.destructive)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Remove \(option.title.isEmpty ? "option package" : option.title)")
                .disabled(disabled)
            }
            TextField("What this package includes", text: $option.description, axis: .vertical)
                .font(Theme.font(13)).lineLimit(2...4)
                .accessibilityLabel("Option package description")
                .disabled(disabled)
            ForEach($option.lines) { $line in
                EstimateRevisionLineRow(
                    line: $line,
                    canMoveUp: false,
                    canMoveDown: false,
                    moveUp: {}, moveDown: {},
                    remove: { removeLine(line.id) }
                )
                .disabled(disabled)
                if line.id != option.lines.last?.id { Rectangle().fill(Theme.border).frame(height: 1) }
            }
            HStack(spacing: 12) {
                Button(action: addLine) {
                    Label("Add line", systemImage: "plus").font(Theme.font(12, weight: .medium))
                        .frame(minHeight: 44)
                }
                .disabled(disabled || option.lines.count >= 500)
                if canUsePriceBook {
                    Button(action: addPriceBook) {
                        Label("Price Book", systemImage: "book.closed").font(Theme.font(12, weight: .medium))
                            .frame(minHeight: 44)
                    }
                    .disabled(disabled || option.lines.count >= 500)
                }
            }
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.border, lineWidth: 1))
    }
}

private struct EstimateRevisionLineRow: View {
    @Binding var line: EstimateRevisionLineDraft
    let canMoveUp: Bool
    let canMoveDown: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                TextField("Line item description", text: $line.description, axis: .vertical)
                    .font(Theme.font(15, weight: .medium)).lineLimit(1...3)
                    .accessibilityLabel("Line item description")
                LineItemActions(name: line.description, canMoveUp: canMoveUp, canMoveDown: canMoveDown,
                                moveUp: moveUp, moveDown: moveDown, remove: remove)
            }
            HStack(spacing: 8) {
                Text("Qty").font(Theme.font(13)).foregroundStyle(Theme.muted)
                LineNumberField(label: "Quantity", placeholder: "1", text: $line.quantity)
                Spacer(minLength: 8)
                LineNumberField(label: "Unit price in dollars", placeholder: "0.00", text: $line.unitPrice,
                                prefix: "$", decimal: true, width: 128)
            }
            if case .some(.priceBookSelection(_, let revision)) = line.source {
                Text("Price Book · Revision \(revision)")
                    .font(Theme.monoFont(12)).foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
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

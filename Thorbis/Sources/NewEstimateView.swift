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
    @State private var query = ""
    @State private var kind = PriceBookKindFilter.all
    @State private var addGroup: EstimateLineGroup?
    @State private var added = 0
    @State private var removed: RemovedLine?
    @State private var confirmDiscard = false
    @FocusState private var focus: EstimateBuilderFocus?
    /// Set once the server created the estimate, so a retry only links it and never creates a duplicate.
    @State private var created: EstimateRecord?
    private let jobID: String?
    private let onCreated: (EstimateRecord) -> Void

    init(customerID: String = "", jobID: String? = nil, title: String = "", onCreated: @escaping (EstimateRecord) -> Void = { _ in }) {
        _customerID = State(initialValue: customerID)
        _title = State(initialValue: title)
        self.jobID = jobID
        self.onCreated = onCreated
    }

    private var canUsePriceBook: Bool { session.can("pricebook.view", feature: "price_book") }
    private var searching: Bool { focus == .search || !query.isEmpty }
    private var total: Int? { lines.isEmpty ? nil : lines.subtotal() }

    var valid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !customerID.isEmpty && !lines.isEmpty &&
        lines.allSatisfy { line in
            !line.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            (Int(line.quantity.trimmingCharacters(in: .whitespacesAndNewlines)).map { (1...100_000).contains($0) } ?? false) &&
            MoneyInput.cents(line.unitPrice) != nil
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if searching {
                    PriceBookResultsList(
                        catalog: catalog, context: PriceBookCatalogContext(organizationID: session.activeOrganization?.id, sessionGeneration: session.generation),
                            query: query, kind: kind, canUsePriceBook: canUsePriceBook,
                        quantityInCurrentDraft: { id in
                            (addGroup.map { lines.lines(in: $0) } ?? lines).quantity(ofPriceBookItem: id)
                        },
                        secondaryPriceText: { _ in nil }, addItem: add, addCustomLine: addCustom, retry: { Task { await refreshCatalog(force: true) } }
                    )
                } else {
                    builder
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .keyboardDoneButton()
            .background(Theme.background)
            .foregroundStyle(Theme.foreground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if lines.isEmpty || created != nil { dismiss() } else { confirmDiscard = true } }.disabled(busy)
                }
            }
            .discardChangesGuard(hasChanges: !lines.isEmpty && created == nil, busy: busy, isPresented: $confirmDiscard) { dismiss() }
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    EstimateSearchBar(query: $query, kind: $kind, focus: $focus, searching: searching,
                                      prompt: addGroup.map { "Add to \($0.title)" } ?? "Search price book or type a line",
                                      finish: finishSearch)
                        .disabled(busy)
                    if searching {
                        PaperActionBar(title: reviewTitle, symbol: "list.bullet", busy: busy) { finishSearch() }
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if let removed {
                        LineRemovedToast(removed: removed, undo: undoRemove, expire: { withAnimation { self.removed = nil } })
                    }
                    if !searching {
                        EstimateBuilderTotal(total: total)
                        PaperActionBar(title: commitTitle, symbol: "doc.badge.plus", busy: busy,
                                       disabled: !valid || !session.can("estimate.create", feature: "estimates")) { Task { await save() } }
                    }
                }
            }
            .sensoryFeedback(.success, trigger: added)
            .animation(EstimateLineGroupsEditor.spring, value: searching)
            .task(id: PriceBookCatalogContext(organizationID: session.activeOrganization?.id, sessionGeneration: session.generation)) { await refreshCatalog() }
            .task {
                guard lines.isEmpty else { return }
                try? await Task.sleep(for: .milliseconds(450))
                if lines.isEmpty, !customerID.isEmpty { focus = .search }
            }
        }
    }

    private var commitTitle: String {
        if created != nil { return "Retry adding to job" }
        guard let total else { return "Save estimate" }
        return "Save estimate · \(money(total, currency: "USD"))"
    }

    private var reviewTitle: String {
        "Review estimate · \(lines.count) \(lines.count == 1 ? "item" : "items")"
    }

    private var builder: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                PaperEyebrow(reference: jobID.map { "JOB-\($0.suffix(4).uppercased())" }, text: "New estimate")
                TextField("Estimate title", text: $title, axis: .vertical)
                    .font(Theme.font(24, weight: .medium)).tracking(-0.36)
                    .accessibilityLabel("Estimate title")
                HStack(spacing: 6) {
                    Chip(text: "Draft", icon: "circle.dashed")
                    ThorbisMenu(items: store.customers.filter { $0.archived != true }.map { customer in
                        ThorbisMenuItem(customer.name, isSelected: customer.id == customerID) { customerID = customer.id }
                    }, title: "Customer") {
                        Chip(text: customerID.isEmpty ? "Choose customer" : store.customerName(customerID), icon: "person",
                             tint: customerID.isEmpty ? Theme.brandText : Theme.muted)
                            .padding(.vertical, 10).contentShape(Rectangle())
                    }
                    .disabled(jobID != nil && !customerID.isEmpty)
                }
            }
            .padding(.bottom, 14)

            EstimateLineGroupsEditor(lines: $lines, disabled: busy, focus: $focus, addTo: startAdding) { line, index in
                withAnimation { removed = RemovedLine(line: line, index: index, optionID: nil) }
            }
            if lines.isEmpty {
                Text(canUsePriceBook ? "Search above to add from the price book, or type any line."
                                     : "Type a line above and add it.")
                    .font(Theme.font(15)).foregroundStyle(Theme.muted).padding(.top, 12)
            }
            if let error { ErrorBanner(message: error).padding(.horizontal, -Theme.gutter).padding(.top, 8) }
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

    private func add(_ item: PriceBookListItem) {
        guard !busy else { return }
        withAnimation(EstimateLineGroupsEditor.spring) {
            guard lines.addPriceBookItem(item, to: addGroup) != nil else {
                error = "An estimate can contain up to 500 line items."
                return
            }
        }
        catalog.recordUse(item.id)
        added += 1
    }

    private func addCustom(_ text: String) {
        guard !busy else { return }
        let group = addGroup ?? (kind == .material ? .material : .work)
        guard let id = lines.addCustomLine(text, to: group) else {
            error = "An estimate can contain up to 500 line items."
            return
        }
        added += 1
        query = ""
        kind = .all
        addGroup = nil
        focus = .price(id)
    }

    private func startAdding(_ group: EstimateLineGroup) {
        addGroup = group
        kind = group == .material ? .material : .all
        focus = .search
    }

    private func finishSearch() {
        query = ""
        kind = .all
        addGroup = nil
        focus = nil
    }

    private func undoRemove() {
        guard let removed else { return }
        withAnimation(EstimateLineGroupsEditor.spring) {
            lines.restoreLine(removed.line, at: removed.index)
            self.removed = nil
        }
    }

    private func save() async {
        guard valid else { return }
        busy = true
        defer { busy = false }
        do {
            let estimate: EstimateRecord
            if let created {
                estimate = created
            } else {
                estimate = try await api.createFieldEstimate(.init(
                    customerId: customerID,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    lines: lines.map {
                        .init(description: $0.description.trimmingCharacters(in: .whitespacesAndNewlines),
                              quantity: Int($0.quantity.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1,
                              unitPrice: .init(amount: MoneyInput.cents($0.unitPrice) ?? 0, currency: "USD"),
                              source: $0.source ?? .manual)
                    }))
                created = estimate
                // On a job, the estimate opens only once it's attached; an unattached one in job
                // context would never count as the job's estimate.
                if jobID == nil { onCreated(estimate) }
            }
            if let jobID {
                do { _ = try await api.linkFieldEstimate(jobID: jobID, estimateID: estimate.id) }
                catch is CancellationError { return }
                catch {
                    self.error = "The estimate was saved but could not be added to the job. \(error.localizedDescription)"
                    return
                }
                onCreated(estimate)
            }
            dismiss()
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}

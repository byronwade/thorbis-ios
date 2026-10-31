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
    @State private var expandedLine: UUID?
    @State private var keyboardUp = false
    @State private var removed: RemovedLine?
    @State private var confirmDiscard = false
    @FocusState private var focus: EstimateBuilderFocus?
    /// Set once the server created the estimate, so a retry only links it and never creates a duplicate.
    @State private var created: EstimateRecord?
    @State private var memberPricing: MemberPricing?
    private let jobID: String?
    private let onCreated: (EstimateRecord) -> Void

    init(customerID: String = "", jobID: String? = nil, title: String = "", onCreated: @escaping (EstimateRecord) -> Void = { _ in }) {
        _customerID = State(initialValue: customerID)
        _title = State(initialValue: title)
        self.jobID = jobID
        self.onCreated = onCreated
    }

    private var canUsePriceBook: Bool { session.can("pricebook.view", feature: "price_book") }
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
            }
            .keyboardDoneButton()
            .trackKeyboard($keyboardUp)
            .background(Theme.background)
            .foregroundStyle(Theme.foreground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ThorbisToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if lines.isEmpty || created != nil { dismiss() } else { confirmDiscard = true } }.disabled(busy)
                }
            }
            .discardChangesGuard(hasChanges: !lines.isEmpty && created == nil, busy: busy, isPresented: $confirmDiscard) { dismiss() }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if let removed {
                        LineRemovedToast(removed: removed, undo: undoRemove, expire: { withAnimation { self.removed = nil } })
                    }
                    // While typing, only the commit stays: the total would sit on the field being edited.
                    if !keyboardUp {
                        EstimateBuilderTotal(total: total, detail: memberLine)
                    }
                    PaperActionBar(title: commitTitle, symbol: "doc.badge.plus", busy: busy,
                                   disabled: !valid || !session.can("estimate.create", feature: "estimates")) { Task { await save() } }
                }
            }
            .sheet(item: $picker) { target in
                PriceBookCartPicker(
                    destination: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "this estimate" : title,
                    canUsePriceBook: canUsePriceBook,
                    quantityInDraft: { lines.quantity(ofPriceBookItem: $0) },
                    secondaryPriceText: { memberPricing?.secondaryPriceText($0) },
                    addItem: { add($0, group: target.group) },
                    addCustomLine: { addCustom($0, group: target.group) },
                    refresh: { await refreshCatalog(force: $0) }
                )
                .environmentObject(session).environmentObject(api)
            }
            .animation(EstimateLineGroupsEditor.spring, value: keyboardUp)
            .task(id: PriceBookCatalogContext(organizationID: session.activeOrganization?.id, sessionGeneration: session.generation)) { await refreshCatalog() }
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

    /// MF-05: what a member would pay, under the total. The saved prices stay the price book's.
    private var memberLine: String? {
        guard let memberPricing, let sum = lines.memberTotal(memberPricing) else { return nil }
        return "Member price \(money(sum, currency: "USD")) · \(memberPricing.discountPercent)% off"
    }

    private var commitTitle: String {
        if created != nil { return "Retry adding to job" }
        guard let total else { return "Save estimate" }
        return "Save estimate · \(money(total, currency: "USD"))"
    }

    private var builder: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                PaperEyebrow(reference: jobID.map { "JOB-\($0.suffix(4).uppercased())" }, text: "New estimate")
                TextField("Estimate title", text: $title, axis: .vertical)
                    .font(Theme.font(24, weight: .medium)).tracking(-0.36)
                    .accessibilityLabel("Estimate title")
                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Circle().fill(Theme.warning).frame(width: 7, height: 7)
                        Text("Draft").font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.foreground)
                    }
                    .accessibilityElement(children: .combine)
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

            EstimateBuilderSection(
                label: lines.isEmpty ? "Items" : "Items · \(lines.count)",
                lines: $lines, disabled: busy, focus: $focus, expandedLine: $expandedLine,
                showTotal: false,
                addItem: { picker = EstimateBuilderTarget() },
                removed: { line, index in withAnimation { removed = RemovedLine(line: line, index: index, optionID: nil) } }
            )
            if lines.isEmpty {
                Text(canUsePriceBook ? "Add from the price book, or type any custom item."
                                     : "Add a custom item: this account can't use the price book.")
                    .font(Theme.font(15)).foregroundStyle(Theme.muted)
            }
            if let error { ErrorBanner(message: error).padding(.horizontal, -Theme.gutter) }
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

    /// One more of a price book item; returns why it couldn't be added, or nil.
    private func add(_ item: PriceBookListItem, group: EstimateLineGroup?) -> String? {
        guard !busy else { return "Saving. Try again in a moment." }
        var addedLine = false
        withAnimation(EstimateLineGroupsEditor.spring) { addedLine = lines.addPriceBookItem(item, to: group) != nil }
        guard addedLine else { return "An estimate can contain up to 500 line items." }
        return nil
    }

    private func addCustom(_ text: String, group: EstimateLineGroup?) {
        guard !busy else { return }
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

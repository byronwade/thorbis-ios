import SwiftUI

/// Equipment at a customer's places: what's installed, its serial and warranty. Office roles can
/// add, edit and remove; the section hides itself when the server doesn't offer equipment.
struct CustomerEquipmentSection: View {
    let customerID: String
    let locations: [ServiceLocationRecord]
    /// Job view: only the units at this location, read-only.
    var onlyLocationID: String? = nil
    var editable = true
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @State private var items: [EquipmentRecord] = []
    @State private var available = false
    @State private var editing: EquipmentEditorItem?
    @State private var error: String?

    private var canEdit: Bool { editable && session.can("customer.edit", feature: "core_crm") }
    private var shown: [EquipmentRecord] {
        guard let onlyLocationID else { return items }
        return items.filter { $0.locationId == nil || $0.locationId == onlyLocationID }
    }

    var body: some View {
        // A zero-size anchor keeps the view (and its load task) alive before anything is shown.
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(width: 0, height: 0)
            if available && (!shown.isEmpty || canEdit) {
                // design 2026-10-30: one panel, rows with the warranty as a status word, no chevrons.
                PaperSection(title: onlyLocationID == nil ? "Equipment" : "Equipment here", count: shown.isEmpty ? nil : shown.count) {
                    if let error { ListErrorRow(message: error).padding(.horizontal, PaperCardMetrics.inset) }
                    if shown.isEmpty {
                        Text("Add the units you service here so the next visit starts with model and serial.")
                            .font(Theme.font(15)).foregroundStyle(Theme.muted)
                            .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 12)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(shown) { unit in
                                if canEdit {
                                    Button { editing = EquipmentEditorItem(record: unit) } label: { row(unit) }
                                        .buttonStyle(RowPressStyle())
                                        .accessibilityHint("Opens the unit to edit")
                                } else {
                                    row(unit)
                                }
                            }
                        }
                        .padding(.vertical, PaperCardMetrics.edge)
                    }
                } accessory: {
                    if canEdit {
                        Button { editing = EquipmentEditorItem(record: nil) } label: {
                            Image(systemName: "plus").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.foreground)
                                .frame(width: 44, height: 44, alignment: .trailing).contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel("Add equipment")
                    }
                }
            }
        }
        .task(id: customerID) { await load() }
        .sheet(item: $editing) { item in
            EquipmentEditor(customerID: customerID, locations: locations, existing: item.record) { await load() }
        }
    }

    private func row(_ unit: EquipmentRecord) -> some View {
        let warranty = unit.warrantyEnd.map { end -> (String, Bool) in
            let expired = end < Calendar.current.startOfDay(for: .now)
            return ("\(expired ? "Warranty ended" : "Warranty until") \(end.formatted(date: .abbreviated, time: .omitted))", expired)
        }
        return PaperListRow(title: unit.name, subtitle: unit.detail.isEmpty ? nil : unit.detail,
                            meta: warranty?.0, subtitleLines: 2) {
            if let warranty {
                StatusWord(text: warranty.1 ? "Out of warranty" : "In warranty", tint: warranty.1 ? nil : Theme.success)
            }
        }
    }

    private func load() async {
        do {
            items = try await api.customerEquipment(customerID)
            available = true
            error = nil
        } catch is CancellationError {
        } catch {
            // 403 for technicians and 404 on older servers: leave the section out.
            available = false
        }
    }
}

struct EquipmentEditorItem: Identifiable {
    let record: EquipmentRecord?
    var id: String { record?.id ?? "new" }
}

struct EquipmentEditor: View {
    let customerID: String
    let locations: [ServiceLocationRecord]
    let existing: EquipmentRecord?
    /// New equipment only: values read elsewhere (the data-plate scan) to start the form with.
    var prefill: EquipmentInput? = nil
    let onSaved: () async -> Void
    @EnvironmentObject private var api: APIClient
    @Environment(\.dismiss) private var dismiss
    @State private var input = EquipmentInput(name: "")
    @State private var installed: Date?
    @State private var warranty: Date?
    @State private var busy = false
    @State private var error: String?
    @State private var confirmRemove = false

    var body: some View {
        NavigationStack {
            // design 2026-10-30: one column, labels above, field wells; Save is the ink commit
            // above the keyboard (it was the toolbar's Save), Cancel stays in the toolbar.
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PaperFormField("What it is") {
                        TextField("e.g. 50-gal gas water heater", text: $input.name).font(Theme.font(16)).fieldWell()
                    }
                    PaperFormField("Type", note: "Optional") { TextField("Water heater", text: binding(\.kind)).font(Theme.font(16)).fieldWell() }
                    PaperFormField("Brand", note: "Optional") { TextField("Brand", text: binding(\.brand)).font(Theme.font(16)).fieldWell() }
                    PaperFormField("Model", note: "Optional") { TextField("Model", text: binding(\.model)).font(Theme.font(16)).fieldWell() }
                    PaperFormField("Serial number", note: "Optional") {
                        TextField("Serial number", text: binding(\.serialNumber)).textInputAutocapitalization(.characters)
                            .font(Theme.font(16)).fieldWell()
                    }
                    if !locations.isEmpty {
                        PaperFormField("Location") {
                            ThorbisSelect(options: [(String?.none, "Not set")]
                                            + locations.map { (Optional($0.id), $0.label.isEmpty ? $0.address : "\($0.label) · \($0.address)") },
                                          selection: $input.locationId, label: "Location")
                                .fieldWell()
                        }
                    }
                    PaperFormField("Dates", note: "Optional") {
                        VStack(spacing: 0) {
                            optionalDate("Installed", $installed)
                            optionalDate("Warranty ends", $warranty)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 2)
                        .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                    }
                    PaperFormField("Notes", note: "Optional") {
                        TextField("Filters, access, history…", text: binding(\.notes), axis: .vertical).lineLimit(2...6)
                            .font(Theme.font(16)).fieldWell()
                    }
                    if let error { ListErrorRow(message: error) }
                    if existing != nil {
                        Button { confirmRemove = true } label: {
                            Text("Remove equipment").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.destructive)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(PressStyle())
                        .disabled(busy)
                    }
                }
                .padding(.horizontal, Theme.gutter).padding(.top, 8).padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .navigationTitle(existing == nil ? "Add equipment" : "Equipment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ThorbisToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() }.disabled(busy) }
            }
            .safeAreaInset(edge: .bottom) {
                PaperActionBar(title: existing == nil ? "Add equipment" : "Save equipment", busy: busy,
                               disabled: input.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) { Task { await save() } }
            }
            .thorbisConfirm("Remove this equipment?", isPresented: $confirmRemove,
                            actions: [ThorbisConfirmAction("Remove", role: .destructive) { Task { await remove() } }])
            .onAppear(perform: fill)
        }
    }

    private func binding(_ key: WritableKeyPath<EquipmentInput, String?>) -> Binding<String> {
        Binding(get: { input[keyPath: key] ?? "" }, set: { input[keyPath: key] = $0 })
    }

    @ViewBuilder private func optionalDate(_ title: String, _ value: Binding<Date?>) -> some View {
        if let date = value.wrappedValue {
            HStack {
                DatePicker(title, selection: Binding(get: { date }, set: { value.wrappedValue = $0 }), displayedComponents: .date)
                Button { value.wrappedValue = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.subtle) }
                    .buttonStyle(.plain).accessibilityLabel("Clear \(title.lowercased())")
            }
        } else {
            Button { value.wrappedValue = .now } label: {
                Text("Add \(title.lowercased()) date").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
        }
    }

    private func fill() {
        guard input.name.isEmpty else { return }
        if let existing {
            input = EquipmentInput(name: existing.name, locationId: existing.locationId, kind: existing.kind, brand: existing.brand,
                                   model: existing.model, serialNumber: existing.serialNumber, notes: existing.notes)
            installed = existing.installedOn.flatMap(EquipmentRecord.day)
            warranty = existing.warrantyEnd
        } else {
            if let prefill { input = prefill }
            if input.locationId == nil, locations.count == 1 { input.locationId = locations.first?.id }
        }
    }

    private func save() async {
        var body = input
        body.name = body.name.trimmingCharacters(in: .whitespacesAndNewlines)
        body.installedOn = installed.map(EquipmentRecord.dayString)
        body.warrantyExpiresOn = warranty.map(EquipmentRecord.dayString)
        busy = true
        defer { busy = false }
        do {
            if let existing { _ = try await api.updateEquipment(customerID, equipmentID: existing.id, body) }
            else { _ = try await api.addEquipment(customerID, body) }
            await onSaved()
            dismiss()
        } catch is CancellationError {
        } catch { self.error = error.isConnectivityFailure ? "Saving needs a connection." : error.localizedDescription }
    }

    private func remove() async {
        guard let existing else { return }
        busy = true
        defer { busy = false }
        do {
            try await api.removeEquipment(customerID, equipmentID: existing.id)
            await onSaved()
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

/// The customer's membership: what plan, the member discount, and when it renews.
struct CustomerMembershipSection: View {
    let customerID: String
    /// The job reads the membership; selling and cancelling stay on the customer (JS-01).
    var editable = true
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @State private var memberships: [MembershipRecord] = []
    @State private var plans: [MembershipPlan] = []
    @State private var available = false
    @State private var choosing = false
    @State private var cancelling: MembershipRecord?
    @State private var error: String?

    private var canEdit: Bool { editable && session.can("customer.edit", feature: "core_crm") }
    private var active: [MembershipRecord] { memberships.filter { $0.status == "active" } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(width: 0, height: 0)
            if available && (!active.isEmpty || (canEdit && !plans.isEmpty)) {
                // design 2026-10-30: the plan as a row on one panel, "Active" as its word; cancel stays in •••.
                PaperSection("Membership", count: active.count > 1 ? active.count : nil) {
                    if let error { ListErrorRow(message: error).padding(.horizontal, PaperCardMetrics.inset) }
                    if active.isEmpty && canEdit {
                        Button { choosing = true } label: {
                            PaperListRow(leading: .icon("plus"), title: "Add a membership",
                                         subtitle: "Member pricing and tune-up visits")
                        }
                        .buttonStyle(RowPressStyle())
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(active) { membership in
                                HStack(spacing: 0) {
                                    PaperListRow(title: membership.name, subtitle: membershipDetail(membership), subtitleLines: 2) {
                                        StatusWord(text: "Active", tint: Theme.success)
                                    }
                                    .accessibilityElement(children: .combine)
                                    if canEdit {
                                        ThorbisMenu(items: [
                                            ThorbisMenuItem("Cancel membership", icon: "xmark.circle", role: .destructive) { cancelling = membership },
                                        ], accessibilityLabel: "Membership actions") {
                                            Image(systemName: "ellipsis").foregroundStyle(Theme.muted)
                                                .frame(width: 44, height: 44).contentShape(Rectangle())
                                        }
                                        .padding(.trailing, 4)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, PaperCardMetrics.edge)
                    }
                }
            }
        }
        .task(id: customerID) { await load() }
        .sheet(isPresented: $choosing) { planPicker }
        .thorbisConfirm(item: $cancelling,
                        title: { _ in "Cancel this membership?" },
                        message: { _ in "Member pricing ends for this customer." },
                        actions: { membership in
            [ThorbisConfirmAction("Cancel membership", role: .destructive) { Task { await cancel(membership) } }]
        })
    }

    private func membershipDetail(_ membership: MembershipRecord) -> String {
        var parts: [String] = []
        if membership.discountPercent > 0 { parts.append("\(membership.discountPercent)% off") }
        if let cadence = membership.cadence, !cadence.isEmpty { parts.append(cadence) }
        if let renews = membership.renewsOn.flatMap(EquipmentRecord.day) { parts.append("Renews \(renews.formatted(date: .abbreviated, time: .omitted))") }
        return parts.isEmpty ? membership.kind.capitalized : parts.joined(separator: " · ")
    }

    private var planPicker: some View {
        NavigationStack {
            ScrollView {
                PaperSection("Plans", count: plans.count) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(plans) { plan in
                            Button { Task { await enroll(plan) } } label: {
                                PaperListRow(title: plan.name,
                                             subtitle: [plan.discountPercent > 0 ? "\(plan.discountPercent)% off work" : nil,
                                                        plan.visitsPerYear.map { "\($0) visit\($0 == 1 ? "" : "s") a year" }, plan.description]
                                                 .compactMap { $0 }.joined(separator: " · "),
                                             subtitleLines: 3) {
                                    if let price = plan.price {
                                        Text("\(money(price, currency: "USD"))\(plan.billingFrequency.map { " / \($0.replacingOccurrences(of: "_", with: " "))" } ?? "")")
                                            .moneyStyle(.row).foregroundStyle(Theme.foreground)
                                    }
                                }
                            }
                            .buttonStyle(RowPressStyle())
                        }
                    }
                    .padding(.vertical, PaperCardMetrics.edge)
                }
                .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 8).padding(.bottom, 24)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Choose a plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ThorbisToolbarItem(placement: .topBarLeading) { Button("Cancel") { choosing = false } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func load() async {
        do {
            memberships = try await api.customerMemberships(customerID)
            plans = (try? await api.membershipPlans()) ?? []
            available = true
        } catch is CancellationError {
        } catch {
            available = false
        }
    }

    private func enroll(_ plan: MembershipPlan) async {
        do {
            _ = try await api.enroll(customerID, planID: plan.id, startsOn: .now)
            choosing = false
            error = nil
            await load()
        } catch { self.error = error.localizedDescription; choosing = false }
    }

    private func cancel(_ membership: MembershipRecord) async {
        do {
            _ = try await api.cancelMembership(customerID, membershipID: membership.id)
            await load()
        } catch { self.error = error.localizedDescription }
    }
}

/// "Member · 10% off" — shown wherever a customer's price matters.
/// Membership as a plain fact beside the customer's name ("★ Member · 15% off"), not a pill: it
/// isn't tappable and isn't a status. Nothing shows for non-members or while it loads.
struct MemberFact: View {
    let customerID: String
    @EnvironmentObject private var api: APIClient
    @State private var pricing: MemberPricing?

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 0, height: 0)
            if let pricing, pricing.isMember {
                Label(pricing.discountPercent > 0 ? "Member · \(pricing.discountPercent)% off" : "Member", systemImage: "star.fill")
                    .labelStyle(MemberFactLabelStyle())
                    .font(Theme.font(13, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .frame(minHeight: 44)
            }
        }
        .task(id: customerID) { pricing = try? await api.memberPricing(customerID) }
    }
}

private struct MemberFactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.brandText)
            configuration.title
        }
    }
}

struct MemberChip: View {
    let customerID: String
    @EnvironmentObject private var api: APIClient
    @State private var pricing: MemberPricing?

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 0, height: 0)
            if let pricing, pricing.isMember {
                Chip(text: pricing.discountPercent > 0 ? "Member · \(pricing.discountPercent)% off" : "Member", icon: "star",
                     tint: Theme.brandText, bg: Theme.brandSurface)
            }
        }
        .task(id: customerID) { pricing = try? await api.memberPricing(customerID) }
    }
}

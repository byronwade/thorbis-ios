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
                VStack(alignment: .leading, spacing: 0) {
                    PaperGroupHeader(title: onlyLocationID == nil ? "Equipment" : "Equipment here", count: shown.count) {
                        if canEdit {
                            Button { editing = EquipmentEditorItem(record: nil) } label: {
                                Image(systemName: "plus").frame(width: 44, height: 44).contentShape(Rectangle())
                            }
                            .accessibilityLabel("Add equipment")
                        }
                    }
                    if let error { Text(error).font(Theme.font(12)).foregroundStyle(Theme.destructive) }
                    if shown.isEmpty {
                        Text("Add the units you service here so the next visit starts with model and serial.")
                            .font(Theme.font(13)).foregroundStyle(Theme.muted).padding(.vertical, 6)
                    }
                    ForEach(shown) { unit in
                        Button { if canEdit { editing = EquipmentEditorItem(record: unit) } } label: { row(unit) }
                            .buttonStyle(.plain)
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
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "shippingbox").font(.system(size: 15)).foregroundStyle(Theme.muted).frame(width: 24).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(unit.name).font(Theme.font(15, weight: .medium))
                if !unit.detail.isEmpty { Text(unit.detail).font(Theme.monoFont(12)).foregroundStyle(Theme.muted) }
                if let end = unit.warrantyEnd {
                    let expired = end < Calendar.current.startOfDay(for: .now)
                    Text("\(expired ? "Warranty ended" : "Warranty until") \(end.formatted(date: .abbreviated, time: .omitted))")
                        .font(Theme.font(12, weight: .medium)).foregroundStyle(expired ? Theme.muted : Theme.success)
                }
            }
            Spacer(minLength: 0)
            if canEdit { Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.subtle).padding(.top, 4) }
        }
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
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
            Form {
                Section {
                    TextField("What it is (e.g. 50-gal gas water heater)", text: $input.name)
                    TextField("Type", text: binding(\.kind))
                    TextField("Brand", text: binding(\.brand))
                    TextField("Model", text: binding(\.model))
                    TextField("Serial number", text: binding(\.serialNumber)).textInputAutocapitalization(.characters)
                }
                if !locations.isEmpty {
                    Section {
                        Picker("Location", selection: $input.locationId) {
                            Text("Not set").tag(String?.none)
                            ForEach(locations) { Text($0.label.isEmpty ? $0.address : "\($0.label) · \($0.address)").tag(Optional($0.id)) }
                        }
                    }
                }
                Section {
                    optionalDate("Installed", $installed)
                    optionalDate("Warranty ends", $warranty)
                }
                Section("Notes") { TextField("Filters, access, history…", text: binding(\.notes), axis: .vertical).lineLimit(2...6) }
                if existing != nil {
                    Section { Button("Remove equipment", role: .destructive) { confirmRemove = true } }
                }
                if let error { Section { Text(error).foregroundStyle(Theme.destructive) } }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(existing == nil ? "Add equipment" : "Equipment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { Task { await save() } }
                        .disabled(busy || input.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog("Remove this equipment?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove", role: .destructive) { Task { await remove() } }
            }
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
            Button("Add \(title.lowercased()) date") { value.wrappedValue = .now }
        }
    }

    private func fill() {
        guard input.name.isEmpty else { return }
        if let existing {
            input = EquipmentInput(name: existing.name, locationId: existing.locationId, kind: existing.kind, brand: existing.brand,
                                   model: existing.model, serialNumber: existing.serialNumber, notes: existing.notes)
            installed = existing.installedOn.flatMap(EquipmentRecord.day)
            warranty = existing.warrantyEnd
        } else if locations.count == 1 {
            input.locationId = locations.first?.id
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
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @State private var memberships: [MembershipRecord] = []
    @State private var plans: [MembershipPlan] = []
    @State private var available = false
    @State private var choosing = false
    @State private var cancelling: MembershipRecord?
    @State private var error: String?

    private var canEdit: Bool { session.can("customer.edit", feature: "core_crm") }
    private var active: [MembershipRecord] { memberships.filter { $0.status == "active" } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(width: 0, height: 0)
            if available && (!active.isEmpty || (canEdit && !plans.isEmpty)) {
                VStack(alignment: .leading, spacing: 0) {
                    PaperGroupHeader(title: "Membership", count: active.isEmpty ? nil : active.count)
                    if let error { Text(error).font(Theme.font(12)).foregroundStyle(Theme.destructive) }
                    ForEach(active) { membership in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "star.circle.fill").font(.system(size: 18)).foregroundStyle(Theme.brandText).frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(membership.name).font(Theme.font(15, weight: .medium))
                                Text(membershipDetail(membership)).font(Theme.font(12)).foregroundStyle(Theme.muted)
                            }
                            Spacer(minLength: 0)
                            if canEdit {
                                Menu {
                                    Button("Cancel membership", role: .destructive) { cancelling = membership }
                                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                                .accessibilityLabel("Membership actions")
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    if active.isEmpty && canEdit {
                        Button { choosing = true } label: {
                            Label("Add a membership", systemImage: "plus.circle").font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.brandText)
                                .frame(minHeight: 44)
                        }
                    }
                }
            }
        }
        .task(id: customerID) { await load() }
        .sheet(isPresented: $choosing) { planPicker }
        .confirmationDialog("Cancel this membership?", isPresented: Binding(get: { cancelling != nil }, set: { if !$0 { cancelling = nil } }),
                            titleVisibility: .visible, presenting: cancelling) { membership in
            Button("Cancel membership", role: .destructive) { Task { await cancel(membership) } }
        } message: { _ in Text("Member pricing ends for this customer.") }
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
            List(plans) { plan in
                Button { Task { await enroll(plan) } } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(plan.name).font(Theme.font(15, weight: .semibold)).foregroundStyle(Theme.foreground)
                            Spacer()
                            if let price = plan.price {
                                Text("\(money(price, currency: "USD"))\(plan.billingFrequency.map { " / \($0.replacingOccurrences(of: "_", with: " "))" } ?? "")")
                                    .font(Theme.monoFont(13, weight: .medium)).foregroundStyle(Theme.foreground)
                            }
                        }
                        Text([plan.discountPercent > 0 ? "\(plan.discountPercent)% off work" : nil,
                              plan.visitsPerYear.map { "\($0) visit\($0 == 1 ? "" : "s") a year" }, plan.description]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    }
                    .padding(.vertical, 4)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Choose a plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { choosing = false } } }
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
struct MemberChip: View {
    let customerID: String
    @EnvironmentObject private var api: APIClient
    @State private var pricing: MemberPricing?

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 0, height: 0)
            if let pricing, pricing.isMember {
                Chip(text: pricing.discountPercent > 0 ? "Member · \(pricing.discountPercent)% off" : "Member", icon: "star.fill",
                     tint: Theme.brandText, bg: Theme.brandSurface)
            }
        }
        .task(id: customerID) { pricing = try? await api.memberPricing(customerID) }
    }
}

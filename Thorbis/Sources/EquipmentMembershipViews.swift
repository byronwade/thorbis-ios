import SwiftUI

/// Equipment at a customer's places: what's installed, its serial and warranty. Office roles can
/// add, edit and remove; the section hides itself when the server doesn't offer equipment.
struct CustomerEquipmentSection: View {
    let customerID: String
    let locations: [ServiceLocationRecord]
    /// Job view: only the units at this location, read-only.
    var onlyLocationID: String? = nil
    var editable = true
    /// Job view: read through the job so assigned technicians see the units too.
    var jobID: String? = nil
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @State private var items: [EquipmentRecord] = []
    @State private var available = false
    @State private var editing: EquipmentEditorItem?
    /// Paper 86A: the unit whose page is pushed.
    @State private var opened: EquipmentRecord?
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
                                if unit.id != shown.first?.id { WellDivider() }
                                // Paper 86A / 87: a unit opens its own page; Edit lives there.
                                Button { opened = unit } label: { row(unit) }
                                    .buttonStyle(RowPressStyle())
                                    .accessibilityHint("Opens the unit")
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
        .sheet(item: $editing) { item in SheetSurface {
            EquipmentEditor(customerID: customerID, locations: locations, existing: item.record) { await load() }
        } }
        .thorbisDestination(item: $opened) { unit in
            EquipmentDetailView(unit: unit, locations: locations, canEdit: canEdit) { await load() }
        }
    }

    private func row(_ unit: EquipmentRecord) -> some View { EquipmentUnitRow(unit: unit, chevron: true) }

    private func load() async {
        if let jobID, let context = try? await JobServiceContextLoader.load(jobID, api: api) {
            items = context.equipmentRecords
            available = true
            error = nil
            return
        }
        do {
            // An older server without the job read, or a failed request: the customer read still serves office staff.
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
    /// Said under "What it is" when the commit is pressed without it; clears as they type.
    @State private var nameProblem: String?
    /// "Scan data plate" beside the serial number (Paper 86C): opens the scanner, which hands
    /// back the brand, model and serial it read.
    @State private var scanning = false
    @FocusState private var nameFocused: Bool
    private static let nameMissing = "Say what it is, like \u{201C}50-gal gas water heater.\u{201D}"

    var body: some View {
        // Paper 86C: Cancel and Save in the title row, then three cards (what it is; when and where;
        // warranty), notes, and a line saying who sees it. Save is never pre-disabled.
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let error { ListErrorRow(message: error) }
                    formCard {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Name").font(Theme.font(13)).foregroundStyle(Theme.muted).accessibilityHidden(true)
                            TextField("", text: $input.name, prompt: .placeholder("50-gal gas water heater"))
                                .font(Theme.font(17, weight: .medium))
                                .focused($nameFocused)
                                .accessibilityLabel("Name")
                            if let nameProblem { FieldProblem(message: nameProblem) }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onChange(of: input.name) { _, _ in nameProblem = nil }
                        WellDivider(leading: 16)
                        stackedField("Type", text: binding(\.kind), prompt: "Air conditioner \u{00B7} condenser")
                        WellDivider(leading: 16)
                        stackedField("Brand", text: binding(\.brand), prompt: "Trane")
                        WellDivider(leading: 16)
                        stackedField("Model", text: binding(\.model), prompt: "XR14 \u{00B7} 4TTR4036L1000A")
                        WellDivider(leading: 16)
                        HStack(spacing: 4) {
                            stackedField("Serial number", text: binding(\.serialNumber), prompt: "19283KUF4F")
                                .textInputAutocapitalization(.characters)
                            Button { scanning = true } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "viewfinder").font(.system(size: 14, weight: .semibold))
                                        .accessibilityHidden(true)
                                    Text("Scan data plate").lineLimit(1)
                                }
                                .paperButton(.compact, tone: .tinted)
                            }
                            .buttonStyle(PressStyle())
                            .disabled(busy)
                            .fixedSize()
                            .padding(.trailing, 12)
                            .accessibilityIdentifier("equipment-scan-plate")
                        }
                    }
                    formCard {
                        dateRow("Install date", $installed)
                        if !locations.isEmpty {
                            WellDivider(leading: 16)
                            // Paper's word is "Property"; the select still announces "Location" (tests read it).
                            ThorbisSelect(options: [(String?.none, "Not set")]
                                            + locations.map { (Optional($0.id), $0.label.isEmpty ? $0.address : "\($0.label) · \($0.address)") },
                                          selection: $input.locationId, label: "Property", menuTitle: "Location")
                                .padding(.horizontal, 16).frame(minHeight: 56)
                        }
                    }
                    formCard {
                        Toggle(isOn: Binding(get: { warranty != nil },
                                             set: { on in warranty = on ? (warranty ?? .now) : nil })) {
                            Text("Under warranty").font(Theme.font(16)).foregroundStyle(Theme.foreground)
                        }
                        .tint(Theme.brand)
                        .padding(.horizontal, 16).frame(minHeight: 56)
                        if warranty != nil {
                            WellDivider(leading: 16)
                            dateRow("Warranty ends", $warranty)
                        }
                    }
                    formCard {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notes").font(Theme.font(13)).foregroundStyle(Theme.muted).accessibilityHidden(true)
                            TextField("", text: binding(\.notes), prompt: .placeholder("Filters, access, history…"), axis: .vertical)
                                .lineLimit(2...6).font(Theme.font(15))
                                .accessibilityLabel("Notes")
                        }
                        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Text("Saved to this customer. Techs see it on every job at this address.")
                        .font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                    if existing != nil {
                        Button { confirmRemove = true } label: {
                            Text("Remove equipment").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.destructive)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(PressStyle())
                        .disabled(busy)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background.ignoresSafeArea())
        .thorbisSheetPresentation([.large])
        .interactiveDismissDisabled(busy)
            .thorbisConfirm("Remove this equipment?", isPresented: $confirmRemove,
                            actions: [ThorbisConfirmAction("Remove", role: .destructive) { Task { await remove() } }])
            .onAppear(perform: fill)
            .sheet(isPresented: $scanning) { SheetSurface {
                DataPlateScannerSheet(onRead: { values in apply(values) }, onDone: { scanning = false })
            } }
            #if DEBUG
            // `--paper-preview-form-errors`: the commit pressed with the name blank.
            .task {
                guard PaperPreview.enabled, ProcessInfo.processInfo.arguments.contains("--paper-preview-form-errors") else { return }
                try? await Task.sleep(for: .milliseconds(600))
                nameProblem = Self.nameMissing
            }
            #endif
    }

    private func binding(_ key: WritableKeyPath<EquipmentInput, String?>) -> Binding<String> {
        Binding(get: { input[keyPath: key] ?? "" }, set: { input[keyPath: key] = $0 })
    }

    /// Paper's title row: Cancel on a card pill, the title, Save on the brand pill.
    private var header: some View {
        ZStack {
            Text(existing == nil ? "Add equipment" : (existing?.name ?? "Equipment")).font(Theme.font(17, weight: .semibold))
                .lineLimit(1).minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 100)
            HStack {
                Button { dismiss() } label: {
                    Text("Cancel").font(Theme.font(16, weight: .medium)).lineLimit(1).fixedSize().foregroundStyle(Theme.foreground)
                        .padding(.horizontal, 16).frame(minHeight: 44)
                        .background(Theme.card, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .disabled(busy)
                Spacer(minLength: 8)
                Button {
                    // Pressed without a name, it says so under the field.
                    if input.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        nameProblem = Self.nameMissing
                        nameFocused = true
                    } else {
                        Task { await save() }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if busy { ProgressView().tint(.white) }
                        Text("Save").font(Theme.font(16, weight: .semibold)).lineLimit(1).fixedSize()
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18).frame(minHeight: 44)
                    .background(Theme.brand, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .disabled(busy)
                .accessibilityLabel(existing == nil ? "Add equipment" : "Save equipment")
                .accessibilityIdentifier("equipment-commit")
            }
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 2)
        // A title row is a bar: it stops growing at xLarge so the pills never break mid-word and
        // the title keeps its room. The form under it follows the reader's text size in full.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    /// One Paper card: the card tone, radius 20, rows separated by an inset hairline.
    private func formCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    /// A label above its answer (13 muted over 17 Medium), typed in place.
    private func stackedField(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Theme.font(13)).foregroundStyle(Theme.muted).accessibilityHidden(true)
            TextField("", text: text, prompt: .placeholder(prompt))
                .font(Theme.font(17, weight: .medium))
                .accessibilityLabel(label)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// An inline date row: the label on the left, the date (or Add) on the right, with a way to clear it.
    @ViewBuilder private func dateRow(_ title: String, _ value: Binding<Date?>) -> some View {
        HStack(spacing: 8) {
            Text(title).font(Theme.font(16)).foregroundStyle(Theme.foreground)
            Spacer(minLength: 8)
            if let date = value.wrappedValue {
                DatePicker(title, selection: Binding(get: { date }, set: { value.wrappedValue = $0 }), displayedComponents: .date)
                    .labelsHidden()
                Button { value.wrappedValue = nil } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.subtle)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle()).accessibilityLabel("Clear \(title.lowercased())")
            } else {
                Button { value.wrappedValue = .now } label: {
                    Text("Add").font(Theme.font(16)).foregroundStyle(Theme.muted)
                        .frame(minWidth: 44, minHeight: 44, alignment: .trailing).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Add \(title.lowercased())")
            }
        }
        .padding(.leading, 16).padding(.trailing, 8).frame(minHeight: 56)
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

    /// Fills the form from a scan. What the tag said replaces brand, model and serial; the name is
    /// only suggested when it is still blank, and a printed date is kept in the notes (the tag's
    /// date is when it was made, not when it was installed).
    private func apply(_ values: DataPlateValues) {
        if let brand = values.brand { input.brand = brand }
        if let model = values.model { input.model = model }
        if let serial = values.serial { input.serialNumber = serial }
        if input.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let name = [values.brand, values.model].compactMap { $0 }.joined(separator: " ")
            if !name.isEmpty { input.name = name }
        }
        if let made = values.made {
            let line = "Made \(made) (from the data plate)"
            let notes = (input.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !notes.contains(line) { input.notes = notes.isEmpty ? line : notes + "\n" + line }
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
    /// Job view: read through the job so assigned technicians see member pricing too.
    var jobID: String? = nil
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var store: Store
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
                // design 2026-10-30: the plan as a row on one panel, "Active" as its word.
                // Paper 85: the plan's name, its benefits and renewal, "Active" with its green mark.
                PaperSection("Maintenance plan", count: active.count > 1 ? active.count : nil) {
                    if let error { ListErrorRow(message: error).padding(.horizontal, PaperCardMetrics.inset) }
                    if active.isEmpty && canEdit {
                        Button { choosing = true } label: {
                            PaperListRow(leading: .icon("plus"), title: "Add a maintenance plan",
                                         subtitle: "Member pricing and tune-up visits")
                        }
                        .buttonStyle(RowPressStyle())
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(active) { membership in
                                if membership.id != active.first?.id { WellDivider() }
                                PaperListRow(title: membership.name, subtitle: membershipDetail(membership), subtitleLines: 2) {
                                    StatusWord(text: "Active", tint: Theme.success)
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                        .padding(.vertical, PaperCardMetrics.edge)
                    }
                }
                // Paper 85: the plan's actions on their own card under it; Cancel membership in
                // the quiet red, 56 tall. It opens Cancel membership (85B).
                if canEdit && !active.isEmpty {
                    PaperCard {
                        ForEach(active) { membership in
                            if membership.id != active.first?.id { WellDivider() }
                            Button { cancelling = membership } label: {
                                Text(active.count > 1 ? "Cancel \(membership.name)" : "Cancel membership")
                                    .font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.destructive)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 9)
                                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(RowPressStyle())
                            .accessibilityIdentifier("membership-cancel-\(membership.id)")
                        }
                    }
                    .padding(.top, 20)
                }
            }
        }
        .task(id: customerID) { await load() }
        .sheet(isPresented: $choosing) { SheetSurface { planPicker } }
        // Paper 85B: cancelling is its own page (what ends, then the red commit).
        .thorbisDestination(item: $cancelling) { membership in
            CancelMembershipView(customerID: customerID, membership: membership,
                                 customerName: store.customerName(customerID),
                                 onCancelled: { await load() })
        }
    }

    private func membershipDetail(_ membership: MembershipRecord) -> String { membership.detail }

    private var planPicker: some View {
        NavigationStack {
            ScrollView {
                PaperSection("Plans", count: plans.count) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(plans) { plan in
                            if plan.id != plans.first?.id { WellDivider() }
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
            .background(Theme.canvas)
            .navigationTitle("Choose a plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ThorbisToolbarItem(placement: .topBarLeading) { Button("Cancel") { choosing = false } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func load() async {
        if let jobID, let context = try? await JobServiceContextLoader.load(jobID, api: api) {
            memberships = context.memberships
            plans = []
            available = true
            return
        }
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


/// One unit (Paper 86): its name over brand · model · installed year, the serial on a quiet line,
/// and the warranty as a coloured word ("Warranty to 2029", "Out of warranty").
struct EquipmentUnitRow: View {
    let unit: EquipmentRecord
    /// The company book (Paper 86): whose it is and where ("Marlowe · 412 Birchwood Ln"), in
    /// place of the brand and model; the serial line is left to the unit's page.
    var place: String? = nil
    /// A quiet chevron after the warranty word where the row opens the unit's page (Paper 87).
    var chevron = false

    var body: some View {
        let end = unit.warrantyEnd
        let expired = end.map { $0 < Calendar.current.startOfDay(for: .now) } ?? false
        let year: String? = end.map { String(Calendar.current.component(.year, from: $0)) }
        let installed: String? = unit.installedOn.flatMap(EquipmentRecord.day)
            .map { "installed \(Calendar.current.component(.year, from: $0))" }
        let made = [unit.brand ?? "", unit.model ?? "", installed ?? ""].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
        let placed = [place ?? "", installed ?? ""].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
        let subtitle = place == nil ? made : placed
        let serial: String? = place == nil ? unit.serialNumber.flatMap { $0.isEmpty ? nil : "SN \($0)" } : nil
        let word: String? = year.map { expired ? "Out of warranty" : "Warranty to \($0)" }
        if place != nil || serial == nil {
            // Paper 86 / 87: the unit over one muted line, the warranty word trailing the name.
            PaperRecordRow(title: unit.name, subtitle: subtitle.isEmpty ? nil : subtitle,
                           status: word, statusColor: expired ? Theme.muted : Theme.success) {
                if chevron { PaperRowChevron() }
            }
        } else {
            PaperListRow(title: unit.name, subtitle: subtitle.isEmpty ? nil : subtitle,
                         meta: serial, subtitleLines: 2) {
                HStack(spacing: 12) {
                    if let word {
                        Text(word)
                            .font(Theme.font(14, weight: .medium))
                            .foregroundStyle(expired ? Theme.muted : Theme.success)
                            .lineLimit(1).fixedSize()
                    }
                    if chevron { PaperRowChevron() }
                }
            }
        }
    }
}

/// Paper 86A "Equipment detail": the unit's name as the title over whose it is and where, its
/// details on one card with Edit beside the label, its notes, and "Start a job for this unit" as
/// the page's one commit. Service history and photos per unit have no route yet, so they are not
/// drawn.
struct EquipmentDetailView: View {
    let unit: EquipmentRecord
    let locations: [ServiceLocationRecord]
    var canEdit = false
    /// Runs after the unit is saved or removed, so the list behind follows.
    var onChanged: () async -> Void = {}
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController
    @Environment(\.dismiss) private var dismiss
    /// The unit as last read after an edit; nil until it is edited here.
    @State private var current: EquipmentRecord?
    @State private var editing = false
    @State private var showNewJob = false
    @State private var openCustomer: Customer?
    @Environment(\.dynamicTypeSize) private var typeSize

    private var shown: EquipmentRecord { current ?? unit }
    private var customer: Customer? { store.customers.first { $0.id == shown.customerId } }
    private var canCreateJob: Bool { session.can("job.create", feature: "jobs") }

    /// "Danielle Marlowe · 412 Birchwood Ln".
    private var subtitle: String {
        let name = shown.customerName ?? customer?.name ?? ""
        let address = locations.first { $0.id == shown.locationId }?.address ?? shown.locationAddress ?? ""
        let street = address.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        return [name, street].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
    }

    private var facts: [EquipmentFact] {
        var rows: [EquipmentFact] = []
        func add(_ label: String, _ value: String?) {
            guard let value, !value.isEmpty else { return }
            rows.append(EquipmentFact(label: label, value: value, tint: nil))
        }
        add("Type", shown.kind)
        add("Brand", shown.brand)
        add("Model", shown.model)
        add("Serial number", shown.serialNumber)
        if let installed = shown.installedOn.flatMap(EquipmentRecord.day) {
            add("Installed", installed.formatted(date: .abbreviated, time: .omitted))
        }
        if let end = shown.warrantyEnd {
            let expired = end < Calendar.current.startOfDay(for: .now)
            rows.append(EquipmentFact(label: "Warranty until", value: end.formatted(date: .abbreviated, time: .omitted),
                                      tint: expired ? Theme.muted : Theme.success))
        }
        return rows
    }

    var body: some View {
        let rows = facts
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(shown.name).font(Theme.font(34, weight: .bold)).tracking(-0.85)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if !subtitle.isEmpty {
                        Text(subtitle).font(Theme.font(15)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, Theme.gutter - PaperCardMetrics.margin)
                PaperSection(title: "Details") {
                    if rows.isEmpty {
                        Text("No brand, model or serial number yet.").font(Theme.font(15)).foregroundStyle(Theme.muted)
                            .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 14)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(rows) { fact in
                                if fact.id != rows.first?.id { WellDivider() }
                                PaperDetailRow(label: fact.label) {
                                    Text(fact.value).foregroundStyle(fact.tint ?? Theme.foreground)
                                }
                                .padding(.horizontal, PaperCardMetrics.inset).frame(minHeight: 52)
                            }
                        }
                    }
                } accessory: {
                    if canEdit {
                        Button { editing = true } label: {
                            Text("Edit").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.brandText)
                                .frame(minWidth: 44, minHeight: 44, alignment: .trailing).contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel("Edit equipment")
                        .accessibilityIdentifier("equipment-edit")
                    }
                }
                if let notes = shown.notes, !notes.isEmpty {
                    PaperSection("Notes") {
                        Text(notes).font(Theme.font(15)).foregroundStyle(Theme.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 12)
                    }
                }
                // At accessibility sizes a pinned commit would cover the page, so it follows the facts.
                if canCreateJob, customer != nil, typeSize.isAccessibilitySize {
                    Button { showNewJob = true } label: { Text("Start a job for this unit").inkCommit() }
                        .buttonStyle(PressStyle())
                        .accessibilityIdentifier("equipment-start-job")
                }
            }
            .paperCardMargin().padding(.top, 8).padding(.bottom, 24)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background)
        // Paper 86A: "+ Start a job for this unit" is the page's commit, pinned at the foot.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if canCreateJob, customer != nil, !typeSize.isAccessibilitySize {
                PaperActionBar(title: "Start a job for this unit", symbol: "plus", identifier: "equipment-start-job") { showNewJob = true }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            let items = menuItems
            if !items.isEmpty {
                ThorbisToolbarItem(placement: .topBarTrailing) {
                    ThorbisMenu(items: items, accessibilityLabel: "Equipment actions") {
                        PaperCircleLabel(symbol: "ellipsis", size: 44, fill: Theme.card)
                    }
                }
            }
        }
        .sheet(isPresented: $editing) { SheetSurface {
            EquipmentEditor(customerID: shown.customerId, locations: locations, existing: shown) { await reload() }
        } }
        .sheet(isPresented: $showNewJob) { SheetSurface { NewJobSheet(preselected: customer, locationID: shown.locationId) } }
        .thorbisDestination(item: $openCustomer) { CustomerDetailView(customer: $0) }
    }

    private var menuItems: [ThorbisMenuItem] {
        var items: [ThorbisMenuItem] = []
        if canEdit { items.append(ThorbisMenuItem("Edit equipment", icon: "pencil") { editing = true }) }
        if let customer { items.append(ThorbisMenuItem("Open customer", icon: "person") { openCustomer = customer }) }
        return items
    }

    /// After Save or Remove in the editor: read the unit again; a removed unit closes its page.
    private func reload() async {
        await onChanged()
        guard let units = try? await api.customerEquipment(shown.customerId) else { return }
        if let fresh = units.first(where: { $0.id == unit.id }) {
            // The customer read leaves out the owner and site names the company book sent.
            var merged = fresh
            if merged.customerName == nil { merged.customerName = shown.customerName }
            if merged.locationAddress == nil, merged.locationId == shown.locationId { merged.locationAddress = shown.locationAddress }
            current = merged
        } else {
            dismiss()
        }
    }
}

/// One "Details" fact on a unit's page.
private struct EquipmentFact: Identifiable {
    let label: String
    let value: String
    let tint: Color?
    var id: String { label }
}

/// Web parity (apps/web equipment.tsx): the company's equipment book from the server, the same rows
/// the office and the customer page read, grouped under the site each unit lives at. A unit opens
/// its customer, where it is edited. Hidden when the read is refused or the server is older.
struct CompanyEquipmentBook: View {
    var onLoaded: (Bool) -> Void = { _ in }
    /// How many units the book holds, for the page's subtitle ("6 units").
    var onCount: (Int) -> Void = { _ in }
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var store: Store
    @State private var items: [EquipmentRecord]?
    @State private var opened: EquipmentRecord?
    /// Paper 86's segments. "Due for service" is left out: the server keeps no service-due date.
    @State private var filter = CompanyEquipmentBook.allFilter

    private static let allFilter = "All"
    private static let warrantyFilter = "Under warranty"

    private func underWarranty(_ unit: EquipmentRecord) -> Bool {
        guard let end = unit.warrantyEnd else { return false }
        return end >= Calendar.current.startOfDay(for: .now)
    }

    private var shown: [EquipmentRecord] {
        let all = (items ?? []).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return filter == CompanyEquipmentBook.warrantyFilter ? all.filter { underWarranty($0) } : all
    }

    /// "Marlowe · 412 Birchwood Ln": whose it is, then the street it sits at.
    private func place(_ unit: EquipmentRecord) -> String {
        let customer = unit.customerName ?? store.customerName(unit.customerId)
        let address = unit.locationAddress ?? unit.locationLabel ?? ""
        let street = address.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        return [customer, street].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
    }

    /// Paper 86 groups by what is due; the server keeps no service-due date, so the groups are
    /// the warranty: still covered, then the rest.
    private func group(_ title: String, _ list: [EquipmentRecord]) -> some View {
        Group {
            if !list.isEmpty {
                PaperCardLabel(title: title, count: list.count).padding(.top, 20)
                PaperRowsCard {
                    ForEach(list) { unit in
                        if unit.id != list.first?.id { WellDivider(leading: 16) }
                        Button { opened = unit } label: {
                            EquipmentUnitRow(unit: unit, place: place(unit))
                        }
                        .buttonStyle(RowPressStyle())
                        .accessibilityHint("Opens the unit")
                    }
                }
            }
        }
    }

    var body: some View {
        let units = shown
        VStack(alignment: .leading, spacing: 0) {
            if let items, !items.isEmpty {
                // Paper 86: "Search or ask" with the filter circle, the segments, then the units
                // grouped on cards: the unit over whose it is, where, and when it went in.
                PaperSearchBar(placeholder: "Search or ask") {
                    ThorbisMenu(items: [CompanyEquipmentBook.allFilter, CompanyEquipmentBook.warrantyFilter].map { name in
                        ThorbisMenuItem(name, isSelected: name == filter) { filter = name }
                    }, title: "Show", accessibilityLabel: "Filter equipment") {
                        PaperFilterCircle(active: filter != CompanyEquipmentBook.allFilter)
                    }
                    .accessibilityValue(filter)
                }
                .paperCardMargin()
                PaperTabs(options: [CompanyEquipmentBook.allFilter, CompanyEquipmentBook.warrantyFilter], selection: $filter)
                    .padding(.top, 16)
                if units.isEmpty {
                    Text("No units under warranty.").font(Theme.font(15)).foregroundStyle(Theme.muted)
                        .padding(.horizontal, Theme.gutter).padding(.top, 20)
                } else {
                    group("Under warranty", units.filter { underWarranty($0) })
                    group("Out of warranty", units.filter { !underWarranty($0) })
                }
            }
        }
        .task(id: session.generation) { await load() }
        .thorbisDestination(item: $opened) { unit in
            EquipmentDetailView(unit: unit, locations: [],
                                canEdit: session.can("customer.edit", feature: "core_crm")) { await load() }
        }
    }

    private func load() async {
        guard session.can("customer.view", feature: "core_crm") else { onLoaded(false); onCount(0); return }
        do {
            let loaded = try await api.allEquipment()
            items = loaded
            onLoaded(!loaded.isEmpty)
            onCount(loaded.count)
            #if DEBUG
            // `--paper-preview-screen equipment-detail`: open the first unit once the book has loaded.
            if PaperPreview.enabled, PaperPreview.screen == "equipment-detail", opened == nil { opened = loaded.first }
            #endif
        } catch is CancellationError {
        } catch {
            items = nil
            onLoaded(false)
            onCount(0)
        }
    }
}


extension MembershipRecord {
    /// "15% off · Twice a year · Renews Mar 1, 2027", or the kind when nothing else is known.
    var detail: String {
        var parts: [String] = []
        if discountPercent > 0 { parts.append("\(discountPercent)% off") }
        if let cadence, !cadence.isEmpty { parts.append(cadence) }
        if let renews = renewsOn.flatMap(EquipmentRecord.day) { parts.append("Renews \(renews.formatted(date: .abbreviated, time: .omitted))") }
        return parts.isEmpty ? kind.capitalized : parts.joined(separator: " \u{00B7} ")
    }
}

/// Web parity (apps/web agreements.tsx): the company's agreements from the server, grouped by kind
/// as on the web (Maintenance, Membership), cancelled ones last. A row opens its customer, where
/// agreements are sold and cancelled. Hidden when the read is refused or the server is older.
struct CompanyAgreementsBook: View {
    var onLoaded: (Bool) -> Void = { _ in }
    /// How many agreements are live, for the page's subtitle ("236 members").
    var onCount: (Int) -> Void = { _ in }
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var store: Store
    @State private var items: [MembershipRecord]?
    /// Paper 85C's first card: the plans the company sells, each with how many members hold it.
    @State private var plans: [MembershipPlan] = []
    @State private var openCustomer: Customer?

    private func members(_ plan: MembershipPlan) -> Int {
        (items ?? []).filter { $0.planId == plan.id && $0.status != "cancelled" }.count
    }

    /// "$29 a month · 2 visits a year · 15% off"; "Custom price" when the plan has none.
    private func planLine(_ plan: MembershipPlan) -> String {
        var parts: [String] = []
        if let price = plan.price {
            // Paper 85C: "$29 a month", no cents on a whole price.
            let full = money(price, currency: "USD")
            let amount = full.hasSuffix(".00") ? String(full.dropLast(3)) : full
            let frequency = plan.billingFrequency ?? ""
            if frequency == "monthly" {
                parts.append("\(amount) a month")
            } else if frequency == "yearly" || frequency == "annual" || frequency == "annually" {
                parts.append("\(amount) a year")
            } else if frequency.isEmpty {
                parts.append(amount)
            } else {
                parts.append("\(amount) / \(frequency.replacingOccurrences(of: "_", with: " "))")
            }
        } else {
            parts.append("Custom price")
        }
        if let visits = plan.visitsPerYear, visits > 0 {
            parts.append(visits == 1 ? "1 visit a year" : "\(visits) visits a year")
        }
        if plan.discountPercent > 0 { parts.append("\(plan.discountPercent)% off") }
        return parts.joined(separator: " \u{00B7} ")
    }

    /// One plan (Paper 85C): 16 Semibold over a 14 muted line, the member count trailing, 64 tall.
    private func planRow(_ plan: MembershipPlan) -> some View {
        let count = members(plan)
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(plan.name).font(Theme.font(16, weight: .semibold)).foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Text(planLine(plan)).font(Theme.font(14)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(count)").font(Theme.font(16, weight: .semibold)).foregroundStyle(Theme.foreground)
        }
        .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(plan.name), \(planLine(plan))")
        .accessibilityValue(count == 1 ? "1 member" : "\(count) members")
    }

    private var groups: [(title: String, rows: [MembershipRecord])] {
        let all = items ?? []
        let live = all.filter { $0.status != "cancelled" }
        let byName: (MembershipRecord, MembershipRecord) -> Bool = {
            customer($0).localizedStandardCompare(customer($1)) == .orderedAscending
        }
        return [("Maintenance", live.filter { $0.kind == "maintenance" }.sorted(by: byName)),
                ("Membership", live.filter { $0.kind != "maintenance" }.sorted(by: byName)),
                ("Cancelled", all.filter { $0.status == "cancelled" }.sorted(by: byName))]
            .filter { !$0.rows.isEmpty }
    }

    private func customer(_ row: MembershipRecord) -> String { row.customerName ?? store.customerName(row.customerId) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Paper 85C: the plans on the first card, straight under the title.
            if !plans.isEmpty {
                PaperRowsCard {
                    ForEach(plans) { plan in
                        if plan.id != plans.first?.id { WellDivider(leading: 16) }
                        planRow(plan)
                    }
                }
            }
            // Then who holds one: the member over their plan and what it gives, the state trailing.
            ForEach(groups, id: \.title) { group in
                PaperCardLabel(title: group.title, count: group.rows.count).padding(.top, 20)
                PaperRowsCard {
                    ForEach(group.rows) { row in
                        if row.id != group.rows.first?.id { WellDivider(leading: 16) }
                        Button { openCustomer = store.customers.first { $0.id == row.customerId } } label: {
                            PaperRecordRow(title: customer(row), subtitle: "\(row.planName ?? row.name) \u{00B7} \(row.detail)",
                                           status: row.status == "cancelled" ? "Cancelled" : "Active",
                                           statusColor: row.status == "cancelled" ? Theme.muted : Theme.success,
                                           dimmed: row.status == "cancelled")
                        }
                        .buttonStyle(RowPressStyle())
                        .accessibilityHint("Opens the customer")
                    }
                }
            }
        }
        .task(id: session.generation) { await load() }
        .thorbisDestination(item: $openCustomer) { CustomerDetailView(customer: $0) }
    }

    private func load() async {
        guard session.can("customer.view", feature: "core_crm") else { onLoaded(false); onCount(0); return }
        do {
            let loaded = try await api.allMemberships()
            items = loaded
            onLoaded(!loaded.isEmpty)
            onCount(loaded.filter { $0.status != "cancelled" }.count)
            // The plans card is extra: an older server or a refused read leaves it out.
            if !loaded.isEmpty, let sold = try? await api.membershipPlans() { plans = sold }
        } catch is CancellationError {
        } catch {
            items = nil
            plans = []
            onLoaded(false)
            onCount(0)
        }
    }
}

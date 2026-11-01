import SwiftUI

enum LocalWorkspaceSection: String, CaseIterable, Hashable {
    case fleet, equipment, agreements, team

    var title: String {
        switch self {
        case .fleet: "Fleet"
        case .equipment: "Equipment"
        case .agreements: "Agreements"
        case .team: "Team additions"
        }
    }

    /// Navigation gating follows apps/web/src/navigation/registry.ts.
    var requiredCapability: String {
        switch self {
        case .fleet: "job.view"
        case .equipment, .agreements: "customer.view"
        case .team: "organization.view"
        }
    }

    var requiredFeature: String? {
        switch self {
        case .fleet: "jobs"
        case .equipment, .agreements: "core_crm"
        case .team: nil
        }
    }

    var fields: [(key: String, label: String, required: Bool)] {
        switch self {
        case .fleet:
            [
                ("name", "Name", true), ("model", "Make and model", false),
                ("plate", "Plate", false), ("year", "Year", false), ("vin", "VIN", false),
                ("assignedTo", "Assigned driver (name or local ID)", false),
                ("mileage", "Mileage as noted", false), ("purchasePrice", "Purchase price as noted", false),
                ("marketValue", "Owner-estimated market value", false),
                ("purchaseDate", "Purchase date (YYYY-MM-DD)", false),
                ("registrationDue", "Registration due (YYYY-MM-DD)", false),
                ("lastOilChange", "Last oil change (YYYY-MM-DD)", false),
                ("nextOilChange", "Next oil change (YYYY-MM-DD)", false),
                ("lastTireRotation", "Last tire rotation (YYYY-MM-DD)", false),
                ("lastNewTires", "Last new tires (YYYY-MM-DD)", false),
                ("lastRepair", "Last repair", false), ("notes", "Notes", false),
            ]
        case .equipment:
            [("name", "Unit name", true), ("site", "Site as written", true),
             ("brand", "Brand", false), ("serial", "Serial", false),
             ("installedYear", "Installed year", false), ("notes", "Notes", false)]
        case .agreements:
            [("name", "Agreement name", true), ("customer", "Customer name as written", true),
             ("cadence", "Visit cadence", true), ("renewsOn", "Renews on (YYYY-MM-DD)", false),
             ("notes", "Notes", false)]
        case .team:
            [("name", "Name", true), ("role", "Role", true), ("phone", "Phone", false)]
        }
    }
}

struct LocalWorkspaceRow: Identifiable {
    let id: String
    let title: String
    let subtitle: String
}

struct LocalWorkspaceDraft: Identifiable {
    let id: String
    let createdAt: String
    var kind: LocalAgreementRecord.Kind = .maintenance
    var values: [String: String] = [:]

    init(id: String = UUID().uuidString,
         createdAt: String = ISO8601DateFormatter().string(from: Date())) {
        self.id = id
        self.createdAt = createdAt
    }

    func value(_ key: String) -> String { values[key] ?? "" }
    func optional(_ key: String) -> String? {
        let value = self.value(key).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
    func required(_ key: String) -> String {
        value(key).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Owns one opened device partition. Clearing this model immediately hides old actor data.
@MainActor
final class LocalWorkspaceViewModel: ObservableObject {
    @Published private(set) var actorID: String?
    @Published private(set) var organizationID: String?
    @Published private(set) var error: String?
    @Published private(set) var revision = 0
    private var storage: LocalWorkspaceRecords?

    func bind(actorID: String, organizationID: String) {
        guard self.actorID != actorID || self.organizationID != organizationID || storage == nil else { return }
        clear()
        do {
            let opened = try LocalWorkspaceRecords(actorID: actorID, organizationID: organizationID)
            storage = opened
            self.actorID = actorID
            self.organizationID = organizationID
        } catch {
            self.error = error.localizedDescription
        }
    }

    func clear() {
        storage = nil
        actorID = nil
        organizationID = nil
        error = nil
        revision += 1
    }

    func rows(_ section: LocalWorkspaceSection) -> [LocalWorkspaceRow] {
        guard let storage else { return [] }
        switch section {
        case .fleet: return storage.vehicles.map { .init(id: $0.id, title: $0.name, subtitle: [$0.model, $0.plate].compactMap { $0 }.joined(separator: " · ")) }
        case .equipment: return storage.equipment.map { .init(id: $0.id, title: $0.name, subtitle: $0.site) }
        case .agreements: return storage.agreements.map { .init(id: $0.id, title: $0.name, subtitle: "\($0.customer) · \($0.kind.rawValue.capitalized)") }
        case .team: return storage.crew.map { .init(id: $0.id, title: $0.name, subtitle: $0.role) }
        }
    }

    func draft(_ section: LocalWorkspaceSection, id: String) -> LocalWorkspaceDraft? {
        guard let storage else { return nil }
        var draft: LocalWorkspaceDraft
        switch section {
        case .fleet:
            guard let row = storage.vehicles.first(where: { $0.id == id }) else { return nil }
            draft = .init(id: row.id, createdAt: row.createdAt)
            draft.values = ["name": row.name, "model": row.model ?? "", "plate": row.plate ?? "",
                            "year": row.year ?? "", "vin": row.vin ?? "", "assignedTo": row.assignedTo ?? "",
                            "mileage": row.mileage ?? "", "purchasePrice": row.purchasePrice ?? "",
                            "marketValue": row.marketValue ?? "", "purchaseDate": row.purchaseDate ?? "",
                            "registrationDue": row.registrationDue ?? "", "lastOilChange": row.lastOilChange ?? "",
                            "nextOilChange": row.nextOilChange ?? "", "lastTireRotation": row.lastTireRotation ?? "",
                            "lastNewTires": row.lastNewTires ?? "", "lastRepair": row.lastRepair ?? "",
                            "notes": row.notes ?? ""]
        case .equipment:
            guard let row = storage.equipment.first(where: { $0.id == id }) else { return nil }
            draft = .init(id: row.id, createdAt: row.createdAt)
            draft.values = ["name": row.name, "site": row.site, "brand": row.brand ?? "",
                            "serial": row.serial ?? "", "installedYear": row.installedYear ?? "",
                            "notes": row.notes ?? ""]
        case .agreements:
            guard let row = storage.agreements.first(where: { $0.id == id }) else { return nil }
            draft = .init(id: row.id, createdAt: row.createdAt)
            draft.kind = row.kind
            draft.values = ["name": row.name, "customer": row.customer, "cadence": row.cadence,
                            "renewsOn": row.renewsOn ?? "", "notes": row.notes ?? ""]
        case .team:
            guard let row = storage.crew.first(where: { $0.id == id }) else { return nil }
            draft = .init(id: row.id, createdAt: row.createdAt)
            draft.values = ["name": row.name, "role": row.role, "phone": row.phone ?? ""]
        }
        return draft
    }

    func save(_ draft: LocalWorkspaceDraft, section: LocalWorkspaceSection) throws {
        guard let storage else { throw Problem(title: "Local book unavailable", status: nil, detail: nil) }
        guard section.fields.filter({ $0.required }).allSatisfy({ !draft.required($0.key).isEmpty }) else {
            throw Problem(title: "Required fields are missing", status: nil, detail: nil)
        }
        switch section {
        case .fleet:
            try storage.save(LocalVehicleRecord(id: draft.id, name: draft.required("name"),
                model: draft.optional("model"), plate: draft.optional("plate"), year: draft.optional("year"),
                vin: draft.optional("vin"), assignedTo: draft.optional("assignedTo"), mileage: draft.optional("mileage"),
                purchasePrice: draft.optional("purchasePrice"), marketValue: draft.optional("marketValue"),
                purchaseDate: draft.optional("purchaseDate"), registrationDue: draft.optional("registrationDue"),
                lastOilChange: draft.optional("lastOilChange"), nextOilChange: draft.optional("nextOilChange"),
                lastTireRotation: draft.optional("lastTireRotation"), lastNewTires: draft.optional("lastNewTires"),
                lastRepair: draft.optional("lastRepair"), notes: draft.optional("notes"), createdAt: draft.createdAt))
        case .equipment:
            try storage.save(LocalEquipmentRecord(id: draft.id, name: draft.required("name"),
                brand: draft.optional("brand"), serial: draft.optional("serial"), site: draft.required("site"),
                installedYear: draft.optional("installedYear"), notes: draft.optional("notes"), createdAt: draft.createdAt))
        case .agreements:
            try storage.save(LocalAgreementRecord(id: draft.id, kind: draft.kind, name: draft.required("name"),
                customer: draft.required("customer"), cadence: draft.required("cadence"),
                renewsOn: draft.optional("renewsOn"), notes: draft.optional("notes"), createdAt: draft.createdAt))
        case .team:
            try storage.save(LocalCrewRecord(id: draft.id, name: draft.required("name"),
                role: draft.required("role"), phone: draft.optional("phone"), createdAt: draft.createdAt))
        }
        revision += 1
    }

    func remove(_ id: String, section: LocalWorkspaceSection) throws {
        guard let storage else { throw Problem(title: "Local book unavailable", status: nil, detail: nil) }
        switch section {
        case .fleet: try storage.removeVehicle(id)
        case .equipment: try storage.removeEquipment(id)
        case .agreements: try storage.removeAgreement(id)
        case .team: try storage.removeCrew(id)
        }
        revision += 1
    }
}

/// Pass the authenticated user and active organization from SessionController.
/// Root navigation should gate with section.requiredCapability/requiredFeature.
struct LocalWorkspaceView: View {
    let section: LocalWorkspaceSection
    let actorID: String
    let organizationID: String
    @StateObject private var model = LocalWorkspaceViewModel()
    @State private var editor: LocalWorkspaceDraft?
    @State private var editorOwner: String?
    @State private var actionError: String?

    private var identityKey: String { "\(actorID.lowercased())|\(organizationID.lowercased())" }

    private func present(_ draft: LocalWorkspaceDraft) {
        editorOwner = identityKey
        editor = draft
    }

    var body: some View {
        // design 2026-10-30: the list system — header, rows on one panel, edits in each row's •••
        // (swipe-to-delete moved there), the one ink commit at the bottom.
        let bound = model.actorID == actorID && model.organizationID == organizationID
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.title).font(Theme.font(30, weight: .medium)).tracking(-0.6)
                        .accessibilityAddTraits(.isHeader)
                    Text("On this device · Not synced").font(Theme.font(15)).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, Theme.gutter - PaperCardMetrics.margin)
                if let error = actionError ?? model.error {
                    Text(error).font(Theme.font(15)).foregroundStyle(Theme.destructive)
                        .padding(.horizontal, Theme.gutter - PaperCardMetrics.margin)
                }
                if bound {
                    let rows = model.rows(section)
                    PaperSection(section.title, count: rows.isEmpty ? nil : rows.count) {
                        if rows.isEmpty {
                            Text("No records on this device").font(Theme.font(15)).foregroundStyle(Theme.muted)
                                .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 14)
                        } else {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(rows) { row in
                                    HStack(spacing: 0) {
                                        Button { if let draft = model.draft(section, id: row.id) { present(draft) } } label: {
                                            PaperListRow(title: row.title, subtitle: row.subtitle.isEmpty ? nil : row.subtitle, subtitleLines: 2)
                                        }
                                        .buttonStyle(RowPressStyle())
                                        ThorbisMenu(items: [
                                            ThorbisMenuItem("Edit", icon: "pencil") { if let draft = model.draft(section, id: row.id) { present(draft) } },
                                            ThorbisMenuItem("Remove", icon: "trash", role: .destructive) {
                                                do { try model.remove(row.id, section: section); actionError = nil }
                                                catch { actionError = error.localizedDescription }
                                            },
                                        ], accessibilityLabel: "Options for \(row.title)") {
                                            Image(systemName: "ellipsis").foregroundStyle(Theme.muted)
                                                .frame(width: 44, height: 44).contentShape(Rectangle())
                                        }
                                        .padding(.trailing, 4)
                                    }
                                }
                            }
                            .padding(.vertical, PaperCardMetrics.edge)
                        }
                    }
                    .id(model.revision)
                } else if model.error == nil {
                    SkeletonRows(count: 3, leading: false, inset: 0)
                }
                Text("These notes stay in this account’s local workspace book. They are not shared with the office or used by dispatch.")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, Theme.gutter - PaperCardMetrics.margin)
            }
            .paperCardMargin().padding(.top, 8).padding(.bottom, 24)
        }
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            PaperActionBar(title: "Add to \(section.title.lowercased())", symbol: "plus", disabled: !bound) {
                present(LocalWorkspaceDraft())
            }
        }
        .task(id: identityKey) {
            editor = nil
            editorOwner = nil
            actionError = nil
            model.bind(actorID: actorID, organizationID: organizationID)
        }
        .sheet(item: $editor) { draft in SheetSurface {
            if editorOwner == identityKey && model.actorID == actorID && model.organizationID == organizationID {
                LocalWorkspaceEditor(section: section, draft: draft) { saved in
                    guard editorOwner == identityKey && model.actorID == actorID && model.organizationID == organizationID else {
                        throw Problem(title: "Session changed", status: nil, detail: nil)
                    }
                    try model.save(saved, section: section)
                    actionError = nil
                }
            } else {
                Text("Session changed").foregroundStyle(.secondary)
            }
        } }
    }
}

private struct LocalWorkspaceEditor: View {
    let section: LocalWorkspaceSection
    @State var draft: LocalWorkspaceDraft
    let onSave: (LocalWorkspaceDraft) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    /// Required fields left empty when Save was pressed, said under each; one clears as it is typed in.
    @State private var missing: Set<String> = []
    @FocusState private var focus: String?

    var body: some View {
        NavigationStack {
            // design 2026-10-30: one column, labels above, field wells; Save is the ink commit.
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("On this device · Not synced").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                    if section == .agreements {
                        PaperFormField("Kind") {
                            ThorbisSelect(options: [(LocalAgreementRecord.Kind.maintenance, "Maintenance"),
                                                    (LocalAgreementRecord.Kind.membership, "Membership")],
                                          selection: $draft.kind, label: "Kind").fieldWell()
                        }
                    }
                    ForEach(section.fields.indices, id: \.self) { index in
                        let field = section.fields[index]
                        PaperFormField(field.label, note: field.required ? nil : "Optional",
                                       error: missing.contains(field.key) ? "Add the \(field.label.lowercased()) to save." : nil) {
                            TextField(field.label, text: Binding(
                                get: { draft.value(field.key) },
                                set: { draft.values[field.key] = $0; missing.remove(field.key) }
                            ), prompt: .placeholder(field.label), axis: field.key == "notes" ? .vertical : .horizontal)
                            .font(Theme.font(16)).fieldWell()
                            .focused($focus, equals: field.key)
                        }
                    }
                    if section == .fleet {
                        Text("Values and maintenance dates are written as entered. Market value is your estimate; no live valuation is connected.")
                            .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    }
                    if let error { Text(error).font(Theme.font(15)).foregroundStyle(Theme.destructive) }
                }
                .padding(.horizontal, Theme.gutter).padding(.top, 8).padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                // Never pre-disabled: pressed with a required field empty, it says which under it.
                PaperActionBar(title: "Save") {
                    let empty = section.fields.filter { $0.required && draft.required($0.key).isEmpty }
                    guard empty.isEmpty else {
                        missing = Set(empty.map(\.key))
                        focus = empty.first?.key
                        return
                    }
                    do { try onSave(draft); dismiss() }
                    catch { self.error = error.localizedDescription }
                }
            }
            .navigationTitle(draft.values.isEmpty ? "New \(section.title)" : "Edit \(section.title)")
            .toolbar {
                ThorbisToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

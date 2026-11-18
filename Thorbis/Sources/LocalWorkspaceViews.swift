import SwiftUI

enum LocalWorkspaceSection: String, CaseIterable, Hashable {
    case fleet, equipment, agreements, team

    var title: String {
        switch self {
        case .fleet: "Fleet"
        case .equipment: "Equipment"
        case .agreements: "Maintenance plans"
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
                ("plate", "License plate", false), ("year", "Year", false), ("vin", "VIN", false),
                ("assignedTo", "Assigned tech", false),
                ("mileage", "Mileage", false), ("purchasePrice", "Purchase price", false),
                ("marketValue", "Market value (your estimate)", false),
                ("purchaseDate", "Purchase date", false),
                ("registrationDue", "Registration due", false),
                ("lastOilChange", "Last oil change", false),
                // Paper 88B: "Next service" ("Oil change at 45,000 mi"), written as entered.
                ("nextOilChange", "Next service", false),
                ("lastTireRotation", "Last tire rotation", false),
                ("lastNewTires", "Last new tires", false),
                ("lastRepair", "Last repair", false), ("notes", "Notes", false),
            ]
        case .equipment:
            [("name", "Name", true), ("site", "Property", true),
             ("brand", "Brand", false), ("serial", "Serial number", false),
             ("installedYear", "Install year", false), ("notes", "Notes", false)]
        case .agreements:
            [("name", "Plan name", true), ("customer", "Customer", true),
             ("cadence", "Visit cadence", true), ("renewsOn", "Renews on", false),
             ("notes", "Notes", false)]
        case .team:
            [("name", "Name", true), ("role", "Role", true), ("phone", "Phone", false)]
        }
    }

    /// Paper 88B / 86C: the editor's cards. Stacked cards put the label over a 17 Medium answer;
    /// inline cards put the label on the left and the answer, muted, on the right.
    var editorCards: [(keys: [String], inline: Bool)] {
        switch self {
        case .fleet:
            [(["name", "model", "plate", "vin"], false),
             (["assignedTo", "mileage", "nextOilChange", "registrationDue"], true),
             (["year", "purchaseDate", "purchasePrice", "marketValue"], true),
             (["lastOilChange", "lastTireRotation", "lastNewTires", "lastRepair"], true),
             (["notes"], false)]
        case .equipment:
            [(["name", "brand", "serial"], false), (["installedYear", "site"], true), (["notes"], false)]
        case .agreements:
            [(["name", "customer"], false), (["cadence", "renewsOn"], true), (["notes"], false)]
        case .team:
            [(["name", "role", "phone"], false)]
        }
    }

    /// The example shown in an empty answer.
    func prompt(_ key: String) -> String {
        switch key {
        case "purchaseDate", "registrationDue", "lastOilChange", "lastTireRotation",
             "lastNewTires", "renewsOn": "YYYY-MM-DD"
        case "nextOilChange": "Oil change at 45,000 mi"
        case "notes": "Anything the next person should know"
        default: fields.first { $0.key == key }?.label ?? ""
        }
    }

    /// The header + and the editor's title for a new record.
    var addTitle: String {
        switch self {
        case .fleet: "Add vehicle"
        case .equipment: "Add equipment"
        case .agreements: "Add maintenance plan"
        case .team: "Add team member"
        }
    }

    var editTitle: String {
        switch self {
        case .fleet: "Edit vehicle"
        case .equipment: "Edit equipment"
        case .agreements: "Edit maintenance plan"
        case .team: "Edit team member"
        }
    }

    /// The subtitle's noun for a count ("6 vehicles").
    func countLabel(_ count: Int) -> String {
        switch self {
        case .fleet: count == 1 ? "1 truck" : "\(count) trucks"
        case .equipment: count == 1 ? "1 unit" : "\(count) units"
        case .agreements: count == 1 ? "1 plan" : "\(count) plans"
        case .team: count == 1 ? "1 person" : "\(count) people"
        }
    }
}

struct LocalWorkspaceRow: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    /// A quiet trailing word (Paper 88: "Unassigned" on a truck with no driver).
    var status: String? = nil
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
        // Paper 88: "Van 3 · Ford Transit" over "Ramon Mendez · plate 8XYZ412".
        case .fleet: return storage.vehicles.map { vehicle in
            let plate: String? = vehicle.plate.map { "plate \($0)" }
            // Paper 88: a truck nobody drives reads "No driver" with "Unassigned" trailing.
            let driver = (vehicle.assignedTo ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return LocalWorkspaceRow(id: vehicle.id, title: [vehicle.name, vehicle.model ?? ""].filter { !$0.isEmpty }.joined(separator: " · "),
                                     subtitle: [driver.isEmpty ? "No driver" : driver, plate ?? ""].filter { !$0.isEmpty }.joined(separator: " · "),
                                     status: driver.isEmpty ? "Unassigned" : nil)
        }
        // Paper 86: the unit over where it is and when it went in.
        case .equipment: return storage.equipment.map { unit in
            let installed: String? = unit.installedYear.map { "installed \($0)" }
            return LocalWorkspaceRow(id: unit.id, title: unit.name,
                                     subtitle: [unit.brand ?? "", unit.site, installed ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
        }
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
    /// Equipment: whether the company's server book has units, so the phone's own notes read as a second list.
    @State private var hasServerEquipment = false
    @State private var hasServerAgreements = false
    /// The shared books' sizes, for the subtitle ("6 units", "236 members").
    @State private var serverEquipmentCount = 0
    @State private var serverAgreementCount = 0
    /// Paper 88A: the truck whose page is pushed.
    @State private var openedVehicle: LocalWorkspaceRow?
    /// Equipment and Agreements: the company's server book is showing, so this phone's notes are second.
    private var sharedEquipment: Bool {
        (section == .equipment && hasServerEquipment) || (section == .agreements && hasServerAgreements)
    }

    private var identityKey: String { "\(actorID.lowercased())|\(organizationID.lowercased())" }

    private func present(_ draft: LocalWorkspaceDraft) {
        editorOwner = identityKey
        editor = draft
    }

    /// "6 vehicles · On this phone": the count, then where these live.
    private func subtitle(rows: [LocalWorkspaceRow], bound: Bool) -> String {
        if sharedEquipment {
            // Paper 86 / 85C: the count leads ("6 units", "236 members").
            if section == .equipment && serverEquipmentCount > 0 {
                return serverEquipmentCount == 1 ? "1 unit" : "\(serverEquipmentCount) units"
            }
            if section == .agreements && serverAgreementCount > 0 {
                return serverAgreementCount == 1 ? "1 member" : "\(serverAgreementCount) members"
            }
            return "Shared with your team"
        }
        guard bound else { return "On this phone" }
        return section.countLabel(rows.count)
    }

    /// One record (Paper 88's row): the name over one muted line, its status word trailing. A
    /// truck opens its own page (88A), which edits and removes it; the other books keep their •••.
    private func rowView(_ row: LocalWorkspaceRow) -> some View {
        HStack(spacing: 0) {
            Button {
                if section == .fleet {
                    openedVehicle = row
                } else if let draft = model.draft(section, id: row.id) {
                    present(draft)
                }
            } label: {
                PaperRecordRow(title: row.title, subtitle: row.subtitle.isEmpty ? nil : row.subtitle, status: row.status)
            }
            .buttonStyle(RowPressStyle())
            if section != .fleet {
                ThorbisMenu(items: [
                    ThorbisMenuItem("Edit", icon: "pencil") { if let draft = model.draft(section, id: row.id) { present(draft) } },
                    ThorbisMenuItem("Remove", icon: "trash", role: .destructive) {
                        do { try model.remove(row.id, section: section); actionError = nil }
                        catch { actionError = error.localizedDescription }
                    },
                ], accessibilityLabel: "Options for \(row.title)") {
                    PaperIcon(.more, size: 16, color: Theme.muted)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .padding(.trailing, 4)
            }
        }
    }

    var body: some View {
        // design 2026-10-30: the list system — header, rows on one panel, edits in each row's •••
        // (swipe-to-delete moved there), the one ink commit at the bottom.
        let bound = model.actorID == actorID && model.organizationID == organizationID
        let rows = bound ? model.rows(section) : []
        // Paper 85C / 86 / 88: the place header (menu circle, brand +, 34 Bold title, muted count),
        // then grouped cards 16 from the edges with 20 between sections.
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PaperHeader(title: section.title, subtitle: subtitle(rows: rows, bound: bound),
                            showsCreate: !sharedEquipment && bound)
                    .environment(\.paperCreate, !sharedEquipment && bound
                                 ? PaperCreateAction(label: section.addTitle, run: { present(LocalWorkspaceDraft()) })
                                 : nil)
                VStack(alignment: .leading, spacing: 0) {
                    if let error = actionError ?? model.error {
                        Text(error).font(Theme.font(15)).foregroundStyle(Theme.destructive)
                            .padding(.horizontal, Theme.gutter).padding(.bottom, 12)
                    }
                    if section == .equipment {
                        CompanyEquipmentBook(onLoaded: { hasServerEquipment = $0 }, onCount: { serverEquipmentCount = $0 })
                    }
                    if section == .agreements {
                        CompanyAgreementsBook(onLoaded: { hasServerAgreements = $0 }, onCount: { serverAgreementCount = $0 })
                    }
                    if bound {
                        // Empty: the shared empty state, not a label repeating the title over a one-line card.
                        if rows.isEmpty && sharedEquipment {
                            EmptyView()
                        } else if rows.isEmpty {
                            ListRoomEmpty(title: "Nothing here yet",
                                          message: "\(section.addTitle) with the + above.")
                        } else {
                            // Paper 88: a 13 Semibold label and its count over one card of rows.
                            PaperCardLabel(title: sharedEquipment ? "Notes on this phone" : (section == .fleet ? "Trucks" : "On this phone"),
                                           count: rows.count)
                                .padding(.top, sharedEquipment ? 20 : 6)
                            PaperRowsCard {
                                ForEach(rows) { row in
                                    if row.id != rows.first?.id { WellDivider(leading: 16) }
                                    rowView(row)
                                }
                            }
                            .id(model.revision)
                        }
                    } else if model.error == nil {
                        SkeletonRows(count: 3, leading: false, inset: 0).paperCardMargin()
                    }
                    // With the shared book showing, units are added where they belong: on the customer.
                    Text(sharedEquipment ? (section == .equipment ? "Add or edit a unit on its customer\u{2019}s page; it shows here for the whole team."
                                                                  : "Add or cancel a plan on its customer\u{2019}s page; it shows here for the whole team.")
                                         : "These notes stay in this account’s local workspace book. They are not shared with the office or used by dispatch.")
                        .font(Theme.font(13)).foregroundStyle(Theme.subtleForeground)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 24).padding(.top, 12)
                }
                .padding(.bottom, 24)
            }
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: identityKey) {
            editor = nil
            editorOwner = nil
            openedVehicle = nil
            actionError = nil
            model.bind(actorID: actorID, organizationID: organizationID)
            #if DEBUG
            // `--paper-preview-screen vehicle-detail`: open the first truck.
            if PaperPreview.enabled, PaperPreview.screen == "vehicle-detail", section == .fleet {
                // The preview account's book starts empty on a fresh simulator: Paper 88A's van.
                if model.rows(.fleet).isEmpty {
                    var van = LocalWorkspaceDraft()
                    van.values = ["name": "Van 3", "model": "Ford Transit 250", "plate": "8XYZ412", "assignedTo": "Ramon Mendez",
                                  "mileage": "84210", "nextOilChange": "2026-12-05", "registrationDue": "2027-06-30",
                                  "notes": "Rear brakes squeal when cold. Pads look fine, check again at next service."]
                    try? model.save(van, section: .fleet)
                }
                openedVehicle = model.rows(.fleet).first
            }
            #endif
        }
        .thorbisDestination(item: $openedVehicle) { row in
            LocalVehicleDetail(id: row.id, model: model) { saved in
                guard model.actorID == actorID && model.organizationID == organizationID else {
                    throw Problem(title: "Session changed", status: nil, detail: nil)
                }
                try model.save(saved, section: .fleet)
                actionError = nil
            }
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


/// One labelled fact on a truck's page.
private struct LocalVehicleFact: Identifiable {
    let label: String
    let value: String
    var due = false
    var id: String { label }
}

/// Paper 88A "Vehicle detail": the truck's name over its make and plate, Details with Edit beside
/// the label, then its service notes. Kept on this phone, and it says so. Truck stock is not tied
/// to a truck in the app, so that card is not drawn.
private struct LocalVehicleDetail: View {
    let id: String
    @ObservedObject var model: LocalWorkspaceViewModel
    let save: (LocalWorkspaceDraft) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var editor: LocalWorkspaceDraft?
    @State private var actionError: String?

    private static let mainKeys: [(key: String, label: String)] = [
        ("assignedTo", "Driver"), ("mileage", "Odometer"),
        ("nextOilChange", "Next service due"), ("registrationDue", "Registration expires"),
    ]
    private static let moreKeys: [(key: String, label: String)] = [
        ("year", "Year"), ("vin", "VIN"), ("purchaseDate", "Purchase date"),
        ("purchasePrice", "Purchase price"), ("marketValue", "Market value (your estimate)"),
        ("lastOilChange", "Last oil change"), ("lastTireRotation", "Last tire rotation"),
        ("lastNewTires", "Last new tires"), ("lastRepair", "Last repair"),
    ]

    private func facts(_ draft: LocalWorkspaceDraft, _ keys: [(key: String, label: String)]) -> [LocalVehicleFact] {
        var rows: [LocalVehicleFact] = []
        for item in keys {
            if let value = draft.optional(item.key) {
                rows.append(LocalVehicleFact(label: item.label, value: Self.shown(item.key, value), due: Self.isDueSoon(item.key, value)))
            }
        }
        return rows
    }

    /// Paper 88A prints what was typed the way people read it: "84,210 mi", "Jun 30, 2027",
    /// "Aug 18 · oil change". Anything typed another way is shown as typed.
    static func shown(_ key: String, _ value: String) -> String {
        switch key {
        case "mileage":
            let digits = value.replacingOccurrences(of: ",", with: "")
            if let miles = Int(digits) { return "\(miles.formatted(.number.grouping(.automatic))) mi" }
            return value
        case "nextOilChange":
            guard let day = EquipmentRecord.day(value) else { return value }
            return "\(day.formatted(.dateTime.month(.abbreviated).day())) \u{00B7} oil change"
        case "registrationDue", "purchaseDate", "lastOilChange", "lastTireRotation", "lastNewTires":
            guard let day = EquipmentRecord.day(value) else { return value }
            return day.formatted(.dateTime.month(.abbreviated).day().year())
        default:
            return value
        }
    }

    /// The next service reads in the warning ink once its day is within a month (or past).
    static func isDueSoon(_ key: String, _ value: String, now: Date = Date()) -> Bool {
        guard key == "nextOilChange", let day = EquipmentRecord.day(value) else { return false }
        return day.timeIntervalSince(now) < 30 * 86_400
    }

    private func subtitle(_ draft: LocalWorkspaceDraft) -> String {
        let plate: String = draft.optional("plate").map { "plate \($0)" } ?? ""
        return [draft.optional("model") ?? "", plate].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
    }

    private func factCard(_ rows: [LocalVehicleFact]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { fact in
                if fact.id != rows.first?.id { WellDivider() }
                // Paper 88A: the answer at 16 Medium; a service coming due in the warning ink.
                PaperDetailRow(label: fact.label) {
                    Text(fact.value).font(Theme.font(16, weight: .medium))
                        .foregroundStyle(fact.due ? Theme.warning : Theme.foreground)
                }
                    .padding(.horizontal, PaperCardMetrics.inset).frame(minHeight: 52)
            }
        }
    }

    private func page(_ draft: LocalWorkspaceDraft) -> some View {
        let line = subtitle(draft)
        let main = facts(draft, Self.mainKeys)
        let more = facts(draft, Self.moreKeys)
        let notes = draft.optional("notes") ?? ""
        return VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text(draft.required("name")).font(Theme.font(34, weight: .bold)).tracking(-0.85)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if !line.isEmpty {
                    Text(line).font(Theme.font(15)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, Theme.gutter - PaperCardMetrics.margin)
            if let actionError {
                Text(actionError).font(Theme.font(15)).foregroundStyle(Theme.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.gutter - PaperCardMetrics.margin)
            }
            PaperSection(title: "Details") {
                if main.isEmpty {
                    Text("No driver, odometer or service dates yet.").font(Theme.font(15)).foregroundStyle(Theme.muted)
                        .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 14)
                } else {
                    factCard(main)
                }
            } accessory: {
                // Paper 88A: "Edit" in the brand ink beside the section label.
                Button { editor = draft } label: {
                    Text("Edit").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.brandText)
                        .frame(minWidth: 44, minHeight: 44, alignment: .trailing).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Edit vehicle")
                .accessibilityIdentifier("vehicle-edit")
            }
            if !more.isEmpty {
                PaperSection("Value and upkeep") { factCard(more) }
            }
            if !notes.isEmpty {
                PaperSection("Service notes") {
                    Text(notes).font(Theme.font(15)).foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 12)
                }
            }
            Text("Saved on this phone only. The office and dispatch don\u{2019}t see it.")
                .font(Theme.font(13)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.gutter - PaperCardMetrics.margin)
        }
    }

    var body: some View {
        let draft = model.draft(.fleet, id: id)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let draft {
                    page(draft)
                } else {
                    Text("This vehicle is no longer on this phone.").font(Theme.font(15)).foregroundStyle(Theme.muted)
                        .padding(.horizontal, Theme.gutter - PaperCardMetrics.margin)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .paperCardMargin().padding(.top, 8).padding(.bottom, 24)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if draft != nil {
                ThorbisToolbarItem(placement: .topBarTrailing) {
                    ThorbisMenu(items: menuItems, accessibilityLabel: "Vehicle actions") {
                        PaperCircleLabel(symbol: "ellipsis", size: 44, fill: Theme.card)
                    }
                }
            }
        }
        .sheet(item: $editor) { editing in SheetSurface {
            LocalWorkspaceEditor(section: .fleet, draft: editing) { saved in
                try save(saved)
                actionError = nil
            }
        } }
    }

    private var menuItems: [ThorbisMenuItem] {
        [ThorbisMenuItem("Edit", icon: "pencil") { editor = model.draft(.fleet, id: id) },
         ThorbisMenuItem("Remove", icon: "trash", role: .destructive) {
             do {
                 try model.remove(id, section: .fleet)
                 dismiss()
             } catch {
                 actionError = error.localizedDescription
             }
         }]
    }
}

/// Paper 88B (Add vehicle) and 86C (Add equipment): Cancel and Save in the title row, then the
/// fields as grouped cards. Saved on this phone only, and it says so under the cards.
private struct LocalWorkspaceEditor: View {
    let section: LocalWorkspaceSection
    @State var draft: LocalWorkspaceDraft
    let onSave: (LocalWorkspaceDraft) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    /// Required fields left empty when Save was pressed, said under each; one clears as it is typed in.
    @State private var missing: Set<String> = []
    @FocusState private var focus: String?
    /// New records open empty; a saved one always has its required name.
    @State private var isNew: Bool

    init(section: LocalWorkspaceSection, draft: LocalWorkspaceDraft,
         onSave: @escaping (LocalWorkspaceDraft) throws -> Void) {
        self.section = section
        _draft = State(initialValue: draft)
        self.onSave = onSave
        _isNew = State(initialValue: draft.required("name").isEmpty)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let error {
                        Text(error).font(Theme.font(15)).foregroundStyle(Theme.destructive)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }
                    if section == .agreements {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Kind").font(Theme.font(13)).foregroundStyle(Theme.muted)
                            ThorbisSegmented(options: [(LocalAgreementRecord.Kind.maintenance, "Maintenance"),
                                                       (LocalAgreementRecord.Kind.membership, "Membership")],
                                             selection: $draft.kind)
                        }
                        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    }
                    ForEach(section.editorCards.indices, id: \.self) { cardIndex in
                        LocalEditorCard(section: section, keys: section.editorCards[cardIndex].keys,
                                        inline: section.editorCards[cardIndex].inline,
                                        draft: $draft, missing: $missing, focus: $focus)
                    }
                    Text(footnote).font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background.ignoresSafeArea())
    }

    private var footnote: String {
        let local = "Saved on this phone only. The office and dispatch don\u{2019}t see it."
        if section == .fleet {
            return "Values and maintenance dates are written as entered. Market value is your estimate; no live valuation is connected. " + local
        }
        return local
    }

    private var header: some View {
        ZStack {
            Text(isNew ? section.addTitle : section.editTitle).font(Theme.font(17, weight: .semibold))
                .lineLimit(1).minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 100)
            HStack {
                Button { dismiss() } label: {
                    Text("Cancel").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                        .padding(.horizontal, 16).frame(minHeight: 44)
                        .background(Theme.card, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                Spacer(minLength: 8)
                // Never pre-disabled: pressed with a required field empty, it says which under it.
                Button { save() } label: {
                    Text("Save").font(Theme.font(16, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18).frame(minHeight: 44)
                        .background(Theme.brand, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 2)
    }

    private func save() {
        var empty: [String] = []
        for field in section.fields where field.required && draft.required(field.key).isEmpty {
            empty.append(field.key)
        }
        guard empty.isEmpty else {
            missing = Set(empty)
            focus = empty.first
            return
        }
        do { try onSave(draft); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

/// One card of the local editor: stacked (13 muted label over a 17 Medium answer) or inline
/// (16 label on the left, the answer muted on the right, 56 tall), an inset hairline between rows.
private struct LocalEditorCard: View {
    let section: LocalWorkspaceSection
    let keys: [String]
    let inline: Bool
    @Binding var draft: LocalWorkspaceDraft
    @Binding var missing: Set<String>
    var focus: FocusState<String?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(keys, id: \.self) { key in
                if key != keys.first { WellDivider(leading: 16) }
                row(key)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private func label(_ key: String) -> String {
        section.fields.first { $0.key == key }?.label ?? key
    }

    private func binding(_ key: String) -> Binding<String> {
        Binding(get: { draft.value(key) },
                set: { draft.values[key] = $0; missing.remove(key) })
    }

    private func problem(_ key: String) -> String? {
        missing.contains(key) ? "Add the \(label(key).lowercased()) to save." : nil
    }

    @ViewBuilder private func row(_ key: String) -> some View {
        if inline {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(label(key)).font(Theme.font(16)).foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityHidden(true)
                    Spacer(minLength: 8)
                    TextField("", text: binding(key), prompt: .placeholder(section.prompt(key)))
                        .font(Theme.font(16)).foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.trailing)
                        .focused(focus, equals: key)
                        .accessibilityLabel(label(key))
                }
                if let message = problem(key) { FieldProblem(message: message) }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(label(key)).font(Theme.font(13)).foregroundStyle(Theme.muted).accessibilityHidden(true)
                TextField("", text: binding(key), prompt: .placeholder(section.prompt(key)),
                          axis: key == "notes" ? .vertical : .horizontal)
                    .font(key == "notes" ? Theme.font(15) : Theme.font(17, weight: .medium))
                    .focused(focus, equals: key)
                    .accessibilityLabel(label(key))
                if let message = problem(key) { FieldProblem(message: message) }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

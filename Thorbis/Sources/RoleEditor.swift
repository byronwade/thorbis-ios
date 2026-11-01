import SwiftUI

// Owner role editing (GET /v1/organization/role-presets, GET/POST /v1/organization/roles,
// POST /v1/organization/roles/{id}/revise). Online only; every save names the revision it edits.

struct RoleBuilderCatalog: Decodable {
    struct Scope: Decodable, Hashable { let id: String; let label: String }
    struct Condition: Decodable, Hashable {
        struct Input: Decodable, Hashable { let kind: String; let min: Int?; let max: Int?; let step: Int? }
        let id: String
        let label: String
        let input: Input
    }
    struct Capability: Decodable, Identifiable, Hashable {
        let id: String
        let label: String
        let description: String
        let resource: String
        let offlineLabel: String?
        let allowedScopes: [Scope]
        let supportedConditions: [Condition]
    }
    let capabilities: [Capability]
}

struct RoleGrant: Codable, Hashable {
    var capability: String
    var scope: String
    var conditions: [String: Int]?
    var effect: String?
}

struct OrganizationRoleDetail: Decodable {
    struct Role: Decodable { let id: String; let currentRevision: Int }
    struct Revision: Decodable { let name: String; let description: String?; let grants: [RoleGrant] }
    let role: Role
    let revision: Revision
}

extension APIClient {
    func roleBuilderCatalog() async throws -> RoleBuilderCatalog {
        try await send("GET", "/v1/organization/role-presets")
    }

    func organizationRole(_ id: String) async throws -> OrganizationRoleDetail {
        guard UUID(uuidString: id) != nil else { throw Problem(title: "Invalid role ID", status: nil, detail: id) }
        return try await send("GET", "/v1/organization/roles/\(id)")
    }

    func createOrganizationRole(name: String, description: String, idempotencyKey: String) async throws -> OrganizationRoleDetail {
        struct Body: Encodable { let idempotencyKey: String; let name: String; let description: String; let grants: [RoleGrant]; let reason: String }
        return try await send("POST", "/v1/organization/roles",
                              body: Body(idempotencyKey: idempotencyKey, name: name, description: description, grants: [],
                                         reason: "Created in the Thorbis iPhone app"))
    }

    /// The role id comes from the route only.
    func reviseOrganizationRole(_ id: String, expectedRevision: Int, name: String, description: String,
                                grants: [RoleGrant]) async throws -> OrganizationRoleDetail {
        struct Body: Encodable { let expectedRevision: Int; let name: String; let description: String; let grants: [RoleGrant]; let reason: String }
        guard UUID(uuidString: id) != nil else { throw Problem(title: "Invalid role ID", status: nil, detail: id) }
        return try await send("POST", "/v1/organization/roles/\(id)/revise",
                              body: Body(expectedRevision: expectedRevision, name: name, description: description, grants: grants,
                                         reason: "Changed in the Thorbis iPhone app"))
    }
}

/// Everything a role can do, in plain words, grouped by what it touches. Each switch turns a
/// permission on; "Whose" picks how far it reaches (their own jobs, their team, everything).
struct RoleEditorView: View {
    let roleID: String
    let onSaved: () async -> Void
    @EnvironmentObject private var api: APIClient
    @Environment(\.dismiss) private var dismiss
    @State private var catalog: RoleBuilderCatalog?
    @State private var detail: OrganizationRoleDetail?
    @State private var name = ""
    @State private var summary = ""
    @State private var grants: [String: RoleGrant] = [:]
    /// Explicit denies aren't edited here; they are kept exactly as they were.
    @State private var denies: [RoleGrant] = []
    @State private var busy = false
    @State private var error: String?
    @State private var search = ""
    /// Said under the name when Save is pressed without one; clears as they type.
    @State private var nameProblem: String?
    @FocusState private var nameFocused: Bool

    private var groups: [(String, [RoleBuilderCatalog.Capability])] {
        let visible = (catalog?.capabilities ?? []).filter {
            search.isEmpty || $0.label.localizedCaseInsensitiveContains(search) || $0.description.localizedCaseInsensitiveContains(search)
        }
        return Dictionary(grouping: visible, by: \.resource)
            .map { ($0.key, $0.value.sorted { $0.label < $1.label }) }
            .sorted { $0.0 < $1.0 }
    }

    var body: some View {
        List {
            Section {
                TextField("Role name", text: $name, prompt: .placeholder("Role name"))
                    .focused($nameFocused)
                    .onChange(of: name) { _, _ in nameProblem = nil }
                if let nameProblem { FieldProblem(message: nameProblem) }
                TextField("What this role is for", text: $summary, prompt: .placeholder("What this role is for"), axis: .vertical).lineLimit(1...3)
            }
            ForEach(groups, id: \.0) { resource, capabilities in
                Section(resource.replacingOccurrences(of: "_", with: " ").capitalized) {
                    ForEach(capabilities) { capability in capabilityRow(capability) }
                }
            }
            if let error { Section { ListErrorRow(message: error) } }
        }
        .searchable(text: $search, prompt: "Find a permission")
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .overlay(alignment: .top) { if catalog == nil && error == nil { SkeletonRows(count: 6, leading: false).background(Theme.canvas) } }
        .navigationTitle(name.isEmpty ? "Role" : name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ThorbisToolbarItem(placement: .topBarTrailing) {
                // Not pre-disabled for a blank name: pressing says what's missing under it. It stays
                // off only while the role is loading or saving.
                Button("Save") {
                    if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        nameProblem = "Name the role, like \u{201C}Lead technician.\u{201D}"
                        nameFocused = true
                    } else {
                        Task { await save() }
                    }
                }
                .disabled(busy || detail == nil)
            }
        }
        .task { await load() }
    }

    @ViewBuilder private func capabilityRow(_ capability: RoleBuilderCatalog.Capability) -> some View {
        let enabled = grants[capability.id] != nil
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(get: { enabled }, set: { on in
                if on { grants[capability.id] = RoleGrant(capability: capability.id, scope: capability.allowedScopes.first?.id ?? "organization") }
                else { grants[capability.id] = nil }
            })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(capability.label).font(Theme.font(15, weight: .medium))
                    Text(capability.description).font(Theme.font(12)).foregroundStyle(Theme.muted)
                }
            }
            if enabled, capability.allowedScopes.count > 1 {
                ThorbisSelect(options: capability.allowedScopes.map { ($0.id, $0.label) },
                              selection: Binding(get: { grants[capability.id]?.scope ?? "" },
                                                 set: { grants[capability.id]?.scope = $0 }),
                              label: "Whose")
            }
            if enabled {
                ForEach(capability.supportedConditions, id: \.id) { condition in
                    let value = grants[capability.id]?.conditions?[condition.id]
                    HStack {
                        Text(condition.label).font(Theme.font(13)).foregroundStyle(Theme.muted)
                        Spacer()
                        TextField(condition.input.kind == "percentage" ? "No limit %" : "No limit $",
                                  text: Binding(get: { value.map { condition.input.kind == "percentage" ? "\($0)" : paymentAmountText($0) } ?? "" },
                                                set: { text in setCondition(capability.id, condition, text) }), prompt: .placeholder(condition.input.kind == "percentage" ? "No limit %" : "No limit $"))
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            .font(Theme.monoFont(15)).frame(maxWidth: 120)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func setCondition(_ capability: String, _ condition: RoleBuilderCatalog.Condition, _ text: String) {
        var grant = grants[capability]
        var conditions = grant?.conditions ?? [:]
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            conditions[condition.id] = nil
        } else if condition.input.kind == "percentage", let number = Int(trimmed) {
            conditions[condition.id] = min(max(number, condition.input.min ?? 0), condition.input.max ?? 100)
        } else if let cents = MoneyInput.cents(trimmed, maximumCents: 100_000_000_000) {
            conditions[condition.id] = cents
        }
        grant?.conditions = conditions.isEmpty ? nil : conditions
        grants[capability] = grant
    }

    private func load() async {
        do {
            async let catalogRequest = api.roleBuilderCatalog()
            async let detailRequest = api.organizationRole(roleID)
            let (loadedCatalog, loadedDetail) = try await (catalogRequest, detailRequest)
            catalog = loadedCatalog
            detail = loadedDetail
            name = loadedDetail.revision.name
            summary = loadedDetail.revision.description ?? ""
            grants = Dictionary(loadedDetail.revision.grants.filter { $0.effect != "deny" }.map { ($0.capability, $0) },
                                uniquingKeysWith: { first, _ in first })
            denies = loadedDetail.revision.grants.filter { $0.effect == "deny" }
            error = nil
        } catch is CancellationError {
        } catch { self.error = error.localizedDescription }
    }

    private func save() async {
        guard let detail else { return }
        busy = true
        defer { busy = false }
        do {
            let ordered = grants.values.sorted { $0.capability < $1.capability } + denies
            _ = try await api.reviseOrganizationRole(roleID, expectedRevision: detail.role.currentRevision,
                                                     name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                                     description: summary.trimmingCharacters(in: .whitespacesAndNewlines), grants: ordered)
            await onSaved()
            dismiss()
        } catch is CancellationError {
        } catch {
            self.error = error.isConnectivityFailure ? "Saving a role needs a connection." : error.localizedDescription
        }
    }
}

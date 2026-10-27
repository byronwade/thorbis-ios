import SwiftUI

/// The API filters this list to members in the caller's assignment reach.
/// It intentionally exposes no role, contact, or policy fields.
struct FieldAssignee: Decodable, Identifiable, Hashable {
    let userId: String
    let displayName: String
    var id: String { userId }
}

private struct FieldAssigneePage: Decodable {
    let items: [FieldAssignee]
    let nextCursor: String?
}

extension APIClient {
    /// Complete keyset scan of the scoped roster. A page may contain
    /// fewer than 200 rows because the API filters by the caller's reach.
    func fieldAssignees() async throws -> [FieldAssignee] {
        let requestGeneration = self.requestGeneration
        var people: [FieldAssignee] = []
        var cursor: String?
        var seen: Set<String> = []
        while true {
            try Task.checkCancellation()
            guard requestGeneration == self.requestGeneration else { throw CancellationError() }
            let page: FieldAssigneePage = try await send(
                "GET", "/v1/organization/assignees",
                queryItems: [URLQueryItem(name: "limit", value: "200")], cursor: cursor
            )
            guard requestGeneration == self.requestGeneration else { throw CancellationError() }
            people.append(contentsOf: page.items)
            guard let next = page.nextCursor else { return people }
            guard !next.isEmpty, seen.insert(next).inserted else {
                throw Problem(title: "Invalid roster page", status: nil,
                              detail: "The assignee list returned a repeated cursor.")
            }
            cursor = next
        }
    }
}

/// Live assignment is kept separate from the device's demonstration dispatch board.
struct JobAssignmentView: View {
    let jobID: String
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var job: JobRecord?
    @State private var assignees: [FieldAssignee] = []
    @State private var loadedGeneration: UUID?
    @State private var selectedUserID: String?
    @State private var loading = false
    @State private var loadID = UUID()
    @State private var saving = false
    @State private var error: String?

    private var isCurrent: Bool {
        loadedGeneration == session.generation && session.can("job.assign", feature: "jobs")
            && job?.organizationId == session.activeOrganization?.id
    }

    var body: some View {
        Form {
            if !session.can("job.assign", feature: "jobs") {
                Text("Assignment is unavailable for this workspace.")
                    .foregroundStyle(.secondary)
            } else {
                if let error { ErrorBanner(message: error) }
                if loading { ProgressView("Loading assignable people…") }
                if isCurrent, let job {
                    Section("Current assignment") {
                        if let current = job.assignedToUserId {
                            Text(assignees.first(where: { $0.userId == current })?.displayName
                                 ?? "Assigned member unavailable in your roster")
                        } else {
                            Text("Unassigned")
                        }
                    }
                    Section("Assign to") {
                        if assignees.isEmpty {
                            Text("No assignable members are available.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(assignees.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }) { person in
                            Button {
                                selectedUserID = person.userId
                            } label: {
                                HStack {
                                    Text(person.displayName)
                                    Spacer()
                                    if selectedUserID == person.userId {
                                        Image(systemName: "checkmark").accessibilityHidden(true)
                                    }
                                }
                            }
                            .accessibilityAddTraits(selectedUserID == person.userId ? .isSelected : [])
                        }
                    }
                    Button("Save assignment") { Task { await save() } }
                        .disabled(saving || selectedUserID == nil || selectedUserID == job.assignedToUserId)
                }
                if saving { ProgressView("Saving assignment…") }
            }
        }
        .navigationTitle("Assign job")
        .task(id: session.generation) { await load() }
        .refreshable { await load() }
    }

    private func load(keepError: Bool = false) async {
        let generation = session.generation
        let operation = UUID()
        loadID = operation
        job = nil
        assignees = []
        selectedUserID = nil
        loadedGeneration = nil
        guard session.can("job.assign", feature: "jobs"),
              let organizationID = session.activeOrganization?.id else { return }
        loading = true
        defer { if loadID == operation { loading = false } }
        do {
            let freshJob = try await api.fieldJob(jobID)
            guard operation == loadID, generation == session.generation,
                  session.can("job.assign", feature: "jobs"),
                  session.activeOrganization?.id == organizationID else { return }
            guard freshJob.organizationId == organizationID else {
                error = "This job is unavailable in the current workspace."
                return
            }
            let roster = try await api.fieldAssignees()
            guard operation == loadID, generation == session.generation,
                  session.can("job.assign", feature: "jobs"),
                  session.activeOrganization?.id == organizationID else { return }
            job = freshJob
            assignees = roster
            selectedUserID = freshJob.assignedToUserId
            loadedGeneration = generation
            if !keepError { error = nil }
        } catch is CancellationError {
        } catch {
            guard operation == loadID, generation == session.generation else { return }
            self.error = error.localizedDescription
        }
    }

    private func save() async {
        guard isCurrent, let job, let selectedUserID,
              assignees.contains(where: { $0.userId == selectedUserID }),
              !saving else { return }
        let generation = session.generation
        let organizationID = job.organizationId
        saving = true
        defer { saving = false }
        do {
            let expected: FieldExpectedAssignee = job.assignedToUserId.map(FieldExpectedAssignee.user) ?? .unassigned
            _ = try await api.assignFieldJob(jobID,
                                             request: .init(userId: selectedUserID, expected: expected))
            guard generation == session.generation,
                  session.can("job.assign", feature: "jobs"),
                  session.activeOrganization?.id == organizationID else { return }
            await store.refresh(api)
            guard generation == session.generation else { return }
            dismiss()
        } catch is CancellationError {
        } catch let problem as Problem where problem.status == 409 {
            guard generation == session.generation else { return }
            error = "This job's assignment changed. Review the latest assignment before saving."
            await load(keepError: true)
        } catch {
            guard generation == session.generation else { return }
            self.error = error.localizedDescription
        }
    }
}

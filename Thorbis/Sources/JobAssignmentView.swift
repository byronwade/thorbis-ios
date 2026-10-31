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

    /// What is missing when they press Save (v2: the commit is never pre-disabled).
    @State private var missing: String?

    /// A modal (design.thorbis.com Places: "Assign a tech" is one task): who has it now, then the
    /// roster on the panel; one tap picks a tech, the ink commit saves it.
    var body: some View {
        ThorbisModalSheet(title: "Assign tech", closeLabel: "Close", onClose: { dismiss() },
                          detents: [.medium, .large],
                          commitTitle: isCurrent && job != nil ? "Save assignment" : nil,
                          busy: saving, commitIdentifier: "assign-save",
                          commit: { attemptSave() }) {
            if !session.can("job.assign", feature: "jobs") {
                PaperEmptyState(symbol: "person.crop.circle.badge.xmark", title: "Assignment unavailable", message: "Your role can't assign jobs in this workspace.")
            } else {
                if let error { ErrorBanner(message: error).padding(.horizontal, -Theme.gutter) }
                if loading { SkeletonRows(count: 4, inset: 0) }
                if isCurrent, let job {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Assigned now").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                        Text(job.assignedToUserId.map { current in
                            assignees.first(where: { $0.userId == current })?.displayName ?? "Someone outside your roster"
                        } ?? "Unassigned").font(Theme.font(16)).foregroundStyle(Theme.foreground)
                    }
                    .accessibilityElement(children: .combine)
                    VStack(alignment: .leading, spacing: 6) {
                        SectionHeader(title: "Assign to", count: assignees.count, horizontalPadding: 0)
                        if assignees.isEmpty {
                            Text("No one can be assigned right now. Ask your office to add a tech.").font(Theme.font(15)).foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            let sorted = assignees.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
                            VStack(spacing: 0) {
                                ForEach(sorted) { person in
                                    let chosen = selectedUserID == person.userId
                                    Button { selectedUserID = person.userId; missing = nil } label: {
                                        HStack(spacing: 12) {
                                            InitialsAvatar(name: person.displayName, size: 28)
                                                .accessibilityHidden(true)
                                            Text(person.displayName).font(Theme.font(16)).foregroundStyle(Theme.foreground)
                                            Spacer(minLength: 8)
                                            if chosen {
                                                Image(systemName: "checkmark").font(.system(size: 14, weight: .medium))
                                                    .foregroundStyle(Theme.brandText).accessibilityHidden(true)
                                            }
                                        }
                                        .padding(.horizontal, 10)
                                        .frame(minHeight: 48).contentShape(Rectangle())
                                    }
                                    .buttonStyle(RowPressStyle())
                                    .accessibilityAddTraits(chosen ? .isSelected : [])
                                }
                            }
                            .padding(.horizontal, -10)
                        }
                        if let missing { FieldProblem(message: missing) }
                    }
                }
            }
        }
        .task(id: session.generation) { await load() }
        .refreshable { await load() }
    }

    /// Press first, then say what is missing under the list.
    private func attemptSave() {
        guard let job else { return }
        guard let selectedUserID else {
            missing = "Pick a tech to assign this job."
            return
        }
        if selectedUserID == job.assignedToUserId {
            let name = assignees.first(where: { $0.userId == selectedUserID })?.displayName ?? "This tech"
            missing = "\(name) already has this job. Pick someone else."
            return
        }
        missing = nil
        Task { await save() }
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

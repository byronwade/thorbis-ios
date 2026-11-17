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

/// Paper 53A's radio: a 22pt ring that fills brand when chosen.
private struct AssigneeRadio: View {
    let selected: Bool

    var body: some View {
        ZStack {
            Circle().strokeBorder(selected ? Theme.brand : Theme.foreground.opacity(0.4), lineWidth: selected ? 2 : 1.5)
                .frame(width: 22, height: 22)
            if selected { Circle().fill(Theme.brand).frame(width: 11, height: 11) }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
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
    /// The job's street, for the line under the title; nil until read (or with no address on file).
    @State private var street: String?

    private var isCurrent: Bool {
        loadedGeneration == session.generation && session.can("job.assign", feature: "jobs")
            && job?.organizationId == session.activeOrganization?.id
    }

    /// What is missing when they press Save (v2: the commit is never pre-disabled).
    @State private var missing: String?

    /// A modal (design.thorbis.com Places: "Assign a tech" is one task): who has it now, then the
    /// roster on the panel; one tap picks a tech, the ink commit saves it.
    var body: some View {
        // Paper 53A: the job under the title, the roster on one card, the commit, then Cancel as a pill.
        ThorbisModalSheet(title: "Assign a technician", subtitle: isCurrent ? jobLine : nil,
                          closeLabel: "Cancel", onClose: { dismiss() },
                          detents: [.medium, .large],
                          commitTitle: isCurrent && job != nil ? commitTitle : nil,
                          busy: saving, commitIdentifier: "assign-save",
                          commit: { attemptSave() }) {
            if !session.can("job.assign", feature: "jobs") {
                PaperEmptyState(symbol: "person.crop.circle.badge.xmark", title: "Assignment unavailable", message: "Your role can't assign jobs in this workspace.")
            } else {
                if let error { ErrorBanner(message: error).padding(.horizontal, -Theme.gutter) }
                if loading { SkeletonRows(count: 4, inset: 0) }
                if isCurrent, let job {
                    // Who has it now is said on that tech's row. Only a tech outside this roster, who
                    // has no row, is named here.
                    if let current = job.assignedToUserId, !assignees.contains(where: { $0.userId == current }) {
                        Text("Assigned now: someone outside your roster").font(Theme.font(15)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        if assignees.isEmpty {
                            Text("No one can be assigned right now. Ask your office to add a tech.").font(Theme.font(15)).foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            // Paper 53A: the suggested tech leads the roster with a brand chip. The
                            // pick is the least-booked tech on the visit's day, as New job offers it.
                            let load = dayLoad(job)
                            let suggestion = Self.suggestion(for: job, among: assignees, load: load)
                            let sorted = assignees.sorted { lhs, rhs in
                                if lhs == suggestion { return true }
                                if rhs == suggestion { return false }
                                return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
                            }
                            VStack(spacing: 0) {
                                ForEach(sorted) { person in
                                    let chosen = selectedUserID == person.userId
                                    let detail = rowDetail(person, job: job, load: load)
                                    if person.userId != sorted.first?.userId { WellDivider(leading: PaperCardMetrics.inset + 36) }
                                    Button { selectedUserID = person.userId; missing = nil } label: {
                                        HStack(spacing: 12) {
                                            AssigneeRadio(selected: chosen)
                                            VStack(alignment: .leading, spacing: 0) {
                                                Text(person.displayName).font(Theme.font(16, weight: .medium)).tracking(-0.16)
                                                    .foregroundStyle(Theme.foreground)
                                                if let detail {
                                                    Text(detail).font(Theme.font(14)).monospacedDigit().foregroundStyle(Theme.muted)
                                                }
                                            }
                                            Spacer(minLength: 8)
                                            if person == suggestion {
                                                Text("Suggested").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.brandText)
                                                    .padding(.horizontal, 10).frame(height: 26)
                                                    .background(Theme.brandSurface, in: Capsule())
                                            }
                                        }
                                        .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 11)
                                        .frame(minHeight: 56)
                                        // Paper 53A: the chosen row sits on brand at 12%.
                                        .background(chosen ? Theme.brand.opacity(0.12) : Color.clear)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(RowPressStyle())
                                    .accessibilityLabel([person.displayName, detail,
                                                         person == suggestion ? "Suggested, fewest jobs that day" : nil]
                                        .compactMap { $0 }.joined(separator: ", "))
                                    .accessibilityAddTraits(chosen ? .isSelected : [])
                                }
                            }
                            .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                        }
                        if let missing { FieldProblem(message: missing) }
                    }
                }
            }
        }
        .task(id: session.generation) { await load() }
        .refreshable { await load() }
    }

    /// Paper 53A: "Drain backup · 214 Maple St · Today, 1:00 p.m." under the title; the street once
    /// it is read, the time once the job has one.
    private var jobLine: String? {
        guard let job else { return nil }
        return [job.title, street, JobFiltering.date(job.scheduledFor).map { $0.visitLabel() }]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// Jobs booked per tech on this visit's day, not counting this job; empty until it has a day.
    private func dayLoad(_ job: JobRecord) -> [String: Int] {
        guard let day = JobFiltering.date(job.scheduledFor) else { return [:] }
        return BookJobSearch.load(store.jobs.filter { $0.id != job.id }, on: day)
    }

    /// The least-booked tech that day; nil until the job has a day.
    private static func suggestion(for job: JobRecord, among people: [FieldAssignee], load: [String: Int]) -> FieldAssignee? {
        guard JobFiltering.date(job.scheduledFor) != nil else { return nil }
        return BookJobSearch.suggested(people, load: load)
    }

    /// "Has this job now · 3 jobs that day": who holds it, and how full their day is.
    private func rowDetail(_ person: FieldAssignee, job: JobRecord, load: [String: Int]) -> String? {
        var parts: [String] = []
        if person.userId == job.assignedToUserId { parts.append("Has this job now") }
        if JobFiltering.date(job.scheduledFor) != nil {
            let count = load[person.userId] ?? 0
            parts.append("\(count) other job\(count == 1 ? "" : "s") that day")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Paper 53A: "Assign Dana Reyes" once someone is picked.
    private var commitTitle: String {
        guard let selectedUserID, let person = assignees.first(where: { $0.userId == selectedUserID }) else { return "Save assignment" }
        return "Assign \(person.displayName)"
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
        street = nil
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
            // Paper 53A: an unassigned job opens on the suggested tech; a reassignment on who has it.
            selectedUserID = freshJob.assignedToUserId
                ?? Self.suggestion(for: freshJob, among: roster, load: dayLoad(freshJob))?.userId
            loadedGeneration = generation
            if !keepError { error = nil }
            // The street for the line under the title; the sheet is already usable without it.
            if session.can("customer.view", feature: "core_crm"),
               let places = try? await api.fieldLocations(freshJob.customerId) {
                guard operation == loadID, generation == session.generation else { return }
                let mine = places.filter { $0.customerId == freshJob.customerId && $0.organizationId == organizationID }
                let place = mine.first(where: { $0.id == freshJob.locationId }) ?? (mine.count == 1 ? mine.first : nil)
                street = place.flatMap {
                    NextStopPlace(jobID: freshJob.id, organizationID: organizationID, customerID: freshJob.customerId,
                                  address: $0.address).firstLine
                }
            }
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

import SwiftUI

/// The head of a Team detail page (Paper 61D, 62D): the title in 28 Bold, then one muted line 6 below.
struct TeamDetailTitle<Line: View>: View {
    let title: String
    @ViewBuilder var line: Line

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Theme.heading()).tracking(-0.56)
                .foregroundStyle(Theme.foreground)
                .lineLimit(2).minimumScaleFactor(0.5)
                .accessibilityAddTraits(.isHeader)
            line
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.gutter).padding(.top, PaperHeaderMetrics.titleTopUnderBar)
    }
}

extension TeamDetailTitle where Line == Text {
    init(title: String, subtitle: String) {
        self.init(title: title) { Text(subtitle).font(Theme.font(15)).foregroundStyle(Theme.muted) }
    }
}

/// A card of rows with no outer margin, for a column that already sits 16 from the screen's edges.
struct TeamCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: shape)
            .clipShape(shape)
    }
}

/// The quiet sentence under a Team card: 13 in the subtle tone, 4 in from the card's edge.
struct TeamFootnote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(Theme.font(13)).foregroundStyle(Theme.subtleForeground)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, PaperCardMetrics.margin + 4).padding(.top, 12)
    }
}

/// Paper 61D "Roles": every role on one card, with what it is for, how many people have it and a
/// chevron into its permissions (Paper 63). Built-in roles people hold (Owner, a server role with
/// no editor) are listed with their count and no chevron: there is nothing to open.
struct TeamRolesView: View {
    let members: [RoleMember]
    let roles: [OrganizationRole]
    let onSaved: () async -> Void
    @State private var editing: OrganizationRole?

    private struct Row: Identifiable {
        let id: String
        let name: String
        let detail: String?
        let count: Int
        let role: OrganizationRole?
    }

    private var rows: [Row] {
        let rank = ["Owner": 0, "Office": 1, "Dispatcher": 2, "Admin": 3, "CSR": 4, "Technician": 5, "Apprentice": 6, "Accountant": 7]
        let custom = roles.map { role in
            Row(id: role.id, name: role.revision.name,
                detail: role.revision.description.flatMap { $0.isEmpty ? nil : $0 } ?? Self.detail(for: role.revision.name),
                count: members.filter { $0.authority.role?.roleId == role.role.id }.count, role: role)
        }
        let customIDs = Set(roles.map(\.role.id))
        let builtIn = Dictionary(grouping: members.filter { member in
            member.authority.role?.roleId.map { !customIDs.contains($0) } ?? true
        }, by: \.roleLabel)
            .filter { name, _ in !custom.contains { $0.name == name } }
            .map { name, people in Row(id: "built-in-" + name, name: name, detail: Self.detail(for: name), count: people.count, role: nil) }
        return (custom + builtIn).sorted { (rank[$0.name] ?? 9, $0.name) < (rank[$1.name] ?? 9, $1.name) }
    }

    /// Paper 61D's line for a role the picker also names; nil for a name it doesn't know.
    private static func detail(for name: String) -> String? {
        ["Owner": "Everything, including payouts", "Office": "Customers, money, schedule",
         "Dispatcher": "Schedule, calls and assigning techs", "Technician": "Own jobs, estimates, payments",
         "Apprentice": "Jobs they ride on, no prices", "Accountant": "Money and reports, read only"][name]
            ?? RolePickerSheet.roles.first { $0.name == name }?.detail
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TeamDetailTitle(title: "Roles", subtitle: "What each kind of teammate can see and do")
                if !rows.isEmpty {
                    PaperRowsCard {
                        ForEach(rows) { row in
                            if row.id != rows.first?.id { WellDivider(leading: 0) }
                            if let role = row.role {
                                Button { editing = role } label: { label(row) }
                                    .buttonStyle(RowPressStyle())
                                    .accessibilityElement(children: .combine)
                                    .accessibilityHint("Opens what this role can do")
                            } else {
                                label(row).accessibilityElement(children: .combine)
                            }
                        }
                    }
                    .padding(.top, 16)
                }
                TeamFootnote("Tap a role to choose exactly what it can see and change. The number is how many people have it.")
            }
            .padding(.bottom, 32)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .thorbisDestination(item: $editing) { role in
            RoleEditorView(roleID: role.id, memberCount: members.filter { $0.authority.role?.roleId == role.role.id }.count) { await onSaved() }
        }
    }

    private func label(_ row: Row) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(row.name).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                if let detail = row.detail {
                    Text(detail).font(Theme.font(14)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(row.count)").font(Theme.font(15)).foregroundStyle(Theme.muted)
                .frame(minWidth: 28, alignment: .trailing)
                .accessibilityLabel("\(row.count) \(row.count == 1 ? "person" : "people")")
            PaperIcon(.chevronRight, size: 16, color: Theme.muted)
                .opacity(row.role == nil ? 0 : 1).accessibilityHidden(true)
        }
        .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// Paper 62E "Offboard": Cancel and the title, the person on the warning surface, their booked
/// jobs that will need someone else, what happens to their access, and the one blue commit.
/// Removal is immediate on the server (no last day to schedule, no truck or card records), so
/// Paper's "Last day", "Change", the per-job reassignment names and the return rows are left out.
struct MemberOffboardSheet: View {
    let member: RoleMember
    let onRemoved: () async -> Void
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var removing: RoleMember?
    @State private var error: String?

    private var futureJobs: [(job: Job, day: Date)] {
        store.jobs.compactMap { job -> (Job, Date)? in
            guard job.assignedToUserId == member.member.userId, !["completed", "cancelled", "closed"].contains(job.status),
                  let day = JobFiltering.date(job.scheduledFor), day >= Calendar.current.startOfDay(for: .now) else { return nil }
            return (job, day)
        }
        .sorted { $0.1 < $1.1 }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Offboard").font(Theme.font(17, weight: .semibold)).foregroundStyle(Theme.foreground)
                    .accessibilityAddTraits(.isHeader)
                HStack {
                    Button { dismiss() } label: {
                        Text("Cancel").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                            .padding(.horizontal, 16).frame(minHeight: 44)
                            .background(Theme.card, in: Capsule())
                    }
                    .buttonStyle(PressStyle())
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 12) {
                        Text(initials(member.member.displayName))
                            .font(Theme.font(14, weight: .semibold)).foregroundStyle(Theme.subtle)
                            .frame(width: 40, height: 40).background(Theme.fill, in: Circle())
                            .dynamicTypeSize(...DynamicTypeSize.large)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(member.member.displayName) · \(member.roleLabel)")
                                .font(Theme.font(16, weight: .semibold)).foregroundStyle(Theme.foreground)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Loses access right away").font(Theme.font(14)).foregroundStyle(Theme.warning)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(Theme.warningSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .accessibilityElement(children: .combine)

                    if !futureJobs.isEmpty {
                        Text("Reassign \(futureJobs.count) future \(futureJobs.count == 1 ? "job" : "jobs")")
                            .font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.horizontal, 4).padding(.top, 4)
                        TeamCard {
                            ForEach(futureJobs, id: \.job.id) { item in
                                if item.job.id != futureJobs.first?.job.id { WellDivider(leading: 0) }
                                VStack(alignment: .leading, spacing: 0) {
                                    Text("\(item.day.formatted(.dateTime.month(.abbreviated).day())) · \(item.job.title)")
                                        .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(store.customerName(item.job.customerId)).font(Theme.font(13)).foregroundStyle(Theme.muted)
                                }
                                .padding(.horizontal, 14).padding(.vertical, 6)
                                .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                    TeamCard {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Access turns off now").font(Theme.font(15)).foregroundStyle(Theme.foreground)
                            Text("Their account and job history are kept").font(Theme.font(13)).foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                        .accessibilityElement(children: .combine)
                        WellDivider(leading: 0)
                        Text("You can invite them again").font(Theme.font(15)).foregroundStyle(Theme.foreground)
                            .padding(.horizontal, 14)
                            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    }
                    if let error { ErrorBanner(message: error).padding(.horizontal, -PaperCardMetrics.margin) }
                }
                .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 16).padding(.bottom, 16)
            }
            Button { removing = member } label: {
                Text("Remove from team").font(Theme.font(17, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Theme.brand, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(PressStyle())
            .accessibilityIdentifier("offboard-commit")
            .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 12).padding(.bottom, 12)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.canvas)
        .presentationDetents([.large])
        .removeMemberPrompt($removing, onRemoved: { _ in
            dismiss()
            await onRemoved()
        }, onError: { message in error = message })
    }
}

/// Paper 62A "Ownership": who owns the company, then handing it to someone on the team. The
/// server transfers at once (there is no request to accept) and has no route to close an
/// organization, so the note says what really happens and Paper's Danger zone is left out.
struct OwnershipView: View {
    let members: [RoleMember]
    let onChanged: () async -> Void
    @EnvironmentObject private var session: SessionController
    @Environment(\.dismiss) private var dismiss
    @State private var pickedID: String?
    @State private var transferring: RoleMember?
    @State private var error: String?

    private var owner: RoleMember? { members.first { $0.member.isLegalOwner } }
    private var candidates: [RoleMember] {
        members.filter { OwnershipTransferRules.canOffer($0, session: session) }
            .sorted { $0.member.displayName.localizedCaseInsensitiveCompare($1.member.displayName) == .orderedAscending }
    }
    private var picked: RoleMember? { candidates.first { $0.id == pickedID } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PaperPageTitle(title: "Ownership", subtitle: session.activeOrganization?.name)
                if let owner {
                    label("Owner")
                    HStack(alignment: .center, spacing: 12) {
                        Text(initials(owner.member.displayName))
                            .font(Theme.font(15, weight: .semibold)).foregroundStyle(Theme.brandText)
                            .frame(width: 40, height: 40).background(Theme.brand.opacity(0.24), in: Circle())
                            .dynamicTypeSize(...DynamicTypeSize.large)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(owner.member.displayName).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                            Text("Owner").font(Theme.font(14)).foregroundStyle(Theme.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.horizontal, PaperCardMetrics.margin)
                    .accessibilityElement(children: .combine)
                }
                if !candidates.isEmpty {
                    label("Transfer ownership")
                    VStack(alignment: .leading, spacing: 12) {
                        ThorbisMenu(items: candidates.map { member in
                            ThorbisMenuItem(member.member.displayName, subtitle: member.roleLabel, isSelected: member.id == pickedID) { pickedID = member.id }
                        }, title: "New owner", accessibilityLabel: "New owner, \(picked?.member.displayName ?? "not chosen")") {
                            HStack(spacing: 10) {
                                Text("New owner").font(Theme.font(15)).foregroundStyle(Theme.muted)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(picked?.member.displayName ?? "Choose").font(Theme.font(16, weight: .medium))
                                    .foregroundStyle(picked == nil ? Theme.muted : Theme.foreground).lineLimit(1)
                                PaperIcon(.chevronDown, size: 16, color: Theme.muted)
                            }
                            .padding(.horizontal, 14).frame(minHeight: 50)
                            .background(Theme.foreground.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("ownership-new-owner")
                        Text("\(picked.map { String($0.member.displayName.split(separator: " ").first ?? "They") } ?? "They") can do everything, including billing. You become an Admin.")
                            .font(Theme.font(14)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                        Button {
                            if let picked { transferring = picked } else { error = "Choose who the new owner is first." }
                        } label: {
                            Text("Transfer ownership").font(Theme.font(16, weight: .semibold)).foregroundStyle(Theme.brandText)
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(Theme.brand.opacity(0.24), in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityIdentifier("ownership-transfer")
                    }
                    .padding(12)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.horizontal, PaperCardMetrics.margin)
                }
                if let error { ErrorBanner(message: error).padding(.top, 12) }
            }
            .padding(.bottom, 44)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: pickedID) { _, _ in error = nil }
        .transferOwnershipPrompt($transferring, onTransferred: {
            await onChanged()
            dismiss()
        }, onError: { message in error = message })
    }

    private func label(_ text: String) -> some View {
        PaperCardLabel(title: text)
            .padding(.top, 22)
    }
}

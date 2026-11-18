import SwiftUI

/// Paper 14B "Choose a role": Cancel, the title and Done over one card of the eight roles, each
/// with a line saying what it can do and a 22pt radio. The server invites seven of them
/// (technician, apprentice, dispatcher, csr, office_manager, accountant, admin); Owner is shown
/// so the list reads whole, and says why it can't be picked.
struct RolePickerSheet: View {
    struct Role: Identifiable {
        /// The server's role id; nil for a role that can't be invited.
        let id: String
        let serverID: String?
        let name: String
        let detail: String
    }

    /// Paper 14B's order and words. "Office" is the server's office manager. Paper's "Manager" has no server role, so the
    /// server's admin is offered under its own name: it grants full control and must say so.
    static let roles: [Role] = [
        Role(id: "owner", serverID: nil, name: "Owner", detail: "Everything, including billing and payouts. Ownership is transferred, not invited."),
        Role(id: "office_manager", serverID: "office_manager", name: "Office", detail: "Customers, scheduling, estimates, invoices and collections"),
        Role(id: "dispatcher", serverID: "dispatcher", name: "Dispatcher", detail: "Schedule and assign jobs, talk to customers"),
        Role(id: "admin", serverID: "admin", name: "Admin", detail: "Full control of the workspace, including members and permissions."),
        Role(id: "csr", serverID: "csr", name: "CSR", detail: "Answers calls and texts, books jobs and appointments, and updates customers."),
        Role(id: "technician", serverID: "technician", name: "Technician", detail: "Their own jobs, time clock and payments"),
        Role(id: "apprentice", serverID: "apprentice", name: "Apprentice", detail: "Rides along. Photos and notes, no prices"),
        Role(id: "accountant", serverID: "accountant", name: "Accountant", detail: "Money and reports only"),
    ]

    /// The picker's name for a server role id ("office_manager" reads "Office").
    static func name(for serverID: String) -> String? { roles.first { $0.serverID == serverID }?.name }

    let current: String
    /// Server role ids this person may hand out.
    let allowed: Set<String>
    let onDone: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var picked: String

    init(current: String, allowed: Set<String>, onDone: @escaping (String) -> Void) {
        self.current = current
        self.allowed = allowed
        self.onDone = onDone
        _picked = State(initialValue: current)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                Button { dismiss() } label: {
                    Text("Cancel").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                        .padding(.horizontal, 16).frame(minHeight: 44)
                        .background(Theme.foreground.opacity(0.08), in: Capsule())
                }
                .buttonStyle(PressStyle())
                Spacer(minLength: 0)
                Button { onDone(picked); dismiss() } label: {
                    Text("Done").font(Theme.font(16, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 18).frame(minHeight: 44)
                        .background(Theme.brand, in: Capsule())
                }
                .buttonStyle(PressStyle())
                .accessibilityIdentifier("role-picker-done")
            }
            .overlay {
                Text("Choose a role").font(Theme.font(17, weight: .semibold)).foregroundStyle(Theme.foreground)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 96)
            }
            .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 18).padding(.bottom, 12)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(Self.roles.enumerated()), id: \.element.id) { index, role in
                        if index > 0 { WellDivider(leading: 0) }
                        row(role)
                    }
                }
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .padding(.horizontal, PaperCardMetrics.margin).padding(.bottom, 16)
            }
        }
        .background(Theme.canvas)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func row(_ role: Role) -> some View {
        let usable = role.serverID.map(allowed.contains) ?? false
        let selected = role.serverID == picked
        return Button { if let id = role.serverID, usable { picked = id } } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(role.name).font(Theme.font(16, weight: .semibold)).foregroundStyle(Theme.foreground)
                    Text(role.detail).font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if selected {
                    PaperIcon(.check, size: 12, color: .white)
                        .frame(width: 22, height: 22).background(Theme.brand, in: Circle())
                } else if usable {
                    Circle().strokeBorder(Theme.borderStrong, lineWidth: 1.5).frame(width: 22, height: 22)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background(selected ? Theme.brand.opacity(0.14) : Color.clear)
            .contentShape(Rectangle())
            .opacity(usable ? 1 : 0.55)
        }
        .buttonStyle(RowPressStyle())
        .disabled(!usable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(role.name). \(role.detail)")
        .accessibilityValue(usable ? "" : "Can\u{2019}t be picked here")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("role-picker-\(role.id)")
    }
}

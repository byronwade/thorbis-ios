import SwiftUI

// Paper 85B · Cancel membership: pushed from the membership's ••• on the customer page.
// Cancelling is `POST /v1/customers/{id}/memberships/{membershipId}` with `status: "cancelled"`
// (customers.updateMembership, customer.edit), through `APIClient.cancelMembership`.
// The server ends member pricing the moment a membership is cancelled, keeps no cancellation
// reason, bills nothing and sends no text, so the screen only says what is true.

/// The words the cancel screen shows, kept apart from the view so they can be tested.
enum MembershipCancellation {
    /// "Comfort Club · Gold · Danielle Marlowe": the plan, then whose it is.
    static func subtitle(_ membership: MembershipRecord, customerName: String?) -> String {
        let plan = membership.planName ?? membership.name
        let parts = [plan, customerName ?? ""]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.joined(separator: " \u{00B7} ")
    }

    /// What cancelling changes. Only the server's own rule: a cancelled membership stops pricing
    /// as a member straight away (customers memberPricing reads active memberships only).
    static func changes(_ membership: MembershipRecord) -> [String] {
        var lines: [String] = []
        // "This plan's": another active membership on the customer can still price them as a member.
        if membership.discountPercent > 0 {
            lines.append("This plan's \(membership.discountPercent)% member pricing ends today")
        } else {
            lines.append("This plan's member pricing ends today")
        }
        return lines
    }

    /// Why the commit is off, or nil when it may be pressed.
    static func blockedReason(_ membership: MembershipRecord, canEdit: Bool) -> String? {
        if membership.status == "cancelled" { return "This membership is already cancelled." }
        if !canEdit { return "You don't have permission to cancel memberships." }
        return nil
    }
}

/// Paper 85B. Push it with `.thorbisDestination(item:)`, which adds the round Back; a plain
/// NavigationLink would show the system chevron instead.
struct CancelMembershipView: View {
    let customerID: String
    let membership: MembershipRecord
    /// The customer's name for the subtitle ("Danielle Marlowe"); nil leaves just the plan.
    var customerName: String? = nil
    /// Runs after the server confirms, before the screen closes, so the caller reloads its list.
    var onCancelled: () async -> Void = {}

    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var error: String?

    private var canEdit: Bool { session.can("customer.edit", feature: "core_crm") }
    private var blocked: String? { MembershipCancellation.blockedReason(membership, canEdit: canEdit) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PaperHeader(title: "Cancel membership",
                            subtitle: MembershipCancellation.subtitle(membership, customerName: customerName))
                    .environment(\.paperMenuButton, false)
                VStack(alignment: .leading, spacing: 10) {
                    changesCard
                    if let error {
                        ListErrorRow(message: error)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, PaperCardMetrics.margin)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { commitBar }
        .interactiveDismissDisabled(busy)
    }

    private var changesCard: some View {
        PaperCard(padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("What changes")
                    .font(Theme.font(16, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
                    .accessibilityAddTraits(.isHeader)
                ForEach(MembershipCancellation.changes(membership), id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\u{2022}")
                            .font(Theme.font(15))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 10, alignment: .leading)
                            .accessibilityHidden(true)
                        Text(line)
                            .font(Theme.font(15))
                            .foregroundStyle(Theme.subtle)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("membership-cancel-changes")
    }

    private var commitBar: some View {
        VStack(spacing: 10) {
            if let blocked {
                Text(blocked)
                    .font(Theme.font(13))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
            Button {
                Task { await cancel() }
            } label: {
                HStack(spacing: 8) {
                    if busy { ProgressView().tint(.white) }
                    Text("Cancel membership")
                }
                .dangerCommit()
            }
            .buttonStyle(PressStyle())
            .disabled(busy || blocked != nil)
            .accessibilityIdentifier("membership-cancel-commit")
        }
        .padding(.horizontal, PaperCardMetrics.margin)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Theme.canvas)
    }

    private func cancel() async {
        guard !busy, blocked == nil else { return }
        busy = true
        defer { busy = false }
        do {
            _ = try await api.cancelMembership(customerID, membershipID: membership.id)
            error = nil
            await onCancelled()
            dismiss()
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }
}

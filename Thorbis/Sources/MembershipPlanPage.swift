import SwiftUI

/// Paper 85 "Maintenance plan": a customer's one active plan as its own page. The plan's name over
/// "PLAN-0231 · Danielle Marlowe", the chips (Active, the price, when it renews), what the plan
/// gives, and its billing facts. The commit ("Book covered visit") and the plan's menu are pinned
/// by the page that hosts this body.
///
/// Paper also draws covered visits used this year, the next charge and the card: the server keeps
/// none of those for a membership, so they are not drawn. With no plan, or several, the body is
/// the plain Membership list (add a plan, or cancel one of many).
struct MembershipPlanBody: View {
    let customerID: String
    let customerName: String
    /// The one active plan, published for the host's pinned commit and menu; nil otherwise.
    @Binding var plan: MembershipRecord?
    /// Bumped by the host after a cancel so the plan is read again.
    let reload: Int
    @EnvironmentObject private var api: APIClient
    @State private var plans: [MembershipPlan] = []
    @State private var loaded = false

    private static let checkGlyph = PaperGlyph(box: 14, [.stroke("M4.6 7.2L6.2 8.8L9.4 5.4", 1.4)])
    private static let clockGlyph = PaperGlyph(box: 12, [.circle(6, 6, 4.5, 1.3), .stroke("M6 3.6V6L7.6 7.2", 1.3)])

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let plan {
                page(plan, sold: plans.first { $0.id == plan.planId })
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    PaperPageTitle(title: "Membership", subtitle: customerName, columnInset: PaperCardMetrics.margin)
                    if loaded { CustomerMembershipSection(customerID: customerID) }
                }
            }
        }
        .task(id: reload) { await load() }
    }

    private func page(_ membership: MembershipRecord, sold: MembershipPlan?) -> some View {
        let benefits = Self.benefits(membership, sold: sold)
        let billing = Self.billing(membership, sold: sold)
        return VStack(alignment: .leading, spacing: 0) {
            PaperPageTitle(title: membership.name, subtitle: "PLAN-\(membership.id.suffix(4).uppercased()) \u{00B7} \(customerName)", columnInset: PaperCardMetrics.margin)
            // Paper 85's chips: 40 tall, 14 Medium on the card; "Active" on the success surface.
            FlowChips {
                HStack(spacing: 6) {
                    Circle().fill(Theme.statusDone).frame(width: 6, height: 6).accessibilityHidden(true)
                    Text("Active").font(Theme.font(14, weight: .semibold)).foregroundStyle(Theme.success)
                }
                .padding(.horizontal, 12).frame(minHeight: 40)
                .background(Theme.successSurface, in: Capsule())
                if let price = Self.price(sold) { chip(price) }
                if let renews = membership.renewsOn.flatMap(EquipmentRecord.day) {
                    chip("Renews \(renews.formatted(.dateTime.month(.abbreviated).year()))", clock: true)
                }
            }
            .padding(.top, 12)
            if !benefits.isEmpty {
                CustomerTabLabel(title: "Plan benefits")
                CustomerRowsCard {
                    ForEach(Array(benefits.enumerated()), id: \.offset) { index, benefit in
                        if index > 0 { WellDivider(leading: 50) }
                        HStack(spacing: 0) {
                            PaperIcon(Self.checkGlyph, size: 18, color: Theme.success)
                                .background(Theme.successSurface, in: Circle())
                                .frame(width: 34, alignment: .leading)
                            Text(benefit).font(Theme.font(16, weight: .medium)).tracking(-0.16).foregroundStyle(Theme.foreground)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.leading, 16).padding(.trailing, 16).padding(.vertical, 8)
                        .frame(minHeight: 56)
                    }
                }
            }
            if !billing.isEmpty {
                CustomerTabLabel(title: "Billing")
                CustomerRowsCard {
                    ForEach(Array(billing.enumerated()), id: \.offset) { index, fact in
                        if index > 0 { WellDivider(leading: 16) }
                        PaperDetailRow(label: fact.label) { Text(fact.value) }
                            .padding(.horizontal, 16).frame(minHeight: 56)
                    }
                }
            }
            if let notes = membership.notes, !notes.isEmpty {
                CustomerTabLabel(title: "Notes")
                CustomerRowsCard {
                    Text(notes).font(Theme.font(15)).foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                }
            }
        }
    }

    private func chip(_ text: String, clock: Bool = false) -> some View {
        HStack(spacing: 6) {
            if clock { PaperIcon(Self.clockGlyph, size: 14, color: Theme.muted) }
            Text(text).font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.subtle)
        }
        .padding(.horizontal, 12).frame(minHeight: 40)
        .background(Theme.card, in: Capsule())
    }

    /// "$29/mo", "$290/yr", or the price over its own cadence.
    static func price(_ plan: MembershipPlan?) -> String? {
        guard let plan, let price = plan.price, price > 0 else { return nil }
        let amount = summaryMoney(price, currency: "USD")
        switch plan.billingFrequency {
        case "monthly"?, "month"?: return "\(amount)/mo"
        case "yearly"?, "annual"?, "annually"?, "year"?: return "\(amount)/yr"
        case let other?: return "\(amount) / \(other.replacingOccurrences(of: "_", with: " "))"
        case nil: return amount
        }
    }

    /// What the plan gives, from the membership and the plan it was sold as.
    static func benefits(_ membership: MembershipRecord, sold: MembershipPlan?) -> [String] {
        var rows: [String] = []
        if membership.discountPercent > 0 { rows.append("\(membership.discountPercent)% off all work") }
        if let visits = sold?.visitsPerYear, visits > 0 { rows.append("\(visits) covered visit\(visits == 1 ? "" : "s") a year") }
        else if let cadence = membership.cadence, !cadence.isEmpty { rows.append(cadence.statusLabel) }
        if let words = sold?.description?.trimmingCharacters(in: .whitespacesAndNewlines), !words.isEmpty { rows.append(words) }
        return rows
    }

    static func billing(_ membership: MembershipRecord, sold: MembershipPlan?) -> [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = []
        if let price = price(sold) { rows.append(("Price", price)) }
        if let renews = membership.renewsOn.flatMap(EquipmentRecord.day) {
            rows.append(("Renews", renews.formatted(.dateTime.month(.abbreviated).day().year())))
        }
        if let since = membership.startsOn.flatMap(EquipmentRecord.day) {
            rows.append(("Member since", since.formatted(.dateTime.month(.abbreviated).year())))
        }
        return rows
    }

    private func load() async {
        guard let memberships = try? await api.customerMemberships(customerID) else { loaded = true; plan = nil; return }
        let active = memberships.filter { $0.status == "active" }
        if active.count == 1 { plans = (try? await api.membershipPlans()) ?? [] }
        plan = active.count == 1 ? active[0] : nil
        loaded = true
    }
}

/// Chips that wrap to the next line when they run out of room.
private struct FlowChips: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placed = arrange(width: bounds.width, subviews: subviews)
        for (index, origin) in placed.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                                  proposal: ProposedViewSize(width: min(bounds.width, subviews[index].sizeThatFits(.unspecified).width), height: nil))
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            var size = view.sizeThatFits(.unspecified)
            if size.width > width { size = view.sizeThatFits(ProposedViewSize(width: width, height: nil)) }
            if x > 0, x + size.width > width { x = 0; y += row + spacing; row = 0 }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            row = max(row, size.height)
            widest = max(widest, x - spacing)
        }
        return (CGSize(width: widest.isFinite ? widest : 0, height: y + row), origins)
    }
}

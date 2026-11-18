import SwiftUI

/// Paper 90 "Payouts": what Stripe holds for the company and what it has sent to the bank, from
/// `GET /v1/organization/money-availability`. Read-only: payouts are managed on the web.
struct PayoutsPage: View {
    let snapshot: MoneyAvailability
    let company: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaperHeader(title: "Payouts", subtitle: company.isEmpty ? "Stripe" : "\(company) \u{00B7} Stripe")
                .environment(\.paperMenuButton, false)
                .environment(\.paperDrawer, nil)
            VStack(alignment: .leading, spacing: 0) {
                if let attention = snapshot.attention {
                    // The server's own words when a payout needs someone; only the mark is tinted.
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.warning)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(attention.title).font(Theme.font(16, weight: .medium))
                            Text(attention.explanation).font(Theme.font(14)).foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .foregroundStyle(Theme.foreground)
                    .padding(PaperCardMetrics.inset).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    .padding(.bottom, 12)
                    .accessibilityElement(children: .combine)
                }
                ForEach(Array(snapshot.balances.enumerated()), id: \.element.id) { index, balance in
                    balanceCard(balance).padding(.top, index == 0 ? 0 : 12)
                }
                if !snapshot.payouts.isEmpty {
                    Text("Recent payouts").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.horizontal, 4).padding(.top, 20).padding(.bottom, 8)
                    VStack(spacing: 0) {
                        ForEach(Array(snapshot.payouts.enumerated()), id: \.offset) { index, payout in
                            if index > 0 { WellDivider(leading: 16) }
                            payoutRow(payout)
                        }
                    }
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                }
                Text("Payouts are managed on the web.")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 16)
            }
            .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 6).padding(.bottom, 24)
        }
    }

    /// Paper 90's hero: "Available balance" over the figure in 40 Bold, a hairline, then the next
    /// payout on its way (or, with none on its way, what is still settling).
    private func balanceCard(_ balance: MoneyAvailability.Balance) -> some View {
        let next = snapshot.payouts.first { $0.currency == balance.currency && ["in_transit", "pending"].contains($0.state) }
        let label = snapshot.balances.count > 1 ? "Available balance \u{00B7} \(balance.currency)" : "Available balance"
        return VStack(alignment: .leading, spacing: 0) {
            Text(label).font(Theme.font(15)).foregroundStyle(Theme.muted)
            Text(money(balance.available, currency: balance.currency))
                .font(Theme.font(40, weight: .bold)).tracking(-1.2).monospacedDigit()
                .foregroundStyle(Theme.foreground)
                .lineLimit(1).minimumScaleFactor(0.6)
                .padding(.top, 2).padding(.bottom, 14)
            WellDivider(leading: 0)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(next.map { "Next payout \(Self.day($0.arrivalDate))" } ?? "Pending")
                    .font(Theme.font(15)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(money(next?.amount ?? balance.pending, currency: balance.currency))
                    .font(Theme.font(15, weight: .medium)).monospacedDigit().foregroundStyle(Theme.foreground)
            }
            .padding(.top, 12)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// Paper 90's row: the arrival day over one muted line, the amount over the state word.
    /// The line is the server's own sentence: the bank's name and number never reach the app.
    private func payoutRow(_ payout: MoneyAvailability.Payout) -> some View {
        let state = Self.stateWord(payout.state)
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    if payout.responsibleActor == "owner" {
                        Image(systemName: "exclamationmark.triangle").font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.warning).accessibilityLabel("Needs you")
                    }
                    Text(Self.day(payout.arrivalDate)).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                }
                Text(payout.explanation).font(Theme.font(14)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 0) {
                Text(money(payout.amount, currency: payout.currency))
                    .font(Theme.font(16, weight: .medium)).monospacedDigit().foregroundStyle(Theme.foreground)
                Text(state.word).font(Theme.font(14)).foregroundStyle(state.tint)
            }
            .fixedSize()
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// "In transit" in the warning hue, "Paid" in the success hue, a failure in the destructive one.
    static func stateWord(_ state: String) -> (word: String, tint: Color) {
        switch state {
        case "in_transit": ("In transit", Theme.warning)
        case "paid": ("Paid", Theme.success)
        case "pending": ("Pending", Theme.muted)
        case "failed": ("Failed", Theme.destructive)
        case "canceled": ("Cancelled", Theme.muted)
        default: (state.replacingOccurrences(of: "_", with: " ").capitalized, Theme.muted)
        }
    }

    /// "2026-10-29" as "Thu, Oct 29" (Paper 90 "Mon, Jul 20"); the text as sent when it isn't a day.
    static func day(_ text: String) -> String {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: String(text.prefix(10))) else { return text }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}

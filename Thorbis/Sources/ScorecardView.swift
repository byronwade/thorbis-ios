import SwiftUI

/// design.thorbis.com/team-goals: My scorecard. Sold is the hero; the rest are labelled rows,
/// and a row with a list behind it opens that list (TG-01, TG-06). No charts, badges or streaks.
struct ScorecardView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @State private var period = ScorecardPeriod.week.rawValue
    @State private var card: Scorecard?
    /// The period `card` was loaded for, so a card is never shown under another period's tab.
    @State private var loadedPeriod: ScorecardPeriod?
    @State private var asOf: Date?
    @State private var error: String?
    private let cache = ScorecardCache()

    private var selected: ScorecardPeriod { ScorecardPeriod(rawValue: period) ?? .week }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("My scorecard").font(Theme.font(30, weight: .medium)).tracking(-0.6).accessibilityAddTraits(.isHeader)
                    Text("Your own work, credited by who the job was assigned to").font(Theme.font(15)).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, Theme.gutter).padding(.bottom, 8)
                PaperTabs(options: ScorecardPeriod.allCases.map(\.rawValue), selection: $period)
                if let error, card == nil { ErrorBanner(message: error) { await load() } }
                Group {
                    if let card, loadedPeriod == selected { content(card) } else if error == nil { SkeletonRows(count: 5, leading: false, inset: 0) }
                }
                .padding(.horizontal, Theme.gutter)
            }
            .padding(.bottom, 24)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task(id: period) { await load() }
    }

    @ViewBuilder private func content(_ card: Scorecard) -> some View {
        let me = card.me
        VStack(alignment: .leading, spacing: 4) {
            Text("Sold").font(Theme.font(13)).foregroundStyle(Theme.muted)
            if let sold = me.sold {
                Text(money(sold, currency: card.currency)).moneyStyle(.hero)
            } else {
                Text("—").moneyStyle(.hero).accessibilityLabel("Not available for your role")
            }
            // TG-03: with no goal set, the number stands alone; never an invented target.
            Text(asOf.map { cachedLabel(card, savedAt: $0) } ?? selected.label(now: Date()))
                .font(Theme.font(13)).foregroundStyle(Theme.muted)
        }
        .padding(.top, 12).padding(.bottom, 16)
        .accessibilityElement(children: .combine)

        if card.truncated {
            Text("Some older work wasn't counted, so these numbers may be low.")
                .font(Theme.font(13)).foregroundStyle(Theme.warning).padding(.bottom, 8)
        }

        if let collected = me.collected {
            row("Collected", money(collected, currency: card.currency), route: .invoices)
        }
        row("Jobs done", "\(me.jobsDone)", route: nil)
        if let average = me.averageTicket, let invoices = me.invoices {
            row("Average ticket", invoices == 0 ? "—" : money(average, currency: card.currency), route: .invoices)
        }
        if let rate = me.closeRateBps, let presented = me.estimatesPresented, let approved = me.estimatesApproved {
            row("Close rate", presented == 0 ? "—" : "\(rate / 100)%", detail: presented == 0 ? nil : "\(approved) of \(presented) estimates", route: .estimates)
        }
        // TG-13: review requests appear once they are measured (BYR-1566).

        Text("Sold counts invoices issued on your jobs. Collected counts payments recorded on them.")
            .font(Theme.font(12)).foregroundStyle(Theme.muted).padding(.top, 16)
    }

    /// TG-14: a cached card names its own dates and when it was saved, so yesterday's
    /// Today never reads as today's.
    private func cachedLabel(_ card: Scorecard, savedAt: Date) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let day = Date.FormatStyle().weekday(.abbreviated).month(.abbreviated).day()
        var range = ""
        if let from = iso.date(from: card.from), let to = iso.date(from: card.to) {
            let last = to.addingTimeInterval(-1)
            range = Calendar.current.isDate(from, inSameDayAs: last)
                ? from.formatted(day)
                : "\(from.formatted(day)) – \(last.formatted(day))"
        }
        let saved = Calendar.current.isDateInToday(savedAt)
            ? savedAt.formatted(date: .omitted, time: .shortened)
            : savedAt.formatted(day.hour().minute())
        return range.isEmpty ? "As of \(saved)" : "\(range) · As of \(saved)"
    }

    @ViewBuilder private func row(_ label: String, _ value: String, detail: String? = nil, route: PaperRoute?) -> some View {
        let line = HStack(alignment: .firstTextBaseline) {
            Text(label).font(Theme.font(15, weight: .medium))
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(value).moneyStyle(.row)
                if let detail { Text(detail).font(Theme.font(13)).foregroundStyle(Theme.muted) }
            }
            if route != nil {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 48)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        if let route {
            NavigationLink(value: route) { line }.buttonStyle(.plain)
        } else {
            line
        }
    }

    private func load() async {
        let generation = session.generation
        let period = selected
        guard let user = session.user?.id, let org = session.activeOrganization?.id else { return }
        if loadedPeriod != period {
            card = nil
            asOf = nil
            error = nil
        }
        do {
            let loaded = try await api.scorecard(period)
            guard session.generation == generation, period == selected else { return }
            card = loaded
            loadedPeriod = period
            asOf = nil
            error = nil
            cache.save(loaded, user: user, org: org, period: period)
        } catch is CancellationError {} catch {
            guard session.generation == generation, period == selected else { return }
            // TG-14: offline shows the last numbers this phone loaded, with their time.
            if let cached = cache.load(user: user, org: org, period: period) {
                card = cached.card
                loadedPeriod = period
                asOf = cached.savedAt
            } else {
                card = nil
            }
            self.error = error.localizedDescription
        }
    }
}

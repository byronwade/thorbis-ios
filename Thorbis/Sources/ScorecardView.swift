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
        let sources = card.sources
        let hero = VStack(alignment: .leading, spacing: 4) {
            Text("Sold").font(Theme.font(13)).foregroundStyle(Theme.muted)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let sold = me.sold {
                    Text(money(sold, currency: card.currency)).moneyStyle(.hero)
                } else {
                    Text("—").moneyStyle(.hero).accessibilityLabel("Not available for your role")
                }
                // TG-08: hitting the goal is one quiet check, nothing more.
                if let fraction = ScorecardGoal.fraction(sold: me.sold, goal: me.goal), fraction >= 1 {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(Theme.success)
                        .accessibilityLabel("Goal hit")
                }
                Spacer(minLength: 0)
                if sources != nil, me.sold != nil {
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
                        .accessibilityHidden(true)
                }
            }
            // TG-03: with no goal set, the number stands alone; never an invented target.
            if let goalLine = ScorecardGoal.line(sold: me.sold, goal: me.goal, currency: card.currency),
               let fraction = ScorecardGoal.fraction(sold: me.sold, goal: me.goal) {
                Text(goalLine).font(Theme.font(15)).foregroundStyle(Theme.foreground)
                GoalBar(fraction: fraction).padding(.vertical, 4)
            }
            Text(asOf.map { cachedLabel(card, savedAt: $0) } ?? selected.label(now: Date()))
                .font(Theme.font(13)).foregroundStyle(Theme.muted)
        }
        .padding(.top, 12).padding(.bottom, 16)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        // TG-19: Sold opens exactly the invoices it counts.
        if let sources, me.sold != nil {
            NavigationLink(value: PaperRoute.filteredInvoices(RecordFilter(ids: sources.invoiceIds, title: "Your invoices · \(selected.filterLabel)"))) {
                hero
            }.buttonStyle(.plain)
        } else {
            hero
        }

        if card.truncated {
            Text("Some older work wasn't counted, so these numbers may be low.")
                .font(Theme.font(13)).foregroundStyle(Theme.warning).padding(.bottom, 8)
        }

        // TG-13: a number this role can't see shows a dash, never a zero and never a missing row.
        let period = selected.filterLabel
        let invoicesRoute = sources.map { PaperRoute.filteredInvoices(RecordFilter(ids: $0.invoiceIds, title: "Your invoices · \(period)")) } ?? .invoices
        if let collected = me.collected {
            row("Collected", money(collected, currency: card.currency), route: invoicesRoute)
        } else {
            row("Collected", "—", route: nil)
        }
        row("Jobs done", "\(me.jobsDone)",
            route: sources.map { PaperRoute.filteredJobs(RecordFilter(ids: $0.jobIds, title: "Your jobs done · \(period)")) })
        if let average = me.averageTicket, let invoices = me.invoices {
            row("Average ticket", invoices == 0 ? "—" : money(average, currency: card.currency), route: invoicesRoute)
        } else {
            row("Average ticket", "—", route: nil)
        }
        if let rate = me.closeRateBps, let presented = me.estimatesPresented, let approved = me.estimatesApproved {
            row("Close rate", presented == 0 ? "—" : "\(rate / 100)%", detail: presented == 0 ? nil : "\(approved) of \(presented) estimates",
                route: sources.map { PaperRoute.filteredEstimates(RecordFilter(ids: $0.estimateIds, title: "Your estimates · \(period)")) } ?? .estimates)
        } else {
            row("Close rate", "—", route: nil)
        }
        // TG-13: review requests appear once they are measured (BYR-1566).

        // TG-18: the leaderboard follows the numbers on Week and Month when the owner turns it on.
        if selected != .today, let board = card.leaderboard, !board.isEmpty {
            PaperGroupHeader(title: "Leaderboard").padding(.top, 20)
            ForEach(board) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(entry.rank)").font(Theme.monoFont(13, weight: .medium)).foregroundStyle(Theme.muted)
                            .frame(minWidth: 20, alignment: .leading)
                        Text(entry.me ? "You" : entry.displayName).font(Theme.font(15, weight: entry.me ? .medium : .regular))
                        Spacer()
                        Text(ScorecardGoal.percent(entry.percentOfGoalBps)).moneyStyle(.row)
                    }
                    GoalBar(fraction: Double(entry.percentOfGoalBps) / 10_000)
                }
                .padding(.vertical, 8)
                .frame(minHeight: 48)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Rank \(entry.rank), \(entry.me ? "you" : entry.displayName), \(ScorecardGoal.percent(entry.percentOfGoalBps)) of goal")
            }
            Text("Ranked by percent of each person's own goal.")
                .font(Theme.font(12)).foregroundStyle(Theme.muted).padding(.top, 4)
        }

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
            // An answer from the server (denied, gone) is final: drop the saved card rather
            // than show numbers this person may no longer see.
            if let problem = error as? Problem, let status = problem.status, (400..<500).contains(status) {
                cache.remove(user: user, org: org, period: period)
                card = nil
                loadedPeriod = nil
                asOf = nil
            // TG-14: offline shows the last numbers this phone loaded, with their time.
            } else if let cached = cache.load(user: user, org: org, period: period) {
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

/// A thin progress bar that stops full; the percent beside it may pass 100% (TG-03, TG-18).
struct GoalBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.border)
                Capsule().fill(Theme.foreground)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

/// Today's one summary row (TG-05, TG-19): "This week · $8,240 of $10,000". It opens My scorecard,
/// shows the last week it loaded when offline (TG-14), and hides when Sold isn't measured for this
/// person (TG-13).
struct ScorecardTodayRow: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @State private var card: Scorecard?
    private let cache = ScorecardCache()

    var body: some View {
        Group {
            if let card, let sold = card.me.sold {
                NavigationLink(value: PaperRoute.scorecard) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(ScorecardGoal.todayRow(sold: sold, goal: card.me.goal, currency: card.currency))
                                .font(Theme.font(15, weight: .medium)).monospacedDigit()
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
                                .accessibilityHidden(true)
                        }
                        if let fraction = ScorecardGoal.fraction(sold: sold, goal: card.me.goal) {
                            GoalBar(fraction: fraction)
                        }
                    }
                    .padding(.vertical, 10)
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens My scorecard")
                .padding(.horizontal, Theme.gutter)
            }
        }
        .task(id: session.generation) { await load() }
    }

    private func load() async {
        guard let user = session.user?.id, let org = session.activeOrganization?.id else { return }
        if card == nil { card = cache.load(user: user, org: org, period: .week)?.card }
        do {
            let loaded = try await api.scorecard(.week)
            card = loaded
            cache.save(loaded, user: user, org: org, period: .week)
        } catch is CancellationError {} catch {
            if let problem = error as? Problem, let status = problem.status, (400..<500).contains(status) {
                cache.remove(user: user, org: org, period: .week)
                card = nil
            }
        }
    }
}

import Foundation
import SwiftUI

/// `GET /v1/reports/scorecard` (Thorbis-TanStack composition/scorecard.ts, BYR-1565).
/// Money is integer minor units. A number the caller can't see is null, never zero (TG-13).
struct Scorecard: Codable, Equatable {
    struct Person: Codable, Equatable, Identifiable {
        let userId: String
        let sold: Int?
        let collected: Int?
        let invoices: Int?
        let averageTicket: Int?
        let jobsDone: Int
        let estimatesPresented: Int?
        let estimatesApproved: Int?
        let closeRateBps: Int?
        /// The period's Sold goal (TG-03, TG-07); nil with no goal or when not asked for.
        var goal: Int? = nil
        var id: String { userId }
    }
    /// What makes up this person's own numbers, so each opens exactly its list (TG-19).
    struct Sources: Codable, Equatable {
        let invoiceIds: [String]
        let jobIds: [String]
        let estimateIds: [String]
        let truncated: Bool
    }
    /// Rank and percent of goal only; never anyone's dollars (TG-09, TG-10).
    struct LeaderboardRow: Codable, Equatable, Identifiable {
        let rank: Int
        let userId: String
        let displayName: String
        let percentOfGoalBps: Int
        let me: Bool
        var id: String { userId }
    }
    let generatedAt: String
    let reportVersion: Int
    let from: String
    let to: String
    let currency: String
    let me: Person
    let people: [Person]
    let truncated: Bool
    var sources: Sources? = nil
    /// Nil while the owner has the leaderboard off (TG-09).
    var leaderboard: [LeaderboardRow]? = nil
}

/// The goal line under the hero: "of $10,000 · 82%" (TG-03). Nil with no goal.
enum ScorecardGoal {
    static func fraction(sold: Int?, goal: Int?) -> Double? {
        guard let sold, let goal, goal > 0 else { return nil }
        return Double(sold) / Double(goal)
    }

    static func percent(_ bps: Int) -> String { "\(bps / 100)%" }

    static func line(sold: Int?, goal: Int?, currency: String) -> String? {
        guard let sold, let goal, goal > 0 else { return nil }
        return "of \(money(goal, currency: currency)) · \(percent(sold * 10_000 / goal))"
    }

    /// Today's summary row (TG-19): "This week · $8,240 of $10,000", or "… sold" with no goal.
    static func todayRow(sold: Int, goal: Int?, currency: String) -> String {
        if let goal, goal > 0 {
            return "This week · \(money(sold, currency: currency)) of \(money(goal, currency: currency))"
        }
        return "This week · \(money(sold, currency: currency)) sold"
    }
}

/// design.thorbis.com/team-goals TG-04: Today / Week / Month, weeks start Monday in local time.
enum ScorecardPeriod: String, CaseIterable, Codable {
    case today = "Today", week = "Week", month = "Month"

    /// [start, now) for the period, in the given calendar's time zone.
    func range(now: Date, calendar base: Calendar = .current) -> (from: Date, to: Date) {
        var calendar = base
        calendar.firstWeekday = 2
        let start: Date
        switch self {
        case .today: start = calendar.startOfDay(for: now)
        case .week: start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        case .month: start = calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
        }
        return (start, now)
    }

    /// Days the period's goal covers (TG-07): a week is 7, a month its own days. Today has no goal.
    func goalDays(now: Date, calendar base: Calendar = .current) -> Int? {
        switch self {
        case .today: return nil
        case .week: return 7
        case .month: return base.range(of: .day, in: .month, for: now)?.count
        }
    }

    /// The period in words under the hero: "Mon Oct 26 – today".
    func label(now: Date, calendar: Calendar = .current) -> String {
        let (from, _) = range(now: now, calendar: calendar)
        switch self {
        case .today: return "Today"
        case .week: return "\(from.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) – today"
        case .month: return now.formatted(.dateTime.month(.wide).year())
        }
    }
}

extension APIClient {
    func scorecard(_ period: ScorecardPeriod, now: Date = Date()) async throws -> Scorecard {
        let (from, to) = period.range(now: now)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var items = [
            URLQueryItem(name: "from", value: iso.string(from: from)),
            URLQueryItem(name: "to", value: iso.string(from: to)),
        ]
        if let days = period.goalDays(now: now) { items.append(URLQueryItem(name: "goalDays", value: String(days))) }
        return try await send("GET", "/v1/reports/scorecard", queryItems: items)
    }
}

/// TG-14: the last scorecard this phone loaded, per person, company and period, shown "As of"
/// when offline. Never derived from queued changes.
struct ScorecardCache {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private struct Entry: Codable { let card: Scorecard; let savedAt: Date }

    private func key(_ user: String, _ org: String, _ period: ScorecardPeriod) -> String {
        "thorbis.scorecard.v1.\(org).\(user).\(period.rawValue)"
    }

    func save(_ card: Scorecard, user: String, org: String, period: ScorecardPeriod, at date: Date = Date()) {
        guard let data = try? JSONEncoder().encode(Entry(card: card, savedAt: date)) else { return }
        defaults.set(data, forKey: key(user, org, period))
    }

    func remove(user: String, org: String, period: ScorecardPeriod) {
        defaults.removeObject(forKey: key(user, org, period))
    }

    func load(user: String, org: String, period: ScorecardPeriod) -> (card: Scorecard, savedAt: Date)? {
        guard let data = defaults.data(forKey: key(user, org, period)),
              let entry = try? JSONDecoder().decode(Entry.self, from: data) else { return nil }
        return (entry.card, entry.savedAt)
    }
}

/// A list opened from the scorecard, filtered to exactly the records behind one number (TG-19).
/// The title names the filter at the top: "Your invoices · This week".
struct RecordFilter: Hashable {
    let ids: [String]
    let title: String
}

extension ScorecardPeriod {
    /// "This week", "This month", "Today": the period as the filtered list's title names it.
    var filterLabel: String {
        switch self {
        case .today: "Today"
        case .week: "This week"
        case .month: "This month"
        }
    }
}

/// Loads records one by one for a filtered list. A technician's invoice list is scoped to their
/// jobs, so reading each id is the one read that always answers; offline it uses what this phone
/// saved. Ids that can't be read are skipped and counted. Once the connection drops it stops
/// asking and uses the saved copies for the rest.
@MainActor
enum FilteredRecords {
    static func load<T>(_ ids: [String], fetch: (String) async throws -> T, cached: (String) -> T? = { _ in nil }) async -> (records: [T], missing: Int) {
        var records: [T] = []
        var missing = 0
        var offline = false
        for id in ids {
            if Task.isCancelled { break }
            var record: T?
            if !offline {
                do { record = try await fetch(id) } catch { offline = error.isConnectivityFailure }
            }
            if let found = record ?? cached(id) { records.append(found) } else { missing += 1 }
        }
        return (records, missing)
    }
}

/// The filter's name and one tap to clear it, at the top of a filtered list (TG-19).
struct RecordFilterBar: View {
    let filter: RecordFilter
    let missing: Int
    let clear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(filter.title).font(Theme.font(15, weight: .medium))
                Spacer()
                Button("Show all", action: clear).font(Theme.font(15))
            }
            if missing > 0 {
                Text(missing == 1 ? "1 record isn't on this phone yet." : "\(missing) records aren't on this phone yet.")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
            }
        }
        .frame(minHeight: 44)
        .padding(.vertical, 6)
    }
}

/// Jobs done, opened from the scorecard: the jobs counted, as the schedule draws them.
struct FilteredJobsView: View {
    let filter: RecordFilter
    @EnvironmentObject private var store: Store

    private var jobs: [Job] {
        let byID = Dictionary(store.jobs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return filter.ids.compactMap { byID[$0] }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(filter.title).font(Theme.font(15, weight: .medium))
                    let missing = filter.ids.count - jobs.count
                    if missing > 0 {
                        Text(missing == 1 ? "1 job isn't on this phone yet." : "\(missing) jobs aren't on this phone yet.")
                            .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    }
                }
                .padding(.horizontal, Theme.gutter).padding(.vertical, 6)
                ForEach(jobs) { job in
                    ScheduleCompactRow(job: job, customer: store.customerName(job.customerId), timeStyle: .time)
                }
                if filter.ids.isEmpty {
                    PaperEmptyState(symbol: "checkmark.circle", title: "No jobs done yet", message: "Jobs you complete in this period appear here.")
                        .padding(.horizontal, Theme.gutter)
                }
            }
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle("Jobs done")
        .navigationBarTitleDisplayMode(.inline)
    }
}

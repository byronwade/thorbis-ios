import Foundation

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
        return try await send("GET", "/v1/reports/scorecard", queryItems: [
            URLQueryItem(name: "from", value: iso.string(from: from)),
            URLQueryItem(name: "to", value: iso.string(from: to)),
        ])
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

    func load(user: String, org: String, period: ScorecardPeriod) -> (card: Scorecard, savedAt: Date)? {
        guard let data = defaults.data(forKey: key(user, org, period)),
              let entry = try? JSONDecoder().decode(Entry.self, from: data) else { return nil }
        return (entry.card, entry.savedAt)
    }
}

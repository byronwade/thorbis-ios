import XCTest
@testable import Thorbis

final class ScorecardTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }

    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    func testWeekStartsMondayInLocalTime() {
        // Wednesday 2026-10-28 09:00 in Chicago (14:00Z).
        let now = date("2026-10-28T14:00:00Z")
        let range = ScorecardPeriod.week.range(now: now, calendar: calendar)
        // Monday 2026-10-26 00:00 Chicago is 05:00Z (CDT, UTC-5).
        XCTAssertEqual(range.from, date("2026-10-26T05:00:00Z"))
        XCTAssertEqual(range.to, now)
    }

    func testSundayBelongsToTheWeekThatStartedMonday() {
        let sunday = date("2026-11-01T18:00:00Z")
        XCTAssertEqual(ScorecardPeriod.week.range(now: sunday, calendar: calendar).from, date("2026-10-26T05:00:00Z"))
    }

    func testTodayAndMonthStartAtLocalMidnight() {
        let now = date("2026-10-28T14:00:00Z")
        XCTAssertEqual(ScorecardPeriod.today.range(now: now, calendar: calendar).from, date("2026-10-28T05:00:00Z"))
        XCTAssertEqual(ScorecardPeriod.month.range(now: now, calendar: calendar).from, date("2026-10-01T05:00:00Z"))
    }

    func testDecodesNullsForNumbersTheRoleCannotSee() throws {
        let json = #"""
        {"freshness":"live","generatedAt":"2026-10-28T14:00:00.000Z","reportVersion":1,
         "from":"2026-10-26T05:00:00.000Z","to":"2026-10-28T14:00:00.000Z","currency":"USD",
         "me":{"userId":"u1","sold":null,"collected":null,"invoices":null,"averageTicket":null,"jobsDone":4,
               "estimatesPresented":3,"estimatesApproved":2,"closeRateBps":6666},
         "people":[],"truncated":false}
        """#
        let card = try JSONDecoder().decode(Scorecard.self, from: Data(json.utf8))
        XCTAssertNil(card.me.sold)
        XCTAssertEqual(card.me.jobsDone, 4)
        XCTAssertEqual(card.me.closeRateBps, 6666)
    }

    func testCacheKeepsTheLastCardPerPersonCompanyAndPeriod() throws {
        let defaults = UserDefaults(suiteName: "ScorecardTests-\(UUID().uuidString)")!
        let cache = ScorecardCache(defaults: defaults)
        let person = Scorecard.Person(userId: "u1", sold: 824_000, collected: 761_000, invoices: 14, averageTicket: 58_857,
                                      jobsDone: 14, estimatesPresented: 8, estimatesApproved: 5, closeRateBps: 6250)
        let card = Scorecard(generatedAt: "2026-10-28T14:00:00Z", reportVersion: 1, from: "a", to: "b", currency: "USD",
                             me: person, people: [person], truncated: false)
        let saved = date("2026-10-28T19:14:00Z")
        cache.save(card, user: "u1", org: "o1", period: .week, at: saved)
        XCTAssertEqual(cache.load(user: "u1", org: "o1", period: .week)?.card, card)
        XCTAssertEqual(cache.load(user: "u1", org: "o1", period: .week)?.savedAt, saved)
        XCTAssertNil(cache.load(user: "u1", org: "o1", period: .month))
        XCTAssertNil(cache.load(user: "u2", org: "o1", period: .week))
        cache.remove(user: "u1", org: "o1", period: .week)
        XCTAssertNil(cache.load(user: "u1", org: "o1", period: .week))
    }
}

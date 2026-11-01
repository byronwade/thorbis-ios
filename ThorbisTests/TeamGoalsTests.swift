import XCTest
@testable import Thorbis

final class TeamGoalsTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }

    func testGoalDaysAreAWeekOrTheMonthsDaysAndNoneForToday() {
        let october = ISO8601DateFormatter().date(from: "2026-10-28T14:00:00Z")!
        XCTAssertNil(ScorecardPeriod.today.goalDays(now: october, calendar: calendar))
        XCTAssertEqual(ScorecardPeriod.week.goalDays(now: october, calendar: calendar), 7)
        XCTAssertEqual(ScorecardPeriod.month.goalDays(now: october, calendar: calendar), 31)
    }

    func testGoalLineAndTodayRowFollowTheCopy() {
        XCTAssertEqual(ScorecardGoal.line(sold: 824_000, goal: 1_000_000, currency: "USD"), "of $10,000.00 · 82%")
        XCTAssertNil(ScorecardGoal.line(sold: 824_000, goal: nil, currency: "USD"))
        XCTAssertEqual(ScorecardGoal.todayRow(sold: 824_000, goal: 1_000_000, currency: "USD"), "This week · $8,240.00 of $10,000.00")
        XCTAssertEqual(ScorecardGoal.todayRow(sold: 824_000, goal: nil, currency: "USD"), "This week · $8,240.00 sold")
    }

    func testDecodesGoalSourcesAndLeaderboard() throws {
        let json = #"""
        {"freshness":"live","generatedAt":"2026-10-28T14:00:00.000Z","reportVersion":1,
         "from":"a","to":"b","currency":"USD",
         "me":{"userId":"u1","sold":180000,"collected":0,"invoices":1,"averageTicket":180000,"jobsDone":1,
               "estimatesPresented":1,"estimatesApproved":1,"closeRateBps":10000,"goal":200000},
         "people":[],"truncated":false,
         "sources":{"invoiceIds":["i1"],"jobIds":["j1"],"estimateIds":["e1"],"truncated":false},
         "leaderboard":[{"rank":1,"userId":"u1","displayName":"Sam","percentOfGoalBps":9000,"me":true}]}
        """#
        let card = try JSONDecoder().decode(Scorecard.self, from: Data(json.utf8))
        XCTAssertEqual(card.me.goal, 200_000)
        XCTAssertEqual(card.sources?.invoiceIds, ["i1"])
        XCTAssertEqual(card.leaderboard?.first?.percentOfGoalBps, 9000)
        XCTAssertEqual(card.leaderboard?.first?.me, true)
    }

    func testAnEditSendsOnlyWhatChangedAndNullClears() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let body = try encoder.encode(TeamGoalEdit.person(userId: "u1", weeklySold: nil).body)
        XCTAssertEqual(String(decoding: body, as: UTF8.self), #"{"personGoals":[{"userId":"u1","weeklySold":null}]}"#)
        let role = try encoder.encode(TeamGoalEdit.role(key: "technician", weeklySold: 1_000_000).body)
        XCTAssertEqual(String(decoding: role, as: UTF8.self), #"{"roleGoals":[{"roleKey":"technician","weeklySold":1000000}]}"#)
    }

    func testApplyingAnEditShowsItBeforeItSyncs() {
        let screen = TeamGoalsSettings(
            version: 1, leaderboardEnabled: false,
            roles: [.init(roleKey: "technician", name: "Technician", weeklySold: 1_000_000, people: 2)],
            people: [
                .init(userId: "u1", displayName: "Ana", roleKey: "technician", roleName: "Technician", override: nil, weeklySold: 1_000_000),
                .init(userId: "u2", displayName: "Bo", roleKey: "technician", roleName: "Technician", override: 600_000, weeklySold: 600_000),
            ],
            truncated: false)
        let raised = screen.applying(.role(key: "technician", weeklySold: 1_200_000))
        XCTAssertEqual(raised.people.map(\.weeklySold), [1_200_000, 600_000])
        let reset = raised.applying(.person(userId: "u2", weeklySold: nil))
        XCTAssertEqual(reset.people[1].weeklySold, 1_200_000)
        XCTAssertNil(reset.people[1].override)
        XCTAssertTrue(screen.applying(.leaderboard(true)).leaderboardEnabled)
    }

    func testPendingEditsReplaceTheSameRowAndStayPerPersonAndCompany() {
        let defaults = UserDefaults(suiteName: "TeamGoalsTests-\(UUID().uuidString)")!
        let pending = PendingTeamGoalEdits(defaults: defaults)
        pending.put(.role(key: "technician", weeklySold: 1), actorID: "a", organizationID: "o")
        pending.put(.person(userId: "u1", weeklySold: 2), actorID: "a", organizationID: "o")
        pending.put(.role(key: "technician", weeklySold: 3), actorID: "a", organizationID: "o")
        XCTAssertEqual(pending.edits(actorID: "a", organizationID: "o"),
                       [.person(userId: "u1", weeklySold: 2), .role(key: "technician", weeklySold: 3)])
        XCTAssertEqual(pending.edits(actorID: "b", organizationID: "o"), [])
        pending.remove(.role(key: "technician", weeklySold: 1), actorID: "a", organizationID: "o")
        XCTAssertEqual(pending.edits(actorID: "a", organizationID: "o").count, 2)
        pending.remove(.role(key: "technician", weeklySold: 3), actorID: "a", organizationID: "o")
        XCTAssertEqual(pending.edits(actorID: "a", organizationID: "o"), [.person(userId: "u1", weeklySold: 2)])
    }
}

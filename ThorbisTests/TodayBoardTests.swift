import XCTest
@testable import Thorbis

/// v2 Today / Board (design.thorbis.com "How we show the work", "Rooms").
final class TodayBoardTests: XCTestCase {
    private func job(_ id: String, _ status: String) -> Job {
        Job(id: id, customerId: nil, title: id, status: status, createdAt: nil, updatedAt: nil, allowedTransitions: nil)
    }

    func testBoardColumnsAreOpenEnRouteOnSiteDoneWithTheQueueUnderOpen() {
        let today = [job("a", "scheduled"), job("b", "dispatched"), job("c", "en_route"), job("d", "arrived"),
                     job("e", "in_progress"), job("f", "paused"), job("g", "completed"), job("h", "draft")]
        let columns = DispatchBoardView.columns(today: today, unscheduled: [job("q", "scheduled")])
        XCTAssertEqual(columns.map(\.title), ["Open", "En route", "On site", "Done"])
        // A status the board doesn't name still lands in Open (its card names it).
        XCTAssertEqual(columns[0].jobs.map(\.id), ["a", "b", "h"])
        XCTAssertEqual(columns[0].waiting.map(\.id), ["q"])
        XCTAssertEqual(columns[1].jobs.map(\.id), ["c"])
        XCTAssertEqual(columns[2].jobs.map(\.id), ["d", "e", "f"])
        XCTAssertEqual(columns[3].jobs.map(\.id), ["g"])
        // Every job today lands in exactly one column.
        XCTAssertEqual(columns.flatMap(\.jobs).count, today.count)
    }

    func testTheTodayColumnAlwaysShowsMinutesSoTimesLineUp() throws {
        var parts = DateComponents()
        parts.year = 2026; parts.month = 10; parts.day = 31; parts.hour = 13; parts.minute = 0
        let date = try XCTUnwrap(Calendar.current.date(from: parts))
        let uses24 = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a") == false
        XCTAssertEqual(date.columnTime, uses24 ? "13:00" : "1:00")
        XCTAssertEqual(date.periodMark, uses24 ? nil : "p.m.")
        XCTAssertEqual(date.clockTime, uses24 ? "13:00" : "1:00 p.m.")
    }

    func testJobMoneyAlwaysHasTwoDecimals() {
        XCTAssertEqual(jobShortMoney(34_000, currency: "USD"), money(34_000, currency: "USD"))
        XCTAssertTrue(jobShortMoney(34_000, currency: "USD").hasSuffix(".00"))
    }
}

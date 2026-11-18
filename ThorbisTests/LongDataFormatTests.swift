import XCTest
@testable import Thorbis

/// Real books hold jobs left on site for weeks and clocks never stopped; their times read in days.
@MainActor
final class LongDataFormatTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testOnSiteTimerReadsDaysPastADay() {
        XCTAssertEqual(JobOnSiteClock.timer(arrived: start, now: start.addingTimeInterval(42 * 60 + 18)), "0:42:18")
        XCTAssertEqual(JobOnSiteClock.timer(arrived: start, now: start.addingTimeInterval(86_399)), "23:59:59")
        XCTAssertEqual(JobOnSiteClock.timer(arrived: start, now: start.addingTimeInterval(471 * 3600 + 13 * 60 + 58)), "19d 15h")
    }

    func testOnSiteLineReadsDaysPastADay() {
        XCTAssertEqual(JobOnSiteClock.line(arrived: start, now: start.addingTimeInterval(12 * 60)), "On site 12 min")
        XCTAssertEqual(JobOnSiteClock.line(arrived: start, now: start.addingTimeInterval(20 * 86_400 + 3 * 3600)), "On site 20 d 3 h")
    }

    func testOnSiteShortReadsDaysPastADay() {
        XCTAssertEqual(JobOnSiteClock.short(arrived: start, now: start.addingTimeInterval(72 * 60)), "1h 12m")
        XCTAssertEqual(JobOnSiteClock.short(arrived: start, now: start.addingTimeInterval(20 * 86_400 + 3 * 3600)), "20d 3h")
    }

    func testAgeSpeaksInTheUnitPeopleRead() {
        XCTAssertEqual(PaperAge.span(days: 1), "1 day")
        XCTAssertEqual(PaperAge.span(days: 13), "13 days")
        XCTAssertEqual(PaperAge.span(days: 14), "2 weeks")
        XCTAssertEqual(PaperAge.span(days: 121), "4 months")
        XCTAssertEqual(PaperAge.span(days: 800), "2 years")
        XCTAssertEqual(PaperAge.ago("issued", days: 0), "issued today")
        XCTAssertEqual(PaperAge.ago("Sent", days: 1), "Sent yesterday")
        XCTAssertEqual(PaperAge.ago("issued", days: 121), "issued 4 months ago")
    }

    func testCountsGroupAndCapInBadges() {
        XCTAssertEqual(PaperCount.text(1_284, locale: Locale(identifier: "en_US")), "1,284")
        XCTAssertEqual(PaperCount.badge(42), "42")
        XCTAssertEqual(PaperCount.badge(1_284), "999+")
    }
}

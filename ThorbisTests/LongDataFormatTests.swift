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

final class ClampedSumTests: XCTestCase {
    func testOrdinarySumsAreExact() {
        XCTAssertEqual(100.addingClamped(3, times: 250), 850)
        XCTAssertEqual(0.addingClamped(-2, times: 50), -100)
    }
    func testAbsurdNumbersClampInsteadOfTrapping() {
        XCTAssertEqual(0.addingClamped(Int.max, times: 2), Int.max)
        XCTAssertEqual(0.addingClamped(Int.max, times: -2), Int.min)
        XCTAssertEqual(Int.max.addingClamped(1, times: 1), Int.max)
        XCTAssertEqual(Int.min.addingClamped(1, times: -1), Int.min)
    }
}

final class KeyboardPinnedBarTests: XCTestCase {
    private let screen: (height: CGFloat, bottomInset: CGFloat) = (874, 34)

    func testDockedKeyboardLiftsTheBarToItsTop() {
        let keyboard = CGRect(x: 0, y: 530, width: 402, height: 344)
        XCTAssertEqual(KeyboardPinnedBarMetrics.overlap(keyboard: keyboard, screen: screen), 310)
    }

    func testAViewThatEndsAtTheScreenFootLiftsAsBefore() {
        // A phone's full-height sheet: its foot is the screen's bottom safe area (874 - 34).
        let keyboard = CGRect(x: 0, y: 530, width: 402, height: 344)
        XCTAssertEqual(KeyboardPinnedBarMetrics.overlap(keyboard: keyboard, screen: screen, restingBottom: 840), 310)
        // A foot reported below the safe area never lifts the bar further than the screen asks.
        XCTAssertEqual(KeyboardPinnedBarMetrics.overlap(keyboard: keyboard, screen: screen, restingBottom: 874), 310)
    }

    func testAnIPadFormSheetClearOfTheKeyboardKeepsItsBarAtItsFoot() {
        // iPad Pro 13-inch, portrait: the keyboard's top is at 974 and the system has moved the
        // form sheet up so it ends at 806. Measured against the screen the bar rose 382 points.
        let pad: (height: CGFloat, bottomInset: CGFloat) = (1376, 20)
        let keyboard = CGRect(x: 0, y: 974, width: 1032, height: 402)
        XCTAssertEqual(KeyboardPinnedBarMetrics.overlap(keyboard: keyboard, screen: pad), 382)
        XCTAssertEqual(KeyboardPinnedBarMetrics.overlap(keyboard: keyboard, screen: pad, restingBottom: 806), 0)
    }

    func testAViewPartlyUnderTheKeyboardLiftsByThatPart() {
        // A sheet the system could not move wholly clear: its foot is 60 points under the keyboard's top.
        let pad: (height: CGFloat, bottomInset: CGFloat) = (1032, 20)
        let keyboard = CGRect(x: 0, y: 620, width: 1376, height: 412)
        XCTAssertEqual(KeyboardPinnedBarMetrics.overlap(keyboard: keyboard, screen: pad, restingBottom: 680), 60)
    }

    func testHiddenOrFloatingKeyboardAsksForNothing() {
        XCTAssertEqual(KeyboardPinnedBarMetrics.overlap(keyboard: CGRect(x: 0, y: 874, width: 402, height: 344), screen: screen), 0)
        XCTAssertEqual(KeyboardPinnedBarMetrics.overlap(keyboard: CGRect(x: 40, y: 300, width: 320, height: 260), screen: screen), 0)
        XCTAssertEqual(KeyboardPinnedBarMetrics.overlap(keyboard: .zero, screen: screen), 0)
        XCTAssertEqual(KeyboardPinnedBarMetrics.overlap(keyboard: .zero, screen: screen, restingBottom: 840), 0)
    }
}

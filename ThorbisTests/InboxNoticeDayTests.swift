import XCTest
@testable import Thorbis

final class InboxNoticeDayTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: -7 * 3600)!
        value.locale = Locale(identifier: "en_US_POSIX")
        return value
    }

    func testDatesAndYearAreBasedOnActualLocalDate() {
        XCTAssertEqual(InboxNoticeDay.header("2026-10-30T17:00:00Z", after: nil, hasPrevious: false, calendar: calendar, locale: Locale(identifier: "en_US")), "Oct 30, 2026")
        XCTAssertEqual(InboxNoticeDay.header("2026-10-30T02:00:00Z", after: "2026-10-30T17:00:00Z", hasPrevious: true, calendar: calendar, locale: Locale(identifier: "en_US")), "Oct 29, 2026")
        let older = InboxNoticeDay.header("2025-03-12T15:00:00Z", after: "2026-10-30T02:00:00Z", hasPrevious: true, calendar: calendar, locale: Locale(identifier: "en_US"))
        XCTAssertTrue(older?.contains("2025") == true)
    }

    func testSameDayHasNoRepeatedHeaderAndUnknownDoesNotInventDate() {
        XCTAssertNil(InboxNoticeDay.header("2026-10-30T18:00:00Z", after: "2026-10-30T17:00:00Z", hasPrevious: true, calendar: calendar, locale: Locale(identifier: "en_US")))
        XCTAssertEqual(InboxNoticeDay.header("invalid", after: "2026-10-30T17:00:00Z", hasPrevious: true, calendar: calendar, locale: Locale(identifier: "en_US")), "Date unavailable")
        XCTAssertNil(InboxNoticeDay.header("also invalid", after: "invalid", hasPrevious: true, calendar: calendar, locale: Locale(identifier: "en_US")))
        XCTAssertEqual(InboxNoticeDay.header("2026-10-30T17:00:00Z", after: "invalid", hasPrevious: true, calendar: calendar, locale: Locale(identifier: "en_US")), "Oct 30, 2026")
        XCTAssertEqual(InboxNoticeDay.header(nil, after: "2026-10-30T17:00:00Z", hasPrevious: true, calendar: calendar, locale: Locale(identifier: "en_US")), "Date unavailable")
        XCTAssertNil(InboxNoticeDay.header(nil, after: nil, hasPrevious: true, calendar: calendar, locale: Locale(identifier: "en_US")))
    }
    func testDSTBoundaryUsesCalendarDaysInsteadOfFixedHours() {
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = TimeZone(identifier: "America/New_York")!
        XCTAssertEqual(InboxNoticeDay.header("2026-03-08T04:30:00Z", after: nil, hasPrevious: false, calendar: eastern, locale: Locale(identifier: "en_US")), "Mar 7, 2026")
    }

    func testMissingAndNullTimestampsDecodeWithoutDroppingNotices() throws {
        let missing = Data(#"{"id":"n1","jobId":"job","title":"Visit","meta":"","read":false}"#.utf8)
        let null = Data(#"{"id":"n2","jobId":"job","title":"Visit","meta":"","at":null,"read":true}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(StaffNotice.self, from: missing).at)
        XCTAssertNil(try JSONDecoder().decode(StaffNotice.self, from: null).at)
    }
}

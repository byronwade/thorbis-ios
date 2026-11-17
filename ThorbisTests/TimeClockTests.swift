import XCTest
@testable import Thorbis

@MainActor
final class TimeClockTests: XCTestCase {
    private let userA = "00000000-0000-4000-8000-000000000001"
    private let userB = "00000000-0000-4000-8000-000000000002"
    private let orgA = "00000000-0000-4000-8000-000000000003"
    private let orgB = "00000000-0000-4000-8000-000000000004"

    /// A fixed calendar so the tests read the same on any machine: Gregorian, New York, weeks from Monday.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        let parts = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        guard let date = calendar.date(from: parts) else {
            XCTFail("bad date")
            return Date(timeIntervalSince1970: 0)
        }
        return date
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    // MARK: Durations

    func testWorkedTimeIsTheSpanAndAnOpenEntryRunsToNow() {
        let closed = TimeClockEntry(clockIn: date(2026, 7, 20, 7, 30), clockOut: date(2026, 7, 20, 16, 12))
        XCTAssertEqual(TimeClockMath.workedSeconds(closed, now: date(2026, 7, 25)), 8 * 3600 + 42 * 60)

        let open = TimeClockEntry(clockIn: date(2026, 7, 21, 7, 58))
        XCTAssertEqual(TimeClockMath.workedSeconds(open, now: date(2026, 7, 21, 10, 12, 36)), 2 * 3600 + 14 * 60 + 36)
        // A clock that reads before the clock-in never gives negative time.
        XCTAssertEqual(TimeClockMath.workedSeconds(open, now: date(2026, 7, 21, 7, 0)), 0)
    }

    func testWordsForDurations() {
        XCTAssertEqual(TimeClockMath.clockLabel(2 * 3600 + 14 * 60 + 36), "2:14:36")
        XCTAssertEqual(TimeClockMath.clockLabel(12 * 60 + 40, short: true), "12:40")
        XCTAssertEqual(TimeClockMath.clockLabel(3600 + 5, short: true), "1:00:05")
        XCTAssertEqual(TimeClockMath.clockLabel(-5), "0:00:00")
        XCTAssertEqual(TimeClockMath.durationLabel(2 * 3600 + 14 * 60 + 59), "2h 14m")
        XCTAssertEqual(TimeClockMath.durationLabel(30 * 60), "30m")
        XCTAssertEqual(TimeClockMath.durationLabel(8 * 3600), "8h")
        XCTAssertEqual(TimeClockMath.decimalHours(8 * 3600), "8.0")
        XCTAssertEqual(TimeClockMath.decimalHours(8 * 3600 + 12 * 60), "8.2")
        XCTAssertEqual(TimeClockMath.minutesLabel(0), "None")
        XCTAssertEqual(TimeClockMath.minutesLabel(90), "1 h 30 min")
    }

    // MARK: Breaks

    func testBreaksComeOffAndARunningBreakFreezesTheTotal() {
        var entry = TimeClockEntry(clockIn: date(2026, 7, 21, 7, 58))
        entry.breaks = [TimeClockBreak(start: date(2026, 7, 21, 9, 28), end: date(2026, 7, 21, 9, 58))]
        let now = date(2026, 7, 21, 12, 0)
        XCTAssertEqual(TimeClockMath.breakSeconds(entry, now: now), 30 * 60)
        XCTAssertEqual(TimeClockMath.workedSeconds(entry, now: now), TimeInterval(3 * 3600 + 32 * 60))

        // On break: the worked total stands still at what was worked before it.
        var onBreak = TimeClockEntry(clockIn: date(2026, 7, 21, 7, 58))
        onBreak.breaks = [TimeClockBreak(start: date(2026, 7, 21, 9, 28))]
        XCTAssertEqual(TimeClockMath.workedSeconds(onBreak, now: date(2026, 7, 21, 9, 40)), 90 * 60)
        XCTAssertEqual(TimeClockMath.workedSeconds(onBreak, now: date(2026, 7, 21, 11, 0)), 90 * 60)
        XCTAssertNotNil(onBreak.openBreak)
    }

    func testOverlappingAndOutOfShiftBreaksAreNotCountedTwiceOrOutsideTheShift() {
        var entry = TimeClockEntry(clockIn: date(2026, 7, 20, 8, 0), clockOut: date(2026, 7, 20, 16, 0))
        entry.breaks = [
            TimeClockBreak(start: date(2026, 7, 20, 12, 0), end: date(2026, 7, 20, 12, 30)),
            TimeClockBreak(start: date(2026, 7, 20, 12, 15), end: date(2026, 7, 20, 12, 45)),
            // Runs past the clock-out: only the part inside the shift counts.
            TimeClockBreak(start: date(2026, 7, 20, 15, 50), end: date(2026, 7, 20, 16, 30)),
            // Wholly before the clock-in: ignored.
            TimeClockBreak(start: date(2026, 7, 20, 6, 0), end: date(2026, 7, 20, 7, 0)),
        ]
        let now = date(2026, 7, 21)
        XCTAssertEqual(TimeClockMath.breakSeconds(entry, now: now), 45 * 60 + 10 * 60)
        XCTAssertEqual(TimeClockMath.workedSeconds(entry, now: now), 8 * 3600 - 55 * 60)
    }

    func testSettingABreakLengthPlacesItInsideTheShift() throws {
        let entry = TimeClockEntry(clockIn: date(2026, 7, 20, 8, 0), clockOut: date(2026, 7, 20, 16, 30),
                                   breaks: [TimeClockBreak(start: date(2026, 7, 20, 9, 0), end: date(2026, 7, 20, 9, 10))])
        let now = date(2026, 7, 21)
        let set = try TimeClockMath.settingBreak(minutes: 30, on: entry, now: now)
        XCTAssertEqual(set.breaks.count, 1)
        XCTAssertEqual(TimeClockMath.workedSeconds(set, now: now), 8 * 3600)
        XCTAssertTrue(try TimeClockMath.settingBreak(minutes: 0, on: entry, now: now).breaks.isEmpty)
        XCTAssertThrowsError(try TimeClockMath.settingBreak(minutes: 9 * 60, on: entry, now: now)) {
            XCTAssertEqual($0 as? TimeClockProblem, .breakTooLong)
        }
    }

    // MARK: Days and weeks

    func testAShiftAcrossMidnightIsSplitBetweenTheTwoDays() {
        // Tuesday 22:00 to Wednesday 06:00, a 30 minute break from 23:45 to 00:15.
        var entry = TimeClockEntry(clockIn: date(2026, 7, 21, 22, 0), clockOut: date(2026, 7, 22, 6, 0))
        entry.breaks = [TimeClockBreak(start: date(2026, 7, 21, 23, 45), end: date(2026, 7, 22, 0, 15))]
        let now = date(2026, 7, 25)
        let tuesday = TimeClockMath.dayInterval(date(2026, 7, 21, 12), calendar: calendar)
        let wednesday = TimeClockMath.dayInterval(date(2026, 7, 22, 12), calendar: calendar)
        XCTAssertEqual(TimeClockMath.workedSeconds(entry, now: now, within: tuesday), 2 * 3600 - 15 * 60)
        XCTAssertEqual(TimeClockMath.workedSeconds(entry, now: now, within: wednesday), 6 * 3600 - 15 * 60)
        XCTAssertEqual(TimeClockMath.workedSeconds(entry, now: now), 7 * 3600 + 30 * 60)

        let week = TimeClockMath.weekInterval(containing: date(2026, 7, 21), calendar: calendar)
        let days = TimeClockMath.days([entry], in: week, now: now, calendar: calendar)
        XCTAssertEqual(days.count, 7)
        let expected: [TimeInterval] = [0, 6300, 20_700, 0, 0, 0, 0]
        XCTAssertEqual(days.map(\.seconds), expected)
        XCTAssertEqual(days[1].firstIn, date(2026, 7, 21, 22, 0))
        XCTAssertEqual(days[1].lastOut, date(2026, 7, 22, 0, 0))
        XCTAssertEqual(days[2].firstIn, date(2026, 7, 22, 0, 0))
        XCTAssertEqual(days[2].lastOut, date(2026, 7, 22, 6, 0))
        XCTAssertEqual(days[1].breakSeconds, 15 * 60)
        XCTAssertTrue(days[0].entries.isEmpty)
    }

    func testWeekStartsOnTheCalendarsFirstWeekdayAndGroupsAcrossTheBoundary() {
        // Monday-first: Mon Jul 20 to Mon Jul 27.
        let week = TimeClockMath.weekInterval(containing: date(2026, 7, 23, 15), calendar: calendar)
        XCTAssertEqual(week.start, date(2026, 7, 20))
        XCTAssertEqual(week.end, date(2026, 7, 27))
        // Sunday night belongs to the week that is ending; one second later is the next week.
        XCTAssertEqual(TimeClockMath.weekInterval(containing: date(2026, 7, 26, 23, 59, 59), calendar: calendar).start, date(2026, 7, 20))
        XCTAssertEqual(TimeClockMath.weekInterval(containing: date(2026, 7, 27, 0, 0, 0), calendar: calendar).start, date(2026, 7, 27))
        XCTAssertEqual(TimeClockMath.weekInterval(containing: date(2026, 7, 23), offsetBy: -1, calendar: calendar).start, date(2026, 7, 13))

        // Sunday-first calendars put the same Sunday at the start of its week.
        var sundayFirst = calendar
        sundayFirst.firstWeekday = 1
        XCTAssertEqual(TimeClockMath.weekInterval(containing: date(2026, 7, 26, 12), calendar: sundayFirst).start, date(2026, 7, 26))

        // Sunday 20:00 to Monday 04:00 straddles the week boundary: four hours to each week.
        let entry = TimeClockEntry(clockIn: date(2026, 7, 26, 20, 0), clockOut: date(2026, 7, 27, 4, 0))
        let now = date(2026, 8, 1)
        let next = TimeClockMath.weekInterval(containing: date(2026, 7, 27, 12), calendar: calendar)
        XCTAssertEqual(TimeClockMath.workedSeconds([entry], now: now, within: week), 4 * 3600)
        XCTAssertEqual(TimeClockMath.workedSeconds([entry], now: now, within: next), 4 * 3600)
        XCTAssertEqual(TimeClockMath.days([entry], in: week, now: now, calendar: calendar).last?.seconds, 4 * 3600)
        XCTAssertEqual(TimeClockMath.days([entry], in: next, now: now, calendar: calendar).first?.seconds, 4 * 3600)
    }

    func testWeekDaysFollowTheClockChange() {
        // The United States falls back on Sunday 1 November 2026: that day is 25 hours long.
        let week = TimeClockMath.weekInterval(containing: date(2026, 10, 28), calendar: calendar)
        let days = TimeClockMath.days([], in: week, now: date(2026, 11, 5), calendar: calendar)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.last?.date, date(2026, 11, 1))
        XCTAssertEqual(TimeClockMath.dayInterval(date(2026, 11, 1, 12), calendar: calendar).duration, 25 * 3600)
    }

    func testTodayIsOpenWhileClockedInAndWeekTotalsAddUp() {
        let now = date(2026, 7, 21, 10, 12)
        let entries = [
            TimeClockEntry(clockIn: date(2026, 7, 20, 7, 30), clockOut: date(2026, 7, 20, 16, 12)),
            TimeClockEntry(clockIn: date(2026, 7, 21, 7, 58)),
        ]
        let week = TimeClockMath.weekInterval(containing: now, calendar: calendar)
        let days = TimeClockMath.days(entries, in: week, now: now, calendar: calendar)
        XCTAssertFalse(days[0].isOpen)
        XCTAssertEqual(days[0].lastOut, date(2026, 7, 20, 16, 12))
        XCTAssertTrue(days[1].isOpen)
        XCTAssertNil(days[1].lastOut)
        XCTAssertFalse(days[1].missedClockOut)
        let weekTotal: TimeInterval = days.reduce(0) { $0 + $1.seconds }
        XCTAssertEqual(weekTotal, TimeInterval(10 * 3600 + 56 * 60))
        XCTAssertEqual(TimeClockMath.overtimeSeconds(weekSeconds: 41 * 3600 + 1800), 5400)
        XCTAssertEqual(TimeClockMath.overtimeSeconds(weekSeconds: 18 * 3600), 0)
    }

    // MARK: Missed clock-out

    func testAnEntryLeftOpenIsAMissedClockOutAndTheFixClosesIt() throws {
        var entry = TimeClockEntry(clockIn: date(2026, 7, 20, 7, 52))
        entry.breaks = [TimeClockBreak(start: date(2026, 7, 20, 12, 0), end: date(2026, 7, 20, 12, 30))]
        XCTAssertFalse(TimeClockMath.isMissedClockOut(entry, now: date(2026, 7, 20, 17, 0)))
        let now = date(2026, 7, 21, 7, 40)
        XCTAssertTrue(TimeClockMath.isMissedClockOut(entry, now: now))
        XCTAssertEqual(TimeClockMath.suggestedClockOut(entry, now: now), date(2026, 7, 20, 15, 52))

        let fixed = try TimeClockMath.fixingClockOut(entry, at: date(2026, 7, 20, 16, 38), reason: .forgot, note: "  ", now: now)
        XCTAssertEqual(fixed.clockOut, date(2026, 7, 20, 16, 38))
        XCTAssertEqual(fixed.change?.reason, .forgot)
        XCTAssertNil(fixed.change?.note)
        XCTAssertEqual(fixed.change?.changedAt, now)
        // 7:52 to 4:38 with 30 minutes of lunch: Paper 27B's "8 h 16 min".
        XCTAssertEqual(TimeClockMath.workedSeconds(fixed, now: now), 8 * 3600 + 16 * 60)
        XCTAssertFalse(TimeClockMath.isMissedClockOut(fixed, now: now))
    }

    func testFixingEndsARunningBreakAndRejectsImpossibleTimes() throws {
        var entry = TimeClockEntry(clockIn: date(2026, 7, 20, 8, 0))
        entry.breaks = [
            TimeClockBreak(start: date(2026, 7, 20, 12, 0), end: date(2026, 7, 20, 12, 30)),
            TimeClockBreak(start: date(2026, 7, 20, 15, 0)),
        ]
        let now = date(2026, 7, 21, 9, 0)
        // A break that never ended: the offered clock-out is when it began.
        XCTAssertEqual(TimeClockMath.suggestedClockOut(entry, now: now), date(2026, 7, 20, 15, 0))

        let late = try TimeClockMath.fixingClockOut(entry, at: date(2026, 7, 20, 16, 0), reason: .phoneDied, note: "Flat battery", now: now)
        XCTAssertEqual(late.breaks.last?.end, date(2026, 7, 20, 16, 0))
        XCTAssertEqual(TimeClockMath.workedSeconds(late, now: now), 8 * 3600 - 30 * 60 - 3600)
        XCTAssertEqual(late.change?.note, "Flat battery")

        // Clocked out before that break began: the break is dropped.
        let early = try TimeClockMath.fixingClockOut(entry, at: date(2026, 7, 20, 14, 0), reason: .other, note: nil, now: now)
        XCTAssertEqual(early.breaks.count, 1)
        XCTAssertEqual(TimeClockMath.workedSeconds(early, now: now), 6 * 3600 - 30 * 60)

        XCTAssertThrowsError(try TimeClockMath.fixingClockOut(entry, at: date(2026, 7, 20, 7, 0), reason: .forgot, note: nil, now: now)) {
            XCTAssertEqual($0 as? TimeClockProblem, .endsBeforeStart)
        }
        XCTAssertThrowsError(try TimeClockMath.fixingClockOut(entry, at: date(2026, 7, 21, 10, 0), reason: .forgot, note: nil, now: now)) {
            XCTAssertEqual($0 as? TimeClockProblem, .inTheFuture)
        }
    }

    // MARK: Store

    func testAClockInSurvivesReopeningTheStore() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let start = date(2026, 7, 21, 7, 58)
        let first = try TimeClockStore(userID: userA, organizationID: orgA, directory: directory)
        XCTAssertNil(first.active)
        try first.clockIn(at: start)
        try first.startBreak(at: date(2026, 7, 21, 9, 28), plannedMinutes: 30)

        // The app was closed: a new store reads the start time, and elapsed is worked out from it.
        let reopened = try TimeClockStore(userID: userA, organizationID: orgA, directory: directory)
        XCTAssertEqual(reopened.active?.clockIn, start)
        XCTAssertEqual(reopened.active?.openBreak?.plannedMinutes, 30)
        try reopened.endBreak(at: date(2026, 7, 21, 9, 58))
        let active = try XCTUnwrap(reopened.active)
        XCTAssertEqual(TimeClockMath.workedSeconds(active, now: date(2026, 7, 21, 12, 58)), 4 * 3600 + 30 * 60)

        let out = try reopened.clockOut(at: date(2026, 7, 21, 16, 28))
        XCTAssertEqual(TimeClockMath.workedSeconds(out, now: date(2026, 7, 22)), 8 * 3600)
        XCTAssertNil(try TimeClockStore(userID: userA, organizationID: orgA, directory: directory).active)
    }

    func testHoursArePersonalToThePersonAndTheWorkspace() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let mine = try TimeClockStore(userID: userA, organizationID: orgA, directory: directory)
        try mine.clockIn(at: date(2026, 7, 21, 8, 0))
        try mine.save(TimeClockTimeOff(from: date(2026, 8, 10), to: date(2026, 8, 12)))

        XCTAssertTrue(try TimeClockStore(userID: userB, organizationID: orgA, directory: directory).entries.isEmpty)
        XCTAssertTrue(try TimeClockStore(userID: userA, organizationID: orgB, directory: directory).entries.isEmpty)
        XCTAssertTrue(try TimeClockStore(userID: userB, organizationID: orgA, directory: directory).timeOff.isEmpty)
        // Upper and lower case ids are the same person.
        XCTAssertEqual(try TimeClockStore(userID: userA.uppercased(), organizationID: orgA, directory: directory).entries.count, 1)
        XCTAssertFalse(mine.fileURL.lastPathComponent.contains(userA))
        XCTAssertFalse(mine.fileURL.lastPathComponent.contains(orgA))
        XCTAssertThrowsError(try TimeClockStore(userID: " ", organizationID: orgA, directory: directory)) {
            XCTAssertEqual($0 as? TimeClockProblem, .invalidIdentity)
        }
    }

    func testTheClockRefusesStepsThatDoNotFollow() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try TimeClockStore(userID: userA, organizationID: orgA, directory: directory)
        XCTAssertThrowsError(try store.clockOut(at: date(2026, 7, 21, 9, 0))) { XCTAssertEqual($0 as? TimeClockProblem, .notClockedIn) }
        XCTAssertThrowsError(try store.startBreak(at: date(2026, 7, 21, 9, 0))) { XCTAssertEqual($0 as? TimeClockProblem, .notClockedIn) }
        try store.clockIn(at: date(2026, 7, 21, 8, 0))
        XCTAssertThrowsError(try store.clockIn(at: date(2026, 7, 21, 8, 5))) { XCTAssertEqual($0 as? TimeClockProblem, .alreadyClockedIn) }
        XCTAssertThrowsError(try store.endBreak(at: date(2026, 7, 21, 9, 0))) { XCTAssertEqual($0 as? TimeClockProblem, .notOnBreak) }
        try store.startBreak(at: date(2026, 7, 21, 12, 0))
        XCTAssertThrowsError(try store.startBreak(at: date(2026, 7, 21, 12, 5))) { XCTAssertEqual($0 as? TimeClockProblem, .alreadyOnBreak) }
        // Clocking out on a break ends the break with the shift.
        let out = try store.clockOut(at: date(2026, 7, 21, 12, 20))
        XCTAssertEqual(out.breaks.last?.end, date(2026, 7, 21, 12, 20))
        XCTAssertEqual(TimeClockMath.workedSeconds(out, now: date(2026, 7, 22)), 4 * 3600)
        XCTAssertEqual(store.entries.count, 1)
    }

    func testEditingAddingAndDeletingEntries() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = date(2026, 7, 22, 9, 0)
        let store = try TimeClockStore(userID: userA, organizationID: orgA, directory: directory)
        var monday = TimeClockEntry(clockIn: date(2026, 7, 20, 8, 0), clockOut: date(2026, 7, 20, 16, 0))
        try store.save(monday, now: now)
        let tuesday = TimeClockEntry(clockIn: date(2026, 7, 21, 8, 0), clockOut: date(2026, 7, 21, 12, 0))
        try store.save(tuesday, now: now)
        // Newest first.
        XCTAssertEqual(store.entries.map(\.id), [tuesday.id, monday.id])

        monday.clockOut = date(2026, 7, 20, 17, 0)
        monday.change = TimeClockEntry.Change(reason: .other, note: "Stayed late", changedAt: now)
        try store.save(monday, now: now)
        let reopened = try TimeClockStore(userID: userA, organizationID: orgA, directory: directory)
        XCTAssertEqual(reopened.entries.count, 2)
        XCTAssertEqual(reopened.entries.last?.clockOut, date(2026, 7, 20, 17, 0))
        XCTAssertEqual(reopened.entries.last?.change?.note, "Stayed late")

        // A punch can't overlap another, end before it starts, or sit in the future.
        let overlapping = TimeClockEntry(clockIn: date(2026, 7, 21, 11, 0), clockOut: date(2026, 7, 21, 13, 0))
        XCTAssertThrowsError(try store.save(overlapping, now: now)) { XCTAssertEqual($0 as? TimeClockProblem, .overlapsAnotherEntry) }
        let backwards = TimeClockEntry(clockIn: date(2026, 7, 19, 12, 0), clockOut: date(2026, 7, 19, 9, 0))
        XCTAssertThrowsError(try store.save(backwards, now: now)) { XCTAssertEqual($0 as? TimeClockProblem, .endsBeforeStart) }
        let future = TimeClockEntry(clockIn: date(2026, 7, 22, 8, 0), clockOut: date(2026, 7, 22, 17, 0))
        XCTAssertThrowsError(try store.save(future, now: now)) { XCTAssertEqual($0 as? TimeClockProblem, .inTheFuture)  }
        // Back to back is fine.
        try store.save(TimeClockEntry(clockIn: date(2026, 7, 21, 12, 0), clockOut: date(2026, 7, 21, 13, 0)), now: now)
        XCTAssertEqual(store.entries.count, 3)

        try store.removeEntry(tuesday.id)
        XCTAssertEqual(try TimeClockStore(userID: userA, organizationID: orgA, directory: directory).entries.count, 2)
    }

    func testFixingAMissedClockOutThroughTheStoreLetsThePersonClockInAgain() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try TimeClockStore(userID: userA, organizationID: orgA, directory: directory)
        let entry = try store.clockIn(at: date(2026, 7, 20, 7, 52))
        let now = date(2026, 7, 21, 7, 45)
        XCTAssertThrowsError(try store.clockIn(at: now)) { XCTAssertEqual($0 as? TimeClockProblem, .alreadyClockedIn) }

        try store.fixMissedClockOut(entry.id, at: date(2026, 7, 20, 16, 38), reason: .forgot, note: nil, now: now)
        XCTAssertNil(store.active)
        XCTAssertEqual(store.entries.first?.change?.reason, .forgot)
        try store.clockIn(at: now)
        XCTAssertEqual(store.active?.clockIn, now)
        XCTAssertEqual(try TimeClockStore(userID: userA, organizationID: orgA, directory: directory).entries.count, 2)
        XCTAssertThrowsError(try store.fixMissedClockOut("missing", at: now, reason: .forgot, note: nil, now: now)) {
            XCTAssertEqual($0 as? TimeClockProblem, .notFound)
        }
    }

    // MARK: Time off

    func testTimeOffIsKeptCountedAndNeverSent() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try TimeClockStore(userID: userA, organizationID: orgA, directory: directory)
        var request = TimeClockTimeOff(from: date(2026, 8, 10, 8), to: date(2026, 8, 12, 17), kind: .vacation,
                                       note: "Family trip", createdAt: date(2026, 7, 21))
        try store.save(request)
        XCTAssertEqual(TimeClockMath.timeOffDays(request, calendar: calendar), 3)
        XCTAssertTrue(TimeClockMath.timeOffCovers(request, day: date(2026, 8, 11, 23), calendar: calendar))
        XCTAssertFalse(TimeClockMath.timeOffCovers(request, day: date(2026, 8, 13, 0), calendar: calendar))
        XCTAssertEqual(TimeClockTimeOff.statusLabel, "Not sent \u{2014} kept on this phone")

        request.kind = .sick
        request.to = date(2026, 8, 10, 8)
        try store.save(request)
        let reopened = try TimeClockStore(userID: userA, organizationID: orgA, directory: directory)
        XCTAssertEqual(reopened.timeOff, [request])
        XCTAssertEqual(TimeClockMath.timeOffDays(request, calendar: calendar), 1)

        request.to = date(2026, 8, 9)
        XCTAssertThrowsError(try store.save(request)) { XCTAssertEqual($0 as? TimeClockProblem, .timeOffEndsBeforeStart) }
        try store.removeTimeOff(request.id)
        XCTAssertTrue(try TimeClockStore(userID: userA, organizationID: orgA, directory: directory).timeOff.isEmpty)
    }

    func testTheModelDropsTheLastPersonsHoursWhenTheSessionChanges() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = TimeClockModel()
        XCTAssertFalse(model.perform { try $0.clockIn() })
        XCTAssertNotNil(model.actionError)

        model.bind(userID: userA, organizationID: orgA, directory: directory)
        XCTAssertTrue(model.isBound)
        XCTAssertTrue(model.perform { try $0.clockIn(at: self.date(2026, 7, 21, 8, 0)) })
        XCTAssertNotNil(model.active)
        XCTAssertFalse(model.perform { try $0.clockIn(at: self.date(2026, 7, 21, 8, 1)) })
        XCTAssertEqual(model.actionError, TimeClockProblem.alreadyClockedIn.errorDescription)

        model.bind(userID: userB, organizationID: orgA, directory: directory)
        XCTAssertNil(model.active)
        XCTAssertNil(model.actionError)
        model.bind(userID: nil, organizationID: orgA, directory: directory)
        XCTAssertFalse(model.isBound)
        XCTAssertNotNil(model.loadError)
        model.bind(userID: userA, organizationID: orgA, directory: directory)
        XCTAssertEqual(model.entries.count, 1)
    }
}

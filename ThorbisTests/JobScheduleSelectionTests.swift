import XCTest
@testable import Thorbis

final class JobScheduleSelectionTests: XCTestCase {
    func testSchedulePresetUsesTheSelectedLocalDayAndClockTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let day = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-26T12:00:00Z"))

        let selected = try XCTUnwrap(JobScheduleSelection.date(on: day, hour: 10, minute: 30, calendar: calendar))

        XCTAssertEqual(ISO8601DateFormatter().string(from: selected), "2026-10-26T14:30:00Z")
        XCTAssertTrue(calendar.isDate(selected, inSameDayAs: day))
    }

    func testTomorrowKeepsTheLocalClockAcrossDaylightSavingTransition() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let today = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-03-07T15:30:00Z"))
        let tomorrow = try XCTUnwrap(JobScheduleSelection.day(today, offset: 1, calendar: calendar))
        let selected = try XCTUnwrap(JobScheduleSelection.date(on: tomorrow, hour: 10, minute: 30, calendar: calendar))

        XCTAssertEqual(ISO8601DateFormatter().string(from: selected), "2026-03-08T14:30:00Z")
        XCTAssertEqual(calendar.component(.hour, from: selected), 10)
    }

    func testArrivalWindowRemainsTwoElapsedHoursAcrossDaylightSavingTransition() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let start = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-03-08T06:30:00Z"))

        let end = try XCTUnwrap(JobScheduleSelection.twoHourWindowEnd(from: start, calendar: calendar))

        XCTAssertEqual(ISO8601DateFormatter().string(from: end), "2026-03-08T08:30:00Z")
        XCTAssertEqual(calendar.component(.hour, from: end), 4)
        XCTAssertEqual(calendar.component(.minute, from: end), 30)
    }

    func testScheduleRequestPreservesBothOccurrencesOfRepeatedFallBackTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let formatter = ISO8601DateFormatter()
        let firstOccurrence = try XCTUnwrap(formatter.date(from: "2026-11-01T05:30:00Z"))
        let secondOccurrence = try XCTUnwrap(formatter.date(from: "2026-11-01T06:30:00Z"))
        let job = try JSONDecoder().decode(JobRecord.self, from: Data(#"{"id":"00000000-0000-4000-8000-000000000001","organizationId":"00000000-0000-4000-8000-000000000002","customerId":"00000000-0000-4000-8000-000000000003","title":"Repair","status":"scheduled","scheduledFor":null,"createdAt":"2026-10-26T12:00:00Z","updatedAt":"2026-10-26T12:00:00Z"}"#.utf8))

        let firstRequest = try XCTUnwrap(JobScheduleSelection.request(
            for: job, selectedDate: firstOccurrence, timeZone: calendar.timeZone, calendar: calendar
        ))
        let secondRequest = try XCTUnwrap(JobScheduleSelection.request(
            for: job, selectedDate: secondOccurrence, timeZone: calendar.timeZone, calendar: calendar
        ))

        XCTAssertEqual(firstRequest.scheduledFor, "2026-11-01T05:30:00Z")
        XCTAssertEqual(secondRequest.scheduledFor, "2026-11-01T06:30:00Z")
    }

    func testScheduleRequestCarriesLocalZoneWindowAndPriorSchedule() throws {
        let job = try JSONDecoder().decode(JobRecord.self, from: Data(#"{"id":"00000000-0000-4000-8000-000000000001","organizationId":"00000000-0000-4000-8000-000000000002","customerId":"00000000-0000-4000-8000-000000000003","title":"Repair","status":"scheduled","scheduledFor":"2026-10-26T12:00:00Z","createdAt":"2026-10-26T12:00:00Z","updatedAt":"2026-10-26T12:00:00Z"}"#.utf8))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let day = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-27T12:00:00Z"))

        let request = try XCTUnwrap(JobScheduleSelection.request(
            for: job, selectedDate: try XCTUnwrap(JobScheduleSelection.date(on: day, hour: 10, minute: 30, calendar: calendar)),
            timeZone: calendar.timeZone, calendar: calendar
        ))
        let encoded = try JSONEncoder().encode(request)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertEqual(body["scheduledFor"] as? String, "2026-10-27T14:30:00Z")
        XCTAssertEqual(body["timeZone"] as? String, "America/New_York")
        XCTAssertEqual(body["arrivalWindowEndsAt"] as? String, "2026-10-27T16:30:00Z")
        XCTAssertEqual(body["expectedPriorScheduledFor"] as? String, "2026-10-26T12:00:00Z")
    }
}

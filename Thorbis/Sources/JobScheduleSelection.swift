import Foundation

enum JobScheduleSelection {
    static func day(_ date: Date, offset: Int, calendar: Calendar = .current) -> Date? {
        guard let target = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date)) else {
            return nil
        }
        return Self.date(on: target,
                    hour: calendar.component(.hour, from: date),
                    minute: calendar.component(.minute, from: date),
                    calendar: calendar)
    }

    static func date(on day: Date, hour: Int, minute: Int, calendar: Calendar = .current) -> Date? {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        let dayComponents = calendar.dateComponents([.era, .year, .month, .day], from: day)
        var components = DateComponents()
        components.era = dayComponents.era
        components.year = dayComponents.year
        components.month = dayComponents.month
        components.day = dayComponents.day
        components.hour = hour
        components.minute = minute
        components.second = 0

        guard let result = calendar.date(from: components) else { return nil }
        let resolved = calendar.dateComponents([.era, .year, .month, .day, .hour, .minute], from: result)
        guard resolved.era == components.era,
              resolved.year == components.year,
              resolved.month == components.month,
              resolved.day == components.day,
              resolved.hour == hour,
              resolved.minute == minute else { return nil }
        return result
    }

    static func minutePrecision(_ date: Date) -> Date {
        let minute = floor(date.timeIntervalSince1970 / 60) * 60
        return Date(timeIntervalSince1970: minute)
    }

    static func twoHourWindowEnd(from start: Date, calendar: Calendar = .current) -> Date? {
        calendar.date(byAdding: .hour, value: 2, to: start)
    }

    static func matchesPreset(_ date: Date, hour: Int, minute: Int, calendar: Calendar = .current) -> Bool {
        calendar.component(.hour, from: date) == hour && calendar.component(.minute, from: date) == minute
    }

    static func request(for job: JobRecord, selectedDate: Date, timeZone: TimeZone,
                        calendar: Calendar = .current) -> FieldScheduleRequest? {
        let start = minutePrecision(selectedDate)
        guard let end = twoHourWindowEnd(from: start, calendar: calendar) else { return nil }
        let formatter = ISO8601DateFormatter()
        return FieldScheduleRequest(
            scheduledFor: formatter.string(from: start),
            timeZone: timeZone.identifier,
            arrivalWindow: .endsAt(formatter.string(from: end)),
            expectedPrior: job.scheduledFor.map(FieldExpectedSchedule.at) ?? .unscheduled
        )
    }
}

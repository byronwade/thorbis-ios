import Foundation

/// ISO 8601 timestamps as the API writes them, with or without fractional seconds.
public enum Timestamp {
    public static func parse(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }

    public static func string(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

public enum Format {
    /// Cents to a localized currency string. Money is integer minor units end to end.
    public static func money(_ cents: Int, currency: String = "USD", locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.locale = locale
        let value = NSDecimalNumber(value: cents).dividing(by: 100)
        return formatter.string(from: value) ?? "\(currency) \(value)"
    }

    /// "Mike Reyes" → "MR". Never empty, so an avatar always has a mark.
    public static func initials(_ name: String) -> String {
        let marks = name.split(whereSeparator: { $0 == " " || $0 == "-" }).prefix(2).compactMap(\.first)
        let result = String(marks).uppercased()
        return result.isEmpty ? "?" : result
    }

    /// Status words. Status is a word first, colour second (design.thorbis.com Color).
    public static func status(_ status: JobStatus) -> String {
        switch status {
        case .scheduled: "Scheduled"
        case .dispatched: "Dispatched"
        case .enRoute: "En route"
        case .arrived: "Arrived"
        case .inProgress: "In progress"
        case .paused: "Paused"
        case .completed: "Completed"
        case .canceled: "Canceled"
        case .unknown: "Unknown"
        }
    }

    public static func status(_ status: EstimateStatus) -> String {
        switch status {
        case .draft: "Draft"
        case .sent: "Sent"
        case .approved: "Approved"
        case .declined: "Declined"
        case .unknown: "Unknown"
        }
    }

    public static func status(_ status: InvoiceStatus) -> String {
        switch status {
        case .draft: "Draft"
        case .issued: "Issued"
        case .paid: "Paid"
        case .void: "Void"
        case .unknown: "Unknown"
        }
    }

    public static func billingTerms(_ raw: String?) -> String? {
        switch raw {
        case "due_on_receipt": "Due on receipt"
        case "net_15": "Net 15"
        case "net_30": "Net 30"
        case "net_45": "Net 45"
        case "net_60": "Net 60"
        default: nil
        }
    }

    /// "Today", "Tomorrow", or a weekday and date in the device's calendar.
    public static func dayTitle(_ day: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(day, inSameDayAs: tomorrow) {
            return "Tomorrow"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEEMMMd")
        return formatter.string(from: day)
    }

    public static func time(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    public static func relative(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "" }
        #if canImport(Darwin)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: now)
        #else
        // Linux Foundation has no RelativeDateTimeFormatter; this path only serves `swift test`.
        let minutes = Int(now.timeIntervalSince(date) / 60)
        if abs(minutes) < 60 { return minutes >= 0 ? "\(minutes) min. ago" : "in \(-minutes) min." }
        let hours = minutes / 60
        if abs(hours) < 24 { return hours >= 0 ? "\(hours) hr. ago" : "in \(-hours) hr." }
        let days = hours / 24
        return days >= 0 ? "\(days) days ago" : "in \(-days) days"
        #endif
    }

    public static func bytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
}

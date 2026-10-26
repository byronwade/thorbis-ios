import Foundation

enum ScheduleRange: String, CaseIterable { case today = "Today", week = "Week", unscheduled = "Unscheduled" }

enum JobFiltering {
    static func date(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }

    static func schedule(_ jobs: [Job], range: ScheduleRange, now: Date = Date(), calendar: Calendar = .current) -> [Job] {
        jobs.filter { job in
            guard !["completed", "canceled"].contains(job.status) else { return false }
            guard let scheduled = date(job.scheduledFor) else { return range == .unscheduled }
            switch range {
            case .today: return calendar.isDate(scheduled, inSameDayAs: now)
            case .week: return calendar.dateInterval(of: .weekOfYear, for: now)?.contains(scheduled) ?? false
            case .unscheduled: return false
            }
        }.sorted { (date($0.scheduledFor) ?? .distantFuture) < (date($1.scheduledFor) ?? .distantFuture) }
    }

    static func jobs(_ jobs: [Job], assignedTo: String?, search: String) -> [Job] {
        jobs.filter { job in
            (assignedTo == nil || job.assignedToUserId == assignedTo) &&
            (search.isEmpty || job.title.localizedCaseInsensitiveContains(search) || job.shortRef.localizedCaseInsensitiveContains(search))
        }.sorted { (date($0.updatedAt) ?? .distantPast) > (date($1.updatedAt) ?? .distantPast) }
    }
}

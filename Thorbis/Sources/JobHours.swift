import Foundation

/// How long the drive and the work took, from the visit steps the tech already taps
/// (design.thorbis.com/job-hours, JH-01..JH-08). No clock: Drive is On my way to Mark arrived,
/// On site is Mark arrived to Wrap up, or to now while the job is still open. A missing tap is
/// named (JH-03), never filled in from the schedule.
struct JobHours: Equatable {
    /// The Time row's words.
    let line: String
    /// True when the line carries at least one duration, so it reads in mono (JH-02).
    let hasDuration: Bool
    /// Drive plus on site, in whole minutes, for the week view.
    let minutes: Int

    private static let openStatuses: Set<String> = ["arrived", "in_progress", "paused"]

    static func make(_ job: JobRecord, now: Date = Date()) -> JobHours? {
        make(status: job.status, enRouteAt: job.enRouteAt, arrivedAt: job.arrivedAt, completedAt: job.completedAt,
             wasPaused: job.pausedAt != nil || job.lastResumeAuditId != nil, now: now)
    }

    static func make(_ job: Job, now: Date = Date()) -> JobHours? {
        make(status: job.status, enRouteAt: job.enRouteAt, arrivedAt: job.arrivedAt, completedAt: job.completedAt,
             wasPaused: job.pausedAt != nil || job.lastResumeAuditId != nil, now: now)
    }

    /// Nil when the job hasn't started moving yet.
    static func make(status: String, enRouteAt: String?, arrivedAt: String?, completedAt: String?,
                     wasPaused: Bool, now: Date) -> JobHours? {
        let enRoute = JobFiltering.date(enRouteAt)
        let arrived = JobFiltering.date(arrivedAt)
        let completed = status == "completed" ? JobFiltering.date(completedAt) : nil
        let isOpen = openStatuses.contains(status)
        guard enRoute != nil || arrived != nil || completed != nil else { return nil }

        var parts: [String] = []
        var total = 0
        var durations = 0
        func span(_ name: String, _ interval: TimeInterval, soFar: Bool = false) {
            parts.append("\(name) \(duration(interval))\(soFar ? " so far" : "")")
            // Add the same rounded-down minutes the label shows, so totals match the parts.
            total += max(0, Int(interval / 60))
            durations += 1
        }

        if let enRoute, let arrived, arrived >= enRoute {
            span("Drive", arrived.timeIntervalSince(enRoute))
        } else if let enRoute, arrived == nil, status == "en_route" {
            span("Drive", now.timeIntervalSince(enRoute), soFar: true)
        } else if enRoute == nil, arrived != nil {
            parts.append("On my way not recorded")
        }

        if let arrived {
            if let completed, completed >= arrived {
                span("On site", completed.timeIntervalSince(arrived))
            } else if isOpen {
                span("On site", now.timeIntervalSince(arrived), soFar: true)
            } else if status == "completed" {
                parts.append("Wrap up not recorded")
            }
        } else if completed != nil || isOpen {
            parts.append("Arrived not recorded")
        }

        guard !parts.isEmpty else { return nil }
        // JH-04: pausing doesn't stop the count in this slice, so say so.
        if arrived != nil, wasPaused { parts.append("includes paused time") }
        return JobHours(line: parts.joined(separator: " · "), hasDuration: durations > 0, minutes: total)
    }

    /// Hours and minutes, rounded down to the minute: "0 h 24 min" (JH-02).
    static func duration(_ interval: TimeInterval) -> String {
        minutes(max(0, Int(interval / 60)))
    }

    static func minutes(_ total: Int) -> String {
        "\(total / 60) h \(total % 60) min"
    }
}

/// The technician's own week of job hours (JH-05): each day with its total, and each job under it.
struct JobWeek: Equatable {
    struct Row: Equatable, Identifiable {
        let id: String
        let title: String
        let reference: String
        let hours: JobHours
    }

    struct Day: Equatable, Identifiable {
        var id: Date { start }
        let start: Date
        let rows: [Row]
        var minutes: Int { rows.reduce(0) { $0 + $1.hours.minutes } }
    }

    let start: Date
    /// Monday (or the calendar's first weekday) through today; future days aren't listed.
    let days: [Day]
    var minutes: Int { days.reduce(0) { $0 + $1.minutes } }

    static func make(_ jobs: [Job], userID: String?, now: Date = Date(), calendar: Calendar = .current) -> JobWeek {
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        let mine = jobs.filter { userID != nil && $0.assignedToUserId == userID }
        var days: [Day] = []
        var day = weekStart
        while day <= now {
            let next = calendar.date(byAdding: .day, value: 1, to: day) ?? now
            let rows = mine.compactMap { job -> Row? in
                // A job belongs to the day the tech started toward it.
                guard let started = JobFiltering.date(job.enRouteAt) ?? JobFiltering.date(job.arrivedAt),
                      started >= day, started < next,
                      let hours = JobHours.make(job, now: now) else { return nil }
                return Row(id: job.id, title: job.title, reference: job.shortRef, hours: hours)
            }
            .sorted { $0.reference < $1.reference }
            days.append(Day(start: day, rows: rows))
            day = next
        }
        return JobWeek(start: weekStart, days: days)
    }
}

import Foundation

/// How long the drive and the work took, from the visit steps the tech already taps
/// (design.thorbis.com/job-hours, JH-01..JH-08). No clock: Drive is On my way to Mark arrived,
/// On site is Mark arrived to Wrap up, or to now while the job is still open. A missing tap is
/// named (JH-03), never filled in from the schedule.
struct JobHours: Equatable {
    /// The Time row's words, or nil when the job hasn't started moving yet.
    let line: String
    /// True when the line carries at least one duration, so it reads in mono (JH-02).
    let hasDuration: Bool

    private static let openStatuses: Set<String> = ["arrived", "in_progress", "paused"]

    static func make(_ job: JobRecord, now: Date = Date()) -> JobHours? {
        let enRoute = JobFiltering.date(job.enRouteAt)
        let arrived = JobFiltering.date(job.arrivedAt)
        let completed = job.status == "completed" ? JobFiltering.date(job.completedAt) : nil
        let isOpen = openStatuses.contains(job.status)
        guard enRoute != nil || arrived != nil || completed != nil else { return nil }

        var parts: [String] = []
        var durations = 0

        if let enRoute, let arrived, arrived >= enRoute {
            parts.append("Drive \(duration(arrived.timeIntervalSince(enRoute)))")
            durations += 1
        } else if let enRoute, arrived == nil, job.status == "en_route" {
            parts.append("Drive \(duration(now.timeIntervalSince(enRoute))) so far")
            durations += 1
        } else if enRoute == nil, arrived != nil {
            parts.append("On my way not recorded")
        }

        if let arrived {
            if let completed, completed >= arrived {
                parts.append("On site \(duration(completed.timeIntervalSince(arrived)))")
                durations += 1
            } else if isOpen {
                parts.append("On site \(duration(now.timeIntervalSince(arrived))) so far")
                durations += 1
            } else if job.status == "completed" {
                parts.append("Wrap up not recorded")
            }
        } else if completed != nil || isOpen {
            parts.append("Arrived not recorded")
        }

        guard !parts.isEmpty else { return nil }
        // JH-04: pausing doesn't stop the count in this slice, so say so.
        if arrived != nil, job.pausedAt != nil || job.lastResumeAuditId != nil {
            parts.append("includes paused time")
        }
        return JobHours(line: parts.joined(separator: " · "), hasDuration: durations > 0)
    }

    /// Hours and minutes, rounded down to the minute: "0 h 24 min" (JH-02).
    static func duration(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int(interval / 60))
        return "\(minutes / 60) h \(minutes % 60) min"
    }
}

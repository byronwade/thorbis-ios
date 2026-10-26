import Foundation

/// A day of scheduled work, in start-time order.
public struct AgendaDay: Hashable, Sendable, Identifiable {
    public let day: Date
    public let jobs: [Job]
    public var id: Date { day }
}

public enum Agenda {
    /// Groups active jobs by the local day they are scheduled for. Jobs without a
    /// time land in `unscheduled`; finished jobs are left out of the agenda.
    public static func build(
        _ jobs: [Job],
        assignedTo userId: String? = nil,
        calendar: Calendar = .current
    ) -> (days: [AgendaDay], unscheduled: [Job]) {
        let mine = jobs.filter { job in
            guard job.status.isActive else { return false }
            guard let userId else { return true }
            return job.assignedToUserId == userId
        }
        var byDay: [Date: [Job]] = [:]
        var unscheduled: [Job] = []
        for job in mine {
            guard let at = job.scheduledDate else { unscheduled.append(job); continue }
            byDay[calendar.startOfDay(for: at), default: []].append(job)
        }
        let days = byDay.keys.sorted().map { day in
            AgendaDay(day: day, jobs: byDay[day, default: []].sorted { ($0.scheduledDate ?? .distantFuture) < ($1.scheduledDate ?? .distantFuture) })
        }
        return (days, unscheduled.sorted { $0.updatedAt > $1.updatedAt })
    }

    /// The job to show as "Next up": work already underway first, then the
    /// earliest appointment from now on, then the most recent overdue one.
    public static func nextUp(_ jobs: [Job], now: Date = Date()) -> Job? {
        let active = jobs.filter(\.status.isActive)
        let underway: [JobStatus] = [.inProgress, .arrived, .enRoute, .paused]
        for status in underway {
            if let job = active.first(where: { $0.status == status }) { return job }
        }
        let timed = active.compactMap { job in job.scheduledDate.map { (job, $0) } }
        if let upcoming = timed.filter({ $0.1 >= now }).min(by: { $0.1 < $1.1 }) { return upcoming.0 }
        return timed.max(by: { $0.1 < $1.1 })?.0
    }
}

/// Status buckets for the Jobs list, in the order a dispatcher reads them.
public enum JobBucket: String, CaseIterable, Hashable, Sendable, Identifiable {
    case active, scheduled, paused, completed, canceled

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .active: "In the field"
        case .scheduled: "Scheduled"
        case .paused: "Paused"
        case .completed: "Completed"
        case .canceled: "Canceled"
        }
    }

    public static func of(_ status: JobStatus) -> JobBucket {
        switch status {
        case .enRoute, .arrived, .inProgress: .active
        case .scheduled, .dispatched, .unknown: .scheduled
        case .paused: .paused
        case .completed: .completed
        case .canceled: .canceled
        }
    }

    public static func group(_ jobs: [Job]) -> [JobGroup] {
        let grouped = Dictionary(grouping: jobs) { of($0.status) }
        return allCases.compactMap { bucket in
            guard let items = grouped[bucket], !items.isEmpty else { return nil }
            return JobGroup(bucket: bucket, jobs: items.sorted { $0.updatedAt > $1.updatedAt })
        }
    }
}

public struct JobGroup: Hashable, Sendable, Identifiable {
    public let bucket: JobBucket
    public let jobs: [Job]
    public var id: JobBucket { bucket }
}

public struct DirectorySection: Hashable, Sendable, Identifiable {
    public let letter: String
    public let customers: [Customer]
    public var id: String { letter }
}

/// Alphabetical sections for the customer directory.
public enum Directory {
    public static func sections(_ customers: [Customer], includeArchived: Bool = false) -> [DirectorySection] {
        let visible = customers.filter { includeArchived || !$0.isArchived }
        let grouped = Dictionary(grouping: visible) { customer -> String in
            guard let first = customer.name.trimmingCharacters(in: .whitespaces).first, first.isLetter else { return "#" }
            return String(first).uppercased()
        }
        return grouped.keys.sorted { lhs, rhs in
            if lhs == "#" { return false }
            if rhs == "#" { return true }
            return lhs < rhs
        }.map { key in
            DirectorySection(letter: key, customers: grouped[key, default: []].sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        }
    }
}

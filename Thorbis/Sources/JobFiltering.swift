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

    /// A list summary can call a visit upcoming only when it has a valid future time.
    static func nextScheduledVisit(_ jobs: [Job], customerID: String, now: Date = Date()) -> Job? {
        let candidates: [(job: Job, time: Date)] = jobs.compactMap { job in
            guard job.customerId == customerID,
                  ["scheduled", "dispatched"].contains(job.status),
                  let time = date(job.scheduledFor), time >= now else { return nil }
            return (job, time)
        }
        return candidates.min { left, right in
            left.time == right.time ? left.job.id < right.job.id : left.time < right.time
        }?.job
    }

    /// When there is no active or upcoming visit, keep an earlier open appointment visible.
    static func overdueScheduledVisit(_ jobs: [Job], customerID: String, now: Date = Date()) -> Job? {
        let candidates: [(job: Job, time: Date)] = jobs.compactMap { job in
            guard job.customerId == customerID,
                  ["scheduled", "dispatched"].contains(job.status),
                  let time = date(job.scheduledFor), time < now else { return nil }
            return (job, time)
        }
        return candidates.min { left, right in
            left.time == right.time ? left.job.id < right.job.id : left.time < right.time
        }?.job
    }

    /// Prefer an active job in the list summary; ties use ID so refresh order cannot change it.
    static func activeCustomerJob(_ jobs: [Job], customerID: String) -> Job? {
        let priorities = ["in_progress": 0, "arrived": 1, "en_route": 2, "paused": 3]
        return jobs.filter { $0.customerId == customerID && priorities[$0.status] != nil }.min { left, right in
            let leftPriority = priorities[left.status] ?? Int.max
            let rightPriority = priorities[right.status] ?? Int.max
            return leftPriority == rightPriority ? left.id < right.id : leftPriority < rightPriority
        }
    }

    /// The same customer-scoped summary drives both the customer list and the detail page.
    static func customerJobSummary(_ jobs: [Job], customerID: String, now: Date = Date()) -> (job: Job, heading: String, openCount: Int)? {
        let open = jobs.filter { $0.customerId == customerID && !["completed", "canceled"].contains($0.status) }
        guard !open.isEmpty else { return nil }
        if let active = activeCustomerJob(open, customerID: customerID) {
            return (active, "Open job", open.count)
        }
        if let next = nextScheduledVisit(open, customerID: customerID, now: now) {
            return (next, "Next visit", open.count)
        }
        if let past = overdueScheduledVisit(open, customerID: customerID, now: now) {
            return (past, "Past scheduled time", open.count)
        }
        guard let fallback = open.min(by: { $0.id < $1.id }) else { return nil }
        return (fallback, "Open job", open.count)
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

    /// The jobs board with the Display sheet applied: the `jobs(_:assignedTo:search:)` base, then
    /// hide completed/canceled when asked, keep only ticked statuses, and re-order. Pure so the
    /// Display sheet's filtering is unit-tested without the view.
    static func board(_ jobs: [Job], assignedTo: String?, search: String,
                      showCompleted: Bool, statuses: Set<String>,
                      ordering: DisplayOptions.Ordering) -> [Job] {
        var result = self.jobs(jobs, assignedTo: assignedTo, search: search)
        if !showCompleted { result = result.filter { !["completed", "canceled"].contains($0.status) } }
        if !statuses.isEmpty { result = result.filter { statuses.contains($0.status) } }
        switch ordering {
        case .recent: break // base is already most-recently-updated first
        case .scheduled:
            result.sort { (date($0.scheduledFor) ?? .distantFuture) < (date($1.scheduledFor) ?? .distantFuture) }
        case .name:
            result.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
        return result
    }

    static func myDay(_ jobs: [Job], actorID: String?, now: Date = Date(), calendar: Calendar = .current) -> [Job] {
        guard let actorID, !actorID.isEmpty else { return [] }
        return jobs.filter { job in
            guard job.assignedToUserId == actorID, let scheduled = date(job.scheduledFor) else { return false }
            return calendar.isDate(scheduled, inSameDayAs: now)
        }.sorted {
            let left = date($0.scheduledFor) ?? .distantFuture
            let right = date($1.scheduledFor) ?? .distantFuture
            return left == right ? $0.id < $1.id : left < right
        }
    }
}

enum MyDayRules {
    static func shouldShowEmptyState(isEmpty: Bool, isLoading: Bool, hasError: Bool) -> Bool {
        isEmpty && !isLoading && !hasError
    }

    static func canStartDriving(_ job: Job, canEdit: Bool) -> Bool {
        canEdit && job.status == "dispatched" && job.allowedTransitions?.contains("en_route") == true
    }
}

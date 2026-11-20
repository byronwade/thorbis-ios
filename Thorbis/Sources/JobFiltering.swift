import Foundation

enum ScheduleRange: String, CaseIterable { case today = "Today", week = "Week", unscheduled = "Unscheduled" }

/// Whose day Schedule shows. Technicians start on their own; office staff and owners on everyone's.
/// Either can switch, so nothing on the board is hidden from someone who could see it before.
enum ScheduleScope: String, CaseIterable {
    case mine = "Mine", everyone = "Everyone"

    static func initial(schedulesOwnDay: Bool, actorID: String?) -> ScheduleScope {
        guard let actorID, !actorID.isEmpty else { return .everyone }
        return schedulesOwnDay ? .mine : .everyone
    }

    /// The assignee to filter on. Unscheduled work is the office's queue, so it always shows everyone's.
    func assignee(_ actorID: String?, range: ScheduleRange) -> String? {
        guard self == .mine, range != .unscheduled, let actorID, !actorID.isEmpty else { return nil }
        return actorID
    }
}

/// One snapshot for customer rows, so each row only examines that customer's jobs.
struct CustomerJobGroups {
    private let groups: [String: [Job]]

    init(jobs: [Job]) {
        groups = jobs.reduce(into: [:]) { result, job in
            guard let customerID = job.customerId else { return }
            result[customerID, default: []].append(job)
        }
    }

    func jobs(for customerID: String) -> [Job] { groups[customerID] ?? [] }
}

enum JobFiltering {
    /// Server timestamps, with or without fractional seconds. Called inside list sorts, so the two
    /// formatters are made once (ISO8601DateFormatter is thread-safe; their options never change).
    static func date(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        // Lists filter and sort on these on every redraw; parsing a few thousand timestamps each
        // time was most of the wait when opening a large company. Each string is parsed once.
        parsedLock.lock()
        if let known = parsed[raw] { parsedLock.unlock(); return known.date }
        parsedLock.unlock()
        let date = isoFractional.date(from: raw) ?? isoPlain.date(from: raw)
        parsedLock.lock()
        if parsed.count >= 60_000 { parsed.removeAll(keepingCapacity: true) }
        parsed[raw] = Parsed(date: date)
        parsedLock.unlock()
        return date
    }
    private struct Parsed { let date: Date? }
    nonisolated(unsafe) private static var parsed: [String: Parsed] = [:]
    private static let parsedLock = NSLock()
    nonisolated(unsafe) static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    nonisolated(unsafe) static let isoPlain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

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

    static func schedule(_ jobs: [Job], range: ScheduleRange, assignedTo: String? = nil,
                         now: Date = Date(), calendar: Calendar = .current) -> [Job] {
        jobs.filter { job in
            guard !["completed", "canceled"].contains(job.status) else { return false }
            if let assignedTo, job.assignedToUserId != assignedTo { return false }
            guard let scheduled = date(job.scheduledFor) else { return range == .unscheduled }
            switch range {
            case .today: return calendar.isDate(scheduled, inSameDayAs: now)
            case .week: return calendar.dateInterval(of: .weekOfYear, for: now)?.contains(scheduled) ?? false
            case .unscheduled: return false
            }
        }.sortedByDate(\.scheduledFor, missing: .distantFuture)
    }

    static func jobs(_ jobs: [Job], assignedTo: String?, search: String) -> [Job] {
        jobs.filter { job in
            (assignedTo == nil || job.assignedToUserId == assignedTo) &&
            (search.isEmpty || job.title.localizedCaseInsensitiveContains(search) || job.shortRef.localizedCaseInsensitiveContains(search))
        }.sortedByDate(\.updatedAt, missing: .distantPast, descending: true)
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
            result = result.sortedByDate(\.scheduledFor, missing: .distantFuture)
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

/// The Jobs filter sheet's choices (Paper 20A) that go past `JobFiltering.board`: whose jobs, and
/// when they are booked. Pure, so the sheet's filtering is unit-tested without the view.
enum JobBoardFilter {
    /// "Assigned to" past Me: anyone, no one yet, or one tech from the roster.
    enum Who: Equatable {
        case anyone, unassigned
        case tech(String)
    }

    /// "Date": by the visit's booked time.
    enum When: String, CaseIterable {
        case any, today, week, overdue

        var label: String {
            switch self {
            case .any: "Any date"
            case .today: "Today"
            case .week: "This week"
            case .overdue: "Overdue"
            }
        }
    }

    /// How the board is ordered ("Sort by"), in the sheet's words.
    static func sortLabel(_ ordering: DisplayOptions.Ordering) -> String {
        switch ordering {
        case .scheduled: "Time"
        case .recent: "Updated"
        case .name: "Name"
        }
    }

    static let sortOrder: [DisplayOptions.Ordering] = [.scheduled, .recent, .name]

    /// Paper 20A's status chips. Each stands for a group of the server's statuses.
    struct StatusGroup: Identifiable {
        let title: String
        let statuses: Set<String>
        var id: String { title }
    }

    static let statusGroups: [StatusGroup] = [
        StatusGroup(title: "In progress", statuses: ["en_route", "arrived", "in_progress"]),
        StatusGroup(title: "Scheduled", statuses: ["scheduled", "dispatched"]),
        StatusGroup(title: "On hold", statuses: ["paused", "on_hold"]),
        StatusGroup(title: "Done", statuses: ["completed"]),
        StatusGroup(title: "Cancelled", statuses: ["canceled"])
    ]

    /// The groups a status filter touches, in the sheet's order.
    static func groups(in statuses: Set<String>) -> [StatusGroup] {
        statusGroups.filter { !$0.statuses.isDisjoint(with: statuses) }
    }

    /// A booked visit whose time has passed.
    static func isOverdue(_ job: Job, now: Date = Date()) -> Bool {
        guard ["scheduled", "dispatched"].contains(job.status), let time = JobFiltering.date(job.scheduledFor) else { return false }
        return time < now
    }

    /// "Pick dates": booked from the start of the first day to the end of the last, either order.
    static func isBooked(_ job: Job, from: Date, to: Date, calendar: Calendar = .current) -> Bool {
        guard let time = JobFiltering.date(job.scheduledFor) else { return false }
        let first = calendar.startOfDay(for: min(from, to))
        let lastDay = calendar.startOfDay(for: max(from, to))
        guard let end = calendar.date(byAdding: .day, value: 1, to: lastDay) else { return false }
        return time >= first && time < end
    }

    /// "Nov 16", or "Nov 16 – Nov 21" when the range spans more than one day.
    static func datesLabel(from: Date, to: Date, calendar: Calendar = .current) -> String {
        let first = min(from, to), last = max(from, to)
        let style = Date.FormatStyle().month(.abbreviated).day()
        if calendar.isDate(first, inSameDayAs: last) { return first.formatted(style) }
        return "\(first.formatted(style)) \u{2013} \(last.formatted(style))"
    }

    /// - Parameter dates: a picked range of days; when set it decides the date instead of `when`.
    static func apply(_ jobs: [Job], who: Who, when: When, dates: (from: Date, to: Date)? = nil,
                      now: Date = Date(), calendar: Calendar = .current) -> [Job] {
        jobs.filter { job in
            switch who {
            case .anyone: break
            case .unassigned: if job.assignedToUserId != nil { return false }
            case .tech(let userID): if job.assignedToUserId != userID { return false }
            }
            if let dates { return isBooked(job, from: dates.from, to: dates.to, calendar: calendar) }
            switch when {
            case .any:
                return true
            case .today:
                guard let time = JobFiltering.date(job.scheduledFor) else { return false }
                return calendar.isDate(time, inSameDayAs: now)
            case .week:
                guard let time = JobFiltering.date(job.scheduledFor) else { return false }
                return calendar.dateInterval(of: .weekOfYear, for: now)?.contains(time) ?? false
            case .overdue:
                return isOverdue(job, now: now)
            }
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

extension Array where Element == Job {
    /// Sorts by a server timestamp, parsing each one once instead of twice per comparison.
    func sortedByDate(_ key: KeyPath<Job, String?>, missing: Date, descending: Bool = false) -> [Job] {
        map { ($0, JobFiltering.date($0[keyPath: key]) ?? missing) }
            .sorted { descending ? $0.1 > $1.1 : $0.1 < $1.1 }
            .map(\.0)
    }
}

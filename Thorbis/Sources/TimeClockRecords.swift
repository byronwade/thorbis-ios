import CryptoKit
import Foundation

/// A person's own hours, kept on this phone. There is no time route on the server yet, so nothing
/// here is sent to the office, dispatch or payroll, and the screens say so.
struct TimeClockBreak: Codable, Identifiable, Equatable, Hashable {
    let id: String
    var start: Date
    /// Nil while the break is running.
    var end: Date?
    /// The length the person chose when the break began ("Lunch · 30 min"), if any.
    var plannedMinutes: Int?

    init(id: String = UUID().uuidString, start: Date, end: Date? = nil, plannedMinutes: Int? = nil) {
        self.id = id; self.start = start; self.end = end; self.plannedMinutes = plannedMinutes
    }
}

struct TimeClockEntry: Codable, Identifiable, Equatable, Hashable {
    /// Paper 27B's reasons for a changed punch.
    enum Reason: String, Codable, CaseIterable, Hashable {
        case forgot, phoneDied, other

        var label: String {
            switch self {
            case .forgot: "Forgot"
            case .phoneDied: "Phone died"
            case .other: "Other"
            }
        }
    }

    /// Why a punch was changed by hand, and when.
    struct Change: Codable, Equatable, Hashable {
        var reason: Reason
        var note: String?
        var changedAt: Date
    }

    let id: String
    /// Stored, never a running counter: elapsed time is always worked out from this, so a clock-in
    /// survives the app being closed.
    var clockIn: Date
    /// Nil while clocked in.
    var clockOut: Date?
    var breaks: [TimeClockBreak]
    var change: Change?

    init(id: String = UUID().uuidString, clockIn: Date, clockOut: Date? = nil,
         breaks: [TimeClockBreak] = [], change: Change? = nil) {
        self.id = id; self.clockIn = clockIn; self.clockOut = clockOut
        self.breaks = breaks; self.change = change
    }

    var isOpen: Bool { clockOut == nil }
    /// The break that is running now, if this entry is still open.
    var openBreak: TimeClockBreak? { isOpen ? breaks.last { $0.end == nil } : nil }
}

/// A time-off request the person wrote. It is kept, not sent: there is no office to receive it.
struct TimeClockTimeOff: Codable, Identifiable, Equatable, Hashable {
    enum Kind: String, Codable, CaseIterable, Hashable {
        case vacation, sick, personal

        var label: String {
            switch self {
            case .vacation: "Vacation"
            case .sick: "Sick"
            case .personal: "Personal"
            }
        }
    }

    /// The only status a request can have on this phone.
    static let statusLabel = "Not sent \u{2014} kept on this phone"

    let id: String
    var from: Date
    var to: Date
    var allDay: Bool
    var kind: Kind
    var note: String?
    let createdAt: Date

    init(id: String = UUID().uuidString, from: Date, to: Date, allDay: Bool = true,
         kind: Kind = .vacation, note: String? = nil, createdAt: Date = Date()) {
        self.id = id; self.from = from; self.to = to; self.allDay = allDay
        self.kind = kind; self.note = note; self.createdAt = createdAt
    }
}

enum TimeClockProblem: LocalizedError, Equatable {
    case invalidIdentity
    case alreadyClockedIn
    case notClockedIn
    case alreadyOnBreak
    case notOnBreak
    case endsBeforeStart
    case inTheFuture
    case breakTooLong
    case overlapsAnotherEntry
    case notFound
    case timeOffEndsBeforeStart

    var errorDescription: String? {
        switch self {
        case .invalidIdentity: "Sign in to a workspace to keep hours on this phone."
        case .alreadyClockedIn: "You are already clocked in."
        case .notClockedIn: "You are not clocked in."
        case .alreadyOnBreak: "You are already on break."
        case .notOnBreak: "You are not on break."
        case .endsBeforeStart: "Clock out has to be after clock in."
        case .inTheFuture: "A punch can\u{2019}t be in the future."
        case .breakTooLong: "The break is longer than the time between clock in and clock out."
        case .overlapsAnotherEntry: "These times overlap another entry."
        case .notFound: "That entry is no longer on this phone."
        case .timeOffEndsBeforeStart: "The last day has to be on or after the first day."
        }
    }
}

/// All the arithmetic, with the clock and the calendar passed in so it can be tested.
enum TimeClockMath {
    /// An entry still open this long after its clock-in is treated as a missed clock-out.
    static let missedAfter: TimeInterval = 16 * 3600
    /// The clock-out offered for a missed one: this long after the clock-in, never past now.
    static let assumedShift: TimeInterval = 8 * 3600
    /// The week's regular hours; anything over is shown as "Over 40 h".
    static let regularWeek: TimeInterval = 40 * 3600

    /// From clock-in to clock-out, or to `now` while open. Nil when that is not a forward span.
    static func span(_ entry: TimeClockEntry, now: Date) -> DateInterval? {
        let end = entry.clockOut ?? now
        guard end > entry.clockIn else { return nil }
        return DateInterval(start: entry.clockIn, end: end)
    }

    /// The entry's breaks, clipped to the entry and merged where they touch, so a break is never
    /// taken off twice and never takes off time outside the shift.
    static func breakSpans(_ entry: TimeClockEntry, now: Date) -> [DateInterval] {
        guard let span = span(entry, now: now) else { return [] }
        let clipped: [DateInterval] = entry.breaks.compactMap { pause in
            let start = max(pause.start, span.start)
            let end = min(pause.end ?? span.end, span.end)
            return end > start ? DateInterval(start: start, end: end) : nil
        }.sorted { $0.start < $1.start }
        var merged: [DateInterval] = []
        for next in clipped {
            if let last = merged.last, next.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, next.end))
            } else {
                merged.append(next)
            }
        }
        return merged
    }

    private static func overlap(_ interval: DateInterval, _ window: DateInterval?) -> TimeInterval {
        guard let window else { return interval.duration }
        return interval.intersection(with: window)?.duration ?? 0
    }

    /// Unpaid break time, in seconds; only the part inside `window` when one is given.
    static func breakSeconds(_ entry: TimeClockEntry, now: Date, within window: DateInterval? = nil) -> TimeInterval {
        breakSpans(entry, now: now).reduce(0) { $0 + overlap($1, window) }
    }

    /// Time worked: the span less its breaks. With a `window` (a day or a week) only the part that
    /// falls inside it counts, so a shift across midnight is split between the two days.
    static func workedSeconds(_ entry: TimeClockEntry, now: Date, within window: DateInterval? = nil) -> TimeInterval {
        guard let span = span(entry, now: now) else { return 0 }
        return max(0, overlap(span, window) - breakSeconds(entry, now: now, within: window))
    }

    static func workedSeconds(_ entries: [TimeClockEntry], now: Date, within window: DateInterval? = nil) -> TimeInterval {
        entries.reduce(0) { $0 + workedSeconds($1, now: now, within: window) }
    }

    /// Midnight to the next midnight in `calendar` (23 or 25 hours when the clocks change).
    static func dayInterval(_ date: Date, calendar: Calendar) -> DateInterval {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return DateInterval(start: start, end: end)
    }

    /// The week holding `date`, starting on the calendar's own first weekday.
    static func weekInterval(containing date: Date, calendar: Calendar) -> DateInterval {
        if let week = calendar.dateInterval(of: .weekOfYear, for: date) { return week }
        let start = calendar.startOfDay(for: date)
        return DateInterval(start: start, duration: 7 * 86_400)
    }

    /// The week `weeks` before or after the one holding `date`.
    static func weekInterval(containing date: Date, offsetBy weeks: Int, calendar: Calendar) -> DateInterval {
        let base = weekInterval(containing: date, calendar: calendar)
        guard weeks != 0, let moved = calendar.date(byAdding: .weekOfYear, value: weeks, to: base.start) else { return base }
        return weekInterval(containing: moved, calendar: calendar)
    }

    /// One day of a week: what was worked in it and the first and last punch that fall in it.
    struct Day: Identifiable, Equatable {
        let date: Date
        let entries: [TimeClockEntry]
        let seconds: TimeInterval
        let breakSeconds: TimeInterval
        /// The earliest start inside the day (midnight when a shift ran in from the day before).
        let firstIn: Date?
        /// The latest end inside the day; nil while an entry in the day is still open.
        let lastOut: Date?
        let isOpen: Bool
        let missedClockOut: Bool
        var id: Date { date }
    }

    static func days(_ entries: [TimeClockEntry], in week: DateInterval, now: Date, calendar: Calendar) -> [Day] {
        var result: [Day] = []
        var cursor = week.start
        while cursor < week.end {
            let day = dayInterval(cursor, calendar: calendar)
            let touching = entries.filter { entry in
                guard let span = span(entry, now: now), let part = span.intersection(with: day) else { return false }
                return part.duration > 0
            }.sorted { $0.clockIn < $1.clockIn }
            let open = touching.contains { $0.isOpen && now >= day.start && now < day.end }
            let firstIn = touching.map { max($0.clockIn, day.start) }.min()
            let lastOut = open ? nil : touching.compactMap { entry in
                span(entry, now: now).map { min($0.end, day.end) }
            }.max()
            result.append(Day(date: day.start, entries: touching,
                              seconds: workedSeconds(touching, now: now, within: day),
                              breakSeconds: touching.reduce(0) { $0 + breakSeconds($1, now: now, within: day) },
                              firstIn: firstIn, lastOut: lastOut, isOpen: open,
                              missedClockOut: touching.contains { isMissedClockOut($0, now: now) }))
            cursor = day.end
        }
        return result
    }

    static func overtimeSeconds(weekSeconds: TimeInterval) -> TimeInterval {
        max(0, weekSeconds - regularWeek)
    }

    /// Still open long after the clock-in: the person most likely left without clocking out.
    static func isMissedClockOut(_ entry: TimeClockEntry, now: Date) -> Bool {
        entry.isOpen && now.timeIntervalSince(entry.clockIn) >= missedAfter
    }

    /// The clock-out offered when fixing a missed one: the start of a break that never ended, or
    /// eight hours after the clock-in. Never later than now.
    static func suggestedClockOut(_ entry: TimeClockEntry, now: Date) -> Date {
        if let pause = entry.openBreak, pause.start > entry.clockIn { return min(pause.start, now) }
        return min(entry.clockIn.addingTimeInterval(assumedShift), now)
    }

    /// Closes an entry at `clockOut`, with the reason. A break still running ends there; breaks
    /// that began after it are dropped.
    static func fixingClockOut(_ entry: TimeClockEntry, at clockOut: Date, reason: TimeClockEntry.Reason,
                               note: String?, now: Date) throws -> TimeClockEntry {
        guard clockOut > entry.clockIn else { throw TimeClockProblem.endsBeforeStart }
        guard clockOut <= now else { throw TimeClockProblem.inTheFuture }
        var fixed = entry
        fixed.clockOut = clockOut
        fixed.breaks = closingBreaks(entry.breaks, at: clockOut)
        fixed.change = TimeClockEntry.Change(reason: reason, note: trimmed(note), changedAt: now)
        return fixed
    }

    /// Ends any running break at `end` and drops breaks that start at or after it.
    static func closingBreaks(_ breaks: [TimeClockBreak], at end: Date) -> [TimeClockBreak] {
        breaks.compactMap { pause in
            guard pause.start < end else { return nil }
            var closed = pause
            closed.end = min(pause.end ?? end, end)
            return closed
        }
    }

    /// Replaces the entry's breaks with one of `minutes`, placed in the middle of the shift. Used
    /// when a break's length is typed afterwards and its real times are not known.
    static func settingBreak(minutes: Int, on entry: TimeClockEntry, now: Date) throws -> TimeClockEntry {
        var next = entry
        guard minutes > 0 else { next.breaks = []; return next }
        guard let span = span(entry, now: now) else { throw TimeClockProblem.endsBeforeStart }
        let length = TimeInterval(minutes * 60)
        guard length < span.duration else { throw TimeClockProblem.breakTooLong }
        let start = span.start.addingTimeInterval((span.duration - length) / 2)
        next.breaks = [TimeClockBreak(start: start, end: start.addingTimeInterval(length))]
        return next
    }

    /// A finished entry must run forward, end by now, and not overlap another entry.
    static func validate(_ entry: TimeClockEntry, among others: [TimeClockEntry], now: Date) throws {
        guard entry.clockIn <= now else { throw TimeClockProblem.inTheFuture }
        if let out = entry.clockOut {
            guard out > entry.clockIn else { throw TimeClockProblem.endsBeforeStart }
            guard out <= now else { throw TimeClockProblem.inTheFuture }
        }
        guard let mine = span(entry, now: max(now, entry.clockIn.addingTimeInterval(1))) else { return }
        for other in others where other.id != entry.id {
            guard let theirs = span(other, now: max(now, other.clockIn.addingTimeInterval(1))),
                  let shared = mine.intersection(with: theirs) else { continue }
            if shared.duration > 0 { throw TimeClockProblem.overlapsAnotherEntry }
        }
    }

    /// How many calendar days a request covers, first and last included.
    static func timeOffDays(_ request: TimeClockTimeOff, calendar: Calendar) -> Int {
        let first = calendar.startOfDay(for: request.from)
        let last = calendar.startOfDay(for: request.to)
        return max(1, (calendar.dateComponents([.day], from: first, to: last).day ?? 0) + 1)
    }

    static func timeOffCovers(_ request: TimeClockTimeOff, day: Date, calendar: Calendar) -> Bool {
        let target = calendar.startOfDay(for: day)
        return target >= calendar.startOfDay(for: request.from) && target <= calendar.startOfDay(for: request.to)
    }

    private static func trimmed(_ text: String?) -> String? {
        guard let value = text?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    // MARK: Words

    /// "2:14:36", for the running total; "12:40" under an hour when `short`.
    static func clockLabel(_ seconds: TimeInterval, short: Bool = false) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
        // A clock left running for days (never clocked out) reads in days, not "471:13:58".
        if hours >= 24 { return "\(hours / 24)d \(hours % 24)h" }
        if short && hours == 0 { return String(format: "%d:%02d", minutes, secs) }
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }

    /// "2h 14m", "30m", "8h".
    static func durationLabel(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int((seconds / 60).rounded(.down)))
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(rest)m" }
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    /// Hours to one decimal, as a timesheet shows them: "8.0", "18.4".
    static func decimalHours(_ seconds: TimeInterval) -> String {
        String(format: "%.1f", max(0, seconds) / 3600)
    }

    /// "30 min", "1 h", "1 h 30 min", for a select.
    static func minutesLabel(_ minutes: Int) -> String {
        guard minutes > 0 else { return "None" }
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }
}

private struct TimeClockBook: Codable {
    var entries: [TimeClockEntry] = []
    var timeOff: [TimeClockTimeOff] = []
}

/// One protected JSON file for each exact person and workspace pair, written atomically.
/// Hours are personal: another person signed in on the same phone, or the same person in another
/// workspace, opens a different file.
@MainActor
final class TimeClockStore {
    let fileURL: URL
    private var book: TimeClockBook

    /// Newest first.
    var entries: [TimeClockEntry] { book.entries.sorted { $0.clockIn > $1.clockIn } }
    var timeOff: [TimeClockTimeOff] { book.timeOff.sorted { $0.from < $1.from } }
    /// The entry that is running now.
    var active: TimeClockEntry? { book.entries.filter(\.isOpen).max { $0.clockIn < $1.clockIn } }

    private static func partitionURL(userID: String, organizationID: String, directory: URL?) throws -> URL {
        let user = userID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let organization = organizationID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !user.isEmpty, !organization.isEmpty else { throw TimeClockProblem.invalidIdentity }
        let root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TimeClockBooks", isDirectory: true)
        let partition = "v1|\(user.count):\(user)|\(organization.count):\(organization)"
        let digest = SHA256.hash(data: Data(partition.utf8)).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent("\(digest).json")
    }

    init(userID: String, organizationID: String, directory: URL? = nil) throws {
        fileURL = try Self.partitionURL(userID: userID, organizationID: organizationID, directory: directory)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            book = try JSONDecoder().decode(TimeClockBook.self, from: Data(contentsOf: fileURL))
        } else {
            book = TimeClockBook()
        }
    }

    private func commit(_ next: TimeClockBook) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                    attributes: [.protectionKey: FileProtectionType.complete])
        try JSONEncoder().encode(next).write(to: fileURL, options: .atomic)
        try manager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: fileURL.path)
        book = next
    }

    private func replacing(_ entry: TimeClockEntry) -> TimeClockBook {
        var next = book
        next.entries.removeAll { $0.id == entry.id }
        next.entries.append(entry)
        return next
    }

    @discardableResult
    func clockIn(at date: Date = Date()) throws -> TimeClockEntry {
        guard active == nil else { throw TimeClockProblem.alreadyClockedIn }
        let entry = TimeClockEntry(clockIn: date)
        try TimeClockMath.validate(entry, among: book.entries, now: date)
        try commit(replacing(entry))
        return entry
    }

    /// Ends the running entry; a break still running ends with it.
    @discardableResult
    func clockOut(at date: Date = Date()) throws -> TimeClockEntry {
        guard var entry = active else { throw TimeClockProblem.notClockedIn }
        guard date > entry.clockIn else { throw TimeClockProblem.endsBeforeStart }
        entry.clockOut = date
        entry.breaks = TimeClockMath.closingBreaks(entry.breaks, at: date)
        try commit(replacing(entry))
        return entry
    }

    func startBreak(at date: Date = Date(), plannedMinutes: Int? = nil) throws {
        guard var entry = active else { throw TimeClockProblem.notClockedIn }
        guard entry.openBreak == nil else { throw TimeClockProblem.alreadyOnBreak }
        entry.breaks.append(TimeClockBreak(start: max(date, entry.clockIn), plannedMinutes: plannedMinutes))
        try commit(replacing(entry))
    }

    func endBreak(at date: Date = Date()) throws {
        guard var entry = active else { throw TimeClockProblem.notClockedIn }
        guard let index = entry.breaks.lastIndex(where: { $0.end == nil }) else { throw TimeClockProblem.notOnBreak }
        entry.breaks[index].end = max(date, entry.breaks[index].start)
        try commit(replacing(entry))
    }

    /// Adds a punch written afterwards, or saves a change to one.
    func save(_ entry: TimeClockEntry, now: Date = Date()) throws {
        try TimeClockMath.validate(entry, among: book.entries, now: now)
        try commit(replacing(entry))
    }

    func fixMissedClockOut(_ id: String, at clockOut: Date, reason: TimeClockEntry.Reason,
                           note: String?, now: Date = Date()) throws {
        guard let entry = book.entries.first(where: { $0.id == id }) else { throw TimeClockProblem.notFound }
        let fixed = try TimeClockMath.fixingClockOut(entry, at: clockOut, reason: reason, note: note, now: now)
        try save(fixed, now: now)
    }

    func removeEntry(_ id: String) throws {
        var next = book
        next.entries.removeAll { $0.id == id }
        try commit(next)
    }

    func save(_ request: TimeClockTimeOff) throws {
        guard request.to >= request.from else { throw TimeClockProblem.timeOffEndsBeforeStart }
        var next = book
        next.timeOff.removeAll { $0.id == request.id }
        next.timeOff.append(request)
        try commit(next)
    }

    func removeTimeOff(_ id: String) throws {
        var next = book
        next.timeOff.removeAll { $0.id == id }
        try commit(next)
    }
}

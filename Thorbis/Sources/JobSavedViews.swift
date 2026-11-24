import Foundation

// Saved job views (Paper 20B / 20C): the server's persisted ViewDefinitions for the `jobs`
// resource (GET/POST /v1/views, /v1/views/{id}/archive|favorite|unfavorite, /v1/views/membership),
// read onto the filters the Jobs screen already has. A view the phone cannot express is listed
// with the reason and never applied.

// MARK: - Wire types

/// Any JSON value. A view's filter is kept exactly as the server sent it, so renaming a view sends
/// the same filter back even when the phone cannot read every part of it.
indirect enum SavedViewJSON: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([SavedViewJSON])
    case object([String: SavedViewJSON])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([SavedViewJSON].self) { self = .array(value) }
        else if let value = try? container.decode([String: SavedViewJSON].self) { self = .object(value) }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not JSON") }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    subscript(key: String) -> SavedViewJSON? {
        if case .object(let fields) = self { return fields[key] }
        return nil
    }
    var text: String? { if case .string(let value) = self { return value }; return nil }
    var list: [SavedViewJSON]? { if case .array(let value) = self { return value }; return nil }
}

struct SavedViewSort: Codable, Equatable, Sendable {
    let field: String
    let direction: String
}

/// One persisted view as GET /v1/views lists it (the server's ViewDefinition plus `source`/`rowId`).
struct SavedJobView: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let resourceId: String
    var label: String
    let description: String?
    /// "personal" or "organization".
    let visibility: String
    let layout: String
    let filter: SavedViewJSON
    let sort: [SavedViewSort]
    let groupBy: String?
    let columns: [String]
    var status: String
    var revision: Int
    let createdBy: String?

    private enum CodingKeys: String, CodingKey {
        case id, resourceId, label, description, visibility, layout, filter, sort, groupBy, columns, status, revision, createdBy
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        resourceId = try values.decode(String.self, forKey: .resourceId)
        label = try values.decode(String.self, forKey: .label)
        filter = try values.decode(SavedViewJSON.self, forKey: .filter)
        description = try? values.decodeIfPresent(String.self, forKey: .description)
        visibility = (try? values.decodeIfPresent(String.self, forKey: .visibility)) ?? ""
        layout = (try? values.decodeIfPresent(String.self, forKey: .layout)) ?? "list"
        sort = (try? values.decodeIfPresent([SavedViewSort].self, forKey: .sort)) ?? []
        groupBy = try? values.decodeIfPresent(String.self, forKey: .groupBy)
        columns = (try? values.decodeIfPresent([String].self, forKey: .columns)) ?? []
        status = (try? values.decodeIfPresent(String.self, forKey: .status)) ?? "active"
        revision = (try? values.decodeIfPresent(Int.self, forKey: .revision)) ?? 1
        createdBy = try? values.decodeIfPresent(String.self, forKey: .createdBy)
    }

    init(id: String, resourceId: String = "jobs", label: String, description: String? = nil,
         visibility: String = "personal", layout: String = "list", filter: SavedViewJSON,
         sort: [SavedViewSort] = [], groupBy: String? = nil, columns: [String] = [],
         status: String = "active", revision: Int = 1, createdBy: String? = nil) {
        self.id = id; self.resourceId = resourceId; self.label = label; self.description = description
        self.visibility = visibility; self.layout = layout; self.filter = filter; self.sort = sort
        self.groupBy = groupBy; self.columns = columns; self.status = status; self.revision = revision
        self.createdBy = createdBy
    }

    var isArchived: Bool { status == "archived" }
}

/// A page of views. One entry the phone cannot read is skipped, not the whole list.
struct SavedJobViewPage: Decodable {
    let items: [SavedJobView]
    let nextCursor: String?

    private enum CodingKeys: String, CodingKey { case items, nextCursor }
    private struct Entry: Decodable {
        let view: SavedJobView?
        init(from decoder: Decoder) throws { view = try? SavedJobView(from: decoder) }
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        items = try values.decode([Entry].self, forKey: .items).compactMap(\.view)
        nextCursor = try? values.decodeIfPresent(String.self, forKey: .nextCursor)
    }
}

/// GET /v1/views/membership: the person's favourites (and opening defaults) for one resource.
struct SavedViewMembership: Decodable, Equatable {
    let favorites: [String]
    let personalDefault: String?
    let organizationDefault: String?

    private enum CodingKeys: String, CodingKey { case favorites, personalDefault, organizationDefault }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        favorites = (try? values.decodeIfPresent([String].self, forKey: .favorites)) ?? []
        personalDefault = try? values.decodeIfPresent(String.self, forKey: .personalDefault)
        organizationDefault = try? values.decodeIfPresent(String.self, forKey: .organizationDefault)
    }
}

/// POST /v1/views (the server's saveViewInputSchema). `expectedRevision` is sent only when
/// changing a view that exists; absent keys are left out, as the schema wants.
struct SavedJobViewSave: Encodable, Equatable {
    let id: String
    let resourceId: String
    let label: String
    var description: String? = nil
    let visibility: String
    var layout: String? = nil
    let filter: SavedViewJSON
    var sort: [SavedViewSort]? = nil
    var groupBy: String? = nil
    var columns: [String]? = nil
    var expectedRevision: Int? = nil
}

// MARK: - The phone's job filters, as one value

/// Everything the Jobs filter sheet can narrow by. The Jobs screen reads its own state into this
/// and takes it back when a view is applied.
struct JobBoardChoices: Equatable {
    enum Assignee: Equatable {
        case anyone, unassigned
        case user(String)
    }
    /// A range of whole days, both ends included, by the visit's booked time.
    struct Days: Equatable {
        var from: Date
        var to: Date
    }

    var assignee: Assignee = .anyone
    /// Empty means every status.
    var statuses: Set<String> = []
    /// "Hiding done": completed and cancelled jobs are left out.
    var hidesDone = false
    var ordering: DisplayOptions.Ordering = .recent
    var days: Days? = nil
    /// Today / This week / Overdue. These move with the calendar, so a view cannot hold them.
    var when: JobBoardFilter.When = .any

    /// Nothing narrowed: the whole board in its usual order.
    var isEverything: Bool { canonical == JobBoardChoices() }

    /// These choices as a saved view would hand them back, so two ways of saying the same thing
    /// (every open status ticked, or "Hiding done") compare equal.
    var canonical: JobBoardChoices {
        guard case .success(let written) = JobSavedViewMapping.write(self),
              case .choices(let read) = JobSavedViewMapping.read(filter: written.filter, sort: written.sort) else { return normalized }
        return read
    }

    /// The same choices in the server's words: only statuses the server has, and whole days.
    var normalized: JobBoardChoices {
        var copy = self
        copy.statuses = statuses.intersection(JobSavedViewMapping.serverStatuses)
        if let days {
            let calendar = Calendar.current
            copy.days = Days(from: calendar.startOfDay(for: min(days.from, days.to)),
                             to: calendar.startOfDay(for: max(days.from, days.to)))
            copy.when = .any
        }
        return copy
    }

    /// The jobs these choices show, the way the Jobs screen filters them.
    func jobs(from all: [Job], now: Date = Date(), calendar: Calendar = .current) -> [Job] {
        var assignedTo: String?
        var who = JobBoardFilter.Who.anyone
        switch assignee {
        case .anyone: break
        case .unassigned: who = .unassigned
        case .user(let id): assignedTo = id
        }
        let board = JobFiltering.board(all, assignedTo: assignedTo, search: "", showCompleted: !hidesDone,
                                       statuses: statuses, ordering: ordering)
        return JobBoardFilter.apply(board, who: who, when: when, dates: days.map { (from: $0.from, to: $0.to) },
                                    now: now, calendar: calendar)
    }
}

// MARK: - Mapping between a view's filter and the phone's filters

enum JobSavedViewMapping {
    static let resourceID = "jobs"
    /// The server's job statuses (jobStatusSchema).
    static let serverStatuses: Set<String> = ["scheduled", "dispatched", "en_route", "arrived", "in_progress",
                                              "paused", "completed", "canceled"]
    static let doneStatuses: Set<String> = ["completed", "canceled"]

    enum Reading: Equatable {
        case choices(JobBoardChoices)
        /// A sentence for the view's row: what it uses that the phone cannot filter by.
        case unsupported(String)
    }

    private struct Unreadable: Error { let reason: String }
    private struct Condition {
        let field: String
        let op: String
        let value: SavedViewJSON?
    }

    private static let fieldLabels: [String: String] = [
        "jobs.title": "job title", "jobs.customer_id": "customer", "jobs.estimate_id": "estimate",
        "jobs.estimate_revision_number": "estimate revision", "jobs.location_id": "location",
        "jobs.team_id": "team", "jobs.created_at": "created date", "jobs.updated_at": "updated date",
        "jobs.board_technician_id": "board technician", "jobs.id": "one job\u{2019}s ID"
    ]

    /// Reads a view onto the phone's filters, or says why it cannot.
    static func read(filter: SavedViewJSON, sort: [SavedViewSort], calendar: Calendar = .current) -> Reading {
        do {
            guard let root = filter["root"] else { throw Unreadable(reason: "This view\u{2019}s filter could not be read.") }
            var choices = JobBoardChoices()
            var allowed: Set<String>?
            var sawAssignee = false
            var after: Date?, before: Date?
            for condition in try conditions(in: root, depth: 0) {
                switch condition.field {
                case "jobs.id":
                    // The server's "everything" filter: every job has an ID.
                    guard condition.op == "is_not_empty" else { throw unsupported(field: condition.field) }
                case "jobs.status":
                    let named = try statuses(condition)
                    let set: Set<String>
                    switch condition.op {
                    case "is", "is_any_of": set = named
                    case "is_not", "is_none_of": set = serverStatuses.subtracting(named)
                    default: throw Unreadable(reason: "Uses a status rule this phone can\u{2019}t apply.")
                    }
                    allowed = allowed.map { $0.intersection(set) } ?? set
                case "jobs.assigned_to_user_id":
                    guard !sawAssignee else { throw Unreadable(reason: "Has more than one technician rule; this phone filters by one.") }
                    sawAssignee = true
                    switch condition.op {
                    case "is_empty":
                        choices.assignee = .unassigned
                    case "is":
                        guard let id = condition.value?.text, !id.isEmpty else { throw Unreadable(reason: "This view\u{2019}s technician could not be read.") }
                        choices.assignee = .user(id)
                    case "is_any_of":
                        let ids = (condition.value?.list ?? []).compactMap(\.text)
                        guard ids.count == 1, let id = ids.first, !id.isEmpty else {
                            throw Unreadable(reason: "Shows several technicians\u{2019} jobs; this phone filters by one.")
                        }
                        choices.assignee = .user(id)
                    default:
                        throw Unreadable(reason: "Shows every assigned job; this phone filters by one technician or none.")
                    }
                case "jobs.scheduled_for":
                    switch condition.op {
                    case "after", "before":
                        guard let time = JobFiltering.date(condition.value?.text) else { throw Unreadable(reason: "This view\u{2019}s dates could not be read.") }
                        if condition.op == "after" {
                            guard after == nil else { throw Unreadable(reason: "Has more than one start date.") }
                            after = time
                        } else {
                            guard before == nil else { throw Unreadable(reason: "Has more than one end date.") }
                            before = time
                        }
                    case "is_empty":
                        throw Unreadable(reason: "Shows jobs with no time. Jobs can\u{2019}t filter by that here; Schedule lists them under Unscheduled.")
                    default:
                        throw Unreadable(reason: "Shows every job with a time; this phone filters between two days.")
                    }
                default:
                    throw unsupported(field: condition.field)
                }
            }
            if let allowed {
                if allowed.isEmpty { throw Unreadable(reason: "No status matches this view, so it would show nothing.") }
                if allowed == serverStatuses.subtracting(doneStatuses) { choices.hidesDone = true }
                else if allowed != serverStatuses { choices.statuses = allowed }
            }
            choices.days = try days(after: after, before: before, calendar: calendar)
            choices.ordering = ordering(sort)
            return .choices(choices)
        } catch let problem as Unreadable {
            return .unsupported(problem.reason)
        } catch {
            return .unsupported("This view\u{2019}s filter could not be read.")
        }
    }

    static func read(_ view: SavedJobView, calendar: Calendar = .current) -> Reading {
        guard view.resourceId == resourceID else { return .unsupported("This view is not for jobs.") }
        return read(filter: view.filter, sort: view.sort, calendar: calendar)
    }

    private static func unsupported(field: String) -> Unreadable {
        let label = fieldLabels[field] ?? field.split(separator: ".").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? "a field"
        return Unreadable(reason: "Filters by \(label), which this phone can\u{2019}t do.")
    }

    /// The conditions of a filter that is one rule or rules joined by "and". Anything else
    /// (either/or groups, rules about a linked record) cannot be shown as the phone's chips.
    private static func conditions(in node: SavedViewJSON, depth: Int) throws -> [Condition] {
        guard depth < 8 else { throw Unreadable(reason: "This view\u{2019}s filter is nested too deeply to read here.") }
        switch node["type"]?.text {
        case "condition":
            guard let field = node["field"]?.text, let op = node["operator"]?.text else {
                throw Unreadable(reason: "This view\u{2019}s filter could not be read.")
            }
            return [Condition(field: field, op: op, value: node["value"])]
        case "group":
            guard let children = node["children"]?.list, !children.isEmpty else {
                throw Unreadable(reason: "This view\u{2019}s filter could not be read.")
            }
            guard node["operator"]?.text == "and" || children.count == 1 else {
                throw Unreadable(reason: "Uses either/or rules; this phone\u{2019}s filters all apply together.")
            }
            return try children.flatMap { try conditions(in: $0, depth: depth + 1) }
        case "relationship":
            let name = node["relationship"]?.text?.split(separator: ".").last.map { $0.replacingOccurrences(of: "_", with: " ") }
            throw Unreadable(reason: "Filters by a linked record (\(name ?? "another list")), which this phone can\u{2019}t do.")
        default:
            throw Unreadable(reason: "This view\u{2019}s filter could not be read.")
        }
    }

    private static func statuses(_ condition: Condition) throws -> Set<String> {
        let raw: [SavedViewJSON]
        if let list = condition.value?.list { raw = list } else if let one = condition.value { raw = [one] } else { raw = [] }
        let named = raw.compactMap(\.text)
        guard !named.isEmpty, named.count == raw.count else { throw Unreadable(reason: "This view\u{2019}s statuses could not be read.") }
        guard Set(named).isSubset(of: serverStatuses) else {
            throw Unreadable(reason: "Uses a status this version of the app doesn\u{2019}t know.")
        }
        return Set(named)
    }

    /// The phone filters by whole days. A view's "after" and "before" become a day range only when
    /// both are there and both fall on a day boundary (within a millisecond).
    private static func days(after: Date?, before: Date?, calendar: Calendar) throws -> JobBoardChoices.Days? {
        if after == nil && before == nil { return nil }
        guard let after, let before else {
            throw Unreadable(reason: "Has an open-ended date; this phone filters between two days.")
        }
        // The day boundary each bound sits on, give or take two milliseconds: "after 23:59:59.999"
        // and "after 00:00:00.000" both start the next morning.
        let slack: TimeInterval = 0.002
        func boundary(_ time: Date) -> Date? {
            let day = calendar.startOfDay(for: time.addingTimeInterval(slack))
            return abs(time.timeIntervalSince(day)) <= slack + 0.0005 ? day : nil
        }
        guard let from = boundary(after), let end = boundary(before),
              let to = calendar.date(byAdding: .day, value: -1, to: end) else {
            throw Unreadable(reason: "Uses exact times; this phone filters by whole days.")
        }
        guard from <= to else { throw Unreadable(reason: "Its dates leave no day to show.") }
        return JobBoardChoices.Days(from: from, to: to)
    }

    /// Ordering never changes which jobs show. An order the phone does not have (by created date,
    /// say) falls back to the board's own: most recently updated first.
    private static func ordering(_ sort: [SavedViewSort]) -> DisplayOptions.Ordering {
        guard let first = sort.first else { return .recent }
        switch (first.field, first.direction) {
        case ("jobs.scheduled_for", "asc"): return .scheduled
        case ("jobs.title", "asc"): return .name
        default: return .recent
        }
    }

    // MARK: Writing

    struct Written: Equatable {
        let filter: SavedViewJSON
        let sort: [SavedViewSort]
    }

    enum WriteProblem: Error, Equatable {
        /// Today / This week / Overdue are worked out each day; the server's filter holds fixed times.
        case movingDate
        case showsNothing

        var message: String {
            switch self {
            case .movingDate: "Today, This week and Overdue change every day, so a view can\u{2019}t hold them. Pick dates instead, or clear the date."
            case .showsNothing: "These filters show no jobs, so there is nothing to save."
            }
        }
    }

    /// The server's filter for the phone's current choices.
    static func write(_ choices: JobBoardChoices, calendar: Calendar = .current) -> Result<Written, WriteProblem> {
        if choices.when != .any && choices.days == nil { return .failure(.movingDate) }
        var nodes: [SavedViewJSON] = []
        switch choices.assignee {
        case .anyone: break
        case .unassigned: nodes.append(condition("jobs.assigned_to_user_id", "is_empty"))
        case .user(let id): nodes.append(condition("jobs.assigned_to_user_id", "is", .string(id)))
        }
        let ticked = choices.statuses.intersection(serverStatuses)
        if !choices.statuses.isEmpty {
            let shown = choices.hidesDone ? ticked.subtracting(doneStatuses) : ticked
            guard !shown.isEmpty else { return .failure(.showsNothing) }
            if shown != serverStatuses {
                nodes.append(shown.count == 1
                    ? condition("jobs.status", "is", .string(shown.first ?? ""))
                    : condition("jobs.status", "is_any_of", .array(shown.sorted().map(SavedViewJSON.string))))
            }
        } else if choices.hidesDone {
            nodes.append(condition("jobs.status", "is_none_of", .array(doneStatuses.sorted().map(SavedViewJSON.string))))
        }
        if let days = choices.days {
            let first = calendar.startOfDay(for: min(days.from, days.to))
            let last = calendar.startOfDay(for: max(days.from, days.to))
            guard let end = calendar.date(byAdding: .day, value: 1, to: last) else { return .failure(.showsNothing) }
            // "after" leaves out its own instant, so step back a millisecond to keep midnight.
            nodes.append(condition("jobs.scheduled_for", "after", .string(lastMillisecond(before: first))))
            nodes.append(condition("jobs.scheduled_for", "before", .string(stamp(end))))
        }
        if nodes.isEmpty { nodes.append(condition("jobs.id", "is_not_empty")) }
        let root: SavedViewJSON = nodes.count == 1 ? nodes[0]
            : .object(["type": .string("group"), "operator": .string("and"), "children": .array(nodes)])
        let sort: SavedViewSort
        switch choices.ordering {
        case .recent: sort = SavedViewSort(field: "jobs.updated_at", direction: "desc")
        case .scheduled: sort = SavedViewSort(field: "jobs.scheduled_for", direction: "asc")
        case .name: sort = SavedViewSort(field: "jobs.title", direction: "asc")
        }
        return .success(Written(filter: .object(["schemaVersion": .number(1), "root": root]), sort: [sort]))
    }

    private static func condition(_ field: String, _ op: String, _ value: SavedViewJSON? = nil) -> SavedViewJSON {
        var fields: [String: SavedViewJSON] = ["type": .string("condition"), "field": .string(field), "operator": .string(op)]
        if let value { fields["value"] = value }
        return .object(fields)
    }

    private static func stamp(_ date: Date) -> String { JobFiltering.isoFractional.string(from: date) }

    /// "…T23:59:59.999Z" for the second before `date`, written out so no rounding can move it.
    private static func lastMillisecond(before date: Date) -> String {
        let second = JobFiltering.isoPlain.string(from: date.addingTimeInterval(-1))
        return second.hasSuffix("Z") ? String(second.dropLast()) + ".999Z" : stamp(date.addingTimeInterval(-0.001))
    }

    /// A new personal view's key, as the web makes it: "jobs." and a lowercase UUID.
    static func newViewID(_ uuid: UUID = UUID()) -> String { "\(resourceID).\(uuid.uuidString.lowercased())" }

    /// A view key is safe to put in a path only in the server's own shape.
    static func isViewID(_ id: String) -> Bool {
        id.range(of: "^[a-z][a-z0-9._-]{1,127}$", options: .regularExpression) != nil
    }

    // MARK: Words

    /// The choices as short chips ("Filters in this view", Paper 20C), in the sheet's order.
    static func summary(_ choices: JobBoardChoices, me: String?, techName: (String) -> String?) -> [String] {
        var words: [String] = []
        switch choices.assignee {
        case .anyone: words.append("Any technician")
        case .unassigned: words.append("Unassigned")
        case .user(let id): words.append(id == me ? "Mine" : techName(id) ?? "One technician")
        }
        let groups = JobBoardFilter.groups(in: choices.statuses.intersection(serverStatuses))
        if !groups.isEmpty { words.append("Status: " + groups.map(\.title).joined(separator: ", ")) }
        if choices.hidesDone { words.append("Hiding done") }
        if let days = choices.days { words.append(JobBoardFilter.datesLabel(from: days.from, to: days.to)) }
        else if choices.when != .any { words.append(choices.when.label) }
        if choices.ordering != .recent { words.append("By \(JobBoardFilter.sortLabel(choices.ordering).lowercased())") }
        return words
    }
}

// MARK: - API

@MainActor
extension APIClient {
    private func viewPath(_ id: String, _ suffix: String) throws -> String {
        guard JobSavedViewMapping.isViewID(id) else { throw Problem(title: "Invalid view", status: nil, detail: id) }
        return "/v1/views/\(id)\(suffix)"
    }

    /// Every saved view for jobs the person may see (their own and the organisation's), not archived.
    func jobSavedViews() async throws -> [SavedJobView] {
        var all: [SavedJobView] = []
        var cursor: String?
        var seen = Set<String>()
        repeat {
            try Task.checkCancellation()
            let page: SavedJobViewPage = try await send("GET", "/v1/views",
                queryItems: [URLQueryItem(name: "resourceId", value: JobSavedViewMapping.resourceID)], cursor: cursor)
            all.append(contentsOf: page.items)
            cursor = page.nextCursor
            if let cursor, cursor.isEmpty || !seen.insert(cursor).inserted {
                throw Problem(title: "Pagination cursor loop", status: nil, detail: "Repeated or empty cursor")
            }
        } while cursor != nil
        return all
    }

    func jobSavedViewMembership() async throws -> SavedViewMembership {
        try await send("GET", "/v1/views/membership",
                       queryItems: [URLQueryItem(name: "resourceId", value: JobSavedViewMapping.resourceID)])
    }

    func saveJobView(_ body: SavedJobViewSave) async throws -> SavedJobView {
        try await send("POST", "/v1/views", body: body)
    }

    func archiveJobView(_ id: String) async throws -> SavedJobView {
        try await send("POST", try viewPath(id, "/archive"))
    }

    func setJobViewFavorite(_ id: String, on: Bool) async throws {
        let _: EmptyResponse = try await send("POST", try viewPath(id, on ? "/favorite" : "/unfavorite"))
    }
}

// MARK: - The person's saved views

/// The saved job views of the signed-in person in the active workspace, with their favourites.
/// Nothing is kept on the phone: views live on the server and are read again on each visit.
@MainActor
final class JobSavedViewsBook: ObservableObject {
    @Published private(set) var views: [SavedJobView] = []
    @Published private(set) var favorites: Set<String> = []
    @Published private(set) var loaded = false
    @Published private(set) var loading = false
    /// Why the list could not be read; nil once it has.
    @Published var problem: String?
    private var identity = ""

    /// Favourites first, then by name.
    var ordered: [SavedJobView] {
        views.sorted { left, right in
            let leftStar = favorites.contains(left.id), rightStar = favorites.contains(right.id)
            if leftStar != rightStar { return leftStar }
            return left.label.localizedStandardCompare(right.label) == .orderedAscending
        }
    }

    func reset(identity: String) {
        guard identity != self.identity else { return }
        self.identity = identity
        views = []; favorites = []; loaded = false; problem = nil
    }

    func load(api: APIClient, identity: String) async {
        reset(identity: identity)
        #if DEBUG
        if PaperPreview.enabled {
            views = JobSavedViewsPreview.views
            favorites = [JobSavedViewsPreview.views[0].id]
            loaded = true
            return
        }
        #endif
        loading = true
        defer { loading = false }
        do {
            let listed = try await api.jobSavedViews()
            guard identity == self.identity else { return }
            views = listed.filter { !$0.isArchived && $0.resourceId == JobSavedViewMapping.resourceID }
            loaded = true
            problem = nil
            // Favourites are a nicety: without them the views still list, by name.
            if let membership = try? await api.jobSavedViewMembership(), identity == self.identity {
                favorites = Set(membership.favorites)
            }
        } catch is CancellationError {
        } catch {
            guard identity == self.identity else { return }
            problem = Self.loadProblem(error)
            // A role that may not read the workspace's views simply has none; that is not a failure.
            if problem == nil { views = []; favorites = []; loaded = true }
        }
    }

    /// What the Jobs list says when saved views fail to load, or nil when there is nothing to say:
    /// the server refuses the list to a role that only sees its own jobs (a technician's
    /// "not permitted: job.view (out_of_scope)"), and that role just has no saved views.
    nonisolated static func loadProblem(_ error: Error) -> String? {
        if let problem = error as? Problem, problem.status == 403 { return nil }
        return "Could not load saved views. \(error.localizedDescription)"
    }

    /// Saves the current filters as a new personal view and returns it.
    func create(label: String, written: JobSavedViewMapping.Written, api: APIClient) async throws -> SavedJobView {
        let body = SavedJobViewSave(id: JobSavedViewMapping.newViewID(), resourceId: JobSavedViewMapping.resourceID,
                                    label: label, visibility: "personal", layout: "list",
                                    filter: written.filter, sort: written.sort)
        let scope = identity
        #if DEBUG
        if PaperPreview.enabled {
            let view = SavedJobView(id: body.id, label: label, filter: written.filter, sort: written.sort,
                                    createdBy: PaperPreview.actorID)
            views.append(view)
            return view
        }
        #endif
        let saved = try await api.saveJobView(body)
        if scope == identity { views.removeAll { $0.id == saved.id }; views.append(saved) }
        return saved
    }

    /// Renames a view: the same definition sent back with the new name and the revision it was read at.
    func rename(_ view: SavedJobView, to label: String, api: APIClient) async throws {
        let scope = identity
        #if DEBUG
        if PaperPreview.enabled { replace(view.id) { $0.label = label }; return }
        #endif
        let saved = try await api.saveJobView(Self.renameBody(view, label: label))
        guard scope == identity else { return }
        replace(view.id) { $0 = saved }
    }

    static func renameBody(_ view: SavedJobView, label: String) -> SavedJobViewSave {
        SavedJobViewSave(id: view.id, resourceId: view.resourceId, label: label, description: view.description,
                         visibility: view.visibility, layout: view.layout, filter: view.filter, sort: view.sort,
                         groupBy: view.groupBy, columns: view.columns, expectedRevision: view.revision)
    }

    /// Archives a view (the server never deletes one). It leaves the list.
    func archive(_ view: SavedJobView, api: APIClient) async throws {
        let scope = identity
        #if DEBUG
        if PaperPreview.enabled { views.removeAll { $0.id == view.id }; return }
        #endif
        _ = try await api.archiveJobView(view.id)
        guard scope == identity else { return }
        views.removeAll { $0.id == view.id }
        favorites.remove(view.id)
    }

    func setFavorite(_ view: SavedJobView, on: Bool, api: APIClient) async throws {
        let scope = identity
        #if DEBUG
        if PaperPreview.enabled { if on { favorites.insert(view.id) } else { favorites.remove(view.id) }; return }
        #endif
        try await api.setJobViewFavorite(view.id, on: on)
        guard scope == identity else { return }
        if on { favorites.insert(view.id) } else { favorites.remove(view.id) }
    }

    private func replace(_ id: String, _ change: (inout SavedJobView) -> Void) {
        guard let index = views.firstIndex(where: { $0.id == id }) else { return }
        change(&views[index])
    }

    /// Who may rename or archive a view, as the server decides it: a personal view only by the
    /// person who made it; an organisation view only with the right to edit organisation settings.
    static func canChange(_ view: SavedJobView, me: String?, canEditOrganization: Bool) -> Bool {
        switch view.visibility {
        case "personal": return me != nil && view.createdBy == me
        case "organization": return canEditOrganization
        default: return false
        }
    }
}

#if DEBUG
/// Design-preview samples only (`--paper-preview`): two views the phone can apply and one it cannot.
enum JobSavedViewsPreview {
    static let views: [SavedJobView] = [
        SavedJobView(id: "jobs.00000000-0000-4000-8000-00000000a001", label: "On hold",
                     filter: .object(["schemaVersion": .number(1), "root": .object([
                        "type": .string("condition"), "field": .string("jobs.status"),
                        "operator": .string("is"), "value": .string("paused")])]),
                     createdBy: PaperPreview.actorID),
        SavedJobView(id: "jobs.00000000-0000-4000-8000-00000000a002", label: "Unassigned",
                     filter: .object(["schemaVersion": .number(1), "root": .object([
                        "type": .string("condition"), "field": .string("jobs.assigned_to_user_id"),
                        "operator": .string("is_empty")])]),
                     createdBy: PaperPreview.actorID),
        SavedJobView(id: "jobs.00000000-0000-4000-8000-00000000a003", label: "Water heaters", visibility: "organization",
                     filter: .object(["schemaVersion": .number(1), "root": .object([
                        "type": .string("condition"), "field": .string("jobs.title"),
                        "operator": .string("contains"), "value": .string("water heater")])]))
    ]
}
#endif

import Foundation

// The office "waiting for a slot" queue (Paper 57F / 20S): follow-up visits the field asked for
// that the server could not book on its own. It is the server's open office reviews
// (GET /v1/scheduling/office-reviews), not the Unscheduled list (jobs with no time): a review
// belongs to a follow-up on a source job, which may itself be booked or finished. The office
// either books it (POST …/{id}/book, which claims the technician's time) or closes it with a
// reason (POST …/{id}/resolve). Both need job.book.followup and job.assign.

// MARK: - Wire types

struct OfficeSlotWindow: Codable, Equatable, Sendable {
    let startsAt: String
    let endsAt: String
}

/// One office review (the server's officeReviewSchema): an open one from the queue, or one read on
/// its own, which may be closed. Only what the phone shows, must send back or checks is read; the
/// booking evidence fields are left alone.
struct OfficeSlotReview: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let sourceJobId: String
    let customerId: String?
    let locationId: String?
    let requestedWindow: OfficeSlotWindow?
    let timeZone: String?
    let serviceNeed: String
    /// The technician the follow-up is for (resourceRequirement.technicianId).
    let technicianId: String?
    /// Why the server could not book it: capacity_unavailable, capacity_conflict, stale_request,
    /// uncertain or out_of_scope.
    let reasonCode: String
    /// Sent back as expectedDecisionVersion so a stale row cannot be booked or closed.
    let decisionVersion: Int
    let status: String
    let createdAt: String?
    /// How a closed review was closed (resolution.kind): "appointment" once it was booked,
    /// "no_action" once it was closed without a visit. Nil while it is open.
    let resolutionKind: String?

    private enum CodingKeys: String, CodingKey {
        case id, sourceJobId, customerId, locationId, requestedWindow, timeZone, serviceNeed
        case resourceRequirement, reasonCode, decisionVersion, status, createdAt, resolution
    }
    private struct Requirement: Decodable { let technicianId: String? }
    private struct Resolution: Decodable { let kind: String? }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        sourceJobId = try values.decode(String.self, forKey: .sourceJobId)
        decisionVersion = try values.decode(Int.self, forKey: .decisionVersion)
        serviceNeed = try values.decode(String.self, forKey: .serviceNeed)
        customerId = try? values.decodeIfPresent(String.self, forKey: .customerId)
        locationId = try? values.decodeIfPresent(String.self, forKey: .locationId)
        requestedWindow = try? values.decodeIfPresent(OfficeSlotWindow.self, forKey: .requestedWindow)
        timeZone = try? values.decodeIfPresent(String.self, forKey: .timeZone)
        technicianId = (try? values.decodeIfPresent(Requirement.self, forKey: .resourceRequirement))?.technicianId
        reasonCode = (try? values.decodeIfPresent(String.self, forKey: .reasonCode)) ?? ""
        status = (try? values.decodeIfPresent(String.self, forKey: .status)) ?? "open"
        createdAt = try? values.decodeIfPresent(String.self, forKey: .createdAt)
        resolutionKind = (try? values.decodeIfPresent(Resolution.self, forKey: .resolution))?.kind
    }

    init(id: String, sourceJobId: String, customerId: String? = nil, locationId: String? = nil,
         requestedWindow: OfficeSlotWindow? = nil, timeZone: String? = nil, serviceNeed: String,
         technicianId: String? = nil, reasonCode: String = "capacity_unavailable", decisionVersion: Int = 1,
         status: String = "open", createdAt: String? = nil, resolutionKind: String? = nil) {
        self.id = id; self.sourceJobId = sourceJobId; self.customerId = customerId; self.locationId = locationId
        self.requestedWindow = requestedWindow; self.timeZone = timeZone; self.serviceNeed = serviceNeed
        self.technicianId = technicianId; self.reasonCode = reasonCode; self.decisionVersion = decisionVersion
        self.status = status; self.createdAt = createdAt; self.resolutionKind = resolutionKind
    }

    /// The source job's number as the app writes it everywhere ("JOB-2214").
    var jobRef: String { "JOB-" + String(sourceJobId.suffix(4)).uppercased() }
}

/// One review read on its own (GET …/{id}). Stricter than a queue row: the server always sends a
/// status, so a body without a string status is not counted as open; it is a read that failed.
struct OfficeSlotReviewRead: Decodable {
    let review: OfficeSlotReview

    private enum CodingKeys: String, CodingKey { case status }

    init(from decoder: Decoder) throws {
        _ = try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .status)
        review = try OfficeSlotReview(from: decoder)
    }
}

/// A page of the queue. A row the phone cannot read is skipped, not the whole queue.
struct OfficeSlotPage: Decodable {
    let items: [OfficeSlotReview]
    let nextCursor: String?

    private enum CodingKeys: String, CodingKey { case items, nextCursor }
    private struct Entry: Decodable {
        let review: OfficeSlotReview?
        init(from decoder: Decoder) throws { review = try? OfficeSlotReview(from: decoder) }
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        items = try values.decode([Entry].self, forKey: .items).compactMap(\.review)
        nextCursor = try? values.decodeIfPresent(String.self, forKey: .nextCursor)
    }
}

/// POST …/book (bookOfficeReviewAppointmentInputSchema; the path supplies officeReviewId).
struct OfficeSlotBookRequest: Encodable, Equatable {
    let expectedDecisionVersion: Int
    /// The booking intent: one per follow-up, kept by the queue for every try (OfficeSlotBookingAttempts).
    /// The server refuses the review's own intent id.
    let intentId: String
    let plannedWindow: OfficeSlotWindow
}

/// POST …/resolve (resolveOfficeReviewNoActionInputSchema): close the review without a visit.
struct OfficeSlotResolveRequest: Encodable, Equatable {
    struct Resolution: Encodable, Equatable {
        let kind = "no_action"
        let reasonCode: String
    }
    let expectedDecisionVersion: Int
    let resolution: Resolution
}

/// What …/book answers: the appointment it made (and the review, now superseded).
struct OfficeSlotBooked: Decodable, Equatable {
    struct Appointment: Decodable, Equatable {
        let id: String
        let plannedWindow: OfficeSlotWindow?
        let status: String?
    }
    let appointment: Appointment
}

// MARK: - Rules

enum OfficeSlotRules {
    /// Why a follow-up is waiting, in plain words.
    static func reasonLabel(_ code: String) -> String {
        switch code {
        case "capacity_unavailable": "No opening at the time asked for"
        case "capacity_conflict": "Another visit took that time"
        case "stale_request": "The request was out of date"
        case "uncertain": "Could not be booked automatically"
        case "out_of_scope": "Outside what books automatically"
        case "": "Needs the office"
        default: code.replacingOccurrences(of: "_", with: " ").capitalizedFirst
        }
    }

    /// The reasons the office can close a review with. Both codes are ones the server's own tests
    /// use; it stores the code as given.
    static let noActionReasons: [(code: String, title: String)] = [
        ("customer_declined", "Customer doesn\u{2019}t want the visit"),
        ("manual_follow_up", "Handled another way")
    ]

    /// "Wed, Nov 18, 1:00 PM – 2:00 PM", in the phone's time zone; nil when a time cannot be read.
    static func windowLabel(_ window: OfficeSlotWindow?, calendar: Calendar = .current, locale: Locale = .current) -> String? {
        guard let window, let start = JobFiltering.date(window.startsAt), let end = JobFiltering.date(window.endsAt) else { return nil }
        var day = Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        day = day.weekday(.abbreviated).month(.abbreviated).day()
        let time = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        let sameDay = calendar.isDate(start, inSameDayAs: end)
        return "\(start.formatted(day)), \(start.formatted(time)) \u{2013} \(sameDay ? "" : end.formatted(day) + ", ")\(end.formatted(time))"
    }

    /// Where the Schedule sheet opens: the time the field asked for when it is still ahead,
    /// otherwise the next full hour; the length asked for, between half an hour and a day.
    static func defaultPlan(for review: OfficeSlotReview, now: Date = Date(), calendar: Calendar = .current) -> (start: Date, minutes: Int) {
        let asked = review.requestedWindow.flatMap { JobFiltering.date($0.startsAt) }
        let askedEnd = review.requestedWindow.flatMap { JobFiltering.date($0.endsAt) }
        var minutes = 120
        if let asked, let askedEnd, askedEnd > asked {
            minutes = min(max(Int(askedEnd.timeIntervalSince(asked) / 60), 30), 24 * 60)
        }
        if let asked, asked > now { return (asked, minutes) }
        let hour = calendar.dateInterval(of: .hour, for: now)?.end ?? now.addingTimeInterval(3600)
        return (hour, minutes)
    }

    /// The window to send: whole seconds, millisecond text in UTC (the server's instant format),
    /// longer than nothing and no longer than a day. Nil when the length is not allowed.
    static func plannedWindow(start: Date, minutes: Int) -> OfficeSlotWindow? {
        guard minutes > 0, minutes <= 24 * 60 else { return nil }
        let from = Date(timeIntervalSince1970: start.timeIntervalSince1970.rounded(.down))
        let to = from.addingTimeInterval(TimeInterval(minutes * 60))
        return OfficeSlotWindow(startsAt: JobFiltering.isoFractional.string(from: from),
                                endsAt: JobFiltering.isoFractional.string(from: to))
    }

    static func bookRequest(for review: OfficeSlotReview, start: Date, minutes: Int, intent: UUID = UUID()) -> OfficeSlotBookRequest? {
        guard let window = plannedWindow(start: start, minutes: minutes) else { return nil }
        return OfficeSlotBookRequest(expectedDecisionVersion: review.decisionVersion,
                                     intentId: intent.uuidString.lowercased(), plannedWindow: window)
    }

    static func resolveRequest(for review: OfficeSlotReview, reasonCode: String) -> OfficeSlotResolveRequest {
        OfficeSlotResolveRequest(expectedDecisionVersion: review.decisionVersion,
                                 resolution: .init(reasonCode: reasonCode))
    }

    /// "3 follow-ups need a time".
    static func countLabel(_ count: Int) -> String {
        count == 0 ? "Nothing is waiting" : "\(count) follow-up\(count == 1 ? "" : "s") need\(count == 1 ? "s" : "") a time"
    }

    /// The sentence under the rows, the web panel's (office-reviews.tsx "How this works"): the
    /// server checks the technician's appointments that are still scheduled, not the whole board.
    static let footer = "Follow-ups the field asked for that could not be booked on their own. Book visit checks the technician\u{2019}s other booked visits before it books."
}

/// Why the last read of the queue failed. It keeps the detail, not a whole sentence: the words
/// depend on whether rows from an earlier read are still listed (OfficeSlotQueue.notice).
struct OfficeSlotListProblem: Equatable {
    enum Kind: Equatable {
        /// 403: the server will not list follow-ups for this person (a team scope, or rights
        /// taken away since the session was read). The web shows its no-access state.
        case noAccess
        /// Anything else: a 5xx, no answer, a 409 paging bound, a repeated cursor.
        case failed
    }

    /// The web's PermissionState title and description, joined (office-reviews.tsx).
    static let noAccessMessage = "Your role can\u{2019}t book follow-ups. Booking a follow-up needs the right to book follow-ups and to assign jobs. An owner or admin can change that."
    /// The web's ErrorState title, shown while nothing has been listed.
    static let loadFailed = "Could not load the follow-ups waiting for a slot."
    /// The web's warning for a failed read with rows from an earlier read still shown: its title,
    /// then the detail, then this.
    static let readAgainFailed = "Could not read the list again."
    static let rowsFromLastRead = "The rows below are from the last read."

    let kind: Kind
    /// What went wrong, in the server's or the system's words.
    let detail: String

    init(_ error: Error) {
        kind = ProblemKind(error) == .forbidden ? .noAccess : .failed
        detail = error.localizedDescription
    }

    /// The words for this problem. With rows still listed, a failed read says the list could not
    /// be read again and that the rows are from the last read, as the web does; with none, that
    /// the follow-ups could not load. A refusal empties the list, so it has one set of words.
    func message(rowsListed: Bool) -> String {
        switch kind {
        case .noAccess: return Self.noAccessMessage
        case .failed where rowsListed:
            // The web shows the detail as its own paragraph; here it is one line, so it ends as a sentence.
            let sentence = detail.isEmpty || ".!?".contains(detail.last ?? ".") ? detail : "\(detail)."
            return [Self.readAgainFailed, sentence, Self.rowsFromLastRead].filter { !$0.isEmpty }.joined(separator: " ")
        case .failed: return "\(Self.loadFailed) \(detail)"
        }
    }

    /// Try again, unless trying again can only get the same answer: a refusal of access, or no
    /// connection, where nothing can be sent.
    func offersRetry(offline: Bool) -> Bool { kind == .failed && !offline }
}

/// What Schedule › Unscheduled says above the queue's rows about the last read: the problem's
/// words, which kind it is (for the symbol), and whether Try again is offered.
struct OfficeSlotListNotice: Equatable {
    let kind: OfficeSlotListProblem.Kind
    let message: String
    let offersRetry: Bool
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: - API

@MainActor
extension APIClient {
    private func officeReviewPath(_ id: String, _ suffix: String) throws -> String {
        guard UUID(uuidString: id) != nil else { throw Problem(title: "Invalid record ID", status: nil, detail: id) }
        return "/v1/scheduling/office-reviews/\(id)\(suffix)"
    }

    /// The open queue, always from the server: a saved copy could offer a row someone already booked.
    func officeSlotReviews() async throws -> [OfficeSlotReview] {
        var all: [OfficeSlotReview] = []
        var cursor: String?
        var seen = Set<String>()
        repeat {
            try Task.checkCancellation()
            let page: OfficeSlotPage = try await send("GET", "/v1/scheduling/office-reviews", cursor: cursor, requireFresh: true)
            all.append(contentsOf: page.items)
            cursor = page.nextCursor
            if let cursor, cursor.isEmpty || !seen.insert(cursor).inserted {
                throw Problem(title: "Pagination cursor loop", status: nil, detail: "Repeated or empty cursor")
            }
        } while cursor != nil
        return all
    }

    /// One follow-up as it stands now, open or closed (GET …/{id}), always from the server. The
    /// Schedule sheet reads it once after a refused try that followed one with no answer.
    /// A body without a status throws (OfficeSlotReviewRead), so it counts as unread, not open.
    func officeSlotReview(_ id: String) async throws -> OfficeSlotReview {
        let read: OfficeSlotReviewRead = try await send("GET", try officeReviewPath(id, ""), requireFresh: true)
        return read.review
    }

    func bookOfficeSlot(_ id: String, request: OfficeSlotBookRequest) async throws -> OfficeSlotBooked {
        try await send("POST", try officeReviewPath(id, "/book"), body: request)
    }

    func resolveOfficeSlot(_ id: String, request: OfficeSlotResolveRequest) async throws {
        let _: EmptyResponse = try await send("POST", try officeReviewPath(id, "/resolve"), body: request)
    }
}

// MARK: - The queue

/// The open queue for the active workspace. Never kept on the phone: it needs signal, because the
/// server checks each row against the job as it stands now.
@MainActor
final class OfficeSlotQueue: ObservableObject {
    @Published private(set) var reviews: [OfficeSlotReview] = []
    @Published private(set) var loaded = false
    @Published private(set) var problem: OfficeSlotListProblem?
    /// The booking id of each follow-up, kept across Schedule sheets while this queue's screen is
    /// shown, and dropped when the workspace or the sign-in changes. A Schedule sheet reads it once,
    /// when it opens, and then keeps its own copy, so it is not published.
    var bookingAttempts = OfficeSlotBookingAttempts()
    private var identity = ""

    static func identity(_ session: SessionController) -> String {
        "\(session.user?.id ?? "")|\(session.activeOrganization?.id ?? "")|\(session.generation)"
    }

    /// Booking and closing both need these two rights, as the server's routes do.
    static func allowed(_ session: SessionController) -> Bool {
        session.can("job.book.followup", feature: "jobs") && session.can("job.assign", feature: "jobs")
    }

    /// What Unscheduled says about the last read. Nil once a read worked. With nothing listed, any
    /// problem is said, since silence would read as nothing waiting. With rows still listed, a
    /// failed read is said online only: offline the Schedule screen's offline banner already says
    /// why the list is not read again, and the web hides its warning there too. The view draws
    /// exactly this.
    func notice(offline: Bool) -> OfficeSlotListNotice? {
        guard let problem else { return nil }
        let rowsListed = !reviews.isEmpty
        if problem.kind == .failed, rowsListed, offline { return nil }
        return OfficeSlotListNotice(kind: problem.kind, message: problem.message(rowsListed: rowsListed),
                                    offersRetry: problem.offersRetry(offline: offline))
    }

    func load(api: APIClient, identity: String) async {
        _ = await reread(api: api, identity: identity)
    }

    /// Reads the list, as `load` does. True only when this read brought the list back for this
    /// identity, so words after an answer say "The list has been read again." only when it was.
    @discardableResult
    func reread(api: APIClient, identity: String) async -> Bool {
        if identity != self.identity {
            self.identity = identity
            reviews = []; loaded = false; problem = nil
            bookingAttempts.removeAll()
        }
        #if DEBUG
        if PaperPreview.enabled {
            if !loaded { reviews = OfficeSlotPreview.reviews }
            loaded = true
            return true
        }
        #endif
        do {
            let listed = try await api.officeSlotReviews()
            guard identity == self.identity else { return false }
            // Oldest first: the follow-up that has waited longest leads.
            reviews = listed.filter { $0.status == "open" }.sorted { ($0.createdAt ?? "") < ($1.createdAt ?? "") }
            loaded = true
            problem = nil
            return true
        } catch is CancellationError {
            return false
        } catch {
            guard identity == self.identity else { return false }
            let failed = OfficeSlotListProblem(error)
            // As on the web: no list once the server refuses access, so no Schedule it would refuse.
            if failed.kind == .noAccess { reviews = [] }
            problem = failed
            return false
        }
    }

    /// Books the follow-up for the given window. The row leaves the queue only once the server has
    /// made the appointment.
    func book(_ review: OfficeSlotReview, request: OfficeSlotBookRequest, api: APIClient) async throws -> OfficeSlotWindow {
        let scope = identity
        #if DEBUG
        if PaperPreview.enabled { reviews.removeAll { $0.id == review.id }; return request.plannedWindow }
        #endif
        let booked = try await api.bookOfficeSlot(review.id, request: request)
        if scope == identity { reviews.removeAll { $0.id == review.id } }
        return booked.appointment.plannedWindow ?? request.plannedWindow
    }

    /// Closes the follow-up without a visit, with the reason given.
    func resolve(_ review: OfficeSlotReview, reasonCode: String, api: APIClient) async throws {
        let scope = identity
        #if DEBUG
        if PaperPreview.enabled { reviews.removeAll { $0.id == review.id }; return }
        #endif
        try await api.resolveOfficeSlot(review.id, request: OfficeSlotRules.resolveRequest(for: review, reasonCode: reasonCode))
        if scope == identity { reviews.removeAll { $0.id == review.id } }
    }
}

#if DEBUG
/// Design-preview samples only (`--paper-preview`), tied to the preview's own job and customer.
enum OfficeSlotPreview {
    static var reviews: [OfficeSlotReview] {
        let start = Calendar.current.date(byAdding: .day, value: 2, to: Calendar.current.startOfDay(for: Date()))?.addingTimeInterval(10 * 3600) ?? Date()
        return [
            OfficeSlotReview(id: "00000000-0000-4000-8000-00000000b001", sourceJobId: PaperPreview.jobID,
                             customerId: PaperPreview.customerID,
                             requestedWindow: OfficeSlotRules.plannedWindow(start: start, minutes: 120),
                             timeZone: TimeZone.current.identifier, serviceNeed: "Capacitor check",
                             technicianId: PaperPreview.actorID, reasonCode: "capacity_conflict"),
            OfficeSlotReview(id: "00000000-0000-4000-8000-00000000b002", sourceJobId: PaperPreview.jobID,
                             customerId: PaperPreview.customerID,
                             requestedWindow: OfficeSlotRules.plannedWindow(start: start.addingTimeInterval(86_400), minutes: 60),
                             timeZone: TimeZone.current.identifier, serviceNeed: "Install the replacement part",
                             technicianId: PaperPreview.actorID, reasonCode: "capacity_unavailable")
        ]
    }
}
#endif

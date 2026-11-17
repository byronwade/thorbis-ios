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

/// One open office review (the server's openOfficeReviewSchema). Only what the phone shows or
/// must send back is read; the booking evidence fields are left alone.
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

    private enum CodingKeys: String, CodingKey {
        case id, sourceJobId, customerId, locationId, requestedWindow, timeZone, serviceNeed
        case resourceRequirement, reasonCode, decisionVersion, status, createdAt
    }
    private struct Requirement: Decodable { let technicianId: String? }

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
    }

    init(id: String, sourceJobId: String, customerId: String? = nil, locationId: String? = nil,
         requestedWindow: OfficeSlotWindow? = nil, timeZone: String? = nil, serviceNeed: String,
         technicianId: String? = nil, reasonCode: String = "capacity_unavailable", decisionVersion: Int = 1,
         status: String = "open", createdAt: String? = nil) {
        self.id = id; self.sourceJobId = sourceJobId; self.customerId = customerId; self.locationId = locationId
        self.requestedWindow = requestedWindow; self.timeZone = timeZone; self.serviceNeed = serviceNeed
        self.technicianId = technicianId; self.reasonCode = reasonCode; self.decisionVersion = decisionVersion
        self.status = status; self.createdAt = createdAt
    }

    /// The source job's number as the app writes it everywhere ("JOB-2214").
    var jobRef: String { "JOB-" + String(sourceJobId.suffix(4)).uppercased() }
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
    /// A new booking intent for this attempt; the server refuses the review's own intent id.
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
    @Published private(set) var loading = false
    @Published var problem: String?
    private var identity = ""

    static func identity(_ session: SessionController) -> String {
        "\(session.user?.id ?? "")|\(session.activeOrganization?.id ?? "")|\(session.generation)"
    }

    /// Booking and closing both need these two rights, as the server's routes do.
    static func allowed(_ session: SessionController) -> Bool {
        session.can("job.book.followup", feature: "jobs") && session.can("job.assign", feature: "jobs")
    }

    func load(api: APIClient, identity: String) async {
        if identity != self.identity {
            self.identity = identity
            reviews = []; loaded = false; problem = nil
        }
        #if DEBUG
        if PaperPreview.enabled {
            if !loaded { reviews = OfficeSlotPreview.reviews }
            loaded = true
            return
        }
        #endif
        loading = true
        defer { loading = false }
        do {
            let listed = try await api.officeSlotReviews()
            guard identity == self.identity else { return }
            // Oldest first: the follow-up that has waited longest leads.
            reviews = listed.filter { $0.status == "open" }.sorted { ($0.createdAt ?? "") < ($1.createdAt ?? "") }
            loaded = true
            problem = nil
        } catch is CancellationError {
        } catch {
            guard identity == self.identity else { return }
            problem = "Could not load the follow-ups waiting for a slot. \(error.localizedDescription)"
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

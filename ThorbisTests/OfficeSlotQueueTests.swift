import XCTest
@testable import Thorbis

/// The office "waiting for a slot" queue: the server's payloads (built from Thorbis-TanStack
/// `domains/scheduling/src/schemas.ts`, with the ids and times its own lifecycle test uses) and
/// the requests the phone sends back.
@MainActor
final class OfficeSlotQueueTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    /// One openOfficeReviewSchema row.
    private let reviewJSON = #"""
    {"id":"018f0000-0000-7000-8000-000000000066","organizationId":"018f0000-0000-7000-8000-000000000001",
     "sourceJobId":"018f0000-0000-7000-8000-000000002214","sourceFollowUpIntentId":"018f0000-0000-7000-8000-000000000008",
     "sourceFollowUpRevision":1,"bookingIntentId":"018f0000-0000-7000-8000-000000000012",
     "bookingFingerprint":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
     "customerId":"018f0000-0000-7000-8000-000000000004","locationId":"018f0000-0000-7000-8000-000000000005",
     "requestedWindow":{"startsAt":"2026-09-02T13:00:00.000Z","endsAt":"2026-09-02T14:00:00.000Z"},
     "timeZone":"America/Los_Angeles","serviceNeed":"Install the replacement part",
     "resourceRequirement":{"technicianId":"018f0000-0000-7000-8000-000000000003","requiredTraitIds":[]},
     "reasonCode":"capacity_conflict","decisionId":"018f0000-0000-7000-8000-000000000067","decisionVersion":2,
     "authorityRevision":"memory-1","evaluatedAt":"2026-09-01T12:00:00.000Z","expiresAt":"2026-09-01T12:05:00.000Z",
     "nextActionOwner":{"type":"queue","id":"office_scheduling"},
     "createdByUserId":"018f0000-0000-7000-8000-000000000003","createdAt":"2026-09-01T12:00:00.000Z","status":"open"}
    """#

    func testDecodesTheOpenQueuePage() throws {
        // GET /v1/scheduling/office-reviews: the last page leaves nextCursor out.
        let page = try decode(OfficeSlotPage.self, #"{"items":[\#(reviewJSON)]}"#)
        XCTAssertNil(page.nextCursor)
        let review = try XCTUnwrap(page.items.first)
        XCTAssertEqual(review.id, "018f0000-0000-7000-8000-000000000066")
        XCTAssertEqual(review.sourceJobId, "018f0000-0000-7000-8000-000000002214")
        XCTAssertEqual(review.jobRef, "JOB-2214")
        XCTAssertEqual(review.customerId, "018f0000-0000-7000-8000-000000000004")
        XCTAssertEqual(review.serviceNeed, "Install the replacement part")
        XCTAssertEqual(review.technicianId, "018f0000-0000-7000-8000-000000000003")
        XCTAssertEqual(review.reasonCode, "capacity_conflict")
        XCTAssertEqual(review.decisionVersion, 2)
        XCTAssertEqual(review.status, "open")
        XCTAssertEqual(review.requestedWindow, OfficeSlotWindow(startsAt: "2026-09-02T13:00:00.000Z", endsAt: "2026-09-02T14:00:00.000Z"))
        XCTAssertEqual(review.timeZone, "America/Los_Angeles")
    }

    func testDecodesOneReviewReadOnItsOwnOpenOrClosed() throws {
        // GET /v1/scheduling/office-reviews/{id} answers officeReviewSchema: open, or closed with its resolution.
        let open = try decode(OfficeSlotReview.self, reviewJSON)
        XCTAssertEqual(open.status, "open")
        XCTAssertNil(open.resolutionKind)
        let closedFields = #","resolvedByUserId":"018f0000-0000-7000-8000-000000000003","resolvedAt":"2026-09-01T12:01:00.000Z"}"#
        let bookedJSON = reviewJSON.replacingOccurrences(of: #""status":"open"}"#, with:
            #""status":"superseded","resolution":{"kind":"appointment","appointmentId":"018f0000-0000-7000-8000-000000000068"}"# + closedFields)
        let booked = try decode(OfficeSlotReview.self, bookedJSON)
        XCTAssertEqual(booked.id, "018f0000-0000-7000-8000-000000000066")
        XCTAssertEqual(booked.status, "superseded")
        XCTAssertEqual(booked.resolutionKind, "appointment")
        let closedJSON = reviewJSON.replacingOccurrences(of: #""status":"open"}"#, with:
            #""status":"resolved","resolution":{"kind":"no_action","reasonCode":"customer_declined"}"# + closedFields)
        let closed = try decode(OfficeSlotReview.self, closedJSON)
        XCTAssertEqual(closed.status, "resolved")
        XCTAssertEqual(closed.resolutionKind, "no_action")
    }

    func testOneReviewReadOnItsOwnNeedsAStatus() throws {
        // The single read must not count a body without a status as open: that read failed.
        XCTAssertEqual(try decode(OfficeSlotReviewRead.self, reviewJSON).review.status, "open")
        let noStatus = reviewJSON.replacingOccurrences(of: #","status":"open"}"#, with: "}")
        XCTAssertNotEqual(noStatus, reviewJSON)
        XCTAssertThrowsError(try decode(OfficeSlotReviewRead.self, noStatus))
        let numberStatus = reviewJSON.replacingOccurrences(of: #""status":"open"}"#, with: #""status":5}"#)
        XCTAssertThrowsError(try decode(OfficeSlotReviewRead.self, numberStatus))
        // A queue row stays lenient, as before.
        XCTAssertEqual(try decode(OfficeSlotReview.self, noStatus).status, "open")
    }

    func testARowWithoutADecisionVersionIsSkipped() throws {
        // Without the version the phone could not book or close it, so it is not offered.
        let page = try decode(OfficeSlotPage.self, #"""
        {"items":[{"id":"018f0000-0000-7000-8000-000000000070","sourceJobId":"018f0000-0000-7000-8000-000000002214","serviceNeed":"x"},
                  \#(reviewJSON)],"nextCursor":"018f0000-0000-7000-8000-000000000066"}
        """#)
        XCTAssertEqual(page.items.map(\.id), ["018f0000-0000-7000-8000-000000000066"])
        XCTAssertEqual(page.nextCursor, "018f0000-0000-7000-8000-000000000066")
    }

    /// POST …/book answers officeReviewAppointmentResultSchema.
    func testDecodesTheBookedAppointment() throws {
        let booked = try decode(OfficeSlotBooked.self, #"""
        {"appointment":{"id":"018f0000-0000-7000-8000-000000000068","organizationId":"018f0000-0000-7000-8000-000000000001",
           "sourceJobId":"018f0000-0000-7000-8000-000000002214","requestedWindow":{"startsAt":"2026-09-02T13:00:00.000Z","endsAt":"2026-09-02T14:00:00.000Z"},
           "plannedWindow":{"startsAt":"2026-09-02T14:00:00.000Z","endsAt":"2026-09-02T15:00:00.000Z"},
           "timeZone":"America/Los_Angeles","serviceNeed":"Install the replacement part","status":"scheduled","version":1},
         "officeReview":{"id":"018f0000-0000-7000-8000-000000000066","status":"superseded",
           "resolution":{"kind":"appointment","appointmentId":"018f0000-0000-7000-8000-000000000068"}}}
        """#)
        XCTAssertEqual(booked.appointment.id, "018f0000-0000-7000-8000-000000000068")
        XCTAssertEqual(booked.appointment.status, "scheduled")
        XCTAssertEqual(booked.appointment.plannedWindow?.startsAt, "2026-09-02T14:00:00.000Z")
    }

    /// The server's strict body: exactly these keys, instants with milliseconds in UTC, a fresh intent.
    func testTheBookRequestMatchesTheServersSchema() throws {
        let review = try decode(OfficeSlotReview.self, reviewJSON)
        let start = ISO8601DateFormatter().date(from: "2026-09-02T14:00:00Z")!.addingTimeInterval(0.4)
        let intent = UUID(uuidString: "018F0000-0000-7000-8000-000000000013")!
        let request = try XCTUnwrap(OfficeSlotRules.bookRequest(for: review, start: start, minutes: 60, intent: intent))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["expectedDecisionVersion", "intentId", "plannedWindow"])
        XCTAssertEqual(json["expectedDecisionVersion"] as? Int, 2)
        XCTAssertEqual(json["intentId"] as? String, "018f0000-0000-7000-8000-000000000013")
        XCTAssertEqual(json["plannedWindow"] as? [String: String],
                       ["startsAt": "2026-09-02T14:00:00.000Z", "endsAt": "2026-09-02T15:00:00.000Z"])
        // The server refuses a window of nothing, or longer than a day.
        XCTAssertNil(OfficeSlotRules.bookRequest(for: review, start: start, minutes: 0))
        XCTAssertNil(OfficeSlotRules.bookRequest(for: review, start: start, minutes: 24 * 60 + 1))
        XCTAssertNotNil(OfficeSlotRules.bookRequest(for: review, start: start, minutes: 24 * 60))
    }

    func testTheResolveRequestMatchesTheServersSchema() throws {
        let review = try decode(OfficeSlotReview.self, reviewJSON)
        let request = OfficeSlotRules.resolveRequest(for: review, reasonCode: "customer_declined")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["expectedDecisionVersion", "resolution"])
        XCTAssertEqual(json["expectedDecisionVersion"] as? Int, 2)
        XCTAssertEqual(json["resolution"] as? [String: String], ["kind": "no_action", "reasonCode": "customer_declined"])
        // Every reason offered is a code the server's bounded-code rule takes.
        for reason in OfficeSlotRules.noActionReasons {
            XCTAssertNotNil(reason.code.range(of: "^[a-z0-9][a-z0-9._:-]*$", options: .regularExpression))
        }
    }

    func testTheSheetOpensOnTheTimeAskedForWhileItIsAhead() throws {
        let review = try decode(OfficeSlotReview.self, reviewJSON)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let before = ISO8601DateFormatter().date(from: "2026-09-01T12:10:00Z")!
        let ahead = OfficeSlotRules.defaultPlan(for: review, now: before, calendar: calendar)
        XCTAssertEqual(ahead.start, ISO8601DateFormatter().date(from: "2026-09-02T13:00:00Z"))
        XCTAssertEqual(ahead.minutes, 60)
        // Once that time has passed: the next full hour, the same length.
        let after = ISO8601DateFormatter().date(from: "2026-09-03T09:20:00Z")!
        let late = OfficeSlotRules.defaultPlan(for: review, now: after, calendar: calendar)
        XCTAssertEqual(late.start, ISO8601DateFormatter().date(from: "2026-09-03T10:00:00Z"))
        XCTAssertEqual(late.minutes, 60)
    }

    /// The words for a failed read of the queue, in the web page's words for the same answer
    /// (office-reviews.tsx PermissionState, ErrorState, and the "Could not read the list again"
    /// warning shown above rows from an earlier read).
    func testAFailedReadOfTheQueueAlwaysSaysWhy() {
        let loadFailed = "Could not load the follow-ups waiting for a slot."
        let readAgain = "Could not read the list again."
        let lastRead = "The rows below are from the last read."
        // A team scope (403 out_of_scope) or rights taken away: the web's no-access words, and no
        // Try again, which could only be refused again.
        let scope = OfficeSlotListProblem(Problem(title: "authorization", status: 403, detail: "out_of_scope", category: "authorization"))
        XCTAssertEqual(scope.kind, .noAccess)
        let noAccess = "Your role can\u{2019}t book follow-ups. Booking a follow-up needs the right to book follow-ups and to assign jobs. An owner or admin can change that."
        XCTAssertEqual(scope.message(rowsListed: false), noAccess)
        XCTAssertEqual(scope.message(rowsListed: true), noAccess)
        XCTAssertFalse(scope.offersRetry(offline: false))
        // A server error, a paging bound and a repeated cursor: the read-failed words with the
        // server's own, and Try again.
        let cases: [(Error, String)] = [
            (Problem(title: "Internal Server Error", status: 500, detail: nil), "Internal Server Error"),
            (Problem(title: "conflict", status: 409, detail: "office review pagination exceeded its scan bound", category: "conflict"),
             "office review pagination exceeded its scan bound"),
            (Problem(title: "conflict", status: 409, detail: "office review pagination did not advance", category: "conflict"),
             "office review pagination did not advance"),
            (Problem(title: "Pagination cursor loop", status: nil, detail: "Repeated or empty cursor"), "Repeated or empty cursor"),
        ]
        for (error, detail) in cases {
            let problem = OfficeSlotListProblem(error)
            XCTAssertEqual(problem.kind, .failed, detail)
            XCTAssertEqual(problem.detail, detail)
            // Nothing listed yet: the follow-ups could not load.
            XCTAssertEqual(problem.message(rowsListed: false), "\(loadFailed) \(detail)")
            // Rows from an earlier read still listed: the list could not be read again.
            XCTAssertEqual(problem.message(rowsListed: true), "\(readAgain) \(detail). \(lastRead)")
            XCTAssertTrue(problem.offersRetry(offline: false), detail)
            // With no connection nothing can be sent, so nothing is offered.
            XCTAssertFalse(problem.offersRetry(offline: true), detail)
        }
        // A detail that already ends a sentence keeps its own stop.
        let stopped = OfficeSlotListProblem(Problem(title: "Unavailable", status: 503, detail: "Try again in a minute."))
        XCTAssertEqual(stopped.message(rowsListed: true), "\(readAgain) Try again in a minute. \(lastRead)")
        let lost = OfficeSlotListProblem(URLError(.networkConnectionLost))
        XCTAssertEqual(lost.kind, .failed)
        XCTAssertTrue(lost.message(rowsListed: false).hasPrefix(loadFailed))
        XCTAssertTrue(lost.message(rowsListed: true).hasPrefix(readAgain))
    }

    /// The queue itself, read through a stubbed server: what Unscheduled says (OfficeSlotQueue.notice,
    /// which the view draws as it is) after each answer, with no rows and with rows.
    func testTheQueueSaysWhyAReadFailedWithOrWithoutRows() async {
        let identity = "user|org|1"
        let page = #"{"items":[\#(reviewJSON)]}"#
        let refused = #"{"title":"authorization","detail":"out_of_scope","category":"authorization"}"#
        let api = APIClient(session: URLProtocolFixture.session([
            .init(500, #"{"title":"Internal Server Error"}"#),
            .init(200, page),
            .init(500, #"{"title":"Internal Server Error"}"#),
            .init(403, refused),
            .init(200, page),
        ]), baseURL: "https://app.thorbis.com")
        let queue = OfficeSlotQueue()
        let failed = OfficeSlotListNotice(kind: .failed,
                                          message: "Could not load the follow-ups waiting for a slot. Internal Server Error",
                                          offersRetry: true)

        // A first read that fails, with nothing listed yet: said, not silence that reads as nothing waiting.
        let first = await queue.reread(api: api, identity: identity)
        XCTAssertFalse(first)
        XCTAssertTrue(queue.reviews.isEmpty)
        XCTAssertEqual(queue.problem?.kind, .failed)
        XCTAssertEqual(queue.notice(offline: false), failed)
        // Offline the words stay, without Try again.
        XCTAssertEqual(queue.notice(offline: true)?.offersRetry, false)

        // A read that works clears it.
        let second = await queue.reread(api: api, identity: identity)
        XCTAssertTrue(second)
        XCTAssertEqual(queue.reviews.map(\.id), ["018f0000-0000-7000-8000-000000000066"])
        XCTAssertNil(queue.problem)
        XCTAssertNil(queue.notice(offline: false))

        // A failure with rows listed: said too, in the web's words for a read that failed again,
        // and the rows stay. Offline it is not repeated beside the offline banner, as on the web.
        await queue.load(api: api, identity: identity)
        XCTAssertEqual(queue.reviews.count, 1)
        XCTAssertEqual(queue.notice(offline: false),
                       OfficeSlotListNotice(kind: .failed,
                                            message: "Could not read the list again. Internal Server Error. The rows below are from the last read.",
                                            offersRetry: true))
        XCTAssertNil(queue.notice(offline: true))

        // A 403 after a good read: the web's no-access words, no Try again, and no rows to Schedule.
        await queue.load(api: api, identity: identity)
        XCTAssertTrue(queue.reviews.isEmpty)
        XCTAssertEqual(queue.problem?.kind, .noAccess)
        XCTAssertEqual(queue.notice(offline: false),
                       OfficeSlotListNotice(kind: .noAccess, message: OfficeSlotListProblem.noAccessMessage, offersRetry: false))

        // Access back: the rows return and nothing is said.
        await queue.load(api: api, identity: identity)
        XCTAssertEqual(queue.reviews.count, 1)
        XCTAssertNil(queue.notice(offline: false))
        XCTAssertEqual(URLProtocolFixture.recorded.count, 5)
        XCTAssertTrue(URLProtocolFixture.recorded.allSatisfy { $0.method == "GET" && $0.url?.path == "/v1/scheduling/office-reviews" })
    }

    func testWords() {
        XCTAssertEqual(OfficeSlotRules.reasonLabel("capacity_conflict"), "Another visit took that time")
        XCTAssertEqual(OfficeSlotRules.reasonLabel("something_new"), "Something new")
        XCTAssertEqual(OfficeSlotRules.countLabel(0), "Nothing is waiting")
        XCTAssertEqual(OfficeSlotRules.countLabel(1), "1 follow-up needs a time")
        XCTAssertEqual(OfficeSlotRules.countLabel(3), "3 follow-ups need a time")
        // The web panel's sentence: the server checks the technician's scheduled appointments.
        XCTAssertEqual(OfficeSlotRules.footer,
                       "Follow-ups the field asked for that could not be booked on their own. Book visit checks the technician\u{2019}s other booked visits before it books.")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let label = OfficeSlotRules.windowLabel(OfficeSlotWindow(startsAt: "2026-09-02T13:00:00.000Z", endsAt: "2026-09-02T14:00:00.000Z"),
                                                calendar: calendar, locale: Locale(identifier: "en_US"))
        XCTAssertEqual(label?.replacingOccurrences(of: "\u{202F}", with: " "), "Wed, Sep 2, 1:00 PM \u{2013} 2:00 PM")
        XCTAssertNil(OfficeSlotRules.windowLabel(OfficeSlotWindow(startsAt: "soon", endsAt: "later")))
    }
}

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

    func testWords() {
        XCTAssertEqual(OfficeSlotRules.reasonLabel("capacity_conflict"), "Another visit took that time")
        XCTAssertEqual(OfficeSlotRules.reasonLabel("something_new"), "Something new")
        XCTAssertEqual(OfficeSlotRules.countLabel(0), "Nothing is waiting")
        XCTAssertEqual(OfficeSlotRules.countLabel(1), "1 follow-up needs a time")
        XCTAssertEqual(OfficeSlotRules.countLabel(3), "3 follow-ups need a time")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let label = OfficeSlotRules.windowLabel(OfficeSlotWindow(startsAt: "2026-09-02T13:00:00.000Z", endsAt: "2026-09-02T14:00:00.000Z"),
                                                calendar: calendar, locale: Locale(identifier: "en_US"))
        XCTAssertEqual(label?.replacingOccurrences(of: "\u{202F}", with: " "), "Wed, Sep 2, 1:00 PM \u{2013} 2:00 PM")
        XCTAssertNil(OfficeSlotRules.windowLabel(OfficeSlotWindow(startsAt: "soon", endsAt: "later")))
    }
}

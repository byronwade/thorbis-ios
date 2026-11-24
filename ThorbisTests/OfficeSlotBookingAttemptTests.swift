import XCTest
@testable import Thorbis

/// One booking id per waiting follow-up, kept by the queue across Schedule sheets until the server
/// books it, and the words each answer shows. One test per state change. The server behaviour
/// these follow is in domains/scheduling authority.ts bookAppointment and resolveNoAction.
final class OfficeSlotBookingAttemptTests: XCTestCase {
    private let intent = UUID(uuidString: "018F0000-0000-7000-8000-0000000000C7")!
    private let id = "018f0000-0000-7000-8000-0000000000c7"
    private let two = OfficeSlotWindow(startsAt: "2026-11-25T14:00:00.000Z", endsAt: "2026-11-25T16:00:00.000Z")
    private let four = OfficeSlotWindow(startsAt: "2026-11-25T16:00:00.000Z", endsAt: "2026-11-25T18:00:00.000Z")
    private let six = OfficeSlotWindow(startsAt: "2026-11-25T18:00:00.000Z", endsAt: "2026-11-25T20:00:00.000Z")
    private func label(_ window: OfficeSlotWindow) -> String { window == two ? "2 PM" : window == four ? "4 PM" : "6 PM" }
    private let lost = "This follow-up was already booked. Your first try was for 2 PM. This try, for 4 PM, didn\u{2019}t book another visit. The list has been read again."
    private let alreadyBooked = "This follow-up was already booked. The list has been read again."

    private func attempt() -> OfficeSlotBookingAttempt { OfficeSlotBookingAttempt(intent: intent) }

    func testBookSendsTheAttemptsIdAndASecondTapSendsNothing() throws {
        var a = attempt()
        let request = a.request(decisionVersion: 2, window: two)
        XCTAssertEqual(request, OfficeSlotBookRequest(expectedDecisionVersion: 2, intentId: id, plannedWindow: two))
        XCTAssertNil(a.request(decisionVersion: 2, window: two))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(XCTUnwrap(request))) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["expectedDecisionVersion", "intentId", "plannedWindow"])
    }

    func testBookedEndsTheSheet() {
        var a = attempt()
        _ = a.request(decisionVersion: 2, window: two)
        XCTAssertNil(a.settle(.booked, label: label))
        XCTAssertEqual(a.phase, .booked)
        XCTAssertNil(a.request(decisionVersion: 2, window: two))
    }

    func testNoAnswerIsUnconfirmedAndNeverSaysItFailed() {
        var a = attempt()
        _ = a.request(decisionVersion: 2, window: two)
        XCTAssertEqual(a.settle(.noAnswer, label: label), OfficeSlotBookingAttempt.noAnswerMessage)
        XCTAssertEqual(a.phase, .unconfirmed(first: two))
        XCTAssertFalse((a.words ?? "").contains("Could not"))
    }

    func testBookingAgainAfterNoAnswerSendsTheSameRequestAndAReplaySaysBooked() {
        var a = attempt()
        let first = a.request(decisionVersion: 2, window: two)
        a.settle(.noAnswer, label: label)
        XCTAssertEqual(a.request(decisionVersion: 2, window: two), first)
        XCTAssertNil(a.settle(.booked, label: label))
        XCTAssertEqual(a.phase, .booked)
    }

    func testAnotherNoAnswerKeepsTheFirstTime() {
        var a = attempt()
        _ = a.request(decisionVersion: 2, window: two)
        a.settle(.noAnswer, label: label)
        XCTAssertEqual(a.request(decisionVersion: 2, window: four)?.intentId, id)
        XCTAssertEqual(a.settle(.noAnswer, label: label), OfficeSlotBookingAttempt.noAnswerMessage)
        XCTAssertEqual(a.phase, .unconfirmed(first: two))
        XCTAssertEqual(a.request(decisionVersion: 2, window: six)?.intentId, id)
        XCTAssertEqual(a.settle(.alreadyUsed, label: label),
                       "This follow-up was already booked. Your first try was for 2 PM. This try, for 6 PM, didn\u{2019}t book another visit. The list has been read again.")
    }

    func testANewTimeAfterNoAnswerThatWasAlreadyUsedNamesTheFirstTime() {
        var a = attempt()
        _ = a.request(decisionVersion: 2, window: two)
        a.settle(.noAnswer, label: label)
        _ = a.request(decisionVersion: 2, window: four)
        let words = a.settle(.alreadyUsed, label: label)
        XCTAssertEqual(words, lost)
        XCTAssertFalse((words ?? "").contains("Booked:"))
        XCTAssertEqual(a.phase, .alreadyBooked)
    }

    func testTheSameTimeAfterNoAnswerThatWasAlreadyUsedSaysOnlyThatItWasAlreadyBooked() {
        var a = attempt()
        _ = a.request(decisionVersion: 2, window: two)
        a.settle(.noAnswer, label: label)
        _ = a.request(decisionVersion: 2, window: two)
        // The visit may well be at 2 PM (another person booked that time), so no time is named.
        let words = a.settle(.alreadyUsed, label: label)
        XCTAssertEqual(words, alreadyBooked)
        XCTAssertFalse((words ?? "").contains("2 PM"))
        XCTAssertEqual(a.phase, .alreadyBooked)
    }

    func testAFirstTryThatWasAlreadyUsedSaysItWasAlreadyBookedAndNamesNoTime() {
        // Two people opened the same follow-up and both kept the asked-for 2 PM; the other booked it.
        var a = attempt()
        _ = a.request(decisionVersion: 2, window: two)
        let words = a.settle(.alreadyUsed, label: label)
        XCTAssertEqual(words, alreadyBooked)
        XCTAssertFalse((words ?? "").contains("2 PM"))
        XCTAssertFalse((words ?? "").contains("was not"))
        XCTAssertEqual(a.phase, .alreadyBooked)
    }

    func testAnAttemptKeptByTheQueueSurvivesClosingTheSheet() {
        var store = OfficeSlotBookingAttempts()
        // First sheet: Book at 2 PM, no answer.
        var first = store.attempt(for: "review-1")
        let sentFirst = first.request(decisionVersion: 2, window: two)
        store.keep(first, for: "review-1")
        var settled = first
        XCTAssertEqual(settled.settle(.noAnswer, label: label), OfficeSlotBookingAttempt.noAnswerMessage)
        store.keep(settled, for: "review-1")
        // Cancel, then Schedule on the same row: the new sheet reads the same attempt.
        var second = store.attempt(for: "review-1")
        XCTAssertEqual(second.phase, .unconfirmed(first: two))
        XCTAssertEqual(second.request(decisionVersion: 2, window: two), sentFirst)
        // The server replays the booking the first try made: the sheet says Booked.
        XCTAssertNil(second.settle(.booked, label: label))
        // Another follow-up gets its own id.
        let other = store.attempt(for: "review-2")
        XCTAssertNotEqual(other.intentId, sentFirst?.intentId)
    }

    func testTheQueueDropsItsAttemptsWhenTheWorkspaceChanges() {
        var store = OfficeSlotBookingAttempts()
        var a = store.attempt(for: "review-1")
        _ = a.request(decisionVersion: 2, window: two)
        store.keep(a, for: "review-1")
        store.removeAll()
        // A late answer for the old workspace is not put back.
        a.settle(.noAnswer, label: label)
        store.keep(a, for: "review-1")
        let fresh = store.attempt(for: "review-1")
        XCTAssertNotEqual(fresh.intentId, a.intentId)
        XCTAssertEqual(fresh.phase, .fresh)
        XCTAssertNil(fresh.sending)
    }

    func testARefusedFirstTryLeavesTheNextTryFresh() {
        var a = attempt()
        _ = a.request(decisionVersion: 2, window: two)
        XCTAssertEqual(a.settle(.refused("appointment capacity is unavailable for this office review"), label: label),
                       "Could not book this follow-up: appointment capacity is unavailable for this office review. The list has been read again.")
        XCTAssertEqual(a.phase, .fresh)
        // The server writes nothing for a refused request, so the same id is free again.
        XCTAssertEqual(a.request(decisionVersion: 2, window: four),
                       OfficeSlotBookRequest(expectedDecisionVersion: 2, intentId: id, plannedWindow: four))
        a.settle(.noAnswer, label: label)
        XCTAssertEqual(a.phase, .unconfirmed(first: four))
    }

    func testARefusalAfterNoAnswerStaysUnconfirmed() {
        var a = attempt()
        _ = a.request(decisionVersion: 2, window: two)
        a.settle(.noAnswer, label: label)
        _ = a.request(decisionVersion: 2, window: four)
        XCTAssertEqual(a.settle(.refused("appointment capacity is unavailable for this office review"), label: label),
                       "Thorbis turned down this try: appointment capacity is unavailable for this office review. Your first try, for 2 PM, may still have gone through. Tap Book visit again to check.")
        XCTAssertEqual(a.phase, .unconfirmed(first: two))
    }

    func testOnceAlreadyBookedNothingMoreIsSent() {
        var a = attempt()
        _ = a.request(decisionVersion: 2, window: two)
        a.settle(.noAnswer, label: label)
        _ = a.request(decisionVersion: 2, window: four)
        a.settle(.alreadyUsed, label: label)
        XCTAssertNil(a.request(decisionVersion: 2, window: four))
        XCTAssertEqual(a.words, lost)
    }

    func testAnAnswerWithNothingInFlightChangesNothing() {
        var a = attempt()
        XCTAssertNil(a.settle(.booked, label: label))
        XCTAssertEqual(a.phase, .fresh)
    }

    func testEachAttemptMakesItsOwnLowercaseId() {
        XCTAssertNotEqual(OfficeSlotBookingAttempt().intentId, OfficeSlotBookingAttempt().intentId)
        let made = OfficeSlotBookingAttempt().intentId
        XCTAssertEqual(made, made.lowercased())
        XCTAssertNotNil(UUID(uuidString: made))
    }

    func testSortsTheErrorsTheAPIClientThrows() {
        let used = Problem(title: "conflict", status: 409, detail: OfficeSlotBookingAttempt.alreadyUsedDetail, category: "conflict")
        XCTAssertEqual(OfficeSlotBookingAttempt.answer(for: used), .alreadyUsed)
        XCTAssertEqual(OfficeSlotBookingAttempt.answer(for: Problem(title: "conflict", status: 409, detail: "office review is already closed", category: "conflict")),
                       .refused("office review is already closed"))
        XCTAssertEqual(OfficeSlotBookingAttempt.answer(for: Problem(title: "authorization", status: 403, detail: "not permitted: job.assign (no_grant)", category: "authorization")),
                       .refused("not permitted: job.assign (no_grant)"))
        XCTAssertEqual(OfficeSlotBookingAttempt.answer(for: Problem(title: "validation", status: 400, detail: "invalid office appointment request", category: "validation")),
                       .refused("invalid office appointment request"))
        XCTAssertEqual(OfficeSlotBookingAttempt.answer(for: Problem(title: "not found", status: 404, detail: nil, category: "not_found")), .refused("not found"))
        for status in [408, 429, 500, 502, 503] {
            XCTAssertEqual(OfficeSlotBookingAttempt.answer(for: Problem(title: "x", status: status, detail: "y")), .noAnswer, "\(status)")
        }
        // The book route answers 201 only for a booking it made or replayed. A 200 that can't be read
        // could be a Wi-Fi sign-in page, so it is no answer.
        XCTAssertEqual(OfficeSlotBookingAttempt.answer(for: Problem(title: "Invalid API response", status: 201, detail: "x")), .booked)
        XCTAssertEqual(OfficeSlotBookingAttempt.answer(for: Problem(title: "Invalid API response", status: 200, detail: "x")), .noAnswer)
        XCTAssertEqual(OfficeSlotBookingAttempt.answer(for: Problem(title: "Network error", status: nil, detail: "x")), .noAnswer)
        XCTAssertEqual(OfficeSlotBookingAttempt.answer(for: Problem(title: "Network error", status: nil, detail: "x", neverSent: true)), .noAnswer)
        XCTAssertEqual(OfficeSlotBookingAttempt.answer(for: URLError(.timedOut)), .noAnswer)
        XCTAssertEqual(OfficeSlotBookingAttempt.answer(for: URLError(.notConnectedToInternet)), .noAnswer)
        XCTAssertEqual(OfficeSlotBookingAttempt.answer(for: CancellationError()), .noAnswer)
        XCTAssertEqual(OfficeSlotBookingAttempt.answer(for: Problem(title: "x", status: 500, detail: OfficeSlotBookingAttempt.alreadyUsedDetail)), .noAnswer)
    }

    func testNoVisitNeededWords() {
        XCTAssertEqual(OfficeSlotCloseWords.answer(for: Problem(title: "conflict", status: 409, detail: "office review is already closed", category: "conflict")),
                       .refused("office review is already closed"))
        XCTAssertEqual(OfficeSlotCloseWords.answer(for: URLError(.networkConnectionLost)), .noAnswer)
        XCTAssertEqual(OfficeSlotCloseWords.answer(for: CancellationError()), .noAnswer)
        XCTAssertEqual(OfficeSlotCloseWords.words(.noAnswer, stillWaiting: true), OfficeSlotCloseWords.noAnswerMessage)
        XCTAssertEqual(OfficeSlotCloseWords.words(.noAnswer, stillWaiting: false), OfficeSlotCloseWords.noAnswerMessage)
        XCTAssertEqual(OfficeSlotCloseWords.words(.refused("office review decision version is no longer current"), stillWaiting: false),
                       "This follow-up is no longer waiting. The list has been read again.")
        XCTAssertEqual(OfficeSlotCloseWords.words(.refused("office review job is no longer current"), stillWaiting: true),
                       "Could not close this follow-up: office review job is no longer current. The list has been read again.")
    }
}

import Foundation

/// One booking id and the time first sent with it, for one waiting follow-up. The queue keeps it
/// (OfficeSlotBookingAttempts), so closing and opening the Schedule sheet again sends the same id.
///
/// The server ties a booking to its intent id (domains/scheduling authority.ts bookAppointment):
/// the same id with the same window replays the booking it made, and once the review is booked any
/// other id or window answers 409 "office appointment intent was already used with different
/// facts". A refused request writes nothing (the whole request is one transaction, and every
/// refusal is thrown before or rolls back the insert), so the id is free again after a refusal and
/// it is kept for every try. That way a first try whose answer was lost is recognised
/// whatever happens next, and nothing is ever booked twice.
struct OfficeSlotBookingAttempt: Equatable {
    /// What a booking request got back, sorted from the error the API client threw (`answer(for:)`).
    enum Answer: Equatable {
        /// The server made the booking, or replayed the one this id made.
        case booked
        /// A 4xx answer for this request: it was not booked by it. The server's own words.
        case refused(String)
        /// The review is already booked, and not by this id with these facts. The server does not say
        /// when that visit is, so the words never say which time was or was not booked.
        case alreadyUsed
        /// No answer, an answer that could not be read, or a send the phone cannot be sure never left.
        case noAnswer
    }

    enum Phase: Equatable {
        /// Nothing sent yet, or every try so far was refused.
        case fresh
        /// A try got no answer and may have booked the follow-up; `first` is the time it was sent for.
        case unconfirmed(first: OfficeSlotWindow)
        /// The server answered that the follow-up was already booked. The sheet sends nothing more.
        case alreadyBooked
        /// The server booked it.
        case booked
    }

    /// The server's words for a review booked with another id or another time.
    static let alreadyUsedDetail = "office appointment intent was already used with different facts"
    static let noAnswerMessage = "No answer from Thorbis, so this phone can\u{2019}t tell if the visit was booked. Tap Book visit again to check."
    static let alreadyBookedMessage = "This follow-up was already booked. The list has been read again."

    /// Lowercase, as the server's uuid schema and the other requests send it.
    let intentId: String
    private(set) var phase: Phase = .fresh
    /// The window of the request in flight, nil when none is.
    private(set) var sending: OfficeSlotWindow?
    /// The words last shown for a settled answer, kept so a tap after the sheet is done repeats them.
    private(set) var words: String?

    init(intent: UUID = UUID()) {
        intentId = intent.uuidString.lowercased()
    }

    var isDone: Bool { phase == .alreadyBooked || phase == .booked }

    /// The request to send for this window: always this attempt's id. Nil while a request is in flight
    /// or once the server has booked the follow-up.
    mutating func request(decisionVersion: Int, window: OfficeSlotWindow) -> OfficeSlotBookRequest? {
        guard sending == nil, !isDone else { return nil }
        sending = window
        return OfficeSlotBookRequest(expectedDecisionVersion: decisionVersion, intentId: intentId, plannedWindow: window)
    }

    /// Settles the request in flight. Returns the words to show, or nil when it was booked (the
    /// sheet then says Booked as it always has). `label` writes a window the way staff read it.
    @discardableResult
    mutating func settle(_ answer: Answer, label: (OfficeSlotWindow) -> String) -> String? {
        guard let sent = sending else { return nil }
        sending = nil
        let next: (Phase, String?)
        switch (phase, answer) {
        case (_, .booked):
            next = (.booked, nil)
        case (.fresh, .noAnswer):
            next = (.unconfirmed(first: sent), Self.noAnswerMessage)
        case (.unconfirmed, .noAnswer):
            next = (phase, Self.noAnswerMessage)
        case let (.fresh, .refused(reason)):
            next = (.fresh, "Could not book this follow-up: \(reason). The list has been read again.")
        case let (.unconfirmed(first), .refused(reason)):
            // The server checks the job, the rights and the version before it looks at whether the
            // review was booked, so this refusal says nothing about the first try.
            next = (phase, "Thorbis turned down this try: \(reason). Your first try, for \(label(first)), may still have gone through. Tap Book visit again to check.")
        case let (.unconfirmed(first), .alreadyUsed) where first != sent:
            next = (.alreadyBooked, "This follow-up was already booked. Your first try was for \(label(first)). This try, for \(label(sent)), didn\u{2019}t book another visit. The list has been read again.")
        case (_, .alreadyUsed):
            next = (.alreadyBooked, Self.alreadyBookedMessage)
        case (.alreadyBooked, _), (.booked, _):
            next = (phase, words)
        }
        phase = next.0
        words = next.1
        return next.1
    }

    /// Sorts what the API client threw, with the refund screen's sorting (RefundSendFailure): a 4xx
    /// other than 408 and 429 is a refusal; anything else may have reached the server. A 201 whose
    /// body could not be read is booked: the book route answers 201 only for a booking it made or
    /// replayed, and both carry the window that was sent.
    static func answer(for error: Error) -> Answer {
        if let problem = error as? Problem, problem.status == 201 { return .booked }
        switch RefundSendFailure.of(error) {
        case .notSent, .unconfirmed:
            return .noAnswer
        case .refusedUpFront, .refused:
            let problem = error as? Problem
            if problem?.status == 409, problem?.detail == alreadyUsedDetail { return .alreadyUsed }
            return .refused(problem?.detail ?? problem?.title ?? error.localizedDescription)
        }
    }
}

/// The booking attempts of one workspace's queue, by follow-up. The Schedule sheet lasts only while
/// it is shown, so it reads its attempt from here and puts it back after every change.
struct OfficeSlotBookingAttempts {
    private var byReview: [String: OfficeSlotBookingAttempt] = [:]

    /// The attempt for this follow-up, made and kept the first time it is asked for.
    mutating func attempt(for reviewId: String) -> OfficeSlotBookingAttempt {
        if let kept = byReview[reviewId] { return kept }
        let made = OfficeSlotBookingAttempt()
        byReview[reviewId] = made
        return made
    }

    /// Puts back a changed copy. Ignored when the store no longer holds that id, because the
    /// workspace or the sign-in changed while the request was out.
    mutating func keep(_ attempt: OfficeSlotBookingAttempt, for reviewId: String) {
        guard byReview[reviewId]?.intentId == attempt.intentId else { return }
        byReview[reviewId] = attempt
    }

    mutating func removeAll() { byReview = [:] }
}

/// The words for "No visit needed" when it does not come back closed. Closing has no id of its
/// own: the server replays a close with the same reason (authority.ts resolveNoAction), and
/// refuses any other close of a review that is no longer open.
enum OfficeSlotCloseWords {
    enum Answer: Equatable {
        case refused(String)
        case noAnswer
    }

    static let noAnswerMessage = "No answer from Thorbis, so this phone can\u{2019}t tell if the follow-up was closed. Pick the same reason again to check."
    static let noLongerWaitingMessage = "This follow-up is no longer waiting. The list has been read again."

    static func answer(for error: Error) -> Answer {
        switch RefundSendFailure.of(error) {
        case .notSent, .unconfirmed:
            return .noAnswer
        case .refusedUpFront, .refused:
            let problem = error as? Problem
            return .refused(problem?.detail ?? problem?.title ?? error.localizedDescription)
        }
    }

    /// - Parameter stillWaiting: whether a fresh read of the queue, made after the answer, still
    ///   lists the follow-up. Pass true when that read failed: then nothing more is known.
    static func words(_ answer: Answer, stillWaiting: Bool) -> String {
        switch answer {
        case .noAnswer:
            return noAnswerMessage
        case let .refused(reason):
            return stillWaiting ? "Could not close this follow-up: \(reason). The list has been read again." : noLongerWaitingMessage
        }
    }
}

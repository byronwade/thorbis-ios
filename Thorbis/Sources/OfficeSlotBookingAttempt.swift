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
///
/// The server checks the job as it stands now before it replays a booking it made, so once the job
/// was reassigned, moved or canceled every further try with this id is refused (409 "office review
/// job facts are no longer current" or "office review job is no longer current"), even when the
/// first try booked it. So a refusal while unconfirmed reads the follow-up once
/// (GET /v1/scheduling/office-reviews/{id}, `check(_:reviewId:)`): booking closes the review in the
/// same transaction, so that read tells whether it was booked, closed without a visit, or is still
/// open. The web page (office-review-booking.ts checkOfficeReviewAttempt) follows the same rule
/// with the same words.
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
        /// A read of the follow-up, after a refused try that followed one with no answer, showed it
        /// was closed without a visit. The sheet sends nothing more.
        case closed
    }

    /// What the one read of the follow-up got back.
    enum ReviewCheck: Equatable {
        case read(OfficeSlotReview)
        /// 403, 404, no answer, or an answer that could not be read.
        case unread
    }

    /// The server's words for a review booked with another id or another time.
    static let alreadyUsedDetail = "office appointment intent was already used with different facts"
    static let noAnswerMessage = "No answer from Thorbis, so this phone can\u{2019}t tell if the visit was booked. Tap Book visit again to check."
    static let alreadyBookedMessage = "This follow-up was already booked. The list has been read again."
    static let checkedClosedMessage = "This follow-up was closed without a visit. The list has been read again."
    /// Added to the unconfirmed words when the follow-up could not be read.
    static let checkUnreadNote = "The follow-up couldn\u{2019}t be read to check."
    static let listReadAgain = " The list has been read again."
    static let listNotReadAgain = " The list couldn\u{2019}t be read again."

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

    var isDone: Bool { phase == .alreadyBooked || phase == .booked || phase == .closed }

    /// The request to send for this window: always this attempt's id. Nil while a request is in flight
    /// or once the attempt is done (booked, already booked, or closed).
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
        case (.alreadyBooked, _), (.booked, _), (.closed, _):
            next = (phase, words)
        }
        phase = next.0
        words = next.1
        return next.1
    }

    /// Whether a refused try should read the follow-up: only while a try may have booked it.
    var needsCheck: Bool {
        guard sending == nil, case .unconfirmed = phase else { return false }
        return true
    }

    /// Acts on the one read of the follow-up made after a refused try while unconfirmed. Changes
    /// nothing in any other state or while a request is in flight.
    /// - booked by an appointment: already booked. The read does not say by which id, so the words
    ///   name no time, and nothing more is sent.
    /// - closed with no visit: closed, and nothing more is sent.
    /// - still open: nothing booked it; the refusal words stay.
    /// - unread, an answer about another review, or one the server's schema does not allow: nothing
    ///   more is known; the unconfirmed words stay and say the follow-up couldn't be read.
    mutating func check(_ result: ReviewCheck, reviewId: String) {
        guard needsCheck else { return }
        var review: OfficeSlotReview?
        if case let .read(read) = result, read.id == reviewId { review = read }
        if let review, review.status == "open" { return }
        if let review, review.resolutionKind == "appointment" {
            phase = .alreadyBooked
            words = Self.alreadyBookedMessage
        } else if let review, review.status == "resolved", review.resolutionKind == "no_action" {
            phase = .closed
            words = Self.checkedClosedMessage
        } else if !(words?.hasSuffix(Self.checkUnreadNote) ?? false) {
            // Said once, however many times the same refusal is checked.
            words = words.map { "\($0) \(Self.checkUnreadNote)" } ?? Self.checkUnreadNote
        }
    }

    /// The words say "The list has been read again." only when it was.
    static func wordsAfterReread(_ words: String, listRead: Bool) -> String {
        guard !listRead, words.hasSuffix(listReadAgain) else { return words }
        return String(words.dropLast(listReadAgain.count)) + listNotReadAgain
    }

    /// Tells the settled words whether the list was read again after the answer.
    mutating func noteReread(listRead: Bool) {
        guard sending == nil, let words else { return }
        self.words = Self.wordsAfterReread(words, listRead: listRead)
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

    /// Puts back a changed copy. Ignored, and false, when the store no longer holds that id,
    /// because the workspace or the sign-in changed while the request was out.
    @discardableResult
    mutating func keep(_ attempt: OfficeSlotBookingAttempt, for reviewId: String) -> Bool {
        guard byReview[reviewId]?.intentId == attempt.intentId else { return false }
        byReview[reviewId] = attempt
        return true
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
    /// - Parameter listRead: false when that read failed, so the words don't say it was read.
    static func words(_ answer: Answer, stillWaiting: Bool, listRead: Bool = true) -> String {
        switch answer {
        case .noAnswer:
            return noAnswerMessage
        case let .refused(reason):
            guard stillWaiting else { return noLongerWaitingMessage }
            return OfficeSlotBookingAttempt.wordsAfterReread(
                "Could not close this follow-up: \(reason).\(OfficeSlotBookingAttempt.listReadAgain)", listRead: listRead)
        }
    }
}

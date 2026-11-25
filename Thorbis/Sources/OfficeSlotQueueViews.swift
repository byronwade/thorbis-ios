import SwiftUI

// Paper 57F "Waiting for a slot" (and 20S, its rows on Jobs): the follow-ups the office has to
// book by hand, each with a Schedule pill. Schedule books through the server, which checks the
// technician's other booked visits; "No visit needed" closes the follow-up with a reason.

/// The queue inside Schedule's Unscheduled list: it loads itself and draws nothing for a role that
/// cannot book, or while nothing is waiting, and says when a read failed (OfficeSlotQueue.notice).
struct OfficeSlotQueueSection: View {
    var roster: [String: String] = [:]
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @StateObject private var queue = OfficeSlotQueue()

    private var allowed: Bool { OfficeSlotQueue.allowed(session) }

    var body: some View {
        Group {
            if allowed { OfficeSlotQueueList(queue: queue, roster: roster) }
        }
        .task(id: "\(OfficeSlotQueue.identity(session))|\(session.isOffline)|\(allowed)") {
            guard allowed, !session.isOffline else { return }
            await queue.load(api: api, identity: OfficeSlotQueue.identity(session))
        }
    }
}

/// The rows (Paper 57F): what is needed in 16 Semibold, who and which job in 14 muted, what was
/// asked for and why it is here in 13, and a 40pt Schedule pill.
struct OfficeSlotQueueList: View {
    @ObservedObject var queue: OfficeSlotQueue
    let roster: [String: String]
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var store: Store
    @State private var scheduling: OfficeSlotReview?
    /// What was just booked or closed, said under the heading until the next change.
    @State private var lastDone: String?
    @State private var doneCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The queue decides when to speak and in which words (OfficeSlotQueue.notice).
            if let notice = queue.notice(offline: session.isOffline) {
                ErrorBanner(message: notice.message,
                            symbol: notice.kind == .noAccess ? "lock" : "exclamationmark.triangle",
                            tint: notice.kind == .noAccess ? Theme.muted : Theme.warning,
                            action: notice.offersRetry ? ErrorBanner.Action(title: "Try again") {
                                await queue.load(api: api, identity: OfficeSlotQueue.identity(session))
                            } : nil)
            }
            if !queue.reviews.isEmpty || lastDone != nil {
                HStack(alignment: .firstTextBaseline) {
                    Text("Waiting for a slot").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    Text("\(queue.reviews.count)").font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .accessibilityLabel(OfficeSlotRules.countLabel(queue.reviews.count))
                }
                .padding(.horizontal, PaperCardMetrics.margin + 4).padding(.top, 20).padding(.bottom, 8)
                if let lastDone {
                    Label(lastDone, systemImage: "checkmark.circle.fill")
                        .font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.success)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, PaperCardMetrics.margin + 4)
                        .padding(.bottom, 8)
                        .accessibilityIdentifier("slotqueue-done")
                }
            }
            if !queue.reviews.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(queue.reviews.enumerated()), id: \.element.id) { index, review in
                        if index > 0 { WellDivider(leading: 16) }
                        row(review)
                    }
                }
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .paperCardMargin()
                Text(OfficeSlotRules.footer)
                    .font(Theme.font(13)).foregroundStyle(Theme.subtle)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, PaperCardMetrics.margin + 4).padding(.top, 12)
            }
        }
        .sensoryFeedback(.success, trigger: doneCount)
        .sheet(item: $scheduling) { review in
            SheetSurface {
                // The queue's attempt for this follow-up: a sheet opened again after no answer
                // starts on the time that try was sent for, with the words it last showed.
                OfficeSlotBookSheet(queue: queue, review: review, attempt: queue.bookingAttempts.attempt(for: review.id),
                                    customer: customer(review),
                                    technician: review.technicianId.flatMap { roster[$0] }) { message in
                    lastDone = message
                    doneCount += 1
                    AccessibilityNotification.Announcement(message).post()
                }
            }
        }
    }

    private func customer(_ review: OfficeSlotReview) -> String? {
        // Only a name the phone really has: no stand-in when the customer list has not loaded.
        guard let id = review.customerId else { return nil }
        return store.customers.first { $0.id == id }?.name
    }

    private func row(_ review: OfficeSlotReview) -> some View {
        let who = [customer(review), review.jobRef].compactMap { $0 }.joined(separator: " \u{00B7} ")
        let asked = OfficeSlotRules.windowLabel(review.requestedWindow).map { "Asked for \($0)" }
        let why = [asked, OfficeSlotRules.reasonLabel(review.reasonCode)].compactMap { $0 }.joined(separator: " \u{00B7} ")
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(review.serviceNeed).font(Theme.font(16, weight: .semibold)).foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Text(who).font(Theme.font(14)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Text(why).font(Theme.font(13)).foregroundStyle(Theme.subtle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            Button { scheduling = review } label: {
                // The same row action as the dispatch board's Assign / Schedule.
                Text("Schedule").lineLimit(1).fixedSize().paperButton(.secondary, tone: .tinted)
            }
            .buttonStyle(PressStyle())
            .disabled(session.isOffline)
            .opacity(session.isOffline ? 0.5 : 1)
            .accessibilityLabel("Schedule \(review.serviceNeed)")
            .accessibilityHint(session.isOffline ? "Needs a connection" : "Pick a time and book it")
            .accessibilityIdentifier("slotqueue-schedule-\(review.id)")
        }
        .padding(.vertical, 14).padding(.leading, 16).padding(.trailing, 12)
        .frame(minHeight: 64)
    }
}

/// The Schedule sheet for one waiting follow-up: when it starts and how long, then "Book visit".
/// The technician is the one the follow-up was asked for; the server holds their time or says why
/// it cannot. "No visit needed" closes the follow-up instead.
struct OfficeSlotBookSheet: View {
    @ObservedObject var queue: OfficeSlotQueue
    let review: OfficeSlotReview
    let customer: String?
    let technician: String?
    /// Called with a sentence once the server has booked or closed it.
    let onDone: (String) -> Void
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var minutes: Int
    @State private var busy = false
    @State private var problem: String?
    @State private var confirmClose = false
    /// The last copy of this follow-up's attempt put back in the queue: what the sheet offers.
    @State private var attempt: OfficeSlotBookingAttempt

    private static let lengths = [60, 120, 180, 240]

    /// - Parameter attempt: the queue's attempt for this follow-up (`OfficeSlotBookingAttempts`).
    init(queue: OfficeSlotQueue, review: OfficeSlotReview, attempt: OfficeSlotBookingAttempt,
         customer: String?, technician: String?, onDone: @escaping (String) -> Void) {
        self.queue = queue
        self.review = review
        self.customer = customer
        self.technician = technician
        self.onDone = onDone
        let plan = attempt.openingPlan(for: review)
        _start = State(initialValue: plan.start)
        _minutes = State(initialValue: plan.minutes)
        _problem = State(initialValue: attempt.sheetWords)
        _attempt = State(initialValue: attempt)
    }

    private var subtitle: String { [customer, review.jobRef].compactMap { $0 }.joined(separator: " \u{00B7} ") }
    /// The lengths offered, with the length the field asked for when it is not one of them.
    private var lengths: [Int] { (Self.lengths + [minutes]).reduce(into: [Int]()) { if !$0.contains($1) { $0.append($1) } }.sorted() }

    var body: some View {
        ThorbisModalSheet(title: "Schedule follow-up", subtitle: subtitle, closeLabel: "Cancel",
                          onClose: busy ? nil : { dismiss() }, detents: [.large],
                          commitTitle: "Book visit", busy: busy,
                          commitDisabledReason: session.isOffline ? "Booking needs a connection." : nil,
                          commitIdentifier: "slotqueue-book", commit: { book() }) {
            if let problem { ErrorBanner(message: problem, outer: 0) }
            ThorbisSheetGroup {
                fact("Needed", review.serviceNeed)
                if let asked = OfficeSlotRules.windowLabel(review.requestedWindow) {
                    WellDivider(leading: 16)
                    fact("Asked for", asked)
                }
                WellDivider(leading: 16)
                fact("Technician", technician ?? (review.technicianId == session.user?.id ? "You" : "The technician it was asked for"))
                WellDivider(leading: 16)
                fact("Why it\u{2019}s here", OfficeSlotRules.reasonLabel(review.reasonCode))
            }
            ThorbisSheetField(label: "Starts") {
                DatePicker("Starts", selection: $start, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
                    .font(Theme.font(16)).foregroundStyle(Theme.foreground).tint(Theme.brand)
                    .padding(.horizontal, 16).frame(minHeight: 56)
                    .background(Theme.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityIdentifier("slotqueue-start")
            }
            ThorbisSheetField(label: "Length", help: "Ends \(end.formatted(date: .omitted, time: .shortened)). The technician\u{2019}s time is held for this long.") {
                FlowRow(spacing: 8, lineSpacing: 8) {
                    ForEach(lengths, id: \.self) { length in
                        let on = length == minutes
                        Button { minutes = length } label: {
                            PaperChoiceChipLabel(title: Self.lengthLabel(length), isOn: on)
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityAddTraits(on ? .isSelected : [])
                        .accessibilityIdentifier("slotqueue-length-\(length)")
                    }
                }
            }
            Text("Booking doesn\u{2019}t message the customer. Tell them the time yourself.")
                .font(Theme.font(13)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
            Button { confirmClose = true } label: {
                Text("No visit needed").font(Theme.font(15, weight: .semibold)).foregroundStyle(Theme.destructive)
                    .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .disabled(!attempt.offersNoVisit(busy: busy, offline: session.isOffline))
            .accessibilityHint("Closes this follow-up without booking a visit")
            .accessibilityIdentifier("slotqueue-no-visit")
        }
        .interactiveDismissDisabled(busy)
        .thorbisConfirm("Close this follow-up?",
                        message: "No visit is booked and it leaves the list. The reason is kept with the job\u{2019}s history.",
                        isPresented: $confirmClose,
                        actions: OfficeSlotRules.noActionReasons.map { reason in
                            ThorbisConfirmAction(reason.title) { close(reason.code) }
                        })
    }

    private var end: Date { start.addingTimeInterval(TimeInterval(minutes * 60)) }

    private static func lengthLabel(_ minutes: Int) -> String {
        if minutes % 60 == 0 { return "\(minutes / 60) h" }
        return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Theme.font(13)).foregroundStyle(Theme.muted)
            Text(value).font(Theme.font(16)).foregroundStyle(Theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private func book() {
        guard !busy else { return }
        guard let window = OfficeSlotRules.plannedWindow(start: start, minutes: minutes) else {
            problem = "Pick a length of a day or less."
            return
        }
        // The queue keeps the attempt, so a sheet opened again after no answer sends the same id.
        var current = queue.bookingAttempts.attempt(for: review.id)
        guard let request = current.request(decisionVersion: review.decisionVersion, window: window) else {
            problem = current.sheetWords
            return
        }
        keep(current)
        let sent = current
        busy = true
        problem = nil
        Task {
            defer { busy = false }
            do {
                let window = try await queue.book(review, request: request, api: api)
                settle(sent, .booked)
                booked(window)
            } catch {
                // A cancelled or unanswered request may still have booked it: the queue keeps the id.
                let answer = OfficeSlotBookingAttempt.answer(for: error)
                var settled = sent
                settled.settle(answer, label: Self.label)
                let kept = keep(settled)
                if answer == .booked {
                    // Thorbis answered 201 but the body could not be read: it booked the window sent.
                    booked(request.plannedWindow)
                } else if kept, case .refused = answer, settled.needsCheck {
                    // The refusal may have come before the server looked for the booking the first
                    // try made (on the server deployed now, any change to the job refuses a retry
                    // even when the first try booked; after the replay change, only the rights,
                    // the version, a close, a missing job or a stale answer from the domain come
                    // first; see OfficeSlotBookingAttempt), so read the follow-up
                    // itself, once for this refusal.
                    let read: OfficeSlotBookingAttempt.ReviewCheck
                    do { read = .read(try await api.officeSlotReview(review.id)) } catch { read = .unread }
                    settled.check(read, reviewId: review.id)
                    keep(settled)
                }
                // Read the queue again behind the sheet: the row may have changed or gone.
                let listRead = await queue.reread(api: api, identity: OfficeSlotQueue.identity(session))
                settled.noteReread(listRead: listRead)
                keep(settled)
                if answer != .booked { problem = settled.sheetWords }
            }
        }
    }

    /// Puts a changed copy of the attempt back in the queue, and shows it when the queue took it.
    @discardableResult
    private func keep(_ changed: OfficeSlotBookingAttempt) -> Bool {
        let kept = queue.bookingAttempts.keep(changed, for: review.id)
        if kept { attempt = changed }
        return kept
    }

    /// Settles the request in flight on a copy of the attempt it was sent from, and puts it back.
    @discardableResult
    private func settle(_ sent: OfficeSlotBookingAttempt, _ answer: OfficeSlotBookingAttempt.Answer) -> String? {
        var settled = sent
        let words = settled.settle(answer, label: Self.label)
        keep(settled)
        return words
    }

    private func booked(_ window: OfficeSlotWindow) {
        onDone("Booked: \(review.serviceNeed), \(Self.label(window))")
        dismiss()
    }

    private static func label(_ window: OfficeSlotWindow) -> String {
        OfficeSlotRules.windowLabel(window) ?? "the time you picked"
    }

    private func close(_ reasonCode: String) {
        guard !busy else { return }
        busy = true
        problem = nil
        Task {
            defer { busy = false }
            do {
                try await queue.resolve(review, reasonCode: reasonCode, api: api)
                onDone("Closed without a visit: \(review.serviceNeed)")
                dismiss()
            } catch {
                // A close whose answer was lost may have landed; a refusal after it finds the row gone.
                let answer = OfficeSlotCloseWords.answer(for: error)
                let listRead = await queue.reread(api: api, identity: OfficeSlotQueue.identity(session))
                let stillWaiting = !listRead || queue.reviews.contains { $0.id == review.id }
                problem = OfficeSlotCloseWords.words(answer, stillWaiting: stillWaiting, listRead: listRead)
            }
        }
    }
}

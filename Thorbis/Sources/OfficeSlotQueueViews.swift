import SwiftUI

// Paper 57F "Waiting for a slot" (and 20S, its rows on Jobs): the follow-ups the office has to
// book by hand, each with a Schedule pill. Schedule books through the server, which checks the
// technician is free; "No visit needed" closes the follow-up with a reason.

/// Paper 57F as its own place: the title, how many are waiting, then the queue.
struct OfficeSlotQueueView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @StateObject private var queue = OfficeSlotQueue()
    @State private var roster: [String: String] = [:]

    init() {}

    private var allowed: Bool { OfficeSlotQueue.allowed(session) }
    private var subtitle: String {
        guard allowed else { return "Booking follow-ups" }
        return queue.loaded ? OfficeSlotRules.countLabel(queue.reviews.count) : "Follow-ups the office books"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PaperHeader(title: "Waiting for a slot", subtitle: subtitle)
                OfflineBanner()
                if !allowed {
                    ListRoomEmpty(title: "Your role can\u{2019}t book follow-ups.",
                                  message: "Booking a follow-up needs the right to book follow-ups and to assign jobs. An owner or admin can change that.")
                } else {
                    OfficeSlotQueueList(queue: queue, roster: roster, standalone: true)
                }
            }
            .padding(.bottom, 24)
        }
        .refreshable { await load() }
        .background(Theme.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("slotqueue-root")
        .task(id: "\(OfficeSlotQueue.identity(session))|\(session.isOffline)|\(allowed)") { await load() }
        .task(id: "roster|\(session.generation)|\(session.isOffline)") {
            guard session.can("job.view", feature: "jobs"), !session.isOffline,
                  let people = try? await api.fieldAssignees() else { return }
            roster = Dictionary(people.map { ($0.userId, $0.displayName) }, uniquingKeysWith: { first, _ in first })
        }
    }

    private func load() async {
        guard allowed, !session.isOffline else { return }
        await queue.load(api: api, identity: OfficeSlotQueue.identity(session))
    }
}

/// The queue inside another screen (Schedule's Unscheduled list): it loads itself and draws
/// nothing for a role that cannot book, offline, or while nothing is waiting.
struct OfficeSlotQueueSection: View {
    var roster: [String: String] = [:]
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @StateObject private var queue = OfficeSlotQueue()

    private var allowed: Bool { OfficeSlotQueue.allowed(session) }

    var body: some View {
        Group {
            if allowed { OfficeSlotQueueList(queue: queue, roster: roster, standalone: false) }
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
    /// On its own page the list also shows loading, empty and offline; inside Schedule it stays out
    /// of the way until there is something to book.
    let standalone: Bool
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var store: Store
    @State private var scheduling: OfficeSlotReview?
    /// What was just booked or closed, said under the heading until the next change.
    @State private var lastDone: String?
    @State private var doneCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let problem = queue.problem, standalone || !queue.reviews.isEmpty {
                ErrorBanner(message: problem, action: .init(title: "Try again") {
                    await queue.load(api: api, identity: OfficeSlotQueue.identity(session))
                })
            }
            if !queue.reviews.isEmpty || lastDone != nil {
                if !standalone {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Waiting for a slot").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 8)
                        Text("\(queue.reviews.count)").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                            .accessibilityLabel(OfficeSlotRules.countLabel(queue.reviews.count))
                    }
                    .padding(.horizontal, PaperCardMetrics.margin + 4).padding(.top, 20).padding(.bottom, 8)
                }
                if let lastDone {
                    Label(lastDone, systemImage: "checkmark.circle.fill")
                        .font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.success)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, PaperCardMetrics.margin + 4)
                        .padding(.top, standalone ? 18 : 0).padding(.bottom, 8)
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
                .padding(.top, standalone && lastDone == nil ? 18 : 0)
                Text("Follow-ups the field asked for that could not be booked on their own. Schedule checks the technician is free before it books.")
                    .font(Theme.font(13)).foregroundStyle(Theme.subtle)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, PaperCardMetrics.margin + 4).padding(.top, 12)
            } else if standalone {
                if session.isOffline && !queue.loaded {
                    ListRoomEmpty(title: "This list needs a connection.",
                                  message: "The server checks each follow-up against the job as it stands now, so it isn\u{2019}t kept on this phone.")
                } else if !queue.loaded && queue.problem == nil {
                    ListRoomSkeleton(count: 3)
                } else if queue.loaded {
                    ListRoomEmpty(title: "Nothing is waiting for a slot.",
                                  message: "A follow-up shows here when the field asks for one and it can\u{2019}t be booked on its own.")
                }
            }
        }
        .sensoryFeedback(.success, trigger: doneCount)
        .sheet(item: $scheduling) { review in
            SheetSurface {
                OfficeSlotBookSheet(queue: queue, review: review, customer: customer(review),
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
                Text("Schedule").font(Theme.font(15, weight: .semibold)).foregroundStyle(Theme.brandText)
                    .lineLimit(1).fixedSize()
                    .padding(.horizontal, 14).frame(minHeight: 40)
                    .background(Theme.brandSurface, in: Capsule())
                    .frame(minHeight: 44).contentShape(Rectangle())
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

    private static let lengths = [60, 120, 180, 240]

    init(queue: OfficeSlotQueue, review: OfficeSlotReview, customer: String?, technician: String?,
         onDone: @escaping (String) -> Void) {
        self.queue = queue
        self.review = review
        self.customer = customer
        self.technician = technician
        self.onDone = onDone
        let plan = OfficeSlotRules.defaultPlan(for: review)
        _start = State(initialValue: plan.start)
        _minutes = State(initialValue: plan.minutes)
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
                            Text(Self.lengthLabel(length)).font(Theme.font(15, weight: on ? .semibold : .medium))
                                .foregroundStyle(on ? Theme.brandText : Theme.foreground)
                                .padding(.horizontal, 14).frame(minHeight: 44)
                                .background(on ? Theme.brandSurface : Theme.field, in: Capsule())
                                .contentShape(Capsule())
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
            .disabled(busy || session.isOffline)
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
        guard let request = OfficeSlotRules.bookRequest(for: review, start: start, minutes: minutes) else {
            problem = "Pick a length of a day or less."
            return
        }
        busy = true
        problem = nil
        Task {
            defer { busy = false }
            do {
                let window = try await queue.book(review, request: request, api: api)
                let when = OfficeSlotRules.windowLabel(window) ?? "the time you picked"
                onDone("Booked: \(review.serviceNeed), \(when)")
                dismiss()
            } catch is CancellationError {
            } catch {
                problem = Self.words(for: error, doing: "book this follow-up")
                // A conflict means the row changed under us; read the queue again behind the sheet.
                await queue.load(api: api, identity: OfficeSlotQueue.identity(session))
            }
        }
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
            } catch is CancellationError {
            } catch {
                problem = Self.words(for: error, doing: "close this follow-up")
                await queue.load(api: api, identity: OfficeSlotQueue.identity(session))
            }
        }
    }

    /// The server's own sentence for a refusal (no opening, already booked, changed since it was
    /// read), with what was being tried in front.
    static func words(for error: Error, doing: String) -> String {
        if let problem = error as? Problem, problem.status == 409 {
            return "Could not \(doing): \(problem.detail ?? problem.title ?? "it changed on the server"). The list has been read again."
        }
        return "Could not \(doing). \(error.localizedDescription)"
    }
}

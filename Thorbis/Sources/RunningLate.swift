import MessageUI
import SwiftUI
import UIKit

// Paper 21R "Running late" (tablet T21R is the same sheet as a centred modal): the tech picks how
// late, sees and edits the text, and sends it. The canonical API has no running-late notice: the
// en_route estimate (`POST /v1/jobs/:id/progress`, etaMinutes) is only accepted on the move *into*
// en_route, and moving the booking (`POST /v1/jobs/:id/schedule`) is the office's Reschedule visit
// (53B), not this. So Send update hands the text to Apple's Messages sheet and the tech sends it
// from their own phone, like the Mail hand-off. Nothing is stored or claimed as sent by the server.

/// How late: one of the three quick steps, or a time the tech picks.
enum RunningLateChoice: Equatable, Hashable {
    case minutes(Int)
    case pickedTime

    static let quickSteps = [10, 20, 30]
}

/// The pure parts of the sheet, kept apart so they are tested without a view.
enum RunningLateDraft {
    /// The new arrival: the promised time plus the delay, counted from now once the promised time
    /// has already gone (so "+10 min" never names a time in the past). Whole minutes, rounded up.
    static func newArrival(promised: Date, delayMinutes: Int, now: Date) -> Date {
        let base = max(promised, now).addingTimeInterval(TimeInterval(delayMinutes * 60))
        let minutes = (base.timeIntervalSinceReferenceDate / 60).rounded(.up)
        return Date(timeIntervalSinceReferenceDate: minutes * 60)
    }

    /// The name to greet: a person's first name; a business keeps its whole name.
    static func greetingName(_ name: String?, commercial: Bool) -> String? {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if commercial { return trimmed }
        return trimmed.split(separator: " ").first.map(String.init)
    }

    /// The text to the customer, in Paper's words: "Hi Danielle, it's Ramon from Wade's Plumbing.
    /// My last job ran long, so I'll be there around 10:50 a.m. instead of 10:30. Sorry for the wait."
    /// No tracking link: there is no tracking page to point at.
    static func message(customer: String?, tech: String?, company: String?, reason: String,
                        newTime: String, oldTime: String) -> String {
        var parts: [String] = []
        let greeting = customer.map { "Hi \($0)," } ?? "Hi,"
        let who: String? = switch (clean(tech), clean(company)) {
        case let (tech?, company?): "it's \(tech) from \(company)."
        case let (tech?, nil): "it's \(tech)."
        case let (nil, company?): "it's \(company)."
        case (nil, nil): nil
        }
        parts.append(who.map { "\(greeting) \($0)" } ?? greeting)

        var why = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = why.last, ".!,;".contains(last) { why.removeLast() }
        let arrival = "I'll be there around \(newTime) instead of \(oldTime)."
        if why.isEmpty {
            parts.append("I'm running late, so \(arrival)")
        } else {
            parts.append("\(why.prefix(1).uppercased())\(why.dropFirst()), so \(arrival)")
        }
        parts.append("Sorry for the wait.")
        return parts.joined(separator: " ")
    }

    private static func clean(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// The "Running late?" sheet. Present it with `.sheet(isPresented:) { RunningLateSheet(job:) }`
/// from a job that is booked and not yet arrived (scheduled, dispatched or en_route with a
/// scheduledFor). `onSent` gets the new arrival time once Messages reports the text as sent; the
/// sheet then closes itself.
struct RunningLateSheet: View {
    let job: JobRecord
    let customer: CustomerRecord?
    let onSent: (Date) -> Void

    init(job: JobRecord, customer: CustomerRecord? = nil, onSent: @escaping (Date) -> Void = { _ in }) {
        self.job = job
        self.customer = customer
        self.onSent = onSent
    }

    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var loadedCustomer: CustomerRecord?
    @State private var customerLoaded = false
    @State private var customerFailed = false
    @State private var choice: RunningLateChoice = .minutes(20)
    @State private var pickedTime = Date()
    @State private var reason = ""
    @State private var text = ""
    /// Once the tech types in the text, a new choice no longer rewrites it.
    @State private var edited = false
    @State private var composing = false
    /// Set when Messages reports the text sent; read once the Messages sheet has closed.
    @State private var sentArrival: Date?
    @State private var problem: String?

    private var shownCustomer: CustomerRecord? { customer ?? loadedCustomer }
    private var promised: Date? { JobFiltering.date(job.scheduledFor) }
    private var phone: String? {
        let trimmed = (shownCustomer?.phone ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    private var firstName: String? {
        RunningLateDraft.greetingName(shownCustomer?.name, commercial: shownCustomer?.accountType == "commercial")
    }

    private var newArrival: Date? {
        guard let promised else { return nil }
        switch choice {
        case .minutes(let minutes): return RunningLateDraft.newArrival(promised: promised, delayMinutes: minutes, now: Date())
        case .pickedTime: return pickedTime
        }
    }

    /// Why Send update is off, in one sentence; nil when the phone can hand the text to Messages.
    private var sendOffReason: String? {
        if promised == nil { return "This job has no booked time, so there is no arrival to move." }
        if customerFailed, phone == nil { return "The customer\u{2019}s phone number didn\u{2019}t load. Close and try again." }
        if customerLoaded || customer != nil, phone == nil { return "The customer has no phone number on file." }
        if !MFMessageComposeViewController.canSendText() { return "This device can\u{2019}t send texts." }
        return nil
    }

    var body: some View {
        // Paper 21R: Cancel is the pill beside the centred title; only Send update sits at the bottom.
        ThorbisModalSheet(title: "Running late?", closeLabel: "Cancel", onClose: { dismiss() },
                          closeStyle: .headerPill, detents: [.large], commitTitle: "Send update",
                          commitDisabledReason: sendOffReason,
                          commitIdentifier: "running-late-send", commit: { attemptSend() },
                          onKeyboardDone: {}) {
            heading
            if promised != nil {
                delayChips
                if choice == .pickedTime { pickedTimeRow }
                reasonWell
                messageBlock
                if let problem { FieldProblem(message: problem) }
            }
        }
        .interactiveDismissDisabled(edited || !reason.isEmpty)
        // The running-late sheet closes only after Messages has gone, so the two never dismiss at once.
        .sheet(isPresented: $composing, onDismiss: {
            guard let arrival = sentArrival else { return }
            sentArrival = nil
            onSent(arrival)
            dismiss()
        }) {
            RunningLateTextComposer(recipient: phone ?? "", message: text) { sent in
                if sent { sentArrival = newArrival }
                composing = false
            }
            .ignoresSafeArea()
        }
        .task(id: job.customerId) { await loadCustomer() }
        .onAppear {
            if let arrival = newArrival { pickedTime = arrival }
            regenerate()
        }
        .onChange(of: choice) { _, _ in regenerate() }
        .onChange(of: pickedTime) { _, _ in regenerate() }
        .onChange(of: reason) { _, _ in regenerate() }
        .onChange(of: shownCustomer?.id) { _, _ in regenerate() }
    }

    // MARK: Heading

    private var heading: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let promised {
                Text("\(JobCalendarDraft.jobNumber(job.id)) \u{00B7} was \(promised.tradeTime)")
                    .font(Theme.font(15)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if let newArrival {
                    Text("New arrival \(newArrival.tradeTime)")
                        .font(Theme.font(22, weight: .bold)).foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.numericText())
                        .accessibilityIdentifier("running-late-arrival")
                }
            } else {
                Text(JobCalendarDraft.jobNumber(job.id))
                    .font(Theme.font(15)).foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    // MARK: How late

    /// One row of four; one column at accessibility sizes so the words stay whole.
    private var delayChips: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            ForEach(RunningLateChoice.quickSteps, id: \.self) { minutes in
                chip(.minutes(minutes), label: "+\(minutes) min", symbol: nil)
            }
            chip(.pickedTime, label: "Pick a time", symbol: "clock")
        }
    }

    private func chip(_ value: RunningLateChoice, label: String, symbol: String?) -> some View {
        let isOn = choice == value
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return Button {
            choice = value
            problem = nil
        } label: {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).accessibilityHidden(true)
                }
                Text(label)
                    .font(Theme.font(symbol == nil ? 15 : 14, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(isOn ? Theme.brandText : Theme.foreground)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(isOn ? Theme.brandSurface : Theme.field, in: shape)
            .overlay { if isOn { shape.strokeBorder(Theme.brand, lineWidth: 1.5) } }
            .contentShape(shape)
        }
        .buttonStyle(PressStyle())
        .layoutPriority(symbol == nil ? 0 : 1)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(value == .pickedTime ? "running-late-pick" : "running-late-\(label.filter(\.isNumber))")
    }

    private var pickedTimeRow: some View {
        HStack {
            Text("New arrival").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
            Spacer(minLength: 8)
            DatePicker("New arrival", selection: $pickedTime, displayedComponents: .hourAndMinute)
                .labelsHidden().datePickerStyle(.compact).tint(Theme.brand)
                .accessibilityLabel("Choose the new arrival time")
                .accessibilityIdentifier("running-late-time")
        }
        .padding(.horizontal, 16).frame(minHeight: 52)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    // MARK: Reason

    private var reasonWell: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Reason (optional)").font(Theme.font(13)).foregroundStyle(Theme.muted)
            TextField("Reason (optional)", text: $reason, prompt: .placeholder("Previous job ran long"))
                .font(Theme.font(17, weight: .medium)).foregroundStyle(Theme.foreground)
                .submitLabel(.done)
                .accessibilityLabel("Reason, optional")
                .accessibilityIdentifier("running-late-reason")
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    // MARK: The text

    private var messageBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(recipientLine)
                .font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
            TextField("Text to the customer", text: Binding(get: { text }, set: { text = $0; edited = true; problem = nil }),
                      axis: .vertical)
                .font(Theme.font(15)).foregroundStyle(Theme.foreground)
                .lineLimit(3...10)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.brandSurface,
                            in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18,
                                                       bottomTrailingRadius: 6, topTrailingRadius: 18, style: .continuous))
                .accessibilityLabel("Text to the customer")
                .accessibilityIdentifier("running-late-message")
        }
    }

    /// "Text to Danielle · (916) 555-0148", or what is missing.
    private var recipientLine: String {
        let name = firstName.map { "Text to \($0)" } ?? "Text to the customer"
        if let phone { return "\(name) \u{00B7} \(phone)" }
        return name
    }

    // MARK: Actions

    private func regenerate() {
        guard !edited, let promised, let newArrival else { return }
        let old = promised.periodMark == newArrival.periodMark ? promised.columnTime : promised.tradeTime
        text = RunningLateDraft.message(customer: firstName, tech: session.user?.name.flatMap { RunningLateDraft.greetingName($0, commercial: false) },
                                        company: session.activeOrganization?.name, reason: reason,
                                        newTime: newArrival.tradeTime, oldTime: old)
    }

    private func attemptSend() {
        guard let newArrival, sendOffReason == nil else { return }
        guard phone != nil else {
            problem = "Still loading the customer\u{2019}s phone number. Try again in a moment."
            return
        }
        if newArrival <= Date() {
            problem = "Pick a time later than now."
            return
        }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            problem = "Write the text to the customer."
            return
        }
        composing = true
    }

    private func loadCustomer() async {
        guard customer == nil else { return }
        do {
            loadedCustomer = try await api.fieldCustomer(job.customerId)
        } catch is CancellationError {
            return
        } catch {
            loadedCustomer = nil
            customerFailed = true
        }
        customerLoaded = true
    }
}

/// Apple's Messages sheet with the text filled in; the tech reviews and sends it themselves.
/// `done(true)` only when Messages reports it sent.
private struct RunningLateTextComposer: UIViewControllerRepresentable {
    let recipient: String
    let message: String
    let done: (Bool) -> Void

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.recipients = [recipient]
        controller.body = message
        controller.messageComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: MFMessageComposeViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let done: (Bool) -> Void
        init(done: @escaping (Bool) -> Void) { self.done = done }
        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            done(result == .sent)
        }
    }
}

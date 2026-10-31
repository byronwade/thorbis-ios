import SwiftUI

// Customer presentation (design.thorbis.com/customer-presentation, CP-01..CP-12): the estimate
// options, the review, the signature and the invoice, shown to the customer holding the
// technician's phone or iPad inside CustomerModeContainer. One question per screen, the price
// always in view, totals in ink, every number labelled, one commit that names the action and
// the amount, and a full-screen confirmation before the device goes back.

// MARK: - Sizes

/// CP-05 sizes. iPad (regular width) steps up; Dynamic Type scales from these.
struct CustomerType {
    let regular: Bool
    init(_ sizeClass: UserInterfaceSizeClass?) { regular = sizeClass == .regular }

    var small: CGFloat { 17 }
    var body: CGFloat { regular ? 22 : 20 }
    var heading: CGFloat { regular ? 28 : 24 }
    var total: CGFloat { regular ? 40 : 34 }
    var target: CGFloat { 56 }
}

// MARK: - Flow

/// What the customer sees, in order. Pure so the steps and amounts can be tested.
struct CustomerEstimateFlow: Equatable {
    enum Step: Equatable { case choose, review, sign, done }

    let estimate: EstimateRecord
    var step: Step
    var selectedOptionID: String?
    private(set) var issuedRevision: CustomerIssuedEstimateRevision?

    init(estimate: EstimateRecord) {
        self.estimate = estimate
        // CP-08: a single scope has nothing to choose, so it opens on the review.
        step = estimate.status == "approved" ? .done : (Self.options(estimate).isEmpty ? .review : .choose)
    }

    static func options(_ estimate: EstimateRecord) -> [FieldEstimateOption] { estimate.options ?? [] }

    var options: [FieldEstimateOption] { issuedRevision.map { $0.options ?? [] } ?? Self.options(estimate) }
    var hasOptions: Bool { !options.isEmpty }
    var selectedOption: FieldEstimateOption? { options.first { $0.id == selectedOptionID } }

    /// The lines and total being approved: the chosen option's, or the estimate's own.
    var lines: [FieldLine] { hasOptions ? selectedOption?.lines ?? [] : issuedRevision?.lines ?? estimate.lines }
    var currency: String { selectedOption?.currency ?? issuedRevision?.currency ?? estimate.lines.first?.unitPrice.currency ?? "USD" }
    var total: Int? {
        if hasOptions { return selectedOption?.totalAmount }
        return issuedRevision?.totalAmount ?? paperLinesTotal(estimate.lines)
    }
    var totalText: String { total.map { money($0, currency: currency) } ?? "" }

    /// The name of what is being approved, said the way the tech says it.
    var choiceName: String { selectedOption?.title ?? issuedRevision?.title ?? estimate.title }

    var canReview: Bool { !hasOptions || selectedOption != nil }

    /// CP-07: the commit names the action and the amount.
    var reviewTitle: String {
        guard let option = selectedOption else { return "Choose an option" }
        return "Review \(option.title) · \(money(option.totalAmount, currency: option.currency))"
    }
    var approveTitle: String {
        let what = selectedOption.map { "Approve \($0.title)" } ?? "Approve and sign"
        return total == nil ? what : "\(what) · \(totalText)"
    }
    var signTitle: String { total == nil ? "Approve" : "Approve \(totalText)" }

    mutating func choose(_ optionID: String) { selectedOptionID = optionID }
    mutating func review() { if canReview { step = .review } }
    mutating func useIssuedRevision(_ revision: CustomerIssuedEstimateRevision) throws {
        try revision.validate(for: estimate)
        issuedRevision = revision
        if !options.contains(where: { $0.id == selectedOptionID }) { selectedOptionID = nil }
        step = canReview ? (hasOptions && step == .choose ? .choose : .review) : .choose
    }
    mutating func back() {
        switch step {
        case .review: if hasOptions { step = .choose }
        case .sign: step = .review
        case .choose, .done: break
        }
    }
}

/// The reason the commit is still waiting, in words (CP-07, never a silent disabled button).
func customerSignatureHint(name: String, hasInk: Bool) -> String? {
    let missingName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    switch (missingName, hasInk) {
    case (true, false): return "Type your name and sign to finish."
    case (true, true): return "Type your name to finish."
    case (false, false): return "Sign in the box to finish."
    case (false, true): return nil
    }
}

// MARK: - Estimate

/// "Show to customer" for an estimate: choose an option, review it, sign, done.
struct CustomerEstimatePresentation: View {
    let jobID: String?
    let customerName: String
    let onApproved: (EstimateRecord?) -> Void
    let onDone: () -> Void
    let returnToDocuments: (() -> Void)?

    @EnvironmentObject private var api: APIClient
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var flow: CustomerEstimateFlow
    @State private var confirmNotToday = false
    @State private var name: String
    @State private var strokes: [[CGPoint]] = []
    @State private var consentText: String?
    @State private var busy = false
    @State private var error: String?
    @State private var signedAt: Date?
    @State private var signedName = ""
    @State private var openingReview = false
    @State private var openingError: String?
    @State private var reviewGeneration: UUID?
    @State private var reviewRequestID = UUID()
    @StateObject private var handoffObservation: CustomerEstimateHandoffObservation
    private var handoff: CustomerEstimateHandoffContext? { handoffObservation.context }
    private var actionBusy: Bool { busy || handoff?.running == true }

    init(estimate: EstimateRecord, jobID: String?, customerName: String, preselectedOptionID: String? = nil,
         handoff: CustomerEstimateHandoffContext? = nil, returnToDocuments: (() -> Void)? = nil,
         onApproved: @escaping (EstimateRecord?) -> Void, onDone: @escaping () -> Void) {
        self.jobID = jobID
        self.customerName = customerName
        self.onApproved = onApproved
        self.onDone = onDone
        self.returnToDocuments = returnToDocuments
        _handoffObservation = StateObject(wrappedValue: CustomerEstimateHandoffObservation(handoff))
        var flow = CustomerEstimateFlow(estimate: estimate)
        if let preselectedOptionID {
            flow.choose(preselectedOptionID)
            flow.review()
        }
        _flow = State(initialValue: flow)
        _name = State(initialValue: handoff?.signature?.signerName ?? handoff?.initialSignerName ?? customerName)
    }

    private var type: CustomerType { CustomerType(sizeClass) }
    /// The proven drawn-signature approval needs a job and a single scope; options go through
    /// the customer action, which records the chosen option with the typed name.
    private var drawnApproval: Bool { jobID != nil && !flow.hasOptions }
    private var reviewReady: Bool {
        !openingReview && flow.issuedRevision != nil && reviewGeneration == api.requestGeneration
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let handoff, !handoff.current() {
                        Text("Return the device to your technician to reopen this job.").font(Theme.font(type.body))
                    } else if handoff?.outcome == .unknown {
                        unknownScreen
                    } else if case .retryable(let reason)? = handoff?.outcome {
                        header(eyebrow: "Connection interrupted", title: flow.choiceName)
                        Text(reason).font(Theme.font(type.body)).fixedSize(horizontal: false, vertical: true)
                    } else if case .needsReview(let reason)? = handoff?.outcome {
                        header(eyebrow: "This estimate needs review", title: flow.choiceName)
                        Text(reason).font(Theme.font(type.body)).fixedSize(horizontal: false, vertical: true)
                    } else if handoff?.outcome?.isApproved == true {
                        doneScreen
                    } else if flow.step == .done || reviewReady {
                        switch flow.step {
                        case .choose: chooseScreen
                        case .review: reviewScreen
                        case .sign: signScreen
                        case .done: doneScreen
                        }
                    } else if let openingError {
                        header(eyebrow: "Your estimate", title: "Couldn't open your estimate")
                        Text(openingError).font(Theme.font(type.body))
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ProgressView("Opening your estimate…")
                            .font(Theme.font(type.body))
                            .frame(maxWidth: .infinity, minHeight: 220)
                            .accessibilityIdentifier("customer-estimate-opening")
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .frame(maxWidth: type.regular ? 1000 : .infinity, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("customer-estimate-presentation-\(flow.estimate.id)")
            bottomBar
        }
        .foregroundStyle(Theme.foreground)
        .task(id: api.requestGeneration) {
            await openReview()
            if handoff != nil, handoff?.signature == nil, handoff?.outcome == nil, reviewReady { await startSigning() }
        }
        .animation(.easeOut(duration: 0.2), value: flow.step)
        .thorbisConfirm("Not ready to decide?",
                        message: "You can think about it and decide later, or decline this estimate now.",
                        isPresented: $confirmNotToday,
                        actions: [
                            ThorbisConfirmAction("I'll think about it") { onDone() },
                            ThorbisConfirmAction("No thanks, decline", role: .destructive) { Task { await decline() } },
                        ])
    }

    // MARK: Screens

    private var chooseScreen: some View {
        VStack(alignment: .leading, spacing: 20) {
            header(eyebrow: "Estimate for \(customerName)", title: "Choose an option")
                .padding(.bottom, -8)
            Text("Tap one. You'll see every line before you sign.")
                .font(Theme.font(type.small)).foregroundStyle(Theme.subtle)
                .fixedSize(horizontal: false, vertical: true)
            let options = flow.options
            if type.regular && options.count <= 3 {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(options) { optionCard($0) }
                }
            } else {
                VStack(spacing: 16) { ForEach(options) { optionCard($0) } }
            }
        }
    }

    /// The whole card is the choice (F25): price first, then the option's name and what it is.
    /// "See what's included" sits below the tap area so it never doubles as a choice; it opens
    /// the option's lines (the review step) with this option chosen.
    private func optionCard(_ option: FieldEstimateOption) -> some View {
        let selected = flow.selectedOptionID == option.id
        let total = money(option.totalAmount, currency: option.currency)
        return VStack(alignment: .leading, spacing: 0) {
            Button { flow.choose(option.id) } label: {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 12) {
                        Text(total)
                            .font(Theme.font(type.total, weight: .medium)).monospacedDigit().tracking(-0.3)
                            .minimumScaleFactor(0.6).lineLimit(1)
                        Spacer(minLength: 8)
                        CustomerRadio(selected: selected)
                    }
                    Text(option.title).font(Theme.font(type.heading, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                    if !option.description.isEmpty {
                        Text(option.description).font(Theme.font(type.small)).foregroundStyle(Theme.subtle)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                    Text("\(option.lines.count) \(option.lines.count == 1 ? "item" : "items")")
                        .font(Theme.font(type.small)).foregroundStyle(Theme.muted)
                        .padding(.top, 10)
                }
                .foregroundStyle(Theme.foreground)
                .frame(maxWidth: .infinity, minHeight: type.target, alignment: .topLeading)
                .padding([.horizontal, .top], 18)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(selected ? "\(option.title), selected" : "Choose \(option.title)")
            .accessibilityValue("Total \(total)")
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            Spacer(minLength: 0)
            Button {
                flow.choose(option.id)
                flow.review()
            } label: {
                Text("See what's included").font(Theme.font(type.small, weight: .medium))
                    .foregroundStyle(Theme.foreground).underline()
                    .frame(maxWidth: .infinity, minHeight: type.target, alignment: .leading)
                    .padding(.horizontal, 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows every line in \(option.title)")
        }
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Selection is the blue ring and the radio; the screen's only ink is the commit (CP-07).
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(selected ? Theme.brand : Theme.border, lineWidth: selected ? 2 : 1))
        .animation(.easeOut(duration: 0.15), value: selected)
    }

    /// "What's included": the chosen option (or the single scope) with every line in full,
    /// its quantity and amount, and the total that will be signed.
    private var reviewScreen: some View {
        VStack(alignment: .leading, spacing: 20) {
            let index = flow.options.firstIndex { $0.id == flow.selectedOptionID }
            header(eyebrow: flow.hasOptions ? "Option \((index ?? 0) + 1) of \(flow.options.count)" : "Your estimate",
                   title: flow.choiceName)
            if flow.hasOptions, let description = flow.selectedOption?.description, !description.isEmpty {
                Text(description).font(Theme.font(type.small)).foregroundStyle(Theme.subtle)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, -10)
            }
            CustomerIncludedLines(lines: flow.lines, type: type,
                                  rows: flow.total.map { [CustomerAmountRow(label: "Total", amount: money($0, currency: flow.currency), emphasis: true)] } ?? [])
        }
    }

    private var signScreen: some View {
        VStack(alignment: .leading, spacing: 18) {
            header(eyebrow: "\(flow.choiceName) · \(flow.totalText)", title: "Sign to approve")
            Text(consentText ?? "By signing, I approve \"\(flow.choiceName)\" for \(flow.totalText) as shown.")
                .font(Theme.font(type.body))
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                Text("Your full name").font(Theme.font(type.small, weight: .medium)).foregroundStyle(Theme.muted)
                TextField("Your full name", text: $name)
                    .textContentType(.name)
                    .font(Theme.font(type.body))
                    .padding(.horizontal, 16)
                    .frame(minHeight: type.target)
                    .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12))
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Your signature").font(Theme.font(type.small, weight: .medium)).foregroundStyle(Theme.muted)
                    Spacer()
                    if SignatureInk.hasInk(strokes) {
                        Button("Clear") { strokes = [] }
                            .font(Theme.font(type.small, weight: .medium))
                            .frame(minWidth: type.target, minHeight: 44)
                    }
                }
                ZStack(alignment: .bottomLeading) {
                    SignaturePad(strokes: $strokes)
                    if !SignatureInk.hasInk(strokes) {
                        Text("Sign here with your finger").font(Theme.font(type.small)).foregroundStyle(.black.opacity(0.45))
                            .padding(16).allowsHitTesting(false)
                    }
                }
                .frame(height: type.regular ? 260 : 220)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
                .accessibilityLabel("Signature box. Sign with your finger.")
                .accessibilityIdentifier("customer-estimate-signature-pad")
                .accessibilityValue(handoff?.signature != nil ? "Signature saved for this estimate" : SignatureInk.hasInk(strokes) ? "Signature entered" : "Signature required")
                .allowsHitTesting(handoff?.submissionStarted != true)
            }
            if let error {
                Text(error).font(Theme.font(type.body)).foregroundStyle(Theme.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var doneScreen: some View {
        VStack(alignment: .center, spacing: 18) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 64)).foregroundStyle(Theme.success)
                .accessibilityHidden(true).padding(.top, 40)
            Text("Approved").font(Theme.font(type.heading + 6, weight: .medium)).accessibilityAddTraits(.isHeader)
            Text(doneSentence).font(Theme.font(type.body)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if flow.total != nil {
                Text(flow.totalText).font(Theme.monoFont(type.total, weight: .medium))
            }
            Text(handoff == nil && returnToDocuments == nil ? "Thank you. Please hand the device back to your technician." : "This estimate is approved. Continue when you're ready.")
                .font(Theme.font(type.body)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var doneSentence: String {
        let what = flow.choiceName
        if let handoff {
            if let signer = handoff.approvedSignerName { return "\(what), signed by \(signer)." }
            return "\(what) is approved."
        }
        if let signedAt {
            return "\(what), signed by \(signedName) at \(signedAt.formatted(date: .omitted, time: .shortened))."
        }
        if let signature = flow.estimate.approvalSignature {
            return "\(what), signed by \(signature.signerName)."
        }
        return "\(what) is approved."
    }

    // MARK: Bottom bar (one ink commit, CP-07)

    @ViewBuilder private var bottomBar: some View {
        VStack(spacing: 10) {
            if let handoff, handoff.outcome != nil {
                if handoff.outcome?.isApproved == true {
                    CustomerPresentationCommit(title: handoff.continueTitle, enabled: true, busy: false, type: type, action: onDone)
                } else if case .retryable? = handoff.outcome {
                    CustomerPresentationCommit(title: "Try again", enabled: handoff.canApprove(), busy: actionBusy, type: type) {
                        handoff.run {
                            await handoff.recoverPreparation()
                            guard handoff.outcome == nil else { return }
                            await approve()
                        }
                    }
                } else if handoff.outcome == .unknown, handoff.retryVerified {
                    CustomerPresentationCommit(title: "Retry exact approval", enabled: handoff.canApprove(), busy: actionBusy, type: type) {
                        handoff.run { await approve() }
                    }
                }
                CustomerSecondaryButton(title: "Back to selected work", type: type, action: handoff.backToReview)
            } else if flow.step == .done || reviewReady {
            switch flow.step {
            case .choose:
                CustomerPresentationCommit(title: flow.reviewTitle, enabled: flow.canReview, busy: false, type: type) { flow.review() }
                if let error { hint(error, danger: true) } else if !flow.canReview { hint("Choose an option above to continue.") }
                HStack(spacing: 8) {
                    CustomerTextButton(title: "Not today", type: type) { confirmNotToday = true }
                    if let returnToDocuments {
                        CustomerTextButton(title: "Job documents", type: type, action: returnToDocuments)
                            .disabled(actionBusy || openingReview)
                            .accessibilityLabel("Back to job documents")
                    }
                }
            case .review:
                CustomerPresentationCommit(title: flow.approveTitle, enabled: true, busy: actionBusy, type: type) { Task { await startSigning() } }
                if let error { hint(error, danger: true) }
                HStack(spacing: 8) {
                    if flow.hasOptions { CustomerTextButton(title: "See other options", type: type) { flow.back() } }
                    CustomerTextButton(title: "Not today", type: type) { confirmNotToday = true }
                }
                if let returnToDocuments {
                    CustomerTextButton(title: "Back to job documents", type: type, action: returnToDocuments)
                        .disabled(actionBusy || openingReview)
                }
            case .sign:
                let reason = customerSignatureHint(name: name, hasInk: SignatureInk.hasInk(strokes))
                CustomerPresentationCommit(title: flow.signTitle, enabled: reason == nil || handoff?.signature != nil, busy: actionBusy, type: type) {
                    if let handoff { handoff.run { await approve() } } else { Task { await approve() } }
                }
                .accessibilityIdentifier(handoff == nil ? "customer-estimate-submit-approval" : "handoff-submit-approval")
                if let reason { hint(reason) }
                CustomerTextButton(title: "Back", type: type) {
                    if let handoff { handoff.backToReview() } else { flow.back(); error = nil }
                }
            case .done:
                if let returnToDocuments {
                    CustomerPresentationCommit(title: "Back to job documents", enabled: true, busy: false, type: type, action: returnToDocuments)
                        .disabled(actionBusy)
                    CustomerSecondaryButton(title: "Hand back to the technician", type: type, action: onDone)
                        .disabled(actionBusy)
                } else {
                    CustomerPresentationCommit(title: "Hand back to the technician", enabled: true, busy: false, type: type, action: onDone)
                }
            }
            } else {
                if openingError != nil {
                    CustomerPresentationCommit(title: "Try again", enabled: true, busy: openingReview, type: type) { Task { await openReview() } }
                }
                CustomerSecondaryButton(title: "Not today", type: type) { onDone() }
                if let returnToDocuments {
                    CustomerSecondaryButton(title: "Back to job documents", type: type, action: returnToDocuments)
                        .disabled(actionBusy || openingReview)
                }
            }
        }
        .padding(.horizontal, Theme.gutter).padding(.top, 12).padding(.bottom, 8)
        .frame(maxWidth: type.regular ? 640 : .infinity)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
        .disabled(actionBusy && handoff == nil)
    }

    private var unknownScreen: some View {
        VStack(alignment: .leading, spacing: 18) {
            header(eyebrow: "Approval needs confirmation", title: flow.choiceName)
            Text("Your approval may have been received. Check its current state before trying again.")
                .font(Theme.font(type.body)).fixedSize(horizontal: false, vertical: true)
            CustomerSecondaryButton(title: "Check approval", type: type) {
                if let handoff { Task { await handoff.checkOutcome() } }
            }
        }
    }

    private func hint(_ text: String, danger: Bool = false) -> some View {
        Text(text).font(Theme.font(type.small)).foregroundStyle(danger ? Theme.destructive : Theme.muted)
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
    }

    private func header(eyebrow: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow).font(Theme.font(type.body)).foregroundStyle(Theme.muted)
            Text(title).font(Theme.font(type.heading + 4, weight: .medium)).accessibilityAddTraits(.isHeader)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Actions

    @State private var standaloneLink: (token: String, action: PublicEstimateAction)?
    private var link: (token: String, action: PublicEstimateAction)? {
        get { handoff?.link ?? standaloneLink }
        nonmutating set { if let handoff { handoff.link = newValue } else { standaloneLink = newValue } }
    }

    private func openReview() async {
        guard flow.estimate.status != "approved" else { return }
        if let handoff {
            guard handoff.current() else { return }
            if handoff.signature != nil || handoff.outcome != nil || handoff.running {
                try? flow.useIssuedRevision(handoff.reviewed.revision)
                flow.selectedOptionID = handoff.reviewed.optionID
                flow.step = handoff.outcome?.isApproved == true ? .done : .sign
                reviewGeneration = api.requestGeneration
                return
            }
        }
        let requestID = UUID(), generation = api.requestGeneration
        reviewRequestID = requestID
        reviewGeneration = nil
        openingReview = true
        openingError = nil
        error = nil
        if handoff == nil { link = nil; uploadedSignature = nil }
        consentText = handoff?.link?.action.consentText
        strokes = []
        defer { if reviewRequestID == requestID { openingReview = false } }
        do {
            if let handoff { try await handoff.validate() }
            let revision = try await api.customerIssuedEstimateRevision(for: flow.estimate, currentAuthority: { handoff?.current() != false })
            try Task.checkCancellation()
            if let handoff {
                guard handoff.current(), handoff.canApprove(), revision == handoff.reviewed.revision else {
                    throw Problem(title: "This estimate changed. Review its current terms again.", status: 409, detail: nil)
                }
            }
            guard reviewRequestID == requestID, generation == api.requestGeneration else { return }
            try flow.useIssuedRevision(revision)
            reviewGeneration = generation
        } catch is CancellationError {
        } catch {
            guard reviewRequestID == requestID, generation == api.requestGeneration else { return }
            openingError = error.isConnectivityFailure
                ? "Opening this estimate needs a connection. Try again when you have signal."
                : error.localizedDescription
        }
    }

    private func startSigning() async {
        error = nil
        guard handoff?.current() != false, handoff?.canApprove() != false, reviewReady, let revision = flow.issuedRevision else {
            openingError = "Ask your technician to reopen the current estimate."
            reviewGeneration = nil
            return
        }
        guard !drawnApproval else { flow.step = .sign; return }
        let generation = api.requestGeneration
        busy = true
        defer { busy = false }
        do {
            let opened: (token: String, action: PublicEstimateAction)
            if let retained = handoff?.link { opened = retained }
            else { opened = try await api.openInPersonEstimateApproval(revision, currentAuthority: { handoff?.current() != false && handoff?.canApprove() != false }) }
            try Task.checkCancellation()
            guard generation == api.requestGeneration else { return }
            guard handoff?.current() != false, handoff?.canApprove() != false else { return }
            link = opened
            consentText = opened.action.consentText
            flow.step = .sign
        } catch is CancellationError {
        } catch {
            self.error = error.isConnectivityFailure ? "Approving needs a connection. Try again when you have signal." : error.localizedDescription
        }
    }

    private func approve() async {
        guard reviewReady, let revision = flow.issuedRevision, let generation = reviewGeneration else { return }
        let signer = handoff?.signature?.signerName ?? name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !signer.isEmpty, signer.count <= 120, SignatureInk.hasInk(strokes) || handoff?.signature != nil else { return }
        guard handoff?.current() != false, handoff?.canApprove() != false else { return }
        busy = true
        defer { busy = false }
        error = nil
        do {
            if let handoff, handoff.signature == nil {
                guard let data = SignatureInk.png(strokes) else { return }
                _ = try handoff.freezeSignature(signerName: signer, png: data, signedAt: ISO8601DateFormatter().string(from: Date()))
            }
            if let handoff { try await handoff.validate() }
            if drawnApproval, let jobID {
                let mediaID = try await uploadSignature(jobID: jobID)
                try Task.checkCancellation()
                guard generation == api.requestGeneration else { return }
                guard handoff?.current() != false, handoff?.canApprove() != false else { return }
                let input = FieldSignatureInput(signerName: signer, signedAt: handoff?.signature?.signedAt ?? ISO8601DateFormatter().string(from: Date()), imageMediaId: mediaID)
                handoff?.submissionStarted = true; handoff?.retryVerified = false
                let approved = try await api.approveFieldEstimate(flow.estimate.id, revisionNumber: revision.revisionNumber, signature: input)
                guard generation == api.requestGeneration else { return }
                if let handoff {
                    guard handoff.current() else { return }
                    guard handoff.canApprove() else { handoff.report(.unknown); return }
                    handoff.report(await handoff.confirmed(approved))
                } else { onApproved(approved) }
            } else if let link {
                let action = link.action
                guard let nonce = action.nonce, let consentVersion = action.consentVersion,
                      action.canApprove(signerName: signer, consent: true, selectedOptionID: flow.selectedOptionID) else {
                    error = "This estimate can't be signed here. Ask your technician."
                    return
                }
                // The drawing is kept with the job; the server records the typed name and option.
                if let jobID { _ = try? await uploadSignature(jobID: jobID) }
                try Task.checkCancellation()
                guard generation == api.requestGeneration else { return }
                guard handoff?.current() != false, handoff?.canApprove() != false else { return }
                let decision = handoff?.publicDecision ?? PublicEstimateActionDecision.approve(
                    revisionNumber: action.revisionNumber, nonce: nonce, contentHash: action.contentHash,
                    signerName: signer, consentVersion: consentVersion, consent: true, optionID: flow.selectedOptionID)
                handoff?.publicDecision = decision
                handoff?.submissionStarted = true; handoff?.retryVerified = false
                let patch = try await api.decidePublicDocumentAction(token: link.token, decision: decision)
                guard generation == api.requestGeneration else { return }
                if let handoff {
                    guard handoff.current() else { return }
                    guard handoff.canApprove() else { handoff.report(.unknown); return }
                    handoff.report(await handoff.publicConfirmed(patch))
                } else { onApproved(nil) }
            } else {
                return
            }
            signedName = signer
            signedAt = Date()
            if handoff == nil || handoff?.outcome?.isApproved == true { flow.step = .done }
        } catch is CancellationError {
        } catch {
            if let handoff, handoff.current() {
                handoff.report(handoff.submissionStarted ? .unknown :
                    customerEstimatePreparationCanRetry(error)
                    ? .retryable("Preparing this approval was interrupted. Try again when connected.")
                    : .needsReview(error.localizedDescription))
            }
            self.error = error.isConnectivityFailure ? "Approving needs a connection. Try again when you have signal." : error.localizedDescription
        }
    }

    @State private var uploadedSignature: (strokes: [[CGPoint]], mediaID: String)?

    private func uploadSignature(jobID: String) async throws -> String {
        if let handoff {
            guard handoff.current(), handoff.canApprove(), let intent = handoff.signature else { throw CancellationError() }
            if let id = handoff.uploadedMediaID { return id }
            let asset = try await handoff.transfer.upload(jobID: jobID, clientAssetID: intent.clientAssetID, kind: "photo", mime: "image/png",
                originalFilename: "signature.png", data: intent.png, tags: ["signature"],
                expectedOrganizationID: handoff.reviewed.estimate.organizationId,
                currentAuthority: { handoff.current() && handoff.canApprove() })
            guard handoff.current(), handoff.canApprove() else { throw CancellationError() }
            handoff.uploadedMediaID = asset.id
            return asset.id
        }
        if let uploadedSignature, uploadedSignature.strokes == strokes { return uploadedSignature.mediaID }
        guard let data = SignatureInk.png(strokes) else {
            throw Problem(title: "The signature could not be saved. Try again.", status: nil, detail: nil)
        }
        let transfer: MediaTransfer
        #if DEBUG
        if PaperPreview.isJobEstimateHandoff {
            transfer = MediaTransfer(api: api, storageSession: PaperPreview.handoffStorageTransport())
        } else { transfer = MediaTransfer(api: api) }
        #else
        transfer = MediaTransfer(api: api)
        #endif
        let asset = try await transfer.upload(jobID: jobID, clientAssetID: UUID().uuidString, kind: "photo", mime: "image/png",
                                                             originalFilename: "signature.png", data: data, tags: ["signature"])
        uploadedSignature = (strokes, asset.id)
        return asset.id
    }

    private func decline() async {
        guard reviewReady, let revision = flow.issuedRevision, let generation = reviewGeneration else { return }
        busy = true
        defer { busy = false }
        do {
            let declined = try await api.declineFieldEstimate(flow.estimate.id, revisionNumber: revision.revisionNumber)
            guard generation == api.requestGeneration else { return }
            onApproved(declined)
            onDone()
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Invoice

/// "Show to customer" for an invoice: what was done, what it cost, what is due, then sign or
/// hand back to pay. Payment itself stays with the technician's collect screen.
struct CustomerInvoicePresentation: View {
    let invoice: InvoiceRecord
    let customerName: String
    /// True when the customer should sign for the work on this device.
    let canSign: Bool
    /// The technician takes payment next (Tap to Pay, card, cash); nil when they can't.
    let onPay: (() -> Void)?
    let onSigned: (InvoiceRecord) -> Void
    let onDone: () -> Void

    @EnvironmentObject private var api: APIClient
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var signing = false
    @State private var name: String
    @State private var strokes: [[CGPoint]] = []
    @State private var busy = false
    @State private var error: String?
    @State private var signedBy: String?

    init(invoice: InvoiceRecord, customerName: String, canSign: Bool, onPay: (() -> Void)?, initiallySigning: Bool = false,
         onSigned: @escaping (InvoiceRecord) -> Void, onDone: @escaping () -> Void) {
        self.invoice = invoice
        self.customerName = customerName
        self.canSign = canSign
        self.onPay = onPay
        self.onSigned = onSigned
        self.onDone = onDone
        _name = State(initialValue: customerName)
        _signing = State(initialValue: initiallySigning)
    }

    private var type: CustomerType { CustomerType(sizeClass) }
    private var total: Int { paperLinesTotal(invoice.lines) ?? 0 }
    private var due: Int { max(total - invoice.amountPaid, 0) }
    private var dueText: String { money(due, currency: invoice.currency) }
    private var authorized: Bool {
        signedBy != nil || (invoice.customerAuthorization.map { $0.linesRevision == invoice.linesRevision } ?? false)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if signing { signScreen } else { invoiceScreen }
                }
                .padding(.horizontal, Theme.gutter).padding(.top, 8).padding(.bottom, 24)
                .frame(maxWidth: type.regular ? 760 : .infinity, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            bottomBar
        }
        .foregroundStyle(Theme.foreground)
    }

    private var invoiceScreen: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Invoice for \(customerName)").font(Theme.font(type.body)).foregroundStyle(Theme.muted)
                Text(due == 0 ? "Paid in full" : "Amount due").font(Theme.font(type.heading + 4, weight: .medium))
                    .accessibilityAddTraits(.isHeader)
                if due > 0 {
                    Text(dueText).font(Theme.monoFont(type.total + 8, weight: .medium))
                        .minimumScaleFactor(0.6).lineLimit(1)
                }
            }
            CustomerLinesCard(lines: invoice.lines, currency: invoice.currency, type: type, rows: amountRows)
            if let signedBy {
                Label("Signed by \(signedBy)", systemImage: "signature")
                    .font(Theme.font(type.body)).foregroundStyle(Theme.foreground)
            } else if let signature = invoice.customerAuthorization, signature.linesRevision == invoice.linesRevision {
                Label("Signed by \(signature.signerName)", systemImage: "signature")
                    .font(Theme.font(type.body)).foregroundStyle(Theme.foreground)
            }
        }
    }

    /// CP: Total, Paid, Amount due as labelled rows, amount due last and largest.
    private var amountRows: [CustomerAmountRow] {
        CustomerDocumentAmounts(lines: invoice.lines, currency: invoice.currency, amountPaid: invoice.amountPaid)
            .map { customerAmountRows($0, currency: invoice.currency) } ?? []
    }

    private var signScreen: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Invoice · \(money(total, currency: invoice.currency))").font(Theme.font(type.body)).foregroundStyle(Theme.muted)
                Text("Sign for the work").font(Theme.font(type.heading + 4, weight: .medium)).accessibilityAddTraits(.isHeader)
            }
            Text("By signing, I confirm the work and charges on this invoice.")
                .font(Theme.font(type.body)).fixedSize(horizontal: false, vertical: true)
            TextField("Your full name", text: $name)
                .textContentType(.name)
                .font(Theme.font(type.body))
                .padding(.horizontal, 16)
                .frame(minHeight: type.target)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("Your full name")
            ZStack(alignment: .bottomLeading) {
                SignaturePad(strokes: $strokes)
                if !SignatureInk.hasInk(strokes) {
                    Text("Sign here with your finger").font(Theme.font(type.small)).foregroundStyle(.black.opacity(0.45))
                        .padding(16).allowsHitTesting(false)
                }
            }
            .frame(height: type.regular ? 260 : 220)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
            .overlay(alignment: .topTrailing) {
                if SignatureInk.hasInk(strokes) {
                    Button("Clear") { strokes = [] }
                        .font(Theme.font(type.small, weight: .medium)).foregroundStyle(.black)
                        .frame(minWidth: type.target, minHeight: 44)
                }
            }
            .accessibilityLabel("Signature box. Sign with your finger.")
            if let error {
                Text(error).font(Theme.font(type.body)).foregroundStyle(Theme.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var bottomBar: some View {
        VStack(spacing: 10) {
            if signing {
                let reason = customerSignatureHint(name: name, hasInk: SignatureInk.hasInk(strokes))
                CustomerPresentationCommit(title: "Sign for \(money(total, currency: invoice.currency))", enabled: reason == nil, busy: busy, type: type) {
                    Task { await sign() }
                }
                if let reason { Text(reason).font(Theme.font(type.small)).foregroundStyle(Theme.muted) }
                CustomerSecondaryButton(title: "Back", type: type) { signing = false; error = nil }
            } else if canSign && !authorized && invoice.jobId != nil {
                CustomerPresentationCommit(title: "Sign for the work", enabled: true, busy: false, type: type) { signing = true }
                CustomerSecondaryButton(title: "Done", type: type) { onDone() }
            } else if due > 0, let onPay {
                CustomerPresentationCommit(title: "Pay \(dueText)", enabled: true, busy: false, type: type) { onPay() }
                CustomerSecondaryButton(title: "Done", type: type) { onDone() }
            } else {
                CustomerPresentationCommit(title: "Hand back to the technician", enabled: true, busy: false, type: type) { onDone() }
            }
        }
        .padding(.horizontal, Theme.gutter).padding(.top, 12).padding(.bottom, 8)
        .frame(maxWidth: type.regular ? 640 : .infinity)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
        .disabled(busy)
    }

    private func sign() async {
        let signer = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let jobID = invoice.jobId, !signer.isEmpty, signer.count <= 120, SignatureInk.hasInk(strokes) else { return }
        busy = true
        defer { busy = false }
        error = nil
        do {
            guard let data = SignatureInk.png(strokes) else {
                error = "The signature could not be saved. Try again."
                return
            }
            let asset = try await MediaTransfer(api: api).upload(jobID: jobID, clientAssetID: UUID().uuidString, kind: "photo", mime: "image/png",
                                                                 originalFilename: "signature.png", data: data, tags: ["signature"])
            let input = FieldSignatureInput(signerName: signer, signedAt: ISO8601DateFormatter().string(from: Date()), imageMediaId: asset.id)
            let updated = try await api.authorizeFieldInvoice(invoice.id, expectedLinesRevision: invoice.linesRevision, signature: input)
            onSigned(updated)
            signedBy = signer
            signing = false
        } catch is CancellationError {
        } catch {
            self.error = error.isConnectivityFailure ? "Signing needs a connection. Try again when you have signal." : error.localizedDescription
        }
    }
}

// MARK: - Shared pieces

struct CustomerAmountRow: Hashable {
    let label: String
    let amount: String
    let emphasis: Bool
}

/// Lines, quantity and amount; consent screens keep the full description inline.
struct CustomerLinesCard: View {
    let lines: [FieldLine]
    let currency: String
    let type: CustomerType
    let rows: [CustomerAmountRow]
    var readingAccess: DocumentDescriptionAccess? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            ForEach(lines) { line in
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 8) {
                            lineDetails(line).frame(maxWidth: .infinity, alignment: .leading)
                            lineValue(line).minimumScaleFactor(0.6).lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            lineDetails(line)
                            Spacer(minLength: 8)
                            lineValue(line).fixedSize()
                        }
                    }
                }
                .padding(.vertical, 14)
                .accessibilityElement(children: readingAccess == nil ? .combine : .contain)
                Rectangle().fill(Theme.border).frame(height: 1)
            }
            if lines.isEmpty {
                Text("Nothing listed yet.").font(Theme.font(type.body)).foregroundStyle(Theme.muted).padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(rows, id: \.self) { row in
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 8) {
                            amountLabel(row)
                            amountValue(row).frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    } else {
                        HStack(alignment: .firstTextBaseline) {
                            amountLabel(row)
                            Spacer(minLength: 8)
                            amountValue(row)
                        }
                    }
                }
                .padding(.vertical, row.emphasis ? 16 : 10)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
    }

    private func lineDetails(_ line: FieldLine) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let readingAccess {
                ReadOnlyDocumentDescription(text: line.description, fontSize: type.body, access: readingAccess)
            } else {
                Text(line.description).font(Theme.font(type.body))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Qty \(line.quantity) × \(money(line.unitPrice.amount, currency: line.unitPrice.currency)) each")
                .font(Theme.font(type.small)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func lineValue(_ line: FieldLine) -> some View {
        Text(paperLinesTotal([line]).map { money($0, currency: line.unitPrice.currency) } ?? "Amount unavailable")
            .font(Theme.monoFont(type.body))
    }

    private func amountLabel(_ row: CustomerAmountRow) -> some View {
        Text(row.label).font(Theme.font(row.emphasis ? type.heading : type.body, weight: row.emphasis ? .medium : .regular))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func amountValue(_ row: CustomerAmountRow) -> some View {
        Text(row.amount)
            .font(Theme.monoFont(row.emphasis ? type.total : type.body, weight: row.emphasis ? .medium : .regular))
            .minimumScaleFactor(0.6).lineLimit(1)
    }
}

func customerAmountRows(_ amounts: CustomerDocumentAmounts, currency: String, invoice: Bool = true) -> [CustomerAmountRow] {
    var rows: [CustomerAmountRow] = []
    if amounts.credits < 0 {
        rows.append(.init(label: "Subtotal", amount: money(amounts.subtotal, currency: currency), emphasis: false))
        rows.append(.init(label: "Discounts and credits", amount: money(amounts.credits, currency: currency), emphasis: false))
    }
    rows.append(.init(label: "Total", amount: money(amounts.total, currency: currency), emphasis: !invoice))
    if invoice {
        if amounts.paid > 0 { rows.append(.init(label: "Paid", amount: money(amounts.paid, currency: currency), emphasis: false)) }
        rows.append(.init(label: "Amount due", amount: money(amounts.due, currency: currency), emphasis: true))
    }
    return rows
}

/// The one commit on a customer screen. Same ink, radius and heights as CustomerCommitButton,
/// plus a visibly off state (a well, not dimmed ink) and room for a two-line title at large
/// Dynamic Type sizes.
struct CustomerPresentationCommit: View {
    let title: String
    let enabled: Bool
    let busy: Bool
    let type: CustomerType
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busy { ProgressView().tint(Theme.background) }
                Text(title).font(Theme.font(type.body, weight: .medium)).lineLimit(2).multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: type.regular ? CustomerModeStyle.regularCommitHeight : CustomerModeStyle.commitHeight)
            .padding(.horizontal, 16)
            .foregroundStyle(enabled ? Theme.background : Theme.muted)
            .background(enabled ? Theme.foreground : Theme.fill, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(!enabled || busy)
    }
}

/// The choice mark on an option card: an empty ring, or the accent disc with a check.
struct CustomerRadio: View {
    let selected: Bool
    var body: some View {
        ZStack {
            if selected {
                Circle().fill(Theme.brand)
                Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
            } else {
                Circle().strokeBorder(Theme.foreground.opacity(0.3), lineWidth: 1.5)
            }
        }
        .frame(width: 26, height: 26)
        .accessibilityHidden(true)
    }
}

/// A quiet action under the commit: words only, still a 56pt target.
struct CustomerTextButton: View {
    let title: String
    let type: CustomerType
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(Theme.font(type.small + 1, weight: .medium))
                .foregroundStyle(Theme.subtle)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: type.target)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}

/// Every line of what the customer is approving on one sheet: the line's whole description,
/// its amount, "2 × $120.00" when there's more than one, then the total. No separators.
struct CustomerIncludedLines: View {
    let lines: [FieldLine]
    let type: CustomerType
    let rows: [CustomerAmountRow]
    /// Consent screens read each description through the protected reader.
    var readingAccess: DocumentDescriptionAccess? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(lines) { line in
                VStack(alignment: .leading, spacing: 6) {
                    if dynamicTypeSize.isAccessibilitySize {
                        description(line)
                        amount(line).frame(maxWidth: .infinity, alignment: .trailing)
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            description(line)
                            amount(line).fixedSize()
                        }
                    }
                    Text(line.quantity == 1
                         ? "1 × \(money(line.unitPrice.amount, currency: line.unitPrice.currency))"
                         : "\(line.quantity) × \(money(line.unitPrice.amount, currency: line.unitPrice.currency))")
                        .font(Theme.font(type.small)).monospacedDigit().foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 18).padding(.vertical, 16)
                .accessibilityElement(children: readingAccess == nil ? .combine : .contain)
            }
            if lines.isEmpty {
                Text("Nothing listed yet.").font(Theme.font(type.body)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(18)
            }
            ForEach(rows, id: \.self) { row in
                HStack(alignment: .firstTextBaseline) {
                    Text(row.label).font(Theme.font(row.emphasis ? type.heading : type.body, weight: row.emphasis ? .medium : .regular))
                    Spacer(minLength: 8)
                    Text(row.amount)
                        .font(Theme.font(row.emphasis ? type.total : type.body, weight: row.emphasis ? .medium : .regular)).monospacedDigit()
                        .minimumScaleFactor(0.6).lineLimit(1)
                }
                .padding(.horizontal, 18).padding(.vertical, row.emphasis ? 18 : 12)
                .background(Theme.background.opacity(0.6))
                .accessibilityElement(children: .combine)
            }
        }
        .documentPanel()
    }

    @ViewBuilder private func description(_ line: FieldLine) -> some View {
        if let readingAccess {
            ReadOnlyDocumentDescription(text: line.description, fontSize: type.body, access: readingAccess)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(line.description).font(Theme.font(type.body))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func amount(_ line: FieldLine) -> some View {
        Text(paperLinesTotal([line]).map { money($0, currency: line.unitPrice.currency) } ?? "Amount unavailable")
            .font(Theme.font(type.body, weight: .medium)).monospacedDigit()
    }
}

/// A document's status as a word at customer size: a small dot carries the hue, the word stays ink.
struct CustomerStatusWord: View {
    let status: String
    let type: CustomerType

    var body: some View {
        let tint = StatusWord.documentTint(status)
        HStack(spacing: 8) {
            if let tint { Circle().fill(tint).frame(width: 9, height: 9).accessibilityHidden(true) }
            Text(status == "issued" ? "Unpaid" : status.statusLabel).font(Theme.font(type.small, weight: .medium))
                .foregroundStyle(tint == nil ? Theme.muted : Theme.foreground)
        }
        .fixedSize()
    }
}

/// "What's included" above a customer document's lines.
struct CustomerIncludedLabel: View {
    let type: CustomerType
    var title = "What’s included"
    var body: some View {
        Text(title).font(Theme.font(type.small, weight: .medium)).foregroundStyle(Theme.muted)
            .accessibilityAddTraits(.isHeader)
            .padding(.bottom, -10)
    }
}

/// A plain secondary action: 56pt, filled well, never ink.
struct CustomerSecondaryButton: View {
    let title: String
    let type: CustomerType
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(Theme.font(type.body, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: type.target)
                .foregroundStyle(Theme.foreground)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
/// `--paper-preview-screen present-estimate | present-estimate-review | present-estimate-detail | present-invoice`.
struct CustomerPresentationPreview: View {
    let screen: String
    var body: some View {
        CustomerModeContainer(onUnlocked: {}) { handBack in
            switch screen {
            case "present-invoice":
                CustomerInvoicePresentation(invoice: PaperPreview.issuedInvoice, customerName: "Danielle Marlowe", canSign: true,
                                            onPay: {}, onSigned: { _ in }, onDone: handBack)
            default:
                CustomerEstimatePresentation(estimate: PaperPreview.optionsEstimate, jobID: PaperPreview.jobID, customerName: "Danielle Marlowe",
                                             preselectedOptionID: screen == "present-estimate-review" ? PaperPreview.optionsEstimate.options?[1].id
                                                : screen == "present-estimate-detail" ? PaperPreview.optionsEstimate.options?[0].id : nil,
                                             onApproved: { _ in }, onDone: handBack)
            }
        }
    }
}
#endif

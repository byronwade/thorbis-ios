import SwiftUI

// Customer presentation (design.thorbis.com/customer-presentation, CP-01..CP-18): the estimate
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

    init(estimate: EstimateRecord) {
        self.estimate = estimate
        // CP-08: a single scope has nothing to choose, so it opens on the review.
        step = estimate.status == "approved" ? .done : (Self.options(estimate).isEmpty ? .review : .choose)
    }

    static func options(_ estimate: EstimateRecord) -> [FieldEstimateOption] { estimate.options ?? [] }

    var options: [FieldEstimateOption] { Self.options(estimate) }
    var hasOptions: Bool { !options.isEmpty }
    var selectedOption: FieldEstimateOption? { options.first { $0.id == selectedOptionID } }

    /// The lines and total being approved: the chosen option's, or the estimate's own.
    var lines: [FieldLine] { hasOptions ? selectedOption?.lines ?? [] : estimate.lines }
    var currency: String { selectedOption?.currency ?? estimate.lines.first?.unitPrice.currency ?? "USD" }
    var total: Int? {
        if hasOptions { return selectedOption?.totalAmount }
        return paperLinesTotal(estimate.lines)
    }
    var totalText: String { total.map { money($0, currency: currency) } ?? "" }

    /// The name of what is being approved, said the way the tech says it.
    var choiceName: String { selectedOption?.title ?? estimate.title }

    var canReview: Bool { !hasOptions || selectedOption != nil }

    /// CP-07: the commit names the action and the amount.
    var reviewTitle: String {
        guard let option = selectedOption else { return "Choose an option" }
        return "Review \(option.title) · \(money(option.totalAmount, currency: option.currency))"
    }
    var approveTitle: String { total == nil ? "Approve and sign" : "Approve and sign · \(totalText)" }
    var signTitle: String { total == nil ? "Approve" : "Approve \(totalText)" }

    mutating func choose(_ optionID: String) { selectedOptionID = optionID }
    mutating func review() { if canReview { step = .review } }
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

// MARK: - In-person approval with options

private struct IssuedPaper: Decodable { let contentHash: String }
private struct InPersonLink: Decodable { let token: String }

@MainActor
extension APIClient {
    /// Options are chosen and signed through the same customer action the emailed link uses, so
    /// the server records which option and whose name. Issuing is content-addressed (a repeat
    /// returns the same paper); minting replaces any earlier link for this revision.
    func openInPersonEstimateApproval(_ id: String, revisionNumber: Int) async throws -> (token: String, action: PublicEstimateAction) {
        struct Empty: Encodable {}
        struct Mint: Encodable { let revisionNumber: Int; let contentHash: String }
        let paper: IssuedPaper = try await send("POST", financialPath("/v1/estimates", id: id, suffix: "/commercial-documents"), body: Empty())
        let link: InPersonLink = try await send("POST", financialPath("/v1/estimates", id: id, suffix: "/action-tokens"),
                                                body: Mint(revisionNumber: revisionNumber, contentHash: paper.contentHash))
        return (link.token, try await publicDocumentAction(token: link.token))
    }
}

// MARK: - Estimate

/// "Show to customer" for an estimate: choose an option, review it, sign, done.
struct CustomerEstimatePresentation: View {
    let jobID: String?
    let customerName: String
    /// True when the company offers financing; the lender decides per amount (CP-13, CP-14).
    let financing: Bool
    let onApproved: (EstimateRecord?) -> Void
    let onDone: () -> Void

    @EnvironmentObject private var api: APIClient
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var flow: CustomerEstimateFlow
    @State private var offer = FinancingOffer.off
    @State private var showTerms = false
    @State private var detailsFor: FieldEstimateOption?
    @State private var confirmNotToday = false
    @State private var name: String
    @State private var strokes: [[CGPoint]] = []
    @State private var consentText: String?
    @State private var busy = false
    @State private var error: String?
    @State private var signedAt: Date?
    @State private var signedName = ""
    @State private var isMember = false

    init(estimate: EstimateRecord, jobID: String?, customerName: String, preselectedOptionID: String? = nil, financing: Bool = false,
         onApproved: @escaping (EstimateRecord?) -> Void, onDone: @escaping () -> Void) {
        self.jobID = jobID
        self.customerName = customerName
        self.financing = financing
        self.onApproved = onApproved
        self.onDone = onDone
        var flow = CustomerEstimateFlow(estimate: estimate)
        if let preselectedOptionID {
            flow.choose(preselectedOptionID)
            flow.review()
        }
        _flow = State(initialValue: flow)
        _name = State(initialValue: customerName)
    }

    private var type: CustomerType { CustomerType(sizeClass) }
    /// The proven drawn-signature approval needs a job and a single scope; options go through
    /// the customer action, which records the chosen option with the typed name.
    private var drawnApproval: Bool { jobID != nil && !flow.hasOptions }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch flow.step {
                    case .choose: chooseScreen
                    case .review: reviewScreen
                    case .sign: signScreen
                    case .done: doneScreen
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .frame(maxWidth: type.regular ? 1000 : .infinity, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            bottomBar
        }
        .foregroundStyle(Theme.foreground)
        .animation(.easeOut(duration: 0.2), value: flow.step)
        .sheet(item: $detailsFor) { option in includedSheet(option) }
        .sheet(isPresented: $showTerms) { FinancingTermsSheet(offer: offer, type: type) }
        .task { await loadOffer() }
        .task { isMember = await api.customerIsMember(flow.estimate.customerId) }
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
            Text("Tap the one you want. You'll see everything again before you sign.")
                .font(Theme.font(type.body)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            let options = flow.options
            if type.regular && options.count <= 3 {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(options) { optionCard($0) }
                }
            } else {
                VStack(spacing: 16) { ForEach(options) { optionCard($0) } }
            }
            if options.contains(where: { offer.example(for: $0.totalAmount) != nil }) { seeTerms }
        }
    }

    /// The lender's disclosure is one tap from any monthly number (CP-14).
    @ViewBuilder private var seeTerms: some View {
        if offer.disclosure != nil {
            Button { showTerms = true } label: {
                Text("See \(offer.lenderName) terms").font(Theme.font(type.body)).underline()
                    .foregroundStyle(Theme.brandText)
                    .frame(minHeight: type.target, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
    }

    private func optionCard(_ option: FieldEstimateOption) -> some View {
        let selected = flow.selectedOptionID == option.id
        return VStack(alignment: .leading, spacing: 10) {
            Text(option.title).font(Theme.font(type.heading, weight: .medium))
                .accessibilityAddTraits(.isHeader)
            if !option.description.isEmpty {
                Text(option.description).font(Theme.font(type.body))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(money(option.totalAmount, currency: option.currency))
                .font(Theme.monoFont(type.total, weight: .medium))
                .minimumScaleFactor(0.6).lineLimit(1)
                .accessibilityLabel("Total \(money(option.totalAmount, currency: option.currency))")
            if let saved = customerSavingsText(option.lines, currency: option.currency) {
                Text("Includes \(savingsLabel(isMember).lowercased()) of \(saved)")
                    .font(Theme.font(type.small)).foregroundStyle(Theme.muted)
            }
            if let example = offer.example(for: option.totalAmount) {
                CustomerFinancingLine(example: example, type: type)
            }
            Button { detailsFor = option } label: {
                Text("See what's included").font(Theme.font(type.body)).underline()
                    .foregroundStyle(Theme.brandText)
                    .frame(minHeight: type.target, alignment: .leading)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            Button { flow.choose(option.id) } label: {
                HStack(spacing: 10) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24))
                        .foregroundStyle(selected ? Theme.brandText : Theme.muted)
                        .accessibilityHidden(true)
                    Text(selected ? "Selected" : "Choose \(option.title)")
                        .font(Theme.font(type.body, weight: .medium))
                }
                .frame(maxWidth: .infinity, minHeight: type.target)
                .foregroundStyle(Theme.foreground)
                // Selection is the blue pointer; the screen's only ink is the commit (CP-07).
                .background(selected ? Theme.brandSurface : Theme.fill, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? Theme.foreground : Theme.border, lineWidth: selected ? 2 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture { flow.choose(option.id) }
    }

    private var reviewScreen: some View {
        VStack(alignment: .leading, spacing: 20) {
            header(eyebrow: "You're approving", title: flow.choiceName)
            if flow.hasOptions, let description = flow.selectedOption?.description, !description.isEmpty {
                Text(description).font(Theme.font(type.body)).fixedSize(horizontal: false, vertical: true)
            }
            CustomerLinesCard(lines: customerEstimateLines(flow.lines), currency: flow.currency, type: type,
                              rows: customerSavingsRows(flow.lines, currency: flow.currency, isMember: isMember)
                                  + (flow.total.map { [CustomerAmountRow(label: "Total", amount: money($0, currency: flow.currency), emphasis: true)] } ?? []))
            if let total = flow.total, let example = offer.example(for: total) {
                CustomerFinancingLine(example: example, type: type)
                seeTerms
            }
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
            Text("Thank you. Please hand the device back to your technician.")
                .font(Theme.font(type.body)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var doneSentence: String {
        let what = flow.choiceName
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
            switch flow.step {
            case .choose:
                CustomerPresentationCommit(title: flow.reviewTitle, enabled: flow.canReview, busy: false, type: type) { flow.review() }
                if let error { hint(error, danger: true) } else if !flow.canReview { hint("Choose an option above to continue.") }
                CustomerSecondaryButton(title: "Not today", type: type) { confirmNotToday = true }
            case .review:
                CustomerPresentationCommit(title: flow.approveTitle, enabled: true, busy: busy, type: type) { Task { await startSigning() } }
                if let error { hint(error, danger: true) }
                HStack(spacing: 10) {
                    if flow.hasOptions { CustomerSecondaryButton(title: "Back", type: type) { flow.back() } }
                    CustomerSecondaryButton(title: "Not today", type: type) { confirmNotToday = true }
                }
            case .sign:
                let reason = customerSignatureHint(name: name, hasInk: SignatureInk.hasInk(strokes))
                CustomerPresentationCommit(title: flow.signTitle, enabled: reason == nil, busy: busy, type: type) { Task { await approve() } }
                if let reason { hint(reason) }
                CustomerSecondaryButton(title: "Back", type: type) { flow.back(); error = nil }
            case .done:
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

    private func includedSheet(_ option: FieldEstimateOption) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(option.title).font(Theme.font(type.heading + 4, weight: .medium))
                    CustomerLinesCard(lines: customerEstimateLines(option.lines), currency: option.currency, type: type,
                                      rows: customerSavingsRows(option.lines, currency: option.currency, isMember: isMember)
                                          + [CustomerAmountRow(label: "Total", amount: money(option.totalAmount, currency: option.currency), emphasis: true)])
                }
                .padding(Theme.gutter)
            }
            .background(Theme.background)
            .foregroundStyle(Theme.foreground)
            .navigationTitle("What's included")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { detailsFor = nil }.font(Theme.font(type.small, weight: .medium)).frame(minHeight: 44)
                }
            }
            .safeAreaInset(edge: .bottom) {
                CustomerPresentationCommit(title: flow.selectedOptionID == option.id ? "Selected" : "Choose \(option.title)",
                                           enabled: true, busy: false, type: type) {
                    flow.choose(option.id)
                    detailsFor = nil
                }
                .padding(.horizontal, Theme.gutter).padding(.vertical, 8)
                .background(Theme.background)
            }
        }
    }

    // MARK: Actions

    @State private var link: (token: String, action: PublicEstimateAction)?

    /// One request for every total on screen; any failure simply shows no financing.
    private func loadOffer() async {
        guard financing else { return }
        let amounts = flow.hasOptions ? flow.options.map(\.totalAmount) : (flow.total.map { [$0] } ?? [])
        offer = await api.financingOffer(amounts: amounts)
    }

    private func startSigning() async {
        error = nil
        guard !drawnApproval else { flow.step = .sign; return }
        guard let revision = flow.estimate.currentRevisionNumber else {
            error = "This estimate can't be signed yet. Ask your technician."
            return
        }
        busy = true
        defer { busy = false }
        do {
            let opened = try await api.openInPersonEstimateApproval(flow.estimate.id, revisionNumber: revision)
            guard opened.action.signingOffered else {
                error = "This estimate can't be signed here. Ask your technician."
                return
            }
            link = opened
            consentText = opened.action.consentText
            flow.step = .sign
        } catch is CancellationError {
        } catch {
            self.error = error.isConnectivityFailure ? "Approving needs a connection. Try again when you have signal." : error.localizedDescription
        }
    }

    private func approve() async {
        let signer = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !signer.isEmpty, signer.count <= 120, SignatureInk.hasInk(strokes) else { return }
        busy = true
        defer { busy = false }
        error = nil
        do {
            if drawnApproval, let jobID, let revision = flow.estimate.currentRevisionNumber {
                let mediaID = try await uploadSignature(jobID: jobID)
                let input = FieldSignatureInput(signerName: signer, signedAt: ISO8601DateFormatter().string(from: Date()), imageMediaId: mediaID)
                let approved = try await api.approveFieldEstimate(flow.estimate.id, revisionNumber: revision, signature: input)
                onApproved(approved)
            } else if let link {
                let action = link.action
                guard let nonce = action.nonce, let consentVersion = action.consentVersion else {
                    error = "This estimate can't be signed here. Ask your technician."
                    return
                }
                // The drawing is kept with the job; the server records the typed name and option.
                if let jobID { _ = try? await uploadSignature(jobID: jobID) }
                _ = try await api.decidePublicDocumentAction(token: link.token, decision: .approve(
                    revisionNumber: action.revisionNumber, nonce: nonce, contentHash: action.contentHash,
                    signerName: signer, consentVersion: consentVersion, consent: true, optionID: flow.selectedOptionID))
                onApproved(nil)
            } else {
                return
            }
            signedName = signer
            signedAt = Date()
            flow.step = .done
        } catch is CancellationError {
        } catch {
            self.error = error.isConnectivityFailure ? "Approving needs a connection. Try again when you have signal." : error.localizedDescription
        }
    }

    @State private var uploadedSignature: (strokes: [[CGPoint]], mediaID: String)?

    private func uploadSignature(jobID: String) async throws -> String {
        if let uploadedSignature, uploadedSignature.strokes == strokes { return uploadedSignature.mediaID }
        guard let data = SignatureInk.png(strokes) else {
            throw Problem(title: "The signature could not be saved. Try again.", status: nil, detail: nil)
        }
        let asset = try await MediaTransfer(api: api).upload(jobID: jobID, clientAssetID: UUID().uuidString, kind: "photo", mime: "image/png",
                                                             originalFilename: "signature.png", data: data, tags: ["signature"])
        uploadedSignature = (strokes, asset.id)
        return asset.id
    }

    private func decline() async {
        guard let revision = flow.estimate.currentRevisionNumber else { onDone(); return }
        busy = true
        defer { busy = false }
        do {
            let declined = try await api.declineFieldEstimate(flow.estimate.id, revisionNumber: revision)
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
    private let openedInvoice: InvoiceRecord
    let customerName: String
    /// True when the customer should sign for the work on this device.
    let canSign: Bool
    /// The technician takes payment next (Tap to Pay, card, cash); nil when they can't.
    let onPay: (() -> Void)?
    /// True when the company offers financing and this person may send an application.
    let financing: Bool
    let onSigned: (InvoiceRecord) -> Void
    let onDone: () -> Void

    @EnvironmentObject private var api: APIClient
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var signing = false
    @State private var offer = FinancingOffer.off
    @State private var applications: [FinancingApplication] = []
    @State private var payChoice: CustomerPayChoice?
    @State private var otherPhone: String?
    @State private var applicationKey = UUID().uuidString
    @State private var sent: FinancingApplication?
    @State private var showTerms = false
    /// The invoice as re-read after the lender funded it while this screen was open.
    @State private var reloadedInvoice: InvoiceRecord?
    private var invoice: InvoiceRecord { reloadedInvoice ?? openedInvoice }
    @State private var name: String
    @State private var strokes: [[CGPoint]] = []
    @State private var busy = false
    @State private var error: String?
    @State private var signedBy: String?
    @State private var isMember = false

    /// Opens on "Choose how to pay" once the offer loads (the pay-screen preview).
    private let opensPayChoice: Bool

    init(invoice: InvoiceRecord, customerName: String, canSign: Bool, onPay: (() -> Void)?, financing: Bool = false,
         opensPayChoice: Bool = false, onSigned: @escaping (InvoiceRecord) -> Void, onDone: @escaping () -> Void) {
        self.opensPayChoice = opensPayChoice
        openedInvoice = invoice
        self.customerName = customerName
        self.canSign = canSign
        self.onPay = onPay
        self.financing = financing
        self.onSigned = onSigned
        self.onDone = onDone
        _name = State(initialValue: customerName)
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
                    if let sent { sentScreen(sent) } else if signing { signScreen } else if payChoice != nil { payScreen } else { invoiceScreen }
                }
                .padding(.horizontal, Theme.gutter).padding(.top, 8).padding(.bottom, 24)
                .frame(maxWidth: type.regular ? 760 : .infinity, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            bottomBar
        }
        .foregroundStyle(Theme.foreground)
        .animation(.easeOut(duration: 0.2), value: payChoice)
        .sheet(isPresented: $showTerms) { FinancingTermsSheet(offer: offer, type: type) }
        .task { await loadFinancing() }
        .task { isMember = await api.customerIsMember(invoice.customerId) }
    }

    /// The lender's example for the amount due, when the company finances it (CP-13, range rule).
    /// Nothing new to apply for while an application is still out with the lender.
    private var dueExample: FinancingExample? {
        guard due > 0, !applications.contains(where: \.isOpen) else { return nil }
        return offer.example(for: due)
    }
    private var latestApplication: FinancingApplication? { applications.first }
    private var financingStatus: String? { latestApplication.flatMap { FinancingWords.status($0, forCustomer: true) } }

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
                // CP-17: where the application stands, in words.
                if let financingStatus {
                    Text(financingStatus).font(Theme.font(type.body)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
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

    // MARK: Choose how to pay (CP-15, CP-16)

    private var payScreen: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Invoice for \(customerName)").font(Theme.font(type.body)).foregroundStyle(Theme.muted)
                Text(payChoice?.title ?? "").font(Theme.font(type.heading + 4, weight: .medium))
                    .accessibilityAddTraits(.isHeader).fixedSize(horizontal: false, vertical: true)
            }
            if payChoice?.canPayInFull == true {
                payCard(.inFull, title: "Pay in full") {
                    Text(dueText).font(Theme.monoFont(type.total, weight: .medium)).minimumScaleFactor(0.6).lineLimit(1)
                    Text("Card or Tap to Pay with your technician").font(Theme.font(type.small)).foregroundStyle(Theme.muted)
                }
            }
            if payChoice?.canFinance == true, let example = dueExample {
                payCard(.overTime, title: "Pay over time") {
                    CustomerFinancingLine(example: example, type: type)
                    Text("With \(offer.lenderName)").font(Theme.font(type.small)).foregroundStyle(Theme.muted)
                }
                if payChoice?.selected == .overTime { applyReview }
            }
            if let error {
                Text(error).font(Theme.font(type.body)).foregroundStyle(Theme.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func payCard(_ method: CustomerPayChoice.Method, title: String, @ViewBuilder content: () -> some View) -> some View {
        let selected = payChoice?.selected == method
        return Button { payChoice?.selected = method; error = nil } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(selected ? Theme.brandText : Theme.muted)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(Theme.font(type.heading, weight: .medium))
                    content()
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: type.target, alignment: .leading)
            .foregroundStyle(Theme.foreground)
            .background(selected ? Theme.brandSurface : Theme.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? Theme.foreground : Theme.border, lineWidth: selected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// CP-16: the customer applies on their own phone; Thorbis never sees credit details.
    private var applyReview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(applySentence).font(Theme.font(type.body)).fixedSize(horizontal: false, vertical: true)
            if let note = offer.creditCheckNote {
                Text(note).font(Theme.font(type.body)).fixedSize(horizontal: false, vertical: true)
            }
            if otherPhone != nil {
                TextField("Mobile number", text: Binding(get: { otherPhone ?? "" }, set: { otherPhone = $0 }))
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .font(Theme.font(type.body))
                    .padding(.horizontal, 16)
                    .frame(minHeight: type.target)
                    .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("Mobile number for the application")
            } else {
                CustomerSecondaryButton(title: "Use a different number", type: type) { otherPhone = "" }
            }
            if offer.disclosure != nil {
                Button { showTerms = true } label: {
                    Text("See \(offer.lenderName) terms").font(Theme.font(type.body)).underline()
                        .foregroundStyle(Theme.brandText)
                        .frame(minHeight: type.target, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
    }

    private var applySentence: String {
        let to = otherPhone == nil ? "your mobile number on file" : "the number below"
        return "\(offer.lenderName) will text a secure application for \(dueText) to \(to). It takes about 2 minutes on your phone."
    }

    /// The typed number, or nil to use the one on file. Invalid text blocks the commit.
    private var typedPhone: (valid: Bool, value: String?) {
        guard let otherPhone else { return (true, nil) }
        guard let mobile = FinancingWords.usMobile(otherPhone) else { return (false, nil) }
        return (true, mobile)
    }

    private func sentScreen(_ application: FinancingApplication) -> some View {
        VStack(alignment: .center, spacing: 18) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 64)).foregroundStyle(Theme.success)
                .accessibilityHidden(true).padding(.top, 40)
            Text("Application sent").font(Theme.font(type.heading + 6, weight: .medium)).accessibilityAddTraits(.isHeader)
            Text("Sent to •••• \(application.sentToLast4)").font(Theme.font(type.body))
            Text(money(application.amount.amount, currency: application.amount.currency))
                .font(Theme.monoFont(type.total, weight: .medium))
            Text("Open the text from \(application.providerName) to apply. The answer shows on this invoice.")
                .font(Theme.font(type.body)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    /// CP: Total, Paid, Amount due as labelled rows, amount due last and largest.
    private var amountRows: [CustomerAmountRow] {
        var rows = customerSavingsRows(invoice.lines, currency: invoice.currency, isMember: isMember)
        rows.append(CustomerAmountRow(label: "Total", amount: money(total, currency: invoice.currency), emphasis: invoice.amountPaid == 0))
        if invoice.amountPaid > 0 {
            rows.append(CustomerAmountRow(label: "Paid", amount: money(invoice.amountPaid, currency: invoice.currency), emphasis: false))
            rows.append(CustomerAmountRow(label: "Amount due", amount: dueText, emphasis: true))
        }
        return rows
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
            if sent != nil {
                CustomerPresentationCommit(title: "Hand back to the technician", enabled: true, busy: false, type: type) { onDone() }
            } else if let choice = payChoice {
                let phone = typedPhone
                let enabled = choice.selected != nil && (choice.selected != .overTime || phone.valid)
                CustomerPresentationCommit(title: choice.commitTitle, enabled: enabled, busy: busy, type: type) {
                    switch choice.selected {
                    case .inFull: onPay?()
                    case .overTime: Task { await apply(phone: phone.value) }
                    case nil: break
                    }
                }
                if let hint = choice.hint {
                    Text(hint).font(Theme.font(type.small)).foregroundStyle(Theme.muted)
                } else if choice.selected == .overTime && !phone.valid {
                    Text("Enter a US mobile number to continue.").font(Theme.font(type.small)).foregroundStyle(Theme.muted)
                }
                CustomerSecondaryButton(title: "Back", type: type) { payChoice = nil; otherPhone = nil; error = nil }
            } else if signing {
                let reason = customerSignatureHint(name: name, hasInk: SignatureInk.hasInk(strokes))
                CustomerPresentationCommit(title: "Sign for \(money(total, currency: invoice.currency))", enabled: reason == nil, busy: busy, type: type) {
                    Task { await sign() }
                }
                if let reason { Text(reason).font(Theme.font(type.small)).foregroundStyle(Theme.muted) }
                CustomerSecondaryButton(title: "Back", type: type) { signing = false; error = nil }
            } else if canSign && !authorized && invoice.jobId != nil {
                CustomerPresentationCommit(title: "Sign for the work", enabled: true, busy: false, type: type) { signing = true }
                CustomerSecondaryButton(title: "Done", type: type) { onDone() }
            } else if due > 0, dueExample != nil || onPay != nil {
                CustomerPresentationCommit(title: "Pay \(dueText)", enabled: true, busy: false, type: type) { pay() }
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

    /// With financing on the table the customer chooses first; otherwise straight to payment.
    private func pay() {
        guard dueExample != nil else { onPay?(); return }
        payChoice = CustomerPayChoice(dueText: dueText, canPayInFull: onPay != nil, canFinance: true,
                                      selected: onPay == nil ? .overTime : nil)
    }

    private func loadFinancing() async {
        guard financing else { return }
        if due > 0 {
            offer = await api.financingOffer(amounts: [due])
            if offer.available, opensPayChoice { pay() }
        }
        // A paid invoice still says "Paid by Wisetack", so the history loads whatever is due.
        let latest = (try? await api.refreshFinancingApplications(invoiceID: invoice.id)) ?? []
        applications = latest
        // A loan funded since the invoice was opened is a payment: show the balance it leaves.
        if latest.contains(where: { $0.status == "funded" }), invoice.amountPaid < (paperLinesTotal(invoice.lines) ?? 0),
           let updated = try? await api.fieldInvoice(invoice.id) {
            reloadedInvoice = updated
            onSigned(updated)
            // The offer answered for the old balance; ask again for what the loan left.
            offer = due > 0 ? await api.financingOffer(amounts: [due]) : .off
        }
    }

    private func apply(phone: String?) async {
        busy = true
        defer { busy = false }
        error = nil
        do {
            let application = try await api.sendFinancingApplication(invoiceID: invoice.id, idempotencyKey: applicationKey, phone: phone)
            applications.insert(application, at: 0)
            sent = application
        } catch is CancellationError {
        } catch {
            // Only a definite refusal starts a new request. After a lost answer or an outage the
            // same key comes back, so the server returns the application it may already have sent.
            if let problem = error as? Problem, let status = problem.status, (400..<500).contains(status) {
                applicationKey = UUID().uuidString
            }
            self.error = error.isConnectivityFailure ? "Sending the application needs a connection. Try again when you have signal." : error.localizedDescription
        }
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

/// What the customer saves off list price on these lines: each price book line records the list
/// price it came from, and the server charges a member the member price (CP: savings show only
/// when the amount already includes them). Invoice lines carry the estimate line's provenance.
func customerSavings(_ lines: [FieldLine]) -> Int {
    lines.reduce(0) { sum, line in
        let source = line.source?.kind == "price_book" ? line.source?.originalUnitPrice
            : line.source?.estimateLineSource?.kind == "price_book" ? line.source?.estimateLineSource?.originalUnitPrice : nil
        guard let list = source, list.currency == line.unitPrice.currency, list.amount > line.unitPrice.amount,
              line.unitPrice.amount >= 0 else { return sum }
        return sum + line.quantity * (list.amount - line.unitPrice.amount)
    }
}

func customerSavingsText(_ lines: [FieldLine], currency: String) -> String? {
    let saved = customerSavings(lines)
    return saved > 0 ? money(saved, currency: currency) : nil
}

/// "Member savings" when the customer holds a membership; otherwise the plain word.
func savingsLabel(_ isMember: Bool) -> String { isMember ? "Member savings" : "Savings" }

/// A labelled savings row (CP-06), shown above the total and never as a strike-through alone.
func customerSavingsRows(_ lines: [FieldLine], currency: String, isMember: Bool) -> [CustomerAmountRow] {
    guard let saved = customerSavingsText(lines, currency: currency) else { return [] }
    return [CustomerAmountRow(label: savingsLabel(isMember), amount: "−\(saved)", emphasis: false)]
}

@MainActor
extension APIClient {
    /// Whether to call savings "member savings". Technicians may not read memberships yet, so any
    /// refusal reads as not known and the row says "Savings".
    func customerIsMember(_ customerID: String) async -> Bool {
        (try? await memberPricing(customerID))?.isMember ?? false
    }
}

struct CustomerAmountRow: Hashable {
    let label: String
    let amount: String
    let emphasis: Bool
}

/// Lines as name, then "Qty × Each" under it, amount on the right; no truncation (CP-06).
struct CustomerLinesCard: View {
    let lines: [FieldLine]
    let currency: String
    let type: CustomerType
    let rows: [CustomerAmountRow]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(lines) { line in
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(line.description).font(Theme.font(type.body))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Qty \(line.quantity) × \(money(line.unitPrice.amount, currency: line.unitPrice.currency)) each")
                            .font(Theme.font(type.small)).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 8)
                    Text(money(line.quantity * line.unitPrice.amount, currency: line.unitPrice.currency))
                        .font(Theme.monoFont(type.body)).fixedSize()
                }
                .padding(.vertical, 14)
                .accessibilityElement(children: .combine)
                Rectangle().fill(Theme.border).frame(height: 1)
            }
            if lines.isEmpty {
                Text("Nothing listed yet.").font(Theme.font(type.body)).foregroundStyle(Theme.muted).padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(rows, id: \.self) { row in
                HStack(alignment: .firstTextBaseline) {
                    Text(row.label).font(Theme.font(row.emphasis ? type.heading : type.body, weight: row.emphasis ? .medium : .regular))
                    Spacer(minLength: 8)
                    Text(row.amount)
                        .font(Theme.monoFont(row.emphasis ? type.total : type.body, weight: row.emphasis ? .medium : .regular))
                        .minimumScaleFactor(0.6).lineLimit(1)
                }
                .padding(.vertical, row.emphasis ? 16 : 10)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
    }
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
/// `--paper-preview-screen present-estimate | present-estimate-review | present-invoice |
/// present-estimate-financing | present-invoice-pay`.
struct CustomerPresentationPreview: View {
    let screen: String
    var body: some View {
        CustomerModeContainer(onUnlocked: {}) { handBack in
            switch screen {
            case "present-invoice":
                CustomerInvoicePresentation(invoice: PaperPreview.issuedInvoice, customerName: "Danielle Marlowe", canSign: true,
                                            onPay: {}, onSigned: { _ in }, onDone: handBack)
            case "present-invoice-pay":
                CustomerInvoicePresentation(invoice: PaperPreview.financingInvoice, customerName: "Danielle Marlowe", canSign: false,
                                            onPay: {}, financing: true, opensPayChoice: true, onSigned: { _ in }, onDone: handBack)
            default:
                CustomerEstimatePresentation(estimate: PaperPreview.optionsEstimate, jobID: PaperPreview.jobID, customerName: "Danielle Marlowe",
                                             preselectedOptionID: screen == "present-estimate-review" ? PaperPreview.optionsEstimate.options?[1].id : nil,
                                             financing: screen == "present-estimate-financing",
                                             onApproved: { _ in }, onDone: handBack)
            }
        }
    }
}
#endif

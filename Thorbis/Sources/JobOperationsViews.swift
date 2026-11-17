import MessageUI
import SwiftUI
import UIKit

/// "Before you close": the server's closeout requirements, then the acknowledgement checks its
/// policy asks for. One source for the checklist screen and the job's on-site panel, so their
/// "x of y" always agree. Nothing here invents a requirement.
struct CloseoutChecklistItem: Identifiable, Hashable {
    let id: String
    let title: String
    let done: Bool
    /// The requirement's kind ("notes", "photos", ...) or "acknowledgement" for a check.
    let kind: String
    /// The server's next action for a blocked requirement, e.g. "add_job_photo".
    let nextAction: String?
    /// Set for an acknowledgement check, confirmed on the checklist screen.
    let checkKey: String?
}

enum CloseoutChecklist {
    static func acknowledgementChecks(_ closeout: FieldCloseout) -> [FieldCloseoutCheckDefinition] {
        closeout.policy.requiredChecks.filter { $0.kind == nil || $0.kind == "acknowledgement" }
    }

    static func items(_ closeout: FieldCloseout) -> [CloseoutChecklistItem] {
        let requirements = closeout.requirements.enumerated().map { offset, requirement in
            CloseoutChecklistItem(id: "requirement-\(offset)-\(requirement.requirement)", title: requirement.detail,
                                  done: requirement.outcome != "blocked", kind: requirement.kind,
                                  nextAction: requirement.outcome == "blocked" ? requirement.nextAction : nil, checkKey: nil)
        }
        let checks = acknowledgementChecks(closeout).map { check in
            CloseoutChecklistItem(id: "check-\(check.key)", title: check.label,
                                  done: closeout.facts.acknowledgedCheckKeys.contains(check.key),
                                  kind: "acknowledgement", nextAction: nil, checkKey: check.key)
        }
        return requirements + checks
    }

    static func progress(_ closeout: FieldCloseout) -> (done: Int, total: Int) {
        let all = items(closeout)
        return (all.filter(\.done).count, all.count)
    }
}

/// OnSite.dc.html "Before you wrap up · 3 of 6": what's left at the house, read from the job's own
/// record (photos by stage, notes, the estimate, the completion invoice) and then any server
/// closeout rule those rows don't already say. A row whose fact hasn't loaded yet is left out
/// rather than shown as missing. A blocked server requirement always keeps its row open, so the
/// list never reaches 0 while the server still holds closing.
struct WrapUpRow: Identifiable, Hashable {
    enum Step: Hashable {
        case beforePhotos
        case diagnosisNote
        case approval
        case afterPhotos
        case signature
        case payment
        /// A closeout rule the rows above don't cover (an acknowledgement, a photo count, ...).
        case server(CloseoutChecklistItem)
    }

    let step: Step
    let title: String
    /// Short and on the right: a count or an amount ("3", "$480.00 due").
    var detail: String? = nil
    let done: Bool

    var id: String {
        if case .server(let item) = step { return item.id }
        return "\(step)"
    }
}

enum WrapUpList {
    struct Inputs {
        /// Photos filed Before / After on this job (server and still on this phone); nil when unknown.
        var beforePhotos: Int?
        var afterPhotos: Int?
        /// The job's estimates once read; nil while loading.
        var estimates: [EstimateRecord]?
        /// The job's invoices once read (void ones included); nil while loading or not viewable.
        var invoices: [InvoiceRecord]?
        var closeout: FieldCloseout?
    }

    /// The row that already speaks for a server requirement, by its next action, then its kind.
    static func covering(_ requirement: FieldCloseoutRequirement) -> WrapUpRow.Step? {
        switch requirement.nextAction {
        case "add_job_note": return .diagnosisNote
        case "collect_customer_authorization": return .signature
        case "collect_payment", "reconcile_commercial_state", "record_unpaid_disposition": return .payment
        default: break
        }
        switch requirement.kind {
        case "notes": return .diagnosisNote
        case "payment_or_unpaid_disposition": return .payment
        default: return nil
        }
    }

    /// The completion invoice when there is one, else the first live invoice on the job.
    static func billingInvoice(_ invoices: [InvoiceRecord]) -> InvoiceRecord? {
        let live = invoices.filter { $0.status != "void" }
        return live.first(where: { $0.origin == "job_completion" }) ?? live.first
    }

    static func rows(_ inputs: Inputs) -> [WrapUpRow] {
        let requirements = inputs.closeout?.requirements ?? []
        let blockedSteps = Set(requirements.filter { $0.outcome == "blocked" }.compactMap(covering))
        var rows: [WrapUpRow] = []

        if let before = inputs.beforePhotos {
            rows.append(WrapUpRow(step: .beforePhotos, title: "Before photos", detail: before > 0 ? "\(before)" : nil, done: before > 0))
        }
        if let closeout = inputs.closeout {
            let notes = closeout.facts.noteCount
            rows.append(WrapUpRow(step: .diagnosisNote, title: "Diagnosis note", detail: notes > 1 ? "\(notes)" : nil,
                                  done: notes > 0 && !blockedSteps.contains(.diagnosisNote)))
        }
        // Approval only when the visit has an estimate in play; a call billed from the truck has none.
        if let estimates = inputs.estimates, !estimates.isEmpty, !estimates.allSatisfy({ $0.status == "declined" }) {
            if let approved = estimates.first(where: { $0.status == "approved" }) {
                let currency = approved.lines.first?.unitPrice.currency ?? "USD"
                rows.append(WrapUpRow(step: .approval, title: "Customer approved \(approved.title)",
                                      detail: paperLinesTotal(approved.lines).map { jobShortMoney($0, currency: currency) }, done: true))
            } else {
                rows.append(WrapUpRow(step: .approval, title: "Customer approval", done: false))
            }
        }
        if let after = inputs.afterPhotos {
            rows.append(WrapUpRow(step: .afterPhotos, title: "After photos", detail: after > 0 ? "\(after)" : nil, done: after > 0))
        }
        if let invoices = inputs.invoices {
            let invoice = billingInvoice(invoices)
            let signed = invoice.map { invoice in invoice.customerAuthorization?.linesRevision == invoice.linesRevision } ?? false
            rows.append(WrapUpRow(step: .signature, title: "Customer signature", done: signed && !blockedSteps.contains(.signature)))
            let due = invoice.flatMap { TechJobFlow.due($0) }
            let owed = invoice?.status == "draft" ? invoice.flatMap { paperLinesTotal($0.lines) } : due
            let paid = invoice.map { $0.status == "paid" || ($0.status == "issued" && due == 0) } ?? false
            let currency = invoice?.currency ?? "USD"
            rows.append(WrapUpRow(step: .payment, title: "Collect payment",
                                  detail: paid ? "Paid" : owed.flatMap { $0 > 0 ? "\(jobShortMoney($0, currency: currency))\u{00A0}due" : nil },
                                  done: paid && !blockedSteps.contains(.payment)))
        }

        // Whatever else the server holds closing on: a blocked rule no row above speaks for (a
        // photo count lands here), then the acknowledgement checks the policy asks for.
        if let closeout = inputs.closeout {
            let items = CloseoutChecklist.items(closeout)
            for (offset, requirement) in requirements.enumerated() where requirement.outcome == "blocked" {
                if let step = covering(requirement), rows.contains(where: { $0.step == step }) { continue }
                if let item = items.first(where: { $0.id == "requirement-\(offset)-\(requirement.requirement)" }) {
                    rows.append(WrapUpRow(step: .server(item), title: item.title, done: false))
                }
            }
            for item in items where item.kind == "acknowledgement" {
                rows.append(WrapUpRow(step: .server(item), title: item.title, done: item.done))
            }
        }
        return rows
    }

    static func left(_ rows: [WrapUpRow]) -> Int { rows.filter { !$0.done }.count }
}

struct JobCloseoutView: View {
    @Environment(\.dynamicTypeSize) private var closeoutTypeSize
    let jobID: String
    /// The job's street when the opener already knows it (street first, the ID after it).
    var place: String? = nil
    /// Paper 21K / 21T "Cancel job": opened from the job's menu, the cancel confirm shows as soon
    /// as the job has loaded and the server still allows it.
    var startsCancel = false
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var session: SessionController
    @EnvironmentObject var store: Store
    @EnvironmentObject var outbox: FieldOutbox
    @EnvironmentObject var pendingMedia: PendingMediaStore
    @State private var askedCancel = false
    @State private var closeout: FieldCloseout?
    @State private var job: JobRecord?
    @State private var error: String?
    @State private var busy = false
    @State private var confirmComplete = false
    @State private var completed = 0
    @State private var confirmCancel = false
    @State private var invoiceID: String?
    @State private var openInvoiceID: String?
    @State private var savedWorkScope: SavedWorkScope?
    @State private var openBilling = false
    @State private var unpaidReasonCode = "customer_will_pay_later"
    @State private var unpaidReason = ""
    @State private var unpaidNextAction = ""
    /// Said above Complete job when it is pressed with the closeout not yet satisfied.
    @State private var completeProblem: String?
    /// The job's bill for Paper F5's Summary, sign-off and Collect (`loadBill`). Nil when this role
    /// can't see invoices or the job has none this phone has read.
    @State private var bill: InvoiceRecord?
    /// Paper F5 (field mode): a job under way wraps up under the visit's five steps, with the
    /// job in the bar. A finished job, and accessibility sizes, keep Paper 83's titled page.
    private var fieldMode: Bool {
        // The saved copy stands in until the job has loaded, so the page opens in its own shape.
        guard let job = job ?? JobDetailCache.job(jobID) else { return false }
        return job.status == "in_progress" && !isCompleted && !closeoutTypeSize.isAccessibilitySize
    }
    private var mayRecordUnpaidDisposition: Bool {
        // Notes, photos and checks waiting on this phone already count; only the unpaid balance is left.
        guard let closeout, !remainingUnmet.isEmpty, session.can("job.edit", feature: "jobs") else { return false }
        return remainingUnmet.allSatisfy { $0.kind == "payment_or_unpaid_disposition" } && closeout.policy.requiredChecks.contains { $0.kind == "payment_or_unpaid_disposition" && $0.allowUnpaidDisposition == true }
    }
    /// What the server still lists as missing, minus what is waiting on this phone (OF-02).
    private var remainingUnmet: [FieldCloseoutRequirement] {
        closeout?.unmet.filter { !waitingSatisfies($0) } ?? []
    }
    private var validDisposition: Bool {
        mayRecordUnpaidDisposition && !unpaidReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !unpaidNextAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && unpaidReason.utf16.count <= 2000 && unpaidNextAction.utf16.count <= 2000
    }
    /// OF-02: a completion saved on this phone shows as done-and-waiting, never as synced.
    private var completionWaiting: Bool { outbox.pendingStatus(for: jobID) == "completed" }
    private var isCompleted: Bool { job?.status == "completed" || completionWaiting }
    /// The status this phone expects, and what the server last allowed from it.
    private var allowsComplete: Bool {
        guard let job else { return false }
        if let queued = outbox.pendingStatus(for: jobID) { return outbox.offlineSteps(from: queued).contains("completed") }
        return job.allowedTransitions?.contains("completed") == true
    }
    /// Work saved on this phone that will satisfy a blocked requirement once it lands (OF-01).
    private func waitingSatisfies(_ requirement: FieldCloseoutRequirement) -> Bool {
        guard requirement.outcome == "blocked", let closeout else { return false }
        switch requirement.kind {
        case "notes": return outbox.pendingNotes(for: jobID).contains { $0.state == .pending }
        case "photos":
            return closeout.facts.photoCount + waitingPhotos >= closeout.policy.requiredPhotoCount
        case "check": return outbox.waitingChecks(jobID: jobID).contains(String(requirement.requirement.dropFirst("check:".count)))
        case "payment_or_unpaid_disposition":
            return waitingPaymentsCoverBalance
        default: return false
        }
    }
    /// Photos of this job still on this phone (`PendingMediaStore`).
    private var waitingPhotos: Int { pendingMedia.items.filter { $0.jobID == jobID && $0.kind == "photo" }.count }
    private var unassociatedPendingPayments: [OutboxEntry.PaymentPayload] {
        outbox.pending.compactMap { entry in
            guard case .payment(let payment) = entry.action, payment.jobId == nil else { return nil }
            return payment
        }
    }
    private var canRefreshRecordedPayments: Bool {
        session.can("invoice.view", feature: "invoicing") && session.can("invoice.view", feature: "payments")
    }
    private var unassociatedRecordedPayments: [OutboxEntry.PaymentPayload] {
        outbox.recordedPayments.filter { $0.jobId == nil }
    }
    private var recordedInvoiceIDsToRefresh: [String] {
        Array(Set(outbox.recordedPayments.filter { $0.jobId == nil || $0.jobId == jobID }.map(\.invoiceId))).sorted()
    }

    /// Cash and check waiting on this phone cover every unpaid balance on the job's invoices as
    /// last seen. A partial payment leaves the requirement (and the unpaid disposition) showing.
    private var waitingPaymentsCoverBalance: Bool {
        // Include the job's invoice list and invoices with payments on this phone. Independent
        // cached copies have no proven ordering, so disagreements leave coverage unknown.
        guard let job, let organizationID = session.activeOrganization?.id, let actorID = session.user?.id,
              job.id == jobID, job.organizationId == organizationID else { return false }
        let unassociated = outbox.pending.compactMap { entry -> OutboxEntry.PaymentPayload? in
            if case .payment(let payload) = entry.action { return payload }
            return nil
        } + outbox.recordedPayments
        let listed = JobDetailCache.invoices(jobID)
        guard !CloseoutInvoiceEvidence.hasUnassociatedPayments(unassociated.map(\.jobId)) else { return false }
        let paidHere = (outbox.pending.compactMap { entry -> String? in
            if case .payment(let payment) = entry.action, payment.jobId == jobID { payment.invoiceId } else { nil }
        } + outbox.recordedPayments.filter { $0.jobId == jobID }.map(\.invoiceId))
        guard let invoices = CloseoutInvoiceEvidence.resolve(
            listed: listed, paidHere: paidHere, id: { $0.id }, cached: JobDetailCache.invoice,
            equivalent: { $0 == $1 }, valid: { $0.jobId == jobID && $0.organizationId == organizationID && $0.customerId == job.customerId }
        ) else { return false }
        var owing: [(String, Int)] = []
        for invoice in invoices where invoice.status == "issued" {
            guard invoice.currency == "USD",
                  let amounts = CustomerDocumentAmounts(lines: invoice.lines, currency: invoice.currency,
                                                        amountPaid: invoice.amountPaid) else { return false }
            if amounts.due > 0 { owing.append((invoice.id, amounts.due)) }
        }
        return !owing.isEmpty && owing.allSatisfy { id, due in
            let payments = outbox.pending.compactMap { entry -> CloseoutInvoiceEvidence.PendingPayment? in
                guard case .payment(let payload) = entry.action, payload.invoiceId == id else { return nil }
                return .init(actorID: entry.actorId, organizationID: entry.organizationId, jobID: payload.jobId,
                             invoiceID: payload.invoiceId, method: payload.method, amount: payload.amountCents)
            }
            guard let pending = CloseoutInvoiceEvidence.pendingAmounts(payments, actorID: actorID,
                organizationID: organizationID, jobID: jobID, invoiceID: id) else { return false }
            return CloseoutInvoiceEvidence.covers(due: due, pending: pending,
                recorded: outbox.recordedPayments.filter { $0.invoiceId == id }.map(\.amountCents))
        }
    }
    private var canComplete: Bool {
        guard let closeout else { return false }
        let ready = closeout.completable || remainingUnmet.isEmpty
        return session.can("job.complete", feature: "jobs") && allowsComplete && (ready || validDisposition)
    }

    /// Paper 83: a short checklist, then one commit.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if fieldMode {
                    // Paper F5: the visit's steps lead, "Wrap up" the current one; the job is in the bar.
                    JobFieldSteps(current: 3)
                        .padding(.top, 8).padding(.bottom, 22)
                } else {
                // Paper 83: the 34 Bold title, then "JOB-2214 · Marlowe residence" in 15 muted.
                VStack(alignment: .leading, spacing: 2) {
                    Text(isCompleted ? "Job complete" : "Wrap up this job")
                        .font(Theme.font(34, weight: .bold)).tracking(-0.85)
                        .lineLimit(2).minimumScaleFactor(0.7)
                        .accessibilityAddTraits(.isHeader)
                    Text(closeoutSubtitle).font(Theme.font(15)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if completionWaiting { WaitingToSyncLabel().padding(.top, 4) }
                }
                .padding(.horizontal, 4)
                .padding(.top, 14).padding(.bottom, 22)
                }
                if let error { ErrorBanner(message: error, retry: closeout == nil ? { await load() } : nil).padding(.horizontal, -PaperCardMetrics.margin) }
                if let closeout {
                    let checks = CloseoutChecklist.acknowledgementChecks(closeout)
                    let waitingChecks = outbox.waitingChecks(jobID: jobID)
                    // Work saved on this phone counts toward the checklist (OF-01), shown as waiting.
                    let progress = (done: closeout.requirements.filter { $0.outcome != "blocked" || waitingSatisfies($0) }.count
                                        + checks.filter { closeout.facts.acknowledgedCheckKeys.contains($0.key) || waitingChecks.contains($0.key) }.count,
                                    total: closeout.requirements.count + checks.count)
                    // Paper 83: "Before you close" with "3 of 4" at the trailing edge, over one card.
                    if !closeout.requirements.isEmpty || !checks.isEmpty {
                    PaperSection(title: checklistTitle) { VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(closeout.requirements.enumerated()), id: \.offset) { offset, requirement in
                        let step = CloseoutNextStep(requirement)
                        if offset > 0 { WellDivider(leading: PaperCardMetrics.inset + markWidth) }
                        let waiting = waitingSatisfies(requirement)
                        let canRecover = !waiting && !session.isOffline && step?.buttonTitle != nil
                            && (step?.capabilities.allSatisfy({ session.can($0, feature: "invoicing") }) ?? false)
                        checklistLayout {
                            // The action stands in for "To do": one control at the edge, not a word and a button.
                            checklistRow(done: requirement.outcome != "blocked" || waiting, title: requirement.detail,
                                         detail: waiting ? "Waiting to sync" : step?.detail, showsStatus: !canRecover)
                            if canRecover, let step, let title = step.buttonTitle {
                                Button { Task { await recover(step) } } label: { actionPill(title) }
                                    .buttonStyle(PressStyle())
                                    .disabled(busy)
                            }
                        }
                        .padding(.horizontal, PaperCardMetrics.inset)
                    }
                    ForEach(checks, id: \.key) { check in
                        let waiting = waitingChecks.contains(check.key)
                        if check.key != checks.first?.key || !closeout.requirements.isEmpty { WellDivider(leading: PaperCardMetrics.inset + markWidth) }
                        let acknowledged = closeout.facts.acknowledgedCheckKeys.contains(check.key) || waiting
                        let canConfirm = !acknowledged && !isCompleted && session.can("job.edit", feature: "jobs")
                        checklistLayout {
                            checklistRow(done: acknowledged, title: check.label, detail: waiting ? "Waiting to sync" : nil,
                                         showsStatus: !canConfirm)
                            if canConfirm {
                                Button { Task { await acknowledge(check.key) } } label: { actionPill("Confirm") }
                                    .buttonStyle(PressStyle())
                                    .disabled(busy)
                                    .accessibilityHint(check.label)
                            }
                        }
                        .padding(.horizontal, PaperCardMetrics.inset)
                    }
                    } } accessory: {
                        // Paper F5 counts what is left ("3 left"); Paper 83, what is done ("3 of 4").
                        Text(checklistCount(done: progress.done, total: progress.total))
                            .font(Theme.font(13, weight: fieldMode ? .semibold : .regular)).monospacedDigit()
                            .foregroundStyle(Theme.muted)
                    }
                    }
                    if closeout.requirements.isEmpty && checks.isEmpty {
                        PaperSection(checklistTitle) {
                            Text("Nothing else is required before closing.").font(Theme.font(15)).foregroundStyle(Theme.muted)
                                .padding(.horizontal, PaperCardMetrics.inset).frame(minHeight: 56)
                        }
                    }
                    if fieldMode {
                        // Paper F5: what the visit came to, then where the customer signs.
                        summarySection(closeout).padding(.top, 16)
                        signOffSection.padding(.top, 16)
                    }
                    if closeout.unmet.contains(where: { $0.kind == "payment_or_unpaid_disposition" && $0.outcome == "blocked" }),
                       !unassociatedPendingPayments.isEmpty || !recordedInvoiceIDsToRefresh.isEmpty {
                        PaperGroupHeader(title: "Payments to check").padding(.top, 22).padding(.horizontal, 4)
                        if !unassociatedPendingPayments.isEmpty || !unassociatedRecordedPayments.isEmpty {
                            Text("Some payments on this phone aren't linked to a job, so they can't confirm this checklist yet.")
                                .font(Theme.font(15)).foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !unassociatedPendingPayments.isEmpty {
                            Text(session.can("job.edit", feature: "jobs") && session.can("invoice.payment.create", feature: "payments")
                                 ? "Connect and sync saved work to send waiting payments."
                                 : "Ask your office to restore your access to sync payments on this phone.")
                                .font(Theme.font(13)).foregroundStyle(Theme.muted).padding(.top, 8)
                            if SavedWorkScope.capture(session: session, api: api, media: pendingMedia, outbox: outbox) != nil {
                                Button("Review saved work") {
                                    savedWorkScope = SavedWorkScope.capture(session: session, api: api, media: pendingMedia, outbox: outbox)
                                }.frame(minHeight: 44).buttonStyle(PressStyle())
                            }
                        }
                        if !recordedInvoiceIDsToRefresh.isEmpty {
                            if canRefreshRecordedPayments {
                                Text("Sent payments may still be updating. Connect, then search these invoice IDs in Invoices on this phone to refresh them.")
                                    .font(Theme.font(13)).foregroundStyle(Theme.muted).padding(.top, 8)
                                ForEach(recordedInvoiceIDsToRefresh, id: \.self) { id in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Invoice \(id.suffix(4).uppercased())").font(Theme.font(15, weight: .medium))
                                        Text(id).font(Theme.monoFont(12)).textSelection(.enabled)
                                    }.frame(minHeight: 44, alignment: .leading)
                                }
                            } else {
                                Text("Ask your office to enable your invoice and payment access, then refresh those invoices on this phone.")
                                    .font(Theme.font(13)).foregroundStyle(Theme.muted).padding(.top, 8)
                            }
                        }
                    }
                    if mayRecordUnpaidDisposition && !isCompleted {
                        // Paper 83A "Balance still due": the amount large and centred over the
                        // invoice it belongs to, as this phone last read it.
                        if let balance = unpaidBalance {
                            VStack(spacing: 4) {
                                Text("Balance still due").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                                Text(balance.amount).font(Theme.font(34, weight: .bold)).tracking(-0.85).monospacedDigit()
                                    .lineLimit(1).minimumScaleFactor(0.6)
                                Text(balance.reference).font(Theme.font(15)).foregroundStyle(Theme.muted)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 22)
                            .accessibilityElement(children: .combine)
                        }
                        // Paper 83A: the reasons as one radio card under the question.
                        PaperSection("Why are you leaving without payment?") {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(unpaidReasonOptions, id: \.code) { option in
                                    if option.code != unpaidReasonOptions.first?.code { WellDivider(leading: PaperCardMetrics.inset + 36) }
                                    UnpaidReasonRow(title: option.title, selected: unpaidReasonCode == option.code) {
                                        unpaidReasonCode = option.code
                                    }
                                }
                            }
                        }
                        .padding(.top, 22)
                        wellField("Explain the unpaid balance", text: $unpaidReason).padding(.top, 16)
                        wellField("Office follow-up action", text: $unpaidNextAction).padding(.top, 8)
                        Text("Completing with this leaves payment outstanding and creates an office follow-up.")
                            .font(Theme.font(13)).foregroundStyle(Theme.muted).padding(.top, 8).padding(.horizontal, 4)
                    }
                    if job?.status == "completed" && !session.isOffline {
                        PaperSection("Billing") {
                            if session.can("invoice.create", feature: "invoicing") {
                                Button { Task { await completionInvoice() } } label: {
                                    PaperMenuRow("Open completion invoice", symbol: "doc.plaintext", filled: true)
                                }.buttonStyle(RowPressStyle()).disabled(busy)
                            }
                            if let invoiceID, session.can("invoice.view", feature: "invoicing") {
                                if session.can("invoice.create", feature: "invoicing") { WellDivider(leading: PaperCardMetrics.inset + 36) }
                                NavigationLink { InvoiceDetailView(id: invoiceID).thorbisBackButton() } label: {
                                    PaperMenuRow("View invoice", symbol: "doc.text", filled: true)
                                }
                                .buttonStyle(RowPressStyle())
                            }
                        }
                        .padding(.top, 22)
                    }
                    // OF-09: cancelling races with dispatch, so it needs signal and says so by not offering it.
                    // Paper F8 / 21U: Cancel job as a red row with its mark on its own card.
                    if !session.isOffline, !isCompleted, session.can("job.cancel", feature: "jobs"), job?.allowedTransitions?.contains("canceled") == true {
                        PaperCard {
                            Button { confirmCancel = true } label: {
                                PaperMenuRow(title: "Cancel job", symbol: "xmark.circle", tint: Theme.destructive, filled: true) { EmptyView() }
                            }
                            .buttonStyle(RowPressStyle())
                            .disabled(busy)
                        }
                        .padding(.top, 22)
                    }
                } else if error == nil {
                    SkeletonRows(count: 4, leading: false, inset: 0)
                }
            }
            // Paper v2: cards 16 from the edges, titles and labels 20 (4 more inside).
            .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 4).padding(.bottom, 24)
        }
        .foregroundStyle(Theme.foreground)
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if !isCompleted, session.can("job.complete", feature: "jobs"), allowsComplete {
                // Not pre-disabled while the closeout is unfinished: pressing says what's left. It is
                // off only until the closeout has loaded.
                VStack(alignment: .leading, spacing: 0) {
                    if let completeProblem, !canComplete {
                        FieldProblem(message: completeProblem)
                            .padding(.horizontal, Theme.gutter).padding(.top, 8)
                    }
                    if fieldMode {
                        fieldBar
                    } else {
                        PaperActionBar(title: "Complete job", symbol: "checkmark", busy: busy, disabled: closeout == nil) {
                            pressComplete()
                        }
                    }
                }
                .background(Theme.background)
            }
        }
        .toolbar { fieldToolbar }
        .task {
            await load()
            // Asked for from the job's menu: the same guard as the Cancel job row below.
            if startsCancel, !askedCancel, !session.isOffline, !isCompleted, session.can("job.cancel", feature: "jobs"),
               job?.allowedTransitions?.contains("canceled") == true {
                askedCancel = true
                confirmCancel = true
            }
        }
        .refreshable { await load() }
        // Queued confirmations landed: show the server's checklist instead of the waiting marks.
        .onChange(of: outbox.syncGeneration) { _, _ in Task { await load() } }
        // Collecting from the checklist comes back here once it's paid, ready to complete.
        .thorbisDestination(item: $openInvoiceID) { InvoiceDetailView(id: $0, returnsWhenPaid: true).onDisappear { Task { await load() } } }
        .thorbisDestination(isPresented: $openBilling) { BillingSchedulesView() }
        .sheet(item: $savedWorkScope) { value in SheetSurface { SavedWorkReviewView(scope: value) } }
        .onChange(of: savedWorkScope?.isCurrent(session: session, api: api, media: pendingMedia, outbox: outbox) ?? true) { _, valid in
            if !valid { savedWorkScope = nil }
        }
        .sensoryFeedback(.success, trigger: completed)
        .thorbisConfirm("Complete this job?", isPresented: $confirmComplete,
                        actions: [ThorbisConfirmAction("Complete job") { Task { await complete() } }])
        // Paper 21U: the sheet is named "Cancel job", with the job under it ("JOB-2214 · AC not cooling").
        .thorbisConfirm("Cancel job", message: job.map { "JOB-\($0.id.suffix(4).uppercased()) \u{00B7} \($0.title)" },
                        isPresented: $confirmCancel,
                        actions: [ThorbisConfirmAction("Cancel job", role: .destructive) { Task { await cancel() } }])
    }
    /// Item and action side by side; at accessibility sizes the action goes under the words, whole.
    private var checklistLayout: AnyLayout {
        closeoutTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                                              : AnyLayout(HStackLayout(spacing: 12))
    }

    /// Paper 83 subtitle: "JOB-2214 · Marlowe residence" (the street first when the opener knows it).
    private var closeoutSubtitle: String {
        let reference = "JOB-\(jobID.suffix(4).uppercased())"
        let customer = job.map { store.customerName($0.customerId) }
        if let place { return [place, customer, reference].compactMap { $0 }.joined(separator: " · ") }
        return [reference, customer].compactMap { $0 }.joined(separator: " · ")
    }

    /// Paper 83A's heading: what is still owed on the job's invoice ("$340.00") and which invoice
    /// ("INV-2209 · Marlowe residence"), from the copy this phone last read. Nil when unknown.
    private var unpaidBalance: (amount: String, reference: String)? {
        guard let invoices = JobDetailCache.invoices(jobID),
              let invoice = WrapUpList.billingInvoice(invoices),
              invoice.status == "issued",
              let due = TechJobFlow.due(invoice), due > 0 else { return nil }
        let number = "INV-\(invoice.id.suffix(4).uppercased())"
        let customer = job.map { store.customerName($0.customerId) }
        return (amount: jobShortMoney(due, currency: invoice.currency),
                reference: [number, customer].compactMap { $0 }.joined(separator: " · "))
    }

    /// The server's unpaid reason codes, in the order the policy lists them.
    private var unpaidReasonOptions: [UnpaidReasonOption] {
        [UnpaidReasonOption(code: "customer_will_pay_later", title: "Customer will pay later"),
         UnpaidReasonOption(code: "office_collection_required", title: "Office collection required"),
         UnpaidReasonOption(code: "payment_attempt_failed", title: "Payment attempt failed"),
         UnpaidReasonOption(code: "other", title: "Other")]
    }

    /// A checklist item's own action: Paper's brand chip ("Now") with a 44pt target. Paper F5
    /// draws it as a 48pt pill at 16 Semibold ("Add photo").
    private func actionPill(_ title: String) -> some View {
        Text(title).font(Theme.font(fieldMode ? 16 : 13, weight: .semibold)).foregroundStyle(Theme.brandText)
            .fixedSize()
            .padding(.horizontal, fieldMode ? 16 : 10).frame(minHeight: fieldMode ? 48 : 26)
            .background(Theme.brandSurface, in: Capsule())
            .frame(minHeight: 44).contentShape(Rectangle())
    }

    /// Paper F5: the job in the bar, centred: its title at 17 Semibold over
    /// "Danielle Marlowe · JOB-2214" at 13 muted. Paper 83's page keeps its own 34 Bold title.
    @ToolbarContentBuilder private var fieldToolbar: some ToolbarContent {
        if fieldMode {
            ThorbisToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(fieldTitle)
                        .font(Theme.font(17, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .accessibilityAddTraits(.isHeader)
                    Text(fieldSubtitle)
                        .font(Theme.font(13)).monospacedDigit()
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
        }
    }

    /// Paper F5 "Finish checklist"; Paper 83 "Before you close".
    private var checklistTitle: String { fieldMode ? "Finish checklist" : "Before you close" }

    /// Paper F5 counts what is left ("3 left"); Paper 83, what is done ("3 of 4").
    private func checklistCount(done: Int, total: Int) -> String {
        guard fieldMode else { return "\(done) of \(total)" }
        let left = max(0, total - done)
        return left > 0 ? "\(left) left" : "All done"
    }

    /// The checklist mark's column: Paper F5's 32pt ring and 12 after it; Paper 83's 20pt mark.
    private var markWidth: CGFloat { fieldMode ? 44 : 34 }

    /// Paper F5's bar title: the job's problem, else its street.
    private var fieldTitle: String {
        let title = (job ?? JobDetailCache.job(jobID))?.title ?? ""
        return title.isEmpty ? (place ?? "Wrap up") : title
    }

    /// Paper F5's second bar line: "Danielle Marlowe · JOB-2214".
    private var fieldSubtitle: String {
        let reference = "JOB-\(jobID.suffix(4).uppercased())"
        guard let job else { return reference }
        let customer = store.customerName(job.customerId)
        return customer == "Customer" ? reference : "\(customer) \u{00B7} \(reference)"
    }

    /// Who signs, as Paper F5 writes it ("Danielle Marlowe signs here"); "Customer" until the name is known.
    private var signerName: String {
        job.map { store.customerName($0.customerId) } ?? "Customer"
    }

    /// Complete job, as the bar presses it: confirm when the closeout allows it, else say what is left.
    private func pressComplete() {
        if canComplete {
            completeProblem = nil
            confirmComplete = true
        } else {
            completeProblem = mayRecordUnpaidDisposition
                ? "Explain the unpaid balance and the office follow-up to complete this job."
                : "Finish the open items above to complete this job."
        }
    }

    /// Paper F5 "Collect $340.00": what the job's bill still owes, when this role can take the
    /// payment here and there is signal. Nil otherwise, and the bar is Complete job alone.
    private var collectTitle: String? {
        guard !session.isOffline, session.can("invoice.view", feature: "invoicing"),
              session.can("invoice.payment.create", feature: "payments"),
              let bill, bill.status == "issued", let due = TechJobFlow.due(bill), due > 0 else { return nil }
        return "Collect \(money(due, currency: bill.currency))"
    }

    /// Paper F5's bar: a quiet 52pt pill over the 60pt commit. With a balance to take, the commit
    /// collects it (the invoice opens, and comes back here once paid) and Complete job is the pill
    /// above. Paper words that pill "Send invoice instead"; leaving unpaid here is Complete job
    /// with the server's unpaid reason, so it keeps its own words.
    private var fieldBar: some View {
        VStack(spacing: 10) {
            if let collect = collectTitle, let bill {
                Button { pressComplete() } label: {
                    Text("Complete job")
                        .font(Theme.font(17, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Theme.fill, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .disabled(busy || closeout == nil)
                .accessibilityIdentifier("closeout-complete")
                Button { openInvoiceID = bill.id } label: {
                    Text(collect)
                        .font(Theme.font(18, weight: .semibold)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .inkCommit(height: 60)
                }
                .buttonStyle(PressStyle())
                .disabled(busy)
                .accessibilityHint("Opens the invoice to take the payment")
                .accessibilityIdentifier("closeout-collect")
            } else {
                Button { pressComplete() } label: {
                    HStack(spacing: 10) {
                        if busy { ProgressView().tint(.white) }
                        Text("Complete job")
                            .font(Theme.font(18, weight: .semibold))
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .inkCommit(height: 60)
                }
                .buttonStyle(PressStyle())
                .disabled(busy || closeout == nil)
                .accessibilityIdentifier("closeout-complete")
            }
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
    }

    /// Paper F5 "Summary": what the visit came to, in rows of a muted label and a 17 Semibold
    /// value. Parts and labor is the bill's total as this phone last read it; time on site runs
    /// from the arrival tap; photos count those still waiting on this phone. A fact the app
    /// doesn't have leaves its row out.
    private func summarySection(_ closeout: FieldCloseout) -> some View {
        PaperSection("Summary") {
            TimelineView(.everyMinute) { context in
                let lines = summaryLines(closeout, now: context.date)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(lines) { line in
                        if line.id != lines.first?.id { WellDivider(leading: PaperCardMetrics.inset) }
                        HStack(alignment: .center, spacing: 12) {
                            Text(line.id).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(line.value).font(Theme.font(17, weight: .semibold)).monospacedDigit()
                                .foregroundStyle(Theme.foreground)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func summaryLines(_ closeout: FieldCloseout, now: Date) -> [CloseoutSummaryLine] {
        var lines: [CloseoutSummaryLine] = []
        if let bill, let total = paperLinesTotal(bill.lines) {
            lines.append(CloseoutSummaryLine(id: "Parts and labor", value: money(total, currency: bill.currency)))
        }
        if let arrived = JobFiltering.date(job?.arrivedAt) {
            lines.append(CloseoutSummaryLine(id: "Time on site", value: JobOnSiteClock.short(arrived: arrived, now: now)))
        }
        lines.append(CloseoutSummaryLine(id: "Photos", value: "\(closeout.facts.photoCount + waitingPhotos)"))
        return lines
    }

    /// Paper F5 "Customer sign-off": a dashed box that says who signs. The signature is taken on
    /// the invoice (it holds the lines the customer agrees to), so the box opens it; once the
    /// bill's current lines are signed it says so. Shown when this role can see the job's bill.
    @ViewBuilder private var signOffSection: some View {
        if session.can("invoice.view", feature: "invoicing"), let bill {
            let signed = bill.customerAuthorization?.linesRevision == bill.linesRevision
            PaperSection("Customer sign-off") {
                Button { openInvoiceID = bill.id } label: {
                    VStack(spacing: 6) {
                        Image(systemName: signed ? "checkmark.circle" : "signature")
                            .font(.system(size: 24, weight: .regular))
                            .foregroundStyle(signed ? Theme.success : Theme.muted)
                            .frame(height: 28)
                            .accessibilityHidden(true)
                        Text(signed ? "\(signerName) signed" : "\(signerName) signs here")
                            .font(Theme.font(17, weight: .medium))
                            .foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.muted, style: StrokeStyle(lineWidth: 1.5, dash: signed ? [] : [5, 4])))
                    .padding(12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .disabled(busy)
                .accessibilityHint(signed ? "Opens the signed invoice" : "Opens the invoice to sign")
                .accessibilityIdentifier("closeout-sign-off")
            }
        }
    }

    private func checklistRow(done: Bool, title: String, detail: String?, showsStatus: Bool = true) -> some View {
        // Paper 83: a filled green tick when done, a brand ring when open; the title 16 Medium,
        // a short detail on the right. At accessibility sizes the detail sits under the title.
        let row = closeoutTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                                               : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        // Paper F5 (field mode): a 32pt ring, the title at 17 Medium, rows 64 tall.
        return HStack(alignment: .center, spacing: 0) {
            CloseoutMark(done: done, field: fieldMode)
                .frame(width: markWidth, alignment: .leading)
            row {
                Text(title).font(fieldMode ? Theme.font(17, weight: .medium) : Theme.font(16, weight: done ? .medium : .semibold))
                    .tracking(fieldMode ? 0 : -0.16)
                    .foregroundStyle(done ? Theme.subtle : Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let detail {
                    Text(detail).font(Theme.font(14)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: fieldMode ? 64 : 56, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title, detail].compactMap { $0 }.joined(separator: ", "))
        .accessibilityValue(done ? "Done" : "To do")
    }

    private func wellField(_ prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text, prompt: .placeholder(prompt), axis: .vertical)
            .font(Theme.font(16)).lineLimit(2...5)
            .padding(12)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).stroke(Theme.border))
    }

    private func load() async {
        do {
            let loadedJob = try await api.fieldJob(jobID)
            let loadedCloseout = try await api.fieldCloseout(jobID)
            job = loadedJob
            closeout = loadedCloseout
            outbox.learn(loadedJob)
            JobDetailCache.save(loadedJob)
            JobDetailCache.save(closeout: loadedCloseout, jobID: jobID)
            error = nil
            await loadBill()
        } catch is CancellationError {} catch {
            if error.isConnectivityFailure {
                // OF-04: the last copy of this checklist, so it can still be worked without signal.
                job = job ?? JobDetailCache.job(jobID)
                closeout = closeout ?? JobDetailCache.closeout(jobID)
                if job != nil, closeout != nil { self.error = nil; return }
                self.error = "This checklist hasn't been opened with signal on this phone yet. Open it again when you're back online."
                return
            }
            self.error = error.localizedDescription
        }
    }
    /// The job's bill for Paper F5's Summary, sign-off and Collect: the completion invoice (else the
    /// first live one) from the copy this phone last read on the job, read again by its id when
    /// there is signal. Quiet: a failed read keeps the saved copy; no access shows no bill.
    private func loadBill() async {
        guard session.can("invoice.view", feature: "invoicing"),
              let cached = JobDetailCache.invoices(jobID).flatMap({ WrapUpList.billingInvoice($0) }),
              cached.jobId == jobID, cached.organizationId == session.activeOrganization?.id else {
            bill = nil
            return
        }
        bill = cached
        guard !session.isOffline, let fresh = try? await api.fieldInvoice(cached.id),
              fresh.id == cached.id, fresh.jobId == jobID else { return }
        bill = fresh
    }

    /// Saves to the phone first when there is no signal, or when the request finds none (OF-01).
    private func queueOffline(_ action: OutboxEntry.Action, label: String? = nil) {
        outbox.enqueue(action, policyVersion: session.policyVersion ?? 0, label: label)
        error = nil
    }
    private func acknowledge(_ key: String) async {
        let label = closeout?.policy.requiredChecks.first { $0.key == key }?.label
        if session.isOffline || !outbox.pending.filter({ $0.jobID == jobID }).isEmpty {
            queueOffline(.acknowledgeCheck(.init(jobId: jobID, checkKey: key)), label: label)
            if !session.isOffline { Task { await outbox.drain(api: api, useCommandEndpoint: session.isFeatureOn("offline_sync")) } }
            return
        }
        busy = true
        defer { busy = false }
        do { _ = try await api.acknowledgeFieldCheck(jobID, checkKey: key); await load() }
        catch is CancellationError {} catch {
            if error.isConnectivityFailure { queueOffline(.acknowledgeCheck(.init(jobId: jobID, checkKey: key)), label: label) }
            else { self.error = error.localizedDescription }
        }
    }
    private func complete() async {
        let reason = unpaidReason.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = unpaidNextAction.trimmingCharacters(in: .whitespacesAndNewlines)
        let disposition: FieldUnpaidDisposition? = validDisposition ? .init(reasonCode: unpaidReasonCode, reason: reason, followUpNextAction: next) : nil
        let queued = OutboxEntry.Action.complete(.init(jobId: jobID, unpaidDisposition: validDisposition
            ? .init(reasonCode: unpaidReasonCode, reason: reason, followUpNextAction: next) : nil))
        // Anything already waiting for this job, photos included, lands first, so the completion
        // queues behind it and the outbox holds it until those uploads finish.
        if session.isOffline || !outbox.pending.filter({ $0.jobID == jobID }).isEmpty
            || pendingMedia.items.contains(where: { $0.jobID == jobID }) {
            queueOffline(queued)
            completed += 1
            if !session.isOffline {
                Task {
                    // Photos first, as on reconnect: the completion is held until this job's are sent.
                    await pendingMedia.drain(api: api, jobID: jobID, canUpload: { session.can("job.edit", feature: "jobs") })
                    outbox.notePendingMedia(pendingMedia.items)
                    await outbox.drain(api: api, useCommandEndpoint: session.isFeatureOn("offline_sync"))
                }
            }
            return
        }
        busy = true
        defer { busy = false }
        do {
            job = try await api.completeFieldJob(jobID, request: .init(unpaidDisposition: disposition))
            completed += 1
            await load()
            await store.refresh(api)
        }
        catch is CancellationError {} catch {
            if error.isConnectivityFailure { queueOffline(queued); completed += 1 }
            else { self.error = error.localizedDescription }
        }
    }
    private func cancel() async {
        busy = true
        defer { busy = false }
        do { job = try await api.cancelFieldJob(jobID); await load(); await store.refresh(api) }
        catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    /// Recovery from the checklist itself, so the tech never has to hunt for the invoice.
    private func recover(_ step: CloseoutNextStep) async {
        switch step {
        case .openBilling: openBilling = true
        case .createInvoice, .collectPayment, .recordUnpaid:
            busy = true
            defer { busy = false }
            do {
                // Idempotent: returns the job's existing completion invoice when there is one.
                let invoice = try await api.ensureFieldCompletionInvoice(jobID)
                invoiceID = invoice.id
                error = nil
                if step != .createInvoice { openInvoiceID = invoice.id }
                await load()
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        case .hint: break
        }
    }

    private func completionInvoice() async {
        busy = true
        defer { busy = false }
        do { let invoice = try await api.ensureFieldCompletionInvoice(jobID); invoiceID = invoice.id; error = nil }
        catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}

/// One row of Paper F5's Summary: its label (also its identity) and its value.
private struct CloseoutSummaryLine: Identifiable {
    let id: String
    let value: String
}

/// Paper 83's checklist mark: a filled green circle with a white tick, or an open brand ring.
/// Paper F5 (field mode) draws it at 32pt, the open ring in the quiet grey.
private struct CloseoutMark: View {
    let done: Bool
    var field = false

    var body: some View {
        Group {
            if done {
                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.white, Theme.statusDone)
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(field ? Theme.muted : Theme.brand)
            }
        }
        .font(.system(size: field ? 30 : 20, weight: field ? .light : .regular))
        .accessibilityHidden(true)
    }
}

/// Paper 53B's day tile: weekday over the date, 62 tall, radius 14; brand when chosen.
private struct ScheduleDayTile: View {
    let weekday: String
    /// Nil draws the calendar glyph (any other date).
    let number: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(weekday).font(Theme.font(12, weight: .medium))
                    .foregroundStyle(selected ? Color.white : Theme.muted)
                    .lineLimit(1).minimumScaleFactor(0.7)
                if let number {
                    Text(number).font(Theme.font(17, weight: selected ? .bold : .semibold)).monospacedDigit()
                        .foregroundStyle(selected ? Color.white : Theme.foreground)
                } else {
                    Image(systemName: "calendar").font(.system(size: 16, weight: .medium))
                        .foregroundStyle(selected ? Color.white : Theme.foreground)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(selected ? Theme.brand : Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct UnpaidReasonOption {
    let code: String
    let title: String
}

/// Paper 83A: one reason on the radio card, a 22pt ring that fills brand when chosen.
private struct UnpaidReasonRow: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().strokeBorder(selected ? Theme.brand : Theme.foreground.opacity(0.4), lineWidth: selected ? 2 : 1.5)
                        .frame(width: 22, height: 22)
                    if selected { Circle().fill(Theme.brand).frame(width: 10, height: 10) }
                }
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
                Text(title).font(Theme.font(16, weight: .medium)).tracking(-0.16)
                    .foregroundStyle(Theme.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 15)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// "Schedule" on a list row that has no time yet: one tap to the schedule sheet instead of
/// row → job → ••• → Schedule. Only for people who may schedule (`job.assign`).
struct ScheduleRowButton: View {
    let job: Job
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Schedule", systemImage: "calendar.badge.plus")
                .font(Theme.font(13, weight: .medium))
                .foregroundStyle(Theme.foreground)
                .padding(.horizontal, 12)
                .frame(height: Theme.chipHeight + 4)
                .background(Theme.fill, in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Schedule \(job.title)")
        .accessibilityIdentifier("schedule-row-\(job.id)")
    }
}

/// The schedule sheet opened from a list. Rows carry a list item, so the sheet reads the job as
/// the server has it now (its current time is the change's expected prior) before offering times.
struct QuickScheduleSheet: View {
    let jobID: String
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @Environment(\.dismiss) private var dismiss
    @State private var record: JobRecord?
    @State private var error: String?

    var body: some View {
        if let record {
            JobScheduleView(job: record)
        } else {
            VStack(spacing: 12) {
                if let error {
                    ErrorBanner(message: error) { await load() }
                    Button("Close") { dismiss() }
                        .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, minHeight: 44)
                } else {
                    SkeletonRows(count: 3, inset: 0)
                        .accessibilityLabel("Opening the schedule")
                }
            }
            .padding(20)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Theme.surface)
            .thorbisSheetPresentation([.height(560), .large])
            .task { await load() }
        }
    }

    private func load() async {
        let generation = session.generation
        let organizationID = session.activeOrganization?.id
        do {
            let loaded = try await api.fieldJob(jobID)
            guard session.generation == generation, session.activeOrganization?.id == organizationID else { return }
            guard loaded.id == jobID, loaded.organizationId == organizationID else {
                throw Problem(title: "Job could not be verified", status: nil, detail: nil)
            }
            error = nil
            record = loaded
        } catch is CancellationError {
        } catch {
            self.error = "Could not open this job's schedule. \(error.localizedDescription)"
        }
    }
}

/// Apple's Messages sheet with the reschedule text filled in (Paper 53B "Let the customer know").
/// The tech reviews and sends it from their own phone, as Running late does; nothing is stored or
/// claimed as sent by the server. `done` runs when Messages closes, sent or not.
private struct ScheduleTextComposer: UIViewControllerRepresentable {
    let recipient: String
    let message: String
    let done: () -> Void

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
        let done: () -> Void
        init(done: @escaping () -> Void) { self.done = done }
        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            done()
        }
    }
}

struct JobScheduleView: View {
    let job: JobRecord
    var onSaved: (JobRecord) -> Void = { _ in }
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var session: SessionController
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @State private var date: Date
    @State private var busy = false
    @State private var saved = false
    @State private var error: String?
    @State private var showsCalendar = false
    @State private var showsCustomTime = false
    /// Paper 53B "Assigned tech": who has the visit, as this sheet last read it.
    @State private var assignedID: String?
    @State private var roster: [FieldAssignee] = []
    @State private var rosterLoaded = false
    @State private var showAssign = false
    /// Paper 53B "Let the customer know": the customer (for a phone number and a first name), the
    /// switch, and Apple's Messages sheet once the new time is saved.
    @State private var customer: CustomerRecord?
    @State private var notifyCustomer = true
    @State private var composing = false
    /// Paper 53B "Cancel visit".
    @State private var confirmCancel = false
    @Environment(\.dynamicTypeSize) private var typeSize

    private let invalidLocalTimeMessage = "That local time does not exist on this date. Choose another date or time."
    private let timeOptions: [(hour: Int, minute: Int)] = [
        (8, 0), (10, 30), (13, 0), (15, 30)
    ]

    init(job: JobRecord, onSaved: @escaping (JobRecord) -> Void = { _ in }) {
        self.job = job
        self.onSaved = onSaved
        _date = State(initialValue: JobFiltering.date(job.scheduledFor) ?? Date())
        let initialDate = JobFiltering.date(job.scheduledFor) ?? Date()
        _showsCustomTime = State(initialValue: !Self.timeOptionsContain(initialDate))
        _assignedID = State(initialValue: job.assignedToUserId)
    }

    private var canAssign: Bool { session.can("job.assign", feature: "jobs") }

    /// The assigned tech's name: from the roster, or the person holding the phone.
    private var assigneeName: String? {
        guard let assignedID else { return nil }
        if let person = roster.first(where: { $0.userId == assignedID }) { return person.displayName }
        if assignedID == session.user?.id { return session.user?.name }
        return nil
    }

    private var assigneeWords: String {
        if assignedID == nil { return "No one yet" }
        if let assigneeName { return assigneeName }
        return rosterLoaded ? "Outside your roster" : ""
    }

    /// The customer's mobile number, when this phone can hand a text to Messages.
    private var textablePhone: String? {
        guard MFMessageComposeViewController.canSendText() else { return nil }
        let trimmed = (customer?.phone ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Paper 53B's text: "Hi Danielle, your AC visit with Wade's Plumbing moved to Wed Jul 22,
    /// 10 AM–12 PM. Reply if that doesn't work." The window is the two hours the schedule saves.
    private var customerMessage: String {
        let first = RunningLateDraft.greetingName(customer?.name, commercial: customer?.accountType == "commercial")
        let greeting = first.map { "Hi \($0)," } ?? "Hi,"
        let company = (session.activeOrganization?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let with = company.isEmpty ? "" : " with \(company)"
        let day = date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        var window = date.tradeTime
        if let end = JobScheduleSelection.twoHourWindowEnd(from: date) { window += "\u{2013}\(end.tradeTime)" }
        let verb = job.scheduledFor == nil ? "is booked for" : "moved to"
        return "\(greeting) your \(job.title) visit\(with) \(verb) \(day), \(window). Reply if that doesn\u{2019}t work."
    }

    /// Cancelling races with dispatch, so it needs signal and the server's say (as Wrap up's row).
    private var canCancelVisit: Bool {
        !session.isOffline && session.can("job.cancel", feature: "jobs")
            && job.allowedTransitions?.contains("canceled") == true
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                // Paper 53B / P1: the visit, a strip of days, then the arrival windows on one card.
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(store.customerName(job.customerId)) · \(job.title)")
                            .font(Theme.font(20, weight: .bold)).tracking(-0.2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(visitSubtitle).font(Theme.font(15)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 4)
                    dayStrip
                    if showsCalendar {
                        DatePicker("Pick date", selection: calendarDateSelection, in: Date.distantPast..., displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .tint(Theme.brand)
                            .padding(.horizontal, 8)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                            .accessibilityLabel("Choose schedule date")
                    }
                    PaperSection("Arrival window · \(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))") {
                        VStack(spacing: 0) {
                            ForEach(timeOptions, id: \.hour) { option in
                                timeRow(hour: option.hour, minute: option.minute)
                                WellDivider()
                            }
                            if showsCustomTime {
                                HStack(spacing: 12) {
                                    Text("Other time").font(Theme.font(16, weight: .medium))
                                    Spacer()
                                    DatePicker("Other time", selection: $date, displayedComponents: .hourAndMinute)
                                        .labelsHidden()
                                        .datePickerStyle(.compact)
                                        .accessibilityLabel("Choose a custom start time")
                                        .onChange(of: date) { _, _ in error = nil }
                                }
                                .padding(.horizontal, PaperCardMetrics.inset)
                                .frame(minHeight: 52)
                            } else {
                                Button { showsCustomTime = true } label: {
                                    Text("Other time…").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.brandText)
                                        .padding(.horizontal, PaperCardMetrics.inset)
                                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(RowPressStyle())
                            }
                        }
                    }
                    if canAssign {
                        // Paper 53B: who has the visit, then the text to the customer, on one card.
                        VStack(spacing: 0) {
                            assignedTechRow
                            if textablePhone != nil {
                                customerTextRow.overlay(alignment: .top) { WellDivider(leading: 0) }
                            }
                        }
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    } else {
                        // A disabled commit says why (design.thorbis.com "Disabled needs a reason").
                        Text("Your role can't schedule jobs. Ask your office to set the time.")
                            .font(Theme.font(13)).foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }
                    if let error { ErrorBanner(message: error).padding(.vertical, 8) }
                    if canCancelVisit {
                        // Paper 53B: "Cancel visit" in 15 Medium red, centred, 44 tall.
                        Button { confirmCancel = true } label: {
                            Text("Cancel visit").font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.destructive)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle())
                        .disabled(saved)
                        .accessibilityIdentifier("schedule-cancel-visit")
                    }
                }
                .padding(.horizontal, PaperCardMetrics.margin)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .disabled(busy)
        }
        // The canvas tone under the sheet, so the day tiles and the window card read as cards.
        .background(Theme.background)
        .foregroundStyle(Theme.foreground)
        .thorbisSheetPresentation(typeSize.isAccessibilitySize ? [.large] : [.height(640), .large])
        .interactiveDismissDisabled(busy)
        .task { await loadPeople() }
        // Paper 53A over 53B: the roster as its own sheet; the row reads the new tech when it closes.
        .sheet(isPresented: $showAssign, onDismiss: { Task { await reloadAssignee() } }) {
            SheetSurface { JobAssignmentView(jobID: job.id) }
        }
        // The new time is saved first; then Messages opens with the text, and the tech sends it.
        .sheet(isPresented: $composing, onDismiss: { dismiss() }) {
            ScheduleTextComposer(recipient: textablePhone ?? "", message: customerMessage) { composing = false }
                .ignoresSafeArea()
        }
        .thorbisConfirm("Cancel job", message: "JOB-\(job.id.suffix(4).uppercased()) \u{00B7} \(job.title)",
                        isPresented: $confirmCancel,
                        actions: [ThorbisConfirmAction("Cancel job", role: .destructive) { Task { await cancelVisit() } }])
    }

    /// Paper 53B: 32pt initials on the brand surface, "Assigned tech" in 16, the name and a chevron
    /// in muted; 56 tall. Opens Assign a technician (53A).
    private var assignedTechRow: some View {
        Button { showAssign = true } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Theme.brandSurface)
                    if let assigneeName {
                        Text(initials(assigneeName)).font(Theme.font(12, weight: .semibold)).foregroundStyle(Theme.brandText)
                    } else {
                        Image(systemName: "person").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.brandText)
                    }
                }
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
                Text("Assigned tech").font(Theme.font(16)).foregroundStyle(Theme.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(assigneeWords).font(Theme.font(16)).foregroundStyle(Theme.muted)
                    .lineLimit(1)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, PaperCardMetrics.inset)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens Assign a technician")
        .accessibilityIdentifier("schedule-assigned-tech")
    }

    /// Paper 53B: the switch, then the text on a fill bubble (14, radius 14). On, saving the new
    /// time opens Messages with this text; the tech sends it from their own phone.
    private var customerTextRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $notifyCustomer) {
                Text("Let the customer know").font(Theme.font(16)).foregroundStyle(Theme.foreground)
            }
            .tint(Theme.brand)
            .accessibilityHint("After you save, Messages opens with this text for you to send")
            .accessibilityIdentifier("schedule-notify-customer")
            if notifyCustomer {
                Text("\u{201C}\(customerMessage)\u{201D}").font(Theme.font(14)).foregroundStyle(Theme.subtle)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Theme.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(.horizontal, PaperCardMetrics.inset).padding(.top, 12).padding(.bottom, 14)
    }

    /// The roster (for the assigned tech's name) and the customer (for the text).
    private func loadPeople() async {
        guard canAssign else { return }
        if let people = try? await api.fieldAssignees() { roster = people }
        rosterLoaded = true
        guard MFMessageComposeViewController.canSendText() else { return }
        customer = try? await api.fieldCustomer(job.customerId)
    }

    /// After Assign a technician closes: who the server says has the visit now.
    private func reloadAssignee() async {
        guard let fresh = try? await api.fieldJob(job.id, requireFresh: true), fresh.id == job.id else { return }
        assignedID = fresh.assignedToUserId
    }

    /// "Cancel visit": the same cancel the job's Wrap up offers (`POST /v1/jobs/{id}/cancel`).
    private func cancelVisit() async {
        guard canCancelVisit, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let updated = try await api.cancelFieldJob(job.id)
            onSaved(updated)
            _ = await store.refresh(api)
            dismiss()
        } catch is CancellationError {
        } catch {
            self.error = "Could not cancel this visit. \(error.localizedDescription)"
        }
    }

    /// Paper 53B: Cancel on the left, the sheet's name centred, the commit as a brand pill.
    private var header: some View {
        let canSave = session.can("job.assign", feature: "jobs")
        return HStack(spacing: 8) {
            Button { dismiss() } label: {
                Text("Cancel").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                    .padding(.horizontal, 16).frame(minHeight: 44)
                    .background(Theme.fill, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(PressStyle())
            .disabled(busy)
            Spacer(minLength: 4)
            Text(job.scheduledFor == nil ? "Schedule visit" : "Move visit")
                .font(Theme.font(17, weight: .semibold))
                .lineLimit(1).minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 4)
            Button { Task { await save() } } label: {
                HStack(spacing: 6) {
                    if busy { ProgressView().tint(.white) }
                    Text(saved ? "Saved" : (job.scheduledFor == nil ? "Schedule" : "Reschedule"))
                        .font(Theme.font(16, weight: .semibold))
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 18).frame(minHeight: 44)
                .background(Theme.brand.opacity(busy || saved || !canSave ? 0.5 : 1), in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(PressStyle())
            .disabled(busy || saved || !canSave)
            .accessibilityLabel(saved ? "Schedule saved" : "Save schedule")
        }
        .padding(.horizontal, PaperCardMetrics.margin)
        .padding(.top, 14).padding(.bottom, 4)
    }

    /// "JOB-2214 · now Tue Jul 21, 10:30 AM" (or "not scheduled yet").
    private var visitSubtitle: String {
        let reference = "JOB-\(job.id.suffix(4).uppercased())"
        if let current = JobFiltering.date(job.scheduledFor) {
            return "\(reference) · now \(current.visitLabel())"
        }
        return "\(reference) · not scheduled yet"
    }

    /// Paper 53B's day strip: the next six days as tiles, the chosen one in brand, then a
    /// calendar tile for any other date.
    private var dayStrip: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let days: [Date] = (0..<6).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
        let inStrip = days.contains { calendar.isDate($0, inSameDayAs: date) }
        return HStack(spacing: 6) {
            ForEach(days, id: \.self) { day in
                let offset = calendar.dateComponents([.day], from: today, to: day).day ?? 0
                ScheduleDayTile(weekday: day.formatted(.dateTime.weekday(.abbreviated)),
                                number: day.formatted(.dateTime.day()),
                                selected: calendar.isDate(day, inSameDayAs: date) && !showsCalendar) {
                    showsCalendar = false
                    selectDay(offset: offset)
                }
                .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
            }
            ScheduleDayTile(weekday: "More", number: nil,
                            selected: showsCalendar || !inStrip) {
                showsCalendar.toggle()
            }
            .accessibilityLabel("Pick date")
        }
    }

    private func selectDay(offset: Int) {
        let calendar = Calendar.current
        let targetDay = calendar.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        if let next = JobScheduleSelection.date(on: targetDay, preservingTimeFrom: date, calendar: calendar) {
            date = next
            error = nil
        } else {
            error = invalidLocalTimeMessage
        }
    }

    private var calendarDateSelection: Binding<Date> {
        Binding(
            get: { date },
            set: { proposedDate in
                guard let selection = JobScheduleSelection.date(
                    on: proposedDate, preservingTimeFrom: date, calendar: .current
                ) else {
                    error = invalidLocalTimeMessage
                    return
                }
                date = selection
                error = nil
            }
        )
    }

    private func timeRow(hour: Int, minute: Int) -> some View {
        let selected = JobScheduleSelection.matchesPreset(date, hour: hour, minute: minute)
        let label = presetLabel(hour: hour, minute: minute)
        return Button {
            if let selectedDate = JobScheduleSelection.date(on: date, hour: hour, minute: minute) {
                date = selectedDate
                showsCustomTime = false
                error = nil
            } else {
                error = invalidLocalTimeMessage
            }
        } label: {
            // Paper 53B: the window's start, a muted note, the chosen row on brand surface with a
            // filled brand tick.
            HStack(spacing: 12) {
                Text(label)
                    .font(Theme.font(16, weight: selected ? .semibold : .medium)).monospacedDigit()
                    .foregroundStyle(Theme.foreground)
                Text("2 hr window").font(Theme.font(14)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if selected {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 22))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.white, Theme.brand)
                        .accessibilityHidden(true)
                } else {
                    Color.clear.frame(width: 22, height: 22)
                }
            }
            .padding(.horizontal, PaperCardMetrics.inset)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(selected ? Theme.brandSurface : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityLabel("\(label), two hour arrival window")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func presetLabel(hour: Int, minute: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let time = calendar.date(from: components) ?? Date()
        return time.tradeTime
    }

    private static func timeOptionsContain(_ date: Date) -> Bool {
        [(8, 0), (10, 30), (13, 0), (15, 30)].contains {
            JobScheduleSelection.matchesPreset(date, hour: $0.0, minute: $0.1)
        }
    }

    private func save() async {
        guard session.can("job.assign", feature: "jobs"), !busy,
              let request = JobScheduleSelection.request(for: job, selectedDate: date,
                                                         timeZone: .current, calendar: .current) else { return }
        busy = true
        defer { busy = false }
        do {
            let updated = try await api.scheduleFieldJob(job.id, request: request)
            saved = true
            onSaved(updated)
            switch await store.refresh(api) {
            case .failed:
                self.error = "Schedule saved, but the jobs list could not refresh. Close this sheet and refresh Jobs before making another change."
                return
            case .applied, .superseded:
                // Paper 53B "Let the customer know": Messages opens with the text; closing it closes this.
                if notifyCustomer, textablePhone != nil { composing = true } else { dismiss() }
            }
        } catch is CancellationError {
        } catch let problem as Problem where problem.status == 409 {
            error = "The schedule changed. Close this sheet and reopen it to review the latest time."
        } catch {
            self.error = "Could not confirm this schedule. Close and refresh the job before trying again. \(error.localizedDescription)"
        }
    }
}

struct JobFollowUpsView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let jobID: String
    /// The job screen's Return visit tool opens the form already on "Schedule a return visit".
    init(jobID: String, initialKind: FieldFollowUpRequest.Kind = .notifyOffice) {
        self.jobID = jobID
        _kind = State(initialValue: initialKind)
    }
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var session: SessionController
    @EnvironmentObject private var outbox: FieldOutbox
    @State private var records: [FieldFollowUpRecord] = []
    @State private var loading = true
    @State private var busy = false
    @State private var error: String?
    /// Said after a follow-up was kept on the phone for lack of signal.
    @State private var savedNote: String?
    @State private var reason = ""
    @State private var nextAction = ""
    @State private var kind: FieldFollowUpRequest.Kind = .notifyOffice
    @State private var booking: FieldFollowUpRecord?
    /// Said under each question when Send follow-up is pressed with it unanswered; clears on typing.
    @State private var reasonProblem: String?
    @State private var nextProblem: String?
    @FocusState private var followUpFocus: Int?
    /// Open follow-ups first, then one short form to ask the office for the next step.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OfflineBanner().padding(.horizontal, -PaperCardMetrics.margin)
                // Paper 21H: the 34 Bold title and the job under it in 15 muted.
                VStack(alignment: .leading, spacing: 2) {
                    Text("Follow-ups").font(Theme.font(34, weight: .bold)).tracking(-0.85)
                        .accessibilityAddTraits(.isHeader)
                    Text("JOB-\(jobID.suffix(4).uppercased())").font(Theme.font(15)).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 4).padding(.top, 14).padding(.bottom, 16)
                if let error { ErrorBanner(message: error, retry: records.isEmpty ? { await load() } : nil).padding(.horizontal, -PaperCardMetrics.margin) }
                if let savedNote {
                    Text(savedNote).font(Theme.font(13)).foregroundStyle(Theme.muted).padding(.bottom, 10).padding(.horizontal, 4)
                }
                let waiting = outbox.pendingFollowUps(for: jobID)
                if !waiting.isEmpty {
                    PaperSection("Waiting to send", count: waiting.count) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(waiting) { entry in
                                if case .followUp(let payload) = entry.action {
                                    PaperListRow(title: payload.reason, subtitle: "Next: \(payload.nextAction)",
                                                 meta: entry.summary, subtitleLines: 3) {
                                        StatusWord(text: entry.state == .pending ? "Saved on this phone" : "Needs review",
                                                   tint: entry.state == .pending ? Theme.muted : Theme.warning)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, PaperCardMetrics.edge)
                    }
                    .padding(.bottom, 20)
                }
                if loading && records.isEmpty { SkeletonRows(count: 4, leading: false, inset: 0) }
                // design 2026-10-30: follow-ups as rows on one panel, the state as a word; Book the
                // return visit and Resolve moved into each row's ••• menu.
                if !records.isEmpty {
                    PaperSection("On this job", count: records.count) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(records) { record in
                                followUpRow(record)
                            }
                        }
                        .padding(.vertical, PaperCardMetrics.edge)
                    }
                    .padding(.bottom, 20)
                }
                if session.can("job.edit", feature: "jobs") {
                    PaperGroupHeader(title: "New follow-up").padding(.horizontal, 4)
                    ThorbisSegmented(options: [
                        (FieldFollowUpRequest.Kind.notifyOffice, "Notify office"),
                        (FieldFollowUpRequest.Kind.officeScheduling, "Schedule a return visit"),
                    ], selection: $kind)
                    .padding(.bottom, 10)
                    followUpField("What happened?", example: "Part on order, customer away until Friday…", text: $reason,
                                  error: reasonProblem, focusID: 0)
                    followUpField("What needs to happen next?", example: "Book a return visit to fit the part…", text: $nextAction,
                                  error: nextProblem, focusID: 1).padding(.top, 12)
                    Text("A return-visit request goes to the office to book; it doesn't reserve a time.")
                        .font(Theme.font(13)).foregroundStyle(Theme.muted).padding(.top, 8).padding(.horizontal, 4)
                }
                if !loading && records.isEmpty && !session.can("job.edit", feature: "jobs") {
                    PaperEmptyState(symbol: "list.bullet", title: "No follow-ups on this job")
                }
            }
            .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 4).padding(.bottom, 24)
        }
        .foregroundStyle(Theme.foreground)
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $booking) { record in SheetSurface {
            FollowUpBookingSheet(jobID: jobID, followUp: record) { Task { await load() } }
        } }
        .safeAreaInset(edge: .bottom) {
            if session.can("job.edit", feature: "jobs") {
                // Never pre-disabled: pressed with a question unanswered, it says which under it.
                PaperActionBar(title: "Send follow-up", symbol: "paperplane", busy: busy) {
                    if showFollowUpProblems() { Task { await create() } }
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    /// The question stays above the field once typing starts (GR-26); the placeholder is only an example.
    private func followUpField(_ label: String, example: String, text: Binding<String>, error: String?, focusID: Int) -> some View {
        PaperFormField(label, error: error) {
            TextField(example, text: text, prompt: .placeholder(example), axis: .vertical)
                .font(Theme.font(16)).lineLimit(2...5)
                .fieldWell()
                .focused($followUpFocus, equals: focusID)
                .onChange(of: text.wrappedValue) { _, _ in if focusID == 0 { reasonProblem = nil } else { nextProblem = nil } }
                .accessibilityLabel(label)
        }
    }

    /// Says what's missing or too long under each question and moves to the first; true when ready.
    private func showFollowUpProblems() -> Bool {
        func problem(_ text: String, missing: String) -> String? {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return missing }
            return text.utf16.count > 2000 ? "Keep this to 2,000 characters." : nil
        }
        reasonProblem = problem(reason, missing: "Say what happened, like \u{201C}Part on order.\u{201D}")
        nextProblem = problem(nextAction, missing: "Say what needs to happen next, like \u{201C}Book a return visit.\u{201D}")
        if reasonProblem != nil { followUpFocus = 0 } else if nextProblem != nil { followUpFocus = 1 }
        return reasonProblem == nil && nextProblem == nil
    }

    private func followUpRow(_ record: FieldFollowUpRecord) -> some View {
        var actions: [ThorbisMenuItem] = []
        if record.status == "open", session.can("job.assign", feature: "jobs") {
            if record.kind == "office_scheduling", record.scheduling?.appointment == nil {
                actions.append(ThorbisMenuItem("Book the return visit", icon: "calendar.badge.plus", isDisabled: busy) { booking = record })
            }
            actions.append(ThorbisMenuItem("Resolve", icon: "checkmark.circle", isDisabled: busy) { Task { await resolve(record.id) } })
        }
        let meta = [record.kind.statusLabel,
                    record.scheduling.map { $0.appointment != nil ? "Visit booked" : "Waiting for office review" }]
            .compactMap { $0 }.joined(separator: " · ")
        // The status and the menu sit beside the reason only; the next step and the meta take the row's
        // full width, so "Next:" isn't squeezed into a column beside an empty gutter.
        let stacked = typeSize.isAccessibilitySize
        return VStack(alignment: .leading, spacing: 2) {
            // At accessibility sizes the status and menu go under the reason, so it keeps whole words.
            (stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 10))) {
                Text(record.reason).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                StatusWord(text: record.status.statusLabel, tint: record.status == "open" ? Theme.warning : Theme.success)
                if !actions.isEmpty {
                    ThorbisMenu(items: actions, accessibilityLabel: "Follow-up actions") {
                        Image(systemName: "ellipsis").foregroundStyle(Theme.muted)
                            .frame(width: 44, height: 32).contentShape(Rectangle())
                    }
                    .padding(.trailing, -12)
                }
            }
            Text("Next: \(record.nextAction)").font(Theme.font(14)).foregroundStyle(Theme.subtle)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
            if !meta.isEmpty {
                Text(meta).font(Theme.font(13)).foregroundStyle(Theme.muted).padding(.top, 1)
            }
        }
        .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do { records = try await api.fieldFollowUps(jobID); error = nil }
        catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    private func create() async {
        busy = true
        defer { busy = false }
        savedNote = nil
        let payload = OutboxEntry.FollowUpPayload(jobId: jobID, kind: kind.rawValue,
                                                  reason: reason.trimmingCharacters(in: .whitespacesAndNewlines),
                                                  nextAction: nextAction.trimmingCharacters(in: .whitespacesAndNewlines))
        // No signal: keep it on the phone; it is sent in order when signal returns (FieldOutbox).
        func keep(attempted: Bool) {
            guard outbox.enqueue(.followUp(payload), policyVersion: session.policyVersion ?? 0, attempted: attempted) != nil else {
                error = "This follow-up couldn't be saved on this phone. Try again when you have signal."
                return
            }
            reason = ""
            nextAction = ""
            error = nil
            savedNote = "Saved on this phone · sends to the office when you’re back online."
        }
        if session.isOffline { keep(attempted: false); return }
        do {
            _ = try await api.requestFieldFollowUp(jobID, request: .init(kind: kind, reason: payload.reason, nextAction: payload.nextAction))
            reason = ""
            nextAction = ""
            await load()
        } catch is CancellationError {} catch {
            // The request may have reached the server before the signal dropped, so the resend
            // checks the job's follow-ups first.
            if error.isConnectivityFailure { keep(attempted: true) } else { self.error = error.localizedDescription }
        }
    }
    private func resolve(_ id: String) async {
        busy = true
        defer { busy = false }
        do { _ = try await api.resolveFieldFollowUp(jobID, followUpID: id); await load() }
        catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}

/// Books an office-scheduling follow-up into a real arrival window. When capacity is short the
/// server sends it to the office instead, and the sheet says so rather than claiming a booking.
struct FollowUpBookingSheet: View {
    let jobID: String
    let followUp: FieldFollowUpRecord
    let onDone: () -> Void
    @EnvironmentObject private var api: APIClient
    @Environment(\.dismiss) private var dismiss
    @State private var day = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
    @State private var start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now
    @State private var hours = 2
    @State private var need = ""
    @State private var busy = false
    @State private var error: String?
    @State private var result: String?
    /// Said under the visit's purpose when Book visit is pressed without one; clears on typing.
    @State private var needProblem: String?
    @FocusState private var needFocused: Bool
    /// One intent per sheet, so a retry after a dropped connection can't book twice.
    @State private var intentID = UUID().uuidString.lowercased()

    var body: some View {
        NavigationStack {
            // design 2026-10-30: one column, labels above, answers in field wells, the one ink
            // commit pinned above the keyboard.
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Paper 21H: the 34 Bold title, the follow-up's reason under it.
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Book a follow-up").font(Theme.font(34, weight: .bold)).tracking(-0.85)
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .accessibilityAddTraits(.isHeader)
                        Text(followUp.reason).font(Theme.font(15)).foregroundStyle(Theme.muted)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 4).padding(.top, 6).padding(.bottom, 4)
                    PaperSection("Arrival window") {
                        VStack(spacing: 0) {
                            DatePicker("Day", selection: $day, in: Date()..., displayedComponents: .date)
                                .font(Theme.font(16, weight: .medium)).frame(minHeight: 56)
                                .padding(.horizontal, PaperCardMetrics.inset)
                            WellDivider()
                            DatePicker("Arrive from", selection: $start, displayedComponents: .hourAndMinute)
                                .font(Theme.font(16, weight: .medium)).frame(minHeight: 56)
                                .padding(.horizontal, PaperCardMetrics.inset)
                            WellDivider()
                            Stepper("Window: \(hours) hour\(hours == 1 ? "" : "s")", value: $hours, in: 1...8)
                                .font(Theme.font(16, weight: .medium)).frame(minHeight: 56)
                                .padding(.horizontal, PaperCardMetrics.inset)
                        }
                        .tint(Theme.brand)
                    }
                    PaperFormField("What the visit is for", error: needProblem) {
                        TextField("Service needed", text: $need, prompt: .placeholder("Service needed"), axis: .vertical).lineLimit(2...4)
                            .font(Theme.font(16)).fieldWell()
                            .focused($needFocused)
                            .onChange(of: need) { _, _ in needProblem = nil }
                    }
                    .padding(.top, 8)
                    if let result { Label(result, systemImage: "checkmark.circle").font(Theme.font(15)).foregroundStyle(Theme.success) }
                    if let error { Text(error).font(Theme.font(15)).foregroundStyle(Theme.destructive) }
                }
                .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 4).padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ThorbisToolbarItem(placement: .topBarLeading) { Button(result == nil ? "Cancel" : "Done") { if result != nil { onDone() }; dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                if result == nil {
                    // Never pre-disabled: pressed without a purpose, it says so under the field.
                    PaperActionBar(title: bookTitle, busy: busy) {
                        if need.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            needProblem = "Say what the visit is for, like \u{201C}Fit the new capacitor.\u{201D}"
                            needFocused = true
                        } else {
                            Task { await book() }
                        }
                    }
                }
            }
            .onAppear { if need.isEmpty { need = followUp.nextAction } }
        }
        .interactiveDismissDisabled(busy)
        .presentationCornerRadius(Theme.cardRadius)
    }

    /// Paper 21H: the commit names the window, "Book Thu, Jul 23, 8:00 a.m.".
    private var bookTitle: String {
        guard let begins = window?.0 else { return "Book visit" }
        return "Book \(begins.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())), \(begins.tradeTime)"
    }

    private var window: (Date, Date)? {
        let calendar = Calendar.current
        let time = calendar.dateComponents([.hour, .minute], from: start)
        guard let begins = calendar.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0, of: day),
              let ends = calendar.date(byAdding: .hour, value: hours, to: begins) else { return nil }
        return (begins, ends)
    }

    private func book() async {
        guard let (begins, ends) = window else { return }
        busy = true
        defer { busy = false }
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let request = FieldFollowUpBookingRequest(intentId: intentID,
                                                  requestedWindow: FieldAppointmentWindow(startsAt: format.string(from: begins), endsAt: format.string(from: ends)),
                                                  timeZone: TimeZone.current.identifier,
                                                  serviceNeed: need.trimmingCharacters(in: .whitespacesAndNewlines),
                                                  requiredTraitIds: [])
        do {
            let booked = try await api.bookFieldFollowUp(jobID, followUpID: followUp.id, request: request)
            result = booked.outcome == "booked"
                ? "Booked for \(begins.weekdayStampLabel)"
                : "No one is free then, so the office will confirm a time."
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.isConnectivityFailure ? "Booking needs a connection. Try again when you have signal." : error.localizedDescription
        }
    }
}

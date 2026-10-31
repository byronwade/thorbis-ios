import SwiftUI

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
    /// Short and on the right: a count or an amount ("3", "$480 due").
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
                                  detail: paid ? "Paid" : owed.flatMap { $0 > 0 ? "\(jobShortMoney($0, currency: currency)) due" : nil },
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
    let jobID: String
    /// The job's street when the opener already knows it (street first, the ID after it).
    var place: String? = nil
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var session: SessionController
    @EnvironmentObject var store: Store
    @State private var closeout: FieldCloseout?
    @State private var job: JobRecord?
    @State private var error: String?
    @State private var busy = false
    @State private var confirmComplete = false
    @State private var completed = 0
    @State private var confirmCancel = false
    @State private var invoiceID: String?
    @State private var openInvoiceID: String?
    @State private var openBilling = false
    @State private var unpaidReasonCode = "customer_will_pay_later"
    @State private var unpaidReason = ""
    @State private var unpaidNextAction = ""
    private var mayRecordUnpaidDisposition: Bool {
        guard let closeout, !closeout.unmet.isEmpty, session.can("job.edit", feature: "jobs") else { return false }
        return closeout.unmet.allSatisfy { $0.kind == "payment_or_unpaid_disposition" } && closeout.policy.requiredChecks.contains { $0.kind == "payment_or_unpaid_disposition" && $0.allowUnpaidDisposition == true }
    }
    private var validDisposition: Bool {
        mayRecordUnpaidDisposition && !unpaidReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !unpaidNextAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && unpaidReason.utf16.count <= 2000 && unpaidNextAction.utf16.count <= 2000
    }
    private var canComplete: Bool {
        guard let closeout else { return false }
        return session.can("job.complete", feature: "jobs") && job?.allowedTransitions?.contains("completed") == true
            && (closeout.completable || validDisposition)
    }

    /// Paper 83: a short checklist, then one commit.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    if let place {
                        PaperEyebrow(text: [place, job.map { store.customerName($0.customerId) }, "JOB-\(jobID.suffix(4).uppercased())"]
                            .compactMap { $0 }.joined(separator: " · "))
                    } else {
                        PaperEyebrow(reference: "JOB-\(jobID.suffix(4).uppercased())", text: job.map { store.customerName($0.customerId) })
                    }
                    Text(job?.status == "completed" ? "Job complete" : "Wrap up this job")
                        .font(Theme.font(24, weight: .medium)).tracking(-0.36).accessibilityAddTraits(.isHeader)
                }
                .padding(.bottom, 14)
                if let error { ErrorBanner(message: error, retry: closeout == nil ? { await load() } : nil).padding(.horizontal, -Theme.gutter) }
                if let closeout {
                    let checks = CloseoutChecklist.acknowledgementChecks(closeout)
                    let progress = CloseoutChecklist.progress(closeout)
                    PaperGroupHeader(title: "Before you close") {
                        Text("\(progress.done) of \(progress.total)").font(Theme.monoFont(12))
                    }
                    // One white sheet for the checklist, as on the job's On site list.
                    if !closeout.requirements.isEmpty || !checks.isEmpty {
                    PaperCard { VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(closeout.requirements.enumerated()), id: \.offset) { _, requirement in
                        let step = CloseoutNextStep(requirement)
                        HStack(spacing: 12) {
                            checklistRow(done: requirement.outcome != "blocked", title: requirement.detail, detail: step?.detail)
                            if let step, let title = step.buttonTitle, step.capabilities.allSatisfy({ session.can($0, feature: "invoicing") }) {
                                Button { Task { await recover(step) } } label: { Text(title) }
                                    .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                                    .frame(minHeight: 44).contentShape(Rectangle())
                                    .buttonStyle(PressStyle())
                                    .disabled(busy)
                            }
                        }
                        .padding(.horizontal, PaperCardMetrics.inset)
                    }
                    ForEach(checks, id: \.key) { check in
                        let acknowledged = closeout.facts.acknowledgedCheckKeys.contains(check.key)
                        HStack(spacing: 12) {
                            checklistRow(done: acknowledged, title: check.label, detail: nil)
                            if !acknowledged && session.can("job.edit", feature: "jobs") {
                                Button { Task { await acknowledge(check.key) } } label: { Text("Confirm") }
                                    .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                                    .frame(minHeight: 44).contentShape(Rectangle())
                                    .buttonStyle(PressStyle())
                                    .disabled(busy)
                            }
                        }
                        .padding(.horizontal, PaperCardMetrics.inset)
                    }
                    }.padding(.vertical, 6) }
                    }
                    if closeout.requirements.isEmpty && checks.isEmpty {
                        Text("Nothing else is required before closing.").font(Theme.font(15)).foregroundStyle(Theme.muted).frame(minHeight: 44)
                    }
                    if mayRecordUnpaidDisposition {
                        PaperGroupHeader(title: "Unpaid follow-up").padding(.top, 18)
                        ThorbisSelect(options: [
                            ("customer_will_pay_later", "Customer will pay later"),
                            ("office_collection_required", "Office collection required"),
                            ("payment_attempt_failed", "Payment attempt failed"),
                            ("other", "Other"),
                        ], selection: $unpaidReasonCode, label: "Reason")
                        wellField("Explain the unpaid balance", text: $unpaidReason)
                        wellField("Office follow-up action", text: $unpaidNextAction).padding(.top, 8)
                        Text("Completing with this leaves payment outstanding and creates an office follow-up.")
                            .font(Theme.font(12)).foregroundStyle(Theme.muted).padding(.top, 8)
                    }
                    if job?.status == "completed" {
                        PaperGroupHeader(title: "Billing").padding(.top, 18)
                        if session.can("invoice.create", feature: "invoicing") {
                            Button { Task { await completionInvoice() } } label: {
                                PaperMenuRow("Open completion invoice", symbol: "doc.plaintext")
                            }.buttonStyle(RowPressStyle()).disabled(busy)
                        }
                        if let invoiceID, session.can("invoice.view", feature: "invoicing") {
                            NavigationLink { InvoiceDetailView(id: invoiceID).thorbisBackButton() } label: { PaperMenuRow("View invoice", symbol: "doc.text") }
                                .buttonStyle(RowPressStyle())
                        }
                    }
                    if session.can("job.cancel", feature: "jobs"), job?.allowedTransitions?.contains("canceled") == true {
                        Button { confirmCancel = true } label: {
                            Text("Cancel job").font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.destructive)
                                .frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle())
                        .padding(.top, 18)
                        .disabled(busy)
                    }
                } else if error == nil {
                    SkeletonRows(count: 4, leading: false, inset: 0)
                }
            }
            .padding(.horizontal, Theme.gutter).padding(.top, 4).padding(.bottom, 24)
        }
        .foregroundStyle(Theme.foreground)
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if job?.status != "completed", session.can("job.complete", feature: "jobs"), job?.allowedTransitions?.contains("completed") == true {
                PaperActionBar(title: "Complete job", symbol: "checkmark", busy: busy, disabled: !canComplete) { confirmComplete = true }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        // Collecting from the checklist comes back here once it's paid, ready to complete.
        .thorbisDestination(item: $openInvoiceID) { InvoiceDetailView(id: $0, returnsWhenPaid: true).onDisappear { Task { await load() } } }
        .thorbisDestination(isPresented: $openBilling) { BillingSchedulesView() }
        .sensoryFeedback(.success, trigger: completed)
        .thorbisConfirm("Complete this job?", isPresented: $confirmComplete,
                        actions: [ThorbisConfirmAction("Complete job") { Task { await complete() } }])
        .thorbisConfirm("Cancel this job?", isPresented: $confirmCancel,
                        actions: [ThorbisConfirmAction("Cancel job", role: .destructive) { Task { await cancel() } }])
    }
    private func checklistRow(done: Bool, title: String, detail: String?) -> some View {
        HStack(alignment: .center, spacing: 12) {
            JobTick(done: done)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.font(15, weight: done ? .regular : .medium))
                    .foregroundStyle(done ? Theme.muted : Theme.foreground)
                if let detail { Text(detail).font(Theme.font(13)).foregroundStyle(Theme.muted) }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "Done" : "Not done")
    }

    private func wellField(_ prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text, axis: .vertical)
            .font(Theme.font(16)).lineLimit(2...5)
            .padding(12)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).stroke(Theme.border))
    }

    private func load() async {
        do {
            job = try await api.fieldJob(jobID)
            closeout = try await api.fieldCloseout(jobID)
            error = nil
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    private func acknowledge(_ key: String) async {
        busy = true
        defer { busy = false }
        do { _ = try await api.acknowledgeFieldCheck(jobID, checkKey: key); await load() }
        catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    private func complete() async {
        busy = true
        defer { busy = false }
        do {
            let disposition: FieldUnpaidDisposition? = validDisposition ? .init(reasonCode: unpaidReasonCode, reason: unpaidReason.trimmingCharacters(in: .whitespacesAndNewlines), followUpNextAction: unpaidNextAction.trimmingCharacters(in: .whitespacesAndNewlines)) : nil
            job = try await api.completeFieldJob(jobID, request: .init(unpaidDisposition: disposition))
            completed += 1
            await load()
            await store.refresh(api)
        }
        catch is CancellationError {} catch { self.error = error.localizedDescription }
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
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                // design 2026-10-30: one column — the day as the one segmented selector, the
                // arrival times as rows on one panel, the chosen one carrying the accent check.
                VStack(alignment: .leading, spacing: 16) {
                    PaperFormField("Day") {
                        dayOptions
                        if showsCalendar {
                            DatePicker("Pick date", selection: calendarDateSelection, in: Date.distantPast..., displayedComponents: .date)
                                .datePickerStyle(.graphical)
                                .tint(Theme.brand)
                                .accessibilityLabel("Choose schedule date")
                        }
                    }
                    PaperFormField("Arrival", note: "2 hr window") {
                        ThorbisSheetGroup {
                            VStack(spacing: 0) {
                                ForEach(timeOptions, id: \.hour) { option in
                                    timeRow(hour: option.hour, minute: option.minute)
                                    WellDivider()
                                }
                                if showsCustomTime {
                                    HStack {
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
                                        Text("Other time…").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                                            .padding(.horizontal, PaperCardMetrics.inset)
                                            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(RowPressStyle())
                                }
                            }
                            .padding(.vertical, PaperCardMetrics.edge)
                        }
                    }
                    if let error { ErrorBanner(message: error).padding(.vertical, 8) }
                }
                .padding(.horizontal, PaperCardMetrics.margin)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .environment(\.paperGroupedWells, true)
            }
            .scrollIndicators(.hidden)
            .disabled(busy)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 4) {
                    PrimaryButton(title: saved ? "Schedule saved" : "Save schedule", busy: busy) { Task { await save() } }
                        .disabled(busy || saved || !session.can("job.assign", feature: "jobs"))
                    if !session.can("job.assign", feature: "jobs") {
                        // A disabled commit says why (design.thorbis.com "Disabled needs a reason").
                        Text("Your role can't schedule jobs. Ask your office to set the time.")
                            .font(Theme.font(13)).foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button("Cancel") { dismiss() }
                        .font(Theme.font(15, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .disabled(busy)
                }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                    .background(Theme.surface)
            }
        }
        .background(Theme.surface)
        .foregroundStyle(Theme.foreground)
        .thorbisSheetPresentation([.height(560), .large])
        .interactiveDismissDisabled(busy)
    }

    private var header: some View {
        ThorbisSheetHeader(title: job.scheduledFor == nil ? "Schedule" : "Reschedule",
                           closeLabel: "Close schedule picker", onClose: busy ? nil : { dismiss() })
    }

    /// Today, Tomorrow or a picked date, as the one segmented selector.
    private var dayOptions: some View {
        let calendar = Calendar.current
        let current = calendar.isDateInToday(date) && !showsCalendar ? "Today"
            : calendar.isDateInTomorrow(date) && !showsCalendar ? "Tomorrow" : "Pick date"
        return PaperTabs(options: ["Today", "Tomorrow", "Pick date"], selection: Binding(
            get: { current },
            set: { picked in
                switch picked {
                case "Today": showsCalendar = false; selectDay(offset: 0)
                case "Tomorrow": showsCalendar = false; selectDay(offset: 1)
                default: showsCalendar = current == "Pick date" ? !showsCalendar : true
                }
            }))
            .padding(.horizontal, -Theme.gutter)
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
            HStack(spacing: 12) {
                Text(label)
                    .font(Theme.font(16, weight: .medium)).monospacedDigit()
                    .foregroundStyle(Theme.foreground)
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.brandText).accessibilityHidden(true)
                }
            }
            .padding(.horizontal, PaperCardMetrics.inset)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
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
                dismiss()
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
    /// Open follow-ups first, then one short form to ask the office for the next step.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OfflineBanner().padding(.horizontal, -Theme.gutter)
                Text("Follow-ups").font(Theme.font(24, weight: .medium)).tracking(-0.36)
                    .accessibilityAddTraits(.isHeader).padding(.bottom, 12)
                if let error { ErrorBanner(message: error, retry: records.isEmpty ? { await load() } : nil).padding(.horizontal, -Theme.gutter) }
                if let savedNote {
                    Text(savedNote).font(Theme.font(13)).foregroundStyle(Theme.muted).padding(.bottom, 10)
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
                    .padding(.horizontal, PaperCardMetrics.margin - Theme.gutter)
                    .padding(.bottom, 14)
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
                    .padding(.horizontal, PaperCardMetrics.margin - Theme.gutter)
                    .padding(.bottom, 14)
                }
                if session.can("job.edit", feature: "jobs") {
                    PaperGroupHeader(title: "New follow-up").padding(.top, 8)
                    ThorbisSegmented(options: [
                        (FieldFollowUpRequest.Kind.notifyOffice, "Notify office"),
                        (FieldFollowUpRequest.Kind.officeScheduling, "Schedule a return visit"),
                    ], selection: $kind)
                    .padding(.bottom, 10)
                    followUpField("What happened?", example: "Part on order, customer away until Friday…", text: $reason)
                    followUpField("What needs to happen next?", example: "Book a return visit to fit the part…", text: $nextAction).padding(.top, 12)
                    Text("A return-visit request goes to the office to book; it doesn't reserve a time.")
                        .font(Theme.font(13)).foregroundStyle(Theme.muted).padding(.top, 8)
                }
                if !loading && records.isEmpty && !session.can("job.edit", feature: "jobs") {
                    PaperEmptyState(symbol: "list.bullet", title: "No follow-ups on this job")
                }
            }
            .padding(.horizontal, Theme.gutter).padding(.top, 4).padding(.bottom, 24)
        }
        .foregroundStyle(Theme.foreground)
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $booking) { record in
            FollowUpBookingSheet(jobID: jobID, followUp: record) { Task { await load() } }
        }
        .safeAreaInset(edge: .bottom) {
            if session.can("job.edit", feature: "jobs") {
                PaperActionBar(title: "Send follow-up", symbol: "paperplane", busy: busy,
                               disabled: reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || nextAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                   || reason.utf16.count > 2000 || nextAction.utf16.count > 2000) { Task { await create() } }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    /// The question stays above the field once typing starts (GR-26); the placeholder is only an example.
    private func followUpField(_ label: String, example: String, text: Binding<String>) -> some View {
        PaperFormField(label) {
            TextField(example, text: text, axis: .vertical)
                .font(Theme.font(16)).lineLimit(2...5)
                .fieldWell()
                .accessibilityLabel(label)
        }
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
        return HStack(alignment: .top, spacing: 0) {
            PaperListRow(title: record.reason, subtitle: "Next: \(record.nextAction)", meta: meta, subtitleLines: 3) {
                StatusWord(text: record.status.statusLabel, tint: record.status == "open" ? Theme.warning : Theme.success)
            }
            if !actions.isEmpty {
                ThorbisMenu(items: actions, accessibilityLabel: "Follow-up actions") {
                    Image(systemName: "ellipsis").foregroundStyle(Theme.muted)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .padding(.trailing, 4).padding(.top, 4)
            }
        }
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
    /// One intent per sheet, so a retry after a dropped connection can't book twice.
    @State private var intentID = UUID().uuidString.lowercased()

    var body: some View {
        NavigationStack {
            // design 2026-10-30: one column, labels above, answers in field wells, the one ink
            // commit pinned above the keyboard.
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PaperFormField("Arrival window") {
                        VStack(spacing: 0) {
                            DatePicker("Day", selection: $day, in: Date()..., displayedComponents: .date)
                                .font(Theme.font(16)).frame(minHeight: 44)
                            DatePicker("Arrive from", selection: $start, displayedComponents: .hourAndMinute)
                                .font(Theme.font(16)).frame(minHeight: 44)
                            Stepper("Window: \(hours) hour\(hours == 1 ? "" : "s")", value: $hours, in: 1...8)
                                .font(Theme.font(16)).frame(minHeight: 44)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                        .tint(Theme.brand)
                    }
                    PaperFormField("What the visit is for") {
                        TextField("Service needed", text: $need, axis: .vertical).lineLimit(2...4)
                            .font(Theme.font(16)).fieldWell()
                    }
                    if let result { Label(result, systemImage: "checkmark.circle").font(Theme.font(15)).foregroundStyle(Theme.success) }
                    if let error { Text(error).font(Theme.font(15)).foregroundStyle(Theme.destructive) }
                }
                .padding(.horizontal, Theme.gutter).padding(.top, 8).padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .navigationTitle("Book return visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ThorbisToolbarItem(placement: .topBarLeading) { Button(result == nil ? "Cancel" : "Done") { if result != nil { onDone() }; dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                if result == nil {
                    PaperActionBar(title: "Book visit", busy: busy,
                                   disabled: need.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) { Task { await book() } }
                }
            }
            .onAppear { if need.isEmpty { need = followUp.nextAction } }
        }
        .interactiveDismissDisabled(busy)
        .presentationCornerRadius(Theme.cardRadius)
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
                ? "Booked for \(begins.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))"
                : "No one is free then, so the office will confirm a time."
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.isConnectivityFailure ? "Booking needs a connection. Try again when you have signal." : error.localizedDescription
        }
    }
}

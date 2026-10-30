import SwiftUI

struct JobCloseoutView: View {
    let jobID: String
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var session: SessionController
    @EnvironmentObject var store: Store
    @EnvironmentObject var outbox: FieldOutbox
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
            return closeout.facts.photoCount + PendingPhotoStore.list(jobID: jobID).count >= closeout.policy.requiredPhotoCount
        case "check": return outbox.waitingChecks(jobID: jobID).contains(String(requirement.requirement.dropFirst("check:".count)))
        case "payment_or_unpaid_disposition":
            return waitingPaymentsCoverBalance
        default: return false
        }
    }
    /// Cash and check waiting on this phone cover every unpaid balance on the job's invoices as
    /// last seen. A partial payment leaves the requirement (and the unpaid disposition) showing.
    private var waitingPaymentsCoverBalance: Bool {
        // The job's invoice list, plus any invoice this phone took cash on for the job; the single
        // invoice copy is newer when a payment was recorded on the invoice screen.
        let listed = JobDetailCache.invoices(jobID) ?? []
        let paidHere = (outbox.pending.compactMap { entry -> String? in
            if case .payment(let payment) = entry.action, payment.jobId == jobID { payment.invoiceId } else { nil }
        } + outbox.recordedPayments.filter { $0.jobId == jobID }.map(\.invoiceId))
            .filter { id in !listed.contains { $0.id == id } }
        let invoices = listed.map { JobDetailCache.invoice($0.id) ?? $0 }
            + Set(paidHere).compactMap { JobDetailCache.invoice($0) }
        let owing = invoices.filter { $0.status == "issued" }.compactMap { invoice -> (String, Int)? in
            let total = invoice.lines.reduce(0) { $0 + $1.quantity * $1.unitPrice.amount }
            let due = total - invoice.amountPaid
            return due > 0 ? (invoice.id, due) : nil
        }
        return !owing.isEmpty && owing.allSatisfy { id, due in
            let queued = outbox.waitingPayments(invoiceID: id, replayableOnly: true).reduce(0) { $0 + $1.amountCents }
            // Recorded from the queue but newer than this phone's saved copy of the invoice.
            let saved = Set((JobDetailCache.payments(id) ?? []).map(\.idempotencyKey))
            let recorded = outbox.recordedPayments
                .filter { $0.invoiceId == id && !saved.contains($0.idempotencyKey) }
                .reduce(0) { $0 + $1.amountCents }
            return queued + recorded >= due
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
                VStack(alignment: .leading, spacing: 6) {
                    PaperEyebrow(reference: "JOB-\(jobID.suffix(4).uppercased())", text: job.map { store.customerName($0.customerId) })
                    Text(isCompleted ? "Job complete" : "Wrap up this job")
                        .font(Theme.font(24, weight: .medium)).tracking(-0.36).accessibilityAddTraits(.isHeader)
                    if completionWaiting { WaitingToSyncLabel() }
                }
                .padding(.bottom, 14)
                if let error { ErrorBanner(message: error, retry: closeout == nil ? { await load() } : nil).padding(.horizontal, -Theme.gutter) }
                if let closeout {
                    let checks = closeout.policy.requiredChecks.filter { $0.kind == nil || $0.kind == "acknowledgement" }
                    let waitingChecks = outbox.waitingChecks(jobID: jobID)
                    let done = closeout.requirements.filter { $0.outcome != "blocked" || waitingSatisfies($0) }.count
                        + checks.filter { closeout.facts.acknowledgedCheckKeys.contains($0.key) || waitingChecks.contains($0.key) }.count
                    PaperGroupHeader(title: "Before you close") {
                        Text("\(done) of \(closeout.requirements.count + checks.count)").font(Theme.monoFont(12))
                    }
                    ForEach(Array(closeout.requirements.enumerated()), id: \.offset) { _, requirement in
                        let step = CloseoutNextStep(requirement)
                        let waiting = waitingSatisfies(requirement)
                        HStack(spacing: 12) {
                            checklistRow(done: requirement.outcome != "blocked" || waiting, title: requirement.detail,
                                         detail: waiting ? "Waiting to sync" : step?.detail)
                            if !waiting, !session.isOffline, let step, let title = step.buttonTitle,
                               step.capabilities.allSatisfy({ session.can($0, feature: "invoicing") }) {
                                Button(title) { Task { await recover(step) } }
                                    .font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.foreground)
                                    .padding(.horizontal, 12).frame(height: Theme.chipHeight + 4)
                                    .background(Theme.fill, in: Capsule())
                                    .frame(minHeight: 44)
                                    .buttonStyle(PressStyle())
                                    .disabled(busy)
                            }
                        }
                    }
                    ForEach(checks, id: \.key) { check in
                        let waiting = waitingChecks.contains(check.key)
                        let acknowledged = closeout.facts.acknowledgedCheckKeys.contains(check.key) || waiting
                        HStack(spacing: 12) {
                            checklistRow(done: acknowledged, title: check.label, detail: waiting ? "Waiting to sync" : nil)
                            if !acknowledged && !isCompleted && session.can("job.edit", feature: "jobs") {
                                Button("Confirm") { Task { await acknowledge(check.key) } }
                                    .font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.foreground)
                                    .padding(.horizontal, 12).frame(height: Theme.chipHeight + 4)
                                    .background(Theme.fill, in: Capsule())
                                    .frame(minHeight: 44)
                                    .buttonStyle(PressStyle())
                                    .disabled(busy)
                                    .accessibilityHint(check.label)
                            }
                        }
                    }
                    if closeout.requirements.isEmpty && checks.isEmpty {
                        Text("Nothing else is required before closing.").font(Theme.font(15)).foregroundStyle(Theme.muted).frame(minHeight: 44)
                    }
                    if mayRecordUnpaidDisposition && !isCompleted {
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
                    if job?.status == "completed" && !session.isOffline {
                        PaperGroupHeader(title: "Billing").padding(.top, 18)
                        if session.can("invoice.create", feature: "invoicing") {
                            Button { Task { await completionInvoice() } } label: {
                                PaperMenuRow("Open completion invoice", symbol: "doc.plaintext")
                            }.buttonStyle(RowPressStyle()).disabled(busy)
                        }
                        if let invoiceID, session.can("invoice.view", feature: "invoicing") {
                            NavigationLink { InvoiceDetailView(id: invoiceID) } label: { PaperMenuRow("View invoice", symbol: "doc.text") }
                                .buttonStyle(RowPressStyle())
                        }
                    }
                    // OF-09: cancelling races with dispatch, so it needs signal and says so by not offering it.
                    if !session.isOffline, !isCompleted, session.can("job.cancel", feature: "jobs"), job?.allowedTransitions?.contains("canceled") == true {
                        Button("Cancel job", role: .destructive) { confirmCancel = true }
                            .font(Theme.font(15, weight: .medium)).frame(minHeight: 44).padding(.top, 18)
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
            if !isCompleted, session.can("job.complete", feature: "jobs"), allowsComplete {
                PaperActionBar(title: "Complete job", symbol: "checkmark", busy: busy, disabled: !canComplete) { confirmComplete = true }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        // Queued confirmations landed: show the server's checklist instead of the waiting marks.
        .onChange(of: outbox.syncGeneration) { _, _ in Task { await load() } }
        .navigationDestination(item: $openInvoiceID) { InvoiceDetailView(id: $0) }
        .navigationDestination(isPresented: $openBilling) { BillingSchedulesView() }
        .sensoryFeedback(.success, trigger: completed)
        .thorbisConfirm("Complete this job?", isPresented: $confirmComplete,
                        actions: [ThorbisConfirmAction("Complete job") { Task { await complete() } }])
        .thorbisConfirm("Cancel this job?", isPresented: $confirmCancel,
                        actions: [ThorbisConfirmAction("Cancel job", role: .destructive) { Task { await cancel() } }])
    }
    private func checklistRow(done: Bool, title: String, detail: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 17)).foregroundStyle(done ? Theme.success : Theme.muted)
                .accessibilityLabel(done ? "Done" : "Not done")
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.font(15, weight: done ? .regular : .medium))
                    .foregroundStyle(done ? Theme.muted : Theme.foreground)
                if let detail { Text(detail).font(Theme.font(13)).foregroundStyle(Theme.muted) }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
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
            let loadedJob = try await api.fieldJob(jobID)
            let loadedCloseout = try await api.fieldCloseout(jobID)
            job = loadedJob
            closeout = loadedCloseout
            outbox.learn(loadedJob)
            JobDetailCache.save(loadedJob)
            JobDetailCache.save(closeout: loadedCloseout, jobID: jobID)
            error = nil
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
            || !PendingPhotoStore.list(jobID: jobID).isEmpty {
            queueOffline(queued)
            completed += 1
            if !session.isOffline {
                Task {
                    // Photos first, as on reconnect: the completion is held until this job's are sent.
                    await PendingPhotoStore.uploadAll(api: api)
                    outbox.countPhotos()
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
                VStack(spacing: 4) {
                    dayOptions
                    if showsCalendar {
                        DatePicker("Pick date", selection: calendarDateSelection, in: Date.distantPast..., displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .tint(Theme.brand)
                            .accessibilityLabel("Choose schedule date")
                    }
                    VStack(spacing: 0) {
                        ForEach(timeOptions, id: \.hour) { option in
                            timeRow(hour: option.hour, minute: option.minute)
                        }
                    }
                    if showsCustomTime {
                        HStack {
                            Label("Other time", systemImage: "clock")
                                .font(Theme.font(15))
                                .foregroundStyle(Theme.muted)
                            Spacer()
                            DatePicker("Other time", selection: $date, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                                .datePickerStyle(.compact)
                                .accessibilityLabel("Choose a custom start time")
                                .onChange(of: date) { _, _ in error = nil }
                        }
                        .frame(minHeight: 44)
                    } else {
                        Button("Other time…") { showsCustomTime = true }
                            .font(Theme.font(15, weight: .medium))
                            .foregroundStyle(Theme.brandText)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    if let error { ErrorBanner(message: error).padding(.vertical, 8) }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .disabled(busy)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 4) {
                    PrimaryButton(title: saved ? "Schedule saved" : "Save schedule", busy: busy) { Task { await save() } }
                        .disabled(busy || saved || !session.can("job.assign", feature: "jobs"))
                    Button("Cancel") { dismiss() }
                        .font(Theme.font(15, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .disabled(busy)
                }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                    .background(Theme.card)
            }
        }
        .background(Theme.card)
        .foregroundStyle(Theme.foreground)
        .presentationDetents([.height(430), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Theme.cardRadius)
        .presentationBackground(Theme.card)
        .interactiveDismissDisabled(busy)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 44, height: 44)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            Text("Schedule")
                .font(Theme.font(17, weight: .medium))
                .tracking(-0.17)
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 30, height: 30)
                    .background(Theme.fill, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Close schedule picker")
            .disabled(busy)
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 20)
    }

    private var dayOptions: some View {
        HStack(spacing: 8) {
            dayButton("Today", offset: 0)
            dayButton("Tomorrow", offset: 1)
            Button {
                showsCalendar.toggle()
            } label: {
                HStack(spacing: 6) {
                    Text("Pick date")
                    Image(systemName: "chevron.down").font(.system(size: 12, weight: .medium))
                        .rotationEffect(.degrees(showsCalendar ? 180 : 0))
                }
                .font(Theme.font(13, weight: .medium))
                .foregroundStyle(showsCalendar ? Theme.brand : Theme.muted)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(showsCalendar ? Theme.brandSurface : Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityAddTraits(showsCalendar ? .isSelected : [])
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
        .padding(.bottom, 4)
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

    private func dayButton(_ title: String, offset: Int) -> some View {
        let calendar = Calendar.current
        let targetDay = calendar.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        let selected = calendar.isDate(date, inSameDayAs: targetDay)
        return Button {
            if let next = JobScheduleSelection.date(on: targetDay, preservingTimeFrom: date, calendar: calendar) {
                date = next
                error = nil
            } else {
                error = invalidLocalTimeMessage
            }
        } label: {
            Text(title)
                .font(Theme.font(13, weight: .medium))
                .foregroundStyle(selected ? Theme.brand : Theme.muted)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(selected ? Theme.brandSurface : Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
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
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(selected ? Theme.brand : Theme.subtle)
                    .frame(width: 20, height: 20)
                Text(label)
                    .font(Theme.monoFont(15, weight: .medium))
                    .foregroundStyle(selected ? Theme.brand : Theme.foreground)
                Spacer(minLength: 8)
                Text("2 hr window")
                    .font(Theme.font(13))
                    .foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
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
        return time.formatted(date: .omitted, time: .shortened)
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
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var session: SessionController
    @State private var records: [FieldFollowUpRecord] = []
    @State private var loading = true
    @State private var busy = false
    @State private var error: String?
    @State private var reason = ""
    @State private var nextAction = ""
    @State private var kind: FieldFollowUpRequest.Kind = .notifyOffice
    @State private var booking: FieldFollowUpRecord?
    /// Open follow-ups first, then one short form to ask the office for the next step.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Follow-ups").font(Theme.font(24, weight: .medium)).tracking(-0.36)
                    .accessibilityAddTraits(.isHeader).padding(.bottom, 12)
                if let error { ErrorBanner(message: error, retry: records.isEmpty ? { await load() } : nil).padding(.horizontal, -Theme.gutter) }
                if loading && records.isEmpty { SkeletonRows(count: 4, leading: false, inset: 0) }
                if !records.isEmpty { PaperGroupHeader(title: "On this job", count: records.count) }
                ForEach(records) { record in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(record.kind.statusLabel).font(Theme.font(12, weight: .medium)).foregroundStyle(Theme.muted)
                            Spacer()
                            PaperStatusChip(status: record.status)
                        }
                        Text(record.reason).font(Theme.font(15, weight: .medium))
                        Text("Next: \(record.nextAction)").font(Theme.font(13)).foregroundStyle(Theme.muted)
                        if let scheduling = record.scheduling {
                            Label(scheduling.appointment != nil ? "Visit booked" : "Waiting for office review",
                                  systemImage: scheduling.appointment != nil ? "calendar.badge.checkmark" : "hourglass")
                                .font(Theme.font(12)).foregroundStyle(Theme.muted)
                        }
                        if record.status == "open", session.can("job.assign", feature: "jobs") {
                            HStack(spacing: 18) {
                                if record.kind == "office_scheduling", record.scheduling?.appointment == nil {
                                    Button("Book the return visit") { booking = record }
                                        .font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.brandText)
                                        .frame(minHeight: 44).disabled(busy)
                                }
                                Button("Resolve") { Task { await resolve(record.id) } }
                                    .font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.brandText)
                                    .frame(minHeight: 44).disabled(busy)
                            }
                        }
                    }
                    .padding(14)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).stroke(Theme.border))
                    .padding(.bottom, 8)
                }
                if session.can("job.edit", feature: "jobs") {
                    PaperGroupHeader(title: "New follow-up").padding(.top, 10)
                    ThorbisSegmented(options: [
                        (FieldFollowUpRequest.Kind.notifyOffice, "Notify office"),
                        (FieldFollowUpRequest.Kind.officeScheduling, "Schedule a return visit"),
                    ], selection: $kind)
                    .padding(.bottom, 10)
                    followUpField("What happened?", text: $reason)
                    followUpField("What needs to happen next?", text: $nextAction).padding(.top, 8)
                    Text("A return-visit request goes to the office to book; it doesn't reserve a time.")
                        .font(Theme.font(12)).foregroundStyle(Theme.muted).padding(.top, 8)
                }
                if !loading && records.isEmpty && !session.can("job.edit", feature: "jobs") {
                    PaperEmptyState(symbol: "list.bullet", title: "No follow-ups", message: "Follow-ups recorded on this job appear here.")
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

    private func followUpField(_ prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text, axis: .vertical)
            .font(Theme.font(16)).lineLimit(2...5)
            .padding(12)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).stroke(Theme.border))
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
        do {
            _ = try await api.requestFieldFollowUp(jobID, request: .init(kind: kind, reason: reason.trimmingCharacters(in: .whitespacesAndNewlines), nextAction: nextAction.trimmingCharacters(in: .whitespacesAndNewlines)))
            reason = ""
            nextAction = ""
            await load()
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
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
            Form {
                Section("Arrival window") {
                    DatePicker("Day", selection: $day, in: Date()..., displayedComponents: .date)
                    DatePicker("Arrive from", selection: $start, displayedComponents: .hourAndMinute)
                    Stepper("Window: \(hours) hour\(hours == 1 ? "" : "s")", value: $hours, in: 1...8)
                }
                Section("What the visit is for") {
                    TextField("Service needed", text: $need, axis: .vertical).lineLimit(2...4)
                }
                if let result { Section { Label(result, systemImage: "checkmark.circle").foregroundStyle(Theme.success) } }
                if let error { Section { Text(error).foregroundStyle(Theme.destructive) } }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Book return visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(result == nil ? "Cancel" : "Done") { if result != nil { onDone() }; dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    if result == nil {
                        Button("Book") { Task { await book() } }
                            .disabled(busy || need.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
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

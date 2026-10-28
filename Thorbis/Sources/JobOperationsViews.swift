import SwiftUI

struct JobCloseoutView: View {
    let jobID: String
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
                    PaperEyebrow(reference: "JOB-\(jobID.suffix(4).uppercased())", text: job.map { store.customerName($0.customerId) })
                    Text(job?.status == "completed" ? "Job complete" : "Wrap up this job")
                        .font(Theme.font(24, weight: .medium)).tracking(-0.36).accessibilityAddTraits(.isHeader)
                }
                .padding(.bottom, 14)
                if let error { ErrorBanner(message: error, retry: closeout == nil ? { await load() } : nil).padding(.horizontal, -Theme.gutter) }
                if let closeout {
                    let checks = closeout.policy.requiredChecks.filter { $0.kind == nil || $0.kind == "acknowledgement" }
                    let done = closeout.requirements.filter { $0.outcome != "blocked" }.count
                        + checks.filter { closeout.facts.acknowledgedCheckKeys.contains($0.key) }.count
                    PaperGroupHeader(title: "Before you close") {
                        Text("\(done) of \(closeout.requirements.count + checks.count)").font(Theme.monoFont(12))
                    }
                    ForEach(Array(closeout.requirements.enumerated()), id: \.offset) { _, requirement in
                        let step = CloseoutNextStep(requirement)
                        HStack(spacing: 12) {
                            checklistRow(done: requirement.outcome != "blocked", title: requirement.detail, detail: step?.detail)
                            if let step, let title = step.buttonTitle, step.capabilities.allSatisfy({ session.can($0, feature: "invoicing") }) {
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
                        let acknowledged = closeout.facts.acknowledgedCheckKeys.contains(check.key)
                        HStack(spacing: 12) {
                            checklistRow(done: acknowledged, title: check.label, detail: nil)
                            if !acknowledged && session.can("job.edit", feature: "jobs") {
                                Button("Confirm") { Task { await acknowledge(check.key) } }
                                    .font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.foreground)
                                    .padding(.horizontal, 12).frame(height: Theme.chipHeight + 4)
                                    .background(Theme.fill, in: Capsule())
                                    .frame(minHeight: 44)
                                    .buttonStyle(PressStyle())
                                    .disabled(busy)
                            }
                        }
                    }
                    if closeout.requirements.isEmpty && checks.isEmpty {
                        Text("Nothing else is required before closing.").font(Theme.font(15)).foregroundStyle(Theme.muted).frame(minHeight: 44)
                    }
                    if mayRecordUnpaidDisposition {
                        PaperGroupHeader(title: "Unpaid follow-up").padding(.top, 18)
                        Picker("Reason", selection: $unpaidReasonCode) {
                            Text("Customer will pay later").tag("customer_will_pay_later")
                            Text("Office collection required").tag("office_collection_required")
                            Text("Payment attempt failed").tag("payment_attempt_failed")
                            Text("Other").tag("other")
                        }
                        .pickerStyle(.menu).frame(minHeight: 44)
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
                            NavigationLink { InvoiceDetailView(id: invoiceID) } label: { PaperMenuRow("View invoice", symbol: "doc.text") }
                                .buttonStyle(RowPressStyle())
                        }
                    }
                    if session.can("job.cancel", feature: "jobs"), job?.allowedTransitions?.contains("canceled") == true {
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
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if job?.status != "completed", session.can("job.complete", feature: "jobs"), job?.allowedTransitions?.contains("completed") == true {
                PaperActionBar(title: "Complete job", symbol: "checkmark", busy: busy, disabled: !canComplete) { confirmComplete = true }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .navigationDestination(item: $openInvoiceID) { InvoiceDetailView(id: $0) }
        .navigationDestination(isPresented: $openBilling) { BillingSchedulesView() }
        .sensoryFeedback(.success, trigger: completed)
        .confirmationDialog("Complete this job?", isPresented: $confirmComplete, titleVisibility: .visible) {
            Button("Complete job") { Task { await complete() } }
        }
        .confirmationDialog("Cancel this job?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Cancel job", role: .destructive) { Task { await cancel() } }
        }
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
        .frame(height: 44)
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
                    Picker("Request", selection: $kind) {
                        Text("Notify office").tag(FieldFollowUpRequest.Kind.notifyOffice)
                        Text("Schedule a return visit").tag(FieldFollowUpRequest.Kind.officeScheduling)
                    }
                    .pickerStyle(.segmented)
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

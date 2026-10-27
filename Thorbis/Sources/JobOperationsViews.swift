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
    @State private var confirmCancel = false
    @State private var invoiceID: String?
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
    var body: some View {
        List {
            if let error { ErrorBanner(message: error) }
            if let closeout {
                Section("Requirements") {
                    ForEach(Array(closeout.requirements.enumerated()), id: \.offset) { _, requirement in
                        VStack(alignment: .leading, spacing: 6) {
                            Label(requirement.detail, systemImage: requirement.outcome == "blocked" ? "exclamationmark.circle" : "checkmark.circle")
                            if let action = requirement.nextAction { Text(action).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    if closeout.requirements.isEmpty { Text("No additional closeout requirements") }
                }
                if session.can("job.edit", feature: "jobs") {
                    Section("Checks") {
                        ForEach(closeout.policy.requiredChecks, id: \.key) { check in
                            if check.kind == nil || check.kind == "acknowledgement" {
                                if closeout.facts.acknowledgedCheckKeys.contains(check.key) {
                                    Label(check.label, systemImage: "checkmark.circle.fill").foregroundStyle(Theme.success)
                                } else {
                                    Button("Confirm: \(check.label)") { Task { await acknowledge(check.key) } }.disabled(busy)
                                }
                            }
                        }
                    }
                }
                if mayRecordUnpaidDisposition {
                    Section("Unpaid follow-up") {
                        Picker("Reason", selection: $unpaidReasonCode) {
                            Text("Customer will pay later").tag("customer_will_pay_later")
                            Text("Office collection required").tag("office_collection_required")
                            Text("Payment attempt failed").tag("payment_attempt_failed")
                            Text("Other").tag("other")
                        }
                        TextField("Explain the unpaid balance", text: $unpaidReason, axis: .vertical)
                        TextField("Office follow-up action", text: $unpaidNextAction, axis: .vertical)
                        Text("Completing with this disposition leaves payment outstanding and creates an office follow-up.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Completion") {
                    if job?.status == "completed" {
                        Label("Job completed", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.success)
                        if session.can("invoice.create", feature: "invoicing") {
                            Button("Open completion invoice") { Task { await completionInvoice() } }.disabled(busy)
                        }
                    } else if session.can("job.complete", feature: "jobs"), job?.allowedTransitions?.contains("completed") == true {
                        Button("Complete job") { confirmComplete = true }.disabled(busy || (!closeout.completable && !validDisposition))
                    }
                    if let invoiceID, session.can("invoice.view", feature: "invoicing") {
                        NavigationLink("View invoice") { InvoiceDetailView(id: invoiceID) }
                    }
                    if session.can("job.cancel", feature: "jobs"), job?.allowedTransitions?.contains("canceled") == true {
                        Button("Cancel job", role: .destructive) { confirmCancel = true }.disabled(busy)
                    }
                    if busy { ProgressView() }
                }
            } else if error == nil { ProgressView("Loading closeout…") }
        }
        .navigationTitle("Closeout")
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog("Complete this job?", isPresented: $confirmComplete, titleVisibility: .visible) {
            Button("Complete job") { Task { await complete() } }
        }
        .confirmationDialog("Cancel this job?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Cancel job", role: .destructive) { Task { await cancel() } }
        }
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
                                .font(Theme.font(14))
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
                            .font(Theme.font(14, weight: .medium))
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
        .presentationCornerRadius(20)
        .presentationBackground(Theme.card)
        .interactiveDismissDisabled(busy)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 44, height: 44)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            Text("Schedule")
                .font(Theme.font(17, weight: .semibold))
                .tracking(-0.17)
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(Theme.fill, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .medium))
                        .rotationEffect(.degrees(showsCalendar ? 180 : 0))
                }
                .font(Theme.font(13, weight: showsCalendar ? .semibold : .medium))
                .foregroundStyle(showsCalendar ? Theme.brand : Theme.muted)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(showsCalendar ? Theme.brandSurface : Theme.fill, in: RoundedRectangle(cornerRadius: 8))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
                .font(Theme.font(13, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? Theme.brand : Theme.muted)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(selected ? Theme.brandSurface : Theme.fill, in: RoundedRectangle(cornerRadius: 8))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                    .font(Theme.monoFont(14, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Theme.brand : Theme.foreground)
                Spacer(minLength: 8)
                Text("2 hr window")
                    .font(Theme.font(13))
                    .foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
    var body: some View {
        List {
            if let error { ErrorBanner(message: error) }
            if loading { ProgressView() }
            ForEach(records) { record in
                Section(record.kind.statusLabel) {
                    Text(record.reason).font(.headline)
                    Text(record.nextAction)
                    LabeledContent("Status", value: record.status.statusLabel)
                    if let scheduling = record.scheduling {
                        Text(scheduling.appointment != nil ? "Visit booked" : "Office review required").foregroundStyle(.secondary)
                    }
                    if record.status == "open", session.can("job.assign", feature: "jobs") {
                        Button("Resolve follow-up") { Task { await resolve(record.id) } }.disabled(busy)
                    }
                }
            }
            if session.can("job.edit", feature: "jobs") {
                Section("New follow-up") {
                    Picker("Request", selection: $kind) {
                        Text("Notify office").tag(FieldFollowUpRequest.Kind.notifyOffice)
                        Text("Ask office to schedule").tag(FieldFollowUpRequest.Kind.officeScheduling)
                    }
                    TextField("Reason", text: $reason, axis: .vertical)
                    TextField("Next action", text: $nextAction, axis: .vertical)
                    Text("A scheduling request goes to the office for review. It does not reserve an appointment.").font(.caption).foregroundStyle(.secondary)
                    Button("Create follow-up") { Task { await create() } }
                        .disabled(busy || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || nextAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reason.utf16.count > 2000 || nextAction.utf16.count > 2000)
                }
            }
        }
        .navigationTitle("Follow-ups")
        .task { await load() }
        .refreshable { await load() }
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

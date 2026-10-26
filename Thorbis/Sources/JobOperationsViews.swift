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
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var session: SessionController
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @State private var date = Date()
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        Form {
            DatePicker("Scheduled for", selection: $date)
            LabeledContent("Time zone", value: TimeZone.current.identifier)
            if let error { Text(error).foregroundStyle(Theme.destructive) }
            Button("Save schedule") { Task { await save() } }.disabled(busy || !session.can("job.assign", feature: "jobs"))
            if busy { ProgressView() }
        }
        .navigationTitle("Schedule job")
        .onAppear { date = JobFiltering.date(job.scheduledFor) ?? Date() }
    }
    private func save() async {
        busy = true
        defer { busy = false }
        do {
            _ = try await api.scheduleFieldJob(job.id, request: .init(scheduledFor: ISO8601DateFormatter().string(from: date), timeZone: TimeZone.current.identifier, expectedPrior: job.scheduledFor.map(FieldExpectedSchedule.at) ?? .unscheduled))
            await store.refresh(api)
            dismiss()
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
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

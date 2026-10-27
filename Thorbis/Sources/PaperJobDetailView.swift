import SwiftUI
import UIKit

struct JobDetailView: View {
    let jobId: String
    let showsBack: Bool

    init(jobId: String, showsBack: Bool = true) {
        self.jobId = jobId
        self.showsBack = showsBack
        #if DEBUG
        _selectedTab = State(initialValue: PaperPreview.enabled && PaperPreview.screen == "job-invoice" ? "Invoice" : "Overview")
        #endif
    }
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var store: Store
    @EnvironmentObject var session: SessionController
    @Environment(\.dismiss) private var dismiss
    @State private var job: JobRecord?
    @State private var notes: [JobNoteRecord] = []
    @State private var note = ""
    @State private var reason = ""
    @State private var nextAction = ""
    @State private var showPause = false
    @State private var busy = false
    @State private var error: String?
    @State private var selectedTab = "Overview"
    @State private var invoices: [InvoiceRecord] = []
    @State private var invoicesLoaded = false
    @State private var selectedInvoiceID: String?
    @State private var invoicePaymentModel: InvoicePaymentCollectionModel?
    @State private var loadedInvoiceModelID: String?
    @State private var showCollectPayment = false
    @State private var activityFilter = "All"
    @State private var showSchedule = false

    private let tabs = ["Overview", "Estimates", "Invoice", "Media", "Activity"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            if let error { ErrorBanner(message: error).padding(.horizontal, 20).padding(.top, 12) }
            if let job {
                if selectedTab == "Media" {
                    header(job, compact: true)
                    tabBar
                    JobMediaView(jobID: jobId)
                } else {
                    ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                    header(job)
                    tabBar
                    VStack(alignment: .leading, spacing: 16) {
                        switch selectedTab {
                        case "Estimates": estimatesContent(job)
                        case "Invoice": invoiceContent(job)
                        case "Activity": activityContent(job)
                        default: overviewContent(job)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, selectedTab == "Invoice" ? 4 : 22)
                    .padding(.bottom, 28)
                    }
                    }
                }
            } else if error == nil {
                ProgressView("Loading job…")
                    .frame(maxWidth: .infinity, minHeight: 240)
            }
        }
        .background(Theme.background)
        .foregroundStyle(Theme.foreground)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .task(id: session.generation) {
            invoicePaymentModel = nil
            loadedInvoiceModelID = nil
            await load()
            if selectedTab == "Invoice" { await loadInvoices() }
        }
        .refreshable {
            if selectedTab == "Invoice" { await loadInvoices() }
            else { await load() }
        }
        .onChange(of: selectedTab) { _, tab in
            if tab == "Invoice" { Task { await loadInvoices() } }
        }
        .onChange(of: selectedInvoiceID) { _, selectedID in
            guard let selectedID, let invoice = invoices.first(where: { $0.id == selectedID }) else { return }
            Task { await loadInvoicePayments(for: invoice) }
        }
        .safeAreaInset(edge: .bottom) {
            if selectedTab == "Overview", let job, let target = availableTransitions(job).first {
                PrimaryButton(title: transitionTitle(target), icon: "arrow.right", busy: busy) {
                    runTransition(target)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(Theme.chrome)
            } else if selectedTab == "Invoice",
                      session.can("invoice.payment.create", feature: "payments"),
                      let invoice = selectedInvoice,
                      let model = invoicePaymentModel,
                      loadedInvoiceModelID == invoice.id {
                PaperInvoiceCollectionFooter(model: model) { showCollectPayment = true }
            }
        }
        .sheet(isPresented: $showPause) {
            NavigationStack {
                Form {
                    TextField("Why are you pausing?", text: $reason, axis: .vertical)
                    TextField("What needs to happen next?", text: $nextAction, axis: .vertical)
                    if let error { Text(error).foregroundStyle(Theme.destructive) }
                    Button("Pause job") { Task { await pause() } }
                        .disabled(busy || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || nextAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reason.utf16.count > 2000 || nextAction.utf16.count > 2000)
                }
                .navigationTitle("Pause job")
                .toolbar { Button("Cancel") { showPause = false }.disabled(busy) }
            }
        }
        .sheet(isPresented: $showSchedule, onDismiss: { Task { await load() } }) {
            if let job {
                JobScheduleView(job: job) { updatedJob in
                    self.job = updatedJob
                }
            }
        }
        .sheet(isPresented: $showCollectPayment) {
            if let invoice = selectedInvoice, let model = invoicePaymentModel {
                InvoicePaymentCollectionSheet(model: model, invoice: model.invoice ?? invoice)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private var topBar: some View {
        HStack {
            if showsBack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 38, height: 38)
                        .background(Theme.fill, in: Circle())
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Back")
            }
            Spacer()
            if let job {
                ShareLink(item: "\(job.title) · \(job.id)") {
                    Image(systemName: "square.and.arrow.up")
                        .frame(width: 38, height: 38)
                        .background(Theme.fill, in: Circle())
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Share job")
                Menu {
                    Button("Copy job ID", systemImage: "doc.on.doc") { UIPasteboard.general.string = job.id }
                    NavigationLink("Closeout") { JobCloseoutView(jobID: jobId).toolbar(.visible, for: .navigationBar) }
                    NavigationLink("Follow-ups") { JobFollowUpsView(jobID: jobId).toolbar(.visible, for: .navigationBar) }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 38, height: 38)
                        .background(Theme.fill, in: Circle())
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("More job actions")
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 16))
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    private func header(_ job: JobRecord, compact: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("JOB-\(job.id.suffix(4).uppercased()) · \(store.customerName(job.customerId))")
                .font(Theme.monoFont(12, weight: .medium))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
            Text(job.title)
                .font(Theme.font(26, weight: .semibold))
                .tracking(-0.39)
                .lineLimit(compact ? 2 : nil)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    statusControl(job)
                    if let date = JobFiltering.date(job.scheduledFor) {
                        Label(scheduleLabel(date), systemImage: "clock")
                            .font(Theme.font(13, weight: .medium))
                            .foregroundStyle(Theme.muted)
                            .padding(.horizontal, 10)
                            .frame(height: 34)
                            .background(Theme.fill, in: Capsule())
                    }
                }

                HStack(spacing: 8) {
                    if let assignedName = assignedDisplayName(for: job) {
                        HStack(spacing: 7) {
                            Text(nameInitials(assignedName))
                                .font(Theme.font(10, weight: .semibold))
                                .foregroundStyle(Theme.brand)
                                .frame(width: 24, height: 24)
                                .background(Theme.brandSurface, in: Circle())
                            Text(shortName(assignedName))
                                .font(Theme.font(13, weight: .medium))
                                .foregroundStyle(Theme.muted)
                        }
                        .padding(.horizontal, 7)
                        .frame(height: 34)
                        .background(Theme.fill, in: Capsule())
                    }
                    if let balance = invoiceBalanceCents {
                        Text("\(money(balance, currency: "USD")) due")
                            .font(Theme.monoFont(12, weight: .medium))
                            .foregroundStyle(Theme.muted)
                            .padding(.horizontal, 10)
                            .frame(height: 34)
                            .background(Theme.fill, in: Capsule())
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private func statusControl(_ job: JobRecord) -> some View {
        let tint = job.status == "completed" ? Theme.success : Theme.warning
        let surface = job.status == "completed" ? Theme.successSurface : Theme.warningSurface
        let transitions = availableTransitions(job)
        if transitions.isEmpty {
            statusChip(job, tint: tint, surface: surface, showsMenu: false)
        } else {
            Menu {
                ForEach(transitions, id: \.self) { target in
                    Button(transitionTitle(target)) { runTransition(target) }
                }
            } label: {
                statusChip(job, tint: tint, surface: surface, showsMenu: true)
            }
            .buttonStyle(.plain)
        }
    }

    private func statusChip(_ job: JobRecord, tint: Color, surface: Color, showsMenu: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: job.status == "completed" ? "checkmark.circle" : "clock")
                .font(.system(size: 13, weight: .medium))
            Text(job.status.statusLabel)
                .font(Theme.font(13, weight: .medium))
            if showsMenu { Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)) }
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(surface, in: Capsule())
        .contentShape(Capsule())
        .accessibilityLabel("Job status, \(job.status.statusLabel)")
    }

    private func scheduleLabel(_ date: Date) -> String {
        let time = date.formatted(.dateTime.hour().minute())
        if Calendar.current.isDateInToday(date) { return "Today · \(time)" }
        return "\(date.formatted(.dateTime.weekday())) · \(time)"
    }

    private func assignedDisplayName(for job: JobRecord) -> String? {
        guard let assignedID = job.assignedToUserId else { return nil }
        guard assignedID == session.user?.id, let name = session.user?.name, !name.isEmpty else { return "Assigned" }
        return name
    }

    private func shortName(_ name: String) -> String {
        let parts = name.split(whereSeparator: \.isWhitespace)
        guard let first = parts.first else { return name }
        guard let last = parts.dropFirst().last else { return String(first) }
        return "\(first) \(last.prefix(1))."
    }

    private func nameInitials(_ name: String) -> String {
        String(name.split(whereSeparator: \.isWhitespace).prefix(2).compactMap(\.first))
    }

    private var invoiceBalanceCents: Int? {
        let issued = invoices.filter { $0.status == "issued" && $0.currency == "USD" }
        guard !issued.isEmpty else { return nil }
        var balanceTotal = 0
        for invoice in issued {
            var invoiceTotal = 0
            for line in invoice.lines {
                guard line.quantity >= 0, line.unitPrice.amount >= 0,
                      line.unitPrice.currency == invoice.currency else { return nil }
                let (lineTotal, lineOverflow) = line.quantity.multipliedReportingOverflow(by: line.unitPrice.amount)
                let (nextTotal, sumOverflow) = invoiceTotal.addingReportingOverflow(lineTotal)
                guard !lineOverflow, !sumOverflow else { return nil }
                invoiceTotal = nextTotal
            }
            let (due, dueOverflow) = invoiceTotal.subtractingReportingOverflow(invoice.amountPaid)
            guard !dueOverflow, due >= 0 else { return nil }
            let (nextBalance, balanceOverflow) = balanceTotal.addingReportingOverflow(due)
            guard !balanceOverflow else { return nil }
            balanceTotal = nextBalance
        }
        return balanceTotal
    }

    private var tabBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(tabs, id: \.self) { tab in
                    Button { selectedTab = tab } label: {
                        Text(tab)
                            .font(Theme.font(13, weight: selectedTab == tab ? .semibold : .medium))
                            .foregroundStyle(selectedTab == tab ? Theme.foreground : Theme.muted)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(selectedTab == tab ? Theme.fill : .clear, in: Capsule())
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
        }
        .scrollIndicators(.hidden)
    }

    private func overviewContent(_ job: JobRecord) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Details")
            if let detail = job.notes, !detail.isEmpty {
                Text(detail)
                    .font(Theme.font(14))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(15)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
            }
            VStack(spacing: 0) {
                detailRow("Customer", store.customerName(job.customerId))
                if let date = JobFiltering.date(job.scheduledFor) { detailRow("Scheduled", date.formatted()) }
                if let reason = job.pauseReason { detailRow("Pause reason", reason) }
                if let next = job.pauseNextAction { detailRow("Next action", next) }
            }
            .padding(.horizontal, 15)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
            sectionTitle("Related work")
            VStack(spacing: 0) {
                ForEach(availableTransitions(job).dropFirst(), id: \.self) { target in
                    actionButton(transitionTitle(target), icon: "arrow.right") { runTransition(target) }
                }
                NavigationLink { JobCloseoutView(jobID: jobId).toolbar(.visible, for: .navigationBar) } label: { actionLabel("Closeout", icon: "checkmark.circle") }
                NavigationLink { JobFollowUpsView(jobID: jobId).toolbar(.visible, for: .navigationBar) } label: { actionLabel("Follow-ups", icon: "list.bullet") }
                if session.can("job.assign", feature: "jobs") {
                    Button { showSchedule = true } label: { actionLabel("Schedule job", icon: "calendar") }
                    NavigationLink { JobAssignmentView(jobID: jobId).toolbar(.visible, for: .navigationBar) } label: { actionLabel("Assign job", icon: "person.crop.circle.badge.plus") }
                }
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func estimatesContent(_ job: JobRecord) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            sectionTitle("Estimates")
            if let estimateID = job.estimateId, session.can("estimate.view", feature: "estimates") {
                NavigationLink { EstimateDetailView(id: estimateID).toolbar(.visible, for: .navigationBar) } label: {
                    actionLabel("View linked estimate", icon: "doc.text")
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                }
            } else {
                emptyCard("No linked estimate is available for this job.")
            }
        }
    }

    private func invoiceContent(_ job: JobRecord) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            if !session.can("invoice.view", feature: "invoicing") {
                emptyCard("Invoice access is unavailable.")
            } else if !invoicesLoaded {
                ProgressView("Loading invoices…").frame(maxWidth: .infinity).padding(30)
            } else if invoices.isEmpty {
                emptyCard("No invoice is linked to this job.")
            } else {
                if invoices.count > 1 {
                    Menu {
                        ForEach(invoices) { invoice in
                            Button("INV-\(invoice.id.suffix(4).uppercased()) · \(invoice.status.statusLabel)") {
                                selectedInvoiceID = invoice.id
                            }
                        }
                    } label: {
                        HStack(spacing: 7) {
                            Text("INV-\((selectedInvoice?.id ?? invoices[0].id).suffix(4).uppercased())")
                                .font(Theme.monoFont(12, weight: .medium))
                            Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 36)
                        .background(Theme.fill, in: Capsule())
                    }
                }
                if let invoice = selectedInvoice {
                    if let model = invoicePaymentModel, loadedInvoiceModelID == invoice.id {
                        PaperJobInvoiceContent(
                            invoice: invoice,
                            paymentModel: model,
                            onCollectPayment: { showCollectPayment = true },
                            onInvoiceUpdated: updateInvoice
                        )
                    } else {
                        ProgressView("Loading invoice…")
                            .frame(maxWidth: .infinity, minHeight: 100)
                    }
                }
            }
        }
    }

    private var selectedInvoice: InvoiceRecord? {
        if let selectedInvoiceID, let selected = invoices.first(where: { $0.id == selectedInvoiceID }) {
            return selected
        }
        return invoices.first
    }

    private func updateInvoice(_ updated: InvoiceRecord) {
        guard let index = invoices.firstIndex(where: { $0.id == updated.id }) else { return }
        invoices[index] = updated
    }

    private func activityContent(_ job: JobRecord) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            sectionTitle("Activity")
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(["All", "Notes", "Status"], id: \.self) { filter in
                        Button { activityFilter = filter } label: {
                            Text(filter)
                                .font(Theme.font(12, weight: activityFilter == filter ? .semibold : .medium))
                                .foregroundStyle(activityFilter == filter ? Theme.foreground : Theme.muted)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .background(activityFilter == filter ? Theme.fill : Theme.card, in: Capsule())
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
            if activityFilter != "Status" {
                ForEach(notes) { record in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(record.body).font(Theme.font(14))
                        if let date = JobFiltering.date(record.createdAt) {
                            Text(date.formatted()).font(Theme.font(11)).foregroundStyle(Theme.muted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(15)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            if activityFilter != "Notes" {
                ForEach(statusEvents(job), id: \.0) { event in
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle").foregroundStyle(Theme.brand)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(event.0).font(Theme.font(14, weight: .medium))
                            Text(event.1.formatted()).font(Theme.font(11)).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                    }
                    .padding(15)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            if notes.isEmpty && statusEvents(job).isEmpty { emptyCard("No activity yet.") }
            if session.can("job.note", feature: "jobs") {
                TextField("Add a note", text: $note, axis: .vertical)
                    .lineLimit(3...8)
                    .padding(13)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                PrimaryButton(title: "Save note", busy: busy) { Task { await saveNote() } }
                    .disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || note.utf16.count > 10_000)
            }
        }
    }

    private func statusEvents(_ job: JobRecord) -> [(String, Date)] {
        let raw: [(String, String?)] = [
            ("Job created", job.createdAt),
            ("Dispatched", job.dispatchedAt),
            ("En route", job.enRouteAt),
            ("Arrived", job.arrivedAt),
            ("Work started", job.startedAt),
            ("Paused", job.pausedAt),
            ("Completed", job.completedAt),
            ("Canceled", job.canceledAt)
        ]
        return raw.compactMap { label, value in
            value.flatMap(JobFiltering.date).map { (label, $0) }
        }
        .sorted { $0.1 > $1.1 }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(Theme.font(16, weight: .semibold))
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(label).foregroundStyle(Theme.muted).frame(width: 95, alignment: .leading)
            Text(value).foregroundStyle(Theme.foreground).frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .font(Theme.font(13))
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actionLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(Theme.brand).frame(width: 20)
            Text(title).font(Theme.font(14, weight: .medium))
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.muted)
        }
        .foregroundStyle(Theme.foreground)
        .padding(15)
        .contentShape(Rectangle())
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { actionLabel(title, icon: icon) }
            .buttonStyle(.plain)
            .disabled(busy)
    }

    private func emptyCard(_ message: String) -> some View {
        Text(message).font(Theme.font(13)).foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private func availableTransitions(_ job: JobRecord) -> [String] {
        (job.allowedTransitions ?? []).filter {
            ["scheduled", "dispatched", "en_route", "arrived", "in_progress", "paused"].contains($0)
                && session.can(["scheduled", "dispatched"].contains($0) ? "job.assign" : "job.edit", feature: "jobs")
        }
    }

    private func transitionTitle(_ target: String) -> String {
        target == "paused" ? "Pause job…" : "Mark \(target.statusLabel.lowercased())"
    }

    private func runTransition(_ target: String) {
        if target == "paused" { showPause = true }
        else { Task { await advance(target) } }
    }

    private func loadInvoices() async {
        guard session.can("invoice.view", feature: "invoicing") else { return }
        let generation = session.generation
        do {
            let all = try await api.fieldInvoices()
            guard session.generation == generation else { return }
            invoices = all.filter { $0.jobId == jobId }
                .sorted { $0.createdAt > $1.createdAt }
            invoicesLoaded = true
            if let selectedInvoice {
                selectedInvoiceID = selectedInvoice.id
                await loadInvoicePayments(for: selectedInvoice)
            }
        } catch is CancellationError {} catch {
            guard session.generation == generation else { return }
            self.error = error.localizedDescription
            invoicesLoaded = true
        }
    }

    private func loadInvoicePayments(for invoice: InvoiceRecord) async {
        guard session.can("invoice.view", feature: "invoicing") else { return }
        if loadedInvoiceModelID != invoice.id {
            loadedInvoiceModelID = invoice.id
            invoicePaymentModel = InvoicePaymentCollectionModel(api: api, invoiceID: invoice.id)
        }
        await invoicePaymentModel?.load()
    }
    private func load() async {
        let generation = session.generation
        do {
            let loadedJob = try await api.fieldJob(jobId)
            guard session.generation == generation else { return }
            job = loadedJob
            let loadedNotes = try await api.fieldNotes(jobId)
            guard session.generation == generation else { return }
            notes = loadedNotes
            error = nil
        } catch is CancellationError {} catch {
            guard session.generation == generation else { return }
            self.error = error.localizedDescription
        }
    }
    private func advance(_ target: String) async {
        let request: FieldProgressRequest
        switch target {
        case "scheduled": request = .scheduled
        case "dispatched": request = .dispatched
        case "en_route": request = .enRoute()
        case "arrived": request = .arrived()
        case "in_progress":
            if job?.status == "paused", let auditID = job?.pauseCycleAuditId, session.can("job.edit", feature: "job_pause_cycle_resume") {
                request = .resume(expectedPauseAuditId: auditID)
            } else { request = .start }
        default: return
        }
        await progress(request)
    }
    private func pause() async {
        if await progress(.pause(reason: reason.trimmingCharacters(in: .whitespacesAndNewlines), nextAction: nextAction.trimmingCharacters(in: .whitespacesAndNewlines))) {
            showPause = false
            reason = ""
            nextAction = ""
        }
    }
    @discardableResult private func progress(_ request: FieldProgressRequest) async -> Bool {
        busy = true
        defer { busy = false }
        do {
            job = try await api.progressFieldJob(jobId, request: request)
            await store.refresh(api)
            error = nil
            return true
        } catch is CancellationError { return false } catch { self.error = error.localizedDescription; return false }
    }
    private func saveNote() async {
        busy = true
        defer { busy = false }
        do {
            let saved = try await api.addFieldNote(jobId, body: note.trimmingCharacters(in: .whitespacesAndNewlines))
            notes.append(saved)
            note = ""
            error = nil
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}

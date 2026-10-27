import SwiftUI
import UIKit

struct JobDetailView: View {
    let jobId: String
    let showsBack: Bool

    init(jobId: String, showsBack: Bool = true) {
        self.jobId = jobId
        self.showsBack = showsBack
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
    @State private var activityFilter = "All"

    private let tabs = ["Overview", "Estimates", "Invoice", "Media", "Activity"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            if let error { ErrorBanner(message: error).padding(.horizontal, 20).padding(.top, 12) }
            if let job {
                header(job)
                tabBar
                if selectedTab == "Media" {
                    JobMediaView(jobID: jobId)
                } else {
                    ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch selectedTab {
                        case "Estimates": estimatesContent(job)
                        case "Invoice": invoiceContent(job)
                        case "Activity": activityContent(job)
                        default: overviewContent(job)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 22)
                    .padding(.bottom, 28)
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
        .task(id: session.generation) { await load() }
        .refreshable { await load() }
        .onChange(of: selectedTab) { _, tab in
            if tab == "Invoice" { Task { await loadInvoices() } }
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
    }

    private var topBar: some View {
        HStack {
            if showsBack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 38, height: 38)
                        .background(Theme.fill, in: Circle())
                }
                .accessibilityLabel("Back")
            }
            Spacer()
            if let job {
                ShareLink(item: "\(job.title) · \(job.id)") {
                    Image(systemName: "square.and.arrow.up")
                        .frame(width: 38, height: 38)
                        .background(Theme.fill, in: Circle())
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

    private func header(_ job: JobRecord) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("JOB-\(job.id.suffix(4).uppercased()) · \(store.customerName(job.customerId))")
                .font(Theme.monoFont(12, weight: .medium))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
            Text(job.title)
                .font(Theme.font(26, weight: .semibold))
                .tracking(-0.39)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Text(job.status.statusLabel)
                    .foregroundStyle(job.status == "completed" ? Theme.success : Theme.warning)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(job.status == "completed" ? Theme.successSurface : Theme.warningSurface, in: RoundedRectangle(cornerRadius: 8))
                if let date = JobFiltering.date(job.scheduledFor) {
                    Label(date.formatted(.dateTime.weekday().hour().minute()), systemImage: "calendar")
                }
                if job.assignedToUserId != nil { Label("Assigned", systemImage: "person") }
            }
            .font(Theme.font(11, weight: .medium))
            .foregroundStyle(Theme.muted)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 16)
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
                    NavigationLink { JobScheduleView(job: job).toolbar(.visible, for: .navigationBar) } label: { actionLabel("Schedule job", icon: "calendar") }
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
            sectionTitle("Invoice")
            if !session.can("invoice.view", feature: "invoicing") {
                emptyCard("Invoice access is unavailable.")
            } else if !invoicesLoaded {
                ProgressView("Loading invoices…").frame(maxWidth: .infinity).padding(30)
            } else if invoices.isEmpty {
                emptyCard("No invoice is linked to this job.")
            } else {
                ForEach(invoices) { invoice in
                    NavigationLink { InvoiceDetailView(id: invoice.id).toolbar(.visible, for: .navigationBar) } label: {
                        actionLabel("Invoice · \(invoice.status.statusLabel)", icon: "doc.text")
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
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
            invoicesLoaded = true
        } catch is CancellationError {} catch {
            guard session.generation == generation else { return }
            self.error = error.localizedDescription
            invoicesLoaded = true
        }
    }
    private func load() async {
        let generation = session.generation
        do {
            let loadedJob = try await api.fieldJob(jobId)
            guard session.generation == generation else { return }
            let loadedNotes = try await api.fieldNotes(jobId)
            guard session.generation == generation else { return }
            job = loadedJob
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

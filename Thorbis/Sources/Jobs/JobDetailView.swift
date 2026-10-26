import PhotosUI
import SwiftUI
import ThorbisCore

/// The job record: next step first, then everything a technician needs on site.
/// Action legality is the server's `allowedTransitions`; nothing here re-derives it.
struct JobDetailView: View {
    @Environment(AppModel.self) private var model
    let jobId: String

    @State private var job: Job?
    @State private var notes: [JobNote] = []
    @State private var notesError: String?
    @State private var photosError: String?
    @State private var photos: [JobPhoto] = []
    @State private var locations: [ServiceLocation] = []
    @State private var loading = false
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var busyAction: JobAction?
    @State private var succeeded = 0

    @State private var pausing = false
    @State private var completing = false
    @State private var confirmingCancel = false
    @State private var scheduling = false
    @State private var assigning = false
    @State private var addingNote = false

    private var current: Job? { job ?? model.cached(job: jobId) }
    private var allowed: [JobStatus] { job?.allowedTransitions ?? [] }
    private var invoice: Invoice? { model.invoices.first { $0.jobId == jobId } }

    var body: some View {
        Group {
            if let job = current {
                content(job)
            } else if let loadError {
                ContentUnavailableView {
                    Label("Couldn't open this job", systemImage: "wrench.and.screwdriver")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Try again") { Task { await load() } }.buttonStyle(.rim).fixedSize()
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.canvas)
        .navigationTitle(current?.reference ?? "Job")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: jobId) { await load() }
        .refreshable { await load() }
        .sensoryFeedback(.success, trigger: succeeded)
    }

    @ViewBuilder
    private func content(_ job: Job) -> some View {
        List {
            if let loadError {
                // Cached content stays visible, but actions depend on a fresh detail read.
                Section {
                    InlineError(message: "Couldn't refresh this job, so its actions may be missing. \(loadError)") {
                        await reloadJob()
                    }
                    .sheetRow()
                }
            }
            Section {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    StatusBadge(job.status)
                    Text(job.title)
                        .font(.title2.weight(.medium))
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    NavigationLink(value: Route.customer(job.customerId)) {
                        Text(model.customerName(job.customerId)).font(.body).foregroundStyle(Theme.inkSecondary)
                    }
                }
                .padding(.vertical, Theme.Space.xs)
                .sheetRow()

                if job.status == .paused, let reason = job.pauseReason {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Label("Paused: \(reason)", systemImage: "pause.circle").foregroundStyle(Theme.ink)
                        if let next = job.pauseNextAction {
                            Text("Next: \(next)").font(.subheadline).foregroundStyle(Theme.inkSecondary)
                        }
                    }
                    .sheetRow()
                }

                actions(job)
            }

            if let actionError {
                Section { InlineError(message: actionError).sheetRow() }
            }

            Section("Appointment") {
                Button { scheduling = true } label: {
                    DetailRow(
                        label: "When",
                        value: job.scheduledDate.map { "\(Format.dayTitle($0)) at \(Format.time($0))" } ?? "Not scheduled",
                        symbol: "calendar"
                    )
                }
                .disabled(job.status.isTerminal)
                .sheetRow()
                Button { assigning = true } label: {
                    DetailRow(label: "Technician", value: model.assigneeName(job.assignedToUserId) ?? "Unassigned", symbol: "person")
                }
                .disabled(job.status.isTerminal)
                .sheetRow()
            }

            siteSection(job)

            if let text = job.notes, !text.isEmpty {
                Section("Description") {
                    Text(text).foregroundStyle(Theme.ink).textSelection(.enabled).sheetRow()
                }
            }

            Section {
                if let notesError {
                    InlineError(message: notesError) { await loadNotes() }.sheetRow()
                } else if notes.isEmpty {
                    Text("No notes yet.").foregroundStyle(Theme.inkQuiet).sheetRow()
                }
                ForEach(notes) { note in
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text(note.body).foregroundStyle(Theme.ink).textSelection(.enabled)
                        Text("\(model.assigneeName(note.authorUserId) ?? "Team") · \(Format.relative(Timestamp.parse(note.createdAt)))")
                            .font(.footnote)
                            .foregroundStyle(Theme.inkQuiet)
                    }
                    .sheetRow()
                }
                Button { addingNote = true } label: {
                    Label("Add note", systemImage: "square.and.pencil").frame(minHeight: Theme.minimumHit)
                }
                .accessibilityIdentifier("add-note")
                .sheetRow()
            } header: {
                Text("Notes")
            } footer: {
                Text("Notes are a running log. They can't be edited or deleted; add a new note to correct one.")
            }

            JobPhotosSection(jobId: job.id, photos: $photos, loadError: photosError) { await loadPhotos() }

            Section("Timeline") {
                ForEach(JobWorkflow.milestones(job)) { milestone in
                    DetailRow(label: milestone.title, value: "\(Format.dayTitle(milestone.at)) \(Format.time(milestone.at))")
                        .sheetRow()
                }
            }

            invoiceSection(job)
        }
        .thorbisList()
        .sheet(isPresented: $pausing) {
            PauseJobSheet { details in await progress(.paused, pause: details) }
        }
        .sheet(isPresented: $completing) {
            CompleteJobSheet(job: job) { notes in await complete(notes: notes) }
        }
        .sheet(isPresented: $scheduling) {
            ScheduleJobSheet(job: job) { updated in apply(updated) }
        }
        .sheet(isPresented: $assigning) {
            AssignJobSheet(job: job) { updated in apply(updated) }
        }
        .sheet(isPresented: $addingNote) {
            AddNoteSheet(jobId: job.id) { note in notes.append(note) }
        }
        .confirmationDialog("Cancel this job?", isPresented: $confirmingCancel, titleVisibility: .visible) {
            Button("Cancel job", role: .destructive) { Task { await cancel() } }
            Button("Keep job", role: .cancel) {}
        } message: {
            Text("The customer's appointment is released. This can't be undone from the app.")
        }
    }

    @ViewBuilder
    private func actions(_ job: Job) -> some View {
        let primary = JobWorkflow.primaryAction(status: job.status, allowed: allowed)
        let secondary = JobWorkflow.secondaryActions(status: job.status, allowed: allowed)
        if primary != nil || !secondary.isEmpty {
            VStack(spacing: Theme.Space.m) {
                if let primary {
                    CommitButton(title: primary.title, symbol: primary.symbol, busy: busyAction == primary) { perform(primary) }
                        .accessibilityIdentifier("primary-action")
                }
                if !secondary.isEmpty {
                    Menu {
                        ForEach(secondary) { action in
                            Button(role: action.isDestructive ? .destructive : nil) { perform(action) } label: {
                                Label(action.title, systemImage: action.symbol)
                            }
                        }
                    } label: {
                        Label("More actions", systemImage: "ellipsis.circle").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.rim)
                    .accessibilityIdentifier("more-actions")
                }
            }
            .padding(.vertical, Theme.Space.xs)
            .sheetRow()
        }
    }

    @ViewBuilder
    private func siteSection(_ job: Job) -> some View {
        let customer = model.customer(job.customerId)
        let site = locations.first { $0.kind == .service } ?? locations.first
        let address = site?.address ?? customer?.address
        if address != nil || customer?.phone != nil || customer?.email != nil {
            Section("Site") {
                if let address {
                    Button {
                        Task { _ = await OutboundLink.directions(to: address, name: customer?.name ?? job.title) }
                    } label: {
                        Label(address, systemImage: "mappin.and.ellipse").foregroundStyle(Theme.ink)
                    }
                    .accessibilityHint("Opens directions in Maps")
                    .sheetRow()
                }
                if let site {
                    ForEach(site.accessNotes) { item in
                        DetailRow(label: item.label, value: item.value).sheetRow()
                    }
                    if let notes = site.notes { Text(notes).font(.subheadline).foregroundStyle(Theme.inkSecondary).sheetRow() }
                }
                ContactActions(phone: customer?.phone, email: customer?.email).sheetRow()
            }
        }
    }

    @ViewBuilder
    private func invoiceSection(_ job: Job) -> some View {
        if let invoice {
            Section("Invoice") {
                NavigationLink(value: Route.invoice(invoice.id)) {
                    HStack {
                        Text(invoice.reference).font(.body.monospaced())
                        Spacer()
                        MoneyText(cents: invoice.total, currency: invoice.currency)
                        StatusBadge(invoice.status)
                    }
                }
                .sheetRow()
            }
        } else if job.status == .completed {
            Section("Invoice") {
                Button {
                    Task { await createInvoice() }
                } label: {
                    Label("Create invoice from this job", systemImage: "doc.badge.plus").frame(minHeight: Theme.minimumHit)
                }
                .sheetRow()
            }
        }
    }

    // MARK: Actions

    private func perform(_ action: JobAction) {
        actionError = nil
        switch action {
        case let .progress(target): Task { await progress(target) }
        case .resume: Task { await progress(.inProgress, expectedPauseAuditId: current?.pauseCycleAuditId) }
        case .pause: pausing = true
        case .complete: completing = true
        case .cancel: confirmingCancel = true
        }
    }

    /// Returns whether the server accepted the change, so sheets keep their drafts on failure.
    @discardableResult
    private func progress(_ target: JobStatus, pause: PauseDetails? = nil, expectedPauseAuditId: String? = nil) async -> Bool {
        let action: JobAction = target == .paused ? .pause : (expectedPauseAuditId != nil ? .resume : .progress(target))
        busyAction = action
        defer { busyAction = nil }
        do {
            apply(try await model.api.progress(jobId, to: target, pause: pause, expectedPauseAuditId: expectedPauseAuditId))
            succeeded += 1
            return true
        } catch {
            actionError = model.message(for: error)
            if (error as? APIError)?.isConflict == true { await reloadJob() }
            return false
        }
    }

    private func complete(notes: String?) async -> Bool {
        busyAction = .complete
        defer { busyAction = nil }
        do {
            apply(try await model.api.complete(jobId, notes: notes))
            succeeded += 1
            return true
        } catch {
            actionError = model.message(for: error)
            return false
        }
    }

    private func cancel() async {
        busyAction = .cancel
        defer { busyAction = nil }
        do {
            apply(try await model.api.cancel(jobId))
        } catch {
            actionError = model.message(for: error)
        }
    }

    /// The mutation response is the server's record: show it now, then refresh
    /// `allowedTransitions` from the detail read without discarding it on failure.
    private func apply(_ updated: Job) {
        job = updated
        model.store(updated)
        Task { await reloadJob() }
    }

    private func createInvoice() async {
        do {
            model.store(try await model.api.completionInvoice(job: jobId))
        } catch {
            actionError = model.message(for: error)
        }
    }

    // MARK: Loading

    private func load() async {
        loading = true
        defer { loading = false }
        await reloadJob()
        guard let job = current else { return }
        async let notesLoaded: Void = loadNotes()
        async let photosLoaded: Void = loadPhotos()
        async let locations = model.api.locations(customer: job.customerId)
        _ = await (notesLoaded, photosLoaded)
        if let value = try? await locations { self.locations = value }
    }

    /// A failed read is shown as a failure, never as an empty log.
    private func loadNotes() async {
        do {
            notes = try await model.api.notes(job: jobId)
            notesError = nil
        } catch {
            notesError = model.message(for: error)
        }
    }

    private func loadPhotos() async {
        do {
            photos = try await model.api.photos(job: jobId)
            photosError = nil
        } catch {
            photosError = model.message(for: error)
        }
    }

    /// Detail reads always come from the server so `allowedTransitions` is current.
    private func reloadJob() async {
        do {
            let fresh = try await model.api.job(jobId)
            job = fresh
            model.store(fresh)
            loadError = nil
        } catch {
            loadError = model.message(for: error)
        }
    }
}

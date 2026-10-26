import SwiftUI
import ThorbisCore

struct JobsView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var showClosed = false
    @State private var creating = false

    private var filtered: [Job] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        return model.jobs.filter { job in
            (showClosed || !job.status.isTerminal)
                && (needle.isEmpty
                    || job.title.lowercased().contains(needle)
                    || job.reference.lowercased().contains(needle)
                    || model.customerName(job.customerId).lowercased().contains(needle))
        }
    }

    var body: some View {
        let groups = JobBucket.group(filtered)
        LoadState(
            isLoading: model.isRefreshing,
            error: model.refreshError,
            isEmpty: model.jobs.isEmpty,
            emptyTitle: "No jobs yet",
            emptySymbol: "wrench.and.screwdriver",
            emptyMessage: "Create a job, or ask the office to assign you one.",
            retry: { await model.refreshAll() }
        ) {
            List {
                if let error = model.refreshError {
                    InlineError(message: error) { await model.refreshAll() }.sheetRow()
                }
                ForEach(groups) { group in
                    Section {
                        ForEach(group.jobs) { job in
                            NavigationLink(value: Route.job(job.id)) { JobRow(job: job) }.sheetRow()
                        }
                    } header: {
                        HStack {
                            Text(group.bucket.title)
                            Text("\(group.jobs.count)").monospacedDigit().foregroundStyle(Theme.inkQuiet)
                        }
                    }
                }
                if groups.isEmpty {
                    Text(query.isEmpty ? "No open jobs." : "No jobs match “\(query)”.")
                        .foregroundStyle(Theme.inkSecondary)
                        .sheetRow()
                }
            }
            .thorbisList()
        }
        .navigationTitle("Jobs")
        .searchable(text: $query, prompt: "Title, customer or JOB-")
        .refreshable { await model.refreshAll() }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Toggle(isOn: $showClosed) {
                    Label("Show closed", systemImage: showClosed ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .toggleStyle(.button)
                .accessibilityLabel(showClosed ? "Hide completed and canceled" : "Show completed and canceled")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    creating = true
                } label: {
                    Label("New job", systemImage: "plus")
                }
                .accessibilityIdentifier("new-job")
            }
            AccountToolbarItem()
        }
        .sheet(isPresented: $creating) {
            NewJobView()
        }
    }
}

struct JobRow: View {
    @Environment(AppModel.self) private var model
    let job: Job

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(job.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(job.status.isTerminal ? Theme.inkSecondary : Theme.ink)
                Spacer(minLength: Theme.Space.s)
                StatusBadge(job.status)
            }
            HStack(spacing: Theme.Space.s) {
                Text(job.reference).font(.footnote.monospaced()).foregroundStyle(Theme.inkQuiet)
                Text(model.customerName(job.customerId)).font(.subheadline).foregroundStyle(Theme.inkSecondary)
                if let at = job.scheduledDate {
                    Text("· \(Format.dayTitle(at)) \(Format.time(at))").font(.subheadline).monospacedDigit().foregroundStyle(Theme.inkQuiet)
                }
            }
            .lineLimit(1)
        }
        .padding(.vertical, Theme.Space.xs)
        .accessibilityElement(children: .combine)
    }
}

/// A transient task in a sheet; the created job opens as a destination afterwards.
struct NewJobView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var customerId: String?
    var onCreated: ((Job) -> Void)?
    @State private var selectedCustomer: String?
    @State private var title = ""
    @State private var notes = ""
    @State private var busy = false
    @State private var error: String?

    private var activeCustomers: [Customer] {
        model.customers.filter { !$0.isArchived }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Customer") {
                    Picker("Customer", selection: $selectedCustomer) {
                        Text("Choose…").tag(String?.none)
                        ForEach(activeCustomers) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .sheetRow()
                }
                Section("Job") {
                    TextField("What needs doing", text: $title, axis: .vertical)
                        .accessibilityIdentifier("job-title")
                        .sheetRow()
                    TextField("Notes for the technician (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                        .sheetRow()
                }
                if let error {
                    Section { Text(error).foregroundStyle(Theme.danger).sheetRow() }
                }
            }
            .thorbisList()
            .navigationTitle("New job")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(!title.isEmpty || !notes.isEmpty)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy {
                        ProgressView()
                    } else {
                        Button("Create job", action: create)
                            .disabled(selectedCustomer == nil || title.trimmingCharacters(in: .whitespaces).isEmpty)
                            .accessibilityIdentifier("create-job")
                    }
                }
            }
            .onAppear { if selectedCustomer == nil { selectedCustomer = customerId } }
        }
    }

    private func create() {
        guard let selectedCustomer else { return }
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                let job = try await model.send { try await $0.createJob(customerId: selectedCustomer, title: title.trimmingCharacters(in: .whitespacesAndNewlines), notes: notes) }
                model.store(job)
                onCreated?(job)
                dismiss()
            } catch {
                self.error = model.message(for: error)
            }
        }
    }
}

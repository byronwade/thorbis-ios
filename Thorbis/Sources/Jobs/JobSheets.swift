import SwiftUI
import ThorbisCore

/// A pause is never ambiguous: it carries a reason and a next action (domains/jobs).
struct PauseJobSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onPause: (PauseDetails) async -> Bool
    @State private var reason = ""
    @State private var nextAction = ""
    @State private var busy = false

    private let suggestions = ["Waiting on parts", "Customer not home", "Needs a second technician", "Waiting on approval"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Why is work stopping?", text: $reason, axis: .vertical).sheetRow()
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.Space.s) {
                            ForEach(suggestions, id: \.self) { suggestion in
                                Button(suggestion) { reason = suggestion }
                                    .font(.subheadline)
                                    .padding(.horizontal, Theme.Space.m)
                                    .frame(minHeight: Theme.minimumHit)
                                    .background(Theme.subtle, in: Capsule())
                                    .overlay(Capsule().strokeBorder(Theme.rim))
                            }
                        }
                    }
                    .sheetRow()
                } header: {
                    Text("Reason")
                }
                Section {
                    TextField("e.g. Pick up the valve from the supplier", text: $nextAction, axis: .vertical).sheetRow()
                } header: {
                    Text("Next action")
                } footer: {
                    Text("The office sees this so the job doesn't sit on hold forever.")
                }
            }
            .thorbisList()
            .navigationTitle("Pause job")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(!reason.isEmpty || !nextAction.isEmpty)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy {
                        ProgressView()
                    } else {
                        Button("Pause job") {
                            busy = true
                            Task {
                                let paused = await onPause(PauseDetails(reason: reason.trimmed, nextAction: nextAction.trimmed))
                                busy = false
                                if paused { dismiss() }
                            }
                        }
                        .disabled(reason.trimmed.isEmpty || nextAction.trimmed.isEmpty)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct CompleteJobSheet: View {
    @Environment(\.dismiss) private var dismiss
    let job: Job
    let onComplete: (String?) async -> Bool
    @State private var notes = ""
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(job.title).font(.headline.weight(.medium)).sheetRow()
                } footer: {
                    Text("Completing closes the job. The office can create the invoice from it.")
                }
                Section("Completion notes") {
                    TextField("What was done (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...10)
                        .sheetRow()
                }
                Section {
                    CommitButton(title: "Complete job", symbol: "checkmark.circle", busy: busy) {
                        busy = true
                        Task {
                            let completed = await onComplete(notes.trimmed.isEmpty ? nil : notes.trimmed)
                            busy = false
                            if completed { dismiss() }
                        }
                    }
                    .accessibilityIdentifier("confirm-complete")
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            .thorbisList()
            .navigationTitle("Complete job")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct ScheduleJobSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let job: Job
    let onSaved: (Job) -> Void
    @State private var start = Date()
    @State private var hasWindow = false
    @State private var windowMinutes = 120
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Arrival", selection: $start, displayedComponents: [.date, .hourAndMinute])
                        .sheetRow()
                    Toggle("Arrival window", isOn: $hasWindow).sheetRow()
                    if hasWindow {
                        Picker("Window", selection: $windowMinutes) {
                            Text("1 hour").tag(60)
                            Text("2 hours").tag(120)
                            Text("3 hours").tag(180)
                            Text("4 hours").tag(240)
                        }
                        .sheetRow()
                    }
                } footer: {
                    Text("Times are in \(TimeZone.current.localizedName(for: .generic, locale: .current) ?? TimeZone.current.identifier).")
                }
                if let error {
                    Section { Text(error).foregroundStyle(Theme.danger).sheetRow() }
                }
            }
            .thorbisList()
            .navigationTitle(job.scheduledFor == nil ? "Schedule" : "Reschedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy { ProgressView() } else { Button("Save", action: save) }
                }
            }
            .onAppear { if let at = job.scheduledDate { start = at } }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                let updated = try await model.send { try await $0.schedule(
                    job.id, at: start, timeZone: .current,
                    windowEnds: hasWindow ? start.addingTimeInterval(TimeInterval(windowMinutes * 60)) : nil,
                    expectedPrior: job.scheduledFor
                ) }
                onSaved(updated)
                dismiss()
            } catch {
                self.error = model.message(for: error)
            }
        }
    }
}

struct AssignJobSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let job: Job
    let onSaved: (Job) -> Void
    @State private var busy: String?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if model.assignees.isEmpty {
                    Text("No one is available to assign, or your role can't assign jobs.")
                        .foregroundStyle(Theme.inkSecondary)
                        .sheetRow()
                }
                ForEach(model.assignees) { person in
                    Button {
                        assign(person)
                    } label: {
                        HStack {
                            Avatar(name: person.displayName)
                            Text(person.userId == model.userId ? "\(person.displayName) (you)" : person.displayName)
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            if busy == person.userId {
                                ProgressView()
                            } else if person.userId == job.assignedToUserId {
                                Image(systemName: "checkmark").foregroundStyle(Theme.accent).accessibilityLabel("Assigned")
                            }
                        }
                        .frame(minHeight: Theme.minimumHit)
                    }
                    .sheetRow()
                }
                if let error {
                    Text(error).foregroundStyle(Theme.danger).sheetRow()
                }
            }
            .thorbisList()
            .navigationTitle("Assign technician")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func assign(_ person: Assignee) {
        guard person.userId != job.assignedToUserId else { dismiss(); return }
        busy = person.userId
        error = nil
        Task {
            defer { busy = nil }
            do {
                onSaved(try await model.send { try await $0.assign(job.id, to: person.userId, expectedAssigneeId: job.assignedToUserId) })
                dismiss()
            } catch {
                self.error = model.message(for: error)
            }
        }
    }
}

struct AddNoteSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let jobId: String
    let onAdded: (JobNote) -> Void
    @State private var text = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What did you see or do?", text: $text, axis: .vertical)
                        .lineLimit(4...12)
                        .focused($focused)
                        .accessibilityIdentifier("note-text")
                        .sheetRow()
                } footer: {
                    Text("Notes can't be edited later.")
                }
                if let error {
                    Section { Text(error).foregroundStyle(Theme.danger).sheetRow() }
                }
            }
            .thorbisList()
            .navigationTitle("Add note")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(!text.isEmpty)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy {
                        ProgressView()
                    } else {
                        Button("Add note", action: save)
                            .disabled(text.trimmed.isEmpty)
                            .accessibilityIdentifier("save-note")
                    }
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                onAdded(try await model.api.addNote(job: jobId, body: text.trimmed))
                dismiss()
            } catch {
                // The draft stays in the field (HIG-013).
                self.error = model.message(for: error)
            }
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

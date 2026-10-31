import SwiftUI
import UIKit

// Run a checklist on a job: tick items, write readings, attach a photo to an item. Progress stays on
// this phone (per workspace, person and job) until the run is finished; finishing posts a summary as
// a job note through the offline-safe note path. Templates live in JobChecklistTemplates.swift.

/// One technician's run of one template on one job.
struct ChecklistRun: Codable, Equatable {
    let templateID: String
    var done: Set<String> = []
    var readings: [String: String] = [:]
    /// Photos attached per item (they go to the job's media queue; this only counts them).
    var photos: [String: Int] = [:]
    var startedAt = Date()

    func reading(_ item: ChecklistItem) -> String {
        (readings[item.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func doneCount(_ template: ChecklistTemplate) -> Int { template.items.filter { done.contains($0.id) }.count }

    /// The job note a finished run posts.
    func summary(_ template: ChecklistTemplate) -> String {
        var lines = ["Checklist · \(template.title) — \(doneCount(template)) of \(template.items.count) done"]
        for item in template.items {
            let value = reading(item)
            let text = item.reading != nil && !value.isEmpty ? "\(item.label): \(value) \(item.reading?.unit ?? "")" : item.label
            let photo = (photos[item.id] ?? 0) > 0 ? " (photo)" : ""
            lines.append(done.contains(item.id) ? "✓ \(text.trimmingCharacters(in: .whitespaces))\(photo)" : "– Not done: \(text)\(photo)")
        }
        let photoTotal = photos.values.reduce(0, +)
        if photoTotal > 0 { lines.append("\(photoTotal) photo\(photoTotal == 1 ? "" : "s") added to this job’s media.") }
        return lines.joined(separator: "\n")
    }
}

/// Checklist progress on this phone, keyed by workspace, person and job. Cleared on sign-out.
@MainActor
enum JobChecklistStore {
    private static let key = "thorbis.jobChecklists.v1"

    private static func slot(_ jobID: String, _ session: SessionController) -> String? {
        guard let actor = session.user?.id, let organization = session.activeOrganization?.id else { return nil }
        return "\(organization)|\(actor)|\(jobID)"
    }

    static func run(jobID: String, session: SessionController) -> ChecklistRun? {
        guard let slot = slot(jobID, session), let data = UserDefaults.standard.dictionary(forKey: key)?[slot] as? Data else { return nil }
        return try? JSONDecoder().decode(ChecklistRun.self, from: data)
    }

    static func save(_ run: ChecklistRun?, jobID: String, session: SessionController) {
        guard let slot = slot(jobID, session) else { return }
        var all = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        all[slot] = run.flatMap { try? JSONEncoder().encode($0) }
        UserDefaults.standard.set(all, forKey: key)
    }

    static func clearAll() { UserDefaults.standard.removeObject(forKey: key) }
}

/// Entry point: present as a sheet from the job (`.sheet { JobChecklistSheet(job: job) { … } }`).
/// `onDone` runs when the technician closes it; reload notes then.
struct JobChecklistSheet: View {
    let jobID: String
    let onDone: () -> Void
    /// DEBUG fixtures: start on this run instead of the phone's saved one.
    var previewRun: ChecklistRun? = nil

    init(job: JobRecord, onDone: @escaping () -> Void) {
        self.init(jobID: job.id, onDone: onDone)
    }

    init(jobID: String, previewRun: ChecklistRun? = nil, onDone: @escaping () -> Void) {
        self.jobID = jobID
        self.previewRun = previewRun
        self.onDone = onDone
    }

    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var outbox: FieldOutbox
    @EnvironmentObject private var pendingMedia: PendingMediaStore
    @State private var run: ChecklistRun?
    @State private var loaded = false
    @State private var busy = false
    @State private var result: JobNotePostResult?
    @State private var photoFor: ChecklistItem?
    @State private var confirmRestart = false
    @State private var problem: String?
    @FocusState private var focused: String?

    private var template: ChecklistTemplate? { run.flatMap { ChecklistTemplates.template($0.templateID) } }
    private var finished: Bool { result?.succeeded == true }
    private var canPhoto: Bool { JobPhotoAttach.canAttach(session) && UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if let run, let template { runList(run, template) } else if !finished { picker }
                    if let result {
                        Label(result.message, systemImage: result.succeeded ? (result == .saved ? "checkmark.circle" : "clock.arrow.circlepath") : "exclamationmark.triangle")
                            .font(Theme.font(14)).foregroundStyle(result.succeeded ? Theme.muted : Theme.destructive)
                            .padding(.horizontal, 4).padding(.top, 8)
                            .accessibilityIdentifier("checklist-result")
                    }
                    if let problem {
                        Label(problem, systemImage: "exclamationmark.triangle").font(Theme.font(14)).foregroundStyle(Theme.destructive)
                            .padding(.horizontal, 4).padding(.top, 8)
                    }
                }
                .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 8).padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .navigationTitle(template?.title ?? "Checklist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ThorbisToolbarItem(placement: .topBarLeading) { PaperCircleButton(symbol: "xmark", label: finished ? "Done" : "Close, progress stays on this phone", action: onDone) }
                if run != nil, !finished {
                    ThorbisToolbarItem(placement: .topBarTrailing) { Button("Start over") { confirmRestart = true } }
                }
                ThorbisKeyboardDoneBar { focused = nil }
            }
            .safeAreaInset(edge: .bottom) {
                if let run, let template {
                    PaperActionBar(title: "Finish · add to notes", symbol: "checklist", busy: busy,
                                   disabled: run.doneCount(template) == 0 || !JobNotePoster.canPost(session)) {
                        Task { await finish(run, template) }
                    }
                } else if finished {
                    PaperActionBar(title: "Done") { onDone() }
                }
            }
            .thorbisConfirm("Start this checklist over?", message: "Ticks and readings saved on this phone are cleared. Photos already added stay on the job.",
                            isPresented: $confirmRestart,
                            actions: [ThorbisConfirmAction("Start over", role: .destructive) { update(nil) }])
            .fullScreenCover(item: $photoFor) { item in
                CameraCapture { image in
                    photoFor = nil
                    if let image { attach(image, to: item) }
                }
                .ignoresSafeArea()
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                run = previewRun ?? JobChecklistStore.run(jobID: jobID, session: session)
            }
        }
    }

    // MARK: Pick a template

    private var picker: some View {
        VStack(alignment: .leading, spacing: 6) {
            PaperGroupHeader(title: "Choose a checklist").padding(.horizontal, 4)
            PaperCard {
                ForEach(ChecklistTemplates.all) { template in
                    Button { update(ChecklistRun(templateID: template.id)) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.title).font(Theme.font(16, weight: .medium))
                            let readings = template.items.filter { $0.reading != nil }.count
                            Text("\(template.items.count) checks" + (readings > 0 ? " · \(readings) readings" : ""))
                                .font(Theme.font(14)).foregroundStyle(Theme.muted)
                        }
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                        .padding(.horizontal, PaperCardMetrics.inset)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                    .accessibilityIdentifier("checklist-template-\(template.id)")
                }
                .padding(.vertical, PaperCardMetrics.edge / 2)
            }
            Text("Checklists are kept on this phone. Finishing one adds a summary to the job’s notes.")
                .font(Theme.font(12)).foregroundStyle(Theme.muted).padding(.horizontal, 4).padding(.top, 4)
        }
    }

    // MARK: Run

    private func runList(_ run: ChecklistRun, _ template: ChecklistTemplate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            PaperGroupHeader(title: "\(run.doneCount(template)) of \(template.items.count) done") {
                Text("Saved on this phone").font(Theme.font(13))
            }
            .padding(.horizontal, 4)
            PaperCard {
                ForEach(template.items) { item in row(item, run) }
                    .padding(.vertical, PaperCardMetrics.edge / 2)
            }
        }
    }

    private func row(_ item: ChecklistItem, _ run: ChecklistRun) -> some View {
        let isDone = run.done.contains(item.id)
        let photos = run.photos[item.id] ?? 0
        return HStack(alignment: .center, spacing: 12) {
            Button { toggle(item) } label: {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(isDone ? Theme.success : Theme.subtle)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel(item.label)
            .accessibilityValue(isDone ? "Done" : "Not done")
            .accessibilityIdentifier("checklist-tick-\(item.id)")
            VStack(alignment: .leading, spacing: 4) {
                Text(item.label).font(Theme.font(16, weight: .medium))
                    .foregroundStyle(isDone ? Theme.muted : Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if let reading = item.reading {
                    HStack(spacing: 6) {
                        TextField(reading.prompt, text: readingBinding(item))
                            .font(Theme.font(15, weight: .medium)).monospacedDigit()
                            .keyboardType(.numbersAndPunctuation)
                            .focused($focused, equals: item.id)
                            .padding(.horizontal, 10).frame(width: 110, height: 36)
                            .background(Theme.fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .accessibilityLabel("\(item.label) in \(reading.unit)")
                        Text(reading.unit).font(Theme.font(14)).foregroundStyle(Theme.muted)
                    }
                }
                if photos > 0 {
                    Text("\(photos) photo\(photos == 1 ? "" : "s") added").font(Theme.font(13)).foregroundStyle(Theme.muted)
                }
            }
            .padding(.vertical, 8)
            Spacer(minLength: 0)
            if canPhoto {
                PaperCircleButton(symbol: "camera", label: "Add a photo for \(item.label)", size: 32) { photoFor = item }
            }
        }
        .padding(.leading, PaperCardMetrics.inset - 10).padding(.trailing, PaperCardMetrics.inset - 6)
    }

    // MARK: Actions

    private func readingBinding(_ item: ChecklistItem) -> Binding<String> {
        Binding(get: { run?.readings[item.id] ?? "" }, set: { value in
            guard var current = run else { return }
            current.readings[item.id] = value
            // Writing a reading is doing the check.
            if !value.trimmingCharacters(in: .whitespaces).isEmpty { current.done.insert(item.id) }
            update(current)
        })
    }

    private func toggle(_ item: ChecklistItem) {
        guard var current = run else { return }
        if current.done.contains(item.id) { current.done.remove(item.id) } else { current.done.insert(item.id) }
        UISelectionFeedbackGenerator().selectionChanged()
        update(current)
    }

    private func update(_ next: ChecklistRun?) {
        run = next
        result = nil
        problem = nil
        JobChecklistStore.save(next, jobID: jobID, session: session)
    }

    private func attach(_ image: UIImage, to item: ChecklistItem) {
        do {
            try JobPhotoAttach.save(image, jobID: jobID, caption: "Checklist · \(item.label)", prefix: "checklist",
                                    api: api, session: session, pendingMedia: pendingMedia)
            guard var current = run else { return }
            current.photos[item.id, default: 0] += 1
            update(current)
        } catch { problem = error.localizedDescription }
    }

    private func finish(_ run: ChecklistRun, _ template: ChecklistTemplate) async {
        focused = nil
        busy = true
        defer { busy = false }
        let outcome = await JobNotePoster.post(run.summary(template), jobID: jobID, api: api, session: session, outbox: outbox)
        if outcome.succeeded {
            JobChecklistStore.save(nil, jobID: jobID, session: session)
            self.run = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        result = outcome
    }
}

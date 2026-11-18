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
    /// Said above Finish when it is pressed with nothing checked; clears once an item is.
    @State private var finishProblem: String?
    @FocusState private var focused: String?

    private var template: ChecklistTemplate? { run.flatMap { ChecklistTemplates.template($0.templateID) } }
    private var finished: Bool { result?.succeeded == true }
    private var canPhoto: Bool { JobPhotoAttach.canAttach(session) && UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    // Paper 21F: the 34 Bold title, "AC repair · 5 of 8 done" under it.
                    PaperPageTitle(title: "Checklist", subtitle: headerSubtitle, columnInset: PaperCardMetrics.margin)
                        .padding(.bottom, 10)
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
                .padding(.horizontal, PaperCardMetrics.margin).padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Paper 21F: the bar is the 44pt back circle alone. "Start over" is behind More.
                ThorbisToolbarItem(placement: .topBarLeading) {
                    PaperCircleButton(symbol: "chevron.left", label: finished ? "Done" : "Close", size: 44, fill: Theme.card, action: onDone)
                        .accessibilityHint(finished ? "" : "Progress stays on this phone.")
                        .accessibilityIdentifier("checklist-close")
                }
                if run != nil, !finished {
                    ThorbisToolbarItem(placement: .topBarTrailing) {
                        ThorbisMenu(items: [ThorbisMenuItem("Start over", icon: "arrow.counterclockwise", role: .destructive) { confirmRestart = true }],
                                    accessibilityLabel: "Checklist actions") {
                            PaperCircleLabel(symbol: "ellipsis", size: 44, fill: Theme.card)
                        }
                    }
                }
                ThorbisKeyboardDoneBar { focused = nil }
            }
            .safeAreaInset(edge: .bottom) {
                if let run, let template {
                    VStack(alignment: .leading, spacing: 0) {
                        if let finishProblem, run.doneCount(template) == 0 {
                            FieldProblem(message: finishProblem)
                                .padding(.horizontal, Theme.gutter).padding(.top, 8)
                        }
                        // Not pre-disabled for an empty run: pressing says what's missing. Without
                        // the note permission it stays off, and the sentence under it says why.
                        PaperActionBar(title: "Mark checklist done", busy: busy,
                                       disabled: !JobNotePoster.canPost(session),
                                       disabledReason: "Your role can't add job notes. Ask your office.") {
                            if run.doneCount(template) == 0 {
                                finishProblem = "Check off at least one item to finish."
                            } else {
                                Task { await finish(run, template) }
                            }
                        }
                    }
                    .background(Theme.background)
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
        // Paper 21F is a page: cards on the page's ground, not on the sheet's panel.
        .paperPageGround()
    }

    /// "AC repair · 5 of 8 done" while a run is open; what to do otherwise.
    private var headerSubtitle: String {
        if let run, let template { return "\(template.title) · \(run.doneCount(template)) of \(template.items.count) done" }
        return finished ? "Added to the job\u{2019}s notes" : "Choose a checklist for this job"
    }

    // MARK: Pick a template

    private var picker: some View {
        VStack(alignment: .leading, spacing: 6) {
            PaperSection("Choose a checklist") {
                ForEach(ChecklistTemplates.all) { template in
                    if template.id != ChecklistTemplates.all.first?.id { WellDivider() }
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
            }
            Text("Checklists are kept on this phone. Finishing one adds a summary to the job’s notes.")
                .font(Theme.font(12)).foregroundStyle(Theme.muted).padding(.horizontal, 4).padding(.top, 4)
        }
    }

    // MARK: Run

    private func runList(_ run: ChecklistRun, _ template: ChecklistTemplate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PaperCard {
                ForEach(template.items) { item in
                    if item.id != template.items.first?.id { WellDivider(leading: PaperCardMetrics.inset + 40) }
                    row(item, run)
                }
            }
            Text("Saved on this phone until you mark it done.").font(Theme.font(13)).foregroundStyle(Theme.muted)
                .padding(.horizontal, 4)
        }
    }

    private func row(_ item: ChecklistItem, _ run: ChecklistRun) -> some View {
        let isDone = run.done.contains(item.id)
        let photos = run.photos[item.id] ?? 0
        // Paper 21F: the 28pt mark 16 from the card's edge and the words 12 after it; the mark's
        // 44pt target takes the other 8 on each side.
        return HStack(alignment: .center, spacing: 4) {
            Button { toggle(item) } label: {
                // Paper 21F: a 28pt filled green tick, or an empty ring.
                ZStack {
                    if isDone {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 28, weight: .regular))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Theme.background, Theme.statusDone)
                    } else {
                        Circle().strokeBorder(Theme.borderStrong, lineWidth: 1.5).frame(width: 28, height: 28)
                    }
                }
                .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel(item.label)
            .accessibilityValue(isDone ? "Done" : "Not done")
            .accessibilityIdentifier("checklist-tick-\(item.id)")
            VStack(alignment: .leading, spacing: 4) {
                Text(item.label).font(Theme.font(16, weight: .medium)).tracking(-0.16)
                    .foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if let reading = item.reading {
                    HStack(spacing: 6) {
                        // An empty reading shows a dash: the label above names it, and a sample number
                        // could pass for a reading that was taken.
                        TextField(reading.prompt, text: readingBinding(item), prompt: .placeholder("\u{2014}"))
                            .font(Theme.font(15, weight: .medium)).monospacedDigit()
                            .keyboardType(.numbersAndPunctuation)
                            .focused($focused, equals: item.id)
                            .padding(.horizontal, 10).frame(width: 110, height: 44)
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
                // Paper 21F: "Add photo" as a brand chip on the row.
                Button { photoFor = item } label: {
                    Text("Add photo").paperButton(.secondary, tone: .tinted)
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Add a photo for \(item.label)")
            }
        }
        .frame(minHeight: 56)
        .padding(.leading, PaperCardMetrics.inset - 8).padding(.trailing, 12)
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

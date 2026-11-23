import SwiftUI
import UIKit

// The job's checklists when they are kept on the server (feature `job_checklists`): the card on
// the job that lists every run, and the sheet that starts one, fills it in and finishes it.
// The rules and the sending are in JobChecklistServer.swift; with the feature off JobChecklistSheet
// (on-phone checklists) is shown instead and nothing here runs.

/// "Finished by Sam · Nov 20, 3:14 PM", "5 of 8 done", and what is still only on this phone.
enum ChecklistEntryWords {
    static func line(_ entry: ChecklistEntry) -> String {
        if entry.completed {
            let who = entry.completedBy.map { "Finished by \($0 == "You" ? "you" : $0)" } ?? "Finished"
            return [who, entry.completedAt?.stampLabel(year: false)].compactMap { $0 }.joined(separator: " \u{00B7} ")
        }
        let progress = "\(entry.done) of \(entry.total) done"
        return entry.unsent ? "\(progress) \u{00B7} on this phone" : progress
    }

    static func next(_ entry: ChecklistEntry) -> String {
        if entry.completed { return line(entry) }
        let item = entry.template.items.first { entry.answers[$0.id]?.done != true }
        return item.map { "Next: \($0.label)" } ?? "All done. Mark it done to finish."
    }
}

/// The job's checklist runs as cards: the ones under way with a progress ring, the finished ones
/// with who finished them and when. Nothing shows until the job has a run.
struct JobChecklistRunsCard: View {
    @ObservedObject var model: JobChecklistModel
    let open: (String) -> Void

    var body: some View {
        let entries = model.entries
        let ordered = entries.filter { !$0.completed } + entries.filter(\.completed)
        if !ordered.isEmpty {
            VStack(spacing: 8) {
                ForEach(Array(ordered.enumerated()), id: \.element.id) { index, entry in
                    Button { open(entry.id) } label: { row(entry) }
                        .buttonStyle(PressStyle())
                        .accessibilityElement(children: .combine)
                        .accessibilityHint(entry.completed ? "Opens the finished checklist" : "Opens this visit's checklist")
                        .accessibilityIdentifier(index == 0 ? "job-checklist-card" : "job-checklist-run-\(entry.id)")
                }
            }
        }
    }

    private func row(_ entry: ChecklistEntry) -> some View {
        HStack(spacing: 12) {
            ZStack {
                if entry.completed {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 24, weight: .regular))
                        .symbolRenderingMode(.palette).foregroundStyle(Theme.background, Theme.statusDone)
                } else {
                    Circle().stroke(Theme.foreground.opacity(0.12), lineWidth: 3)
                    Circle().trim(from: 0, to: CGFloat(entry.done) / CGFloat(max(entry.total, 1)))
                        .stroke(Theme.brandText, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            }
            .frame(width: 22, height: 22).padding(3)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.completed ? entry.template.title : "\(entry.template.title) \u{00B7} \(entry.done) of \(entry.total)")
                    .font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Text(entry.completed || !entry.unsent ? ChecklistEntryWords.next(entry) : "On this phone. Sends when you\u{2019}re back online.")
                    .font(Theme.font(14)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            PaperIcon(.jobChevronRight, size: 16, color: Theme.muted).frame(width: 24, height: 24)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .panelBackground(cornerRadius: Theme.cardRadius)
        .contentShape(Rectangle())
    }
}

/// The sheet: every checklist on the job, the ones that can be started, and one run to fill in.
struct JobServerChecklistSheet: View {
    let jobID: String
    @ObservedObject var model: JobChecklistModel
    /// The run to open on; nil opens the one under way, or the list.
    var opening: String? = nil
    /// Open on the list even when one run is under way.
    var startsOnList = false
    let onDone: () -> Void

    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var pendingMedia: PendingMediaStore
    @State private var openRun: String?
    @State private var appeared = false
    @State private var busy = false
    @State private var starting: String?
    @State private var finishProblem: String?
    @State private var said: String?
    @State private var photoFor: ServerChecklistItem?
    @State private var confirmRemove = false
    @State private var confirmLetGo = false
    @FocusState private var focused: String?

    private var entry: ChecklistEntry? { openRun.flatMap(model.entry) }
    private var canWrite: Bool { JobNotePoster.canPost(session) }
    private var canPhoto: Bool { JobPhotoAttach.canAttach(session) && UIImagePickerController.isSourceTypeAvailable(.camera) }
    /// The run as the model knows it now (its ID changes once the server has it).
    private var runKey: String? { entry?.id ?? openRun }
    private var note: String? { [openRun, entry?.id].compactMap { $0 }.compactMap { model.notes[$0] ?? model.draft($0).flatMap { model.notes[$0.runID] } }.first }
    private var onlyOnPhone: Bool { openRun.flatMap { model.draft($0) }.map { !$0.started } ?? false }
    /// Answers kept on this phone for a run someone else finished first.
    private var keptAnswers: String? { openRun.flatMap { model.keptText($0) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    PaperPageTitle(title: "Checklist", subtitle: subtitle, columnInset: PaperCardMetrics.margin)
                        .padding(.bottom, 10)
                    if let entry { runList(entry) } else { list }
                }
                .padding(.horizontal, PaperCardMetrics.margin).padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await model.load(api: api) }
            .background(Theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                PaperPageSheetBar {
                    PaperCircleButton(symbol: "xmark", label: "Close", size: 44, fill: Theme.card, action: close)
                        .accessibilityHint("Your answers are saved.")
                        .accessibilityIdentifier("checklist-close")
                } trailing: {
                    if entry != nil {
                        ThorbisMenu(items: menuItems, accessibilityLabel: "Checklist actions") {
                            PaperCircleLabel(symbol: "ellipsis", size: 44, fill: Theme.card)
                        }
                        .accessibilityIdentifier("checklist-actions")
                    }
                }
                .background(Theme.background)
            }
            .toolbar { ThorbisKeyboardDoneBar { focused = nil } }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .thorbisConfirm("Remove this checklist?", message: "It was only on this phone. Its answers are cleared.",
                            isPresented: $confirmRemove,
                            actions: [ThorbisConfirmAction("Remove", role: .destructive) {
                                if let openRun { model.discard(openRun) }
                                openRun = nil
                            }])
            .thorbisConfirm("Let go of your answers?", message: "This checklist was finished before they were sent. They\u{2019}re cleared from this phone.",
                            isPresented: $confirmLetGo,
                            actions: [ThorbisConfirmAction("Let go", role: .destructive) {
                                if let openRun { model.discardKept(openRun) }
                            }])
            .fullScreenCover(item: $photoFor) { item in
                CameraCapture { image in
                    photoFor = nil
                    if let image { attach(image, to: item) }
                }
                .ignoresSafeArea()
            }
            .task {
                guard !appeared else { return }
                appeared = true
                openRun = startsOnList ? nil : opening ?? Self.firstOpen(model.entries)
                await model.load(api: api)
                if openRun == nil, opening == nil, !startsOnList { openRun = Self.firstOpen(model.entries) }
            }
            .onChange(of: session.isOffline) { _, offline in
                if !offline { Task { await model.load(api: api) } }
            }
        }
        .paperPageGround()
    }

    /// The one run under way opens straight away; two or none shows the list.
    static func firstOpen(_ entries: [ChecklistEntry]) -> String? {
        let open = entries.filter { !$0.completed }
        return open.count == 1 ? open[0].id : nil
    }

    private var subtitle: String {
        guard let entry else { return "Checklists on this job" }
        return "\(entry.template.title) \u{00B7} \(ChecklistEntryWords.line(entry))"
    }

    private var menuItems: [ThorbisMenuItem] {
        var items = [
            ThorbisMenuItem("All checklists on this job", icon: "list.bullet") { focused = nil; finishProblem = nil; said = nil; openRun = nil },
            ThorbisMenuItem("Reload", icon: "arrow.clockwise") { Task { await model.load(api: api) } },
        ]
        if onlyOnPhone {
            items.append(ThorbisMenuItem("Remove this checklist", icon: "trash", role: .destructive) { confirmRemove = true })
        }
        if let keptAnswers {
            items.append(ThorbisMenuItem("Copy my answers", icon: "doc.on.doc") {
                UIPasteboard.general.string = keptAnswers
                said = "Your answers are copied."
            })
            items.append(ThorbisMenuItem("Let go of my answers", icon: "trash", role: .destructive) { confirmLetGo = true })
        }
        return items
    }

    @ViewBuilder private var bottomBar: some View {
        if let entry {
            if entry.completed {
                PaperActionBar(title: "Done") { close() }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    if let finishProblem {
                        FieldProblem(message: finishProblem).padding(.horizontal, Theme.gutter).padding(.top, 8)
                            .accessibilityIdentifier("checklist-finish-problem")
                    }
                    PaperActionBar(title: "Mark checklist done", busy: busy, disabled: !canWrite,
                                   disabledReason: "Your role can\u{2019}t fill in checklists. Ask your office.") {
                        Task { await finish() }
                    }
                }
                .background(Theme.background)
            }
        }
    }

    // MARK: The list

    @ViewBuilder private var list: some View {
        let entries = model.entries
        VStack(alignment: .leading, spacing: 16) {
            if model.showingSaved {
                Label("No signal. This is what\u{2019}s saved on this phone.", systemImage: "wifi.slash")
                    .font(Theme.font(14)).foregroundStyle(Theme.muted).padding(.horizontal, 4)
            }
            if let error = model.loadError {
                ErrorBanner(message: error) { await model.load(api: api) }.padding(.horizontal, -PaperCardMetrics.margin)
            }
            if let said {
                Label(said, systemImage: "checkmark.circle").font(Theme.font(14)).foregroundStyle(Theme.muted).padding(.horizontal, 4)
                    .accessibilityIdentifier("checklist-result")
            }
            if !entries.isEmpty {
                PaperSection(title: "On this job", count: entries.count) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { WellDivider() }
                        Button { said = nil; openRun = entry.id } label: {
                            PaperListRow(title: entry.template.title, subtitle: ChecklistEntryWords.line(entry)) { PaperChevron() }
                        }
                        .buttonStyle(RowPressStyle())
                        .accessibilityIdentifier("checklist-run-\(entry.id)")
                    }
                } accessory: { EmptyView() }
            }
            if canWrite {
                if model.templates.isEmpty {
                    if model.loaded || model.showingSaved {
                        PaperEmptyState(symbol: "checklist", title: "No checklists to start",
                                        message: ChecklistFeature.canManage(session)
                                            ? "Add your company\u{2019}s checklists in Business settings, under Checklists."
                                            : "Ask your office to add your company\u{2019}s checklists.")
                            .padding(.vertical, 12)
                    } else if entries.isEmpty {
                        SkeletonSection(rows: 3)
                    }
                } else {
                    PaperSection("Start a checklist") {
                        ForEach(Array(model.templates.enumerated()), id: \.element.id) { index, template in
                            if index > 0 { WellDivider() }
                            Button { Task { await start(template) } } label: {
                                PaperListRow(title: template.title, subtitle: ChecklistRules.summary(template.items)) {
                                    if starting == template.id { ProgressView() } else { PaperChevron() }
                                }
                            }
                            .buttonStyle(RowPressStyle())
                            .disabled(starting != nil)
                            .accessibilityIdentifier("checklist-template-\(template.id)")
                        }
                    }
                    Text("Answers are saved to the job as you go, for the whole team to see.")
                        .font(Theme.font(12)).foregroundStyle(Theme.muted).padding(.horizontal, 4)
                }
            } else if entries.isEmpty, model.loaded {
                PaperEmptyState(symbol: "checklist", title: "No checklists on this job", message: "Your role can\u{2019}t start one. Ask your office.")
                    .padding(.vertical, 12)
            }
        }
    }

    // MARK: One run

    private func runList(_ entry: ChecklistEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PaperCard {
                ForEach(entry.template.items) { item in
                    if item.id != entry.template.items.first?.id { WellDivider(leading: PaperCardMetrics.inset + 40) }
                    row(item, entry)
                }
            }
            if let note {
                let waiting = note == ChecklistRules.onPhoneWords
                Label(note, systemImage: waiting ? "clock.arrow.circlepath" : "exclamationmark.triangle")
                    .font(Theme.font(14)).foregroundStyle(waiting ? Theme.muted : Theme.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4).padding(.top, 4)
                    .accessibilityIdentifier("checklist-note")
            } else if !entry.completed {
                Text(entry.unsent && session.isOffline ? ChecklistRules.onPhoneWords : "Saved to the job as you go.")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted).padding(.horizontal, 4)
            }
            if let said {
                Label(said, systemImage: "checkmark.circle").font(Theme.font(14)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, 4).padding(.top, 4)
                    .accessibilityIdentifier("checklist-result")
            }
        }
    }

    private func row(_ item: ServerChecklistItem, _ entry: ChecklistEntry) -> some View {
        let answer = entry.answers[item.id] ?? ChecklistDraftAnswer(done: false)
        let locked = entry.completed || !canWrite
        let other = model.run(entry.id)?.answer(item.id).flatMap { stored -> String? in
            guard stored.done, let by = stored.answeredByUserId, model.who(by) != "You",
                  model.draft(entry.id)?.unsent[item.id] == nil else { return nil }
            return "By \(model.who(by))"
        }
        return HStack(alignment: .center, spacing: 4) {
            Button { toggle(item, answer) } label: {
                ZStack {
                    if answer.done {
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
            .disabled(locked)
            .accessibilityLabel(item.label)
            .accessibilityValue(answer.done ? "Done" : "Not done")
            .accessibilityIdentifier("checklist-tick-\(item.id)")
            VStack(alignment: .leading, spacing: 4) {
                (Text(item.label).font(Theme.font(16, weight: .medium))
                 + Text(item.required ? "  Needed" : "").font(Theme.font(13, weight: .medium)).foregroundColor(Theme.warning))
                    .tracking(-0.16)
                    .foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if item.kind != .tick {
                    if locked {
                        let words = [answer.text, item.kind == .number ? item.unit ?? "" : ""].filter { !$0.isEmpty }.joined(separator: " ")
                        if !answer.text.isEmpty { Text(words).font(Theme.font(15)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true) }
                    } else {
                        valueField(item, answer)
                    }
                    if let problem = ChecklistRules.problem(answer, for: item) { FieldProblem(message: problem) }
                }
                if let other { Text(other).font(Theme.font(13)).foregroundStyle(Theme.muted) }
            }
            .padding(.vertical, 8)
            Spacer(minLength: 0)
            if canPhoto, !entry.completed {
                Button { photoFor = item } label: { Text("Add photo").paperButton(.secondary, tone: .tinted) }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Add a photo for \(item.label)")
            }
        }
        .frame(minHeight: 56)
        .padding(.leading, PaperCardMetrics.inset - 8).padding(.trailing, 12)
    }

    @ViewBuilder private func valueField(_ item: ServerChecklistItem, _ answer: ChecklistDraftAnswer) -> some View {
        let binding = Binding(get: { answer.text }, set: { text in
            // Writing something is doing the check; clearing it leaves the tick as it was.
            let done = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? answer.done : true
            change(item, ChecklistDraftAnswer(done: done, text: text))
        })
        if item.kind == .number {
            HStack(spacing: 6) {
                TextField(item.label, text: binding, prompt: .placeholder("\u{2014}"))
                    .font(Theme.font(15, weight: .medium)).monospacedDigit()
                    .keyboardType(.numbersAndPunctuation)
                    .focused($focused, equals: item.id)
                    .padding(.horizontal, 10).frame(width: 110, height: 44)
                    .background(Theme.fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityLabel(item.unit.map { "\(item.label) in \($0)" } ?? item.label)
                    .accessibilityIdentifier("checklist-value-\(item.id)")
                if let unit = item.unit { Text(unit).font(Theme.font(14)).foregroundStyle(Theme.muted) }
            }
        } else {
            TextField(item.label, text: binding, prompt: .placeholder("Write what you found"), axis: .vertical)
                .font(Theme.font(15)).lineLimit(1...4)
                .focused($focused, equals: item.id)
                .padding(.horizontal, 10).padding(.vertical, 10).frame(minHeight: 44)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityLabel(item.label)
                .accessibilityIdentifier("checklist-value-\(item.id)")
        }
    }

    // MARK: Actions

    /// Closing sends what was just ticked at once, without waiting for the pause after typing.
    private func close() {
        focused = nil
        model.stopTimers()
        Task { await model.flush(api: api) }
        onDone()
    }

    private func change(_ item: ServerChecklistItem, _ answer: ChecklistDraftAnswer) {
        guard let runKey else { return }
        finishProblem = nil; said = nil
        model.set(runKey, item: item, to: answer, api: api)
    }

    private func toggle(_ item: ServerChecklistItem, _ answer: ChecklistDraftAnswer) {
        UISelectionFeedbackGenerator().selectionChanged()
        change(item, ChecklistDraftAnswer(done: !answer.done, text: answer.text))
    }

    private func start(_ template: ServerChecklistTemplate) async {
        starting = template.id
        defer { starting = nil }
        said = nil; finishProblem = nil
        openRun = await model.start(template, api: api)
    }

    private func finish() async {
        guard let runKey else { return }
        focused = nil
        busy = true
        defer { busy = false }
        switch await model.finish(runKey, api: api) {
        case .finished:
            finishProblem = nil
            said = "Finished. It\u{2019}s saved on the job."
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .onPhone:
            finishProblem = nil
            said = ChecklistRules.onPhoneWords
        case .problem(let words):
            finishProblem = words
        }
    }

    private func attach(_ image: UIImage, to item: ServerChecklistItem) {
        do {
            try JobPhotoAttach.save(image, jobID: jobID, caption: "Checklist \u{00B7} \(item.label)", prefix: "checklist",
                                    api: api, session: session, pendingMedia: pendingMedia)
            said = "Photo added to this job\u{2019}s photos."
        } catch { finishProblem = error.localizedDescription }
    }
}

#if DEBUG
/// Sample checklists for the design preview (`--paper-preview-job-checklists`): one run under way
/// with a teammate's answers, one finished, and two templates. Never shown against a real workspace.
enum ChecklistPreviewData {
    static let teammate = "00000000-0000-4000-8000-0000000000a7"
    static let names = [teammate: "Sam Ortiz"]

    static let hvac = ServerChecklistTemplate(id: "00000000-0000-4000-8000-00000000c101", title: "HVAC service", items: [
        .init(id: "thermostat", label: "Thermostat calls for heat and cool"),
        .init(id: "filter", label: "Air filter checked or replaced"),
        .init(id: "pressure-suction", label: "Suction pressure", kind: .number, unit: "psi", required: true),
        .init(id: "amps", label: "Compressor amp draw", kind: .number, unit: "A"),
        .init(id: "found", label: "What you found", kind: .text),
        .init(id: "electrical", label: "Electrical connections tight, no burn marks", required: true),
    ], revision: 3, archivedAt: nil, updatedAt: nil)

    static let visit = ServerChecklistTemplate(id: "00000000-0000-4000-8000-00000000c102", title: "General visit", items: [
        .init(id: "problem", label: "Confirmed the problem with the customer"),
        .init(id: "protect", label: "Floors and work area protected"),
        .init(id: "cleanup", label: "Work area cleaned up"),
    ], revision: 1, archivedAt: nil, updatedAt: nil)

    static let archived = ServerChecklistTemplate(id: "00000000-0000-4000-8000-00000000c103", title: "Old spring tune-up", items: [
        .init(id: "coil", label: "Outdoor coil clean and clear"),
    ], revision: 4, archivedAt: "2026-10-02T15:00:00Z", updatedAt: nil)

    static func stamp(_ minutesAgo: Double) -> String { ISO8601DateFormatter().string(from: Date().addingTimeInterval(-minutesAgo * 60)) }

    static var runs: [ServerChecklistRun] {
        let me = PaperPreview.actorID
        let finished = ServerChecklistRun(
            id: "00000000-0000-4000-8000-00000000c201", jobId: PaperPreview.jobID, clientRunId: nil, templateId: visit.id, templateRevision: 1,
            template: visit.copy,
            answers: visit.items.map { ServerChecklistAnswer(itemId: $0.id, done: true, value: nil, answeredByUserId: teammate, answeredAt: stamp(200)) },
            revision: 5, status: "completed", startedByUserId: teammate, startedAt: stamp(240), completedByUserId: teammate, completedAt: stamp(190))
        let open = ServerChecklistRun(
            id: "00000000-0000-4000-8000-00000000c202", jobId: PaperPreview.jobID, clientRunId: nil, templateId: hvac.id, templateRevision: 3,
            template: hvac.copy,
            answers: [
                .init(itemId: "thermostat", done: true, value: nil, answeredByUserId: teammate, answeredAt: stamp(40)),
                .init(itemId: "filter", done: true, value: nil, answeredByUserId: me, answeredAt: stamp(30)),
                .init(itemId: "pressure-suction", done: true, value: .number(118), answeredByUserId: me, answeredAt: stamp(20)),
            ],
            revision: 4, status: "in_progress", startedByUserId: teammate, startedAt: stamp(45))
        return [finished, open]
    }

    /// `--paper-preview-checklist-state list|run|done|offline|needed`.
    @MainActor static func model() -> (JobChecklistModel, String?) {
        let args = ProcessInfo.processInfo.arguments
        let state = args.firstIndex(of: "--paper-preview-checklist-state").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? "run"
        let model = JobChecklistModel()
        let open = runs[1].id
        switch state {
        case "offline":
            let draft = ChecklistDraft(runID: open, templateID: hvac.id, templateRevision: 3, template: hvac.copy, started: true,
                                       unsent: ["amps": .init(done: true, text: "14.6")])
            model.preview(runs: runs, templates: [hvac, visit], names: names, drafts: [draft], notes: [open: ChecklistRules.onPhoneWords], me: PaperPreview.actorID)
            return (model, open)
        case "list":
            model.preview(runs: runs, templates: [hvac, visit], names: names, me: PaperPreview.actorID)
            return (model, nil)
        case "done":
            model.preview(runs: runs, templates: [hvac, visit], names: names, me: PaperPreview.actorID)
            return (model, runs[0].id)
        default:
            model.preview(runs: runs, templates: [hvac, visit], names: names, me: PaperPreview.actorID)
            return (model, open)
        }
    }
}
#endif

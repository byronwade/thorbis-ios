import SwiftUI

// Business settings › Checklists, when checklists are kept on the server (feature
// `job_checklists`): the company's checklist templates. Anyone who can see jobs reads them; an
// owner (`organization.settings.edit`) adds, changes, puts away and brings back. Templates are
// never deleted. With the feature off the page lists the four that come with the app, as before.

enum ChecklistTemplateSaveResult: Equatable {
    case saved
    case problem(String)
    /// Someone else changed it first. Carries the template as it is now, when it could be read.
    case stale(String, ServerChecklistTemplate?)
}

@MainActor
final class ChecklistTemplatesModel: ObservableObject {
    @Published private(set) var templates: [ServerChecklistTemplate]?
    @Published private(set) var loadError: String?
    @Published private(set) var addingStarters = false
    @Published var notice: String?

    var active: [ServerChecklistTemplate] { (templates ?? []).filter { !$0.isArchived } }
    var archived: [ServerChecklistTemplate] { (templates ?? []).filter(\.isArchived) }

    #if DEBUG
    private var isPreview = false
    func preview(_ sample: [ServerChecklistTemplate]) { isPreview = true; templates = sample }
    #endif

    /// Owners also see the ones that were put away, so they can bring them back.
    func load(api: APIClient, includeArchived: Bool) async {
        #if DEBUG
        if isPreview { return }
        #endif
        let generation = api.requestGeneration
        do {
            let fresh = try await api.checklistTemplates(includeArchived: includeArchived)
            guard generation == api.requestGeneration else { return }
            templates = fresh; loadError = nil
        } catch is CancellationError {
        } catch {
            guard generation == api.requestGeneration else { return }
            loadError = error.isConnectivityFailure ? "No connection. Checklists need signal to change." : ChecklistProblem(error).words()
        }
    }

    private func put(_ template: ServerChecklistTemplate) {
        var next = templates ?? []
        if let index = next.firstIndex(where: { $0.id == template.id }) { next[index] = template } else { next.insert(template, at: 0) }
        templates = next
    }

    /// What `POST /v1/jobs/checklist-templates/{id}` takes for this edit: only what changed, with
    /// the revision the edit started from. Nil when nothing changed.
    static func update(from base: ServerChecklistTemplate, title: String, items: [ServerChecklistItem]) -> ChecklistTemplateUpdate? {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = clean(items)
        var body = ChecklistTemplateUpdate(expectedRevision: base.revision)
        if name != base.title { body.title = name }
        if cleaned != clean(base.items) { body.items = cleaned }
        return body.title == nil && body.items == nil ? nil : body
    }

    /// Items as they are sent: words trimmed, a unit only on a number.
    static func clean(_ items: [ServerChecklistItem]) -> [ServerChecklistItem] {
        items.map { item in
            let unit = item.unit?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return ServerChecklistItem(id: item.id, label: item.label.trimmingCharacters(in: .whitespacesAndNewlines), kind: item.kind,
                                       unit: item.kind == .number && !unit.isEmpty ? unit : nil, required: item.required)
        }
    }

    func save(base: ServerChecklistTemplate?, title: String, items: [ServerChecklistItem], api: APIClient) async -> ChecklistTemplateSaveResult {
        if let problem = ChecklistRules.problem(title: title, items: items) { return .problem(problem) }
        #if DEBUG
        if isPreview {
            put(ServerChecklistTemplate(id: base?.id ?? UUID().uuidString, title: title, items: Self.clean(items), revision: (base?.revision ?? 0) + 1))
            return .saved
        }
        #endif
        do {
            if let base {
                guard let body = Self.update(from: base, title: title, items: items) else { return .saved }
                put(try await api.updateChecklistTemplate(base.id, body))
            } else {
                put(try await api.createChecklistTemplate(ChecklistTemplateCreate(title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                                                                  items: Self.clean(items))))
            }
            return .saved
        } catch is CancellationError {
            return .problem("That was stopped before it saved. Try again.")
        } catch {
            let problem = ChecklistProblem(error)
            guard problem == .stale, let base else { return .problem(Self.words(problem)) }
            // Someone else saved first: read it again so the next Save names the current revision.
            await load(api: api, includeArchived: true)
            let fresh = templates?.first { $0.id == base.id }
            return .stale("Someone else changed this checklist. Press Save again to keep your version, or Cancel to keep theirs.", fresh)
        }
    }

    static func words(_ problem: ChecklistProblem) -> String {
        switch problem {
        case .offline: "No connection. Checklists need signal to change."
        case .templateArchived: "This checklist is put away. Bring it back to change it."
        case .forbidden: "Only an owner can change checklists."
        default: problem.words()
        }
    }

    /// Puts a checklist away or brings it back. Both are safe to repeat.
    func setArchived(_ template: ServerChecklistTemplate, _ archived: Bool, api: APIClient) async -> String? {
        #if DEBUG
        if isPreview {
            var next = template; next.archivedAt = archived ? ISO8601DateFormatter().string(from: Date()) : nil
            put(next); return nil
        }
        #endif
        do {
            put(archived ? try await api.archiveChecklistTemplate(template.id) : try await api.restoreChecklistTemplate(template.id))
            return nil
        } catch is CancellationError {
            return nil
        } catch { return Self.words(ChecklistProblem(error)) }
    }

    /// Creates the app's built-in checklists the workspace does not have yet. Only ever called
    /// from the owner's own tap. Stops at the first refusal and says how far it got.
    func addStarters(api: APIClient, organization: String, defaults: UserDefaults = .standard) async {
        guard !addingStarters else { return }
        addingStarters = true
        defer { addingStarters = false }
        let wanted = ChecklistRules.startersToAdd(existing: templates ?? [])
        var added = 0
        for starter in wanted {
            do {
                #if DEBUG
                if isPreview { put(ServerChecklistTemplate(id: UUID().uuidString, title: starter.title, items: starter.items, revision: 1)); added += 1; continue }
                #endif
                put(try await api.createChecklistTemplate(starter))
                added += 1
            } catch is CancellationError {
                return
            } catch {
                let why = Self.words(ChecklistProblem(error))
                notice = added == 0 ? why : "\(added) of \(wanted.count) added. \(why)"
                return
            }
        }
        ChecklistDraftStore.markStartersAdded(organization: organization, defaults: defaults)
        notice = added == 0 ? "Your company already has these checklists." : "\(added) starter checklist\(added == 1 ? "" : "s") added. Tap one to change it."
    }
}

private struct ChecklistTemplateEditorRequest: Identifiable {
    let id = UUID()
    let template: ServerChecklistTemplate?
}

/// The checklists card on Business settings › Checklists when the server keeps them.
struct ServerChecklistTemplatesSection: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @StateObject private var model = ChecklistTemplatesModel()
    @State private var editor: ChecklistTemplateEditorRequest?
    @State private var reading: ServerChecklistTemplate?
    @State private var confirmStarters = false

    private var canManage: Bool { ChecklistFeature.canManage(session) }
    private var offersStarters: Bool {
        guard canManage, let templates = model.templates, let organization = session.activeOrganization?.id else { return false }
        return !ChecklistDraftStore.startersAdded(organization: organization) && !ChecklistRules.startersToAdd(existing: templates).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = model.loadError {
                ErrorBanner(message: error) { await load() }.padding(.horizontal, -PaperCardMetrics.margin)
            }
            if let notice = model.notice {
                Label(notice, systemImage: "info.circle").font(Theme.font(14)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
                    .accessibilityIdentifier("checklist-templates-notice")
            }
            if model.templates == nil, model.loadError == nil {
                SkeletonSection(rows: 3)
            } else if model.templates != nil {
                PaperSection(title: "Job checklists", count: model.active.count) {
                    if model.active.isEmpty {
                        PaperEmptyState(symbol: "checklist", title: "No checklists yet",
                                        message: canManage ? "Add one for the work your team does. A tech fills it in on the job."
                                                           : "Your company has not added any checklists.",
                                        actionTitle: canManage ? "Add a checklist" : nil) {
                            editor = ChecklistTemplateEditorRequest(template: nil)
                        }
                        .padding(.vertical, 12)
                    } else {
                        ForEach(Array(model.active.enumerated()), id: \.element.id) { index, template in
                            if index > 0 { WellDivider(leading: PaperCardMetrics.inset) }
                            row(template)
                        }
                    }
                } accessory: {
                    if canManage, !model.active.isEmpty {
                        Button { editor = ChecklistTemplateEditorRequest(template: nil) } label: {
                            Text("Add").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.brandText)
                                .padding(.vertical, 13).contentShape(Rectangle()).padding(.vertical, -13)
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel("Add a checklist")
                        .accessibilityIdentifier("checklist-template-add")
                    }
                }
                if offersStarters {
                    Button { confirmStarters = true } label: {
                        PaperPillLabel(title: "Add the starter checklists", symbol: "plus", height: 48, tinted: true, busy: model.addingStarters)
                    }
                    .buttonStyle(PressStyle())
                    .disabled(model.addingStarters)
                    .accessibilityIdentifier("checklist-template-starters")
                    note("Adds \(Self.list(ChecklistRules.startersToAdd(existing: model.templates ?? []).map(\.title))). You can change them after.")
                }
                note(canManage ? "A tech starts one from a job. The answers are saved on the job for the whole team."
                               : "A tech starts one from a job. An owner changes them in Business settings.")
                if canManage, !model.archived.isEmpty {
                    PaperSection(title: "Put away", count: model.archived.count) {
                        ForEach(Array(model.archived.enumerated()), id: \.element.id) { index, template in
                            if index > 0 { WellDivider(leading: PaperCardMetrics.inset) }
                            row(template)
                        }
                    } accessory: { EmptyView() }
                    .padding(.top, 12)
                    note("Put-away checklists can\u{2019}t be started. Ones already on a job stay as they were.")
                }
            }
        }
        .task { await load() }
        .sheet(item: $editor) { request in SheetSurface {
            ChecklistTemplateEditor(existing: request.template,
                                    onSave: { base, title, items in await model.save(base: base, title: title, items: items, api: api) },
                                    onArchive: { template, archived in await model.setArchived(template, archived, api: api) })
        } }
        .thorbisDestination(item: $reading) { ServerChecklistStepsView(template: $0) }
        .thorbisConfirm("Add the starter checklists?",
                        message: "They are added for your whole company. You can change them or put them away after.",
                        isPresented: $confirmStarters,
                        actions: [ThorbisConfirmAction("Add them") {
                            guard let organization = session.activeOrganization?.id else { return }
                            Task { await model.addStarters(api: api, organization: organization) }
                        }])
    }

    /// "HVAC service, Plumbing repair and General visit".
    static func list(_ names: [String]) -> String {
        guard names.count > 1, let last = names.last else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + last
    }

    private func load() async {
        #if DEBUG
        if PaperPreview.enabled {
            let empty = ProcessInfo.processInfo.arguments.contains("--paper-preview-checklist-templates-empty")
            if model.templates == nil { model.preview(empty ? [] : [ChecklistPreviewData.hvac, ChecklistPreviewData.visit, ChecklistPreviewData.archived]) }
            if ProcessInfo.processInfo.arguments.contains("--paper-preview-checklist-template-edit"), editor == nil {
                editor = ChecklistTemplateEditorRequest(template: ChecklistPreviewData.hvac)
            }
            return
        }
        #endif
        await model.load(api: api, includeArchived: canManage)
    }

    private func row(_ template: ServerChecklistTemplate) -> some View {
        Button {
            if canManage { editor = ChecklistTemplateEditorRequest(template: template) } else { reading = template }
        } label: {
            PaperListRow(title: template.title, subtitle: ChecklistRules.summary(template.items)) { PaperChevron() }
        }
        .buttonStyle(RowPressStyle())
        .accessibilityHint(canManage ? (template.isArchived ? "Opens it to bring back" : "Opens it to change") : "Shows its steps")
        .accessibilityIdentifier("checklist-template-row-\(template.id)")
    }

    private func note(_ text: String) -> some View {
        Text(text).font(Theme.font(13)).foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }
}

/// One checklist's steps, to read (anyone who is not an owner).
struct ServerChecklistStepsView: View {
    let template: ServerChecklistTemplate

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PaperHeader(title: template.title, subtitle: ChecklistRules.summary(template.items))
                    .environment(\.paperMenuButton, false)
                    .environment(\.paperDrawer, nil)
                PaperCard {
                    ForEach(Array(template.items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { WellDivider(leading: PaperCardMetrics.inset) }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.label).font(Theme.font(16, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                            Text(ChecklistRules.kindLine(item)).font(Theme.font(14)).foregroundStyle(Theme.muted)
                        }
                        .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 12)
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 10).padding(.bottom, 44)
            }
            .frame(maxWidth: 600, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.canvas)
        .foregroundStyle(Theme.foreground)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Add or change one checklist. Save is never pre-disabled: pressed with something missing, it says what.
private struct ChecklistTemplateEditor: View {
    let onSave: @MainActor (ServerChecklistTemplate?, String, [ServerChecklistItem]) async -> ChecklistTemplateSaveResult
    let onArchive: @MainActor (ServerChecklistTemplate, Bool) async -> String?
    @Environment(\.dismiss) private var dismiss
    /// The template this edit started from; replaced when someone else's change is read.
    @State private var base: ServerChecklistTemplate?
    @State private var title: String
    @State private var items: [ServerChecklistItem]
    @State private var problem: String?
    @State private var busy = false
    @State private var confirmingArchive = false
    @FocusState private var focused: String?

    init(existing: ServerChecklistTemplate?,
         onSave: @escaping @MainActor (ServerChecklistTemplate?, String, [ServerChecklistItem]) async -> ChecklistTemplateSaveResult,
         onArchive: @escaping @MainActor (ServerChecklistTemplate, Bool) async -> String?) {
        self.onSave = onSave
        self.onArchive = onArchive
        _base = State(initialValue: existing)
        _title = State(initialValue: existing?.title ?? "")
        _items = State(initialValue: existing?.items ?? [ServerChecklistItem(id: "step-1", label: "")])
    }

    private var archived: Bool { base?.isArchived ?? false }
    private static let kinds: [(value: ServerChecklistItem.Kind, label: String)] = [(.tick, "Check"), (.text, "Words"), (.number, "Number")]

    var body: some View {
        VStack(spacing: 0) {
            if archived {
                PaperTaskBar(title: "Put-away checklist", cancelTitle: "Close", onCancel: { dismiss() })
            } else {
                LearnEditorHeader(title: base == nil ? "New checklist" : "Edit checklist", saveIdentifier: "checklist-template-save",
                                  onCancel: { dismiss() }, onSave: save)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if archived {
                        Text("This checklist is put away. Techs can\u{2019}t start it. Bring it back to use or change it.")
                            .font(Theme.font(14)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }
                    field("Name") {
                        TextField("", text: $title, prompt: .placeholder("AC tune-up"))
                            .font(Theme.font(16)).focused($focused, equals: "title")
                            .onChange(of: title) { _, _ in problem = nil }
                            .accessibilityLabel("Checklist name")
                            .accessibilityIdentifier("checklist-template-title")
                    }
                    Text("Steps").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted).padding(.horizontal, 4).padding(.top, 4)
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in step(index, item) }
                    if !archived, items.count < ChecklistRules.itemLimit {
                        Button(action: addStep) {
                            PaperPillLabel(title: "Add a step", symbol: "plus", height: 48, tinted: true)
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityIdentifier("checklist-template-add-step")
                    }
                    if let problem {
                        InlineProblem(message: problem).padding(.horizontal, 4)
                            .accessibilityIdentifier("checklist-template-problem")
                    }
                    if busy { ProgressView().frame(maxWidth: .infinity).padding(.top, 4).accessibilityLabel("Saving") }
                    if let base {
                        Button { focused = nil; if archived { setArchived(false) } else { confirmingArchive = true } } label: {
                            Text(archived ? "Bring back" : "Put away").font(Theme.font(16, weight: .medium))
                                .foregroundStyle(archived ? Theme.brandText : Theme.destructive)
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle())
                        .padding(.top, 8)
                        .accessibilityIdentifier(archived ? "checklist-template-restore" : "checklist-template-archive")
                        Text(archived ? "It goes back on the list techs start from."
                                      : "Techs can\u{2019}t start \u{201C}\(base.title)\u{201D} any more. Ones already on a job stay. You can bring it back.")
                            .font(Theme.font(13)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .disabled(busy)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background.ignoresSafeArea())
        .onAppear { if base == nil { focused = "title" } }
        .thorbisConfirm("Put this checklist away?",
                        message: "Techs can\u{2019}t start it any more. Ones already on a job stay as they are. You can bring it back.",
                        isPresented: $confirmingArchive,
                        actions: [ThorbisConfirmAction("Put away", role: .destructive) { setArchived(true) }])
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
            content()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .disabled(archived)
    }

    private func binding(_ index: Int) -> Binding<ServerChecklistItem> {
        Binding(get: { items.indices.contains(index) ? items[index] : ServerChecklistItem(id: "", label: "") },
                set: { if items.indices.contains(index) { items[index] = $0; problem = nil } })
    }

    private func step(_ index: Int, _ item: ServerChecklistItem) -> some View {
        let value = binding(index)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Text("\(index + 1)").font(Theme.font(15, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.muted)
                    .frame(width: 22, alignment: .leading).padding(.top, 2)
                TextField("", text: value.label, prompt: .placeholder("What the tech checks"), axis: .vertical)
                    .font(Theme.font(16)).lineLimit(1...3)
                    .focused($focused, equals: item.id)
                    .accessibilityLabel("Step \(index + 1)")
                    .accessibilityIdentifier("checklist-template-step-\(index)")
            }
            if !archived {
                ThorbisSegmented(options: Self.kinds, selection: value.kind)
                    .accessibilityLabel("What step \(index + 1) asks for")
                if item.kind == .number {
                    HStack(spacing: 8) {
                        Text("Unit").font(Theme.font(15)).foregroundStyle(Theme.muted)
                        TextField("", text: Binding(get: { item.unit ?? "" }, set: { value.wrappedValue.unit = $0.isEmpty ? nil : $0 }),
                                  prompt: .placeholder("psi"))
                            .font(Theme.font(15)).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .padding(.horizontal, 10).frame(width: 110, height: 44)
                            .background(Theme.fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .accessibilityLabel("Unit for step \(index + 1)")
                    }
                }
                Toggle(isOn: value.required) {
                    Text("Needed to finish").font(Theme.font(15)).fixedSize(horizontal: false, vertical: true)
                }
                .tint(Theme.brand)
                .frame(minHeight: 44)
                HStack(spacing: 4) {
                    move(index, by: -1, symbol: "chevron.up", word: "Move step \(index + 1) up")
                    move(index, by: 1, symbol: "chevron.down", word: "Move step \(index + 1) down")
                    Spacer(minLength: 0)
                    if items.count > 1 {
                        Button { withMotion { _ = items.remove(at: index) }; problem = nil } label: {
                            Text("Remove").font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.destructive)
                                .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel("Remove step \(index + 1)")
                    }
                }
            } else {
                Text(ChecklistRules.kindLine(item)).font(Theme.font(14)).foregroundStyle(Theme.muted).padding(.leading, 30)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .disabled(archived)
    }

    private func move(_ index: Int, by offset: Int, symbol: String, word: String) -> some View {
        let possible = items.indices.contains(index + offset)
        return Button { withMotion { items.swapAt(index, index + offset) } } label: {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(possible ? Theme.foreground : Theme.muted.opacity(0.5))
                .frame(width: 36, height: 36).background(Theme.fill, in: Circle())
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(!possible)
        .accessibilityLabel(word)
    }

    private func addStep() {
        // A key that is not in use; the label's own key is set when the checklist is saved.
        let id = ChecklistRules.itemID(for: "step \(items.count + 1)", existing: items.map(\.id))
        withMotion { items.append(ServerChecklistItem(id: id, label: "")) }
        problem = nil
        focused = id
    }

    /// New steps get a key from their words; steps the server already has keep theirs, so
    /// answers on jobs stay attached.
    static func keyed(_ items: [ServerChecklistItem], keeping known: Set<String>) -> [ServerChecklistItem] {
        var taken = items.map(\.id).filter(known.contains)
        return items.map { item in
            guard !known.contains(item.id) else { return item }
            var next = item
            next.id = ChecklistRules.itemID(for: item.label, existing: taken)
            taken.append(next.id)
            return next
        }
    }

    private func save() {
        guard !busy else { return }
        focused = nil
        if let found = ChecklistRules.problem(title: title, items: items) { problem = found; return }
        busy = true
        let sending = Self.keyed(items, keeping: Set(base?.items.map(\.id) ?? []))
        Task {
            let result = await onSave(base, title, sending)
            busy = false
            switch result {
            case .saved: dismiss()
            case .problem(let words): problem = words
            case .stale(let words, let fresh):
                problem = words
                if let fresh { base = fresh }
            }
        }
    }

    private func setArchived(_ archived: Bool) {
        guard !busy, let base else { return }
        busy = true
        Task {
            let failure = await onArchive(base, archived)
            busy = false
            if let failure { problem = failure } else { dismiss() }
        }
    }
}

extension ChecklistTemplatesModel {
    /// New steps keyed from their words, known ones untouched (the editor's rule, for tests).
    static func keyed(_ items: [ServerChecklistItem], keeping known: Set<String>) -> [ServerChecklistItem] {
        ChecklistTemplateEditor.keyed(items, keeping: known)
    }
}

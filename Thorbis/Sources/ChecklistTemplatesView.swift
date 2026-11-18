import SwiftUI

// Business settings › Checklists (Paper 99).
//
// The server keeps ONE closeout policy per company (`GET/POST /v1/jobs/closeout-policy`): whether
// a job note is required, how many photos, and an ordered list of named checks a technician
// confirms before a job can be finished. There are no named templates on the server, so this page
// edits that one list. A save sends the whole policy back; everything this page does not edit
// (the customer-signature and payment rules) is sent back exactly as it was read.
//
// The checklists a technician runs from a job's tools come with the app (JobChecklistTemplates);
// they are listed here to read, not to change.

/// The company's closeout policy as this page reads it. Missing fields mean "nothing required",
/// the same default the server answers with before anything is configured.
struct CompanyCloseoutPolicy: Decodable, Equatable {
    var requireNotes: Bool
    var requiredPhotoCount: Int
    var requiredChecks: [FieldCloseoutCheckDefinition]
    var updatedAt: String?

    init(requireNotes: Bool = false, requiredPhotoCount: Int = 0,
         requiredChecks: [FieldCloseoutCheckDefinition] = [], updatedAt: String? = nil) {
        self.requireNotes = requireNotes
        self.requiredPhotoCount = requiredPhotoCount
        self.requiredChecks = requiredChecks
        self.updatedAt = updatedAt
    }

    private enum Keys: String, CodingKey { case requireNotes, requiredPhotoCount, requiredChecks, updatedAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        requireNotes = try c.decodeIfPresent(Bool.self, forKey: .requireNotes) ?? false
        requiredPhotoCount = max(0, try c.decodeIfPresent(Int.self, forKey: .requiredPhotoCount) ?? 0)
        // A check that can't be read is an error, never dropped: a save would then delete it.
        requiredChecks = try c.decodeIfPresent([FieldCloseoutCheckDefinition].self, forKey: .requiredChecks) ?? []
        updatedAt = try? c.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    /// What `POST /v1/jobs/closeout-policy` takes (setCloseoutPolicyInputSchema): the whole policy.
    struct Write: Encodable, Equatable {
        let requireNotes: Bool
        let requiredPhotoCount: Int
        let requiredChecks: [FieldCloseoutCheckDefinition]
    }

    var write: Write {
        Write(requireNotes: requireNotes, requiredPhotoCount: requiredPhotoCount, requiredChecks: requiredChecks)
    }
}

/// The edits an owner can make to the checks, and the server's limits on them.
enum CloseoutPolicyRules {
    static let maxChecks = 50
    static let maxLabel = 200
    static let maxKey = 100
    static let maxPhotos = 50
    /// Keys the server reserves for its signature and payment rules.
    static let reservedKeys: Set<String> = ["customer_authorization", "payment_or_unpaid_disposition"]

    /// A check a technician confirms by hand. The other kinds are proved by a signature or an invoice.
    static func isAcknowledgement(_ check: FieldCloseoutCheckDefinition) -> Bool {
        check.kind == nil || check.kind == "acknowledgement"
    }

    static func acknowledgements(_ policy: CompanyCloseoutPolicy) -> [FieldCloseoutCheckDefinition] {
        policy.requiredChecks.filter(isAcknowledgement)
    }

    /// Why a typed name can't be saved, or nil when it can.
    static func problem(label: String, in policy: CompanyCloseoutPolicy, replacing key: String? = nil) -> String? {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Type what the tech confirms." }
        if trimmed.count > maxLabel { return "Keep it under \(maxLabel) characters." }
        if key == nil, policy.requiredChecks.count >= maxChecks { return "A company can have up to \(maxChecks) checks." }
        let taken = policy.requiredChecks.contains {
            $0.key != key && $0.label.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(trimmed) == .orderedSame
        }
        return taken ? "There is already a check with this name." : nil
    }

    /// A stable key for a new check, made from its name: lowercase words joined by "_", never one
    /// already in use and never one the server reserves. The key does not change when the check
    /// is renamed, so a job that already confirmed it stays confirmed.
    static func key(for label: String, existing: [String]) -> String {
        let folded = label.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")).lowercased()
        var words: [String] = []
        var current = ""
        for scalar in folded.unicodeScalars {
            let isPlain = (scalar.value >= 97 && scalar.value <= 122) || (scalar.value >= 48 && scalar.value <= 57)
            if isPlain { current.unicodeScalars.append(scalar) } else if !current.isEmpty { words.append(current); current = "" }
        }
        if !current.isEmpty { words.append(current) }
        var base = String(words.joined(separator: "_").prefix(80))
        while base.hasSuffix("_") { base.removeLast() }
        if base.isEmpty { base = "check" }
        let taken = Set(existing).union(reservedKeys)
        if !taken.contains(base) { return base }
        var number = 2
        while taken.contains("\(base)_\(number)") { number += 1 }
        return "\(base)_\(number)"
    }

    /// A new check goes after the last one a technician confirms, before any rule that follows.
    static func adding(_ label: String, to policy: CompanyCloseoutPolicy) -> CompanyCloseoutPolicy {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let check = FieldCloseoutCheckDefinition(key: key(for: trimmed, existing: policy.requiredChecks.map(\.key)),
                                                 label: trimmed, kind: nil, allowUnpaidDisposition: nil)
        var next = policy
        if let last = next.requiredChecks.lastIndex(where: isAcknowledgement) {
            next.requiredChecks.insert(check, at: last + 1)
        } else {
            next.requiredChecks.insert(check, at: 0)
        }
        return next
    }

    static func renaming(_ key: String, to label: String, in policy: CompanyCloseoutPolicy) -> CompanyCloseoutPolicy {
        var next = policy
        next.requiredChecks = policy.requiredChecks.map { check in
            guard check.key == key, isAcknowledgement(check) else { return check }
            return FieldCloseoutCheckDefinition(key: check.key, label: label.trimmingCharacters(in: .whitespacesAndNewlines),
                                                kind: check.kind, allowUnpaidDisposition: check.allowUnpaidDisposition)
        }
        return next
    }

    static func removing(_ key: String, from policy: CompanyCloseoutPolicy) -> CompanyCloseoutPolicy {
        var next = policy
        next.requiredChecks.removeAll { $0.key == key && isAcknowledgement($0) }
        return next
    }

    /// Moves one check up (-1) or down (+1) among the checks a technician confirms. The signature
    /// and payment rules keep their places. Out of range leaves the policy as it was.
    static func moving(_ key: String, by offset: Int, in policy: CompanyCloseoutPolicy) -> CompanyCloseoutPolicy {
        let slots = policy.requiredChecks.indices.filter { isAcknowledgement(policy.requiredChecks[$0]) }
        guard let from = slots.firstIndex(where: { policy.requiredChecks[$0].key == key }),
              slots.indices.contains(from + offset) else { return policy }
        var next = policy
        next.requiredChecks.swapAt(slots[from], slots[from + offset])
        return next
    }

    static func canMove(_ key: String, by offset: Int, in policy: CompanyCloseoutPolicy) -> Bool {
        let keys = acknowledgements(policy).map(\.key)
        guard let from = keys.firstIndex(of: key) else { return false }
        return keys.indices.contains(from + offset)
    }

    static func photos(_ count: Int) -> Int { min(max(count, 0), maxPhotos) }
}

extension APIClient {
    func companyCloseoutPolicy() async throws -> CompanyCloseoutPolicy {
        try await send("GET", "/v1/jobs/closeout-policy")
    }

    /// Replaces the company's policy; the server answers with what it saved.
    func setCompanyCloseoutPolicy(_ policy: CompanyCloseoutPolicy) async throws -> CompanyCloseoutPolicy {
        try await send("POST", "/v1/jobs/closeout-policy", body: policy.write)
    }
}

@MainActor
final class ChecklistSettingsModel: ObservableObject {
    @Published private(set) var policy: CompanyCloseoutPolicy?
    @Published private(set) var loadError: String?
    @Published private(set) var saving = false
    @Published var saveError: String?

    func load(api: APIClient, session: SessionController) async {
        #if DEBUG
        if PaperPreview.enabled { if policy == nil { policy = Self.previewPolicy }; return }
        #endif
        let generation = session.generation
        do {
            let fresh = try await api.companyCloseoutPolicy()
            guard session.generation == generation else { return }
            policy = fresh
            loadError = nil
        } catch is CancellationError {
        } catch {
            guard session.generation == generation else { return }
            loadError = error.plainMessage(subject: "checklists")
        }
    }

    /// Sends the whole policy. On success the screen shows what the server saved; on failure it
    /// keeps what was there and returns the reason.
    @discardableResult
    func save(_ next: CompanyCloseoutPolicy, api: APIClient, session: SessionController) async -> String? {
        guard next != policy else { return nil }
        guard !saving else { return "Still saving the last change. Try again in a moment." }
        #if DEBUG
        if PaperPreview.enabled { policy = next; return nil }
        #endif
        saving = true
        defer { saving = false }
        let generation = session.generation
        do {
            let saved = try await api.setCompanyCloseoutPolicy(next)
            guard session.generation == generation else { return nil }
            policy = saved
            saveError = nil
            return nil
        } catch is CancellationError {
            return nil
        } catch {
            return error.plainMessage(subject: "checklists")
        }
    }

    #if DEBUG
    /// Design preview only (`--paper-preview`); never shown against a real workspace.
    static let previewPolicy = CompanyCloseoutPolicy(
        requireNotes: true, requiredPhotoCount: 2,
        requiredChecks: [
            .init(key: "swept_area", label: "Swept and cleaned the work area", kind: nil, allowUnpaidDisposition: nil),
            .init(key: "old_parts", label: "Showed the customer the old parts", kind: "acknowledgement", allowUnpaidDisposition: nil),
            .init(key: "customer_authorization", label: "Customer signed for the work", kind: "customer_authorization", allowUnpaidDisposition: nil),
        ])
    #endif
}

private struct CloseoutCheckEditorRequest: Identifiable {
    let id = UUID()
    let check: FieldCloseoutCheckDefinition?
}

/// Business settings › Checklists.
struct ChecklistTemplatesView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @StateObject private var model = ChecklistSettingsModel()
    @State private var editor: CloseoutCheckEditorRequest?
    @State private var reordering = false
    /// The order being arranged; sent once, when "Done" is pressed.
    @State private var arranged: CompanyCloseoutPolicy?
    /// The photo count being stepped; sent a moment after the last press.
    @State private var photoDraft: Int?
    @State private var photoSave: Task<Void, Never>?
    @State private var openedTemplate: ChecklistTemplate?

    private var canView: Bool { session.can("job.view", feature: "jobs") }
    private var canEdit: Bool { session.can("organization.settings.edit", feature: "jobs") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Paper 99: the 34 Bold title, one muted line, then the cards.
                PaperHeader(title: "Checklists", subtitle: "What your team checks on each kind of job")
                    .environment(\.paperMenuButton, false)
                    .environment(\.paperDrawer, nil)
                VStack(alignment: .leading, spacing: 20) {
                    // Paper 99 opens with the card of checklists, then the rules under it.
                    if canView { templates }
                    if !canView {
                        InlineProblem(message: "Ask your office for access to jobs to see the company’s checks.")
                            .padding(.horizontal, 4)
                    } else if let policy = arranged ?? model.policy {
                        if let error = model.saveError {
                            ErrorBanner(message: error).padding(.horizontal, -PaperCardMetrics.margin)
                        }
                        checks(policy)
                        options(policy)
                    } else if let error = model.loadError {
                        ErrorBanner(message: error) { await model.load(api: api, session: session) }
                            .padding(.horizontal, -PaperCardMetrics.margin)
                    } else {
                        SkeletonSection(rows: 4)
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
        .accessibilityIdentifier("checklists-root")
        .toolbar {
            if canEdit, model.policy != nil, !reordering {
                ThorbisToolbarItem(placement: .topBarTrailing) {
                    Button { editor = CloseoutCheckEditorRequest(check: nil) } label: { CreamCircleLabel(symbol: "plus", ink: true) }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel("Add a check")
                        .accessibilityIdentifier("checklists-add")
                }
            }
        }
        .refreshable { if canView, !reordering { await model.load(api: api, session: session) } }
        .task { if canView { await model.load(api: api, session: session) } }
        .sheet(item: $editor) { request in SheetSurface {
            CloseoutCheckEditor(existing: request.check, policy: model.policy ?? CompanyCloseoutPolicy(),
                                onSave: { label in await save(label: label, for: request.check) },
                                onRemove: { if let check = request.check { return await remove(check) } else { return nil } })
        } }
        .thorbisDestination(item: $openedTemplate) { ChecklistTemplateStepsView(template: $0) }
        .sensoryFeedback(.success, trigger: model.policy?.updatedAt)
    }

    // MARK: The company's checks

    @ViewBuilder
    private func checks(_ policy: CompanyCloseoutPolicy) -> some View {
        let items = CloseoutPolicyRules.acknowledgements(policy)
        VStack(alignment: .leading, spacing: 8) {
            PaperSection(title: "Before a job is finished", count: items.count) {
                if items.isEmpty {
                    PaperEmptyState(symbol: "checklist", title: "No checks yet",
                                    message: canEdit ? "Add what a tech should confirm before finishing a job."
                                                     : "Your company has not added any checks.",
                                    actionTitle: canEdit ? "Add a check" : nil) {
                        editor = CloseoutCheckEditorRequest(check: nil)
                    }
                    .padding(.vertical, 12)
                } else {
                    ForEach(Array(items.enumerated()), id: \.element.key) { index, check in
                        if index > 0 { WellDivider(leading: PaperCardMetrics.inset) }
                        checkRow(check, position: index + 1, of: items.count, in: policy)
                    }
                }
            } accessory: {
                if canEdit, items.count > 1 {
                    Button { reordering ? finishReordering() : startReordering() } label: {
                        Text(reordering ? "Done" : "Reorder").font(Theme.font(13, weight: .semibold))
                            .foregroundStyle(Theme.brandText)
                            .padding(.vertical, 13).contentShape(Rectangle()).padding(.vertical, -13)
                    }
                    .buttonStyle(PressStyle())
                    .disabled(model.saving)
                    .accessibilityIdentifier("checklists-reorder")
                }
            }
            note(canEdit
                 ? "A job can’t be finished until a tech confirms each of these. Changes apply to every open job."
                 : "A job can’t be finished until a tech confirms each of these. An owner changes them in Business settings.")
        }
    }

    @ViewBuilder
    private func checkRow(_ check: FieldCloseoutCheckDefinition, position: Int, of total: Int,
                          in policy: CompanyCloseoutPolicy) -> some View {
        let label = Text(check.label).font(Theme.font(16, weight: .medium))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        if reordering {
            HStack(spacing: 4) {
                label.accessibilityLabel("\(check.label), \(position) of \(total)")
                moveButton(check, by: -1, symbol: "chevron.up", word: "Move up", in: policy)
                moveButton(check, by: 1, symbol: "chevron.down", word: "Move down", in: policy)
            }
            .padding(.leading, PaperCardMetrics.inset).padding(.trailing, 6).padding(.vertical, 6)
            .frame(minHeight: 56)
        } else if canEdit {
            Button { editor = CloseoutCheckEditorRequest(check: check) } label: {
                HStack(spacing: 8) {
                    label
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.muted).accessibilityHidden(true)
                }
                .padding(.leading, PaperCardMetrics.inset).padding(.trailing, 14).padding(.vertical, 12)
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .accessibilityHint("Rename or remove")
        } else {
            label
                .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 12)
                .frame(minHeight: 56)
        }
    }

    private func moveButton(_ check: FieldCloseoutCheckDefinition, by offset: Int, symbol: String, word: String,
                            in policy: CompanyCloseoutPolicy) -> some View {
        let possible = CloseoutPolicyRules.canMove(check.key, by: offset, in: policy)
        return Button {
            withMotion { arranged = CloseoutPolicyRules.moving(check.key, by: offset, in: policy) }
        } label: {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(possible ? Theme.foreground : Theme.muted.opacity(0.5))
                .frame(width: 36, height: 36)
                .background(Theme.fill, in: Circle())
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(!possible)
        .accessibilityLabel("\(word): \(check.label)")
    }

    // MARK: Options (Paper 99's second card): the policy's other rules

    @ViewBuilder
    private func options(_ policy: CompanyCloseoutPolicy) -> some View {
        let fixed = policy.requiredChecks.filter { !CloseoutPolicyRules.isAcknowledgement($0) }
        let photos = photoDraft ?? policy.requiredPhotoCount
        if canEdit || policy.requireNotes || policy.requiredPhotoCount > 0 || !fixed.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                PaperSection("Options") {
                    if canEdit {
                        Toggle(isOn: Binding(get: { policy.requireNotes }, set: { on in
                            var next = policy
                            next.requireNotes = on
                            apply(next)
                        })) {
                            Text("Require a job note").font(Theme.font(16, weight: .medium))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .tint(Theme.brand)
                        .disabled(model.saving || reordering)
                        .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 9)
                        .frame(minHeight: 56)
                        .accessibilityIdentifier("checklists-require-note")
                        WellDivider(leading: PaperCardMetrics.inset)
                        HStack(spacing: 8) {
                            Text("Photos required").font(Theme.font(16, weight: .medium))
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityHidden(true)
                            SalesQuantityStepper(value: photos, range: 0...CloseoutPolicyRules.maxPhotos,
                                                 name: photos == 1 ? "photo required" : "photos required") { stepPhotos($0, policy) }
                                .disabled(reordering)
                        }
                        .padding(.leading, PaperCardMetrics.inset).padding(.trailing, 10).padding(.vertical, 6)
                        .frame(minHeight: 56)
                    } else {
                        fact("Job note", policy.requireNotes ? "Required" : "Not required")
                        WellDivider(leading: PaperCardMetrics.inset)
                        fact("Photos", policy.requiredPhotoCount == 0 ? "Not required" : "\(policy.requiredPhotoCount) required")
                    }
                    ForEach(fixed, id: \.key) { rule in
                        WellDivider(leading: PaperCardMetrics.inset)
                        fact(rule.label, "Required")
                    }
                }
                if !fixed.isEmpty {
                    note("Signature and payment rules are proved by the job’s own records. They can’t be changed in the app yet.")
                }
            }
        }
    }

    private func fact(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(Theme.font(16, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            StatusWord(text: value)
        }
        .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 12)
        .frame(minHeight: 56)
        .accessibilityElement(children: .combine)
    }

    // MARK: The checklists that come with the app

    private var templates: some View {
        VStack(alignment: .leading, spacing: 8) {
            PaperCard {
                VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(ChecklistTemplates.all.enumerated()), id: \.element.id) { index, template in
                    if index > 0 { WellDivider(leading: PaperCardMetrics.inset) }
                    Button { openedTemplate = template } label: {
                        PaperListRow(title: template.title,
                                     subtitle: "\(template.items.count) step\(template.items.count == 1 ? "" : "s")") {
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.muted).accessibilityHidden(true)
                        }
                    }
                    .buttonStyle(RowPressStyle())
                }
            }
            }
            note("These come with the app. A tech runs one from a job’s tools and the result is saved as a job note. They can’t be changed yet.")
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(Theme.font(13)).foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    // MARK: Changes

    private func apply(_ next: CompanyCloseoutPolicy) {
        Task { model.saveError = await model.save(next, api: api, session: session) }
    }

    private func save(label: String, for existing: FieldCloseoutCheckDefinition?) async -> String? {
        guard let policy = model.policy else { return "The company’s checks have not loaded yet." }
        if let problem = CloseoutPolicyRules.problem(label: label, in: policy, replacing: existing?.key) { return problem }
        let next = existing.map { CloseoutPolicyRules.renaming($0.key, to: label, in: policy) }
            ?? CloseoutPolicyRules.adding(label, to: policy)
        return await model.save(next, api: api, session: session)
    }

    private func remove(_ check: FieldCloseoutCheckDefinition) async -> String? {
        guard let policy = model.policy else { return "The company’s checks have not loaded yet." }
        return await model.save(CloseoutPolicyRules.removing(check.key, from: policy), api: api, session: session)
    }

    private func startReordering() {
        arranged = model.policy
        withMotion { reordering = true }
    }

    private func finishReordering() {
        let next = arranged
        withMotion { reordering = false }
        Task {
            if let next { model.saveError = await model.save(next, api: api, session: session) }
            arranged = nil
        }
    }

    /// Steps the count on screen at once and sends it after the presses stop.
    private func stepPhotos(_ count: Int, _ policy: CompanyCloseoutPolicy) {
        let value = CloseoutPolicyRules.photos(count)
        photoDraft = value
        photoSave?.cancel()
        photoSave = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, var next = model.policy else { return }
            next.requiredPhotoCount = value
            model.saveError = await model.save(next, api: api, session: session)
            if !Task.isCancelled { photoDraft = nil }
        }
    }
}

/// Add or rename one check. Save is never pre-disabled: pressed with nothing typed, it says so.
private struct CloseoutCheckEditor: View {
    let existing: FieldCloseoutCheckDefinition?
    let policy: CompanyCloseoutPolicy
    let onSave: @MainActor (String) async -> String?
    let onRemove: @MainActor () async -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var label: String
    @State private var problem: String?
    @State private var busy = false
    @State private var confirmingRemove = false
    @FocusState private var focused: Bool

    init(existing: FieldCloseoutCheckDefinition?, policy: CompanyCloseoutPolicy,
         onSave: @escaping @MainActor (String) async -> String?, onRemove: @escaping @MainActor () async -> String?) {
        self.existing = existing
        self.policy = policy
        self.onSave = onSave
        self.onRemove = onRemove
        _label = State(initialValue: existing?.label ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            LearnEditorHeader(title: existing == nil ? "Add check" : "Edit check", saveIdentifier: "checklists-save",
                              onCancel: { dismiss() }, onSave: save)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What the tech confirms").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                        TextField("", text: $label, prompt: .placeholder("Swept and cleaned the work area"), axis: .vertical)
                            .font(Theme.font(16))
                            .lineLimit(1...4)
                            .focused($focused)
                            .onChange(of: label) { _, _ in problem = nil }
                            .accessibilityLabel("What the tech confirms")
                            .accessibilityIdentifier("checklists-label")
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    if let problem { InlineProblem(message: problem).padding(.horizontal, 4) }
                    Text(existing == nil
                         ? "Techs confirm it on every job before finishing. It saves for the whole company."
                         : "Renaming keeps what techs already confirmed on open jobs.")
                        .font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                    if busy { ProgressView().frame(maxWidth: .infinity).padding(.top, 4).accessibilityLabel("Saving") }
                    if existing != nil {
                        Button { focused = false; confirmingRemove = true } label: {
                            Text("Remove check").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.destructive)
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle())
                        .padding(.top, 8)
                        .accessibilityIdentifier("checklists-remove")
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
        .onAppear { if existing == nil { focused = true } }
        .thorbisConfirm("Remove this check?",
                        message: "Techs will no longer confirm “\(existing?.label ?? "")” before finishing a job.",
                        isPresented: $confirmingRemove,
                        actions: [ThorbisConfirmAction("Remove check", role: .destructive) { remove() }])
    }

    private func remove() {
        guard !busy else { return }
        busy = true
        Task {
            let failure = await onRemove()
            busy = false
            if let failure { problem = failure } else { dismiss() }
        }
    }

    private func save() {
        guard !busy else { return }
        if let found = CloseoutPolicyRules.problem(label: label, in: policy, replacing: existing?.key) {
            problem = found
            return
        }
        busy = true
        Task {
            let failure = await onSave(label)
            busy = false
            if let failure { problem = failure } else { dismiss() }
        }
    }
}

/// One checklist that comes with the app: its steps, to read.
struct ChecklistTemplateStepsView: View {
    let template: ChecklistTemplate

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PaperHeader(title: template.title,
                            subtitle: "\(template.items.count) step\(template.items.count == 1 ? "" : "s")")
                    .environment(\.paperMenuButton, false)
                    .environment(\.paperDrawer, nil)
                PaperCard {
                    ForEach(Array(template.items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { WellDivider(leading: PaperCardMetrics.inset) }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.label).font(Theme.font(16, weight: .medium))
                                .fixedSize(horizontal: false, vertical: true)
                            // Paper 99A's type line: "Check", or "Reading \u{00B7} psi".
                            Text(item.reading.map { reading in
                                (["Reading", reading.prompt] + (reading.unit.isEmpty ? [] : [reading.unit])).joined(separator: " \u{00B7} ")
                            } ?? "Check")
                                .font(Theme.font(14)).foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
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

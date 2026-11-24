import Foundation

// Checklists kept on the server (feature `job_checklists`, contracts/api/http.md "Job checklists").
// A workspace keeps checklist templates; a job holds runs of them. This file is the part with no
// screen: what the server sends and takes, the rules that can be checked on the phone, what is kept
// here when there is no signal, and the model that sends it. With the feature off none of this
// runs and JobChecklist.swift's on-phone checklist is used exactly as before.

enum ChecklistFeature {
    static let flag = "job_checklists"
    @MainActor static func isOn(_ session: SessionController) -> Bool { session.isFeatureOn(flag) }
    /// Owners manage templates (`organization.settings.edit`).
    @MainActor static func canManage(_ session: SessionController) -> Bool { session.can("organization.settings.edit", feature: "jobs") }
}

// MARK: - What the server sends

struct ServerChecklistItem: Codable, Hashable, Identifiable {
    enum Kind: String, Codable, CaseIterable { case tick, text, number }

    var id: String
    var label: String
    var kind: Kind
    /// Only a number has a unit ("psi").
    var unit: String?
    var required: Bool

    init(id: String, label: String, kind: Kind = .tick, unit: String? = nil, required: Bool = false) {
        self.id = id; self.label = label; self.kind = kind; self.unit = unit; self.required = required
    }

    private enum Keys: String, CodingKey { case id, label, kind, unit, required }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = try c.decode(String.self, forKey: .id)
        label = try c.decode(String.self, forKey: .label)
        kind = Kind(rawValue: try c.decode(String.self, forKey: .kind)) ?? .tick
        unit = try c.decodeIfPresent(String.self, forKey: .unit)
        required = try c.decodeIfPresent(Bool.self, forKey: .required) ?? false
    }

    /// Exactly the fields the server's strict item takes: a unit goes with a number and nothing else.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(id, forKey: .id)
        try c.encode(label.trimmingCharacters(in: .whitespacesAndNewlines), forKey: .label)
        try c.encode(kind.rawValue, forKey: .kind)
        let trimmed = unit?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if kind == .number, !trimmed.isEmpty { try c.encode(trimmed, forKey: .unit) }
        try c.encode(required, forKey: .required)
    }
}

/// A template's title and items: what a run copies when it starts, and never changes after.
struct ChecklistTemplateCopy: Codable, Hashable {
    var title: String
    var items: [ServerChecklistItem]
}

struct ServerChecklistTemplate: Codable, Hashable, Identifiable {
    let id: String
    var title: String
    var items: [ServerChecklistItem]
    var revision: Int
    var archivedAt: String? = nil
    var updatedAt: String? = nil

    var isArchived: Bool { archivedAt != nil }
    var copy: ChecklistTemplateCopy { ChecklistTemplateCopy(title: title, items: items) }
}

/// A text answer or a number reading.
enum ChecklistValue: Codable, Hashable {
    case text(String)
    case number(Double)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let number = try? c.decode(Double.self) { self = .number(number) } else { self = .text(try c.decode(String.self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .text(let text): try c.encode(text)
        case .number(let number): try c.encode(number)
        }
    }

    /// "118" for 118.0, "14.6" for 14.6; text as written.
    var words: String {
        switch self {
        case .text(let text): text
        case .number(let number): number == number.rounded() && abs(number) < 1e15 ? String(Int64(number)) : String(number)
        }
    }
}

struct ServerChecklistAnswer: Codable, Hashable {
    let itemId: String
    let done: Bool
    var value: ChecklistValue?
    var answeredByUserId: String?
    var answeredAt: String?
}

struct ServerChecklistRun: Codable, Hashable, Identifiable {
    let id: String
    let jobId: String
    var clientRunId: String?
    let templateId: String
    let templateRevision: Int
    /// The copy taken when the run started. The screen draws from this, never the live template.
    let template: ChecklistTemplateCopy
    var answers: [ServerChecklistAnswer]
    var revision: Int
    var status: String
    var startedByUserId: String?
    var startedAt: String
    var completedByUserId: String? = nil
    var completedAt: String? = nil
    var updatedAt: String? = nil

    var isCompleted: Bool { status == "completed" }
    func answer(_ itemID: String) -> ServerChecklistAnswer? { answers.first { $0.itemId == itemID } }
    var doneCount: Int { template.items.filter { answer($0.id)?.done == true }.count }
    /// True for the run's own ID or the ID this phone minted for it.
    func isCalled(_ reference: String) -> Bool { id == reference || clientRunId == reference }
}

// MARK: - What the server takes

struct ChecklistTemplateCreate: Encodable, Equatable {
    let title: String
    let items: [ServerChecklistItem]
}

struct ChecklistTemplateUpdate: Encodable, Equatable {
    let expectedRevision: Int
    var title: String?
    var items: [ServerChecklistItem]?
}

struct ChecklistRunStart: Encodable, Equatable {
    let templateId: String
    /// Minted on the phone, so starting twice (a retry, a lost answer) is the same run.
    let runId: String
    let expectedTemplateRevision: Int
}

struct ChecklistAnswerInput: Encodable, Equatable {
    let itemId: String
    let done: Bool
    /// Left out for a tick, and to clear a text or number.
    var value: ChecklistValue?
}

struct ChecklistAnswersSave: Encodable, Equatable {
    let expectedRevision: Int
    let answers: [ChecklistAnswerInput]
}

struct ChecklistRunComplete: Encodable, Equatable {
    let expectedRevision: Int
}

private struct ChecklistItemsEnvelope<Item: Decodable>: Decodable { let items: [Item] }
private struct ChecklistNoBody: Encodable {}

@MainActor
extension APIClient {
    private func checklistPath(job: String, run: String? = nil, _ suffix: String = "") throws -> String {
        guard UUID(uuidString: job) != nil, run.map({ UUID(uuidString: $0) != nil }) ?? true else {
            throw Problem(title: "Invalid record ID", status: nil, detail: run ?? job)
        }
        return "/v1/jobs/\(job)/checklist-runs" + (run.map { "/\($0)" } ?? "") + suffix
    }
    private func templatePath(_ id: String, _ suffix: String = "") throws -> String {
        guard UUID(uuidString: id) != nil else { throw Problem(title: "Invalid record ID", status: nil, detail: id) }
        return "/v1/jobs/checklist-templates/\(id)\(suffix)"
    }

    func checklistTemplates(includeArchived: Bool = false) async throws -> [ServerChecklistTemplate] {
        let envelope: ChecklistItemsEnvelope<ServerChecklistTemplate> = try await send(
            "GET", "/v1/jobs/checklist-templates",
            queryItems: includeArchived ? [URLQueryItem(name: "includeArchived", value: "true")] : [], requireFresh: true)
        return envelope.items
    }

    func createChecklistTemplate(_ body: ChecklistTemplateCreate) async throws -> ServerChecklistTemplate {
        try await send("POST", "/v1/jobs/checklist-templates", body: body)
    }

    func updateChecklistTemplate(_ id: String, _ body: ChecklistTemplateUpdate) async throws -> ServerChecklistTemplate {
        try await send("POST", try templatePath(id), body: body)
    }

    /// Archive and restore take no body and are safe to repeat.
    func archiveChecklistTemplate(_ id: String) async throws -> ServerChecklistTemplate {
        try await send("POST", try templatePath(id, "/archive"), body: Optional<ChecklistNoBody>.none)
    }

    func restoreChecklistTemplate(_ id: String) async throws -> ServerChecklistTemplate {
        try await send("POST", try templatePath(id, "/restore"), body: Optional<ChecklistNoBody>.none)
    }

    func checklistRuns(jobID: String) async throws -> [ServerChecklistRun] {
        let envelope: ChecklistItemsEnvelope<ServerChecklistRun> = try await send("GET", try checklistPath(job: jobID), requireFresh: true)
        return envelope.items
    }

    func startChecklistRun(jobID: String, _ body: ChecklistRunStart) async throws -> ServerChecklistRun {
        try await send("POST", try checklistPath(job: jobID), body: body)
    }

    /// `run` is the run's ID or the ID this phone minted for it.
    func saveChecklistAnswers(jobID: String, run: String, _ body: ChecklistAnswersSave) async throws -> ServerChecklistRun {
        try await send("POST", try checklistPath(job: jobID, run: run, "/answers"), body: body)
    }

    func completeChecklistRun(jobID: String, run: String, _ body: ChecklistRunComplete) async throws -> ServerChecklistRun {
        try await send("POST", try checklistPath(job: jobID, run: run, "/complete"), body: body)
    }
}

// MARK: - Kept on this phone

/// One answer as the person typed it. A number stays as text until it is sent, so "11" on the way
/// to "118" is never thrown away.
struct ChecklistDraftAnswer: Codable, Equatable {
    var done: Bool
    var text: String = ""
}

/// What this phone holds for a run it started or changed and has not finished sending.
struct ChecklistDraft: Codable, Equatable, Identifiable {
    /// The ID this phone minted (a run started here), or the server run's own ID (a run someone
    /// else started that was changed here). Either is how the server is asked for the run.
    let runID: String
    let templateID: String
    let templateRevision: Int
    /// The template as it was when the run started, so it can be drawn with no signal.
    let template: ChecklistTemplateCopy
    /// The server has this run.
    var started: Bool
    /// Answers not on the server yet, by item.
    var unsent: [String: ChecklistDraftAnswer] = [:]
    /// "Mark checklist done" was pressed; it finishes once the answers are in.
    var finishing = false
    var startedAt = Date()

    var id: String { runID }
}

/// Unsent checklist work and the last lists read, per workspace and person. Cleared on sign-out.
@MainActor
enum ChecklistDraftStore {
    private static let draftsKey = "thorbis.jobChecklistDrafts.v1"
    private static let runsKey = "thorbis.jobChecklistRuns.v1"
    private static let templatesKey = "thorbis.checklistTemplates.v1"
    private static let startersKey = "thorbis.checklistStartersAdded.v1"

    static func owner(_ session: SessionController) -> String? {
        guard let actor = session.user?.id, let organization = session.activeOrganization?.id else { return nil }
        return "\(organization)|\(actor)"
    }

    private static func read<Value: Decodable>(_ key: String, _ slot: String, _ defaults: UserDefaults) -> Value? {
        guard let data = defaults.dictionary(forKey: key)?[slot] as? Data else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }
    private static func write<Value: Encodable>(_ value: Value?, _ key: String, _ slot: String, _ defaults: UserDefaults) {
        var all = defaults.dictionary(forKey: key) ?? [:]
        all[slot] = value.flatMap { try? JSONEncoder().encode($0) }
        defaults.set(all, forKey: key)
    }

    static func drafts(owner: String, jobID: String, defaults: UserDefaults = .standard) -> [ChecklistDraft] {
        read(draftsKey, "\(owner)|\(jobID)", defaults) ?? []
    }
    static func save(_ drafts: [ChecklistDraft], owner: String, jobID: String, defaults: UserDefaults = .standard) {
        write(drafts.isEmpty ? nil : drafts, draftsKey, "\(owner)|\(jobID)", defaults)
    }
    /// Jobs with unsent checklist work for this person, for sending when signal comes back.
    static func jobsWithDrafts(owner: String, defaults: UserDefaults = .standard) -> [String] {
        (defaults.dictionary(forKey: draftsKey) ?? [:]).keys
            .filter { $0.hasPrefix(owner + "|") }.map { String($0.dropFirst(owner.count + 1)) }.sorted()
    }

    static func runs(owner: String, jobID: String, defaults: UserDefaults = .standard) -> [ServerChecklistRun] {
        read(runsKey, "\(owner)|\(jobID)", defaults) ?? []
    }
    static func save(runs: [ServerChecklistRun], owner: String, jobID: String, defaults: UserDefaults = .standard) {
        write(runs.isEmpty ? nil : runs, runsKey, "\(owner)|\(jobID)", defaults)
    }

    /// The last template list read, so a checklist can be started with no signal.
    static func templates(owner: String, defaults: UserDefaults = .standard) -> [ServerChecklistTemplate] {
        read(templatesKey, owner, defaults) ?? []
    }
    static func save(templates: [ServerChecklistTemplate], owner: String, defaults: UserDefaults = .standard) {
        write(templates, templatesKey, owner, defaults)
    }

    /// The starter checklists were added to this workspace from this phone: the offer is not made again.
    static func startersAdded(organization: String, defaults: UserDefaults = .standard) -> Bool {
        (defaults.array(forKey: startersKey) as? [String] ?? []).contains(organization)
    }
    static func markStartersAdded(organization: String, defaults: UserDefaults = .standard) {
        let all = Set(defaults.array(forKey: startersKey) as? [String] ?? []).union([organization])
        defaults.set(all.sorted(), forKey: startersKey)
    }

    static func clearAll(defaults: UserDefaults = .standard) {
        for key in [draftsKey, runsKey, templatesKey, startersKey] { defaults.removeObject(forKey: key) }
    }
}

// MARK: - Rules the phone can check

/// Why a checklist request did not go through, in a form the screen can act on.
enum ChecklistProblem: Equatable {
    /// No signal: the work stays on this phone.
    case offline
    /// Someone else changed the run first. Reload it and put this person's answers back on top.
    case stale
    case completed
    case canceledJob
    /// Required items that are not done, by item ID.
    case requiredMissing([String])
    case nothingDone
    /// The template was edited since this phone read it.
    case templateChanged
    case templateArchived
    case tooManyRuns
    case tooManyTemplates
    case featureOff
    case forbidden
    case gone
    case other(String)

    init(_ error: Error) {
        if error.isConnectivityFailure { self = .offline; return }
        guard let problem = error as? Problem else { self = .other("That didn\u{2019}t go through. Try again."); return }
        let detail = (problem.detail ?? "").lowercased()
        switch problem.status {
        case 409:
            if detail.hasPrefix("stale checklist") { self = .stale }
            else if detail.contains("completed checklist run cannot be changed") { self = .completed }
            else if detail.contains("canceled job") { self = .canceledJob }
            else if detail.hasPrefix("required checklist items are not done") {
                let ids = (problem.detail ?? "").split(separator: ":", maxSplits: 1).last.map(String.init) ?? ""
                self = .requiredMissing(ids.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
            }
            else if detail.hasPrefix("mark at least one item done") { self = .nothingDone }
            else if detail.hasPrefix("the checklist template changed") { self = .templateChanged }
            else if detail.contains("archived checklist template") { self = .templateArchived }
            else if detail.contains("at most") && detail.contains("checklist runs") { self = .tooManyRuns }
            else if detail.contains("at most") && detail.contains("checklist templates") { self = .tooManyTemplates }
            else { self = .other("That didn\u{2019}t go through. Reload and try again.") }
        case 403:
            self = problem.category == "feature_unavailable" || problem.code == "feature_unavailable" ? .featureOff : .forbidden
        case 404: self = .gone
        default: self = .other(error.plainMessage(subject: "checklists"))
        }
    }

    /// What the person reads. `template` turns item IDs into the names on the screen.
    func words(_ template: ChecklistTemplateCopy? = nil) -> String {
        switch self {
        case .offline: return ChecklistRules.onPhoneWords
        case .stale: return "Someone else changed this checklist. It was reloaded with your answers kept."
        case .completed: return "This checklist is already finished, so it can\u{2019}t be changed."
        case .canceledJob: return "This job was canceled, so its checklist can\u{2019}t be changed."
        case .requiredMissing(let ids):
            let names = ids.map { id in template?.items.first { $0.id == id }?.label ?? id }
            return names.isEmpty ? "Finish the needed items first." : "Still needed: \(names.joined(separator: ", "))."
        case .nothingDone: return "Check off at least one item to finish."
        case .templateChanged: return "Your office changed this checklist. Pick it again to start with the new one."
        case .templateArchived: return "Your office put this checklist away. Pick another one."
        case .tooManyRuns: return "This job already has 50 checklists, which is the most it can hold."
        case .tooManyTemplates: return "Your company already has 100 checklists, which is the most it can keep."
        case .featureOff: return "Checklists aren\u{2019}t turned on for your company yet."
        case .forbidden: return "Your role can\u{2019}t change this checklist. Ask your office."
        case .gone: return "This checklist was moved or is no longer here. Go back and reload."
        case .other(let message): return message
        }
    }
}

enum ChecklistRules {
    static let onPhoneWords = "Saved on this phone. It will send when you\u{2019}re back online."
    /// Someone finished the run before this phone's answers reached it: they are kept, not lost.
    static let keptWords = "This checklist was finished before your answers were sent. They\u{2019}re still on this phone."
    static let titleLimit = 120, labelLimit = 200, unitLimit = 16, itemLimit = 60, textLimit = 2000
    static let numberLimit = 1e12

    /// "118", "14.6" and "14,6" are numbers; anything else is not.
    static func number(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(trimmed), value.isFinite, abs(value) <= numberLimit else { return nil }
        return value
    }

    /// The answer as the server takes it, or nil when it can't be sent as typed (a number that
    /// isn't one). A tick carries no value; an empty text or number clears the value.
    static func wire(_ answer: ChecklistDraftAnswer, for item: ServerChecklistItem) -> ChecklistAnswerInput? {
        let text = answer.text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch item.kind {
        case .tick: return ChecklistAnswerInput(itemId: item.id, done: answer.done)
        case .text: return ChecklistAnswerInput(itemId: item.id, done: answer.done, value: text.isEmpty ? nil : .text(String(text.prefix(textLimit))))
        case .number:
            if text.isEmpty { return ChecklistAnswerInput(itemId: item.id, done: answer.done) }
            guard let value = number(text) else { return nil }
            return ChecklistAnswerInput(itemId: item.id, done: answer.done, value: .number(value))
        }
    }

    /// Said under a number box whose text is not a number.
    static func problem(_ answer: ChecklistDraftAnswer, for item: ServerChecklistItem) -> String? {
        item.kind == .number && wire(answer, for: item) == nil ? "Type a number, like 118 or 14.6." : nil
    }

    /// The server's answer in the shape the screen edits.
    static func draft(_ answer: ServerChecklistAnswer?) -> ChecklistDraftAnswer {
        ChecklistDraftAnswer(done: answer?.done ?? false, text: answer?.value?.words ?? "")
    }

    /// What the screen shows: the server's answers with this phone's unsent ones on top.
    static func shown(_ template: ChecklistTemplateCopy, run: ServerChecklistRun?, unsent: [String: ChecklistDraftAnswer]) -> [String: ChecklistDraftAnswer] {
        Dictionary(uniqueKeysWithValues: template.items.map { ($0.id, unsent[$0.id] ?? draft(run?.answer($0.id))) })
    }

    /// The unsent answers that still differ from what the server holds, in the template's order.
    /// After someone else's change this is "put my ticks back on top": an answer the server
    /// already has is not sent, and an item this person did not touch is left as the server has it.
    static func changes(_ unsent: [String: ChecklistDraftAnswer], onto run: ServerChecklistRun) -> [ChecklistAnswerInput] {
        run.template.items.compactMap { item in
            guard let mine = unsent[item.id], let input = wire(mine, for: item) else { return nil }
            let stored = run.answer(item.id)
            let same = (stored?.done ?? false) == input.done && stored?.value == input.value
            return same ? nil : input
        }
    }

    /// Unsent answers the server now holds (or that are not for this run): nothing left to send for them.
    static func settled(_ unsent: [String: ChecklistDraftAnswer], on run: ServerChecklistRun) -> Set<String> {
        let pending = Set(changes(unsent, onto: run).map(\.itemId))
        return Set(unsent.keys.filter { id in
            guard let item = run.template.items.first(where: { $0.id == id }) else { return true }
            return !pending.contains(id) && wire(unsent[id] ?? .init(done: false), for: item) != nil
        })
    }

    static func doneCount(_ template: ChecklistTemplateCopy, _ answers: [String: ChecklistDraftAnswer]) -> Int {
        template.items.filter { answers[$0.id]?.done == true }.count
    }

    /// Required items that are not done, or are done with nothing written (a text or a number).
    static func missingRequired(_ template: ChecklistTemplateCopy, _ answers: [String: ChecklistDraftAnswer]) -> [ServerChecklistItem] {
        template.items.filter { item in
            guard item.required else { return false }
            let answer = answers[item.id] ?? ChecklistDraftAnswer(done: false)
            if !answer.done { return true }
            return item.kind != .tick && answer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Why "Mark checklist done" can't go yet, checked before anything is sent.
    static func finishProblem(_ template: ChecklistTemplateCopy, _ answers: [String: ChecklistDraftAnswer]) -> String? {
        if let bad = template.items.first(where: { problem(answers[$0.id] ?? .init(done: false), for: $0) != nil }) {
            return "\(bad.label) needs a number."
        }
        if doneCount(template, answers) == 0 { return ChecklistProblem.nothingDone.words() }
        let missing = missingRequired(template, answers)
        return missing.isEmpty ? nil : ChecklistProblem.requiredMissing(missing.map(\.id)).words(template)
    }

    // MARK: Templates

    /// A stable key for a new item: lowercase letters, digits, "-" and "_", unique in the template.
    static func itemID(for label: String, existing: [String]) -> String {
        var slug = ""
        for scalar in label.lowercased().unicodeScalars {
            if ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) { slug.unicodeScalars.append(scalar) }
            else if !slug.isEmpty, slug.last != "-" { slug.append("-") }
        }
        while slug.hasSuffix("-") { slug.removeLast() }
        slug = String(slug.prefix(48))
        while slug.hasSuffix("-") { slug.removeLast() }
        if slug.isEmpty { slug = "item" }
        guard existing.contains(slug) else { return slug }
        var number = 2
        while existing.contains("\(slug)-\(number)") { number += 1 }
        return "\(slug)-\(number)"
    }

    /// Why a template can't be saved as typed; nil when it can.
    static func problem(title: String, items: [ServerChecklistItem]) -> String? {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "Give the checklist a name." }
        if name.count > titleLimit { return "Keep the name under \(titleLimit) letters." }
        if items.isEmpty { return "Add at least one step." }
        if items.count > itemLimit { return "A checklist can have up to \(itemLimit) steps." }
        for (index, item) in items.enumerated() {
            let label = item.label.trimmingCharacters(in: .whitespacesAndNewlines)
            if label.isEmpty { return "Step \(index + 1) needs words." }
            if label.count > labelLimit { return "Step \(index + 1) is too long. Keep it under \(labelLimit) letters." }
            if let unit = item.unit, unit.trimmingCharacters(in: .whitespacesAndNewlines).count > unitLimit {
                return "Keep the unit on step \(index + 1) under \(unitLimit) letters."
            }
        }
        return nil
    }

    /// The app's four built-in checklists as the server takes them: a reading becomes a number
    /// with its unit, everything else a tick. Nothing is required.
    static var starters: [ChecklistTemplateCreate] {
        ChecklistTemplates.all.map { template in
            ChecklistTemplateCreate(title: template.title, items: template.items.map { item in
                ServerChecklistItem(id: item.id, label: item.label, kind: item.reading == nil ? .tick : .number,
                                    unit: item.reading?.unit, required: false)
            })
        }
    }

    /// The starters this workspace does not have yet, matched by name (archived ones count).
    static func startersToAdd(existing: [ServerChecklistTemplate]) -> [ChecklistTemplateCreate] {
        let have = Set(existing.map { $0.title.trimmingCharacters(in: .whitespaces).lowercased() })
        return starters.filter { !have.contains($0.title.lowercased()) }
    }

    /// "8 steps · 3 readings".
    static func summary(_ items: [ServerChecklistItem]) -> String {
        let readings = items.filter { $0.kind == .number }.count
        return "\(items.count) step\(items.count == 1 ? "" : "s")" + (readings > 0 ? " \u{00B7} \(readings) reading\(readings == 1 ? "" : "s")" : "")
    }

    /// "Check", "Words" or "Number · psi", with "needed" when it is required.
    static func kindLine(_ item: ServerChecklistItem) -> String {
        var words: [String]
        switch item.kind {
        case .tick: words = ["Check"]
        case .text: words = ["Words"]
        case .number: words = ["Number"] + ((item.unit ?? "").isEmpty ? [] : [item.unit ?? ""])
        }
        if item.required { words.append("Needed") }
        return words.joined(separator: " \u{00B7} ")
    }
}

// MARK: - One job's checklists

/// One row on the job: a run on the server, or one started here that has not reached it yet.
struct ChecklistEntry: Identifiable, Equatable {
    /// How the run is asked for: its own ID, or the ID this phone minted.
    let id: String
    let template: ChecklistTemplateCopy
    let answers: [String: ChecklistDraftAnswer]
    let completed: Bool
    let completedAt: Date?
    let completedBy: String?
    let startedBy: String?
    let startedAt: Date?
    /// Something for this run is still only on this phone.
    let unsent: Bool

    var done: Int { ChecklistRules.doneCount(template, answers) }
    var total: Int { template.items.count }
}

@MainActor
final class JobChecklistModel: ObservableObject {
    @Published private(set) var templates: [ServerChecklistTemplate] = []
    @Published private(set) var runs: [ServerChecklistRun] = []
    @Published private(set) var drafts: [ChecklistDraft] = []
    @Published private(set) var loaded = false
    @Published private(set) var loadError: String?
    /// The lists on screen came from this phone because there is no signal.
    @Published private(set) var showingSaved = false
    /// What to say under a run: a refusal, or that its answers are still on this phone.
    @Published private(set) var notes: [String: String] = [:]
    @Published private(set) var sending: Set<String> = []
    /// People's names by ID, when this person may read the roster.
    @Published private(set) var names: [String: String] = [:]

    private(set) var jobID = ""
    private var owner = ""
    private var me: String?
    private var defaults = UserDefaults.standard
    private var again: Set<String> = []
    private var timers: [String: Task<Void, Never>] = [:]
    /// How long after the last tick the answers are sent.
    var quietTime: Duration = .milliseconds(700)
    #if DEBUG
    /// Design preview: sample data, nothing sent.
    private(set) var isPreview = false
    #endif

    func configure(jobID: String, owner: String, me: String?, defaults: UserDefaults = .standard) {
        guard self.jobID != jobID || self.owner != owner else { return }
        self.jobID = jobID; self.owner = owner; self.me = me; self.defaults = defaults
        drafts = ChecklistDraftStore.drafts(owner: owner, jobID: jobID, defaults: defaults)
        runs = ChecklistDraftStore.runs(owner: owner, jobID: jobID, defaults: defaults)
        templates = ChecklistDraftStore.templates(owner: owner, defaults: defaults).filter { !$0.isArchived }
        notes = [:]; loaded = false; loadError = nil
    }

    // MARK: Reading

    func run(_ reference: String) -> ServerChecklistRun? { runs.first { $0.isCalled(reference) } }
    func draft(_ reference: String) -> ChecklistDraft? {
        drafts.first { $0.runID == reference } ?? run(reference).flatMap { run in drafts.first { run.isCalled($0.runID) } }
    }

    /// Every run on the job, oldest first, then the ones started here that the server doesn't have yet.
    var entries: [ChecklistEntry] {
        let known = runs.map { run -> ChecklistEntry in
            let draft = drafts.first { run.isCalled($0.runID) }
            // A finished run shows what the server holds; answers kept after it was finished
            // elsewhere stay on the phone, apart, until the person copies or lets go of them.
            return ChecklistEntry(id: run.id, template: run.template,
                                  answers: ChecklistRules.shown(run.template, run: run, unsent: run.isCompleted ? [:] : draft?.unsent ?? [:]),
                                  completed: run.isCompleted, completedAt: run.completedAt.flatMap(Self.date),
                                  completedBy: run.completedByUserId.map(who), startedBy: run.startedByUserId.map(who),
                                  startedAt: Self.date(run.startedAt),
                                  unsent: draft.map { !$0.unsent.isEmpty || $0.finishing } ?? false)
        }
        let local = drafts.filter { draft in !runs.contains { $0.isCalled(draft.runID) } }.map { draft in
            ChecklistEntry(id: draft.runID, template: draft.template,
                           answers: ChecklistRules.shown(draft.template, run: nil, unsent: draft.unsent),
                           completed: false, completedAt: nil, completedBy: nil, startedBy: "You", startedAt: draft.startedAt, unsent: true)
        }
        return known + local
    }

    func entry(_ reference: String) -> ChecklistEntry? {
        if let run = run(reference) { return entries.first { $0.id == run.id } }
        return entries.first { $0.id == reference }
    }

    /// "You", the person's name, or "A teammate" when the roster can't be read.
    func who(_ userID: String) -> String {
        if userID == me { return "You" }
        return names[userID] ?? "A teammate"
    }

    static func date(_ raw: String) -> Date? { JobFiltering.isoFractional.date(from: raw) ?? JobFiltering.isoPlain.date(from: raw) }

    /// The job's tile: what is under way, or what was finished.
    var tileDetail: String {
        let all = entries
        if let open = all.last(where: { !$0.completed }) { return "\(open.done) of \(open.total) done" }
        let finished = all.filter(\.completed).count
        return finished == 0 ? "Start one for this visit" : "\(finished) finished"
    }

    /// Reads the job's runs and the templates. With no signal the last lists stay, and say so.
    func load(api: APIClient, people: Bool = true) async {
        #if DEBUG
        if isPreview { return }
        #endif
        guard !jobID.isEmpty else { return }
        let generation = api.requestGeneration
        do {
            async let freshRuns = api.checklistRuns(jobID: jobID)
            async let freshTemplates = api.checklistTemplates()
            let (jobRuns, list) = try await (freshRuns, freshTemplates)
            guard generation == api.requestGeneration else { return }
            runs = jobRuns; templates = list.filter { !$0.isArchived }
            ChecklistDraftStore.save(runs: jobRuns, owner: owner, jobID: jobID, defaults: defaults)
            ChecklistDraftStore.save(templates: templates, owner: owner, defaults: defaults)
            loadError = nil; showingSaved = false; loaded = true
            if people, names.isEmpty, let roster = try? await api.fieldAssignees(), generation == api.requestGeneration {
                names = Dictionary(roster.map { ($0.userId, $0.displayName) }, uniquingKeysWith: { first, _ in first })
            }
            await flush(api: api)
        } catch is CancellationError {
        } catch {
            guard generation == api.requestGeneration else { return }
            loaded = true
            if error.isConnectivityFailure { showingSaved = true; loadError = nil }
            else { loadError = ChecklistProblem(error).words() }
        }
    }

    // MARK: Changing

    private func persist() { ChecklistDraftStore.save(drafts, owner: owner, jobID: jobID, defaults: defaults) }

    private func setRuns(_ next: [ServerChecklistRun]) {
        runs = next
        ChecklistDraftStore.save(runs: next, owner: owner, jobID: jobID, defaults: defaults)
    }
    private func upsert(_ run: ServerChecklistRun) {
        var next = runs
        if let index = next.firstIndex(where: { $0.id == run.id }) { next[index] = run } else { next.append(run) }
        setRuns(next)
    }

    /// Starts a run of this template: the ID is minted here and the run is kept on this phone at
    /// once, then sent. Returns how to ask for it.
    @discardableResult
    func start(_ template: ServerChecklistTemplate, api: APIClient, runID: String = UUID().uuidString) async -> String {
        drafts.append(ChecklistDraft(runID: runID, templateID: template.id, templateRevision: template.revision,
                                     template: template.copy, started: false))
        persist()
        await flush(api: api, only: runID)
        return runID
    }

    /// Changes one answer on this phone and sends it a moment after the last change.
    func set(_ reference: String, item: ServerChecklistItem, to answer: ChecklistDraftAnswer, api: APIClient) {
        guard !(run(reference)?.isCompleted ?? false), let index = draftIndex(reference, creating: true) else { return }
        drafts[index].unsent[item.id] = answer
        persist()
        let key = drafts[index].runID
        notes[key] = nil
        timers[key]?.cancel()
        timers[key] = Task { [weak self, quietTime] in
            try? await Task.sleep(for: quietTime)
            guard !Task.isCancelled else { return }
            await self?.flush(api: api, only: key)
        }
    }

    /// Stops the short waits before answers are sent (the sheet closing sends at once instead).
    func stopTimers() {
        timers.values.forEach { $0.cancel() }
        timers = [:]
    }

    private func draftIndex(_ reference: String, creating: Bool) -> Int? {
        if let index = drafts.firstIndex(where: { $0.runID == reference }) { return index }
        guard let run = run(reference) else { return nil }
        if let index = drafts.firstIndex(where: { run.isCalled($0.runID) }) { return index }
        guard creating else { return nil }
        drafts.append(ChecklistDraft(runID: run.id, templateID: run.templateId, templateRevision: run.templateRevision,
                                     template: run.template, started: true))
        return drafts.count - 1
    }

    /// Removes a run that only ever existed on this phone (its start was refused, or never sent).
    func discard(_ reference: String) {
        guard let index = drafts.firstIndex(where: { $0.runID == reference }), !drafts[index].started else { return }
        timers[reference]?.cancel()
        drafts.remove(at: index); notes[reference] = nil
        persist()
    }

    /// Answers this phone kept for a run someone else finished first, one line per item, to copy.
    func keptText(_ reference: String) -> String? {
        guard run(reference)?.isCompleted == true, let draft = draft(reference), !draft.unsent.isEmpty else { return nil }
        let lines = draft.template.items.compactMap { item -> String? in
            guard let answer = draft.unsent[item.id] else { return nil }
            let text = answer.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = text.isEmpty ? (answer.done ? "Done" : "Not done") : [text, item.unit].compactMap { $0 }.joined(separator: " ")
            return "\(item.label): \(value)"
        }
        return lines.isEmpty ? nil : ([draft.template.title] + lines).joined(separator: "\n")
    }

    /// Lets go of answers this phone kept for a run someone else finished first. Only on the
    /// person's word: a finished run is never taken as a receipt for them.
    func discardKept(_ reference: String) {
        guard run(reference)?.isCompleted == true, let index = draftIndex(reference, creating: false) else { return }
        let key = drafts[index].runID
        timers[key]?.cancel()
        drafts.remove(at: index); notes[key] = nil
        persist()
    }

    enum FinishResult: Equatable {
        case finished
        /// No signal: it finishes by itself when the phone is back online.
        case onPhone
        case problem(String)
    }

    /// "Mark checklist done". Checked here first, so a missing item is named without a round trip.
    func finish(_ reference: String, api: APIClient) async -> FinishResult {
        guard let entry = entry(reference) else { return .problem(ChecklistProblem.gone.words()) }
        if let problem = ChecklistRules.finishProblem(entry.template, entry.answers) { return .problem(problem) }
        guard let index = draftIndex(reference, creating: true) else { return .problem(ChecklistProblem.gone.words()) }
        let key = drafts[index].runID
        drafts[index].finishing = true
        persist()
        timers[key]?.cancel()
        await flush(api: api, only: key)
        if run(reference)?.isCompleted == true || run(key)?.isCompleted == true {
            // Finished elsewhere first, with answers of this person's the server never got.
            if drafts.contains(where: { $0.runID == key }) { return .problem(notes[key] ?? ChecklistRules.keptWords) }
            return .finished
        }
        if let index = drafts.firstIndex(where: { $0.runID == key }) {
            if let note = notes[key], note != ChecklistRules.onPhoneWords {
                // Refused: the answers stay, but it is not left trying to finish behind the person's back.
                drafts[index].finishing = false
                persist()
                return .problem(note)
            }
            return .onPhone
        }
        return .problem(notes[key] ?? ChecklistProblem.other("That didn\u{2019}t go through. Try again.").words())
    }

    // MARK: Sending

    /// Sends what this phone holds: starts runs the server doesn't have, saves unsent answers, and
    /// finishes runs that were marked done. Safe to call at any time; one send per run at a time.
    func flush(api: APIClient, only: String? = nil) async {
        #if DEBUG
        if isPreview { previewApply(only); return }
        #endif
        for key in drafts.map(\.runID) where only == nil || key == only {
            if sending.contains(key) { again.insert(key); continue }
            sending.insert(key)
            repeat {
                again.remove(key)
                await send(key, api: api)
            } while again.contains(key)
            sending.remove(key)
        }
    }

    private func send(_ key: String, api: APIClient) async {
        let generation = api.requestGeneration
        func current() -> Bool { generation == api.requestGeneration && drafts.contains { $0.runID == key } }
        func fail(_ error: Error, template: ChecklistTemplateCopy?) { notes[key] = ChecklistProblem(error).words(template) }
        guard var draft = drafts.first(where: { $0.runID == key }) else { return }
        func write(_ change: (inout ChecklistDraft) -> Void) {
            guard let index = drafts.firstIndex(where: { $0.runID == key }) else { return }
            change(&drafts[index]); draft = drafts[index]
            persist()
        }
        // 1. The run itself. Starting again with the same ID answers with the run already started.
        if !draft.started {
            do {
                let run = try await api.startChecklistRun(jobID: jobID, ChecklistRunStart(
                    templateId: draft.templateID, runId: draft.runID, expectedTemplateRevision: draft.templateRevision))
                guard current() else { return }
                upsert(run)
                write { $0.started = true }
            } catch is CancellationError { return } catch {
                guard current() else { return }
                return fail(error, template: draft.template)
            }
        }
        // 2. Answers, with the revision the server last gave. A stale revision reloads the run and
        //    puts this person's unsent answers back on top, once.
        var reloaded = false
        while true {
            guard current(), let latest = drafts.first(where: { $0.runID == key }) else { return }
            draft = latest
            if run(key) == nil, !reloaded, await reloadRuns(api: api) { reloaded = true; continue }
            guard let run = run(key) else { notes[key] = ChecklistProblem.gone.words(); return }
            if run.isCompleted {
                // Nothing of this person's is missing from the finished run: let go of it.
                if ChecklistRules.changes(draft.unsent, onto: run).isEmpty {
                    drafts.removeAll { $0.runID == key }; persist()
                    return
                }
                // Someone finished it before these answers were sent. A finished run is not a
                // receipt for them: they stay on this phone until the person copies or lets go.
                write { $0.finishing = false }
                notes[key] = ChecklistRules.keptWords
                return
            }
            let sent = draft.unsent
            let changes = ChecklistRules.changes(sent, onto: run)
            if changes.isEmpty {
                let settled = ChecklistRules.settled(sent, on: run)
                if !settled.isEmpty { write { for id in settled where $0.unsent[id] == sent[id] { $0.unsent[id] = nil } } }
                break
            }
            do {
                let updated = try await api.saveChecklistAnswers(jobID: jobID, run: key,
                                                                 ChecklistAnswersSave(expectedRevision: run.revision, answers: changes))
                guard current() else { return }
                upsert(updated)
                // Only what was sent is cleared; a tick made while it was on its way goes next.
                write { for (id, answer) in sent where $0.unsent[id] == answer && changes.contains(where: { $0.itemId == id }) { $0.unsent[id] = nil } }
                // After a reload for someone else's change, the line saying so stays.
                if !reloaded { notes[key] = nil }
            } catch is CancellationError { return } catch {
                guard current() else { return }
                let problem = ChecklistProblem(error)
                if problem == .stale || problem == .completed, !reloaded, await reloadRuns(api: api) {
                    reloaded = true
                    if problem == .stale { notes[key] = problem.words() }
                    continue
                }
                return fail(error, template: draft.template)
            }
        }
        // 3. Finishing.
        guard current(), draft.finishing, let run = run(key) else {
            // Nothing left to send for a run the server has: this phone lets go of it.
            if current(), draft.started, draft.unsent.isEmpty, !draft.finishing { drafts.removeAll { $0.runID == key }; persist() }
            return
        }
        if !draft.unsent.isEmpty { notes[key] = ChecklistRules.finishProblem(run.template, ChecklistRules.shown(run.template, run: run, unsent: draft.unsent)); return }
        for attempt in 0..<2 {
            guard let run = self.run(key) else { return }
            do {
                let done = try await api.completeChecklistRun(jobID: jobID, run: key, ChecklistRunComplete(expectedRevision: run.revision))
                guard current() else { return }
                upsert(done)
                drafts.removeAll { $0.runID == key }; persist()
                notes[key] = nil
                return
            } catch is CancellationError { return } catch {
                guard current() else { return }
                if ChecklistProblem(error) == .stale, attempt == 0, await reloadRuns(api: api) { continue }
                return fail(error, template: run.template)
            }
        }
    }

    /// Reads the job's runs again. False when that could not be done.
    private func reloadRuns(api: APIClient) async -> Bool {
        guard let fresh = try? await api.checklistRuns(jobID: jobID) else { return false }
        setRuns(fresh)
        return true
    }

    #if DEBUG
    // MARK: Design preview (`--paper-preview`): sample runs, nothing sent, never a real workspace.

    func preview(runs sample: [ServerChecklistRun], templates list: [ServerChecklistTemplate], names people: [String: String],
                 drafts held: [ChecklistDraft] = [], notes said: [String: String] = [:], me: String?) {
        isPreview = true
        jobID = PaperPreview.jobID; owner = "preview"; self.me = me
        runs = sample; templates = list; names = people; drafts = held; notes = said
        loaded = true
    }

    /// In the preview a tick lands on the sample run at once, and "done" finishes it.
    private func previewApply(_ only: String?) {
        for draft in drafts where only == nil || draft.runID == only {
            if let index = runs.firstIndex(where: { $0.isCalled(draft.runID) }) {
                for change in ChecklistRules.changes(draft.unsent, onto: runs[index]) {
                    runs[index].answers.removeAll { $0.itemId == change.itemId }
                    runs[index].answers.append(ServerChecklistAnswer(itemId: change.itemId, done: change.done, value: change.value, answeredByUserId: me, answeredAt: nil))
                }
                if draft.finishing { runs[index].status = "completed"; runs[index].completedByUserId = me; runs[index].completedAt = ISO8601DateFormatter().string(from: Date()) }
                drafts.removeAll { $0.runID == draft.runID }
            } else if draft.unsent.isEmpty {
                runs.append(ServerChecklistRun(id: draft.runID, jobId: jobID, clientRunId: draft.runID, templateId: draft.templateID,
                                               templateRevision: draft.templateRevision, template: draft.template, answers: [], revision: 1,
                                               status: "in_progress", startedByUserId: me, startedAt: ISO8601DateFormatter().string(from: Date())))
                drafts.removeAll { $0.runID == draft.runID }
            }
        }
    }
    #endif
}

/// Sends unsent checklist work for every job when signal comes back, without opening the jobs.
@MainActor
enum ChecklistSync {
    static func flushAll(api: APIClient, session: SessionController, defaults: UserDefaults = .standard) async {
        guard ChecklistFeature.isOn(session), !session.isOffline, let owner = ChecklistDraftStore.owner(session) else { return }
        for jobID in ChecklistDraftStore.jobsWithDrafts(owner: owner, defaults: defaults) {
            let model = JobChecklistModel()
            model.configure(jobID: jobID, owner: owner, me: session.user?.id, defaults: defaults)
            // The runs are read first so answers go with the server's current revision.
            await model.load(api: api, people: false)
        }
    }
}

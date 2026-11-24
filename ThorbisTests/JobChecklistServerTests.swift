import XCTest
@testable import Thorbis

/// Checklists kept on the server (feature `job_checklists`): what is sent, how a stale revision is
/// handled, what stays on the phone with no signal, and the words a person reads.
@MainActor
final class JobChecklistServerTests: XCTestCase {
    private let jobID = "11111111-1111-4111-8111-111111111111"
    private let templateID = "22222222-2222-4222-8222-222222222222"
    private let runID = "33333333-3333-4333-8333-333333333333"
    private let clientRunID = "44444444-4444-4444-8444-444444444444"
    private let me = "55555555-5555-4555-8555-555555555555"
    private let sam = "66666666-6666-4666-8666-666666666666"
    private let origin = "https://app.thorbis.com"
    private var defaults: UserDefaults!

    override func setUp() async throws { defaults = UserDefaults(suiteName: "checklists-\(UUID().uuidString)")! }

    private let items: [ServerChecklistItem] = [
        .init(id: "thermostat", label: "Thermostat calls for heat and cool"),
        .init(id: "suction", label: "Suction pressure", kind: .number, unit: "psi", required: true),
        .init(id: "found", label: "What you found", kind: .text),
    ]
    private var template: ServerChecklistTemplate { ServerChecklistTemplate(id: templateID, title: "HVAC service", items: items, revision: 3) }

    private let itemsJSON = #"[{"id":"thermostat","label":"Thermostat calls for heat and cool","kind":"tick","required":false},{"id":"suction","label":"Suction pressure","kind":"number","unit":"psi","required":true},{"id":"found","label":"What you found","kind":"text","required":false}]"#

    private func runJSON(revision: Int = 1, answers: String = "[]", status: String = "in_progress", client: Bool = true, completed: String = "") -> String {
        #"{"id":"\#(runID)","organizationId":"77777777-7777-4777-8777-777777777777","jobId":"\#(jobID)"\#(client ? #","clientRunId":"\#(clientRunID)""# : ""),"templateId":"\#(templateID)","templateRevision":3,"template":{"title":"HVAC service","items":\#(itemsJSON)},"answers":\#(answers),"revision":\#(revision),"status":"\#(status)","startedByUserId":"\#(sam)","startedAt":"2026-11-20T14:00:00.000Z"\#(completed),"updatedAt":"2026-11-20T14:05:00.000Z"}"#
    }
    private func answerJSON(_ item: String, done: Bool = true, value: String? = nil, by: String) -> String {
        #"{"itemId":"\#(item)","done":\#(done)\#(value.map { #","value":\#($0)"# } ?? ""),"answeredByUserId":"\#(by)","answeredAt":"2026-11-20T14:03:00.000Z"}"#
    }
    private func conflict(_ detail: String) -> URLProtocolFixture.Reply {
        .init(409, #"{"type":"https://thorbis.com/problems/conflict","title":"conflict","status":409,"category":"conflict","detail":"\#(detail)"}"#)
    }
    private func decodeRun(_ json: String) throws -> ServerChecklistRun { try JSONDecoder().decode(ServerChecklistRun.self, from: Data(json.utf8)) }
    private func body(_ index: Int) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(URLProtocolFixture.recorded[index].body)) as? [String: Any])
    }
    private func json(_ value: some Encodable) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }

    private func model(_ replies: [URLProtocolFixture.Reply], runs: [ServerChecklistRun] = [], drafts: [ChecklistDraft] = []) -> (JobChecklistModel, APIClient) {
        let api = APIClient(session: URLProtocolFixture.session(replies), baseURL: origin)
        ChecklistDraftStore.save(runs: runs, owner: "org|me", jobID: jobID, defaults: defaults)
        ChecklistDraftStore.save(drafts, owner: "org|me", jobID: jobID, defaults: defaults)
        let model = JobChecklistModel()
        model.quietTime = .seconds(60)
        model.configure(jobID: jobID, owner: "org|me", me: me, defaults: defaults)
        return (model, api)
    }

    // MARK: What is sent

    func testRunRequestBodiesAndPaths() async throws {
        let api = APIClient(session: URLProtocolFixture.session([
            .init(201, runJSON()), .init(200, runJSON(revision: 2)), .init(200, runJSON(revision: 3, status: "completed")),
            .init(200, #"{"items":[\#(runJSON())]}"#),
        ]), baseURL: origin)
        _ = try await api.startChecklistRun(jobID: jobID, ChecklistRunStart(templateId: templateID, runId: clientRunID, expectedTemplateRevision: 3))
        _ = try await api.saveChecklistAnswers(jobID: jobID, run: clientRunID, ChecklistAnswersSave(expectedRevision: 1, answers: [
            .init(itemId: "thermostat", done: true), .init(itemId: "suction", done: true, value: .number(118)),
            .init(itemId: "found", done: true, value: .text("Low charge")),
        ]))
        _ = try await api.completeChecklistRun(jobID: jobID, run: clientRunID, ChecklistRunComplete(expectedRevision: 2))
        let runs = try await api.checklistRuns(jobID: jobID)
        XCTAssertEqual(runs.first?.clientRunId, clientRunID)

        let requests = URLProtocolFixture.recorded
        XCTAssertEqual(requests.map(\.method), ["POST", "POST", "POST", "GET"])
        XCTAssertEqual(requests.map { $0.url?.path }, [
            "/v1/jobs/\(jobID)/checklist-runs", "/v1/jobs/\(jobID)/checklist-runs/\(clientRunID)/answers",
            "/v1/jobs/\(jobID)/checklist-runs/\(clientRunID)/complete", "/v1/jobs/\(jobID)/checklist-runs",
        ])
        let start = try body(0)
        XCTAssertEqual(Set(start.keys), ["templateId", "runId", "expectedTemplateRevision"], "The job is in the path, never the body")
        XCTAssertEqual(start["runId"] as? String, clientRunID); XCTAssertEqual(start["expectedTemplateRevision"] as? Int, 3)
        let save = try body(1)
        XCTAssertEqual(Set(save.keys), ["expectedRevision", "answers"])
        let answers = try XCTUnwrap(save["answers"] as? [[String: Any]])
        XCTAssertEqual(Set(answers[0].keys), ["itemId", "done"], "A tick carries no value")
        XCTAssertEqual(answers[1]["value"] as? Double, 118); XCTAssertTrue(answers[1]["value"] is NSNumber, "A reading is a number, not text")
        XCTAssertEqual(answers[2]["value"] as? String, "Low charge")
        XCTAssertEqual(try body(2) as NSDictionary, ["expectedRevision": 2])
    }

    func testTemplateRequestBodies() async throws {
        let stored = #"{"id":"\#(templateID)","organizationId":"77777777-7777-4777-8777-777777777777","title":"HVAC service","items":\#(itemsJSON),"revision":4,"createdByUserId":"\#(me)","updatedByUserId":"\#(me)","createdAt":"2026-11-20T14:00:00.000Z","updatedAt":"2026-11-20T14:00:00.000Z"}"#
        let api = APIClient(session: URLProtocolFixture.session([
            .init(201, stored), .init(200, stored), .init(200, stored), .init(200, stored), .init(200, #"{"items":[\#(stored)]}"#),
        ]), baseURL: origin)
        _ = try await api.createChecklistTemplate(ChecklistTemplateCreate(title: "HVAC service", items: items))
        let update = try XCTUnwrap(ChecklistTemplatesModel.update(from: template, title: "HVAC tune-up", items: items))
        _ = try await api.updateChecklistTemplate(templateID, update)
        _ = try await api.archiveChecklistTemplate(templateID)
        _ = try await api.restoreChecklistTemplate(templateID)
        let list = try await api.checklistTemplates(includeArchived: true)
        XCTAssertEqual(list.first?.revision, 4)

        let requests = URLProtocolFixture.recorded
        XCTAssertEqual(requests.map { $0.url?.path }, [
            "/v1/jobs/checklist-templates", "/v1/jobs/checklist-templates/\(templateID)",
            "/v1/jobs/checklist-templates/\(templateID)/archive", "/v1/jobs/checklist-templates/\(templateID)/restore",
            "/v1/jobs/checklist-templates",
        ])
        XCTAssertEqual(requests[4].url?.query, "includeArchived=true")
        let create = try body(0)
        XCTAssertEqual(Set(create.keys), ["title", "items"], "Create takes exactly a title and items")
        let sent = try XCTUnwrap(create["items"] as? [[String: Any]])
        XCTAssertEqual(Set(sent[0].keys), ["id", "label", "kind", "required"], "No unit on a tick")
        XCTAssertEqual(Set(sent[1].keys), ["id", "label", "kind", "unit", "required"])
        XCTAssertEqual(sent[1]["kind"] as? String, "number"); XCTAssertEqual(sent[1]["unit"] as? String, "psi"); XCTAssertEqual(sent[1]["required"] as? Bool, true)
        XCTAssertEqual(try body(1) as NSDictionary, ["expectedRevision": 3, "title": "HVAC tune-up"], "Only what changed, with the revision the edit started from")
        XCTAssertTrue(requests[2].body?.isEmpty ?? true, "Archive takes no body"); XCTAssertTrue(requests[3].body?.isEmpty ?? true)
    }

    func testAnUpdateSendsOnlyWhatChanged() throws {
        XCTAssertNil(ChecklistTemplatesModel.update(from: template, title: " HVAC service ", items: items), "Nothing changed, nothing sent")
        var changed = items
        changed[0].required = true
        let body = try XCTUnwrap(ChecklistTemplatesModel.update(from: template, title: "HVAC service", items: changed))
        XCTAssertNil(body.title); XCTAssertEqual(body.items?.count, 3); XCTAssertEqual(body.expectedRevision, 3)
        // A unit typed on a step that is then changed to a tick is not sent.
        var odd = items
        odd[0].unit = "psi"
        XCTAssertNil(ChecklistTemplatesModel.clean(odd)[0].unit)
        XCTAssertEqual(try json(odd[0]).keys.sorted(), ["id", "kind", "label", "required"])
    }

    func testNewStepsGetKeysAndKnownStepsKeepTheirs() {
        let edited = [items[0], ServerChecklistItem(id: "step-2", label: "Filter checked / replaced!"), ServerChecklistItem(id: "step-3", label: "Thermostat"),
                      ServerChecklistItem(id: "step-4", label: "Thermostat"), ServerChecklistItem(id: "step-5", label: "\u{00B0}F")]
        let keyed = ChecklistTemplatesModel.keyed(edited, keeping: ["thermostat", "suction", "found"])
        XCTAssertEqual(keyed.map(\.id), ["thermostat", "filter-checked-replaced", "thermostat-2", "thermostat-3", "f"])
        XCTAssertEqual(ChecklistRules.itemID(for: "!!!", existing: []), "item")
        let pattern = try! NSRegularExpression(pattern: "^[a-z0-9][a-z0-9_-]{0,63}$")
        for id in keyed.map(\.id) + [ChecklistRules.itemID(for: String(repeating: "Long words ", count: 30), existing: [])] {
            XCTAssertNotNil(pattern.firstMatch(in: id, range: NSRange(id.startIndex..., in: id)), id)
        }
    }

    func testTheStarterChecklistsAreTheAppsFourAsTheServerTakesThem() throws {
        let starters = ChecklistRules.starters
        XCTAssertEqual(starters.map(\.title), ["HVAC service", "Plumbing repair", "Electrical safety", "General visit"])
        XCTAssertEqual(starters.map(\.items.count), ChecklistTemplates.all.map(\.items.count))
        let pattern = try NSRegularExpression(pattern: "^[a-z0-9][a-z0-9_-]{0,63}$")
        for starter in starters {
            XCTAssertEqual(Set(starter.items.map(\.id)).count, starter.items.count, "Item keys are unique in \(starter.title)")
            XCTAssertNil(ChecklistRules.problem(title: starter.title, items: starter.items))
            for item in starter.items {
                XCTAssertNotNil(pattern.firstMatch(in: item.id, range: NSRange(item.id.startIndex..., in: item.id)), item.id)
                XCTAssertFalse(item.required)
                XCTAssertEqual(item.unit != nil, item.kind == .number)
                XCTAssertLessThanOrEqual(item.unit?.count ?? 0, ChecklistRules.unitLimit)
            }
        }
        let suction = try XCTUnwrap(starters[0].items.first { $0.id == "pressure-suction" })
        XCTAssertEqual(try json(suction) as NSDictionary, ["id": "pressure-suction", "label": "Suction pressure", "kind": "number", "unit": "psi", "required": false])
        XCTAssertEqual(Set(try json(starters[3]).keys), ["title", "items"])
        // Matched by name, so a second tap (or one the workspace already has) adds nothing twice.
        var mine = template; mine.title = "hvac service"
        var away = template; away.title = "General visit"; away.archivedAt = "2026-11-01T00:00:00Z"
        XCTAssertEqual(ChecklistRules.startersToAdd(existing: [mine, away]).map(\.title), ["Plumbing repair", "Electrical safety"])
        XCTAssertEqual(ChecklistRules.startersToAdd(existing: []).count, 4)
    }

    func testStartersAreCreatedOnceAndTheOfferIsRemembered() async throws {
        let stored = { (title: String) in #"{"id":"\#(UUID().uuidString)","title":"\#(title)","items":[{"id":"a","label":"A","kind":"tick"}],"revision":1}"# }
        let api = APIClient(session: URLProtocolFixture.session([
            .init(200, #"{"items":[\#(stored("HVAC service"))]}"#),
            .init(201, stored("Plumbing repair")), .init(201, stored("Electrical safety")), .init(201, stored("General visit")),
        ]), baseURL: origin)
        let model = ChecklistTemplatesModel()
        await model.load(api: api, includeArchived: true)
        XCTAssertFalse(ChecklistDraftStore.startersAdded(organization: "org", defaults: defaults))
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1, "Nothing is created until the owner asks")
        await model.addStarters(api: api, organization: "org", defaults: defaults)
        XCTAssertEqual(URLProtocolFixture.recorded.dropFirst().map(\.method), ["POST", "POST", "POST"], "The one it already has is not added again")
        XCTAssertEqual(try (1...3).map { try body($0)["title"] as? String }, ["Plumbing repair", "Electrical safety", "General visit"])
        XCTAssertEqual(model.active.count, 4)
        XCTAssertTrue(ChecklistDraftStore.startersAdded(organization: "org", defaults: defaults))
        XCTAssertEqual(model.notice, "3 starter checklists added. Tap one to change it.")
        XCTAssertTrue(ChecklistRules.startersToAdd(existing: model.templates ?? []).isEmpty)
    }

    func testAStaleTemplateSaveReloadsAndKeepsTheOwnersWords() async throws {
        var newer = template; newer.revision = 4; newer.title = "HVAC service (Sam)"
        let newerJSON = #"{"id":"\#(templateID)","title":"HVAC service (Sam)","items":\#(itemsJSON),"revision":4}"#
        let api = APIClient(session: URLProtocolFixture.session([
            conflict("stale checklist template revision: expected 3, current is 4; reload the template and retry"),
            .init(200, #"{"items":[\#(newerJSON)]}"#),
        ]), baseURL: origin)
        let model = ChecklistTemplatesModel()
        let result = await model.save(base: template, title: "HVAC tune-up", items: items, api: api)
        guard case .stale(let words, let fresh) = result else { return XCTFail("Expected a stale answer, got \(result)") }
        XCTAssertEqual(words, "Someone else changed this checklist. Press Save again to keep your version, or Cancel to keep theirs.")
        XCTAssertEqual(fresh?.revision, 4, "The next Save names the current revision")
        XCTAssertEqual(try body(0)["expectedRevision"] as? Int, 3)
        let outcome1 = await model.save(base: nil, title: " ", items: items, api: api)
        XCTAssertEqual(outcome1, .problem("Give the checklist a name."))
        let outcome2 = await model.save(base: nil, title: "A", items: [.init(id: "x", label: " ")], api: api)
        XCTAssertEqual(outcome2, .problem("Step 1 needs words."))
        XCTAssertEqual(URLProtocolFixture.recorded.count, 2, "A checklist that can't be saved is not sent")
    }

    // MARK: What the server sends

    func testRunsAndTemplatesDecodeWithNumbersTextAndMissingFields() throws {
        let run = try decodeRun(runJSON(revision: 4, answers: "[\(answerJSON("thermostat", by: sam)),\(answerJSON("suction", value: "118.5", by: me)),\(answerJSON("found", value: "\"Low charge\"", by: me))]"))
        XCTAssertEqual(run.answer("suction")?.value, .number(118.5)); XCTAssertEqual(run.answer("found")?.value, .text("Low charge"))
        XCTAssertNil(run.answer("thermostat")?.value); XCTAssertEqual(run.doneCount, 3)
        XCTAssertEqual(run.template.items.map(\.kind), [.tick, .number, .text]); XCTAssertEqual(run.template.items[1].unit, "psi")
        XCTAssertTrue(run.isCalled(runID)); XCTAssertTrue(run.isCalled(clientRunID)); XCTAssertFalse(run.isCompleted)
        XCTAssertEqual(ChecklistValue.number(118).words, "118"); XCTAssertEqual(ChecklistValue.number(14.6).words, "14.6")
        let bare = try JSONDecoder().decode(ServerChecklistItem.self, from: Data(#"{"id":"a","label":"A","kind":"tick"}"#.utf8))
        XCTAssertFalse(bare.required, "`required` defaults to false")
        let done = try decodeRun(runJSON(revision: 5, status: "completed", completed: #","completedByUserId":"\#(sam)","completedAt":"2026-11-20T15:14:00.000Z""#))
        XCTAssertTrue(done.isCompleted); XCTAssertEqual(done.completedByUserId, sam)
    }

    // MARK: Rules on the phone

    func testAnswersAsTheServerTakesThem() {
        let tick = items[0], number = items[1], text = items[2]
        XCTAssertEqual(ChecklistRules.wire(.init(done: true, text: "ignored"), for: tick), .init(itemId: "thermostat", done: true))
        XCTAssertEqual(ChecklistRules.wire(.init(done: true, text: " 118 "), for: number), .init(itemId: "suction", done: true, value: .number(118)))
        XCTAssertEqual(ChecklistRules.wire(.init(done: true, text: "14,6"), for: number)?.value, .number(14.6))
        XCTAssertEqual(ChecklistRules.wire(.init(done: false, text: ""), for: number), .init(itemId: "suction", done: false), "An empty reading clears the value")
        XCTAssertNil(ChecklistRules.wire(.init(done: true, text: "about 118"), for: number), "Not a number: never sent as typed")
        XCTAssertNil(ChecklistRules.wire(.init(done: true, text: "1e13"), for: number), "Outside what the server takes")
        XCTAssertEqual(ChecklistRules.problem(.init(done: true, text: "about 118"), for: number), "Type a number, like 118 or 14.6.")
        XCTAssertNil(ChecklistRules.problem(.init(done: true, text: "about 118"), for: text))
        XCTAssertEqual(ChecklistRules.wire(.init(done: true, text: "  Low charge \n"), for: text)?.value, .text("Low charge"))
        XCTAssertNil(ChecklistRules.wire(.init(done: true, text: "   "), for: text)?.value)
    }

    func testAStaleRunKeepsMyUnsentAnswersOnTopOfTheirs() throws {
        // Sam ticked the thermostat and wrote 120 for suction while my phone held 118 and a note.
        let theirs = try decodeRun(runJSON(revision: 5, answers: "[\(answerJSON("thermostat", by: sam)),\(answerJSON("suction", value: "120", by: sam))]"))
        let mine: [String: ChecklistDraftAnswer] = ["thermostat": .init(done: true), "suction": .init(done: true, text: "118"), "found": .init(done: true, text: "Low charge")]
        let changes = ChecklistRules.changes(mine, onto: theirs)
        XCTAssertEqual(changes, [.init(itemId: "suction", done: true, value: .number(118)), .init(itemId: "found", done: true, value: .text("Low charge"))],
                       "What they already have is not sent again; what differs is mine, in the checklist's order")
        XCTAssertEqual(ChecklistRules.settled(mine, on: theirs), ["thermostat"])
        let shown = ChecklistRules.shown(theirs.template, run: theirs, unsent: ["found": .init(done: true, text: "Low charge")])
        XCTAssertEqual(shown["thermostat"], .init(done: true), "Their tick shows")
        XCTAssertEqual(shown["suction"], .init(done: true, text: "120")); XCTAssertEqual(shown["found"]?.text, "Low charge")
        // An item the run does not have is dropped, never sent.
        XCTAssertTrue(ChecklistRules.changes(["gone": .init(done: true)], onto: theirs).isEmpty)
        XCTAssertEqual(ChecklistRules.settled(["gone": .init(done: true)], on: theirs), ["gone"])
    }

    func testFinishingNamesWhatIsMissingBeforeAnythingIsSent() {
        let copy = template.copy
        XCTAssertEqual(ChecklistRules.finishProblem(copy, [:]), "Check off at least one item to finish.")
        XCTAssertEqual(ChecklistRules.finishProblem(copy, ["thermostat": .init(done: true)]), "Still needed: Suction pressure.")
        XCTAssertEqual(ChecklistRules.finishProblem(copy, ["thermostat": .init(done: true), "suction": .init(done: true, text: " ")]), "Still needed: Suction pressure.",
                       "A needed reading that is ticked but empty is not done")
        XCTAssertEqual(ChecklistRules.finishProblem(copy, ["suction": .init(done: true, text: "abc")]), "Suction pressure needs a number.")
        XCTAssertNil(ChecklistRules.finishProblem(copy, ["suction": .init(done: true, text: "118")]))
        XCTAssertEqual(ChecklistRules.missingRequired(copy, [:]).map(\.id), ["suction"])
    }

    func testServerRefusalsBecomePlainWords() {
        func problem(_ status: Int, _ detail: String, category: String? = nil) -> ChecklistProblem {
            ChecklistProblem(Problem(title: "conflict", status: status, detail: detail, category: category))
        }
        XCTAssertEqual(problem(409, "stale checklist run revision: expected 2, current is 5; reload the run and retry"), .stale)
        XCTAssertEqual(problem(409, "stale checklist template revision: expected 3, current is 4; reload the template and retry"), .stale)
        XCTAssertEqual(problem(409, "a completed checklist run cannot be changed"), .completed)
        XCTAssertEqual(problem(409, "checklists cannot be changed on a canceled job"), .canceledJob)
        XCTAssertEqual(problem(409, "required checklist items are not done: suction, found"), .requiredMissing(["suction", "found"]))
        XCTAssertEqual(problem(409, "mark at least one item done before completing the checklist"), .nothingDone)
        XCTAssertEqual(problem(409, "the checklist template changed: expected revision 3, current is 4; reload the templates and start again"), .templateChanged)
        XCTAssertEqual(problem(409, "an archived checklist template cannot start a new run"), .templateArchived)
        XCTAssertEqual(problem(409, "an archived checklist template cannot be changed; restore it first"), .templateArchived)
        XCTAssertEqual(problem(409, "a job can hold at most 50 checklist runs"), .tooManyRuns)
        XCTAssertEqual(problem(409, "a workspace can keep at most 100 checklist templates, archived ones included"), .tooManyTemplates)
        XCTAssertEqual(problem(403, "job_checklists is not available", category: "feature_unavailable"), .featureOff)
        XCTAssertEqual(problem(403, "missing job.note"), .forbidden)
        XCTAssertEqual(problem(404, "checklist run not found"), .gone)
        XCTAssertEqual(ChecklistProblem(Problem(title: "Network error", status: nil, detail: "This needs a connection.")), .offline)

        let copy = template.copy
        XCTAssertEqual(ChecklistProblem.requiredMissing(["suction", "found"]).words(copy), "Still needed: Suction pressure, What you found.")
        XCTAssertEqual(ChecklistProblem.completed.words(), "This checklist is already finished, so it can\u{2019}t be changed.")
        XCTAssertEqual(ChecklistProblem.canceledJob.words(), "This job was canceled, so its checklist can\u{2019}t be changed.")
        XCTAssertEqual(ChecklistProblem.stale.words(), "Someone else changed this checklist. It was reloaded with your answers kept.")
        XCTAssertEqual(ChecklistProblem.offline.words(), "Saved on this phone. It will send when you\u{2019}re back online.")
        XCTAssertEqual(ChecklistProblem.templateChanged.words(), "Your office changed this checklist. Pick it again to start with the new one.")
        for refusal in [ChecklistProblem.stale, .completed, .canceledJob, .nothingDone, .templateChanged, .templateArchived, .tooManyRuns, .featureOff, .forbidden, .gone] {
            XCTAssertFalse(refusal.words().lowercased().contains("revision"), "No server words reach the screen")
        }
    }

    // MARK: One job's checklists

    func testStartingMintsTheRunHereAndSavesAnswersWithTheServersRevision() async throws {
        let (model, api) = model([.init(201, runJSON()), .init(200, runJSON(revision: 2, answers: "[\(answerJSON("thermostat", by: me))]"))])
        let reference = await model.start(template, api: api, runID: clientRunID)
        XCTAssertEqual(reference, clientRunID)
        XCTAssertEqual(model.runs.map(\.id), [runID]); XCTAssertTrue(model.drafts.isEmpty, "Nothing is left on the phone once the server has it")
        XCTAssertEqual(try body(0)["runId"] as? String, clientRunID); XCTAssertEqual(try body(0)["expectedTemplateRevision"] as? Int, 3)

        model.set(clientRunID, item: items[0], to: .init(done: true), api: api)
        XCTAssertEqual(model.entry(clientRunID)?.done, 1, "The tick shows at once")
        XCTAssertEqual(ChecklistDraftStore.drafts(owner: "org|me", jobID: jobID, defaults: defaults).first?.unsent["thermostat"], .init(done: true), "And is on disk before it is sent")
        model.stopTimers()
        await model.flush(api: api)
        XCTAssertEqual(URLProtocolFixture.recorded.count, 2)
        XCTAssertEqual(try body(1)["expectedRevision"] as? Int, 1)
        XCTAssertEqual(model.run(runID)?.revision, 2); XCTAssertTrue(model.drafts.isEmpty)
        await model.flush(api: api)
        XCTAssertEqual(URLProtocolFixture.recorded.count, 2, "Nothing unsent, nothing sent")
    }

    func testWithNoSignalTheRunStaysOnThePhoneAndSendsLaterWithTheSameID() async throws {
        let (model, api) = model([URLProtocolFixture.offline, URLProtocolFixture.offline])
        await model.start(template, api: api, runID: clientRunID)
        model.set(clientRunID, item: items[1], to: .init(done: true, text: "118"), api: api)
        model.stopTimers()
        XCTAssertEqual(model.notes[clientRunID], nil, "A new tick clears the last line")
        await model.flush(api: api)
        XCTAssertEqual(model.notes[clientRunID], "Saved on this phone. It will send when you\u{2019}re back online.")
        let entry = try XCTUnwrap(model.entry(clientRunID))
        XCTAssertTrue(entry.unsent); XCTAssertEqual(entry.template.title, "HVAC service", "Drawn from the copy kept with the run")
        XCTAssertEqual(entry.answers["suction"], .init(done: true, text: "118")); XCTAssertEqual(ChecklistEntryWords.line(entry), "1 of 3 done \u{00B7} on this phone")

        // The app is closed. Later, with signal, a new model picks the work up from disk.
        let api2 = APIClient(session: URLProtocolFixture.session([
            .init(201, runJSON()), .init(200, runJSON(revision: 2, answers: "[\(answerJSON("suction", value: "118", by: me))]")),
        ]), baseURL: origin)
        let later = JobChecklistModel()
        later.configure(jobID: jobID, owner: "org|me", me: me, defaults: defaults)
        XCTAssertEqual(later.drafts.map(\.runID), [clientRunID])
        XCTAssertEqual(ChecklistDraftStore.jobsWithDrafts(owner: "org|me", defaults: defaults), [jobID])
        await later.flush(api: api2)
        XCTAssertEqual(URLProtocolFixture.recorded.map { $0.url?.path }, ["/v1/jobs/\(jobID)/checklist-runs", "/v1/jobs/\(jobID)/checklist-runs/\(clientRunID)/answers"])
        XCTAssertEqual(try body(0)["runId"] as? String, clientRunID, "The same ID, so a start that did reach the server is not doubled")
        let answers = try XCTUnwrap(try body(1)["answers"] as? [[String: Any]])
        XCTAssertEqual(answers.count, 1); XCTAssertEqual(answers[0]["value"] as? Double, 118)
        XCTAssertTrue(later.drafts.isEmpty); XCTAssertNil(later.notes[clientRunID])
        XCTAssertTrue(ChecklistDraftStore.jobsWithDrafts(owner: "org|me", defaults: defaults).isEmpty)
    }

    func testAStaleRevisionReloadsTheRunAndPutsMyTickBackOnTop() async throws {
        let mine = try decodeRun(runJSON(revision: 2))
        let theirs = runJSON(revision: 5, answers: "[\(answerJSON("thermostat", by: sam)),\(answerJSON("suction", value: "120", by: sam))]")
        let merged = runJSON(revision: 6, answers: "[\(answerJSON("thermostat", by: sam)),\(answerJSON("suction", value: "120", by: sam)),\(answerJSON("found", value: "\"Low charge\"", by: me))]")
        let (model, api) = model([
            conflict("stale checklist run revision: expected 2, current is 5; reload the run and retry"),
            .init(200, #"{"items":[\#(theirs)]}"#),
            .init(200, merged),
        ], runs: [mine])
        model.set(runID, item: items[0], to: .init(done: true), api: api)
        model.set(runID, item: items[2], to: .init(done: true, text: "Low charge"), api: api)
        model.stopTimers()
        await model.flush(api: api)
        let requests = URLProtocolFixture.recorded
        XCTAssertEqual(requests.map(\.method), ["POST", "GET", "POST"])
        XCTAssertEqual(try body(0)["expectedRevision"] as? Int, 2)
        XCTAssertEqual(try body(2)["expectedRevision"] as? Int, 5, "Sent again with the revision just read")
        let again = try XCTUnwrap(try body(2)["answers"] as? [[String: Any]])
        XCTAssertEqual(again.map { $0["itemId"] as? String }, ["found"], "Sam already ticked the thermostat, so only my note goes")
        let entry = try XCTUnwrap(model.entry(runID))
        XCTAssertEqual(entry.answers["suction"]?.text, "120", "Sam's reading shows after the reload")
        XCTAssertEqual(entry.answers["found"]?.text, "Low charge"); XCTAssertEqual(entry.done, 3)
        XCTAssertEqual(model.notes[runID], "Someone else changed this checklist. It was reloaded with your answers kept.")
        XCTAssertTrue(model.drafts.isEmpty)
        XCTAssertEqual(model.who(sam), "A teammate"); XCTAssertEqual(model.who(me), "You")
    }

    func testAStaleRevisionIsTriedOnceNotForever() async throws {
        let stale = conflict("stale checklist run revision: expected 2, current is 5; reload the run and retry")
        let (model, api) = model([stale, .init(200, #"{"items":[\#(runJSON(revision: 5))]}"#), stale, stale, stale], runs: [try decodeRun(runJSON(revision: 2))])
        model.set(runID, item: items[0], to: .init(done: true), api: api)
        model.stopTimers()
        await model.flush(api: api)
        XCTAssertEqual(URLProtocolFixture.recorded.count, 3, "One reload and one more try")
        XCTAssertEqual(model.entry(runID)?.answers["thermostat"], .init(done: true), "My tick is still on the phone")
        XCTAssertNotNil(model.notes[runID])
    }

    func testAFinishedRunAndACanceledJobAreSaidPlainly() async throws {
        let finished = runJSON(revision: 9, status: "completed", completed: #","completedByUserId":"\#(sam)","completedAt":"2026-11-20T15:14:00.000Z""#)
        var (model, api) = model([conflict("a completed checklist run cannot be changed"), .init(200, #"{"items":[\#(finished)]}"#)],
                                 runs: [try decodeRun(runJSON(revision: 2))])
        model.set(runID, item: items[0], to: .init(done: true), api: api)
        model.stopTimers()
        await model.flush(api: api)
        XCTAssertEqual(model.notes[runID], "This checklist was finished before your answers were sent. They\u{2019}re still on this phone.")
        XCTAssertEqual(model.drafts.count, 1, "A teammate finishing first is not a receipt for my unsent tick")
        XCTAssertEqual(model.drafts.first?.unsent["thermostat"], .init(done: true))
        XCTAssertEqual(ChecklistDraftStore.drafts(owner: "org|me", jobID: jobID, defaults: defaults).count, 1, "Kept across launches")
        let entry = try XCTUnwrap(model.entry(runID))
        XCTAssertTrue(entry.completed); XCTAssertEqual(entry.completedBy, "A teammate")
        XCTAssertEqual(entry.answers["thermostat"], .init(done: false), "The finished run shows what the server holds")
        XCTAssertTrue(ChecklistEntryWords.line(entry).hasPrefix("Finished by A teammate \u{00B7} "))
        XCTAssertEqual(model.keptText(runID), "HVAC service\nThermostat calls for heat and cool: Done")
        model.set(runID, item: items[0], to: .init(done: false), api: api)
        XCTAssertEqual(model.drafts.first?.unsent["thermostat"], .init(done: true), "A finished run can't be changed on the phone")
        await model.flush(api: api)
        XCTAssertEqual(URLProtocolFixture.recorded.count, 2, "A tick that can never land is not kept trying")
        XCTAssertNotNil(model.notes[runID])
        model.discardKept(runID)
        XCTAssertTrue(model.drafts.isEmpty, "Let go only on the person's word")
        XCTAssertTrue(ChecklistDraftStore.drafts(owner: "org|me", jobID: jobID, defaults: defaults).isEmpty)

        defaults = UserDefaults(suiteName: "checklists-\(UUID().uuidString)")!
        (model, api) = self.model([conflict("checklists cannot be changed on a canceled job")], runs: [try decodeRun(runJSON(revision: 2))])
        model.set(runID, item: items[0], to: .init(done: true), api: api)
        model.stopTimers()
        await model.flush(api: api)
        XCTAssertEqual(model.notes[runID], "This job was canceled, so its checklist can\u{2019}t be changed.")
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
    }

    func testMarkingDoneSendsAnswersFirstThenCompletes() async throws {
        let answered = "[\(answerJSON("suction", value: "118", by: me))]"
        let done = runJSON(revision: 4, answers: answered, status: "completed", completed: #","completedByUserId":"\#(me)","completedAt":"2026-11-20T15:14:00.000Z""#)
        let (model, api) = model([.init(200, runJSON(revision: 3, answers: answered)), .init(200, done)], runs: [try decodeRun(runJSON(revision: 2))])
        let outcome3 = await model.finish(runID, api: api)
        XCTAssertEqual(outcome3, .problem("Check off at least one item to finish."))
        model.set(runID, item: items[0], to: .init(done: true), api: api)
        let outcome4 = await model.finish(runID, api: api)
        XCTAssertEqual(outcome4, .problem("Still needed: Suction pressure."))
        XCTAssertTrue(URLProtocolFixture.recorded.isEmpty, "Said on the phone, without asking the server")
        model.set(runID, item: items[0], to: .init(done: false), api: api)
        model.set(runID, item: items[1], to: .init(done: true, text: "118"), api: api)
        let outcome5 = await model.finish(runID, api: api)
        XCTAssertEqual(outcome5, .finished)
        XCTAssertEqual(URLProtocolFixture.recorded.map { $0.url?.lastPathComponent }, ["answers", "complete"])
        XCTAssertEqual(try body(1) as NSDictionary, ["expectedRevision": 3], "Completed with the revision the save answered")
        XCTAssertEqual(model.entry(runID)?.completedBy, "You"); XCTAssertTrue(model.drafts.isEmpty)
        XCTAssertEqual(model.tileDetail, "1 finished")
    }

    func testTheServerNamingAMissingItemUsesItsLabelAndFinishingOfflineWaits() async throws {
        var (model, api) = model([conflict("required checklist items are not done: suction")],
                                 runs: [try decodeRun(runJSON(revision: 2, answers: "[\(answerJSON("thermostat", by: sam))]", client: false))])
        // The phone thinks suction is done (an old copy); the server says otherwise.
        ChecklistDraftStore.save(runs: [try decodeRun(runJSON(revision: 2, answers: "[\(answerJSON("suction", value: "118", by: sam))]", client: false))],
                                 owner: "org|me", jobID: jobID, defaults: defaults)
        model = JobChecklistModel(); model.quietTime = .seconds(60)
        model.configure(jobID: jobID, owner: "org|me", me: me, defaults: defaults)
        let outcome6 = await model.finish(runID, api: api)
        XCTAssertEqual(outcome6, .problem("Still needed: Suction pressure."))
        XCTAssertEqual(model.drafts.first?.finishing, false, "A refused finish is not retried behind the person's back")

        defaults = UserDefaults(suiteName: "checklists-\(UUID().uuidString)")!
        (model, api) = self.model([URLProtocolFixture.offline], runs: [try decodeRun(runJSON(revision: 2, answers: "[\(answerJSON("suction", value: "118", by: sam))]", client: false))])
        let outcome7 = await model.finish(runID, api: api)
        XCTAssertEqual(outcome7, .onPhone)
        XCTAssertEqual(model.drafts.first?.finishing, true, "It finishes by itself when the phone is back online")
        XCTAssertEqual(model.entry(runID)?.unsent, true)
        let api2 = APIClient(session: URLProtocolFixture.session([.init(200, runJSON(revision: 3, status: "completed", client: false))]), baseURL: origin)
        await model.flush(api: api2)
        XCTAssertEqual(model.entry(runID)?.completed, true); XCTAssertTrue(model.drafts.isEmpty)
    }

    func testAChangedTemplateKeepsTheRunOnThePhoneUntilItIsRemoved() async throws {
        let (model, api) = model([conflict("the checklist template changed: expected revision 3, current is 4; reload the templates and start again")])
        await model.start(template, api: api, runID: clientRunID)
        XCTAssertEqual(model.notes[clientRunID], "Your office changed this checklist. Pick it again to start with the new one.")
        XCTAssertEqual(model.entries.count, 1)
        model.discard(clientRunID)
        XCTAssertTrue(model.entries.isEmpty); XCTAssertTrue(ChecklistDraftStore.drafts(owner: "org|me", jobID: jobID, defaults: defaults).isEmpty)
    }

    func testTheJobListsEveryRunWithWhoAndWhen() throws {
        let done = try decodeRun(runJSON(revision: 5, status: "completed", completed: #","completedByUserId":"\#(me)","completedAt":"2026-11-20T15:14:00.000Z""#))
        var open = try decodeRun(runJSON(revision: 2, answers: "[\(answerJSON("thermostat", by: sam))]"))
        open = ServerChecklistRun(id: "99999999-9999-4999-8999-999999999999", jobId: jobID, clientRunId: nil, templateId: open.templateId, templateRevision: 3,
                                  template: open.template, answers: open.answers, revision: 2, status: "in_progress", startedByUserId: sam, startedAt: open.startedAt)
        let (model, _) = model([], runs: [done, open])
        XCTAssertEqual(model.entries.map(\.completed), [true, false])
        XCTAssertEqual(model.entries[0].completedBy, "You")
        XCTAssertTrue(ChecklistEntryWords.line(model.entries[0]).hasPrefix("Finished by you \u{00B7} Nov 20"))
        XCTAssertEqual(ChecklistEntryWords.line(model.entries[1]), "1 of 3 done")
        XCTAssertEqual(ChecklistEntryWords.next(model.entries[1]), "Next: Suction pressure")
        XCTAssertEqual(model.tileDetail, "1 of 3 done")
        XCTAssertEqual(JobServerChecklistSheet.firstOpen(model.entries), open.id, "The one under way opens straight away")
    }

    // MARK: The feature flag

    private func session(features: [String], capabilities: [String] = ["job.view", "job.note"]) async -> SessionController {
        let actor = "019f0000-0000-7000-8000-000000000011", organization = "019f0000-0000-7000-8000-000000000001"
        let session = #"{"user":{"id":"\#(actor)","name":"Fixture","email":"fixture@example.invalid","emailVerified":true},"session":{"id":"fixture-session","userId":"\#(actor)","activeOrganizationId":"\#(organization)","expiresAt":"2099-10-27T12:00:00.000Z"}}"#
        let list = capabilities.map { "\"\($0)\"" }.joined(separator: ",")
        let catalog = #"{"authority":{"actorId":"\#(actor)","organizationId":"\#(organization)","policyVersion":1,"generation":"fixture-generation"},"capabilities":[\#(list)],"resources":[],"views":[]}"#
        let decisions = features.map { #""\#($0)":{"enabled":true,"released":true,"entitled":true,"stage":"general"}"# }.joined(separator: ",")
        let exposure = #"{"organizationId":"\#(organization)","evaluatedAt":"2026-11-20T12:00:00.000Z","features":{\#(decisions)}}"#
        let api = APIClient(session: URLProtocolFixture.session([.init(200, session), .init(200, #"[{"id":"\#(organization)","name":"Fixture workspace"}]"#),
                                                                 .init(200, catalog), .init(200, exposure)]), baseURL: origin)
        let controller = SessionController(api: api, defaults: UserDefaults(suiteName: "checklists.session.\(UUID().uuidString)")!)
        await controller.restore()
        XCTAssertEqual(controller.phase, .ready)
        return controller
    }

    func testEverythingHereWaitsForTheFeature() async throws {
        let off = await session(features: ["jobs"])
        XCTAssertFalse(ChecklistFeature.isOn(off), "Today's production: the on-phone checklists are used")
        let owner = try XCTUnwrap(ChecklistDraftStore.owner(off))
        ChecklistDraftStore.save([ChecklistDraft(runID: clientRunID, templateID: templateID, templateRevision: 3, template: template.copy, started: false)],
                                 owner: owner, jobID: jobID, defaults: defaults)
        let api = APIClient(session: URLProtocolFixture.session([]), baseURL: origin)
        await ChecklistSync.flushAll(api: api, session: off, defaults: defaults)
        XCTAssertTrue(URLProtocolFixture.recorded.isEmpty, "With the feature off nothing is asked of the checklist routes")

        let on = await session(features: ["jobs", "job_checklists"])
        XCTAssertTrue(ChecklistFeature.isOn(on))
        XCTAssertFalse(ChecklistFeature.canManage(on), "A tech reads templates and cannot change them")
        let boss = await session(features: ["jobs", "job_checklists"], capabilities: ["job.view", "organization.settings.edit"])
        XCTAssertTrue(ChecklistFeature.canManage(boss))
    }
}

import XCTest
@testable import Thorbis

/// Saved job views: the server's payloads (shapes from Thorbis-TanStack `domains/views` and the
/// `jobs` query resource) and the mapping between a view's filter and the phone's job filters.
@MainActor
final class JobSavedViewsTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    private func filter(_ root: String) throws -> SavedViewJSON {
        try decode(SavedViewJSON.self, #"{"schemaVersion":1,"root":\#(root)}"#)
    }

    private func choices(_ root: String, sort: [SavedViewSort] = []) throws -> JobBoardChoices? {
        if case .choices(let choices) = JobSavedViewMapping.read(filter: try filter(root), sort: sort, calendar: utc) { return choices }
        return nil
    }

    private func reason(_ root: String) throws -> String? {
        if case .unsupported(let reason) = JobSavedViewMapping.read(filter: try filter(root), sort: [], calendar: utc) { return reason }
        return nil
    }

    // MARK: Decoding

    /// GET /v1/views?resourceId=jobs: a ListedView page (ViewDefinition + source + rowId), as
    /// `storedViewToDefinition` builds it. The last page has no nextCursor.
    func testDecodesAListedViewPage() throws {
        let page = try decode(SavedJobViewPage.self, #"""
        {"items":[
          {"id":"jobs.018f0000-0000-7000-8000-0000000000aa","resourceId":"jobs","owner":"jobs",
           "permissionProjection":"job.view","schemaVersion":1,"revision":3,"label":"Open work",
           "description":"Everything under way","visibility":"personal","layout":"board",
           "filter":{"schemaVersion":1,"root":{"type":"condition","field":"jobs.status","operator":"is","value":"in_progress"}},
           "sort":[{"field":"jobs.created_at","direction":"desc"}],"columns":["jobs.title","jobs.status"],
           "status":"active","createdBy":"018f0000-0000-7000-8000-000000000002",
           "createdAt":"2026-09-01T12:00:00.000Z","updatedAt":"2026-09-02T12:00:00.000Z",
           "source":"persisted","rowId":"018f0000-0000-7000-8000-000000000064"},
          {"id":"jobs.shared","resourceId":"jobs","revision":1,"label":"Company board","visibility":"organization",
           "layout":"table","filter":{"schemaVersion":1,"root":{"type":"condition","field":"jobs.id","operator":"is_not_empty"}},
           "sort":[],"columns":[],"status":"archived","source":"persisted"}
        ]}
        """#)
        XCTAssertNil(page.nextCursor)
        XCTAssertEqual(page.items.map(\.id), ["jobs.018f0000-0000-7000-8000-0000000000aa", "jobs.shared"])
        let first = try XCTUnwrap(page.items.first)
        XCTAssertEqual(first.label, "Open work")
        XCTAssertEqual(first.revision, 3)
        XCTAssertEqual(first.visibility, "personal")
        XCTAssertEqual(first.layout, "board")
        XCTAssertEqual(first.sort, [SavedViewSort(field: "jobs.created_at", direction: "desc")])
        XCTAssertEqual(first.columns, ["jobs.title", "jobs.status"])
        XCTAssertEqual(first.createdBy, "018f0000-0000-7000-8000-000000000002")
        XCTAssertEqual(first.filter["root"]?["value"]?.text, "in_progress")
        XCTAssertFalse(first.isArchived)
        XCTAssertTrue(page.items[1].isArchived)
    }

    func testAMalformedViewIsSkippedAndTheRestKept() throws {
        let page = try decode(SavedJobViewPage.self, #"""
        {"items":[{"id":"jobs.broken","resourceId":"jobs"},
                  {"id":"jobs.good","resourceId":"jobs","label":"Good","filter":{"schemaVersion":1,"root":{"type":"condition","field":"jobs.id","operator":"is_not_empty"}}}],
         "nextCursor":"018f0000-0000-7000-8000-000000000064"}
        """#)
        XCTAssertEqual(page.items.map(\.id), ["jobs.good"])
        XCTAssertEqual(page.nextCursor, "018f0000-0000-7000-8000-000000000064")
        // Defaults for what an older server might leave out.
        XCTAssertEqual(page.items[0].revision, 1)
        XCTAssertEqual(page.items[0].sort, [])
        XCTAssertEqual(page.items[0].status, "active")
    }

    /// GET /v1/views/membership (ViewMembership): undefined defaults are absent from the JSON.
    func testDecodesMembership() throws {
        let membership = try decode(SavedViewMembership.self, #"""
        {"resourceId":"jobs","favorites":["jobs.open","jobs.018f0000-0000-7000-8000-0000000000aa"],"subscriptions":[],
         "organizationDefault":"jobs.open"}
        """#)
        XCTAssertEqual(membership.favorites, ["jobs.open", "jobs.018f0000-0000-7000-8000-0000000000aa"])
        XCTAssertNil(membership.personalDefault)
        XCTAssertEqual(membership.organizationDefault, "jobs.open")
    }

    // MARK: Reading a view onto the phone's filters

    func testTheServersOwnSystemFiltersRead() throws {
        // jobs.all
        XCTAssertEqual(try choices(#"{"type":"condition","field":"jobs.id","operator":"is_not_empty"}"#), JobBoardChoices())
        // jobs.open: every status but completed and canceled is the phone's "Hiding done".
        var hidingDone = JobBoardChoices()
        hidingDone.hidesDone = true
        XCTAssertEqual(try choices(#"{"type":"condition","field":"jobs.status","operator":"is_any_of","value":["scheduled","dispatched","en_route","arrived","in_progress","paused"]}"#), hidingDone)
        // jobs.completed
        var done = JobBoardChoices()
        done.statuses = ["completed"]
        XCTAssertEqual(try choices(#"{"type":"condition","field":"jobs.status","operator":"is","value":"completed"}"#), done)
    }

    func testAnAndGroupReadsEveryRule() throws {
        let read = try choices(#"""
        {"type":"group","operator":"and","children":[
          {"type":"condition","field":"jobs.assigned_to_user_id","operator":"is","value":"018f0000-0000-7000-8000-000000000002"},
          {"type":"condition","field":"jobs.status","operator":"is_none_of","value":["canceled"]},
          {"type":"condition","field":"jobs.scheduled_for","operator":"after","value":"2026-11-15T23:59:59.999Z"},
          {"type":"condition","field":"jobs.scheduled_for","operator":"before","value":"2026-11-22T00:00:00.000Z"}
        ]}
        """#, sort: [SavedViewSort(field: "jobs.scheduled_for", direction: "asc")])
        let found = try XCTUnwrap(read)
        XCTAssertEqual(found.assignee, .user("018f0000-0000-7000-8000-000000000002"))
        XCTAssertEqual(found.statuses, JobSavedViewMapping.serverStatuses.subtracting(["canceled"]))
        XCTAssertFalse(found.hidesDone)
        XCTAssertEqual(found.ordering, .scheduled)
        let day = { (text: String) in ISO8601DateFormatter().date(from: text)! }
        XCTAssertEqual(found.days, JobBoardChoices.Days(from: day("2026-11-16T00:00:00Z"), to: day("2026-11-21T00:00:00Z")))
    }

    func testUnassignedAndOneTechFromAList() throws {
        XCTAssertEqual(try choices(#"{"type":"condition","field":"jobs.assigned_to_user_id","operator":"is_empty"}"#)?.assignee, .unassigned)
        XCTAssertEqual(try choices(#"{"type":"condition","field":"jobs.assigned_to_user_id","operator":"is_any_of","value":["tech-1"]}"#)?.assignee, .user("tech-1"))
    }

    func testAnOrderThePhoneLacksFallsBackWithoutChangingTheJobs() throws {
        let read = try choices(#"{"type":"condition","field":"jobs.id","operator":"is_not_empty"}"#,
                               sort: [SavedViewSort(field: "jobs.created_at", direction: "desc")])
        XCTAssertEqual(read?.ordering, .recent)
    }

    func testWhatThePhoneCannotFilterByIsRefusedWithAReason() throws {
        let cases: [(String, String)] = [
            (#"{"type":"condition","field":"jobs.title","operator":"contains","value":"heater"}"#, "job title"),
            (#"{"type":"condition","field":"jobs.customer_id","operator":"is","value":"c1"}"#, "customer"),
            (#"{"type":"condition","field":"jobs.created_at","operator":"after","value":"2026-01-01T00:00:00.000Z"}"#, "created date"),
            (#"{"type":"condition","field":"jobs.scheduled_for","operator":"is_empty"}"#, "no time"),
            (#"{"type":"condition","field":"jobs.scheduled_for","operator":"after","value":"2026-11-16T00:00:00.000Z"}"#, "open-ended"),
            (#"{"type":"condition","field":"jobs.assigned_to_user_id","operator":"is_any_of","value":["a","b"]}"#, "several technicians"),
            (#"{"type":"condition","field":"jobs.assigned_to_user_id","operator":"is_not_empty"}"#, "every assigned job"),
            (#"{"type":"condition","field":"jobs.status","operator":"is","value":"on_fire"}"#, "status"),
            (#"{"type":"group","operator":"or","children":[{"type":"condition","field":"jobs.status","operator":"is","value":"paused"},{"type":"condition","field":"jobs.assigned_to_user_id","operator":"is_empty"}]}"#, "either/or"),
            (#"{"type":"relationship","relationship":"jobs.invoices","quantifier":"any","filter":{"type":"condition","field":"invoices.status","operator":"is","value":"sent"}}"#, "linked record"),
            (#"{"type":"mystery"}"#, "could not be read")
        ]
        for (root, expected) in cases {
            let found = try XCTUnwrap(try reason(root), "should be unsupported: \(root)")
            XCTAssertTrue(found.localizedCaseInsensitiveContains(expected), "\(found) should mention \(expected)")
        }
        // Times that are not on a day boundary cannot become a whole-day range.
        let exact = try reason(#"""
        {"type":"group","operator":"and","children":[
          {"type":"condition","field":"jobs.scheduled_for","operator":"after","value":"2026-11-16T09:30:00.000Z"},
          {"type":"condition","field":"jobs.scheduled_for","operator":"before","value":"2026-11-22T00:00:00.000Z"}]}
        """#)
        XCTAssertEqual(exact, "Uses exact times; this phone filters by whole days.")
        // Statuses that cancel each other out show nothing, which the phone cannot express.
        XCTAssertNotNil(try reason(#"""
        {"type":"group","operator":"and","children":[
          {"type":"condition","field":"jobs.status","operator":"is","value":"paused"},
          {"type":"condition","field":"jobs.status","operator":"is","value":"completed"}]}
        """#))
    }

    func testAViewForAnotherResourceIsNotApplied() throws {
        let view = SavedJobView(id: "customers.x", resourceId: "customers", label: "VIPs",
                                filter: try filter(#"{"type":"condition","field":"jobs.id","operator":"is_not_empty"}"#))
        XCTAssertEqual(JobSavedViewMapping.read(view), .unsupported("This view is not for jobs."))
    }

    // MARK: Writing the phone's filters as a view

    func testNoFiltersWritesTheServersEverythingFilter() throws {
        let written = try JobSavedViewMapping.write(JobBoardChoices(), calendar: utc).get()
        XCTAssertEqual(written.filter, try filter(#"{"type":"condition","field":"jobs.id","operator":"is_not_empty"}"#))
        XCTAssertEqual(written.sort, [SavedViewSort(field: "jobs.updated_at", direction: "desc")])
    }

    func testWritesEachChoiceInTheServersOperators() throws {
        var choices = JobBoardChoices()
        choices.assignee = .user("tech-1")
        choices.statuses = ["paused", "on_hold"] // the phone's "On hold" group; the server has only "paused"
        choices.ordering = .name
        let day = { (text: String) in ISO8601DateFormatter().date(from: text)! }
        choices.days = JobBoardChoices.Days(from: day("2026-11-16T00:00:00Z"), to: day("2026-11-21T00:00:00Z"))
        let written = try JobSavedViewMapping.write(choices, calendar: utc).get()
        XCTAssertEqual(written.filter, try filter(#"""
        {"type":"group","operator":"and","children":[
          {"type":"condition","field":"jobs.assigned_to_user_id","operator":"is","value":"tech-1"},
          {"type":"condition","field":"jobs.status","operator":"is","value":"paused"},
          {"type":"condition","field":"jobs.scheduled_for","operator":"after","value":"2026-11-15T23:59:59.999Z"},
          {"type":"condition","field":"jobs.scheduled_for","operator":"before","value":"2026-11-22T00:00:00.000Z"}]}
        """#))
        XCTAssertEqual(written.sort, [SavedViewSort(field: "jobs.title", direction: "asc")])
    }

    func testHidingDoneAndUnassigned() throws {
        var choices = JobBoardChoices()
        choices.assignee = .unassigned
        choices.hidesDone = true
        let written = try JobSavedViewMapping.write(choices, calendar: utc).get()
        XCTAssertEqual(written.filter, try filter(#"""
        {"type":"group","operator":"and","children":[
          {"type":"condition","field":"jobs.assigned_to_user_id","operator":"is_empty"},
          {"type":"condition","field":"jobs.status","operator":"is_none_of","value":["canceled","completed"]}]}
        """#))
    }

    func testMovingDatesAndEmptyResultsAreNotSaved() {
        var today = JobBoardChoices()
        today.when = .today
        XCTAssertEqual(JobSavedViewMapping.write(today, calendar: utc), .failure(.movingDate))
        var nothing = JobBoardChoices()
        nothing.statuses = ["completed"]
        nothing.hidesDone = true
        XCTAssertEqual(JobSavedViewMapping.write(nothing, calendar: utc), .failure(.showsNothing))
    }

    func testWhatIsWrittenReadsBackAsTheSameChoices() throws {
        let day = { (text: String) in ISO8601DateFormatter().date(from: text)! }
        var all: [JobBoardChoices] = [JobBoardChoices()]
        var one = JobBoardChoices(); one.assignee = .unassigned; one.statuses = ["scheduled", "dispatched"]; one.ordering = .scheduled
        var two = JobBoardChoices(); two.assignee = .user("tech-9"); two.hidesDone = true
        var three = JobBoardChoices(); three.days = .init(from: day("2026-12-01T00:00:00Z"), to: day("2026-12-01T00:00:00Z")); three.ordering = .name
        var four = JobBoardChoices(); four.statuses = ["completed", "canceled", "paused"]
        all += [one, two, three, four]
        for choices in all {
            let written = try JobSavedViewMapping.write(choices, calendar: utc).get()
            XCTAssertEqual(JobSavedViewMapping.read(filter: written.filter, sort: written.sort, calendar: utc), .choices(choices))
        }
    }

    func testEveryOpenStatusTickedIsTheSameViewAsHidingDone() {
        var ticked = JobBoardChoices()
        ticked.statuses = JobSavedViewMapping.serverStatuses.subtracting(JobSavedViewMapping.doneStatuses)
        var hiding = JobBoardChoices()
        hiding.hidesDone = true
        XCTAssertEqual(ticked.canonical, hiding.canonical)
        XCTAssertTrue(JobBoardChoices().isEverything)
        XCTAssertFalse(hiding.isEverything)
    }

    // MARK: Requests

    /// POST /v1/views (saveViewInputSchema): optional keys are left out, never sent as null.
    func testANewViewsBodyHasOnlyTheKeysTheServerTakes() throws {
        let written = try JobSavedViewMapping.write(JobBoardChoices(), calendar: utc).get()
        let id = JobSavedViewMapping.newViewID(UUID(uuidString: "0F8FAD5B-D9CB-469F-A165-70867728950E")!)
        XCTAssertEqual(id, "jobs.0f8fad5b-d9cb-469f-a165-70867728950e")
        XCTAssertTrue(JobSavedViewMapping.isViewID(id))
        XCTAssertFalse(JobSavedViewMapping.isViewID("jobs/../x"))
        let body = SavedJobViewSave(id: id, resourceId: "jobs", label: "Everything", visibility: "personal",
                                    layout: "list", filter: written.filter, sort: written.sort)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["id", "resourceId", "label", "visibility", "layout", "filter", "sort"])
        XCTAssertEqual((json["filter"] as? [String: Any])?["schemaVersion"] as? Int, 1)
    }

    /// A rename sends the stored definition back untouched, with the revision it was read at.
    func testRenameKeepsTheFilterAndSendsTheRevision() throws {
        let stored = try filter(#"{"type":"condition","field":"jobs.title","operator":"contains","value":"heater"}"#)
        let view = SavedJobView(id: "jobs.abc", label: "Heaters", description: "Tank swaps", visibility: "organization",
                                layout: "board", filter: stored, sort: [SavedViewSort(field: "jobs.title", direction: "asc")],
                                groupBy: "jobs.status", columns: ["jobs.title"], revision: 4, createdBy: "someone")
        let body = JobSavedViewsBook.renameBody(view, label: "Water heaters")
        XCTAssertEqual(body, SavedJobViewSave(id: "jobs.abc", resourceId: "jobs", label: "Water heaters",
                                              description: "Tank swaps", visibility: "organization", layout: "board",
                                              filter: stored, sort: [SavedViewSort(field: "jobs.title", direction: "asc")],
                                              groupBy: "jobs.status", columns: ["jobs.title"], expectedRevision: 4))
    }

    func testOnlyTheOwnerOrAnOrganisationEditorMayChangeAView() throws {
        let any = try filter(#"{"type":"condition","field":"jobs.id","operator":"is_not_empty"}"#)
        let mine = SavedJobView(id: "jobs.a", label: "A", visibility: "personal", filter: any, createdBy: "me")
        let shared = SavedJobView(id: "jobs.b", label: "B", visibility: "organization", filter: any, createdBy: "other")
        XCTAssertTrue(JobSavedViewsBook.canChange(mine, me: "me", canEditOrganization: false))
        XCTAssertFalse(JobSavedViewsBook.canChange(mine, me: "other", canEditOrganization: true))
        XCTAssertFalse(JobSavedViewsBook.canChange(shared, me: "me", canEditOrganization: false))
        XCTAssertTrue(JobSavedViewsBook.canChange(shared, me: "me", canEditOrganization: true))
    }

    // MARK: Words and counts

    func testSummaryAndJobCount() {
        var choices = JobBoardChoices()
        choices.assignee = .user("me")
        choices.statuses = ["paused"]
        XCTAssertEqual(JobSavedViewMapping.summary(choices, me: "me", techName: { _ in nil }), ["Mine", "Status: On hold"])
        choices.assignee = .user("t2")
        XCTAssertEqual(JobSavedViewMapping.summary(choices, me: "me", techName: { _ in "Ramon M." }).first, "Ramon M.")
        let jobs = [
            Job(id: "1", customerId: nil, title: "a", status: "paused", createdAt: nil, updatedAt: nil, allowedTransitions: nil, assignedToUserId: "t2"),
            Job(id: "2", customerId: nil, title: "b", status: "paused", createdAt: nil, updatedAt: nil, allowedTransitions: nil, assignedToUserId: "me"),
            Job(id: "3", customerId: nil, title: "c", status: "scheduled", createdAt: nil, updatedAt: nil, allowedTransitions: nil, assignedToUserId: "t2")
        ]
        XCTAssertEqual(choices.jobs(from: jobs).map(\.id), ["1"])
    }
}

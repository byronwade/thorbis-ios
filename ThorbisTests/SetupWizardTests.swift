import XCTest
@testable import Thorbis

@MainActor
final class SetupWizardTests: XCTestCase {
    func testCSVReaderHandlesQuotesCommasAndLineBreaks() {
        let text = "Name,Phone,Notes\r\n\"Smith, Ann\",555-0100,\"Gate code \"\"42\"\"\nBack door\"\n,,\nBob,555-0101,\n"
        XCTAssertEqual(CSVReader.rows(text), [
            ["Name", "Phone", "Notes"],
            ["Smith, Ann", "555-0100", "Gate code \"42\"\nBack door"],
            ["", "", ""],
            ["Bob", "555-0101", ""],
        ])
    }

    func testMappingGuessesCommonExportHeaders() {
        let mapping = CustomerImportMapping.guess(["First Name", "Last Name", "Mobile Phone", "E-mail", "Street Address", "City", "State", "Zip Code", "Customer Notes"])
        XCTAssertNil(mapping.name)
        XCTAssertEqual(mapping.firstName, 0)
        XCTAssertEqual(mapping.lastName, 1)
        XCTAssertEqual(mapping.phone, 2)
        XCTAssertEqual(mapping.email, 3)
        XCTAssertEqual(mapping.address, 4)
        XCTAssertEqual(mapping.city, 5)
        XCTAssertEqual(mapping.state, 6)
        XCTAssertEqual(mapping.zip, 7)
        XCTAssertEqual(mapping.notes, 8)
        XCTAssertTrue(mapping.canImport)
        XCTAssertEqual(CustomerImportMapping.guess(["Customer Name", "Phone"]).name, 0)
        XCTAssertFalse(CustomerImportMapping.guess(["Phone", "Email"]).canImport)
    }

    func testRowsBecomeTheServerShape() throws {
        let mapping = CustomerImportMapping.guess(["First Name", "Last Name", "Phone", "Email", "Address", "City", "State", "Zip"])
        let row = try XCTUnwrap(CustomerImportRow.from(["Ann", "Smith", "555-0100; 555-0101", "", "1 Oak St", "Austin", "TX", "78701"], mapping: mapping))
        XCTAssertEqual(row, CustomerImportRow(name: "Ann Smith", phones: ["555-0100", "555-0101"], emails: nil,
                                              addresses: ["1 Oak St, Austin, TX 78701"], notes: nil))
        XCTAssertNil(CustomerImportRow.from(["", "", "555-0100"], mapping: mapping))
        let json = String(data: try JSONEncoder().encode(row), encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("emails"))
    }

    func testChunksStayWithinBothServerLimits() {
        let light = CustomerImportRow(name: "A", phones: ["1"], emails: nil, addresses: nil, notes: nil)
        XCTAssertEqual(CustomerImportRow.chunks(Array(repeating: light, count: 250)).map(\.count), [100, 100, 50])
        let heavy = CustomerImportRow(name: "B", phones: Array(repeating: "1", count: 5), emails: Array(repeating: "e", count: 5),
                                      addresses: ["x"], notes: nil)
        XCTAssertEqual(heavy.work, 12)
        let ranges = CustomerImportRow.chunks(Array(repeating: heavy, count: 40))
        XCTAssertEqual(ranges.map(\.count), [16, 16, 8])
        XCTAssertTrue(ranges.allSatisfy { $0.count * heavy.work <= CustomerImportRow.maxWorkPerRequest })
        XCTAssertEqual(CustomerImportRow.chunks([]), [])
    }

    func testRowsWithoutANameAreCountedNotDropped() {
        let model = CustomerImportModel()
        model.headers = ["Name", "Phone"]
        model.records = [["Ann", "1"], ["", "2"], ["", ""], ["Bob", ""]]
        model.mapping = .guess(model.headers)
        let prepared = model.prepared
        XCTAssertEqual(prepared.rows.map(\.name), ["Ann", "Bob"])
        XCTAssertEqual(prepared.lines, [2, 5], "a blank row still counts toward the spreadsheet row number")
        XCTAssertEqual(prepared.unnamed, [3])
        XCTAssertEqual(model.rowCount, 3)
    }

    // MARK: Customer import: counting a retried chunk, row warnings, who may import

    private typealias Outcome = CustomerImportResult.Outcome
    private static let notesWarning = "notes were not imported: they are kept on a service address and this row has none"

    private func importAPI(_ replies: [URLProtocolFixture.Reply]) -> APIClient {
        APIClient(session: URLProtocolFixture.session(replies), baseURL: "https://app.thorbis.com")
    }

    /// An answer from POST /v1/customer-imports: one row per entry, numbered from 1, with the summary counted from them.
    private func importReply(dryRun: Bool, _ rows: [(status: String, extra: String)]) -> URLProtocolFixture.Reply {
        let body = rows.enumerated().map { index, row in
            #"{"row":\#(index + 1),"status":"\#(row.status)","name":"Person \#(index)"\#(row.extra)}"#
        }.joined(separator: ",")
        func tally(_ status: String) -> Int { rows.filter { $0.status == status }.count }
        return .init(200, #"{"dryRun":\#(dryRun),"summary":{"new":\#(tally("new")),"duplicate":\#(tally("duplicate")),"invalid":\#(tally("invalid"))},"rows":[\#(body)]}"#)
    }

    /// A mapped file of `count` named rows with a phone each (two records a row, so 100 rows fill a chunk).
    private func importModel(rows count: Int) -> CustomerImportModel {
        let model = CustomerImportModel()
        model.headers = ["Name", "Phone"]
        model.records = (0..<count).map { ["Person \($0)", "555-010-\(1000 + $0)"] }
        model.mapping = .guess(model.headers)
        return model
    }

    private func answer(_ rows: [Outcome]) -> CustomerImportResult {
        func tally(_ status: String) -> Int { rows.filter { $0.status == status }.count }
        return CustomerImportResult(dryRun: false, summary: .init(new: tally("new"), duplicate: tally("duplicate"), invalid: tally("invalid")), rows: rows)
    }

    func testAChunkWithADefiniteAnswerCountsTheServersNewTotal() {
        let preview = [Outcome(row: 1, status: "new"), Outcome(row: 2, status: "new")]
        let committed = answer([Outcome(row: 1, status: "new", customerId: "c1"),
                                Outcome(row: 2, status: "duplicate", matchedOn: "phone", existingCustomerId: "x")])
        let counted = CustomerImportModel.confirmedNew(preview: preview, answer: committed, uncertain: false, alreadyCounted: [])
        XCTAssertEqual(counted.count, 1, "Not uncertain: summary.new, whatever the preview said")
        XCTAssertEqual(counted.created, ["c1"])
    }

    func testAnUncertainChunkCountsRowsTheLostTrySaved() {
        let preview = [Outcome(row: 1, status: "new"), Outcome(row: 2, status: "new"), Outcome(row: 3, status: "new")]
        let resent = answer([Outcome(row: 1, status: "duplicate", matchedOn: "phone", existingCustomerId: "a"),
                             Outcome(row: 2, status: "duplicate", matchedOn: "email", existingCustomerId: "b"),
                             Outcome(row: 3, status: "duplicate", matchedOn: "phone", existingCustomerId: "c")])
        let counted = CustomerImportModel.confirmedNew(preview: preview, answer: resent, uncertain: true, alreadyCounted: [])
        XCTAssertEqual(counted.count, 3)
        XCTAssertEqual(counted.created, ["a", "b", "c"])
    }

    func testTwoRowsPointingAtOneCustomerAreCountedOnce() {
        let preview = [Outcome(row: 1, status: "new"), Outcome(row: 2, status: "new")]
        let resent = answer([Outcome(row: 1, status: "duplicate", matchedOn: "phone", existingCustomerId: "same"),
                             Outcome(row: 2, status: "duplicate", matchedOn: "email", existingCustomerId: "same")])
        let counted = CustomerImportModel.confirmedNew(preview: preview, answer: resent, uncertain: true, alreadyCounted: [])
        XCTAssertEqual(counted.count, 1)
        XCTAssertEqual(counted.created, ["same"])
    }

    func testACustomerAnEarlierChunkCreatedIsNotCountedAgain() {
        // The row repeats a contact from chunk 1: it previewed as new (every chunk is previewed
        // before any is saved) but points at the customer chunk 1 already counted.
        let preview = [Outcome(row: 1, status: "new"), Outcome(row: 2, status: "new")]
        let resent = answer([Outcome(row: 1, status: "duplicate", matchedOn: "phone", existingCustomerId: "fromChunk1"),
                             Outcome(row: 2, status: "duplicate", matchedOn: "phone", existingCustomerId: "lost")])
        let counted = CustomerImportModel.confirmedNew(preview: preview, answer: resent, uncertain: true, alreadyCounted: ["fromChunk1"])
        XCTAssertEqual(counted.count, 1)
        XCTAssertEqual(counted.created, ["lost"])
    }

    func testAnUncertainChunkThatHadNotLandedCountsItsNewRows() {
        let preview = [Outcome(row: 1, status: "new"), Outcome(row: 2, status: "new")]
        let committed = answer([Outcome(row: 1, status: "new", customerId: "c1"), Outcome(row: 2, status: "new", customerId: "c2")])
        let counted = CustomerImportModel.confirmedNew(preview: preview, answer: committed, uncertain: true, alreadyCounted: [])
        XCTAssertEqual(counted.count, 2)
        XCTAssertEqual(counted.created, ["c1", "c2"])
    }

    func testRowsThePreviewCalledDuplicateOrInvalidAreNeverCounted() {
        let preview = [Outcome(row: 1, status: "duplicate", matchedOn: "phone", existingCustomerId: "old"),
                       Outcome(row: 2, status: "invalid", reasons: ["phones.0: needs at least 7 digits"]),
                       Outcome(row: 3, status: "duplicate", matchedOn: "email", duplicateOfRow: 1)]
        let resent = answer([Outcome(row: 1, status: "duplicate", matchedOn: "phone", existingCustomerId: "old"),
                             Outcome(row: 2, status: "invalid", reasons: ["phones.0: needs at least 7 digits"]),
                             Outcome(row: 3, status: "duplicate", matchedOn: "email", existingCustomerId: "old2")])
        let counted = CustomerImportModel.confirmedNew(preview: preview, answer: resent, uncertain: true, alreadyCounted: [])
        XCTAssertEqual(counted.count, 0)
        XCTAssertEqual(counted.created, [])
    }

    func testOnlyAnAnswerThatMayHaveLandedMakesAChunkUncertain() {
        XCTAssertTrue(CustomerImportModel.answerWasLost(Problem(title: "Network error", status: nil, detail: "timed out")))
        XCTAssertTrue(CustomerImportModel.answerWasLost(CancellationError()), "Cancel while the request is out")
        XCTAssertTrue(CustomerImportModel.answerWasLost(Problem(title: "Unavailable", status: 503, detail: nil)))
        XCTAssertTrue(CustomerImportModel.answerWasLost(Problem(title: "Timeout", status: 408, detail: nil)))
        XCTAssertTrue(CustomerImportModel.answerWasLost(Problem(title: "Slow down", status: 429, detail: nil)))
        XCTAssertTrue(CustomerImportModel.answerWasLost(Problem(title: "Invalid API response", status: 200, detail: nil)), "Saved, answer unreadable")
        XCTAssertFalse(CustomerImportModel.answerWasLost(Problem(title: "Network error", status: nil, detail: "offline", neverSent: true)))
        XCTAssertFalse(CustomerImportModel.answerWasLost(Problem(title: "Forbidden", status: 403, detail: nil, category: "authorization")))
        XCTAssertFalse(CustomerImportModel.answerWasLost(Problem(title: "Invalid", status: 400, detail: nil, category: "validation")))
    }

    func testATimedOutChunkSentAgainCountsTheCustomersOfBothChunks() async {
        let model = importModel(rows: 102)
        XCTAssertEqual(CustomerImportRow.chunks(model.rows).map(\.count), [100, 2])
        let api = importAPI([
            importReply(dryRun: true, (0..<100).map { _ in (status: "new", extra: #","warnings":[]"#) }),
            importReply(dryRun: true, [(status: "new", extra: #","warnings":[]"#), (status: "new", extra: #","warnings":[]"#)]),
            importReply(dryRun: false, (0..<100).map { (status: "new", extra: #","customerId":"c\#($0)","warnings":[]"#) }),
            URLProtocolFixture.timedOut,
            // The lost try saved both rows: sent again, they match the customers it made.
            importReply(dryRun: false, [(status: "duplicate", extra: #","matchedOn":"phone","existingCustomerId":"lost1""#),
                                        (status: "duplicate", extra: #","matchedOn":"phone","existingCustomerId":"lost2""#)]),
        ])

        await model.check(api: api)
        XCTAssertEqual(model.phase, .preview)
        XCTAssertEqual(model.preview?.new, 102)
        XCTAssertEqual(model.commitTitle, "Import 102 customers")

        let first = await model.commit(api: api)
        XCTAssertFalse(first)
        XCTAssertEqual(model.phase, .preview)
        XCTAssertEqual(model.imported, 100)
        XCTAssertEqual(model.committedChunks, 1)
        XCTAssertEqual(model.uncertainChunk, 1)
        XCTAssertEqual(model.error, "The last save could not be confirmed. 100 customers are confirmed so far. Try again to finish; nobody already added is added twice.")
        XCTAssertEqual(model.commitTitle, "Import the rest")

        let again = await model.commit(api: api)
        XCTAssertTrue(again)
        XCTAssertEqual(model.phase, .done)
        XCTAssertEqual(model.imported, 102)
        XCTAssertNil(model.uncertainChunk)
        XCTAssertNil(model.error)
        XCTAssertEqual(model.createdCustomerIDs.count, 102)
        XCTAssertEqual(URLProtocolFixture.recorded.count, 5, "Only the chunk without an answer is sent again")
    }

    func testADefiniteRefusalIsNotUncertainAndItsRetryCountsTheServersNewTotal() async {
        let model = importModel(rows: 2)
        let api = importAPI([
            importReply(dryRun: true, [(status: "new", extra: ""), (status: "new", extra: "")]),
            .init(400, #"{"title":"Invalid request","status":400,"detail":"rows: try again","category":"validation"}"#),
            importReply(dryRun: false, [(status: "new", extra: #","customerId":"c1","warnings":[]"#),
                                        (status: "duplicate", extra: #","matchedOn":"phone","existingCustomerId":"elsewhere""#)]),
        ])
        await model.check(api: api)

        let first = await model.commit(api: api)
        XCTAssertFalse(first)
        XCTAssertNil(model.uncertainChunk, "A 4xx is a definite answer: nothing was saved")
        XCTAssertEqual(model.error, "Imported 0 before an error: rows: try again Try again to import the rest.")

        let again = await model.commit(api: api)
        XCTAssertTrue(again)
        XCTAssertEqual(model.imported, 1, "summary.new only; the duplicate was someone else's customer")
    }

    func testARequestThatNeverLeftIsNotUncertain() async {
        let model = importModel(rows: 1)
        let api = importAPI([importReply(dryRun: true, [(status: "new", extra: "")]), URLProtocolFixture.offline])
        await model.check(api: api)
        let committed = await model.commit(api: api)
        XCTAssertFalse(committed)
        XCTAssertNil(model.uncertainChunk)
        XCTAssertTrue(model.error?.hasPrefix("Imported 0 before an error: ") == true)
    }

    func testARetryThatFailsAfterALostAnswerNeverSaysNothingWasSaved() async {
        let model = importModel(rows: 1)
        let api = importAPI([importReply(dryRun: true, [(status: "new", extra: "")]),
                             URLProtocolFixture.timedOut,
                             URLProtocolFixture.offline,
                             .init(400, #"{"title":"Invalid request","status":400,"detail":"rows: try again","category":"validation"}"#)])
        await model.check(api: api)

        let first = await model.commit(api: api)
        XCTAssertFalse(first)
        XCTAssertEqual(model.uncertainChunk, 0)
        XCTAssertEqual(model.commitTitle, "Import the rest", "The lost try may have saved the chunk")

        // Still without signal: the retry never leaves, but the first try may have landed whole.
        let second = await model.commit(api: api)
        XCTAssertFalse(second)
        XCTAssertEqual(model.uncertainChunk, 0)
        XCTAssertFalse(model.error?.hasPrefix("Imported 0 before an error") ?? true)
        XCTAssertEqual(model.error, "This needs a connection. Try again when you have signal. 0 customers are confirmed so far. Try again to finish; nobody already added is added twice.")

        // A definite refusal on the retry does not settle the earlier lost try either.
        let third = await model.commit(api: api)
        XCTAssertFalse(third)
        XCTAssertEqual(model.uncertainChunk, 0)
        XCTAssertEqual(model.error, "rows: try again 0 customers are confirmed so far. Try again to finish; nobody already added is added twice.")
    }

    func testOutcomesDecodeWithAndWithoutTheirOptionalFields() throws {
        let json = #"""
        {"dryRun":false,"summary":{"new":1,"duplicate":2,"invalid":1},"rows":[
          {"row":1,"status":"new","name":"No Site","customerId":"c1","warnings":["notes were not imported: they are kept on a service address and this row has none"]},
          {"row":2,"status":"duplicate","name":"Same Line","matchedOn":"phone","existingCustomerId":"e1"},
          {"row":3,"status":"duplicate","name":"Dana Again","matchedOn":"email","duplicateOfRow":1},
          {"row":4,"status":"invalid","reasons":["phones.0: needs at least 7 digits"]}
        ]}
        """#
        let result = try JSONDecoder().decode(CustomerImportResult.self, from: Data(json.utf8))
        XCTAssertEqual(result.rows[0], Outcome(row: 1, status: "new", name: "No Site", warnings: [Self.notesWarning], customerId: "c1"))
        XCTAssertEqual(result.rows[1], Outcome(row: 2, status: "duplicate", name: "Same Line", matchedOn: "phone", existingCustomerId: "e1"))
        XCTAssertEqual(result.rows[2], Outcome(row: 3, status: "duplicate", name: "Dana Again", matchedOn: "email", duplicateOfRow: 1))
        XCTAssertEqual(result.rows[3], Outcome(row: 4, status: "invalid", reasons: ["phones.0: needs at least 7 digits"]))

        let bare = try JSONDecoder().decode(CustomerImportResult.self, from: Data(#"{"dryRun":true,"summary":{"new":1,"duplicate":0,"invalid":0},"rows":[{"row":1,"status":"new"}]}"#.utf8))
        XCTAssertEqual(bare.rows, [Outcome(row: 1, status: "new")])
        XCTAssertNil(bare.rows[0].warnings)
        XCTAssertNil(bare.rows[0].customerId)
    }

    func testThePreviewListsTheFirstFiveRowWarningsOnTheirSpreadsheetLines() async {
        let model = CustomerImportModel()
        model.headers = ["Name", "Phone", "Notes"]
        // Line 1 is the header; the blank line 3 still counts toward the line numbers.
        var records: [[String]] = [["A", "555-010-1000", "Gate"], ["", "", ""], ["B", "555-010-1001", ""]]
        for index in 0..<5 { records.append(["P\(index)", "555-010-20\(index)0", "Dog"]) }
        model.records = records
        model.mapping = .guess(model.headers)
        XCTAssertEqual(model.prepared.lines, [2, 4, 5, 6, 7, 8, 9])
        let warned = #","warnings":["\#(Self.notesWarning)"]"#
        var answered: [(status: String, extra: String)] = [(status: "new", extra: warned), (status: "new", extra: #","warnings":[]"#)]
        for _ in 0..<5 { answered.append((status: "new", extra: warned)) }
        let api = importAPI([importReply(dryRun: true, answered)])

        await model.check(api: api)

        XCTAssertEqual(model.phase, .preview)
        XCTAssertEqual(model.warningCount, 6)
        XCTAssertEqual(model.warnings, [2, 5, 6, 7, 8].map { "Row \($0): \(Self.notesWarning)" })
        XCTAssertEqual(model.previewOutcomes[0]?.count, 7)
        model.reset()
        XCTAssertEqual(model.warnings, [])
        XCTAssertEqual(model.warningCount, 0)
        XCTAssertTrue(model.previewOutcomes.isEmpty)
    }

    func testOnlyARoleRefusalReadsAsOne() {
        let role = "Your role can\u{2019}t import customers."
        XCTAssertEqual(CustomerImportModel.message(for: Problem(title: "Forbidden", status: 403, detail: "missing customer.view", category: "authorization")), role)
        XCTAssertEqual(CustomerImportModel.message(for: Problem(title: "Forbidden", status: 403, detail: "missing customer.view")), role, "An older server sends no category")
        XCTAssertEqual(CustomerImportModel.message(for: Problem(title: "Feature unavailable", status: 403, detail: "Customers are not on for this company.", category: "feature_unavailable")),
                       "Customers are not on for this company.")
        XCTAssertEqual(CustomerImportModel.message(for: Problem(title: "Server error", status: 500, detail: "Something went wrong.")), "Something went wrong.")
    }

    func testARoleRefusalBeforeAnythingIsImportedSaysOnlyThat() async {
        let model = importModel(rows: 1)
        let api = importAPI([importReply(dryRun: true, [(status: "new", extra: "")]),
                             .init(403, #"{"title":"Forbidden","status":403,"detail":"missing customer.view","category":"authorization"}"#)])
        await model.check(api: api)
        _ = await model.commit(api: api)
        XCTAssertEqual(model.error, "Your role can\u{2019}t import customers.")
        XCTAssertNil(model.uncertainChunk)
    }

    func testImportIsOfferedOnlyWithCreateEditAndView() {
        func offered(_ granted: Set<String>) -> Bool { CustomerImportModel.permitted { granted.contains($0) } }
        XCTAssertTrue(offered(["customer.create", "customer.edit", "customer.view"]))
        XCTAssertFalse(offered(["customer.create", "customer.edit"]), "The route also needs customer.view")
        XCTAssertFalse(offered(["customer.create", "customer.view"]))
        XCTAssertFalse(offered(["customer.edit", "customer.view"]))
        XCTAssertFalse(offered([]))
    }

    func testTradesRoundTripInListOrder() {
        let picked = SetupTrades.parse("Plumbing, Solar, HVAC")
        XCTAssertEqual(picked, ["Plumbing", "Solar", "HVAC"])
        XCTAssertEqual(SetupTrades.join(picked), "HVAC, Plumbing, Solar")
        XCTAssertEqual(SetupTrades.parse(nil), [])
    }

    func testFormationDateKeepsTheCalendarDay() throws {
        let date = try XCTUnwrap(SetupDates.parse("2019-03-04"))
        XCTAssertEqual(SetupDates.format(date), "2019-03-04")
        XCTAssertNil(SetupDates.parse("March 2019"))
    }

    func testResumeIsRememberedPerCompany() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "setup-wizard-tests"))
        defaults.removePersistentDomain(forName: "setup-wizard-tests")
        SetupProgress.save(.services, organizationID: "org_a", defaults: defaults)
        XCTAssertEqual(SetupProgress.load("org_a", defaults: defaults), .services)
        XCTAssertNil(SetupProgress.load("org_b", defaults: defaults))
        XCTAssertNil(SetupProgress.load(nil, defaults: defaults))
        SetupProgress.saveSkipped([.team, .payments], organizationID: "org_a", defaults: defaults)
        XCTAssertEqual(SetupProgress.skipped("org_a", defaults: defaults), [.team, .payments])
        XCTAssertEqual(SetupProgress.skipped("org_b", defaults: defaults), [])
    }

    func testOnlyTheCompanyStepHasRequiredFacts() {
        XCTAssertEqual(SetupStep.company.required, ["legal_name", "primary_phone", "business_address"])
        XCTAssertTrue(SetupStep.allCases.filter { $0 != .company }.allSatisfy { $0.required.isEmpty })
        let all = Set(SetupStep.allCases.flatMap(\.facts))
        XCTAssertTrue(all.isSuperset(of: ["legal_name", "business_address", "primary_phone", "industry", "entity_type", "email_sender_address"]))
    }
}

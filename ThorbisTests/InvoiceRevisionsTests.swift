import XCTest
@testable import Thorbis

@MainActor
final class InvoiceRevisionsTests: XCTestCase {
    private let jobID = "00000000-0000-4000-8000-000000000007"
    private let estimateID = "00000000-0000-4000-8000-000000000008"
    private let invoiceID = "00000000-0000-4000-8000-00000000000a"
    private let customerID = "00000000-0000-4000-8000-000000000003"

    private func jobJSON(status: String, completedAt: String?) -> String {
        let completed = completedAt.map { #","completedAt":"\#($0)""# } ?? ""
        return #"{"id":"\#(jobID)","organizationId":"00000000-0000-4000-8000-000000000002","customerId":"\#(customerID)","title":"AC not cooling","status":"\#(status)","createdAt":"2026-11-18T12:00:00Z","updatedAt":"2026-11-20T12:00:00Z"\#(completed)}"#
    }

    private func invoiceJSON(status: String = "issued", linesRevision: Int = 3, lines: String = "[]", extra: String = "") -> String {
        #"{"id":"\#(invoiceID)","organizationId":"00000000-0000-4000-8000-000000000002","customerId":"\#(customerID)","jobId":"\#(jobID)","createdByUserId":"00000000-0000-4000-8000-000000000004","origin":"job_completion","sourceOperationKey":"completion:test","status":"\#(status)","lines":\#(lines),"linesRevision":\#(linesRevision),"amountPaid":0,"currency":"USD","createdAt":"2026-10-26T12:00:00Z","updatedAt":"2026-10-26T12:00:00Z"\#(extra)}"#
    }

    private func invoice(status: String = "issued", linesRevision: Int = 3, lines: String = "[]", extra: String = "",
                         change: ([String: Any]) -> [String: Any] = { $0 }) throws -> InvoiceRecord {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(invoiceJSON(status: status, linesRevision: linesRevision, lines: lines, extra: extra).utf8)) as? [String: Any])
        return try JSONDecoder().decode(InvoiceRecord.self, from: JSONSerialization.data(withJSONObject: change(object)))
    }

    private func estimate(status: String = "approved", id: String? = nil, customer: String? = nil) throws -> EstimateRecord {
        let json = #"{"id":"\#(id ?? estimateID)","organizationId":"00000000-0000-4000-8000-000000000002","customerId":"\#(customer ?? customerID)","createdByUserId":"00000000-0000-4000-8000-000000000004","status":"\#(status)","currentRevisionNumber":1,"title":"Water heater add-ons","lines":[],"createdAt":"2026-10-26T12:00:00Z","updatedAt":"2026-10-26T12:00:00Z"}"#
        return try JSONDecoder().decode(EstimateRecord.self, from: Data(json.utf8))
    }

    private func problem(_ status: Int, code: String? = nil, category: String? = nil, detail: String = "The server's words") -> Problem {
        Problem(title: "Refused", status: status, detail: detail, code: code, category: category)
    }

    private func problemJSON(_ status: Int, code: String? = nil, category: String? = nil) -> String {
        var object: [String: Any] = ["title": "Refused", "status": status, "detail": "The server's words"]
        if let code { object["code"] = code }
        if let category { object["category"] = category }
        return String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    private func revision(_ number: Int, kind: String = "lines_edited", billed: [String] = [], signed: Bool = false,
                          before: Int? = nil, total: Int = 34_000, at: String = "2026-11-20T19:14:00Z") -> InvoiceRevisionRecord {
        InvoiceRevisionRecord(
            id: "rev-\(number)", linesRevision: number, kind: kind,
            billedEstimates: billed.map { .init(estimateId: $0, estimateRevisionNumber: 1) },
            previousTotal: before.map { FieldMoney(amount: $0, currency: "USD") }, total: FieldMoney(amount: total, currency: "USD"),
            revisedAt: at, authorization: signed ? .init(id: "auth", signerName: "Dana", signedAt: at) : nil)
    }

    private func history(_ items: [InvoiceRevisionRecord], current: Int = 3, signed: Bool = false) -> InvoiceRevisionHistory {
        InvoiceRevisionHistory(invoiceId: invoiceID, currentLinesRevision: current, currentRevisionSigned: signed, items: items)
    }

    // MARK: Reopen

    func testReopenSendsExactlyTheCompletionTimeAndTheReason() async throws {
        let client = APIClient(session: URLProtocolFixture.session([.init(200, jobJSON(status: "in_progress", completedAt: nil))]),
                               baseURL: "https://app.thorbis.com")
        let request = try XCTUnwrap(JobReopen.request(completedAt: "2026-11-20T15:40:00.123Z", reason: "  Customer called back \n"))

        let job = try await client.reopenFieldJob(jobID, request: request)

        XCTAssertEqual(job.status, "in_progress")
        XCTAssertNil(job.completedAt)
        let sent = try XCTUnwrap(URLProtocolFixture.recorded.first)
        XCTAssertEqual(sent.method, "POST")
        XCTAssertEqual(sent.url?.path, "/v1/jobs/\(jobID)/reopen")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(sent.body)) as? [String: String])
        XCTAssertEqual(body, ["expectedCompletedAt": "2026-11-20T15:40:00.123Z", "reason": "Customer called back"])
    }

    func testReopenLeavesTheReasonOutWhenNoneWasTyped() throws {
        let request = try XCTUnwrap(JobReopen.request(completedAt: "2026-11-20T15:40:00Z", reason: "   "))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: String])
        XCTAssertEqual(body, ["expectedCompletedAt": "2026-11-20T15:40:00Z"])
    }

    func testReopenRefusesAMissingCompletionTimeAndAnOverlongReason() {
        XCTAssertNil(JobReopen.request(completedAt: nil, reason: "x"))
        XCTAssertNil(JobReopen.request(completedAt: "", reason: "x"))
        XCTAssertNotNil(JobReopen.request(completedAt: "t", reason: String(repeating: "a", count: 2_000)))
        XCTAssertNil(JobReopen.request(completedAt: "t", reason: String(repeating: "a", count: 2_001)))
    }

    func testReopenRejectsAnInvalidJobIDBeforeSending() async {
        let client = APIClient(session: URLProtocolFixture.session([]), baseURL: "https://app.thorbis.com")
        do {
            _ = try await client.reopenFieldJob("nope", request: .init(expectedCompletedAt: "t", reason: nil))
            XCTFail("Expected a refusal")
        } catch {}
        XCTAssertTrue(URLProtocolFixture.recorded.isEmpty)
    }

    func testReopenShowsOnlyOnACompletedJobWithTheFlagAndCompletePermission() {
        func offer(status: String = "completed", completedAt: String? = "t", flag: Bool = true, can: Bool = true,
                   pending: Bool = false, off: Bool = false) -> Bool {
            JobReopen.canOffer(status: status, completedAt: completedAt, flagOn: flag, canComplete: can,
                               hasPendingChange: pending, serverSaysOff: off)
        }
        XCTAssertTrue(offer())
        XCTAssertFalse(offer(flag: false), "Hidden while the server flag is off")
        XCTAssertFalse(offer(can: false))
        XCTAssertFalse(offer(status: "in_progress"))
        XCTAssertFalse(offer(status: "canceled"))
        XCTAssertFalse(offer(completedAt: nil))
        XCTAssertFalse(offer(pending: true))
        XCTAssertFalse(offer(off: true), "Hidden once the server answered feature_unavailable")
    }

    func testReopenFailuresReadInPlainWords() {
        XCTAssertEqual(JobReopenFailure.of(problem(403, category: "feature_unavailable")), .unavailable)
        XCTAssertEqual(JobReopenFailure.of(problem(403, category: "authorization")), .notAllowed)
        XCTAssertEqual(JobReopenFailure.notAllowed.message, "You can\u{2019}t reopen this job. Ask the office.")
        XCTAssertEqual(JobReopenFailure.of(problem(404)), .notFound)
        XCTAssertEqual(JobReopenFailure.of(problem(409, code: "job_canceled")), .canceled)
        XCTAssertEqual(JobReopenFailure.of(problem(409, code: "job_completion_changed")), .changed)
        XCTAssertEqual(JobReopenFailure.of(problem(400, category: "validation")), .invalid)
        XCTAssertEqual(JobReopenFailure.of(problem(500)), .other("The server's words"))
        XCTAssertTrue(JobReopenFailure.changed.reloadsJob)
        XCTAssertTrue(JobReopenFailure.canceled.reloadsJob)
        XCTAssertFalse(JobReopenFailure.notAllowed.reloadsJob)
        XCTAssertFalse(JobReopenFailure.unavailable.reloadsJob)
    }

    func testTheServersCategoryAndCodeReachTheApp() async {
        let client = APIClient(session: URLProtocolFixture.session([.init(403, problemJSON(403, category: "feature_unavailable"))]),
                               baseURL: "https://app.thorbis.com")
        do {
            _ = try await client.reopenFieldJob(jobID, request: .init(expectedCompletedAt: "t", reason: nil))
            XCTFail("Expected a refusal")
        } catch {
            XCTAssertEqual((error as? Problem)?.category, "feature_unavailable")
            XCTAssertEqual(JobReopenFailure.of(error), .unavailable)
        }
    }

    // MARK: Add an approved estimate

    func testAddApprovedEstimateSendsOnlyTheEstimateAndTheRevision() async throws {
        let client = APIClient(session: URLProtocolFixture.session([.init(200, invoiceJSON(linesRevision: 4))]),
                               baseURL: "https://app.thorbis.com")

        let updated = try await client.addApprovedEstimate(toInvoice: invoiceID, request: .init(estimateId: estimateID, expectedLinesRevision: 3))

        XCTAssertEqual(updated.linesRevision, 4)
        let sent = try XCTUnwrap(URLProtocolFixture.recorded.first)
        XCTAssertEqual(sent.method, "POST")
        XCTAssertEqual(sent.url?.path, "/v1/invoices/\(invoiceID)/approved-estimates")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(sent.body)) as? [String: Any])
        XCTAssertEqual(Set(body.keys), ["estimateId", "expectedLinesRevision"])
        XCTAssertEqual(body["estimateId"] as? String, estimateID)
        XCTAssertEqual(body["expectedLinesRevision"] as? Int, 3)
    }

    func testAStaleInvoiceIsReadAgainAndTriedOnceMore() async throws {
        let client = APIClient(session: URLProtocolFixture.session([
            .init(409, problemJSON(409, code: "invoice_lines_revision_stale")),
            .init(200, invoiceJSON(linesRevision: 5)),
            .init(200, invoiceJSON(linesRevision: 6)),
        ]), baseURL: "https://app.thorbis.com")
        let adder = EstimateInvoiceAdder()

        let updated = await adder.add(.init(estimate: try estimate(), invoice: try invoice(linesRevision: 3)), api: client)

        XCTAssertEqual(updated?.linesRevision, 6)
        XCTAssertNil(adder.failure)
        let posts = URLProtocolFixture.recorded.filter { $0.method == "POST" }
        XCTAssertEqual(posts.count, 2)
        let retry = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(posts.last?.body)) as? [String: Any])
        XCTAssertEqual(retry["expectedLinesRevision"] as? Int, 5, "The retry carries the revision just read")
        XCTAssertEqual(adder.billed(on: try invoice()), [estimateID])
    }

    func testASecondStaleAnswerSaysTheInvoiceChangedAndStops() async throws {
        let client = APIClient(session: URLProtocolFixture.session([
            .init(409, problemJSON(409, code: "invoice_lines_revision_stale")),
            .init(200, invoiceJSON(linesRevision: 5)),
            .init(409, problemJSON(409, code: "invoice_lines_revision_stale")),
        ]), baseURL: "https://app.thorbis.com")
        let adder = EstimateInvoiceAdder()

        let updated = await adder.add(.init(estimate: try estimate(), invoice: try invoice()), api: client)

        XCTAssertNil(updated)
        XCTAssertEqual(adder.failure, "This invoice changed. Check it and try again.")
        XCTAssertEqual(URLProtocolFixture.recorded.filter { $0.method == "POST" }.count, 2)
    }

    func testAlreadyBilledIsRememberedAndFeatureOffHidesTheAction() async throws {
        let billedClient = APIClient(session: URLProtocolFixture.session([.init(409, problemJSON(409, code: "estimate_already_billed"))]),
                                     baseURL: "https://app.thorbis.com")
        let adder = EstimateInvoiceAdder()
        let none = await adder.add(.init(estimate: try estimate(), invoice: try invoice()), api: billedClient)
        XCTAssertNil(none)
        XCTAssertEqual(adder.failure, "This estimate is already on the invoice.")
        XCTAssertEqual(adder.billed(on: try invoice()), [estimateID])
        XCTAssertFalse(adder.serverSaysOff)

        let offClient = APIClient(session: URLProtocolFixture.session([.init(403, problemJSON(403, category: "feature_unavailable"))]),
                                  baseURL: "https://app.thorbis.com")
        let off = EstimateInvoiceAdder()
        _ = await off.add(.init(estimate: try estimate(), invoice: try invoice()), api: offClient)
        XCTAssertTrue(off.serverSaysOff)
        XCTAssertFalse(InvoiceEstimateBilling.canOffer(estimate: try estimate(), invoice: try invoice(), billed: nil,
                                                       flagOn: true, canEditInvoice: true, serverSaysOff: off.serverSaysOff))
    }

    func testEveryNamedRefusalHasPlainWords() {
        let words: [String: String] = [
            "invoice_lines_revision_stale": "This invoice changed. Check it and try again.",
            "estimate_already_billed": "This estimate is already on the invoice.",
            "estimate_not_approved_for_job": "Only an approved estimate for this job can be added.",
            "invoice_total_below_paid": "That would make the invoice less than what\u{2019}s been paid.",
            "invoice_collection_in_progress": "A card payment is in progress. Finish or cancel it, then try again.",
            "invoice_financing_in_progress": "Financing is in progress on this invoice.",
            "invoice_billing_history_unknown": "Add these lines by hand; this older invoice can\u{2019}t take an estimate.",
            "invoice_revision_price_book_attachment_unsupported":
                "Add this as a typed line; price book items can\u{2019}t be added to an issued invoice yet.",
        ]
        for (code, expected) in words {
            XCTAssertEqual(InvoiceRevisionWords.message(code: code), expected, code)
        }
        for code in ["job_canceled", "invoice_not_revisable", "invoice_not_job_invoice", "invoice_line_limit",
                     "invoice_total_negative", "estimate_not_reconciled", "invoice_revisions_unavailable"] {
            let message = InvoiceRevisionWords.message(code: code)
            XCTAssertNotNil(message, code)
            XCTAssertFalse(message?.contains("_") == true, "\(code) must not show a code")
        }
        XCTAssertNil(InvoiceRevisionWords.message(code: "something_new"))
        XCTAssertNil(InvoiceRevisionWords.message(code: nil))
    }

    func testAddFailuresMapFromTheServersAnswer() {
        XCTAssertEqual(InvoiceEstimateAddFailure.of(problem(409, code: "invoice_lines_revision_stale")), .stale)
        XCTAssertEqual(InvoiceEstimateAddFailure.of(problem(409, code: "estimate_already_billed")), .alreadyBilled)
        XCTAssertEqual(InvoiceEstimateAddFailure.of(problem(403, category: "feature_unavailable")), .unavailable)
        XCTAssertEqual(InvoiceEstimateAddFailure.of(problem(403, category: "authorization")), .notAllowed)
        for code in ["estimate_not_approved_for_job", "invoice_total_below_paid", "invoice_collection_in_progress",
                     "invoice_financing_in_progress", "invoice_billing_history_unknown", "job_canceled", "invoice_not_revisable",
                     "invoice_not_job_invoice", "invoice_line_limit", "invoice_total_negative", "estimate_not_reconciled"] {
            XCTAssertEqual(InvoiceEstimateAddFailure.of(problem(409, code: code)),
                           .message(InvoiceRevisionWords.message(code: code) ?? ""), code)
        }
        XCTAssertEqual(InvoiceEstimateAddFailure.of(problem(409, code: "unknown_code")), .message("The server's words"))
        XCTAssertEqual(InvoiceEstimateAddFailure.of(problem(500)), .message("The server's words"))
    }

    func testTheOfferNeedsTheFlagAnApprovedEstimateAndALiveInvoice() throws {
        func offer(_ estimate: EstimateRecord, _ invoice: InvoiceRecord?, billed: Set<String>? = [], flag: Bool = true, edit: Bool = true) -> Bool {
            InvoiceEstimateBilling.canOffer(estimate: estimate, invoice: invoice, billed: billed, flagOn: flag, canEditInvoice: edit)
        }
        XCTAssertTrue(offer(try estimate(), try invoice()))
        XCTAssertTrue(offer(try estimate(), try invoice(status: "paid")), "Any status except void")
        XCTAssertTrue(offer(try estimate(), try invoice(status: "draft")))
        XCTAssertFalse(offer(try estimate(), try invoice(), flag: false), "Hidden while the server flag is off")
        XCTAssertFalse(offer(try estimate(), try invoice(), edit: false))
        XCTAssertFalse(offer(try estimate(), nil), "No invoice on the job")
        XCTAssertFalse(offer(try estimate(), try invoice(status: "void")))
        XCTAssertFalse(offer(try estimate(status: "sent"), try invoice()))
        XCTAssertFalse(offer(try estimate(customer: "00000000-0000-4000-8000-0000000000ff"), try invoice()))
        XCTAssertFalse(offer(try estimate(), try invoice(), billed: [estimateID]))
        XCTAssertTrue(offer(try estimate(), try invoice(), billed: nil), "Versions unread: still offered, the server decides")
    }

    func testAlreadyBilledComesFromTheVersionsThenTheInvoiceItself() throws {
        let read = history([revision(1, kind: "created"), revision(2, kind: "estimate_added", billed: [estimateID]), revision(3)])
        XCTAssertEqual(InvoiceEstimateBilling.billedEstimateIDs(read), [estimateID])
        XCTAssertTrue(InvoiceEstimateBilling.isBilled(estimateID: estimateID, invoice: try invoice(), billed: InvoiceEstimateBilling.billedEstimateIDs(read)))
        XCTAssertFalse(InvoiceEstimateBilling.isBilled(estimateID: estimateID, invoice: try invoice(), billed: []))
        XCTAssertFalse(InvoiceEstimateBilling.isBilled(estimateID: estimateID, invoice: try invoice(), billed: nil))
        let sourced = try invoice { var object = $0; object["sourceEstimateId"] = self.estimateID; return object }
        XCTAssertTrue(InvoiceEstimateBilling.isBilled(estimateID: estimateID, invoice: sourced, billed: nil))
        let line = #"[{"id":"00000000-0000-4000-8000-00000000000b","description":"Tank","quantity":1,"unitPrice":{"amount":100,"currency":"USD"},"source":{"kind":"estimate","estimateId":"\#(estimateID)","estimateLineId":"00000000-0000-4000-8000-00000000000c"}}]"#
        XCTAssertTrue(InvoiceEstimateBilling.isBilled(estimateID: estimateID, invoice: try invoice(lines: line), billed: nil))
    }

    func testTheJobsInvoiceIsItsCompletionInvoiceNeverADepositOrAVoid() throws {
        let completion = try invoice()
        let deposit = try invoice { var object = $0; object["id"] = "00000000-0000-4000-8000-0000000000d1"; object["origin"] = "estimate_deposit"; return object }
        let voided = try invoice(status: "void") { var object = $0; object["id"] = "00000000-0000-4000-8000-0000000000d2"; return object }
        let other = try invoice { var object = $0; object["id"] = "00000000-0000-4000-8000-0000000000d3"; object["jobId"] = "00000000-0000-4000-8000-0000000000ee"; return object }
        XCTAssertEqual(InvoiceEstimateBilling.jobInvoice([deposit, voided, other, completion], jobID: jobID)?.id, completion.id)
        XCTAssertNil(InvoiceEstimateBilling.jobInvoice([deposit, voided, other], jobID: jobID))
    }

    func testAnApprovalSeenWhileTheJobIsOpenIsOfferedOnce() {
        var watcher = EstimateApprovalWatcher()
        XCTAssertEqual(watcher.observe([(id: "a", status: "sent"), (id: "b", status: "approved")]), [],
                       "An estimate first seen approved is not offered")
        XCTAssertEqual(watcher.observe([]), [], "A reload that briefly lists nothing forgets nothing")
        XCTAssertEqual(watcher.observe([(id: "a", status: "approved"), (id: "b", status: "approved")]), ["a"])
        XCTAssertEqual(watcher.observe([(id: "a", status: "approved")]), [], "Offered once")
        XCTAssertEqual(watcher.observe([(id: "a", status: "sent")]), [])
        XCTAssertEqual(watcher.observe([(id: "a", status: "approved")]), [], "Never a second offer for the same estimate")
    }

    func testTheOfferAsksBeforeAdding() throws {
        let asked = EstimateInvoiceOffer(estimate: try estimate(), invoice: try invoice(), afterApproval: true)
        XCTAssertEqual(asked.title, "Add this to the invoice?")
        XCTAssertEqual(EstimateInvoiceOffer(estimate: try estimate(), invoice: try invoice()).title, "Add to the invoice?")
        XCTAssertTrue(asked.message.contains("Water heater add-ons"))
    }

    // MARK: Editing an issued invoice

    func testLinesOpenForIssuedAndPaidOnlyWithTheFlag() {
        XCTAssertTrue(InvoiceRevisionWords.linesEditable(status: "draft", flagOn: false))
        XCTAssertTrue(InvoiceRevisionWords.linesEditable(status: "draft", flagOn: true))
        for status in ["issued", "paid"] {
            XCTAssertFalse(InvoiceRevisionWords.linesEditable(status: status, flagOn: false), "Today's behaviour with the flag off")
            XCTAssertTrue(InvoiceRevisionWords.linesEditable(status: status, flagOn: true))
        }
        XCTAssertFalse(InvoiceRevisionWords.linesEditable(status: "void", flagOn: true))
    }

    func testARevisableEditorSendsTheSameRequestWithTheRevisionItRead() throws {
        let line = #"[{"id":"00000000-0000-4000-8000-00000000000b","description":"Repair","quantity":2,"unitPrice":{"amount":1250,"currency":"USD"},"source":{"kind":"manual"}}]"#
        var state = InvoiceLineEditorState(invoice: try invoice(status: "issued", linesRevision: 7, lines: line), revisable: true)
        XCTAssertTrue(state.isEditable)
        state.addManualLine()
        state.lines[1].description = "Extra valve"
        state.lines[1].unitPrice = "40.00"

        let request = try state.makeRequest()

        XCTAssertEqual(request.expectedLinesRevision, 7)
        XCTAssertEqual(request.lines.map(\.description), ["Repair", "Extra valve"])
        XCTAssertEqual(request.lines[1].unitPrice, FieldMoney(amount: 4_000, currency: "USD"))

        var locked = InvoiceLineEditorState(invoice: try invoice(status: "issued", lines: line))
        XCTAssertFalse(locked.isEditable)
        locked.addManualLine()
        XCTAssertEqual(locked.lines.count, 1)
        XCTAssertThrowsError(try locked.makeRequest()) { XCTAssertEqual($0 as? InvoiceLineEditorError, .notDraft) }
        var voided = InvoiceLineEditorState(invoice: try invoice(status: "void", lines: line), revisable: true)
        XCTAssertFalse(voided.isEditable)
        XCTAssertThrowsError(try voided.removeLine(id: voided.lines[0].id)) { XCTAssertEqual($0 as? InvoiceLineEditorError, .notDraft) }
    }

    /// What a real server answered a technician who took a quantity off an issued invoice.
    func testALowerTotalRefusedForTheRoleReadsInPlainWords() {
        let refused = Problem(title: "authorization", status: 403, detail: "not permitted: invoice.discount (out_of_scope)",
                              code: nil, category: "authorization")
        XCTAssertEqual(InvoiceRevisionWords.lineEditMessage(refused), InvoiceRevisionWords.lowerTotalRefused)
        XCTAssertFalse(InvoiceRevisionWords.lineEditMessage(refused).contains("invoice.discount"))
        let other = Problem(title: "authorization", status: 403, detail: "not permitted: invoice.edit (no_grant)",
                            code: nil, category: "authorization")
        XCTAssertEqual(InvoiceRevisionWords.lineEditMessage(other), InvoiceRevisionWords.roleRefused)
        // A feature that is off keeps its own words.
        let off = Problem(title: "feature unavailable", status: 403, detail: "invoice_revisions is not released to this organization",
                          code: nil, category: "feature_unavailable")
        XCTAssertEqual(InvoiceRevisionWords.lineEditMessage(off), "invoice_revisions is not released to this organization")
    }

    func testLineEditRefusalsReadInPlainWordsAndKeepStaleHandling() {
        XCTAssertEqual(InvoiceRevisionWords.lineEditMessage(problem(409, code: "invoice_total_below_paid")),
                       "That would make the invoice less than what\u{2019}s been paid.")
        XCTAssertEqual(InvoiceRevisionWords.lineEditMessage(problem(409, code: "invoice_revision_price_book_attachment_unsupported")),
                       "Add this as a typed line; price book items can\u{2019}t be added to an issued invoice yet.")
        for code in ["invoice_total_below_paid", "invoice_collection_in_progress", "invoice_financing_in_progress",
                     "invoice_revision_price_book_attachment_unsupported", "invoice_revisions_unavailable"] {
            XCTAssertTrue(InvoiceRevisionWords.lineEditKeepsEdits(problem(409, code: code)), code)
        }
        // A stale write, and the flag-off answer, behave as they did: the server's words, and the reload offer.
        let settled = problem(409, detail: "issued paper is settled")
        XCTAssertEqual(InvoiceRevisionWords.lineEditMessage(settled), "issued paper is settled")
        XCTAssertFalse(InvoiceRevisionWords.lineEditKeepsEdits(settled))
        XCTAssertFalse(InvoiceRevisionWords.lineEditKeepsEdits(problem(409, code: "invoice_lines_revision_stale")))
        XCTAssertFalse(InvoiceRevisionWords.lineEditKeepsEdits(problem(409)))
        XCTAssertFalse(InvoiceRevisionWords.lineEditKeepsEdits(problem(500, code: "invoice_total_below_paid")))
        XCTAssertEqual(InvoiceRevisionWords.lineEditMessage(problem(400, code: "invoice_total_below_paid")), "The server's words")
    }

    // MARK: History

    func testRevisionsReadEveryPageOldestFirst() async throws {
        func page(_ items: String, next: String?) -> String {
            #"{"invoiceId":"\#(invoiceID)","currentLinesRevision":3,"currentRevisionSigned":false,"items":[\#(items)]\#(next.map { #","nextCursor":"\#($0)""# } ?? "")}"#
        }
        let created = #"{"id":"r1","linesRevision":1,"kind":"created","billedEstimates":[],"lines":[],"total":{"amount":42000,"currency":"USD"},"amountPaid":0,"invoiceStatus":"draft","revisedByUserId":"u","revisedAt":"2026-11-18T17:02:00Z"}"#
        let added = #"{"id":"r2","linesRevision":2,"kind":"estimate_added","billedEstimates":[{"estimateId":"\#(estimateID)","estimateRevisionNumber":2}],"lines":[{"id":"00000000-0000-4000-8000-00000000000b","description":"Tank","quantity":1,"unitPrice":{"amount":36000,"currency":"USD"},"source":null}],"previousTotal":{"amount":42000,"currency":"USD"},"total":{"amount":78000,"currency":"USD"},"amountPaid":0,"invoiceStatus":"issued","issuedSnapshotId":"s","revisedByUserId":"u","revisedAt":"2026-11-20T19:14:00Z","authorization":{"id":"a","signerName":"Dana","signedAt":"2026-11-20T19:20:00Z"}}"#
        let client = APIClient(session: URLProtocolFixture.session([.init(200, page(created, next: "c2")), .init(200, page(added, next: nil))]),
                               baseURL: "https://app.thorbis.com")

        let read = try await client.fieldInvoiceRevisions(invoiceID)

        XCTAssertEqual(read.items.map(\.linesRevision), [1, 2])
        XCTAssertEqual(read.currentLinesRevision, 3)
        XCTAssertFalse(read.currentRevisionSigned)
        XCTAssertEqual(read.items[1].billedEstimates, [.init(estimateId: estimateID, estimateRevisionNumber: 2)])
        XCTAssertEqual(read.items[1].authorization?.signerName, "Dana")
        XCTAssertEqual(read.items[1].lines.first?.description, "Tank")
        let requests = URLProtocolFixture.recorded
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].method, "GET")
        XCTAssertEqual(requests[0].url?.path, "/v1/invoices/\(invoiceID)/revisions")
        XCTAssertTrue(requests[1].url?.query?.contains("cursor=c2") == true)
    }

    func testEachVersionReadsAsOnePlainRow() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/Chicago"))
        let locale = Locale(identifier: "en_US")
        XCTAssertEqual(InvoiceRevisionWords.row(revision(2, kind: "estimate_added", before: 42_000, total: 78_000, at: "2026-11-20T20:14:00Z"),
                                                timeZone: zone, locale: locale),
                       "Estimate added \u{00B7} $420.00 \u{2192} $780.00 \u{00B7} Nov 20, 2:14 PM")
        XCTAssertEqual(InvoiceRevisionWords.row(revision(3, kind: "lines_edited", before: 78_000, total: 78_000, at: "2026-11-20T20:14:00Z"),
                                                timeZone: zone, locale: locale),
                       "Lines changed \u{00B7} $780.00 \u{00B7} Nov 20, 2:14 PM")
        XCTAssertEqual(InvoiceRevisionWords.row(revision(1, kind: "created", total: 42_000, at: "2026-11-18T17:02:00Z"), timeZone: zone, locale: locale),
                       "Created \u{00B7} $420.00 \u{00B7} Nov 18, 11:02 AM")
        XCTAssertEqual(InvoiceRevisionWords.kindWord("lines_edited"), "Lines changed")
        XCTAssertEqual(InvoiceRevisionWords.kindWord("something_new"), "Changed")
        XCTAssertEqual(InvoiceRevisionWords.row(revision(4, kind: "created", total: 100, at: "not a date"), timeZone: zone, locale: locale),
                       "Created \u{00B7} $1.00")
    }

    func testTheUnsignedNoteNeedsAnEarlierSignedVersionOnAnIssuedInvoice() {
        let signedEarlier = history([revision(1, kind: "created"), revision(2, signed: true), revision(3)])
        func shows(_ read: InvoiceRevisionHistory?, status: String = "issued", revision: Int = 3) -> Bool {
            InvoiceRevisionWords.showsUnsignedNote(status: status, linesRevision: revision, history: read)
        }
        XCTAssertTrue(shows(signedEarlier))
        XCTAssertTrue(shows(signedEarlier, status: "paid"))
        XCTAssertFalse(shows(signedEarlier, status: "draft"))
        XCTAssertFalse(shows(signedEarlier, status: "void"))
        XCTAssertFalse(shows(nil), "Versions unread: say nothing")
        XCTAssertFalse(shows(history([revision(1, kind: "created"), revision(2), revision(3)])), "Never signed before")
        XCTAssertFalse(shows(history([revision(1), revision(2, signed: true), revision(3, signed: true)], signed: true)))
        XCTAssertFalse(shows(signedEarlier, revision: 4), "The read is older than the invoice on screen")
        XCTAssertEqual(InvoiceRevisionWords.unsignedNote, "The customer hasn\u{2019}t signed this version")
    }
}

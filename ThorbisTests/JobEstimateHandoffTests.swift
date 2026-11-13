import XCTest
@testable import Thorbis

final class JobEstimateHandoffSelectionTests: XCTestCase {
    func testTwoIndependentEstimatesStaySelectedTogether() {
        var selection = JobEstimateHandoffSelection()
        selection.setSelected("a", selected: true, eligibleIDs: ["a", "b"])
        selection.setSelected("b", selected: true, eligibleIDs: ["a", "b"])
        XCTAssertEqual(selection.selectedIDs, ["a", "b"])
        selection.setSelected("a", selected: false, eligibleIDs: ["a", "b"])
        XCTAssertEqual(selection.selectedIDs, ["b"])
    }
    func testIneligibleDraftApprovedOrForeignIDCannotJoinSelection() {
        var selection = JobEstimateHandoffSelection()
        for id in ["draft", "approved", "foreign"] {
            selection.setSelected(id, selected: true, eligibleIDs: ["sent"])
        }
        selection.setSelected("sent", selected: true, eligibleIDs: ["sent"])
        XCTAssertEqual(selection.selectedIDs, ["sent"])
    }
    func testPackagesRemainExclusiveOnlyInsideTheirOwnEstimate() {
        var selection = JobEstimateHandoffSelection()
        selection.chooseOption(estimateID: "a", optionID: "good", allowedOptionIDs: ["good", "better"])
        selection.chooseOption(estimateID: "b", optionID: "basic", allowedOptionIDs: ["basic"])
        selection.chooseOption(estimateID: "a", optionID: "better", allowedOptionIDs: ["good", "better"])
        selection.chooseOption(estimateID: "a", optionID: "foreign", allowedOptionIDs: ["good", "better"])
        XCTAssertEqual(selection.optionIDs, ["a": "better", "b": "basic"])
    }
    func testPartialRefreshKeepsSelectionAndAuthoritativeRemovalInvalidatesIt() {
        var selection = JobEstimateHandoffSelection()
        selection.setSelected("a", selected: true, eligibleIDs: ["a", "b"])
        selection.setSelected("b", selected: true, eligibleIDs: ["a", "b"])
        selection.reconcile(knownIDs: ["a"], complete: false)
        XCTAssertEqual(selection.selectedIDs, ["a", "b"])
        selection.reconcile(knownIDs: ["a"], complete: true)
        XCTAssertEqual(selection.selectedIDs, ["a"])
    }
    func testSelectionChangeRetiresReviewGenerationButRedundantChoiceDoesNot() {
        var selection = JobEstimateHandoffSelection()
        let original = selection.generation
        selection.setSelected("a", selected: true, eligibleIDs: ["a"])
        XCTAssertNotEqual(selection.generation, original)
        let selected = selection.generation
        selection.setSelected("a", selected: true, eligibleIDs: ["a"])
        XCTAssertEqual(selection.generation, selected)
        selection.chooseOption(estimateID: "a", optionID: "good", allowedOptionIDs: ["good"])
        XCTAssertNotEqual(selection.generation, selected)
    }
}

@MainActor
final class JobEstimateHandoffModelTests: XCTestCase {
    private let actor = "00000000-0000-4000-8000-000000000001"
    private let org = "00000000-0000-4000-8000-000000000002"
    private let customer = "00000000-0000-4000-8000-000000000003"
    private let jobID = "00000000-0000-4000-8000-000000000004"
    private let a = "00000000-0000-4000-8000-000000000011"
    private let b = "00000000-0000-4000-8000-000000000012"
    private func record(_ id: String, status: String = "sent") -> String {
        #"{"id":"\#(id)","organizationId":"\#(org)","customerId":"\#(customer)","createdByUserId":"\#(actor)","status":"\#(status)","currentRevisionNumber":1,"title":"Sample scope","lines":[{"id":"line","description":"Repair","quantity":1,"unitPrice":{"amount":19000,"currency":"USD"}}],"createdAt":"2026-10-29T00:00:00Z","updatedAt":"2026-10-29T00:00:00Z"}"#
    }
    private func revision(_ id: String, status: String = "issued") -> String {
        #"{"id":"00000000-0000-4000-8000-000000000099","estimateId":"\#(id)","organizationId":"\#(org)","customerId":"\#(customer)","revisionNumber":1,"status":"\#(status)","title":"Sample scope","lines":[{"id":"line","description":"Repair","quantity":1,"unitPrice":{"amount":19000,"currency":"USD"}}],"totalAmount":19000,"currency":"USD"}"#
    }
    private var jobJSON: String { #"{"id":"\#(jobID)","organizationId":"\#(org)","customerId":"\#(customer)","title":"Sample visit","status":"in_progress","createdAt":"2026-10-29T00:00:00Z","updatedAt":"2026-10-29T00:00:00Z"}"# }
    private func ready(_ responses: [URLProtocolFixture.Reply], job: String? = nil) async throws -> JobEstimateHandoffModel {
        let sessionJSON = #"{"user":{"id":"\#(actor)","name":"Sample"},"session":{"userId":"\#(actor)","activeOrganizationId":"\#(org)","expiresAt":"2099-10-29T00:00:00Z"}}"#
        let catalog = #"{"authority":{"actorId":"\#(actor)","organizationId":"\#(org)","policyVersion":1,"generation":"sample"},"capabilities":["job.view","estimate.view","estimate.send","estimate.approve"],"resources":[],"views":[]}"#
        let features = #"{"organizationId":"\#(org)","evaluatedAt":"2026-10-29T00:00:00Z","features":{"jobs":{"enabled":true,"released":true,"entitled":true},"estimates":{"enabled":true,"released":true,"entitled":true}}}"#
        let api = APIClient(session: URLProtocolFixture.session([.init(200, sessionJSON), .init(200, #"[{"id":"\#(org)","name":"Sample"}]"#), .init(200, catalog), .init(200, features)] + responses), baseURL: "https://app.thorbis.com")
        let session = SessionController(api: api, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await session.restore()
        let jobRecord = try JSONDecoder().decode(JobRecord.self, from: Data((job ?? jobJSON).utf8))
        return JobEstimateHandoffModel(job: jobRecord, customerName: "Sample customer", documents: JobDocumentCollections(), api: api, session: session)
    }
    private func membership(_ ids: [String], next: String? = nil, foreignJob: String? = nil) -> String {
        let links = ids.map { #"{"id":"\#($0)","jobId":"\#(foreignJob ?? jobID)","estimateId":"\#($0)","linkedAt":"2026-10-29T00:00:00Z"}"# }.joined(separator: ",")
        return #"{"items":[\#(links)],"nextCursor":\#(next.map { "\"\($0)\"" } ?? "null")}"#
    }
    private let packageID = "00000000-0000-4000-8000-000000000055"
    private func packageRecord(status: String = "sent") throws -> String {
        var value = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(record(a, status: status).utf8)) as? [String: Any])
        value["options"] = try packageOptions()
        return String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
    }
    private func packageOptions() throws -> [[String: Any]] {
        let value = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(record(a).utf8)) as? [String: Any])
        return [["id": packageID, "title": "Sample package", "description": "Sample description", "lines": value["lines"]!, "totalAmount": 19000, "currency": "USD"]]
    }
    private func packageRevision() throws -> String {
        var value = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(revision(a).utf8)) as? [String: Any])
        value["options"] = try packageOptions()
        return String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
    }
    private func packageAction(approved: Bool, receipt: Bool = true, mutation: [String: Any] = [:]) throws -> String {
        var value: [String: Any] = ["kind": "estimate", "title": "Sample scope", "status": approved ? "approved" : "sent", "revisionNumber": 1, "contentHash": String(repeating: "a", count: 64), "allowedActions": approved ? [] : ["approve"], "nonce": "retained-nonce", "totalAmount": 19000, "currency": "USD", "consentVersion": "estimate-approval-v1", "consentText": "I approve the selected scope and price and agree that my typed name is my electronic signature.", "options": [["id": packageID, "title": "Sample package", "description": "Sample description", "totalAmount": 19000, "currency": "USD"]]]
        if approved && receipt { value["acceptance"] = ["id": "00000000-0000-4000-8000-000000000077", "optionId": packageID, "signerName": "Canonical signer", "acceptedAt": "2026-10-29T12:00:00Z", "totalAmount": 19000] }
        value.merge(mutation) { _, new in new }
        return String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
    }
    private func unresolvedPackage(_ acceptedAction: String) async throws -> (JobEstimateHandoffModel, CustomerEstimateHandoffContext) {
        let model = try await ready([.init(200, jobJSON), .init(200, membership([a])), .init(200, try packageRecord()), .init(200, try packageRecord()), .init(200, try packageRevision()), .init(200, try packageRecord(status: "approved")), .init(200, acceptedAction)])
        await model.refresh(); model.setSelected(a, selected: true); model.chooseOption(estimateID: a, optionID: packageID); await model.reviewSelected()
        let context = try XCTUnwrap(model.context(for: a))
        _ = try context.freezeSignature(signerName: "Retained input", png: Data([1,2,3]), signedAt: "2026-10-29T12:00:00Z")
        let initial = try JSONDecoder().decode(PublicEstimateAction.self, from: Data(packageAction(approved: false).utf8))
        context.link = ("retained-test-token", initial)
        context.publicDecision = .approve(revisionNumber: 1, nonce: "retained-nonce", contentHash: String(repeating: "a", count: 64), signerName: "Retained input", consentVersion: "estimate-approval-v1", consent: true, optionID: packageID)
        context.submissionStarted = true; context.report(.unknown)
        return (model, context)
    }
    func testPublicReconciliationUsesSameTokenCanonicalAcceptanceForPackageAndSigner() async throws {
        let (model, context) = try await unresolvedPackage(packageAction(approved: true))
        let intent = context.signature, decision = context.publicDecision
        await model.reconcile(context.id)
        XCTAssertEqual(model.approvedCount, 1)
        XCTAssertEqual(context.approvedSignerName, "Canonical signer")
        XCTAssertEqual(context.signature, intent); XCTAssertEqual(context.publicDecision, decision)
        XCTAssertEqual(context.link?.token, "retained-test-token")
        XCTAssertTrue(URLProtocolFixture.recorded.contains { $0.url?.path == "/v1/public/document-actions/retained-test-token" })
        XCTAssertTrue(URLProtocolFixture.recorded.allSatisfy { $0.method == "GET" })
    }
    func testCanonicalPatchAcceptanceConfirmsWithoutReplacingTokenOrReadingAnotherAction() async throws {
        let (model, context) = try await unresolvedPackage(packageAction(approved: true))
        let patch = try JSONDecoder().decode(PublicEstimateActionPatch.self, from: Data(packageAction(approved: true).utf8))
        context.report(await context.publicConfirmed(patch))
        XCTAssertEqual(model.approvedCount, 1); XCTAssertEqual(context.approvedSignerName, "Canonical signer")
        XCTAssertNotNil(context.acceptedAction)
        XCTAssertFalse(URLProtocolFixture.recorded.contains { $0.url?.path == "/v1/public/document-actions/retained-test-token" })
        XCTAssertTrue(URLProtocolFixture.recorded.allSatisfy { $0.method == "GET" })
    }
    func testAbsentPatchAcceptanceReadsCanonicalActionFromSameRetainedToken() async throws {
        let (model, context) = try await unresolvedPackage(packageAction(approved: true))
        let patch = try JSONDecoder().decode(PublicEstimateActionPatch.self, from: Data(#"{"status":"approved"}"#.utf8))
        context.report(await context.publicConfirmed(patch))
        XCTAssertEqual(model.approvedCount, 1); XCTAssertEqual(context.approvedSignerName, "Canonical signer")
        XCTAssertEqual(context.link?.token, "retained-test-token")
        XCTAssertEqual(URLProtocolFixture.recorded.last?.url?.path, "/v1/public/document-actions/retained-test-token")
        XCTAssertTrue(URLProtocolFixture.recorded.allSatisfy { $0.method == "GET" })
        model.retire(); XCTAssertNil(context.acceptedAction); XCTAssertNil(context.signature)
    }
    func testBareApprovedAggregateCannotConfirmRequestedPackageWithoutCanonicalAcceptance() async throws {
        let (model, context) = try await unresolvedPackage(packageAction(approved: true, receipt: false))
        await model.reconcile(context.id)
        XCTAssertEqual(model.approvedCount, 0)
        XCTAssertNil(context.approvedSignerName)
        XCTAssertEqual(model.records.first?.status, "approved", "The bare current aggregate remains visible without unsupported package attribution")
        XCTAssertTrue(URLProtocolFixture.recorded.contains { $0.url?.path == "/v1/public/document-actions/retained-test-token" })
    }
    func testMismatchedPublicAcceptanceCannotReplaceFrozenChoiceOrConfirmSelectedPackage() async throws {
        let wrongReceipt: [String: Any] = ["id": "00000000-0000-4000-8000-000000000077", "optionId": b, "signerName": "Canonical signer", "acceptedAt": "2026-10-29T12:00:00Z", "totalAmount": 19000]
        var fractional = wrongReceipt; fractional["optionId"] = packageID; fractional["totalAmount"] = 19000.5
        for mutation: [String: Any] in [["acceptance": wrongReceipt], ["acceptance": fractional], ["revisionNumber": 2], ["contentHash": String(repeating: "b", count: 64)], ["currency": "EUR"], ["status": "sent"]] {
            let (model, context) = try await unresolvedPackage(packageAction(approved: true, mutation: mutation))
            let intent = context.signature
            await model.reconcile(context.id)
            XCTAssertEqual(model.approvedCount, 0)
            XCTAssertNil(context.approvedSignerName)
            XCTAssertEqual(context.reviewed.optionID, packageID); XCTAssertEqual(context.signature, intent)
            XCTAssertEqual(context.link?.token, "retained-test-token")
            XCTAssertTrue(URLProtocolFixture.recorded.allSatisfy { $0.method == "GET" })
        }
    }
    func testRetainedUnknownCheckpointSurvivesAnotherSelectionAndPackageChange() async throws {
        let c = "00000000-0000-4000-8000-000000000013"
        var third = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(record(c).utf8)) as? [String: Any]); third["options"] = try packageOptions()
        let thirdJSON = String(decoding: try JSONSerialization.data(withJSONObject: third), as: UTF8.self)
        let model = try await ready([])
        URLProtocolFixture.setRoutes([
            "/v1/jobs/\(jobID)": .init(200, jobJSON), "/v1/jobs/\(jobID)/estimates": .init(200, membership([a,b,c])),
            "/v1/estimates/\(a)": .init(200, record(a)), "/v1/estimates/\(b)": .init(200, record(b)),
            "/v1/estimates/\(c)": .init(200, thirdJSON),
            "/v1/estimates/\(a)/revisions/1": .init(200, revision(a)), "/v1/estimates/\(b)/revisions/1": .init(200, revision(b))
        ])
        await model.refresh(); model.setSelected(a, selected: true); model.setSelected(b, selected: true); await model.reviewSelected()
        let first = try XCTUnwrap(model.context(for: a)), second = try XCTUnwrap(model.context(for: b))
        first.report(await first.confirmed(try JSONDecoder().decode(EstimateRecord.self, from: Data(record(a, status: "approved").utf8))))
        let intent = try second.freezeSignature(signerName: "Sample signer", png: Data([1,2,3]), signedAt: "2026-10-29T12:00:00Z")
        second.submissionStarted = true; second.report(.unknown)
        model.setSelected(c, selected: true); model.chooseOption(estimateID: c, optionID: packageID)
        XCTAssertTrue(model.reviewed.isEmpty)
        await model.reconcile(second.id)
        XCTAssertTrue(second.retryVerified)
        XCTAssertTrue(model.checkpointContext(for: second.id) === second, "Explicit retry resolves the retained exact context independently of the new selection")
        XCTAssertEqual(second.signature, intent); XCTAssertTrue(second.canApprove())
        XCTAssertTrue(URLProtocolFixture.recorded.allSatisfy { $0.method == "GET" })
        model.api.invalidateRequests()
        XCTAssertNil(model.checkpointContext(for: second.id))
    }
    private func recoverablePreparation(_ replies: [URLProtocolFixture.Reply]) async throws -> (JobEstimateHandoffModel, CustomerEstimateHandoffContext) {
        let model = try await ready([.init(200, jobJSON), .init(200, membership([a])), .init(200, record(a)), .init(200, record(a)), .init(200, revision(a))] + replies)
        await model.refresh(); model.setSelected(a, selected: true); await model.reviewSelected()
        let context = try XCTUnwrap(model.context(for: a))
        _ = try context.freezeSignature(signerName: "Sample signer", png: Data([1,2,3]), signedAt: "2026-10-29T12:00:00Z")
        context.report(.retryable("Connection interrupted"))
        return (model, context)
    }
    func testPreSubmissionRecoveryRevalidatesExactTermsAndKeepsSignatureAndAssetIdentity() async throws {
        let (model, context) = try await recoverablePreparation([.init(200, jobJSON), .init(200, membership([a])), .init(200, record(a)), .init(200, revision(a))])
        let intent = context.signature
        await model.retryPreparation(context.id)
        XCTAssertNil(context.outcome)
        XCTAssertEqual(context.signature, intent); XCTAssertFalse(context.submissionStarted)
        XCTAssertEqual(URLProtocolFixture.recorded.suffix(4).compactMap { $0.url?.path }, ["/v1/jobs/\(jobID)", "/v1/jobs/\(jobID)/estimates", "/v1/estimates/\(a)", "/v1/estimates/\(a)/revisions/1"])
        XCTAssertTrue(URLProtocolFixture.recorded.allSatisfy { $0.method == "GET" })
    }
    func testPreSubmissionRecoveryNeverClearsUnknownOrChangedTermsOrRetiredAuthority() async throws {
        var newer = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(record(a).utf8)) as? [String: Any]); newer["currentRevisionNumber"] = 2
        let (model, context) = try await recoverablePreparation([.init(200, jobJSON), .init(200, membership([a])), .init(200, String(decoding: try JSONSerialization.data(withJSONObject: newer), as: UTF8.self))])
        let intent = context.signature
        await model.retryPreparation(context.id)
        if case .needsReview? = context.outcome {} else { XCTFail("Changed current revision requires review, never a silent retry reset") }
        XCTAssertEqual(context.signature, intent)
        context.submissionStarted = true; context.report(.unknown)
        let before = URLProtocolFixture.recorded.count
        await model.retryPreparation(context.id)
        XCTAssertEqual(context.outcome, .unknown); XCTAssertEqual(URLProtocolFixture.recorded.count, before)
        model.api.invalidateRequests(); await model.retryPreparation(context.id)
        XCTAssertEqual(URLProtocolFixture.recorded.count, before); XCTAssertEqual(context.signature, intent)
    }
    func testCompleteCollectionIncludesSecondPageAndIndependentSelection() async throws {
        let model = try await ready([.init(200, jobJSON), .init(200, membership([a], next: a)), .init(200, record(a)), .init(200, membership([b])), .init(200, record(b))])
        await model.refresh()
        XCTAssertEqual(model.records.map(\.id), [a]); XCTAssertFalse(model.complete)
        XCTAssertTrue(model.canLoadMoreEstimates)
        model.setSelected(a, selected: true); XCTAssertFalse(model.canReview)
        await model.loadMoreEstimates()
        XCTAssertEqual(model.records.map(\.id), [a, b]); XCTAssertTrue(model.complete)
        model.setSelected(b, selected: true)
        XCTAssertEqual(model.selectedIDs, [a, b])
        XCTAssertEqual(URLProtocolFixture.recorded.filter { $0.url?.path.hasSuffix("/estimates") == true }.count, 2)
    }
    func testInterruptedPartialHandoffOffersRetryAndKeepsSelection() async throws {
        let model = try await ready([])
        let ids = (11...16).map { String(format: "00000000-0000-4000-8000-%012d", $0) }
        let gate = URLProtocolFixture.Gate(); defer { gate.release() }
        var routes: [String: URLProtocolFixture.Reply] = [
            "/v1/jobs/\(jobID)": .init(200, jobJSON),
            "/v1/jobs/\(jobID)/estimates": .init(200, membership(ids))
        ]
        for id in ids { routes["/v1/estimates/\(id)"] = .init(200, record(id), gate: id == ids.last ? gate : nil) }
        URLProtocolFixture.setRoutes(routes)
        let task = Task { @MainActor in await model.refresh() }
        for _ in 0..<300 where model.records.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        let first = try XCTUnwrap(model.records.first)
        model.setSelected(first.id, selected: true)
        XCTAssertTrue(model.selectedIDs.contains(first.id))
        XCTAssertFalse(model.complete)
        XCTAssertFalse(model.canReview, "A partial collection cannot authorize a full review")
        task.cancel(); gate.release(); await task.value
        XCTAssertFalse(model.loading)
        XCTAssertFalse(model.complete)
        XCTAssertNotNil(model.error, "An interrupted partial load must offer a recovery action")
        XCTAssertTrue(model.selectedIDs.contains(first.id))
    }
    func testCancelledLastPageKeepsSelectionAndOffersRetry() async throws {
        let gate = URLProtocolFixture.Gate(); defer { gate.release() }
        let model = try await ready([.init(200, jobJSON), .init(200, membership([a], next: a)), .init(200, record(a)),
                                     .init(200, membership([b]), gate: gate)])
        await model.refresh(); model.setSelected(a, selected: true)
        XCTAssertTrue(model.canLoadMoreEstimates); XCTAssertTrue(model.selectedIDs.contains(a))
        let task = Task { @MainActor in await model.loadMoreEstimates() }
        for _ in 0..<300 where !model.loading { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(model.loading)
        task.cancel(); gate.release(); await task.value
        XCTAssertFalse(model.complete); XCTAssertFalse(model.canReview)
        XCTAssertNotNil(model.error); XCTAssertTrue(model.selectedIDs.contains(a))
    }
    func testInterruptedLastPageDetailsRetryTheSameMembershipCursor() async throws {
        let gate = URLProtocolFixture.Gate(); defer { gate.release() }
        let model = try await ready([.init(200, jobJSON), .init(200, membership([a], next: a)), .init(200, record(a)),
                                     .init(200, membership([b])), .init(200, record(b), gate: gate),
                                     .init(200, membership([b])), .init(200, record(b))])
        await model.refresh(); model.setSelected(a, selected: true)
        let task = Task { @MainActor in await model.loadMoreEstimates() }
        for _ in 0..<300 where !URLProtocolFixture.recorded.contains(where: { $0.url?.path == "/v1/estimates/\(b)" }) {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(URLProtocolFixture.recorded.contains { $0.url?.path == "/v1/estimates/\(b)" }, "The final membership page must be received before interrupting its details")
        task.cancel(); gate.release(); await task.value
        XCTAssertFalse(model.complete); XCTAssertFalse(model.canReview)
        XCTAssertNotNil(model.error); XCTAssertTrue(model.selectedIDs.contains(a))
        XCTAssertTrue(model.canLoadMoreEstimates, "The interrupted membership cursor must stay retryable")
        await model.loadMoreEstimates()
        XCTAssertEqual(model.records.map(\.id), [a, b]); XCTAssertTrue(model.complete)
        XCTAssertTrue(model.selectedIDs.contains(a))
        let membershipRequests = URLProtocolFixture.recorded.compactMap(\.url).filter { $0.path == "/v1/jobs/\(jobID)/estimates" }
        let cursors = membershipRequests.compactMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "cursor" })?.value }
        XCTAssertEqual(cursors, [a, a], "Retry must request the interrupted page, never skip or exhaust it")
    }
    func testBannerRetryResumesInterruptedPageInsteadOfRestartingJob() async throws {
        let gate = URLProtocolFixture.Gate(); defer { gate.release() }
        let model = try await ready([.init(200, jobJSON), .init(200, membership([a], next: a)), .init(200, record(a)),
                                     .init(200, membership([b])), .init(200, record(b), gate: gate),
                                     .init(200, membership([b])), .init(200, record(b))])
        await model.refresh(); model.setSelected(a, selected: true)
        let task = Task { @MainActor in await model.loadMoreEstimates() }
        for _ in 0..<300 where !URLProtocolFixture.recorded.contains(where: { $0.url?.path == "/v1/estimates/\(b)" }) {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(URLProtocolFixture.recorded.contains { $0.url?.path == "/v1/estimates/\(b)" })
        task.cancel(); gate.release(); await task.value
        XCTAssertNotNil(model.error)
        await model.retryEstimateLoading()
        XCTAssertEqual(URLProtocolFixture.recorded.filter { $0.url?.path == "/v1/jobs/\(jobID)" }.count, 1,
                       "Retry after Load more must not restart the job scan")
        XCTAssertTrue(model.selectedIDs.contains(a))
        XCTAssertEqual(model.records.map(\.id), [a, b]); XCTAssertTrue(model.complete)
        let cursors = URLProtocolFixture.recorded.compactMap(\.url).filter { $0.path == "/v1/jobs/\(jobID)/estimates" }.compactMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "cursor" })?.value }
        XCTAssertEqual(cursors, [a, a])
    }
    func testBannerRetryAfterInitialFailureRefreshesJob() async throws {
        let model = try await ready([.init(503, #"{"status":503,"title":"Unavailable"}"#), .init(200, jobJSON), .init(200, membership([a])), .init(200, record(a))])
        await model.refresh()
        XCTAssertNotNil(model.error)
        await model.retryEstimateLoading()
        XCTAssertEqual(URLProtocolFixture.recorded.filter { $0.url?.path == "/v1/jobs/\(jobID)" }.count, 2)
        XCTAssertEqual(model.records.map(\.id), [a]); XCTAssertTrue(model.complete)
    }
    func testInterruptedLaterPageDoesNotPublishPartialRows() async throws {
        let ids = (21...26).map { String(format: "00000000-0000-4000-8000-%012d", $0) }
        let gate = URLProtocolFixture.Gate(); defer { gate.release() }
        let model = try await ready([.init(200, jobJSON), .init(200, membership([a], next: a)), .init(200, record(a))])
        await model.refresh(); model.setSelected(a, selected: true)
        var routes: [String: URLProtocolFixture.Reply] = ["/v1/jobs/\(jobID)/estimates": .init(200, membership(ids))]
        for id in ids { routes["/v1/estimates/\(id)"] = .init(200, record(id), gate: id == ids.last ? gate : nil) }
        URLProtocolFixture.setRoutes(routes)
        let task = Task { @MainActor in await model.loadMoreEstimates() }
        for _ in 0..<300 where !URLProtocolFixture.recorded.contains(where: { $0.url?.path == "/v1/estimates/\(ids.last!)" }) {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(URLProtocolFixture.recorded.contains { $0.url?.path == "/v1/estimates/\(ids.last!)" })
        XCTAssertEqual(model.records.map(\.id), [a])
        task.cancel(); gate.release(); await task.value
        XCTAssertEqual(model.records.map(\.id), [a]); XCTAssertTrue(model.selectedIDs.contains(a))
        XCTAssertFalse(model.complete); XCTAssertTrue(model.canLoadMoreEstimates)
        for id in ids { routes["/v1/estimates/\(id)"] = .init(200, record(id)) }
        URLProtocolFixture.setRoutes(routes)
        await model.retryEstimateLoading()
        XCTAssertEqual(model.records.map(\.id), [a] + ids); XCTAssertTrue(model.complete)
        XCTAssertTrue(model.selectedIDs.contains(a))
    }
    func testApprovedEstimateAllowsReadOnlyDetailsButCannotBeSelectedForApproval() async throws {
        let model = try await ready([])
        let estimatePath = "/v1/estimates/\(a)"
        let membershipPath = "/v1/jobs/\(jobID)/estimates"
        let singlePath = "\(membershipPath)/\(a)"
        let link = #"{"id":"\#(a)","jobId":"\#(jobID)","estimateId":"\#(a)"}"#
        URLProtocolFixture.setRoutes([
            "/v1/jobs/\(jobID)": .init(200, jobJSON), membershipPath: .init(200, membership([a])),
            singlePath: .init(200, link), estimatePath: .init(200, record(a, status: "approved")),
            "\(estimatePath)/revisions/1": .init(200, revision(a, status: "approved"))
        ])
        await model.refresh()
        let approved = try XCTUnwrap(model.records.first)
        XCTAssertTrue(model.detailsCurrent(approved, authority: model.session.authorityRevision))
        let issued = try await model.issuedDetails(approved, authority: model.session.authorityRevision)
        XCTAssertEqual(issued.estimateId, a)
        model.setSelected(a, selected: true)
        XCTAssertFalse(model.selectedIDs.contains(a))
        XCTAssertFalse(model.canReview)
    }
    func testReceiptValidatesFoldedMaterialsAndExplicitCreditsWithoutOverflow() throws {
        var value = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(revision(a, status: "approved").utf8)) as? [String: Any])
        let lines: [[String: Any]] = [
            ["id": "line", "description": "Repair", "quantity": 1, "unitPrice": ["amount": 19000, "currency": "USD"]],
            ["id": "hidden", "description": "Internal part", "quantity": 2, "unitPrice": ["amount": 1000, "currency": "USD"], "showToCustomer": false],
            ["id": "credit", "description": "Courtesy credit", "quantity": 1, "unitPrice": ["amount": -1000, "currency": "USD"]]
        ]
        value["lines"] = lines; value["totalAmount"] = 20000
        let issued = try JSONDecoder().decode(CustomerIssuedEstimateRevision.self, from: JSONSerialization.data(withJSONObject: value))
        let json = #"{"id":"receipt","estimateId":"\#(a)","revisionId":"00000000-0000-4000-8000-000000000099","revisionNumber":1,"contentHash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","signerName":"Alex","acceptedAt":"2026-10-29T12:00:00Z","totalAmount":20000,"currency":"USD","lines":[{"id":"line","description":"Repair","quantity":1,"unitPrice":{"amount":19000,"currency":"USD"}},{"id":"credit","description":"Courtesy credit","quantity":1,"unitPrice":{"amount":-1000,"currency":"USD"}},{"id":"hidden","description":"Materials","quantity":1,"unitPrice":{"amount":2000,"currency":"USD"}}]}"#
        let receipt = try JSONDecoder().decode(CustomerEstimateAcceptanceReceipt.self, from: Data(json.utf8))
        XCTAssertNoThrow(try receipt.validate(for: issued))
        XCTAssertEqual(CustomerDocumentAmounts(lines: receipt.lines, currency: "USD")?.credits, -1000)
        XCTAssertFalse(receipt.lines.contains { $0.description == "Internal part" })
        let overflow = FieldLine(id: "bad", description: "Bad", quantity: Int.max,
                                 unitPrice: FieldMoney(amount: 2, currency: "USD"), source: nil)
        XCTAssertNil(CustomerDocumentAmounts(lines: [overflow], currency: "USD"))
    }
    func testOverviewPriceDoesNotReturnAfterEstimatePermissionRevokedAndRegranted() async throws {
        let model = try await ready([])
        let membershipPath = "/v1/jobs/\(jobID)/estimates", estimatePath = "/v1/estimates/\(a)"
        let link = #"{"id":"\#(a)","jobId":"\#(jobID)","estimateId":"\#(a)"}"#
        URLProtocolFixture.setRoutes(["/v1/jobs/\(jobID)": .init(200, jobJSON), membershipPath: .init(200, membership([a])),
                                      estimatePath: .init(200, record(a))])
        await model.refresh()
        let estimate = try XCTUnwrap(model.records.first)
        let gate = URLProtocolFixture.Gate(); defer { gate.release() }
        let revisionPath = "\(estimatePath)/revisions/1"
        let sessionJSON = #"{"user":{"id":"\#(actor)","name":"Sample"},"session":{"userId":"\#(actor)","activeOrganizationId":"\#(org)","expiresAt":"2099-10-29T00:00:00Z"}}"#
        let features = #"{"organizationId":"\#(org)","evaluatedAt":"2026-10-29T00:00:00Z","features":{"jobs":{"enabled":true,"released":true,"entitled":true},"estimates":{"enabled":true,"released":true,"entitled":true}}}"#
        func routes(_ allowed: Bool) -> [String: URLProtocolFixture.Reply] {
            let capabilities = allowed ? #""job.view","estimate.view","estimate.approve""# : #""job.view""#
            let catalog = #"{"authority":{"actorId":"\#(actor)","organizationId":"\#(org)","policyVersion":1,"generation":"sample"},"capabilities":[\#(capabilities)],"resources":[],"views":[]}"#
            return ["/v1/jobs/\(jobID)": .init(200, jobJSON), "\(membershipPath)/\(a)": .init(200, link),
                    estimatePath: .init(200, record(a)), revisionPath: .init(200, revision(a), gate: gate),
                    "/api/auth/get-session": .init(200, sessionJSON), "/v1/query/catalog": .init(200, catalog),
                    "/v1/features": .init(200, features)]
        }
        URLProtocolFixture.setRoutes(routes(true))
        let task = Task { @MainActor in await model.loadOverviewPrices() }
        for _ in 0..<300 where !URLProtocolFixture.recorded.contains(where: { $0.url?.path == revisionPath }) {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(URLProtocolFixture.recorded.contains { $0.url?.path == revisionPath }, "The issued response must be in flight before revocation")
        URLProtocolFixture.setRoutes(routes(false)); await model.session.revalidate()
        XCTAssertFalse(model.session.can("estimate.view", feature: "estimates"))
        XCTAssertFalse(model.isCurrent)
        URLProtocolFixture.setRoutes(routes(true)); await model.session.revalidate()
        XCTAssertTrue(model.session.can("estimate.view", feature: "estimates"))
        XCTAssertFalse(model.isCurrent, "Regrant must not revive the old handoff authority")
        gate.release(); await task.value
        XCTAssertNil(model.revision(for: estimate.id), "An old in-flight price must never republish after regrant")
        XCTAssertFalse(model.overviewPriceFailures.contains(estimate.id), "An old response must not publish a retry state into the retired handoff")
    }

    func testCancelledOverviewPriceCannotPublishAfterHandoffDisappears() async throws {
        let model = try await ready([])
        let membershipPath = "/v1/jobs/\(jobID)/estimates", estimatePath = "/v1/estimates/\(a)"
        let link = #"{"id":"\#(a)","jobId":"\#(jobID)","estimateId":"\#(a)"}"#
        URLProtocolFixture.setRoutes(["/v1/jobs/\(jobID)": .init(200, jobJSON), membershipPath: .init(200, membership([a])),
                                      estimatePath: .init(200, record(a))])
        await model.refresh()
        let estimate = try XCTUnwrap(model.records.first)
        let gate = URLProtocolFixture.Gate(); defer { gate.release() }
        let revisionPath = "\(estimatePath)/revisions/1"
        URLProtocolFixture.setRoutes(["/v1/jobs/\(jobID)": .init(200, jobJSON), "\(membershipPath)/\(a)": .init(200, link),
                                      estimatePath: .init(200, record(a)), revisionPath: .init(200, revision(a), gate: gate)])
        let task = Task { @MainActor in await model.loadOverviewPrices() }
        for _ in 0..<300 where !URLProtocolFixture.recorded.contains(where: { $0.url?.path == revisionPath }) {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(URLProtocolFixture.recorded.contains { $0.url?.path == revisionPath }, "The issued response must be in flight before disappearance")
        task.cancel(); model.retire(clearDocuments: false); gate.release(); await task.value
        XCTAssertNil(model.revision(for: estimate.id))
        XCTAssertTrue(model.records.isEmpty)
        XCTAssertTrue(model.overviewPriceFailures.isEmpty)
    }

    func testReceiptIsDiscardedWhenAuthorityChangesDuringRead() async throws {
        let model = try await ready([])
        let estimatePath = "/v1/estimates/\(a)", membershipPath = "/v1/jobs/\(jobID)/estimates"
        let receiptPath = "\(estimatePath)/revisions/1/acceptance"
        let link = #"{"id":"\#(a)","jobId":"\#(jobID)","estimateId":"\#(a)"}"#
        let receipt = #"{"id":"receipt","estimateId":"\#(a)","revisionId":"00000000-0000-4000-8000-000000000099","revisionNumber":1,"contentHash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","signerName":"Alex","acceptedAt":"2026-10-29T12:00:00Z","totalAmount":19000,"currency":"USD","lines":[{"id":"line","description":"Repair","quantity":1,"unitPrice":{"amount":19000,"currency":"USD"}}]}"#
        let gate = URLProtocolFixture.Gate(); defer { gate.release() }
        URLProtocolFixture.setRoutes(["/v1/jobs/\(jobID)": .init(200, jobJSON), membershipPath: .init(200, membership([a])),
            "\(membershipPath)/\(a)": .init(200, link), estimatePath: .init(200, record(a, status: "approved")),
            "\(estimatePath)/revisions/1": .init(200, revision(a, status: "approved")), receiptPath: .init(200, receipt, gate: gate)])
        await model.refresh()
        let record = try XCTUnwrap(model.records.first), authority = model.session.authorityRevision
        let issued = try await model.issuedDetails(record, authority: authority)
        let task = Task { @MainActor in try await model.approvedReceipt(record, revision: issued, authority: authority) }
        for _ in 0..<300 where !URLProtocolFixture.recorded.contains(where: { $0.url?.path == receiptPath }) { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(URLProtocolFixture.recorded.contains { $0.url?.path == receiptPath })
        model.api.invalidateRequests(); gate.release()
        do { _ = try await task.value; XCTFail("Retired authority must not expose a receipt") } catch { }
    }
    func testApprovedReceiptRequiresCurrentJobAndDistinguishesMissingFromDenied() async throws {
        let model = try await ready([])
        let estimatePath = "/v1/estimates/\(a)"
        let membershipPath = "/v1/jobs/\(jobID)/estimates"
        let link = #"{"id":"\#(a)","jobId":"\#(jobID)","estimateId":"\#(a)"}"#
        let receiptPath = "\(estimatePath)/revisions/1/acceptance"
        let valid = #"{"id":"receipt","estimateId":"\#(a)","revisionId":"00000000-0000-4000-8000-000000000099","revisionNumber":1,"contentHash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","signerName":"Alex","acceptedAt":"2026-10-29T12:00:00Z","totalAmount":19000,"currency":"USD","lines":[{"id":"line","description":"Repair","quantity":1,"unitPrice":{"amount":19000,"currency":"USD"}}]}"#
        func routes(_ status: Int, _ body: String) -> [String: URLProtocolFixture.Reply] {
            ["/v1/jobs/\(jobID)": .init(200, jobJSON), membershipPath: .init(200, membership([a])),
             "\(membershipPath)/\(a)": .init(200, link), estimatePath: .init(200, record(a, status: "approved")),
             "\(estimatePath)/revisions/1": .init(200, revision(a, status: "approved")), receiptPath: .init(status, body)]
        }
        URLProtocolFixture.setRoutes(routes(200, valid)); await model.refresh()
        let estimate = try XCTUnwrap(model.records.first)
        let authority = model.session.authorityRevision
        let issued = try await model.issuedDetails(estimate, authority: authority)
        let receipt = try await model.approvedReceipt(estimate, revision: issued, authority: authority)
        XCTAssertEqual(receipt?.signerName, "Alex")
        XCTAssertEqual(receipt?.lines.first?.description, "Repair")
        var changed = routes(200, valid)
        changed[estimatePath] = .init(200, record(a, status: "approved").replacingOccurrences(of: "\"currentRevisionNumber\":1", with: "\"currentRevisionNumber\":2"))
        URLProtocolFixture.setRoutes(changed)
        do { _ = try await model.approvedReceipt(estimate, revision: issued, authority: authority); XCTFail("A superseded revision must not be presented as current") }
        catch { }
        URLProtocolFixture.setRoutes(routes(404, #"{"status":404,"title":"Not found"}"#))
        let absent = try await model.approvedReceipt(estimate, revision: issued, authority: authority)
        XCTAssertNil(absent)
        URLProtocolFixture.setRoutes(routes(403, #"{"status":403,"title":"Denied"}"#))
        do { _ = try await model.approvedReceipt(estimate, revision: issued, authority: authority); XCTFail("A denied receipt must not be treated as unsigned") }
        catch let problem as Problem { XCTAssertEqual(problem.status, 403) }
        URLProtocolFixture.setRoutes(routes(200, valid.replacingOccurrences(of: "Repair", with: "Different")))
        do { _ = try await model.approvedReceipt(estimate, revision: issued, authority: authority); XCTFail("Mismatched scope must be rejected") }
        catch let problem as Problem { XCTAssertEqual(problem.status, 409) }
    }
    func testIssuedDetailsUsesTargetedMembershipAndRefuses403OrRemovedLink() async throws {
        let model = try await ready([])
        let membershipPath = "/v1/jobs/\(jobID)/estimates"
        let singlePath = "\(membershipPath)/\(a)"
        let item = #"{"id":"\#(a)","jobId":"\#(jobID)","estimateId":"\#(a)"}"#
        let estimatePath = "/v1/estimates/\(a)"
        func routes(_ status: Int, _ links: [String]) -> [String: URLProtocolFixture.Reply] {
            ["/v1/jobs/\(jobID)": .init(200, jobJSON), membershipPath: .init(200, membership(links)),
             singlePath: .init(status, status == 200 ? item : #"{"status":\#(status),"title":"Unavailable"}"#),
             estimatePath: .init(200, record(a)), "\(estimatePath)/revisions/1": .init(200, revision(a))]
        }
        URLProtocolFixture.setRoutes(routes(200, [a])); await model.refresh()
        let estimate = try XCTUnwrap(model.records.first)
        URLProtocolFixture.setRoutes(routes(200, [a]))
        _ = try await model.issuedDetails(estimate, authority: model.session.authorityRevision)
        XCTAssertEqual(URLProtocolFixture.recorded.filter { $0.url?.path == singlePath }.count, 2)
        XCTAssertFalse(URLProtocolFixture.recorded.contains { $0.url?.path == membershipPath }, "A linked detail must not scan all pages")
        URLProtocolFixture.setRoutes(routes(403, [a]))
        do { _ = try await model.issuedDetails(estimate, authority: model.session.authorityRevision); XCTFail("Denied access must not fall back") }
        catch let problem as Problem { XCTAssertEqual(problem.status, 403) }
        XCTAssertFalse(URLProtocolFixture.recorded.contains { $0.url?.path == membershipPath })
        URLProtocolFixture.setRoutes(routes(404, []))
        do { _ = try await model.issuedDetails(estimate, authority: model.session.authorityRevision); XCTFail("Removed estimate must not open") }
        catch let problem as Problem { XCTAssertEqual(problem.status, 409) }
        URLProtocolFixture.setRoutes(routes(404, [a]))
        _ = try await model.issuedDetails(estimate, authority: model.session.authorityRevision)
        XCTAssertEqual(URLProtocolFixture.recorded.filter { $0.url?.path == membershipPath }.count, 2, "Older server fallback checks both boundaries")
    }
    func testIssuedDetailsAllowsUnlinkedOriginButNeverFallsBackOnDeniedAccess() async throws {
        let originJob = jobJSON.replacingOccurrences(of: "\"title\":\"Sample visit\"", with: "\"estimateId\":\"\(a)\",\"title\":\"Sample visit\"")
        let model = try await ready([], job: originJob)
        let membershipPath = "/v1/jobs/\(jobID)/estimates", singlePath = "/v1/jobs/\(jobID)/estimates/\(a)"
        let estimatePath = "/v1/estimates/\(a)"
        func routes(_ status: Int) -> [String: URLProtocolFixture.Reply] {
            ["/v1/jobs/\(jobID)": .init(200, originJob), membershipPath: .init(200, membership([])),
             singlePath: .init(status, #"{"status":\#(status),"title":"Unavailable"}"#),
             estimatePath: .init(200, record(a)), "\(estimatePath)/revisions/1": .init(200, revision(a))]
        }
        URLProtocolFixture.setRoutes(routes(404)); await model.refresh()
        let estimate = try XCTUnwrap(model.records.first)
        URLProtocolFixture.setRoutes(routes(404))
        _ = try await model.issuedDetails(estimate, authority: model.session.authorityRevision)
        XCTAssertFalse(URLProtocolFixture.recorded.contains { $0.url?.path == membershipPath }, "The freshly verified origin needs no link scan")
        URLProtocolFixture.setRoutes(routes(403))
        do { _ = try await model.issuedDetails(estimate, authority: model.session.authorityRevision); XCTFail("Origin must not bypass denied access") }
        catch let problem as Problem { XCTAssertEqual(problem.status, 403) }
    }
    func testIssuedDetailsStopsWhenAuthorityChangesDuringTargetedRead() async throws {
        let model = try await ready([])
        let membershipPath = "/v1/jobs/\(jobID)/estimates", singlePath = "/v1/jobs/\(jobID)/estimates/\(a)"
        let item = #"{"id":"\#(a)","jobId":"\#(jobID)","estimateId":"\#(a)"}"#
        let estimatePath = "/v1/estimates/\(a)"
        URLProtocolFixture.setRoutes(["/v1/jobs/\(jobID)": .init(200, jobJSON), membershipPath: .init(200, membership([a])),
                                      estimatePath: .init(200, record(a))])
        await model.refresh()
        let estimate = try XCTUnwrap(model.records.first), gate = URLProtocolFixture.Gate()
        defer { gate.release() }
        URLProtocolFixture.setRoutes(["/v1/jobs/\(jobID)": .init(200, jobJSON), singlePath: .init(200, item, gate: gate),
                                      estimatePath: .init(200, record(a)), "\(estimatePath)/revisions/1": .init(200, revision(a))])
        let task = Task { @MainActor in try await model.issuedDetails(estimate, authority: model.session.authorityRevision) }
        for _ in 0..<300 where !URLProtocolFixture.recorded.contains(where: { $0.url?.path == singlePath }) { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(URLProtocolFixture.recorded.contains { $0.url?.path == singlePath })
        model.api.invalidateRequests(); gate.release()
        do { _ = try await task.value; XCTFail("Retired authority cannot open issued terms") } catch { }
        XCTAssertFalse(URLProtocolFixture.recorded.contains { $0.url?.path == "\(estimatePath)/revisions/1" })
    }
    func testApprovedAndDraftStayVisibleButNeverEnterApprovalSelection() async throws {
        let model = try await ready([])
        URLProtocolFixture.setRoutes([
            "/v1/jobs/\(jobID)": .init(200, jobJSON),
            "/v1/jobs/\(jobID)/estimates": .init(200, membership([a, b])),
            "/v1/estimates/\(a)": .init(200, record(a, status: "approved")),
            "/v1/estimates/\(b)": .init(200, record(b, status: "draft"))
        ])
        await model.refresh()
        XCTAssertEqual(model.records.count, 2)
        model.setSelected(a, selected: true); model.setSelected(b, selected: true)
        XCTAssertTrue(model.selectedIDs.isEmpty)
        XCTAssertFalse(model.canReview)
        XCTAssertTrue(URLProtocolFixture.recorded.allSatisfy { $0.method == "GET" })
    }
    func testForeignJobSameCustomerCannotBecomeAnApprovalCandidate() async throws {
        let foreign = "00000000-0000-4000-8000-000000000088"
        let model = try await ready([.init(200, jobJSON), .init(200, membership([b], foreignJob: foreign))])
        await model.refresh()
        XCTAssertFalse(model.records.contains { $0.id == b }); XCTAssertFalse(model.complete)
        model.setSelected(b, selected: true)
        XCTAssertTrue(model.selectedIDs.isEmpty)
        XCTAssertFalse(URLProtocolFixture.recorded.contains { $0.url?.path == "/v1/estimates/\(b)" })
    }
    func testAPIContextChangeRetiresOldSelectionAuthority() async throws {
        let model = try await ready([.init(200, jobJSON), .init(200, membership([a])), .init(200, record(a))])
        await model.refresh(); XCTAssertTrue(model.isCurrent)
        model.api.invalidateRequests()
        XCTAssertFalse(model.isCurrent)
        model.setSelected(a, selected: true); await model.reviewSelected()
        XCTAssertTrue(model.selectedIDs.isEmpty); XCTAssertTrue(model.reviewed.isEmpty)
    }
    func testInconsistentCanonicalTotalRequiresReviewInsteadOfInventingASum() async throws {
        let inconsistent = revision(a).replacingOccurrences(of: "\"totalAmount\":19000", with: "\"totalAmount\":20000")
        let model = try await ready([.init(200, jobJSON), .init(200, membership([a])), .init(200, record(a)), .init(200, record(a)), .init(200, inconsistent)])
        await model.refresh(); model.setSelected(a, selected: true); await model.reviewSelected()
        XCTAssertTrue(model.reviewed.isEmpty)
        XCTAssertNotNil(model.error)
    }
    func testNextCheckpointPrefillsConfirmedSignerWithoutCarryingInkOrConsent() async throws {
        let model = try await ready([])
        URLProtocolFixture.setRoutes([
            "/v1/jobs/\(jobID)": .init(200, jobJSON), "/v1/jobs/\(jobID)/estimates": .init(200, membership([a,b])),
            "/v1/estimates/\(a)": .init(200, record(a)), "/v1/estimates/\(b)": .init(200, record(b)),
            "/v1/estimates/\(a)/revisions/1": .init(200, revision(a)), "/v1/estimates/\(b)/revisions/1": .init(200, revision(b))
        ])
        await model.refresh(); model.setSelected(a, selected: true); model.setSelected(b, selected: true); await model.reviewSelected()
        let first = try XCTUnwrap(model.context(for: a)), second = try XCTUnwrap(model.context(for: b))
        _ = try first.freezeSignature(signerName: "Sample different signer", png: Data([1,2,3]), signedAt: "2026-10-29T12:00:00Z")
        let approved = try JSONDecoder().decode(EstimateRecord.self, from: Data(record(a, status: "approved").utf8))
        first.report(await first.confirmed(approved))
        XCTAssertNil(first.approvedSignerName, "Canonical approval with no recorded signature cannot attribute the retained input name")
        XCTAssertEqual(second.initialSignerName, "Sample different signer")
        XCTAssertNil(second.signature); XCTAssertNil(second.uploadedMediaID); XCTAssertNil(second.publicDecision)
    }
    func testRetiredHandoffRemainsProtectedUntilAuthenticatedExitThenReleasesPrivateModel() async throws {
        let presenter = JobEstimateHandoffPresenter()
        weak var releasedModel: JobEstimateHandoffModel?
        do {
            let model = try await ready([.init(200, jobJSON), .init(200, membership([a])), .init(200, record(a)), .init(200, record(a)), .init(200, revision(a))])
            await model.refresh(); model.setSelected(a, selected: true); await model.reviewSelected()
            let context = try XCTUnwrap(model.context(for: a))
            _ = try context.freezeSignature(signerName: "Sample signer", png: Data([1,2,3]), signedAt: "2026-10-29T12:00:00Z")
            presenter.present(model, onAuthenticatedExit: {})
            releasedModel = model
            model.retire()
            XCTAssertTrue(presenter.active === model, "Retirement must not expose the underlying staff branch")
            XCTAssertTrue(model.records.isEmpty); XCTAssertTrue(model.contexts.isEmpty)
            XCTAssertNil(model.documents.estimates); XCTAssertNil(context.signature)
            XCTAssertEqual(model.customerName, ""); XCTAssertEqual(model.jobTitle, "")
            presenter.authenticatedExit()
            XCTAssertNil(presenter.active)
        }
        await Task.yield()
        XCTAssertNil(releasedModel, "The presenter/context callbacks must not retain the exited private model")
    }
    func testDetachedInvoiceSourceCannotPresentAfterDelayedJobRead() async throws {
        let gate = URLProtocolFixture.Gate()
        let model = try await ready([.init(200, jobJSON, gate: gate)])
        let presenter = JobEstimateHandoffPresenter()
        var attached = true
        let task = Task { await presenter.openCustomerView(jobID: jobID, customerID: customer,
            customerName: "Sample", start: .invoice("invoice-a"), api: model.api, session: model.session,
            sourceStillAttached: { attached }, onExit: { _ in XCTFail("Detached source cannot receive handoff") }) }
        defer { gate.release(); task.cancel() }
        for _ in 0..<100 where !URLProtocolFixture.recorded.contains(where: { $0.url?.path == "/v1/jobs/\(jobID)" }) {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(URLProtocolFixture.recorded.contains(where: { $0.url?.path == "/v1/jobs/\(jobID)" }))
        attached = false; gate.release()
        let result = await task.value
        XCTAssertEqual(result, .superseded)
        XCTAssertNil(presenter.active)
    }
    func testInvalidatedOrCancelledJobReadCannotFallBackToLegacyPresentation() async throws {
        for cancel in [false, true] {
            let gate = URLProtocolFixture.Gate()
            let model = try await ready([.init(200, jobJSON, gate: gate)])
            let presenter = JobEstimateHandoffPresenter()
            let task = Task { await presenter.openCustomerView(jobID: jobID, customerID: customer,
                customerName: "Sample", start: .invoice("invoice-a"), api: model.api, session: model.session,
                onExit: { _ in }) }
            defer { gate.release(); task.cancel() }
            for _ in 0..<100 where !URLProtocolFixture.recorded.contains(where: { $0.url?.path == "/v1/jobs/\(jobID)" }) {
                try await Task.sleep(for: .milliseconds(50))
            }
            XCTAssertTrue(URLProtocolFixture.recorded.contains(where: { $0.url?.path == "/v1/jobs/\(jobID)" }))
            if cancel { task.cancel() } else { model.api.invalidateRequests() }
            gate.release()
            let result = await task.value
            XCTAssertEqual(result, .superseded)
            XCTAssertNil(presenter.active)
        }
    }
    func testCurrentHandoffReturnsRequestedInvoiceToStaff() async throws {
        let model = try await ready([])
        let presenter = JobEstimateHandoffPresenter()
        let callback = expectation(description: "Current handoff returns the selected invoice")
        presenter.present(model, start: .invoice("invoice-a")) { exit in
            if case .collect("invoice-a") = exit { callback.fulfill() }
        }
        XCTAssertTrue(presenter.active === model)
        presenter.authenticatedExit(.collect(invoiceID: "invoice-a"))
        await fulfillment(of: [callback], timeout: 1)
    }
    func testPresenterReportsWhenAnotherCustomerHandoffPreventsOpening() async throws {
        let model = try await ready([])
        let presenter = JobEstimateHandoffPresenter()
        let lease = try XCTUnwrap(presenter.claimLegacy())
        XCTAssertFalse(presenter.present(model, onAuthenticatedExit: {}))
        XCTAssertNil(presenter.active)
        lease.release()
    }
    func testQueuedCollectDoesNotRunAfterAnotherCustomerHandoffStarts() async throws {
        let model = try await ready([])
        let presenter = JobEstimateHandoffPresenter()
        let callback = expectation(description: "Earlier collection must not run behind a newer handoff")
        callback.isInverted = true
        presenter.present(model, start: .invoice("invoice-a")) { exit in
            if case .collect = exit { callback.fulfill() }
        }
        presenter.authenticatedExit(.collect(invoiceID: "invoice-a"))
        let lease = try XCTUnwrap(presenter.claimLegacy())
        await fulfillment(of: [callback], timeout: 0.5)
        lease.release()
    }
    func testQueuedCollectDoesNotRunAfterAuthorityChanges() async throws {
        let model = try await ready([])
        let presenter = JobEstimateHandoffPresenter()
        let callback = expectation(description: "Queued collection must not use retired authority")
        callback.isInverted = true
        presenter.present(model, start: .invoice("invoice-a")) { exit in
            if case .collect = exit { callback.fulfill() }
        }
        presenter.authenticatedExit(.collect(invoiceID: "invoice-a"))
        model.api.invalidateRequests()
        await fulfillment(of: [callback], timeout: 0.5)
    }
    func testRetiredHandoffCannotReturnCollectToStaff() async throws {
        let model = try await ready([])
        let presenter = JobEstimateHandoffPresenter()
        let callback = expectation(description: "Retired handoff must not open collection")
        callback.isInverted = true
        presenter.present(model, start: .invoice("invoice-a")) { exit in
            if case .collect = exit { callback.fulfill() }
        }
        XCTAssertTrue(presenter.active === model)
        model.api.invalidateRequests()
        XCTAssertFalse(model.isCurrentJob)
        presenter.authenticatedExit(.collect(invoiceID: "invoice-a"))
        await fulfillment(of: [callback], timeout: 0.5)
    }
    func testResultAttributionUsesCanonicalSignerInsteadOfRetainedInput() async throws {
        let model = try await ready([.init(200, jobJSON), .init(200, membership([a])), .init(200, record(a)), .init(200, record(a)), .init(200, revision(a))])
        await model.refresh(); model.setSelected(a, selected: true); await model.reviewSelected()
        let context = try XCTUnwrap(model.context(for: a))
        let intent = try context.freezeSignature(signerName: "Retained input name", png: Data([1,2,3]), signedAt: "2026-10-29T12:00:00Z")
        var canonical = try JSONDecoder().decode(EstimateRecord.self, from: Data(record(a, status: "approved").utf8))
        canonical.approvalSignature = .init(id: "00000000-0000-4000-8000-000000000077", signerName: "Canonical recorded signer", signedAt: "2026-10-29T12:01:00Z", imageMediaId: "00000000-0000-4000-8000-000000000078")
        context.report(await context.confirmed(canonical))
        XCTAssertEqual(context.approvedSignerName, "Canonical recorded signer")
        XCTAssertEqual(context.signature, intent, "Canonical display attribution must not replace the retained attempt")
    }
    func testReviewedTermsComeFromBothExactImmutableRevisions() async throws {
        let model = try await ready([])
        URLProtocolFixture.setRoutes([
            "/v1/jobs/\(jobID)": .init(200, jobJSON), "/v1/jobs/\(jobID)/estimates": .init(200, membership([a,b])),
            "/v1/estimates/\(a)": .init(200, record(a)), "/v1/estimates/\(b)": .init(200, record(b)),
            "/v1/estimates/\(a)/revisions/1": .init(200, revision(a)), "/v1/estimates/\(b)/revisions/1": .init(200, revision(b))
        ])
        await model.refresh(); model.setSelected(a, selected: true); model.setSelected(b, selected: true)
        await model.reviewSelected()
        XCTAssertEqual(model.reviewed.map(\.id), [a,b]); XCTAssertEqual(model.reviewed.map(\.revision.totalAmount), [19000,19000])
    }
    func testRefreshedNewRevisionDoesNotShowCachedPriorPackageTerms() async throws {
        var updated = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(packageRecord().utf8)) as? [String: Any])
        updated["currentRevisionNumber"] = 2
        var newOptions = try packageOptions()
        newOptions[0]["description"] = "Current revision package description"
        updated["options"] = newOptions
        let newRecord = String(decoding: try JSONSerialization.data(withJSONObject: updated), as: UTF8.self)
        let model = try await ready([.init(200, jobJSON), .init(200, membership([a])), .init(200, try packageRecord()),
                                     .init(200, try packageRecord()), .init(200, try packageRevision()),
                                     .init(200, jobJSON), .init(200, membership([a])), .init(200, newRecord)])
        await model.refresh()
        model.setSelected(a, selected: true)
        model.chooseOption(estimateID: a, optionID: packageID)
        await model.reviewSelected()
        XCTAssertEqual(model.options(for: a).first?.description, "Sample description")
        await model.refresh()
        XCTAssertEqual(model.records.first?.currentRevisionNumber, 2)
        XCTAssertNil(model.revision(for: a), "An old issued revision cannot describe new terms")
        XCTAssertEqual(model.options(for: a).first?.description, "Current revision package description")
        XCTAssertTrue(URLProtocolFixture.recorded.allSatisfy { $0.method == "GET" })
    }

    func testRefreshingPartialSuccessKeepsUnknownAttemptAndReviewedSelection() async throws {
        let model = try await ready([])
        URLProtocolFixture.setRoutes([
            "/v1/jobs/\(jobID)": .init(200, jobJSON), "/v1/jobs/\(jobID)/estimates": .init(200, membership([a,b])),
            "/v1/estimates/\(a)": .init(200, record(a)), "/v1/estimates/\(b)": .init(200, record(b)),
            "/v1/estimates/\(a)/revisions/1": .init(200, revision(a)), "/v1/estimates/\(b)/revisions/1": .init(200, revision(b))
        ])
        await model.refresh(); model.setSelected(a, selected: true); model.setSelected(b, selected: true); await model.reviewSelected()
        let first = try XCTUnwrap(model.context(for: a)), second = try XCTUnwrap(model.context(for: b))
        let approved = try JSONDecoder().decode(EstimateRecord.self, from: Data(record(a, status: "approved").utf8))
        first.report(await first.confirmed(approved))
        let intent = try second.freezeSignature(signerName: "Sample signer", png: Data([1,2,3]), signedAt: "2026-10-29T12:00:00Z")
        second.submissionStarted = true; second.report(.unknown)
        URLProtocolFixture.setRoutes([
            "/v1/jobs/\(jobID)": .init(200, jobJSON), "/v1/jobs/\(jobID)/estimates": .init(200, membership([a,b])),
            "/v1/estimates/\(a)": .init(200, record(a, status: "approved")), "/v1/estimates/\(b)": .init(200, record(b))
        ])
        await model.refresh()
        XCTAssertEqual(model.selectedIDs, [a,b], "Confirmed work stays part of this reviewed handoff; it is not sent again")
        XCTAssertTrue(model.context(for: b) === second)
        XCTAssertEqual(second.signature, intent)
        XCTAssertTrue(second.canApprove(), "Refreshing another document's success must not orphan this exact reviewed attempt")
        XCTAssertEqual(model.approvedCount, 1); XCTAssertEqual(model.unknownCount, 1)
        model.setSelected(a, selected: false)
        XCTAssertTrue(second.canApprove(), "Changing another card cannot replace or orphan this already submitted exact intent")
        XCTAssertEqual(second.signature, intent)
    }
    func testRefreshOfAlreadyApprovedRevisionCannotPostAgainWithoutAReceipt() async throws {
        let model = try await ready([.init(200, jobJSON), .init(200, membership([a])), .init(200, record(a)), .init(200, record(a)), .init(200, revision(a)), .init(200, jobJSON), .init(200, membership([a])), .init(200, record(a, status: "approved"))])
        await model.refresh(); model.setSelected(a, selected: true); await model.reviewSelected()
        let context = try XCTUnwrap(model.context(for: a))
        XCTAssertTrue(context.canApprove())
        await model.refresh()
        XCTAssertFalse(context.canApprove(), "A refreshed approved record is read-only even before its local receipt is reconciled")
        XCTAssertTrue(URLProtocolFixture.recorded.allSatisfy { $0.method == "GET" })
    }
    func testRetainedAttemptNeverReplacesBytesNameTimeOrAssetAfterRecreation() async throws {
        let model = try await ready([.init(200, jobJSON), .init(200, membership([a])), .init(200, record(a)), .init(200, record(a)), .init(200, revision(a))])
        await model.refresh(); model.setSelected(a, selected: true); await model.reviewSelected()
        let reviewed = try XCTUnwrap(model.reviewed.first)
        let context = try XCTUnwrap(model.contexts[reviewed.key])
        let original = try context.freezeSignature(signerName: "Sample signer", png: Data([1,2,3]), signedAt: "2026-10-29T12:00:00Z")
        XCTAssertEqual(try context.freezeSignature(signerName: "Sample signer", png: Data([1,2,3]), signedAt: "2026-10-29T12:00:00Z"), original)
        XCTAssertThrowsError(try context.freezeSignature(signerName: "Changed", png: Data([4]), signedAt: "2026-10-29T12:01:00Z"))
        XCTAssertEqual(model.contexts[reviewed.key]?.signature, original)
        XCTAssertEqual(context.signature?.clientAssetID, original.clientAssetID)
    }
}

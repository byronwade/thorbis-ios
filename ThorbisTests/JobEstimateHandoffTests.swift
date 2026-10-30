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
    private func revision(_ id: String) -> String {
        #"{"id":"00000000-0000-4000-8000-000000000099","estimateId":"\#(id)","organizationId":"\#(org)","customerId":"\#(customer)","revisionNumber":1,"status":"issued","title":"Sample scope","lines":[{"id":"line","description":"Repair","quantity":1,"unitPrice":{"amount":19000,"currency":"USD"}}],"totalAmount":19000,"currency":"USD"}"#
    }
    private var jobJSON: String { #"{"id":"\#(jobID)","organizationId":"\#(org)","customerId":"\#(customer)","title":"Sample visit","status":"in_progress","createdAt":"2026-10-29T00:00:00Z","updatedAt":"2026-10-29T00:00:00Z"}"# }
    private func ready(_ responses: [URLProtocolFixture.Reply]) async throws -> JobEstimateHandoffModel {
        let sessionJSON = #"{"user":{"id":"\#(actor)","name":"Sample"},"session":{"userId":"\#(actor)","activeOrganizationId":"\#(org)","expiresAt":"2099-10-29T00:00:00Z"}}"#
        let catalog = #"{"authority":{"actorId":"\#(actor)","organizationId":"\#(org)","policyVersion":1,"generation":"sample"},"capabilities":["job.view","estimate.view","estimate.send","estimate.approve"],"resources":[],"views":[]}"#
        let features = #"{"organizationId":"\#(org)","evaluatedAt":"2026-10-29T00:00:00Z","features":{"jobs":{"enabled":true,"released":true,"entitled":true},"estimates":{"enabled":true,"released":true,"entitled":true}}}"#
        let api = APIClient(session: URLProtocolFixture.session([.init(200, sessionJSON), .init(200, #"[{"id":"\#(org)","name":"Sample"}]"#), .init(200, catalog), .init(200, features)] + responses), baseURL: "https://app.thorbis.com")
        let session = SessionController(api: api, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await session.restore()
        let job = try JSONDecoder().decode(JobRecord.self, from: Data(jobJSON.utf8))
        return JobEstimateHandoffModel(job: job, customerName: "Sample customer", documents: JobDocumentCollections(), api: api, session: session)
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
        let model = try await ready([.init(200, jobJSON), .init(200, membership([a,b,c])), .init(200, record(a)), .init(200, record(b)), .init(200, thirdJSON), .init(200, record(a)), .init(200, revision(a)), .init(200, record(b)), .init(200, revision(b)), .init(200, record(b)), .init(200, record(b)), .init(200, revision(b)), .init(200, jobJSON), .init(200, membership([a,b,c]))])
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
        let model = try await ready([.init(200, jobJSON), .init(200, membership([a], next: "next")), .init(200, membership([b])), .init(200, record(a)), .init(200, record(b))])
        await model.refresh()
        XCTAssertEqual(model.records.map(\.id), [a, b]); XCTAssertTrue(model.complete)
        model.setSelected(a, selected: true); model.setSelected(b, selected: true)
        XCTAssertEqual(model.selectedIDs, [a, b])
        XCTAssertEqual(URLProtocolFixture.recorded.filter { $0.url?.path.hasSuffix("/estimates") == true }.count, 2)
    }
    func testApprovedAndDraftStayVisibleButNeverEnterApprovalSelection() async throws {
        let model = try await ready([.init(200, jobJSON), .init(200, membership([a, b])), .init(200, record(a, status: "approved")), .init(200, record(b, status: "draft"))])
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
        let model = try await ready([.init(200, jobJSON), .init(200, membership([a,b])), .init(200, record(a)), .init(200, record(b)), .init(200, record(a)), .init(200, revision(a)), .init(200, record(b)), .init(200, revision(b))])
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
        let model = try await ready([.init(200, jobJSON), .init(200, membership([a,b])), .init(200, record(a)), .init(200, record(b)), .init(200, record(a)), .init(200, revision(a)), .init(200, record(b)), .init(200, revision(b))])
        await model.refresh(); model.setSelected(a, selected: true); model.setSelected(b, selected: true)
        await model.reviewSelected()
        XCTAssertEqual(model.reviewed.map(\.id), [a,b]); XCTAssertEqual(model.reviewed.map(\.revision.totalAmount), [19000,19000])
    }
    func testRefreshingPartialSuccessKeepsUnknownAttemptAndReviewedSelection() async throws {
        let model = try await ready([.init(200, jobJSON), .init(200, membership([a,b])), .init(200, record(a)), .init(200, record(b)), .init(200, record(a)), .init(200, revision(a)), .init(200, record(b)), .init(200, revision(b)), .init(200, jobJSON), .init(200, membership([a,b])), .init(200, record(a, status: "approved")), .init(200, record(b))])
        await model.refresh(); model.setSelected(a, selected: true); model.setSelected(b, selected: true); await model.reviewSelected()
        let first = try XCTUnwrap(model.context(for: a)), second = try XCTUnwrap(model.context(for: b))
        let approved = try JSONDecoder().decode(EstimateRecord.self, from: Data(record(a, status: "approved").utf8))
        first.report(await first.confirmed(approved))
        let intent = try second.freezeSignature(signerName: "Sample signer", png: Data([1,2,3]), signedAt: "2026-10-29T12:00:00Z")
        second.submissionStarted = true; second.report(.unknown)
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

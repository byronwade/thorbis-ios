import XCTest
@testable import Thorbis

@MainActor
final class PublicEstimateActionTests: XCTestCase {
    func testParsesThorbisEstimateActionLinksAndRejectsOtherHosts() throws {
        XCTAssertEqual(
            PublicEstimateActionLink.token(from: URL(string: "https://app.thorbis.com/app/d/issued_token-1")!),
            "issued_token-1"
        )
        XCTAssertEqual(
            PublicEstimateActionLink.token(from: URL(string: "thorbis://document/issued_token-2")!),
            "issued_token-2"
        )
        XCTAssertNil(PublicEstimateActionLink.token(from: URL(string: "https://example.com/app/d/issued_token")!))
        XCTAssertNil(PublicEstimateActionLink.token(from: URL(string: "https://app.thorbis.com/app/d/return")!))
    }

    func testApprovalReadinessRequiresOptionNameAndConsent() throws {
        let action = try makeAction(options: #"[{"id":"option-1","title":"Standard","description":"Replace the unit","totalAmount":4200,"currency":"USD"}]"#)

        XCTAssertFalse(action.canApprove(signerName: "Hayley Wade", consent: true, selectedOptionID: nil))
        XCTAssertFalse(action.canApprove(signerName: "   ", consent: true, selectedOptionID: "option-1"))
        XCTAssertFalse(action.canApprove(signerName: "Hayley Wade", consent: false, selectedOptionID: "option-1"))
        XCTAssertTrue(action.canApprove(signerName: " Hayley Wade ", consent: true, selectedOptionID: "option-1"))
    }

    func testPlainApprovalRequiresExplicitServerPermissionAndIssuedScope() throws {
        let action = try makeAction(options: "[]", signed: false)
        XCTAssertTrue(action.canApprovePlainly)

        let noScope = try makeAction(options: "[]", signed: false, scope: "[]")
        XCTAssertFalse(noScope.canApprovePlainly)

        let signatureOnly = try makeAction(options: "[]", signed: true, plain: false)
        XCTAssertFalse(signatureOnly.canApprovePlainly)
    }

    func testPublicDecisionUsesExactTokenRouteAndDoesNotHandleSessionCookies() async throws {
        let api = APIClient(session: URLProtocolFixture.session([
            .init(200, actionJSON),
            .init(200, actionJSON)
        ]), baseURL: "https://app.thorbis.com")

        let _: PublicEstimateAction = try await api.publicDocumentAction(token: "issued_token-1")
        let _: PublicEstimateActionPatch = try await api.decidePublicDocumentAction(
            token: "issued_token-1",
            decision: .requestChanges(revisionNumber: 7, nonce: "nonce-value-123", message: "Please clarify the condenser model.")
        )

        let requests = URLProtocolFixture.recorded
        XCTAssertEqual(requests.map(\.url?.path), [
            "/v1/public/document-actions/issued_token-1",
            "/v1/public/document-actions/issued_token-1/request-changes"
        ])
        XCTAssertEqual(requests[1].method, "POST")
        XCTAssertFalse(requests[0].handlesCookies)
        XCTAssertFalse(requests[1].handlesCookies)
        let body = try XCTUnwrap(requests[1].body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["revisionNumber"] as? Int, 7)
        XCTAssertEqual(json["nonce"] as? String, "nonce-value-123")
        XCTAssertEqual(json["message"] as? String, "Please clarify the condenser model.")
        XCTAssertNil(json["contentHash"])
        XCTAssertNil(requests[1].header("cookie"))
    }

    func testSignedApprovalCarriesIssuedIdentityAndConsentEvidence() async throws {
        let api = APIClient(session: URLProtocolFixture.session([.init(200, actionJSON)]), baseURL: "https://app.thorbis.com")
        let _: PublicEstimateActionPatch = try await api.decidePublicDocumentAction(
            token: "issued_token-1",
            decision: .approve(
                revisionNumber: 7,
                nonce: "nonce-value-123",
                contentHash: "issued-content-hash-12345",
                signerName: "Hayley Wade",
                consentVersion: "estimate-approval-v1",
                consent: true,
                optionID: "option-1"
            )
        )

        let request = try XCTUnwrap(URLProtocolFixture.recorded.first)
        XCTAssertEqual(request.url?.path, "/v1/public/document-actions/issued_token-1/approve")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.body)) as? [String: Any])
        XCTAssertEqual(json["revisionNumber"] as? Int, 7)
        XCTAssertEqual(json["nonce"] as? String, "nonce-value-123")
        XCTAssertEqual(json["contentHash"] as? String, "issued-content-hash-12345")
        XCTAssertEqual(json["signerName"] as? String, "Hayley Wade")
        XCTAssertEqual(json["consentVersion"] as? String, "estimate-approval-v1")
        XCTAssertEqual(json["consent"] as? Bool, true)
        XCTAssertEqual(json["optionId"] as? String, "option-1")
    }

    func testRejectsPathLikeActionTokensBeforeNetworkRequest() async {
        let api = APIClient(session: URLProtocolFixture.session([]), baseURL: "https://app.thorbis.com")
        do {
            let _: PublicEstimateAction = try await api.publicDocumentAction(token: "../private")
            XCTFail("Expected an invalid token to be rejected")
        } catch {}
        XCTAssertTrue(URLProtocolFixture.recorded.isEmpty)
    }

    func testPartialDecisionResponseKeepsIssuedPaperAndConsumesNonce() throws {
        let action = try JSONDecoder().decode(PublicEstimateAction.self, from: Data(actionJSON.utf8))
        let patch = try JSONDecoder().decode(PublicEstimateActionPatch.self, from: Data(#"{"status":"approved"}"#.utf8))
        let updated = action.applying(
            patch,
            after: .approvePlainly(revisionNumber: 7, nonce: "nonce-value-123")
        )

        XCTAssertEqual(updated.status, .approved)
        XCTAssertEqual(updated.html, action.html)
        XCTAssertEqual(updated.revisionNumber, action.revisionNumber)
        XCTAssertNil(updated.nonce)
    }

    func testActionModelLoadsPublicEstimateWithoutRequiringWorkspaceState() async throws {
        let api = APIClient(session: URLProtocolFixture.session([.init(200, actionJSON)]), baseURL: "https://app.thorbis.com")
        let model = PublicEstimateActionModel()

        await model.load(api: api, token: "issued_token-1")

        XCTAssertEqual(model.action?.title, "Condenser replacement")
        XCTAssertEqual(model.action?.status, .sent)
        XCTAssertNil(model.loadError)
        XCTAssertNil(model.unavailableMessage)
        XCTAssertFalse(URLProtocolFixture.recorded[0].handlesCookies)
    }

    func testTokenSwitchStartsNewLoadAndIgnoresLatePreviousResponse() async throws {
        let firstGate = URLProtocolFixture.Gate()
        let secondJSON = actionJSON.replacingOccurrences(
            of: "\"title\":\"Condenser replacement\"",
            with: "\"title\":\"Second estimate\""
        )
        let api = APIClient(session: URLProtocolFixture.session([
            .init(200, actionJSON, gate: firstGate),
            .init(200, secondJSON)
        ]), baseURL: "https://app.thorbis.com")
        let model = PublicEstimateActionModel()

        let firstLoad = Task { await model.load(api: api, token: "first-token") }
        for _ in 0..<100 where URLProtocolFixture.recorded.count < 1 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(URLProtocolFixture.recorded.first?.url?.path, "/v1/public/document-actions/first-token")

        let secondLoad = Task { await model.load(api: api, token: "second-token") }
        for _ in 0..<100 where URLProtocolFixture.recorded.count < 2 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(URLProtocolFixture.recorded.map(\.url?.path), [
            "/v1/public/document-actions/first-token",
            "/v1/public/document-actions/second-token"
        ])
        await secondLoad.value
        XCTAssertEqual(model.action?.title, "Second estimate")

        firstGate.release()
        await firstLoad.value
        XCTAssertEqual(model.action?.title, "Second estimate")
    }

    func testSwitchingTokenClearsPreviousEstimateAndCustomerDraft() async throws {
        let secondGate = URLProtocolFixture.Gate()
        let secondJSON = actionJSON.replacingOccurrences(
            of: "\"title\":\"Condenser replacement\"",
            with: "\"title\":\"Second estimate\""
        )
        let api = APIClient(session: URLProtocolFixture.session([
            .init(200, actionJSON),
            .init(200, secondJSON, gate: secondGate)
        ]), baseURL: "https://app.thorbis.com")
        let model = PublicEstimateActionModel()
        await model.load(api: api, token: "first-token")
        model.selectedOptionID = "option-1"
        model.signerName = "Hayley Wade"
        model.consent = true
        model.changeMessage = "Please clarify the model."

        let secondLoad = Task { await model.load(api: api, token: "second-token") }
        for _ in 0..<100 where URLProtocolFixture.recorded.count < 2 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertNil(model.action)
        XCTAssertNil(model.selectedOptionID)
        XCTAssertEqual(model.signerName, "")
        XCTAssertFalse(model.consent)
        XCTAssertEqual(model.changeMessage, "")

        secondGate.release()
        await secondLoad.value
        XCTAssertEqual(model.action?.title, "Second estimate")
    }

    func testDecisionResponseCannotOverwriteEstimateOpenedWhileItWasSubmitting() async throws {
        let approvalGate = URLProtocolFixture.Gate()
        let secondJSON = actionJSON.replacingOccurrences(
            of: "\"title\":\"Condenser replacement\"",
            with: "\"title\":\"Second estimate\""
        )
        let api = APIClient(session: URLProtocolFixture.session([
            .init(200, actionJSON),
            .init(200, #"{"status":"declined"}"#, gate: approvalGate),
            .init(200, secondJSON)
        ]), baseURL: "https://app.thorbis.com")
        let model = PublicEstimateActionModel()
        await model.load(api: api, token: "first-token")

        let oldDecision = Task {
            await model.submit(.decline(revisionNumber: 7, nonce: "nonce-value-123"), api: api, token: "first-token")
        }
        for _ in 0..<100 where URLProtocolFixture.recorded.count < 2 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(model.isSubmitting)

        await model.load(api: api, token: "second-token")
        XCTAssertEqual(model.action?.title, "Second estimate")
        XCTAssertFalse(model.isSubmitting)

        approvalGate.release()
        await oldDecision.value
        XCTAssertEqual(model.action?.title, "Second estimate")
        XCTAssertEqual(model.action?.status, .sent)
    }

    func testActionModelSubmitsRequestChangesAndPreservesPaperOnPartialResponse() async throws {
        let api = APIClient(session: URLProtocolFixture.session([
            .init(200, actionJSON),
            .init(200, #"{"status":"changes_requested"}"#)
        ]), baseURL: "https://app.thorbis.com")
        let model = PublicEstimateActionModel()
        await model.load(api: api, token: "issued_token-1")
        model.changeMessage = "Please clarify the condenser model."

        await model.submit(
            .requestChanges(revisionNumber: 7, nonce: "nonce-value-123", message: model.changeMessage),
            api: api,
            token: "issued_token-1"
        )

        XCTAssertEqual(model.action?.status, .changesRequested)
        XCTAssertEqual(model.action?.html, "<h1>Estimate</h1>")
        XCTAssertNil(model.action?.nonce)
        XCTAssertNil(model.actionError)
        XCTAssertEqual(model.changeMessage, "")
        XCTAssertEqual(URLProtocolFixture.recorded.map(\.url?.path), [
            "/v1/public/document-actions/issued_token-1",
            "/v1/public/document-actions/issued_token-1/request-changes"
        ])
        XCTAssertFalse(URLProtocolFixture.recorded[1].handlesCookies)
    }

    func testActionModelRejectsDecisionForOlderRevisionBeforeSending() async throws {
        let api = APIClient(session: URLProtocolFixture.session([.init(200, actionJSON)]), baseURL: "https://app.thorbis.com")
        let model = PublicEstimateActionModel()
        await model.load(api: api, token: "issued_token-1")

        await model.submit(.decline(revisionNumber: 6, nonce: "nonce-value-123"), api: api, token: "issued_token-1")

        XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
        XCTAssertNotNil(model.action)
        XCTAssertNotNil(model.actionError)
    }

    func testActionModelClearsStaleEstimateAfterConflictAndKeepsRetryableErrorInline() async throws {
        let staleAPI = APIClient(session: URLProtocolFixture.session([
            .init(200, actionJSON),
            .init(409, #"{"title":"Stale estimate","status":409,"detail":"Revision changed"}"#)
        ]), baseURL: "https://app.thorbis.com")
        let staleModel = PublicEstimateActionModel()
        await staleModel.load(api: staleAPI, token: "issued_token-1")
        await staleModel.submit(.decline(revisionNumber: 7, nonce: "nonce-value-123"), api: staleAPI, token: "issued_token-1")
        XCTAssertNil(staleModel.action)
        XCTAssertNotNil(staleModel.unavailableMessage)

        let retryableAPI = APIClient(session: URLProtocolFixture.session([
            .init(200, actionJSON),
            .init(503, #"{"title":"Service unavailable","status":503,"detail":"Try again."}"#)
        ]), baseURL: "https://app.thorbis.com")
        let retryableModel = PublicEstimateActionModel()
        await retryableModel.load(api: retryableAPI, token: "issued_token-1")
        await retryableModel.submit(.decline(revisionNumber: 7, nonce: "nonce-value-123"), api: retryableAPI, token: "issued_token-1")
        XCTAssertEqual(retryableModel.action?.status, .sent)
        XCTAssertEqual(retryableModel.actionError, "Try again.")
        XCTAssertNil(retryableModel.unavailableMessage)
    }

    private func makeAction(
        options: String,
        signed: Bool = true,
        plain: Bool = true,
        scope: String = #"[{"id":"line-1","description":"Replace condenser","quantity":1,"unitPrice":4200}]"#
    ) throws -> PublicEstimateAction {
        var json = actionJSON
            .replacingOccurrences(of: "\"options\":[]", with: "\"options\":\(options)")
            .replacingOccurrences(of: "\"scopeLines\":[]", with: "\"scopeLines\":\(scope)")
            .replacingOccurrences(of: "\"approvalWithoutSignatureAllowed\":true", with: "\"approvalWithoutSignatureAllowed\":\(plain)")
        if !signed {
            json = json.replacingOccurrences(of: ",\"consentVersion\":\"estimate-approval-v1\",\"consentText\":\"I approve this estimate.\"", with: "")
        }
        return try JSONDecoder().decode(PublicEstimateAction.self, from: Data(json.utf8))
    }

    private var actionJSON: String {
        #"{"kind":"estimate","title":"Condenser replacement","status":"sent","revisionNumber":7,"contentHash":"issued-content-hash-12345","allowedActions":["approve","decline","request_changes"],"nonce":"nonce-value-123","totalAmount":4200,"currency":"USD","html":"<h1>Estimate</h1>","approvalWithoutSignatureAllowed":true,"scopeLines":[],"options":[],"consentVersion":"estimate-approval-v1","consentText":"I approve this estimate."}"#
    }
}

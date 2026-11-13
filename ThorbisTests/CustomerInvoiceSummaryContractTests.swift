import XCTest
import CryptoKit
@testable import Thorbis

@MainActor
private final class FailingSummaryPendingStore: CustomerSummaryPendingStoring {
    enum Failure: Error { case write }
    func load(scope: CustomerSummaryPendingScope) throws -> CustomerSummaryPendingAttempt? { nil }
    func loadForRecovery(scope: CustomerSummaryPendingScope) throws -> CustomerSummaryPendingAttempt? { nil }
    func insert(_ pending: CustomerSummaryPendingAttempt) throws { throw Failure.write }
    func complete(scope: CustomerSummaryPendingScope, proof: CustomerSummaryReplayProof, currentAuthority: @MainActor () -> Bool) throws { XCTFail("Unexpected completion") }
}

@MainActor
final class CustomerInvoiceSummaryContractTests: XCTestCase {
    private let scope = JobDocumentScope(jobID: "job-1", organizationID: "org-1", customerID: "customer-1")
    private func decode(_ changes: [String: Any] = [:]) throws -> CustomerInvoiceSummary {
        var payload: [String: Any] = [
            "kind": "customer_invoice_presentation", "presentationVersion": 1,
            "presentationScopeId": "invoice:invoice-1:lines:2:customer:v1", "isSignedDocument": false,
            "issuedSnapshotId": "00000000-0000-4000-8000-000000000001", "organizationId": "org-1", "customerId": "customer-1",
            "invoiceId": "invoice-1", "jobId": "job-1", "linesRevision": 2,
            "status": "issued", "currency": "USD", "totalAmount": 10000, "amountPaid": 2500,
            "balanceDue": 7500, "lines": [["id": "line-1", "description": "Materials", "quantity": 1,
                                              "unitPrice": ["amount": 10000, "currency": "USD"]]]
        ]
        changes.forEach { payload[$0.key] = $0.value }
        return try JSONDecoder().decode(CustomerInvoiceSummary.self, from: JSONSerialization.data(withJSONObject: payload))
    }
    func testAcceptsOnlyMatchingUnsignedScopedPresentationWithReconciledAmounts() throws {
        XCTAssertTrue(try decode().matches(scope: scope, invoiceID: "invoice-1", linesRevision: 2))
        for override in [["organizationId": "other"], ["customerId": "other"], ["jobId": "other"],
                         ["invoiceId": "other"], ["linesRevision": 3], ["presentationVersion": 2],
                         ["kind": "invoice"], ["isSignedDocument": true], ["issuedSnapshotId": NSNull()], ["issuedSnapshotId": "invalid"],
                         ["totalAmount": 1], ["balanceDue": 1], ["currency": "EUR"]] as [[String: Any]] {
            XCTAssertFalse(try decode(override).matches(scope: scope, invoiceID: "invoice-1", linesRevision: 2))
        }
        XCTAssertFalse(try decode(["status": "draft", "amountPaid": 0, "balanceDue": 10000]).matches(scope: scope, invoiceID: "invoice-1", linesRevision: 2))
        XCTAssertFalse(try decode(["status": "paid", "totalAmount": 0, "amountPaid": 0, "balanceDue": 0, "lines": []]).matches(scope: scope, invoiceID: "invoice-1", linesRevision: 2))
        XCTAssertFalse(try decode(["status": "issued", "amountPaid": 10000, "balanceDue": 0]).matches(scope: scope, invoiceID: "invoice-1", linesRevision: 2))
    }
    func testConsentAndSignedSummaryReceiptMatchOnlyTheShownTerms() async throws {
        let digest = "sha256:" + String(repeating: "a", count: 64)
        let version = "invoice-summary-consent-v1"
        let text = "I approve the customer invoice summary shown above. Payment status is not part of this authorization."
        let consent: [String: Any] = ["digest": digest, "consentVersion": version, "consentText": text]
        let organization = "00000000-0000-4000-8000-000000000011"
        let customer = "00000000-0000-4000-8000-000000000012"
        let job = "00000000-0000-4000-8000-000000000013"
        let invoice = "00000000-0000-4000-8000-000000000014"
        let line = "00000000-0000-4000-8000-000000000015"
        let fields: [String: Any] = ["organizationId": organization, "customerId": customer, "jobId": job, "invoiceId": invoice,
            "presentationScopeId": "invoice:\(invoice):lines:2:customer:v1", "summaryConsent": consent,
            "lines": [["id": line, "description": "Materials", "quantity": 1, "unitPrice": ["amount": 10000, "currency": "USD"]]]]
        let summary = try decode(fields)
        XCTAssertNotNil(summary.validatedConsent)
        var unknown = fields; unknown["summaryConsent"] = ["digest": digest, "consentVersion": "v2", "consentText": text]
        XCTAssertNil(try decode(unknown).validatedConsent)
        unknown["summaryConsent"] = ["digest": "sha256:" + String(repeating: "A", count: 64), "consentVersion": version, "consentText": text]
        XCTAssertNil(try decode(unknown).validatedConsent)
        unknown["summaryConsent"] = ["digest": digest, "consentVersion": version, "consentText": "Different consent"]
        XCTAssertNil(try decode(unknown).validatedConsent)
        var receipt: [String: Any] = ["kind": "signed_customer_invoice_summary", "id": "00000000-0000-4000-8000-000000000010",
            "organizationId": organization, "customerId": customer, "jobId": job, "invoiceId": invoice,
            "linesRevision": 2, "issuedSnapshotId": "00000000-0000-4000-8000-000000000001", "digest": digest,
            "consentVersion": version, "consentText": text, "signerName": "Alex", "signedAt": "2026-11-13T12:00:00Z",
            "recordedAt": "2026-11-13T12:00:01Z", "currency": "USD", "totalAmount": 10000,
            "lines": [["id": line, "description": "Materials", "quantity": 1, "unitPrice": ["amount": 10000, "currency": "USD"]]]]
        func decoded() throws -> CustomerInvoiceSummaryReceipt { try JSONDecoder().decode(CustomerInvoiceSummaryReceipt.self, from: JSONSerialization.data(withJSONObject: receipt)) }
        XCTAssertTrue(try decoded().matches(summary: summary, signerName: "Alex", signedAt: "2026-11-13T12:00:00Z"))
        XCTAssertFalse(try decoded().matches(summary: summary, signerName: "Other", signedAt: "2026-11-13T12:00:00Z"))
        XCTAssertFalse(try decoded().matches(summary: summary, signerName: "Alex", signedAt: "2026-11-13T12:00:01Z"))
        receipt["signedAt"] = "2026-11-13T12:00:00.000Z"
        XCTAssertTrue(try decoded().matches(summary: summary, signerName: "Alex", signedAt: "2026-11-13T12:00:00Z"))
        receipt["signedAt"] = "2026-11-13T12:00:00Z"
        var handoffCurrent = true
        let handoff = CustomerSummarySigningContext(summary: summary, actorID: "00000000-0000-4000-8000-000000000025", current: { handoffCurrent })
        let boundary = CustomerSummarySigningContext(summary: summary, actorID: "00000000-0000-4000-8000-000000000025", current: { true })
        XCTAssertThrowsError(try boundary.freeze(signerName: "Alex", signedAt: "2026-11-13T12:00:00Z", png: Data(repeating: 1, count: 512 * 1024 + 1))) { error in
            XCTAssertEqual((error as? Problem)?.title, "Signature is too large. Clear it and sign again.")
        }
        let maximum = try boundary.freeze(signerName: "Alex", signedAt: "2026-11-13T12:00:00Z", png: Data(repeating: 1, count: 512 * 1024))
        XCTAssertEqual(maximum.png.count, 512 * 1024)
        XCTAssertThrowsError(try boundary.freeze(signerName: "Alex", signedAt: maximum.signedAt, png: Data(repeating: 1, count: 512 * 1024 + 1)))
        XCTAssertEqual(try boundary.signature().idempotencyKey, maximum.idempotencyKey, "An oversized retry cannot erase a frozen attempt")
        let signature = try handoff.freeze(signerName: " Alex ", signedAt: "2026-11-13T12:00:00Z", png: Data([1, 2, 3]))
        XCTAssertEqual(try handoff.freeze(signerName: "Alex", signedAt: signature.signedAt, png: signature.png), signature)
        XCTAssertThrowsError(try handoff.freeze(signerName: "Alex", signedAt: signature.signedAt, png: Data([4])))
        XCTAssertThrowsError(try handoff.attempt())
        var assetJSON: [String: Any] = ["id": "00000000-0000-4000-8000-000000000020", "organizationId": organization,
            "jobId": job, "uploaderUserId": "00000000-0000-4000-8000-000000000025", "kind": "photo", "mime": "image/png",
            "sizeBytes": signature.png.count, "originalFilename": "signature.png",
            "contentHash": SHA256.hash(data: signature.png).map { String(format: "%02x", $0) }.joined(),
            "storageKey": "preview", "uploadState": "stored", "tags": ["signature"], "archived": false,
            "createdAt": signature.signedAt, "updatedAt": signature.signedAt]
        func media() throws -> MediaAssetRecord { try JSONDecoder().decode(MediaAssetRecord.self, from: JSONSerialization.data(withJSONObject: assetJSON)) }
        try handoff.acceptUploadedMedia(media())
        let frozenAttempt = try handoff.attempt()
        XCTAssertEqual(frozenAttempt.idempotencyKey, signature.idempotencyKey)
        XCTAssertEqual(try handoff.attempt().imageMediaId, frozenAttempt.imageMediaId)
        assetJSON["id"] = "00000000-0000-4000-8000-000000000022"
        XCTAssertThrowsError(try handoff.acceptUploadedMedia(media()))
        assetJSON["jobId"] = "00000000-0000-4000-8000-000000000099"
        XCTAssertThrowsError(try handoff.acceptUploadedMedia(media()))
        let validReceipt = try decoded()
        assetJSON["id"] = "00000000-0000-4000-8000-000000000020"; assetJSON["jobId"] = job
        let validAsset = try media()
        var uploadCount = 0; var attempts: [CustomerSummarySigningAttempt] = []
        let coordinator = CustomerSummarySigningCoordinator(summary: summary, actorID: "00000000-0000-4000-8000-000000000025", current: { true },
            lookup: { .unsigned }, upload: { _ in uploadCount += 1; return validAsset }, submit: { value in
                attempts.append(value)
                if attempts.count == 1 { throw URLError(.networkConnectionLost) }
                return validReceipt
            })
        await coordinator.checkStatus(); XCTAssertEqual(coordinator.phase, .unsigned)
        await coordinator.sign(signerName: "Alex", signedAt: "2026-11-13T12:00:00Z", png: Data(repeating: 1, count: 512 * 1024 + 1))
        XCTAssertEqual(coordinator.phase, .unsigned); XCTAssertFalse(coordinator.hasFrozenSignature)
        XCTAssertEqual(coordinator.errorMessage, "Signature is too large. Clear it and sign again.")
        XCTAssertEqual(uploadCount, 0)
        await coordinator.sign(signerName: "Alex", signedAt: "2026-11-13T12:00:00Z", png: Data([1, 2, 3]))
        XCTAssertEqual(coordinator.phase, .unavailable); XCTAssertTrue(coordinator.hasFrozenSignature)
        await coordinator.retryFrozen(); XCTAssertEqual(attempts.count, 1, "An uncertain result requires a fresh status check")
        await coordinator.checkStatus(); XCTAssertEqual(coordinator.phase, .unsigned)
        await coordinator.retryFrozen()
        XCTAssertEqual(coordinator.phase, .signed); XCTAssertEqual(uploadCount, 1)
        XCTAssertEqual(attempts.count, 2); XCTAssertEqual(attempts[0].idempotencyKey, attempts[1].idempotencyKey)
        XCTAssertEqual(attempts[0].imageMediaId, attempts[1].imageMediaId)
        var pending: CheckedContinuation<Void, Never>?
        let retiredCoordinator = CustomerSummarySigningCoordinator(summary: summary, actorID: "00000000-0000-4000-8000-000000000025", current: { true },
            lookup: { await withCheckedContinuation { pending = $0 }; return .signed(validReceipt) },
            upload: { _ in validAsset }, submit: { _ in validReceipt })
        let check = Task { @MainActor in await retiredCoordinator.checkStatus() }
        for _ in 0..<100 where pending == nil { await Task.yield() }
        XCTAssertNotNil(pending); retiredCoordinator.retire(); pending?.resume(); await check.value
        XCTAssertEqual(retiredCoordinator.phase, .idle); XCTAssertNil(retiredCoordinator.receipt)
        var suspendedSubmission: CheckedContinuation<Void, Never>?
        var suspendedAttempts: [CustomerSummarySigningAttempt] = []
        let suspended = CustomerSummarySigningCoordinator(summary: summary, actorID: "00000000-0000-4000-8000-000000000025", current: { true },
            lookup: { .unsigned }, upload: { _ in validAsset }, submit: { value in
                suspendedAttempts.append(value)
                if suspendedAttempts.count == 1 { await withCheckedContinuation { suspendedSubmission = $0 } }
                return validReceipt
            })
        await suspended.checkStatus()
        let originalSubmission = Task { @MainActor in await suspended.sign(signerName: "Alex", signedAt: "2026-11-13T12:00:00Z", png: Data([1, 2, 3])) }
        for _ in 0..<100 where suspendedSubmission == nil { await Task.yield() }
        XCTAssertNotNil(suspendedSubmission); suspended.deactivate()
        await suspended.checkStatus(); XCTAssertEqual(suspended.phase, .unsigned)
        suspendedSubmission?.resume(); await originalSubmission.value
        XCTAssertEqual(suspended.phase, .unsigned, "A response from the previous activation must not publish")
        await suspended.retryFrozen(); XCTAssertEqual(suspended.phase, .signed)
        XCTAssertEqual(suspendedAttempts.count, 2)
        XCTAssertEqual(suspendedAttempts[0].idempotencyKey, suspendedAttempts[1].idempotencyKey)
        handoffCurrent = false
        XCTAssertThrowsError(try handoff.attempt())
        handoff.retire(); handoffCurrent = true
        XCTAssertThrowsError(try handoff.attempt())
        let attempt = try XCTUnwrap(CustomerSummarySigningAttempt(summary: summary, signerName: "Alex", signedAt: "2026-11-13T12:00:00Z", imageMediaId: "00000000-0000-4000-8000-000000000020", idempotencyKey: "00000000-0000-4000-8000-000000000021"))
        let pendingScope = CustomerSummaryPendingScope(origin: "https://app.thorbis.com", actorID: UUID().uuidString.lowercased(), organizationID: organization, customerID: customer, jobID: job, invoiceID: invoice)
        let pendingAttempt = CustomerSummaryPendingAttempt(scope: pendingScope, summary: summary, attempt: attempt)
        XCTAssertTrue(pendingAttempt.isValid(for: pendingScope)); XCTAssertTrue(pendingAttempt.matches(validReceipt))
        let encodedPending = try JSONEncoder().encode(pendingAttempt)
        XCTAssertFalse(String(decoding: encodedPending, as: UTF8.self).contains("png"), "Recovery must not persist signature ink")
        let restored = try JSONDecoder().decode(CustomerSummaryPendingAttempt.self, from: encodedPending)
        XCTAssertTrue(restored.isValid(for: pendingScope)); XCTAssertEqual(restored.attempt.idempotencyKey, attempt.idempotencyKey)
        let otherActor = CustomerSummaryPendingScope(origin: pendingScope.origin, actorID: "00000000-0000-4000-8000-000000000026", organizationID: organization, customerID: customer, jobID: job, invoiceID: invoice)
        XCTAssertFalse(restored.isValid(for: otherActor))
        let otherOrigin = CustomerSummaryPendingScope(origin: "https://other.example", actorID: pendingScope.actorID, organizationID: organization, customerID: customer, jobID: job, invoiceID: invoice)
        XCTAssertFalse(restored.isValid(for: otherOrigin))
        var invalidPending = try XCTUnwrap(JSONSerialization.jsonObject(with: encodedPending) as? [String: Any])
        var invalidAttempt = try XCTUnwrap(invalidPending["attempt"] as? [String: Any]); invalidAttempt["consent"] = false; invalidPending["attempt"] = invalidAttempt
        let invalid = try JSONDecoder().decode(CustomerSummaryPendingAttempt.self, from: JSONSerialization.data(withJSONObject: invalidPending))
        XCTAssertFalse(invalid.isValid(for: pendingScope))
        let replayPayload = String(decoding: try JSONSerialization.data(withJSONObject: receipt), as: UTF8.self)
        let replayAPI = APIClient(session: URLProtocolFixture.session([.init(201, replayPayload)]), baseURL: "https://app.thorbis.com")
        let proof = try await replayAPI.replayCustomerSummaryPending(restored, scope: pendingScope, currentAuthority: { true })
        XCTAssertEqual(proof.receipt.id, validReceipt.id)
        let store = KeychainCustomerSummaryPendingStore()
        XCTAssertNil(try store.load(scope: pendingScope))
        try store.insert(restored)
        XCTAssertThrowsError(try store.insert(restored), "An unresolved record cannot be overwritten")
        let equivalent = CustomerSummaryPendingScope(origin: "https://APP.THORBIS.COM/", actorID: pendingScope.actorID.uppercased(), organizationID: organization.uppercased(), customerID: customer.uppercased(), jobID: job.uppercased(), invoiceID: invoice.uppercased())
        XCTAssertTrue(restored.isValid(for: equivalent))
        XCTAssertNotNil(try store.load(scope: equivalent))
        let duplicateEquivalent = CustomerSummaryPendingAttempt(scope: equivalent, summary: summary, attempt: attempt)
        XCTAssertThrowsError(try store.insert(duplicateEquivalent), "Equivalent spelling must not evade the pending guard")
        for bad in ["https://app.thorbis.com.evil/", "https://user@app.thorbis.com", "https://app.thorbis.com/path", "http://app.thorbis.com"] {
            let invalidOrigin = CustomerSummaryPendingScope(origin: bad, actorID: pendingScope.actorID, organizationID: organization, customerID: customer, jobID: job, invoiceID: invoice)
            XCTAssertFalse(invalidOrigin.isValid); XCTAssertThrowsError(try store.load(scope: invalidOrigin))
        }
        XCTAssertNotNil(try store.load(scope: pendingScope))
        let missingMediaAPI = APIClient(session: URLProtocolFixture.session([.init(409, "{\"title\":\"Signature image is unavailable\"}")]), baseURL: "https://app.thorbis.com")
        do { _ = try await missingMediaAPI.replayCustomerSummaryPending(restored, scope: pendingScope, currentAuthority: { true }); XCTFail("Missing media cannot prove a prior submission failed") } catch { }
        XCTAssertNotNil(try store.load(scope: pendingScope), "An ambiguous conflict must retain the pending attempt")
        let changedJob = CustomerSummaryPendingScope(origin: pendingScope.origin, actorID: pendingScope.actorID, organizationID: organization, customerID: customer, jobID: "00000000-0000-4000-8000-000000000099", invoiceID: invoice)
        XCTAssertThrowsError(try store.load(scope: changedJob), "Current-document reads must not display an old job's terms")
        let oldForRecovery = try XCTUnwrap(store.loadForRecovery(scope: changedJob))
        XCTAssertEqual(oldForRecovery.scope.jobID, job); XCTAssertEqual(oldForRecovery.attempt.idempotencyKey, attempt.idempotencyKey)
        XCTAssertNil(try store.loadForRecovery(scope: otherActor), "A different actor cannot access this pending attempt")
        let changedLinkAPI = APIClient(session: URLProtocolFixture.session([.init(404, "{}")]), baseURL: "https://app.thorbis.com")
        do { _ = try await changedLinkAPI.replayCustomerSummaryPending(oldForRecovery, scope: oldForRecovery.scope, currentAuthority: { true }); XCTFail("The held backend currently refuses changed-link replay") } catch { }
        XCTAssertNotNil(try store.loadForRecovery(scope: changedJob), "A 404 must retain the original pending attempt")
        XCTAssertThrowsError(try store.complete(scope: pendingScope, proof: proof, currentAuthority: { false }))
        XCTAssertNotNil(try store.load(scope: pendingScope))
        try store.complete(scope: pendingScope, proof: proof, currentAuthority: { true })
        XCTAssertNil(try store.load(scope: pendingScope))
        // Losing the first POST and recreating the handoff cannot generate a second key.
        assetJSON["id"] = "00000000-0000-4000-8000-000000000020"; assetJSON["jobId"] = job; assetJSON["uploaderUserId"] = pendingScope.actorID
        let durableAsset = try media()
        let failedAPI = APIClient(session: URLProtocolFixture.session([URLProtocolFixture.offline]), baseURL: "https://app.thorbis.com")
        var lookupCalls = 0
        let firstOwner = CustomerSummaryDurableCoordinator(summary: summary, scope: pendingScope, store: store, current: { true },
            lookup: { lookupCalls += 1; return .unsigned }, upload: { _ in durableAsset }, replay: { pending in
                XCTAssertNotNil(try store.load(scope: pendingScope), "Pending terms must be saved before POST")
                return try await failedAPI.replayCustomerSummaryPending(pending, scope: pendingScope, currentAuthority: { true })
            })
        await firstOwner.inspect(); XCTAssertEqual(firstOwner.phase, .ready)
        await firstOwner.sign(signerName: "Alex", signedAt: "2026-11-13T12:00:00Z", png: Data([1, 2, 3]))
        XCTAssertEqual(firstOwner.phase, .needsRecovery); XCTAssertNotNil(try store.load(scope: pendingScope))
        let firstBody = try XCTUnwrap(URLProtocolFixture.recorded.first?.body)
        firstOwner.retire()
        let recoveredAPI = APIClient(session: URLProtocolFixture.session([.init(201, replayPayload)]), baseURL: "https://app.thorbis.com")
        let nextOwner = CustomerSummaryDurableCoordinator(summary: summary, scope: pendingScope, store: store, current: { true },
            lookup: { lookupCalls += 1; return .unsigned }, upload: { _ in durableAsset }, replay: { pending in
                try await recoveredAPI.replayCustomerSummaryPending(pending, scope: pendingScope, currentAuthority: { true })
            })
        await nextOwner.inspect(); XCTAssertEqual(nextOwner.phase, .needsRecovery); XCTAssertEqual(lookupCalls, 1)
        await nextOwner.recover(); XCTAssertEqual(nextOwner.phase, .signed); XCTAssertNil(try store.load(scope: pendingScope))
        let replayBody = try XCTUnwrap(URLProtocolFixture.recorded.first?.body)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: firstBody) as? NSDictionary, try JSONSerialization.jsonObject(with: replayBody) as? NSDictionary)
        var attemptedAssets: [String] = []
        let uploadAPI = APIClient(session: URLProtocolFixture.session([.init(201, replayPayload)]), baseURL: "https://app.thorbis.com")
        let uploadOwner = CustomerSummaryDurableCoordinator(summary: summary, scope: pendingScope, store: store, current: { true },
            lookup: { .unsigned }, upload: { signature in
                attemptedAssets.append(signature.clientAssetID)
                if attemptedAssets.count == 1 { throw URLError(.networkConnectionLost) }
                return durableAsset
            }, replay: { pending in try await uploadAPI.replayCustomerSummaryPending(pending, scope: pendingScope, currentAuthority: { true }) })
        await uploadOwner.inspect()
        await uploadOwner.sign(signerName: "Alex", signedAt: "2026-11-13T12:00:00Z", png: Data([1, 2, 3]))
        XCTAssertEqual(uploadOwner.phase, .ready); XCTAssertTrue(uploadOwner.hasFrozenSignature)
        XCTAssertNil(try store.load(scope: pendingScope), "No financial POST starts before upload is confirmed")
        await uploadOwner.retryCapture(); XCTAssertEqual(uploadOwner.phase, .signed)
        XCTAssertEqual(attemptedAssets.count, 2); XCTAssertEqual(attemptedAssets[0], attemptedAssets[1])
        // A receipt for the old revision is resolved, but never displayed as the new revision's signature.
        try store.insert(restored)
        var changedFields = fields; changedFields["linesRevision"] = 3
        changedFields["presentationScopeId"] = "invoice:\(invoice):lines:3:customer:v1"
        changedFields["summaryConsent"] = ["digest": "sha256:" + String(repeating: "b", count: 64), "consentVersion": version, "consentText": text]
        let changedSummary = try decode(changedFields)
        let oldAPI = APIClient(session: URLProtocolFixture.session([.init(201, replayPayload)]), baseURL: "https://app.thorbis.com")
        let changedOwner = CustomerSummaryDurableCoordinator(summary: changedSummary, scope: pendingScope, store: store, current: { true },
            lookup: { .unsigned }, upload: { _ in durableAsset }, replay: { pending in try await oldAPI.replayCustomerSummaryPending(pending, scope: pendingScope, currentAuthority: { true }) })
        await changedOwner.inspect(); XCTAssertEqual(changedOwner.phase, .needsRecovery)
        await changedOwner.recover(); XCTAssertEqual(changedOwner.phase, .previousResolved)
        XCTAssertNil(changedOwner.receipt); XCTAssertNil(try store.load(scope: pendingScope))
        var shouldNotPost = false
        let failingOwner = CustomerSummaryDurableCoordinator(summary: summary, scope: pendingScope, store: FailingSummaryPendingStore(), current: { true },
            lookup: { .unsigned }, upload: { _ in durableAsset }, replay: { _ in shouldNotPost = true; throw URLError(.cannotConnectToHost) })
        await failingOwner.inspect(); await failingOwner.sign(signerName: "Alex", signedAt: "2026-11-13T12:00:00Z", png: Data([1, 2, 3]))
        XCTAssertEqual(failingOwner.phase, .unavailable); XCTAssertFalse(shouldNotPost, "Storage failure must block POST")
        var waitingLookup: CheckedContinuation<CustomerSummaryAuthorizationState, Never>?
        let racingOwner = CustomerSummaryDurableCoordinator(summary: summary, scope: pendingScope, store: store, current: { true },
            lookup: { await withCheckedContinuation { waitingLookup = $0 } }, upload: { _ in durableAsset }, replay: { _ in throw URLError(.notConnectedToInternet) })
        let race = Task { @MainActor in await racingOwner.inspect() }
        for _ in 0..<100 where waitingLookup == nil { await Task.yield() }
        XCTAssertNotNil(waitingLookup); try store.insert(restored)
        waitingLookup?.resume(returning: .unsigned); await race.value
        XCTAssertEqual(racingOwner.phase, .needsRecovery, "A pending write racing an unsigned lookup must block new signing")
        let newJobID = "00000000-0000-4000-8000-000000000099"
        let currentScope = CustomerSummaryPendingScope(origin: pendingScope.origin, actorID: pendingScope.actorID,
            organizationID: organization, customerID: customer, jobID: newJobID, invoiceID: invoice)
        var newJobFields = fields; newJobFields["jobId"] = newJobID
        let newJobSummary = try decode(newJobFields)
        let changedLinkAPI2 = APIClient(session: URLProtocolFixture.session([.init(404, "{}")]), baseURL: "https://app.thorbis.com")
        let changedLinkOwner = CustomerSummaryDurableCoordinator(summary: newJobSummary, scope: currentScope, store: store, current: { true },
            lookup: { XCTFail("Old pending attempt must block current unsigned lookup"); return .unsigned }, upload: { _ in durableAsset },
            replay: { pending in try await changedLinkAPI2.replayCustomerSummaryPending(pending, scope: pending.scope, currentAuthority: { true }) })
        await changedLinkOwner.inspect(); XCTAssertEqual(changedLinkOwner.phase, .needsRecovery)
        await changedLinkOwner.recover(); XCTAssertEqual(changedLinkOwner.phase, .needsRecovery)
        XCTAssertNil(changedLinkOwner.receipt); XCTAssertNotNil(try store.loadForRecovery(scope: currentScope))
        try store.complete(scope: pendingScope, proof: proof, currentAuthority: { true })
        // A stale onDisappear must not retire a newly reopened destination.
        let authority = CustomerHandoffExitAuthority(actor: pendingScope.actorID, organization: organization, origin: pendingScope.origin,
            sessionGeneration: UUID(), authorityRevision: UUID(), requestGeneration: UUID(), scopeRevision: UUID())
        let key = try XCTUnwrap(CustomerSummaryHandoffKey(summary: summary, scope: pendingScope, authority: authority))
        let registry = CustomerSummaryHandoffRegistry()
        var live = true; var checks = 0; var delayedLookup: CheckedContinuation<CustomerSummaryAuthorizationState, Never>?
        func make(_ current: @escaping @MainActor () -> Bool) -> CustomerSummaryDurableCoordinator {
            CustomerSummaryDurableCoordinator(summary: summary, scope: pendingScope, store: store, current: current,
                lookup: { checks += 1; if checks == 1 { return await withCheckedContinuation { delayedLookup = $0 } }; return .unsigned },
                upload: { _ in durableAsset }, replay: { _ in throw URLError(.notConnectedToInternet) })
        }
        let firstActivation = try XCTUnwrap(registry.activate(key: key, authorityCurrent: { live }, make: make))
        let oldLookup = Task { @MainActor in await firstActivation.coordinator.inspect() }
        for _ in 0..<100 where delayedLookup == nil { await Task.yield() }
        XCTAssertNotNil(delayedLookup)
        let secondActivation = try XCTUnwrap(registry.activate(key: key, authorityCurrent: { live }, make: make))
        XCTAssertTrue(firstActivation.coordinator === secondActivation.coordinator)
        await secondActivation.coordinator.inspect(); XCTAssertEqual(secondActivation.coordinator.phase, .ready)
        registry.deactivate(firstActivation.token)
        delayedLookup?.resume(returning: .unsigned); await oldLookup.value
        XCTAssertEqual(secondActivation.coordinator.phase, .ready)
        live = false; await secondActivation.coordinator.inspect()
        XCTAssertEqual(secondActivation.coordinator.phase, .unavailable, "Revoked authority must hide signing state")
        registry.deactivate(secondActivation.token); registry.retire()
        XCTAssertNil(registry.activate(key: key, authorityCurrent: { true }, make: make))
        // Leaving during upload must not advance to POST, and reopening retries the same capture.
        var uploadWait: CheckedContinuation<Void, Never>?; var assetIDs: [String] = []
        let uploadRegistry = CustomerSummaryHandoffRegistry()
        let uploadAPI2 = APIClient(session: URLProtocolFixture.session([.init(201, replayPayload)]), baseURL: "https://app.thorbis.com")
        func makeUploading(_ current: @escaping @MainActor () -> Bool) -> CustomerSummaryDurableCoordinator {
            CustomerSummaryDurableCoordinator(summary: summary, scope: pendingScope, store: store, current: current, lookup: { .unsigned },
                upload: { signature in
                    assetIDs.append(signature.clientAssetID)
                    if assetIDs.count == 1 { await withCheckedContinuation { uploadWait = $0 } }
                    return durableAsset
                }, replay: { pending in try await uploadAPI2.replayCustomerSummaryPending(pending, scope: pendingScope, currentAuthority: current) })
        }
        let uploadFirst = try XCTUnwrap(uploadRegistry.activate(key: key, authorityCurrent: { true }, make: makeUploading))
        await uploadFirst.coordinator.inspect()
        let uploadTask = Task { @MainActor in await uploadFirst.coordinator.sign(signerName: "Alex", signedAt: "2026-11-13T12:00:00Z", png: Data([1, 2, 3])) }
        for _ in 0..<100 where uploadWait == nil { await Task.yield() }
        XCTAssertNotNil(uploadWait); uploadRegistry.deactivate(uploadFirst.token)
        let uploadSecond = try XCTUnwrap(uploadRegistry.activate(key: key, authorityCurrent: { true }, make: makeUploading))
        await uploadSecond.coordinator.inspect(); uploadWait?.resume(); await uploadTask.value
        XCTAssertEqual(uploadSecond.coordinator.phase, .ready); XCTAssertTrue(URLProtocolFixture.recorded.isEmpty)
        await uploadSecond.coordinator.retryCapture()
        XCTAssertEqual(uploadSecond.coordinator.phase, .signed); XCTAssertEqual(assetIDs.count, 2); XCTAssertEqual(assetIDs[0], assetIDs[1])
        uploadRegistry.retire()
        // An in-flight POST persists across navigation and can only be recovered with the original key.
        let postGate = URLProtocolFixture.Gate(); defer { postGate.release() }
        let postAPI = APIClient(session: URLProtocolFixture.session([.init(201, replayPayload, gate: postGate), .init(201, replayPayload)]), baseURL: "https://app.thorbis.com")
        let postRegistry = CustomerSummaryHandoffRegistry()
        func makePosting(_ current: @escaping @MainActor () -> Bool) -> CustomerSummaryDurableCoordinator {
            CustomerSummaryDurableCoordinator(summary: summary, scope: pendingScope, store: store, current: current, lookup: { .unsigned },
                upload: { _ in durableAsset }, replay: { pending in try await postAPI.replayCustomerSummaryPending(pending, scope: pendingScope, currentAuthority: current) })
        }
        let postFirst = try XCTUnwrap(postRegistry.activate(key: key, authorityCurrent: { true }, make: makePosting))
        await postFirst.coordinator.inspect()
        let postTask = Task { @MainActor in await postFirst.coordinator.sign(signerName: "Alex", signedAt: "2026-11-13T12:00:00Z", png: Data([1, 2, 3])) }
        for _ in 0..<1500 where URLProtocolFixture.recorded.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1); postRegistry.deactivate(postFirst.token)
        let postSecond = try XCTUnwrap(postRegistry.activate(key: key, authorityCurrent: { true }, make: makePosting))
        await postSecond.coordinator.inspect(); XCTAssertEqual(postSecond.coordinator.phase, .needsRecovery)
        postGate.release(); await postTask.value
        XCTAssertNotNil(try store.load(scope: pendingScope)); XCTAssertEqual(postSecond.coordinator.phase, .needsRecovery)
        await postSecond.coordinator.recover(); XCTAssertEqual(postSecond.coordinator.phase, .signed); XCTAssertNil(try store.load(scope: pendingScope))
        let postBodies = try URLProtocolFixture.recorded.map { try XCTUnwrap($0.body) }
        XCTAssertEqual(postBodies.count, 2)
        if postBodies.count == 2 { XCTAssertEqual(try JSONSerialization.jsonObject(with: postBodies[0]) as? NSDictionary, try JSONSerialization.jsonObject(with: postBodies[1]) as? NSDictionary) }
        postRegistry.retire()
        let receiptJSON = String(decoding: try JSONSerialization.data(withJSONObject: receipt), as: UTF8.self)
        let api = APIClient(session: URLProtocolFixture.session([.init(201, receiptJSON), .init(201, receiptJSON)]), baseURL: "https://app.thorbis.com")
        _ = try await api.authorizeCustomerInvoiceSummary(summary, attempt: attempt, currentAuthority: { true })
        _ = try await api.authorizeCustomerInvoiceSummary(summary, attempt: attempt, currentAuthority: { true })
        XCTAssertEqual(URLProtocolFixture.recorded.map(\.method), ["POST", "POST"])
        let bodies = try URLProtocolFixture.recorded.map { try XCTUnwrap($0.body) }
        XCTAssertEqual(try JSONSerialization.jsonObject(with: bodies[0]) as? NSDictionary, try JSONSerialization.jsonObject(with: bodies[1]) as? NSDictionary)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodies[0]) as? [String: Any])
        XCTAssertEqual(body["consentDigest"] as? String, digest)
        XCTAssertEqual(body["idempotencyKey"] as? String, "00000000-0000-4000-8000-000000000021")
        XCTAssertEqual(body["consent"] as? Bool, true)
        let signedJSON = String(decoding: try JSONSerialization.data(withJSONObject: ["status": "signed", "receipt": receipt]), as: UTF8.self)
        var wrongReceipt = receipt; wrongReceipt["jobId"] = "00000000-0000-4000-8000-000000000099"
        let wrongJSON = String(decoding: try JSONSerialization.data(withJSONObject: ["status": "signed", "receipt": wrongReceipt]), as: UTF8.self)
        let lookup = APIClient(session: URLProtocolFixture.session([.init(200, signedJSON), .init(200, "{\"status\":\"unsigned\"}"), .init(404, "{}"), .init(200, wrongJSON), .init(403, "{}"), .init(200, "{\"status\":\"unknown\"}")]), baseURL: "https://app.thorbis.com")
        guard case .signed = try await lookup.currentCustomerSummaryAuthorization(summary, currentAuthority: { true }) else { return XCTFail("Expected matching signed receipt") }
        let lookupURL = try XCTUnwrap(URLProtocolFixture.recorded.last?.url)
        XCTAssertEqual(URLComponents(url: lookupURL, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, digest)
        XCTAssertEqual(URLProtocolFixture.recorded.last?.cachePolicy, .reloadIgnoringLocalCacheData)
        guard case .unsigned = try await lookup.currentCustomerSummaryAuthorization(summary, currentAuthority: { true }) else { return XCTFail("Expected explicit unsigned") }
        do { _ = try await lookup.currentCustomerSummaryAuthorization(summary, currentAuthority: { true }); XCTFail("404 cannot mean unsigned") } catch { }
        do { _ = try await lookup.currentCustomerSummaryAuthorization(summary, currentAuthority: { true }); XCTFail("Foreign receipt cannot be accepted") } catch { }
        do { _ = try await lookup.currentCustomerSummaryAuthorization(summary, currentAuthority: { true }); XCTFail("Permission denial cannot mean unsigned") } catch { }
        do { _ = try await lookup.currentCustomerSummaryAuthorization(summary, currentAuthority: { true }); XCTFail("Unknown states cannot mean unsigned") } catch { }
        let lookupGate = URLProtocolFixture.Gate(); defer { lookupGate.release() }
        let gatedLookup = APIClient(session: URLProtocolFixture.session([.init(200, "{\"status\":\"unsigned\"}", gate: lookupGate)]), baseURL: "https://app.thorbis.com")
        var lookupActive = true
        let lookupTask = Task { @MainActor in try await gatedLookup.currentCustomerSummaryAuthorization(summary, currentAuthority: { lookupActive }) }
        for _ in 0..<1500 where URLProtocolFixture.recorded.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
        lookupActive = false; lookupGate.release()
        do { _ = try await lookupTask.value; XCTFail("Retired authority cannot establish unsigned state") } catch is CancellationError { } catch { XCTFail("Expected cancellation, got \(error)") }
        let gate = URLProtocolFixture.Gate(); defer { gate.release() }
        let gatedAPI = APIClient(session: URLProtocolFixture.session([.init(201, receiptJSON, gate: gate)]), baseURL: "https://app.thorbis.com")
        var active = true
        let task = Task { @MainActor in try await gatedAPI.authorizeCustomerInvoiceSummary(summary, attempt: attempt, currentAuthority: { active }) }
        for _ in 0..<1500 where URLProtocolFixture.recorded.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
        active = false; gate.release()
        do { _ = try await task.value; XCTFail("Retired authority must not receive a signing result") } catch is CancellationError { } catch { XCTFail("Expected cancellation, got \(error)") }
        receipt["jobId"] = "other"; XCTAssertFalse(try decoded().matches(summary: summary, signerName: "Alex", signedAt: "2026-11-13T12:00:00Z")); receipt["jobId"] = job
        receipt["digest"] = "sha256:" + String(repeating: "b", count: 64); XCTAssertFalse(try decoded().matches(summary: summary, signerName: "Alex", signedAt: "2026-11-13T12:00:00Z")); receipt["digest"] = digest
        receipt["lines"] = [["id": line, "description": "Hidden internal material", "quantity": 1, "unitPrice": ["amount": 10000, "currency": "USD"]]]
        XCTAssertFalse(try decoded().matches(summary: summary, signerName: "Alex", signedAt: "2026-11-13T12:00:00Z"))
    }

    func testStandaloneSummaryRequiresNoJobAndMatchingCustomer() throws {
        let summary = try decode(["jobId": NSNull()])
        XCTAssertTrue(summary.matches(organizationID: "org-1", customerID: "customer-1", jobID: nil, invoiceID: "invoice-1", linesRevision: 2))
        XCTAssertFalse(summary.matches(organizationID: "org-1", customerID: "other", jobID: nil, invoiceID: "invoice-1", linesRevision: 2))
        XCTAssertFalse(summary.matches(organizationID: "org-1", customerID: "customer-1", jobID: "job-1", invoiceID: "invoice-1", linesRevision: 2))
    }

    func testSummaryReadRequiresFreshServerAndMatchingScope() async throws {
        let id = "00000000-0000-4000-8000-000000000101"
        let jobScope = JobDocumentScope(jobID: "job-1", organizationID: "org-1", customerID: "customer-1")
        let json = try responseJSON(id: id)
        let api = APIClient(session: URLProtocolFixture.session([.init(200, json)]), baseURL: "https://app.thorbis.com")
        let summary = try await api.customerInvoiceSummary(scope: jobScope, invoiceID: id, linesRevision: 2, currentAuthority: { true })
        XCTAssertEqual(summary.lines.first?.description, "Materials")
        XCTAssertEqual(URLProtocolFixture.recorded.last?.url?.path, "/v1/invoices/\(id)/customer-presentation")
        XCTAssertEqual(URLProtocolFixture.recorded.last?.cachePolicy, .reloadIgnoringLocalCacheData)
    }

    func testSummaryReadRejectsOfflineAndMismatchedJob() async throws {
        let id = "00000000-0000-4000-8000-000000000101"
        let jobScope = JobDocumentScope(jobID: "job-1", organizationID: "org-1", customerID: "customer-1")
        let api = APIClient(session: URLProtocolFixture.session([URLProtocolFixture.offline, .init(200, try responseJSON(id: id, job: "other"))]), baseURL: "https://app.thorbis.com")
        let cacheScope = "customer-invoice-summary-\(UUID().uuidString)"
        api.savedCopyScope = cacheScope
        let path = "/v1/invoices/\(id)/customer-presentation"
        let key = SavedCopies.key(origin: "https://app.thorbis.com", path: path, query: [])
        let saved = Data(try responseJSON(id: id).utf8)
        SavedCopyStore.shared.write(saved, scope: cacheScope, key: key)
        SavedCopyStore.shared.waitForQueuedWrites()
        XCTAssertEqual(SavedCopyStore.shared.read(scope: cacheScope, key: key)?.data, saved)
        do { _ = try await api.customerInvoiceSummary(scope: jobScope, invoiceID: id, linesRevision: 2, currentAuthority: { true }); XCTFail("Offline response must not use cached or raw invoice lines") } catch { }
        do { _ = try await api.customerInvoiceSummary(scope: jobScope, invoiceID: id, linesRevision: 2, currentAuthority: { true }); XCTFail("A different job must not be displayed") } catch { }
    }

    func testSummaryReadDiscardsResponseAfterAuthorityChanges() async throws {
        let id = "00000000-0000-4000-8000-000000000101"
        let jobScope = JobDocumentScope(jobID: "job-1", organizationID: "org-1", customerID: "customer-1")
        let gate = URLProtocolFixture.Gate(); defer { gate.release() }
        let api = APIClient(session: URLProtocolFixture.session([.init(200, try responseJSON(id: id), gate: gate)]), baseURL: "https://app.thorbis.com")
        var authorized = true
        let task = Task { @MainActor in try await api.customerInvoiceSummary(scope: jobScope, invoiceID: id, linesRevision: 2, currentAuthority: { authorized }) }
        for _ in 0..<1500 where URLProtocolFixture.recorded.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
        authorized = false; gate.release()
        do { _ = try await task.value; XCTFail("A response under retired authority must be discarded") } catch is CancellationError { } catch { XCTFail("Expected cancellation, got \(error)") }
    }

    private func responseJSON(id: String, job: String = "job-1") throws -> String {
        let response: [String: Any] = ["kind": "customer_invoice_presentation", "presentationVersion": 1,
            "presentationScopeId": "invoice:\(id):lines:2:customer:v1", "isSignedDocument": false,
            "issuedSnapshotId": "00000000-0000-4000-8000-000000000001", "organizationId": "org-1", "customerId": "customer-1",
            "invoiceId": id, "jobId": job, "linesRevision": 2, "status": "issued", "currency": "USD",
            "totalAmount": 10000, "amountPaid": 2500, "balanceDue": 7500,
            "lines": [["id": "line-1", "description": "Materials", "quantity": 1, "unitPrice": ["amount": 10000, "currency": "USD"]]]]
        return String(decoding: try JSONSerialization.data(withJSONObject: response), as: UTF8.self)
    }

}

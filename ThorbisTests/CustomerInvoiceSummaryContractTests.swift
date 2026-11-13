import XCTest
import CryptoKit
@testable import Thorbis

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
        var authority = true
        var abandonedLookup: CheckedContinuation<Void, Never>?
        let abandonedCheck = CustomerSummarySigningCoordinator(summary: summary, actorID: "00000000-0000-4000-8000-000000000025", current: { authority },
            lookup: { await withCheckedContinuation { abandonedLookup = $0 }; return .unsigned },
            upload: { _ in validAsset }, submit: { _ in validReceipt })
        let abandonedCheckTask = Task { @MainActor in await abandonedCheck.checkStatus() }
        for _ in 0..<100 where abandonedLookup == nil { await Task.yield() }
        XCTAssertEqual(abandonedCheck.phase, .checking)
        authority = false; abandonedLookup?.resume(); await abandonedCheckTask.value
        XCTAssertEqual(abandonedCheck.phase, .idle, "Abandoned lookup must not stay checking")
        authority = true; await abandonedCheck.checkStatus(); XCTAssertEqual(abandonedCheck.phase, .unsigned)
        var abandonedSubmit: CheckedContinuation<Void, Never>?
        let abandonedSigning = CustomerSummarySigningCoordinator(summary: summary, actorID: "00000000-0000-4000-8000-000000000025", current: { authority },
            lookup: { .unsigned }, upload: { _ in validAsset }, submit: { _ in
                await withCheckedContinuation { abandonedSubmit = $0 }; return validReceipt
            })
        await abandonedSigning.checkStatus()
        let abandonedSignTask = Task { @MainActor in await abandonedSigning.sign(signerName: "Alex", signedAt: "2026-11-13T12:00:00Z", png: Data([1, 2, 3])) }
        for _ in 0..<100 where abandonedSubmit == nil { await Task.yield() }
        XCTAssertEqual(abandonedSigning.phase, .submitting)
        authority = false; abandonedSubmit?.resume(); await abandonedSignTask.value
        XCTAssertEqual(abandonedSigning.phase, .idle, "Abandoned submit must not stay submitting")
        await abandonedSigning.retryFrozen(); XCTAssertEqual(abandonedSigning.phase, .idle)
        authority = true; await abandonedSigning.checkStatus(); XCTAssertEqual(abandonedSigning.phase, .unsigned)
        await abandonedSigning.retryFrozen(); XCTAssertEqual(abandonedSigning.phase, .signed)
        handoffCurrent = false
        XCTAssertThrowsError(try handoff.attempt())
        handoff.retire(); handoffCurrent = true
        XCTAssertThrowsError(try handoff.attempt())
        let attempt = try XCTUnwrap(CustomerSummarySigningAttempt(summary: summary, signerName: "Alex", signedAt: "2026-11-13T12:00:00Z", imageMediaId: "00000000-0000-4000-8000-000000000020", idempotencyKey: "00000000-0000-4000-8000-000000000021"))
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

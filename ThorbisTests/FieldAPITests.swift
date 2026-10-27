import XCTest
@testable import Thorbis

@MainActor
final class FieldAPITests: XCTestCase {
    private let org = "00000000-0000-4000-8000-000000000002"
    private let customerID = "00000000-0000-4000-8000-000000000003"
    private let jobID = "00000000-0000-4000-8000-000000000001"

    func testJobDetailDecodesScheduleAssignmentPauseEvidenceAndServerTransitions() async throws {
        let session = URLProtocolFixture.session([.init(200, #"{"id":"00000000-0000-4000-8000-000000000001","organizationId":"00000000-0000-4000-8000-000000000002","customerId":"00000000-0000-4000-8000-000000000003","title":"Repair","status":"paused","assignedToUserId":"00000000-0000-4000-8000-000000000004","scheduledFor":"2026-10-27T13:00:00.000Z","pausedAt":"2026-10-26T13:00:00.000Z","pauseReason":"Need a part","pauseNextAction":"Return tomorrow","pauseCycleAuditId":"00000000-0000-4000-8000-000000000005","createdAt":"2026-10-26T12:00:00.000Z","updatedAt":"2026-10-26T13:00:00.000Z","allowedTransitions":["in_progress","completed","canceled"]}"#)])
        let client = APIClient(session: session, baseURL: "https://app.thorbis.com")

        let job = try await client.fieldJob(jobID)

        XCTAssertEqual(job.scheduledFor, "2026-10-27T13:00:00.000Z")
        XCTAssertEqual(job.assignedToUserId, "00000000-0000-4000-8000-000000000004")
        XCTAssertEqual(job.pauseCycleAuditId, "00000000-0000-4000-8000-000000000005")
        XCTAssertEqual(job.allowedTransitions, ["in_progress", "completed", "canceled"])
        XCTAssertEqual(URLProtocolFixture.recorded.first?.url?.path, "/v1/jobs/\(jobID)")
    }

    func testFieldJobListPaginatesAndRefusesRepeatedCursor() async throws {
        let first = #"{"items":[{"id":"00000000-0000-4000-8000-000000000001","organizationId":"00000000-0000-4000-8000-000000000002","customerId":"00000000-0000-4000-8000-000000000003","title":"First","status":"scheduled","createdAt":"2026-10-26T12:00:00Z","updatedAt":"2026-10-26T12:00:00Z"}],"nextCursor":"same"}"#
        let second = #"{"items":[],"nextCursor":"same"}"#
        let client = APIClient(session: URLProtocolFixture.session([.init(200, first), .init(200, second)]), baseURL: "https://app.thorbis.com")

        do {
            _ = try await client.fieldJobs()
            XCTFail("Expected complete-list protection")
        } catch let problem as Problem {
            XCTAssertEqual(problem.title, "Pagination cursor loop")
        }
        XCTAssertEqual(URLProtocolFixture.recorded.count, 2)
    }

    func testProgressPauseAndResumeEncodeRequiredEvidence() async throws {
        let job = #"{"id":"00000000-0000-4000-8000-000000000001","organizationId":"00000000-0000-4000-8000-000000000002","customerId":"00000000-0000-4000-8000-000000000003","title":"Repair","status":"paused","createdAt":"2026-10-26T12:00:00Z","updatedAt":"2026-10-26T13:00:00Z"}"#
        let client = APIClient(session: URLProtocolFixture.session([.init(200, job), .init(200, job)]), baseURL: "https://app.thorbis.com")

        _ = try await client.progressFieldJob(jobID, request: .pause(reason: "Need a part", nextAction: "Return tomorrow"))
        _ = try await client.progressFieldJob(jobID, request: .resume(expectedPauseAuditId: "00000000-0000-4000-8000-000000000005"))

        let bodies = try URLProtocolFixture.recorded.map { try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap($0.body)) as? [String: Any]) }
        XCTAssertEqual(bodies[0]["to"] as? String, "paused")
        XCTAssertEqual((bodies[0]["pause"] as? [String: String])?["reason"], "Need a part")
        XCTAssertEqual((bodies[0]["pause"] as? [String: String])?["nextAction"], "Return tomorrow")
        XCTAssertEqual(bodies[1]["to"] as? String, "in_progress")
        XCTAssertEqual(bodies[1]["expectedPauseAuditId"] as? String, "00000000-0000-4000-8000-000000000005")
    }

    func testContactAndServiceLocationDecodeTheirOwnRecords() async throws {
        let contact = #"{"items":[{"id":"00000000-0000-4000-8000-000000000006","organizationId":"00000000-0000-4000-8000-000000000002","customerId":"00000000-0000-4000-8000-000000000003","name":"Alex","role":"Tenant","primary":true,"createdAt":"2026-10-26T12:00:00Z","updatedAt":"2026-10-26T12:00:00Z"}]}"#
        let location = #"{"items":[{"id":"00000000-0000-4000-8000-000000000007","organizationId":"00000000-0000-4000-8000-000000000002","customerId":"00000000-0000-4000-8000-000000000003","label":"Home","kind":"service","address":"123 Main","coordinates":{"latitude":40.0,"longitude":-73.0},"createdAt":"2026-10-26T12:00:00Z","updatedAt":"2026-10-26T12:00:00Z"}]}"#
        let client = APIClient(session: URLProtocolFixture.session([.init(200, contact), .init(200, location)]), baseURL: "https://app.thorbis.com")

        let contacts = try await client.fieldContacts(customerID)
        let locations = try await client.fieldLocations(customerID)

        XCTAssertEqual(contacts.first?.role, "Tenant")
        XCTAssertEqual(contacts.first?.primary, true)
        XCTAssertEqual(locations.first?.kind, "service")
        XCTAssertEqual(locations.first?.coordinates?.longitude, -73.0)
    }

    func testEstimateAndInvoiceListsDecodeMoneyWithoutInventingTotals() async throws {
        let estimate = #"{"items":[{"id":"00000000-0000-4000-8000-000000000008","organizationId":"00000000-0000-4000-8000-000000000002","customerId":"00000000-0000-4000-8000-000000000003","createdByUserId":"00000000-0000-4000-8000-000000000004","status":"draft","title":"Quote","lines":[{"id":"00000000-0000-4000-8000-000000000009","description":"Repair","quantity":2,"unitPrice":{"amount":12500,"currency":"USD"}}],"createdAt":"2026-10-26T12:00:00Z","updatedAt":"2026-10-26T12:00:00Z"}]}"#
        let invoice = #"{"items":[{"id":"00000000-0000-4000-8000-00000000000a","organizationId":"00000000-0000-4000-8000-000000000002","customerId":"00000000-0000-4000-8000-000000000003","createdByUserId":"00000000-0000-4000-8000-000000000004","origin":"manual","sourceOperationKey":"manual:test","status":"draft","lines":[{"id":"00000000-0000-4000-8000-000000000009","description":"Repair","quantity":2,"unitPrice":{"amount":12500,"currency":"USD"}}],"linesRevision":1,"amountPaid":0,"currency":"USD","createdAt":"2026-10-26T12:00:00Z","updatedAt":"2026-10-26T12:00:00Z"}]}"#
        let client = APIClient(session: URLProtocolFixture.session([.init(200, estimate), .init(200, invoice)]), baseURL: "https://app.thorbis.com")

        let estimates = try await client.fieldEstimates()
        let invoices = try await client.fieldInvoices()
        XCTAssertEqual(estimates.first?.lines.first?.unitPrice.amount, 12500)
        XCTAssertEqual(invoices.first?.amountPaid, 0)
    }

    func testAddingNoteUsesBodyOnlyAndReturnsAuthoritativeRecord() async throws {
        let reply = #"{"id":"00000000-0000-4000-8000-00000000000b","organizationId":"00000000-0000-4000-8000-000000000002","jobId":"00000000-0000-4000-8000-000000000001","authorUserId":"00000000-0000-4000-8000-000000000004","body":"Valve is leaking","createdAt":"2026-10-26T12:00:00Z"}"#
        let client = APIClient(session: URLProtocolFixture.session([.init(201, reply)]), baseURL: "https://app.thorbis.com")

        let note = try await client.addFieldNote(jobID, body: "Valve is leaking")

        XCTAssertEqual(note.authorUserId, "00000000-0000-4000-8000-000000000004")
        let request = try XCTUnwrap(URLProtocolFixture.recorded.first)
        XCTAssertEqual(request.url?.path, "/v1/jobs/\(jobID)/notes")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.body)) as? [String: String])
        XCTAssertEqual(body, ["body": "Valve is leaking"])
    }

    func testCreatingEstimateUsesMinorUnitsAndCanonicalRoute() async throws {
        let reply = #"{"id":"00000000-0000-4000-8000-000000000008","organizationId":"00000000-0000-4000-8000-000000000002","customerId":"00000000-0000-4000-8000-000000000003","createdByUserId":"00000000-0000-4000-8000-000000000004","status":"draft","title":"Quote","lines":[],"createdAt":"2026-10-26T12:00:00Z","updatedAt":"2026-10-26T12:00:00Z"}"#
        let client = APIClient(session: URLProtocolFixture.session([.init(201, reply)]), baseURL: "https://app.thorbis.com")

        let request = FieldEstimateCreate(customerId: customerID, title: "Quote", lines: [
            .init(description: "Repair", quantity: 2, unitPrice: .init(amount: 12500, currency: "USD"))
        ])
        _ = try await client.createFieldEstimate(request)

        let sent = try XCTUnwrap(URLProtocolFixture.recorded.first)
        XCTAssertEqual(sent.url?.path, "/v1/estimates")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(sent.body)) as? [String: Any])
        let line = try XCTUnwrap((body["lines"] as? [[String: Any]])?.first)
        XCTAssertEqual((line["unitPrice"] as? [String: Any])?["amount"] as? Int, 12500)
    }

    func testMediaRegistrationReturnsUploadTargetForClientMintedAsset() async throws {
        let reply = #"{"asset":{"id":"00000000-0000-4000-8000-00000000000c","organizationId":"00000000-0000-4000-8000-000000000002","jobId":"00000000-0000-4000-8000-000000000001","uploaderUserId":"00000000-0000-4000-8000-000000000004","kind":"photo","mime":"image/jpeg","sizeBytes":4,"originalFilename":"valve.jpg","contentHash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","storageKey":"generated","uploadState":"pending","tags":[],"archived":false,"createdAt":"2026-10-26T12:00:00Z","updatedAt":"2026-10-26T12:00:00Z"},"uploadTarget":{"url":"https://upload.example.invalid/one","method":"PUT","expiresAt":"2026-10-26T12:05:00Z","headers":{"Content-Type":"image/jpeg"}}}"#
        let client = APIClient(session: URLProtocolFixture.session([.init(201, reply)]), baseURL: "https://app.thorbis.com")
        let input = FieldMediaRegistrationRequest(clientAssetId: "00000000-0000-4000-8000-00000000000d", kind: "photo", mime: "image/jpeg", sizeBytes: 4, originalFilename: "valve.jpg", contentHash: String(repeating: "a", count: 64))

        let result = try await client.registerFieldMedia(jobID, request: input)

        XCTAssertEqual(result.asset.uploadState, "pending")
        XCTAssertEqual(result.uploadTarget?.method, "PUT")
        let sent = try XCTUnwrap(URLProtocolFixture.recorded.first)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(sent.body)) as? [String: Any])
        XCTAssertEqual(body["clientAssetId"] as? String, "00000000-0000-4000-8000-00000000000d")
        XCTAssertNil(body["jobId"])
    }

    func testPendingMediaRegistrationRequiresExactlyOneUploadMethod() throws {
        let asset = #"{"id":"00000000-0000-4000-8000-00000000000c","organizationId":"00000000-0000-4000-8000-000000000002","jobId":"00000000-0000-4000-8000-000000000001","uploaderUserId":"00000000-0000-4000-8000-000000000004","kind":"photo","mime":"image/jpeg","sizeBytes":4,"originalFilename":"valve.jpg","contentHash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","storageKey":"generated","uploadState":"pending","tags":[],"archived":false,"createdAt":"2026-10-26T12:00:00Z","updatedAt":"2026-10-26T12:00:00Z"}"#
        let decoder = JSONDecoder()
        XCTAssertThrowsError(try decoder.decode(FieldMediaRegistration.self, from: Data("{\"asset\":\(asset)}".utf8)))
        XCTAssertThrowsError(try decoder.decode(FieldMediaRegistration.self, from: Data("{\"asset\":\(asset),\"uploadTarget\":{\"url\":\"https://upload.example.invalid\",\"method\":\"PUT\",\"expiresAt\":\"2026-10-26T12:05:00Z\",\"headers\":{}},\"resumable\":{\"uploadId\":\"x\",\"partSize\":4,\"parts\":[],\"expiresAt\":\"2026-10-26T12:05:00Z\"}}".utf8)))
    }

    func testCreateContactAndLocationUseCustomerPathWithoutClientTenantFields() async throws {
        let contact = #"{"id":"00000000-0000-4000-8000-000000000006","organizationId":"00000000-0000-4000-8000-000000000002","customerId":"00000000-0000-4000-8000-000000000003","name":"Alex","primary":true,"createdAt":"2026-10-26T12:00:00Z","updatedAt":"2026-10-26T12:00:00Z"}"#
        let location = #"{"id":"00000000-0000-4000-8000-000000000007","organizationId":"00000000-0000-4000-8000-000000000002","customerId":"00000000-0000-4000-8000-000000000003","label":"Home","kind":"service","address":"123 Main","createdAt":"2026-10-26T12:00:00Z","updatedAt":"2026-10-26T12:00:00Z"}"#
        let client = APIClient(session: URLProtocolFixture.session([.init(201, contact), .init(201, location)]), baseURL: "https://app.thorbis.com")

        _ = try await client.createFieldContact(customerID, request: .init(name: "Alex", role: "Homeowner", email: "alex@example.com", phone: "555-0100"))
        _ = try await client.createFieldLocation(customerID, request: .init(label: "Home", kind: "service", address: "123 Main"))

        let sent = URLProtocolFixture.recorded
        XCTAssertEqual(sent.map { $0.url?.path }, ["/v1/customers/\(customerID)/contacts", "/v1/customers/\(customerID)/locations"])
        let contactBody = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(sent[0].body)) as? [String: Any])
        XCTAssertNil(contactBody["primary"])
        XCTAssertEqual(contactBody["role"] as? String, "Homeowner")
        XCTAssertEqual(contactBody["email"] as? String, "alex@example.com")
        XCTAssertEqual(contactBody["phone"] as? String, "555-0100")
        XCTAssertNil(contactBody["customerId"])
        let locationBody = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(sent[1].body)) as? [String: Any])
        XCTAssertEqual(locationBody["kind"] as? String, "service")
        XCTAssertNil(locationBody["organizationId"])
    }

    func testCustomerContactDraftTrimsFieldsAndOmitsBlankOptionals() {
        let draft = CustomerContactDraft(
            name: "  Alex Morgan  ",
            role: "  Homeowner  ",
            email: "   ",
            phone: " (415) 555-0134 "
        )

        let request = draft.makeRequest()

        XCTAssertEqual(request?.name, "Alex Morgan")
        XCTAssertEqual(request?.role, "Homeowner")
        XCTAssertNil(request?.email)
        XCTAssertEqual(request?.phone, "(415) 555-0134")
        XCTAssertNil(request?.primary)
    }

    func testCustomerContactCollectionTracksReadinessSeparatelyFromOtherCustomerData() throws {
        var state = CustomerContactCollectionState()
        XCTAssertFalse(state.isLoaded)

        let contacts = try JSONDecoder().decode([CustomerContactRecord].self, from: Data(#"[{"id":"contact-1","organizationId":"org-1","customerId":"customer-1","name":"Alex","primary":true,"createdAt":"2026-10-26T12:00:00Z","updatedAt":"2026-10-26T12:00:00Z"}]"#.utf8))
        state.receive(contacts)

        XCTAssertTrue(state.isLoaded)
        XCTAssertEqual(state.contacts.map(\.id), ["contact-1"])
    }

    func testCustomerContactDraftRequiresANonblankName() {
        let draft = CustomerContactDraft(name: " \n ", role: "Spouse", email: "alex@example.com", phone: "555-0100")

        XCTAssertNil(draft.makeRequest())
    }

    func testBlankCustomerContactOptionalsAreOmittedFromRequestBody() async throws {
        let contact = #"{"id":"00000000-0000-4000-8000-000000000006","organizationId":"00000000-0000-4000-8000-000000000002","customerId":"00000000-0000-4000-8000-000000000003","name":"Alex","primary":false,"createdAt":"2026-10-26T12:00:00Z","updatedAt":"2026-10-26T12:00:00Z"}"#
        let client = APIClient(session: URLProtocolFixture.session([.init(201, contact)]), baseURL: "https://app.thorbis.com")
        let request = try XCTUnwrap(CustomerContactDraft(name: " Alex ", role: " ", email: "\n", phone: " ").makeRequest())

        _ = try await client.createFieldContact(customerID, request: request)

        let sent = try XCTUnwrap(URLProtocolFixture.recorded.first)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(sent.body)) as? [String: Any])
        XCTAssertEqual(body["name"] as? String, "Alex")
        XCTAssertNil(body["primary"])
        XCTAssertNil(body["role"])
        XCTAssertNil(body["email"])
        XCTAssertNil(body["phone"])
    }

    func testMalformedRecordIDDoesNotReachTransport() async {
        let client = APIClient(session: URLProtocolFixture.session([]), baseURL: "https://app.thorbis.com")
        do {
            _ = try await client.fieldJob("../other")
            XCTFail("Expected bad record ID")
        } catch is Problem {} catch { XCTFail("Unexpected: \(error)") }
        XCTAssertTrue(URLProtocolFixture.recorded.isEmpty)
    }

    func testCreatingManualJobSendsOnlyJobOwnedFields() async throws {
        let job = #"{"id":"00000000-0000-4000-8000-000000000001","organizationId":"00000000-0000-4000-8000-000000000002","customerId":"00000000-0000-4000-8000-000000000003","title":"Repair","status":"scheduled","createdAt":"2026-10-26T12:00:00Z","updatedAt":"2026-10-26T12:00:00Z"}"#
        let client = APIClient(session: URLProtocolFixture.session([.init(201, job)]), baseURL: "https://app.thorbis.com")

        _ = try await client.createFieldJob(.init(customerId: customerID, title: "Repair", notes: "Leaking valve"))

        let sent = try XCTUnwrap(URLProtocolFixture.recorded.first)
        XCTAssertEqual(sent.url?.path, "/v1/jobs")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(sent.body)) as? [String: Any])
        XCTAssertEqual(body["customerId"] as? String, customerID)
        XCTAssertEqual(body["notes"] as? String, "Leaking valve")
        XCTAssertNil(body["estimateId"])
        XCTAssertNil(body["organizationId"])
    }

    func testLegacyPhotoListDecodesMetadataAndDoesNotConfuseItWithMediaAssets() async throws {
        let reply = #"{"items":[{"id":"00000000-0000-4000-8000-00000000000e","organizationId":"00000000-0000-4000-8000-000000000002","jobId":"00000000-0000-4000-8000-000000000001","authorUserId":"00000000-0000-4000-8000-000000000004","contentType":"image/jpeg","byteSize":42,"storageKey":"generated","createdAt":"2026-10-26T12:00:00Z"}]}"#
        let client = APIClient(session: URLProtocolFixture.session([.init(200, reply)]), baseURL: "https://app.thorbis.com")

        let photos = try await client.fieldPhotos(jobID)

        XCTAssertEqual(photos.first?.authorUserId, "00000000-0000-4000-8000-000000000004")
        XCTAssertEqual(photos.first?.contentType, "image/jpeg")
        XCTAssertEqual(URLProtocolFixture.recorded.first?.url?.path, "/v1/jobs/\(jobID)/photos")
    }
}

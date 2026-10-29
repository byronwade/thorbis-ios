import XCTest
@testable import Thorbis

@MainActor
final class FieldAPITests: XCTestCase {
    private let org = "00000000-0000-4000-8000-000000000002"
    private let customerID = "00000000-0000-4000-8000-000000000003"
    private let jobID = "00000000-0000-4000-8000-000000000001"

    func testArchivedCustomerListRequestsArchivedRecordsAndDecodesArchiveCycle() async throws {
        let firstPage = #"{"items":[{"id":"00000000-0000-4000-8000-000000000003","organizationId":"00000000-0000-4000-8000-000000000002","name":"Archived customer","archived":true,"archiveCycleAuditId":"00000000-0000-4000-8000-000000000005","createdAt":"2026-10-26T12:00:00Z","updatedAt":"2026-10-27T12:00:00Z"}],"nextCursor":"opaque-cursor"}"#
        let secondPage = #"{"items":[{"id":"00000000-0000-4000-8000-000000000004","organizationId":"00000000-0000-4000-8000-000000000002","name":"Active customer","archived":false,"createdAt":"2026-10-26T12:00:00Z","updatedAt":"2026-10-27T12:00:00Z"}] }"#
        let client = APIClient(session: URLProtocolFixture.session([.init(200, firstPage), .init(200, secondPage)]), baseURL: "https://app.thorbis.com")

        let customers = try await client.fieldCustomers(includeArchived: true)

        XCTAssertEqual(customers.count, 2)
        XCTAssertEqual(customers.first?.archived, true)
        XCTAssertEqual(customers.first?.archiveCycleAuditId, "00000000-0000-4000-8000-000000000005")
        let requests = URLProtocolFixture.recorded
        XCTAssertEqual(requests.count, 2)
        for (index, request) in requests.enumerated() {
            XCTAssertEqual(request.url?.path, "/v1/customers")
            let query = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems)
            var values = Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value ?? "") })
            XCTAssertEqual(values.removeValue(forKey: "includeArchived"), "true")
            if index == 1 { XCTAssertEqual(values, ["cursor": "opaque-cursor"]) }
            else { XCTAssertTrue(values.isEmpty) }
        }
    }

    func testCustomerHistoryDecodesCanonicalItemsAndUsesCustomerHistoryRoute() async throws {
        let history = #"{"items":[{"occurredAt":"2026-10-27T12:00:00.000Z","kind":"job","subjectId":"00000000-0000-4000-8000-000000000001","summary":"Job completed"}],"nextCursor":"opaque-cursor"}"#
        let client = APIClient(session: URLProtocolFixture.session([.init(200, history)]), baseURL: "https://app.thorbis.com")

        let page = try await client.fieldCustomerHistory(customerID)

        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.items[0].kind, "job")
        XCTAssertEqual(page.items[0].subjectId, jobID)
        XCTAssertEqual(page.items[0].summary, "Job completed")
        XCTAssertEqual(page.nextCursor, "opaque-cursor")
        let request = try XCTUnwrap(URLProtocolFixture.recorded.first)
        XCTAssertEqual(request.url?.path, "/v1/customers/\(customerID)/history")
        XCTAssertEqual(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems,
                       [URLQueryItem(name: "limit", value: "50")])
    }

    func testCustomerHistoryUsesReturnedCursorForLoadEarlierPage() async throws {
        let first = #"{"items":[{"occurredAt":"2026-10-27T12:00:00.000Z","kind":"job","subjectId":"00000000-0000-4000-8000-000000000001","summary":"Latest"}],"nextCursor":"opaque-cursor"}"#
        let earlier = #"{"items":[{"occurredAt":"2026-10-26T12:00:00.000Z","kind":"contact","subjectId":"00000000-0000-4000-8000-000000000005","summary":"Contact added"}]}"#
        let client = APIClient(session: URLProtocolFixture.session([.init(200, first), .init(200, earlier)]), baseURL: "https://app.thorbis.com")

        let page = try await client.fieldCustomerHistory(customerID)
        let earlierPage = try await client.fieldCustomerHistory(customerID, cursor: try XCTUnwrap(page.nextCursor))

        XCTAssertNil(earlierPage.nextCursor)
        XCTAssertEqual(earlierPage.items.first?.summary, "Contact added")
        let request = try XCTUnwrap(URLProtocolFixture.recorded.last)
        XCTAssertEqual(request.url?.path, "/v1/customers/\(customerID)/history")
        XCTAssertEqual(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems,
                       [URLQueryItem(name: "limit", value: "50"), URLQueryItem(name: "cursor", value: "opaque-cursor")])
    }

    func testCustomerListScopesMatchRecentAllAndArchivedViews() throws {
        let records = #"[{"id":"00000000-0000-4000-8000-000000000002","organizationId":"00000000-0000-4000-8000-000000000002","name":"Alpha","archived":false,"createdAt":"2026-10-26T12:00:00Z","updatedAt":"2026-10-26T12:00:00Z"},{"id":"00000000-0000-4000-8000-000000000003","organizationId":"00000000-0000-4000-8000-000000000002","name":"Beta","archived":true,"createdAt":"2026-10-26T12:00:00Z","updatedAt":"2026-10-27T12:00:00Z"},{"id":"00000000-0000-4000-8000-000000000004","organizationId":"00000000-0000-4000-8000-000000000002","name":"Gamma","archived":false,"createdAt":"2026-10-27T12:00:00Z","updatedAt":"2026-10-27T13:00:00Z"}]"#
        let customers = try JSONDecoder().decode([CustomerRecord].self, from: Data(records.utf8))

        XCTAssertEqual(CustomerListScope.recent.customers(from: customers).map(\.id), [
            "00000000-0000-4000-8000-000000000004", "00000000-0000-4000-8000-000000000002"
        ])
        XCTAssertEqual(CustomerListScope.all.customers(from: customers).map(\.id), [
            "00000000-0000-4000-8000-000000000002", "00000000-0000-4000-8000-000000000003", "00000000-0000-4000-8000-000000000004"
        ])
        XCTAssertEqual(CustomerListScope.archived.customers(from: customers).map(\.id), [
            "00000000-0000-4000-8000-000000000003"
        ])
    }

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

    func testJobActivityReadsJobAndNotesWithoutUsingCachedResponses() async throws {
        let job = #"{"id":"00000000-0000-4000-8000-000000000001","organizationId":"00000000-0000-4000-8000-000000000002","customerId":"00000000-0000-4000-8000-000000000003","title":"Repair","status":"scheduled","createdAt":"2026-10-26T12:00:00Z","updatedAt":"2026-10-26T12:00:00Z"}"#
        let client = APIClient(session: URLProtocolFixture.session([.init(200, job), .init(200, #"{"items":[]}"#)]), baseURL: "https://app.thorbis.com")

        let loadedJob = try await client.fieldJob(jobID, requireFresh: true)
        let loadedNotes = try await client.fieldNotes(jobID, requireFresh: true)

        XCTAssertEqual(loadedJob.id, jobID)
        XCTAssertTrue(loadedNotes.isEmpty)
        let requests = URLProtocolFixture.recorded
        XCTAssertEqual(requests.map { $0.url?.path }, ["/v1/jobs/\(jobID)", "/v1/jobs/\(jobID)/notes"])
        for request in requests {
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            XCTAssertEqual(request.header("Cache-Control"), "no-cache")
        }
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

    func testProgressEnRouteEncodesOptionalEta() async throws {
        let job = #"{"id":"00000000-0000-4000-8000-000000000001","organizationId":"00000000-0000-4000-8000-000000000002","customerId":"00000000-0000-4000-8000-000000000003","title":"Repair","status":"en_route","createdAt":"2026-10-26T12:00:00Z","updatedAt":"2026-10-26T13:00:00Z"}"#
        let client = APIClient(session: URLProtocolFixture.session([.init(200, job), .init(200, job)]), baseURL: "https://app.thorbis.com")

        _ = try await client.progressFieldJob(jobID, request: .enRoute(etaMinutes: 45))
        _ = try await client.progressFieldJob(jobID, request: .enRoute())

        let bodies = try URLProtocolFixture.recorded.map { try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap($0.body)) as? [String: Any]) }
        XCTAssertEqual(bodies.map { $0["to"] as? String }, ["en_route", "en_route"])
        XCTAssertEqual(bodies[0]["etaMinutes"] as? Int, 45)
        XCTAssertNil(bodies[1]["etaMinutes"])
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

    func testTaggingAStoredPhotoPostsTheStageAndKeepsTheCaption() async throws {
        let mediaID = "00000000-0000-4000-8000-00000000000c"
        let reply = #"{"id":"00000000-0000-4000-8000-00000000000c","organizationId":"00000000-0000-4000-8000-000000000002","jobId":"00000000-0000-4000-8000-000000000001","uploaderUserId":"00000000-0000-4000-8000-000000000004","kind":"photo","mime":"image/jpeg","sizeBytes":4,"originalFilename":"valve.jpg","contentHash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","storageKey":"generated","uploadState":"stored","tags":["Warranty","After"],"caption":"Coil","archived":false,"createdAt":"2026-10-26T12:00:00Z","updatedAt":"2026-10-26T12:10:00Z"}"#
        let client = APIClient(session: URLProtocolFixture.session([.init(200, reply)]), baseURL: "https://app.thorbis.com")

        let updated = try await client.tagFieldMedia(mediaID, tags: MediaStageTags.applying(.after, to: ["Warranty", "Before"]), caption: "Coil")

        XCTAssertEqual(updated.tags, ["Warranty", "After"])
        XCTAssertEqual(updated.caption, "Coil")
        let sent = try XCTUnwrap(URLProtocolFixture.recorded.first)
        XCTAssertEqual(sent.method, "POST")
        XCTAssertEqual(sent.url?.path, "/v1/media/\(mediaID)/tags")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(sent.body)) as? [String: Any])
        XCTAssertEqual(body["tags"] as? [String], ["Warranty", "After"])
        XCTAssertEqual(body["caption"] as? String, "Coil")
    }

    func testTaggingDropsBlankTagsAndOmitsAnEmptyCaption() async throws {
        let mediaID = "00000000-0000-4000-8000-00000000000c"
        let reply = #"{"id":"00000000-0000-4000-8000-00000000000c","organizationId":"00000000-0000-4000-8000-000000000002","jobId":"00000000-0000-4000-8000-000000000001","uploaderUserId":"00000000-0000-4000-8000-000000000004","kind":"photo","mime":"image/jpeg","sizeBytes":4,"originalFilename":"valve.jpg","contentHash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","storageKey":"generated","uploadState":"stored","tags":["After"],"archived":false,"createdAt":"2026-10-26T12:00:00Z","updatedAt":"2026-10-26T12:10:00Z"}"#
        let client = APIClient(session: URLProtocolFixture.session([.init(200, reply)]), baseURL: "https://app.thorbis.com")

        _ = try await client.tagFieldMedia(mediaID, tags: [" After ", ""], caption: "   ")

        let sent = try XCTUnwrap(URLProtocolFixture.recorded.first)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(sent.body)) as? [String: Any])
        XCTAssertEqual(body["tags"] as? [String], ["After"])
        XCTAssertNil(body["caption"])
    }

    func testTaggingRejectsTooManyTagsAndABadMediaIDBeforeSending() async {
        let client = APIClient(session: URLProtocolFixture.session([]), baseURL: "https://app.thorbis.com")
        let mediaID = "00000000-0000-4000-8000-00000000000c"

        do {
            _ = try await client.tagFieldMedia(mediaID, tags: (1...21).map { "tag-\($0)" })
            XCTFail("Expected too many tags")
        } catch let problem as Problem {
            XCTAssertEqual(problem.title, "Too many photo tags")
        } catch { XCTFail("Unexpected error: \(error)") }

        do {
            _ = try await client.tagFieldMedia("not-a-photo", tags: ["Before"])
            XCTFail("Expected an invalid media id")
        } catch let problem as Problem {
            XCTAssertEqual(problem.title, "Invalid media ID")
        } catch { XCTFail("Unexpected error: \(error)") }

        XCTAssertTrue(URLProtocolFixture.recorded.isEmpty)
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

    func testUpdateContactCanClearNullableFieldsAndPromotePrimary() async throws {
        let contactID = "00000000-0000-4000-8000-000000000006"
        let updated = #"{"id":"00000000-0000-4000-8000-000000000006","organizationId":"00000000-0000-4000-8000-000000000002","customerId":"00000000-0000-4000-8000-000000000003","name":"Alex","role":null,"email":null,"phone":null,"primary":true,"createdAt":"2026-10-26T12:00:00Z","updatedAt":"2026-10-26T13:00:00Z"}"#
        let client = APIClient(session: URLProtocolFixture.session([.init(200, updated), .init(200, updated)]), baseURL: "https://app.thorbis.com")

        let cleared = try await client.updateFieldContact(customerID, contactID, request: .init(
            name: "Alex", role: .clear, email: .clear, phone: .clear
        ))
        let promoted = try await client.updateFieldContact(customerID, contactID, request: .init(primary: true))

        XCTAssertNil(cleared.role)
        XCTAssertNil(cleared.email)
        XCTAssertNil(cleared.phone)
        XCTAssertTrue(promoted.primary)
        let sent = URLProtocolFixture.recorded
        XCTAssertEqual(sent.map { $0.url?.path }, [
            "/v1/customers/\(customerID)/contacts/\(contactID)",
            "/v1/customers/\(customerID)/contacts/\(contactID)"
        ])
        let clearingBody = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(sent[0].body)) as? [String: Any])
        XCTAssertEqual(clearingBody["name"] as? String, "Alex")
        XCTAssertTrue(clearingBody["role"] is NSNull)
        XCTAssertTrue(clearingBody["email"] is NSNull)
        XCTAssertTrue(clearingBody["phone"] is NSNull)
        XCTAssertNil(clearingBody["primary"])
        let primaryBody = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(sent[1].body)) as? [String: Any])
        XCTAssertEqual(primaryBody.count, 1)
        XCTAssertEqual(primaryBody["primary"] as? Bool, true)
    }

    func testRemoveContactUsesBodylessPostAndAcceptsNoContent() async throws {
        let contactID = "00000000-0000-4000-8000-000000000006"
        let client = APIClient(session: URLProtocolFixture.session([.init(204, "")]), baseURL: "https://app.thorbis.com")

        try await client.removeFieldContact(customerID, contactID)

        let sent = try XCTUnwrap(URLProtocolFixture.recorded.first)
        XCTAssertEqual(sent.method, "POST")
        XCTAssertEqual(sent.url?.path, "/v1/customers/\(customerID)/contacts/\(contactID)/remove")
        XCTAssertNil(sent.body)
    }

    func testContactMutationRejectsInvalidPathIDsBeforeSending() async {
        let client = APIClient(session: URLProtocolFixture.session([]), baseURL: "https://app.thorbis.com")
        do {
            _ = try await client.updateFieldContact(customerID, "../other", request: .init(primary: true))
            XCTFail("Expected invalid contact ID to be rejected")
        } catch let problem as Problem {
            XCTAssertEqual(problem.title, "Invalid record ID")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertTrue(URLProtocolFixture.recorded.isEmpty)
    }

    func testUpdateFieldLocationSendsNullableValuesToClearAndDecodesSavedRecord() async throws {
        let locationID = "00000000-0000-4000-8000-000000000007"
        let location = #"{"id":"00000000-0000-4000-8000-000000000007","organizationId":"00000000-0000-4000-8000-000000000002","customerId":"00000000-0000-4000-8000-000000000003","label":"Shop","kind":"service","address":"456 Main","notes":null,"coordinates":null,"gateCode":null,"alarmCode":null,"dogOnSite":null,"parking":null,"createdAt":"2026-10-26T12:00:00Z","updatedAt":"2026-10-26T13:00:00Z"}"#
        let client = APIClient(session: URLProtocolFixture.session([.init(200, location)]), baseURL: "https://app.thorbis.com")

        let saved = try await client.updateFieldLocation(customerID, locationID, request: .init(
            label: "Shop", kind: "service", address: "456 Main", notes: nil, coordinates: nil,
            gateCode: nil, alarmCode: nil, dogOnSite: nil, parking: nil
        ))

        XCTAssertEqual(saved.address, "456 Main")
        let sent = try XCTUnwrap(URLProtocolFixture.recorded.first)
        XCTAssertEqual(sent.method, "POST")
        XCTAssertEqual(sent.url?.path, "/v1/customers/\(customerID)/locations/\(locationID)")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(sent.body)) as? [String: Any])
        XCTAssertEqual(body["label"] as? String, "Shop")
        XCTAssertEqual(body["address"] as? String, "456 Main")
        for key in ["notes", "coordinates", "gateCode", "alarmCode", "dogOnSite", "parking"] {
            XCTAssertTrue(body[key] is NSNull, "Expected \(key) to be explicitly cleared")
        }
        XCTAssertNil(body["customerId"])
        XCTAssertNil(body["organizationId"])
    }

    func testRemoveFieldLocationUsesEmptyPostAndAcceptsNoContent() async throws {
        let locationID = "00000000-0000-4000-8000-000000000007"
        let client = APIClient(session: URLProtocolFixture.session([.init(204, "")]), baseURL: "https://app.thorbis.com")

        try await client.removeFieldLocation(customerID, locationID)

        let sent = try XCTUnwrap(URLProtocolFixture.recorded.first)
        XCTAssertEqual(sent.method, "POST")
        XCTAssertEqual(sent.url?.path, "/v1/customers/\(customerID)/locations/\(locationID)/remove")
        XCTAssertNil(sent.body)
    }

    func testFieldLocationMutationsRejectInvalidIdsBeforeSending() async throws {
        let client = APIClient(session: URLProtocolFixture.session([]), baseURL: "https://app.thorbis.com")
        let update = FieldLocationUpdate(
            label: "Home", kind: "service", address: "123 Main", notes: nil, coordinates: nil,
            gateCode: nil, alarmCode: nil, dogOnSite: nil, parking: nil
        )

        do {
            _ = try await client.updateFieldLocation(customerID, "not-a-uuid", request: update)
            XCTFail("Expected invalid location ID to be rejected")
        } catch let problem as Problem {
            XCTAssertEqual(problem.title, "Invalid record ID")
        }
        do {
            try await client.removeFieldLocation("not-a-uuid", "00000000-0000-4000-8000-000000000007")
            XCTFail("Expected invalid customer ID to be rejected")
        } catch let problem as Problem {
            XCTAssertEqual(problem.title, "Invalid record ID")
        }
        XCTAssertTrue(URLProtocolFixture.recorded.isEmpty)
    }

    func testServiceLocationDraftTrimsValuesAndBuildsCoordinates() throws {
        let draft = ServiceLocationDraft(
            label: "  Shop  ", kind: "billing", address: "  456 Main  ", notes: "  Side entrance  ",
            latitude: " 40.25 ", longitude: "-73.5", gateCode: "  1234# ", alarmCode: " ",
            dogOnSite: " Rusty ", parking: "  Rear lot  "
        )

        let request = try draft.makeCreateRequest()

        XCTAssertEqual(request.label, "Shop")
        XCTAssertEqual(request.kind, "billing")
        XCTAssertEqual(request.address, "456 Main")
        XCTAssertEqual(request.notes, "Side entrance")
        XCTAssertEqual(request.coordinates, FieldCoordinates(latitude: 40.25, longitude: -73.5))
        XCTAssertEqual(request.gateCode, "1234#")
        XCTAssertNil(request.alarmCode)
        XCTAssertEqual(request.dogOnSite, "Rusty")
        XCTAssertEqual(request.parking, "Rear lot")
    }

    func testServiceLocationMutationRejectsAnOlderPendingRefresh() {
        let original = serviceLocation(id: "original", label: "Before")
        let updated = serviceLocation(id: "original", label: "After")
        var state = ServiceLocationCollectionState()
        state.save(original)

        let pendingRefresh = state.beginLoad()
        state.save(updated)

        XCTAssertFalse(state.receive([original], generation: pendingRefresh))
        XCTAssertEqual(state.locations, [updated])

        let secondPendingRefresh = state.beginLoad()
        state.remove(id: updated.id)

        XCTAssertFalse(state.receive([updated], generation: secondPendingRefresh))
        XCTAssertTrue(state.locations.isEmpty)
    }

    private func serviceLocation(id: String, label: String) -> ServiceLocationRecord {
        ServiceLocationRecord(
            id: id,
            organizationId: org,
            customerId: customerID,
            label: label,
            kind: "service",
            address: "123 Main St",
            notes: nil,
            coordinates: nil,
            gateCode: nil,
            alarmCode: nil,
            dogOnSite: nil,
            parking: nil,
            createdAt: "2026-10-27T12:00:00Z",
            updatedAt: "2026-10-27T12:00:00Z"
        )
    }

    func testServiceLocationDraftRejectsMissingRequiredValuesAndInvalidCoordinatePairs() {
        XCTAssertThrowsError(try ServiceLocationDraft(label: " ", kind: "service", address: "123 Main").makeCreateRequest())
        XCTAssertThrowsError(try ServiceLocationDraft(label: "Home", kind: "service", address: " ").makeCreateRequest())
        XCTAssertThrowsError(try ServiceLocationDraft(label: "Home", kind: "service", address: "123 Main", latitude: "40").makeCreateRequest())
        XCTAssertThrowsError(try ServiceLocationDraft(label: "Home", kind: "service", address: "123 Main", latitude: "91", longitude: "0").makeCreateRequest())
    }

    func testCustomerContactDraftTrimsFieldsAndOmitsBlankOptionals() throws {
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

        let update = try XCTUnwrap(draft.makeUpdateRequest())
        let encoded = try JSONEncoder().encode(update)
        let updateBody = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(updateBody["name"] as? String, "Alex Morgan")
        XCTAssertEqual(updateBody["role"] as? String, "Homeowner")
        XCTAssertTrue(updateBody["email"] is NSNull)
        XCTAssertEqual(updateBody["phone"] as? String, "(415) 555-0134")
    }

    func testCustomerContactCollectionTracksReadinessSeparatelyFromOtherCustomerData() throws {
        var state = CustomerContactCollectionState()
        XCTAssertFalse(state.isLoaded)

        let contacts = try JSONDecoder().decode([CustomerContactRecord].self, from: Data(#"[{"id":"contact-1","organizationId":"org-1","customerId":"customer-1","name":"Alex","primary":true,"createdAt":"2026-10-26T12:00:00Z","updatedAt":"2026-10-26T12:00:00Z"}]"#.utf8))
        let generation = state.beginLoading()
        XCTAssertTrue(state.receive(contacts, generation: generation))

        XCTAssertTrue(state.isLoaded)
        XCTAssertEqual(state.contacts.map(\.id), ["contact-1"])
    }

    func testRemovingPrimaryContactRejectsStaleRefreshAndPromotesOldestRemainingContact() {
        let primary = customerContact(id: "primary", name: "Current", primary: true, createdAt: "2026-10-27T12:00:00Z")
        let oldest = customerContact(id: "oldest", name: "First added", primary: false, createdAt: "2026-10-26T12:00:00Z")
        let newest = customerContact(id: "newest", name: "Last added", primary: false, createdAt: "2026-10-27T13:00:00Z")
        var state = CustomerContactCollectionState()
        let initialLoad = state.beginLoading()
        state.receive([primary, newest, oldest], generation: initialLoad)
        let pendingRefresh = state.beginLoading()

        state.remove(id: primary.id)

        XCTAssertFalse(state.receive([primary, newest, oldest], generation: pendingRefresh))
        XCTAssertEqual(Set(state.contacts.map(\.id)), Set([oldest.id, newest.id]))
        XCTAssertTrue(state.contacts.first(where: { $0.id == oldest.id })?.primary == true)
        XCTAssertFalse(state.contacts.first(where: { $0.id == newest.id })?.primary ?? true)
    }

    private func customerContact(id: String, name: String, primary: Bool, createdAt: String) -> CustomerContactRecord {
        CustomerContactRecord(
            id: id,
            organizationId: org,
            customerId: customerID,
            name: name,
            role: nil,
            email: nil,
            phone: nil,
            primary: primary,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    func testCustomerContactDraftRequiresANonblankName() {
        let draft = CustomerContactDraft(name: " \n ", role: "Spouse", email: "alex@example.com", phone: "555-0100")

        XCTAssertNil(draft.makeRequest())
        XCTAssertNil(draft.makeUpdateRequest())
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
        // This optional jobs.locationId is the organization's branch scope, not a customer service address.
        let branchLocationID = "00000000-0000-4000-8000-000000000004"

        _ = try await client.createFieldJob(.init(customerId: customerID, title: "Repair", locationId: branchLocationID, notes: "Leaking valve"))

        let sent = try XCTUnwrap(URLProtocolFixture.recorded.first)
        XCTAssertEqual(sent.url?.path, "/v1/jobs")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(sent.body)) as? [String: Any])
        XCTAssertEqual(body["customerId"] as? String, customerID)
        XCTAssertEqual(body["locationId"] as? String, branchLocationID)
        XCTAssertEqual(body["notes"] as? String, "Leaking valve")
        XCTAssertNil(body["teamId"])
        XCTAssertNil(body["assignedToUserId"])
        XCTAssertNil(body["priority"])
        XCTAssertNil(body["estimateId"])
        XCTAssertNil(body["organizationId"])
    }

    func testFieldJobDraftBuildsTrimmedSupportedRequest() throws {
        var draft = FieldJobDraft()
        draft.customerID = customerID
        draft.title = "  Water heater repair  "
        draft.notes = "  Leaking valve in the basement  "

        XCTAssertTrue(draft.canCreate)
        let request = try XCTUnwrap(draft.request)
        XCTAssertEqual(request.customerId, customerID)
        XCTAssertEqual(request.title, "Water heater repair")
        XCTAssertEqual(request.notes, "Leaking valve in the basement")
        XCTAssertNil(request.teamId)
        XCTAssertNil(request.locationId)
    }

    func testFieldJobDraftRequiresCustomerAndNonblankTitleAndDropsBlankNotes() throws {
        var draft = FieldJobDraft()
        draft.title = "   \n"
        XCTAssertFalse(draft.canCreate)
        XCTAssertNil(draft.request)

        draft.customerID = customerID
        XCTAssertFalse(draft.canCreate)
        draft.title = "Repair"
        draft.notes = "  \n  "

        let request = try XCTUnwrap(draft.request)
        XCTAssertTrue(draft.canCreate)
        XCTAssertNil(request.notes)
        XCTAssertNil(request.locationId)
    }

    func testFieldJobDraftUsesCanonicalTitleAndNotesLimits() throws {
        var draft = FieldJobDraft(
            customerID: customerID,
            title: String(repeating: "T", count: 200),
            notes: String(repeating: "N", count: 10_000)
        )
        XCTAssertTrue(draft.canCreate)
        XCTAssertNotNil(draft.request)

        draft.title.append("T")
        XCTAssertFalse(draft.canCreate)
        XCTAssertNil(draft.request)

        draft.title = "Repair"
        draft.notes.append("N")
        XCTAssertFalse(draft.canCreate)
        XCTAssertNil(draft.request)
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

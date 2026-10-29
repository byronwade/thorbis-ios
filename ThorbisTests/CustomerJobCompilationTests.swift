import XCTest
@testable import Thorbis

@MainActor
final class CustomerJobCompilationTests: XCTestCase {
    private let org = uid(4)
    private let customer = uid(3)
    private let jobA = uid(1)
    private let jobB = uid(2)
    private let author = uid(5)

    func testTwoJobsCompileToThirtyFiveAndStayGrouped() async throws {
        let replies = fixture(photosA: 15, photosB: 20, notesA: 15, notesB: 20, documentsA: 15, documentsB: 20, estimatesA: 15, estimatesB: 20, invoicesA: 15, invoicesB: 20, historyA: 15, historyB: 20)
        let client = APIClient(session: URLProtocolFixture.session(replies.map { .init(200, $0) }), baseURL: "https://app.thorbis.com")

        let compiled = try await CustomerJobCompilationLoader.load(customerID: customer, organizationID: org, api: client)

        XCTAssertEqual(compiled.photoCount, 35)
        XCTAssertEqual(compiled.noteCount, 35)
        XCTAssertEqual(compiled.documentCount, 35)
        XCTAssertEqual(compiled.estimateCount, 35)
        XCTAssertEqual(compiled.invoiceCount, 35)
        XCTAssertEqual(compiled.activityCount, 35)
        XCTAssertEqual(compiled.contacts.count, 1)
        XCTAssertEqual(compiled.locations.count, 1)
        assertGrouped(compiled.photos, counts: (15, 20))
        assertGrouped(compiled.notes, counts: (15, 20))
        assertGrouped(compiled.documents, counts: (15, 20))
        assertGrouped(compiled.estimates, counts: (15, 20))
        assertGrouped(compiled.invoices, counts: (15, 20))
        assertGrouped(compiled.activity, counts: (15, 20))
        XCTAssertTrue(compiled.photos.allSatisfy { group in group.items.allSatisfy { photo in
            if case let .modern(asset, _) = photo { return asset.kind == "photo" && !asset.archived }
            return false
        } })
        XCTAssertTrue(compiled.documents.allSatisfy { group in group.items.allSatisfy { $0.kind != "photo" && !$0.archived } })
        XCTAssertTrue(compiled.estimatesOffJob.isEmpty)
        XCTAssertTrue(compiled.invoicesOffJob.isEmpty)

        let requests = URLProtocolFixture.recorded
        XCTAssertEqual(requests.count, 16)
        assertCustomerQuery(requests[0], path: "/v1/jobs")
        XCTAssertEqual(requests[1].url?.path, "/v1/customers/\(customer)/contacts")
        XCTAssertEqual(requests[2].url?.path, "/v1/customers/\(customer)/locations")
        assertCustomerQuery(requests[3], path: "/v1/estimates")
        assertCustomerQuery(requests[4], path: "/v1/invoices")
        XCTAssertEqual(requests[5].url?.path, "/v1/jobs/\(jobA)/notes")
        XCTAssertEqual(requests[6].url?.path, "/v1/jobs/\(jobA)/media")
        XCTAssertEqual(requests[7].url?.path, "/v1/jobs/\(jobA)/estimates")
        XCTAssertEqual(requests[8].url?.path, "/v1/jobs/\(jobA)/invoices")
        XCTAssertEqual(requests[9].url?.path, "/v1/jobs/\(jobB)/notes")
        XCTAssertEqual(requests[10].url?.path, "/v1/jobs/\(jobB)/media")
        XCTAssertEqual(requests[11].url?.path, "/v1/jobs/\(jobB)/estimates")
        XCTAssertEqual(requests[12].url?.path, "/v1/jobs/\(jobB)/invoices")
        XCTAssertEqual(requests[13].url?.path, "/v1/customers/\(customer)/history")
    }

    func testCustomerScopeFiltersForeignJobsContactsAndLocations() async throws {
        var bodies = fixture(photosA: 1, photosB: 1, notesA: 0, notesB: 0, documentsA: 0, documentsB: 0, estimatesA: 0, estimatesB: 0, invoicesA: 0, invoicesB: 0, historyA: 0, historyB: 0)
        var foreignCustomer = job(id: uid(98), title: "Foreign customer")
        foreignCustomer["customerId"] = uid(99)
        var foreignOrg = job(id: uid(97), title: "Foreign workspace")
        foreignOrg["organizationId"] = uid(99)
        bodies[0] = page([job(id: jobA, title: "Water heater"), job(id: jobB, title: "AC"), foreignCustomer, foreignOrg])
        var wrongContact = contact(); wrongContact["customerId"] = uid(99)
        var wrongLocation = location(); wrongLocation["organizationId"] = uid(99)
        bodies[1] = page([contact(), wrongContact]); bodies[2] = page([location(), wrongLocation])
        let client = APIClient(session: URLProtocolFixture.session(bodies.map { .init(200, $0) }), baseURL: "https://app.thorbis.com")
        let compiled = try await CustomerJobCompilationLoader.load(customerID: customer, organizationID: org, api: client)
        XCTAssertTrue(compiled.identityIncomplete)
        XCTAssertEqual(compiled.contacts.count, 1); XCTAssertEqual(compiled.locations.count, 1)
        XCTAssertEqual(compiled.photoCount, 2)
        XCTAssertFalse(URLProtocolFixture.recorded.contains { $0.url?.path.contains(uid(98)) == true || $0.url?.path.contains(uid(97)) == true })
        let mediaRequests = URLProtocolFixture.recorded.filter { $0.url?.path.hasSuffix("/media") == true }
        XCTAssertTrue(mediaRequests.allSatisfy { URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)?.queryItems?.contains(URLQueryItem(name: "includeArchived", value: "true")) == true })
    }

    func testForeignDocumentsNotesAndLinksAreExcludedAndMarkedPartial() async throws {
        var bodies = fixture(photosA: 0, photosB: 0, notesA: 1, notesB: 0, documentsA: 0, documentsB: 0, estimatesA: 1, estimatesB: 0, invoicesA: 1, invoicesB: 0, historyA: 0, historyB: 0)
        var badEstimate = estimate(id: uid(70001), title: "Wrong customer"); badEstimate["customerId"] = uid(99)
        var badEstimateOrg = estimate(id: uid(70002), title: "Wrong workspace"); badEstimateOrg["organizationId"] = uid(99)
        var badInvoice = invoice(id: uid(80001), jobID: jobA); badInvoice["organizationId"] = uid(99)
        var badInvoiceCustomer = invoice(id: uid(80003), jobID: jobA); badInvoiceCustomer["customerId"] = uid(99)
        let badNote = note(id: uid(10001), job: jobB, body: "Wrong job")
        var badNoteOrg = note(id: uid(10002), job: jobA, body: "Wrong workspace"); badNoteOrg["organizationId"] = uid(99)
        bodies[3] = page([estimate(id: uid(7000), title: "Valid"), badEstimate, badEstimateOrg])
        bodies[4] = page([invoice(id: uid(9000), jobID: jobA), badInvoice, badInvoiceCustomer])
        bodies[5] = page([note(id: uid(10000), job: jobA, body: "Valid"), badNote, badNoteOrg])
        bodies[7] = page([link(id: uid(99001), job: jobB, estimate: uid(7000)), link(id: uid(99002), job: jobA, estimate: uid(70001))])
        bodies[8] = page([invoice(id: uid(9000), jobID: jobA), invoice(id: uid(80002), jobID: jobB)])
        let client = APIClient(session: URLProtocolFixture.session(bodies.map { .init(200, $0) }), baseURL: "https://app.thorbis.com")
        let compiled = try await CustomerJobCompilationLoader.load(customerID: customer, organizationID: org, api: client)
        XCTAssertEqual(compiled.noteCount, 1)
        XCTAssertEqual(compiled.estimateCount, 1)
        XCTAssertEqual(compiled.invoiceCount, 1)
        XCTAssertTrue(compiled.notesIncomplete)
        XCTAssertTrue(compiled.estimatesIncomplete)
        XCTAssertTrue(compiled.invoicesIncomplete)
    }

    func testOneFailedJobMediaKeepsOtherJobsPhotosAndMarksTotalIncomplete() async throws {
        let bodies = fixture(photosA: 2, photosB: 3, notesA: 0, notesB: 0, documentsA: 0, documentsB: 0, estimatesA: 0, estimatesB: 0, invoicesA: 0, invoicesB: 0, historyA: 0, historyB: 0)
        var replies = bodies.map { URLProtocolFixture.Reply(200, $0) }
        replies[6] = URLProtocolFixture.Reply(500, #"{"title":"Unavailable","status":500}"#)
        let client = APIClient(session: URLProtocolFixture.session(replies), baseURL: "https://app.thorbis.com")

        let compiled = try await CustomerJobCompilationLoader.load(customerID: customer, organizationID: org, api: client)

        XCTAssertEqual(compiled.photoCount, 3)
        XCTAssertEqual(compiled.photos.map(\.jobID), [jobB])
        XCTAssertEqual(compiled.mediaIncompleteJobIDs, [jobA])
        XCTAssertEqual(compiled.documentIncompleteJobIDs, [jobA])
    }

    func testFailedTombstoneReadDoesNotExposeLegacyFromThatJob() async throws {
        var bodies = fixture(photosA: 0, photosB: 0, notesA: 0, notesB: 0, documentsA: 0, documentsB: 0, estimatesA: 0, estimatesB: 0, invoicesA: 0, invoicesB: 0, historyA: 0, historyB: 0)
        // The legacy read for job A must be skipped entirely; only B's list is returned.
        bodies[14] = page([legacyPhoto(id: uid(20_001), job: jobB, key: "historical/unique")])
        var replies = bodies.map { URLProtocolFixture.Reply(200, $0) }
        replies[6] = URLProtocolFixture.Reply(500, #"{"title":"Unavailable","status":500}"#)
        let client = APIClient(session: URLProtocolFixture.session(replies), baseURL: "https://app.thorbis.com")
        let compiled = try await CustomerJobCompilationLoader.load(customerID: customer, organizationID: org, api: client)
        XCTAssertEqual(compiled.photos.map(\.jobID), [jobB])
        XCTAssertEqual(compiled.mediaIncompleteJobIDs, [jobA])
        let paths = URLProtocolFixture.recorded.compactMap { $0.url?.path }
        XCTAssertFalse(paths.contains("/v1/jobs/\(jobA)/photos"))
        XCTAssertTrue(paths.contains("/v1/jobs/\(jobB)/photos"))
    }

    func testMediaWithWrongJobOrOrganizationIsExcludedAndMakesCountIncomplete() async throws {
        var bodies = fixture(photosA: 1, photosB: 1, notesA: 0, notesB: 0, documentsA: 0, documentsB: 0, estimatesA: 0, estimatesB: 0, invoicesA: 0, invoicesB: 0, historyA: 0, historyB: 0)
        var wrongOrg = media(id: uid(1_002), job: jobA, kind: "photo", archived: false)
        wrongOrg["organizationId"] = uid(99)
        bodies[6] = page([media(id: uid(1_000), job: jobA, kind: "photo", archived: false),
                          media(id: uid(1_001), job: jobB, kind: "photo", archived: false), wrongOrg])
        let client = APIClient(session: URLProtocolFixture.session(bodies.map { .init(200, $0) }), baseURL: "https://app.thorbis.com")

        let compiled = try await CustomerJobCompilationLoader.load(customerID: customer, organizationID: org, api: client)

        XCTAssertEqual(compiled.photoCount, 2)
        XCTAssertEqual(compiled.photos.first?.items.map(\.id), ["media:\(uid(1_000))"])
        XCTAssertEqual(compiled.mediaIncompleteJobIDs, [jobA])
    }

    func testMixedModernAndLegacyPhotosCountOncePerJob() async throws {
        var bodies = fixture(photosA: 15, photosB: 19, notesA: 0, notesB: 0, documentsA: 0, documentsB: 0, estimatesA: 0, estimatesB: 0, invoicesA: 0, invoicesB: 0, historyA: 0, historyB: 0)
        bodies[14] = page([legacyPhoto(id: uid(20_000), job: jobA, key: "media/\(uid(1_000))")])
        bodies[15] = page([legacyPhoto(id: uid(20_001), job: jobB, key: "historical/unique")])
        let client = APIClient(session: URLProtocolFixture.session(bodies.map { .init(200, $0) }), baseURL: "https://app.thorbis.com")

        let compiled = try await CustomerJobCompilationLoader.load(customerID: customer, organizationID: org, api: client)

        XCTAssertEqual(compiled.photoCount, 35)
        XCTAssertEqual(compiled.photos.map(\.jobID), [jobA, jobB])
        XCTAssertEqual(compiled.photos.map(\.count), [15, 20])
        XCTAssertTrue(compiled.mediaIncompleteJobIDs.isEmpty)
    }

    func testConflictingSameKeyPhotoMetadataIsCountedOnceAndMarkedIncomplete() async throws {
        var bodies = fixture(photosA: 1, photosB: 0, notesA: 0, notesB: 0, documentsA: 0, documentsB: 0, estimatesA: 0, estimatesB: 0, invoicesA: 0, invoicesB: 0, historyA: 0, historyB: 0)
        var legacy = legacyPhoto(id: uid(20_000), job: jobA, key: "media/\(uid(1_000))")
        legacy["byteSize"] = 64
        bodies[14] = page([legacy])
        let client = APIClient(session: URLProtocolFixture.session(bodies.map { .init(200, $0) }), baseURL: "https://app.thorbis.com")

        let compiled = try await CustomerJobCompilationLoader.load(customerID: customer, organizationID: org, api: client)

        XCTAssertEqual(compiled.photoCount, 1)
        XCTAssertEqual(compiled.mediaIncompleteJobIDs, [jobA])
        guard case let .modern(_, fallback)? = compiled.photos.first?.items.first else { return XCTFail("Expected the verified modern photo") }
        XCTAssertNil(fallback, "Conflicting metadata must never become a legacy fallback")
    }

    func testFailedLegacyPhotoReadKeepsModernPhotosButMakesCountIncomplete() async throws {
        let bodies = fixture(photosA: 2, photosB: 1, notesA: 0, notesB: 0, documentsA: 0, documentsB: 0, estimatesA: 0, estimatesB: 0, invoicesA: 0, invoicesB: 0, historyA: 0, historyB: 0)
        var replies = bodies.map { URLProtocolFixture.Reply(200, $0) }
        replies[14] = URLProtocolFixture.Reply(500, #"{"title":"Unavailable","status":500}"#)
        let client = APIClient(session: URLProtocolFixture.session(replies), baseURL: "https://app.thorbis.com")

        let compiled = try await CustomerJobCompilationLoader.load(customerID: customer, organizationID: org, api: client)

        XCTAssertEqual(compiled.photoCount, 3)
        XCTAssertEqual(compiled.mediaIncompleteJobIDs, [jobA])
        XCTAssertTrue(compiled.documentIncompleteJobIDs.isEmpty, "A legacy-only failure does not make modern documents incomplete")
    }

    func testArchivedMediaIsLeftOutOfTheCustomerCounts() async throws {
        let replies = fixture(photosA: 1, photosB: 0, notesA: 0, notesB: 0, documentsA: 1, documentsB: 0, estimatesA: 0, estimatesB: 0, invoicesA: 0, invoicesB: 0, historyA: 0, historyB: 0, archivedPhotoOnA: true, archivedDocumentOnA: true)
        let client = APIClient(session: URLProtocolFixture.session(replies.map { .init(200, $0) }), baseURL: "https://app.thorbis.com")

        let compiled = try await CustomerJobCompilationLoader.load(customerID: customer, organizationID: org, api: client)

        XCTAssertEqual(compiled.photoCount, 1)
        XCTAssertEqual(compiled.documentCount, 1)
        XCTAssertEqual(compiled.photos.map(\.jobID), [jobA])
        XCTAssertNil(compiled.photos.first { $0.jobID == jobB })
    }

    func testRecordsThatAreNotOnAJobStayInTheTotals() async throws {
        var replies = fixture(photosA: 0, photosB: 0, notesA: 0, notesB: 0, documentsA: 0, documentsB: 0, estimatesA: 1, estimatesB: 0, invoicesA: 1, invoicesB: 0, historyA: 0, historyB: 0)
        // An estimate with no job link, and an invoice with no job, must still be counted.
        let looseEstimate = estimate(id: uid(70_000), title: "Not linked")
        let looseInvoice = invoice(id: uid(80_000), jobID: nil)
        replies[3] = page([estimate(id: uid(7_000), title: "On the job"), looseEstimate])
        replies[4] = page([invoice(id: uid(9_000), jobID: jobA), looseInvoice])
        replies[13] = page([
            ["occurredAt": "2026-08-01T12:00:00Z", "kind": "payment", "subjectId": uid(90), "summary": "Paid"],
            ["occurredAt": "2026-08-02T12:00:00Z", "kind": "contact", "subjectId": uid(50), "summary": "Added a contact"],
        ])
        let client = APIClient(session: URLProtocolFixture.session(replies.map { .init(200, $0) }), baseURL: "https://app.thorbis.com")

        let compiled = try await CustomerJobCompilationLoader.load(customerID: customer, organizationID: org, api: client)

        XCTAssertEqual(compiled.estimateCount, 2)
        XCTAssertEqual(compiled.estimates.map(\.count), [1])
        XCTAssertEqual(compiled.estimatesOffJob.map(\.title), ["Not linked"])
        XCTAssertEqual(compiled.invoiceCount, 2)
        XCTAssertEqual(compiled.invoices.map(\.count), [1])
        XCTAssertEqual(compiled.invoicesOffJob.count, 1)
        XCTAssertEqual(compiled.activityCount, 0)
        XCTAssertEqual(compiled.accountActivity.map(\.kind), ["payment", "contact"])
    }

    func testAnInvoiceThatExistsOnlyOnTheJobIsStillCounted() async throws {
        var replies = fixture(photosA: 0, photosB: 0, notesA: 0, notesB: 0, documentsA: 0, documentsB: 0, estimatesA: 0, estimatesB: 0, invoicesA: 0, invoicesB: 0, historyA: 0, historyB: 0)
        let onlyOnJob = invoice(id: uid(9_500), jobID: jobA)
        replies[4] = page([])
        replies[8] = page([onlyOnJob])
        let client = APIClient(session: URLProtocolFixture.session(replies.map { .init(200, $0) }), baseURL: "https://app.thorbis.com")

        let compiled = try await CustomerJobCompilationLoader.load(customerID: customer, organizationID: org, api: client)

        XCTAssertEqual(compiled.invoiceCount, 1)
        XCTAssertEqual(compiled.invoices.map(\.jobID), [jobA])
        XCTAssertEqual(compiled.invoices.first?.items.map(\.id), [uid(9_500)])
        XCTAssertTrue(compiled.invoicesOffJob.isEmpty)
    }

    func testAJobInvoiceAlreadyOnTheCustomerListIsNotCountedTwice() async throws {
        var replies = fixture(photosA: 0, photosB: 0, notesA: 0, notesB: 0, documentsA: 0, documentsB: 0, estimatesA: 0, estimatesB: 0, invoicesA: 1, invoicesB: 0, historyA: 0, historyB: 0)
        replies[8] = page([
            invoice(id: uid(9_000), jobID: jobA),
            invoice(id: uid(9_500), jobID: jobA),
        ])
        let client = APIClient(session: URLProtocolFixture.session(replies.map { .init(200, $0) }), baseURL: "https://app.thorbis.com")

        let compiled = try await CustomerJobCompilationLoader.load(customerID: customer, organizationID: org, api: client)

        XCTAssertEqual(compiled.invoiceCount, 2)
        XCTAssertEqual(compiled.invoices.first?.items.map(\.id), [uid(9_000), uid(9_500)])
    }

    func testAMissingJobInvoiceRouteKeepsTheCustomerList() async throws {
        let bodies = fixture(photosA: 1, photosB: 0, notesA: 0, notesB: 0, documentsA: 0, documentsB: 0, estimatesA: 0, estimatesB: 0, invoicesA: 1, invoicesB: 0, historyA: 0, historyB: 0)
        var replies = bodies.map { URLProtocolFixture.Reply(200, $0) }
        replies[8] = URLProtocolFixture.Reply(404, #"{"title":"Not found","status":404,"detail":"No job invoices"}"#)
        replies[12] = URLProtocolFixture.Reply(405, #"{"title":"Method not allowed","status":405}"#)
        let client = APIClient(session: URLProtocolFixture.session(replies), baseURL: "https://app.thorbis.com")

        let compiled = try await CustomerJobCompilationLoader.load(customerID: customer, organizationID: org, api: client)

        XCTAssertEqual(compiled.invoiceCount, 1)
        XCTAssertEqual(compiled.photoCount, 1)
        XCTAssertEqual(compiled.invoices.first?.items.map(\.id), [uid(9_000)])
    }

    func testAnotherJobInvoiceFailureStillFailsTheCompilation() async throws {
        let bodies = fixture(photosA: 0, photosB: 0, notesA: 0, notesB: 0, documentsA: 0, documentsB: 0, estimatesA: 0, estimatesB: 0, invoicesA: 1, invoicesB: 0, historyA: 0, historyB: 0)
        var replies = bodies.map { URLProtocolFixture.Reply(200, $0) }
        replies[8] = URLProtocolFixture.Reply(500, #"{"title":"Server error","status":500,"detail":"Unavailable"}"#)
        let client = APIClient(session: URLProtocolFixture.session(replies), baseURL: "https://app.thorbis.com")

        do {
            _ = try await CustomerJobCompilationLoader.load(customerID: customer, organizationID: org, api: client)
            XCTFail("A job invoice failure other than 404 or 405 must fail the compilation")
        } catch let problem as Problem {
            XCTAssertEqual(problem.status, 500)
        }
    }

    func testPhotosStillCompileWhenEstimatesAndInvoicesAreClosed() async throws {
        let replies = [
            page([job(id: jobA, title: "Water heater"), job(id: jobB, title: "AC not cooling")]),
            page([contact()]),
            page([location()]),
            page([]),
            page([media(id: uid(1_000), job: jobA, kind: "photo", archived: false), media(id: uid(1_001), job: jobA, kind: "photo", archived: false)]),
            page([]),
            page([media(id: uid(2_000), job: jobB, kind: "photo", archived: false)]),
            page([]),
            page([]),
            page([]),
        ]
        let client = APIClient(session: URLProtocolFixture.session(replies.map { .init(200, $0) }), baseURL: "https://app.thorbis.com")

        let compiled = try await CustomerJobCompilationLoader.load(
            customerID: customer,
            organizationID: org,
            api: client,
            access: CustomerRecordAccess(estimates: false, invoices: false)
        )

        XCTAssertEqual(compiled.photoCount, 3)
        XCTAssertEqual(compiled.estimateCount, 0)
        XCTAssertEqual(compiled.invoiceCount, 0)
        XCTAssertFalse(compiled.estimatesAccessible)
        XCTAssertFalse(compiled.invoicesAccessible)
        let paths = URLProtocolFixture.recorded.compactMap { $0.url?.path }
        XCTAssertFalse(paths.contains("/v1/estimates"))
        XCTAssertFalse(paths.contains("/v1/invoices"))
        XCTAssertFalse(paths.contains { $0.hasPrefix("/v1/jobs/") && ($0.hasSuffix("/estimates") || $0.hasSuffix("/invoices")) })
        XCTAssertEqual(paths.filter { $0.hasSuffix("/media") }.count, 2)
    }

    func testRepeatedActivityCursorIsPartialAndRetainsLoadedEntries() async throws {
        var replies = fixture(photosA: 0, photosB: 0, notesA: 0, notesB: 0, documentsA: 0, documentsB: 0, estimatesA: 0, estimatesB: 0, invoicesA: 0, invoicesB: 0, historyA: 1, historyB: 0)
        let first = ["items": [historyEntry(day: 1, job: jobA, summary: "First")], "nextCursor": "same"] as [String: Any]
        let second = ["items": [historyEntry(day: 2, job: jobA, summary: "Second")], "nextCursor": "same"] as [String: Any]
        replies[13] = String(decoding: try JSONSerialization.data(withJSONObject: first), as: UTF8.self)
        replies.insert(String(decoding: try JSONSerialization.data(withJSONObject: second), as: UTF8.self), at: 14)
        let client = APIClient(session: URLProtocolFixture.session(replies.map { .init(200, $0) }), baseURL: "https://app.thorbis.com")
        let compiled = try await CustomerJobCompilationLoader.load(customerID: customer, organizationID: org, api: client)
        XCTAssertTrue(compiled.activityIncomplete)
        XCTAssertEqual(compiled.activityCount, 2)
    }

    func testCustomerMoneyStillLoadsWhenJobsAreClosed() async throws {
        let replies = [
            page([contact()]),
            page([location()]),
            page([estimate(id: uid(7_000), title: "Loose estimate")]),
            page([invoice(id: uid(9_000), jobID: nil)]),
            page([["occurredAt": "2026-08-02T12:00:00Z", "kind": "contact", "subjectId": uid(50), "summary": "Added a contact"]]),
        ]
        let client = APIClient(session: URLProtocolFixture.session(replies.map { .init(200, $0) }), baseURL: "https://app.thorbis.com")

        let compiled = try await CustomerJobCompilationLoader.load(
            customerID: customer,
            organizationID: org,
            api: client,
            access: CustomerRecordAccess(jobs: false, estimates: true, invoices: true)
        )

        XCTAssertEqual(compiled.estimateCount, 1)
        XCTAssertEqual(compiled.estimatesOffJob.map(\.title), ["Loose estimate"])
        XCTAssertEqual(compiled.invoiceCount, 1)
        XCTAssertEqual(compiled.invoicesOffJob.map(\.id), [uid(9_000)])
        XCTAssertEqual(compiled.photoCount, 0)
        XCTAssertFalse(compiled.jobsAccessible)
        XCTAssertTrue(compiled.estimatesAccessible)
        XCTAssertTrue(compiled.invoicesAccessible)
        XCTAssertEqual(compiled.contacts.count, 1)
        XCTAssertEqual(compiled.locations.count, 1)
        XCTAssertEqual(compiled.accountActivity.map(\.kind), ["contact"])
        let paths = URLProtocolFixture.recorded.compactMap { $0.url?.path }
        XCTAssertFalse(paths.contains("/v1/jobs"))
        XCTAssertFalse(paths.contains { $0.hasPrefix("/v1/jobs/") })
        XCTAssertTrue(paths.contains("/v1/estimates"))
        XCTAssertTrue(paths.contains("/v1/invoices"))
        XCTAssertTrue(paths.contains("/v1/customers/\(customer)/history"))
    }

    func testAnInvoiceRowNamesTheInvoiceAndItsStatus() {
        let record = InvoiceRecord(
            id: uid(9_000), organizationId: org, customerId: customer, jobId: jobA, createdByUserId: author,
            locationId: nil, scheduleId: nil, origin: "manual", sourceOperationKey: "op", sourceEstimateId: nil,
            sourceEstimateRevisionNumber: nil, manualPhysicalServiceEvidence: nil, status: "issued", lines: [],
            linesRevision: 1, amountPaid: 0, currency: "USD", issuedAt: nil, paidAt: nil, voidedAt: nil,
            createdAt: "2026-07-01T12:00:00Z", updatedAt: "2026-07-01T12:00:00Z"
        )
        XCTAssertEqual(CustomerRecordLabel.invoice(record), "INV-9000 · Issued")
        let sameStatus = InvoiceRecord(
            id: uid(9_001), organizationId: org, customerId: customer, jobId: jobA, createdByUserId: author,
            locationId: nil, scheduleId: nil, origin: "manual", sourceOperationKey: "op", sourceEstimateId: nil,
            sourceEstimateRevisionNumber: nil, manualPhysicalServiceEvidence: nil, status: "issued", lines: [],
            linesRevision: 1, amountPaid: 0, currency: "USD", issuedAt: nil, paidAt: nil, voidedAt: nil,
            createdAt: "2026-07-01T12:00:00Z", updatedAt: "2026-07-01T12:00:00Z"
        )
        XCTAssertNotEqual(CustomerRecordLabel.invoice(record), CustomerRecordLabel.invoice(sameStatus))
    }

    func testRecordsActivityOpensTheNamedRecordAndLeavesAPaymentClosed() async throws {
        var replies = fixture(photosA: 0, photosB: 0, notesA: 0, notesB: 0, documentsA: 0, documentsB: 0, estimatesA: 1, estimatesB: 0, invoicesA: 1, invoicesB: 0, historyA: 0, historyB: 0)
        let estimateID = uid(7_000)
        let invoiceID = uid(9_000)
        let paymentID = uid(90)
        replies[13] = page([
            ["occurredAt": "2026-08-01T12:00:00Z", "kind": "job", "subjectId": jobA, "summary": "Booked"],
            ["occurredAt": "2026-08-02T12:00:00Z", "kind": "estimate", "subjectId": estimateID, "summary": "Sent"],
            ["occurredAt": "2026-08-03T12:00:00Z", "kind": "invoice", "subjectId": invoiceID, "summary": "Issued"],
            ["occurredAt": "2026-08-04T12:00:00Z", "kind": "payment", "subjectId": paymentID, "summary": "Paid"],
            ["occurredAt": "2026-08-05T12:00:00Z", "kind": "contact", "subjectId": uid(50), "summary": "Added a contact"],
            ["occurredAt": "2026-08-06T12:00:00Z", "kind": "location", "subjectId": uid(51), "summary": "Added a place"],
        ])
        let client = APIClient(session: URLProtocolFixture.session(replies.map { .init(200, $0) }), baseURL: "https://app.thorbis.com")

        let compiled = try await CustomerJobCompilationLoader.load(customerID: customer, organizationID: org, api: client)

        let grouped = compiled.activity.flatMap(\.items)
        XCTAssertEqual(grouped.map(\.kind).sorted(), ["estimate", "invoice", "job"])
        XCTAssertEqual(compiled.accountActivity.map(\.kind), ["payment", "contact", "location"])
        for entry in grouped + compiled.accountActivity {
            XCTAssertEqual(
                CustomerRecordsView.activityDestination(entry, customerID: customer),
                ActivityDestinationMapping.customerHistory(entry, customerID: customer)
            )
        }
        XCTAssertEqual(destination(in: grouped, kind: "job"), .job(jobA))
        XCTAssertEqual(destination(in: grouped, kind: "estimate"), .estimate(estimateID))
        XCTAssertEqual(destination(in: grouped, kind: "invoice"), .invoice(invoiceID))
        XCTAssertNil(destination(in: compiled.accountActivity, kind: "payment"))
        XCTAssertEqual(destination(in: compiled.accountActivity, kind: "contact"), .contact(customerID: customer, contactID: uid(50)))
        XCTAssertEqual(destination(in: compiled.accountActivity, kind: "location"), .location(customerID: customer, locationID: uid(51)))
    }

    private func destination(in entries: [CustomerHistoryEntry], kind: String) -> ActivityDestination? {
        let entry = try? XCTUnwrap(entries.first { $0.kind == kind })
        return entry.flatMap { CustomerRecordsView.activityDestination($0, customerID: customer) }
    }

    private func assertGrouped<Item>(_ groups: [CustomerJobGroup<Item>], counts: (Int, Int)) {
        XCTAssertEqual(groups.map(\.jobID), [jobA, jobB])
        XCTAssertEqual(groups.map(\.title), ["Water heater", "AC not cooling"])
        XCTAssertEqual(groups.map(\.count), [counts.0, counts.1])
    }

    private func assertCustomerQuery(_ request: URLProtocolFixture.RecordedRequest, path: String) {
        XCTAssertEqual(request.url?.path, path)
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertTrue(items.contains(URLQueryItem(name: "customerId", value: customer)))
    }

    /// Reply order matches CustomerJobCompilationLoader with estimates and invoices open: jobs, contacts, locations, estimates, invoices, then each job's notes, media, estimate links, and invoices, then history.
    private func fixture(photosA: Int, photosB: Int, notesA: Int, notesB: Int, documentsA: Int, documentsB: Int, estimatesA: Int, estimatesB: Int, invoicesA: Int, invoicesB: Int, historyA: Int, historyB: Int, archivedPhotoOnA: Bool = false, archivedDocumentOnA: Bool = false) -> [String] {
        let estimates = (0..<estimatesA).map { estimate(id: uid(7_000 + $0), title: "Estimate A \($0)") }
            + (0..<estimatesB).map { estimate(id: uid(8_000 + $0), title: "Estimate B \($0)") }
        let invoices = (0..<invoicesA).map { invoice(id: uid(9_000 + $0), jobID: jobA) }
            + (0..<invoicesB).map { invoice(id: uid(10_000 + $0), jobID: jobB) }
        let linksA = (0..<estimatesA).map { link(id: uid(11_000 + $0), job: jobA, estimate: uid(7_000 + $0)) }
        let linksB = (0..<estimatesB).map { link(id: uid(12_000 + $0), job: jobB, estimate: uid(8_000 + $0)) }
        var mediaA = (0..<photosA).map { media(id: uid(1_000 + $0), job: jobA, kind: "photo", archived: false) }
            + (0..<documentsA).map { media(id: uid(3_000 + $0), job: jobA, kind: "document", archived: false) }
        if archivedPhotoOnA { mediaA.append(media(id: uid(1_900), job: jobA, kind: "photo", archived: true)) }
        if archivedDocumentOnA { mediaA.append(media(id: uid(3_900), job: jobA, kind: "document", archived: true)) }
        let mediaB = (0..<photosB).map { media(id: uid(2_000 + $0), job: jobB, kind: "photo", archived: false) }
            + (0..<documentsB).map { media(id: uid(4_000 + $0), job: jobB, kind: "document", archived: false) }
        let history = (0..<historyA).map { historyEntry(day: $0 + 1, job: jobA, summary: "Job A \($0)") }
            + (0..<historyB).map { historyEntry(day: $0 + 1, job: jobB, summary: "Job B \($0)") }
        return [
            page([job(id: jobA, title: "Water heater"), job(id: jobB, title: "AC not cooling")]),
            page([contact()]),
            page([location()]),
            page(estimates),
            page(invoices),
            page((0..<notesA).map { note(id: uid(5_000 + $0), job: jobA, body: "Note A \($0)") }),
            page(mediaA),
            page(linksA),
            page([]),
            page((0..<notesB).map { note(id: uid(6_000 + $0), job: jobB, body: "Note B \($0)") }),
            page(mediaB),
            page(linksB),
            page([]),
            page(history),
            page([]),
            page([]),
        ]
    }

    private func page(_ items: [[String: Any]]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: ["items": items])
        return String(decoding: data, as: UTF8.self)
    }

    private func job(id: String, title: String) -> [String: Any] {
        ["id": id, "organizationId": org, "customerId": customer, "title": title, "status": "completed", "createdAt": "2026-07-01T12:00:00Z", "updatedAt": "2026-07-02T12:00:00Z"]
    }

    private func note(id: String, job: String, body: String) -> [String: Any] {
        ["id": id, "organizationId": org, "jobId": job, "authorUserId": author, "body": body, "createdAt": "2026-07-01T12:00:00Z"]
    }

    private func media(id: String, job: String, kind: String, archived: Bool) -> [String: Any] {
        ["id": id, "organizationId": org, "jobId": job, "uploaderUserId": author, "kind": kind, "mime": kind == "photo" ? "image/jpeg" : "application/pdf", "sizeBytes": 128, "originalFilename": "\(id).\(kind == "photo" ? "jpg" : "pdf")", "contentHash": "abc", "storageKey": "media/\(id)", "uploadState": "stored", "tags": [String](), "archived": archived, "createdAt": "2026-07-01T12:00:00Z", "updatedAt": "2026-07-01T12:00:00Z"]
    }

    private func legacyPhoto(id: String, job: String, key: String) -> [String: Any] {
        ["id": id, "organizationId": org, "jobId": job, "authorUserId": author,
         "contentType": "image/jpeg", "byteSize": 128, "storageKey": key, "createdAt": "2026-07-01T12:00:00Z"]
    }

    private func estimate(id: String, title: String) -> [String: Any] {
        ["id": id, "organizationId": org, "customerId": customer, "createdByUserId": author, "status": "draft", "title": title, "lines": [Any](), "createdAt": "2026-07-01T12:00:00Z", "updatedAt": "2026-07-01T12:00:00Z"]
    }

    private func invoice(id: String, jobID: String?) -> [String: Any] {
        var fields: [String: Any] = ["id": id, "organizationId": org, "customerId": customer, "createdByUserId": author, "origin": "manual", "sourceOperationKey": "op-\(id)", "status": "draft", "lines": [Any](), "linesRevision": 1, "amountPaid": 0, "currency": "USD", "createdAt": "2026-07-01T12:00:00Z", "updatedAt": "2026-07-01T12:00:00Z"]
        if let jobID { fields["jobId"] = jobID }
        return fields
    }

    private func link(id: String, job: String, estimate: String) -> [String: Any] {
        ["id": id, "jobId": job, "estimateId": estimate]
    }

    private func historyEntry(day: Int, job: String, summary: String) -> [String: Any] {
        ["occurredAt": String(format: "2026-07-%02dT12:%02d:00Z", min(day, 28), day % 60), "kind": "job", "subjectId": job, "summary": summary]
    }

    private func contact() -> [String: Any] {
        ["id": uid(50), "organizationId": org, "customerId": customer, "name": "Danielle Marlowe", "primary": true, "createdAt": "2026-07-01T12:00:00Z", "updatedAt": "2026-07-01T12:00:00Z"]
    }

    private func location() -> [String: Any] {
        ["id": uid(51), "organizationId": org, "customerId": customer, "label": "Home", "kind": "service", "address": "1 Main St", "createdAt": "2026-07-01T12:00:00Z", "updatedAt": "2026-07-01T12:00:00Z"]
    }
}

private func uid(_ n: Int) -> String { String(format: "00000000-0000-4000-8000-%012d", n) }

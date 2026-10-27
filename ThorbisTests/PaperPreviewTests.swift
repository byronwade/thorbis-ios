#if DEBUG
import XCTest
@testable import Thorbis

@MainActor
final class PaperPreviewTests: XCTestCase {
    func testRealSessionRestoreAndDomainDecodersUsePreviewFixtures() async throws {
        let api = PaperPreview.api()
        let session = SessionController(api: api, defaults: PaperPreview.defaults())
        await session.restore()
        XCTAssertEqual(session.phase, .ready, session.error ?? "")
        XCTAssertTrue(session.can("job.view", feature: "jobs"))
        XCTAssertTrue(session.can("estimate.create", feature: "estimate_option_signing"))
        XCTAssertTrue(session.can("estimate.discount", feature: "estimates"))
        XCTAssertTrue(session.can("invoice.edit", feature: "invoicing"))
        XCTAssertTrue(session.can("invoice.issue", feature: "invoicing"))
        let jobs = try await api.jobs()
        let customers = try await api.customers()
        XCTAssertEqual(jobs.count, 6)
        XCTAssertEqual(customers.count, 5)
        let job = try await api.fieldJob(PaperPreview.jobID)
        XCTAssertEqual(job.title, "AC not cooling")
        let customer = try await api.fieldCustomer(PaperPreview.customerID)
        XCTAssertEqual(customer.name, "Danielle Marlowe")
        let contacts = try await api.fieldContacts(PaperPreview.customerID)
        let locations = try await api.fieldLocations(PaperPreview.customerID)
        XCTAssertEqual(contacts.map(\.name), ["Danielle Marlowe", "Taylor Marlowe"])
        XCTAssertTrue(contacts[0].primary)
        XCTAssertFalse(contacts[1].primary)
        XCTAssertFalse(locations.isEmpty)
    }

    func testInvoiceEditorPreviewUsesReadOnlyInvoiceAndPriceBookFixtures() async throws {
        let invoice = PaperPreview.invoice
        XCTAssertEqual(invoice.status, "draft")
        XCTAssertEqual(invoice.lines.count, 3)
        XCTAssertEqual(invoice.linesRevision, 3)

        let page = try await PaperPreview.api().priceBookItems(limit: 50)
        XCTAssertEqual(page.items.first?.description, "Replace capacitor")
        XCTAssertEqual(page.items.first?.revision, 4)
        XCTAssertNil(page.nextCursor)

        let previewAPI = PaperPreview.api()
        let invoiceList = try await previewAPI.fieldInvoices()
        XCTAssertEqual(invoiceList.map(\.id), [PaperPreview.issuedInvoice.id])
        let issuedInvoice = try await previewAPI.fieldInvoice(PaperPreview.issuedInvoice.id)
        XCTAssertEqual(issuedInvoice.status, "issued")
        XCTAssertEqual(issuedInvoice.lines.count, 3)
        let payments = try await previewAPI.fieldPayments(issuedInvoice.id)
        XCTAssertTrue(payments.isEmpty)
    }

    func testPaperInvoiceBalanceReflectsUnpaidPartialPaidAndUnavailableStates() throws {
        let issued = PaperInvoiceBalance(invoice: PaperPreview.issuedInvoice, balanceCents: 44_000)
        XCTAssertEqual(issued.statusLabel, "Unpaid")
        XCTAssertEqual(issued.balanceCents, 44_000)

        var partialJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(PaperPreview.issuedInvoice)) as? [String: Any]
        )
        partialJSON["amountPaid"] = 10_000
        let partialInvoice = try JSONDecoder().decode(
            InvoiceRecord.self,
            from: JSONSerialization.data(withJSONObject: partialJSON)
        )
        let partial = PaperInvoiceBalance(invoice: partialInvoice, balanceCents: 34_000)
        XCTAssertEqual(partial.statusLabel, "Partially paid")
        XCTAssertEqual(partial.balanceCents, 34_000)

        let paid = PaperInvoiceBalance(invoice: PaperPreview.refundInvoice, balanceCents: 0)
        XCTAssertEqual(paid.statusLabel, "Paid")

        let unavailable = PaperInvoiceBalance(invoice: PaperPreview.issuedInvoice, balanceCents: nil)
        XCTAssertEqual(unavailable.statusLabel, "Balance unavailable")
        XCTAssertNil(unavailable.balanceCents)
    }

    @MainActor
    func testPaperInvoiceContentStateAdvancesWhenTheObservedModelLoads() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "thorbis.paper-invoice-content-state-test"))
        defaults.removePersistentDomain(forName: "thorbis.paper-invoice-content-state-test")
        let model = InvoicePaymentCollectionModel(
            api: PaperPreview.api(),
            invoiceID: PaperPreview.issuedInvoice.id,
            intentStore: InvoicePaymentIntentStore(defaults: defaults)
        )

        XCTAssertEqual(PaperInvoiceContentState.resolve(invoiceID: PaperPreview.issuedInvoice.id, model: model), .loading)
        await model.load()
        XCTAssertEqual(PaperInvoiceContentState.resolve(invoiceID: PaperPreview.issuedInvoice.id, model: model), .ready)
    }

    func testPaymentRefundPreviewUsesAConsistentRecordedPaymentFixture() async throws {
        let api = PaperPreview.api()
        let invoice = try await api.fieldInvoice(PaperPreview.refundInvoice.id)
        let payments = try await api.fieldPayments(PaperPreview.refundInvoice.id)

        XCTAssertEqual(payments.count, 1)
        XCTAssertEqual(invoice.amountPaid, payments[0].amount.amount)
        XCTAssertEqual(payments[0].invoiceId, invoice.id)
        XCTAssertEqual(payments[0].status.rawValue, "recorded")
    }

    func testPaymentRefundPreviewRejectsRefundSubmission() async {
        do {
            _ = try await PaperPreview.api().refundFieldPayment(
                PaperPreview.refundPayment.id,
                reason: "Sample refund for design review."
            )
            XCTFail("Design previews must remain read-only")
        } catch let problem as Problem {
            XCTAssertEqual(problem.status, 405)
            XCTAssertTrue(problem.localizedDescription.localizedCaseInsensitiveContains("cannot be changed"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testEstimateRevisionPreviewUsesPaperFixtureAndPreservesPriceBookRevision() throws {
        let estimate = PaperPreview.estimate
        let state = EstimateRevisionEditorState(estimate: estimate)

        XCTAssertEqual(estimate.status, "sent")
        XCTAssertEqual(estimate.currentRevisionNumber, 2)
        XCTAssertEqual(estimate.lines.count, 2)
        XCTAssertEqual(estimate.options?.count, 1)
        XCTAssertFalse(state.hasChanges)
        XCTAssertFalse(state.hasUnsupportedLineSources)
        XCTAssertEqual(state.lines.last?.source, .priceBookSelection(
            itemID: "00000000-0000-4000-8000-000000009201", revision: 4
        ))
    }

    func testPublicEstimatePreviewUsesAnIssuedPaperAndTwoSelectablePackages() async throws {
        let action = try await PaperPreview.api().publicDocumentAction(token: "preview-estimate")

        XCTAssertEqual(action.title, "AC not cooling — Compressor replacement")
        XCTAssertEqual(action.status, .sent)
        XCTAssertEqual(action.options?.map(\.title), ["Compressor repair", "Full system replacement"])
        XCTAssertTrue(action.signingOffered)
        XCTAssertTrue(action.html?.contains("Danielle Marlowe") == true)
    }

    func testEveryRequestIsInterceptedAndUnknownHostsNeverFallThrough() async throws {
        let session = PaperPreview.transport()
        for raw in ["https://example.invalid/unreachable", "https://app.thorbis.com/unknown"] {
            let (_, response) = try await session.data(from: XCTUnwrap(URL(string: raw)))
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 404)
            XCTAssertTrue(PaperPreviewProtocol.canInit(with: URLRequest(url: try XCTUnwrap(URL(string: raw)))))
        }
    }

    func testMutationsAreRejectedEvenForKnownFixtureRoutes() async throws {
        let session = PaperPreview.transport()
        for method in ["POST", "PUT", "PATCH", "DELETE"] {
            var request = URLRequest(url: try XCTUnwrap(URL(string: "https://app.thorbis.com/v1/jobs")))
            request.httpMethod = method
            let (body, response) = try await session.data(for: request)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 405)
            XCTAssertTrue(String(decoding: body, as: UTF8.self).contains("read-only"))
        }
    }

    func testDefaultsAreIsolatedFromOtherPreviewSessions() {
        let first = PaperPreview.defaults()
        let second = PaperPreview.defaults()
        first.set(true, forKey: "thorbis.session.explicitlySignedOut")
        XCTAssertFalse(second.bool(forKey: "thorbis.session.explicitlySignedOut"))
    }
}
#endif

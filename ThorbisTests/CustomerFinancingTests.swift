import XCTest
@testable import Thorbis

final class CustomerFinancingTests: XCTestCase {
    private let offerJSON = #"""
    {"available":true,"provider":"wisetack","providerName":"Wisetack",
     "minimum":{"amount":50000,"currency":"USD"},"maximum":{"amount":2500000,"currency":"USD"},
     "disclosure":"Lender terms.","creditCheckNote":null,
     "examples":[
       {"amount":{"amount":985000,"currency":"USD"},"available":true,"monthlyAmount":{"amount":20924,"currency":"USD"},
        "termMonths":60,"aprBasisPoints":999,"terms":"60 months at 9.99% APR. Subject to approval."},
       {"amount":{"amount":48000,"currency":"USD"},"available":false,"monthlyAmount":null,"termMonths":null,"aprBasisPoints":null,"terms":null},
       {"amount":{"amount":238500,"currency":"USD"},"available":true,"monthlyAmount":null,"termMonths":null,"aprBasisPoints":null,"terms":null}
     ]}
    """#

    private func offer() throws -> FinancingOffer {
        try JSONDecoder().decode(FinancingOffer.self, from: Data(offerJSON.utf8))
    }

    private func application(_ status: String, approved: Int? = nil) -> FinancingApplication {
        FinancingApplication(id: "a", invoiceId: "i", provider: "wisetack", providerName: "Wisetack", status: status,
                             amount: FieldMoney(amount: 985_000, currency: "USD"),
                             approvedAmount: approved.map { FieldMoney(amount: $0, currency: "USD") },
                             sentToLast4: "3344", paymentId: nil, createdAt: "", updatedAt: "")
    }

    func testTheMonthlyLineAlwaysComesWithItsTerms() throws {
        let example = try XCTUnwrap(try offer().example(for: 985_000))
        XCTAssertEqual(FinancingWords.monthly(example), "or as low as \(money(20_924, currency: "USD"))/mo")
        XCTAssertEqual(example.terms, "60 months at 9.99% APR. Subject to approval.")
    }

    func testOutsideTheLendersRangeNothingShows() throws {
        XCTAssertNil(try offer().example(for: 48_000), "below $500 the line is absent, not disabled")
        XCTAssertNil(try offer().example(for: 12_345), "an amount the server did not answer for shows nothing")
        XCTAssertNil(FinancingOffer.off.example(for: 985_000))
    }

    func testNoLenderExampleMeansNoNumber() throws {
        let example = try XCTUnwrap(try offer().example(for: 238_500))
        XCTAssertNil(FinancingWords.monthly(example), "CP-14: no example, no monthly number")
    }

    func testStatusIsSaidInWordsWithoutACreditReason() {
        XCTAssertEqual(FinancingWords.status(application("sent"), forCustomer: true), "Application sent to •••• 3344")
        XCTAssertEqual(FinancingWords.status(application("approved", approved: 900_000), forCustomer: false),
                       "Approved for \(money(900_000, currency: "USD")) with Wisetack")
        XCTAssertEqual(FinancingWords.status(application("funded"), forCustomer: true), "Paid by Wisetack")
        XCTAssertEqual(FinancingWords.status(application("declined"), forCustomer: true), "Not approved. You can pay another way")
        XCTAssertEqual(FinancingWords.status(application("expired"), forCustomer: false), "Not approved. You can pay another way")
        XCTAssertNil(FinancingWords.status(application("canceled"), forCustomer: true))
        XCTAssertEqual(FinancingWords.status(application("canceled"), forCustomer: false), "Application canceled")
    }

    func testThePayScreenPreselectsNothingAndTheCommitNamesTheChoice() {
        var choice = CustomerPayChoice(dueText: "$9,850.00", canPayInFull: true, canFinance: true, selected: nil)
        XCTAssertEqual(choice.title, "Choose how to pay $9,850.00")
        XCTAssertEqual(choice.commitTitle, "Choose how to pay")
        XCTAssertEqual(choice.hint, "Choose one above to continue.")
        choice.selected = .inFull
        XCTAssertEqual(choice.commitTitle, "Pay $9,850.00")
        choice.selected = .overTime
        XCTAssertEqual(choice.commitTitle, "Text me the application")
        XCTAssertNil(choice.hint)
    }

    func testTypedMobileNumbersBecomeE164() {
        XCTAssertEqual(FinancingWords.usMobile("(555) 201-3344"), "+15552013344")
        XCTAssertEqual(FinancingWords.usMobile("1 555.201.3344"), "+15552013344")
        XCTAssertNil(FinancingWords.usMobile("555-0134"))
        XCTAssertNil(FinancingWords.usMobile("(155) 201-3344"), "area codes never start with 1")
    }
    @MainActor
    func testFinancingResponsesStayOnRequestedInvoice() async throws {
        let invoice = "00000000-0000-4000-8000-000000000101"
        let other = "00000000-0000-4000-8000-000000000102"
        func response(_ invoiceID: String) throws -> String {
            let item: [String: Any] = ["id": "00000000-0000-4000-8000-000000000103", "invoiceId": invoiceID,
                "provider": "wisetack", "providerName": "Wisetack", "status": "sent", "amount": ["amount": 100000, "currency": "USD"],
                "sentToLast4": "3344", "createdAt": "2026-11-13T12:00:00Z", "updatedAt": "2026-11-13T12:00:00Z"]
            return String(decoding: try JSONSerialization.data(withJSONObject: item), as: UTF8.self)
        }
        let valid = try response(invoice), foreign = try response(other)
        let api = APIClient(session: URLProtocolFixture.session([.init(201, valid), .init(201, foreign), .init(200, "{\"applications\":[\(foreign)]}"), .init(200, valid)]), baseURL: "https://app.thorbis.com")
        let key = "00000000-0000-4000-8000-000000000104"
        let sent = try await api.sendFinancingApplication(invoiceID: invoice, idempotencyKey: key, phone: nil)
        XCTAssertEqual(sent.invoiceId, invoice)
        do { _ = try await api.sendFinancingApplication(invoiceID: invoice, idempotencyKey: key, phone: nil); XCTFail("Foreign invoice response must fail") }
        catch let problem as Problem { XCTAssertNil(problem.status, "An ambiguous result must preserve the request key") }
        catch { XCTFail("Expected a verification error") }
        do { _ = try await api.refreshFinancingApplications(invoiceID: invoice); XCTFail("Foreign invoice history must fail") } catch { }
        let otherApplication = "00000000-0000-4000-8000-000000000105"
        do { _ = try await api.cancelFinancingApplication(invoiceID: invoice, applicationID: otherApplication); XCTFail("A different application cannot be accepted") } catch { }
        XCTAssertEqual(URLProtocolFixture.recorded.map { $0.url?.path }, ["/v1/invoices/\(invoice)/financing-applications", "/v1/invoices/\(invoice)/financing-applications", "/v1/invoices/\(invoice)/financing-applications/refresh", "/v1/invoices/\(invoice)/financing-applications/\(otherApplication)/cancel"])
    }

}

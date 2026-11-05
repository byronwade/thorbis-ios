import XCTest
@testable import Thorbis

@MainActor
final class PaymentsCollectionTests: XCTestCase {
    private let paymentID = "00000000-0000-4000-8000-000000000101"
    private let invoiceID = "00000000-0000-4000-8000-000000000201"

    private func response(payment: String? = nil, invoice: String? = nil, amount: String = "12500", refunded: String = "2500", net: String = "10000", cursor: String? = nil) -> String {
        let id = payment ?? paymentID
        let next = cursor.map { "\"\($0)\"" } ?? "null"
        return "{\"schemaVersion\":1,\"resourceId\":\"payments\",\"purpose\":\"collection\",\"localMode\":\"online_required\",\"items\":[{\"id\":\"\(id)\",\"resourceId\":\"payments\",\"fields\":{\"payments.id\":\"\(id)\",\"payments.invoice_id\":\"\(invoice ?? invoiceID)\",\"payments.status\":\"recorded\",\"payments.method\":\"card\",\"payments.recorded_at\":\"2026-10-26T12:30:00Z\",\"payments.amount\":\"\(amount)\",\"payments.refunded_amount\":\"\(refunded)\",\"payments.net_amount\":\"\(net)\"}}],\"nextCursor\":\(next)}"
    }

    func testPaymentsPageUsesWebViewFreshReadAndPreservesRefunds() async throws {
        let cursor = paymentID
        let api = APIClient(session: URLProtocolFixture.session([.init(200, response(cursor: cursor))]), baseURL: "https://app.thorbis.com")
        let page = try await api.paymentsCollectionPage(isCurrent: { true })
        XCTAssertEqual(page.nextCursor, cursor)
        XCTAssertEqual(page.items.first?.invoiceID, invoiceID)
        XCTAssertEqual(page.items.first?.amount, 12500)
        XCTAssertEqual(page.items.first?.refundedAmount, 2500)
        XCTAssertEqual(page.items.first?.netAmount, 10000)
        let request = try XCTUnwrap(URLProtocolFixture.recorded.first)
        let parts = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertTrue(parts.contains { $0.name == "resourceId" && $0.value == "payments" })
        XCTAssertTrue(parts.contains { $0.name == "viewId" && $0.value == "payments.all" })
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(request.header("Cache-Control"), "no-cache")
    }

    func testFinancedPaymentIsReadableWithoutEnablingManualRecording() async throws {
        let body = response().replacingOccurrences(of: "\"payments.method\":\"card\"", with: "\"payments.method\":\"financing\"")
        let api = APIClient(session: URLProtocolFixture.session([.init(200, body)]), baseURL: "https://app.thorbis.com")
        let page = try await api.paymentsCollectionPage(isCurrent: { true })
        XCTAssertEqual(page.items.first?.method, .financing)
    }

    func testPaymentsPageRejectsWrongProjectionAndUnverifiableAmounts() async {
        let bad = [response(amount: "-1"), response(amount: "12500", refunded: "13000", net: "-500"),
                   response(amount: "12500", refunded: "2500", net: "9000"), response(invoice: "not-a-uuid"),
                   response().replacingOccurrences(of: "online_required", with: "complete")]
        for body in bad {
            let api = APIClient(session: URLProtocolFixture.session([.init(200, body)]), baseURL: "https://app.thorbis.com")
            do { _ = try await api.paymentsCollectionPage(isCurrent: { true }); XCTFail("Invalid projection must fail closed") }
            catch { }
        }
    }

    func testPaymentsPageRejectsInvalidOrRepeatingContinuation() async {
        let otherID = "00000000-0000-4000-8000-000000000102"
        for (body, cursor) in [(response(cursor: otherID), Optional<String>.none), (response(cursor: paymentID), Optional(paymentID))] {
            let api = APIClient(session: URLProtocolFixture.session([.init(200, body)]), baseURL: "https://app.thorbis.com")
            do { _ = try await api.paymentsCollectionPage(cursor: cursor, isCurrent: { true }); XCTFail("Invalid continuation must fail closed") }
            catch { }
        }
    }

    func testLatePaymentsErrorCannotEscapeAfterAuthorityChanges() async throws {
        let gate = URLProtocolFixture.Gate(); defer { gate.release() }
        let api = APIClient(session: URLProtocolFixture.session([.init(403, "{}", gate: gate)]), baseURL: "https://app.thorbis.com")
        var current = true
        let task = Task { try await api.paymentsCollectionPage(isCurrent: { current }) }
        for _ in 0..<100 where URLProtocolFixture.recorded.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
        current = false
        gate.release()
        do { _ = try await task.value; XCTFail("A stale error must not escape") }
        catch is CancellationError { }
        catch { XCTFail("Expected cancellation after authority changed") }
    }

    func testRowDistinguishesRecordedAndRefundedAmounts() {
        func item(_ status: FieldPaymentStatus, refunded: Int) -> PaymentsCollectionItem {
            PaymentsCollectionItem(id: paymentID, invoiceID: invoiceID, status: status, method: .card,
                recordedAt: "2026-10-26T12:30:00Z", amount: 12500, refundedAmount: refunded, netAmount: 12500 - refunded)
        }
        XCTAssertEqual(PaymentsCollectionRow(item: item(.recorded, refunded: 0)).statusLabel, "Recorded")
        XCTAssertEqual(PaymentsCollectionRow(item: item(.recorded, refunded: 2500)).statusLabel, "Partially refunded")
        XCTAssertEqual(PaymentsCollectionRow(item: item(.refunded, refunded: 12500)).statusLabel, "Refunded")
    }

    func testLatePaymentsPageCannotPublishAfterAuthorityChanges() async throws {
        let gate = URLProtocolFixture.Gate(); defer { gate.release() }
        let api = APIClient(session: URLProtocolFixture.session([.init(200, response(), gate: gate)]), baseURL: "https://app.thorbis.com")
        var current = true
        let task = Task { try await api.paymentsCollectionPage(isCurrent: { current }) }
        for _ in 0..<100 where URLProtocolFixture.recorded.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
        current = false
        gate.release()
        do { _ = try await task.value; XCTFail("A stale context must not return a page") }
        catch { }
    }
}

import XCTest
import CoreImage
@testable import Thorbis

@MainActor
final class PaymentLinkPresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let address = "https://pay.example.invalid/invoice/token?source=field%20app&key=a%2Bb"

    func testReadyLinkKeepsTheExactServerURLAndExpiry() {
        let expiry = now.addingTimeInterval(60)
        XCTAssertEqual(PaymentLinkPresentation(link: link(expires: expiry), at: now),
                       .ready(URL(string: address)!, expiresAt: expiry))
    }

    func testExpiryBoundaryRemovesActiveCheckout() {
        XCTAssertEqual(PaymentLinkPresentation(link: link(expires: now), at: now), .expired)
        XCTAssertEqual(PaymentLinkPresentation(link: link(expires: now.addingTimeInterval(-1)), at: now), .expired)
    }

    func testMalformedExpiryAndUnsafeURLsCannotBePresented() {
        XCTAssertEqual(PaymentLinkPresentation(link: .init(url: address, expiresAt: "not-a-date"), at: now), .unavailable)
        for url in ["http://pay.example.invalid/x", "https://user:password@pay.example.invalid/x",
                    "https://pay.example.invalid:8443/x", "https:///", "https://pay.example.invalid/has space"] {
            XCTAssertEqual(PaymentLinkPresentation(link: link(url: url), at: now), .unavailable, url)
        }
    }

    func testQRIndependentlyDecodesTheExactCheckoutPayload() throws {
        let image = try XCTUnwrap(PaymentLinkQRCode.image(for: URL(string: address)!))
        XCTAssertLessThanOrEqual(image.width, 1024)
        XCTAssertEqual(image.width, image.height)
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: CIContext(),
                                                options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let decoded = detector.features(in: CIImage(cgImage: image))
            .compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        XCTAssertEqual(decoded, [address])
    }

    func testOversizedQRStillKeepsAShareableValidLink() {
        let url = "https://pay.example.invalid/" + String(repeating: "x", count: 4096)
        XCTAssertNil(PaymentLinkQRCode.image(for: URL(string: url)!))
        guard case .ready(let shareURL, _) = PaymentLinkPresentation(link: link(url: url), at: now) else {
            return XCTFail("An encoding limit must not remove Share and Copy")
        }
        XCTAssertEqual(shareURL.absoluteString, url)
    }

    func testInvoiceBalanceMustStillMatchTheCreatedLink() {
        XCTAssertEqual(PaymentLinkInvoiceState(status: "issued", currency: "USD", balanceCents: 34000, requestedBalanceCents: 34000), .ready)
        XCTAssertEqual(PaymentLinkInvoiceState(status: "issued", currency: "USD", balanceCents: 24000, requestedBalanceCents: 34000), .changed)
        XCTAssertEqual(PaymentLinkInvoiceState(status: "voided", currency: "USD", balanceCents: 34000, requestedBalanceCents: 34000), .changed)
        XCTAssertEqual(PaymentLinkInvoiceState(status: "issued", currency: "EUR", balanceCents: 34000, requestedBalanceCents: 34000), .changed)
    }

    func testPaidNeedsCanonicalPaidStatusAndZeroBalance() {
        XCTAssertEqual(PaymentLinkInvoiceState(status: "paid", currency: "USD", balanceCents: 0, requestedBalanceCents: 34000), .paid)
        XCTAssertEqual(PaymentLinkInvoiceState(status: "issued", currency: "USD", balanceCents: 0, requestedBalanceCents: 34000), .changed)
        XCTAssertEqual(PaymentLinkInvoiceState(status: "paid", currency: "USD", balanceCents: 100, requestedBalanceCents: 34000), .changed)
        XCTAssertEqual(PaymentLinkInvoiceState(status: nil, currency: nil, balanceCents: nil, requestedBalanceCents: 34000), .changed)
    }

    private func link(url: String? = nil, expires: Date? = nil) -> FieldInvoicePayLink {
        .init(url: url ?? address,
              expiresAt: ISO8601DateFormatter().string(from: expires ?? now.addingTimeInterval(60)))
    }
}

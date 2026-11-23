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

    func testQRIndependentlyDecodesTheExactCheckoutPayload() async throws {
        let rendered = await PaymentLinkQRCode.image(for: URL(string: address)!)
        let image = try XCTUnwrap(rendered)
        XCTAssertLessThanOrEqual(image.width, 1024)
        XCTAssertEqual(image.width, image.height)
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: CIContext(),
                                                options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let decoded = detector.features(in: CIImage(cgImage: image))
            .compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        XCTAssertEqual(decoded, [address])
    }

    /// The code used to be drawn inside a view's task, on the main actor, and held the screen for
    /// the whole drawing. This suite runs on the main actor, as a view's task does.
    func testQRIsDrawnOffTheMainThread() async {
        XCTAssertNotEqual(pthread_main_np(), 0, "The test itself must start on the main thread to prove anything")
        let drawn = await PaymentLinkQRCode.drawn(for: URL(string: address)!)
        XCTAssertNotNil(drawn.image)
        XCTAssertFalse(drawn.onMainThread, "The drawing itself must not run on the main thread")
    }

    func testOnlyAReadyLinkShowsACodeAndOnlyItsOwn() async throws {
        let url = URL(string: address)!
        let other = URL(string: "https://pay.example.invalid/invoice/another")!
        let expiry = now.addingTimeInterval(60)
        let rendered = await PaymentLinkQRCode.image(for: url)
        let image = try XCTUnwrap(rendered)
        let drawn: (url: URL, image: CGImage?) = (url, image)
        XCTAssertTrue(PaymentLinkPresentation.ready(url, expiresAt: expiry).code(from: drawn) === image)
        XCTAssertNil(PaymentLinkPresentation.ready(other, expiresAt: expiry).code(from: drawn), "Another link's code is never shown")
        XCTAssertNil(PaymentLinkPresentation.ready(url, expiresAt: expiry).code(from: nil), "Nothing is shown while the code is being drawn")
        XCTAssertNil(PaymentLinkPresentation.ready(url, expiresAt: expiry).code(from: (url, nil)), "A link too long to draw has no code")
        XCTAssertNil(PaymentLinkPresentation.expired.code(from: drawn), "An expired link shows no code, even one already drawn")
        XCTAssertNil(PaymentLinkPresentation.unavailable.code(from: drawn))
    }

    func testOversizedQRStillKeepsAShareableValidLink() async {
        let url = "https://pay.example.invalid/" + String(repeating: "x", count: 4096)
        let oversized = await PaymentLinkQRCode.image(for: URL(string: url)!)
        XCTAssertNil(oversized)
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

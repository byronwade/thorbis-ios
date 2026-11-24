import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

enum PaymentLinkPresentation: Equatable {
    case ready(URL, expiresAt: Date)
    case expired
    case unavailable

    init(link: FieldInvoicePayLink?, at date: Date) {
        guard let link, let url = link.shareURL, let host = url.host, !host.isEmpty,
              link.url.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              url.absoluteString == link.url,
              let expiry = JobFiltering.date(link.expiresAt) else {
            self = .unavailable
            return
        }
        self = expiry > date ? .ready(url, expiresAt: expiry) : .expired
    }

    /// The drawn code this link may show. Only a ready link shows one, and only the code drawn
    /// for its own address: an expired link shows none, however recently one was drawn for it.
    func code(from drawn: (url: URL, image: CGImage?)?) -> CGImage? {
        guard case .ready(let url, _) = self, let drawn, drawn.url == url else { return nil }
        return drawn.image
    }
}

enum PaymentLinkInvoiceState: Equatable {
    case ready, paid, changed

    init(status: String?, currency: String?, balanceCents: Int?, requestedBalanceCents: Int?) {
        if status == "paid", currency == "USD", balanceCents == 0 {
            self = .paid
        } else if status == "issued", currency == "USD", let balanceCents,
                  balanceCents > 0, balanceCents == requestedBalanceCents {
            self = .ready
        } else {
            self = .changed
        }
    }
}

enum PaymentLinkQRCode {
    /// Bounded local rendering with four modules of quiet zone and integer scaling.
    /// Long URLs keep Share/Copy; they never trigger unbounded image allocation.
    ///
    /// Always drawn on a detached task, and there is no synchronous way in. A view's task runs on
    /// the main actor, and the code used to be drawn there: on a busy CI machine the app's main
    /// thread did not answer for 18 seconds while it drew (BYR-1839).
    static func image(for url: URL) async -> CGImage? {
        await drawn(for: url).image
    }

    /// What `image(for:)` hands back, with whether the drawing itself ran on the main thread.
    static func drawn(for url: URL) async -> (image: CGImage?, onMainThread: Bool) {
        let result = await Task.detached(priority: .userInitiated) { draw(url) }.value
        return (result.image, result.onMainThread)
    }

    /// A finished image never changes, so it is safe to hand from the drawing task to the caller.
    private struct Drawn: @unchecked Sendable {
        let image: CGImage?
        let onMainThread: Bool
    }

    private nonisolated static func draw(_ url: URL) -> Drawn {
        Drawn(image: pixels(for: url), onMainThread: pthread_main_np() != 0)
    }

    private nonisolated static func pixels(for url: URL) -> CGImage? {
        let data = Data(url.absoluteString.utf8)
        guard data.count <= 2048 else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let code = filter.outputImage else { return nil }
        let extent = CGRect(x: 0, y: 0, width: code.extent.width + 8, height: code.extent.height + 8)
        let white = CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: extent)
        let padded = code.transformed(by: CGAffineTransform(translationX: 4, y: 4)).composited(over: white)
        let scale = max(1, min(8, floor(1024 / extent.width)))
        let scaled = padded.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }
}

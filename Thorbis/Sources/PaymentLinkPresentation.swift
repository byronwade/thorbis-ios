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
    static func image(for url: URL) -> CGImage? {
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

import MapKit
import SwiftUI

/// The single typed outbound-link adapter (apps/mobile AGENTS.md, GAP-APP-003).
/// It only builds call, message, email and Maps hand-offs from record fields.
/// There is no arbitrary URL input and no purchase or checkout destination.
enum OutboundLink {
    case call(String)
    case message(String)
    case email(String)

    var url: URL? {
        switch self {
        case let .call(number):
            let digits = number.filter { $0.isNumber || $0 == "+" }
            return digits.isEmpty ? nil : URL(string: "tel:\(digits)")
        case let .message(number):
            let digits = number.filter { $0.isNumber || $0 == "+" }
            return digits.isEmpty ? nil : URL(string: "sms:\(digits)")
        case let .email(address):
            guard address.contains("@"), let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) else { return nil }
            return URL(string: "mailto:\(encoded)")
        }
    }

    var title: String {
        switch self {
        case .call: "Call"
        case .message: "Message"
        case .email: "Email"
        }
    }

    var symbol: String {
        switch self {
        case .call: "phone"
        case .message: "message"
        case .email: "envelope"
        }
    }

    /// Driving directions in Apple Maps for a street address.
    @MainActor
    static func directions(to address: String, name: String) async -> Bool {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = address
        request.resultTypes = .address
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return false }
        item.name = name
        return item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}

/// A row of contact hand-offs, each a full 44pt target with a visible word.
struct ContactActions: View {
    let phone: String?
    let email: String?
    @Environment(\.openURL) private var openURL

    private var links: [OutboundLink] {
        var links: [OutboundLink] = []
        if let phone, !phone.isEmpty { links += [.call(phone), .message(phone)] }
        if let email, !email.isEmpty { links.append(.email(email)) }
        return links.filter { $0.url != nil }
    }

    var body: some View {
        if !links.isEmpty {
            HStack(spacing: Theme.Space.m) {
                ForEach(links, id: \.title) { link in
                    Button {
                        if let url = link.url { openURL(url) }
                    } label: {
                        Label(link.title, systemImage: link.symbol)
                            .labelStyle(.titleAndIcon)
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.rim)
                }
            }
        }
    }
}

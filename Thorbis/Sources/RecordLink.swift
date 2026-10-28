import Foundation

/// `thorbis://customer/<id>`, `thorbis://estimate/<id>` and `thorbis://invoice/<id>`: open one record
/// from a notification, a shortcut or another app (BYR-416 deep links). Jobs keep `JobActivityLink`.
/// A link only says where to go; the screen it opens still asks the server, which decides access.
enum RecordLink: Hashable {
    case customer(String)
    case estimate(String)
    case invoice(String)

    init?(url: URL) {
        guard url.scheme == "thorbis", let host = url.host()?.lowercased(),
              let id = url.pathComponents.dropFirst().first, UUID(uuidString: id) != nil else { return nil }
        switch host {
        case "customer": self = .customer(id)
        case "estimate": self = .estimate(id)
        case "invoice": self = .invoice(id)
        default: return nil
        }
    }

    /// The push payload's `thorbis` object may name one record besides a job.
    init?(push thorbis: [String: Any]) {
        if let id = thorbis["invoiceId"] as? String, UUID(uuidString: id) != nil { self = .invoice(id) }
        else if let id = thorbis["estimateId"] as? String, UUID(uuidString: id) != nil { self = .estimate(id) }
        else if let id = thorbis["customerId"] as? String, UUID(uuidString: id) != nil { self = .customer(id) }
        else { return nil }
    }

    var url: URL? {
        switch self {
        case .customer(let id): URL(string: "thorbis://customer/\(id)")
        case .estimate(let id): URL(string: "thorbis://estimate/\(id)")
        case .invoice(let id): URL(string: "thorbis://invoice/\(id)")
        }
    }

    /// The capability and feature the destination needs; without them the link is ignored.
    var access: (capability: String, feature: String) {
        switch self {
        case .customer: ("customer.view", "core_crm")
        case .estimate: ("estimate.view", "estimates")
        case .invoice: ("invoice.view", "invoicing")
        }
    }
}

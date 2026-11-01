import SwiftUI

// Customer financing (design.thorbis.com/customer-presentation, CP-13..CP-18). The lender is
// Wisetack: the server answers what to say beside a total, texts the application to the
// customer's own phone, and reads the answer back. Nothing here decides a rate or a price.

// MARK: - Wire shapes (services/api /v1/financing, /v1/invoices/{id}/financing-applications)

struct FinancingExample: Codable, Hashable {
    let amount: FieldMoney
    /// False outside the lender's range: nothing about financing shows for this amount.
    let available: Bool
    let monthlyAmount: FieldMoney?
    let termMonths: Int?
    let aprBasisPoints: Int?
    /// "60 months at 9.99% APR. Subject to approval." Always shown with the monthly number (CP-14).
    let terms: String?
}

struct FinancingOffer: Codable, Hashable {
    let available: Bool
    let provider: String?
    let providerName: String?
    let minimum: FieldMoney?
    let maximum: FieldMoney?
    let disclosure: String?
    let creditCheckNote: String?
    let examples: [FinancingExample]

    static let off = FinancingOffer(available: false, provider: nil, providerName: nil, minimum: nil, maximum: nil,
                                    disclosure: nil, creditCheckNote: nil, examples: [])

    /// The example for exactly this amount, only when the lender finances it.
    func example(for cents: Int) -> FinancingExample? {
        guard available else { return nil }
        return examples.first { $0.amount.amount == cents && $0.available }
    }

    var lenderName: String { providerName ?? "the lender" }
}

struct FinancingApplication: Codable, Hashable, Identifiable {
    let id: String
    let invoiceId: String
    let provider: String
    let providerName: String
    let status: String
    let amount: FieldMoney
    let approvedAmount: FieldMoney?
    let sentToLast4: String
    let paymentId: String?
    let createdAt: String
    let updatedAt: String

    var isOpen: Bool { ["preparing", "sent", "approved"].contains(status) }
}

private struct FinancingApplicationList: Decodable { let applications: [FinancingApplication] }

@MainActor
extension APIClient {
    /// The lender's line for each amount. Off, held or not permitted all read as "no financing".
    func financingOffer(amounts: [Int]) async -> FinancingOffer {
        let unique = Array(Set(amounts.filter { $0 > 0 })).sorted().prefix(10)
        guard !unique.isEmpty else { return .off }
        let items = unique.map { URLQueryItem(name: "amount", value: String($0)) }
        return (try? await send("GET", "/v1/financing/offer", queryItems: items)) ?? .off
    }

    /// Reads open applications back from the lender first, so a funded loan shows as paid.
    func refreshFinancingApplications(invoiceID: String) async throws -> [FinancingApplication] {
        struct Empty: Encodable {}
        let list: FinancingApplicationList = try await send(
            "POST", financialPath("/v1/invoices", id: invoiceID, suffix: "/financing-applications/refresh"), body: Empty())
        return list.applications
    }

    func cancelFinancingApplication(invoiceID: String, applicationID: String) async throws -> FinancingApplication {
        struct Empty: Encodable {}
        guard UUID(uuidString: applicationID) != nil else { throw URLError(.badURL) }
        return try await send("POST", financialPath("/v1/invoices", id: invoiceID, suffix: "/financing-applications/\(applicationID.lowercased())/cancel"),
                              body: Empty())
    }

    /// The lender texts the application to `phone`, or to the customer's mobile on file.
    func sendFinancingApplication(invoiceID: String, idempotencyKey: String, phone: String?) async throws -> FinancingApplication {
        struct Body: Encodable { let idempotencyKey: String; let phone: String? }
        return try await send("POST", financialPath("/v1/invoices", id: invoiceID, suffix: "/financing-applications"),
                              body: Body(idempotencyKey: idempotencyKey, phone: phone))
    }
}

// MARK: - Words (CP-14, CP-17, CP-18)

enum FinancingWords {
    /// The server feature that holds every financing route (internal until launch).
    static let feature = "consumer_financing"

    /// "or as low as $209.24/mo", or nil when the lender gave no example (CP-14).
    static func monthly(_ example: FinancingExample) -> String? {
        guard let monthly = example.monthlyAmount, example.terms != nil else { return nil }
        return "or as low as \(money(monthly.amount, currency: monthly.currency))/mo"
    }

    /// One line in words for the invoice, or nil when there is nothing to say to this reader.
    /// Canceled applications are the staff's business, never the customer's.
    static func status(_ application: FinancingApplication, forCustomer: Bool) -> String? {
        switch application.status {
        case "preparing", "sent": return "Application sent to •••• \(application.sentToLast4)"
        case "approved":
            let amount = application.approvedAmount ?? application.amount
            return "Approved for \(money(amount.amount, currency: amount.currency)) with \(application.providerName)"
        case "funded": return "Paid by \(application.providerName)"
        case "declined", "expired": return "Not approved. You can pay another way"
        case "failed": return "Couldn't send the application. Try again"
        case "canceled": return forCustomer ? nil : "Application canceled"
        default: return nil
        }
    }

    /// A US mobile typed any way ("(555) 201-3344", "555.201.3344") as +1 and ten digits.
    static func usMobile(_ typed: String) -> String? {
        var digits = typed.filter(\.isNumber)
        if digits.count == 11, digits.hasPrefix("1") { digits.removeFirst() }
        guard digits.count == 10, let area = digits.first, let exchange = digits.dropFirst(3).first,
              area != "0", area != "1", exchange != "0", exchange != "1" else { return nil }
        return "+1\(digits)"
    }
}

// MARK: - Pay screen state

/// "Choose how to pay $total": two sibling cards, neither pre-selected (CP-15).
struct CustomerPayChoice: Equatable {
    enum Method: Equatable { case inFull, overTime }

    let dueText: String
    let canPayInFull: Bool
    let canFinance: Bool
    var selected: Method?

    var title: String { "Choose how to pay \(dueText)" }

    /// CP-07: the commit names what happens next.
    var commitTitle: String {
        switch selected {
        case .inFull: return "Pay \(dueText)"
        case .overTime: return "Text me the application"
        case nil: return "Choose how to pay"
        }
    }

    var hint: String? { selected == nil ? "Choose one above to continue." : nil }
}

// MARK: - Views

/// The monthly line one size under a total (CP-13) and its terms right under it (CP-14).
struct CustomerFinancingLine: View {
    let example: FinancingExample
    let type: CustomerType

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let monthly = FinancingWords.monthly(example), let terms = example.terms {
                Text(monthly).font(Theme.monoFont(type.heading, weight: .medium))
                    .minimumScaleFactor(0.7).lineLimit(1)
                Text(terms).font(Theme.font(type.small)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Pay over time available").font(Theme.font(type.body)).foregroundStyle(Theme.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The lender's disclosure, verbatim, behind "See terms" (CP-14).
struct FinancingTermsSheet: View {
    let offer: FinancingOffer
    let type: CustomerType
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(offer.disclosure ?? "")
                    .font(Theme.font(type.body))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.gutter)
            }
            .background(Theme.background)
            .foregroundStyle(Theme.foreground)
            .navigationTitle("\(offer.lenderName) terms")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }.font(Theme.font(type.small, weight: .medium)).frame(minHeight: 44)
                }
            }
        }
    }
}

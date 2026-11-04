import SwiftUI

/// Not mounted in production while the server offer contract is held.
struct HeldCustomerOfferShop: View {
    let token: String
    let currentAuthority: @MainActor () -> Bool
    let onReview: (CustomerOfferQuote, [CustomerOfferSelection]) -> Void
    @EnvironmentObject private var api: APIClient
    @Environment(\.dismiss) private var dismiss
    @State private var cart: CustomerOfferCart
    @State private var busy = false
    @State private var loaded = false
    @State private var error: String?
    @State private var generation: UUID?

    init(token: String, revisionNumber: Int, contentHash: String, optionID: String?,
         currentAuthority: @escaping @MainActor () -> Bool,
         onReview: @escaping (CustomerOfferQuote, [CustomerOfferSelection]) -> Void) {
        self.token = token
        self.currentAuthority = currentAuthority
        self.onReview = onReview
        _cart = State(initialValue: CustomerOfferCart(revisionNumber: revisionNumber, contentHash: contentHash, optionID: optionID))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Optional work").font(Theme.customerFont(30, weight: .medium))
                    Text("Choose any extras you’d like. You’ll review the total before approving.")
                        .font(Theme.customerFont(20)).foregroundStyle(Theme.muted)
                    if let error {
                        Text(error).font(Theme.customerFont(20)).foregroundStyle(Theme.muted)
                        Button("Try again") { Task { await load() } }.frame(minHeight: 56)
                    } else if !loaded {
                        ProgressView("Loading options…").font(Theme.customerFont(20))
                    } else if cart.offers.isEmpty {
                        Text("There are no optional items for this estimate.").font(Theme.customerFont(20))
                    } else {
                        ForEach(cart.offers) { item in offerRow(item) }
                    }
                    if let quote = cart.quote {
                        Text("Review your total").font(Theme.customerFont(24, weight: .medium))
                        quoteGroup(title: quote.base.title ?? "Included work", lines: quote.base.lines, total: quote.base.totalAmount)
                        ForEach(quote.addOns, id: \.id) { item in quoteGroup(title: item.title, lines: item.lines, total: item.totalAmount) }
                        HStack { Text("Total"); Spacer(); Text(price(quote.totalAmount)) }
                            .font(Theme.customerFont(24, weight: .medium))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            VStack(spacing: 8) {
                if let quote = cart.quote {
                    Button("Continue with \(price(quote.totalAmount))") {
                        guard generation == api.requestGeneration, currentAuthority(), cart.quoteIsCurrent(now: Date()) else {
                            cart.invalidateQuote(); error = "This total expired. Please review it again."
                            return
                        }
                        onReview(quote, cart.selections)
                    }
                        .frame(maxWidth: .infinity, minHeight: 56)
                } else if loaded && error == nil {
                    Button("Review total") { Task { await requestQuote() } }
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                Button("Back") { dismiss() }.frame(minHeight: 56)
            }.font(Theme.customerFont(20, weight: .medium)).padding(.horizontal, 24)
        }
        .task { generation = api.requestGeneration; await load() }
        .onChange(of: api.requestGeneration) { _, _ in cart.retire(); loaded = false; error = "Ask your technician to reopen this estimate." }
    }

    private func offerRow(_ item: CustomerAvailableOffer) -> some View {
        let selected = cart.selections.first { $0.offerId == item.id.lowercased() }?.quantity
        return VStack(alignment: .leading, spacing: 8) {
            Text(item.title).font(Theme.customerFont(22, weight: .medium))
            Text(item.description).font(Theme.customerFont(20)).fixedSize(horizontal: false, vertical: true)
            Text("From \(price(item.totalAmount)) for \(item.quantityPolicy.min)")
                .font(Theme.customerFont(18)).foregroundStyle(Theme.muted)
            if let selected {
                HStack {
                    Button("Remove") { cart.setQuantity(nil, for: item.id) }.frame(minHeight: 56)
                    Spacer()
                    Button("−") { cart.setQuantity(selected - item.quantityPolicy.step, for: item.id) }
                        .frame(minWidth: 56, minHeight: 56).accessibilityLabel("Decrease \(item.title)")
                    Text("\(selected)").font(Theme.customerFont(20))
                    Button("+") { cart.setQuantity(selected + item.quantityPolicy.step, for: item.id) }
                        .frame(minWidth: 56, minHeight: 56).accessibilityLabel("Increase \(item.title)")
                }
            } else {
                Button("Add \(item.title)") { cart.setQuantity(item.quantityPolicy.min, for: item.id) }.frame(minHeight: 56)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func quoteGroup(title: String, lines: [CustomerOfferLine], total: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) { Text(title); Spacer(); Text(price(total)) }
                .font(Theme.customerFont(20, weight: .medium))
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line.description).font(Theme.customerFont(18)).fixedSize(horizontal: false, vertical: true)
                Text("\(line.quantity) × \(price(line.unitPrice)) · \(price(line.totalAmount))")
                    .font(Theme.customerFont(17)).foregroundStyle(Theme.muted)
            }
        }
    }

    private func price(_ cents: Int) -> String {
        money(cents, currency: "USD")
    }
    private func load() async {
        guard !busy, generation == api.requestGeneration, currentAuthority() else { return }
        busy = true; error = nil
        defer { busy = false }
        let ticket = cart.ticket
        do {
            let response = try await api.heldAvailableOffers(token: token, revisionNumber: cart.revisionNumber,
                optionID: cart.optionID, currentAuthority: currentAuthority)
            guard generation == api.requestGeneration, currentAuthority(), cart.install(response, ticket: ticket) else { return }
            loaded = true
        } catch is CancellationError {} catch { self.error = "We couldn’t load the options. Check your connection and try again." }
    }
    private func requestQuote() async {
        guard !busy, generation == api.requestGeneration, currentAuthority() else { return }
        busy = true; error = nil
        defer { busy = false }
        let ticket = cart.ticket
        do {
            let response = try await api.heldOfferQuote(token: token, revisionNumber: cart.revisionNumber,
                optionID: cart.optionID, selections: cart.selections, currentAuthority: currentAuthority)
            guard generation == api.requestGeneration, currentAuthority(), cart.install(response, ticket: ticket, now: Date()) else {
                error = "The estimate changed. Ask your technician to reopen it."
                return
            }
        } catch is CancellationError {} catch { self.error = "We couldn’t prepare the total. Check your connection and try again." }
    }
}

import SwiftUI
import UIKit

struct InvoicePaymentLinkView: View {
    @ObservedObject var model: InvoicePaymentCollectionModel
    let payLink: FieldInvoicePayLink?
    let requestedBalanceCents: Int?
    let customerName: String
    let isCreating: Bool
    let canCreate: Bool
    let error: String?
    let onCreate: () -> Void
    let onDone: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var renderedCode: (url: URL, image: CGImage)?
    @State private var copiedURL: URL?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(customerName).font(Theme.font(15)).foregroundStyle(Theme.muted)
                    MoneyFigure(label: "Balance due", cents: model.outstandingCents ?? 0,
                                currency: model.invoice?.currency ?? "USD")
                    if let error { ErrorBanner(message: error) }
                    if let loadError = model.loadError {
                        ErrorBanner(message: loadError) { await model.load() }
                    } else if model.isLoading || !model.historyComplete {
                        ProgressView("Checking invoice…").frame(maxWidth: .infinity, minHeight: 100)
                    } else if model.paymentTotalCents != model.invoice?.amountPaid {
                        Text("The invoice is updating. Check payment status before sharing a link.")
                            .font(Theme.font(15)).foregroundStyle(Theme.muted)
                    } else {
                        handoff(at: context.date)
                    }
                    if invoiceState != .paid || model.loadError != nil || !model.historyComplete ||
                        model.paymentTotalCents != model.invoice?.amountPaid {
                        Button { Task { await model.load() } } label: {
                            Label("Check payment status", systemImage: "arrow.clockwise")
                                .font(Theme.font(15, weight: .medium))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .disabled(model.isLoading || isCreating)
                        .accessibilityIdentifier("check-invoice-payment-status")
                    }
                }
                .frame(maxWidth: 520)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .refreshable { await model.load() }
        }
        .background(Theme.background.ignoresSafeArea())
        .foregroundStyle(Theme.foreground)
        .navigationTitle("Payment link")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ThorbisToolbarItem(placement: .topBarTrailing) {
                Button("Done", action: onDone).frame(minWidth: 44, minHeight: 44)
            }
        }
        .task(id: payLink?.url) {
            renderedCode = nil
            if let url = payLink?.shareURL, let image = PaymentLinkQRCode.image(for: url) {
                renderedCode = (url, image)
            }
            await model.load()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.load() } }
        }
    }

    private var invoiceState: PaymentLinkInvoiceState {
        .init(status: model.invoice?.status, currency: model.invoice?.currency,
              balanceCents: model.outstandingCents, requestedBalanceCents: requestedBalanceCents)
    }

    @ViewBuilder
    private func handoff(at date: Date) -> some View {
        switch invoiceState {
        case .paid:
            Label("Invoice paid", systemImage: "checkmark.circle.fill")
                .font(Theme.font(22, weight: .medium)).foregroundStyle(Theme.success)
                .accessibilityIdentifier("invoice-payment-confirmed")
        case .changed:
            recovery("Invoice changed", message: "The balance or invoice status has changed. Use a new link for the current balance.")
        case .ready:
            switch PaymentLinkPresentation(link: payLink, at: date) {
            case .ready(let url, let expiration):
                Text("Scan to pay").font(Theme.font(22, weight: .medium))
                if let renderedCode, renderedCode.url == url {
                    Image(uiImage: UIImage(cgImage: renderedCode.image))
                        .interpolation(.none).resizable().scaledToFit()
                        .frame(maxWidth: 280)
                        .padding(12)
                        .background(.white, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Payment QR code")
                        .accessibilityHint("The customer scans this with their phone camera")
                        .accessibilityIdentifier("invoice-payment-qr")
                } else {
                    Text("Share the secure link to open checkout on the customer’s phone.")
                        .font(Theme.font(15)).foregroundStyle(Theme.muted)
                }
                Text("Ask \(customerName) to scan with their phone camera to pay by card.")
                    .font(Theme.font(15)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                ShareLink(item: url) {
                    Label("Share payment link", systemImage: "square.and.arrow.up").inkCommit()
                }
                .accessibilityIdentifier("share-invoice-payment-link")
                Button(copiedURL == url ? "Link copied" : "Copy link") {
                    UIPasteboard.general.string = url.absoluteString
                    copiedURL = url
                }
                .font(Theme.font(15, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 44)
                Text("Expires \(expiration.formatted(date: .abbreviated, time: .shortened))")
                    .font(Theme.font(12)).foregroundStyle(Theme.subtle)
            case .expired:
                recovery("Payment link expired", message: "Create a new secure link before asking the customer to pay.")
            case .unavailable:
                recovery("Payment link unavailable", message: "Create a new secure link to continue.")
            }
        }
    }

    private func recovery(_ title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(Theme.font(22, weight: .medium))
            Text(message).font(Theme.font(15)).foregroundStyle(Theme.muted)
            PrimaryButton(title: "Create new payment link", busy: isCreating, action: onCreate)
                .disabled(!canCreate)
        }
    }
}

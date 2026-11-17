import SwiftUI
import UIKit

struct InvoicePaymentLinkView: View {
    @ObservedObject var model: InvoicePaymentCollectionModel
    let payLink: FieldInvoicePayLink?
    let requestedBalanceCents: Int?
    /// The invoice's number as the sheet that opened this shows it ("INV-2209").
    let invoiceReference: String
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
                // Paper 39C Scan to pay: the balance centred in the largest Bold over the invoice and the
                // customer in 15 muted, the code on a white card, the scan caption and the waiting line,
                // then the link.
                VStack(alignment: .center, spacing: 20) {
                    VStack(spacing: 4) {
                        Text(money(model.outstandingCents ?? 0, currency: model.invoice?.currency ?? "USD"))
                            .font(Theme.font(34, weight: .bold)).monospacedDigit().tracking(-1)
                            .lineLimit(1).minimumScaleFactor(0.6)
                            .accessibilityLabel("Balance due \(money(model.outstandingCents ?? 0, currency: model.invoice?.currency ?? "USD"))")
                        Text("\(invoiceReference) \u{00B7} \(customerName)")
                            .font(Theme.font(15)).monospacedDigit().foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                    if let error { ErrorBanner(message: error) }
                    if let loadError = model.loadError {
                        ErrorBanner(message: loadError) { await model.load() }
                    } else if model.isLoading || !model.historyComplete {
                        SkeletonRows(count: 2, leading: false, inset: 0).accessibilityLabel("Checking invoice")
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
                .padding(.horizontal, PaperCardMetrics.margin)
                .padding(.top, 8).padding(.bottom, 20)
                .frame(maxWidth: .infinity)
            }
            .refreshable { await model.load() }
        }
        .background(Theme.background)
        .foregroundStyle(Theme.foreground)
        // Paper 39C: "Scan to pay" as the large title.
        .navigationTitle("Scan to pay")
        .navigationBarTitleDisplayMode(.large)
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
                .font(Theme.font(22, weight: .bold)).foregroundStyle(Theme.success)
                .accessibilityIdentifier("invoice-payment-confirmed")
        case .changed:
            recovery("Invoice changed", message: "The balance or invoice status has changed. Use a new link for the current balance.")
        case .ready:
            switch PaymentLinkPresentation(link: payLink, at: date) {
            case .ready(let url, let expiration):
                if let renderedCode, renderedCode.url == url {
                    Image(uiImage: UIImage(cgImage: renderedCode.image))
                        .interpolation(.none).resizable().scaledToFit()
                        .frame(maxWidth: 204)
                        .padding(18)
                        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Payment QR code")
                        .accessibilityHint("The customer scans this with their phone camera")
                        .accessibilityIdentifier("invoice-payment-qr")
                } else {
                    Text("Share the secure link to open checkout on the customer’s phone.")
                        .font(Theme.font(15)).foregroundStyle(Theme.muted)
                }
                // Paper 39C: the caption as wide as the code, then the waiting line with its spinner.
                Text("Ask the customer to scan with their phone camera")
                    .font(Theme.font(15)).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 240)
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(Theme.brandText)
                        .accessibilityHidden(true)
                    Text("Waiting for payment")
                        .font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                // Paper 39C: a pill on the field fill, the words alone in 16 Semibold, 50 tall.
                ShareLink(item: url) {
                    Text("Text the link instead")
                        .font(Theme.font(16, weight: .semibold)).foregroundStyle(Theme.foreground)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Theme.fill, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .accessibilityIdentifier("share-invoice-payment-link")
                Button(copiedURL == url ? "Link copied" : "Copy link") {
                    UIPasteboard.general.string = url.absoluteString
                    copiedURL = url
                }
                .font(Theme.font(15, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 44)
                Text("Expires \(expiration.stampLabel())")
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
            Text(title).font(Theme.font(22, weight: .bold))
            Text(message).font(Theme.font(15)).foregroundStyle(Theme.muted)
            PrimaryButton(title: "Create new payment link", busy: isCreating, action: onCreate)
                .disabled(!canCreate)
            // A disabled commit says why (design.thorbis.com "Disabled needs a reason").
            if !canCreate && !isCreating {
                Text(model.collectBlockedReason ?? "Your role can't create payment links. Ask your office to send one.")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

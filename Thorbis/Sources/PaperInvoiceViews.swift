import SwiftUI

@MainActor
enum PaperInvoiceContentState: Equatable {
    case loading
    case failed(String)
    case ready

    static func resolve(invoiceID: String, model: InvoicePaymentCollectionModel) -> Self {
        if model.invoice?.id == invoiceID { return .ready }
        if let loadError = model.loadError { return .failed(loadError) }
        return .loading
    }
}

struct PaperInvoiceBalance: Equatable {
    let balanceCents: Int?
    let statusLabel: String

    init(invoice: InvoiceRecord, balanceCents: Int?) {
        self.balanceCents = balanceCents
        switch invoice.status {
        case "draft":
            statusLabel = "Draft"
        case "void", "voided":
            statusLabel = "Voided"
        case "paid":
            statusLabel = "Paid"
        default:
            guard let balanceCents else {
                statusLabel = "Balance unavailable"
                return
            }
            if balanceCents == 0 {
                statusLabel = "Paid"
            } else if invoice.amountPaid > 0 {
                statusLabel = "Partially paid"
            } else {
                statusLabel = "Unpaid"
            }
        }
    }
}

struct PaperInvoiceCollectionFooter: View {
    @ObservedObject var model: InvoicePaymentCollectionModel
    var invoiceReference: String? = nil
    let onCollectPayment: () -> Void

    var body: some View {
        if model.canOfferCollection {
            VStack(alignment: .leading, spacing: 8) {
                if let invoiceReference {
                    Text("For \(invoiceReference)")
                        .font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .accessibilityIdentifier("job-collect-selected-invoice")
                }
                PrimaryButton(title: "Collect payment", busy: model.isRecording, action: onCollectPayment)
                    .disabled(!model.canRecordPayment)
                    .accessibilityHint([invoiceReference.map { "For \($0)" }, model.collectBlockedReason].compactMap { $0 }.joined(separator: ". "))
                // A disabled commit says why (design.thorbis.com Controls).
                if let reason = model.collectBlockedReason {
                    Text(reason).font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityHidden(true)
                }
            }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(Theme.canvas)
        }
    }
}

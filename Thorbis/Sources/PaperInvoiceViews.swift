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

struct PaperJobInvoiceContent: View {
    let invoice: InvoiceRecord
    @ObservedObject var paymentModel: InvoicePaymentCollectionModel
    let onCollectPayment: () -> Void
    let onInvoiceUpdated: (InvoiceRecord) -> Void

    @EnvironmentObject private var session: SessionController

    private var balance: PaperInvoiceBalance {
        PaperInvoiceBalance(invoice: displayedInvoice, balanceCents: paymentModel.outstandingCents)
    }

    private var displayedInvoice: InvoiceRecord { paymentModel.invoice ?? invoice }

    var body: some View {
        Group {
            switch PaperInvoiceContentState.resolve(invoiceID: invoice.id, model: paymentModel) {
            case .loading:
                SkeletonRows(count: 4, leading: false, inset: 0)
            case .failed(let message):
                ErrorBanner(message: message) { await paymentModel.load() }
            case .ready:
                VStack(alignment: .leading, spacing: 18) {
                    balanceHeader
                    lineItems
                    InvoicePaymentsSection(
                        model: paymentModel,
                        invoice: displayedInvoice,
                        onCollectPayment: onCollectPayment,
                        onInvoiceUpdated: onInvoiceUpdated
                    )
                    activity
                }
            }
        }
        .accessibilityIdentifier("paper-job-invoice-content")
    }

    private var balanceHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            PaperEyebrow(reference: "INV-\(displayedInvoice.id.suffix(4).uppercased())",
                         text: balance.statusLabel == "Unpaid" || balance.statusLabel == "Partially paid" ? "Balance due" : balance.statusLabel)

            HStack(spacing: 12) {
                Text(balance.balanceCents.map { money($0, currency: invoice.currency) } ?? "—")
                    .font(Theme.monoFont(30, weight: .medium))
                    .tracking(-0.5)
                    .foregroundStyle(Theme.foreground)
                    .accessibilityLabel(balance.balanceCents.map { "Balance due \(money($0, currency: displayedInvoice.currency))" } ?? "Balance unavailable")
                    .accessibilityAddTraits(.updatesFrequently)
                Spacer(minLength: 4)
                statusChip
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var statusChip: some View {
        // Status is a word on the neutral well (MA-10); only a small dot carries the hue.
        return HStack(spacing: 6) {
            Circle().fill(statusColor).frame(width: 6, height: 6).accessibilityHidden(true)
            Text(balance.statusLabel)
        }
            .font(Theme.font(12, weight: .medium))
            .foregroundStyle(Theme.foreground)
            .padding(.horizontal, 10)
            .frame(height: Theme.chipHeight)
            .background(Theme.fill, in: Capsule())
    }

    private var statusColor: Color {
        switch balance.statusLabel {
        case "Paid": Theme.success
        case "Unpaid", "Partially paid": Theme.warning
        case "Voided": Theme.destructive
        default: Theme.muted
        }
    }

    private var lineItems: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Line items")
                .font(Theme.font(13, weight: .medium))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 2)

            VStack(spacing: 0) {
                ForEach(Array(displayedInvoice.lines.enumerated()), id: \.element.id) { index, line in
                    HStack(spacing: 12) {
                        Text(line.description)
                            .font(Theme.font(15, weight: .medium))
                            .foregroundStyle(Theme.foreground)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text(lineAmount(line).map { money($0, currency: line.unitPrice.currency) } ?? "—")
                            .font(Theme.monoFont(13, weight: .medium))
                            .foregroundStyle(Theme.foreground)
                            .fixedSize()
                    }
                    .frame(minHeight: 44)
                    if index < displayedInvoice.lines.count - 1 {
                        Divider().overlay(Theme.border)
                    }
                }

                Divider().overlay(Theme.border)
                HStack {
                    Text("Total")
                        .font(Theme.font(15, weight: .medium))
                        .foregroundStyle(Theme.foreground)
                    Spacer()
                    Text(paymentModel.totalCents.map { money($0, currency: displayedInvoice.currency) } ?? "Unavailable")
                        .font(Theme.monoFont(13, weight: .medium))
                        .foregroundStyle(Theme.foreground)
                }
                .frame(minHeight: 44)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).stroke(Theme.border, lineWidth: 1))
        }
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Activity")
                .font(Theme.font(13, weight: .medium))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 2)

            VStack(alignment: .leading, spacing: 11) {
                ForEach(Array(activityItems.enumerated()), id: \.offset) { index, event in
                    HStack(alignment: .top, spacing: 10) {
                        ZStack {
                            Circle().stroke(Theme.border, lineWidth: 1.4).frame(width: 9, height: 9)
                        }
                        .frame(width: 9, height: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title)
                                .font(Theme.font(13))
                                .foregroundStyle(Theme.muted)
                            if let date = event.date {
                                Text(date.formatted(date: .omitted, time: .shortened))
                                    .font(Theme.monoFont(12))
                                    .foregroundStyle(Theme.subtle)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .overlay(alignment: .leading) {
                        if index < activityItems.count - 1 {
                            Rectangle()
                                .fill(Theme.border)
                                .frame(width: 1)
                                .padding(.leading, 4)
                                .padding(.top, 14)
                                .padding(.bottom, -11)
                        }
                    }
                }
            }
        }
    }

    private var activityItems: [PaperInvoiceActivity] {
        var items = [PaperInvoiceActivity(
            title: displayedInvoice.sourceEstimateId.map { "Invoice created from E-\($0.suffix(4).uppercased())" } ?? "Invoice created",
            date: JobFiltering.date(displayedInvoice.createdAt)
        )]
        if let issuedAt = displayedInvoice.issuedAt {
            items.append(PaperInvoiceActivity(title: "Invoice issued", date: JobFiltering.date(issuedAt)))
        }
        for payment in paymentModel.payments {
            let amount = payment.netAmount ?? payment.amount
            let title = payment.status == .refunded
                ? "Payment refunded · \(money(amount.amount, currency: amount.currency))"
                : "\(payment.method.capitalized) payment · \(money(amount.amount, currency: amount.currency))"
            items.append(PaperInvoiceActivity(title: title, date: JobFiltering.date(payment.recordedAt)))
        }
        return items.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }

    private func lineAmount(_ line: FieldLine) -> Int? {
        guard line.quantity >= 0, line.unitPrice.amount >= 0,
              line.unitPrice.currency == displayedInvoice.currency else { return nil }
        let (amount, overflow) = line.quantity.multipliedReportingOverflow(by: line.unitPrice.amount)
        return overflow ? nil : amount
    }
}

struct PaperInvoiceCollectionFooter: View {
    @ObservedObject var model: InvoicePaymentCollectionModel
    let onCollectPayment: () -> Void

    var body: some View {
        if model.canOfferCollection {
            PrimaryButton(title: "Collect payment", busy: model.isRecording, action: onCollectPayment)
                .disabled(!model.canRecordPayment)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(Theme.chrome)
        }
    }
}

private struct PaperInvoiceActivity {
    let title: String
    let date: Date?
}

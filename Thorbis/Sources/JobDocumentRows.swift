import SwiftUI

/// The same recognizable paper in the technician list and the customer handoff.
struct JobDocumentRow: View {
    let reference: String
    let title: String
    let status: String
    let amount: String?
    var detail: String? = nil
    var fresh = true
    var customerFacing = false
    var symbol = "doc.text"

    var body: some View {
        Group {
            if customerFacing { customerRow } else { technicianRow }
        }
        .foregroundStyle(Theme.foreground)
        .multilineTextAlignment(.leading)
        .padding(.horizontal, 16)
        .padding(.vertical, customerFacing ? 16 : 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).stroke(Theme.border))
        .contentShape(Rectangle())
    }

    private var technicianRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.brandText)
                .frame(width: 26, height: 26)
                .background(Theme.brandSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        titleText
                        Spacer(minLength: 4)
                        if let amount { Text(amount).moneyStyle(.row).fixedSize() }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        titleText
                        if let amount { Text(amount).moneyStyle(.row) }
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 8) {
                        statusIndicator
                        Text(reference).font(Theme.monoFont(12)).foregroundStyle(Theme.muted)
                        Spacer(minLength: 4)
                        if fresh { PaperDisclosure() }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        statusIndicator
                        HStack {
                            Text(reference).font(Theme.monoFont(12)).foregroundStyle(Theme.muted)
                            Spacer(minLength: 4)
                            if fresh { PaperDisclosure() }
                        }
                    }
                }
                if let detail {
                    Text(detail).font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !fresh {
                    Label("Needs refresh", systemImage: "arrow.clockwise")
                        .font(Theme.font(13)).foregroundStyle(Theme.muted)
                }
            }
        }
    }

    private var titleText: some View {
        Text(title).font(Theme.font(17, weight: .medium))
            .fixedSize(horizontal: false, vertical: true)
    }

    /// design 2026-10-30 (Present.dc.html): price first, then what it is, then the reference and
    /// its state as a word at customer size. No pill, no chevron; the whole card opens it.
    private var customerRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let amount {
                Text(amount).font(Theme.font(28, weight: .medium)).monospacedDigit()
                    .minimumScaleFactor(0.7).lineLimit(1)
            }
            Text(title).font(Theme.font(20, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail).font(Theme.font(17)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(reference).font(Theme.font(17)).monospacedDigit().foregroundStyle(Theme.muted)
                if fresh {
                    CustomerStatusWord(status: status, type: CustomerType(nil))
                } else {
                    Label("Needs refresh", systemImage: "arrow.clockwise")
                        .font(Theme.font(17)).foregroundStyle(Theme.muted)
                }
            }
            .padding(.top, 2)
        }
    }

    @ViewBuilder private var statusIndicator: some View {
        if fresh { PaperStatusChip(status: status) }
        else { Text("Status needs refresh").font(Theme.font(customerFacing ? 17 : 13)).foregroundStyle(Theme.muted) }
    }
}

extension JobDocumentRow {
    init(estimate: EstimateRecord, fresh: Bool, customerFacing: Bool = false) {
        reference = "EST-\(estimate.id.suffix(4).uppercased())"
        title = estimate.title
        status = estimate.status
        // Whole alternatives are never added together or presented as add-ons.
        if estimate.status == "approved" && estimate.options == nil {
            amount = nil
            detail = fresh ? "View estimate details" : nil
        } else if let options = estimate.options, !options.isEmpty {
            amount = nil
            detail = estimate.status == "approved" ? (fresh ? "View estimate details" : nil) : "\(options.count) \(options.count == 1 ? "option" : "options")"
        } else {
            amount = paperLinesTotal(estimate.lines).map { money($0, currency: estimate.lines.first?.unitPrice.currency ?? "USD") }
            detail = nil
        }
        self.fresh = fresh
        self.customerFacing = customerFacing
        self.symbol = "doc.text"
    }

    init(invoice: InvoiceRecord, fresh: Bool, customerFacing: Bool = false) {
        reference = "INV-\(invoice.id.suffix(4).uppercased())"
        title = invoice.origin == "estimate_deposit" ? "Deposit" : "Invoice"
        status = invoice.status
        amount = paperLinesTotal(invoice.lines).map { money($0, currency: invoice.currency) }
        if invoice.status == "issued", let total = paperLinesTotal(invoice.lines), invoice.amountPaid >= 0, total >= invoice.amountPaid {
            detail = "\(money(total - invoice.amountPaid, currency: invoice.currency)) due"
        } else {
            detail = nil
        }
        self.fresh = fresh
        self.customerFacing = customerFacing
        self.symbol = "doc.plaintext"
    }
}

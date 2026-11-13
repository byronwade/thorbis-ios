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
    /// On a grouped well with other rows (the job's Money): no card of its own.
    var grouped = false
    /// Job estimates use the compact, individually bordered Paper document card.
    var jobEstimateCard = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if customerFacing { customerRow }
            else if jobEstimateCard { estimateCardRow }
            else { technicianRow }
        }
        .foregroundStyle(Theme.foreground)
        .multilineTextAlignment(.leading)
        .padding(.horizontal, 16)
        .padding(.vertical, customerFacing ? 16 : 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(grouped ? AnyShapeStyle(Color.clear) : AnyShapeStyle(ThorbisPanelStyle()), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay {
            if jobEstimateCard {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).stroke(Theme.border)
            }
        }
        .contentShape(Rectangle())
    }

    func asJobEstimateCard() -> JobDocumentRow {
        var row = self
        row.jobEstimateCard = true
        return row
    }

    /// Paper's job estimate card shows what the work is and what happens next.
    /// Amounts and freshness still come from the validated document read.
    private var estimateCardRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            let titleLayout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
            titleLayout {
                Text(title).font(Theme.font(16, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let amount { Text(amount).moneyStyle(.row).fixedSize() }
            }
            let detailLayout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
            detailLayout {
                if fresh {
                    StatusWord(documentStatus: status)
                    if let message = estimateStatusMessage {
                        Text(message).font(Theme.font(13)).foregroundStyle(Theme.muted)
                    }
                } else {
                    Label("Needs refresh", systemImage: "arrow.clockwise")
                        .font(Theme.font(13)).foregroundStyle(Theme.muted)
                }
                if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                Text([reference, detail].compactMap { $0 }.joined(separator: " · "))
                    .font(Theme.font(13)).monospacedDigit().foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    private var estimateStatusMessage: String? {
        switch status.lowercased() {
        case "draft": "Not sent yet"
        case "sent": "Awaiting approval"
        default: nil
        }
    }

    /// The row for a grouped well: the well draws the surface and the hairlines.
    func onWell() -> JobDocumentRow {
        var row = self
        row.grouped = true
        return row
    }

    /// design 2026-10-30 row: title and one supporting line (reference, options or what's due),
    /// the amount and the status as a word on the right. No tile, no pill, no chevron; the whole
    /// card opens the document. At accessibility sizes the right column moves under the title.
    private var technicianRow: some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                             : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        return layout {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.font(16, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text([reference, detail].compactMap { $0 }.joined(separator: " · "))
                    .font(Theme.font(15)).monospacedDigit().foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if !fresh {
                    Label("Needs refresh", systemImage: "arrow.clockwise")
                        .font(Theme.font(13)).foregroundStyle(Theme.muted)
                }
            }
            .frame(maxWidth: stacked ? .infinity : nil, alignment: .leading)
            if !stacked { Spacer(minLength: 8) }
            VStack(alignment: stacked ? .leading : .trailing, spacing: 4) {
                if let amount { Text(amount).moneyStyle(.row).fixedSize() }
                if fresh { StatusWord(documentStatus: status) }
                else { Text("Status needs refresh").font(Theme.font(13)).foregroundStyle(Theme.muted) }
            }
        }
        .padding(.vertical, 4)
    }

    private var titleText: some View {
        Text(title).font(Theme.customerFont(17, weight: .medium))
            .fixedSize(horizontal: false, vertical: true)
    }

    /// design 2026-10-30 (Present.dc.html): price first, then what it is, then the reference and
    /// its state as a word at customer size. No pill, no chevron; the whole card opens it.
    private var customerRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let amount {
                Text(amount).font(Theme.customerFont(28, weight: .medium)).monospacedDigit()
                    .minimumScaleFactor(0.7).lineLimit(1)
            }
            Text(title).font(Theme.customerFont(20, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail).font(Theme.customerFont(17)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            let metadataLayout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 10))
            metadataLayout {
                Text(reference).font(Theme.customerFont(17)).monospacedDigit().foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if fresh {
                    CustomerStatusWord(status: status, type: CustomerType(nil))
                } else {
                    Label("Needs refresh", systemImage: "arrow.clockwise")
                        .font(Theme.customerFont(17)).foregroundStyle(Theme.muted)
                }
            }
            .padding(.top, 2)
        }
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
        } else if customerFacing {
            if let currency = estimate.lines.first?.unitPrice.currency,
               let display = customerEstimateDisplay(estimate.lines, currency: currency) {
                amount = money(display.amounts.total, currency: currency)
                detail = nil
            } else {
                amount = nil
                detail = "Amount needs verification"
            }
        } else {
            amount = paperLinesTotal(estimate.lines).map { money($0, currency: estimate.lines.first?.unitPrice.currency ?? "USD") }
            detail = nil
        }
        self.fresh = fresh
        self.customerFacing = customerFacing
        self.symbol = "doc.text"
    }

    init(invoice: InvoiceRecord, fresh: Bool, customerFacing: Bool = false, invoiceReference: String? = nil) {
        reference = invoiceReference ?? "INV-\(invoice.id.suffix(4).uppercased())"
        title = invoice.origin == "estimate_deposit" ? "Deposit" : "Invoice"
        status = invoice.status
        if customerFacing {
            if let verified = CustomerDocumentAmounts(lines: invoice.lines, currency: invoice.currency, amountPaid: invoice.amountPaid) {
                amount = money(verified.total, currency: invoice.currency)
                if invoice.status == "issued", verified.total >= invoice.amountPaid {
                    detail = "\(money(verified.due, currency: invoice.currency))\u{00A0}due"
                } else {
                    detail = nil
                }
            } else {
                amount = nil
                detail = "Amount needs verification"
            }
        } else {
            amount = paperLinesTotal(invoice.lines).map { money($0, currency: invoice.currency) }
            if invoice.status == "issued", let total = paperLinesTotal(invoice.lines), invoice.amountPaid >= 0, total >= invoice.amountPaid {
                detail = "\(money(total - invoice.amountPaid, currency: invoice.currency))\u{00A0}due"
            } else {
                detail = nil
            }
        }
        self.fresh = fresh
        self.customerFacing = customerFacing
        self.symbol = "doc.plaintext"
    }
}

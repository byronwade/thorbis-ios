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
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if customerFacing { customerRow } else { technicianRow }
        }
        .foregroundStyle(Theme.foreground)
        .multilineTextAlignment(.leading)
        .padding(.horizontal, 16)
        .padding(.vertical, customerFacing ? 16 : 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(grouped ? Color.clear : Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay { if !grouped { RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).stroke(Theme.border) } }
        .contentShape(Rectangle())
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
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(reference).font(Theme.customerFont(17)).monospacedDigit().foregroundStyle(Theme.muted)
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

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
    /// Job estimates use Paper 23's estimate row: status mark, title, "Sent · Waiting on customer", amount.
    var jobEstimateCard = false
    /// What happened with the status, e.g. "Signed 9:24 AM" on an approved estimate.
    var statusNote: String? = nil
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
        .contentShape(Rectangle())
    }

    func asJobEstimateCard() -> JobDocumentRow {
        var row = self
        row.jobEstimateCard = true
        return row
    }

    private var statusKey: String { status.lowercased() }

    /// The status as a word ("Unpaid" for an issued invoice), as `StatusWord(documentStatus:)` says it.
    private var statusWordText: String { statusKey == "issued" ? "Unpaid" : status.statusLabel }

    /// "Sent · Waiting on customer": the status word in its tone at 14 Medium, the rest muted.
    private func statusLine(_ notes: [String]) -> Text {
        var line: Text = Text(statusWordText).font(Theme.font(14, weight: .medium))
            .foregroundColor(StatusWord.documentTint(statusKey) ?? Theme.muted)
        for note in notes {
            line = line + Text(" · \(note)")
        }
        return line
    }

    /// Paper 23's estimate row: a 20pt status mark, the title at 16 Medium over the status and what
    /// happens next at 14, the amount at the trailing edge; 64 tall. The reference is still spoken.
    /// Amounts and freshness still come from the validated document read.
    private var estimateCardRow: some View {
        let stacked = typeSize.isAccessibilitySize
        return HStack(alignment: .center, spacing: 12) {
            estimateMark
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(Theme.font(16, weight: .medium)).tracking(-0.16)
                    .fixedSize(horizontal: false, vertical: true)
                if fresh {
                    statusLine(estimateNotes).font(Theme.font(14)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(estimateSpokenSubtitle)
                } else {
                    Label("\(reference) · Needs refresh", systemImage: "arrow.clockwise")
                        .font(Theme.font(14)).monospacedDigit().foregroundStyle(Theme.muted)
                }
                if stacked, let amount {
                    Text(amount).moneyStyle(.row).padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !stacked, let amount {
                Text(amount).moneyStyle(.row).fixedSize()
            }
        }
        .frame(minHeight: 48)
    }

    /// Paper 23: a green check when approved, an amber ring while it waits on the customer, a dashed
    /// ring for a draft. Decorative; the word beside it is what is read.
    @ViewBuilder private var estimateMark: some View {
        switch statusKey {
        case "sent", "viewed":
            Circle().strokeBorder(Theme.statusInProgress, lineWidth: 2).frame(width: 18, height: 18)
        default:
            StatusGlyph(tone: StatusWord.documentTone(statusKey) ?? .unscheduled, label: "", size: 20)
        }
    }

    private var estimateStatusMessage: String? {
        switch statusKey {
        case "draft": "Not sent yet"
        case "sent": "Waiting on customer"
        default: nil
        }
    }

    /// What follows the status word: what happens next, then when it was signed or what it holds.
    private var estimateNotes: [String] {
        var notes: [String] = []
        if let message = estimateStatusMessage { notes.append(message) }
        if let statusNote {
            notes.append(statusNote)
        } else if let detail {
            notes.append(detail)
        }
        return notes
    }

    /// VoiceOver keeps the reference the row no longer draws: "EST-2218, Sent · Waiting on customer · 2 options".
    private var estimateSpokenSubtitle: String {
        var parts: [String] = [statusWordText]
        if let message = estimateStatusMessage { parts.append(message) }
        if let statusNote { parts.append(statusNote) }
        if let detail { parts.append(detail) }
        return "\(reference), " + parts.joined(separator: " · ")
    }

    /// The row for a grouped well: the well draws the surface and the hairlines.
    func onWell() -> JobDocumentRow {
        var row = self
        row.grouped = true
        return row
    }

    /// Paper 23/24's document row: the reference at 16 Medium over "Unpaid · $524.88" at 14 (the
    /// status word in its tone), a chevron at the trailing edge; 64 tall. The whole row opens the
    /// document. A deposit says so beside its reference.
    private var technicianRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title == "Invoice" ? reference : "\(reference) · \(title)")
                    .font(Theme.font(16, weight: .medium)).tracking(-0.16).monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                if fresh {
                    statusLine([detail ?? amount].compactMap { $0 })
                        .font(Theme.font(14)).monospacedDigit().foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text((["Status needs refresh"] + [detail ?? amount].compactMap { $0 }).joined(separator: " · "))
                        .font(Theme.font(14)).monospacedDigit().foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Label("Needs refresh", systemImage: "arrow.clockwise")
                        .font(Theme.font(13)).foregroundStyle(Theme.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            PaperChevron()
                .foregroundStyle(Theme.muted).accessibilityHidden(true)
        }
        .frame(minHeight: 48)
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
        // Paper 23: "Approved · Signed 9:24 AM" (the day instead once it isn't today).
        if estimate.status == "approved", let signed = JobFiltering.date(estimate.approvalSignature?.signedAt) {
            let when = Calendar.current.isDateInToday(signed)
                ? signed.formatted(date: .omitted, time: .shortened)
                : signed.formatted(.dateTime.month(.abbreviated).day())
            statusNote = "Signed \(when)"
        }
        self.fresh = fresh
        self.customerFacing = customerFacing
        self.symbol = "doc.text"
    }

    init(invoice: InvoiceRecord, fresh: Bool, customerFacing: Bool = false, invoiceReference: String? = nil) {
        reference = invoiceReference ?? "INV-\(invoice.id.suffix(4).uppercased())"
        title = invoice.isDeposit ? "Deposit" : "Invoice"
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

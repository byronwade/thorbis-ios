import SwiftUI

// Redesign phase 3 (2026-10-31): estimates and invoices in Linear's grammar — a status glyph on the
// job hues, the word beside it, tinted property chips, glyph-led list rows and semibold tabular
// amounts. Staff screens only; customer mode keeps its own presentation.

/// An estimate's or invoice's status as one of the job glyph's tones plus the word people read.
/// It maps onto the existing `StatusTone` cases (no new cases), so job screens are unchanged.
///
/// Estimates: draft → dashed ring, sent → ring, viewed → quarter, approved → check, declined → ×.
/// Invoices: draft → dashed ring, issued → ring ("Unpaid"), issued with some paid → half ("Part
/// paid"), paid → teal $, overdue → red ! , void → ×. "Viewed" and "Overdue" show only when the server
/// sends that status: the records carry no viewed time or due date, so neither is derived (no fake data).
struct DocumentStatus: Equatable {
    let tone: StatusTone
    let word: String

    init(tone: StatusTone, word: String) {
        self.tone = tone
        self.word = word
    }

    init(estimateStatus status: String) {
        switch status {
        case "draft": self.init(tone: .unscheduled, word: "Draft")
        case "sent": self.init(tone: .scheduled, word: "Sent")
        case "viewed": self.init(tone: .dispatched, word: "Viewed")
        case "approved": self.init(tone: .done, word: "Approved")
        case "declined": self.init(tone: .cancelled, word: "Declined")
        default: self.init(tone: .scheduled, word: status.statusLabel)
        }
    }

    /// `balance` is what is still owed (nil when the lines can't be totalled).
    init(invoiceStatus status: String, amountPaid: Int, balance: Int?) {
        switch status {
        case "draft": self.init(tone: .unscheduled, word: "Draft")
        case "issued", "sent", "open":
            if amountPaid > 0, let balance, balance <= 0 {
                // Paid in full, waiting for the server to mark it paid.
                self.init(tone: .invoiced, word: "Paid")
            } else if amountPaid > 0 {
                self.init(tone: .inProgress, word: "Part paid")
            } else {
                self.init(tone: .scheduled, word: "Unpaid")
            }
        case "partial", "partially_paid": self.init(tone: .inProgress, word: "Part paid")
        case "paid": self.init(tone: .invoiced, word: "Paid")
        case "overdue": self.init(tone: .attention, word: "Overdue")
        case "void", "voided": self.init(tone: .cancelled, word: "Void")
        default: self.init(tone: .scheduled, word: status.statusLabel)
        }
    }

    init(invoice: InvoiceRecord) {
        let balance = paperLinesTotal(invoice.lines).map { $0 - invoice.amountPaid }
        self.init(invoiceStatus: invoice.status, amountPaid: invoice.amountPaid, balance: balance)
    }

    var glyph: StatusGlyph { StatusGlyph(tone: tone, label: word) }
}

extension StatusTone {
    /// An estimate's status on the job hues (see `DocumentStatus`).
    init(estimateStatus status: String) { self = DocumentStatus(estimateStatus: status).tone }
    /// An invoice's status on the job hues (see `DocumentStatus`).
    init(invoice: InvoiceRecord) { self = DocumentStatus(invoice: invoice).tone }
}

extension WrappingPropertyChip where Leading == AnyView {
    /// A document's status as a tinted chip led by its glyph (the job header's status chip).
    init(document status: DocumentStatus, action: (() -> Void)? = nil) {
        self.init(text: status.word, tint: status.tone.surface, textColor: status.tone.text, action: action) {
            AnyView(status.glyph.accessibilityHidden(true))
        }
    }
}

extension Theme {
    /// A money amount in a redesigned list or section: semibold and tabular (spec "amounts").
    /// Staff screens only; `moneyFont` keeps its weights for customer mode.
    static func amountFont(_ size: CGFloat = 16) -> Font { monoFont(size, weight: .semibold) }
}

/// An estimate or invoice in a list (Estimates, Invoices, Needs attention): the status glyph, the
/// title in semibold, who and the reference, then the amount in semibold tabular figures with an
/// optional word under it. At accessibility sizes the amount drops under the words. VoiceOver reads
/// the row as one element: title, who, status, amount.
struct DocumentListRowContent: View {
    let status: DocumentStatus
    let title: String
    /// "Customer · EST-1A2B".
    var subtitle: String? = nil
    /// A quieter third line ("Sent 9 days ago").
    var meta: String? = nil
    var amount: String? = nil
    /// Under the amount ("Balance due"); nil leaves the amount alone.
    var amountNote: String? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.paperRowInset) private var inset

    /// Where the hairline starts: past the glyph, under the text.
    static let dividerInset: CGFloat = PaperCardMetrics.inset + 16 + 12

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            status.glyph.accessibilityHidden(true)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
            let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                                 : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 10))
            layout {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.font(16, weight: .semibold))
                        .foregroundStyle(status.tone == .cancelled ? Theme.muted : Theme.foreground)
                        .lineLimit(stacked ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle).font(Theme.font(14)).monospacedDigit().foregroundStyle(Theme.subtle)
                            .lineLimit(stacked ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let meta, !meta.isEmpty {
                        Text(meta).font(Theme.font(13)).monospacedDigit().foregroundStyle(Theme.muted)
                            .lineLimit(stacked ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if amount != nil || amountNote != nil {
                    VStack(alignment: stacked ? .leading : .trailing, spacing: 3) {
                        if let amount {
                            Text(amount).font(Theme.amountFont(16)).foregroundStyle(Theme.foreground)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        if let amountNote {
                            Text(amountNote).font(Theme.font(13, weight: .medium)).foregroundStyle(status.tone.text)
                                .lineLimit(stacked ? nil : 1)
                        }
                    }
                    .fixedSize(horizontal: !stacked, vertical: true)
                }
            }
        }
        .padding(.horizontal, inset).padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title, subtitle, meta, status.word, amount, amountNote == status.word ? nil : amountNote]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "))
    }
}

/// A label and its value on a well (a document's totals, a payment's facts). `strong` sets the
/// value in semibold, for the figure the section is about.
struct WellAmountRow: View {
    let label: String
    let value: String
    var strong = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                                                  : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        layout {
            Text(label).font(Theme.font(16, weight: strong ? .semibold : .regular))
                .foregroundStyle(strong ? Theme.foreground : Theme.subtle)
                .fixedSize(horizontal: false, vertical: true)
            if !typeSize.isAccessibilitySize { Spacer(minLength: 12) }
            Text(value).font(strong ? Theme.amountFont(17) : Theme.monoFont(16))
                .foregroundStyle(strong ? Theme.foreground : Theme.subtle)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

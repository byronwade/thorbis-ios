import SwiftUI

// v2 money rooms (31 October 2026): estimates, invoices, payments, Home's money and the lists that
// lead to them, in design.thorbis.com's Evidence grammar ("The question, then $186.00. Paper.").
// New pieces only; the older DocumentRows API stays as it was.

extension Theme {
    /// A tabular amount in a row or a line: Paper's 16 Medium, beside a 16 Medium row title.
    static func rowAmountFont(_ size: CGFloat = 16) -> Font { monoFont(size, weight: .medium) }
}

/// One priced line on paper: the name (and its explanation) on the left, the quantity in a tabular
/// column, then the two-decimal amount right-aligned. Above one, the unit price sits under the name.
/// At accessibility sizes the quantity and amount drop under the name.
struct EvidenceLineRow: View {
    let line: FieldLine
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .subheadline) private var quantityWidth: CGFloat = 32

    var body: some View {
        let text = LineText(line.description)
        let unit = money(line.unitPrice.amount, currency: line.unitPrice.currency)
        let amount = paperLinesTotal([line]).map { money($0, currency: line.unitPrice.currency) }
        let stacked = typeSize.isAccessibilitySize
        VStack(alignment: .leading, spacing: 3) {
            if stacked {
                Text(text.name).font(Theme.font(16, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                // One figure per line, each whole: side by side they broke mid-number ("$120.0" over "0").
                Text("\(line.quantity) × \(unit)").font(Theme.monoFont(14)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if let amount { Text(amount).font(Theme.rowAmountFont(16)).lineLimit(1).fixedSize() }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(text.name).font(Theme.font(16, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(line.quantity)").font(Theme.monoFont(15)).foregroundStyle(Theme.muted)
                        .frame(width: quantityWidth, alignment: .trailing)
                    if let amount {
                        // At least as wide as "$9,999.00", so the quantity column stays put
                        // whatever each line costs (sized by a hidden template, not a frame).
                        ZStack(alignment: .trailing) {
                            Text(verbatim: "$9,999.00").hidden().accessibilityHidden(true)
                            Text(amount)
                        }
                        .font(Theme.rowAmountFont(16)).lineLimit(1).fixedSize()
                    }
                }
                if line.quantity != 1 {
                    Text("\(unit)\u{00A0}each").font(Theme.monoFont(14)).foregroundStyle(Theme.muted)
                }
            }
            if let detail = text.detail {
                Text(detail).font(Theme.font(14)).foregroundStyle(Theme.muted)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(Theme.foreground)
        .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([text.name, text.detail, "quantity \(line.quantity)", "\(unit)\u{00A0}each", amount]
            .compactMap { $0 }.joined(separator: ", "))
    }
}

/// A total under the lines, as Paper draws its totals card: the label at the leading edge in 15
/// muted, the amount at the trailing edge in 15 tabular. `strong` is the figure the section ends on
/// (Total, Balance due): a 16 Semibold label and a 24 Bold amount.
struct EvidenceTotalRow: View {
    let label: String
    let value: String
    var strong = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).font(Theme.font(strong ? 16 : 15, weight: strong ? .semibold : .regular))
                .foregroundStyle(strong ? Theme.foreground : Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value).font(strong ? Theme.monoFont(24, weight: .bold) : Theme.monoFont(15))
                .foregroundStyle(Theme.foreground)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, strong ? 6 : 4)
        .accessibilityElement(children: .combine)
    }
}

/// An estimate or invoice in a v2 list (Estimates, Invoices, Needs attention): the name first, one
/// quiet line under it, then on the trailing edge the tabular amount over the status word with its
/// mark. VoiceOver reads it as one element.
struct MoneyListRow: View {
    let title: String
    var subtitle: String? = nil
    let status: DocumentStatus
    /// Replaces the status word (still with its mark): "Sent 9 days ago" stays in the subtitle.
    var statusWord: String? = nil
    var amount: String? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.paperRowInset) private var inset

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        let word = statusWord ?? status.word
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                             : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.font(16, weight: .medium))
                    .foregroundStyle(status.tone == .cancelled ? Theme.muted : Theme.foreground)
                    // One line beside the amount: a long business name cuts at the end, so a list of
                    // hundreds stays one row per record (the whole name opens with the record).
                    .lineLimit(stacked ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle, !subtitle.isEmpty { subtitleLines(subtitle, stacked: stacked) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: stacked ? .leading : .trailing, spacing: 3) {
                if let amount {
                    Text(amount).font(Theme.rowAmountFont(16)).foregroundStyle(Theme.foreground)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                StatusLabel(tone: status.tone, word: word, emphasis: .quiet)
            }
            .fixedSize(horizontal: !stacked, vertical: true)
        }
        .padding(.horizontal, inset).padding(.vertical, 11)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title, subtitle, word, amount].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "))
    }

    /// "INV-2209 · balance due" on one line when it fits; otherwise each part on its own line, so a
    /// "·" never ends a line (as JobRoomRow does for problem · customer).
    @ViewBuilder private func subtitleLines(_ subtitle: String, stacked: Bool) -> some View {
        let parts = subtitle.components(separatedBy: " \u{00B7} ")
        if parts.count > 1 && !stacked {
            ViewThatFits(in: .horizontal) {
                subtitleText(subtitle, lines: 1).fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { subtitleText($0.element, lines: 1) }
                }
            }
        } else if parts.count > 1 {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(parts.enumerated()), id: \.offset) { subtitleText($0.element, lines: nil) }
            }
        } else {
            subtitleText(subtitle, lines: stacked ? nil : 2)
        }
    }

    private func subtitleText(_ text: String, lines: Int?) -> some View {
        Text(text).font(Theme.font(14)).monospacedDigit().foregroundStyle(Theme.muted)
            .lineLimit(lines)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A form's field (design.thorbis.com Forms): the label stays above, an optional "Optional" note
/// beside it, the answer in a sunk well, and one slot under it where help sits and an error takes
/// its place. Required fields carry no star.
struct FormField<Content: View>: View {
    let label: String
    var optional = false
    var help: String? = nil
    var error: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(label).font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                // Same marker as PaperFormField ("Notes for the tech · Optional"), one form grammar.
                if optional { Text("\u{00B7} Optional").font(Theme.font(13)).foregroundStyle(Theme.muted.opacity(0.8)) }
            }
            .accessibilityHidden(true)
            content
            if let error {
                FieldProblem(message: error)
            } else if let help {
                Text(help).font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A money field's well with the `$` affix inside it (design.thorbis.com "Affixes in the well").
struct MoneyFieldWell<Field: View>: View {
    var prefix = "$"
    @ViewBuilder var field: Field
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(prefix).font(Theme.monoFont(16)).foregroundStyle(Theme.muted).accessibilityHidden(true)
            field
        }
        .fieldWell()
    }
}

/// A calm state note inside a page (pending, unknown, confirmed): the status word with its mark,
/// then a sentence. No tinted box and no side rail; the word carries it.
struct StateNote: View {
    let tone: StatusTone
    let word: String
    let message: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            StatusLabel(tone: tone, word: word)
            Text(message).font(Theme.font(14)).foregroundStyle(Theme.subtle)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

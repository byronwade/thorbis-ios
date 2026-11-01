import SwiftUI

// v2 money rooms (31 October 2026): estimates, invoices, payments, Home's money and the lists that
// lead to them, in design.thorbis.com's Evidence grammar ("The question, then $186.00. Paper.").
// New pieces only; the older DocumentRows API stays as it was.

extension Theme {
    /// The one large figure on a money screen: 30 Medium, tabular (the v2 ramp's money hero).
    /// Scales with Dynamic Type from `.largeTitle`.
    static let moneyHeroFont = Font.custom("Inter-Regular", size: 30, relativeTo: .largeTitle)
        .weight(.medium).monospacedDigit()
    /// A tabular amount in a row or a line: Medium, on the staff ramp.
    static func rowAmountFont(_ size: CGFloat = 15) -> Font { monoFont(size, weight: .medium) }
}

/// "Invoice 2209" with its status word beside it, then the figure the screen is about: a 13pt
/// label ("Balance due") over the 30pt amount. Evidence leads with the question and the number.
struct EvidenceHeader: View {
    /// The question: "Invoice 2209", "Estimate 4F2A".
    let title: String
    let status: DocumentStatus
    /// A quieter line under the title (an estimate's own name).
    var subtitle: String? = nil
    let figureLabel: String
    let cents: Int
    let currency: String
    var statusIdentifier: String? = nil
    /// The title's identifier (the room hides the navigation bar title, so tests find it here).
    var titleIdentifier = "document-title"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title).font(Theme.font(20, weight: .medium)).tracking(-0.2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(titleIdentifier)
                StatusLabel(tone: status.tone, word: status.word, emphasis: .quiet)
                    .accessibilityLabel("Status, \(status.word)")
                    .accessibilityIdentifier(statusIdentifier ?? "document-status")
                Spacer(minLength: 0)
            }
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle).font(Theme.font(15)).foregroundStyle(Theme.subtle)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(figureLabel).font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                Text(money(cents, currency: currency))
                    .font(Theme.moneyHeroFont).tracking(-0.6)
                    .foregroundStyle(cents == 0 ? Theme.muted : Theme.foreground)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: cents)
            }
            .padding(.top, 20)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)
        }
        .foregroundStyle(Theme.foreground)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One quiet property of a document: a 13pt label in a fixed column, the value in body type.
/// With an action the value reads as a link-like row (opens the customer, the job).
struct EvidenceProperty: View {
    let label: String
    let value: String
    var action: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .footnote) private var labelWidth: CGFloat = 84

    var body: some View {
        if let action {
            Button(action: action) { content(linked: true) }
                .buttonStyle(RowPressStyle())
                .accessibilityHint("Opens the \(label.lowercased())")
        } else {
            content(linked: false)
        }
    }

    private func content(linked: Bool) -> some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                             : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        return layout {
            Text(label).font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                .frame(width: stacked ? nil : labelWidth, alignment: .leading)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(Theme.font(15)).foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if linked {
                    Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.muted).accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .frame(minHeight: linked ? 44 : 32, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A run of quiet properties, grouped by space (no panel, no lines).
struct EvidenceProperties<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
    }
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
                Text(text.name).font(Theme.font(15, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .firstTextBaseline) {
                    Text("\(line.quantity) × \(unit)").font(Theme.monoFont(14)).foregroundStyle(Theme.muted)
                    Spacer(minLength: 8)
                    if let amount { Text(amount).font(Theme.rowAmountFont(15)) }
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(text.name).font(Theme.font(15, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(line.quantity)").font(Theme.monoFont(15)).foregroundStyle(Theme.muted)
                        .frame(width: quantityWidth, alignment: .trailing)
                    if let amount {
                        Text(amount).font(Theme.rowAmountFont(15)).lineLimit(1).fixedSize()
                    }
                }
                if line.quantity != 1 {
                    Text("\(unit)\u{00A0}each").font(Theme.monoFont(13)).foregroundStyle(Theme.muted)
                }
            }
            if let detail = text.detail {
                Text(detail).font(Theme.font(14)).foregroundStyle(Theme.subtle)
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

/// A total under the lines: the label, then the amount in the amount column. `strong` is the
/// figure the section ends on (Total, Balance due).
struct EvidenceTotalRow: View {
    let label: String
    let value: String
    var strong = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).font(Theme.font(strong ? 15 : 14, weight: strong ? .medium : .regular))
                .foregroundStyle(strong ? Theme.foreground : Theme.subtle)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(value).font(strong ? Theme.rowAmountFont(15) : Theme.monoFont(14))
                .foregroundStyle(strong ? Theme.foreground : Theme.subtle)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 4)
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
                Text(title).font(Theme.font(15, weight: .medium))
                    .foregroundStyle(status.tone == .cancelled ? Theme.muted : Theme.foreground)
                    .lineLimit(stacked ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(Theme.font(14)).monospacedDigit().foregroundStyle(Theme.muted)
                        .lineLimit(stacked ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: stacked ? .leading : .trailing, spacing: 3) {
                if let amount {
                    Text(amount).font(Theme.rowAmountFont(15)).foregroundStyle(Theme.foreground)
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
                Text(label).font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                if optional { Text("Optional").font(Theme.font(13)).foregroundStyle(Theme.muted) }
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

/// A form's cluster: a 13 Medium heading over related fields, grouped by space (no card per field).
struct FormCluster<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                Text(title).font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.subtle)
                    .accessibilityAddTraits(.isHeader)
            }
            content
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

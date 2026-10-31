import SwiftUI
import UIKit

// The job screen's pieces (v2, Linear's issue detail on design.thorbis.com tokens): each section is
// a grouped well under a 13 Medium label with its count, rows separated by space (no lines); status
// as a word with its mark; quiet circles; the on-site toolkit; invoice lines with two-decimal money;
// and a quiet activity timeline (no rail).

extension ContainerValues {
    /// Set on a row inside a `JobPanel` to leave out the hairline under it (a caption that belongs
    /// to the row below, say).
    @Entry var jobPanelJoinsNext = false
}

extension View {
    /// No hairline between this row and the next one in its `JobPanel`.
    func jobPanelJoinsNext() -> some View { containerValue(\.jobPanelJoinsNext, true) }
}

/// A section's grouped well (radius 14, `Theme.well`), with an inset hairline between rows. Pass
/// `dividers: false` for content that draws its own structure (the activity timeline).
struct JobPanel<Content: View>: View {
    var dividers = true
    @ViewBuilder var content: Content

    var body: some View {
        Well {
            if dividers {
                Group(subviews: content) { rows in
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        row
                        if index < rows.count - 1, !row.containerValues.jobPanelJoinsNext {
                            WellDivider(leading: 16)
                        }
                    }
                }
            } else {
                content
            }
        }
    }
}

/// A section's header (redesign `SectionHeader` type: semibold 15 in the secondary colour, the
/// count beside it in the same voice), with at most one text action on the right. `mark` puts a
/// small tinted glyph before the title (the access and hazards header uses a warning triangle).
struct JobPanelLabel: View {
    let title: String
    /// Shown beside the title ("6", "3 of 6"); spoken with it.
    var count: String? = nil
    var mark: String? = nil
    var markTint: Color = Theme.warning
    var actionTitle: String? = nil
    var actionIdentifier: String? = nil
    var action: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // At accessibility sizes the action goes under the label; side by side both break mid-word.
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                             : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
        layout {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let mark {
                    Image(systemName: mark)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(markTint)
                        .accessibilityHidden(true)
                }
                // v2: section labels are 13 Medium in the marker grey, the count in the same voice.
                (Text(title).font(Theme.font(13, weight: .medium))
                 + Text(count.map { "  \($0)" } ?? "").font(Theme.font(13)))
                    .monospacedDigit()
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(count.map { "\(title), \($0)" } ?? title)
                    .accessibilityAddTraits(.isHeader)
            }
            if !stacked { Spacer(minLength: 8) }
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(Theme.font(15, weight: .medium))
                        .foregroundStyle(Theme.foreground)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minWidth: 44, minHeight: 44, alignment: stacked ? .leading : .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityIdentifier(actionIdentifier ?? "")
            }
        }
        .padding(.horizontal, 4)
        .frame(minHeight: 32)
        .padding(.vertical, actionTitle == nil || stacked ? 0 : -6)
    }
}

/// A header and its well.
struct JobPanelSection<Content: View>: View {
    let title: String
    var count: String? = nil
    var mark: String? = nil
    var actionTitle: String? = nil
    var actionIdentifier: String? = nil
    var action: (() -> Void)? = nil
    var dividers = true
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            JobPanelLabel(title: title, count: count, mark: mark, actionTitle: actionTitle,
                          actionIdentifier: actionIdentifier, action: action)
            JobPanel(dividers: dividers) { content }
        }
    }
}

/// One row: optional leading date or time, a 16pt title and one 14pt supporting line, and
/// anything short on the right (a time, a status word, an amount).
struct JobPanelRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var leading: String? = nil
    var titleSize: CGFloat = 16
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let leading {
                Text(leading)
                    .font(Theme.monoFont(14, weight: .medium))
                    .foregroundStyle(Theme.foreground)
                    .frame(width: 58, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.font(titleSize, weight: .medium))
                    .foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Theme.font(14))
                        .foregroundStyle(Theme.subtle)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}

extension JobPanelRow where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, leading: String? = nil, titleSize: CGFloat = 16) {
        self.init(title: title, subtitle: subtitle, leading: leading, titleSize: titleSize) { EmptyView() }
    }
}

/// A label and its value on one line ("Gate code   4417").
struct JobPanelFact: View {
    let label: String
    let value: String
    var mono = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // A short value sits on the label's line; a long one (or any at accessibility sizes) reads
        // under its label, left aligned, instead of a ragged right-aligned paragraph.
        Group {
            if typeSize.isAccessibilitySize {
                stacked
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        labelText.fixedSize()
                        Spacer(minLength: 8)
                        valueText.lineLimit(1).fixedSize()
                    }
                    stacked
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var labelText: some View { Text(label).font(Theme.font(15)).foregroundStyle(Theme.muted) }
    private var valueText: some View {
        Text(value)
            .font(mono ? Theme.monoFont(15, weight: .medium) : Theme.font(15))
            .foregroundStyle(Theme.foreground)
    }
    private var stacked: some View {
        VStack(alignment: .leading, spacing: 2) {
            labelText.fixedSize(horizontal: false, vertical: true)
            valueText.multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A status as a word with a small dot in its colour; the colour never appears without the word.
struct JobStatusWord: View {
    let word: String
    let color: Color
    var size: CGFloat = 13

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7).accessibilityHidden(true)
            Text(word).font(Theme.font(size, weight: .medium)).foregroundStyle(Theme.foreground)
        }
        .fixedSize()
    }
}

/// A quiet 44pt circle with its word under it, for the header's Call, Text, Directions, Show customer.
struct JobCircleLabel: View {
    let title: String
    let symbol: String
    var enabled = true
    /// The glyph and its circle grow with Dynamic Type (never under 44pt, capped so the row still fits).
    @ScaledMetric(relativeTo: .body) private var glyph: CGFloat = 17
    @ScaledMetric(relativeTo: .body) private var circle: CGFloat = 44

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: min(glyph, 26), weight: .medium))
                .foregroundStyle(Theme.foreground)
                .frame(width: min(max(circle, 44), 64), height: min(max(circle, 44), 64))
                .background(Theme.well, in: Circle())
            Text(title)
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.subtle)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .opacity(enabled ? 1 : 0.4)
        .contentShape(Rectangle())
    }
}

/// The three job sections as Linear text tabs (the style Today uses, `PaperTabs(textTabs:)`): plain
/// words on the ground, the chosen one on a light well pill, left-aligned. Values stay "Overview",
/// "Money", "Activity"; only the words change. A label with its own words and spoken form keeps
/// `PaperTabs` out (it binds the label to the value and has no per-tab identifiers).
struct JobSectionControl: View {
    let options: [(value: String, label: String, spoken: String)]
    @Binding var selection: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var pill

    var body: some View {
        JobSectionRowLayout(spacing: 4, fills: false) {
            ForEach(options, id: \.value) { option in
                let isOn = option.value == selection
                Button { withMotion(.snappy) { selection = option.value } } label: {
                    // An amount is never cut ("Money · $3…"): when the whole label can't fit, the
                    // tab drops the "· amount" and keeps the word; the amount is still spoken.
                    ViewThatFits(in: .horizontal) {
                        Text(option.label).fixedSize()
                        Text(Self.shortLabel(option.label)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                        .font(Theme.font(15, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(isOn ? Theme.foreground : Theme.muted)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .frame(minHeight: Theme.chipHeight + 4)
                        .background { if isOn { Capsule().fill(Theme.fill).matchedGeometryEffect(id: "pill", in: pill) } }
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(option.spoken)
                .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("job-section-\(option.value.lowercased())")
            }
        }
        // The pill glides on a small spring; the section below swaps with the existing snappy motion.
        .animation(Theme.selectionSpring(reduceMotion: reduceMotion), value: selection)
        .sensoryFeedback(.selection, trigger: selection)
    }

    /// "Money · $340" → "Money"; a label without a count stays as it is.
    static func shortLabel(_ label: String) -> String {
        label.components(separatedBy: " · ").first ?? label
    }
}

/// One row of segments that shares the width fairly: each segment gets what its whole label
/// needs while the row has room (spare width split evenly); when it doesn't, every segment
/// gives up width in proportion to what it asked for, so no one label is squeezed alone.
struct JobSectionRowLayout: Layout {
    var spacing: CGFloat = 2
    /// False for text tabs: each keeps its own width, left-aligned, while the row has room.
    var fills = true

    private func widths(_ subviews: Subviews, total: CGFloat) -> [CGFloat] {
        guard !subviews.isEmpty else { return [] }
        let ideal = subviews.map { $0.sizeThatFits(.unspecified).width }
        let available = max(0, total - spacing * CGFloat(subviews.count - 1))
        let wanted = ideal.reduce(0, +)
        if wanted <= available {
            guard fills else { return ideal }
            let extra = (available - wanted) / CGFloat(subviews.count)
            return ideal.map { $0 + extra }
        }
        guard wanted > 0 else { return ideal.map { _ in available / CGFloat(subviews.count) } }
        return ideal.map { available * $0 / wanted }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified) }
        let natural = ideal.map(\.width).reduce(0, +) + spacing * CGFloat(max(0, subviews.count - 1))
        let total = proposal.width ?? natural
        let ws = widths(subviews, total: total)
        let height = zip(subviews, ws).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: proposal.height)).height }.max() ?? 0
        return CGSize(width: fills ? total : min(total, natural), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, width) in zip(subviews, widths(subviews, total: bounds.width)) {
            subview.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width + spacing
        }
    }
}

/// One tool on the on-site grid: an 84pt well tile, glyph over word.
struct JobToolTile: View {
    let title: String
    let symbol: String
    var enabled = true
    var hint: String? = nil
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    /// OnSite.dc.html: a 22pt glyph that grows with Dynamic Type.
    @ScaledMetric(relativeTo: .body) private var glyph: CGFloat = 22

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: min(glyph, 32), weight: .regular))
                    .foregroundStyle(Theme.foreground)
                    .frame(height: min(glyph, 32) + 4)
                // The word wraps to a second line rather than shrinking (three, then two columns
                // as text grows keep it whole); at accessibility sizes it takes the lines it needs.
                Text(title)
                    .font(Theme.font(13, weight: .medium))
                    .foregroundStyle(Theme.foreground)
                    .multilineTextAlignment(.center)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 84)
            .background(Theme.well, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .opacity(enabled ? 1 : 0.45)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .accessibilityLabel(title)
        .accessibilityHint(hint ?? "")
        .accessibilityIdentifier("job-tool-\(title.lowercased().replacingOccurrences(of: " ", with: "-"))")
    }
}

/// OnSite.dc.html: what to know before touching anything, at the top while on site. Facts in
/// bold, site notes after; codes copy on a long press.
struct JobAccessBanner: View {
    let facts: [JobPropertyHistory.Fact]
    /// Set when the facts are the account's only address rather than the job's own site.
    var caveat: String? = nil

    private var headline: String {
        facts.filter { $0.label != "Site notes" }.map { fact in
            switch fact.label {
            case "Gate code": "Gate \(fact.value)"
            case "Alarm code": "Alarm \(fact.value)"
            case "Dog": "Dog: \(fact.value)"
            default: "\(fact.label): \(fact.value)"
            }
        }.joined(separator: " · ")
    }

    private var notes: String? { facts.first { $0.label == "Site notes" }?.value }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.warning)
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Before you go in")
                    .font(Theme.font(13, weight: .semibold))
                    .foregroundStyle(Theme.warning)
                    .accessibilityHidden(true)
                (Text(headline.isEmpty ? "" : headline + ".").font(Theme.monoFont(15, weight: .semibold)).foregroundStyle(Theme.foreground)
                 + Text(notes.map { (headline.isEmpty ? "" : " ") + $0 } ?? "").font(Theme.font(15)).foregroundStyle(Theme.subtle))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let caveat {
                    Text(caveat).font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        // v2: the warning reads from its words ("Before you go in") on the tinted ground; no edge rail.
        .background(Theme.warningSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .contentShape(Rectangle())
        .contextMenu {
            ForEach(facts.filter(\.isCode)) { fact in
                Button("Copy \(fact.label.lowercased())", systemImage: "doc.on.doc") { UIPasteboard.general.string = fact.value }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Before you go in. \(headline). \(notes ?? "")")
        .accessibilityHint(facts.contains(where: \.isCode) ? "Touch and hold to copy a code" : "")
        .accessibilityIdentifier("job-access-banner")
    }
}

/// "On site 42 min" from the arrival tap; never from the schedule.
enum JobOnSiteClock {
    static func line(arrived: Date, now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(arrived) / 60))
        return minutes < 60 ? "On site \(minutes) min" : "On site \(minutes / 60) h \(minutes % 60) min"
    }
}

/// v2 (design.thorbis.com "Money is $186.00. Always two decimals"): the job screens' money, never
/// mixed with whole dollars. The name is kept so the job's call sites follow.
func jobShortMoney(_ cents: Int, currency: String) -> String {
    money(cents, currency: currency)
}

/// An invoice's lines as design.thorbis.com draws them: the line, its quantity and its amount in
/// tabular columns, two decimals always ("Service call   1   $186.00"). One VoiceOver item per line.
struct JobInvoiceLineRows: View {
    let lines: [FieldLine]
    let currency: String
    @Environment(\.dynamicTypeSize) private var typeSize

    static func amount(_ line: FieldLine) -> Int? {
        let (total, overflow) = line.quantity.multipliedReportingOverflow(by: line.unitPrice.amount)
        return overflow ? nil : total
    }

    var body: some View {
        ForEach(lines) { line in
            let amount = Self.amount(line).map { money($0, currency: line.unitPrice.currency) }
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                                                      : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
            layout {
                Text(line.description).font(Theme.font(15)).foregroundStyle(Theme.foreground)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(line.quantity)").font(Theme.monoFont(14)).foregroundStyle(Theme.muted)
                        .frame(minWidth: 20, alignment: .trailing)
                    Text(amount ?? "—").font(Theme.monoFont(15)).foregroundStyle(Theme.foreground)
                        .frame(minWidth: 72, alignment: .trailing)
                }
                .fixedSize()
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(line.description), quantity \(line.quantity)\(amount.map { ", \($0)" } ?? "")")
        }
    }
}

// MARK: Activity timeline (Linear's issue activity: a thin line through small glyphs)

/// What kind of thing happened, for the timeline's glyph. Decorative: the row's words say it.
struct JobActivityGlyph: View {
    /// `ActivityFeedSubject.kind`: note, status, estimate, call, media.
    let kind: String
    /// The entry's title; a status entry's word picks its status glyph ("Dispatched", "Arrived").
    let title: String
    /// A note saved on this phone and still waiting to sync.
    var pending = false
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 20

    static func tone(forStatusEvent title: String) -> StatusTone {
        switch title {
        case "Dispatched", "En route": .dispatched
        case "Arrived", "Work started", "Paused": .inProgress
        case "Completed": .done
        case "Canceled": .cancelled
        default: .unscheduled
        }
    }

    /// v2: a quiet mark, not a coloured disc: the kind's small glyph in the marker grey; a status
    /// change keeps its small status mark (colour beside the word, never alone).
    private var mark: (symbol: String, tint: Color) {
        if pending { return ("clock", Theme.warning) }
        switch kind {
        case "note": return ("text.alignleft", Theme.muted)
        case "media": return ("camera", Theme.muted)
        case "estimate": return ("doc.text", Theme.muted)
        case "call": return ("phone", Theme.muted)
        default: return ("circle.fill", Theme.muted)
        }
    }

    var body: some View {
        Group {
            if kind == "status" {
                StatusGlyph(tone: Self.tone(forStatusEvent: title), label: title, size: 12)
            } else {
                Image(systemName: mark.symbol)
                    .font(.system(size: size * 0.6, weight: .regular))
                    .foregroundStyle(mark.tint)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// One timeline row: a quiet mark, then the entry. v2: no rail line; space separates the entries.
/// `isFirst` and `isLast` are kept so call sites compile.
struct JobTimelineItem<Content: View>: View {
    let kind: String
    let title: String
    var pending = false
    var isFirst = false
    var isLast = false
    /// Top padding of the row; the glyph sits level with the first line of text.
    var verticalPadding: CGFloat = 10
    @ViewBuilder var content: Content
    @ScaledMetric(relativeTo: .body) private var glyph: CGFloat = 20

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            JobActivityGlyph(kind: kind, title: title, pending: pending)
                .padding(.top, 1)
            content
        }
        .padding(.vertical, verticalPadding)
    }
}

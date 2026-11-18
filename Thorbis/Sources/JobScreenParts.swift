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
    func jobPanelJoinsNext(_ joins: Bool = true) -> some View { containerValue(\.jobPanelJoinsNext, joins) }
}

/// A section's rows. On the job (a Record room, `paperRecordRoom`) they sit on the page with no
/// panel; elsewhere on a grouped well (radius 14, `Theme.well`). Space, never a line, between rows.
struct JobPanel<Content: View>: View {
    var dividers = true
    @ViewBuilder var content: Content
    @Environment(\.paperRecordRoom) private var recordRoom

    var body: some View {
        if recordRoom {
            // v2 Record room: no panel; rows sit on the page, their words under the section label.
            VStack(alignment: .leading, spacing: 0) { rows }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, RecordRoom.outset(rowInset: 16))
        } else {
            Well { rows }
        }
    }

    @ViewBuilder private var rows: some View {
        Group {
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
    /// Draws the action as this glyph instead of its words (Paper 21: the plus beside
    /// "Contacts · 3"); `actionTitle` is then what VoiceOver says.
    var actionSymbol: String? = nil
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
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(markTint)
                        .accessibilityHidden(true)
                }
                // Paper v2 (21 Job details): a section's label is 13 Semibold in the marker grey,
                // its count after it in the same voice ("Contacts · 3").
                Text(count.map { "\(title) · \($0)" } ?? title)
                    .font(Theme.font(13, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(count.map { "\(title), \($0)" } ?? title)
                    .accessibilityAddTraits(.isHeader)
            }
            if !stacked { Spacer(minLength: 8) }
            if let actionTitle, let action {
                // Paper: the section's one action is a brand-text word at the label's trailing edge ("Edit").
                Button(action: action) {
                    Group {
                        if let actionSymbol {
                            Image(systemName: actionSymbol)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Theme.brandText)
                        } else {
                            // Paper: 13 Semibold in the brand text tone ("Edit").
                            Text(actionTitle)
                                .font(Theme.font(13, weight: .semibold))
                                .foregroundStyle(Theme.brandText)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(minWidth: 44, minHeight: 44, alignment: stacked ? .leading : .trailing)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(actionTitle)
                .accessibilityIdentifier(actionIdentifier ?? "")
            }
        }
        .padding(.horizontal, 4)
        .frame(minHeight: 26)
        .padding(.vertical, actionTitle == nil || stacked ? 0 : -9)
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
        // Paper v2: 8 between a section's label and its card.
        VStack(alignment: .leading, spacing: 8) {
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

/// Job sections as Paper's segmented control (21 Job details, as `PaperTabs` draws it): a card
/// track (radius 11, inset 2), every segment the same width, the chosen one raised on a pill. A
/// label with its own words and spoken form keeps `PaperTabs` out (it binds the label to the value
/// and has no per-tab identifiers).
struct JobSectionControl: View {
    let options: [(value: String, label: String, spoken: String)]
    @Binding var selection: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var pill

    var body: some View {
        // Segments share the width fairly (`JobSectionRowLayout`); a label that can't fit its
        // segment drops its "· amount" and keeps the word.
        JobSectionRowLayout(spacing: 2, fills: true) {
            ForEach(options, id: \.value) { option in
                let isOn = option.value == selection
                Button { withMotion(.snappy) { selection = option.value } } label: {
                    // An amount is never cut ("Money · $3…"): when the whole label can't fit, the
                    // tab drops the "· amount" and keeps the word; the amount is still spoken.
                    ViewThatFits(in: .horizontal) {
                        Text(option.label).fixedSize()
                        Text(Self.shortLabel(option.label)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                        // Paper v2 segment: 14 Semibold in ink when chosen, 14 Medium in the body grey otherwise.
                        .font(Theme.font(14, weight: isOn ? .semibold : .medium))
                        .monospacedDigit()
                        .foregroundStyle(isOn ? Theme.foreground : Theme.subtle)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background {
                            if isOn {
                                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.selectedSegment)
                                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                                    .padding(.vertical, 3)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(option.spoken)
                .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("job-section-\(option.value.lowercased())")
            }
        }
        .padding(.horizontal, 2)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        // The pill glides on a small spring; the section below swaps with the existing snappy motion.
        .animation(Theme.selectionSpring(reduceMotion: reduceMotion), value: selection)
        .sensoryFeedback(.selection, trigger: selection)
    }

    /// "Money · $340.00" → "Money"; a label without a count stays as it is.
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
            .panelBackground(cornerRadius: Theme.cardRadius)
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

/// Paper F4 "Working": one capture tile. A 108pt card, its mark in the brand tone at the top, the
/// word at 17 Semibold over one 13pt line of what is already there ("4 added"). Two sit side by side.
struct JobCaptureTile: View {
    let title: String
    let symbol: String
    let detail: String
    var enabled = true
    var hint: String? = nil
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(Theme.brandText)
                    .frame(height: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(Theme.font(17, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(Theme.font(13))
                        .monospacedDigit()
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 108, maxHeight: .infinity, alignment: .topLeading)
            .panelBackground(cornerRadius: Theme.cardRadius)
            .opacity(enabled ? 1 : 0.45)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(detail)")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(hint ?? "")
        .accessibilityIdentifier(identifier)
    }
}

/// OnSite.dc.html: what to know before touching anything, at the top while on site. Facts in
/// bold, site notes after; codes copy on a long press.
struct JobAccessBanner: View {
    let facts: [JobPropertyHistory.Fact]
    /// Set when the facts are the account's only address rather than the job's own site.
    var caveat: String? = nil
    /// Paper F3: why the office sent the visit, as the last row of "Know before you knock".
    var description: String? = nil
    /// Paper F3: the equipment on file at this place ("Trane XR14 · 2019"), between the codes and
    /// the description.
    var equipment: String? = nil
    /// False while driving (Paper F2), where the codes ride in the call card instead: only the
    /// site's warning shows.
    var showsCodes = true

    /// One row of "Know before you knock".
    private struct KnowRow: Identifiable {
        let id: String
        let symbol: String
        let title: String
        var subtitle: String? = nil
    }

    private var knowRows: [KnowRow] {
        guard showsCodes else { return [] }
        var rows: [KnowRow] = []
        if !headline.isEmpty {
            rows.append(KnowRow(id: "codes", symbol: "key", title: headline, subtitle: caveat))
        } else if let caveat {
            rows.append(KnowRow(id: "caveat", symbol: "house", title: caveat))
        }
        if let equipment, !equipment.isEmpty {
            rows.append(KnowRow(id: "equipment", symbol: "wrench.adjustable", title: equipment))
        }
        if let description, !description.isEmpty {
            rows.append(KnowRow(id: "description", symbol: "doc.text", title: description))
        }
        return rows
    }

    /// The codes and the dog on one line ("Gate 4482# · Dog: friendly").
    var headline: String {
        facts.filter { $0.label != "Site notes" }.map { fact in
            switch fact.label {
            case "Gate code": "Gate \(fact.value)"
            case "Alarm code": "Alarm \(fact.value)"
            case "Dog": "Dog: \(fact.value)"
            default: "\(fact.label): \(fact.value)"
            }
        }.joined(separator: " · ")
    }

    var notes: String? { facts.first { $0.label == "Site notes" }?.value }

    var body: some View {
        // Paper F3 "Arrived": the site's warning on its own warning-tone card, then "Know before
        // you knock" over a card whose first row is the codes behind a key.
        VStack(alignment: .leading, spacing: 16) {
            if let notes {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(Theme.warning)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    Text(notes)
                        .font(Theme.font(17, weight: .semibold))
                        .foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                .background(Theme.warningSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            }
            let rows = knowRows
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Know before you knock")
                        .font(Theme.font(13, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 4)
                    // Paper F3: one card, a 62pt row per fact (the codes behind a key, why the
                    // office sent the visit behind a page), a hairline between rows from the words.
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(rows) { row in
                            HStack(alignment: .center, spacing: 12) {
                                Image(systemName: row.symbol)
                                    .font(.system(size: 18, weight: .regular))
                                    .foregroundStyle(Theme.muted)
                                    .frame(width: 28)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(row.title)
                                        .font(Theme.font(17, weight: .medium))
                                        .monospacedDigit()
                                        .foregroundStyle(Theme.foreground)
                                        .fixedSize(horizontal: false, vertical: true)
                                    if let subtitle = row.subtitle {
                                        Text(subtitle).font(Theme.font(14)).foregroundStyle(Theme.muted)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
                            .overlay(alignment: .top) {
                                if row.id != rows.first?.id {
                                    Rectangle().fill(Theme.hairline).frame(height: 1)
                                        .padding(.leading, 56)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                    }
                    .panelBackground(cornerRadius: Theme.cardRadius)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .contextMenu {
            ForEach(facts.filter(\.isCode)) { fact in
                Button("Copy \(fact.label.lowercased())", systemImage: "doc.on.doc") { UIPasteboard.general.string = fact.value }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(["Before you go in", showsCodes ? headline : "", notes ?? "",
                             showsCodes ? (equipment ?? "") : "", showsCodes ? (description ?? "") : ""]
            .filter { !$0.isEmpty }.joined(separator: ". "))
        .accessibilityHint(facts.contains(where: \.isCode) ? "Touch and hold to copy a code" : "")
        .accessibilityIdentifier("job-access-banner")
    }
}

/// Paper F2 to F4 (field mode): where the visit is, as five bars over their words. Steps behind
/// are green, the current one brand, the rest quiet. Only the visit's own statuses have a step.
struct JobFieldSteps: View {
    static let titles = ["Driving", "Arrived", "Working", "Wrap up", "Paid"]
    /// The step the visit is on: 0 Driving, 1 Arrived, 2 Working.
    let current: Int
    /// Paper F6 "Paid": the last step is behind too, so every bar is green.
    var allDone = false
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The step for a job status; nil when the job is not out on its visit.
    static func step(for status: String) -> Int? {
        switch status {
        case "en_route": return 0
        case "arrived": return 1
        case "in_progress": return 2
        default: return nil
        }
    }

    private var shown: Int { min(max(current, 0), Self.titles.count - 1) }

    private func tint(_ index: Int) -> Color {
        if index < shown || allDone { return Theme.statusDone }
        return index == shown ? Theme.brand : Theme.fill
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 4) {
                ForEach(0..<Self.titles.count, id: \.self) { index in
                    VStack(spacing: 6) {
                        Capsule().fill(tint(index)).frame(height: 4)
                        // Five words do not fit across at accessibility sizes; the current one reads below.
                        if !typeSize.isAccessibilitySize {
                            Text(Self.titles[index])
                                .font(Theme.font(12, weight: .semibold))
                                .foregroundStyle(index == shown ? Theme.foreground : Theme.muted)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            if typeSize.isAccessibilitySize {
                Text(Self.titles[shown])
                    .font(Theme.font(12, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Visit progress")
        .accessibilityValue("\(Self.titles[shown]), step \(shown + 1) of \(Self.titles.count)")
        .accessibilityIdentifier("job-field-steps")
    }
}

/// "On site 42 min" from the arrival tap; never from the schedule.
enum JobOnSiteClock {
    static func line(arrived: Date, now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(arrived) / 60))
        return minutes < 60 ? "On site \(minutes) min" : "On site \(minutes / 60) h \(minutes % 60) min"
    }

    /// Paper F4's timer card: hours, minutes and seconds since the arrival tap ("0:42:18").
    static func timer(arrived: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(arrived)))
        return String(format: "%d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
    }

    /// Paper F5's Summary row: "1h 12m" since the arrival tap; "12m" under an hour.
    static func short(arrived: Date, now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(arrived) / 60))
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
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
    var invoiceID: String? = nil
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
            .accessibilityIdentifier(invoiceID.map { "job-invoice-line-\($0)-\(line.id)" } ?? "")
        }
    }
}

// MARK: Money (Paper 23 and 24)

/// Paper 23's totals card on the job's Money: what is waiting on the customer and what is approved,
/// each a 13 Semibold label over its amount at 22 Bold, then "Build an estimate" as a quiet 48pt
/// pill. Amounts are the validated sums of `JobEstimateSummary`; an approved total that can't be
/// known says so instead of showing a number.
struct JobEstimateSummaryCard: View {
    let summary: JobEstimateSummary
    var onBuild: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Paper's order: awaiting approval first, then approved.
    private var figures: [JobEstimateSummary.Amount] {
        summary.amounts.filter { $0.status != "approved" } + summary.amounts.filter { $0.status == "approved" }
    }

    private var mixedCurrencies: Bool { Set(summary.amounts.map(\.currency)).count > 1 }

    private func title(_ amount: JobEstimateSummary.Amount) -> String {
        let word = amount.status == "approved" ? "Approved" : "Awaiting approval"
        return mixedCurrencies ? "\(word) \u{00B7} \(amount.currency)" : word
    }

    private var optionsNote: String {
        "\(summary.optionCount) \(summary.optionCount == 1 ? "estimate has" : "estimates have") pricing options. Review those options separately."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !figures.isEmpty {
                // Side by side as Paper draws them; one under the other at accessibility sizes.
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                                                          : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
                layout {
                    ForEach(figures) { amount in
                        figure(title(amount), value: money(amount.cents, currency: amount.currency))
                            .accessibilityIdentifier(amount.status == "approved" ? "job-estimates-approved" : "job-estimates-awaiting")
                    }
                }
            }
            if summary.approvedUnavailable || summary.optionCount > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    if summary.approvedUnavailable {
                        Text("Approved total unavailable")
                            .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                        Text("Open approved estimates to review their amounts.")
                            .font(Theme.font(14)).foregroundStyle(Theme.muted)
                    }
                    if summary.optionCount > 0 {
                        Text(optionsNote).font(Theme.font(14)).foregroundStyle(Theme.muted)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            if let onBuild {
                Button(action: onBuild) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.shield").font(.system(size: 16, weight: .medium))
                            .accessibilityHidden(true)
                        Text("Build an estimate")
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .paperButton(.card, tone: .quiet, fills: true)
                }
                .buttonStyle(PressStyle())
                .accessibilityIdentifier("job-estimates-build")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func figure(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text(value).font(Theme.font(22, weight: .bold)).tracking(-0.44).monospacedDigit()
                .foregroundStyle(Theme.foreground)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Paper 24's totals under an invoice's lines: Subtotal (and credits, when there are any) at 15,
/// a hairline, then Total at 22 Bold; what has been paid and what is left once money has come in.
/// Lines carry no separate tax, so no Tax row is drawn. Nothing shows when the lines can't be
/// added up safely.
struct JobInvoiceTotals: View {
    let invoice: InvoiceRecord

    var body: some View {
        if let amounts = CustomerDocumentAmounts(lines: invoice.lines, currency: invoice.currency,
                                                 amountPaid: max(0, invoice.amountPaid)) {
            VStack(alignment: .leading, spacing: 8) {
                if amounts.credits != 0 {
                    row("Subtotal", amounts.subtotal)
                    row("Credits", amounts.credits)
                }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Total").font(Theme.font(16, weight: .semibold)).foregroundStyle(Theme.foreground)
                    Spacer(minLength: 8)
                    Text(money(amounts.total, currency: invoice.currency))
                        .font(Theme.font(22, weight: .bold)).tracking(-0.44).monospacedDigit()
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .padding(.top, 8)
                .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
                .accessibilityElement(children: .combine)
                if amounts.paid > 0 {
                    row("Paid", amounts.paid)
                    row("Balance due", amounts.due)
                }
            }
            .accessibilityIdentifier("job-invoice-totals-\(invoice.id)")
        }
    }

    private func row(_ label: String, _ cents: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).font(Theme.font(15)).foregroundStyle(Theme.muted)
            Spacer(minLength: 8)
            Text(money(cents, currency: invoice.currency)).font(Theme.font(15)).monospacedDigit()
                .foregroundStyle(Theme.foreground)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Paper 24's balance card, top half: "INV-2209 · Balance due" at 13 Semibold with the invoice's
/// status on its tinted pill, then what is owed at 34 Bold. The card's Collect payment pill sits
/// under it. One VoiceOver stop: reference, status, amount.
struct JobInvoiceBalanceHeader: View {
    let reference: String
    /// "Deposit" for a deposit invoice, so it never reads as the job's bill.
    var kind: String? = nil
    let status: String
    let amount: String
    @Environment(\.dynamicTypeSize) private var typeSize

    private var statusWord: String { status == "issued" ? "Unpaid" : status.statusLabel }
    private var caption: String {
        [reference, kind, "Balance due"].compactMap { $0 }.joined(separator: " \u{00B7} ")
    }

    var body: some View {
        let tone = StatusWord.documentTone(status) ?? .unscheduled
        // At accessibility sizes the status goes under the reference so neither is cut.
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                                                  : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
        return VStack(alignment: .leading, spacing: 6) {
            layout {
                Text(caption)
                    .font(Theme.font(13, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    StatusGlyph(tone: tone, label: "", size: 12)
                        .accessibilityHidden(true)
                    Text(statusWord).font(Theme.font(13, weight: .semibold)).foregroundStyle(tone.text)
                }
                .padding(.leading, 8).padding(.trailing, 10)
                .frame(minHeight: 26)
                .background(tone.surface, in: Capsule())
                .fixedSize()
            }
            Text(amount)
                .font(Theme.font(34, weight: .bold)).tracking(-0.85).monospacedDigit()
                .foregroundStyle(Theme.foreground)
                .lineLimit(1).minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(caption), \(statusWord), \(amount)")
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
    /// Paper 21B: the mark sits in a 32pt disc on the field fill, the way the job's Activity draws it.
    var disc = false
    @ViewBuilder var content: Content
    @ScaledMetric(relativeTo: .body) private var glyph: CGFloat = 20

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if disc {
                JobActivityGlyph(kind: kind, title: title, pending: pending)
                    .frame(width: 32, height: 32)
                    .background(Theme.fill, in: Circle())
            } else {
                JobActivityGlyph(kind: kind, title: title, pending: pending)
                    .padding(.top, 1)
            }
            content
        }
        .padding(.vertical, verticalPadding)
    }
}

/// Paper 21K "More": the eight rows' own 22pt line glyphs (stroke 1.6), from its SVGs.
extension PaperGlyph {
    static let moreTime = PaperGlyph(box: 22, [.rect(3.5, 4.5, 15, 14, rx: 3, 1.6), .stroke("M3.5 9h15M7.5 2.5v4M14.5 2.5v4", 1.6)])
    static let morePerson = PaperGlyph(box: 22, [.circle(11, 8, 3.5, 1.6), .stroke("M4.5 18.5c.8-3.2 3.4-5 6.5-5s5.7 1.8 6.5 5", 1.6)])
    static let moreEnvelope = PaperGlyph(box: 22, [.rect(3, 5, 16, 12, rx: 3, 1.6), .stroke("M4 7.5l7 5 7-5", 1.6)])
    static let moreCamera = PaperGlyph(box: 22, [
        .stroke("M3 8.5A2.5 2.5 0 0 1 5.5 6h1.7l1.3-2h5l1.3 2h1.7A2.5 2.5 0 0 1 19 8.5v7a2.5 2.5 0 0 1-2.5 2.5h-11A2.5 2.5 0 0 1 3 15.5z", 1.6),
        .circle(11, 12, 3.2, 1.6),
    ])
    static let morePhone = PaperGlyph(box: 22, [
        .stroke("M7.2 3.5H5.5a2 2 0 0 0-2 2.2c.6 6.5 5.3 11.2 11.8 11.8a2 2 0 0 0 2.2-2v-1.7a1.5 1.5 0 0 0-1.1-1.4l-2.6-.8a1.5 1.5 0 0 0-1.5.4l-.9.9a8 8 0 0 1-3.3-3.3l.9-.9a1.5 1.5 0 0 0 .4-1.5l-.8-2.6a1.5 1.5 0 0 0-1.4-1.1z", 1.6),
    ])
    static let moreBubble = PaperGlyph(box: 22, [.stroke("M4 7a3 3 0 0 1 3-3h8a3 3 0 0 1 3 3v5a3 3 0 0 1-3 3h-4l-4 3.5V15a3 3 0 0 1-3-3z", 1.6)])
    static let morePause = PaperGlyph(box: 22, [.circle(11, 11, 8, 1.6), .stroke("M9 8v6M13 8v6", 1.6)])
    static let moreCancel = PaperGlyph(box: 22, [.circle(11, 11, 8, 1.6), .stroke("M8.2 8.2l5.6 5.6M13.8 8.2l-5.6 5.6", 1.6)])
}

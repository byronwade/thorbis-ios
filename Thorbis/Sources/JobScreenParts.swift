import SwiftUI
import UIKit

// The job screen's pieces (Job.dc.html, OnSite.dc.html, JobActivity.dc.html): one white panel per
// section on the cream ground with a 13pt label above it, rows of a title and one line, status as
// a word beside its dot, quiet 44pt circles, and the technician's on-site toolkit.

/// A section's white panel: radius 14, a faint rim, no separators between rows.
struct JobPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.border.opacity(0.55), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.04), radius: 1, y: 1)
    }
}

/// The 13pt marker label above a panel, with at most one text action on the right.
struct JobPanelLabel: View {
    let title: String
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
            Text(title)
                .font(Theme.font(13, weight: .medium))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if !stacked { Spacer(minLength: 8) }
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(Theme.font(13, weight: .medium))
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
        .frame(minHeight: 30)
        .padding(.vertical, actionTitle == nil || stacked ? 0 : -7)
    }
}

/// A label and its panel.
struct JobPanelSection<Content: View>: View {
    let title: String
    var actionTitle: String? = nil
    var actionIdentifier: String? = nil
    var action: (() -> Void)? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            JobPanelLabel(title: title, actionTitle: actionTitle, actionIdentifier: actionIdentifier, action: action)
            JobPanel { content }
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

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.foreground)
                .frame(width: 44, height: 44)
                .background(Theme.fill, in: Circle())
                .overlay(Circle().strokeBorder(Theme.border.opacity(0.6), lineWidth: 1))
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

/// The three job sections as one pill segmented control: field track, the chosen one a raised
/// white pill. Values stay "Overview", "Money", "Activity"; only the words change.
struct JobSectionControl: View {
    let options: [(value: String, label: String, spoken: String)]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let isOn = option.value == selection
                Button { withMotion(.snappy) { selection = option.value } } label: {
                    Text(option.label)
                        .font(Theme.monoFont(14, weight: .medium))
                        .foregroundStyle(isOn ? Theme.foreground : Theme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background {
                            if isOn {
                                Capsule().fill(Theme.selectedSegment)
                                    .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
                                    .shadow(color: Color.black.opacity(0.10), radius: 1, y: 1)
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(option.spoken)
                .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("job-section-\(option.value.lowercased())")
            }
        }
        .padding(.horizontal, 3)
        .background(Theme.fill, in: Capsule().inset(by: 1))
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// One tool on the on-site grid: an 84pt white tile, glyph over word.
struct JobToolTile: View {
    let title: String
    let symbol: String
    var enabled = true
    var hint: String? = nil
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Theme.foreground)
                    .frame(height: 24)
                Text(title)
                    .font(Theme.font(13, weight: .medium))
                    .foregroundStyle(Theme.foreground)
                    .multilineTextAlignment(.center)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 84)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.border.opacity(0.55), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.04), radius: 1, y: 1)
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

/// A closeout row's tick: green with a check when done, an empty ring when not.
struct JobTick: View {
    let done: Bool

    var body: some View {
        ZStack {
            if done {
                Circle().fill(Theme.success)
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.onInk)
            } else {
                Circle().strokeBorder(Theme.foreground.opacity(0.3), lineWidth: 1.5)
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
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
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.warning)
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
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
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.border.opacity(0.55), lineWidth: 1))
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

/// Whole dollars without cents, cents when there are some: "$340", "$340.50".
func jobShortMoney(_ cents: Int, currency: String) -> String {
    let text = money(cents, currency: currency)
    return cents % 100 == 0 && text.hasSuffix(".00") ? String(text.dropLast(3)) : text
}

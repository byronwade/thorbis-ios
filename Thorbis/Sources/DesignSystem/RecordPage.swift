import SwiftUI

// Owner 2026-11-21: decluttered record pages. A job, a customer, an estimate and an invoice share
// one skeleton instead of four: a top bar (Back, the title once the header has scrolled away, at
// most "+" and "•••"), then `RecordHeader` (small id and ONE status badge, the title, one muted
// line), then `RelatedRow` (the records this one belongs with, one tap away, always in this spot).
// Lists share `RecordListRow` and `RecordFilterChips`. This departs from the Paper file's separate
// headers (21, 35C, 40C, 48N) on purpose; the type, colours and spacing are still Paper v2's.

/// A record's status as one small tinted word. A chevron when tapping it opens the status sheet.
struct RecordStatusBadge: View {
    let word: String
    let tone: StatusTone
    var opensMenu = false

    var body: some View {
        HStack(spacing: 4) {
            Text(word).font(Theme.font(12, weight: .semibold)).foregroundStyle(tone.text)
                .fixedSize(horizontal: false, vertical: true)
            if opensMenu { PaperIcon(.chevronDown, size: 10, color: tone.text).accessibilityHidden(true) }
        }
        .padding(.horizontal, 8).padding(.vertical, 2)
        .background(tone.surface, in: Capsule())
    }
}

/// The header every record page starts with: "JOB-2214  [Dispatched]", the title, one muted line.
/// Nothing else belongs here: chips, steps and links have their own homes (the bottom bar, `RelatedRow`).
struct RecordHeader<Badge: View>: View {
    let reference: String
    var referenceSpoken: String? = nil
    var referenceIdentifier: String? = nil
    let title: String
    var titleIdentifier: String? = nil
    var subtitle: String? = nil
    var subtitleSpoken: String? = nil
    var subtitleIdentifier: String? = nil
    @ViewBuilder var badge: Badge
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            FlowRow(spacing: 8, lineSpacing: 4) {
                if !reference.isEmpty {
                    Text(reference).font(Theme.font(13, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(referenceSpoken ?? reference)
                        .accessibilityIdentifier(referenceIdentifier ?? "record-reference")
                }
                badge
            }
            // Three lines at most, like every page title; the whole title is read by VoiceOver.
            Text(title).font(Theme.heading()).tracking(-0.56)
                .foregroundStyle(Theme.foreground)
                .multilineTextAlignment(.leading)
                .lineLimit(typeSize.isAccessibilitySize ? 6 : 3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(titleIdentifier ?? "record-title")
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle).font(Theme.font(15)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(subtitleSpoken ?? subtitle)
                    .accessibilityIdentifier(subtitleIdentifier ?? "record-subtitle")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 14)
    }
}

extension RecordHeader where Badge == EmptyView {
    init(reference: String, referenceSpoken: String? = nil, referenceIdentifier: String? = nil,
         title: String, titleIdentifier: String? = nil,
         subtitle: String? = nil, subtitleSpoken: String? = nil, subtitleIdentifier: String? = nil) {
        self.init(reference: reference, referenceSpoken: referenceSpoken, referenceIdentifier: referenceIdentifier,
                  title: title, titleIdentifier: titleIdentifier,
                  subtitle: subtitle, subtitleSpoken: subtitleSpoken, subtitleIdentifier: subtitleIdentifier) { EmptyView() }
    }
}

/// One record a page links to: "Danielle Marlowe", "JOB-2214", "Estimates · 2", "Invoice · $340.00 due".
struct RelatedLink: Identifiable {
    /// Also the pill's accessibility identifier.
    let id: String
    let title: String
    var detail: String? = nil
    var hint: String? = nil
    let action: () -> Void
}

/// The records a page belongs with, as quiet pills directly under its header: the same place on a
/// job, an estimate and an invoice, in the same order (customer, job, estimates, invoice). Only
/// what exists is listed, never the page itself. Nothing is drawn when there is nothing to link.
struct RelatedRow: View {
    let links: [RelatedLink]
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if !links.isEmpty {
            Group {
                if typeSize.isAccessibilitySize {
                    // Large text: the pills wrap onto their own lines instead of scrolling sideways.
                    FlowRow(spacing: 8, lineSpacing: 0) { pills }
                        .padding(.horizontal, 16)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) { pills }.padding(.horizontal, 16)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Related")
            .accessibilityIdentifier("record-related")
        }
    }

    @ViewBuilder private var pills: some View {
        ForEach(links) { link in
            Button(action: link.action) {
                (Text(link.title).font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.foreground)
                 + Text(link.detail.map { " \u{00B7} \($0)" } ?? "").font(Theme.font(14)).foregroundStyle(Theme.muted))
                    .monospacedDigit()
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .frame(minWidth: 44, minHeight: 34)
                    .background(Theme.quietFill, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel([link.title, link.detail].compactMap { $0 }.joined(separator: ", "))
            .accessibilityHint(link.hint ?? "Opens it")
            .accessibilityIdentifier(link.id)
        }
    }
}

/// The record's title in the bar once its header has scrolled under it, so the page always says
/// what it is. Hidden from VoiceOver: the header is the page's heading.
struct RecordBarTitle: ToolbarContent {
    let title: String
    let shown: Bool

    var body: some ToolbarContent {
        ThorbisToolbarItem(placement: .principal) {
            // Drawn only once the header is gone, so the page never holds its title twice.
            if shown {
                Text(title).font(Theme.font(17, weight: .semibold)).foregroundStyle(Theme.foreground)
                    .lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: max(120, UIScreen.main.bounds.width - 236))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
        }
    }
}

extension View {
    /// Reports when this view (a record's header) has scrolled out under the bar.
    func reportsRecordHeaderCollapse(_ collapsed: Binding<Bool>) -> some View {
        onGeometryChange(for: Bool.self) { $0.frame(in: .scrollView).maxY < 8 } action: { collapsed.wrappedValue = $0 }
    }
}

/// One filter row per page: a single line of choice chips that scrolls sideways when it has to.
/// Jobs, Estimates, Invoices, Customers and a job's Activity all filter with this, so a list never
/// stacks a second chip row or mixes chips with a segmented control. Finer choices (the
/// stage of a job's photos) are one control inside their section, never a second chip row.
struct RecordFilterChips: View {
    struct Chip: Identifiable {
        let id: String
        let title: String
        var spoken: String? = nil
        var identifier: String? = nil
    }

    let chips: [Chip]
    @Binding var selection: String
    var hint: String? = nil
    /// The page's own leading inset; the row bleeds to the screen's edges so chips scroll under them.
    var inset: CGFloat = 16
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            // Large text: one menu control in place of a row that could not fit two chips.
            ThorbisMenu(items: chips.map { chip in
                ThorbisMenuItem(chip.title, isSelected: chip.id == selection) { selection = chip.id }
            }, title: "Show", accessibilityLabel: "Show, \(chips.first { $0.id == selection }?.title ?? "")") {
                HStack(spacing: 12) {
                    Text(chips.first { $0.id == selection }?.title ?? "").font(Theme.font(15, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 13, weight: .medium)).accessibilityHidden(true)
                }
                .foregroundStyle(Theme.foreground)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            }
            .padding(.horizontal, inset)
            .accessibilityIdentifier("record-filter-menu")
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(chips) { chip in
                        let isOn = chip.id == selection
                        Button { withMotion(.snappy) { selection = chip.id } } label: {
                            PaperChoiceChipLabel(title: chip.title, isOn: isOn)
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel(chip.spoken ?? chip.title)
                        .accessibilityHint(hint ?? "")
                        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
                        .accessibilityIdentifier(chip.identifier ?? "record-filter-\(chip.id.lowercased())")
                    }
                }
                .padding(.horizontal, inset)
            }
        }
    }
}

/// One row for every list of records: the title, one muted line, and at the trailing edge either
/// an amount or a status word. No leading mark, no third line, no avatar.
struct RecordListRow: View {
    enum Trailing: Equatable {
        case none
        case amount(String)
        case status(String, StatusTone)
    }

    let title: String
    let detail: String
    var trailing: Trailing = .none
    /// Finished or cancelled records read quieter.
    var quiet = false
    /// The muted line in the error hue (a late visit, an overdue invoice).
    var urgent = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                             : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.font(16, weight: .medium)).tracking(-0.16)
                    .foregroundStyle(quiet ? Theme.subtle : Theme.foreground)
                    .lineLimit(stacked ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)
                if !detail.isEmpty {
                    Text(detail).font(Theme.font(14))
                        .foregroundStyle(urgent ? Theme.destructive : Theme.muted)
                        .lineLimit(stacked ? nil : 1)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            switch trailing {
            case .none: EmptyView()
            case .amount(let amount):
                Text(amount).font(Theme.font(16, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(quiet ? Theme.muted : Theme.foreground)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .fixedSize(horizontal: !stacked, vertical: false)
            case .status(let word, let tone):
                RecordStatusBadge(word: word, tone: tone)
                    .fixedSize(horizontal: !stacked, vertical: false)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .contentShape(Rectangle())
    }
}

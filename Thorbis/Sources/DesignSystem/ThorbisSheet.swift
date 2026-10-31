import SwiftUI

// MARK: - Scaffold

/// The title row every Thorbis sheet shares (v2): 17pt Medium title on the left, a close circle
/// on the right, 20pt from the edges. The grabber above stays the system's.
struct ThorbisSheetHeader: View {
    let title: String?
    var closeLabel = "Close"
    var onClose: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let title {
                Text(title).font(Theme.font(17, weight: .medium)).foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
            if let onClose {
                PaperCircleButton(symbol: "xmark", label: closeLabel, size: 30, fill: Theme.fill, action: onClose)
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 14).padding(.bottom, 4)
    }
}

extension View {
    /// A modal sheet's presentation (v2, design.thorbis.com "Our sheet does not" use glass): the
    /// panel as its background (no Liquid Glass on iOS 26), the system grabber, the given detents.
    /// The scrim behind stays the system's solid dim.
    func thorbisSheetPresentation(_ detents: Set<PresentationDetent> = [.medium, .large]) -> some View {
        self
            .presentationDetents(detents)
            .presentationDragIndicator(.visible)
            .presentationBackground(Theme.surface)
    }
}

/// A bottom sheet, Linear-mobile style: the shared title row with a close circle, then the content
/// grouped by space on the panel. Use for filters and display options.
struct ThorbisSheetScaffold<Content: View>: View {
    var title: String? = nil
    var onClose: (() -> Void)? = nil
    var detents: Set<PresentationDetent> = [.medium, .large]
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            if title != nil || onClose != nil {
                ThorbisSheetHeader(title: title, onClose: onClose)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    content()
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, title == nil ? 18 : 12)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .thorbisSheetPresentation(detents)
    }
}

/// A modal (design.thorbis.com Places: "One task. Done or not."): the shared title row, the content
/// grouped by space on the panel with 20pt padding (fields are sunk wells), and one ink commit
/// inside the sheet's padding at the bottom. The commit is never pre-disabled: let them press it,
/// then show what is missing under the field. When it truly must be off, `commitDisabledReason`
/// says why under the commit.
struct ThorbisModalSheet<Content: View>: View {
    let title: String
    var closeLabel = "Close"
    var onClose: (() -> Void)? = nil
    var detents: Set<PresentationDetent> = [.medium, .large]
    var commitTitle: String? = nil
    var commitSymbol: String? = nil
    var busy = false
    /// Non-nil turns the commit off and shows this sentence under it.
    var commitDisabledReason: String? = nil
    var destructive = false
    var commitIdentifier: String? = nil
    var commit: () -> Void = {}
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            ThorbisSheetHeader(title: title, closeLabel: closeLabel, onClose: onClose)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    content()
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let commitTitle {
                VStack(alignment: .leading, spacing: 8) {
                    Button(action: commit) {
                        HStack(spacing: 7) {
                            if busy { ProgressView().tint(destructive ? .white : Theme.onInk) }
                            else if let commitSymbol { Image(systemName: commitSymbol).accessibilityHidden(true) }
                            Text(commitTitle)
                        }
                        .modifier(CommitLook(destructive: destructive, enabled: commitDisabledReason == nil))
                    }
                    .buttonStyle(PressStyle())
                    .disabled(busy || commitDisabledReason != nil)
                    .accessibilityHint(commitDisabledReason ?? "")
                    .accessibilityIdentifier(commitIdentifier ?? "sheet-commit")
                    if let commitDisabledReason {
                        Text(commitDisabledReason).font(Theme.font(13)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, Theme.gutter).padding(.top, 8).padding(.bottom, 12)
                .background(Theme.surface)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(Theme.foreground)
        .background(Theme.surface)
        .thorbisSheetPresentation(detents)
    }
}

private struct CommitLook: ViewModifier {
    let destructive: Bool
    let enabled: Bool
    func body(content: Content) -> some View {
        if destructive { content.dangerCommit(enabled: enabled) } else { content.inkCommit(enabled: enabled) }
    }
}

/// A labelled field in a modal: the label stays above (13 Medium, marker), the answer in a sunk
/// well, and one slot under it where help sits and an error takes its place.
struct ThorbisSheetField<Content: View>: View {
    let label: String
    var help: String? = nil
    var error: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
            content()
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

// MARK: - Grouped rows

/// One rounded panel step that holds a run of sheet rows (Linear's grouped rows, radius 14). v2:
/// no lines between rows. Put an optional label above it with `ThorbisSheetLabel`.
struct ThorbisSheetGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        // On the sheet's panel a group is one step darker (the select's sink), radius 14.
        VStack(alignment: .leading, spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
            .environment(\.paperRowInset, PaperCardMetrics.inset)
    }
}

/// Where rows of a sheet group meet; draws nothing (v2).
struct ThorbisSheetDivider: View {
    var body: some View { WellDivider() }
}

/// The chrome label above a sheet group, like a list's `SectionHeader`.
struct ThorbisSheetLabel: View {
    let title: String
    var body: some View {
        Text(title).font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4).padding(.bottom, -10)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A row that shows its current value; tap opens a `ThorbisMenu` of `options` and the chosen one
/// calls `onSelect`. The value reads as the answer, with Linear's small up-down chevron.
struct ThorbisSheetRow: View {
    let label: String
    let value: String
    var options: [String] = []
    var onSelect: (String) -> Void = { _ in }

    var body: some View {
        ThorbisMenu(
            items: options.map { option in
                ThorbisMenuItem(option, isSelected: option == value) { onSelect(option) }
            },
            title: label,
            accessibilityLabel: "\(label), \(value)"
        ) {
            HStack(spacing: 8) {
                Text(label).font(Theme.font(16)).foregroundStyle(Theme.foreground)
                Spacer(minLength: 8)
                Text(value).font(Theme.font(15)).foregroundStyle(Theme.muted).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.muted).accessibilityHidden(true)
            }
            .padding(.horizontal, PaperCardMetrics.inset).frame(minHeight: 48).contentShape(Rectangle())
        }
    }
}

/// A row with a label and a trailing switch. A switch is a switch — the reference keeps the
/// native control; only its tint is ours.
struct ThorbisSheetToggleRow: View {
    let label: String
    @Binding var isOn: Bool
    var body: some View {
        Toggle(isOn: $isOn) {
            Text(label).font(Theme.font(16)).foregroundStyle(Theme.foreground)
        }
        .tint(Theme.brand)
        .padding(.horizontal, PaperCardMetrics.inset).frame(minHeight: 48)
    }
}

// MARK: - Chips

/// A selectable capsule chip: a word on the well, filled with the ink when on. The reference
/// sheet's "Row properties" grid.
struct ThorbisChipToggle: View {
    let label: String
    let isOn: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Theme.font(13, weight: .medium))
                .foregroundStyle(isOn ? Theme.onInk : Theme.foreground)
                .lineLimit(1).fixedSize()
                .padding(.horizontal, 12).frame(minHeight: Theme.chipHeight)
                .background(isOn ? Theme.ink : Theme.fill, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
                // 44pt to the finger, 28 to the eye.
                .padding(.vertical, 8).contentShape(Rectangle()).padding(.vertical, -8)
        }
        .buttonStyle(PressStyle())
        // A small spring as the chip fills (phase 4); a plain fade under Reduce Motion.
        .animation(Theme.selectionSpring(reduceMotion: reduceMotion), value: isOn)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

/// A wrapping row of chips using the shared `FlowRow` layout.
struct ThorbisChipGroup<Data: RandomAccessCollection, ID: Hashable>: View where Data.Element: Hashable {
    let data: Data
    let id: KeyPath<Data.Element, ID>
    let isOn: (Data.Element) -> Bool
    let label: (Data.Element) -> String
    let toggle: (Data.Element) -> Void

    var body: some View {
        FlowRow(spacing: 8, lineSpacing: 8) {
            ForEach(data, id: id) { element in
                ThorbisChipToggle(label: label(element), isOn: isOn(element)) { toggle(element) }
            }
        }
    }
}

// MARK: - A reusable list "Display" model (drives filter/display sheets)

/// How a list is grouped, ordered and filtered. A value type so the rules are unit-testable
/// without any UI. Screens map these onto their own filtering.
struct DisplayOptions: Equatable {
    enum Grouping: String, CaseIterable, Identifiable {
        case status, assignee, date, none
        var id: String { rawValue }
        var label: String {
            switch self {
            case .status: "Status"
            case .assignee: "Assignee"
            case .date: "Date"
            case .none: "None"
            }
        }
    }
    enum Ordering: String, CaseIterable, Identifiable {
        case recent, scheduled, name
        var id: String { rawValue }
        var label: String {
            switch self {
            case .recent: "Last updated"
            case .scheduled: "Scheduled time"
            case .name: "Name"
            }
        }
    }

    var grouping: Grouping = .status
    var ordering: Ordering = .recent
    var showCompleted: Bool = true
}

#if DEBUG
#Preview("ThorbisSheet — display options") {
    struct Demo: View {
        @State private var opts = DisplayOptions()
        @State private var fields: Set<String> = ["Customer", "Time"]
        let allFields = ["Customer", "Time", "Job #", "Status", "Assignee", "Address"]
        var body: some View {
            ThorbisSheetScaffold(title: "Display", onClose: {}) {
                ThorbisSheetGroup {
                    ThorbisSheetRow(label: "Grouping", value: opts.grouping.label,
                                    options: DisplayOptions.Grouping.allCases.map(\.label)) { picked in
                        opts.grouping = DisplayOptions.Grouping.allCases.first { $0.label == picked } ?? .status
                    }
                    ThorbisSheetDivider()
                    ThorbisSheetRow(label: "Ordering", value: opts.ordering.label,
                                    options: DisplayOptions.Ordering.allCases.map(\.label)) { picked in
                        opts.ordering = DisplayOptions.Ordering.allCases.first { $0.label == picked } ?? .recent
                    }
                    ThorbisSheetDivider()
                    ThorbisSheetToggleRow(label: "Show completed", isOn: $opts.showCompleted)
                }
                ThorbisSheetLabel(title: "Row properties")
                ThorbisChipGroup(data: allFields, id: \.self, isOn: { fields.contains($0) }, label: { $0 }) { field in
                    if fields.contains(field) { fields.remove(field) } else { fields.insert(field) }
                }
            }
        }
    }
    return Color.clear.sheet(isPresented: .constant(true)) { Demo() }
}
#endif

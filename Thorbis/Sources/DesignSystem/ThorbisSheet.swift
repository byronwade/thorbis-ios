import SwiftUI

// MARK: - Scaffold

/// A bottom sheet, Linear-mobile style: a grabber, an optional semibold title row with a close
/// circle, and grouped rounded wells on the white ground (phase 4, like Linear's display options). Use for filters and display options — the
/// place stock `Picker`/`confirmationDialog` used to go.
struct ThorbisSheetScaffold<Content: View>: View {
    var title: String? = nil
    var onClose: (() -> Void)? = nil
    var detents: Set<PresentationDetent> = [.medium, .large]
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            if title != nil || onClose != nil {
                HStack {
                    if let title {
                        Text(title).font(Theme.font(18, weight: .semibold)).foregroundStyle(Theme.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                    }
                    Spacer(minLength: 0)
                    if let onClose {
                        PaperCircleButton(symbol: "xmark", label: "Close", action: onClose)
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 14).padding(.bottom, 6)
            }
            ScrollView {
                // Calm and roomy, like Linear's display options: grouped wells with generous gaps.
                VStack(alignment: .leading, spacing: 24) {
                    content()
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, title == nil ? 18 : 6)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.background)
        .presentationDetents(detents)
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Grouped rows

/// One rounded well that holds a run of sheet rows (phase 4: Linear's grouped rows, radius 14,
/// inset hairlines via `ThorbisSheetDivider`). Put an optional label above it with `ThorbisSheetLabel`.
struct ThorbisSheetGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        Well { content() }
    }
}

/// The inset hairline between rows of a sheet group.
struct ThorbisSheetDivider: View {
    var body: some View { WellDivider() }
}

/// The semibold label above a sheet group, like a list's `SectionHeader`.
struct ThorbisSheetLabel: View {
    let title: String
    var body: some View {
        Text(title).font(Theme.font(14, weight: .semibold)).foregroundStyle(Theme.muted)
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
                Text(label).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                Spacer(minLength: 8)
                Text(value).font(Theme.font(15)).foregroundStyle(Theme.muted).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.muted).accessibilityHidden(true)
            }
            .padding(.horizontal, PaperCardMetrics.inset).frame(minHeight: 52).contentShape(Rectangle())
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
            Text(label).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
        }
        .tint(Theme.brand)
        .padding(.horizontal, PaperCardMetrics.inset).frame(minHeight: 52)
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
                .padding(.horizontal, 12).frame(minHeight: Theme.chipHeight + 4)
                .background(isOn ? Theme.ink : Theme.fill, in: Capsule())
                .overlay(Capsule().stroke(isOn ? Color.clear : Theme.border))
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

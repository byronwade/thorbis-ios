import SwiftUI
import UIKit

// MARK: - Scaffold

/// Where a sheet draws its way out (Paper v2).
enum ThorbisSheetCloseStyle {
    /// Paper's default. A `ThorbisModalSheet` whose close is "Cancel" and that has a bottom commit
    /// draws Cancel as a pill under the commit (Pause this job, Assign a technician); every other
    /// sheet draws the 44pt close circle beside the title (Schedule).
    case automatic
    /// The 44pt circle with a cross: on the right of a leading title, on the left of a centred one.
    case circle
    /// The close word as a pill on the left of the title row; the title is centred.
    case headerPill
    /// `ThorbisModalSheet` only: the close word as a full-width pill at the bottom, under the commit.
    /// The header draws no close.
    case bottomPill
}

/// A commit drawn in the title row (Paper Edit photo: a 44pt brand pill, "Done"), in place of a
/// bottom commit. Its identifier defaults to `sheet-commit`.
struct ThorbisSheetHeaderAction {
    var title: String
    var busy = false
    var enabled = true
    var identifier: String? = nil
    /// Read by VoiceOver while the commit is off ("Your role can't add customers.").
    var hint: String? = nil
    /// What VoiceOver reads when it says more than the pill ("Save" reads "Save equipment").
    var accessibilityLabel: String? = nil
    var action: () -> Void
}

/// The title row every Thorbis sheet shares (Paper v2), 20pt from the edges under the system
/// grabber. By default a 22 Bold title on the left with an optional 15pt muted line under it, and a
/// 44pt close circle on the right. With `closeStyle: .headerPill` or a `trailing` commit the close
/// moves to the left, the title is centred at 17 Semibold and the commit pill sits on the right.
struct ThorbisSheetHeader: View {
    let title: String?
    /// One muted line under the title that names the thing ("AC not cooling · JOB-2214").
    var subtitle: String? = nil
    var closeLabel = "Close"
    var onClose: (() -> Void)? = nil
    var closeStyle: ThorbisSheetCloseStyle = .automatic
    var trailing: ThorbisSheetHeaderAction? = nil

    private var closeOnLeft: Bool { closeStyle == .headerPill || trailing != nil }
    private var drawsClose: Bool { onClose != nil && closeStyle != .bottomPill }

    var body: some View {
        Group {
            if closeOnLeft { barRow } else { titleRow }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, PaperSheetMetrics.headerTop).padding(.bottom, 6)
    }

    /// Leading title and subtitle, the close circle on the right.
    private var titleRow: some View {
        HStack(alignment: .center, spacing: 12) {
            PaperSheetTitle(title: title, subtitle: subtitle)
            if drawsClose, let onClose {
                PaperCircleButton(symbol: "xmark", label: closeLabel, size: 44, fill: Theme.fill, action: onClose)
            }
        }
    }

    /// Close on the left, the title centred, the commit pill on the right.
    private var barRow: some View {
        ZStack {
            VStack(spacing: 1) {
                if let title {
                    Text(title).font(Theme.font(17, weight: .semibold)).foregroundStyle(Theme.foreground)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .accessibilityAddTraits(.isHeader)
                }
                if let subtitle {
                    Text(subtitle).font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            .padding(.horizontal, 92)
            HStack(spacing: 12) {
                if drawsClose, let onClose {
                    if closeStyle == .headerPill {
                        Button(action: onClose) {
                            Text(closeLabel).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                                .lineLimit(1).fixedSize()
                                .padding(.horizontal, 16).frame(minHeight: 44)
                                .background(Theme.fill, in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(PressStyle())
                    } else {
                        PaperCircleButton(symbol: "xmark", label: closeLabel, size: 44, fill: Theme.fill, action: onClose)
                    }
                }
                Spacer(minLength: 0)
                if let trailing {
                    Button(action: trailing.action) {
                        HStack(spacing: 6) {
                            if trailing.busy { ProgressView().tint(.white) }
                            Text(trailing.title)
                        }
                        .font(Theme.font(16, weight: .semibold)).foregroundStyle(Color.white)
                        .lineLimit(1).fixedSize()
                        .padding(.horizontal, 18).frame(minHeight: 44)
                        .background(Theme.brand.opacity(trailing.enabled ? 1 : 0.45), in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(PressStyle())
                    .disabled(trailing.busy || !trailing.enabled)
                    .accessibilityIdentifier(trailing.identifier ?? "sheet-commit")
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
    }
}

/// A sheet's title words (Paper 20A "Filters", 21E "Pause this job", 21K): 22/28 Bold (-0.02em)
/// and, 2 under it, one 15/20 muted line that names the thing. Every sheet that leads with a
/// title draws it with this, whatever sits at its trailing edge (close circle, Reset, Done).
struct PaperSheetTitle: View {
    let title: String?
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let title {
                Text(title).font(Theme.font(22, weight: .bold)).tracking(-0.44).foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            if let subtitle {
                Text(subtitle).font(Theme.font(15)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Where the first row of each kind of sheet stands, so every sheet of a kind opens at one height:
/// a compact sheet's title row (`ThorbisSheetHeader`) and a task sheet's bar (`PaperTaskBar`) sit
/// 14 under the sheet's top; a sheet Paper draws as a whole page (40 Edit invoice, 21F Checklist,
/// 36 Sign estimate, 65 Settings) puts its 44pt circle row 2 under it, as a pushed page does under
/// the status bar (Paper's circle row: `paddingTop: 2`).
enum PaperSheetMetrics {
    static let headerTop: CGFloat = 14
    static let pageTop: CGFloat = 2
}

/// The circle row of a sheet that is a whole page (Paper 40, 21F, 36): the way out on the left, an
/// optional "…" or quiet word on the right, 16 from the sides, `PaperSheetMetrics.pageTop` under the
/// sheet's top. Put it in `.safeAreaInset(edge: .top, spacing: 0)` with the system bar hidden, so it
/// stands at the same height on every page sheet instead of wherever a navigation bar centres it.
struct PaperPageSheetBar<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            leading
            Spacer(minLength: 0)
            trailing
        }
        .frame(minHeight: 44)
        .padding(.horizontal, PaperCardMetrics.margin)
        .padding(.top, PaperSheetMetrics.pageTop).padding(.bottom, 2)
    }
}

/// A task sheet's title row (Paper 27A "Time off", 42B, 82C, 88B, 21T): the way out on a card pill
/// (16 Medium), the title in 17/22 Semibold between, the commit on a brand pill (16 Semibold). 44
/// tall, 16 from the edges, 14 under the sheet's top. This is the one bar for a sheet that is a
/// form; a short sheet uses `ThorbisSheetHeader` (22 Bold title, close circle).
/// When the three do not fit one line the title takes its own line under the pills.
struct PaperTaskBar: View {
    let title: String
    var cancelTitle = "Cancel"
    var cancelDisabled = false
    /// The way out's identifier where UI tests find it ("edit-customer-cancel").
    var cancelIdentifier: String? = nil
    /// What VoiceOver reads for the way out when "Cancel" alone is unclear.
    var cancelAccessibilityLabel: String? = nil
    /// The brand pill; nil where the commit sits at the bottom of the sheet (or there is none).
    var commit: ThorbisSheetHeaderAction? = nil
    let onCancel: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(titleInRow: true)
            VStack(alignment: .leading, spacing: 10) {
                row(titleInRow: false)
                titleText.fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, PaperCardMetrics.margin).padding(.top, PaperSheetMetrics.headerTop).padding(.bottom, 2)
    }

    private var titleText: some View {
        Text(title).font(Theme.font(17, weight: .semibold)).foregroundStyle(Theme.foreground)
            .accessibilityAddTraits(.isHeader)
    }

    private func row(titleInRow: Bool) -> some View {
        HStack(spacing: 0) {
            Button(action: onCancel) {
                Text(cancelTitle).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                    .lineLimit(1).fixedSize()
                    .padding(.horizontal, 16).frame(minHeight: 44)
                    .background(Theme.card, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(PressStyle())
            .disabled(cancelDisabled)
            .accessibilityLabel(cancelAccessibilityLabel ?? cancelTitle)
            .modifier(OptionalIdentifier(identifier: cancelIdentifier))
            Spacer(minLength: 8)
            if titleInRow { titleText.lineLimit(1).fixedSize(); Spacer(minLength: 8) }
            if let commit {
                Button(action: commit.action) {
                    HStack(spacing: 6) {
                        if commit.busy { ProgressView().tint(.white) }
                        Text(commit.title).font(Theme.font(16, weight: .semibold)).lineLimit(1).fixedSize()
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 18).frame(minHeight: 44)
                    .background(Theme.brand.opacity(commit.enabled ? 1 : 0.45), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .disabled(commit.busy || !commit.enabled)
                .accessibilityLabel(commit.accessibilityLabel ?? commit.title)
                .accessibilityHint(commit.hint ?? "")
                .accessibilityIdentifier(commit.identifier ?? "sheet-commit")
            } else if titleInRow {
                // Balances the way out so the title sits in the middle (Paper 41A / 27B).
                Text(cancelTitle).font(Theme.font(16, weight: .medium)).lineLimit(1).fixedSize()
                    .padding(.horizontal, 16).hidden().accessibilityHidden(true)
            }
        }
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
            .thorbisSheetSurface()
    }
}

/// A bottom sheet, Linear-mobile style: the shared title row with a close circle, then the content
/// grouped by space on the panel. Use for filters and display options.
struct ThorbisSheetScaffold<Content: View>: View {
    var title: String? = nil
    var onClose: (() -> Void)? = nil
    var detents: Set<PresentationDetent> = [.medium, .large]
    /// A commit in the title row (Paper 40D "Add"): the brand pill on the right, the close circle
    /// on the left and the title centred, as `ThorbisSheetHeader` draws any `trailing` action.
    var headerAction: ThorbisSheetHeaderAction? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            if title != nil || onClose != nil || headerAction != nil {
                ThorbisSheetHeader(title: title, onClose: onClose, trailing: headerAction)
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
///
/// Paper v2 chrome: a "Cancel" close with a bottom commit is a fill pill under the commit (side by
/// side with it while the keyboard is up, so both stay in reach); a "Close" is the 44pt circle
/// beside the title. `subtitle` names the thing under the title. `commitInHeader` moves the commit
/// into the title row as a brand pill (Paper Edit photo) with the close on the left.
struct ThorbisModalSheet<Content: View>: View {
    let title: String
    /// One muted line under the title that names the thing ("AC not cooling · JOB-2214").
    var subtitle: String? = nil
    var closeLabel = "Close"
    var onClose: (() -> Void)? = nil
    var closeStyle: ThorbisSheetCloseStyle = .automatic
    var detents: Set<PresentationDetent> = [.medium, .large]
    var commitTitle: String? = nil
    var commitSymbol: String? = nil
    var busy = false
    /// Non-nil turns the commit off and shows this sentence under it.
    var commitDisabledReason: String? = nil
    var destructive = false
    var commitIdentifier: String? = nil
    var commit: () -> Void = {}
    /// Draws the commit as a pill in the title row instead of at the bottom.
    var commitInHeader = false
    /// Number pads and accessibility sizes have no Return; Done under the commit puts the keyboard
    /// away (MA-16). A form drag would pull an empty New customer sheet (#460).
    var onKeyboardDone: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var keyboardShown = false

    /// The bottom commit's title; nil when there is no commit or it sits in the title row.
    private var bottomCommitTitle: String? { commitInHeader ? nil : commitTitle }

    /// True when the close is the pill under the commit.
    private var cancelAtBottom: Bool {
        guard onClose != nil else { return false }
        switch closeStyle {
        case .bottomPill: return true
        case .automatic: return closeLabel == "Cancel" && bottomCommitTitle != nil
        case .circle, .headerPill: return false
        }
    }

    private var headerCloseStyle: ThorbisSheetCloseStyle {
        if cancelAtBottom { return .bottomPill }
        if closeStyle == .automatic { return commitInHeader && closeLabel != "Close" ? .headerPill : .circle }
        return closeStyle
    }

    private var headerCommit: ThorbisSheetHeaderAction? {
        guard commitInHeader, let commitTitle else { return nil }
        return ThorbisSheetHeaderAction(title: commitTitle, busy: busy, enabled: commitDisabledReason == nil,
                                        identifier: commitIdentifier, action: commit)
    }

    /// With the keyboard up Cancel and the commit share one row, so neither is pushed off a short sheet.
    private var sideBySide: Bool {
        cancelAtBottom && bottomCommitTitle != nil && keyboardShown && !typeSize.isAccessibilitySize
    }

    private func commitButton(_ commitTitle: String) -> some View {
        Button(action: commit) {
            HStack(spacing: 7) {
                if busy { ProgressView().tint(.white) }
                else if let commitSymbol { Image(systemName: commitSymbol).accessibilityHidden(true) }
                Text(commitTitle)
            }
            .modifier(CommitLook(destructive: destructive, enabled: commitDisabledReason == nil))
        }
        .buttonStyle(PressStyle())
        .disabled(busy || commitDisabledReason != nil)
        .accessibilityHint(commitDisabledReason ?? "")
        .accessibilityIdentifier(commitIdentifier ?? "sheet-commit")
    }

    /// Paper: the close word on a 50pt fill pill, 8 under the commit.
    private var cancelPill: some View {
        Button { onClose?() } label: {
            Text(closeLabel).font(Theme.font(16, weight: .semibold)).foregroundStyle(Theme.foreground)
                .frame(maxWidth: .infinity).frame(minHeight: Theme.commitHeight)
                .background(Theme.fill, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
    }

    var body: some View {
        VStack(spacing: 0) {
            ThorbisSheetHeader(title: title, subtitle: subtitle, closeLabel: closeLabel, onClose: onClose,
                               closeStyle: headerCloseStyle, trailing: headerCommit)
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
            // A drag down the form puts the keyboard away, as the forms did before the shared modal.
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                if bottomCommitTitle != nil || cancelAtBottom {
                    VStack(alignment: .leading, spacing: 8) {
                        if sideBySide, let bottomCommitTitle {
                            HStack(spacing: 10) {
                                cancelPill
                                commitButton(bottomCommitTitle)
                            }
                        } else {
                            if let bottomCommitTitle { commitButton(bottomCommitTitle) }
                            if cancelAtBottom { cancelPill }
                        }
                        if bottomCommitTitle != nil, let commitDisabledReason {
                            Text(commitDisabledReason).font(Theme.font(13)).foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityHidden(true)
                        }
                    }
                    // Paper v2: the commit and Cancel sit 20 from the sheet's edges; above and below them, the
                    // same room as every pinned bar (PaperActionBarMetrics).
                    .padding(.horizontal, Theme.gutter).padding(.top, PaperActionBarMetrics.top)
                    .padding(.bottom, keyboardShown && onKeyboardDone != nil ? 4 : PaperActionBarMetrics.bottom)
                }
                if onKeyboardDone != nil, keyboardShown {
                    HStack {
                        Spacer(minLength: 0)
                        Button("Done") {
                            onKeyboardDone?()
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        }
                        .buttonStyle(ThorbisBarButtonStyle(prominent: true))
                        .accessibilityIdentifier("keyboard-done")
                    }
                    .padding(.horizontal, Theme.gutter).padding(.top, bottomCommitTitle == nil && !cancelAtBottom ? 8 : 0).padding(.bottom, 8)
                }
            }
            .background(Theme.surface)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardShown = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardShown = false }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(Theme.foreground)
        .background(Theme.surface)
        // At accessibility sizes the task opens full height so the fields and the commit both show.
        .thorbisSheetPresentation(typeSize.isAccessibilitySize ? [.large] : detents)
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
            Text(label).font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                .padding(.horizontal, 4)
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

/// A selectable chip. Paper has one chip (20A: 40 tall, 14 Medium, brand tint when chosen), so
/// this is `PaperChoiceChip` under its older name; kept so existing call sites read the same.
struct ThorbisChipToggle: View {
    let label: String
    let isOn: Bool
    let action: () -> Void
    var body: some View {
        PaperChoiceChip(title: label, isOn: isOn, action: action)
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

/// A sheet's content on the panel (`thorbisSheetSurface`): wrap a `.sheet` content closure that
/// shows an app screen or an editor, so screens in sheets share one ground with the modals.
/// System UI (share, Safari, Quick Look, Mail, Calendar and Contacts editors) stays native.
struct SheetSurface<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View { content().thorbisSheetSurface() }
}

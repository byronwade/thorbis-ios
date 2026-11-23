import SwiftUI

/// The job's status sheet (Paper 21T "Change job status"): a full-width bottom sheet opened from the
/// status chip. It lists where the job is now (the brand row), then every move the server allows,
/// in cards: forward moves first, then the moves that step back or stop the work (Pause job, Move
/// back to scheduled). Destructive moves keep their danger tone. On iPad it is the centred card of
/// Paper's tablet file.
///
/// Built on `ThorbisMenuModel`, so the run-after-close behaviour matches `ThorbisMenu`: a tapped
/// move closes the sheet, then runs. The cards and rows are its own (`JobStatusMenuPanel`).
///
/// Optional, all defaulted:
/// - `subtitle`: the muted line under the title (Paper: "JOB-2214 · AC not cooling").
/// - `footnote`: one quiet sentence under the cards (Paper: "Danielle gets a text when you move to
///   Wrap up."). Pass it only when the server says so.
/// - A row's `detail` (`ThorbisMenuItem.detail`) is its trailing value (a step's time, "Next",
///   "$340 due"); the current row's `subtitle` follows "Current" ("Current · 0:42 on site").
/// - `doneSteps`: the steps the job has already passed (Paper 21T: a green tick, the step's name
///   and when it happened). They lead the first card and are not choices; pass only steps with a
///   real time from the job's record.
struct JobStatusMenu<Label: View>: View {
    /// Each inner array is one group; empty groups are skipped.
    let groups: [[ThorbisMenuItem]]
    var title: String? = "Status"
    var accessibilityLabel: String? = nil
    /// Screenshot-only: open on appear (preview flags).
    var opensOnAppear = false
    var subtitle: String? = nil
    var footnote: String? = nil
    var doneSteps: [JobStatusDoneStep] = []
    @ViewBuilder var label: () -> Label

    @State private var model = ThorbisMenuModel()
    @State private var regularWidth = false

    private func present() {
        regularWidth = ThorbisMenuWindow.isRegularWidth
        model.isPresented = true
    }

    var body: some View {
        Button { ThorbisKeyboard.dismiss { present() } } label: { label() }
            .buttonStyle(PressStyle())
            .sensoryFeedback(.selection, trigger: model.isPresented) { _, open in open }
            .accessibilityLabel(accessibilityLabel ?? title ?? "Status")
            // The chosen move waits for the sheet to go (`onDismiss`), so a move that opens its own
            // sheet (Pause job asks why) never collides with this one.
            .sheet(isPresented: $model.isPresented, onDismiss: { model.finish() }) {
                JobStatusMenuPanel(groups: groups.filter { !$0.isEmpty }, title: title, subtitle: subtitle,
                                   footnote: footnote, doneSteps: doneSteps, regularWidth: regularWidth,
                                   onSelect: { model.choose($0) }, onClose: { model.isPresented = false })
            }
            .task {
                guard opensOnAppear else { return }
                try? await Task.sleep(for: .milliseconds(900))
                present()
            }
    }
}

/// A step the job has already passed (Paper 21T): its name and when it happened, behind a green
/// tick. It is a fact on the sheet, never a choice.
struct JobStatusDoneStep: Identifiable, Equatable {
    let id: String
    var title: String
    /// When the step happened, as the sheet shows it ("9:12 AM").
    var time: String? = nil
}

/// The sheet's content (Paper 21T "Change job status"): a Cancel pill and the title at 17 Semibold
/// on one line, a muted line under them, then each group as its own 20-radius card, 12 apart. The
/// first card is the job's steps: where it is now (the brand row, "Current") and each move forward,
/// 56pt rows led by a 28pt mark. Later cards hold the moves that stop or step back, 60pt rows split
/// by a hairline. It fits its rows, scrolls when they outgrow the screen, and opens full height in
/// a landscape phone and at accessibility sizes.
struct JobStatusMenuPanel: View {
    let groups: [[ThorbisMenuItem]]
    var title: String? = nil
    var subtitle: String? = nil
    var footnote: String? = nil
    /// Steps already passed, drawn at the top of the first card (see `JobStatusDoneStep`).
    var doneSteps: [JobStatusDoneStep] = []
    /// iPad: Paper's centred card, sized to its rows, with no grabber.
    var regularWidth = false
    let onSelect: (ThorbisMenuItem) -> Void
    var onClose: () -> Void = {}
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// A touch over the real height on purpose: a short estimate would make a sheet that fits scroll.
    private var estimatedHeight: CGFloat {
        var rows: CGFloat = 0
        for index in groups.indices {
            let group = groups[index]
            if index == 0 {
                rows += 16 + CGFloat(group.count + doneSteps.count) * 57
            } else {
                rows += group.reduce(CGFloat(0)) { $0 + ($1.subtitle == nil ? 61 : 67) }
            }
        }
        let gaps = CGFloat(max(groups.count - 1, 0)) * 12
        let header: CGFloat = 24 + 48 + (subtitle == nil ? 0 : 26) + 16
        let foot: CGFloat = (footnote == nil ? 0 : 48) + 46
        let total: CGFloat = header + rows + gaps + foot
        return total * typeSize.sheetHeightScale
    }

    private var detents: Set<PresentationDetent> {
        if verticalSizeClass == .compact || typeSize.isAccessibilitySize { return [.large] }
        return estimatedHeight <= 640 ? [.height(estimatedHeight)] : [.medium, .large]
    }

    private var regularHeight: CGFloat {
        let window = ThorbisMenuWindow.height
        let cap: CGFloat = window > 0 ? max(240, window - 120) : 640
        return min(max(estimatedHeight - 24, 160), cap)
    }

    var body: some View {
        if regularWidth {
            ScrollView { content }
                .scrollBounceBehavior(.basedOnSize)
                .frame(width: 520, height: regularHeight)
                .background(Theme.surface)
                .presentationSizing(.fitted)
                .presentationBackground(Theme.surface)
                .presentationCornerRadius(Theme.cardRadius + 8)
                .presentationDragIndicator(.hidden)
        } else {
            ScrollView { content }
                .scrollBounceBehavior(.basedOnSize)
                .background(Theme.surface)
                .presentationDetents(detents)
                .presentationBackground(Theme.surface)
                .presentationCornerRadius(Theme.cardRadius + 8)
                .presentationDragIndicator(.visible)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            VStack(spacing: 12) {
                ForEach(groups.indices, id: \.self) { index in
                    JobStatusMenuGroup(rows: groups[index], steps: index == 0,
                                       doneSteps: index == 0 ? doneSteps : [], onSelect: onSelect)
                }
            }
            .padding(.top, 16)
            if let footnote {
                Text(footnote).font(Theme.font(13)).foregroundStyle(Theme.subtle)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 12).padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, PaperCardMetrics.margin)
        .padding(.top, regularWidth ? 16 : 24).padding(.bottom, 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title ?? "Status")
        .accessibilityAction(.escape) { onClose() }
    }

    /// Paper 21T: Cancel on the left, the title centred on the same line, the job under them. Each
    /// move runs as it is tapped, so there is no Done to press (see the report with this change).
    private var header: some View {
        VStack(spacing: 6) {
            ZStack {
                if let title {
                    Text(title)
                        .font(Theme.font(17, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                        .multilineTextAlignment(.center)
                        .lineLimit(2).minimumScaleFactor(0.8)
                        .padding(.horizontal, 92)
                        .accessibilityAddTraits(.isHeader)
                }
                HStack(spacing: 0) {
                    Button(action: onClose) {
                        Text("Cancel")
                            .font(Theme.font(16, weight: .medium))
                            .foregroundStyle(Theme.foreground)
                            .lineLimit(1)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 44)
                            .background(Theme.fill, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityIdentifier("job-status-cancel")
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            if let subtitle {
                Text(subtitle)
                    .font(Theme.font(14))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
}

/// One card of the status sheet. `steps` is the first card (Paper 21T's step list): rows float
/// inside the card's padding and the current step wears the brand surface. The other cards are
/// plain rows split by a hairline, destructive ones in the danger tone.
private struct JobStatusMenuGroup: View {
    let rows: [ThorbisMenuItem]
    let steps: Bool
    var doneSteps: [JobStatusDoneStep] = []
    let onSelect: (ThorbisMenuItem) -> Void
    @ScaledMetric(relativeTo: .body) private var markColumn: CGFloat = 28

    /// Paper 21T: a step already passed. A green tick, its name and when it happened; not a button.
    private func doneRow(_ step: JobStatusDoneStep) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Theme.statusDone)
                .frame(width: markColumn)
                .accessibilityHidden(true)
            Text(step.title)
                .font(Theme.font(16))
                .foregroundStyle(Theme.subtle)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let time = step.time {
                Text(time).font(Theme.font(14)).monospacedDigit().foregroundStyle(Theme.subtle)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(step.time.map { "\(step.title), done at \($0)" } ?? "\(step.title), done")
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(doneSteps) { step in
                doneRow(step)
            }
            // Keyed by slot and occupant, as ThorbisMenuRows.group(_:) does: the items are rebuilt on
            // every render, an unchanged list keeps its rows, and a slot a refresh fills with another
            // status gets a new row, so a press already on it is dropped, never retargeted.
            ForEach(Array(rows.enumerated()), id: \.offset) { index, item in
                Button { onSelect(item) } label: { row(item, divided: !steps && index > 0) }
                    .buttonStyle(MenuRowPressStyle(radius: steps ? 14 : 0))
                    .disabled(item.isDisabled)
                    .opacity(item.isDisabled ? 0.4 : 1)
                    .id(ThorbisMenuRowKey(item))
            }
        }
        .padding(.vertical, steps ? 6 : 0)
        .padding(.horizontal, steps ? 8 : 0)
        .background(Theme.fill)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private func row(_ item: ThorbisMenuItem, divided: Bool) -> some View {
        let isDestructive = item.role == .destructive
        let isCurrent = steps && item.isSelected
        let weight: Font.Weight = isCurrent ? .semibold : (isDestructive ? .medium : .regular)
        let height: CGFloat = (isCurrent || !steps) ? 60 : 56
        return HStack(spacing: 14) {
            mark(item, isCurrent: isCurrent, isDestructive: isDestructive)
                .frame(width: markColumn)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title)
                    .font(Theme.font(16, weight: weight))
                    .foregroundStyle(isDestructive ? Theme.destructive : Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if isCurrent {
                    // The selected trait already says it to VoiceOver; the row keeps its plain name.
                    Text(currentCaption(item)).font(Theme.font(13)).foregroundStyle(Theme.brandText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityHidden(true)
                } else if let subtitle = item.subtitle {
                    Text(subtitle).font(Theme.font(14)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            // Paper 21T: the step's time, "Next" or what is owed, right-aligned.
            if let detail = item.detail {
                Text(detail).font(Theme.font(14)).foregroundStyle(isCurrent ? Theme.muted : Theme.subtle)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, steps ? 8 : 16).padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
        .background(isCurrent ? Theme.brandSurface : Color.clear,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .top) {
            if divided { Rectangle().fill(Theme.hairline).frame(height: 1).accessibilityHidden(true) }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(item.isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// Paper 21T: "Current", then what the caller knows about it ("Current · 0:42 on site").
    private func currentCaption(_ item: ThorbisMenuItem) -> String {
        if let subtitle = item.subtitle, !subtitle.isEmpty { return "Current · \(subtitle)" }
        return "Current"
    }

    /// Paper 21T: the current step is the brand dot; every move keeps the mark of where it leads.
    @ViewBuilder
    private func mark(_ item: ThorbisMenuItem, isCurrent: Bool, isDestructive: Bool) -> some View {
        if isCurrent {
            Circle().fill(Theme.brand).frame(width: 28, height: 28)
                .overlay { Circle().fill(Color.white).frame(width: 10, height: 10) }
                .accessibilityHidden(true)
        } else if let status = item.status {
            StatusGlyph(tone: status, label: item.title, size: 20)
                .accessibilityHidden(true)
        } else if let icon = item.icon {
            Image(systemName: icon).font(.system(size: 18, weight: .regular))
                .foregroundStyle(isDestructive ? Theme.destructive : (item.tint ?? Theme.foreground))
                .accessibilityHidden(true)
        } else {
            Color.clear.frame(height: 1).accessibilityHidden(true)
        }
    }
}

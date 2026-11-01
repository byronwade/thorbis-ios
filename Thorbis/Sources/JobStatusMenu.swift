import SwiftUI

/// The job's status popover (v2, design.thorbis.com "A popover is one choice"): it grows from the
/// status chip and lists where the job is now (checked), then every move the server allows, in
/// groups separated by space: forward moves first, then the moves that step back or stop the work
/// (Pause job…, Move back to scheduled). Destructive moves keep their danger tone in their own group.
///
/// Built from `ThorbisMenuRows` and `ThorbisMenuModel`, so rows, press, checks and the
/// run-after-close behaviour match `ThorbisMenu`; only the grouping is new.
struct JobStatusMenu<Label: View>: View {
    /// Each inner array is one group; empty groups are skipped.
    let groups: [[ThorbisMenuItem]]
    var title: String? = "Status"
    var accessibilityLabel: String? = nil
    /// Screenshot-only: open on appear (preview flags).
    var opensOnAppear = false
    @ViewBuilder var label: () -> Label

    @State private var model = ThorbisMenuModel()

    var body: some View {
        Button { ThorbisKeyboard.dismiss { model.isPresented = true } } label: { label() }
            .buttonStyle(PressStyle())
            .sensoryFeedback(.selection, trigger: model.isPresented) { _, open in open }
            .accessibilityLabel(accessibilityLabel ?? title ?? "Status")
            // Down from a chip in the top half of the window, up from one in the bottom half.
            .anchoredPopover(isPresented: $model.isPresented) {
                JobStatusMenuPanel(groups: groups.filter { !$0.isEmpty }, title: title,
                                   onSelect: { model.choose($0) }, onClose: { model.isPresented = false })
                    .onDisappear { model.finish() }
                    .presentationCompactAdaptation(.popover)
                    .presentationBackground(Theme.surface)
            }
            .task {
                guard opensOnAppear else { return }
                try? await Task.sleep(for: .milliseconds(900))
                model.isPresented = true
            }
    }
}

/// The grouped panel: a caption, then each group's rows with a small gap (space, never a line)
/// between groups. Scrolls only when it would outgrow the room it is given.
struct JobStatusMenuPanel: View {
    let groups: [[ThorbisMenuItem]]
    var title: String? = nil
    let onSelect: (ThorbisMenuItem) -> Void
    var onClose: () -> Void = {}
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    private var width: CGFloat {
        if typeSize.isAccessibilitySize { return 340 }
        return typeSize >= .xxLarge ? 300 : 264
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(groups.enumerated()), id: \.offset) { index, rows in
                if index > 0 { Color.clear.frame(height: 8).accessibilityHidden(true) }
                // Each group reuses the shared rows; only the first carries the caption.
                ThorbisMenuRows(items: rows, title: index == 0 ? title : nil, onSelect: onSelect)
                    .padding(.top, index == 0 ? 0 : -6)
            }
        }
    }

    var body: some View {
        // Whole when it fits the room the popover is given; otherwise the rows scroll from the top,
        // caption first (large text, many moves).
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }.scrollBounceBehavior(.basedOnSize)
        }
        .frame(width: width)
        // design.thorbis.com Motion: a menu fades in at 120ms ease-out; it does not fly.
        .opacity(shown || reduceMotion ? 1 : 0)
        .onAppear { withAnimation(.easeOut(duration: 0.12)) { shown = true } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title ?? "Status")
        .accessibilityAction(.escape) { onClose() }
    }
}

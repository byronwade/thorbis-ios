import SwiftUI
import UIKit

// Row swipe actions (owner-approved 31 Oct 2026): shortcuts on a list row, revealed by a horizontal
// drag. Our rows sit in a `ScrollView` (Today mixes the Now panel, the stop-card pager and pinned
// labels in one scroll; Jobs and Inbox are lazy stacks on the canvas), not a `List`, so the system
// `.swipeActions` is not available. Moving those screens to `List` would disturb all of that, so the
// row carries its own drag instead:
//
// - A UIKit pan (`RowSwipePan`) that only begins when the drag is clearly sideways, and never from
//   the screen's leading 24pt, which belongs to the drawer's edge swipe (roots) and Back (pushed).
//   The scroll view's own pan waits for it to decline, so vertical scrolling is untouched.
// - Thresholds: half an action's width opens it; past 55% of the row (or a fast fling) a full swipe
//   runs the one action marked for it. One row is open per screen; scrolling closes it, and a tap
//   on an open row closes it rather than opening the record.
// - The buttons are Thorbis buttons with the word showing, in our tokens: ink, the panel, or a
//   status's text on its own surface (all pairs held by scripts/tests/contrast.py).
// - Gestures are never the only path: each screen also offers these actions on the record itself,
//   and the row exposes them to VoiceOver as custom actions (`rowSwipeAccessibility`).

/// One button behind a row.
struct RowSwipeAction: Identifiable {
    enum Tone {
        /// The ink commit: type-colour fill, inverse type.
        case ink
        /// The panel: the quiet fill with the type colour.
        case panel
        /// A status move: the status's text-safe colour on its own surface, led by its mark.
        case status(StatusTone)
    }

    /// Also the button's accessibility identifier.
    let id: String
    let title: String
    let symbol: String
    var tone: Tone = .panel
    /// What VoiceOver and Voice Control call it ("Call Danielle Marlowe").
    var spokenName: String? = nil
    /// Sent and not yet answered: the word stays while its mark turns into a loader.
    var busy = false
    let run: () -> Void
}

/// Which row is open on a screen: opening one closes the other, and scrolling closes it.
@MainActor
final class RowSwipeState: ObservableObject {
    @Published var openID: String?
    #if DEBUG
    /// Screenshot-only (`--paper-preview-swipe leading|trailing`): the first row that can, opens.
    var previewOpened = false
    #endif

    func close() { if openID != nil { openID = nil } }
}

/// The swipe thresholds, kept apart from the view so they can be read and tested.
enum RowSwipeMotion {
    /// Past this share of the row (or flung past it), a trailing drag runs the full-swipe action.
    static let fullSwipeShare: CGFloat = 0.55
    /// A fling this fast settles the drag in its direction.
    static let flingSpeed: CGFloat = 600

    enum Settle: Equatable { case closed, leading, trailing, fullSwipe }

    /// Where a released drag settles. `offset` is the row's horizontal offset (positive: the leading
    /// actions show), `velocity` the fling in points per second.
    static func settle(offset: CGFloat, velocity: CGFloat, leadingWidth: CGFloat, trailingWidth: CGFloat,
                       rowWidth: CGFloat, fullSwipe: Bool) -> Settle {
        if offset < 0 {
            guard trailingWidth > 0 else { return .closed }
            if fullSwipe, -offset > rowWidth * fullSwipeShare || (-offset > trailingWidth && velocity < -flingSpeed * 2) {
                return .fullSwipe
            }
            if velocity > flingSpeed { return .closed }
            return -offset > trailingWidth / 2 || velocity < -flingSpeed ? .trailing : .closed
        }
        if offset > 0 {
            guard leadingWidth > 0 else { return .closed }
            if velocity < -flingSpeed { return .closed }
            return offset > leadingWidth / 2 || velocity > flingSpeed ? .leading : .closed
        }
        return .closed
    }
}

/// A row with swipe actions behind it. `content` is the row as it is today (its link, its press).
struct RowSwipeContainer<Content: View>: View {
    /// The row's identity on the screen (one open at a time).
    let id: String
    var leading: [RowSwipeAction] = []
    var trailing: [RowSwipeAction] = []
    /// The trailing action a full swipe runs; nil when none may run without a second look.
    var fullSwipeID: String? = nil
    /// Still reading what the row offers on that side: the drag shows "Checking" there.
    var checkingLeading = false
    var checkingTrailing = false
    /// The drag started: read what the row offers, if it isn't known yet.
    var onReveal: () -> Void = {}
    @ObservedObject var state: RowSwipeState
    @ViewBuilder var content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var dragging = false
    @State private var armed = false
    @State private var rowWidth: CGFloat = 390
    #if DEBUG
    /// Screenshot-only: the side the preview opens, applied with this render's actions.
    @State private var previewSide: HorizontalEdge?
    #endif
    @ScaledMetric(relativeTo: .footnote) private var scaledCell: CGFloat = 84
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    /// A cell grows with the type, but two never cover more than about three quarters of the row.
    private var cellWidth: CGFloat { min(scaledCell, max(84, rowWidth * 0.38)) }
    private var leadingCells: Int { leading.isEmpty ? (checkingLeading ? 1 : 0) : leading.count }
    private var trailingCells: Int { trailing.isEmpty ? (checkingTrailing ? 1 : 0) : trailing.count }
    private var leadingWidth: CGFloat { CGFloat(leadingCells) * cellWidth }
    private var trailingWidth: CGFloat { CGFloat(trailingCells) * cellWidth }
    private var fullSwipe: RowSwipeAction? { fullSwipeID.flatMap { id in trailing.first { $0.id == id } } }
    private var motion: Animation? { reduceMotion ? nil : .easeOut(duration: 0.18) }

    var body: some View {
        content()
            .background(Theme.background)
            .overlay {
                // An open row closes on a tap instead of opening the record under it.
                if offset != 0 && !dragging {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { close() }
                        .accessibilityHidden(true)
                }
            }
            .offset(x: offset)
            .background(alignment: .leading) { if offset > 0 { side(leading, checking: checkingLeading, edge: .leading) } }
            .background(alignment: .trailing) { if offset < 0 { side(trailing, checking: checkingTrailing, edge: .trailing) } }
            .clipped()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
            .gesture(RowSwipePan(began: began, changed: changed, ended: ended))
            .onChange(of: state.openID) { _, open in
                if open != id, offset != 0, !dragging { withAnimation(motion) { offset = 0 } }
            }
            // The side settles to what it now offers once the read lands (or closes if nothing).
            .onChange(of: trailing.map(\.id)) { _, _ in resettle() }
            .onChange(of: leading.map(\.id)) { _, _ in resettle() }
            .onChange(of: checkingTrailing) { _, _ in resettle() }
            .onChange(of: checkingLeading) { _, _ in resettle() }
            // A full swipe holds the row open on its turning cell until the answer lands.
            .onChange(of: trailing.contains(where: \.busy)) { was, now in if was && !now { close() } }
            #if DEBUG
            .task { await previewOpen() }
            .onChange(of: previewSide) { _, side in
                guard let side, !state.previewOpened, side == .leading ? !leading.isEmpty : !trailing.isEmpty else { return }
                // `--paper-preview-swipe-row <suffix>`: only the row whose id ends with it.
                let args = ProcessInfo.processInfo.arguments
                if let at = args.firstIndex(of: "--paper-preview-swipe-row"), args.indices.contains(at + 1),
                   !id.hasSuffix(args[at + 1]) { return }
                state.previewOpened = true
                state.openID = id
                offset = side == .leading ? leadingWidth : -trailingWidth
            }
            #endif
    }

    /// The cells on one side. Each keeps a fixed width; a lone full-swipe cell stretches to the drag.
    @ViewBuilder private func side(_ actions: [RowSwipeAction], checking: Bool, edge: HorizontalEdge) -> some View {
        let revealed = abs(offset)
        HStack(spacing: 0) {
            if actions.isEmpty && checking {
                RowSwipeChecking().frame(width: max(cellWidth, revealed))
            } else {
                ForEach(actions) { action in
                    let stretches = actions.count == 1 || (edge == .trailing && action.id == fullSwipeID && action.id == actions.last?.id)
                    let width = stretches ? max(cellWidth, revealed - CGFloat(actions.count - 1) * cellWidth) : cellWidth
                    RowSwipeButton(action: action, armed: armed && action.id == fullSwipeID) {
                        guard !action.busy else { return }
                        // A move holds the row open while it is sent; anything else closes it.
                        if !(edge == .trailing && action.id == fullSwipeID) { close() }
                        action.run()
                    }
                    .frame(width: width)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func began() {
        dragging = true
        if state.openID != id { state.openID = id }
        onReveal()
    }

    private func changed(_ translation: CGFloat) {
        let base: CGFloat = state.openID == id ? settledOffset : 0
        var next = base + (layoutDirection == .rightToLeft ? -translation : translation)
        // A side with nothing (and nothing being read) doesn't move.
        if next > 0 && leadingCells == 0 { next = 0 }
        if next < 0 && trailingCells == 0 { next = 0 }
        // Past the cells the drag resists, unless a full swipe can run.
        if next > leadingWidth { next = leadingWidth + rubber(next - leadingWidth) }
        if next < -trailingWidth && fullSwipe == nil { next = -trailingWidth - rubber(-next - trailingWidth) }
        offset = min(next, rowWidth)
        offset = max(offset, -rowWidth)
        let nowArmed = fullSwipe != nil && -offset > rowWidth * RowSwipeMotion.fullSwipeShare
        if nowArmed != armed {
            armed = nowArmed
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        }
    }

    private func ended(_ translation: CGFloat, _ velocity: CGFloat) {
        dragging = false
        let signed = layoutDirection == .rightToLeft ? -velocity : velocity
        let result = RowSwipeMotion.settle(offset: offset, velocity: signed, leadingWidth: leadingWidth,
                                           trailingWidth: trailingWidth, rowWidth: rowWidth, fullSwipe: fullSwipe != nil)
        armed = false
        switch result {
        case .fullSwipe:
            guard let action = fullSwipe else { close(); return }
            // The cell settles back to its own width and turns while the move is sent; the row
            // closes when the answer lands (`busy` ends).
            action.run()
            withAnimation(motion) { offset = -trailingWidth }
        case .leading: withAnimation(motion) { offset = leadingWidth }
        case .trailing: withAnimation(motion) { offset = -trailingWidth }
        case .closed: close()
        }
    }

    private var settledOffset: CGFloat { offset > 0 ? leadingWidth : offset < 0 ? -trailingWidth : 0 }

    private func resettle() {
        guard !dragging, offset != 0 else { return }
        let target = offset > 0 ? leadingWidth : -trailingWidth
        if target == 0 { close() } else { withAnimation(motion) { offset = target } }
    }

    private func close() {
        withAnimation(motion) { offset = 0 }
        if state.openID == id { state.openID = nil }
    }

    private func rubber(_ distance: CGFloat) -> CGFloat { distance * 0.25 }

    #if DEBUG
    /// `--paper-preview-swipe leading|trailing`: the first row with that side reads what it offers,
    /// then opens, so a screenshot shows the revealed actions without a gesture.
    private func previewOpen() async {
        guard PaperPreview.enabled, !state.previewOpened,
              let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--paper-preview-swipe"),
              ProcessInfo.processInfo.arguments.indices.contains(index + 1) else { return }
        let wantsLeading = ProcessInfo.processInfo.arguments[index + 1] == "leading"
        try? await Task.sleep(for: .seconds(2))
        guard !state.previewOpened else { return }
        onReveal()
        try? await Task.sleep(for: .seconds(1.5))
        // The first row that now offers that side opens (the check runs on the fresh render).
        previewSide = wantsLeading ? .leading : .trailing
    }
    #endif
}

/// One action cell: the mark over the word, both always showing.
private struct RowSwipeButton: View {
    let action: RowSwipeAction
    var armed = false
    let tap: () -> Void

    private var fill: Color {
        switch action.tone {
        case .ink: Theme.ink
        case .panel: Theme.fill
        case .status(let tone): tone.surface
        }
    }

    private var word: Color {
        switch action.tone {
        case .ink: Theme.onInk
        case .panel: Theme.foreground
        case .status(let tone): tone.text
        }
    }

    var body: some View {
        Button(action: tap) {
            VStack(spacing: 4) {
                if action.busy {
                    ProgressView().controlSize(.small).tint(word)
                } else if case .status(let tone) = action.tone {
                    StatusMark(tone: tone)
                } else {
                    Image(systemName: action.symbol).font(.system(size: 17, weight: .medium)).accessibilityHidden(true)
                }
                Text(action.title)
                    .font(Theme.font(13, weight: .medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(word)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: armed ? .leading : .center)
            .padding(.leading, armed ? 16 : 0)
            .background(fill)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(action.spokenName ?? action.title)
        .accessibilityValue(action.busy ? "Sending" : "")
        .accessibilityIdentifier(action.id)
    }
}

/// The side's cell while the row reads what it offers: the loader turns beside the word.
private struct RowSwipeChecking: View {
    var body: some View {
        VStack(spacing: 6) {
            ProgressView().tint(Theme.muted)
            Text("Checking").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.fill)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Checking what this job offers")
        .accessibilityIdentifier("row-swipe-checking")
    }
}

extension View {
    /// The row's swipe actions as VoiceOver custom actions (and Voice Control names), on the row's
    /// own accessibility element, so the gesture is never the only way to reach them.
    func rowSwipeAccessibility(_ actions: [RowSwipeAction]) -> some View {
        modifier(RowSwipeAccessibility(actions: actions))
    }
}

/// One `accessibilityAction(named:)` per action, on the element itself. (The builder form,
/// `accessibilityActions { ForEach }`, wraps an element that ignores its children in a new one.)
private struct RowSwipeAccessibility: ViewModifier {
    let actions: [RowSwipeAction]

    func body(content: Content) -> some View {
        switch actions.count {
        case 0: content
        case 1: content.accessibilityAction(named: name(0), actions[0].run)
        case 2: content.accessibilityAction(named: name(0), actions[0].run).accessibilityAction(named: name(1), actions[1].run)
        default:
            content.accessibilityAction(named: name(0), actions[0].run).accessibilityAction(named: name(1), actions[1].run)
                .accessibilityAction(named: name(2), actions[2].run)
        }
    }

    private func name(_ index: Int) -> Text { Text(actions[index].spokenName ?? actions[index].title) }
}

/// A sideways pan that leaves vertical scrolling and the screen's leading edge alone.
struct RowSwipePan: UIGestureRecognizerRepresentable {
    let began: () -> Void
    let changed: (CGFloat) -> Void
    let ended: (CGFloat, CGFloat) -> Void

    /// The leading strip the drawer's edge swipe and the system Back own.
    static let edgeZone: CGFloat = 24

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        pan.maximumNumberOfTouches = 1
        return pan
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let translation = recognizer.translation(in: recognizer.view).x
        switch recognizer.state {
        case .began: began(); changed(translation)
        case .changed: changed(translation)
        case .ended, .cancelled, .failed: ended(translation, recognizer.velocity(in: recognizer.view).x)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer, let window = pan.view?.window else { return false }
            let velocity = pan.velocity(in: pan.view)
            let start = pan.location(in: window).x - pan.translation(in: window).x
            let edge = window.effectiveUserInterfaceLayoutDirection == .rightToLeft
                ? start > window.bounds.width - RowSwipePan.edgeZone : start < RowSwipePan.edgeZone
            guard !edge else { return false }
            return abs(velocity.x) > abs(velocity.y) * 1.4
        }

        /// The scroll view's pan waits for this one to decline, so a sideways drag never scrolls and
        /// an up-and-down one scrolls as it always did.
        func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            other.view is UIScrollView && other is UIPanGestureRecognizer
        }
    }
}

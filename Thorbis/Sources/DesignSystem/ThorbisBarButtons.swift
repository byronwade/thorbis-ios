import SwiftUI
import UIKit

// Thorbis buttons for the navigation bar (user direction, 30 October 2026): pushed screens and
// sheets use our own controls rather than the system's default bar buttons. The bar itself,
// swipe-back, sheets and their dismissal stay native (golden rules 6 and 11).
//
// - `ThorbisBackButton` — the round chevron that replaces the system back button.
// - `.thorbisBackButton()` — hides the system back button and puts ours on the leading side.
// - `ThorbisToolbarItem` — a bar item whose Buttons wear `ThorbisBarButtonStyle` and, on iOS 26,
//   drop the shared Liquid Glass capsule so the Thorbis control is the only surface.
// - `ThorbisBarButtonStyle` — the text pill for Done / Cancel / Save / Close.

// MARK: - Back

/// The round back control for a pushed screen: `chevron.left` in a bordered card circle,
/// 44pt hit area, labelled "Back" so VoiceOver, Voice Control and UI tests find it as before.
struct ThorbisBackButton: View {
    @Environment(\.dismiss) private var dismiss
    var action: (() -> Void)? = nil

    var body: some View {
        PaperCircleButton(symbol: "chevron.left", label: "Back", fill: Theme.card, bordered: true) {
            if let action { action() } else { dismiss() }
        }
    }
}

private struct ThorbisBackButtonModifier: ViewModifier {
    let isEnabled: Bool

    /// Pushed screens keep Back alone (C-Job.dc.html): the drawer lives on the place's root, one
    /// Back or edge swipe away, so the bar never stacks two circles at its leading edge.
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .navigationBarBackButtonHidden(true)
                .toolbar {
                    ThorbisToolbarItem(placement: .topBarLeading) { ThorbisBackButton() }
                }
        } else {
            content
        }
    }
}

extension View {
    /// Swap the system back button for the Thorbis one. Apply to a pushed destination, never to
    /// a stack's root. Swipe-back keeps working (see `UINavigationController` below).
    func thorbisBackButton(_ isEnabled: Bool = true) -> some View {
        modifier(ThorbisBackButtonModifier(isEnabled: isEnabled))
    }
}

extension View {
    /// `navigationDestination` whose pushed screen wears the Thorbis back button.
    func thorbisDestination<D: Hashable, C: View>(for data: D.Type, @ViewBuilder destination: @escaping (D) -> C) -> some View {
        navigationDestination(for: data) { destination($0).thorbisBackButton() }
    }

    func thorbisDestination<C: View>(isPresented: Binding<Bool>, @ViewBuilder destination: () -> C) -> some View {
        navigationDestination(isPresented: isPresented) { destination().thorbisBackButton() }
    }

    func thorbisDestination<D: Hashable, C: View>(item: Binding<D?>, @ViewBuilder destination: @escaping (D) -> C) -> some View {
        navigationDestination(item: item) { destination($0).thorbisBackButton() }
    }
}

/// Hiding the system back button switches off UIKit's edge-swipe pop. Re-enable it on every
/// navigation controller: the gesture begins whenever there is a screen to go back to.
///
/// UIKit's swipe only listens at the screen's edge. A stack that starts further in — the iPad's
/// detail column beside its list, a readable-width column, a form sheet — gets its own pan from
/// its own leading edge (`columnBackSwipe`), so a swipe from where the screen visibly starts goes
/// back there too. A stack at the screen's edge (every phone screen) keeps UIKit's alone.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    private static let columnBackSwipeName = "thorbis.columnBackSwipe"
    /// How far in from the stack's leading edge the swipe may start.
    private static let columnEdgeWidth: CGFloat = 22

    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
        let pan = UIPanGestureRecognizer(target: self, action: #selector(thorbisColumnBackSwipe(_:)))
        pan.name = Self.columnBackSwipeName
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        view.addGestureRecognizer(pan)
    }

    private func isColumnBackSwipe(_ recognizer: UIGestureRecognizer) -> Bool {
        recognizer.name == Self.columnBackSwipeName && recognizer.view === view
    }

    private var leadsRightToLeft: Bool { view.effectiveUserInterfaceLayoutDirection == .rightToLeft }

    /// Whether the stack starts in from the window's edge, where UIKit's own swipe cannot reach.
    private var startsInFromScreenEdge: Bool {
        guard let window = view.window else { return false }
        let frame = view.convert(view.bounds, to: window)
        return leadsRightToLeft ? frame.maxX < window.bounds.maxX - 1 : frame.minX > 1
    }

    private var canGoBack: Bool { viewControllers.count > 1 && transitionCoordinator == nil }

    @objc private func thorbisColumnBackSwipe(_ pan: UIPanGestureRecognizer) {
        guard pan.state == .ended else { return }
        let sign: CGFloat = leadsRightToLeft ? -1 : 1
        let distance = pan.translation(in: view).x * sign
        let speed = pan.velocity(in: view).x * sign
        guard distance > 60 || (distance > 20 && speed > 500), canGoBack else { return }
        popViewController(animated: true)
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard isColumnBackSwipe(gestureRecognizer) else { return true }
        // Only touches in the stack's own leading edge, and only where UIKit's swipe cannot help.
        guard canGoBack, startsInFromScreenEdge else { return false }
        let x = touch.location(in: view).x
        return leadsRightToLeft ? x > view.bounds.width - Self.columnEdgeWidth : x < Self.columnEdgeWidth
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if isColumnBackSwipe(gestureRecognizer), let pan = gestureRecognizer as? UIPanGestureRecognizer {
            let velocity = pan.velocity(in: view)
            let inward = leadsRightToLeft ? -velocity.x : velocity.x
            return canGoBack && inward > 0 && abs(velocity.x) > abs(velocity.y)
        }
        guard gestureRecognizer === interactivePopGestureRecognizer else { return true }
        return viewControllers.count > 1 && transitionCoordinator == nil
    }

    // Let the pop and a scroll view's own pan coexist, as the system back button allows.
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                  shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        gestureRecognizer === interactivePopGestureRecognizer
    }

    // A swipe that starts in the column's edge is the back swipe first: the content's own pans
    // (a row's swipe actions, a horizontal scroller) wait for it to fail, as at the screen's edge.
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                  shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        isColumnBackSwipe(gestureRecognizer) && other.view?.isDescendant(of: view) == true
    }
}

// MARK: - Bar items

/// A toolbar item that carries Thorbis controls. Plain `Button`s inside take the pill style
/// (`prominent` for the one confirming action); `ThorbisMenu`/`PaperCircleButton` keep their own.
struct ThorbisToolbarItem<Content: View>: ToolbarContent {
    let placement: ToolbarItemPlacement
    var prominent = false
    /// CustomerPresentation's stronger floor (rule 13): 17pt text, 56pt target.
    var customerFacing = false
    @ViewBuilder let content: () -> Content

    var body: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: placement) { styled }.sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: placement) { styled }
        }
    }

    private var styled: some View {
        content().buttonStyle(ThorbisBarButtonStyle(prominent: prominent, customerFacing: customerFacing))
            .fixedSize()
    }
}

/// The keyboard's Done bar: one Thorbis pill at the trailing edge above the keyboard, in place of
/// a stock `ToolbarItemGroup(placement: .keyboard)` button.
struct ThorbisKeyboardDoneBar: ToolbarContent {
    let action: () -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done", action: action)
                .buttonStyle(ThorbisBarButtonStyle(prominent: true))
        }
    }
}

/// The bar's text pill: Inter medium on a bordered card capsule, or ink for the confirming
/// action. 36pt visible, 44pt to the finger, presses like every Thorbis button (MA-07).
struct ThorbisBarButtonStyle: ButtonStyle {
    var prominent = false
    var customerFacing = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font((customerFacing ? Theme.customerFont(17, weight: .medium) : Theme.font(15, weight: .medium)))
            .lineLimit(1)
            // iOS 26 bars propose a circle-sized width to items; keep the whole word ("Cancel", not "C").
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(prominent ? Theme.onInk : Theme.foreground)
            .padding(.horizontal, 14)
            .frame(minWidth: customerFacing ? 48 : 36, minHeight: customerFacing ? 48 : 36)
            .background(prominent ? Theme.ink : Theme.card, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.border, lineWidth: prominent ? 0 : 1))
            .opacity(isEnabled ? 1 : 0.4)
            .frame(minHeight: customerFacing ? 56 : 44)
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

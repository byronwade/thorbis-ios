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

/// A compact back chevron for the phone's pushed screens, where the menu circle leads the bar:
/// the chevron alone (no circle) so the pair reads as one control group, 44pt to the finger.
struct ThorbisCompactBackButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button { dismiss() } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.foreground)
                .frame(width: 36, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Back")
    }
}

private struct ThorbisBackButtonModifier: ViewModifier {
    let isEnabled: Bool
    /// The phone drawer, offered on every screen of a place (nil on iPad and in sheets' own stacks).
    @Environment(\.paperDrawerReach) private var drawer
    /// Inside a sheet or full-screen cover the bar keeps Back alone.
    @State private var presented = false

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .navigationBarBackButtonHidden(true)
                .toolbar {
                    ThorbisToolbarItem(placement: .topBarLeading) { leading }
                }
                .background { if drawer != nil { PresentationProbe(presented: $presented).frame(width: 0, height: 0).accessibilityHidden(true) } }
        } else {
            content
        }
    }

    /// Phone place screens: the menu circle where it sits on every root, Back beside it. Elsewhere
    /// the round back circle alone.
    @ViewBuilder private var leading: some View {
        if let drawer, !presented {
            HStack(spacing: 2) {
                if Self.backFirst {
                    ThorbisCompactBackButton()
                    DrawerMenuCircle(control: drawer, size: 36)
                } else {
                    DrawerMenuCircle(control: drawer, size: 36)
                    ThorbisCompactBackButton()
                }
            }
        } else {
            ThorbisBackButton()
        }
    }

    /// Screenshot-only: the other arrangement, Back first, kept for the comparison shot.
    private static var backFirst: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--paper-preview-back-first")
        #else
        false
        #endif
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
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === interactivePopGestureRecognizer else { return true }
        return viewControllers.count > 1 && transitionCoordinator == nil
    }

    // Let the pop and a scroll view's own pan coexist, as the system back button allows.
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                  shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        gestureRecognizer === interactivePopGestureRecognizer
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

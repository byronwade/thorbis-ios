import SwiftUI
import UIKit

/// Pins a bottom bar above the keyboard using the keyboard's own reported frame.
///
/// SwiftUI's keyboard safe area can go stale inside a sheet: opened right after another keyboard
/// (a number pad on the page beneath) was dismissed, the sheet kept that earlier, shorter height and
/// the commit sat behind the taller search keyboard. This takes the keyboard out of the safe area
/// and lifts the bar by the frame UIKit reports, on every change.
///
/// The lift is how far the keyboard covers the view the bar is in, not the screen. On a phone the
/// two are the same: the sheet ends at the screen's bottom. An iPad form sheet ends higher, and the
/// system has already moved it clear of the keyboard, so there the bar stays at the sheet's foot
/// (BYR-1843: measured against the screen, it rose a second time into the middle of the sheet).
private struct KeyboardPinnedBar<Bar: View>: ViewModifier {
    @ViewBuilder var bar: Bar
    @State private var overlap: CGFloat = 0
    @State private var keyboard: CGRect = .zero
    /// The foot of this view now, in the window's coordinates (an iPad sheet's foot moves up with the keyboard).
    @State private var restingBottom: CGFloat?

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) { bar.padding(.bottom, overlap) }
            // Read inside `ignoresSafeArea`, where the keyboard does not shorten the view.
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: {
                restingBottom = $0
                apply(animated: false)
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { update($0, animated: true) }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidChangeFrameNotification)) { update($0, animated: false) }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboard = .zero
                withAnimation(.easeOut(duration: 0.25)) { overlap = 0 }
            }
    }

    private func update(_ note: Notification, animated: Bool) {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        keyboard = frame
        apply(animated: animated)
    }

    /// Recomputes the lift from the last keyboard frame and the view's foot. The view moves too:
    /// an iPad sheet slides up as the keyboard arrives, after the keyboard's own notification.
    private func apply(animated: Bool) {
        // A compact-width sheet ends at the screen's foot, so a phone keeps exactly the lift it
        // had; only a regular-width window's form sheet needs its own foot.
        let foot = ThorbisMenuWindow.isRegularWidth ? restingBottom : nil
        let next = KeyboardPinnedBarMetrics.overlap(keyboard: keyboard, screen: KeyboardPinnedBarMetrics.screen,
                                                    restingBottom: foot)
        guard abs(next - overlap) > 0.5 else { return }
        if animated { withAnimation(.easeOut(duration: 0.25)) { overlap = next } } else { overlap = next }
    }
}

enum KeyboardPinnedBarMetrics {
    @MainActor static var screen: (height: CGFloat, bottomInset: CGFloat) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first
        return (window?.bounds.height ?? 0, window?.safeAreaInsets.bottom ?? 0)
    }

    /// How far a bar must rise to clear the keyboard. The bar rests at `restingBottom`, the foot of
    /// the view it is in (window coordinates), and never lower than the screen's bottom safe area,
    /// which is also where it rests when the view's foot is not known. A keyboard that is off
    /// screen, undocked above the bottom edge, of no height, or wholly below the view asks for nothing.
    static func overlap(keyboard: CGRect, screen: (height: CGFloat, bottomInset: CGFloat),
                        restingBottom: CGFloat? = nil) -> CGFloat {
        guard screen.height > 0, keyboard.height > 0, keyboard.maxY >= screen.height - 1 else { return 0 }
        let screenFoot = screen.height - screen.bottomInset
        let foot = restingBottom.map { min($0, screenFoot) } ?? screenFoot
        return max(0, foot - keyboard.minY)
    }
}

extension View {
    /// A bottom bar that always clears the keyboard; see `KeyboardPinnedBar`.
    func keyboardPinnedBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        modifier(KeyboardPinnedBar(bar: bar))
    }
}

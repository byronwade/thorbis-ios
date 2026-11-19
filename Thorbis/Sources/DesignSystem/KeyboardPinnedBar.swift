import SwiftUI
import UIKit

/// Pins a bottom bar above the keyboard using the keyboard's own reported frame.
///
/// SwiftUI's keyboard safe area can go stale inside a sheet: opened right after another keyboard
/// (a number pad on the page beneath) was dismissed, the sheet kept that earlier, shorter height and
/// the commit sat behind the taller search keyboard. This takes the keyboard out of the safe area
/// and lifts the bar by the frame UIKit reports, on every change.
private struct KeyboardPinnedBar<Bar: View>: ViewModifier {
    @ViewBuilder var bar: Bar
    @State private var overlap: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) { bar.padding(.bottom, overlap) }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { update($0, animated: true) }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidChangeFrameNotification)) { update($0, animated: false) }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                withAnimation(.easeOut(duration: 0.25)) { overlap = 0 }
            }
    }

    private func update(_ note: Notification, animated: Bool) {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let next = KeyboardPinnedBarMetrics.overlap(keyboard: frame, screen: KeyboardPinnedBarMetrics.screen)
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

    /// How far a bar resting on the bottom safe area must rise to clear the keyboard. A keyboard
    /// that is off screen, undocked above the bottom edge, or of no height asks for nothing.
    static func overlap(keyboard: CGRect, screen: (height: CGFloat, bottomInset: CGFloat)) -> CGFloat {
        guard screen.height > 0, keyboard.height > 0, keyboard.maxY >= screen.height - 1 else { return 0 }
        return max(0, screen.height - keyboard.minY - screen.bottomInset)
    }
}

extension View {
    /// A bottom bar that always clears the keyboard; see `KeyboardPinnedBar`.
    func keyboardPinnedBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        modifier(KeyboardPinnedBar(bar: bar))
    }
}

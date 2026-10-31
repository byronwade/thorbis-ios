import SwiftUI

/// Linear's toast (phase 4): a dark capsule with a glyph, a few words and at most one action
/// ("Undo"). It confirms something the screen already shows changed; it never carries an error
/// (errors stay in an `ErrorBanner` where the problem is) and never stands alone as proof that a
/// consequential operation succeeded (golden rule 14). VoiceOver hears the words when it appears.
struct ThorbisToast: View {
    let symbol: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.toastText)
                .accessibilityHidden(true)
            Text(message)
                .font(Theme.font(15, weight: .medium))
                .foregroundStyle(Theme.toastText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil, alignment: .leading)
            if let actionTitle, let action {
                Spacer(minLength: 4)
                Button(action: action) {
                    Text(actionTitle)
                        .font(Theme.font(15, weight: .medium))
                        .foregroundStyle(Theme.toastText)
                        .padding(.horizontal, 12).frame(minHeight: 30)
                        .background(Theme.toastText.opacity(0.14), in: Capsule())
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(.leading, 16).padding(.trailing, action == nil ? 18 : 6)
        .frame(minHeight: 48)
        .background(Theme.toastFill, in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        .accessibilityElement(children: .combine)
        .onAppear { AccessibilityNotification.Announcement(message).post() }
    }

    /// Rises from the bottom; only fades under Reduce Motion.
    static func transition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }
}

#if DEBUG
#Preview("ThorbisToast") {
    VStack(spacing: 12) {
        ThorbisToast(symbol: "trash", message: "Line removed", actionTitle: "Undo") {}
        ThorbisToast(symbol: "checkmark.circle.fill", message: "Saved")
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.canvas)
}
#endif

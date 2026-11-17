import SwiftUI

/// The toast (Paper 74 "Status update sent"): a 52pt card pill with a hairline rim and a soft
/// shadow, a 22pt mark (a green tick for a confirmation), the words in 15 Semibold and at most one
/// action in brand-text ("View", "Undo"). It confirms something the screen already shows changed;
/// it never carries an error (errors stay in an `ErrorBanner` where the problem is) and never
/// stands alone as proof that a consequential operation succeeded (golden rule 14). VoiceOver
/// hears the words when it appears.
struct ThorbisToast: View {
    let symbol: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(symbol.hasPrefix("checkmark") ? Theme.statusDone : Theme.foreground)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            Text(message)
                .font(Theme.font(15, weight: .semibold))
                .foregroundStyle(Theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil, alignment: .leading)
            if let actionTitle, let action {
                Spacer(minLength: 4)
                Button(action: action) {
                    Text(actionTitle)
                        .font(Theme.font(15, weight: .semibold))
                        .foregroundStyle(Theme.brandText)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(.leading, 14).padding(.trailing, 18)
        .frame(minHeight: 52)
        .background(Theme.card, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
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

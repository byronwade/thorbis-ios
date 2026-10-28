import SwiftUI

/// MA-15 inside a grouped List: the words stay body colour and only the mark is tinted.
struct ListErrorRow: View {
    let message: String

    var body: some View {
        Label {
            Text(message).foregroundStyle(Theme.foreground)
        } icon: {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.destructive)
        }
        .font(Theme.font(15))
    }
}

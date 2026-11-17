import SwiftUI

/// Paper 73C inside a card or grouped list: the load problem in a row. The words stay body
/// colour (16pt) and only the mark carries the warning tone.
struct ListErrorRow: View {
    let message: String

    var body: some View {
        Label {
            Text(message).foregroundStyle(Theme.foreground)
        } icon: {
            Image(systemName: "exclamationmark.circle").foregroundStyle(Theme.warning)
        }
        .font(Theme.font(16))
        .frame(minHeight: 44, alignment: .leading)
    }
}

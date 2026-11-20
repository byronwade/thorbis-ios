import SwiftUI

/// Paper 73C inside a card or grouped list: the load problem in a row. The words stay body
/// colour (16pt) and only the mark carries the warning tone.
struct ListErrorRow: View {
    let message: String

    var body: some View {
        // The shared banner strip (Paper 73), so a failed row reads like every other problem.
        PaperBannerStrip(symbol: "exclamationmark.triangle", tone: .warning, text: message) { EmptyView() }
            .accessibilityElement(children: .combine)
    }
}

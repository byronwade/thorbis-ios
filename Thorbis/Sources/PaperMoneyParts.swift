import SwiftUI

extension View {
    /// A sheet that Paper draws as a full page (35 Create estimate, 36 Sign estimate, 39 Collect
    /// payment, 40 Edit invoice): the page's ground (#141414) with cards on top, instead of the
    /// sheet panel, where a card is the same tone as the ground and disappears.
    func paperPageGround() -> some View {
        environment(\.thorbisSheetCanvas, false)
            .presentationBackground(Theme.background)
    }
}

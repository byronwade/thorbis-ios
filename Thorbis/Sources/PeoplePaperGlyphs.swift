import SwiftUI

// Paper's own glyphs for the customer, message, record and search screens (Paper 47–51, 76–77,
// 85–88), copied from each artboard's SVG.
extension PaperGlyph {
    /// A row's chevron (Paper 48N, 86A, 87): 14pt, stroke 1.6, in `subtle-foreground`.
    static let rowChevron14 = PaperGlyph(box: 14, [.stroke("M5 3l4 4-4 4", 1.6)])
    /// The handset on Paper 48N's Call circle and 49N's missed-call line.
    static let handset = PaperGlyph(box: 18, [.stroke("M5.5 2.5L7.5 6L6 7.5C6.8 9.3 8.7 11.2 10.5 12L12 10.5L15.5 12.5L14.5 15C14.2 15.6 13.6 16 12.9 15.9C7.5 15.3 2.7 10.5 2.1 5.1C2 4.4 2.4 3.8 3 3.5Z", 1.5)])
    /// Paper 47's Archive cell.
    static let archiveBox = PaperGlyph(box: 24, [.rect(3, 4, 18, 4, rx: 1, 1.8),
                                                 .stroke("M5 8v11a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1V8M10 12.5h4", 1.8)])
}

/// A row's trailing chevron as Paper draws it.
struct PaperRowChevron: View {
    var body: some View { PaperIcon(.rowChevron14, size: 14, color: Theme.subtleForeground) }
}

import SwiftUI

/// Paper's own glyphs for the job's sheets (26A New contact, 21F Checklist, 21G On my way, 21H
/// Book a follow-up, 83 Wrap up), copied from the artboards' SVG data.
extension PaperGlyph {
    /// 26A: the chosen role chip's tick.
    static let contactTick = PaperGlyph(box: 10, [.stroke("M2 5.2L4 7.2L8 3", 1.5)])
}

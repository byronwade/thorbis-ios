import SwiftUI

/// Paper's own glyphs for the job's sheets (26A New contact, 21F Checklist, 21G On my way, 21H
/// Book a follow-up, 83 Wrap up), copied from the artboards' SVG data.
extension PaperGlyph {
    /// 26A: the chosen role chip's tick.
    static let contactTick = PaperGlyph(box: 10, [.stroke("M2 5.2L4 7.2L8 3", 1.5)])
    // F3A Can't start: the reason tiles' 20pt glyphs and the photo tile's plus.
    static let cantStartHome = PaperGlyph(box: 20, [.stroke("M3.5 9L10 3.5L16.5 9V16.5H3.5Z", 1.6)])
    static let cantStartPart = PaperGlyph(box: 20, [.rect(3.5, 5.5, 13, 10, rx: 2, 1.6), .stroke("M7 5.5V4h6v1.5", 1.6)])
    static let cantStartUnsafe = PaperGlyph(box: 20, [.stroke("M10 3L17.5 16H2.5Z", 1.6), .stroke("M10 8v3.5", 1.6)])
    static let cantStartApproval = PaperGlyph(box: 20, [.circle(10, 10, 7, 1.6), .stroke("M10 6v4.5l2.5 1.5", 1.6)])
    static let cantStartPlus = PaperGlyph(box: 22, [.stroke("M11 5v12M5 11h12", 1.7)])
}

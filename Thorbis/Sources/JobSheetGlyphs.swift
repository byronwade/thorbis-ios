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

/// Paper 22 "Add to job": the rows' 22pt glyphs.
extension PaperGlyph {
    static let addEstimate = PaperGlyph(box: 22, [.stroke("M6 3H13L17 7V19H6V3Z", 1.5), .stroke("M13 3V7H17", 1.5)])
    static let addInvoice = PaperGlyph(box: 22, [.rect(3, 5.5, 16, 11, rx: 2, 1.5), .stroke("M3 9.5H19", 1.5)])
    static let addNote = PaperGlyph(box: 22, [.stroke("M14.5 4L18 7.5L8 17.5H4.5V14L14.5 4Z", 1.5), .stroke("M12 19H18", 1.5)])
    static let addContact = PaperGlyph(box: 24, [.circle(9, 7, 4, 1.6), .stroke("M2 21v-2a7 7 0 0 1 14 0v2M19 8v6M22 11h-6", 1.6)])
    static let addClose = PaperGlyph(box: 12, [.stroke("M3 3L9 9M9 3L3 9", 1.3)])
    static let addChevron = PaperGlyph(box: 16, [.stroke("M6 3.5L10.5 8 6 12.5", 1.6)])
}

/// Paper 26B "Contact": the quick-action tiles' glyphs.
extension PaperGlyph {
    static let contactCall = PaperGlyph(box: 16, [.stroke("M3 2.5C2.7 2.5 2.5 2.7 2.5 3C2.5 8.8 7.2 13.5 13 13.5C13.3 13.5 13.5 13.3 13.5 13V10.8C13.5 10.5 13.3 10.3 13 10.2L10.8 9.5C10.6 9.4 10.3 9.5 10.2 9.7L9.6 10.6C8 9.8 6.2 8 5.4 6.4L6.3 5.8C6.5 5.7 6.6 5.4 6.5 5.2L5.8 3C5.7 2.7 5.5 2.5 5.2 2.5H3Z", 1.3)])
    static let contactText = PaperGlyph(box: 16, [.stroke("M2.5 8C2.5 5 5 3 8 3C11 3 13.5 5 13.5 8C13.5 11 11 13 8 13C7.2 13 6.5 12.9 5.8 12.6L3 13.3L3.8 11C3 10.2 2.5 9.2 2.5 8Z", 1.3)])
    static let contactEmail = PaperGlyph(box: 20, [.rect(3, 5, 14, 10.5, rx: 2, 1.6), .stroke("M3.5 6l6.5 5 6.5-5", 1.6)])
}

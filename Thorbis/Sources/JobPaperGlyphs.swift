import SwiftUI

/// Paper's own glyphs for the job screens (21 Job details, 23/24 Money, 21A/21B Activity and
/// field mode F2 to F8), copied from the artboards' SVG data.
extension PaperGlyph {
    static let jobKey = PaperGlyph(box: 20, [.circle(6.5, 13.5, 3.5, 1.6), .stroke("M9 11L16.5 3.5M13.5 6.5L16 9M11.5 8.5L13.5 10.5", 1.6)])
    static let jobWarning = PaperGlyph(box: 20, [.stroke("M10 3L18 16.5H2L10 3Z", 1.6), .stroke("M10 8.5V11.5M10 14V14.1", 1.6)])
    static let jobChevronRight = PaperGlyph.chevronRight
    static let jobChevronRight18 = PaperGlyph(box: 18, [.stroke("M7 4.5L11.5 9L7 13.5", 1.6)])
    static let jobUpDown = PaperGlyph(box: 12, [.stroke("M3.5 4.5L6 2L8.5 4.5M3.5 7.5L6 10L8.5 7.5", 1.2)])
    static let jobPlus = PaperGlyph(box: 14, [.stroke("M7 2.5V11.5M2.5 7H11.5", 1.5)])
    static let jobTrash = PaperGlyph(box: 16, [.stroke("M3 4.5H13M6.5 4.5V3H9.5V4.5M4.5 4.5L5 13H11L11.5 4.5", 1.5)])
    static let jobStepPlus = PaperGlyph(box: 14, [.stroke("M7 3V11M3 7H11", 1.8)])
    static let jobDotsVertical = PaperGlyph(box: 16, [.circle(8, 3, 1.2), .circle(8, 8, 1.2), .circle(8, 13, 1.2)])
    static let jobShieldCheck = PaperGlyph(box: 15, [
        .stroke("M7.5 1.8L12.8 4.4V8.2C12.8 11 10.6 12.9 7.5 13.7C4.4 12.9 2.2 11 2.2 8.2V4.4L7.5 1.8Z", 1.4),
        .stroke("M5.4 7.7L7 9.3L9.8 6.3", 1.4)])
    static let jobCard = PaperGlyph(box: 16, [.rect(2, 3.5, 12, 9, rx: 1.8, 1.4), .stroke("M2 6.5H14", 1.4)])
    static let jobCamera = PaperGlyph(box: 22, [
        .stroke("M3 8.2C3 7.5 3.5 7 4.2 7H6.6L8 5H14L15.4 7H17.8C18.5 7 19 7.5 19 8.2V16.3C19 17 18.5 17.5 17.8 17.5H4.2C3.5 17.5 3 17 3 16.3V8.2Z", 1.5),
        .circle(11, 12, 3, 1.5)])
    static let jobSend = PaperGlyph(box: 16, [.stroke("M8 13V3M8 3L4 7M8 3L12 7", 1.8)])
    static let jobPhoto = PaperGlyph(box: 22, [.rect(3, 4, 16, 14, rx: 2, 1.8), .circle(8, 9, 1.6, 1.6),
                                               .stroke("M3 15L8 11L12 14L15 12L19 15", 1.8)])
    static let jobSignature = PaperGlyph(box: 28, [.stroke("M4 19c3-7 6-11 8-10s-2 9 0 10 4-5 6-5 1 4 3 4 2-1 3-2M4 24h20", 1.6)])
    // Paper 75 New job: the chips' 14pt glyphs.
    static let newJobPerson = PaperGlyph(box: 12, [.circle(6, 4, 2.2, 1.3), .stroke("M1.8 10.5C2.4 8.5 4 7.3 6 7.3C8 7.3 9.6 8.5 10.2 10.5", 1.3)])
    static let newJobClock = PaperGlyph(box: 12, [.circle(6, 6, 4.5, 1.3), .stroke("M6 3.6V6L7.6 7.2", 1.3)])
    static let newJobAssignee = PaperGlyph(box: 12, [.circle(6, 4, 2.2, 1.3), .stroke("M1.8 10.5C2.4 8.5 4 7.3 6 7.3C8 7.3 9.6 8.5 10.2 10.5", 1.3),
                                                     .stroke("M9.5 3.5H12M10.75 2.25V4.75", 1.1)])
    static let jobPaidCheck = PaperGlyph(box: 34, [.stroke("M8 17.5l6 6L26 10.5", 3)])
}

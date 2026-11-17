import SwiftUI

/// Paper's own glyphs for the job screens (21 Job details, 23/24 Money, 21A/21B Activity and
/// field mode F2 to F8), copied from the artboards' SVG data.
extension PaperGlyph {
    static let jobKey = PaperGlyph(box: 20, [.circle(6.5, 13.5, 3.5, 1.6), .stroke("M9 11L16.5 3.5M13.5 6.5L16 9M11.5 8.5L13.5 10.5", 1.6)])
    static let jobWarning = PaperGlyph(box: 20, [.stroke("M10 3L18 16.5H2L10 3Z", 1.6), .stroke("M10 8.5V11.5M10 14V14.1", 1.6)])
    static let jobChevronRight = PaperGlyph(box: 16, [.stroke("M6 3.5L10.5 8L6 12.5", 1.6)])
    static let jobChevronRight18 = PaperGlyph(box: 18, [.stroke("M7 4.5L11.5 9L7 13.5", 1.6)])
    static let jobUpDown = PaperGlyph(box: 12, [.stroke("M3.5 4.5L6 2L8.5 4.5M3.5 7.5L6 10L8.5 7.5", 1.2)])
    static let jobArrowOut = PaperGlyph(box: 12, [.stroke("M4 3H9V8M9 3L3 9", 1.2)])
    static let jobPlus = PaperGlyph(box: 14, [.stroke("M7 2.5V11.5M2.5 7H11.5", 1.5)])
    static let jobTrash = PaperGlyph(box: 16, [.stroke("M3 4.5H13M6.5 4.5V3H9.5V4.5M4.5 4.5L5 13H11L11.5 4.5", 1.5)])
    static let jobStepPlus = PaperGlyph(box: 14, [.stroke("M7 3V11M3 7H11", 1.8)])
    static let jobStepMinus = PaperGlyph(box: 14, [.stroke("M3 7H11", 1.8)])
    static let jobDotsVertical = PaperGlyph(box: 16, [.circle(8, 3, 1.2), .circle(8, 8, 1.2), .circle(8, 13, 1.2)])
    static let jobDots = PaperGlyph(box: 14, [.circle(3, 7, 1.1), .circle(7, 7, 1.1), .circle(11, 7, 1.1)])
    static let jobShieldCheck = PaperGlyph(box: 15, [
        .stroke("M7.5 1.8L12.8 4.4V8.2C12.8 11 10.6 12.9 7.5 13.7C4.4 12.9 2.2 11 2.2 8.2V4.4L7.5 1.8Z", 1.4),
        .stroke("M5.4 7.7L7 9.3L9.8 6.3", 1.4)])
    static let jobClock = PaperGlyph(box: 11, [.circle(5.5, 5.5, 4.2, 1.3), .stroke("M5.5 3.2V5.5L7 7", 1.3)])
    static let jobCard = PaperGlyph(box: 16, [.rect(2, 3.5, 12, 9, rx: 1.8, 1.4), .stroke("M2 6.5H14", 1.4)])
    static let jobCamera = PaperGlyph(box: 22, [
        .stroke("M3 8.2C3 7.5 3.5 7 4.2 7H6.6L8 5H14L15.4 7H17.8C18.5 7 19 7.5 19 8.2V16.3C19 17 18.5 17.5 17.8 17.5H4.2C3.5 17.5 3 17 3 16.3V8.2Z", 1.5),
        .circle(11, 12, 3, 1.5)])
    static let jobSend = PaperGlyph(box: 16, [.stroke("M8 13V3M8 3L4 7M8 3L12 7", 1.8)])
    static let jobArrowRight = PaperGlyph(box: 12, [.stroke("M6 1.5L10.5 6L6 10.5M10.5 6H1.5", 1.4)])
    static let jobPhoto = PaperGlyph(box: 22, [.rect(3, 4, 16, 14, rx: 2, 1.8), .circle(8, 9, 1.6, 1.6),
                                               .stroke("M3 15L8 11L12 14L15 12L19 15", 1.8)])
    static let jobPencil = PaperGlyph(box: 12, [.stroke("M8.5 1.5L10.5 3.5L4 10H2V8L8.5 1.5Z", 1.2)])
    static let jobDollar = PaperGlyph(box: 12, [.stroke("M6 1V11M8.5 3H4.75C3.9 3 3.25 3.65 3.25 4.5C3.25 5.35 3.9 6 4.75 6H7.25C8.1 6 8.75 6.65 8.75 7.5C8.75 8.35 8.1 9 7.25 9H3.25", 1.3)])
    static let jobScan = PaperGlyph(box: 20, [.stroke("M3.5 7V5C3.5 4.2 4.2 3.5 5 3.5H7M13 3.5H15C15.8 3.5 16.5 4.2 16.5 5V7M16.5 13V15C16.5 15.8 15.8 16.5 15 16.5H13M7 16.5H5C4.2 16.5 3.5 15.8 3.5 15V13M6.5 10H13.5", 1.6)])
    static let jobDocument = PaperGlyph(box: 14, [.stroke("M3.5 1.5H8.5L10.5 3.5V12.5H3.5V1.5Z", 1.2), .stroke("M8.5 1.5V3.5H10.5", 1.2)])
    static let jobDownload = PaperGlyph(box: 15, [.stroke("M7.5 2.5V9.5M7.5 9.5L4.5 6.5M7.5 9.5L10.5 6.5M3 12.5H12", 1.3)])
    static let jobCheck = PaperGlyph(box: 12, [.stroke("M3.85 6.15 5.3 7.6 8.15 4.5", 1.3)])
    static let jobSignature = PaperGlyph(box: 28, [.stroke("M4 19c3-7 6-11 8-10s-2 9 0 10 4-5 6-5 1 4 3 4 2-1 3-2M4 24h20", 1.6)])
}

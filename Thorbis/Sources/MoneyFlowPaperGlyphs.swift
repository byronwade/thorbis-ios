import SwiftUI

/// Paper's own marks for the estimate-to-paid flow (35 Create estimate, 39 Collect payment, 40 Edit
/// invoice), copied from the artboards' SVG data.
extension PaperGlyph {
    /// 35/40: the 20pt share tray in the header circle.
    static let shareTray = PaperGlyph(box: 20, [.stroke("M10 3V12M6.5 6L10 2.5L13.5 6M4.5 10.5V15.5C4.5 16.1 4.9 16.5 5.5 16.5H14.5C15.1 16.5 15.5 16.1 15.5 15.5V10.5", 1.7)])
    /// 35/40: three 1.6 dots in the header circle.
    static let moreLarge = PaperGlyph(box: 20, [.circle(4.5, 10, 1.6), .circle(10, 10, 1.6), .circle(15.5, 10, 1.6)])
    /// 35: Draft, a ring with its right half filled.
    static let statusHalf = PaperGlyph(box: 14, [.circle(7, 7, 6, 1.4), .fill("M7 3.2 A3.8 3.8 0 0 1 7 10.8 Z")])
    /// 35/40: the 14pt clock in a heading pill.
    static let clockPill = PaperGlyph(box: 14, [.circle(7, 7, 6, 1.4), .stroke("M7 3.8V7L9 8.5", 1.4)])
    /// 35: the quantity pill's trash.
    static let trash = PaperGlyph(box: 16, [.stroke("M3 4.5H13M6.5 4.5V3H9.5V4.5M4.5 4.5L5 13H11L11.5 4.5", 1.5)])
    /// 35: the quantity pill's plus and minus.
    static let stepPlus = PaperGlyph(box: 14, [.stroke("M7 3V11M3 7H11", 1.8)])
    static let stepMinus = PaperGlyph(box: 14, [.stroke("M3 7H11", 1.8)])
    /// 35: the shield and check on "Present to customer".
    static let shieldCheck = PaperGlyph(box: 15, [.stroke("M7.5 1.8L12.8 4.4V8.2C12.8 11 10.6 12.9 7.5 13.7C4.4 12.9 2.2 11 2.2 8.2V4.4L7.5 1.8Z", 1.5),
                                                  .stroke("M5.4 7.7L7 9.3L9.8 6.3", 1.5)])
    /// 35: the save disk in the 50pt circle beside the commit.
    static let saveDisk = PaperGlyph(box: 17, [.stroke("M4 2.5h7l2.5 2.5v9a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1v-10.5a1 1 0 0 1 1-1z", 1.5),
                                               .stroke("M5.5 2.5v3h5v-3", 1.5), .stroke("M5.5 9.5h6", 1.5)])
    /// 39: the three waves in the Tap to Pay ring.
    static let contactless = PaperGlyph(box: 26, [.stroke("M8.5 9.5a6.4 6.4 0 0 1 0 7", 1.8), .stroke("M12 7.5a9.6 9.6 0 0 1 0 11", 1.8),
                                                  .stroke("M15.5 5.5a12.8 12.8 0 0 1 0 15", 1.8)])
    /// 39's method rows, each on a 19 box.
    static let payCard = PaperGlyph(box: 19, [.rect(2, 4.5, 15, 10, rx: 1.8, 1.5), .stroke("M2 8h15", 1.5), .stroke("M5 11.5h3", 1.5)])
    static let payCode = PaperGlyph(box: 19, [.rect(2.5, 2.5, 5.5, 5.5, rx: 1, 1.5), .rect(11, 2.5, 5.5, 5.5, rx: 1, 1.5),
                                              .rect(2.5, 11, 5.5, 5.5, rx: 1, 1.5), .stroke("M11 11.5h2.5v2.5M16.5 11.5v5M11 16.5h3", 1.5)])
    static let payLink = PaperGlyph(box: 19, [.stroke("M7.5 11.5l4-4", 1.5), .stroke("M8.5 6.2l1.4-1.4a3 3 0 0 1 4.3 4.3L12.8 10.5", 1.5),
                                              .stroke("M10.5 12.8l-1.4 1.4a3 3 0 0 1-4.3-4.3L6.2 8.5", 1.5)])
    static let payCheck = PaperGlyph(box: 19, [.rect(2, 4.5, 15, 10, rx: 1.5, 1.5), .stroke("M5 8h5M5 11h3.2", 1.5), .circle(13.6, 9.5, 1.4, 1.3)])
    static let payCash = PaperGlyph(box: 19, [.rect(2, 5, 15, 9, rx: 1.5, 1.5), .circle(9.5, 9.5, 2, 1.4), .stroke("M4.6 7.4h.01M14.4 11.6h.01", 1.6)])
    /// 39: the 12pt up-and-down chevrons beside a value that opens a choice.
    static let upDown = PaperGlyph(box: 14, [.stroke("M4.2 5.6L7 2.8l2.8 2.8", 1.5), .stroke("M4.2 8.4L7 11.2l2.8-2.8", 1.5)])
    /// 38: the cart in the bar under the options.
    static let cart = PaperGlyph(box: 24, [.stroke("M3.5 5H5.5L7.5 15.5H17.5L19.5 8H6.5", 1.8), .circle(9, 19, 1.4), .circle(16.5, 19, 1.4)])
}

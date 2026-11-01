import SwiftUI

/// v2 Record rooms (design.thorbis.com "Rooms" and "the page is one pour"): on a job or a customer,
/// sections are separated by space under 13 Medium labels, with no panel behind their rows. Screens
/// that are Record rooms set `.environment(\.paperRecordRoom, true)`; `PaperCard` / `PaperSection`
/// and the job's `JobPanel` then draw their rows straight on the page, shifted so a row's words line
/// up with its section's label. Off by default, so forms, settings and sheets keep their panels.
private struct PaperRecordRoomKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var paperRecordRoom: Bool {
        get { self[PaperRecordRoomKey.self] }
        set { self[PaperRecordRoomKey.self] = newValue }
    }
}

enum RecordRoom {
    /// A section label's own side padding (`SectionHeader`, `JobPanelLabel`).
    static let labelInset: CGFloat = 4
    /// How far a panel's rows move out once the panel is gone, so their words meet the label.
    static func outset(rowInset: CGFloat) -> CGFloat { -(rowInset - labelInset) }
}

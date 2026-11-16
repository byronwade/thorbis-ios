import Foundation

/// Captures exactly what the technician chose to submit. A delayed response may clear
/// the field only if it still contains that same draft.
struct NoteSubmissionSnapshot {
    let original: String
    let body: String
    init(_ original: String) {
        self.original = original
        body = original.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func remainingDraft(current: String) -> String { current == original ? "" : current }
}

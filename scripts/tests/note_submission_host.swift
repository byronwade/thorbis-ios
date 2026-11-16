import Foundation
// NOTE_SUBMISSION_SOURCE
@main struct Probe {
    static func main() async {
        let initial = NoteSubmissionSnapshot("Original note ")
        precondition(initial.body == "Original note")
        let request = Task { await Task.yield(); return initial }
        let newer = "Original note with more detail"
        let sent = await request.value
        precondition(sent.remainingDraft(current: newer) == newer, "delayed acknowledgement must not erase newer typing")
        precondition(sent.remainingDraft(current: "Original note ") == "")
        precondition(sent.remainingDraft(current: "replacement") == "replacement")
        print("delayed note acknowledgement preserves newer edits")
    }
}

import Foundation
struct JobNoteRecord: Equatable { let id: String; let organizationId: String; let jobId: String; let body: String }
struct JobNotesPage { let items: [JobNoteRecord]; let nextCursor: String? }
// NOTES_STATE_SOURCE
@main struct Probe {
    static func main() throws {
        let org = "00000000-0000-4000-8000-000000000001"
        let job = "00000000-0000-4000-8000-000000000002"
        let firstID = "00000000-0000-4000-8000-000000000003"
        let nextID = "00000000-0000-4000-8000-000000000004"
        let first = JobNoteRecord(id: firstID, organizationId: org, jobId: job, body: "Recent")
        let next = JobNoteRecord(id: nextID, organizationId: org, jobId: job, body: "Earlier")
        var state = JobNotesPageState(organizationID: org, jobID: job)
        try state.accept(JobNotesPage(items: [first], nextCursor: firstID), requestedCursor: nil)
        precondition(state.items == [first] && state.nextCursor == firstID)
        do { try state.accept(JobNotesPage(items: [next], nextCursor: firstID), requestedCursor: firstID); preconditionFailure("cursor loop") } catch {}
        precondition(state.items == [first] && state.nextCursor == firstID)
        do { try state.accept(JobNotesPage(items: [JobNoteRecord(id: nextID, organizationId: org, jobId: "foreign", body: "bad")], nextCursor: nil), requestedCursor: firstID); preconditionFailure("foreign job") } catch {}
        precondition(state.items == [first])
        do { try state.accept(JobNotesPage(items: [first], nextCursor: nil), requestedCursor: firstID); preconditionFailure("duplicate note") } catch {}
        do { try state.accept(JobNotesPage(items: [JobNoteRecord(id: nextID, organizationId: "foreign", jobId: job, body: "bad")], nextCursor: nil), requestedCursor: firstID); preconditionFailure("foreign organization") } catch {}
        do { try state.accept(JobNotesPage(items: [next], nextCursor: "invalid"), requestedCursor: firstID); preconditionFailure("invalid cursor") } catch {}
        precondition(state.items == [first] && state.nextCursor == firstID)
        try state.accept(JobNotesPage(items: [next], nextCursor: nil), requestedCursor: firstID)
        precondition(state.items == [first, next] && state.nextCursor == nil)
        do { try state.accept(JobNotesPage(items: [next], nextCursor: nil), requestedCursor: firstID); preconditionFailure("stale page") } catch {}
        print("job notes page state passed")
    }
}

import Foundation

/// A page is accepted only as a whole. The caller still checks live session/job authority
/// immediately before publishing and keeps partial data out of complete offline caches.
struct JobNotesPageState {
    let organizationID: String
    let jobID: String
    private(set) var items: [JobNoteRecord] = []
    private(set) var nextCursor: String?
    private var started = false
    private var seenCursors = Set<String>()

    init(organizationID: String, jobID: String) {
        self.organizationID = organizationID
        self.jobID = jobID
    }

    mutating func accept(_ page: JobNotesPage, requestedCursor: String?) throws {
        guard (started ? nextCursor != nil && requestedCursor == nextCursor : requestedCursor == nil),
              UUID(uuidString: organizationID) != nil, UUID(uuidString: jobID) != nil else { throw JobNotesPageError.invalid }
        var ids = Set(items.map { $0.id.lowercased() })
        for item in page.items {
            guard UUID(uuidString: item.id) != nil,
                  item.organizationId.lowercased() == organizationID.lowercased(),
                  item.jobId.lowercased() == jobID.lowercased(), ids.insert(item.id.lowercased()).inserted else {
                throw JobNotesPageError.invalid
            }
        }
        var seen = seenCursors
        if let cursor = page.nextCursor {
            let normalized = cursor.lowercased()
            guard UUID(uuidString: cursor) != nil, page.items.last?.id.lowercased() == normalized,
                  seen.insert(normalized).inserted else { throw JobNotesPageError.invalid }
        }
        items.append(contentsOf: page.items)
        nextCursor = page.nextCursor
        seenCursors = seen
        started = true
    }
}

enum JobNotesPageError: Error { case invalid }

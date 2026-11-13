import Foundation

/// A single job's membership scan. Each call reads exactly one page on explicit demand.
/// This object does not establish authorization or approve estimates; callers must bind
/// `isCurrent` to the active actor, workspace, origin, job and capability throughout.
@MainActor
final class JobEstimateMembershipPager {
    struct Page {
        let links: [JobEstimateLink]
        let nextCursor: String?
        /// True only when the caller verified an uncached, authorized response for this page.
        let isAuthoritative: Bool
    }
    struct InvalidPage: Error {}

    private let jobID: String
    private var started = false
    private var exhausted = false
    private var sawUnverifiedPage = false
    private var inFlight = false
    private var nextCursor: String?
    private var seenCursors: Set<String> = []
    private var seenLinks: Set<String> = []
    private var seenEstimates: Set<String> = []
    private(set) var estimateIDs: [String] = []

    init(jobID: String) { self.jobID = jobID }
    /// An exhausted cursor is not a frozen snapshot: links can change between pages.
    /// Approval must independently revalidate exact selected memberships and terms.
    /// These are historical scan facts, not proof of current authority or a server snapshot.
    var scanReachedEnd: Bool { started && exhausted }
    var scanUsedOnlyFreshResponses: Bool { scanReachedEnd && !sawUnverifiedPage }
    var canLoadMore: Bool { !exhausted && !inFlight }

    func loadNext(isCurrent: @MainActor () -> Bool,
                  fetch: @MainActor (String?) async throws -> Page) async throws {
        guard isCurrent(), !Task.isCancelled else { throw CancellationError() }
        guard !exhausted, !inFlight else { throw InvalidPage() }
        inFlight = true
        defer { inFlight = false }
        let requestCursor = nextCursor
        let page = try await fetch(requestCursor)
        try Task.checkCancellation()
        guard isCurrent() else { throw CancellationError() }
        guard page.links.allSatisfy({ $0.jobId.lowercased() == jobID.lowercased() && !$0.id.isEmpty && !$0.estimateId.isEmpty }),
              Set(page.links.map { $0.id.lowercased() }).count == page.links.count,
              page.links.allSatisfy({ !seenLinks.contains($0.id.lowercased()) }) else { throw InvalidPage() }
        if let cursor = page.nextCursor {
            // The canonical jobs endpoint uses the last returned link UUID as its keyset cursor.
            guard !cursor.isEmpty, cursor.lowercased() != requestCursor?.lowercased(),
                  !seenCursors.contains(cursor.lowercased()),
                  page.links.last?.id.lowercased() == cursor.lowercased() else { throw InvalidPage() }
        }
        // Commit the page atomically only after every identity and cursor check succeeds.
        for link in page.links {
            seenLinks.insert(link.id.lowercased())
            if seenEstimates.insert(link.estimateId.lowercased()).inserted { estimateIDs.append(link.estimateId) }
        }
        if let cursor = page.nextCursor { seenCursors.insert(cursor.lowercased()) }
        nextCursor = page.nextCursor
        exhausted = page.nextCursor == nil
        sawUnverifiedPage = sawUnverifiedPage || !page.isAuthoritative
        started = true
    }
}

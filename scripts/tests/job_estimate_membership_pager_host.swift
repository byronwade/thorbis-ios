import Foundation

struct JobEstimateLink: Sendable { let id: String; let jobId: String; let estimateId: String }

@main struct Probe {
    @MainActor static func main() async throws {
        let pager = JobEstimateMembershipPager(jobID: "job")
        var requests: [String?] = []
        var current = true
        let fetch: @MainActor (String?) async throws -> JobEstimateMembershipPager.Page = { cursor in
            requests.append(cursor)
            if cursor == nil { return .init(links: [.init(id: "2", jobId: "job", estimateId: "b")], nextCursor: "2", isAuthoritative: true) }
            return .init(links: [.init(id: "1", jobId: "job", estimateId: "a")], nextCursor: nil, isAuthoritative: true)
        }
        try await pager.loadNext(isCurrent: { current }, fetch: fetch)
        precondition(requests.count == 1 && pager.estimateIDs == ["b"] && !pager.scanUsedOnlyFreshResponses && pager.canLoadMore)
        try await pager.loadNext(isCurrent: { current }, fetch: fetch)
        precondition(requests.count == 2 && pager.estimateIDs == ["b", "a"] && pager.scanUsedOnlyFreshResponses && !pager.canLoadMore)
        // Historical scan facts remain true after retirement; caller must not mistake them
        // for authority. A later load still refuses the retired scope.
        current = false
        do {
            try await pager.loadNext(isCurrent: { current }, fetch: fetch)
            preconditionFailure("Retired scope accepted")
        } catch is CancellationError { }
        precondition(pager.scanReachedEnd && pager.scanUsedOnlyFreshResponses)
        current = true
        let stale = JobEstimateMembershipPager(jobID: "job")
        do {
            try await stale.loadNext(isCurrent: { current }) { _ in
                current = false
                return .init(links: [.init(id: "1", jobId: "job", estimateId: "a")], nextCursor: nil, isAuthoritative: true)
            }
            preconditionFailure("Expected scope retirement")
        } catch is CancellationError { }
        precondition(stale.estimateIDs.isEmpty && !stale.scanUsedOnlyFreshResponses)
        current = true
        let foreign = JobEstimateMembershipPager(jobID: "job")
        do {
            try await foreign.loadNext(isCurrent: { current }) { _ in
                .init(links: [.init(id: "1", jobId: "other", estimateId: "x")], nextCursor: nil, isAuthoritative: true)
            }
            preconditionFailure("Foreign link accepted")
        } catch is JobEstimateMembershipPager.InvalidPage { }
        precondition(foreign.estimateIDs.isEmpty && !foreign.scanUsedOnlyFreshResponses)
        let cached = JobEstimateMembershipPager(jobID: "job")
        try await cached.loadNext(isCurrent: { current }) { _ in
            .init(links: [.init(id: "1", jobId: "job", estimateId: "a")], nextCursor: nil, isAuthoritative: false)
        }
        precondition(!cached.scanUsedOnlyFreshResponses && !cached.canLoadMore && cached.estimateIDs == ["a"])
        let loop = JobEstimateMembershipPager(jobID: "job")
        try await loop.loadNext(isCurrent: { current }) { _ in
            .init(links: [.init(id: "2", jobId: "job", estimateId: "b")], nextCursor: "2", isAuthoritative: true)
        }
        do {
            try await loop.loadNext(isCurrent: { current }) { _ in
                .init(links: [.init(id: "1", jobId: "job", estimateId: "a")], nextCursor: "2", isAuthoritative: true)
            }
            preconditionFailure("Repeated cursor accepted")
        } catch is JobEstimateMembershipPager.InvalidPage { }
        precondition(loop.estimateIDs == ["b"] && !loop.scanUsedOnlyFreshResponses && loop.canLoadMore)
        let malformed = JobEstimateMembershipPager(jobID: "job")
        do {
            try await malformed.loadNext(isCurrent: { current }) { _ in
                .init(links: [.init(id: "2", jobId: "job", estimateId: "b")], nextCursor: "wrong", isAuthoritative: true)
            }
            preconditionFailure("Cursor must name the last returned link")
        } catch is JobEstimateMembershipPager.InvalidPage {}
        precondition(malformed.estimateIDs.isEmpty && malformed.canLoadMore)
        let retry = JobEstimateMembershipPager(jobID: "job")
        enum Offline: Error { case unavailable }
        do {
            try await retry.loadNext(isCurrent: { current }) { _ in throw Offline.unavailable }
            preconditionFailure("Expected offline failure")
        } catch Offline.unavailable { }
        precondition(retry.estimateIDs.isEmpty && retry.canLoadMore && !retry.scanUsedOnlyFreshResponses)
        try await retry.loadNext(isCurrent: { current }) { _ in
            .init(links: [.init(id: "a", jobId: "job", estimateId: "same"), .init(id: "b", jobId: "job", estimateId: "same")], nextCursor: nil, isAuthoritative: true)
        }
        precondition(retry.estimateIDs == ["same"] && retry.scanUsedOnlyFreshResponses)
        let concurrent = JobEstimateMembershipPager(jobID: "job")
        var release: CheckedContinuation<Void, Never>?
        let first = Task { @MainActor in
            try await concurrent.loadNext(isCurrent: { current }) { _ in
                await withCheckedContinuation { release = $0 }
                return .init(links: [.init(id: "1", jobId: "job", estimateId: "a")], nextCursor: nil, isAuthoritative: true)
            }
        }
        while release == nil { await Task.yield() }
        do {
            try await concurrent.loadNext(isCurrent: { current }) { _ in
                preconditionFailure("Concurrent duplicate request started")
            }
            preconditionFailure("Concurrent load accepted")
        } catch is JobEstimateMembershipPager.InvalidPage { }
        release?.resume()
        try await first.value
        precondition(concurrent.estimateIDs == ["a"] && concurrent.scanUsedOnlyFreshResponses)
        let mixed = JobEstimateMembershipPager(jobID: "JOB")
        try await mixed.loadNext(isCurrent: { current }) { _ in
            .init(links: [.init(id: "AA", jobId: "job", estimateId: "AB"), .init(id: "BB", jobId: "JOB", estimateId: "ab")], nextCursor: nil, isAuthoritative: true)
        }
        precondition(mixed.estimateIDs == ["AB"])
        // The handoff still has to load each page's details after membership arrives.
        // If that work is interrupted, the final cursor must remain retryable.
        let interrupted = JobEstimateMembershipPager(jobID: "job")
        try await interrupted.loadNext(isCurrent: { current }) { _ in
            .init(links: [.init(id: "a", jobId: "job", estimateId: "first")], nextCursor: "a", isAuthoritative: true)
        }
        var interruptedCursors: [String?] = []
        do {
            try await interrupted.loadNext(isCurrent: { current }, beforeCommit: { candidate in
                precondition(candidate.estimateIDs == ["first", "second"] && candidate.scanReachedEnd)
                throw CancellationError()
            }) { cursor in
                interruptedCursors.append(cursor)
                return .init(links: [.init(id: "b", jobId: "job", estimateId: "second")], nextCursor: nil, isAuthoritative: true)
            }
            preconditionFailure("Expected detail interruption")
        } catch is CancellationError { }
        guard interrupted.canLoadMore && interrupted.estimateIDs == ["first"] else {
            throw Offline.unavailable
        }
        try await interrupted.loadNext(isCurrent: { current }) { cursor in
            interruptedCursors.append(cursor)
            return .init(links: [.init(id: "b", jobId: "job", estimateId: "second")], nextCursor: nil, isAuthoritative: true)
        }
        precondition(interruptedCursors.count == 2 && interruptedCursors.allSatisfy { $0 == "a" })
        precondition(interrupted.estimateIDs == ["first", "second"] && interrupted.scanUsedOnlyFreshResponses)
        let retiredDuringDetails = JobEstimateMembershipPager(jobID: "job")
        current = true
        do {
            try await retiredDuringDetails.loadNext(isCurrent: { current }, beforeCommit: { _ in
                current = false
            }) { _ in .init(links: [.init(id: "a", jobId: "job", estimateId: "first")], nextCursor: nil, isAuthoritative: true) }
            preconditionFailure("Retired authority cannot commit prepared details")
        } catch is CancellationError { }
        precondition(retiredDuringDetails.estimateIDs.isEmpty && retiredDuringDetails.canLoadMore)
        current = true
        let preparing = JobEstimateMembershipPager(jobID: "job")
        var releaseDetails: CheckedContinuation<Void, Never>?
        let preparation = Task { @MainActor in
            try await preparing.loadNext(isCurrent: { current }, beforeCommit: { _ in
                await withCheckedContinuation { releaseDetails = $0 }
            }) { _ in .init(links: [.init(id: "a", jobId: "job", estimateId: "first")], nextCursor: nil, isAuthoritative: true) }
        }
        while releaseDetails == nil { await Task.yield() }
        precondition(preparing.estimateIDs.isEmpty && !preparing.canLoadMore)
        do {
            try await preparing.loadNext(isCurrent: { current }) { _ in preconditionFailure("duplicate fetch") }
            preconditionFailure("A page was accepted during detail preparation")
        } catch is JobEstimateMembershipPager.InvalidPage { }
        releaseDetails?.resume(); try await preparation.value
        precondition(preparing.estimateIDs == ["first"] && preparing.scanReachedEnd)
        print("membership paging probe passed")
    }
}

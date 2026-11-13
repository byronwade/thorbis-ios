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
        precondition(requests.count == 1 && pager.estimateIDs == ["b"] && !pager.allPagesAuthoritative && pager.canLoadMore)
        try await pager.loadNext(isCurrent: { current }, fetch: fetch)
        precondition(requests.count == 2 && pager.estimateIDs == ["b", "a"] && pager.allPagesAuthoritative && !pager.canLoadMore)
        let stale = JobEstimateMembershipPager(jobID: "job")
        do {
            try await stale.loadNext(isCurrent: { current }) { _ in
                current = false
                return .init(links: [.init(id: "1", jobId: "job", estimateId: "a")], nextCursor: nil, isAuthoritative: true)
            }
            preconditionFailure("Expected scope retirement")
        } catch is CancellationError { }
        precondition(stale.estimateIDs.isEmpty && !stale.allPagesAuthoritative)
        current = true
        let foreign = JobEstimateMembershipPager(jobID: "job")
        do {
            try await foreign.loadNext(isCurrent: { current }) { _ in
                .init(links: [.init(id: "1", jobId: "other", estimateId: "x")], nextCursor: nil, isAuthoritative: true)
            }
            preconditionFailure("Foreign link accepted")
        } catch is JobEstimateMembershipPager.InvalidPage { }
        precondition(foreign.estimateIDs.isEmpty && !foreign.allPagesAuthoritative)
        let cached = JobEstimateMembershipPager(jobID: "job")
        try await cached.loadNext(isCurrent: { current }) { _ in
            .init(links: [.init(id: "1", jobId: "job", estimateId: "a")], nextCursor: nil, isAuthoritative: false)
        }
        precondition(!cached.allPagesAuthoritative && !cached.canLoadMore && cached.estimateIDs == ["a"])
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
        precondition(loop.estimateIDs == ["b"] && !loop.allPagesAuthoritative && loop.canLoadMore)
        let retry = JobEstimateMembershipPager(jobID: "job")
        enum Offline: Error { case unavailable }
        do {
            try await retry.loadNext(isCurrent: { current }) { _ in throw Offline.unavailable }
            preconditionFailure("Expected offline failure")
        } catch Offline.unavailable { }
        precondition(retry.estimateIDs.isEmpty && retry.canLoadMore && !retry.allPagesAuthoritative)
        try await retry.loadNext(isCurrent: { current }) { _ in
            .init(links: [.init(id: "a", jobId: "job", estimateId: "same"), .init(id: "b", jobId: "job", estimateId: "same")], nextCursor: nil, isAuthoritative: true)
        }
        precondition(retry.estimateIDs == ["same"] && retry.allPagesAuthoritative)
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
        precondition(concurrent.estimateIDs == ["a"] && concurrent.allPagesAuthoritative)
        print("membership paging probe passed")
    }
}

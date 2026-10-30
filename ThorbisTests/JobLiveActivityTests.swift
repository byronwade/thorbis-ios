import XCTest
@testable import Thorbis

final class JobLiveActivityTests: XCTestCase {
    func testJobLinkRoundTrips() throws {
        let url = try XCTUnwrap(JobActivityLink.url(jobID: "00000000-0000-4000-8000-000000002214"))
        XCTAssertEqual(url.absoluteString, "thorbis://job/00000000-0000-4000-8000-000000002214")
        XCTAssertEqual(JobActivityLink.jobID(from: url), "00000000-0000-4000-8000-000000002214")
    }

    func testOtherLinksAreNotJobs() {
        XCTAssertNil(JobActivityLink.jobID(from: URL(string: "thorbis://document/abc")!))
        XCTAssertNil(JobActivityLink.jobID(from: URL(string: "thorbis://job/")!))
        XCTAssertNil(JobActivityLink.jobID(from: URL(string: "https://job/123")!))
        // A job link must not be mistaken for a public estimate token.
        XCTAssertNil(PublicEstimateActionLink.token(from: URL(string: "thorbis://job/123")!))
    }

    func testFieldStepsAndLabels() {
        func state(_ status: String) -> JobActivityAttributes.ContentState {
            .init(status: status, since: .now, waitingToSync: false)
        }
        XCTAssertEqual(state("en_route").label, "On my way")
        XCTAssertEqual(state("en_route").step, 0)
        XCTAssertEqual(state("arrived").label, "On site")
        XCTAssertEqual(state("arrived").step, 1)
        XCTAssertEqual(state("in_progress").step, 2)
        XCTAssertEqual(state("paused").label, "Paused")
        XCTAssertEqual(JobLiveActivity.liveStatuses, ["en_route", "arrived", "in_progress", "paused"])
    }

    func testNextJobPrefersTheJobUnderWayThenTheEarliestBooking() {
        func job(_ id: String, _ status: String, _ at: String?) -> Job {
            var job = Job(id: id, customerId: nil, title: id, status: status, createdAt: nil, updatedAt: nil, allowedTransitions: nil)
            job.scheduledFor = at
            return job
        }
        let later = job("later", "scheduled", "2026-10-27T18:00:00Z")
        let sooner = job("sooner", "dispatched", "2026-10-27T14:30:00Z")
        let done = job("done", "completed", "2026-10-27T12:00:00Z")
        XCTAssertEqual(PaperWorkGroups.next([later, done, sooner])?.id, "sooner")
        XCTAssertEqual(PaperWorkGroups.next([later, job("working", "in_progress", nil), sooner])?.id, "working")
        XCTAssertNil(PaperWorkGroups.next([done]))
        XCTAssertEqual(JobActivityLink.jobID(from: URL(string: "thorbis://job/next")!), JobActivityLink.nextJob)
    }
}

@MainActor
final class JobActivityLifecycleTests: XCTestCase {
    @MainActor private final class SuspendedEnd {
        var continuation: CheckedContinuation<Void, Never>?
        func wait() async { await withCheckedContinuation { continuation = $0 } }
        func release() { continuation?.resume(); continuation = nil }
    }
    @MainActor private final class ResultState { var requests = 0; var authorized = true }

    func testRetiredAuthorityCannotRequestAfterSuspendedEnd() async {
        let lifecycle = JobActivityLifecycle()
        let pending = SuspendedEnd()
        let state = ResultState()
        let task = Task {
            await lifecycle.perform(endCount: 1, isAuthorized: { state.authorized },
                                    end: { _ in await pending.wait() }, finish: { state.requests += 1 })
        }
        for _ in 0..<100 where pending.continuation == nil { await Task.yield() }
        XCTAssertNotNil(pending.continuation)
        state.authorized = false
        pending.release()
        await task.value
        XCTAssertEqual(state.requests, 0)
    }

    func testNewerSyncSupersedesSuspendedOldSync() async {
        let lifecycle = JobActivityLifecycle()
        let pending = SuspendedEnd()
        let state = ResultState()
        let old = Task {
            await lifecycle.perform(endCount: 1, isAuthorized: { true },
                                    end: { _ in await pending.wait() }, finish: { state.requests += 100 })
        }
        for _ in 0..<100 where pending.continuation == nil { await Task.yield() }
        XCTAssertNotNil(pending.continuation)
        let next = Task { await lifecycle.perform(endCount: 0, isAuthorized: { true }, end: { _ in }, finish: { state.requests += 1 }) }
        await Task.yield()
        pending.release()
        await old.value
        await next.value
        XCTAssertEqual(state.requests, 1)
    }

    func testCancelledSyncCannotRequestAfterSuspendedEnd() async {
        let lifecycle = JobActivityLifecycle()
        let pending = SuspendedEnd()
        let state = ResultState()
        let task = Task {
            await lifecycle.perform(endCount: 1, isAuthorized: { true },
                                    end: { _ in await pending.wait() }, finish: { state.requests += 1 })
        }
        for _ in 0..<100 where pending.continuation == nil { await Task.yield() }
        XCTAssertNotNil(pending.continuation)
        task.cancel()
        pending.release()
        await task.value
        XCTAssertEqual(state.requests, 0)
    }
    func testRetirementDismissesOldCardBeforeNewAuthorizedSync() async {
        let lifecycle = JobActivityLifecycle()
        let oldEnd = SuspendedEnd()
        let dismissal = SuspendedEnd()
        let state = ResultState()
        let old = Task {
            await lifecycle.perform(endCount: 1, isAuthorized: { true },
                                    end: { _ in await oldEnd.wait() }, finish: { state.requests += 100 })
        }
        for _ in 0..<100 where oldEnd.continuation == nil { await Task.yield() }
        XCTAssertNotNil(oldEnd.continuation)
        lifecycle.retire(endCount: 1, end: { _ in await dismissal.wait() })
        let next = Task {
            await lifecycle.perform(endCount: 0, isAuthorized: { true }, end: { _ in }, finish: { state.requests += 1 })
        }
        oldEnd.release()
        await old.value
        for _ in 0..<100 where dismissal.continuation == nil { await Task.yield() }
        XCTAssertNotNil(dismissal.continuation)
        XCTAssertEqual(state.requests, 0, "A new card must wait until the old card is dismissed")
        dismissal.release()
        await next.value
        XCTAssertEqual(state.requests, 1)
    }

}

final class JobNextStepTests: XCTestCase {
    func testCardOffersOnlyTheNextForwardFieldStep() {
        func next(_ status: String) -> JobNextStep? {
            JobActivityAttributes.ContentState(status: status, since: .now, waitingToSync: false).nextStep
        }
        XCTAssertEqual(next("dispatched")?.target, "en_route")
        XCTAssertEqual(next("dispatched")?.title, "On my way")
        XCTAssertEqual(next("en_route")?.target, "arrived")
        XCTAssertEqual(next("en_route")?.title, "Mark arrived")
        XCTAssertEqual(next("arrived")?.target, "in_progress")
        XCTAssertEqual(next("arrived")?.title, "Start work")
        // Pausing, resuming and finishing need the app.
        XCTAssertNil(next("in_progress"))
        XCTAssertNil(next("paused"))
        XCTAssertNil(next("completed"))
    }

    @MainActor
    func testEveryOfferedStepMapsToARequestTheOutboxCanQueue() throws {
        for status in ["scheduled", "en_route", "arrived"] {
            let step = try XCTUnwrap(JobNextStep.after(status))
            let request = try XCTUnwrap(JobStepIntentRunner.request(for: step.target))
            let payload = try XCTUnwrap(OutboxEntry.ProgressPayload(jobID: "job-1", request: request))
            XCTAssertEqual(payload.to, step.target)
        }
        XCTAssertNil(JobStepIntentRunner.request(for: "paused"))
    }

    func testCompactStatusIsAlwaysAWord() {
        for status in JobLiveActivity.liveStatuses {
            let state = JobActivityAttributes.ContentState(status: status, since: .now, waitingToSync: false)
            XCTAssertFalse(state.shortLabel.isEmpty)
            XCTAssertTrue(state.shortLabel.first?.isLetter ?? false)
        }
    }
}

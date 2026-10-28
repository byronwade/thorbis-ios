import ActivityKit
import Foundation

/// Keeps one Live Activity in step with the job the technician has under way.
/// Nonisolated: ActivityKit's Activity is not Sendable, so it never crosses to the main actor.
enum JobLiveActivity {
    static let liveStatuses: Set<String> = ["en_route", "arrived", "in_progress", "paused"]

    static func sync(job: JobRecord, status: String, waitingToSync: Bool, customer: String, address: String?) async {
        let running = Activity<JobActivityAttributes>.activities
        guard liveStatuses.contains(status) else {
            for activity in running where activity.attributes.jobID == job.id { await end(activity) }
            return
        }
        let current = running.first { $0.attributes.jobID == job.id }
        // Keep the timer running from the first time this status was seen on the phone.
        let kept = current.flatMap { $0.content.state.status == status ? $0.content.state.since : nil }
        let state = JobActivityAttributes.ContentState(status: status, since: JobFiltering.date(stamp(job, status)) ?? kept ?? Date(),
                                                       waitingToSync: waitingToSync)
        let content = ActivityContent(state: state, staleDate: nil)
        // One job at a time: starting another job ends the previous card.
        for activity in running where activity.attributes.jobID != job.id { await end(activity) }
        if let current {
            if current.content.state != state { await current.update(content) }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = JobActivityAttributes(jobID: job.id, jobNumber: "JOB-\(job.id.suffix(4).uppercased())",
                                               title: job.title, customer: customer, address: address)
        _ = try? Activity.request(attributes: attributes, content: content)
    }

    static func endAll() async {
        for activity in Activity<JobActivityAttributes>.activities { await end(activity) }
    }

    private static func end(_ activity: Activity<JobActivityAttributes>) async {
        await activity.end(nil, dismissalPolicy: .immediate)
    }

    private static func stamp(_ job: JobRecord, _ status: String) -> String? {
        switch status {
        case "en_route": job.enRouteAt
        case "arrived": job.arrivedAt
        case "in_progress": job.startedAt
        case "paused": job.pausedAt
        default: nil
        }
    }
}

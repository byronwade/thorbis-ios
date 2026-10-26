import Foundation

/// One thing a person can do to a job from the field. Legality comes from the
/// server's `allowedTransitions` (domains/jobs/src/workflow.ts); this type only
/// orders and names what the server allows, it never adds a move.
public enum JobAction: Hashable, Sendable, Identifiable {
    case progress(JobStatus)
    case resume
    case pause
    case complete
    case cancel

    public var id: String {
        switch self {
        case .progress(let status): "progress:" + status.rawValue
        case .resume: "resume"
        case .pause: "pause"
        case .complete: "complete"
        case .cancel: "cancel"
        }
    }

    /// A commit keeps a word: the verb the technician would say out loud.
    public var title: String {
        switch self {
        case .progress(.scheduled): "Move back to scheduled"
        case .progress(.dispatched): "Dispatch"
        case .progress(.enRoute): "Start driving"
        case .progress(.arrived): "Arrive"
        case .progress(.inProgress): "Start work"
        case .progress: "Update status"
        case .resume: "Resume work"
        case .pause: "Pause job"
        case .complete: "Complete job"
        case .cancel: "Cancel job"
        }
    }

    /// SF Symbol name for the action's mark.
    public var symbol: String {
        switch self {
        case .progress(.enRoute): "car"
        case .progress(.arrived): "mappin.and.ellipse"
        case .progress(.inProgress), .resume: "wrench.and.screwdriver"
        case .progress(.dispatched): "paperplane"
        case .progress: "arrow.uturn.backward"
        case .pause: "pause.circle"
        case .complete: "checkmark.circle"
        case .cancel: "xmark.circle"
        }
    }

    public var isDestructive: Bool { self == .cancel }
}

public enum JobWorkflow {
    /// The single next step to show as the job's commit, if any.
    public static func primaryAction(status: JobStatus, allowed: [JobStatus]) -> JobAction? {
        let can = Set(allowed)
        switch status {
        case .scheduled, .dispatched:
            if can.contains(.enRoute) { return .progress(.enRoute) }
            if can.contains(.arrived) { return .progress(.arrived) }
        case .enRoute:
            if can.contains(.arrived) { return .progress(.arrived) }
        case .arrived:
            if can.contains(.inProgress) { return .progress(.inProgress) }
        case .inProgress:
            if can.contains(.completed) { return .complete }
        case .paused:
            if can.contains(.inProgress) { return .resume }
        case .completed, .canceled, .unknown:
            return nil
        }
        return can.contains(.completed) ? .complete : nil
    }

    /// Everything else the server allows, in service-path order, with cancel last.
    public static func secondaryActions(status: JobStatus, allowed: [JobStatus]) -> [JobAction] {
        let primary = primaryAction(status: status, allowed: allowed)
        var actions: [JobAction] = []
        let order: [JobStatus] = [.dispatched, .enRoute, .arrived, .inProgress, .paused, .scheduled]
        for target in order where allowed.contains(target) {
            let action: JobAction = switch target {
            case .paused: .pause
            case .inProgress where status == .paused: .resume
            default: .progress(target)
            }
            if action != primary, !actions.contains(action) { actions.append(action) }
        }
        if allowed.contains(.completed), primary != .complete { actions.append(.complete) }
        if allowed.contains(.canceled) { actions.append(.cancel) }
        return actions
    }

    /// The server matrix, used only where the list endpoint omits `allowedTransitions`
    /// (rows render a hint; the detail screen always uses server truth).
    public static func fallbackTransitions(from status: JobStatus) -> [JobStatus] {
        switch status {
        case .scheduled: [.dispatched, .enRoute, .arrived, .inProgress, .completed, .canceled]
        case .dispatched: [.scheduled, .enRoute, .arrived, .inProgress, .completed, .canceled]
        case .enRoute: [.dispatched, .arrived, .inProgress, .completed, .canceled]
        case .arrived: [.enRoute, .inProgress, .completed, .canceled]
        case .inProgress: [.paused, .completed, .canceled]
        case .paused: [.inProgress, .completed, .canceled]
        case .completed, .canceled, .unknown: []
        }
    }

    /// Timeline of milestones the server has clocked, oldest first.
    public static func milestones(_ job: Job) -> [Milestone] {
        let pairs: [(String, String?)] = [
            ("Created", job.createdAt), ("Dispatched", job.dispatchedAt), ("En route", job.enRouteAt),
            ("Arrived", job.arrivedAt), ("Started", job.startedAt), ("Paused", job.pausedAt),
            ("Completed", job.completedAt), ("Canceled", job.canceledAt),
        ]
        return pairs
            .compactMap { title, raw in Timestamp.parse(raw).map { Milestone(title: title, at: $0) } }
            .sorted { $0.at < $1.at }
    }
}

public struct Milestone: Hashable, Sendable, Identifiable {
    public let title: String
    public let at: Date
    public var id: String { title }
}

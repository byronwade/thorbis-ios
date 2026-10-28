/// Chooses prominence from known job state; mutations still use the existing server-backed handlers.
enum JobPrimaryAction: Equatable {
    case progress(String)
    case wrapUp

    static func resolve(status: String, allowedTransitions: [String], canEdit: Bool,
                        canAssign: Bool = false, canResume: Bool = false) -> Self? {
        let order = ["scheduled": 0, "dispatched": 0, "en_route": 1, "arrived": 2, "in_progress": 3, "paused": 3]
        guard let current = order[status] else { return nil }

        if status == "scheduled", canAssign, allowedTransitions.contains("dispatched") {
            return .progress("dispatched")
        }
        guard canEdit else { return nil }
        if status == "in_progress" { return .wrapUp }
        if status == "paused" {
            // Only surfaces that retain pause evidence can offer the existing resume handler.
            return canResume && allowedTransitions.contains("in_progress") ? .progress("in_progress") : nil
        }
        for target in ["en_route", "arrived", "in_progress"] {
            if allowedTransitions.contains(target), (order[target] ?? 0) > current {
                return .progress(target)
            }
        }
        return nil
    }
}

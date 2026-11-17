import Foundation

/// Checks one job association for read-only issued terms. A missing link may be the
/// job's origin estimate, or an older server without this route. Approval still
/// revalidates the complete membership set independently.
@MainActor
enum JobEstimateDetailMembership {
    struct InvalidMembership: Error {}

    static func verify(jobID: String, estimateID: String, originID: String?,
                       isCurrent: @MainActor () -> Bool,
                       read: @MainActor () async throws -> JobEstimateLink,
                       list: @MainActor () async throws -> [JobEstimateLink]) async throws {
        guard isCurrent(), !Task.isCancelled else { throw CancellationError() }
        do {
            let link = try await read()
            guard isCurrent(), !Task.isCancelled else { throw CancellationError() }
            guard link.jobId.caseInsensitiveCompare(jobID) == .orderedSame,
                  link.estimateId.caseInsensitiveCompare(estimateID) == .orderedSame else { throw InvalidMembership() }
        } catch let problem as Problem where problem.status == 404 {
            guard isCurrent(), !Task.isCancelled else { throw CancellationError() }
            if originID?.caseInsensitiveCompare(estimateID) == .orderedSame { return }
            let links = try await list()
            guard isCurrent(), !Task.isCancelled else { throw CancellationError() }
            guard links.allSatisfy({ $0.jobId.caseInsensitiveCompare(jobID) == .orderedSame }),
                  links.contains(where: { $0.estimateId.caseInsensitiveCompare(estimateID) == .orderedSame }) else { throw InvalidMembership() }
        }
    }
}

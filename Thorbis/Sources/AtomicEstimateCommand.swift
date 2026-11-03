import Foundation

/// Held wire contract for server-authoritative job estimate creation. The backend
/// is not deployed and there is no versioned readiness proof, so no production
/// code may send this command until that proof and durable recovery are integrated.
struct AtomicEstimateCommand: Codable, Equatable {
    static let productionEnabled = false
    static let command = "jobs.createRelatedEstimate"

    struct Money: Codable, Equatable {
        let amount: Int
        let currency: String
    }
    struct Source: Codable, Equatable {
        let kind: String
        let priceBookItemId: String?
        let priceBookRevision: Int?
        static let manual = Source(kind: "manual", priceBookItemId: nil, priceBookRevision: nil)
        static func priceBook(itemID: String, revision: Int) -> Self {
            .init(kind: "price_book", priceBookItemId: itemID.lowercased(), priceBookRevision: revision)
        }
        var valid: Bool {
            if kind == "manual" { return priceBookItemId == nil && priceBookRevision == nil }
            guard kind == "price_book", let priceBookItemId, UUID(uuidString: priceBookItemId) != nil,
                  let priceBookRevision, (1...Int(Int32.max)).contains(priceBookRevision) else { return false }
            return true
        }
    }
    struct Line: Codable, Equatable {
        let description: String
        let quantity: Int
        let unitPrice: Money
        let source: Source?
        let group: String?
        let showToCustomer: Bool?
        var valid: Bool {
            !description.isEmpty && description == description.trimmingCharacters(in: .whitespacesAndNewlines) && !description.contains("\0") &&
            description.utf16.count <= 200 && (1...100_000).contains(quantity) &&
            unitPrice.currency == "USD" && (-100_000_000...100_000_000).contains(unitPrice.amount) &&
            (source?.valid ?? true) && (group == nil || group == "work" || group == "material")
        }
    }
    struct Payload: Codable, Equatable {
        let jobId: String
        let title: String
        let lines: [Line]
    }
    struct Envelope: Encodable {
        let commandId, deviceId, actorId, organizationId: String
        let policyVersion: Int
        let command: String
        let clientCreatedAt: String
        let payload: Payload
    }
    struct Batch: Encodable { let commands: [Envelope] }
    struct Response: Decodable {
        struct Link: Decodable {
            let id, organizationId, jobId, estimateId: String
            let linkedByUserId: String?
        }
        struct Outcome: Decodable {
            let commandId, status: String
            let category: String?
            let result: Link?
        }
        let outcomes: [Outcome]
    }
    enum Decision: Equatable {
        case linked(estimateID: String, linkID: String)
        case needsReview
        case unknown
    }
    enum Invalid: Error { case scope, payload }

    private static func validTimestamp(_ value: String) -> Bool {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if formatter.date(from: value) != nil { return true }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value) != nil
    }

    private static func validOrigin(_ value: String) -> Bool {
        guard let parts = URLComponents(string: value), let host = parts.host,
              host == host.lowercased(), !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.path.isEmpty, parts.query == nil, parts.fragment == nil,
              parts.string == value else { return false }
        if parts.scheme == "https" { return true }
        #if DEBUG
        return parts.scheme == "http" && ["127.0.0.1", "localhost", "[::1]"].contains(host)
        #else
        return false
        #endif
    }

    let commandID, deviceID, actorID, organizationID: String
    let policyVersion: Int
    let origin: String
    let createdAt: String
    let payload: Payload

    static func make(jobID: String, title: String, lines: [Line], actorID: String,
                     organizationID: String, deviceID: String, policyVersion: Int,
                     origin: String, createdAt: String, commandID: String) throws -> Self {
        guard [jobID, actorID, organizationID, deviceID, commandID].allSatisfy({ UUID(uuidString: $0) != nil }),
              policyVersion > 0, validOrigin(origin), validTimestamp(createdAt) else { throw Invalid.scope }
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty, normalizedTitle.utf16.count <= 200,
              (1...500).contains(lines.count), lines.allSatisfy(\.valid) else { throw Invalid.payload }
        return .init(commandID: commandID.lowercased(), deviceID: deviceID.lowercased(),
                     actorID: actorID.lowercased(), organizationID: organizationID.lowercased(),
                     policyVersion: policyVersion, origin: origin, createdAt: createdAt,
                     payload: .init(jobId: jobID.lowercased(), title: normalizedTitle, lines: lines))
    }
    var batch: Batch {
        .init(commands: [.init(commandId: commandID, deviceId: deviceID, actorId: actorID,
                               organizationId: organizationID, policyVersion: policyVersion,
                               command: Self.command, clientCreatedAt: createdAt, payload: payload)])
    }
    /// The server derives customer and location from the job, not this draft.
    /// A caller must obtain `job` freshly under the same current authority lease.
    /// A mismatch keeps the operation pending for review, never a new create.
    func matchesDraftJob(_ job: JobRecord, customerID: String, locationID: String?) -> Bool {
        guard UUID(uuidString: customerID) != nil,
              locationID.map({ UUID(uuidString: $0) != nil }) ?? true,
              job.id.lowercased() == payload.jobId,
              job.organizationId.lowercased() == organizationID,
              job.customerId.lowercased() == customerID.lowercased(),
              job.locationId?.lowercased() == locationID?.lowercased(),
              ["scheduled", "dispatched", "en_route", "arrived", "in_progress", "paused", "completed"].contains(job.status) else { return false }
        return true
    }
    /// Caller must freshly verify both job and estimate authority before use.
    func maySend(actorID: String, organizationID: String, jobID: String,
                 origin: String, authorized: Bool) -> Bool {
        isValid && authorized && self.actorID == actorID.lowercased() && self.organizationID == organizationID.lowercased() &&
        payload.jobId == jobID.lowercased() && self.origin == origin
    }
    private var isValid: Bool {
        [commandID, deviceID, actorID, organizationID, payload.jobId].allSatisfy { UUID(uuidString: $0) != nil && $0 == $0.lowercased() } &&
        policyVersion > 0 && Self.validOrigin(origin) && Self.validTimestamp(createdAt) &&
        !payload.title.isEmpty && payload.title == payload.title.trimmingCharacters(in: .whitespacesAndNewlines) && payload.title.utf16.count <= 200 &&
        (1...500).contains(payload.lines.count) && payload.lines.allSatisfy(\.valid)
    }
    /// A refusal can be a replay denied after access changed, so it cannot prove
    /// that the original write did not commit or permit a second create.
    func interpret(_ response: Response) -> Decision {
        guard response.outcomes.count == 1, let outcome = response.outcomes.first,
              outcome.commandId.lowercased() == commandID else { return .unknown }
        if outcome.status == "rejected" { return .needsReview }
        guard outcome.status == "applied" || outcome.status == "duplicate", let link = outcome.result,
              link.organizationId.lowercased() == organizationID, link.jobId.lowercased() == payload.jobId,
              link.linkedByUserId?.lowercased() == actorID,
              UUID(uuidString: link.id) != nil, UUID(uuidString: link.estimateId) != nil else { return .unknown }
        return .linked(estimateID: link.estimateId.lowercased(), linkID: link.id.lowercased())
    }
}

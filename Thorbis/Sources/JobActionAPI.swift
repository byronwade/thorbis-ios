import Foundation

struct FieldCloseoutCheckDefinition: Codable, Hashable {
    let key: String
    let label: String
    let kind: String?
    let allowUnpaidDisposition: Bool?
}

struct FieldCloseoutPolicy: Codable, Hashable {
    let organizationId: String?
    let requireNotes: Bool
    let requiredPhotoCount: Int
    let requiredChecks: [FieldCloseoutCheckDefinition]
    let updatedByUserId: String?
    let updatedAt: String?
}

struct FieldCloseoutTarget: Codable, Hashable {
    let id: String
    let organizationId: String
    let customerId: String
    let locationId: String?
    let estimateId: String?
    let estimateRevisionNumber: Int?
}

struct FieldCloseoutFacts: Codable, Hashable {
    let noteCount: Int
    let photoCount: Int
    let acknowledgedCheckKeys: [String]
    let authorizationTarget: FieldCloseoutTarget
}

struct FieldAcknowledgedCheck: Codable, Hashable {
    let checkKey: String
    let acknowledgedByUserId: String
    let acknowledgedAt: String
}

struct FieldCloseoutRequirement: Codable, Hashable {
    let requirement: String
    let kind: String
    let outcome: String
    let detail: String
    let nextAction: String?
    let commercialSource: String?
}

struct FieldCloseout: Codable, Hashable {
    let policy: FieldCloseoutPolicy
    let facts: FieldCloseoutFacts
    let acknowledged: [FieldAcknowledgedCheck]
    let requirements: [FieldCloseoutRequirement]
    let unmet: [FieldCloseoutRequirement]
    let completable: Bool
}

struct FieldCloseoutCheckRecord: Codable, Identifiable, Hashable {
    let id: String
    let organizationId: String
    let jobId: String
    let checkKey: String
    let acknowledgedByUserId: String
    let acknowledgedAt: String
}

struct FieldUnpaidDisposition: Encodable {
    let reasonCode: String
    let reason: String
    let followUpNextAction: String
}

struct FieldCompleteRequest: Encodable {
    let notes: String?
    let unpaidDisposition: FieldUnpaidDisposition?

    init(notes: String? = nil, unpaidDisposition: FieldUnpaidDisposition? = nil) {
        self.notes = notes
        self.unpaidDisposition = unpaidDisposition
    }
}

/// Distinguishes omitted preconditions from an explicit expected nil assignee.
enum FieldExpectedAssignee {
    case omitted
    case unassigned
    case user(String)
}

struct FieldAssignRequest: Encodable {
    let userId: String
    let expected: FieldExpectedAssignee

    init(userId: String, expected: FieldExpectedAssignee = .omitted) {
        self.userId = userId
        self.expected = expected
    }

    private enum CodingKeys: String, CodingKey { case userId, expectedAssigneeId }

    func encode(to encoder: Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        try fields.encode(userId, forKey: .userId)
        switch expected {
        case .omitted: break
        case .unassigned: try fields.encodeNil(forKey: .expectedAssigneeId)
        case .user(let id): try fields.encode(id, forKey: .expectedAssigneeId)
        }
    }
}

enum FieldExpectedSchedule {
    case omitted
    case unscheduled
    case at(String)
}

enum FieldArrivalWindow {
    case preserve
    case pointTime
    case endsAt(String)
}

struct FieldScheduleRequest: Encodable {
    let scheduledFor: String
    let timeZone: String?
    let arrivalWindow: FieldArrivalWindow
    let expectedPrior: FieldExpectedSchedule

    init(scheduledFor: String, timeZone: String? = nil,
         arrivalWindow: FieldArrivalWindow = .preserve,
         expectedPrior: FieldExpectedSchedule = .omitted) {
        self.scheduledFor = scheduledFor
        self.timeZone = timeZone
        self.arrivalWindow = arrivalWindow
        self.expectedPrior = expectedPrior
    }

    private enum CodingKeys: String, CodingKey {
        case scheduledFor, timeZone, arrivalWindowEndsAt, expectedPriorScheduledFor
    }

    func encode(to encoder: Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        try fields.encode(scheduledFor, forKey: .scheduledFor)
        try fields.encodeIfPresent(timeZone, forKey: .timeZone)
        switch arrivalWindow {
        case .preserve: break
        case .pointTime: try fields.encodeNil(forKey: .arrivalWindowEndsAt)
        case .endsAt(let time): try fields.encode(time, forKey: .arrivalWindowEndsAt)
        }
        switch expectedPrior {
        case .omitted: break
        case .unscheduled: try fields.encodeNil(forKey: .expectedPriorScheduledFor)
        case .at(let time): try fields.encode(time, forKey: .expectedPriorScheduledFor)
        }
    }
}

struct FieldFollowUpAppointment: Codable, Hashable {
    let id: String
    let status: String
    let plannedWindow: FieldAppointmentWindow
    let timeZone: String
}

struct FieldAppointmentWindow: Codable, Hashable {
    let startsAt: String
    let endsAt: String
}

struct FieldFollowUpOfficeReview: Codable, Hashable {
    let id: String
    let status: String
    let reasonCode: String
    let requestedWindow: FieldAppointmentWindow
    let timeZone: String
}

struct FieldFollowUpScheduling: Codable, Hashable {
    let outcome: String
    let appointment: FieldFollowUpAppointment?
    let officeReview: FieldFollowUpOfficeReview?
}

struct FieldFollowUpRecord: Codable, Identifiable, Hashable {
    let id: String
    let organizationId: String
    let jobId: String
    let kind: String
    let reason: String
    let nextAction: String
    let ownerUserId: String
    let requestedFor: String?
    let status: String
    let revision: Int?
    let createdByUserId: String
    let createdAt: String
    let resolvedAt: String?
    let resolvedByUserId: String?
    let scheduling: FieldFollowUpScheduling?
}

struct FieldFollowUpRequest: Encodable {
    enum Kind: String, Encodable, Hashable { case officeScheduling = "office_scheduling", notifyOffice = "notify_office" }
    let kind: Kind
    let reason: String
    let nextAction: String
    let ownerUserId: String?
    let requestedFor: String?

    init(kind: Kind, reason: String, nextAction: String,
         ownerUserId: String? = nil, requestedFor: String? = nil) {
        self.kind = kind
        self.reason = reason
        self.nextAction = nextAction
        self.ownerUserId = ownerUserId
        self.requestedFor = requestedFor
    }
}

struct FieldFollowUpBookingRequest: Encodable {
    let intentId: String
    let requestedWindow: FieldAppointmentWindow
    let timeZone: String
    let serviceNeed: String
    let requiredTraitIds: [String]
}

/// A booking request may create an office review when capacity is unavailable.
struct FieldFollowUpBookingResult: Decodable {
    let outcome: String
    let appointment: FieldFollowUpAppointment?
    let officeReview: FieldFollowUpOfficeReview?

    private enum CodingKeys: String, CodingKey { case outcome, appointment, officeReview }

    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        outcome = try fields.decode(String.self, forKey: .outcome)
        appointment = try fields.decodeIfPresent(FieldFollowUpAppointment.self, forKey: .appointment)
        officeReview = try fields.decodeIfPresent(FieldFollowUpOfficeReview.self, forKey: .officeReview)
        let valid = switch outcome {
        case "booked": appointment != nil && officeReview == nil
        case "office_review_required": officeReview != nil && appointment == nil
        default: false
        }
        guard valid else {
            throw DecodingError.dataCorruptedError(forKey: .outcome, in: fields,
                debugDescription: "Booking outcome requires its matching appointment or office review")
        }
    }
}

private struct JobActionItems<T: Decodable>: Decodable { let items: [T] }

@MainActor
extension APIClient {
    private func jobActionPath(_ jobID: String, _ suffix: String) throws -> String {
        guard UUID(uuidString: jobID) != nil else {
            throw Problem(title: "Invalid job ID", status: nil, detail: jobID)
        }
        return "/v1/jobs/\(jobID)\(suffix)"
    }

    func fieldCloseoutPolicy() async throws -> FieldCloseoutPolicy {
        try await send("GET", "/v1/jobs/closeout-policy")
    }

    func fieldCloseout(_ jobID: String) async throws -> FieldCloseout {
        try await send("GET", jobActionPath(jobID, "/closeout"))
    }

    func completeFieldJob(_ jobID: String, request: FieldCompleteRequest = .init()) async throws -> JobRecord {
        try await send("POST", jobActionPath(jobID, "/complete"), body: request)
    }

    func cancelFieldJob(_ jobID: String) async throws -> JobRecord {
        try await send("POST", jobActionPath(jobID, "/cancel"))
    }

    func acknowledgeFieldCheck(_ jobID: String, checkKey: String) async throws -> FieldCloseoutCheckRecord {
        struct Body: Encodable { let checkKey: String }
        return try await send("POST", jobActionPath(jobID, "/checks"), body: Body(checkKey: checkKey))
    }

    func assignFieldJob(_ jobID: String, request: FieldAssignRequest) async throws -> JobRecord {
        try await send("POST", jobActionPath(jobID, "/assign"), body: request)
    }

    func scheduleFieldJob(_ jobID: String, request: FieldScheduleRequest) async throws -> JobRecord {
        try await send("POST", jobActionPath(jobID, "/schedule"), body: request)
    }

    func undoFieldReschedule(_ jobID: String, sourceAuditId: String) async throws -> JobRecord {
        struct Body: Encodable { let sourceAuditId: String }
        return try await send("POST", jobActionPath(jobID, "/reschedule/undo"), body: Body(sourceAuditId: sourceAuditId))
    }

    func fieldFollowUps(_ jobID: String) async throws -> [FieldFollowUpRecord] {
        let page: JobActionItems<FieldFollowUpRecord> = try await send("GET", jobActionPath(jobID, "/followups"))
        return page.items
    }

    func requestFieldFollowUp(_ jobID: String, request: FieldFollowUpRequest) async throws -> FieldFollowUpRecord {
        try await send("POST", jobActionPath(jobID, "/followups"), body: request)
    }

    func resolveFieldFollowUp(_ jobID: String, followUpID: String) async throws -> FieldFollowUpRecord {
        guard UUID(uuidString: followUpID) != nil else {
            throw Problem(title: "Invalid follow-up ID", status: nil, detail: followUpID)
        }
        return try await send("POST", jobActionPath(jobID, "/followups/\(followUpID)/resolve"))
    }

    func bookFieldFollowUp(_ jobID: String, followUpID: String,
                           request: FieldFollowUpBookingRequest) async throws -> FieldFollowUpBookingResult {
        guard UUID(uuidString: followUpID) != nil else {
            throw Problem(title: "Invalid follow-up ID", status: nil, detail: followUpID)
        }
        return try await send("POST", jobActionPath(jobID, "/followups/\(followUpID)/book"), body: request)
    }
}

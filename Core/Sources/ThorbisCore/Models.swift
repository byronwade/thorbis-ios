import Foundation

// Wire models for the canonical Thorbis API (services/api, contracts/api/http.md).
// They mirror the domain schemas in byronwade/Thorbis-TanStack (domains/*/src/schemas.ts).
// Every enum decodes unknown values to `.unknown` so a server that adds a state
// never makes a list unreadable on an older build.

/// Keyset page (`@thorbis/validation` Page). `nextCursor` is absent on the last page.
public struct Page<Item: Decodable & Sendable>: Decodable, Sendable {
    public let items: [Item]
    public let nextCursor: String?

    public init(items: [Item], nextCursor: String? = nil) {
        self.items = items
        self.nextCursor = nextCursor
    }
}

/// Whole-collection responses (`{ items: [...] }`) for small child collections.
public struct Items<Item: Decodable & Sendable>: Decodable, Sendable {
    public let items: [Item]
}

/// Integer minor units (cents) plus currency, as `moneySchema` stores them.
public struct Money: Codable, Hashable, Sendable {
    public let amount: Int
    public let currency: String

    public init(amount: Int, currency: String = "USD") {
        self.amount = amount
        self.currency = currency
    }

    public static func usd(_ cents: Int) -> Money { Money(amount: cents, currency: "USD") }
}

// MARK: - Jobs

public enum JobStatus: String, Codable, Hashable, Sendable, CaseIterable {
    case scheduled, dispatched
    case enRoute = "en_route"
    case arrived
    case inProgress = "in_progress"
    case paused, completed, canceled
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = JobStatus(rawValue: raw) ?? .unknown
    }

    public var isTerminal: Bool { self == .completed || self == .canceled }
    public var isActive: Bool { !isTerminal && self != .unknown }
}

public struct Job: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let organizationId: String?
    public let customerId: String
    public let title: String
    public let notes: String?
    public let status: JobStatus
    public let assignedToUserId: String?
    public let scheduledFor: String?
    public let createdAt: String
    public let updatedAt: String
    public let dispatchedAt: String?
    public let enRouteAt: String?
    public let arrivedAt: String?
    public let startedAt: String?
    public let pausedAt: String?
    public let pauseReason: String?
    public let pauseNextAction: String?
    public let pauseCycleAuditId: String?
    public let completedAt: String?
    public let canceledAt: String?
    public let estimateId: String?
    /// Served only by `GET /v1/jobs/:id`: the workflow matrix decides, the client renders.
    public let allowedTransitions: [JobStatus]?

    public init(
        id: String, organizationId: String? = nil, customerId: String, title: String,
        notes: String? = nil, status: JobStatus, assignedToUserId: String? = nil,
        scheduledFor: String? = nil, createdAt: String, updatedAt: String,
        dispatchedAt: String? = nil, enRouteAt: String? = nil, arrivedAt: String? = nil,
        startedAt: String? = nil, pausedAt: String? = nil, pauseReason: String? = nil,
        pauseNextAction: String? = nil, pauseCycleAuditId: String? = nil,
        completedAt: String? = nil, canceledAt: String? = nil, estimateId: String? = nil,
        allowedTransitions: [JobStatus]? = nil
    ) {
        self.id = id; self.organizationId = organizationId; self.customerId = customerId
        self.title = title; self.notes = notes; self.status = status
        self.assignedToUserId = assignedToUserId; self.scheduledFor = scheduledFor
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.dispatchedAt = dispatchedAt
        self.enRouteAt = enRouteAt; self.arrivedAt = arrivedAt; self.startedAt = startedAt
        self.pausedAt = pausedAt; self.pauseReason = pauseReason; self.pauseNextAction = pauseNextAction
        self.pauseCycleAuditId = pauseCycleAuditId; self.completedAt = completedAt
        self.canceledAt = canceledAt; self.estimateId = estimateId
        self.allowedTransitions = allowedTransitions
    }

    /// The short reference people read aloud on the phone ("JOB-3F2A").
    public var reference: String { "JOB-" + String(id.replacingOccurrences(of: "-", with: "").suffix(4)).uppercased() }
    public var scheduledDate: Date? { Timestamp.parse(scheduledFor) }
    public var updatedDate: Date? { Timestamp.parse(updatedAt) }
}

public struct JobNote: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let jobId: String
    public let authorUserId: String
    public let body: String
    public let createdAt: String

    public init(id: String, jobId: String, authorUserId: String, body: String, createdAt: String) {
        self.id = id; self.jobId = jobId; self.authorUserId = authorUserId; self.body = body; self.createdAt = createdAt
    }
}

public struct JobPhoto: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let jobId: String
    public let authorUserId: String
    public let contentType: String
    public let byteSize: Int
    public let createdAt: String

    public init(id: String, jobId: String, authorUserId: String, contentType: String, byteSize: Int, createdAt: String) {
        self.id = id; self.jobId = jobId; self.authorUserId = authorUserId
        self.contentType = contentType; self.byteSize = byteSize; self.createdAt = createdAt
    }

    /// `jobPhotoContentTypes` in domains/jobs. HEIC is accepted as-is.
    public static let acceptedContentTypes: Set<String> = ["image/jpeg", "image/png", "image/webp", "image/heic"]
    /// 15 MB, the server's per-photo cap.
    public static let maxByteSize = 15 * 1024 * 1024
}

public struct Assignee: Codable, Hashable, Identifiable, Sendable {
    public let userId: String
    public let displayName: String
    public var id: String { userId }

    public init(userId: String, displayName: String) {
        self.userId = userId; self.displayName = displayName
    }
}

// MARK: - Customers

public enum ContactMethod: String, Codable, Hashable, Sendable, CaseIterable {
    case phone, sms, email
}

public struct Customer: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let email: String?
    public let phone: String?
    public let address: String?
    public let accountType: String?
    public let preferredContact: ContactMethod?
    public let billingTerms: String?
    public let archived: Bool?
    public let createdAt: String?
    public let updatedAt: String?

    public init(
        id: String, name: String, email: String? = nil, phone: String? = nil, address: String? = nil,
        accountType: String? = nil, preferredContact: ContactMethod? = nil, billingTerms: String? = nil,
        archived: Bool? = false, createdAt: String? = nil, updatedAt: String? = nil
    ) {
        self.id = id; self.name = name; self.email = email; self.phone = phone; self.address = address
        self.accountType = accountType; self.preferredContact = preferredContact
        self.billingTerms = billingTerms; self.archived = archived
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        phone = try c.decodeIfPresent(String.self, forKey: .phone)
        address = try c.decodeIfPresent(String.self, forKey: .address)
        accountType = try c.decodeIfPresent(String.self, forKey: .accountType)
        // An unknown preference must not hide the customer.
        preferredContact = (try? c.decodeIfPresent(ContactMethod.self, forKey: .preferredContact)) ?? nil
        billingTerms = try c.decodeIfPresent(String.self, forKey: .billingTerms)
        archived = try c.decodeIfPresent(Bool.self, forKey: .archived)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    public var isArchived: Bool { archived ?? false }
}

public struct CustomerContact: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let customerId: String
    public let name: String
    public let role: String?
    public let email: String?
    public let phone: String?
    public let primary: Bool

    public init(id: String, customerId: String, name: String, role: String? = nil, email: String? = nil, phone: String? = nil, primary: Bool = false) {
        self.id = id; self.customerId = customerId; self.name = name; self.role = role
        self.email = email; self.phone = phone; self.primary = primary
    }
}

public struct Coordinates: Codable, Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude; self.longitude = longitude
    }
}

public enum ServiceLocationKind: String, Codable, Hashable, Sendable, CaseIterable {
    case service, billing
}

public struct ServiceLocation: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let customerId: String
    public let label: String
    public let kind: ServiceLocationKind
    public let address: String
    public let notes: String?
    public let coordinates: Coordinates?
    public let gateCode: String?
    public let alarmCode: String?
    public let dogOnSite: String?
    public let parking: String?

    public init(
        id: String, customerId: String, label: String, kind: ServiceLocationKind, address: String,
        notes: String? = nil, coordinates: Coordinates? = nil, gateCode: String? = nil,
        alarmCode: String? = nil, dogOnSite: String? = nil, parking: String? = nil
    ) {
        self.id = id; self.customerId = customerId; self.label = label; self.kind = kind
        self.address = address; self.notes = notes; self.coordinates = coordinates
        self.gateCode = gateCode; self.alarmCode = alarmCode; self.dogOnSite = dogOnSite; self.parking = parking
    }

    /// Site access a technician needs on arrival, in reading order.
    public var accessNotes: [LabeledValue] {
        [("Gate", gateCode), ("Alarm", alarmCode), ("Dog on site", dogOnSite), ("Parking", parking)]
            .compactMap { pair in pair.1.map { LabeledValue(label: pair.0, value: $0) } }
    }
}

public struct LabeledValue: Hashable, Sendable, Identifiable {
    public let label: String
    public let value: String
    public var id: String { label }

    public init(label: String, value: String) {
        self.label = label; self.value = value
    }
}

// MARK: - Estimates and invoices

public struct DocumentLine: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let description: String
    public let quantity: Int
    public let unitPrice: Money

    public init(id: String, description: String, quantity: Int, unitPrice: Money) {
        self.id = id; self.description = description; self.quantity = quantity; self.unitPrice = unitPrice
    }

    public var total: Int { quantity * unitPrice.amount }
}

public enum EstimateStatus: String, Codable, Hashable, Sendable {
    case draft, sent, approved, declined, unknown

    public init(from decoder: Decoder) throws {
        self = EstimateStatus(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
}

public struct EstimateOption: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let description: String
    public let lines: [DocumentLine]
    public let totalAmount: Int
}

public struct Estimate: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let customerId: String
    public let status: EstimateStatus
    public let currentRevisionNumber: Int?
    public let title: String
    public let lines: [DocumentLine]
    public let options: [EstimateOption]?
    public let createdAt: String
    public let updatedAt: String
    public let sentAt: String?
    public let approvedAt: String?
    public let declinedAt: String?

    public init(
        id: String, customerId: String, status: EstimateStatus, currentRevisionNumber: Int? = nil,
        title: String, lines: [DocumentLine], options: [EstimateOption]? = nil, createdAt: String,
        updatedAt: String, sentAt: String? = nil, approvedAt: String? = nil, declinedAt: String? = nil
    ) {
        self.id = id; self.customerId = customerId; self.status = status
        self.currentRevisionNumber = currentRevisionNumber; self.title = title; self.lines = lines
        self.options = options; self.createdAt = createdAt; self.updatedAt = updatedAt
        self.sentAt = sentAt; self.approvedAt = approvedAt; self.declinedAt = declinedAt
    }

    public var total: Int { lines.reduce(0) { $0 + $1.total } }
    /// The currency the server priced this estimate in (taken from its lines).
    public var currency: String {
        lines.first?.unitPrice.currency ?? options?.first?.lines.first?.unitPrice.currency ?? "USD"
    }
    public var reference: String { "EST-" + String(id.replacingOccurrences(of: "-", with: "").suffix(4)).uppercased() }
}

public enum InvoiceStatus: String, Codable, Hashable, Sendable {
    case draft, issued, paid, void, unknown

    public init(from decoder: Decoder) throws {
        self = InvoiceStatus(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
}

public struct Invoice: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let customerId: String
    public let jobId: String?
    public let status: InvoiceStatus
    public let lines: [DocumentLine]
    public let linesRevision: Int
    public let amountPaid: Int
    public let currency: String
    public let issuedAt: String?
    public let paidAt: String?
    public let voidedAt: String?
    public let createdAt: String
    public let updatedAt: String

    public init(
        id: String, customerId: String, jobId: String? = nil, status: InvoiceStatus, lines: [DocumentLine],
        linesRevision: Int = 1, amountPaid: Int = 0, currency: String = "USD", issuedAt: String? = nil,
        paidAt: String? = nil, voidedAt: String? = nil, createdAt: String, updatedAt: String
    ) {
        self.id = id; self.customerId = customerId; self.jobId = jobId; self.status = status
        self.lines = lines; self.linesRevision = linesRevision; self.amountPaid = amountPaid
        self.currency = currency; self.issuedAt = issuedAt; self.paidAt = paidAt
        self.voidedAt = voidedAt; self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    public var total: Int { lines.reduce(0) { $0 + $1.total } }
    public var balance: Int { max(total - amountPaid, 0) }
    public var reference: String { "INV-" + String(id.replacingOccurrences(of: "-", with: "").suffix(4)).uppercased() }
}

public struct Payment: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let invoiceId: String
    public let amount: Money
    public let refundedAmount: Int?
    public let method: String
    public let status: String
    public let recordedAt: String
}

// MARK: - Inbox, search and identity

/// `GET /v1/staff/notices`: job notices addressed to the signed-in staff member.
public struct StaffNotice: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let jobId: String
    public let title: String
    public let meta: String
    public let at: String
    public let read: Bool

    public init(id: String, jobId: String, title: String, meta: String, at: String, read: Bool) {
        self.id = id; self.jobId = jobId; self.title = title; self.meta = meta; self.at = at; self.read = read
    }
}

public struct StaffNoticePage: Decodable, Sendable {
    public let items: [StaffNotice]
    public let nextCursor: String?
}

public struct SearchResult: Codable, Hashable, Identifiable, Sendable {
    public let resultType: String
    public let entityId: String
    public let title: String
    public let subtitle: String?
    public let status: String?
    public var id: String { resultType + ":" + entityId }

    public init(resultType: String, entityId: String, title: String, subtitle: String? = nil, status: String? = nil) {
        self.resultType = resultType; self.entityId = entityId; self.title = title
        self.subtitle = subtitle; self.status = status
    }

    /// What the result opens in the app. Unknown kinds stay visible but inert.
    public var destination: SearchDestination {
        switch resultType.lowercased() {
        case "job", "jobs": .job(entityId)
        case "customer", "customers": .customer(entityId)
        case "estimate", "estimates": .estimate(entityId)
        case "invoice", "invoices": .invoice(entityId)
        default: .unsupported
        }
    }
}

public enum SearchDestination: Hashable, Sendable {
    case job(String), customer(String), estimate(String), invoice(String), unsupported
}

public struct SearchResponse: Decodable, Sendable {
    public let items: [SearchResult]
    public let nextCursor: String?
}

public struct Account: Codable, Hashable, Sendable {
    public let id: String
    public let name: String?
    public let email: String?

    public init(id: String, name: String?, email: String?) {
        self.id = id; self.name = name; self.email = email
    }
}

public struct Organization: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let slug: String?

    public init(id: String, name: String, slug: String? = nil) {
        self.id = id; self.name = name; self.slug = slug
    }
}

/// Better Auth `GET /api/auth/get-session`.
public struct AuthSession: Decodable, Sendable {
    public struct User: Decodable, Sendable {
        public let id: String
        public let name: String?
        public let email: String?
    }
    public struct Session: Decodable, Sendable {
        public let activeOrganizationId: String?
    }
    public let user: User
    public let session: Session
}

public struct AccountDeletionRequest: Decodable, Hashable, Sendable {
    public let id: String
    public let status: String
    public let createdAt: String?
}

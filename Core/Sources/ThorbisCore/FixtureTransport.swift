#if DEBUG
import Foundation

/// A synthetic in-memory Thorbis API for previews, UI tests and `--ui-fixture`
/// launches. Debug builds only: Release binaries never contain it.
/// It follows the real routes and status rules closely enough to exercise every
/// screen, but it is not evidence that production behaves the same way.
public actor FixtureTransport: HTTPTransport {
    public static let userId = "018f0000-0000-7000-8000-0000000000a1"
    public static let organizationId = "018f0000-0000-7000-8000-0000000000b1"

    private var jobs: [String: Job]
    private var customers: [String: Customer]
    private var contacts: [String: [CustomerContact]]
    private var locations: [String: [ServiceLocation]]
    private var notes: [String: [JobNote]]
    private var photos: [String: [JobPhoto]]
    private var estimates: [String: Estimate]
    private var invoices: [String: Invoice]
    private var notices: [StaffNotice]
    private var counter = 0
    private let now: Date
    public private(set) var requests: [HTTPRequest] = []

    public init(now: Date = Date()) {
        self.now = now
        let seed = FixtureSeed(now: now)
        jobs = Dictionary(uniqueKeysWithValues: seed.jobs.map { ($0.id, $0) })
        customers = Dictionary(uniqueKeysWithValues: seed.customers.map { ($0.id, $0) })
        contacts = seed.contacts
        locations = seed.locations
        notes = seed.notes
        photos = [:]
        estimates = Dictionary(uniqueKeysWithValues: seed.estimates.map { ($0.id, $0) })
        invoices = Dictionary(uniqueKeysWithValues: seed.invoices.map { ($0.id, $0) })
        notices = seed.notices
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        let segments = request.url.path.split(separator: "/").map(String.init)
        let ids = segments.filter(Self.isId)
        let route = "/" + segments.map { Self.isId($0) ? ":id" : $0 }.joined(separator: "/")
        let body = request.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        switch (request.method, route) {
        case ("POST", "/api/auth/sign-in/email"):
            guard (body["password"] as? String)?.isEmpty == false else {
                return problem(401, "Invalid email or password")
            }
            return HTTPResponse(status: 200, cookies: [ResponseCookie(name: "better-auth.session_token", value: "fixture-session")], body: json(["token": "fixture"]))
        case ("GET", "/api/auth/get-session"):
            return HTTPResponse(status: 200, body: json([
                "user": ["id": Self.userId, "name": "Mike Reyes", "email": "mike@example.com"],
                "session": ["activeOrganizationId": Self.organizationId],
            ]))
        case ("GET", "/api/auth/organization/list"):
            return HTTPResponse(status: 200, body: json([["id": Self.organizationId, "name": "Reyes Plumbing", "slug": "reyes"]]))
        case ("POST", "/api/auth/organization/set-active"), ("POST", "/api/auth/sign-out"):
            return HTTPResponse(status: 200, body: json(["success": true]))
        case ("GET", "/v1/me"):
            return HTTPResponse(status: 200, body: json(["me": ["account": ["id": Self.userId, "name": "Mike Reyes", "email": "mike@example.com"]]]))
        case ("GET", "/v1/jobs"):
            let customerId = query(request, "customerId")
            return page(jobs.values.filter { customerId == nil || $0.customerId == customerId }.sorted { $0.id > $1.id })
        case ("POST", "/v1/jobs"):
            guard let customerId = body["customerId"] as? String, customers[customerId] != nil,
                  let title = body["title"] as? String, !title.isEmpty
            else { return problem(400, "customerId and title are required") }
            let job = Job(id: nextId(), organizationId: Self.organizationId, customerId: customerId, title: title,
                          notes: body["notes"] as? String, status: .scheduled, createdAt: stamp(), updatedAt: stamp())
            jobs[job.id] = job
            return encode(job, status: 201)
        case ("GET", "/v1/jobs/:id"):
            let id = ids[0]
            guard let job = jobs[id] else { return problem(404, "job not found") }
            return encode(withTransitions(job))
        case ("POST", "/v1/jobs/:id/progress"):
            let id = ids[0]
            guard let job = jobs[id] else { return problem(404, "job not found") }
            guard let target = (body["to"] as? String).flatMap(JobStatus.init(rawValue:)),
                  JobWorkflow.fallbackTransitions(from: job.status).contains(target)
            else { return problem(409, "that status change is not allowed from \(job.status.rawValue)") }
            let pause = body["pause"] as? [String: Any]
            if target == .paused, (pause?["reason"] as? String)?.isEmpty != false {
                return problem(400, "a pause needs a reason and a next action")
            }
            let updated = moved(job, to: target, pauseReason: pause?["reason"] as? String, pauseNext: pause?["nextAction"] as? String)
            jobs[id] = updated
            return encode(updated)
        case ("POST", "/v1/jobs/:id/complete"):
            let id = ids[0]
            guard let job = jobs[id] else { return problem(404, "job not found") }
            guard JobWorkflow.fallbackTransitions(from: job.status).contains(.completed) else { return problem(409, "job is already closed") }
            let updated = moved(job, to: .completed)
            jobs[id] = updated
            return encode(updated)
        case ("POST", "/v1/jobs/:id/cancel"):
            let id = ids[0]
            guard let job = jobs[id] else { return problem(404, "job not found") }
            guard !job.status.isTerminal else { return problem(409, "job is already closed") }
            let updated = moved(job, to: .canceled)
            jobs[id] = updated
            return encode(updated)
        case ("POST", "/v1/jobs/:id/schedule"):
            let id = ids[0]
            guard let job = jobs[id] else { return problem(404, "job not found") }
            let updated = rebuilt(job, scheduledFor: body["scheduledFor"] as? String)
            jobs[id] = updated
            return encode(updated)
        case ("POST", "/v1/jobs/:id/assign"):
            let id = ids[0]
            guard let job = jobs[id] else { return problem(404, "job not found") }
            let updated = rebuilt(job, assignee: body["userId"] as? String)
            jobs[id] = updated
            return encode(updated)
        case ("GET", "/v1/jobs/:id/notes"):
            let id = ids[0]
            return encode(["items": notes[id, default: []]])
        case ("POST", "/v1/jobs/:id/notes"):
            let id = ids[0]
            guard let text = body["body"] as? String, !text.trimmingCharacters(in: .whitespaces).isEmpty else {
                return problem(400, "a note needs text")
            }
            let note = JobNote(id: nextId(), jobId: id, authorUserId: Self.userId, body: text, createdAt: stamp())
            notes[id, default: []].append(note)
            return encode(note, status: 201)
        case ("GET", "/v1/jobs/:id/photos"):
            let id = ids[0]
            return encode(["items": photos[id, default: []]])
        case ("POST", "/v1/jobs/:id/photos"):
            let id = ids[0]
            let photo = JobPhoto(id: nextId(), jobId: id, authorUserId: Self.userId,
                                 contentType: request.headers["content-type"] ?? "image/jpeg",
                                 byteSize: request.body?.count ?? 0, createdAt: stamp())
            photos[id, default: []].append(photo)
            return encode(photo, status: 201)
        case ("GET", "/v1/jobs/:id/photos/:id"):
            return HTTPResponse(status: 200, headers: ["content-type": "image/png"], body: Data())
        case ("POST", "/v1/jobs/:id/completion-invoice"):
            let id = ids[0]
            guard let job = jobs[id] else { return problem(404, "job not found") }
            if let existing = invoices.values.first(where: { $0.jobId == id }) { return encode(existing) }
            let invoice = Invoice(id: nextId(), customerId: job.customerId, jobId: id, status: .draft,
                                  lines: [DocumentLine(id: nextId(), description: job.title, quantity: 1, unitPrice: .usd(18_500))],
                                  createdAt: stamp(), updatedAt: stamp())
            invoices[invoice.id] = invoice
            return encode(invoice)
        case ("GET", "/v1/organization/assignees"):
            return page([Assignee(userId: Self.userId, displayName: "Mike Reyes"),
                         Assignee(userId: "018f0000-0000-7000-8000-0000000000a2", displayName: "Dana Ortiz")])
        case ("GET", "/v1/customers"):
            return page(customers.values.sorted { $0.id > $1.id })
        case ("POST", "/v1/customers"):
            guard let name = body["name"] as? String, !name.isEmpty else { return problem(400, "a customer needs a name") }
            let customer = Customer(id: nextId(), name: name, email: body["email"] as? String, phone: body["phone"] as? String,
                                    address: body["address"] as? String, createdAt: stamp(), updatedAt: stamp())
            customers[customer.id] = customer
            return encode(customer, status: 201)
        case ("GET", "/v1/customers/:id"):
            let id = ids[0]
            guard let customer = customers[id] else { return problem(404, "customer not found") }
            return encode(customer)
        case ("GET", "/v1/customers/:id/contacts"):
            let id = ids[0]
            return encode(["items": contacts[id, default: []]])
        case ("POST", "/v1/customers/:id/contacts"):
            let id = ids[0]
            let contact = CustomerContact(id: nextId(), customerId: id, name: body["name"] as? String ?? "",
                                          role: body["role"] as? String, email: body["email"] as? String,
                                          phone: body["phone"] as? String, primary: body["primary"] as? Bool ?? false)
            contacts[id, default: []].append(contact)
            return encode(contact, status: 201)
        case ("GET", "/v1/customers/:id/locations"):
            let id = ids[0]
            return encode(["items": locations[id, default: []]])
        case ("POST", "/v1/customers/:id/locations"):
            let id = ids[0]
            let location = ServiceLocation(id: nextId(), customerId: id, label: body["label"] as? String ?? "Home",
                                           kind: .service, address: body["address"] as? String ?? "",
                                           notes: body["notes"] as? String, gateCode: body["gateCode"] as? String)
            locations[id, default: []].append(location)
            return encode(location, status: 201)
        case ("GET", "/v1/estimates"):
            let customerId = query(request, "customerId")
            return page(estimates.values.filter { customerId == nil || $0.customerId == customerId }.sorted { $0.id > $1.id })
        case ("GET", "/v1/estimates/:id"):
            let id = ids[0]
            guard let estimate = estimates[id] else { return problem(404, "estimate not found") }
            return encode(estimate)
        case ("POST", "/v1/estimates/:id/send"), ("POST", "/v1/estimates/:id/approve"), ("POST", "/v1/estimates/:id/decline"):
            let id = ids[0]
            let action = segments.last ?? ""
            guard let estimate = estimates[id] else { return problem(404, "estimate not found") }
            let status: EstimateStatus = switch action { case "send": .sent; case "approve": .approved; default: .declined }
            let updated = Estimate(id: estimate.id, customerId: estimate.customerId, status: status,
                                   currentRevisionNumber: max(estimate.currentRevisionNumber ?? 0, 1), title: estimate.title,
                                   lines: estimate.lines, createdAt: estimate.createdAt, updatedAt: stamp(),
                                   sentAt: status == .sent ? stamp() : estimate.sentAt,
                                   approvedAt: status == .approved ? stamp() : nil, declinedAt: status == .declined ? stamp() : nil)
            estimates[id] = updated
            return encode(updated)
        case ("GET", "/v1/invoices"):
            let customerId = query(request, "customerId")
            return page(invoices.values.filter { customerId == nil || $0.customerId == customerId }.sorted { $0.id > $1.id })
        case ("GET", "/v1/invoices/:id"):
            let id = ids[0]
            guard let invoice = invoices[id] else { return problem(404, "invoice not found") }
            return encode(invoice)
        case ("POST", "/v1/invoices/:id/issue"):
            let id = ids[0]
            guard let invoice = invoices[id] else { return problem(404, "invoice not found") }
            guard invoice.status == .draft else { return problem(409, "only a draft can be issued") }
            let updated = Invoice(id: invoice.id, customerId: invoice.customerId, jobId: invoice.jobId, status: .issued,
                                  lines: invoice.lines, linesRevision: invoice.linesRevision, amountPaid: invoice.amountPaid,
                                  issuedAt: stamp(), createdAt: invoice.createdAt, updatedAt: stamp())
            invoices[id] = updated
            return encode(updated)
        case ("GET", "/v1/invoices/:id/payments"):
            return page([Payment]())
        case ("GET", "/v1/staff/notices"):
            return encode(["items": notices])
        case ("POST", "/v1/staff/notices/read"):
            notices = notices.map { StaffNotice(id: $0.id, jobId: $0.jobId, title: $0.title, meta: $0.meta, at: $0.at, read: true) }
            return HTTPResponse(status: 200, body: json(["read": true, "marked": notices.count]))
        case ("GET", "/v1/search"):
            let text = (query(request, "q") ?? "").lowercased()
            var results: [SearchResult] = []
            results += jobs.values.filter { $0.title.lowercased().contains(text) }.map {
                SearchResult(resultType: "job", entityId: $0.id, title: $0.title, subtitle: customers[$0.customerId]?.name, status: $0.status.rawValue)
            }
            results += customers.values.filter { $0.name.lowercased().contains(text) }.map {
                SearchResult(resultType: "customer", entityId: $0.id, title: $0.name, subtitle: $0.address)
            }
            return encode(["items": results.sorted { $0.title < $1.title }])
        case ("POST", "/v1/account-lifecycle/deletion-requests"):
            return problem(409, "recent reauthentication is required")
        case ("GET", "/v1/account-lifecycle/deletion-requests/current"):
            return problem(404, "account lifecycle request not found")
        default:
            return problem(404, "no fixture route for \(request.method) \(request.url.path)")
        }
    }

    // MARK: helpers

    private static func isId(_ segment: String) -> Bool {
        segment.count == 36 && segment.filter { $0 == "-" }.count == 4
    }

    private func nextId() -> String {
        counter += 1
        return fixtureId(900_000 + counter)
    }

    private func stamp() -> String { Timestamp.string(now) }

    private func query(_ request: HTTPRequest, _ name: String) -> String? {
        URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }

    private func withTransitions(_ job: Job) -> Job {
        rebuilt(job, transitions: JobWorkflow.fallbackTransitions(from: job.status))
    }

    private func moved(_ job: Job, to status: JobStatus, pauseReason: String? = nil, pauseNext: String? = nil) -> Job {
        let at = stamp()
        return Job(
            id: job.id, organizationId: job.organizationId, customerId: job.customerId, title: job.title, notes: job.notes,
            status: status, assignedToUserId: job.assignedToUserId, scheduledFor: job.scheduledFor,
            createdAt: job.createdAt, updatedAt: at,
            dispatchedAt: status == .dispatched ? at : job.dispatchedAt, enRouteAt: status == .enRoute ? at : job.enRouteAt,
            arrivedAt: status == .arrived ? at : job.arrivedAt, startedAt: status == .inProgress && job.startedAt == nil ? at : job.startedAt,
            pausedAt: status == .paused ? at : nil, pauseReason: status == .paused ? pauseReason : nil,
            pauseNextAction: status == .paused ? pauseNext : nil,
            pauseCycleAuditId: status == .paused ? nextId() : job.pauseCycleAuditId,
            completedAt: status == .completed ? at : nil, canceledAt: status == .canceled ? at : nil,
            estimateId: job.estimateId, locationId: job.locationId
        )
    }

    private func rebuilt(_ job: Job, scheduledFor: String? = nil, assignee: String? = nil, transitions: [JobStatus]? = nil) -> Job {
        Job(
            id: job.id, organizationId: job.organizationId, customerId: job.customerId, title: job.title, notes: job.notes,
            status: job.status, assignedToUserId: assignee ?? job.assignedToUserId, scheduledFor: scheduledFor ?? job.scheduledFor,
            createdAt: job.createdAt, updatedAt: transitions == nil ? stamp() : job.updatedAt,
            dispatchedAt: job.dispatchedAt, enRouteAt: job.enRouteAt, arrivedAt: job.arrivedAt, startedAt: job.startedAt,
            pausedAt: job.pausedAt, pauseReason: job.pauseReason, pauseNextAction: job.pauseNextAction,
            pauseCycleAuditId: job.pauseCycleAuditId, completedAt: job.completedAt, canceledAt: job.canceledAt,
            estimateId: job.estimateId, locationId: job.locationId, allowedTransitions: transitions
        )
    }

    private func page<T: Encodable>(_ items: [T]) -> HTTPResponse { encode(["items": items]) }

    private func encode<T: Encodable>(_ value: T, status: Int = 200) -> HTTPResponse {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return HTTPResponse(status: status, headers: ["content-type": "application/json"], body: (try? encoder.encode(value)) ?? Data())
    }

    private func json(_ value: Any) -> Data { (try? JSONSerialization.data(withJSONObject: value)) ?? Data() }

    private func problem(_ status: Int, _ detail: String) -> HTTPResponse {
        HTTPResponse(status: status, headers: ["content-type": "application/problem+json"],
                     body: json(["type": "https://thorbis.com/problems/fixture", "title": "fixture", "status": status, "detail": detail]))
    }
}

/// UUID-shaped ids that sort by creation order, like the server's UUIDv7s.
func fixtureId(_ n: Int) -> String {
    let digits = String(n)
    return "018f0000-0000-7000-8000-" + String(repeating: "0", count: max(0, 12 - digits.count)) + digits
}

/// Synthetic records. Names and addresses are invented.
struct FixtureSeed {
    let jobs: [Job]
    let customers: [Customer]
    let contacts: [String: [CustomerContact]]
    let locations: [String: [ServiceLocation]]
    let notes: [String: [JobNote]]
    let estimates: [Estimate]
    let invoices: [Invoice]
    let notices: [StaffNotice]

    init(now: Date) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        func at(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> String {
            let day = calendar.date(byAdding: .day, value: dayOffset, to: today) ?? today
            return Timestamp.string(calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day)
        }
        let created = at(-3, 9)
        let me = FixtureTransport.userId
        func id(_ n: Int) -> String { fixtureId(n) }

        customers = [
            Customer(id: id(101), name: "Alvarez Residence", email: "ana.alvarez@example.com", phone: "(555) 010-2201",
                     address: "1420 Juniper Ave, Austin, TX", accountType: "residential", preferredContact: .sms, createdAt: created),
            Customer(id: id(102), name: "Brightside Dental", email: "office@brightside.example", phone: "(555) 010-4410",
                     address: "88 Commerce St, Austin, TX", accountType: "commercial", preferredContact: .email,
                     billingTerms: "net_30", createdAt: created),
            Customer(id: id(103), name: "Chen Family", phone: "(555) 010-7781", address: "5 Elm Ct, Round Rock, TX",
                     accountType: "residential", preferredContact: .phone, createdAt: created),
            Customer(id: id(104), name: "Okafor Bakery", email: "hello@okafor.example", address: "301 Main St, Austin, TX",
                     accountType: "commercial", createdAt: created),
        ]
        jobs = [
            Job(id: id(201), customerId: id(101), title: "Water heater replacement", notes: "50 gal gas, garage. Old unit leaking at the base.",
                status: .enRoute, assignedToUserId: me, scheduledFor: at(0, 9), createdAt: created, updatedAt: at(0, 8, 40),
                dispatchedAt: at(0, 8, 15), enRouteAt: at(0, 8, 40), locationId: id(401)),
            Job(id: id(202), customerId: id(102), title: "Backflow test", status: .scheduled, assignedToUserId: me,
                scheduledFor: at(0, 13, 30), createdAt: created, updatedAt: created, locationId: id(402)),
            Job(id: id(203), customerId: id(103), title: "Kitchen drain clog", status: .scheduled, assignedToUserId: me,
                scheduledFor: at(1, 10), createdAt: created, updatedAt: created),
            Job(id: id(204), customerId: id(104), title: "Grease trap service", status: .paused, assignedToUserId: me,
                scheduledFor: at(-1, 15), createdAt: created, updatedAt: at(-1, 16),
                startedAt: at(-1, 15, 10), pausedAt: at(-1, 16), pauseReason: "Waiting on replacement baffle",
                pauseNextAction: "Pick up part from supplier", pauseCycleAuditId: id(901)),
            Job(id: id(205), customerId: id(101), title: "Annual plumbing inspection", status: .completed, assignedToUserId: me,
                scheduledFor: at(-20, 11), createdAt: at(-25, 9), updatedAt: at(-20, 12), completedAt: at(-20, 12)),
            Job(id: id(206), customerId: id(103), title: "Estimate: repipe master bath", status: .scheduled,
                createdAt: created, updatedAt: at(-1, 10)),
        ]
        contacts = [
            id(101): [CustomerContact(id: id(301), customerId: id(101), name: "Ana Alvarez", role: "Owner",
                                      email: "ana.alvarez@example.com", phone: "(555) 010-2201", primary: true)],
            id(102): [CustomerContact(id: id(302), customerId: id(102), name: "Priya Nair", role: "Office manager",
                                      email: "office@brightside.example", phone: "(555) 010-4410", primary: true)],
        ]
        locations = [
            id(101): [ServiceLocation(id: id(401), customerId: id(101), label: "Home", kind: .service,
                                      address: "1420 Juniper Ave, Austin, TX", notes: "Side gate is unlocked on weekdays.",
                                      gateCode: "4417", dogOnSite: "Friendly lab, kept inside", parking: "Driveway")],
            id(102): [ServiceLocation(id: id(402), customerId: id(102), label: "Clinic", kind: .service,
                                      address: "88 Commerce St, Austin, TX", parking: "Rear lot, spot 4")],
        ]
        notes = [
            id(201): [JobNote(id: id(501), jobId: id(201), authorUserId: me, body: "Customer confirmed by text. Shutoff valve is behind the unit.", createdAt: at(0, 8))],
        ]
        estimates = [
            Estimate(id: id(601), customerId: id(103), status: .draft, title: "Repipe master bath",
                     lines: [DocumentLine(id: id(611), description: "PEX repipe, master bath", quantity: 1, unitPrice: .usd(240_000)),
                             DocumentLine(id: id(612), description: "Drywall patch", quantity: 3, unitPrice: .usd(12_500))],
                     createdAt: created, updatedAt: created),
            Estimate(id: id(602), customerId: id(101), status: .sent, currentRevisionNumber: 1, title: "Water heater replacement",
                     lines: [DocumentLine(id: id(621), description: "50 gal gas water heater, installed", quantity: 1, unitPrice: .usd(185_000))],
                     createdAt: at(-5, 9), updatedAt: at(-4, 9), sentAt: at(-4, 9)),
        ]
        invoices = [
            Invoice(id: id(701), customerId: id(101), jobId: id(205), status: .paid,
                    lines: [DocumentLine(id: id(711), description: "Annual inspection", quantity: 1, unitPrice: .usd(14_900))],
                    amountPaid: 14_900, issuedAt: at(-20, 12), paidAt: at(-19, 9), createdAt: at(-20, 12), updatedAt: at(-19, 9)),
            Invoice(id: id(702), customerId: id(102), status: .issued,
                    lines: [DocumentLine(id: id(721), description: "Backflow test, 2 devices", quantity: 2, unitPrice: .usd(9_500))],
                    issuedAt: at(-2, 12), createdAt: at(-2, 12), updatedAt: at(-2, 12)),
        ]
        notices = [
            StaffNotice(id: id(801), jobId: id(201), title: "Ana Alvarez confirmed the appointment", meta: "Water heater replacement", at: at(0, 8), read: false),
            StaffNotice(id: id(802), jobId: id(202), title: "New job assigned to you", meta: "Backflow test · Brightside Dental", at: at(-1, 17), read: true),
        ]
    }
}
#endif

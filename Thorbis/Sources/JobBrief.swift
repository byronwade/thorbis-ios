import SwiftUI
import UIKit

// Everything a technician reads on the job's Overview (design.thorbis.com/job-screen, JS-01..JS-14),
// and the one top-right menu that holds every action the bar isn't carrying (JS-02, JS-03).

/// An action in the job's ••• menu.
enum JobMenuAction: Hashable {
    case transition(String)
    case schedule
    case addToCalendar
    case assign
    case billWithoutEstimate
    case deposit
    case wrapUp
    case followUps
    /// Customer view: the job's estimates, invoices and the customer's own details, in customer mode.
    case customerView
    case email
    case copyID
    /// Paper 21R: text the customer a new arrival time from the tech's own phone.
    case runningLate
    /// Paper F3A: arrived but can't start — tell the office why, as a follow-up on the job.
    case cantStart
}

/// JS-02/JS-03: the job's menu, grouped visit, money, finish, record. Only what this person can do
/// now; the bar's step is never repeated; empty groups are dropped, so no menu is ever a lone item
/// behind a divider and an empty menu means no ••• at all.
enum JobMenu {
    struct Inputs: Equatable {
        /// Status moves this role may make, already without the one the bar carries.
        var transitions: [String] = []
        var canSchedule = false
        var canAssign = false
        var canBillWithoutEstimate = false
        var canRequestDeposit = false
        /// Wrap up is in the bar once the money is settled (TF-09); then it leaves the menu.
        var barIsWrapUp = false
        var canWrapUp = true
        var canShowToCustomer = false
        var canEditCustomer = false
        /// The visit has a time, so it can go on the person's own calendar.
        var canAddToCalendar = false
        /// A verified customer or contact email is loaded.
        var canEmail = false
        /// Booked and not there yet (scheduled, dispatched or on the way).
        var canSendRunningLate = false
        /// Arrived, and this person may edit the job.
        var canReportCantStart = false
    }

    static func groups(_ inputs: Inputs) -> [[JobMenuAction]] {
        // Pause reads last in the visit group: forward moves first, the stop after them.
        let moves = inputs.transitions.filter { $0 != "paused" }.map(JobMenuAction.transition)
            + (inputs.transitions.contains("paused") ? [.transition("paused")] : [])
        var visit: [JobMenuAction] = []
        if inputs.canReportCantStart { visit.append(.cantStart) }
        if inputs.canSendRunningLate { visit.append(.runningLate) }
        visit += moves
        if inputs.canSchedule { visit.append(.schedule) }
        if inputs.canAddToCalendar { visit.append(.addToCalendar) }
        if inputs.canAssign { visit.append(.assign) }
        var money: [JobMenuAction] = []
        if inputs.canBillWithoutEstimate { money.append(.billWithoutEstimate) }
        if inputs.canRequestDeposit { money.append(.deposit) }
        var finish: [JobMenuAction] = []
        if inputs.canWrapUp, !inputs.barIsWrapUp { finish.append(.wrapUp) }
        finish.append(.followUps)
        var record: [JobMenuAction] = []
        if inputs.canShowToCustomer || inputs.canEditCustomer { record.append(.customerView) }
        if inputs.canEmail { record.append(.email) }
        record.append(.copyID)
        return [visit, money, finish, record].filter { !$0.isEmpty }
    }
}

/// One of the customer's other visits, read through this job (GET /v1/jobs/{id}/visit-history).
struct JobVisitRecord: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let status: String
    let notes: String?
    let assignedToUserId: String?
    let scheduledFor: String?
    let completedAt: String?
    let canceledAt: String?
    let createdAt: String

    /// When it happened, or would: finished, then booked, then opened (same order as the server).
    var when: Date? {
        JobFiltering.date(completedAt) ?? JobFiltering.date(canceledAt) ?? JobFiltering.date(scheduledFor) ?? JobFiltering.date(createdAt)
    }
}

private struct JobVisitPage: Decodable { let items: [JobVisitRecord] }

@MainActor
extension APIClient {
    func fieldVisitHistory(_ jobID: String) async throws -> [JobVisitRecord] {
        guard UUID(uuidString: jobID) != nil else { throw Problem(title: "Invalid job ID", status: nil, detail: jobID) }
        let page: JobVisitPage = try await send("GET", "/v1/jobs/\(jobID)/visit-history")
        return page.items
    }
}

/// How a person is reached: one tap per channel (JS-06).
struct JobReach: Equatable {
    let call: URL?
    let text: URL?
    let email: URL?

    init(phone: String?, email: String?) {
        let digits = phone.map { $0.filter { $0.isNumber || $0 == "+" } }.flatMap { $0.count >= 7 ? $0 : nil }
        call = digits.flatMap { URL(string: "tel:\($0)") }
        text = digits.flatMap { URL(string: "sms:\($0)") }
        let address = email?.trimmingCharacters(in: .whitespaces)
        self.email = address.flatMap { $0.contains("@") ? URL(string: "mailto:\($0)") : nil }
    }

    var isEmpty: Bool { call == nil && email == nil }
}

/// The people on the account, primary first, then by name; the customer itself when no contact exists.
enum JobContacts {
    struct Person: Identifiable, Equatable {
        let id: String
        let name: String
        let detail: String?
        let phone: String?
        let email: String?
        /// The account's primary contact: its initials wear the brand tone (Paper 21).
        var primary = false
        var reach: JobReach { JobReach(phone: phone, email: email) }
    }

    static func people(contacts: [CustomerContactRecord], customer: CustomerRecord?) -> [Person] {
        let sorted = contacts.sorted { lhs, rhs in
            if lhs.primary != rhs.primary { return lhs.primary }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        var people = sorted.map { contact in
            let detail = [contact.role, contact.primary ? "Primary" : nil].compactMap { $0 }.joined(separator: " · ")
            return Person(id: contact.id, name: contact.name, detail: detail.isEmpty ? nil : detail,
                          phone: contact.phone, email: contact.email, primary: contact.primary)
        }
        // The account's own number is the fallback, never a second copy of a contact's.
        if let customer, people.allSatisfy({ $0.reach.isEmpty }),
           !JobReach(phone: customer.phone, email: customer.email).isEmpty {
            people.insert(Person(id: "customer-\(customer.id)", name: customer.name, detail: "Account",
                                 phone: customer.phone, email: customer.email), at: 0)
        }
        return people
    }

    /// "Prefers text" from the account's preferred channel.
    static func preference(_ customer: CustomerRecord?) -> String? {
        switch customer?.preferredContact {
        case "sms": "Prefers text"
        case "phone": "Prefers a call"
        case "email": "Prefers email"
        default: nil
        }
    }
}

/// JS-06: every contact with its own Call, Text and Email.
struct JobContactsSection: View {
    let people: [JobContacts.Person]
    let preference: String?
    let loaded: Bool
    let failed: Bool
    /// When known, each real contact opens its own record; the account fallback never does.
    var customerID: String? = nil
    /// The account's name as the job already shows it: a contact with the same name leads with
    /// its role instead of repeating the name (each fact once).
    var customerName: String? = nil
    /// Paper 21 / 26A: the plus beside the label adds a contact. Nil when this person can't.
    var onAdd: (() -> Void)? = nil
    let retry: () async -> Void

    var body: some View {
        // Paper 21: 8 between the label and its card.
        VStack(alignment: .leading, spacing: 8) {
            JobPanelLabel(title: "Contacts", count: people.isEmpty ? nil : "\(people.count)",
                          actionTitle: onAdd == nil ? nil : "Add contact", actionSymbol: "plus",
                          actionIdentifier: "job-contacts-add", action: onAdd)
            if failed && people.isEmpty {
                // JS-11: the section says what didn't load and offers one Try again; the job still shows.
                HStack(spacing: 8) {
                    ListErrorRow(message: "Contacts didn't load.")
                    Spacer(minLength: 8)
                    Button("Try again") { Task { await retry() } }
                        .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                        .frame(minHeight: 44)
                }
            } else if !loaded {
                SkeletonRows(count: 1, leading: false, inset: 0)
            } else if people.isEmpty {
                Text("No phone or email on file for this customer.")
                    .font(Theme.font(15)).foregroundStyle(Theme.muted).frame(minHeight: 44)
                    .padding(.horizontal, 4)
            }
            if !people.isEmpty {
                // Paper 21: one card, a 64pt row per person, the hairline between rows starting at the words.
                JobPanel(dividers: false) {
                    if let preference {
                        Text(preference).font(Theme.font(13)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 16).padding(.top, 10)
                    }
                    ForEach(people) { person in
                        JobContactRow(person: person, divided: person.id != people.first?.id,
                                      route: customerID.flatMap { id in
                                          person.id.hasPrefix("customer-") ? nil : PaperRoute.contact(customerID: id, contactID: person.id)
                                      })
                    }
                }
            }
        }
    }
}

/// Paper 21 / 26: a person on the job. Initials on a 36pt circle (the primary contact's in the
/// brand tone), the name at 16 Medium over the role at 14, then Call and Text as 44pt circles.
private struct JobContactRow: View {
    let person: JobContacts.Person
    /// A hairline above the row's words (every row but the first).
    var divided = false
    var route: PaperRoute? = nil
    @Environment(\.openURL) private var openURL
    @Environment(\.inboxText) private var inboxText

    var body: some View {
        let reach = person.reach
        HStack(spacing: 12) {
            Text(initials(person.name))
                .font(Theme.font(13, weight: .semibold))
                .foregroundStyle(person.primary ? Theme.brandText : Theme.subtle)
                .frame(width: 36, height: 36)
                .background(person.primary ? Theme.brandSurface : Theme.fill, in: Circle())
                .dynamicTypeSize(...DynamicTypeSize.large)
                .accessibilityHidden(true)
            HStack(spacing: 8) {
                // Only the words open the contact; Call and Text stay their own buttons.
                if let route {
                    NavigationLink(value: route) {
                        info
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                    .accessibilityHint("Opens the contact")
                } else {
                    info.frame(maxWidth: .infinity, alignment: .leading)
                }
                if let call = reach.call { glyph("phone", label: "Call \(person.name)") { openURL(call) } }
                if let text = reach.text { glyph("message", label: "Text \(person.name)") { inboxText(text, name: person.name, openURL: openURL) } }
                // Paper draws Call and Text; Email takes their place for a contact with no number.
                if reach.call == nil, let email = reach.email { glyph("envelope", label: "Email \(person.name)") { openURL(email) } }
            }
            .padding(.trailing, 12).padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .overlay(alignment: .top) {
                if divided { Rectangle().fill(Theme.hairline).frame(height: 1).accessibilityHidden(true) }
            }
        }
        .padding(.leading, 16)
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(person.name).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = person.detail {
                Text(detail).font(Theme.font(14)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        // One spoken line, the name included even where the screen leaves it out.
        .accessibilityLabel([person.name, person.detail, person.phone?.isEmpty == false ? person.phone : person.email]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "))
    }

    private func glyph(_ symbol: String, label: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            // Paper: an 18pt line glyph on a 44pt fill circle.
            Image(systemName: symbol).font(.system(size: 17, weight: .regular)).foregroundStyle(Theme.foreground)
                .frame(width: 44, height: 44)
                .background(Theme.fill, in: Circle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }
}

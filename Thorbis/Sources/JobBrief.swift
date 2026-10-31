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
    }

    static func groups(_ inputs: Inputs) -> [[JobMenuAction]] {
        // Pause reads last in the visit group: forward moves first, the stop after them.
        let moves = inputs.transitions.filter { $0 != "paused" }.map(JobMenuAction.transition)
            + (inputs.transitions.contains("paused") ? [.transition("paused")] : [])
        var visit = moves
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
                          phone: contact.phone, email: contact.email)
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
    let retry: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            JobPanelLabel(title: "Contacts", count: people.isEmpty ? nil : "\(people.count)")
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
                JobPanel {
                    if let preference {
                        Text(preference).font(Theme.font(13)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 16).padding(.top, 10)
                            .jobPanelJoinsNext()
                    }
                    ForEach(people) { person in
                        JobContactRow(person: person,
                                      route: customerID.flatMap { id in
                                          person.id.hasPrefix("customer-") ? nil : PaperRoute.contact(customerID: id, contactID: person.id)
                                      })
                            .padding(.horizontal, 16)
                    }
                }
            }
        }
    }
}

private struct JobContactRow: View {
    let person: JobContacts.Person
    var route: PaperRoute? = nil
    @Environment(\.openURL) private var openURL

    var body: some View {
        let reach = person.reach
        HStack(spacing: 8) {
            // Only the words open the contact; Call, Text and Email stay their own buttons.
            if let route {
                NavigationLink(value: route) {
                    HStack(spacing: 6) {
                        info
                        Spacer(minLength: 4)
                        PaperDisclosure()
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
                .accessibilityHint("Opens the contact")
            } else {
                info
                Spacer(minLength: 8)
            }
            if let call = reach.call { glyph("phone", label: "Call \(person.name)") { openURL(call) } }
            if let text = reach.text { glyph("message", label: "Text \(person.name)") { openURL(text) } }
            if let email = reach.email { glyph("envelope", label: "Email \(person.name)") { openURL(email) } }
        }
        .padding(.vertical, 6)
        .frame(minHeight: 56)
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(person.name).font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = person.detail {
                Text(detail).font(Theme.font(13)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            if let phone = person.phone, !phone.isEmpty {
                Text(phone).font(Theme.monoFont(13)).foregroundStyle(Theme.muted)
            } else if let email = person.email, !email.isEmpty {
                Text(email).font(Theme.font(13)).foregroundStyle(Theme.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func glyph(_ symbol: String, label: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: symbol).font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.foreground)
                .frame(width: 44, height: 44)
                .background(Theme.fill, in: Circle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }
}

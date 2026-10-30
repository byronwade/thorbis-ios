import SwiftUI
import UIKit

// Everything a technician reads on the job's Overview (design.thorbis.com/job-screen, JS-01..JS-14),
// and the one top-right menu that holds every action the bar isn't carrying (JS-02, JS-03).

/// An action in the job's ••• menu.
enum JobMenuAction: Hashable {
    case transition(String)
    case schedule
    case assign
    case billWithoutEstimate
    case deposit
    case wrapUp
    case followUps
    case showToCustomer
    case customerDetails
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
    }

    static func groups(_ inputs: Inputs) -> [[JobMenuAction]] {
        // Pause reads last in the visit group: forward moves first, the stop after them.
        let moves = inputs.transitions.filter { $0 != "paused" }.map(JobMenuAction.transition)
            + (inputs.transitions.contains("paused") ? [.transition("paused")] : [])
        var visit = moves
        if inputs.canSchedule { visit.append(.schedule) }
        if inputs.canAssign { visit.append(.assign) }
        var money: [JobMenuAction] = []
        if inputs.canBillWithoutEstimate { money.append(.billWithoutEstimate) }
        if inputs.canRequestDeposit { money.append(.deposit) }
        var finish: [JobMenuAction] = []
        if inputs.canWrapUp, !inputs.barIsWrapUp { finish.append(.wrapUp) }
        finish.append(.followUps)
        var record: [JobMenuAction] = []
        if inputs.canShowToCustomer { record.append(.showToCustomer) }
        if inputs.canEditCustomer { record.append(.customerDetails) }
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

/// JS-04: the dispatch summary, quoted, with the pause reason above it when paused.
struct JobOfficeNote: View {
    let notes: String?
    let pauseReason: String?
    let pauseNextAction: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if pauseReason != nil || pauseNextAction != nil {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Paused", systemImage: "pause.circle")
                        .font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.warning)
                    if let pauseReason { Text(pauseReason).font(Theme.font(15)) }
                    if let pauseNextAction {
                        Text("Next: \(pauseNextAction)").font(Theme.font(15)).foregroundStyle(Theme.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Theme.warningSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .accessibilityElement(children: .combine)
            }
            if let notes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    PaperGroupHeader(title: "From the office")
                    Text(notes)
                        .font(Theme.font(15)).lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(14)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).stroke(Theme.border))
                }
            }
        }
    }
}

/// JS-06: every contact with its own Call, Text and Email.
struct JobContactsSection: View {
    let people: [JobContacts.Person]
    let preference: String?
    let loaded: Bool
    let failed: Bool
    let retry: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaperGroupHeader(title: "Contacts", count: people.count) {
                if let preference { Text(preference).font(Theme.font(13)).foregroundStyle(Theme.muted) }
            }
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
            }
            ForEach(people) { person in
                JobContactRow(person: person)
            }
        }
    }
}

private struct JobContactRow: View {
    let person: JobContacts.Person
    @Environment(\.openURL) private var openURL

    var body: some View {
        let reach = person.reach
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name).font(Theme.font(15, weight: .medium))
                if let detail = person.detail { Text(detail).font(Theme.font(13)).foregroundStyle(Theme.muted) }
                if let phone = person.phone, !phone.isEmpty {
                    Text(phone).font(Theme.monoFont(13)).foregroundStyle(Theme.muted).textSelection(.enabled)
                } else if let email = person.email, !email.isEmpty {
                    Text(email).font(Theme.font(13)).foregroundStyle(Theme.muted).textSelection(.enabled)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            if let call = reach.call { glyph("phone", label: "Call \(person.name)") { openURL(call) } }
            if let text = reach.text { glyph("message", label: "Text \(person.name)") { openURL(text) } }
            if let email = reach.email { glyph("envelope", label: "Email \(person.name)") { openURL(email) } }
        }
        .padding(.vertical, 6)
        .frame(minHeight: 56)
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

/// JS-07: the address, then each access fact on its own row; codes in mono, copied with a long press.
struct JobSiteSection: View {
    let place: ServiceLocationRecord
    let showsLabel: Bool
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaperGroupHeader(title: "Getting in")
            Button {
                if let url = Directions.url(address: place.address, coordinates: place.coordinates) { openURL(url) }
            } label: {
                PaperDetailRow(label: showsLabel ? place.label : "Address") {
                    HStack(spacing: 4) {
                        Text(place.address).foregroundStyle(Theme.brandText)
                        Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.brandText)
                    }
                }
            }
            .buttonStyle(PressStyle())
            .accessibilityHint("Opens driving directions in Maps")
            if let gate = place.gateCode { code("Gate code", gate) }
            if let alarm = place.alarmCode { code("Alarm code", alarm) }
            if let dog = place.dogOnSite { PaperDetailRow("Dog", value: dog) }
            if let parking = place.parking { PaperDetailRow("Parking", value: parking) }
            if let notes = place.notes, !notes.isEmpty { PaperDetailRow("Site notes", value: notes) }
        }
    }

    private func code(_ label: String, _ value: String) -> some View {
        PaperDetailRow(label: label) { Text(value).font(Theme.monoFont(15, weight: .medium)) }
            .contentShape(Rectangle())
            .contextMenu {
                Button("Copy \(label.lowercased())", systemImage: "doc.on.doc") { UIPasteboard.general.string = value }
            }
            .accessibilityHint("Touch and hold to copy")
    }
}

/// JS-09: what's been done on this visit, as counts that open their place.
struct JobVisitCounts: View {
    let latestNote: String?
    let noteCount: Int
    let photoCount: String?
    let openFollowUps: Int?
    let openNotes: () -> Void
    let openPhotos: () -> Void
    let openFollowUpsScreen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaperGroupHeader(title: "On this visit")
            Button(action: openNotes) {
                PaperMenuRow("Notes", symbol: "text.bubble", subtitle: latestNote.map { "“\($0)”" }, value: "\(noteCount)")
            }
            .buttonStyle(RowPressStyle())
            Button(action: openPhotos) {
                PaperMenuRow("Photos", symbol: "photo.on.rectangle", value: photoCount)
            }
            .buttonStyle(RowPressStyle())
            Button(action: openFollowUpsScreen) {
                PaperMenuRow("Follow-ups", symbol: "list.bullet",
                             subtitle: (openFollowUps ?? 0) > 0 ? "Waiting on the office" : nil,
                             value: openFollowUps.map(String.init))
            }
            .buttonStyle(RowPressStyle())
        }
    }
}

/// JS-10: the customer's other visits, newest first, with what the office wrote.
struct JobPastVisitsSection: View {
    let visits: [JobVisitRecord]
    let currentUserID: String?

    var body: some View {
        if !visits.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                PaperGroupHeader(title: "Past visits", count: visits.count)
                ForEach(visits) { visit in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(visit.title).font(Theme.font(15, weight: .medium)).lineLimit(2)
                            Spacer(minLength: 8)
                            if let when = visit.when {
                                Text(when.formatted(.dateTime.month(.abbreviated).day().year()))
                                    .font(Theme.monoFont(12)).foregroundStyle(Theme.muted)
                            }
                        }
                        Text(byline(visit)).font(Theme.font(13)).foregroundStyle(Theme.muted)
                        if let notes = visit.notes, !notes.isEmpty {
                            Text(notes).font(Theme.font(13)).foregroundStyle(Theme.foreground).lineLimit(2)
                        }
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func byline(_ visit: JobVisitRecord) -> String {
        var parts = [visit.status.statusLabel]
        if let assignee = visit.assignedToUserId { parts.append(assignee == currentUserID ? "You" : "Another tech") }
        return parts.joined(separator: " · ")
    }
}

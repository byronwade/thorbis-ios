import Contacts
import ContactsUI
import EventKit
import EventKitUI
import MessageUI
import SwiftUI
import UIKit

// Calendar, Contacts and Mail hand-offs. Each one opens Apple's own sheet so the person reviews
// and saves or sends it themselves; nothing leaves the device except through their own action.

/// A calendar event for one scheduled visit, reviewed in the system editor before it is saved.
struct JobCalendarDraft: Equatable {
    static let defaultDuration: TimeInterval = 60 * 60

    var title: String
    var location: String?
    var start: Date
    var end: Date
    var notes: String

    /// The short job reference people already see on the lock screen.
    static func jobNumber(_ jobID: String) -> String { "JOB-\(jobID.suffix(4).uppercased())" }

    /// Nil when the job has no valid scheduled time. The location is only the job's own verified
    /// service location; no site is inferred from the customer's other addresses.
    static func make(job: JobRecord, customerName: String?, locations: [ServiceLocationRecord]) -> JobCalendarDraft? {
        guard let start = JobFiltering.date(job.scheduledFor) else { return nil }
        let place = job.locationId.flatMap { id in
            locations.first { $0.id == id && $0.customerId == job.customerId && $0.organizationId == job.organizationId }
        }
        let address = place?.address.trimmingCharacters(in: .whitespacesAndNewlines)
        let customer = customerName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = [customer?.isEmpty == false ? customer : nil, jobNumber(job.id)].compactMap { $0 }.joined(separator: "\n")
        return JobCalendarDraft(title: job.title, location: address?.isEmpty == false ? address : nil,
                                start: start, end: start.addingTimeInterval(defaultDuration), notes: notes)
    }

    func event(in store: EKEventStore) -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.title = title
        event.location = location
        event.startDate = start
        event.endDate = end
        event.notes = notes
        return event
    }
}

/// A contact card prefilled from a customer or one of their contacts, for the system card.
struct ContactCardDraft: Equatable {
    var givenName = ""
    var familyName = ""
    var organization: String?
    var jobTitle: String?
    var phone: String?
    var email: String?
    var address: String?

    static func make(customer: CustomerRecord) -> ContactCardDraft {
        var draft = ContactCardDraft()
        let name = customer.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if customer.accountType == "commercial" {
            draft.organization = name
        } else {
            (draft.givenName, draft.familyName) = split(name)
        }
        draft.phone = clean(customer.phone)
        draft.email = clean(customer.email)
        draft.address = clean(customer.address)
        return draft
    }

    static func make(contact: CustomerContactRecord, customerName: String?, address: String?) -> ContactCardDraft {
        var draft = ContactCardDraft()
        (draft.givenName, draft.familyName) = split(contact.name.trimmingCharacters(in: .whitespacesAndNewlines))
        let company = clean(customerName)
        draft.organization = company == draft.fullName ? nil : company
        draft.jobTitle = clean(contact.role)
        draft.phone = clean(contact.phone)
        draft.email = clean(contact.email)
        draft.address = clean(address)
        return draft
    }

    var fullName: String { [givenName, familyName].filter { !$0.isEmpty }.joined(separator: " ") }

    func contact() -> CNMutableContact {
        let card = CNMutableContact()
        card.givenName = givenName
        card.familyName = familyName
        if let organization { card.organizationName = organization }
        if let jobTitle { card.jobTitle = jobTitle }
        if let phone { card.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMain, value: CNPhoneNumber(stringValue: phone))] }
        if let email { card.emailAddresses = [CNLabeledValue(label: CNLabelWork, value: email as NSString)] }
        if let address {
            let postal = CNMutablePostalAddress()
            postal.street = address
            card.postalAddresses = [CNLabeledValue(label: CNLabelWork, value: postal)]
        }
        return card
    }

    private static func clean(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// First word is the given name, the rest the family name; a single word stays a given name.
    private static func split(_ name: String) -> (String, String) {
        let parts = name.split(separator: " ", maxSplits: 1).map(String.init)
        return (parts.first ?? "", parts.count > 1 ? parts[1] : "")
    }
}

/// An email the person writes and sends from their own account.
struct MailDraft: Equatable {
    var recipient: String
    var subject: String?

    init?(recipient: String?, subject: String? = nil) {
        let address = recipient?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard address.contains("@"), !address.contains(where: \.isWhitespace) else { return nil }
        self.recipient = address
        self.subject = subject?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    /// The fallback when Mail has no account: another mail app opens with the same draft.
    var mailtoURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipient
        if let subject { components.queryItems = [URLQueryItem(name: "subject", value: subject)] }
        return components.url
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// One system hand-off to present.
enum DeviceHandoff: Identifiable {
    case calendar(JobCalendarDraft)
    case contact(ContactCardDraft)
    case mail(MailDraft)

    var id: String {
        switch self {
        case .calendar(let draft): "calendar|\(draft.title)|\(draft.start.timeIntervalSince1970)"
        case .contact(let draft): "contact|\(draft.fullName)|\(draft.organization ?? "")|\(draft.phone ?? "")|\(draft.email ?? "")"
        case .mail(let draft): "mail|\(draft.recipient)|\(draft.subject ?? "")"
        }
    }
}

extension View {
    /// Presents Calendar, Contacts and Mail hand-offs set on `request`. Calendar asks for
    /// add-only access first; a denial explains itself and offers Settings.
    func deviceHandoffs(_ request: Binding<DeviceHandoff?>) -> some View {
        modifier(DeviceHandoffPresenter(request: request))
    }
}

private struct DeviceHandoffPresenter: ViewModifier {
    @Binding var request: DeviceHandoff?
    @State private var presented: DeviceHandoff?
    @State private var calendarDenied = false
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content
            .onChange(of: request?.id) { _, _ in
                guard let next = request else { return }
                request = nil
                Task { await route(next) }
            }
            .sheet(item: $presented) { handoff in
                switch handoff {
                case .calendar(let draft): CalendarEventEditor(draft: draft).ignoresSafeArea()
                case .contact(let draft): ContactCardEditor(draft: draft).ignoresSafeArea()
                case .mail(let draft): MailComposer(draft: draft).ignoresSafeArea()
                }
            }
            .thorbisConfirm("Calendar access is off",
                            message: "Allow Thorbis to add events in Settings to put this visit on your calendar.",
                            isPresented: $calendarDenied,
                            actions: [ThorbisConfirmAction("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                            }])
    }

    @MainActor
    private func route(_ handoff: DeviceHandoff) async {
        switch handoff {
        case .calendar:
            if await CalendarAccess.requestAddOnly() { presented = handoff } else { calendarDenied = true }
        case .mail(let draft):
            if MFMailComposeViewController.canSendMail() {
                presented = handoff
            } else if let url = draft.mailtoURL {
                openURL(url)
            }
        case .contact:
            presented = handoff
        }
    }
}

@MainActor
enum CalendarAccess {
    static let store = EKEventStore()

    /// Add-only (write-only) access: Thorbis never reads the person's calendar.
    static func requestAddOnly() async -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .writeOnly, .fullAccess: return true
        case .denied, .restricted: return false
        case .notDetermined: return (try? await store.requestWriteOnlyAccessToEvents()) ?? false
        @unknown default: return false
        }
    }
}

private struct CalendarEventEditor: UIViewControllerRepresentable {
    let draft: JobCalendarDraft
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let controller = EKEventEditViewController()
        controller.eventStore = CalendarAccess.store
        controller.event = draft.event(in: CalendarAccess.store)
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator { dismiss() } }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let done: () -> Void
        init(done: @escaping () -> Void) { self.done = done }
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) { done() }
    }
}

private struct ContactCardEditor: UIViewControllerRepresentable {
    let draft: ContactCardDraft
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UINavigationController {
        let card = CNContactViewController(forUnknownContact: draft.contact())
        // Without a store the card hides Create New Contact; saving goes through Apple's own UI.
        card.contactStore = CNContactStore()
        card.allowsActions = false
        card.delegate = context.coordinator
        card.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { _ in context.coordinator.done() })
        return UINavigationController(rootViewController: card)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator { dismiss() } }

    final class Coordinator: NSObject, CNContactViewControllerDelegate {
        let done: () -> Void
        init(done: @escaping () -> Void) { self.done = done }
        func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) { done() }
    }
}

private struct MailComposer: UIViewControllerRepresentable {
    let draft: MailDraft
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.setToRecipients([draft.recipient])
        if let subject = draft.subject { controller.setSubject(subject) }
        controller.mailComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator { dismiss() } }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let done: () -> Void
        init(done: @escaping () -> Void) { self.done = done }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) { done() }
    }
}

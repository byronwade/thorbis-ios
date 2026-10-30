import LocalAuthentication
import SwiftUI

// MARK: - API

/// `customers.update` body. Only changed fields are sent; `.clear` sends null.
struct FieldCustomerUpdate: Encodable {
    var name: String? = nil
    var email: FieldContactPatch<String> = .unchanged
    var phone: FieldContactPatch<String> = .unchanged
    var address: FieldContactPatch<String> = .unchanged
    var preferredContact: FieldContactPatch<String> = .unchanged

    var isEmpty: Bool {
        guard name == nil else { return false }
        for patch in [email, phone, address, preferredContact] {
            if case .unchanged = patch { continue }
            return false
        }
        return true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try Self.encode(email, forKey: .email, in: &container)
        try Self.encode(phone, forKey: .phone, in: &container)
        try Self.encode(address, forKey: .address, in: &container)
        try Self.encode(preferredContact, forKey: .preferredContact, in: &container)
    }

    private enum CodingKeys: String, CodingKey { case name, email, phone, address, preferredContact }

    private static func encode(_ value: FieldContactPatch<String>, forKey key: CodingKeys,
                               in container: inout KeyedEncodingContainer<CodingKeys>) throws {
        switch value {
        case .unchanged: break
        case .clear: try container.encodeNil(forKey: key)
        case .value(let value): try container.encode(value, forKey: key)
        }
    }
}

@MainActor
extension APIClient {
    /// `POST /v1/customers/{id}` (customer.edit). The server records the change set in the audit log.
    func updateFieldCustomer(_ customerID: String, request: FieldCustomerUpdate) async throws -> CustomerRecord {
        guard UUID(uuidString: customerID) != nil else {
            throw Problem(title: "Invalid record ID", status: nil, detail: customerID)
        }
        return try await send("POST", "/v1/customers/\(customerID)", body: request)
    }
}

// MARK: - Draft

/// What the customer changed while holding the device. Pure, so the hand-back review and the
/// save plan can be tested without a screen.
struct CustomerSelfEditDraft: Equatable {
    struct Contact: Equatable, Identifiable {
        let id: String
        var name: String
        var phone: String
        var email: String
    }

    struct Location: Equatable, Identifiable {
        let id: String
        let label: String
        var address: String
    }

    struct PreferredOption: Identifiable, Sendable {
        let value: String
        let label: String
        var id: String { value }
    }

    static let preferredOptions = [PreferredOption(value: "phone", label: "Call"), PreferredOption(value: "sms", label: "Text"),
                                   PreferredOption(value: "email", label: "Email")]

    private(set) var original: CustomerRecord
    private(set) var originalContacts: [Contact]
    private(set) var originalLocations: [Location]
    let originalTexts: Bool?

    var name: String
    var phone: String
    var email: String
    var address: String
    var preferredContact: String?
    var contacts: [Contact]
    var locations: [Location]
    /// nil until someone has answered; the customer can answer for themselves here.
    var allowsTexts: Bool?
    var newContactName = ""
    var newContactPhone = ""
    var newContactEmail = ""

    init(record: CustomerRecord, contacts: [CustomerContactRecord], locations: [ServiceLocationRecord],
         smsConsent: CustomerSmsConsent?) {
        original = record
        name = record.name
        phone = record.phone ?? ""
        email = record.email ?? ""
        address = record.address ?? ""
        preferredContact = record.preferredContact
        let mappedContacts = contacts.map { Contact(id: $0.id, name: $0.name, phone: $0.phone ?? "", email: $0.email ?? "") }
        originalContacts = mappedContacts
        self.contacts = mappedContacts
        let mappedLocations = locations.filter { $0.kind == "service" }.map { Location(id: $0.id, label: $0.label, address: $0.address) }
        originalLocations = mappedLocations
        self.locations = mappedLocations
        let texts = smsConsent.map { $0.decision == "grant" }
        originalTexts = texts
        allowsTexts = texts
    }

    // MARK: Validation

    var nameError: String? {
        let value = Self.clean(name)
        if value.isEmpty { return "Enter your name." }
        if value.count > 200 { return "Use 200 characters or fewer." }
        return nil
    }

    var emailError: String? { Self.emailProblem(email) }

    var newContactError: String? {
        guard hasNewContact else { return nil }
        if Self.clean(newContactName).isEmpty { return "Add a name for the new contact." }
        return Self.emailProblem(newContactEmail)
    }

    var contactErrors: [String: String] {
        var errors: [String: String] = [:]
        for contact in contacts {
            if Self.clean(contact.name).isEmpty { errors[contact.id] = "Add a name." }
            else if let problem = Self.emailProblem(contact.email) { errors[contact.id] = problem }
        }
        return errors
    }

    var locationErrors: [String: String] {
        var errors: [String: String] = [:]
        for location in locations where Self.clean(location.address).isEmpty { errors[location.id] = "Enter the address." }
        return errors
    }

    var isValid: Bool {
        nameError == nil && emailError == nil && newContactError == nil && contactErrors.isEmpty && locationErrors.isEmpty &&
        Self.clean(phone).count <= 30 && Self.clean(address).count <= 500
    }

    private var hasNewContact: Bool {
        !(Self.clean(newContactName).isEmpty && Self.clean(newContactPhone).isEmpty && Self.clean(newContactEmail).isEmpty)
    }

    // MARK: Save plan

    var customerUpdate: FieldCustomerUpdate {
        var update = FieldCustomerUpdate()
        let cleanedName = Self.clean(name)
        if cleanedName != original.name { update.name = cleanedName }
        update.phone = Self.patch(phone, from: original.phone)
        update.email = Self.patch(email, from: original.email)
        update.address = Self.patch(address, from: original.address)
        if preferredContact != original.preferredContact {
            update.preferredContact = preferredContact.map { .value($0) } ?? .clear
        }
        return update
    }

    var contactUpdates: [(id: String, request: FieldContactUpdate)] {
        contacts.compactMap { contact in
            guard let before = originalContacts.first(where: { $0.id == contact.id }), before != contact.trimmed else { return nil }
            let update = FieldContactUpdate(
                name: Self.clean(contact.name) == before.name ? nil : Self.clean(contact.name),
                email: Self.patch(contact.email, from: before.email.isEmpty ? nil : before.email),
                phone: Self.patch(contact.phone, from: before.phone.isEmpty ? nil : before.phone)
            )
            return (contact.id, update)
        }
    }

    var newContact: FieldContactCreate? {
        guard hasNewContact else { return nil }
        return CustomerContactDraft(name: newContactName, role: nil, email: newContactEmail, phone: newContactPhone).makeRequest()
    }

    var locationChanges: [(id: String, address: String)] {
        locations.compactMap { location in
            let cleaned = Self.clean(location.address)
            guard let before = originalLocations.first(where: { $0.id == location.id }), cleaned != before.address else { return nil }
            return (location.id, cleaned)
        }
    }

    var textsChange: Bool? {
        guard let allowsTexts, allowsTexts != originalTexts else { return nil }
        return allowsTexts
    }

    /// Plain-words list for the staff review after the device comes back.
    var changeSummary: [String] {
        var lines: [String] = []
        let update = customerUpdate
        if let newName = update.name { lines.append("Name: \(original.name) → \(newName)") }
        lines += Self.describe("Phone", update.phone, before: original.phone)
        lines += Self.describe("Email", update.email, before: original.email)
        lines += Self.describe("Billing address", update.address, before: original.address)
        if case .unchanged = update.preferredContact {} else {
            lines.append("Best way to reach: \(Self.preferredLabel(preferredContact))")
        }
        for (id, _) in contactUpdates {
            if let contact = contacts.first(where: { $0.id == id }) { lines.append("Updated contact \(Self.clean(contact.name))") }
        }
        if let newContact { lines.append("New contact \(newContact.name)") }
        for change in locationChanges {
            let label = locations.first(where: { $0.id == change.id })?.label ?? "Service address"
            lines.append("\(label): \(change.address)")
        }
        if let texts = textsChange { lines.append(texts ? "Agreed to job texts" : "Asked to stop job texts") }
        return lines
    }

    var hasChanges: Bool { !changeSummary.isEmpty }

    static func preferredLabel(_ value: String?) -> String {
        preferredOptions.first(where: { $0.value == value })?.label ?? "No preference"
    }

    // MARK: Helpers

    static func clean(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }

    private static func patch(_ value: String, from before: String?) -> FieldContactPatch<String> {
        let cleaned = clean(value)
        if cleaned == (before ?? "") { return .unchanged }
        return cleaned.isEmpty ? .clear : .value(cleaned)
    }

    private static func describe(_ label: String, _ patch: FieldContactPatch<String>, before: String?) -> [String] {
        switch patch {
        case .unchanged: []
        case .clear: ["\(label): removed \(before ?? "")"]
        case .value(let value): ["\(label): \(value)"]
        }
    }

    private static func emailProblem(_ value: String) -> String? {
        let cleaned = clean(value)
        guard !cleaned.isEmpty else { return nil }
        let parts = cleaned.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."), !parts[1].hasPrefix("."), !parts[1].hasSuffix("."),
              !cleaned.contains(" ") else { return "Check the email address." }
        return nil
    }
}

private extension CustomerSelfEditDraft.Contact {
    var trimmed: Self {
        Self(id: id, name: CustomerSelfEditDraft.clean(name), phone: CustomerSelfEditDraft.clean(phone),
             email: CustomerSelfEditDraft.clean(email))
    }
}

// MARK: - Customer mode container

enum StaffUnlock {
    /// Face ID, Touch ID or the device passcode. A device with no passcode can't lock, so it
    /// opens straight away rather than trapping the technician in customer mode.
    @MainActor static func unlock(reason: String = "Unlock to leave customer mode") async -> Bool {
        let context = LAContext()
        var problem: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &problem) else { return true }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}

/// Customer-facing sizes (design.thorbis.com customer presentation): 20 pt body, 17 pt smallest
/// text, 56 pt tap targets, commits 56 pt on iPhone and 60 pt on iPad.
enum CustomerModeStyle {
    static let body: CGFloat = 20
    static let smallest: CGFloat = 17
    static let target: CGFloat = 56
    static let commitHeight: CGFloat = 56
    static let regularCommitHeight: CGFloat = 60
    static let readableWidth: CGFloat = 560
}

/// The one commit on a customer-facing screen: ink fill (blue is only a pointer), full readable
/// width, 56 pt on iPhone and 60 pt on iPad.
struct CustomerCommitButton: View {
    let title: String
    var icon: String? = nil
    var busy = false
    let action: () -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busy { ProgressView().tint(Theme.background) } else if let icon { Image(systemName: icon) }
                Text(title).font(Theme.font(CustomerModeStyle.body, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .frame(minHeight: sizeClass == .regular ? CustomerModeStyle.regularCommitHeight : CustomerModeStyle.commitHeight)
            .foregroundStyle(Theme.background)
            .background(Theme.foreground, in: RoundedRectangle(cornerRadius: 14))
        }
        .disabled(busy)
    }
}

/// Hand the device to the customer. Shows only `content` full screen: no tab bar, no staff menus,
/// no swipe-to-dismiss. The lock in the corner (or `handBack`, which shows "please hand the
/// device back") needs the technician's Face ID or passcode before `onUnlocked` runs.
///
/// Present it with `.fullScreenCover`. `content` gets a `handBack` action for its own Done button.
private struct CustomerModeUnlockKey: EnvironmentKey {
    static let defaultValue: (@MainActor () async -> Void)? = nil
}
extension EnvironmentValues {
    var customerModeUnlock: (@MainActor () async -> Void)? {
        get { self[CustomerModeUnlockKey.self] }
        set { self[CustomerModeUnlockKey.self] = newValue }
    }
}
/// A pushed customer destination requests the container's existing authentication boundary.
struct CustomerModeOwnerUnlockButton: View {
    @Environment(\.customerModeUnlock) private var unlock
    @State private var busy = false
    var body: some View {
        Button {
            guard !busy, let unlock else { return }
            busy = true
            Task { await unlock(); busy = false }
        } label: {
            HStack(spacing: 8) { Image(systemName: "lock"); Text("Hand back") }
                .font(Theme.font(17, weight: .medium)).frame(minHeight: CustomerModeStyle.target)
        }
        .accessibilityLabel("Hand back to the technician")
        .accessibilityHint("Technician authentication is required to leave customer mode.")
        .accessibilityIdentifier("customer-mode-owner-exit")
        .disabled(busy || unlock == nil)
    }
}

struct CustomerModeContainer<Content: View>: View {
    let onUnlocked: () -> Void
    @ViewBuilder let content: (_ handBack: @escaping () -> Void) -> Content
    private let ownerControlTitle: String?
    private let authenticateOwner: @MainActor () async -> Bool
    init(onUnlocked: @escaping () -> Void, ownerControlTitle: String? = nil,
         authenticateOwner: @escaping @MainActor () async -> Bool = { await StaffUnlock.unlock() },
         @ViewBuilder content: @escaping (_ handBack: @escaping () -> Void) -> Content) {
        self.onUnlocked = onUnlocked; self.ownerControlTitle = ownerControlTitle
        self.authenticateOwner = authenticateOwner; self.content = content
    }
    @State private var handingBack = false
    @State private var unlocking = false

    var body: some View {
        NavigationStack {
            Group {
                if handingBack { handBackScreen } else { content({ handingBack = true }) }
            }
            .background(Theme.background.ignoresSafeArea())
            .foregroundStyle(Theme.foreground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ownerToolbar }
        }
        .environment(\.customerModeUnlock, { await unlock() })

        #if DEBUG
        .overlay {
            if PaperPreview.isJobEstimateHandoff {
                JobEstimateHandoffReceiptMetadata().frame(width: 0, height: 0).allowsHitTesting(false)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if PaperPreview.isJobEstimateHandoff && !ProcessInfo.processInfo.arguments.contains("--paper-preview-handoff-hide-controls") { JobEstimateHandoffPreviewControls() }
            else if PaperPreview.isJobEstimateRecoveryPreview { PaperPreviewConnectionMenu() }
            else if PaperPreview.isJobDocumentsPreview && ProcessInfo.processInfo.arguments.contains("--paper-preview-documents-status-change") { PaperPreviewConnectionMenu() }
        }
        #endif
        .interactiveDismissDisabled()
        .persistentSystemOverlays(.hidden)
    }

    @ToolbarContentBuilder private var ownerToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { Task { await unlock() } } label: {
                Group {
                    if let ownerControlTitle { HStack(spacing: 8) { Image(systemName: "lock"); Text(ownerControlTitle) }.font(Theme.font(17, weight: .medium)) }
                    else { Image(systemName: "lock").font(.system(size: 20)) }
                }.frame(minWidth: CustomerModeStyle.target, minHeight: CustomerModeStyle.target).contentShape(Rectangle())
            }
            .accessibilityLabel(ownerControlTitle == nil ? "Technician: unlock to leave customer mode" : "Hand back to the technician")
            .accessibilityHint("Technician authentication is required to leave customer mode.")
            .accessibilityIdentifier(ownerControlTitle == nil ? "lock" : "customer-mode-owner-exit")
            .disabled(unlocking)
        }
    }

    private var handBackScreen: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "hand.wave").font(.system(size: 44)).foregroundStyle(Theme.brandText).accessibilityHidden(true)
            Text("Thank you").font(Theme.font(28, weight: .semibold)).tracking(-0.42)
                .accessibilityAddTraits(.isHeader)
            Text("Please hand the device back to your technician.")
                .font(Theme.font(CustomerModeStyle.body)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            Spacer()
            VStack(spacing: 8) {
                CustomerCommitButton(title: "Technician: unlock", icon: "faceid", busy: unlocking) { Task { await unlock() } }
                Button("Go back") { handingBack = false }
                    .font(Theme.font(CustomerModeStyle.body, weight: .medium)).foregroundStyle(Theme.brandText)
                    .frame(maxWidth: .infinity, minHeight: CustomerModeStyle.target)
            }
            .frame(maxWidth: CustomerModeStyle.readableWidth)
        }
        .padding(.horizontal, Theme.gutter).padding(.bottom, 16)
        .frame(maxWidth: .infinity)
    }

    private func unlock() async {
        guard !unlocking else { return }
        unlocking = true
        defer { unlocking = false }
        if await authenticateOwner() { onUnlocked() }
    }
}

// MARK: - Screen

/// "Show to customer": the customer's own details, presented in customer mode for them to check
/// and correct on the technician's phone or iPad. Notes, balances, gate codes, other customers and
/// the rest of the app stay hidden, and nothing is saved until the technician has unlocked the
/// device and seen the changes. Each save is the normal audited customer write, under the
/// technician's name.
struct CustomerSelfEditView: View {
    let customerID: String
    let onFinished: () -> Void

    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @State private var draft: CustomerSelfEditDraft?
    @State private var loadError: String?
    @State private var staffReview = false
    @State private var savedAll = false
    @State private var showErrors = false
    @State private var saving = false
    @State private var saveError: String?
    @State private var consentKey = UUID().uuidString
    @FocusState private var focused: Bool

    private var businessName: String { session.activeOrganization?.name ?? "us" }

    var body: some View {
        if staffReview {
            NavigationStack {
                Group { if savedAll { saved } else { review } }
                    .background(Theme.background.ignoresSafeArea())
                    .foregroundStyle(Theme.foreground)
                    .navigationTitle("Customer view")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .interactiveDismissDisabled(saving)
        } else {
            CustomerModeContainer(onUnlocked: {
                focused = false
                if draft?.hasChanges == true { staffReview = true } else { onFinished() }
            }) { handBack in
                editing(handBack: handBack)
            }
            .task { await load() }
        }
    }

    // MARK: Editing (customer)

    @ViewBuilder private func editing(handBack: @escaping () -> Void) -> some View {
        if let draft = Binding($draft) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your details").font(Theme.font(34, weight: .bold)).tracking(-0.68)
                            .accessibilityAddTraits(.isHeader)
                        Text("Check what \(businessName) has on file and fix anything that's wrong.")
                            .font(Theme.font(CustomerModeStyle.body)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 8).padding(.bottom, 24)

                    group("You") {
                        field("Name", text: draft.name, content: .name, error: showErrors ? draft.wrappedValue.nameError : nil)
                        field("Mobile phone", text: draft.phone, content: .telephoneNumber, keyboard: .phonePad)
                        field("Email", text: draft.email, content: .emailAddress, keyboard: .emailAddress,
                              error: showErrors ? draft.wrappedValue.emailError : nil)
                        field("Billing address", text: draft.address, content: .fullStreetAddress, axis: .vertical)
                    }

                    group("Best way to reach you") {
                        HStack(spacing: 8) {
                            ForEach(CustomerSelfEditDraft.preferredOptions) { option in
                                choice(option.label, selected: draft.wrappedValue.preferredContact == option.value) {
                                    draft.wrappedValue.preferredContact = draft.wrappedValue.preferredContact == option.value ? nil : option.value
                                }
                            }
                        }
                        Toggle(isOn: Binding(get: { draft.wrappedValue.allowsTexts == true },
                                             set: { draft.wrappedValue.allowsTexts = $0 })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Text me about my appointments").font(Theme.font(CustomerModeStyle.body, weight: .medium))
                                Text("On my way, arrival and job updates. Reply STOP any time.")
                                    .font(Theme.font(CustomerModeStyle.smallest)).foregroundStyle(Theme.muted)
                            }
                        }
                        .tint(Theme.brand)
                        .frame(minHeight: 56)
                        .padding(.top, 6)
                    }

                    if !draft.wrappedValue.locations.isEmpty {
                        group(draft.wrappedValue.locations.count == 1 ? "Service address" : "Service addresses") {
                            ForEach(draft.locations) { location in
                                field(location.wrappedValue.label, text: location.address, content: .fullStreetAddress, axis: .vertical,
                                      error: showErrors ? draft.wrappedValue.locationErrors[location.wrappedValue.id] : nil)
                            }
                        }
                    }

                    group("Other people we can contact") {
                        ForEach(draft.contacts) { contact in
                            VStack(alignment: .leading, spacing: 8) {
                                field("Name", text: contact.name, content: .name,
                                      error: showErrors ? draft.wrappedValue.contactErrors[contact.wrappedValue.id] : nil)
                                field("Phone", text: contact.phone, content: .telephoneNumber, keyboard: .phonePad)
                                field("Email", text: contact.email, content: .emailAddress, keyboard: .emailAddress)
                            }
                            .padding(.bottom, 12)
                        }
                        Text("Add someone").font(Theme.font(CustomerModeStyle.smallest, weight: .medium)).foregroundStyle(Theme.muted).padding(.top, 2)
                        field("Name", text: draft.newContactName, content: .name,
                              error: showErrors ? draft.wrappedValue.newContactError : nil)
                        field("Phone", text: draft.newContactPhone, content: .telephoneNumber, keyboard: .phonePad)
                        field("Email", text: draft.newContactEmail, content: .emailAddress, keyboard: .emailAddress)
                    }
                }
                .frame(maxWidth: CustomerModeStyle.readableWidth, alignment: .leading)
                .padding(.horizontal, Theme.gutter)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                CustomerCommitButton(title: "Done") {
                    focused = false
                    if draft.wrappedValue.isValid { handBack() } else { showErrors = true }
                }
                .frame(maxWidth: CustomerModeStyle.readableWidth)
                .padding(.horizontal, Theme.gutter).padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(Theme.background)
            }
        } else if let loadError {
            ContentUnavailableView("Couldn't open your details", systemImage: "person.crop.circle.badge.exclamationmark",
                                   description: Text(loadError + " Hand the device back to your technician."))
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Review (technician)

    private var review: some View {
        let changes = draft?.changeSummary ?? []
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Review changes").font(Theme.font(24, weight: .medium)).tracking(-0.36)
                    .accessibilityAddTraits(.isHeader)
                Text("These save to the customer's record and activity under your name.")
                    .font(Theme.font(15)).foregroundStyle(Theme.muted)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(changes.enumerated()), id: \.offset) { index, line in
                        Text(line).font(Theme.font(15)).padding(.vertical, 10)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        if index < changes.count - 1 { Divider().overlay(Theme.border) }
                    }
                }
                .padding(.horizontal, 14)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                if let saveError {
                    Text(saveError).font(Theme.font(13)).foregroundStyle(Theme.destructive)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.destructiveSurface, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .frame(maxWidth: CustomerModeStyle.readableWidth, alignment: .leading)
            .padding(.horizontal, Theme.gutter).padding(.top, 8)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                PrimaryButton(title: "Save changes", busy: saving) { Task { await save() } }
                Button("Discard changes", role: .destructive) { onFinished() }
                    .font(Theme.font(15, weight: .medium)).frame(minHeight: 44).disabled(saving)
            }
            .frame(maxWidth: CustomerModeStyle.readableWidth)
            .padding(.horizontal, Theme.gutter).padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Theme.background)
        }
    }

    private var saved: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle").font(.system(size: 44)).foregroundStyle(Theme.success).accessibilityHidden(true)
            Text("Customer details saved").font(Theme.font(22, weight: .semibold))
            Spacer()
            PrimaryButton(title: "Done") { onFinished() }.frame(maxWidth: CustomerModeStyle.readableWidth)
        }
        .padding(.horizontal, Theme.gutter).padding(.bottom, 16)
        .frame(maxWidth: .infinity)
    }

    // MARK: Pieces

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Theme.font(CustomerModeStyle.smallest, weight: .semibold)).foregroundStyle(Theme.muted)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(.bottom, 24)
    }

    private func field(_ label: String, text: Binding<String>, content: UITextContentType? = nil,
                       keyboard: UIKeyboardType = .default, axis: Axis = .horizontal, error: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(Theme.font(CustomerModeStyle.smallest)).foregroundStyle(Theme.muted)
                TextField("", text: text, axis: axis)
                    .font(Theme.font(CustomerModeStyle.body))
                    .textContentType(content)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
                    .autocorrectionDisabled(keyboard != .default)
                    .lineLimit(axis == .vertical ? 1...3 : 1...1)
                    .focused($focused)
                    .accessibilityLabel(label)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .frame(minHeight: 68, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(error == nil ? Theme.border : Theme.destructive))
            if let error { Text(error).font(Theme.font(CustomerModeStyle.smallest)).foregroundStyle(Theme.destructive) }
        }
    }

    private func choice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Theme.font(CustomerModeStyle.body, weight: .medium))
                .frame(maxWidth: .infinity).frame(height: CustomerModeStyle.commitHeight)
                .foregroundStyle(selected ? Theme.brandText : Theme.foreground)
                .background(selected ? Theme.brandSurface : Theme.card, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Theme.brandText : Theme.border))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Actions

    private func load() async {
        guard draft == nil else { return }
        do {
            let record = try await api.fieldCustomer(customerID)
            let contacts = try await api.fieldContacts(customerID)
            let locations = try await api.fieldLocations(customerID)
            let consent: CustomerSmsConsent?
            do { consent = try await api.customerSmsConsent(customerID) } catch { consent = nil }
            draft = CustomerSelfEditDraft(record: record, contacts: contacts, locations: locations, smsConsent: consent)
        } catch is CancellationError {
        } catch {
            loadError = error.isConnectivityFailure ? "This needs a connection." : "Something went wrong."
        }
    }

    /// Customer record first, then contacts, addresses and the text decision. Each step is its own
    /// audited write; the draft is rebased after each one so a retry doesn't repeat finished work.
    private func save() async {
        guard var current = draft else { return }
        saving = true
        defer { saving = false }
        saveError = nil
        do {
            let update = current.customerUpdate
            if !update.isEmpty {
                let record = try await api.updateFieldCustomer(customerID, request: update)
                current = current.rebased(record: record)
                draft = current
            }
            for change in current.contactUpdates {
                let saved = try await api.updateFieldContact(customerID, change.id, request: change.request)
                current = current.rebased(contact: saved)
                draft = current
            }
            if let create = current.newContact {
                _ = try await api.createFieldContact(customerID, request: create)
                current.newContactName = ""; current.newContactPhone = ""; current.newContactEmail = ""
                draft = current
            }
            if !current.locationChanges.isEmpty {
                let records = try await api.fieldLocations(customerID)
                for change in current.locationChanges {
                    guard let existing = records.first(where: { $0.id == change.id }) else { continue }
                    let saved = try await api.updateFieldLocation(customerID, change.id, request: FieldLocationUpdate(
                        label: existing.label, kind: existing.kind, address: change.address, notes: existing.notes,
                        // The map pin belonged to the old address.
                        coordinates: nil, gateCode: existing.gateCode, alarmCode: existing.alarmCode,
                        dogOnSite: existing.dogOnSite, parking: existing.parking))
                    current = current.rebased(location: saved)
                    draft = current
                }
            }
            if let texts = current.textsChange {
                let consent: CustomerSmsConsent?
                do { consent = try await api.customerSmsConsent(customerID) } catch { consent = nil }
                _ = try await api.recordCustomerSmsConsent(
                    customerID, grant: texts, expectedVersion: consent?.version, idempotencyKey: consentKey,
                    evidenceRef: "Customer chose this themselves in customer mode on staff's Thorbis iPhone app")
            }
            savedAll = true
        } catch is CancellationError {
        } catch {
            saveError = error.isConnectivityFailure ? "Saving needs a connection. Try again when you have signal." : error.localizedDescription
        }
    }
}

extension CustomerSelfEditDraft {
    /// After a step saves, later steps compare against what the server now holds.
    func rebased(record: CustomerRecord) -> Self {
        var copy = self
        copy.original = record
        return copy
    }

    func rebased(contact: CustomerContactRecord) -> Self {
        var copy = self
        if let index = copy.originalContacts.firstIndex(where: { $0.id == contact.id }) {
            copy.originalContacts[index] = Contact(id: contact.id, name: contact.name, phone: contact.phone ?? "", email: contact.email ?? "")
        }
        return copy
    }

    func rebased(location: ServiceLocationRecord) -> Self {
        var copy = self
        if let index = copy.originalLocations.firstIndex(where: { $0.id == location.id }) {
            copy.originalLocations[index] = Location(id: location.id, label: location.label, address: location.address)
        }
        return copy
    }
}

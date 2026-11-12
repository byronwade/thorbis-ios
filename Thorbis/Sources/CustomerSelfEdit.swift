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

struct ConditionalCustomerUpdate: Encodable {
    let update: FieldCustomerUpdate
    let original: CustomerRecord
    private enum Key: String, CodingKey { case expected, name, email, phone, address, preferredContact }
    func encode(to encoder: Encoder) throws {
        try update.encode(to: encoder)
        var container = encoder.container(keyedBy: Key.self)
        var expected = container.nestedContainer(keyedBy: Key.self, forKey: .expected)
        if update.name != nil { try expected.encode(original.name, forKey: .name) }
        func baseline(_ patch: FieldContactPatch<String>, _ value: String?, _ key: Key) throws {
            if case .unchanged = patch { return }
            if let value { try expected.encode(value, forKey: key) } else { try expected.encodeNil(forKey: key) }
        }
        try baseline(update.email, original.email, .email)
        try baseline(update.phone, original.phone, .phone)
        try baseline(update.address, original.address, .address)
        try baseline(update.preferredContact, original.preferredContact, .preferredContact)
    }
}

struct ConditionalContactBaseline: Codable, Equatable {
    let id: String, organizationId: String, customerId: String, name: String
    let email: String?, phone: String?
    init(_ record: CustomerContactRecord) {
        id = record.id; organizationId = record.organizationId; customerId = record.customerId
        name = record.name; email = record.email; phone = record.phone
    }
}

struct ConditionalLocationBaseline: Codable, Equatable {
    let id: String, organizationId: String, customerId: String, address: String
    let coordinates: FieldCoordinates?
    init(_ record: ServiceLocationRecord) {
        id = record.id; organizationId = record.organizationId; customerId = record.customerId
        address = record.address; coordinates = record.coordinates
    }
}

struct ConditionalContactUpdate: Encodable {
    let update: FieldContactUpdate
    let original: ConditionalContactBaseline
    private enum Key: String, CodingKey { case expected, name, email, phone }
    func encode(to encoder: Encoder) throws {
        try update.encode(to: encoder)
        var c = encoder.container(keyedBy: Key.self)
        var expected = c.nestedContainer(keyedBy: Key.self, forKey: .expected)
        if update.name != nil { try expected.encode(original.name, forKey: .name) }
        func baseline(_ patch: FieldContactPatch<String>, _ value: String?, _ key: Key) throws {
            if case .unchanged = patch { return }
            if let value { try expected.encode(value, forKey: key) } else { try expected.encodeNil(forKey: key) }
        }
        try baseline(update.email, original.email, .email)
        try baseline(update.phone, original.phone, .phone)
    }
}

struct ConditionalLocationUpdate: Encodable {
    let address: String
    let original: ConditionalLocationBaseline
    private enum Key: String, CodingKey { case address, coordinates, expected }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(address, forKey: .address)
        try c.encodeNil(forKey: .coordinates)
        var expected = c.nestedContainer(keyedBy: Key.self, forKey: .expected)
        try expected.encode(original.address, forKey: .address)
        if let coordinates = original.coordinates { try expected.encode(coordinates, forKey: .coordinates) }
        else { try expected.encodeNil(forKey: .coordinates) }
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
    func updateFieldCustomerConditionally(_ customerID: String, request: ConditionalCustomerUpdate) async throws -> CustomerRecord {
        guard UUID(uuidString: customerID) != nil else { throw Problem(title: "Invalid record ID", status: nil, detail: customerID) }
        return try await send("POST", "/v1/customers/\(customerID)", body: request)
    }
}

// MARK: - Draft

/// What the customer changed while holding the device. Pure, so the hand-back review and the
/// save plan can be tested without a screen.
struct CustomerSelfEditConflict: Identifiable {
    let id: String
    let label: String
    let mine: String
    let current: String
}

struct CustomerSelfEditDraft: Codable, Equatable {
    struct Contact: Codable, Equatable, Identifiable {
        let id: String
        var name: String
        var phone: String
        var email: String
    }

    struct Location: Codable, Equatable, Identifiable {
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
    private(set) var originalTexts: Bool?
    private(set) var originalConsentVersion: String?
    private(set) var consentBaselineKnown: Bool?
    // Nil means an older persisted draft without lossless baselines. It must be reconciled first.
    private(set) var conditionalContactBaselines: [ConditionalContactBaseline]?
    private(set) var conditionalLocationBaselines: [ConditionalLocationBaseline]?

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
         smsConsent: CustomerSmsConsent?, consentKnown: Bool = true) {
        original = record
        originalConsentVersion = smsConsent?.version
        consentBaselineKnown = consentKnown
        conditionalContactBaselines = contacts.map(ConditionalContactBaseline.init)
        conditionalLocationBaselines = locations.map(ConditionalLocationBaseline.init)
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

    func conditionalCustomerUpdate() -> ConditionalCustomerUpdate {
        ConditionalCustomerUpdate(update: customerUpdate, original: original)
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
                Text(title).font(Theme.customerFont(CustomerModeStyle.body, weight: .semibold))
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
                .font(Theme.customerFont(17, weight: .medium)).frame(minHeight: CustomerModeStyle.target)
        }
        .accessibilityLabel("Hand back")
        .accessibilityHint("Technician authentication is required to leave customer mode.")
        .accessibilityIdentifier("customer-mode-owner-exit")
        .disabled(busy || unlock == nil)
    }
}

#if DEBUG
/// DEBUG fixture controls for customer mode, laid out above the protected navigation stack so
/// they push it down instead of covering its toolbar.
private struct CustomerModePreviewControlsStack: ViewModifier {
    @EnvironmentObject private var session: SessionController
    @State private var replaced = false
    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            if ProcessInfo.processInfo.arguments.contains("--paper-preview-legacy-handoff-test") {
                Button(replaced ? "Preview session replaced" : "Preview replace session") {
                    Task { await session.restore(); replaced = true }
                }.frame(minHeight: 44).accessibilityIdentifier(replaced ? "preview-session-replaced" : "preview-replace-session")
            }
            if PaperPreview.isJobEstimateHandoff && !ProcessInfo.processInfo.arguments.contains("--paper-preview-handoff-hide-controls") { JobEstimateHandoffPreviewControls() }
            else if PaperPreview.isJobEstimateRecoveryPreview { PaperPreviewConnectionMenu() }
            else if PaperPreview.isJobDocumentsPreview && ProcessInfo.processInfo.arguments.contains("--paper-preview-documents-status-change") { PaperPreviewConnectionMenu() }
            content
        }
    }
}
#endif

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
            .background(Theme.canvas)
            .foregroundStyle(Theme.foreground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ownerToolbar }
        }
        .environment(\.customerModeUnlock, { await unlock() })
        // Customers never get the staff drawer, even on screens pushed inside customer mode.
        .environment(\.paperDrawer, nil)

        #if DEBUG
        .overlay {
            if PaperPreview.isJobEstimateHandoff {
                JobEstimateHandoffReceiptMetadata().frame(width: 0, height: 0).allowsHitTesting(false)
            }
        }
        // Stacked above the navigation stack, not a `safeAreaInset`: once the session changed under
        // the cover, the inset stopped moving the navigation bar down, so the DEBUG disclosure sat on
        // top of the Hand back pill and VoiceOver / XCTest could not reach the pill's hit point.
        .modifier(CustomerModePreviewControlsStack())
        #endif
        .interactiveDismissDisabled()
        .persistentSystemOverlays(.hidden)
    }

    @ToolbarContentBuilder private var ownerToolbar: some ToolbarContent {
        ThorbisToolbarItem(placement: .topBarTrailing, customerFacing: true) {
            if ownerControlTitle == nil {
                // Present.dc.html: the lock is a quiet 44pt circle, not a pill; same action and label.
                Button { Task { await unlock() } } label: {
                    PaperCircleLabel(symbol: "lock", size: 44, fill: Theme.fill)
                        .frame(minWidth: CustomerModeStyle.target, minHeight: CustomerModeStyle.target).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Technician: unlock to leave customer mode")
                .accessibilityHint("Technician authentication is required to leave customer mode.")
                .accessibilityIdentifier("lock")
                .disabled(unlocking)
            } else {
            Button { Task { await unlock() } } label: {
                Group {
                    if let ownerControlTitle { HStack(spacing: 8) { Image(systemName: "lock"); Text(ownerControlTitle) }.font(Theme.customerFont(17, weight: .medium)) }
                    else { Image(systemName: "lock").font(.system(size: 20)) }
                }.frame(minWidth: CustomerModeStyle.target, minHeight: CustomerModeStyle.target).contentShape(Rectangle())
            }
            .accessibilityLabel(ownerControlTitle == nil ? "Technician: unlock to leave customer mode" : "Hand back")
            .accessibilityHint("Technician authentication is required to leave customer mode.")
            .accessibilityIdentifier(ownerControlTitle == nil ? "lock" : "customer-mode-owner-exit")
            .disabled(unlocking)
            }
        }
    }

    private var handBackScreen: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "hand.wave").font(.system(size: 44)).foregroundStyle(Theme.brandText).accessibilityHidden(true)
            Text("Thank you").font(Theme.customerFont(28, weight: .semibold)).tracking(-0.42)
                .accessibilityAddTraits(.isHeader)
            Text("Please hand the device back to your technician.")
                .font(Theme.customerFont(CustomerModeStyle.body)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            Spacer()
            VStack(spacing: 8) {
                CustomerCommitButton(title: "Technician: unlock", icon: "faceid", busy: unlocking) { Task { await unlock() } }
                Button("Go back") { handingBack = false }
                    .font(Theme.customerFont(CustomerModeStyle.body, weight: .medium)).foregroundStyle(Theme.brandText)
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

/// The customer's own details in customer mode: the draft they edit, then the technician's audited
/// save. One model so Customer view can hold the draft across its other sections and run the staff
/// review only after the technician has unlocked.
@MainActor
final class CustomerSelfEditModel: ObservableObject {
    struct RecoveryEvidence {
        let record: CustomerRecord
        let contacts: [CustomerContactRecord]
        let locations: [ServiceLocationRecord]
        let consent: CustomerSmsConsent?
    }
    let customerID: String
    @Published var draft: CustomerSelfEditDraft?
    @Published private(set) var loadError: String?
    @Published private(set) var saving = false
    @Published private(set) var saveError: String?
    @Published private(set) var savedAll = false
    @Published private(set) var saveNeedsReconciliation = false
    @Published private(set) var recoveryEvidence: RecoveryEvidence?
    @Published private(set) var checkingRecovery = false
    private var consentKey = UUID().uuidString
    private let recoveryStore: CustomerSelfEditRecoveryStoring
    private var recoveryScope: CustomerSelfEditRecoveryScope?
    private var recoveryLoaded = false
    private(set) var pendingWrite: CustomerSelfEditPendingWrite?

    init(customerID: String, recoveryStore: CustomerSelfEditRecoveryStoring = KeychainCustomerSelfEditRecoveryStore.shared,
         recoveryScope: CustomerSelfEditRecoveryScope? = nil) {
        self.customerID = customerID; self.recoveryStore = recoveryStore; self.recoveryScope = recoveryScope
    }

    func bindRecovery(api: APIClient, session: SessionController) -> Bool {
        guard session.phase == .ready, let actor = session.user?.id, let organization = session.activeOrganization?.id,
              let origin = api.normalizedOrigin, session.can("customer.edit", feature: "core_crm") else {
            loadError = "Customer details aren't available. Return to your technician and try again."
            return false
        }
        let next = CustomerSelfEditRecoveryScope(actorID: actor, organizationID: organization, customerID: customerID, origin: origin)
        guard recoveryScope == nil || recoveryScope == next else {
            loadError = "Customer details aren't available. Return to your technician and try again."
            return false
        }
        recoveryScope = next
        return true
    }

    private func checkpoint(_ draft: CustomerSelfEditDraft, pending: CustomerSelfEditPendingWrite?) throws {
        guard let recoveryScope else { throw CancellationError() }
        try recoveryStore.save(.init(draft: draft, pending: pending, consentKey: consentKey), scope: recoveryScope)
        pendingWrite = pending
    }

    var hasChanges: Bool { draft?.hasChanges == true }

    func inspectRecovery(api: APIClient, currentAuthority: @escaping @MainActor () -> Bool) async {
        guard currentAuthority(), saveNeedsReconciliation, let scope = recoveryScope else { return }
        checkingRecovery = true
        defer { checkingRecovery = false }
        do {
            let evidence = try await SavedCopies.$liveOnly.withValue(true) {
                let record = try await api.fieldCustomer(customerID)
                guard currentAuthority(), record.id == customerID, record.organizationId == scope.organizationID else { throw CancellationError() }
                let contacts = try await api.allContactsForRecovery(customerID, currentAuthority: currentAuthority)
                guard currentAuthority(), contacts.allSatisfy({ $0.customerId == customerID && $0.organizationId == scope.organizationID }) else { throw CancellationError() }
                let locations = try await api.allLocationsForRecovery(customerID, currentAuthority: currentAuthority)
                guard currentAuthority(), locations.allSatisfy({ $0.customerId == customerID && $0.organizationId == scope.organizationID }) else { throw CancellationError() }
                let needsConsent = pendingWrite == .consent || draft?.allowsTexts != draft?.originalTexts
                let consent = needsConsent ? try await api.customerSmsConsent(customerID) : nil
                guard currentAuthority() else { throw CancellationError() }
                return RecoveryEvidence(record: record, contacts: contacts, locations: locations, consent: consent)
            }
            guard currentAuthority() else { return }
            recoveryEvidence = evidence
            saveError = nil
        } catch is CancellationError {
        } catch {
            guard currentAuthority() else { return }
            saveError = "Couldn't check the customer record. Connect and try again."
        }
    }

    func resolveRecovery(contactAlreadySaved: Bool, keepConflictingEdits: Bool?, currentAuthority: @MainActor () -> Bool) {
        guard currentAuthority(), let evidence = recoveryEvidence, var current = draft, let pendingWrite else { return }
        guard recoveryConflicts.isEmpty || keepConflictingEdits != nil,
              !(recoveryHasRemovedTargets && keepConflictingEdits == true) else { return }
        if case .createContact = pendingWrite {
            guard contactAlreadySaved, !matchingNewContacts.isEmpty else { return }
        }
        current = current.mergingRecovery(record: evidence.record, contacts: evidence.contacts, locations: evidence.locations,
                                          preferServerForConflicts: keepConflictingEdits == false)
        if pendingWrite == .consent || current.allowsTexts != current.originalTexts {
            let latest = evidence.consent.map { $0.decision == "grant" }
            if keepConflictingEdits == false, current.allowsTexts != current.originalTexts,
               latest != current.originalTexts, current.allowsTexts != latest { current.allowsTexts = latest }
            current = current.rebased(consent: evidence.consent)
        }
        if case .createContact = pendingWrite, contactAlreadySaved {
            if let match = matchingNewContacts.first { current = current.addingRecoveredContact(match) }
            current.newContactName = ""; current.newContactPhone = ""; current.newContactEmail = ""
        }
        // A recovered consent decision may have consumed the old idempotency key.
        // After the technician reviews fresh evidence, any new attempt is a new
        // conditional decision and must not reuse that key with a changed version.
        if pendingWrite == .consent { consentKey = UUID().uuidString }
        do {
            try checkpoint(current, pending: nil)
            draft = current; saveNeedsReconciliation = false; recoveryEvidence = nil; saveError = nil
        } catch { saveError = "Couldn't save your review on this device. Try again." }
    }

    var recoveryConflicts: [CustomerSelfEditConflict] {
        guard let draft, let evidence = recoveryEvidence else { return [] }
        var conflicts = draft.recoveryConflicts(record: evidence.record, contacts: evidence.contacts, locations: evidence.locations)
        if pendingWrite == .consent || draft.allowsTexts != draft.originalTexts {
            let latest = evidence.consent.map { $0.decision == "grant" }
            if draft.allowsTexts != draft.originalTexts, latest != draft.originalTexts, draft.allowsTexts != latest {
                func words(_ value: Bool?) -> String { value.map { $0 ? "Allow job texts" : "Stop job texts" } ?? "Not set" }
                conflicts.append(.init(id: "sms-consent", label: "Job texts", mine: words(draft.allowsTexts), current: words(latest)))
            }
        }
        return conflicts
    }

    var recoveryHasRemovedTargets: Bool {
        guard let draft, let evidence = recoveryEvidence else { return false }
        return draft.hasRemovedEditedTargets(contacts: evidence.contacts, locations: evidence.locations)
    }

    var matchingNewContacts: [CustomerContactRecord] {
        guard let draft, let recoveryEvidence else { return [] }
        let previous = Set(draft.originalContacts.map(\.id))
        func normalized(_ value: String?) -> String { (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        return recoveryEvidence.contacts.filter { contact in
            !previous.contains(contact.id) && normalized(contact.name) == normalized(draft.newContactName) &&
            normalized(contact.phone) == normalized(draft.newContactPhone) && normalized(contact.email) == normalized(draft.newContactEmail)
        }
    }

    func load(api: APIClient, currentAuthority: @escaping @MainActor () -> Bool = { true }) async {
        guard currentAuthority(), draft == nil else { return }
        guard let recoveryScope else { loadError = "Customer details can't be secured on this device. Try again."; return }
        if !recoveryLoaded {
            do {
                let saved = try recoveryStore.load(scope: recoveryScope)
                if let saved {
                    if saved.completed {
                        try? recoveryStore.remove(scope: recoveryScope)
                        recoveryLoaded = true
                    } else {
                    guard saved.draft.original.id == customerID, saved.draft.original.organizationId == recoveryScope.organizationID else {
                        loadError = "Saved customer changes couldn't be verified. Return to your technician."
                        return
                    }
                    try await SavedCopies.$liveOnly.withValue(true) {
                        let current = try await api.fieldCustomer(customerID, requireFresh: true)
                        guard currentAuthority(), current.id == customerID, current.organizationId == recoveryScope.organizationID else { throw CancellationError() }
                        let contacts = try await api.allContactsForRecovery(customerID, currentAuthority: currentAuthority)
                        guard currentAuthority(), contacts.allSatisfy({ $0.customerId == customerID && $0.organizationId == recoveryScope.organizationID }) else { throw CancellationError() }
                        let locations = try await api.allLocationsForRecovery(customerID, currentAuthority: currentAuthority)
                        guard currentAuthority(), locations.allSatisfy({ $0.customerId == customerID && $0.organizationId == recoveryScope.organizationID }) else { throw CancellationError() }
                        if saved.draft.originalTexts != nil || saved.draft.allowsTexts != nil {
                            _ = try await api.customerSmsConsent(customerID)
                            guard currentAuthority() else { throw CancellationError() }
                        }
                    }
                    // Missing original contacts or locations are reviewed against the live record;
                    // blocking here would trap the keychain draft and skip staff recovery.
                    guard currentAuthority() else { return }
                    recoveryLoaded = true
                    draft = saved.draft; pendingWrite = saved.pending ?? .reviewDraft; consentKey = saved.consentKey
                    saveNeedsReconciliation = true
                    saveError = saved.pending == nil ? "Check saved edits against the current customer record." : "A change may have saved. Check the customer record before continuing."
                    return
                    }
                }
                recoveryLoaded = true
            } catch {
                recoveryLoaded = false
                loadError = "Connect to verify and open saved customer changes."
                return
            }
        }
        // A retry starts clean, so "Try again" shows the skeleton instead of the old failure.
        loadError = nil
        do {
            let record = try await api.fieldCustomer(customerID)
            guard currentAuthority() else { return }
            let contacts = try await api.fieldContacts(customerID)
            guard currentAuthority() else { return }
            let locations = try await api.fieldLocations(customerID)
            guard currentAuthority() else { return }
            let consent: CustomerSmsConsent?
            let consentKnown: Bool
            do { consent = try await api.customerSmsConsent(customerID); consentKnown = true }
            catch { consent = nil; consentKnown = false }
            guard currentAuthority(), draft == nil else { return }
            draft = CustomerSelfEditDraft(record: record, contacts: contacts, locations: locations, smsConsent: consent, consentKnown: consentKnown)
        } catch is CancellationError {
        } catch {
            loadError = error.customerSentence(.openDetails)
        }
    }

    /// Customer record first, then contacts, addresses and the text decision. Each step is its own
    /// audited write; the draft is rebased after each one so a retry doesn't repeat finished work.
    func save(api: APIClient, currentAuthority: @escaping @MainActor () -> Bool = { true }) async {
        guard currentAuthority(), var current = draft else { return }
        guard recoveryScope != nil else { saveError = "Customer changes can't be secured on this device. Try again."; return }
        guard !saveNeedsReconciliation else {
            saveError = "Some changes may have saved. Check the customer record before trying again."
            return
        }
        saving = true
        defer { saving = false }
        saveError = nil
        var writeInFlight = false
        let generation = api.requestGeneration
        let scopeRevision = api.savedCopyScopeRevision
        let copyScope = api.savedCopyScope
        let boundScope = recoveryScope
        func authority() -> Bool {
            currentAuthority() && api.requestGeneration == generation && api.savedCopyScopeRevision == scopeRevision &&
            api.savedCopyScope == copyScope && recoveryScope == boundScope && api.normalizedOrigin == boundScope?.origin
        }
        func confirmWrite() -> Bool {
            guard authority() else {
                saveNeedsReconciliation = true
                saveError = "Some changes may have saved. Check the customer record before trying again."
                return false
            }
            writeInFlight = false
            return true
        }
        do {
            try checkpoint(current, pending: nil)
            let needsGuardedWrite = !current.customerUpdate.isEmpty || !current.contactUpdates.isEmpty || !current.locationChanges.isEmpty
            if needsGuardedWrite {
                guard authority(), let scope = boundScope else { return }
                let capability = try await api.customerConditionalRead(customerID)
                guard authority(), capability.provenance.origin == scope.origin,
                      capability.value.id == customerID, capability.value.organizationId == scope.organizationID else { throw CancellationError() }
                guard capability.supportsConditionalWrites else {
                    saveError = "Customer changes can't be safely saved until the server supports protected updates. Your changes are kept on this device."
                    return
                }
                guard current.contactUpdates.allSatisfy({ change in current.conditionalContactBaselines?.contains(where: { $0.id == change.id && $0.customerId == customerID && $0.organizationId == scope.organizationID }) == true }),
                      current.locationChanges.allSatisfy({ change in current.conditionalLocationBaselines?.contains(where: { $0.id == change.id && $0.customerId == customerID && $0.organizationId == scope.organizationID }) == true }) else {
                    try checkpoint(current, pending: .reviewDraft)
                    saveNeedsReconciliation = true
                    saveError = "Review the current customer record before saving these kept changes."
                    return
                }
            }
            let update = current.customerUpdate
            if !update.isEmpty {
                guard authority() else { return }
                try checkpoint(current, pending: .customer)
                writeInFlight = true
                let record = try await api.updateFieldCustomerConditionally(customerID, request: current.conditionalCustomerUpdate())
                guard record.id == customerID, record.organizationId == recoveryScope?.organizationID else {
                    saveNeedsReconciliation = true; saveError = "The customer update couldn't be verified. Check the record before continuing."; return
                }
                guard confirmWrite() else { return }
                current = current.rebased(record: record)
                draft = current
                try checkpoint(current, pending: nil)
            }
            for change in current.contactUpdates {
                guard authority() else { return }
                try checkpoint(current, pending: .contact(change.id))
                writeInFlight = true
                guard let baseline = current.conditionalContactBaselines?.first(where: { $0.id == change.id }) else { throw CancellationError() }
                let saved = try await api.updateFieldContactConditionally(customerID, change.id, request: ConditionalContactUpdate(update: change.request, original: baseline))
                guard saved.id == change.id, saved.customerId == customerID, saved.organizationId == recoveryScope?.organizationID else {
                    saveNeedsReconciliation = true; saveError = "The contact update couldn't be verified. Check the record before continuing."; return
                }
                guard confirmWrite() else { return }
                current = current.rebased(contact: saved)
                draft = current
                try checkpoint(current, pending: nil)
            }
            if let create = current.newContact {
                guard authority() else { return }
                try checkpoint(current, pending: .createContact)
                writeInFlight = true
                let created = try await api.createFieldContact(customerID, request: create)
                guard created.customerId == customerID, created.organizationId == recoveryScope?.organizationID else {
                    saveNeedsReconciliation = true; saveError = "The contact couldn't be verified. Check the record before continuing."; return
                }
                guard confirmWrite() else { return }
                current.newContactName = ""; current.newContactPhone = ""; current.newContactEmail = ""
                draft = current
                try checkpoint(current, pending: nil)
            }
            if !current.locationChanges.isEmpty {
                guard authority() else { return }
                let records = try await api.allLocationsForRecovery(customerID, currentAuthority: authority)
                guard authority() else { return }
                for change in current.locationChanges {
                    guard authority() else { return }
                    guard let existing = records.first(where: { $0.id == change.id }),
                          existing.organizationId == recoveryScope?.organizationID, existing.customerId == customerID else {
                        try checkpoint(current, pending: .reviewDraft)
                        saveNeedsReconciliation = true
                        saveError = "A service location changed or was removed. Review the customer record before saving."
                        return
                    }
                    try checkpoint(current, pending: .location(change.id))
                    writeInFlight = true
                    guard let baseline = current.conditionalLocationBaselines?.first(where: { $0.id == change.id }) else { throw CancellationError() }
                    let saved = try await api.updateFieldLocationConditionally(customerID, change.id, request: ConditionalLocationUpdate(address: change.address, original: baseline))
                    guard saved.id == change.id, saved.customerId == customerID, saved.organizationId == recoveryScope?.organizationID else {
                        saveNeedsReconciliation = true; saveError = "The location update couldn't be verified. Check the record before continuing."; return
                    }
                    guard confirmWrite() else { return }
                    current = current.rebased(location: saved)
                    draft = current
                    try checkpoint(current, pending: nil)
                }
            }
            if let texts = current.textsChange {
                guard authority() else { return }
                guard current.consentBaselineKnown == true else {
                    try checkpoint(current, pending: .reviewDraft)
                    saveNeedsReconciliation = true
                    saveError = "Check the current text preference before saving the kept changes."
                    return
                }
                try checkpoint(current, pending: .consent)
                writeInFlight = true
                let savedConsent = try await api.recordCustomerSmsConsent(
                    customerID, grant: texts, expectedVersion: current.originalConsentVersion, idempotencyKey: consentKey,
                    evidenceRef: "Customer chose this themselves in customer mode on staff's Thorbis iPhone app")
                guard confirmWrite() else { return }
                current = current.rebased(consent: savedConsent)
                draft = current
                try checkpoint(current, pending: nil)
            }
            guard let recoveryScope else { throw CancellationError() }
            try recoveryStore.save(.init(draft: current, pending: nil, consentKey: consentKey, completed: true), scope: recoveryScope)
            savedAll = true
            try? recoveryStore.remove(scope: recoveryScope)
        } catch is CancellationError {
            if writeInFlight { saveNeedsReconciliation = true; saveError = "Some changes may have saved. Check the customer record before trying again." }
        } catch {
            if writeInFlight || pendingWrite != nil {
                saveNeedsReconciliation = true
                saveError = "Some changes may have saved. Check the customer record before trying again."
            } else {
                saveError = error.isConnectivityFailure ? "Saving needs a connection. Try again when you have signal." : error.localizedDescription
            }
        }
    }}

/// The customer's side: check and fix their details. `done` leaves this form (hand back, or back to
/// Customer view); nothing is saved here.
struct CustomerSelfEditForm: View {
    @ObservedObject var model: CustomerSelfEditModel
    var doneTitle = "Done"
    var currentAuthority: @MainActor () -> Bool = { true }
    let done: () -> Void
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @State private var showErrors = false
    @FocusState private var focused: Bool

    private var businessName: String { session.activeOrganization?.name ?? "us" }

    var body: some View {
        Group {
        if model.saveNeedsReconciliation {
            VStack(spacing: 20) {
                Spacer()
                Text("Your technician needs to check a previous change.")
                    .font(Theme.customerFont(CustomerModeStyle.body)).multilineTextAlignment(.center)
                CustomerCommitButton(title: "Hand back to the technician", icon: "hand.wave", action: done)
                Spacer()
            }.padding(Theme.gutter)
        } else if let draft = Binding($model.draft) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your details").font(Theme.customerFont(34, weight: .bold)).tracking(-0.68)
                            .accessibilityAddTraits(.isHeader)
                        Text("Check what \(businessName) has on file and fix anything that's wrong.")
                            .font(Theme.customerFont(CustomerModeStyle.body)).foregroundStyle(Theme.muted)
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
                                Text("Text me about my appointments").font(Theme.customerFont(CustomerModeStyle.body, weight: .medium))
                                Text("On my way, arrival and job updates. Reply STOP any time.")
                                    .font(Theme.customerFont(CustomerModeStyle.smallest)).foregroundStyle(Theme.muted)
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
                        Text("Add someone").font(Theme.customerFont(CustomerModeStyle.smallest, weight: .medium)).foregroundStyle(Theme.muted).padding(.top, 2)
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
                CustomerCommitButton(title: doneTitle) {
                    focused = false
                    if draft.wrappedValue.isValid { done() } else { showErrors = true }
                }
                .frame(maxWidth: CustomerModeStyle.readableWidth)
                .padding(.horizontal, Theme.gutter).padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(Theme.canvas)
            }
        } else if let loadError = model.loadError {
            ScrollView {
                CustomerStateMessage(symbol: "person.crop.circle.badge.exclamationmark", title: "We couldn’t open your details",
                                     message: loadError, actionTitle: "Try again") { Task { await model.load(api: api, currentAuthority: currentAuthority) } }
                    .frame(maxWidth: CustomerModeStyle.readableWidth, alignment: .leading)
                    .padding(.horizontal, Theme.gutter)
                    .frame(maxWidth: .infinity)
            }
        } else {
            ScrollView {
                CustomerSkeleton(caption: "Opening your details…", lines: 4, heading: false, amounts: false)
                    .frame(maxWidth: CustomerModeStyle.readableWidth, alignment: .leading)
                    .padding(.horizontal, Theme.gutter).padding(.top, 16)
                    .frame(maxWidth: .infinity)
            }
        }
        }
        .task {
            guard model.bindRecovery(api: api, session: session) else { return }
            await model.load(api: api, currentAuthority: currentAuthority)
        }
    }

    // MARK: Pieces

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Theme.customerFont(CustomerModeStyle.smallest, weight: .semibold)).foregroundStyle(Theme.muted)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(.bottom, 24)
    }

    private func field(_ label: String, text: Binding<String>, content: UITextContentType? = nil,
                       keyboard: UIKeyboardType = .default, axis: Axis = .horizontal, error: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(Theme.customerFont(CustomerModeStyle.smallest)).foregroundStyle(Theme.muted)
                TextField("", text: text, axis: axis)
                    .font(Theme.customerFont(CustomerModeStyle.body))
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
            .panelBackground(cornerRadius: 12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(error == nil ? Theme.border : Theme.destructive))
            if let error { Text(error).font(Theme.customerFont(CustomerModeStyle.smallest)).foregroundStyle(Theme.destructive) }
        }
    }

    private func choice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Theme.customerFont(CustomerModeStyle.body, weight: .medium))
                .frame(maxWidth: .infinity).frame(height: CustomerModeStyle.commitHeight)
                .foregroundStyle(selected ? Theme.brandText : Theme.foreground)
                .background(selected ? Theme.brandSurface : Theme.card, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Theme.brandText : Theme.border))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The technician's side, after unlocking: review the customer's changes, then save under staff's name.
struct CustomerSelfEditReview: View {
    @ObservedObject var model: CustomerSelfEditModel
    var currentAuthority: @MainActor () -> Bool = { true }
    let onFinished: () -> Void
    @EnvironmentObject private var api: APIClient
    @State private var keepConflictingEdits: Bool?

    var body: some View {
        NavigationStack {
            Group { if model.savedAll { saved } else if model.saveNeedsReconciliation { recovery } else { review } }
                .background(Theme.canvas)
                .foregroundStyle(Theme.foreground)
                .navigationTitle("Customer view")
                .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(model.saving)
    }

    private var recovery: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Check the last change").font(Theme.customerFont(24, weight: .medium))
                Text("A previous request may have saved. Your other edits are kept on this device. Check the customer record before continuing.")
                    .font(Theme.customerFont(15)).foregroundStyle(Theme.muted)
                if let message = model.saveError { Text(message).font(Theme.customerFont(13)).foregroundStyle(Theme.destructive) }
                if let evidence = model.recoveryEvidence {
                    Text("Current customer record").font(Theme.customerFont(17, weight: .medium))
                    Text(evidence.record.name).font(Theme.customerFont(15))
                    if let phone = evidence.record.phone { Text(phone).font(Theme.customerFont(15)) }
                    if let email = evidence.record.email { Text(email).font(Theme.customerFont(15)) }
                    if !model.recoveryConflicts.isEmpty {
                        Text("These details changed in both places").font(Theme.customerFont(17, weight: .medium))
                        ForEach(model.recoveryConflicts) { conflict in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(conflict.label).font(Theme.customerFont(15, weight: .medium))
                                Text("Your edit: \(conflict.mine)")
                                Text("On the record: \(conflict.current)")
                            }.font(Theme.customerFont(15)).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Button(keepConflictingEdits == true ? "✓ Keep my edits" : "Keep my edits") { keepConflictingEdits = true }
                            .frame(minHeight: 44)
                            .disabled(model.recoveryHasRemovedTargets)
                        Button(keepConflictingEdits == false ? "✓ Use the record's values" : "Use the record's values") { keepConflictingEdits = false }
                            .frame(minHeight: 44)
                        if keepConflictingEdits == nil { Text("Choose which values to keep before continuing.").font(Theme.customerFont(13)).foregroundStyle(Theme.muted) }
                        if model.recoveryHasRemovedTargets { Text("A contact or location was removed. Restore it before keeping its edit, or use the record's values.").font(Theme.customerFont(13)).foregroundStyle(Theme.muted) }
                    }
                    if case .createContact = model.pendingWrite {
                        Text("Contacts now on this customer").font(Theme.customerFont(17, weight: .medium))
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(evidence.contacts) { contact in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(contact.name)
                                    if let phone = contact.phone { Text(phone).foregroundStyle(Theme.muted) }
                                    if let email = contact.email { Text(email).foregroundStyle(Theme.muted) }
                                }.font(Theme.customerFont(15)).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        if model.matchingNewContacts.isEmpty {
                            Text("The new contact isn't confirmed yet. Check again before making another contact.")
                                .font(Theme.customerFont(15)).foregroundStyle(Theme.muted)
                        } else {
                            Text("A new contact matches the details you entered. Confirm only if you found it above.")
                                .font(Theme.customerFont(15)).foregroundStyle(Theme.muted)
                            PrimaryButton(title: "The contact is listed") {
                                model.resolveRecovery(contactAlreadySaved: true, keepConflictingEdits: keepConflictingEdits, currentAuthority: currentAuthority)
                            }
                            .disabled((!model.recoveryConflicts.isEmpty && keepConflictingEdits == nil) || (model.recoveryHasRemovedTargets && keepConflictingEdits == true))
                        }
                    } else {
                        PrimaryButton(title: "Use the current record") {
                            model.resolveRecovery(contactAlreadySaved: false, keepConflictingEdits: keepConflictingEdits, currentAuthority: currentAuthority)
                        }
                        .disabled((!model.recoveryConflicts.isEmpty && keepConflictingEdits == nil) || (model.recoveryHasRemovedTargets && keepConflictingEdits == true))
                    }
                }
                PrimaryButton(title: model.recoveryEvidence == nil ? "Check customer record" : "Check again", busy: model.checkingRecovery) {
                    Task { await model.inspectRecovery(api: api, currentAuthority: currentAuthority) }
                }
                Button("Done") { onFinished() }.font(Theme.customerFont(15, weight: .medium)).frame(minHeight: 44)
            }
            .frame(maxWidth: CustomerModeStyle.readableWidth, alignment: .leading)
            .padding(Theme.gutter).frame(maxWidth: .infinity)
        }
    }

    private var review: some View {
        let changes = model.draft?.changeSummary ?? []
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Review changes").font(Theme.customerFont(24, weight: .medium)).tracking(-0.36)
                    .accessibilityAddTraits(.isHeader)
                Text("These save to the customer's record and activity under your name.")
                    .font(Theme.customerFont(15)).foregroundStyle(Theme.muted)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(changes.enumerated()), id: \.offset) { index, line in
                        Text(line).font(Theme.customerFont(15)).padding(.vertical, 10)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                }
                .padding(.horizontal, 14)
                .panelBackground(cornerRadius: 12)
                if let saveError = model.saveError {
                    Text(saveError).font(Theme.customerFont(13)).foregroundStyle(Theme.destructive)
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
                PrimaryButton(title: "Save changes", busy: model.saving) { Task { await model.save(api: api, currentAuthority: currentAuthority) } }
                Button("Discard changes", role: .destructive) { onFinished() }
                    .font(Theme.customerFont(15, weight: .medium)).frame(minHeight: 44).disabled(model.saving)
            }
            .frame(maxWidth: CustomerModeStyle.readableWidth)
            .padding(.horizontal, Theme.gutter).padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Theme.canvas)
        }
    }

    private var saved: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle").font(.system(size: 44)).foregroundStyle(Theme.success).accessibilityHidden(true)
            Text("Customer details saved").font(Theme.customerFont(22, weight: .semibold))
            Spacer()
            PrimaryButton(title: "Done") { onFinished() }.frame(maxWidth: CustomerModeStyle.readableWidth)
        }
        .padding(.horizontal, Theme.gutter).padding(.bottom, 16)
        .frame(maxWidth: .infinity)
    }
}

/// Customer view without a job: just "Your details", in customer mode, then the staff review.
struct CustomerSelfEditView: View {
    let customerID: String
    let onFinished: () -> Void
    let currentAuthority: @MainActor () -> Bool
    @StateObject private var model: CustomerSelfEditModel
    @State private var staffReview = false

    init(customerID: String, currentAuthority: @escaping @MainActor () -> Bool = { true }, onFinished: @escaping () -> Void) {
        self.customerID = customerID
        self.onFinished = onFinished
        self.currentAuthority = currentAuthority
        _model = StateObject(wrappedValue: CustomerSelfEditModel(customerID: customerID))
    }

    var body: some View {
        if staffReview {
            CustomerSelfEditReview(model: model, currentAuthority: currentAuthority, onFinished: onFinished)
        } else {
            CustomerModeContainer(onUnlocked: {
                guard currentAuthority() else { return }
                if model.hasChanges || model.saveNeedsReconciliation { staffReview = true } else { onFinished() }
            }, authenticateOwner: customerHandoffAuthenticate) { handBack in
                CustomerSelfEditForm(model: model, currentAuthority: currentAuthority, done: handBack)
            }
        }
    }
}


extension CustomerSelfEditDraft {
    func hasRemovedEditedTargets(contacts latestContacts: [CustomerContactRecord], locations latestLocations: [ServiceLocationRecord]) -> Bool {
        contacts.contains { edited in
            guard let old = originalContacts.first(where: { $0.id == edited.id }) else { return false }
            return !latestContacts.contains(where: { $0.id == edited.id }) && edited != old
        } || locations.contains { edited in
            guard let old = originalLocations.first(where: { $0.id == edited.id }) else { return false }
            return !latestLocations.contains(where: { $0.id == edited.id }) && edited.address != old.address
        }
    }
    func recoveryConflicts(record: CustomerRecord, contacts latestContacts: [CustomerContactRecord], locations latestLocations: [ServiceLocationRecord]) -> [CustomerSelfEditConflict] {
        var conflicts: [CustomerSelfEditConflict] = []
        func add(_ label: String, _ original: String, _ edited: String, _ latest: String, id: String? = nil) {
            guard edited != original, latest != original, edited != latest else { return }
            conflicts.append(.init(id: id ?? label, label: label, mine: edited.isEmpty ? "Not set" : edited, current: latest.isEmpty ? "Not set" : latest))
        }
        add("Customer name", original.name, name, record.name)
        add("Customer phone", original.phone ?? "", phone, record.phone ?? "")
        add("Customer email", original.email ?? "", email, record.email ?? "")
        add("Billing address", original.address ?? "", address, record.address ?? "")
        add("Preferred contact", original.preferredContact ?? "", preferredContact ?? "", record.preferredContact ?? "")
        for edited in contacts {
            guard let old = originalContacts.first(where: { $0.id == edited.id }) else { continue }
            guard let latest = latestContacts.first(where: { $0.id == edited.id }) else {
                if edited != old { conflicts.append(.init(id: "contact-\(old.id)-removed", label: "\(old.name) · contact", mine: "Edited contact", current: "Removed from the record")) }
                continue
            }
            add("\(old.name) · name", old.name, edited.name, latest.name, id: "contact-\(old.id)-name")
            add("\(old.name) · phone", old.phone, edited.phone, latest.phone ?? "", id: "contact-\(old.id)-phone")
            add("\(old.name) · email", old.email, edited.email, latest.email ?? "", id: "contact-\(old.id)-email")
        }
        for edited in locations {
            guard let old = originalLocations.first(where: { $0.id == edited.id }) else { continue }
            guard let latest = latestLocations.first(where: { $0.id == edited.id }) else {
                if edited.address != old.address { conflicts.append(.init(id: "location-\(old.id)-removed", label: "\(old.label) · address", mine: edited.address, current: "Removed from the record")) }
                continue
            }
            add("\(old.label) · address", old.address, edited.address, latest.address, id: "location-\(old.id)-address")
        }
        return conflicts
    }
    func addingRecoveredContact(_ contact: CustomerContactRecord) -> Self {
        var copy = self
        guard !copy.originalContacts.contains(where: { $0.id == contact.id }) else { return copy }
        let value = Contact(id: contact.id, name: contact.name, phone: contact.phone ?? "", email: contact.email ?? "")
        copy.originalContacts.append(value); copy.contacts.append(value)
        copy.conditionalContactBaselines?.append(ConditionalContactBaseline(contact))
        return copy
    }
    /// Keep explicit customer edits while adopting newer server values for fields they never touched.
    func mergingRecovery(record: CustomerRecord, contacts latestContacts: [CustomerContactRecord], locations latestLocations: [ServiceLocationRecord],
                         preferServerForConflicts: Bool = false) -> Self {
        var copy = self
        copy.conditionalContactBaselines = latestContacts.map(ConditionalContactBaseline.init)
        copy.conditionalLocationBaselines = latestLocations.map(ConditionalLocationBaseline.init)
        func useLatest<T: Equatable>(_ old: T, _ edited: T, _ latest: T) -> Bool {
            edited == old || (preferServerForConflicts && latest != old && edited != latest)
        }
        if useLatest(original.name, name, record.name) { copy.name = record.name }
        if useLatest(original.phone ?? "", phone, record.phone ?? "") { copy.phone = record.phone ?? "" }
        if useLatest(original.email ?? "", email, record.email ?? "") { copy.email = record.email ?? "" }
        if useLatest(original.address ?? "", address, record.address ?? "") { copy.address = record.address ?? "" }
        if useLatest(original.preferredContact, preferredContact, record.preferredContact) { copy.preferredContact = record.preferredContact }
        copy.original = record
        do {
            let contactIDs = Set(latestContacts.map(\.id)), locationIDs = Set(latestLocations.map(\.id))
            let removedContacts = Set(originalContacts.filter { old in
                !contactIDs.contains(old.id) && (preferServerForConflicts || contacts.first(where: { $0.id == old.id }) == old)
            }.map(\.id))
            let removedLocations = Set(originalLocations.filter { old in
                !locationIDs.contains(old.id) && (preferServerForConflicts || locations.first(where: { $0.id == old.id }) == old)
            }.map(\.id))
            copy.contacts.removeAll { removedContacts.contains($0.id) }
            copy.originalContacts.removeAll { removedContacts.contains($0.id) }
            copy.locations.removeAll { removedLocations.contains($0.id) }
            copy.originalLocations.removeAll { removedLocations.contains($0.id) }
        }
        for latest in latestContacts {
            guard let originalIndex = copy.originalContacts.firstIndex(where: { $0.id == latest.id }),
                  let draftIndex = copy.contacts.firstIndex(where: { $0.id == latest.id }) else { continue }
            let old = copy.originalContacts[originalIndex]
            let fresh = Contact(id: latest.id, name: latest.name, phone: latest.phone ?? "", email: latest.email ?? "")
            if useLatest(old.name, copy.contacts[draftIndex].name, fresh.name) { copy.contacts[draftIndex].name = fresh.name }
            if useLatest(old.phone, copy.contacts[draftIndex].phone, fresh.phone) { copy.contacts[draftIndex].phone = fresh.phone }
            if useLatest(old.email, copy.contacts[draftIndex].email, fresh.email) { copy.contacts[draftIndex].email = fresh.email }
            copy.originalContacts[originalIndex] = fresh
        }
        for latest in latestLocations {
            guard let originalIndex = copy.originalLocations.firstIndex(where: { $0.id == latest.id }),
                  let draftIndex = copy.locations.firstIndex(where: { $0.id == latest.id }) else { continue }
            let old = copy.originalLocations[originalIndex]
            let fresh = Location(id: latest.id, label: latest.label, address: latest.address)
            if useLatest(old.address, copy.locations[draftIndex].address, fresh.address) { copy.locations[draftIndex].address = fresh.address }
            copy.originalLocations[originalIndex] = fresh
        }
        return copy
    }
    /// After a step saves, later steps compare against what the server now holds.
    func rebased(record: CustomerRecord) -> Self {
        var copy = self
        copy.original = record
        return copy
    }

    func rebased(contact: CustomerContactRecord) -> Self {
        var copy = self
        if let index = copy.conditionalContactBaselines?.firstIndex(where: { $0.id == contact.id }) {
            copy.conditionalContactBaselines?[index] = ConditionalContactBaseline(contact)
        }
        if let index = copy.originalContacts.firstIndex(where: { $0.id == contact.id }) {
            copy.originalContacts[index] = Contact(id: contact.id, name: contact.name, phone: contact.phone ?? "", email: contact.email ?? "")
        }
        return copy
    }

    func rebased(location: ServiceLocationRecord) -> Self {
        var copy = self
        if let index = copy.conditionalLocationBaselines?.firstIndex(where: { $0.id == location.id }) {
            copy.conditionalLocationBaselines?[index] = ConditionalLocationBaseline(location)
        }
        if let index = copy.originalLocations.firstIndex(where: { $0.id == location.id }) {
            copy.originalLocations[index] = Location(id: location.id, label: location.label, address: location.address)
        }
        return copy
    }

    func rebased(consent: CustomerSmsConsent?) -> Self {
        var copy = self
        copy.originalTexts = consent.map { $0.decision == "grant" }
        copy.originalConsentVersion = consent?.version
        copy.consentBaselineKnown = true
        return copy
    }
}

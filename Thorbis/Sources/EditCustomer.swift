import SwiftUI

// Paper 48C "Edit customer": the office's own edit of a customer's details. A sheet with Cancel,
// the title and Save in one row, then the details in cards. Everything saves through the canonical
// routes: the customer record (`POST /v1/customers/{id}`, customers.update) and, where the
// address or notes live on a service location, that location (`POST /v1/customers/{id}/locations/{id}`).
// Property type (House / Condo / Rental / Business) has no server field, so it is not shown.
// "Archive customer" under the cards opens Paper 48B (see the end of this file).

// MARK: - API

/// `customers.update` body for this screen. Omitted leaves a field alone, null clears it
/// (updateCustomerInputSchema is nullish). Only what changed is sent.
struct EditCustomerUpdate: Encodable {
    var name: String? = nil
    var email: FieldContactPatch<String> = .unchanged
    var phone: FieldContactPatch<String> = .unchanged
    var address: FieldContactPatch<String> = .unchanged
    var referralSource: FieldContactPatch<String> = .unchanged
    var preferredContact: FieldContactPatch<String> = .unchanged

    var isEmpty: Bool {
        guard name == nil else { return false }
        for patch in [email, phone, address, referralSource, preferredContact] {
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
        try Self.encode(referralSource, forKey: .referralSource, in: &container)
        try Self.encode(preferredContact, forKey: .preferredContact, in: &container)
    }

    private enum CodingKeys: String, CodingKey { case name, email, phone, address, referralSource, preferredContact }

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
    /// `POST /v1/customers/{id}` (customers.update, customer.edit). The server keeps the change set
    /// in the customer's audit log.
    func saveCustomerEdit(_ customerID: String, request: EditCustomerUpdate) async throws -> CustomerRecord {
        guard UUID(uuidString: customerID) != nil else {
            throw Problem(title: "Invalid record ID", status: nil, detail: customerID)
        }
        return try await send("POST", "/v1/customers/\(customerID)", body: request)
    }
}

// MARK: - Draft

/// What the person changed. Pure, so the save plan is testable without a screen.
///
/// Where each address lives:
/// - Service address: the first service location when there is one, otherwise the customer's own
///   address (New customer keeps the service address there).
/// - Billing address: a billing location when there is one; otherwise the customer's own address
///   when a service location holds the service address. With neither, there is only one address,
///   so "Billing same as service" is not offered.
/// - Notes: the service location's notes. The customer record itself has no notes field.
struct EditCustomerDraft: Equatable {
    enum AddressStore: Equatable {
        case customer
        case location(String)
    }

    /// One location save: the new address (nil leaves it) and the notes when they changed.
    struct LocationEdit: Equatable {
        let id: String
        var address: String?
        var notesChanged: Bool
        /// The new notes; nil clears them. Read only when `notesChanged`.
        var notes: String?
    }

    struct ContactOption: Identifiable, Sendable {
        let value: String
        let label: String
        var id: String { value }
    }

    /// Paper's order: Text, Call, Email (contactMethodSchema sms / phone / email).
    static let contactOptions = [ContactOption(value: "sms", label: "Text"), ContactOption(value: "phone", label: "Call"),
                                 ContactOption(value: "email", label: "Email")]

    private(set) var original: CustomerRecord
    private(set) var originalService: ServiceLocationRecord?
    private(set) var originalBilling: ServiceLocationRecord?

    var name: String
    var phone: String
    var email: String
    var serviceAddress: String
    var billingSameAsService: Bool
    var billingAddress: String
    var referralSource: String
    var preferredContact: String?
    var notes: String

    init(record: CustomerRecord, locations: [ServiceLocationRecord]) {
        original = record
        originalService = locations.first(where: { $0.kind == "service" })
        originalBilling = locations.first(where: { $0.kind == "billing" })
        name = record.name
        phone = record.phone ?? ""
        email = record.email ?? ""
        referralSource = record.referralSource ?? ""
        preferredContact = record.preferredContact
        let service = originalService?.address ?? record.address ?? ""
        serviceAddress = service
        notes = originalService?.notes ?? ""
        let billing: String
        if let originalBilling { billing = originalBilling.address }
        else if originalService != nil { billing = record.address ?? "" }
        else { billing = "" }
        billingAddress = billing
        billingSameAsService = Self.clean(billing).isEmpty || Self.same(billing, service)
    }

    // MARK: Where things live

    var serviceStore: AddressStore { originalService.map { .location($0.id) } ?? .customer }

    var billingStore: AddressStore? {
        if let originalBilling { return .location(originalBilling.id) }
        return originalService == nil ? nil : .customer
    }

    /// "Billing same as service" shows only when billing has somewhere of its own to live.
    var offersBillingChoice: Bool { billingStore != nil }

    /// Notes need a service location to hold them.
    var holdsNotes: Bool { originalService != nil }

    private var originalBillingAddress: String {
        if let originalBilling { return originalBilling.address }
        return originalService == nil ? "" : (original.address ?? "")
    }

    /// The billing address to store, or nil to leave it. Same as service keeps an empty billing
    /// address empty (empty already means "same"); otherwise it follows the service address.
    var desiredBilling: String? {
        guard billingStore != nil else { return nil }
        if billingSameAsService {
            return Self.clean(originalBillingAddress).isEmpty ? nil : Self.clean(serviceAddress)
        }
        return Self.clean(billingAddress)
    }

    // MARK: Validation (said under the field once Save is pressed)

    var nameError: String? {
        let value = Self.clean(name)
        if value.isEmpty { return "Add a name, like Danielle Marlowe." }
        if value.count > 200 { return "Keep the name to 200 characters." }
        return nil
    }

    var phoneError: String? { Self.clean(phone).count > 30 ? "Keep the phone number to 30 characters." : nil }

    var emailError: String? {
        let value = Self.clean(email)
        guard !value.isEmpty else { return nil }
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."), !parts[1].hasPrefix("."),
              !parts[1].hasSuffix("."), !value.contains(" ") else {
            return "Check the email address, like danielle@example.com."
        }
        return nil
    }

    var serviceAddressError: String? {
        let value = Self.clean(serviceAddress)
        if value.isEmpty, serviceStore != .customer { return "Enter the service address." }
        if value.count > 500 { return "Keep the address to 500 characters." }
        return nil
    }

    var billingAddressError: String? {
        guard offersBillingChoice, !billingSameAsService else { return nil }
        let value = Self.clean(billingAddress)
        if value.isEmpty, let store = billingStore, store != .customer { return "Enter the billing address." }
        if value.count > 500 { return "Keep the address to 500 characters." }
        return nil
    }

    var referralError: String? { Self.clean(referralSource).count > 120 ? "Keep this to 120 characters." : nil }

    var notesError: String? { Self.clean(notes).count > 2000 ? "Keep notes to 2,000 characters." : nil }

    var isValid: Bool {
        nameError == nil && phoneError == nil && emailError == nil && serviceAddressError == nil &&
        billingAddressError == nil && referralError == nil && notesError == nil
    }

    // MARK: Save plan

    var customerUpdate: EditCustomerUpdate {
        var update = EditCustomerUpdate()
        let cleanedName = Self.clean(name)
        if cleanedName != original.name { update.name = cleanedName }
        update.phone = Self.patch(phone, from: original.phone)
        update.email = Self.patch(email, from: original.email)
        update.referralSource = Self.patch(referralSource, from: original.referralSource)
        if preferredContact != original.preferredContact {
            update.preferredContact = preferredContact.map { .value($0) } ?? .clear
        }
        if serviceStore == AddressStore.customer {
            update.address = Self.patch(serviceAddress, from: original.address)
        } else if billingStore == AddressStore.customer, let billing = desiredBilling {
            update.address = Self.patch(billing, from: original.address)
        }
        return update
    }

    var serviceLocationEdit: LocationEdit? {
        guard let service = originalService else { return nil }
        let address = Self.clean(serviceAddress)
        let cleanedNotes = Self.clean(notes)
        let addressChanged = address != service.address
        let notesChanged = cleanedNotes != (service.notes ?? "")
        guard addressChanged || notesChanged else { return nil }
        return LocationEdit(id: service.id, address: addressChanged ? address : nil, notesChanged: notesChanged,
                            notes: cleanedNotes.isEmpty ? nil : cleanedNotes)
    }

    var billingLocationEdit: LocationEdit? {
        guard let billing = originalBilling, let desired = desiredBilling, desired != billing.address else { return nil }
        return LocationEdit(id: billing.id, address: desired, notesChanged: false, notes: nil)
    }

    var hasChanges: Bool { !customerUpdate.isEmpty || serviceLocationEdit != nil || billingLocationEdit != nil }

    /// The full location body for `edit`, carrying every other stored value through: the update
    /// route writes each field it is given, so a missing one would be cleared. The map pin goes
    /// only when the address moved (it belonged to the old address).
    static func locationUpdate(_ edit: LocationEdit, existing: ServiceLocationRecord) -> FieldLocationUpdate {
        let address = edit.address ?? existing.address
        let moved = address != existing.address
        return FieldLocationUpdate(label: existing.label, kind: existing.kind, address: address,
                                   notes: edit.notesChanged ? edit.notes : existing.notes,
                                   coordinates: moved ? nil : existing.coordinates, gateCode: existing.gateCode,
                                   alarmCode: existing.alarmCode, dogOnSite: existing.dogOnSite, parking: existing.parking)
    }

    // MARK: Rebase (a retry doesn't repeat finished work)

    func rebased(record: CustomerRecord) -> Self {
        var copy = self
        copy.original = record
        return copy
    }

    func rebased(location: ServiceLocationRecord) -> Self {
        var copy = self
        if copy.originalService?.id == location.id { copy.originalService = location }
        if copy.originalBilling?.id == location.id { copy.originalBilling = location }
        return copy
    }

    // MARK: Helpers

    static func clean(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }

    private static func same(_ lhs: String, _ rhs: String) -> Bool {
        clean(lhs).caseInsensitiveCompare(clean(rhs)) == .orderedSame
    }

    private static func patch(_ value: String, from before: String?) -> FieldContactPatch<String> {
        let cleaned = clean(value)
        if cleaned == (before ?? "") { return .unchanged }
        return cleaned.isEmpty ? .clear : .value(cleaned)
    }
}

// MARK: - Model

@MainActor
final class EditCustomerModel: ObservableObject {
    let customerID: String
    @Published var draft: EditCustomerDraft?
    @Published private(set) var loadError: String?
    @Published private(set) var saving = false
    @Published private(set) var saveError: String?

    init(customerID: String) { self.customerID = customerID }

    func load(api: APIClient) async {
        guard draft == nil else { return }
        loadError = nil
        do {
            let record = try await api.fieldCustomer(customerID, requireFresh: true)
            let locations = try await api.fieldLocations(customerID)
            guard draft == nil else { return }
            draft = EditCustomerDraft(record: record, locations: locations)
        } catch is CancellationError {
        } catch {
            loadError = error.plainMessage(subject: "this customer")
        }
    }

    /// The customer record first, then the service and billing locations. Each is its own audited
    /// write; the draft is rebased after each so a retry only sends what is still unsaved.
    /// Returns the saved record when everything went through.
    func save(api: APIClient) async -> CustomerRecord? {
        guard var current = draft, !saving else { return nil }
        saving = true
        defer { saving = false }
        saveError = nil
        do {
            let update = current.customerUpdate
            if !update.isEmpty {
                let record = try await api.saveCustomerEdit(customerID, request: update)
                current = current.rebased(record: record)
                draft = current
            }
            let edits = [current.serviceLocationEdit, current.billingLocationEdit].compactMap { $0 }
            if !edits.isEmpty {
                // The latest stored values, so the gate code, pin and the rest carry through untouched.
                let records = try await api.fieldLocations(customerID)
                for edit in edits {
                    guard let existing = records.first(where: { $0.id == edit.id }) else { continue }
                    let saved = try await api.updateFieldLocation(customerID, edit.id,
                                                                  request: EditCustomerDraft.locationUpdate(edit, existing: existing))
                    current = current.rebased(location: saved)
                    draft = current
                }
            }
            return current.original
        } catch is CancellationError {
            return nil
        } catch {
            saveError = error.isConnectivityFailure ? "Saving needs a connection. Try again when you have signal."
                                                    : error.plainMessage(subject: "this customer")
            return nil
        }
    }
}

// MARK: - Screen

/// Paper 48C "Edit customer". Present as a sheet from the customer's page; `onSaved` gets the
/// saved record so the page can reload.
struct EditCustomerSheet: View {
    let customerID: String
    var onSaved: (CustomerRecord) -> Void = { _ in }
    /// Paper 48C's "Archive customer" under the cards: closes the sheet, then the customer's page
    /// opens Archive customer (48B). Nil leaves the link out.
    var onArchive: (() -> Void)? = nil
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: EditCustomerModel
    @State private var showErrors = false
    @State private var editingReferral = false
    @FocusState private var focused: Field?

    private enum Field: Hashable { case name, phone, email, service, billing, notes }

    init(customerID: String, onSaved: @escaping (CustomerRecord) -> Void = { _ in }, onArchive: (() -> Void)? = nil) {
        self.customerID = customerID
        self.onSaved = onSaved
        self.onArchive = onArchive
        _model = StateObject(wrappedValue: EditCustomerModel(customerID: customerID))
    }

    private var canEdit: Bool { session.can("customer.edit", feature: "core_crm") }
    private var canArchive: Bool { session.can("customer.archive", feature: "core_crm") }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 12) { content }
                    .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 32)
                    .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.sidebar.ignoresSafeArea())
        .thorbisSheetPresentation([.large])
        .interactiveDismissDisabled(model.saving || model.draft?.hasChanges == true)
        .task { await model.load(api: api) }
        .sheet(isPresented: $editingReferral) {
            if let draft = Binding($model.draft) {
                ReferralSourceSheet(value: draft.referralSource)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        ZStack {
            Text("Edit customer").font(Theme.font(17, weight: .semibold))
                .lineLimit(1).minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 100)
            HStack {
                Button { dismiss() } label: {
                    Text("Cancel").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                        .padding(.horizontal, 16).frame(minHeight: 44)
                        .background(Theme.card, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .disabled(model.saving)
                .accessibilityIdentifier("edit-customer-cancel")
                Spacer(minLength: 8)
                Button { Task { await commit() } } label: {
                    HStack(spacing: 6) {
                        if model.saving { ProgressView().tint(.white) }
                        Text("Save").font(Theme.font(16, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18).frame(minHeight: 44)
                    .background(Theme.brand, in: Capsule())
                    .opacity(canEdit && model.draft != nil ? 1 : 0.45)
                    .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .disabled(model.saving || !canEdit || model.draft == nil)
                .accessibilityHint(canEdit ? "" : "Your role can't edit customers.")
                .accessibilityIdentifier("edit-customer-save")
            }
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 2)
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if !canEdit {
            Text("Your role can't edit customers. Ask your office.")
                .font(Theme.font(13)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        if let saveError = model.saveError {
            ErrorBanner(message: saveError, outer: 0)
        }
        if let draft = Binding($model.draft) {
            form(draft)
        } else if let loadError = model.loadError {
            ErrorBanner(message: loadError, action: ErrorBanner.Action(title: "Try again", run: { await model.load(api: api) }),
                        outer: 0)
        } else {
            card { SkeletonRows(count: 3, leading: false, inset: 16) }
        }
    }

    @ViewBuilder private func form(_ draft: Binding<EditCustomerDraft>) -> some View {
        let value = draft.wrappedValue
        card {
            field("Name", text: draft.name, example: "Danielle Marlowe", focus: .name, content: .name,
                  error: showErrors ? value.nameError : nil, identifier: "edit-customer-name")
            WellDivider(leading: 16)
            field("Mobile", text: draft.phone, example: "(916) 555-0148", focus: .phone, content: .telephoneNumber,
                  keyboard: .phonePad, error: showErrors ? value.phoneError : nil, identifier: "edit-customer-phone")
            WellDivider(leading: 16)
            field("Email", text: draft.email, example: "danielle@example.com", focus: .email, content: .emailAddress,
                  keyboard: .emailAddress, error: showErrors ? value.emailError : nil, identifier: "edit-customer-email")
        }

        card {
            HStack(alignment: .center, spacing: 12) {
                field("Service address", text: draft.serviceAddress, example: "412 Birchwood Ln, Sacramento",
                      focus: .service, content: .fullStreetAddress, axis: .vertical,
                      error: showErrors ? value.serviceAddressError : nil, identifier: "edit-customer-service-address",
                      padded: false)
                PaperIcon(.formPin, size: 20, color: Theme.muted)
                    .frame(width: 20, height: 20).accessibilityHidden(true)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            if value.offersBillingChoice {
                WellDivider(leading: 16)
                Toggle(isOn: draft.billingSameAsService) {
                    Text("Billing same as service").font(Theme.font(16))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .tint(Theme.brand)
                .padding(.horizontal, 16).frame(minHeight: 56)
                .accessibilityIdentifier("edit-customer-billing-same")
                if !value.billingSameAsService {
                    WellDivider(leading: 16)
                    field("Billing address", text: draft.billingAddress, example: "PO Box 1180, Sacramento",
                          focus: .billing, content: .fullStreetAddress, axis: .vertical,
                          error: showErrors ? value.billingAddressError : nil, identifier: "edit-customer-billing-address")
                }
            }
        }

        card {
            Button { editingReferral = true } label: {
                HStack(spacing: 8) {
                    Text("How they found us").font(Theme.font(16)).foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    let source = EditCustomerDraft.clean(value.referralSource)
                    Text(source.isEmpty ? "Add" : source).font(Theme.font(16)).foregroundStyle(Theme.muted)
                        .lineLimit(1)
                    PaperChevron()
                        .foregroundStyle(Theme.subtle).accessibilityHidden(true)
                }
                .padding(.horizontal, 16).frame(minHeight: 56).contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .accessibilityLabel("How they found us")
            .accessibilityValue(EditCustomerDraft.clean(value.referralSource).isEmpty ? "Not set" : value.referralSource)
            .accessibilityIdentifier("edit-customer-referral")
            if showErrors, let referralError = value.referralError {
                FieldProblem(message: referralError).padding(.horizontal, 16).padding(.bottom, 10)
            }
            WellDivider(leading: 16)
            VStack(alignment: .leading, spacing: 8) {
                PreferredContactLabel(isSet: value.preferredContact != nil) { draft.wrappedValue.preferredContact = nil }
                ThorbisSegmented(options: EditCustomerDraft.contactOptions.map { (value: $0.value, label: $0.label) },
                                 selection: Binding(get: { draft.wrappedValue.preferredContact ?? "" },
                                                    set: { draft.wrappedValue.preferredContact = $0.isEmpty ? nil : $0 }))
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 14)
            .accessibilityIdentifier("edit-customer-preferred-contact")
        }

        card {
            VStack(alignment: .leading, spacing: 4) {
                Text("Notes").font(Theme.font(13)).foregroundStyle(Theme.muted)
                if value.holdsNotes {
                    TextField("", text: draft.notes, prompt: .placeholder("Gate code, parking, best time to visit"), axis: .vertical)
                        .font(Theme.font(15))
                        .lineLimit(2...10)
                        .focused($focused, equals: .notes)
                        .accessibilityLabel("Notes")
                        .accessibilityIdentifier("edit-customer-notes")
                    if showErrors, let notesError = value.notesError { FieldProblem(message: notesError) }
                } else {
                    Text("Notes are kept on a service location. Add one on the customer's page to keep notes here.")
                        .font(Theme.font(15)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        // Paper 48C: "Customer since 2022" (13) over a quiet red "Archive customer" (15 Medium, 44 tall).
        VStack(spacing: 4) {
            if let since = JobFiltering.date(value.original.createdAt) {
                Text("Customer since \(since.formatted(.dateTime.year()))")
                    .font(Theme.font(13)).foregroundStyle(Theme.subtle)
            }
            if let onArchive, canArchive, !value.original.archived {
                Button {
                    dismiss()
                    onArchive()
                } label: {
                    Text("Archive customer").font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.destructive)
                        .padding(.horizontal, 16).frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .disabled(model.saving)
                .accessibilityIdentifier("edit-customer-archive")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    // MARK: Pieces

    /// One Paper card: the card tone, radius 20, rows separated by an inset hairline.
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// A label above its answer (13 muted over 17 Medium), typed in place; the problem under it.
    private func field(_ label: String, text: Binding<String>, example: String, focus: Field,
                       content: UITextContentType? = nil, keyboard: UIKeyboardType = .default,
                       axis: Axis = .horizontal, error: String? = nil, identifier: String,
                       padded: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Theme.font(13)).foregroundStyle(Theme.muted)
            TextField("", text: text, prompt: .placeholder(example), axis: axis)
                .font(Theme.font(17, weight: .medium))
                .textContentType(content)
                .keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
                .autocorrectionDisabled(keyboard != .default)
                .lineLimit(axis == .vertical ? 1...3 : 1...1)
                .focused($focused, equals: focus)
                .accessibilityLabel(label)
                .accessibilityIdentifier(identifier)
            if let error { FieldProblem(message: error) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, padded ? 16 : 0).padding(.vertical, padded ? 12 : 0)
    }

    // MARK: Save

    private func commit() async {
        focused = nil
        showErrors = true
        guard canEdit, let draft = model.draft, draft.isValid else { return }
        guard draft.hasChanges else { dismiss(); return }
        if let saved = await model.save(api: api) {
            onSaved(saved)
            dismiss()
        }
    }
}

/// "How they found us": the server keeps it as free words (up to 120 characters), so it is typed,
/// not picked from a list.
struct ReferralSourceSheet: View {
    @Binding var value: String
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        ThorbisModalSheet(title: "How they found us", closeLabel: "Cancel", onClose: { dismiss() },
                          detents: [.medium], commitTitle: "Done", commitIdentifier: "edit-customer-referral-done",
                          commit: {
                              value = EditCustomerDraft.clean(text)
                              dismiss()
                          }) {
            TextField("", text: $text, prompt: .placeholder("Neighbor referral"))
                .font(Theme.font(16))
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .onSubmit {
                    value = EditCustomerDraft.clean(text)
                    dismiss()
                }
                .focused($focused)
                .accessibilityLabel("How they found us")
                .fieldWell()
        }
        .onAppear {
            text = value
            focused = true
        }
    }
}

// MARK: - Archive and restore (Paper 48B, 48H)

// Archiving is `POST /v1/customers/{id}/archive` and restoring `POST /v1/customers/{id}/restore`
// (customers.archive / customers.restore, both under the customer.archive capability). Each takes
// an optional `reason` of up to 500 characters that the server keeps in the customer's audit log.
// The customer list carries no archive reason or date, so the archived list shows where each
// customer is instead.

/// `customers.archive` / `customers.restore` body: the reason is left out when there is none.
struct CustomerLifecycleBody: Encodable {
    var reason: String? = nil
}

@MainActor
extension APIClient {
    /// `POST /v1/customers/{id}/archive`. Jobs, invoices and equipment are kept.
    func archiveCustomer(_ customerID: String, reason: String?) async throws -> CustomerRecord {
        guard UUID(uuidString: customerID) != nil else {
            throw Problem(title: "Invalid record ID", status: nil, detail: customerID)
        }
        return try await send("POST", "/v1/customers/\(customerID)/archive", body: CustomerLifecycleBody(reason: reason))
    }

    /// `POST /v1/customers/{id}/restore`. Puts the customer back in Customers.
    func restoreCustomer(_ customerID: String) async throws -> CustomerRecord {
        guard UUID(uuidString: customerID) != nil else {
            throw Problem(title: "Invalid record ID", status: nil, detail: customerID)
        }
        return try await send("POST", "/v1/customers/\(customerID)/restore", body: CustomerLifecycleBody())
    }
}

/// Paper 48B's reasons, in Paper's order. Pure, so the words sent to the server are testable.
enum CustomerArchiveReason: String, CaseIterable, Identifiable {
    case movedAway = "Moved away"
    case duplicate = "Duplicate record"
    case noLonger = "No longer a customer"
    case other = "Other"

    var id: String { rawValue }

    /// The reason the server keeps: the choice, then the note in quotes (Other · “sold the
    /// rental”), cut to the server's 500 characters. Nil when there is nothing to say.
    static func text(_ reason: CustomerArchiveReason?, note: String) -> String? {
        let cleaned = note.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        if let reason { parts.append(reason.rawValue) }
        if !cleaned.isEmpty { parts.append(reason == nil ? cleaned : "\u{201C}\(cleaned)\u{201D}") }
        guard !parts.isEmpty else { return nil }
        return String(parts.joined(separator: " \u{00B7} ").prefix(500))
    }
}

/// Paper 48B "Archive customer". Push it with `.thorbisDestination`, which adds the round Back.
struct ArchiveCustomerView: View {
    let customerID: String
    let customerName: String
    /// Runs after the server confirms, before the screen closes, so the caller reloads.
    var onArchived: (CustomerRecord) async -> Void = { _ in }

    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @Environment(\.dismiss) private var dismiss
    @State private var reason: CustomerArchiveReason?
    @State private var note = ""
    @State private var busy = false
    @State private var error: String?

    private var canArchive: Bool { session.can("customer.archive", feature: "core_crm") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PaperHeader(title: "Archive customer", subtitle: customerName)
                    .environment(\.paperMenuButton, false)
                VStack(alignment: .leading, spacing: 12) {
                    PaperSection("Reason") {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(CustomerArchiveReason.allCases.enumerated()), id: \.element.id) { index, option in
                                if index > 0 { WellDivider(leading: 50) }
                                reasonRow(option)
                            }
                        }
                    }
                    TextField("", text: $note, prompt: .placeholder("Add a note"), axis: .vertical)
                        .font(Theme.font(16))
                        .lineLimit(1...4)
                        .textInputAutocapitalization(.sentences)
                        .accessibilityLabel("Note")
                        .accessibilityIdentifier("archive-customer-note")
                        .fieldWell()
                    Text("Their jobs and invoices are kept. You can restore them any time from Customers.")
                        .font(Theme.font(14)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                    if let error {
                        ListErrorRow(message: error)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, PaperCardMetrics.margin)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .foregroundStyle(Theme.foreground)
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { commitBar }
        .interactiveDismissDisabled(busy)
    }

    /// A radio row: a 22pt ring (brand with a dot when chosen) and the reason at 16 Medium, 56 tall.
    private func reasonRow(_ option: CustomerArchiveReason) -> some View {
        let chosen = reason == option
        return Button { reason = option } label: {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle().strokeBorder(chosen ? Theme.brand : Theme.borderStrong, lineWidth: chosen ? 2 : 1.5)
                    if chosen { Circle().fill(Theme.brand).frame(width: 10, height: 10) }
                }
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
                Text(option.rawValue).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityIdentifier("archive-customer-reason-\(option.id)")
    }

    private var commitBar: some View {
        VStack(spacing: 10) {
            if !canArchive {
                Text("Your role can't archive customers. Ask your office.")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
            Button { Task { await archive() } } label: {
                HStack(spacing: 8) {
                    if busy { ProgressView().tint(.white) }
                    Text("Archive customer")
                }
                .inkCommit()
            }
            .buttonStyle(PressStyle())
            .disabled(busy || !canArchive)
            .accessibilityIdentifier("archive-customer-commit")
        }
        .padding(.horizontal, PaperCardMetrics.margin)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Theme.canvas)
    }

    private func archive() async {
        guard !busy, canArchive else { return }
        busy = true
        defer { busy = false }
        do {
            let saved = try await api.archiveCustomer(customerID, reason: CustomerArchiveReason.text(reason, note: note))
            error = nil
            await onArchived(saved)
            dismiss()
        } catch is CancellationError {
        } catch {
            self.error = error.isConnectivityFailure ? "Archiving needs a connection. Try again when you have signal."
                                                     : error.plainMessage(subject: "this customer")
        }
    }
}

/// Paper 48H "Archived customers": who is archived, each with Restore. Push it with
/// `.thorbisDestination`. `customers` is the book the list already loaded; `onRestored` hands the
/// restored record back so the list drops it.
struct ArchivedCustomersView: View {
    let customers: [CustomerRecord]
    var onRestored: (CustomerRecord) async -> Void = { _ in }

    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @State private var query = ""
    @State private var restoring: String?
    @State private var error: String?

    private var canRestore: Bool { session.can("customer.archive", feature: "core_crm") }
    private var archived: [CustomerRecord] { CustomerListScope.archived.customers(from: customers) }
    private var shown: [CustomerRecord] {
        let words = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return archived }
        return archived.filter { customer in
            [customer.name, customer.address, customer.phone].contains { $0?.localizedCaseInsensitiveContains(words) == true }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PaperPageTitle(title: "Archived customers", subtitle: "\(archived.count) archived \u{00B7} jobs and invoices are kept")
                searchField.padding(.top, 16)
                if let error {
                    ErrorBanner(message: error, outer: PaperCardMetrics.margin).padding(.top, 12)
                }
                if shown.isEmpty {
                    ListRoomEmpty(symbol: "magnifyingglass", title: archived.isEmpty ? "No archived customers" : "No archived customers match",
                                  message: archived.isEmpty ? "Customers you archive move here." : "Try a name, street or phone number.")
                        .padding(.top, 8)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        PaperCard {
                            ForEach(Array(shown.enumerated()), id: \.element.id) { index, customer in
                                if index > 0 { WellDivider(leading: 16) }
                                row(customer)
                            }
                        }
                        Text("Restore puts a customer back in Customers with their jobs, invoices and equipment. Archived customers don't get texts or reminders.")
                            .font(Theme.font(13)).foregroundStyle(Theme.subtle)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 8).padding(.top, 12)
                    }
                    .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 20)
                }
            }
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .foregroundStyle(Theme.foreground)
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// "Search archived" on the card, 46 tall, radius 14.
    private var searchField: some View {
        HStack(spacing: 8) {
            PaperIcon(.searchSmall, size: 18, color: Theme.muted).accessibilityHidden(true)
            TextField("", text: $query, prompt: .placeholder("Search archived"))
                .font(Theme.font(16)).foregroundStyle(Theme.foreground)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .frame(minHeight: 46)
                .accessibilityLabel("Search archived")
                .accessibilityIdentifier("archived-customers-search")
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted)
                        .frame(width: 32, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 46)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, PaperCardMetrics.margin)
    }

    /// The name (16 Medium) over where they are (14 muted), opening the customer; Restore trails
    /// as a 44pt pill on the fill, 15 Semibold.
    private func row(_ customer: CustomerRecord) -> some View {
        let place = [customer.address, customer.phone].compactMap { $0?.isEmpty == false ? $0 : nil }.first
        let busy = restoring == customer.id
        let listCustomer = Customer(id: customer.id, name: customer.name, archived: customer.archived, createdAt: customer.createdAt)
        return HStack(alignment: .center, spacing: 12) {
            PaperSplitLink(id: customer.id, value: listCustomer) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(customer.name).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(place ?? "Archived").font(Theme.font(14)).foregroundStyle(Theme.muted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .accessibilityIdentifier("archived-customer-row-\(customer.id)")
            if canRestore {
                Button { Task { await restore(customer) } } label: {
                    HStack(spacing: 6) {
                        if busy { ProgressView() }
                        Text("Restore")
                    }
                    .paperButton(.secondary, tone: .quiet)
                }
                .buttonStyle(PressStyle())
                .disabled(restoring != nil)
                .accessibilityLabel("Restore \(customer.name)")
                .accessibilityIdentifier("archived-customer-restore-\(customer.id)")
            }
        }
        .padding(.leading, 16).padding(.trailing, 14).padding(.vertical, 12)
    }

    private func restore(_ customer: CustomerRecord) async {
        guard restoring == nil, canRestore else { return }
        restoring = customer.id
        defer { restoring = nil }
        do {
            let saved = try await api.restoreCustomer(customer.id)
            error = nil
            await onRestored(saved)
        } catch is CancellationError {
        } catch {
            self.error = error.isConnectivityFailure ? "Restoring needs a connection. Try again when you have signal."
                                                     : error.plainMessage(subject: "this customer")
        }
    }
}

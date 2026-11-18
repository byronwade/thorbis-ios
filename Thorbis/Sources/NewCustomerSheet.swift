import SwiftUI
import UIKit

/// Customer intake as on the web: a name is all that's required, the rest helps the
/// technician call, text and find the place.
struct NewCustomerSheet: View {
    /// Seeds the name, e.g. with what was typed into a customer search before tapping New.
    var initialName: String = ""
    /// Seeds the phone and address, e.g. from the inline new-customer fields in a booking.
    var initialPhone: String = ""
    var initialAddress: String = ""
    var onCreated: (Customer) -> Void = { _ in }
    /// Paper 47A's "Save and book a job" under the cards. Off where the sheet is already part of a
    /// booking (New job's own "new customer").
    var offersBooking = false
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController
    @Environment(\.dismiss) private var dismiss
    @State private var request = NewCustomerRequest(name: "", accountType: "residential")
    @State private var phone = ""
    @State private var email = ""
    @State private var address = ""
    /// "How they found us": free words, up to 120 characters (customers.create referralSource).
    @State private var referral = ""
    @State private var editingReferral = false
    /// The saved customer whose new job is open ("Save and book a job").
    @State private var bookFor: Customer?
    @State private var busy = false
    @State private var error: String?
    @State private var lookup: CustomerPhoneLookup = .notApplicable
    @FocusState private var focused: Field?
    @State private var commitPressed = false
    @State private var keyboardShown = false
    /// The email is checked once they leave the field or press Save.
    @State private var emailChecked = false

    private enum Field { case name, phone, email, address }

    private var trimmedName: String { request.name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var emailValid: Bool {
        let value = email.trimmingCharacters(in: .whitespaces)
        return value.isEmpty || (value.contains("@") && value.contains(".") && !value.contains(" "))
    }
    private var valid: Bool { !trimmedName.isEmpty && trimmedName.count <= 200 && emailValid && phone.count <= 30 && address.count <= 500 }

    var body: some View {
        let canCreate = session.can("customer.create", feature: "core_crm")
        // Paper 47A: Cancel and Save customer in the title row, then the form as grouped cards on
        // the canvas. Save is never pre-disabled unless the role can't add customers (and says so).
        VStack(spacing: 0) {
            header(canCreate: canCreate)
            ScrollView {
                VStack(spacing: 12) {
                    if !canCreate {
                        Text("Your role can't add customers. Ask your office.")
                            .font(Theme.font(13)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let error { ErrorBanner(message: error, outer: 0) }
                    card {
                        field("Name", text: $request.name, prompt: "Danielle Marlowe", focus: .name, error: nameProblem)
                            .textContentType(.name).submitLabel(.next).onSubmit { focused = .phone }
                        WellDivider(leading: 16)
                        field("Mobile", text: $phone, prompt: "(916) 555-0142", focus: .phone, error: phoneProblem)
                            .textContentType(.telephoneNumber).keyboardType(.phonePad)
                        WellDivider(leading: 16)
                        field("Email", text: $email, prompt: "danielle@example.com", focus: .email,
                              error: emailChecked && !emailValid ? "Check the email address, like danielle@example.com." : nil)
                            .textContentType(.emailAddress).keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .submitLabel(.next).onSubmit { focused = .address }
                    }
                    if case .found(let existing) = lookup { existingCustomerCard(existing) }
                    card {
                        HStack(alignment: .center, spacing: 12) {
                            field("Service address", text: $address, prompt: "412 Birchwood Ln, Sacramento", focus: .address,
                                  error: addressProblem, padded: false)
                                .textContentType(.fullStreetAddress).submitLabel(.done)
                                .onSubmit { Task { await commit() } }
                            PaperIcon(.formPin, size: 20, color: Theme.muted)
                                .frame(width: 20, height: 20).accessibilityHidden(true)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        WellDivider(leading: 16)
                        choice("Account type") {
                            ThorbisSegmented(options: [("residential", "Residential"), ("commercial", "Commercial")],
                                             selection: Binding(get: { request.accountType ?? "residential" }, set: { request.accountType = $0 }))
                        }
                    }
                    // Paper 47A: how they found us, then how they like to be reached, on one card.
                    card {
                        referralRow
                        WellDivider(leading: 16)
                        VStack(alignment: .leading, spacing: 8) {
                            PreferredContactLabel(isSet: request.preferredContact != nil) { request.preferredContact = nil }
                            ThorbisSegmented(options: [("sms", "Text"), ("phone", "Call"), ("email", "Email")],
                                             selection: Binding(get: { request.preferredContact ?? "" }, set: { request.preferredContact = $0.isEmpty ? nil : $0 }))
                        }
                        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if offersBooking && canCreate && session.can("job.create", feature: "jobs") { bookingAction }
                }
                .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 32)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // MA-16: number pads and accessibility sizes have no Return; Done puts the keyboard away.
            if keyboardShown {
                HStack {
                    Spacer(minLength: 0)
                    Button("Done") {
                        focused = nil
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .buttonStyle(ThorbisBarButtonStyle(prominent: true))
                    .accessibilityIdentifier("keyboard-done")
                }
                .padding(.horizontal, Theme.gutter).padding(.vertical, 8)
                .background(Theme.background)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardShown = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardShown = false }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.background.ignoresSafeArea())
        .thorbisSheetPresentation([.large])
            .foregroundStyle(Theme.foreground)
            .sheet(isPresented: $editingReferral) { ReferralSourceSheet(value: $referral) }
            // "Save and book a job": the new job opens over this sheet; closing it closes both.
            .sheet(item: $bookFor, onDismiss: { dismiss() }) { customer in
                SheetSurface { NewJobSheet(preselected: customer) }
            }
            .onAppear {
                if request.name.isEmpty { request.name = initialName.trimmingCharacters(in: .whitespacesAndNewlines) }
                if phone.isEmpty { phone = initialPhone.trimmingCharacters(in: .whitespacesAndNewlines) }
                if address.isEmpty { address = initialAddress.trimmingCharacters(in: .whitespacesAndNewlines) }
                focused = .name
            }
            .task(id: CustomerPhoneLookup.digits(phone)) { await checkPhone() }
            .onChange(of: focused) { old, _ in if old == .email { emailChecked = true } }
            .onChange(of: email) { _, _ in if focused == .email { emailChecked = false } }
            #if DEBUG
            .task {
                // `--paper-preview-form-errors`: Save pressed with the name blank and a bad email.
                guard PaperPreview.enabled, ProcessInfo.processInfo.arguments.contains("--paper-preview-form-errors") else { return }
                try? await Task.sleep(for: .milliseconds(300))
                request.name = ""
                email = "danielle@"
                await commit()
                try? await Task.sleep(for: .milliseconds(600))
                focused = nil
            }
            #endif
            // MA-16: typed details aren't lost to a stray swipe; Cancel still leaves.
            .interactiveDismissDisabled(busy || !trimmedName.isEmpty || !phone.isEmpty || !email.isEmpty || !address.isEmpty)
    }

    /// Paper's title row: Cancel on a card pill, the title, Save customer on the brand pill.
    private func header(canCreate: Bool) -> some View {
        // Paper's row is justify-between: a long "Save customer" pill leaves the title less room.
        HStack(spacing: 8) {
                Button { dismiss() } label: {
                    Text("Cancel").font(Theme.font(16, weight: .medium)).lineLimit(1).fixedSize().foregroundStyle(Theme.foreground)
                        .padding(.horizontal, 16).frame(minHeight: 44)
                        .background(Theme.card, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .disabled(busy)
                Text("New customer").font(Theme.font(17, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.isHeader)
                Button { Task { await commit() } } label: {
                    HStack(spacing: 6) {
                        if busy { ProgressView().tint(.white) }
                        Text("Save customer").font(Theme.font(16, weight: .semibold)).lineLimit(1).fixedSize()
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18).frame(minHeight: 44)
                    .background(Theme.brand, in: Capsule())
                    .opacity(canCreate ? 1 : 0.45)
                    .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .disabled(busy || !canCreate)
                .accessibilityLabel("Save customer")
                .accessibilityHint(canCreate ? "" : "Your role can't add customers. Ask your office.")
                .accessibilityIdentifier("sheet-commit")
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 2)
        // A title row is a bar: it stops growing at xLarge so the pills never break mid-word and
        // the title keeps its room. The form under it follows the reader's text size in full.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    /// "How they found us" with the answer trailing in the muted ink and a quiet chevron, 56 tall.
    private var referralRow: some View {
        let source = referral.trimmingCharacters(in: .whitespacesAndNewlines)
        return Button { editingReferral = true } label: {
            HStack(spacing: 8) {
                Text("How they found us").font(Theme.font(16)).foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(source.isEmpty ? "Add" : source).font(Theme.font(16)).foregroundStyle(Theme.muted)
                    .lineLimit(1)
                PaperChevron()
                    .foregroundStyle(Theme.muted).accessibilityHidden(true)
            }
            .padding(.horizontal, 16).frame(minHeight: 56).contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityLabel("How they found us")
        .accessibilityValue(source.isEmpty ? "Not set" : source)
        .accessibilityIdentifier("new-customer-referral")
    }

    /// Paper 47A: an outlined "Save and book a job" (50 tall, 16 Semibold) over one line saying
    /// what it does.
    private var bookingAction: some View {
        let first = trimmedName.split(separator: " ").first.map(String.init)
        return VStack(spacing: 6) {
            Button { Task { await commit(thenBook: true) } } label: {
                Text("Save and book a job").font(Theme.font(16, weight: .semibold)).foregroundStyle(Theme.foreground)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .overlay(Capsule().strokeBorder(Theme.muted, lineWidth: 1))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressStyle())
            .disabled(busy)
            .accessibilityIdentifier("new-customer-save-and-book")
            Text("Saves \(first ?? "the customer"), then opens a new job for them.")
                .font(Theme.font(13)).foregroundStyle(Theme.subtle)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    /// One Paper card: the card tone, radius 20, rows separated by an inset hairline.
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    /// A label above its answer (13 muted over 17 Medium), typed in place; the problem under it.
    private func field(_ label: String, text: Binding<String>, prompt: String, focus: Field,
                       error: String? = nil, padded: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Theme.font(13)).foregroundStyle(Theme.muted).accessibilityHidden(true)
            TextField("", text: text, prompt: .placeholder(prompt))
                .font(Theme.font(17, weight: .medium))
                .focused($focused, equals: focus)
                .accessibilityLabel(label)
            if let error { FieldProblem(message: error) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, padded ? 16 : 0).padding(.vertical, padded ? 12 : 0)
    }

    /// A small label over a segmented choice, inside a card.
    private func choice<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(Theme.font(13)).foregroundStyle(Theme.muted)
            content()
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The name's problem, shown once they've pressed Save (validate on commit, not on every key).
    private var nameProblem: String? {
        guard commitPressed else { return nil }
        if trimmedName.isEmpty { return "Add a name, like Danielle Marlowe." }
        if trimmedName.count > 200 { return "Keep the name to 200 characters." }
        return nil
    }

    /// Phone and address limits, said under their fields after Save is pressed.
    private var phoneProblem: String? { commitPressed && phone.count > 30 ? "Keep the phone number to 30 characters." : nil }
    private var addressProblem: String? { commitPressed && address.count > 500 ? "Keep the address to 500 characters." : nil }

    private func commit(thenBook: Bool = false) async {
        commitPressed = true
        emailChecked = true
        guard valid else {
            focused = nameProblem != nil ? .name : (!emailValid ? .email : nil)
            return
        }
        await save(thenBook: thenBook)
    }

    /// Paper's quiet notice: this number already belongs to someone, so offer them instead.
    private func existingCustomerCard(_ existing: Customer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("\(existing.name) already has this number", systemImage: "person.crop.circle.badge.checkmark")
                .font(Theme.font(14, weight: .medium))
            Text("Use their record so the job and history stay in one place.")
                .font(Theme.font(13)).foregroundStyle(Theme.muted)
            Button {
                onCreated(existing)
                dismiss()
            } label: {
                Text("Use \(existing.name)").font(Theme.font(14, weight: .medium))
                    .frame(maxWidth: .infinity).frame(minHeight: 44)
                    .foregroundStyle(Theme.foreground)
                    .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .panelBackground(cornerRadius: Theme.cardRadius)
        .accessibilityElement(children: .contain)
    }

    private func checkPhone() async {
        let number = phone
        guard CustomerPhoneLookup.digits(number).count >= 7, session.can("customer.view", feature: "core_crm") else {
            lookup = .notApplicable
            return
        }
        try? await Task.sleep(nanoseconds: 400_000_000)
        guard !Task.isCancelled else { return }
        // A refused or failed check never blocks intake; it just shows nothing.
        let result = (try? await api.lookupCustomer(phone: number)) ?? .unknown
        guard !Task.isCancelled, number == phone else { return }
        lookup = result
    }

    private func save(thenBook: Bool = false) async {
        guard valid, !busy else { return }
        busy = true
        defer { busy = false }
        var body = request
        body.name = trimmedName
        func clean(_ value: String) -> String? {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        body.phone = clean(phone)
        body.email = clean(email)
        body.address = clean(address)
        do {
            let source = clean(String(referral.prefix(120)))
            let customer: Customer
            if let source {
                // The same create, with "How they found us" beside the request's own fields.
                customer = try await api.send("POST", "/v1/customers", body: NewCustomerIntake(request: body, referralSource: source))
            } else {
                customer = try await api.createCustomer(body)
            }
            await store.refresh(api)
            onCreated(customer)
            if thenBook {
                focused = nil
                bookFor = customer
            } else {
                dismiss()
            }
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}

/// `customers.create` with "How they found us": the request's own fields, then `referralSource`
/// (createCustomerInputSchema accepts it; up to 120 characters).
struct NewCustomerIntake: Encodable {
    let request: NewCustomerRequest
    let referralSource: String

    private enum CodingKeys: String, CodingKey { case referralSource }

    func encode(to encoder: Encoder) throws {
        try request.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(referralSource, forKey: .referralSource)
    }
}

/// "Preferred contact" over its segments. Nothing is chosen until the person picks; once they
/// have, a quiet "No preference" beside the label takes the choice back (the server keeps it
/// optional), so a mis-tap never becomes a fact.
struct PreferredContactLabel: View {
    let isSet: Bool
    let clear: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Preferred contact").font(Theme.font(13)).foregroundStyle(Theme.muted)
            Spacer(minLength: 8)
            if isSet {
                Button(action: clear) {
                    Text("No preference").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.brandText)
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                // The label row stays one line tall; the tap target still reaches 44.
                .padding(.vertical, -13)
                .accessibilityLabel("No contact preference")
                .accessibilityIdentifier("preferred-contact-clear")
            }
        }
    }
}

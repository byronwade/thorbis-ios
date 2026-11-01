import SwiftUI

/// Customer intake as on the web: a name is all that's required, the rest helps the
/// technician call, text and find the place.
struct NewCustomerSheet: View {
    /// Seeds the name, e.g. with what was typed into a customer search before tapping New.
    var initialName: String = ""
    /// Seeds the phone and address, e.g. from the inline new-customer fields in a booking.
    var initialPhone: String = ""
    var initialAddress: String = ""
    var onCreated: (Customer) -> Void = { _ in }
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController
    @Environment(\.dismiss) private var dismiss
    @State private var request = NewCustomerRequest(name: "", accountType: "residential")
    @State private var phone = ""
    @State private var email = ""
    @State private var address = ""
    @State private var busy = false
    @State private var error: String?
    @State private var lookup: CustomerPhoneLookup = .notApplicable
    @FocusState private var focused: Field?
    @State private var commitPressed = false
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
        NavigationStack {
            ScrollView {
                // v2 form: the label stays above, examples as placeholders, help under the field and
                // the error in its place, related fields clustered by space, optional fields marked.
                VStack(alignment: .leading, spacing: 32) {
                    Text("New customer").font(Theme.font(24, weight: .medium)).tracking(-0.3)
                        .accessibilityAddTraits(.isHeader)
                    FormCluster(title: "Who") {
                        FormField(label: "Name", help: "As it goes on the invoice.", error: nameProblem) {
                            input($request.name, prompt: "Danielle Marlowe", focus: .name, label: "Name")
                                .textContentType(.name).submitLabel(.next).onSubmit { focused = .phone }
                        }
                        FormField(label: "Phone", optional: true, help: "Used to call and text about visits.", error: phoneProblem) {
                            input($phone, prompt: "(916) 555-0142", focus: .phone, label: "Phone")
                                .textContentType(.telephoneNumber).keyboardType(.phonePad)
                        }
                        if case .found(let existing) = lookup { existingCustomerCard(existing) }
                        FormField(label: "Email", optional: true, help: "Receipts and estimates go here.",
                                  error: emailChecked && !emailValid ? "Check the email address, like danielle@example.com." : nil) {
                            input($email, prompt: "danielle@example.com", focus: .email, label: "Email")
                                .textContentType(.emailAddress).keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .submitLabel(.next).onSubmit { focused = .address }
                        }
                    }
                    FormCluster(title: "Where") {
                        FormField(label: "Service address", optional: true, help: "Where the truck goes. You can add more places later.", error: addressProblem) {
                            input($address, prompt: "412 Birchwood Ln, Sacramento", focus: .address, label: "Service address")
                                .textContentType(.fullStreetAddress).submitLabel(.done)
                                .onSubmit { Task { await commit() } }
                        }
                    }
                    FormCluster(title: "Account") {
                        FormField(label: "Type") {
                            ThorbisSegmented(options: [("residential", "Residential"), ("commercial", "Commercial")],
                                             selection: Binding(get: { request.accountType ?? "residential" }, set: { request.accountType = $0 }))
                        }
                        FormField(label: "Prefers", optional: true) {
                            ThorbisSegmented(options: [("", "None"), ("phone", "Call"), ("sms", "Text"), ("email", "Email")],
                                             selection: Binding(get: { request.preferredContact ?? "" }, set: { request.preferredContact = $0.isEmpty ? nil : $0 }))
                        }
                    }
                    if let error { ErrorBanner(message: error).padding(.horizontal, -Theme.gutter) }
                }
                .padding(.horizontal, Theme.gutter).padding(.top, 8).padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.canvas)
            .foregroundStyle(Theme.foreground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ThorbisToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) } }
            .safeAreaInset(edge: .bottom) {
                // Not pre-disabled: pressed with a problem, it says what under the field.
                PaperActionBar(title: "Save customer", symbol: "person.badge.plus", busy: busy,
                               disabled: !session.can("customer.create", feature: "core_crm"),
                               disabledReason: session.can("customer.create", feature: "core_crm") ? nil : "Your role can't add customers. Ask your office.") { Task { await commit() } }
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
    }

    /// A text input in the sunk well (design.thorbis.com Depth: the field sinks).
    private func input(_ text: Binding<String>, prompt: String, focus: Field, label: String) -> some View {
        TextField("", text: text, prompt: .placeholder(prompt))
            .font(Theme.font(16))
            .focused($focused, equals: focus)
            .accessibilityLabel(label)
            .fieldWell()
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

    private func commit() async {
        commitPressed = true
        emailChecked = true
        guard valid else {
            focused = nameProblem != nil ? .name : (!emailValid ? .email : nil)
            return
        }
        await save()
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

    private func save() async {
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
            let customer = try await api.createCustomer(body)
            await store.refresh(api)
            onCreated(customer)
            dismiss()
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}

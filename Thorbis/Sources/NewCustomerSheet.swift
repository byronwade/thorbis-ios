import SwiftUI

/// Customer intake as on the web: a name is all that's required, the rest helps the
/// technician call, text and find the place.
struct NewCustomerSheet: View {
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
                VStack(alignment: .leading, spacing: 16) {
                    Text("New customer").font(Theme.font(26, weight: .semibold)).tracking(-0.39)
                        .accessibilityAddTraits(.isHeader)
                    field("Name", text: $request.name, prompt: "Danielle Marlowe", focus: .name)
                        .textContentType(.name).submitLabel(.next).onSubmit { focused = .phone }
                    field("Phone", text: $phone, prompt: "(555) 014-2276", focus: .phone)
                        .textContentType(.telephoneNumber).keyboardType(.phonePad)
                    if case .found(let existing) = lookup { existingCustomerCard(existing) }
                    field("Email", text: $email, prompt: "name@example.com", focus: .email)
                        .textContentType(.emailAddress).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .submitLabel(.next).onSubmit { focused = .address }
                    if !emailValid { Text("Check the email address.").font(Theme.font(12)).foregroundStyle(Theme.destructive) }
                    field("Service address", text: $address, prompt: "412 Birchwood Ln, Sacramento", focus: .address)
                        .textContentType(.fullStreetAddress).submitLabel(.done)
                        .onSubmit { if valid { Task { await save() } } }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Account").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                        Picker("Account", selection: Binding(get: { request.accountType ?? "residential" }, set: { request.accountType = $0 })) {
                            Text("Residential").tag("residential")
                            Text("Commercial").tag("commercial")
                        }
                        .pickerStyle(.segmented)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Prefers").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                        Picker("Preferred contact", selection: Binding(get: { request.preferredContact ?? "" }, set: { request.preferredContact = $0.isEmpty ? nil : $0 })) {
                            Text("No preference").tag("")
                            Text("Call").tag("phone")
                            Text("Text").tag("sms")
                            Text("Email").tag("email")
                        }
                        .pickerStyle(.segmented)
                    }
                    if let error { ErrorBanner(message: error).padding(.horizontal, -Theme.gutter) }
                }
                .padding(.horizontal, Theme.gutter).padding(.top, 8).padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .foregroundStyle(Theme.foreground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) } }
            .safeAreaInset(edge: .bottom) {
                PaperActionBar(title: "Save customer", symbol: "person.badge.plus", busy: busy,
                               disabled: !valid || !session.can("customer.create", feature: "core_crm")) { Task { await save() } }
            }
            .onAppear { focused = .name }
            .task(id: CustomerPhoneLookup.digits(phone)) { await checkPhone() }
            // MA-16: typed details aren't lost to a stray swipe; Cancel still leaves.
            .interactiveDismissDisabled(busy || !trimmedName.isEmpty || !phone.isEmpty || !email.isEmpty || !address.isEmpty)
        }
    }

    private func field(_ label: String, text: Binding<String>, prompt: String, focus: Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
            TextField("", text: text, prompt: Text(prompt).foregroundStyle(Theme.subtle))
                .font(Theme.font(16))
                .focused($focused, equals: focus)
                .padding(.horizontal, 14).frame(minHeight: 46)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
        }
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
                Text("Use \(existing.name)").font(Theme.font(14, weight: .semibold))
                    .frame(maxWidth: .infinity).frame(minHeight: 44)
                    .foregroundStyle(Theme.brand)
                    .background(Theme.fill, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
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

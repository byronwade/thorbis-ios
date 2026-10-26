import SwiftUI
import ThorbisCore

/// A name is the only thing you must know to open an account (domains/customers).
struct NewCustomerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var input = NewCustomer(name: "")
    @State private var phone = ""
    @State private var email = ""
    @State private var address = ""
    @State private var commercial = false
    @State private var busy = false
    @State private var error: String?

    private var dirty: Bool { !input.name.isEmpty || !phone.isEmpty || !email.isEmpty || !address.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("Customer") {
                    TextField("Name", text: $input.name)
                        .textContentType(.name)
                        .accessibilityIdentifier("customer-name")
                        .sheetRow()
                    Picker("Type", selection: $commercial) {
                        Text("Residential").tag(false)
                        Text("Commercial").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .sheetRow()
                }
                Section("Contact") {
                    TextField("Phone", text: $phone).keyboardType(.phonePad).textContentType(.telephoneNumber).sheetRow()
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .sheetRow()
                    TextField("Address", text: $address, axis: .vertical).textContentType(.fullStreetAddress).sheetRow()
                }
                Section("Preferred contact") {
                    Picker("Preferred contact", selection: $input.preferredContact) {
                        Text("No preference").tag(ContactMethod?.none)
                        Text("Phone call").tag(Optional(ContactMethod.phone))
                        Text("Text message").tag(Optional(ContactMethod.sms))
                        Text("Email").tag(Optional(ContactMethod.email))
                    }
                    .sheetRow()
                }
                if let error {
                    Section { Text(error).foregroundStyle(Theme.danger).sheetRow() }
                }
            }
            .thorbisList()
            .navigationTitle("New customer")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(dirty)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy {
                        ProgressView()
                    } else {
                        Button("Save customer", action: save).disabled(input.name.trimmed.isEmpty)
                    }
                }
            }
        }
    }

    private func save() {
        busy = true
        error = nil
        var payload = input
        payload.phone = phone
        payload.email = email
        payload.address = address
        payload.accountType = commercial ? "commercial" : "residential"
        Task {
            defer { busy = false }
            do {
                model.store(try await model.api.createCustomer(payload))
                dismiss()
            } catch {
                self.error = model.message(for: error)
            }
        }
    }
}

struct AddContactSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let customerId: String
    let onAdded: (CustomerContact) -> Void
    @State private var name = ""
    @State private var role = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var primary = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name).textContentType(.name).sheetRow()
                    TextField("Role (e.g. Property manager)", text: $role).sheetRow()
                    TextField("Phone", text: $phone).keyboardType(.phonePad).textContentType(.telephoneNumber).sheetRow()
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .sheetRow()
                    Toggle("Primary contact", isOn: $primary).sheetRow()
                }
                if let error { Section { Text(error).foregroundStyle(Theme.danger).sheetRow() } }
            }
            .thorbisList()
            .navigationTitle("Add contact")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(!name.isEmpty)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy {
                        ProgressView()
                    } else {
                        Button("Add contact") {
                            busy = true
                            error = nil
                            let input = NewContact(name: name.trimmed, role: role.trimmed.nilIfEmpty, email: email.trimmed.nilIfEmpty,
                                                   phone: phone.trimmed.nilIfEmpty, primary: primary)
                            Task {
                                defer { busy = false }
                                do {
                                    onAdded(try await model.api.addContact(customer: customerId, input))
                                    dismiss()
                                } catch {
                                    self.error = model.message(for: error)
                                }
                            }
                        }
                        .disabled(name.trimmed.isEmpty)
                    }
                }
            }
        }
    }
}

struct AddLocationSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let customerId: String
    let onAdded: (ServiceLocation) -> Void
    @State private var label = "Home"
    @State private var kind: ServiceLocationKind = .service
    @State private var address = ""
    @State private var notes = ""
    @State private var gateCode = ""
    @State private var alarmCode = ""
    @State private var dog = ""
    @State private var parking = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Label", text: $label).sheetRow()
                    Picker("Kind", selection: $kind) {
                        Text("Service").tag(ServiceLocationKind.service)
                        Text("Billing").tag(ServiceLocationKind.billing)
                    }
                    .pickerStyle(.segmented)
                    .sheetRow()
                    TextField("Street address", text: $address, axis: .vertical).textContentType(.fullStreetAddress).sheetRow()
                }
                Section {
                    TextField("Gate code", text: $gateCode).sheetRow()
                    TextField("Alarm code", text: $alarmCode).sheetRow()
                    TextField("Dog on site", text: $dog).sheetRow()
                    TextField("Parking", text: $parking).sheetRow()
                    TextField("Notes", text: $notes, axis: .vertical).sheetRow()
                } header: {
                    Text("Site access")
                } footer: {
                    Text("What a technician needs to get on site.")
                }
                if let error { Section { Text(error).foregroundStyle(Theme.danger).sheetRow() } }
            }
            .thorbisList()
            .navigationTitle("Add location")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(!address.isEmpty)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy {
                        ProgressView()
                    } else {
                        Button("Add location", action: save).disabled(label.trimmed.isEmpty || address.trimmed.isEmpty)
                    }
                }
            }
        }
    }

    private func save() {
        busy = true
        error = nil
        let input = NewServiceLocation(
            label: label.trimmed, kind: kind, address: address.trimmed, notes: notes.trimmed.nilIfEmpty,
            gateCode: gateCode.trimmed.nilIfEmpty, alarmCode: alarmCode.trimmed.nilIfEmpty,
            dogOnSite: dog.trimmed.nilIfEmpty, parking: parking.trimmed.nilIfEmpty
        )
        Task {
            defer { busy = false }
            do {
                onAdded(try await model.api.addLocation(customer: customerId, input))
                dismiss()
            } catch {
                self.error = model.message(for: error)
            }
        }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

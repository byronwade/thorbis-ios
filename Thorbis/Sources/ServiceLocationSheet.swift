import SwiftUI
import UIKit

struct ServiceLocationSheet: View {
    let customerID: String
    let location: ServiceLocationRecord?
    let fullHeight: Bool
    let onSaved: (ServiceLocationRecord) -> Void

    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ServiceLocationDraft
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focusedField: LocationField?

    private enum LocationField: Hashable {
        case label, address, notes, latitude, longitude, gateCode, alarmCode, dogOnSite, parking
    }

    init(customerID: String, location: ServiceLocationRecord?, fullHeight: Bool = false, onSaved: @escaping (ServiceLocationRecord) -> Void) {
        self.customerID = customerID
        self.location = location
        self.fullHeight = fullHeight
        self.onSaved = onSaved
        _draft = State(initialValue: ServiceLocationDraft(
            label: location?.label ?? "",
            kind: location?.kind ?? "service",
            address: location?.address ?? "",
            notes: location?.notes ?? "",
            latitude: location?.coordinates.map { String($0.latitude) } ?? "",
            longitude: location?.coordinates.map { String($0.longitude) } ?? "",
            gateCode: location?.gateCode ?? "",
            alarmCode: location?.alarmCode ?? "",
            dogOnSite: location?.dogOnSite ?? "",
            parking: location?.parking ?? ""
        ))
    }

    private var isEditing: Bool { location != nil }
    private var canAttemptSave: Bool { !busy && session.can("customer.edit", feature: "core_crm") }

    var body: some View {
        VStack(spacing: 14) {
            Capsule().fill(Theme.border).frame(width: 36, height: 4).padding(.top, 10)

            ZStack {
                Text(isEditing ? "Edit location" : "New location")
                    .font(Theme.font(17, weight: .semibold))
                // MA-16: Cancel leading; the one commit is the ink button at the bottom.
                HStack {
                    Button("Cancel") { dismiss() }
                        .font(Theme.font(15))
                        .foregroundStyle(Theme.foreground)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel("Cancel location changes")
                        .disabled(busy)
                    Spacer()
                }
            }
            .frame(minHeight: 44)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    paperField("Label", placeholder: "Main house", text: $draft.label, field: .label)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Type").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                        HStack(spacing: 6) {
                            kindChip("Service", value: "service")
                            kindChip("Billing", value: "billing")
                        }
                    }

                    paperField("Address", placeholder: "Street, city", text: $draft.address, field: .address, multiline: true)
                    paperField("Notes", placeholder: "Entry instructions or site context", text: $draft.notes, field: .notes, multiline: true)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Map pin").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                        HStack(spacing: 8) {
                            paperField("Latitude", placeholder: "37.7749", text: $draft.latitude, field: .latitude, keyboard: .numbersAndPunctuation, capitalization: .never)
                            paperField("Longitude", placeholder: "-122.4194", text: $draft.longitude, field: .longitude, keyboard: .numbersAndPunctuation, capitalization: .never)
                        }
                        Text("Optional. Clear both coordinates to remove the map pin.")
                            .font(Theme.font(12)).foregroundStyle(Theme.muted)
                    }

                    Text("Access and parking")
                        .font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                        .padding(.top, 2)
                    paperField("Gate code", placeholder: "Optional", text: $draft.gateCode, field: .gateCode, capitalization: .never)
                    paperField("Alarm code", placeholder: "Optional", text: $draft.alarmCode, field: .alarmCode, capitalization: .never)
                    paperField("Dogs on site", placeholder: "Name or instructions", text: $draft.dogOnSite, field: .dogOnSite)
                    paperField("Parking", placeholder: "Where to park", text: $draft.parking, field: .parking)
                }
                .padding(.bottom, 4)
            }
            .scrollDismissesKeyboard(.interactively)
            .disabled(busy)

            VStack(spacing: 8) {
                if let error {
                    Text(error).font(Theme.font(13)).foregroundStyle(Theme.destructive)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("service-location-save-error")
                }
                Button { Task { await save() } } label: {
                    Group {
                        if busy { ProgressView().tint(Theme.onInk) }
                        else { Text(isEditing ? "Save changes" : "Add location") }
                    }
                    .inkCommit(enabled: canAttemptSave)
                }
                .buttonStyle(PressStyle())
                .disabled(!canAttemptSave)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .foregroundStyle(Theme.foreground)
        .background(Theme.card)
        .toolbar(.hidden, for: .navigationBar)
        .presentationDetents(fullHeight ? [.large] : [.height(600), .large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(Theme.cardRadius)
        .presentationBackground(Theme.card)
        .interactiveDismissDisabled(busy)
    }

    private func paperField(
        _ title: String,
        placeholder: String,
        text: Binding<String>,
        field: LocationField,
        keyboard: UIKeyboardType = .default,
        multiline: Bool = false,
        capitalization: TextInputAutocapitalization = .sentences
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
            TextField(placeholder, text: text, axis: multiline ? .vertical : .horizontal)
                // design.thorbis.com mobile: input type is at least 16.
                .font(field == .latitude || field == .longitude || field == .gateCode || field == .alarmCode ? Theme.monoFont(16) : Theme.font(16))
                .keyboardType(keyboard)
                .textInputAutocapitalization(capitalization)
                .autocorrectionDisabled(field == .latitude || field == .longitude || field == .gateCode || field == .alarmCode)
                .textContentType(field == .address ? .fullStreetAddress : nil)
                .focused($focusedField, equals: field)
                // MA-16: return moves to the next field (multi-line fields keep return for new lines).
                .submitLabel(field == .parking ? .done : .next)
                .onSubmit { focusedField = next(after: field) }
                .padding(.horizontal, 14)
                .frame(minHeight: multiline ? 70 : 48, maxHeight: multiline ? 84 : 48, alignment: .topLeading)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .stroke(focusedField == field ? Theme.foreground : Theme.border,
                                lineWidth: focusedField == field ? 1.5 : 1)
                }
        }
    }

    private func next(after field: LocationField) -> LocationField? {
        switch field {
        case .label: .address
        case .address: .notes
        case .notes: .latitude
        case .latitude: .longitude
        case .longitude: .gateCode
        case .gateCode: .alarmCode
        case .alarmCode: .dogOnSite
        case .dogOnSite: .parking
        case .parking: nil
        }
    }

    private func kindChip(_ title: String, value: String) -> some View {
        let selected = draft.kind == value
        return Button { draft.kind = value } label: {
            Text(title)
                .font(Theme.font(13, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? Theme.onInk : Theme.muted)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(selected ? Theme.ink : Theme.fill, in: Capsule())
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func save() async {
        guard !busy else { return }
        guard session.can("customer.edit", feature: "core_crm") else {
            error = "You don’t have permission to edit customer locations."
            return
        }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let saved: ServiceLocationRecord
            if let location {
                saved = try await api.updateFieldLocation(customerID, location.id, request: draft.makeUpdateRequest())
            } else {
                saved = try await api.createFieldLocation(customerID, request: draft.makeCreateRequest())
            }
            onSaved(saved)
            dismiss()
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }
}

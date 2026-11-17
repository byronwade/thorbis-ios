import SwiftUI
import UIKit

struct ServiceLocationSheet: View {
    let customerID: String
    let location: ServiceLocationRecord?
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

    init(customerID: String, location: ServiceLocationRecord?, onSaved: @escaping (ServiceLocationRecord) -> Void) {
        self.customerID = customerID
        self.location = location
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
        // Paper 87B: Cancel and Save in the title row, then the place as grouped cards on the canvas.
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let error {
                        Text(error).font(Theme.font(13)).foregroundStyle(Theme.destructive)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                            .accessibilityIdentifier("service-location-save-error")
                    }
                    if !busy && !canAttemptSave {
                        // A disabled commit says why (design.thorbis.com "Disabled needs a reason").
                        Text("Your role can't change addresses. Ask your office.").font(Theme.font(13)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                    card {
                        stackedField("Address", placeholder: "Street, city", text: $draft.address, field: .address, multiline: true)
                        WellDivider(leading: 16)
                        stackedField("Place name", placeholder: "Main house", text: $draft.label, field: .label)
                        WellDivider(leading: 16)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Type").font(Theme.font(13)).foregroundStyle(Theme.muted)
                            ThorbisSegmented(options: [("service", "Service"), ("billing", "Billing")], selection: $draft.kind)
                        }
                        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    card {
                        stackedField("Gate code", placeholder: "1907#", text: $draft.gateCode, field: .gateCode, capitalization: .never)
                        WellDivider(leading: 16)
                        stackedField("Alarm code", placeholder: "Optional", text: $draft.alarmCode, field: .alarmCode, capitalization: .never)
                        WellDivider(leading: 16)
                        stackedField("Pets", placeholder: "Dog in the backyard", text: $draft.dogOnSite, field: .dogOnSite)
                        WellDivider(leading: 16)
                        stackedField("Parking", placeholder: "Park on the street", text: $draft.parking, field: .parking)
                        WellDivider(leading: 16)
                        stackedField("Access notes", placeholder: "Text before you open the side gate", text: $draft.notes, field: .notes, multiline: true)
                    }
                    card {
                        inlineField("Latitude", placeholder: "37.7749", text: $draft.latitude, field: .latitude)
                        WellDivider(leading: 16)
                        inlineField("Longitude", placeholder: "-122.4194", text: $draft.longitude, field: .longitude)
                    }
                    // Paper 87B's line first; the map pin's own rule after it.
                    Text("Gate code and notes show on every job here. The map pin is optional; clear both to remove it.")
                        .font(Theme.font(13)).foregroundStyle(Theme.subtle)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .disabled(busy)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Theme.cardRadius)
        .thorbisSheetSurface()
        .interactiveDismissDisabled(busy)
    }

    /// Paper's title row: Cancel on a card pill, the title, Save on the brand pill.
    private var header: some View {
        ZStack {
            Text(isEditing ? "Edit property" : "Add property")
                .font(Theme.font(17, weight: .semibold))
                .lineLimit(1).minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 100)
            HStack {
                Button { dismiss() } label: {
                    Text("Cancel").font(Theme.font(16, weight: .medium)).lineLimit(1).fixedSize().foregroundStyle(Theme.foreground)
                        .padding(.horizontal, 16).frame(minHeight: 44)
                        .background(Theme.card, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Cancel location changes")
                .disabled(busy)
                Spacer(minLength: 8)
                Button { Task { await save() } } label: {
                    HStack(spacing: 6) {
                        if busy { ProgressView().tint(.white) }
                        Text("Save").font(Theme.font(16, weight: .semibold)).lineLimit(1).fixedSize()
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18).frame(minHeight: 44)
                    .background(Theme.brand, in: Capsule())
                    .opacity(canAttemptSave || busy ? 1 : 0.45)
                    .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .disabled(!canAttemptSave)
                .accessibilityLabel(isEditing ? "Save changes" : "Add location")
            }
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 2)
        // A title row is a bar: it stops growing at xLarge so the pills never break mid-word and
        // the title keeps its room. The form under it follows the reader's text size in full.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    /// One Paper card: the card tone, radius 20, rows separated by an inset hairline.
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    /// A label above its answer (13 muted over 17 Medium), typed in place.
    private func stackedField(
        _ title: String,
        placeholder: String,
        text: Binding<String>,
        field: LocationField,
        multiline: Bool = false,
        capitalization: TextInputAutocapitalization = .sentences
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Theme.font(13)).foregroundStyle(Theme.muted).accessibilityHidden(true)
            TextField("", text: text, prompt: .placeholder(placeholder), axis: multiline ? .vertical : .horizontal)
                .font(field == .notes ? Theme.font(15) : Theme.font(17, weight: .medium))
                .lineLimit(multiline ? 1...4 : 1...1)
                .textInputAutocapitalization(capitalization)
                .autocorrectionDisabled(field == .gateCode || field == .alarmCode)
                .textContentType(field == .address ? .fullStreetAddress : nil)
                .focused($focusedField, equals: field)
                // MA-16: return moves to the next field (multi-line fields keep return for new lines).
                .submitLabel(field == .longitude ? .done : .next)
                .onSubmit { focusedField = next(after: field) }
                .accessibilityLabel(title)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A label on the left, its answer (muted, right-aligned) on the right, 56 tall.
    private func inlineField(_ title: String, placeholder: String, text: Binding<String>, field: LocationField) -> some View {
        HStack(spacing: 8) {
            Text(title).font(Theme.font(16)).foregroundStyle(Theme.foreground).accessibilityHidden(true)
            Spacer(minLength: 8)
            TextField("", text: text, prompt: .placeholder(placeholder))
                .font(Theme.monoFont(16)).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.trailing)
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .focused($focusedField, equals: field)
                .submitLabel(field == .longitude ? .done : .next)
                .onSubmit { focusedField = next(after: field) }
                .accessibilityLabel(title)
        }
        .padding(.horizontal, 16).frame(minHeight: 56)
    }

    private func next(after field: LocationField) -> LocationField? {
        switch field {
        case .address: .label
        case .label: .gateCode
        case .gateCode: .alarmCode
        case .alarmCode: .dogOnSite
        case .dogOnSite: .parking
        case .parking: .notes
        case .notes: .latitude
        case .latitude: .longitude
        case .longitude: nil
        }
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

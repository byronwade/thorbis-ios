import SwiftUI

// Plans the company sells (add, edit, stop selling) and a customer's membership (edit, remove).
// Plans: `POST /v1/membership-plans` and `/v1/membership-plans/{planId}` (organization.settings.edit).
// Memberships: `POST /v1/customers/{id}/memberships/{membershipId}` and `…/remove` (customer.edit).

/// The server features these routes sit behind. With the feature off the server refuses the call,
/// so the app hides the control or skips the call. An unknown key reads as off.
enum ServerFlag: String, CaseIterable {
    /// `POST /v1/devices` and `/v1/devices/unregister`.
    case staffPush = "staff_push_notifications"
    /// `GET` and `POST /v1/customers/{id}/sms-consent`.
    case jobTexts = "job_sms_notices"
    /// `POST /v1/jobs/{id}/reschedule/undo`.
    case rescheduleUndo = "job_schedule_cycle_undo"
}

extension SessionController {
    func isOn(_ flag: ServerFlag) -> Bool { isFeatureOn(flag.rawValue) }
}

/// Who may change plans and memberships, and what a refused save says.
enum MembershipAccess {
    /// The server's rule for adding, editing and archiving a plan.
    @MainActor static func canEditPlans(_ session: SessionController) -> Bool {
        session.can("organization.settings.edit", feature: "core_crm")
    }

    /// The server's rule for editing and removing a customer's membership.
    @MainActor static func canEditMemberships(_ session: SessionController) -> Bool {
        session.can("customer.edit", feature: "core_crm")
    }

    /// The server's rule for giving a membership a percent off other than its plan's (0 without a
    /// plan) when it is added, or other than its stored percent when it is edited.
    @MainActor static func canOverrideMembershipDiscount(_ session: SessionController) -> Bool {
        session.can("organization.settings.edit", feature: "core_crm")
    }

    static let planRefused = "You can\u{2019}t change plans. Ask an owner or admin to do it."
    static let membershipRefused = "You can\u{2019}t change this membership. Ask an owner or admin to do it."
    static let discountRefused = "You can\u{2019}t change the percent off. Ask an owner or admin to do it."
    /// Under the percent off when it is shown and not typed in.
    static let discountLocked = "Only an owner or admin can change the percent off."
    /// In place of Remove when putting the membership back would need the company settings permission.
    static let removeLocked = "Only an owner or admin can remove this membership: adding it back with this percent off could need one of them."

    /// Whether adding this membership back after a removal would need organization.settings.edit,
    /// the same answer as the web's `undoNeedsDiscountAuthority`. The server checks a re-add like a
    /// new sale: against the plan's current percent when the plan is still offered, against 0 when
    /// there is no plan or it was archived. `plans` is nil while they are not loaded; a membership
    /// with a plan then counts as needing it, so Remove is not offered on a guess.
    static func restoreNeedsDiscountAuthority(_ membership: MembershipRecord, plans: [MembershipPlan]?) -> Bool {
        if membership.planId != nil && plans == nil { return true }
        if let plan = plans?.first(where: { $0.id == membership.planId && !$0.archived }) {
            return membership.discountPercent != plan.discountPercent
        }
        return membership.discountPercent > 0
    }

    /// What to show when a save fails. A 403 gets plain words instead of the server's.
    /// `discountChanged` says the refused request carried a new percent off. Only then can a 403
    /// that names the company settings permission be about the percent: the detail alone is not
    /// enough, because a plan save is refused with the same words.
    static func saveError(_ error: Error, plan: Bool, discountChanged: Bool = false) -> String {
        if error.isConnectivityFailure { return "Saving needs a connection." }
        if let problem = error as? Problem, problem.status == 403 {
            if plan { return planRefused }
            if discountChanged, problem.detail?.contains("organization.settings.edit") == true { return discountRefused }
            return membershipRefused
        }
        return error.localizedDescription
    }
}

/// The plan form as typed, and the checks before it is sent.
struct MembershipPlanForm: Equatable {
    enum Field: Equatable { case name, cadence, visits, price, discount, description }
    struct Problem: Error, Equatable {
        let field: Field
        let message: String
    }

    var name = ""
    var kind = "maintenance"
    var cadence = ""
    var visits = ""
    /// Dollars as typed: "29" or "29.50".
    var price = ""
    var billingFrequency: String?
    var discount = ""
    var description = ""

    static let kinds: [(value: String, label: String)] = [("maintenance", "Maintenance"), ("membership", "Membership")]
    static let frequencies: [(value: String?, label: String)] = [
        (nil, "Not set"), ("monthly", "Every month"), ("quarterly", "Every 3 months"), ("annual", "Every year"), ("one_time", "One time"),
    ]
    /// The server's limits.
    static let nameLimit = 120
    static let notesLimit = 2000
    static let priceLimit = 2_147_483_647

    init() {}

    init(_ plan: MembershipPlan) {
        name = plan.name
        kind = plan.kind
        cadence = plan.cadence ?? ""
        visits = plan.visitsPerYear.map(String.init) ?? ""
        price = plan.price.map(Self.dollars) ?? ""
        billingFrequency = plan.billingFrequency
        discount = plan.discountPercent > 0 ? String(plan.discountPercent) : ""
        description = plan.description ?? ""
    }

    /// 2900 → "29", 2950 → "29.50".
    static func dollars(_ cents: Int) -> String {
        cents % 100 == 0 ? String(cents / 100) : String(format: "%d.%02d", cents / 100, cents % 100)
    }

    /// "$1,250.00" → 125000. Nil when it isn't a price.
    static func cents(_ text: String) -> Int? {
        let plain = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
        return MoneyInput.cents(plain, maximumCents: priceLimit)
    }

    /// A whole number from `range`, nil when the field is empty; throws when it is anything else.
    static func whole(_ text: String, in range: ClosedRange<Int>, field: Field, message: String) throws -> Int? {
        let plain = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "%", with: "")
        if plain.isEmpty { return nil }
        guard plain.allSatisfy(\.isASCII), plain.allSatisfy(\.isNumber), let value = Int(plain), range.contains(value) else {
            throw Problem(field: field, message: message)
        }
        return value
    }

    /// The checked plan, or the first thing to fix.
    func input() throws -> MembershipPlanInput {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { throw Problem(field: .name, message: "Give the plan a name, like \u{201C}Comfort Club.\u{201D}") }
        if name.utf16.count > Self.nameLimit { throw Problem(field: .name, message: "Make the name shorter.") }
        if cadence.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count > Self.nameLimit {
            throw Problem(field: .cadence, message: "Make this shorter.")
        }
        var cents: Int?
        if !price.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let typed = Self.cents(price) else { throw Problem(field: .price, message: "Type a price like 29 or 29.50.") }
            cents = typed
        }
        let visits = try Self.whole(visits, in: 0...52, field: .visits, message: "Type a number from 0 to 52.")
        let discount = try Self.whole(discount, in: 0...100, field: .discount, message: "Type a number from 0 to 100.")
        if description.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count > Self.notesLimit {
            throw Problem(field: .description, message: "Make this shorter.")
        }
        return MembershipPlanInput(name: name, kind: kind, cadence: MembershipInput.text(cadence), visitsPerYear: visits, price: cents,
                                   billingFrequency: billingFrequency, discountPercent: discount ?? 0,
                                   description: MembershipInput.text(description))
    }
}

/// A customer's membership as typed, and the checks before it is sent.
struct MembershipForm: Equatable {
    enum Field: Equatable { case name, cadence, discount, dates, notes }
    struct Problem: Error, Equatable {
        let field: Field
        let message: String
    }

    var name: String
    var kind: String
    var cadence: String
    var discount: String
    var starts: Date?
    var renews: Date?
    var locationId: String?
    var notes: String
    /// Not edited here: Cancel membership has its own page.
    let status: String
    /// The percent off the membership was saved with. A percent equal to it is not sent.
    let originalDiscount: Int

    init(_ record: MembershipRecord) {
        name = record.name
        kind = record.kind
        cadence = record.cadence ?? ""
        discount = record.discountPercent > 0 ? String(record.discountPercent) : ""
        originalDiscount = record.discountPercent
        starts = record.startsOn.flatMap(EquipmentRecord.day)
        renews = record.renewsOn.flatMap(EquipmentRecord.day)
        locationId = record.locationId
        notes = record.notes ?? ""
        status = record.status
    }

    func input() throws -> MembershipInput {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { throw Problem(field: .name, message: "Give it a name, like \u{201C}Comfort Club.\u{201D}") }
        if name.utf16.count > MembershipPlanForm.nameLimit { throw Problem(field: .name, message: "Make the name shorter.") }
        if cadence.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count > MembershipPlanForm.nameLimit {
            throw Problem(field: .cadence, message: "Make this shorter.")
        }
        let percent: Int?
        do {
            percent = try MembershipPlanForm.whole(discount, in: 0...100, field: .discount, message: "Type a number from 0 to 100.")
        } catch let problem as MembershipPlanForm.Problem {
            throw Problem(field: .discount, message: problem.message)
        }
        if let starts, let renews, renews < starts {
            throw Problem(field: .dates, message: "It can\u{2019}t renew before it starts.")
        }
        if notes.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count > MembershipPlanForm.notesLimit {
            throw Problem(field: .notes, message: "Make the notes shorter.")
        }
        return MembershipInput(locationId: locationId, name: name, kind: kind, cadence: cadence,
                               startsOn: starts.map(EquipmentRecord.dayString), renewsOn: renews.map(EquipmentRecord.dayString),
                               status: status, discountPercent: percent ?? 0, originalDiscountPercent: originalDiscount,
                               notes: notes)
    }
}

extension MembershipInput {
    init(locationId: String?, name: String, kind: String, cadence: String?, startsOn: String?, renewsOn: String?,
         status: String, discountPercent: Int, originalDiscountPercent: Int, notes: String?) {
        self.locationId = locationId
        self.name = name
        self.kind = kind
        self.cadence = cadence
        self.startsOn = startsOn
        self.renewsOn = renewsOn
        self.status = status
        self.discountPercent = discountPercent
        self.originalDiscountPercent = originalDiscountPercent
        self.notes = notes
    }
}

// MARK: Form pieces (shared with the equipment form)

/// One Paper form card: the card tone, radius 20, rows separated by an inset hairline.
struct PaperFormCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

/// A label above its answer (13 muted over 17 Medium), typed in place, with what to fix under it.
struct PaperStackedField: View {
    let label: String
    @Binding var text: String
    let prompt: String
    var keyboard: UIKeyboardType = .default
    var problem: String? = nil
    /// Set where the form sends the cursor back to this field.
    var focus: FocusState<Bool>.Binding? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Theme.font(13)).foregroundStyle(Theme.muted).accessibilityHidden(true)
            if let focus { field.focused(focus) } else { field }
            if let problem { FieldProblem(message: problem) }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var field: some View {
        TextField("", text: $text, prompt: .placeholder(prompt))
            .font(Theme.font(17, weight: .medium))
            .keyboardType(keyboard)
            .accessibilityLabel(label)
    }
}

/// A field this person may see and not change: the label and value set like `PaperStackedField`,
/// with one muted line under it that says who can change it. No text field, so no keyboard.
private struct PaperLockedField: View {
    let label: String
    let value: String
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Theme.font(13)).foregroundStyle(Theme.muted)
            Text(value).font(Theme.font(17, weight: .medium)).foregroundStyle(Theme.foreground)
            Text(note).font(Theme.font(13)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// An inline date row: the label on the left, the date (or Add) on the right, with a way to clear it.
struct PaperDateRow: View {
    let title: String
    @Binding var value: Date?

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(Theme.font(16)).foregroundStyle(Theme.foreground)
            Spacer(minLength: 8)
            if let date = value {
                DatePicker(title, selection: Binding(get: { date }, set: { value = $0 }), displayedComponents: .date)
                    .labelsHidden()
                Button { value = nil } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.subtle)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle()).accessibilityLabel("Clear \(title.lowercased())")
            } else {
                Button { value = .now } label: {
                    Text("Add").font(Theme.font(16)).foregroundStyle(Theme.muted)
                        .frame(minWidth: 44, minHeight: 44, alignment: .trailing).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Add \(title.lowercased())")
            }
        }
        .padding(.leading, 16).padding(.trailing, 8).frame(minHeight: 56)
    }
}

/// The notes card: a quiet label over a growing text field.
private struct PaperNotesField: View {
    let label: String
    @Binding var text: String
    let prompt: String
    var problem: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Theme.font(13)).foregroundStyle(Theme.muted).accessibilityHidden(true)
            TextField("", text: $text, prompt: .placeholder(prompt), axis: .vertical)
                .lineLimit(2...6).font(Theme.font(15))
                .accessibilityLabel(label)
            if let problem { FieldProblem(message: problem) }
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The quiet red action at the foot of an edit form.
private struct PaperFormRemoveButton: View {
    let title: String
    let identifier: String
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.destructive)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(PressStyle())
        .disabled(disabled)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: Plan editor

struct MembershipPlanEditorItem: Identifiable {
    let plan: MembershipPlan?
    var id: String { plan?.id ?? "new" }
}

/// Add a plan, change one, or stop selling it. The same sheet as the equipment form: Cancel and
/// Save in the title row, then cards.
struct MembershipPlanEditor: View {
    let existing: MembershipPlan?
    let onSaved: () async -> Void
    @EnvironmentObject private var api: APIClient
    @Environment(\.dismiss) private var dismiss
    @State private var form = MembershipPlanForm()
    @State private var filled = false
    @State private var busy = false
    @State private var error: String?
    @State private var problem: MembershipPlanForm.Problem?
    @State private var confirmArchive = false
    @FocusState private var nameFocused: Bool

    private func problem(_ field: MembershipPlanForm.Field) -> String? { problem?.field == field ? problem?.message : nil }

    var body: some View {
        VStack(spacing: 0) {
            PaperTaskBar(title: existing == nil ? "New plan" : (existing?.name ?? "Plan"), cancelDisabled: busy,
                         commit: ThorbisSheetHeaderAction(title: "Save", busy: busy, identifier: "plan-commit",
                                                          accessibilityLabel: existing == nil ? "Add plan" : "Save plan") { commit() }) { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let error { ListErrorRow(message: error).accessibilityIdentifier("plan-error") }
                    PaperFormCard {
                        PaperStackedField(label: "Name", text: $form.name, prompt: "Comfort Club", problem: problem(.name), focus: $nameFocused)
                        WellDivider(leading: 16)
                        ThorbisSelect(options: MembershipPlanForm.kinds, selection: $form.kind, label: "Type")
                            .padding(.horizontal, 16).frame(minHeight: 56)
                    }
                    PaperFormCard {
                        PaperStackedField(label: "Price", text: $form.price, prompt: "29.00", keyboard: .decimalPad, problem: problem(.price))
                        WellDivider(leading: 16)
                        ThorbisSelect(options: MembershipPlanForm.frequencies, selection: $form.billingFrequency, label: "Billed")
                            .padding(.horizontal, 16).frame(minHeight: 56)
                    }
                    PaperFormCard {
                        PaperStackedField(label: "Visits a year", text: $form.visits, prompt: "2", keyboard: .numberPad, problem: problem(.visits))
                        WellDivider(leading: 16)
                        PaperStackedField(label: "How often", text: $form.cadence, prompt: "Twice a year", problem: problem(.cadence))
                        WellDivider(leading: 16)
                        PaperStackedField(label: "Percent off work", text: $form.discount, prompt: "15", keyboard: .numberPad,
                                          problem: problem(.discount))
                    }
                    PaperFormCard {
                        PaperNotesField(label: "What you get", text: $form.description, prompt: "Tune-ups, priority booking\u{2026}",
                                        problem: problem(.description))
                    }
                    Text(existing == nil ? "Add it to a customer on their page."
                                         : "Members keep the name and percent off they signed up with.")
                        .font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                    if existing != nil {
                        PaperFormRemoveButton(title: "Stop selling this plan", identifier: "plan-archive", disabled: busy) { confirmArchive = true }
                    }
                }
                .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background.ignoresSafeArea())
        .thorbisSheetPresentation([.large])
        .interactiveDismissDisabled(busy)
        .thorbisConfirm("Stop selling this plan?",
                        message: "Members who have it keep it. You can\u{2019}t add it to new customers.",
                        isPresented: $confirmArchive,
                        actions: [ThorbisConfirmAction("Stop selling", role: .destructive) { Task { await archive() } }])
        .onAppear {
            guard !filled else { return }
            filled = true
            if let existing { form = MembershipPlanForm(existing) }
        }
        .onChange(of: form) { _, _ in problem = nil }
    }

    /// Save is never pre-disabled: pressed with something wrong, it says so under the field.
    private func commit() {
        do {
            let input = try form.input()
            Task { await save(input) }
        } catch let found as MembershipPlanForm.Problem {
            problem = found
            if found.field == .name { nameFocused = true }
        } catch {}
    }

    private func save(_ input: MembershipPlanInput) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            if let existing { _ = try await api.updateMembershipPlan(existing.id, input) }
            else { _ = try await api.createMembershipPlan(input) }
            await onSaved()
            dismiss()
        } catch is CancellationError {
        } catch { self.error = MembershipAccess.saveError(error, plan: true) }
    }

    private func archive() async {
        guard let existing, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            _ = try await api.archiveMembershipPlan(existing.id)
            await onSaved()
            dismiss()
        } catch is CancellationError {
        } catch { self.error = MembershipAccess.saveError(error, plan: true) }
    }
}

// MARK: Membership editor

/// Change a customer's membership, or remove one added by mistake.
struct MembershipEditor: View {
    let customerID: String
    let membership: MembershipRecord
    let onSaved: () async -> Void
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @Environment(\.dismiss) private var dismiss
    @State private var form: MembershipForm
    @State private var locations: [ServiceLocationRecord] = []
    /// The plans still offered, nil until loaded or when the load fails.
    @State private var plans: [MembershipPlan]?
    /// True once the plans load has finished, loaded or not.
    @State private var plansSettled = false
    @State private var busy = false
    @State private var error: String?
    @State private var problem: MembershipForm.Problem?
    @State private var confirmRemove = false
    @FocusState private var nameFocused: Bool

    init(customerID: String, membership: MembershipRecord, onSaved: @escaping () async -> Void) {
        self.customerID = customerID
        self.membership = membership
        self.onSaved = onSaved
        _form = State(initialValue: MembershipForm(membership))
    }

    private func problem(_ field: MembershipForm.Field) -> String? { problem?.field == field ? problem?.message : nil }
    private var canChangeDiscount: Bool { MembershipAccess.canOverrideMembershipDiscount(session) }
    /// Remove is a hard delete: offered only when this person could put the membership back as it was.
    private var canRemove: Bool {
        canChangeDiscount || !MembershipAccess.restoreNeedsDiscountAuthority(membership, plans: plans)
    }

    var body: some View {
        VStack(spacing: 0) {
            PaperTaskBar(title: membership.name, cancelDisabled: busy,
                         commit: ThorbisSheetHeaderAction(title: "Save", busy: busy, identifier: "membership-commit",
                                                          accessibilityLabel: "Save membership") { commit() }) { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let error { ListErrorRow(message: error).accessibilityIdentifier("membership-error") }
                    PaperFormCard {
                        PaperStackedField(label: "Name", text: $form.name, prompt: "Comfort Club", problem: problem(.name), focus: $nameFocused)
                        WellDivider(leading: 16)
                        ThorbisSelect(options: MembershipPlanForm.kinds, selection: $form.kind, label: "Type")
                            .padding(.horizontal, 16).frame(minHeight: 56)
                    }
                    PaperFormCard {
                        PaperStackedField(label: "How often", text: $form.cadence, prompt: "Twice a year", problem: problem(.cadence))
                        WellDivider(leading: 16)
                        if canChangeDiscount {
                            PaperStackedField(label: "Percent off work", text: $form.discount, prompt: "15", keyboard: .numberPad,
                                              problem: problem(.discount))
                        } else {
                            // The server refuses a new percent off without the company settings
                            // permission, so it is shown, not typed in.
                            PaperLockedField(label: "Percent off work",
                                             value: membership.discountPercent > 0 ? "\(membership.discountPercent)%" : "None",
                                             note: MembershipAccess.discountLocked)
                                .accessibilityIdentifier("membership-discount-locked")
                        }
                    }
                    PaperFormCard {
                        PaperDateRow(title: "Starts", value: $form.starts)
                        WellDivider(leading: 16)
                        PaperDateRow(title: "Renews", value: $form.renews)
                        if let dates = problem(.dates) {
                            FieldProblem(message: dates).padding(.horizontal, 12).padding(.bottom, 12)
                        }
                        if !locations.isEmpty {
                            WellDivider(leading: 16)
                            ThorbisSelect(options: [(String?.none, "All places")]
                                            + locations.map { (Optional($0.id), $0.label.isEmpty ? $0.address : "\($0.label) \u{00B7} \($0.address)") },
                                          selection: $form.locationId, label: "Property", menuTitle: "Location")
                                .padding(.horizontal, 16).frame(minHeight: 56)
                        }
                    }
                    PaperFormCard {
                        PaperNotesField(label: "Notes", text: $form.notes, prompt: "Anything the team should know\u{2026}",
                                        problem: problem(.notes))
                    }
                    if canRemove {
                        PaperFormRemoveButton(title: "Remove membership", identifier: "membership-remove", disabled: busy) { confirmRemove = true }
                    } else if plansSettled || membership.planId == nil {
                        // Nothing is said while the answer still waits on the plans.
                        Text(MembershipAccess.removeLocked).font(Theme.font(13)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("membership-remove-locked")
                    }
                }
                .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background.ignoresSafeArea())
        .thorbisSheetPresentation([.large])
        .interactiveDismissDisabled(busy)
        .thorbisConfirm("Remove this membership?",
                        message: "It is deleted from this customer for good. Use this if it was added by mistake.",
                        isPresented: $confirmRemove,
                        actions: [ThorbisConfirmAction("Remove", role: .destructive) { Task { await remove() } }])
        .task {
            // The property row is extra: without the places it is left out and the saved place is kept.
            locations = ((try? await api.fieldLocations(customerID)) ?? []).filter { $0.kind == "service" }
        }
        .task {
            // Its own task, so the places are not held up. A failed load leaves the plans nil.
            plans = try? await api.membershipPlans()
            plansSettled = true
        }
        .onChange(of: form) { _, _ in problem = nil }
    }

    private func commit() {
        do {
            let input = try form.input()
            Task { await save(input) }
        } catch let found as MembershipForm.Problem {
            problem = found
            if found.field == .name { nameFocused = true }
        } catch {}
    }

    private func save(_ input: MembershipInput) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            _ = try await api.updateMembership(customerID, membershipID: membership.id, input)
            await onSaved()
            dismiss()
        } catch is CancellationError {
        } catch { self.error = MembershipAccess.saveError(error, plan: false, discountChanged: input.discountChanged) }
    }

    private func remove() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await api.removeMembership(customerID, membershipID: membership.id)
            await onSaved()
            dismiss()
        } catch is CancellationError {
        } catch { self.error = MembershipAccess.saveError(error, plan: false) }
    }
}

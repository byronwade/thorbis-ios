import AVFoundation
import PhotosUI
import SwiftUI

// Training (Paper 28 "Content portal"): the place header, search, All / Licenses / Learning, then
// grouped cards. The designed course, lesson and exam screens (64, 64A, 64B) need a course
// catalogue the server does not have, so the catalogue shows its empty state and the person keeps
// their own licenses and courses here, on this phone.

// MARK: - Shared pieces (Training, Marketing and Help)

/// Who the on-phone books belong to: this sign-in, in this workspace.
struct LearnIdentity: Equatable {
    let actorID: String
    let organizationID: String

    @MainActor init?(_ session: SessionController) {
        guard let actor = session.user?.id, let organization = session.activeOrganization?.id else { return nil }
        actorID = actor
        organizationID = organization
    }

    var key: String { "\(actorID.lowercased())|\(organizationID.lowercased())" }
}

/// Paper 88B's sheet header: Cancel and Save in the title row.
struct LearnEditorHeader: View {
    let title: String
    let saveIdentifier: String
    let onCancel: () -> Void
    let onSave: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button(action: onCancel) {
                    Text("Cancel").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                        .padding(.horizontal, 16).frame(minHeight: 44)
                        .background(Theme.card, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                Spacer(minLength: 8)
                if !typeSize.isAccessibilitySize { titleText.layoutPriority(-1) }
                Spacer(minLength: 8)
                // Never pre-disabled: pressed with a required field empty, it says which under it.
                Button(action: onSave) {
                    Text("Save").font(Theme.font(16, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 18).frame(minHeight: 44)
                        .background(Theme.brand, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .accessibilityIdentifier(saveIdentifier)
            }
            // At the largest text sizes the title takes its own line so Cancel and Save stay whole.
            if typeSize.isAccessibilitySize { titleText.frame(maxWidth: .infinity, alignment: .leading) }
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 2)
    }

    private var titleText: some View {
        Text(title).font(Theme.font(17, weight: .semibold)).foregroundStyle(Theme.foreground)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

/// One grouped card of an editor.
struct LearnCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: shape)
            .clipShape(shape)
    }
}

/// A stacked editor row: the 13 muted label over a 17 Medium answer, typed in place.
struct LearnField: View {
    let label: String
    @Binding var text: String
    var prompt = ""
    var multiline = false
    var problem: String? = nil
    var keyboard: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .sentences
    var identifier = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Theme.font(13)).foregroundStyle(Theme.muted).accessibilityHidden(true)
            TextField("", text: $text, prompt: .placeholder(prompt.isEmpty ? label : prompt),
                      axis: multiline ? .vertical : .horizontal)
                .font(multiline ? Theme.font(15) : Theme.font(17, weight: .medium))
                .foregroundStyle(Theme.foreground)
                .keyboardType(keyboard)
                .textInputAutocapitalization(capitalization)
                .autocorrectionDisabled(keyboard != .default)
                .accessibilityLabel(label)
                .accessibilityIdentifier(identifier)
            if let problem { FieldProblem(message: problem) }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
    }
}

/// An inline date row: the label on the left, the day (or Add) on the right, with a way to clear it.
struct LearnDateRow: View {
    let title: String
    @Binding var date: Date?

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(Theme.font(16)).foregroundStyle(Theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let chosen = date {
                DatePicker(title, selection: Binding(get: { chosen }, set: { date = $0 }), displayedComponents: .date)
                    .labelsHidden()
                    .tint(Theme.brand)
                Button { date = nil } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.subtle)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Clear \(title.lowercased())")
            } else {
                Button { date = .now } label: {
                    Text("Add").font(Theme.font(16)).foregroundStyle(Theme.brandText)
                        .frame(minWidth: 44, minHeight: 44, alignment: .trailing).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Add \(title.lowercased())")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
    }
}

/// Paper 28 / 98's search: a 50-tall field on the card, radius 14, that narrows this page.
struct LearnSearchField: View {
    @Binding var query: String
    let prompt: String
    let label: String
    let identifier: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.muted).accessibilityHidden(true)
            TextField("", text: $query, prompt: .placeholder(prompt))
                .font(Theme.font(16)).foregroundStyle(Theme.foreground)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .submitLabel(.search)
                .frame(minHeight: 50)
                .accessibilityLabel(label)
                .accessibilityIdentifier(identifier)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted)
                        .frame(width: 32, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// The quiet line that says where these records live.
struct LearnFootnote: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "iphone").font(.system(size: 12, weight: .medium)).accessibilityHidden(true)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(Theme.font(13)).foregroundStyle(Theme.muted)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }
}

/// "Add" in the brand ink beside a section's label (Paper 88A's "Edit").
struct LearnSectionAction: View {
    let title: String
    let label: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.brandText)
                .frame(minWidth: 44, minHeight: 44, alignment: .trailing).contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

/// A sentence inside a card that has no rows yet.
struct LearnEmptyRow: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
            Text(message).font(Theme.font(14)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Model

/// Owns the opened partition. Re-binding to another identity hides the old one's records at once.
@MainActor
final class TrainingModel: ObservableObject {
    @Published private(set) var revision = 0
    @Published private(set) var error: String?
    private(set) var key: String?
    private var storage: TrainingRecords?

    var isBound: Bool { storage != nil }
    var credentials: [TrainingCredential] { storage?.credentials ?? [] }
    var courses: [TrainingCourse] { storage?.courses ?? [] }

    func bind(_ identity: LearnIdentity?) {
        guard let identity else {
            storage = nil; key = nil; error = nil; revision += 1
            return
        }
        guard key != identity.key || storage == nil else { return }
        storage = nil
        key = identity.key
        do {
            #if DEBUG
            if PaperPreview.enabled {
                storage = try PlacesPreviewData.training(actorID: identity.actorID, organizationID: identity.organizationID)
                error = nil
                revision += 1
                return
            }
            #endif
            storage = try TrainingRecords(actorID: identity.actorID, organizationID: identity.organizationID)
            error = nil
        } catch {
            self.error = "Training could not open what is saved on this phone. \(error.localizedDescription)"
        }
        revision += 1
    }

    private func open() throws -> TrainingRecords {
        guard let storage else { throw Problem(title: "Training is not open on this phone", status: nil, detail: nil) }
        return storage
    }

    func credential(_ id: String) -> TrainingCredential? { credentials.first { $0.id == id } }
    func photoURL(_ file: String?) -> URL? { storage?.photoURL(file) }

    func save(_ credential: TrainingCredential, photo: CredentialPhotoChange) throws {
        try open().save(credential, photo: photo)
        revision += 1
    }

    func save(_ course: TrainingCourse) throws {
        try open().save(course)
        revision += 1
    }

    func removeCredential(_ id: String) throws {
        try open().removeCredential(id)
        revision += 1
    }

    func removeCourse(_ id: String) throws {
        try open().removeCourse(id)
        revision += 1
    }
}

/// The card's photo, sized for a phone and written as JPEG.
enum TrainingCardPhoto {
    static func jpeg(_ image: UIImage, maxSide: CGFloat = 1600) -> Data? {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, maxSide / longest)
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let drawn = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return drawn.jpegData(compressionQuality: 0.8)
    }
}

private enum TrainingFilter: String, Hashable {
    case all, licenses, learning
}

/// What the sheet is editing; `record` is nil for a new one.
private struct TrainingCredentialEditing: Identifiable {
    let id = UUID()
    let record: TrainingCredential?
}

private struct TrainingCourseEditing: Identifiable {
    let id = UUID()
    let record: TrainingCourse?
}

// MARK: - Root

struct TrainingView: View {
    @EnvironmentObject private var session: SessionController
    @StateObject private var model = TrainingModel()
    @State private var query = ""
    @State private var filter = TrainingFilter.all
    @State private var credentialEditor: TrainingCredentialEditing?
    @State private var courseEditor: TrainingCourseEditing?
    @State private var opened: TrainingCredential?
    @State private var choosing = false
    @State private var actionError: String?
    @State private var copiedCourse: String?

    init() {}

    private var identity: LearnIdentity? { LearnIdentity(session) }

    private func matches(_ credential: TrainingCredential, _ needle: String) -> Bool {
        needle.isEmpty || [credential.name, credential.number ?? "", credential.issuer ?? ""]
            .contains { $0.localizedCaseInsensitiveContains(needle) }
    }

    private func matches(_ course: TrainingCourse, _ needle: String) -> Bool {
        needle.isEmpty || [course.title, course.progress ?? "", course.link ?? ""]
            .contains { $0.localizedCaseInsensitiveContains(needle) }
    }

    private func subtitle(_ credentials: [TrainingCredential], today: Date) -> String {
        guard !credentials.isEmpty else { return "Licenses, certifications and courses" }
        let count = credentials.count == 1 ? "1 license" : "\(credentials.count) licenses"
        let due = credentials.filter { CredentialExpiry(expiresOn: $0.expiresOn, today: today).needsAttention }.count
        return due == 0 ? "\(count) \u{00B7} all in date" : "\(count) \u{00B7} \(due) need attention"
    }

    var body: some View {
        let today = Date()
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = CredentialExpiry.sorted(model.credentials, today: today)
        let credentials = all.filter { matches($0, needle) }
        let attention = credentials.filter { CredentialExpiry(expiresOn: $0.expiresOn, today: today).needsAttention }
        let courses = model.courses.filter { matches($0, needle) }.sorted { !$0.done && $1.done }
        let showsLicenses = filter != .learning
        let showsLearning = filter != .licenses
        let nothingMatches = !needle.isEmpty && (showsLicenses ? credentials.isEmpty : true) && (showsLearning ? courses.isEmpty : true)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PaperHeader(title: "Training", subtitle: subtitle(all, today: today))
                // Paper 28: the search field, then All / Training / Manuals; here the two kinds kept on this phone.
                PlaceSearchField(query: $query, identifier: "training-search")
                PaperTabs(options: ["All", "Licenses", "Learning"], selection: Binding(
                    get: { filter == .all ? "All" : filter == .licenses ? "Licenses" : "Learning" },
                    set: { filter = $0 == "Licenses" ? .licenses : $0 == "Learning" ? .learning : .all }))
                    .padding(.top, 16)
                VStack(alignment: .leading, spacing: 0) {
                    if let error = actionError ?? model.error {
                        Text(error).font(Theme.font(15)).foregroundStyle(Theme.destructive)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, PaperCardMetrics.margin + 4).padding(.top, 14)
                    }
                    if nothingMatches {
                        PaperEmptyState(symbol: "magnifyingglass", title: "No matches",
                                        message: "No license or course matches \u{201C}\(needle)\u{201D}.",
                                        actionTitle: "Clear search") { query = "" }
                            .padding(.top, 22)
                    } else {
                        if showsLicenses && !attention.isEmpty {
                            // Paper 28 "Pinned": what is due, with its state in a chip.
                            PaperCardLabel(title: "Needs attention", count: attention.count).padding(.top, 22)
                            PaperRowsCard {
                                ForEach(attention) { credential in
                                    if credential.id != attention.first?.id { WellDivider(leading: 48) }
                                    credentialRow(credential, today: today, chip: true)
                                }
                            }
                        }
                        if showsLicenses {
                            PaperCardLabel(title: "Licenses and certifications") {
                                sectionAdd("Add license", identifier: "training-add-license") {
                                    credentialEditor = TrainingCredentialEditing(record: nil)
                                }
                            }
                            .padding(.top, 22)
                            PaperRowsCard {
                                if credentials.isEmpty {
                                    LearnEmptyRow(title: "No licenses yet",
                                                  message: "Add a license or certification with its number and the day it expires. Add a photo of the card to show on site.")
                                } else {
                                    ForEach(credentials) { credential in
                                        if credential.id != credentials.first?.id { WellDivider(leading: 48) }
                                        credentialRow(credential, today: today, chip: false)
                                    }
                                }
                            }
                        }
                        if showsLearning {
                            PaperCardLabel(title: "My learning") {
                                sectionAdd("Add course", identifier: "training-add-course") {
                                    courseEditor = TrainingCourseEditing(record: nil)
                                }
                            }
                            .padding(.top, 22)
                            PaperRowsCard {
                                if courses.isEmpty {
                                    LearnEmptyRow(title: "Nothing in progress",
                                                  message: "Add a course you are taking, with its link and a note on how far you are.")
                                } else {
                                    ForEach(courses) { course in
                                        if course.id != courses.first?.id { WellDivider(leading: 48) }
                                        courseRow(course)
                                    }
                                }
                            }
                        }
                    }
                    PlacePhoneLine(text: "Kept on this phone \u{00B7} the office doesn\u{2019}t see it").padding(.top, 16)
                }
                .padding(.bottom, 24)
                .id(model.revision)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .foregroundStyle(Theme.foreground)
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("training-root")
        .placeBarCreate("Add to Training", shows: model.isBound) { choosing = true }
        .task(id: identity?.key ?? "") {
            credentialEditor = nil
            courseEditor = nil
            opened = nil
            actionError = nil
            model.bind(identity)
            #if DEBUG
            if PaperPreview.enabled {
                switch PaperPreview.screen {
                case "training-license": opened = model.credentials.first
                case "training-license-editor": credentialEditor = TrainingCredentialEditing(record: model.credentials.first)
                default: break
                }
            }
            #endif
        }
        .thorbisDestination(item: $opened) { credential in
            TrainingCredentialDetail(id: credential.id, model: model)
        }
        .thorbisConfirm("Add to Training", isPresented: $choosing, actions: [
            ThorbisConfirmAction("License or certification") { credentialEditor = TrainingCredentialEditing(record: nil) },
            ThorbisConfirmAction("Course I\u{2019}m taking") { courseEditor = TrainingCourseEditing(record: nil) },
        ])
        .sheet(item: $credentialEditor) { editing in SheetSurface {
            TrainingCredentialEditor(record: editing.record, photoURL: model.photoURL(editing.record?.photoFile)) { saved, photo in
                try model.save(saved, photo: photo)
                actionError = nil
            }
        } }
        .sheet(item: $courseEditor) { editing in SheetSurface {
            TrainingCourseEditor(record: editing.record) { saved in
                try model.save(saved)
                actionError = nil
            }
        } }
    }

    private func expiryColor(_ expiry: CredentialExpiry) -> Color {
        switch expiry {
        case .expired: Theme.destructive
        case .today, .soon: Theme.warning
        case .valid: Theme.success
        case .none: Theme.muted
        }
    }

    /// Paper 58C's row: the license over its number, where it stands at the trailing edge.
    /// Paper 28's "View all" beside a group's label (13 Semibold brand); here it adds to the group.
    private func sectionAdd(_ label: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Add").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.brandText)
                .frame(minWidth: 44, minHeight: 44, alignment: .trailing).contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .padding(.vertical, -13)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    /// Paper 28: a pinned row leads with an 8pt dot and ends on a 26-tall chip; a listed one leads
    /// with the page mark and ends on a chevron. 64 tall, 14 from the trailing edge.
    private func credentialRow(_ credential: TrainingCredential, today: Date, chip: Bool) -> some View {
        let expiry = CredentialExpiry(expiresOn: credential.expiresOn, today: today)
        let label = CredentialExpiry.label(expiresOn: credential.expiresOn, today: today)
        let line = [credential.issuer ?? "", credential.number.map { "#\($0)" } ?? ""].filter { !$0.isEmpty }
            .joined(separator: " \u{00B7} ")
        let warm = expiry == .today || isSoon(expiry)
        return Button { opened = credential } label: {
            if chip {
                OnPhoneRow(title: credential.name, subtitle: line.isEmpty ? nil : line, leadingWidth: 20, minHeight: 64, trailingInset: 14) {
                    Circle().fill(warm ? Theme.statusInProgress : Theme.destructive).frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                } trailing: {
                    Text(label).font(Theme.font(13, weight: .semibold))
                        .foregroundStyle(expiryColor(expiry))
                        .lineLimit(1)
                        .padding(.horizontal, 10).frame(minHeight: 26)
                        .background(warm ? Theme.warningSurface : Theme.destructiveSurface, in: Capsule())
                }
            } else {
                OnPhoneRow(title: credential.name, subtitle: expiry.needsAttention || line.isEmpty ? label : "\(line) \u{00B7} \(label)",
                         subtitleColor: expiry.needsAttention ? expiryColor(expiry) : Theme.muted,
                         leadingWidth: 20, minHeight: 64, trailingInset: 14) {
                    PaperIcon(.placePage, size: 20, color: Theme.subtle)
                } trailing: {
                    PlaceChevron()
                }
            }
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the license")
    }

    private func isSoon(_ expiry: CredentialExpiry) -> Bool {
        if case .soon = expiry { return true }
        return false
    }

    /// Paper 28's training row: a play mark, the course, a quiet line; its ••• holds the rest.
    private func courseRow(_ course: TrainingCourse) -> some View {
        let host = TrainingLink.host(course.link)
        let line = (course.progress ?? "").isEmpty ? (course.done ? "Finished" : "No progress note yet") : (course.progress ?? "")
        var items: [ThorbisMenuItem] = [
            ThorbisMenuItem(course.done ? "Mark not done" : "Mark done", icon: course.done ? "circle" : "checkmark.circle") {
                var next = course
                next.done.toggle()
                run { try model.save(next) }
            },
        ]
        if let url = TrainingLink.url(course.link) {
            items.append(ThorbisMenuItem("Copy link", icon: "doc.on.doc") {
                UIPasteboard.general.string = url.absoluteString
                copiedCourse = course.id
            })
        }
        items.append(ThorbisMenuItem("Edit", icon: "pencil") { courseEditor = TrainingCourseEditing(record: course) })
        items.append(ThorbisMenuItem("Remove", icon: "trash", role: .destructive) { run { try model.removeCourse(course.id) } })
        let quiet = copiedCourse == course.id ? "Link copied" : [line, host ?? ""].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
        return HStack(spacing: 0) {
            Button { courseEditor = TrainingCourseEditing(record: course) } label: {
                OnPhoneRow(title: course.title, subtitle: quiet, subtitleColor: course.done ? Theme.success : Theme.muted,
                         leadingWidth: 20, minHeight: 64, trailingInset: 0,
                         titleColor: course.done ? Theme.subtle : Theme.foreground) {
                    PaperIcon(.placePlay, size: 20, color: Theme.subtle)
                } trailing: {
                    EmptyView()
                }
            }
            .buttonStyle(RowPressStyle())
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the course to edit")
            // Paper ends the row on a chevron; this row's other moves (mark done, copy link,
            // remove) have no other home, so it ends on the ••• that holds them.
            ThorbisMenu(items: items, accessibilityLabel: "Options for \(course.title)") {
                PaperIcon(.more, size: 16, color: Theme.muted)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .padding(.trailing, 4)
        }
    }

    private func run(_ work: () throws -> Void) {
        do { try work(); actionError = nil }
        catch { actionError = error.localizedDescription }
    }
}

// MARK: - License page

private struct TrainingFact: Identifiable {
    let label: String
    let value: String
    var id: String { label }
}

/// Paper 58C's license, opened: its name, where it stands, the card's photo, then the details
/// with Edit beside the label.
private struct TrainingCredentialDetail: View {
    let id: String
    @ObservedObject var model: TrainingModel
    @Environment(\.dismiss) private var dismiss
    @State private var editing: TrainingCredentialEditing?
    @State private var confirmRemove = false
    @State private var actionError: String?
    @State private var photo: UIImage?
    @State private var copied = false

    private func facts(_ credential: TrainingCredential) -> [TrainingFact] {
        var rows: [TrainingFact] = []
        if let number = credential.number { rows.append(TrainingFact(label: "Number", value: number)) }
        if let issuer = credential.issuer { rows.append(TrainingFact(label: "Issued by", value: issuer)) }
        if let date = LearnDay.date(from: credential.expiresOn) {
            rows.append(TrainingFact(label: "Expires", value: LearnDay.label(date)))
        }
        return rows
    }

    private func page(_ credential: TrainingCredential) -> some View {
        let today = Date()
        let expiry = CredentialExpiry(expiresOn: credential.expiresOn, today: today)
        let rows = facts(credential)
        return VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text(credential.name).font(Theme.font(34, weight: .bold)).tracking(-0.85)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(CredentialExpiry.label(expiresOn: credential.expiresOn, today: today))
                    .font(Theme.font(15, weight: expiry.needsAttention ? .semibold : .regular))
                    .foregroundStyle(statusColor(expiry))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)
            if let actionError {
                Text(actionError).font(Theme.font(15)).foregroundStyle(Theme.destructive)
                    .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
            }
            if let photo {
                PaperSection("Card") {
                    Image(uiImage: photo).resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(12)
                        .accessibilityLabel("Photo of the \(credential.name) card")
                }
            }
            PaperSection(title: "Details") {
                if rows.isEmpty {
                    Text("No number, issuer or expiry date yet.").font(Theme.font(15)).foregroundStyle(Theme.muted)
                        .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 14)
                } else {
                    ForEach(rows) { fact in
                        if fact.id != rows.first?.id { WellDivider() }
                        PaperDetailRow(label: fact.label) { Text(fact.value).textSelection(.enabled) }
                            .padding(.horizontal, PaperCardMetrics.inset).frame(minHeight: 52)
                    }
                }
            } accessory: {
                LearnSectionAction(title: "Edit", label: "Edit license", identifier: "training-license-edit") {
                    editing = TrainingCredentialEditing(record: credential)
                }
            }
            if let number = credential.number {
                Button {
                    UIPasteboard.general.string = number
                    copied = true
                } label: {
                    Text(copied ? "Number copied" : "Copy number")
                        .font(Theme.font(16, weight: .semibold)).foregroundStyle(Theme.foreground)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Theme.fill, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .accessibilityIdentifier("training-license-copy")
            }
            if let notes = credential.notes, !notes.isEmpty {
                PaperSection("Notes") {
                    Text(notes).font(Theme.font(15)).foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 12)
                }
            }
            LearnFootnote(text: "Saved on this phone only. The office and your other devices don\u{2019}t see it.")
        }
    }

    private func statusColor(_ expiry: CredentialExpiry) -> Color {
        switch expiry {
        case .expired: Theme.destructive
        case .today, .soon: Theme.warning
        case .valid: Theme.success
        case .none: Theme.muted
        }
    }

    var body: some View {
        let credential = model.credential(id)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let credential {
                    page(credential)
                } else {
                    Text("This license is no longer on this phone.").font(Theme.font(15)).foregroundStyle(Theme.muted)
                        .padding(.horizontal, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .paperCardMargin().padding(.top, 8).padding(.bottom, 24)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if credential != nil {
                ThorbisToolbarItem(placement: .topBarTrailing) {
                    ThorbisMenu(items: [
                        ThorbisMenuItem("Edit", icon: "pencil") { editing = TrainingCredentialEditing(record: model.credential(id)) },
                        ThorbisMenuItem("Remove", icon: "trash", role: .destructive) { confirmRemove = true },
                    ], accessibilityLabel: "License actions") {
                        PaperCircleLabel(symbol: "ellipsis", size: 44, fill: Theme.card)
                    }
                }
            }
        }
        .task(id: "\(model.revision)|\(credential?.photoFile ?? "")") {
            guard let url = model.photoURL(credential?.photoFile) else { photo = nil; return }
            photo = UIImage(contentsOfFile: url.path)
        }
        .thorbisConfirm("Remove this license?", message: "It and its card photo are deleted from this phone.",
                        isPresented: $confirmRemove, actions: [
            ThorbisConfirmAction("Remove", role: .destructive) {
                do { try model.removeCredential(id); dismiss() }
                catch { actionError = error.localizedDescription }
            },
        ])
        .sheet(item: $editing) { item in SheetSurface {
            TrainingCredentialEditor(record: item.record, photoURL: model.photoURL(item.record?.photoFile)) { saved, change in
                try model.save(saved, photo: change)
                actionError = nil
            }
        } }
    }
}

// MARK: - Editors

/// Add or edit a license: its name and number, who issued it, the day it expires, a photo of
/// the card and a note. Saved on this phone only, and it says so under the cards.
private struct TrainingCredentialEditor: View {
    let record: TrainingCredential?
    let photoURL: URL?
    let onSave: (TrainingCredential, CredentialPhotoChange) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var number: String
    @State private var issuer: String
    @State private var expires: Date?
    @State private var notes: String
    @State private var missingName = false
    @State private var error: String?
    /// A photo chosen in this sheet, not yet saved.
    @State private var picked: UIImage?
    @State private var removed = false
    @State private var existing: UIImage?
    @State private var pick: PhotosPickerItem?
    @State private var showCamera = false

    init(record: TrainingCredential?, photoURL: URL?,
         onSave: @escaping (TrainingCredential, CredentialPhotoChange) throws -> Void) {
        self.record = record
        self.photoURL = photoURL
        self.onSave = onSave
        _name = State(initialValue: record?.name ?? "")
        _number = State(initialValue: record?.number ?? "")
        _issuer = State(initialValue: record?.issuer ?? "")
        _expires = State(initialValue: LearnDay.date(from: record?.expiresOn))
        _notes = State(initialValue: record?.notes ?? "")
    }

    private var shown: UIImage? { picked ?? (removed ? nil : existing) }
    private var cameraReady: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
            && ![.denied, .restricted].contains(AVCaptureDevice.authorizationStatus(for: .video))
    }

    var body: some View {
        VStack(spacing: 0) {
            LearnEditorHeader(title: record == nil ? "Add license" : "Edit license",
                              saveIdentifier: "training-license-save", onCancel: { dismiss() }, onSave: save)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let error {
                        Text(error).font(Theme.font(15)).foregroundStyle(Theme.destructive)
                            .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
                    }
                    LearnCard {
                        LearnField(label: "Name", text: Binding(get: { name }, set: { name = $0; missingName = false }),
                                   prompt: "EPA 608 Universal",
                                   problem: missingName ? "Add the name to save." : nil,
                                   capitalization: .words, identifier: "training-license-name")
                        WellDivider()
                        LearnField(label: "Number", text: $number, prompt: "License or certificate number",
                                   capitalization: .characters)
                        WellDivider()
                        LearnField(label: "Issued by", text: $issuer, prompt: "State board, EPA, manufacturer",
                                   capitalization: .words)
                    }
                    LearnCard { LearnDateRow(title: "Expires", date: $expires) }
                    photoCard
                    LearnCard {
                        LearnField(label: "Notes", text: $notes, prompt: "Renewal steps, class hours, who to call", multiline: true)
                    }
                    LearnFootnote(text: "Saved on this phone only. The office and your other devices don\u{2019}t see it.")
                }
                .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background.ignoresSafeArea())
        .task {
            if let photoURL { existing = UIImage(contentsOfFile: photoURL.path) }
        }
        .onChange(of: pick) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    picked = image
                    removed = false
                    error = nil
                } else {
                    error = "That photo could not be read. Choose another."
                }
                pick = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraCapture { image in
                showCamera = false
                if let image { picked = image; removed = false; error = nil }
            }
            .ignoresSafeArea()
        }
    }

    /// The card's photo: what is there, then Take photo, Choose photo and Remove.
    private var photoCard: some View {
        LearnCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Photo of the card").font(Theme.font(13)).foregroundStyle(Theme.muted)
                if let shown {
                    Image(uiImage: shown).resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .accessibilityLabel("Photo of the card")
                } else {
                    Text("No photo yet. A photo lets you show the card on site without your wallet.")
                        .font(Theme.font(15)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { photoButtons }
                    VStack(alignment: .leading, spacing: 8) { photoButtons }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var photoButtons: some View {
        if cameraReady {
            Button { showCamera = true } label: { TrainingCapsuleLabel(title: "Take photo", symbol: "camera") }
                .buttonStyle(PressStyle())
                .accessibilityIdentifier("training-license-camera")
        }
        PhotosPicker(selection: $pick, matching: .images) { TrainingCapsuleLabel(title: "Choose photo", symbol: "photo.on.rectangle") }
            .buttonStyle(PressStyle())
            .accessibilityIdentifier("training-license-photo")
        if shown != nil {
            Button { picked = nil; removed = true } label: { TrainingCapsuleLabel(title: "Remove", symbol: "trash") }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Remove photo")
        }
    }

    private func clean(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func save() {
        guard let title = clean(name) else { missingName = true; return }
        var change = CredentialPhotoChange.keep
        if let picked {
            guard let data = TrainingCardPhoto.jpeg(picked) else {
                error = "That photo could not be saved. Choose another."
                return
            }
            change = .replace(data)
        } else if removed {
            change = .remove
        }
        let saved = TrainingCredential(id: record?.id ?? UUID().uuidString, name: title, number: clean(number),
                                       issuer: clean(issuer), expiresOn: expires.map { LearnDay.string(from: $0) },
                                       photoFile: record?.photoFile, notes: clean(notes),
                                       createdAt: record?.createdAt ?? ISO8601DateFormatter().string(from: Date()))
        do { try onSave(saved, change); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

/// A quiet capsule button's face: a mark and a word on the fill, 44 tall.
private struct TrainingCapsuleLabel: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 14, weight: .medium)).accessibilityHidden(true)
            Text(title).font(Theme.font(15, weight: .medium)).fixedSize()
        }
        .foregroundStyle(Theme.foreground)
        .padding(.horizontal, 14).frame(minHeight: 44)
        .background(Theme.fill, in: Capsule())
        .contentShape(Capsule())
    }
}

/// Add or edit a course the person is taking: its title, link, a progress note and Done.
private struct TrainingCourseEditor: View {
    let record: TrainingCourse?
    let onSave: (TrainingCourse) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var link: String
    @State private var progress: String
    @State private var done: Bool
    @State private var missingTitle = false
    @State private var badLink = false
    @State private var error: String?

    init(record: TrainingCourse?, onSave: @escaping (TrainingCourse) throws -> Void) {
        self.record = record
        self.onSave = onSave
        _title = State(initialValue: record?.title ?? "")
        _link = State(initialValue: record?.link ?? "")
        _progress = State(initialValue: record?.progress ?? "")
        _done = State(initialValue: record?.done ?? false)
    }

    var body: some View {
        VStack(spacing: 0) {
            LearnEditorHeader(title: record == nil ? "Add course" : "Edit course",
                              saveIdentifier: "training-course-save", onCancel: { dismiss() }, onSave: save)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let error {
                        Text(error).font(Theme.font(15)).foregroundStyle(Theme.destructive)
                            .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
                    }
                    LearnCard {
                        LearnField(label: "Title", text: Binding(get: { title }, set: { title = $0; missingTitle = false }),
                                   prompt: "EPA 608 renewal",
                                   problem: missingTitle ? "Add the title to save." : nil,
                                   identifier: "training-course-title")
                        WellDivider()
                        LearnField(label: "Link", text: Binding(get: { link }, set: { link = $0; badLink = false }),
                                   prompt: "https://",
                                   problem: badLink ? "Use a web address that starts with https://, or leave it empty." : nil,
                                   keyboard: .URL, capitalization: .never)
                    }
                    LearnCard {
                        LearnField(label: "Progress", text: $progress, prompt: "Module 2 of 4, exam booked for Friday", multiline: true)
                        WellDivider()
                        ThorbisSheetToggleRow(label: "Done", isOn: $done)
                            .accessibilityIdentifier("training-course-done")
                    }
                    LearnFootnote(text: "Saved on this phone only. Thorbis keeps the link for you to copy; it does not open it or track the course.")
                }
                .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background.ignoresSafeArea())
    }

    private func save() {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = link.trimmingCharacters(in: .whitespacesAndNewlines)
        missingTitle = name.isEmpty
        badLink = !address.isEmpty && TrainingLink.url(address) == nil
        guard !missingTitle, !badLink else { return }
        let note = progress.trimmingCharacters(in: .whitespacesAndNewlines)
        let saved = TrainingCourse(id: record?.id ?? UUID().uuidString, title: name,
                                   link: address.isEmpty ? nil : address, progress: note.isEmpty ? nil : note, done: done,
                                   createdAt: record?.createdAt ?? ISO8601DateFormatter().string(from: Date()))
        do { try onSave(saved); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

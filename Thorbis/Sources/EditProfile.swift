import SwiftUI

// MARK: - Edit profile (Paper "Missing screens" 65B)
//
// The person's own name, through Better Auth `POST /api/auth/update-user` (`{ name }`, answers
// `{ status: true }`). The auth user holds only a name, an email and an image URL, and nothing
// uploads a person's photo, so Paper's Change photo, Name customers see, Mobile, Face ID to unlock,
// Two-step sign in and the "on my way" note are left out. Email is shown, not edited: update-user
// does not change it.

struct ProfileNameUpdate: Encodable {
    let name: String
}

/// The words and checks Edit profile shows, kept apart from the view so they are unit-tested.
enum ProfileEdit {
    /// The name as it will be saved: no spaces at either end.
    static func clean(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Said under the field when Save is pressed with no name.
    static func nameProblem(_ name: String) -> String? {
        clean(name).isEmpty ? "Add your name." : nil
    }

    static func hasChanges(original: String, edited: String) -> Bool {
        clean(original) != clean(edited)
    }

    /// Up to two letters from the name, or from the email when there is no name.
    static func initials(name: String, email: String?) -> String {
        let source = clean(name).isEmpty ? (email ?? "") : clean(name)
        let words = source.split(whereSeparator: { $0 == " " || $0 == "@" || $0 == "." })
        let letters = words.prefix(2).compactMap { $0.first }.map { String($0) }.joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    /// What the sheet says when the server refuses or cannot be reached.
    static func saveMessage(status: Int?, detail: String?) -> String {
        switch status {
        case 401: return "Your session ended. Sign in again to change your name."
        case 429: return "Too many changes in a row. Wait a minute, then try again."
        default: return detail ?? "Your name wasn't saved. Try again."
        }
    }
}

extension APIClient {
    /// Better Auth's own route. `authed: false` like every other `/api/auth/*` call, so a refusal here
    /// is said on the sheet instead of signing the person out.
    func updateProfileName(_ name: String) async throws {
        let _: APIClient.EmptyResponse = try await send("POST", "/api/auth/update-user",
                                                        body: ProfileNameUpdate(name: name), authed: false)
    }
}

/// 65B · Edit profile. Present as a sheet (Cancel, the title and Save in one row, as Edit customer).
/// `name` is the person's current name; `onSaved` gets the saved name.
struct EditProfileSheet: View {
    var onSaved: (String) -> Void = { _ in }
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var original: String
    @State private var saving = false
    @State private var showErrors = false
    @State private var saveError: String?
    @State private var changingPassword = false
    @FocusState private var nameFocused: Bool

    init(name: String, onSaved: @escaping (String) -> Void = { _ in }) {
        self.onSaved = onSaved
        _name = State(initialValue: name)
        _original = State(initialValue: name)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 16) {
                    avatar
                    if let saveError {
                        ErrorBanner(message: saveError, outer: 0)
                            .accessibilityIdentifier("edit-profile-error")
                    }
                    detailsCard
                    passwordCard
                }
                .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 24).padding(.bottom, 32)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.sidebar.ignoresSafeArea())
        .thorbisSheetPresentation([.large])
        .interactiveDismissDisabled(saving || ProfileEdit.hasChanges(original: original, edited: name))
        .sheet(isPresented: $changingPassword) { ChangePasswordSheet() }
    }

    // MARK: Header (Paper: Cancel pill, the 17 Semibold title, the brand Save pill)

    private var header: some View {
        PaperTaskBar(title: "Edit profile", cancelDisabled: saving, cancelIdentifier: "edit-profile-cancel",
                     commit: ThorbisSheetHeaderAction(title: "Save", busy: saving, identifier: "edit-profile-save") {
                         Task { await save() }
                     }) { dismiss() }
    }

    // MARK: Content

    /// The initials circle. There is no photo upload for a person, so there is no Change photo.
    private var avatar: some View {
        Text(ProfileEdit.initials(name: name, email: session.user?.email))
            .font(Theme.font(24, weight: .semibold))
            .foregroundStyle(Theme.brandText)
            .frame(width: 88, height: 88)
            .background(Theme.brandSurface, in: Circle())
            .dynamicTypeSize(...DynamicTypeSize.large)
            .accessibilityHidden(true)
            .frame(maxWidth: .infinity)
    }

    private var detailsCard: some View {
        card {
            VStack(alignment: .leading, spacing: 2) {
                Text("Name").font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .accessibilityHidden(true)
                TextField("Name", text: $name, prompt: .placeholder("Ramon Mendez"))
                    .font(Theme.font(17))
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .onSubmit { Task { await save() } }
                    .focused($nameFocused)
                    .onChange(of: name) { _, _ in saveError = nil }
                    .accessibilityLabel("Name")
                    .accessibilityIdentifier("edit-profile-name")
                if showErrors, let problem = ProfileEdit.nameProblem(name) {
                    FieldProblem(message: problem)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 12)
            if let email = session.user?.email, !email.isEmpty {
                WellDivider(leading: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Email").font(Theme.font(13)).foregroundStyle(Theme.muted)
                    Text(email).font(Theme.font(17))
                        .lineLimit(1).minimumScaleFactor(0.7).truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("edit-profile-email")
            }
        }
    }

    private var passwordCard: some View {
        card {
            Button { changingPassword = true } label: {
                HStack(spacing: 8) {
                    Text("Password").font(Theme.font(16)).foregroundStyle(Theme.foreground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Change").font(Theme.font(16)).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 16).frame(minHeight: 56).contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .disabled(saving)
            .accessibilityLabel("Change password")
            .accessibilityIdentifier("edit-profile-password")
        }
    }

    /// One Paper card: the card tone, radius 20, rows split by an inset hairline.
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    // MARK: Save

    private func save() async {
        guard !saving else { return }
        nameFocused = false
        showErrors = true
        saveError = nil
        guard ProfileEdit.nameProblem(name) == nil else { nameFocused = true; return }
        let cleaned = ProfileEdit.clean(name)
        guard ProfileEdit.hasChanges(original: original, edited: cleaned) else { dismiss(); return }
        saving = true
        defer { saving = false }
        do {
            try await api.updateProfileName(cleaned)
            original = cleaned
            name = cleaned
            onSaved(cleaned)
            dismiss()
        } catch is CancellationError {
            return
        } catch let problem as Problem {
            saveError = ProfileEdit.saveMessage(status: problem.status, detail: problem.detail)
        } catch {
            saveError = ProfileEdit.saveMessage(status: nil, detail: nil)
        }
    }
}

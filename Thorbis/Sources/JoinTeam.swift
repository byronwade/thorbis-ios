import SwiftUI
import UIKit
import UserNotifications

// Accepting a team invitation (Paper 05A You're invited, 05B Join the team, 05C You're in,
// 29B Join another workspace). Owners create and cancel invitations through
// /v1/organization/invitations (TeamInvites.swift); the invitee answers on Better Auth's own
// paths, which the server leaves open:
//
// - GET  /api/auth/organization/get-invitation?id=      → organizationName, inviterEmail, role, …
// - POST /api/auth/organization/accept-invitation        { invitationId } (makes it the active workspace)
// - GET  /api/auth/organization/list-user-invitations    pending invitations to the signed-in email
// - POST /api/auth/send-verification-email               { email, callbackURL }
//
// Every one needs a signed-in account whose email is the invited address, confirmed by email
// (Thorbis invitation ids are not Better Auth's opaque ids). So a signed-out person makes or
// opens their account first, and only then sees who invited them. No business rules here: the
// server decides who may join; the phone shows its answer.

// MARK: - Invitation links

/// The invitation id from the email's link (`…/accept-invitation?id=…`), the app's own scheme
/// (`thorbis://accept-invitation?id=…`) or a pasted id. Never opens anything: the id only goes to
/// this app's own API, which checks it.
enum InvitationLink {
    /// The web page the invitation email links to (TanStack `ACCEPT_INVITATION_PATH`).
    static let webPath = "/accept-invitation"
    /// Where the web app is mounted on its site (TanStack `APP_BASE_PATH`); the root is the public site.
    static let webAppBase = "/app"

    static func id(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased() else { return nil }
        var path = components.path
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        let isWebLink = scheme == "https" && path.hasSuffix(webPath)
        let isAppLink = scheme == "thorbis"
            && (components.host?.lowercased() == "accept-invitation" || path.hasSuffix(webPath))
        guard isWebLink || isAppLink else { return nil }
        guard let raw = components.queryItems?.first(where: { $0.name == "id" })?.value else { return nil }
        return validated(raw)
    }

    static func id(fromPasted text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("://") {
            guard let url = URL(string: trimmed) else { return nil }
            return id(from: url)
        }
        if trimmed.contains("accept-invitation") {
            // A link copied without its scheme ("thorbis.com/app/accept-invitation?id=…").
            guard let url = URL(string: "https://" + trimmed) else { return nil }
            return id(from: url)
        }
        return validated(trimmed)
    }

    /// Letters, digits, hyphen and underscore, 8 to 128 long (UUIDs and Better Auth ids).
    static func validated(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 8, value.count <= 128 else { return nil }
        let ok = value.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_")
        }
        return ok ? value : nil
    }

    /// Where the confirm-email link returns to, under the web app's base as the web page builds it
    /// ("/app/accept-invitation?id=…"). Without an id, the web app's own start page: left out, Better
    /// Auth would send the browser to "/", the public site.
    static func verificationCallback(for id: String?) -> String {
        guard let id, validated(id) != nil else { return webAppBase + "/" }
        // A validated id is letters, digits, "-" and "_", which the web's encodeURIComponent keeps.
        return "\(webAppBase)\(webPath)?id=\(id)"
    }
}

// MARK: - Server answers

/// `GET /api/auth/organization/get-invitation`.
struct InvitationDetails: Decodable, Equatable {
    let id: String
    let organizationId: String
    let organizationName: String
    let inviterEmail: String?
    let email: String
    /// The server's column allows none; shown as `InvitationWords.role(nil)`.
    let role: String?
    let expiresAt: String?
}

/// One row of `GET /api/auth/organization/list-user-invitations` (pending only).
struct UserInvitation: Decodable, Identifiable, Equatable {
    let id: String
    let email: String
    let role: String?
    let organizationId: String
    let organizationName: String?
    let status: String
    let expiresAt: String?
    let createdAt: String?
}

/// Better Auth's refusals, read the way the web invitation page reads them.
enum InvitationRefusal: Equatable {
    /// The account's email is not confirmed yet.
    case verifyEmail
    /// Signed in as someone the invitation was not sent to.
    case wrongAccount
    /// Used, canceled, expired or never existed.
    case gone
    /// The workspace has no room for another member.
    case teamFull
    /// No session (signed out on another device, or expired).
    case signedOut
    /// No signal or the server did not answer.
    case unreachable

    static let verifyCodes: Set<String> = [
        "EMAIL_VERIFICATION_REQUIRED_FOR_INVITATION",
        "EMAIL_VERIFICATION_REQUIRED_BEFORE_ACCEPTING_OR_REJECTING_INVITATION",
    ]

    static func from(_ error: Error) -> InvitationRefusal {
        if error.isConnectivityFailure { return .unreachable }
        guard let problem = error as? Problem else { return .unreachable }
        if let code = problem.title {
            if verifyCodes.contains(code) { return .verifyEmail }
            if code == "ORGANIZATION_MEMBERSHIP_LIMIT_REACHED" { return .teamFull }
        }
        switch problem.status {
        case 401: return .signedOut
        case 403: return .wrongAccount
        case 400, 404: return .gone
        default: return .unreachable
        }
    }

    var message: String {
        switch self {
        case .verifyEmail: "Confirm your email before you join."
        case .wrongAccount: "This invitation was sent to a different email address."
        case .gone: "This invitation no longer works. It may have expired, been canceled, or already been used. Ask whoever invited you to send a new one."
        case .teamFull: "This team is full. Ask whoever invited you to make room."
        case .signedOut: "Sign in again to answer this invitation."
        case .unreachable: "Thorbis could not be reached. Check your connection and try again."
        }
    }
}

/// Words for an invitation's role and dates.
enum InvitationWords {
    /// Said for an invitation that carries no role.
    static let noRole = "Team member"

    static func role(_ role: String?) -> String {
        guard let role = role?.trimmingCharacters(in: .whitespacesAndNewlines), !role.isEmpty else { return noRole }
        return TeamInvitation.roles.first { $0.id == role }?.label ?? role.statusLabel
    }

    /// Whether the invitation names a role, so a sentence can say "as a Technician".
    static func hasRole(_ role: String?) -> Bool {
        !(role?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    static func date(_ raw: String?) -> Date? { JobFiltering.date(raw) }

    /// "In 7 days", or nil when the date is missing or already past.
    static func expires(_ raw: String?, now: Date = Date()) -> String? {
        guard let date = date(raw), date > now else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let words = formatter.localizedString(for: date, relativeTo: now)
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    /// "Jul 18 · expires in 4 days" for a recent invite.
    static func recentLine(created: String?, expires: String?, now: Date = Date()) -> String {
        var parts: [String] = []
        if let made = date(created) { parts.append(made.formatted(.dateTime.month(.abbreviated).day())) }
        if let left = self.expires(expires, now: now) { parts.append("expires \(left.lowercased())") }
        return parts.joined(separator: " · ")
    }

    static func initial(_ name: String) -> String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
    }
}

extension APIClient {
    func invitation(id: String) async throws -> InvitationDetails {
        try await send("GET", "/api/auth/organization/get-invitation",
                       queryItems: [URLQueryItem(name: "id", value: id)], authed: false)
    }

    func acceptInvitation(id: String) async throws {
        struct Body: Encodable { let invitationId: String }
        let _: EmptyResponse = try await send("POST", "/api/auth/organization/accept-invitation",
                                              body: Body(invitationId: id), authed: false)
    }

    func userInvitations() async throws -> [UserInvitation] {
        try await send("GET", "/api/auth/organization/list-user-invitations", authed: false)
    }

    func sendInvitationVerificationEmail(email: String, invitationID: String?) async throws {
        struct Body: Encodable { let email: String; let callbackURL: String }
        let _: EmptyResponse = try await send("POST", "/api/auth/send-verification-email",
                                              body: Body(email: email, callbackURL: InvitationLink.verificationCallback(for: invitationID)),
                                              authed: false)
    }
}

/// Accept, then reopen the session so the new workspace (made active by the server) is loaded.
@MainActor
enum InvitationJoin {
    static func join(invitationID: String, organizationID: String, api: APIClient, session: SessionController) async throws {
        try await api.acceptInvitation(id: invitationID)
        await session.restore()
        if session.activeOrganization?.id != organizationID,
           session.organizations.contains(where: { $0.id == organizationID }) {
            await session.selectOrganization(id: organizationID)
        }
    }
}

// MARK: - 05A / 05B / 05C: joining from an invitation link

/// The whole join from one invitation id, in any session phase: account first when signed out,
/// then the invitation (05A), then You're in (05C). Host it above the session's phase switch so
/// signing in or creating the account does not tear it down.
struct JoinTeamFlow: View {
    let invitationID: String
    /// Leaves without joining (shown as Close when set).
    var onClose: (() -> Void)? = nil
    /// After You're in: "See today's jobs".
    let onFinished: () -> Void

    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController

    private enum Step: Equatable {
        case welcome
        case createAccount
        case signIn
        case loading
        case details(InvitationDetails)
        case confirmEmail
        case refused(InvitationRefusal)
        case joined(String)
    }

    @State private var step: Step = .loading
    @State private var busy = false
    @State private var problem: String?
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var verificationSent = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.horizontal, PaperCardMetrics.margin).padding(.bottom, 20)
                .frame(maxWidth: 470, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.canvas)
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        // Waits out a cold launch's session restore; never resets a step the person is on.
        .task(id: session.phase) {
            if step == .loading || step == .welcome { await start() }
        }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome: welcome
        case .createAccount: createAccount
        case .signIn: signIn
        case .loading:
            ThorbisLoadingLine(message: "Loading invitation\u{2026}").frame(minHeight: 240)
        case .details(let invitation): details(invitation)
        case .confirmEmail: confirmEmail
        case .refused(let refusal): refused(refusal)
        case .joined(let organization): joined(organization)
        }
    }

    /// 05A while signed out: the invitation can only be read once the invitee has an account.
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 0) {
            closeBar
            JoinHeading(title: "You're invited",
                        message: "Create your account with the email address the invitation was sent to.")
                .padding(.top, 40)
        }
    }

    /// 05B: name, email and a password make the account the invitation is answered from.
    private var createAccount: some View {
        VStack(alignment: .leading, spacing: 0) {
            stepBar(back: .welcome, label: "Step 2 of 3")
            JoinHeading(title: "Join the team", message: "This is how the office and customers see you")
                .padding(.top, 14)
            JoinCard {
                JoinTextField(label: "Full name", text: $name, placeholder: "Your name", content: .name)
                WellDivider()
                JoinTextField(label: "Email", text: $email, placeholder: "you@company.com", content: .emailAddress)
            }
            .padding(.top, 20)
            passwordCard(label: "Create password", content: .newPassword)
                .padding(.top, 16)
            if let problem { FieldProblem(message: problem).padding(.horizontal, 4).padding(.top, 8) }
        }
    }

    private var signIn: some View {
        VStack(alignment: .leading, spacing: 0) {
            stepBar(back: .welcome, label: "Step 2 of 3")
            JoinHeading(title: "Sign in", message: "Sign in with the email address the invitation was sent to.")
                .padding(.top, 14)
            JoinCard {
                JoinTextField(label: "Email", text: $email, placeholder: "you@company.com", content: .username)
            }
            .padding(.top, 20)
            passwordCard(label: "Password", content: .password)
                .padding(.top, 16)
            if let problem { FieldProblem(message: problem).padding(.horizontal, 4).padding(.top, 8) }
        }
    }

    /// 05A once the invitation is readable: who, which company, which role, until when.
    private func details(_ invitation: InvitationDetails) -> some View {
        VStack(alignment: .center, spacing: 0) {
            closeBar
            HStack(spacing: 10) {
                Text(InvitationWords.initial(invitation.organizationName))
                    .font(Theme.font(17, weight: .bold)).foregroundStyle(Color.white)
                    .frame(width: 36, height: 36)
                    .background(Theme.brand, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                Text(invitation.organizationName).font(Theme.font(17, weight: .semibold)).foregroundStyle(Theme.foreground)
            }
            .padding(.top, 40)
            Text("You're invited")
                .font(Theme.heading()).tracking(-0.56)
                .foregroundStyle(Theme.foreground)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 48)
            invitationLead(invitation)
                .font(Theme.font(17)).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24).padding(.top, 16)
            JoinCard {
                JoinFactRow(label: "Role", value: InvitationWords.role(invitation.role), strong: true)
                WellDivider()
                JoinFactRow(label: "Sent to", value: invitation.email)
                if let left = InvitationWords.expires(invitation.expiresAt) {
                    WellDivider()
                    JoinFactRow(label: "Link expires", value: left)
                }
            }
            .padding(.top, 28)
            if let problem { FieldProblem(message: problem).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4).padding(.top, 8) }
        }
    }

    private func invitationLead(_ invitation: InvitationDetails) -> Text {
        let who = Text(invitation.inviterEmail ?? "Your team")
        let lead = who + Text(" invited you to ")
            + Text(invitation.organizationName).foregroundStyle(Theme.foreground).fontWeight(.semibold)
        // With no role the sentence ends at the company; the Role row below still says "Team member".
        guard InvitationWords.hasRole(invitation.role) else { return lead + Text(".") }
        return lead + Text(" as a ")
            + Text(InvitationWords.role(invitation.role)).foregroundStyle(Theme.foreground).fontWeight(.semibold)
            + Text(".")
    }

    private var confirmEmail: some View {
        VStack(alignment: .leading, spacing: 0) {
            closeBar
            JoinHeading(title: "Confirm your email",
                        message: "Before you join, confirm that \(session.user?.email ?? "your email") is yours. We will email you a link.")
                .padding(.top, 40)
            if verificationSent {
                Text("We sent a confirmation link. Open it, then come back here and join.")
                    .font(Theme.font(15)).foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4).padding(.top, 16)
            }
            if let problem { FieldProblem(message: problem).padding(.horizontal, 4).padding(.top, 8) }
        }
    }

    private func refused(_ refusal: InvitationRefusal) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            closeBar
            JoinHeading(title: refusalTitle(refusal), message: refusalMessage(refusal))
                .padding(.top, 40)
        }
    }

    private func refusalTitle(_ refusal: InvitationRefusal) -> String {
        switch refusal {
        case .wrongAccount: "Different email address"
        case .gone, .teamFull: "Invitation unavailable"
        case .unreachable: "Invitation not loaded"
        case .verifyEmail: "Confirm your email"
        case .signedOut: "Sign in again"
        }
    }

    private func refusalMessage(_ refusal: InvitationRefusal) -> String {
        guard refusal == .wrongAccount, let current = session.user?.email else { return refusal.message }
        return "You are signed in as \(current). Sign out, then sign in or create an account with the address the invitation was sent to."
    }

    /// 05C: in, with the one permission the app asks for here.
    private func joined(_ organization: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "checkmark")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.success)
                .frame(width: 64, height: 64)
                .background(Theme.successSurface, in: Circle())
                .accessibilityHidden(true)
                .padding(.top, 56)
            Text(welcomeTitle)
                .font(Theme.font(34, weight: .bold)).tracking(-0.85)
                .foregroundStyle(Theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 14)
            Text("Welcome to \(organization).")
                .font(Theme.font(17)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
            JoinCard { JoinNotificationsRow(payments: PushNotifications.receivesPaymentAlerts(session)) }
                .padding(.top, 28)
            Text("You can change these any time in Settings.")
                .font(Theme.font(13)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4).padding(.top, 10)
        }
    }

    private var welcomeTitle: String {
        let first = session.user?.name?.split(separator: " ").first.map(String.init) ?? ""
        return first.isEmpty ? "You're in" : "You're in, \(first)"
    }

    // MARK: Bars

    @ViewBuilder private var closeBar: some View {
        if let onClose {
            HStack {
                Spacer()
                Button("Close") { onClose() }
                    .buttonStyle(ThorbisBarButtonStyle())
                    .disabled(busy)
                    .accessibilityIdentifier("join-close")
            }
            .padding(.top, 8)
        }
    }

    private func stepBar(back: Step, label: String) -> some View {
        HStack {
            PaperCircleButton(symbol: "chevron.left", label: "Back", size: 44, fill: Theme.card) {
                problem = nil
                step = back
            }
            .disabled(busy)
            Spacer()
            Text(label).font(Theme.font(15)).foregroundStyle(Theme.muted)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.top, 8)
    }

    private func passwordCard(label: String, content: UITextContentType) -> some View {
        JoinCard {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(Theme.font(13)).foregroundStyle(Theme.muted).accessibilityHidden(true)
                    Group {
                        if showPassword {
                            TextField(label, text: $password, prompt: .placeholder("Password"))
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                        } else {
                            SecureField(label, text: $password, prompt: .placeholder("Password"))
                        }
                    }
                    .textContentType(content)
                    .textFieldStyle(.plain)
                    .font(Theme.font(17, weight: .medium))
                    .foregroundStyle(Theme.foreground)
                    .accessibilityLabel(label)
                }
                Button { showPassword.toggle() } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye").foregroundStyle(Theme.muted)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showPassword ? "Hide password" : "Show password")
            }
            .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 12)
        }
    }

    // MARK: Footer (the one commit, under the thumb)

    @ViewBuilder private var footer: some View {
        VStack(spacing: 10) {
            switch step {
            case .welcome:
                commit("Accept invite", id: "join-accept") { problem = nil; step = .createAccount }
                Text("Already have an account? Sign in with")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .padding(.top, 8)
                Button { problem = nil; step = .signIn } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "envelope").font(.system(size: 15, weight: .medium)).accessibilityHidden(true)
                        Text("Email")
                    }
                    .paperButton(.card, tone: .quiet, fills: true)
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Sign in with email")
                .accessibilityIdentifier("join-sign-in-email")
            case .createAccount:
                note("You'll sign in with your email and this password.")
                commit("Join the team", id: "join-create-account") { Task { await createAccountAndContinue() } }
            case .signIn:
                commit("Sign in", id: "join-sign-in") { Task { await signInAndContinue() } }
            case .loading:
                EmptyView()
            case .details(let invitation):
                commit("Accept invite", id: "join-accept") { Task { await accept(invitation) } }
                if let inviter = invitation.inviterEmail {
                    note("Not you? Ask \(inviter) to resend the invite.")
                }
            case .confirmEmail:
                commit(verificationSent ? "I've confirmed it" : "Send confirmation email", id: "join-confirm-email") {
                    Task { if verificationSent { await lookUp() } else { await sendVerification() } }
                }
                if verificationSent {
                    quiet("Send again", id: "join-send-again") { Task { await sendVerification() } }
                }
            case .refused(let refusal):
                switch refusal {
                case .unreachable:
                    commit("Try again", id: "join-retry") { Task { await start() } }
                case .wrongAccount, .signedOut:
                    commit("Sign out", id: "join-sign-out") { Task { await signOutAndRestart() } }
                case .verifyEmail:
                    commit("Send confirmation email", id: "join-confirm-email") { Task { await sendVerification() } }
                case .gone:
                    // Someone who accepted on the web page from the confirm-email link lands here.
                    if session.user != nil {
                        quiet("Already joined on the web? Open Thorbis", id: "join-open") {
                            Task { await session.restore(); onFinished() }
                        }
                    }
                case .teamFull:
                    EmptyView()
                }
            case .joined:
                commit("See today's jobs", id: "join-done") { onFinished() }
            }
        }
        .paperActionBarGround(Theme.canvas, maxWidth: 470)
    }

    private func commit(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busy { ProgressView().tint(.white) }
                Text(title)
            }
            .inkCommit()
        }
        .buttonStyle(PressStyle())
        .disabled(busy)
        .accessibilityIdentifier(id)
    }

    private func quiet(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Theme.font(14, weight: .semibold)).foregroundStyle(Theme.brandText)
                .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityIdentifier(id)
    }

    private func note(_ words: String) -> some View {
        Text(words).font(Theme.font(13)).foregroundStyle(Theme.muted)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }

    // MARK: Actions

    private func start() async {
        problem = nil
        if session.phase == .restoring {
            step = .loading
        } else if session.user == nil {
            step = .welcome
        } else {
            await lookUp()
        }
    }

    private func lookUp() async {
        problem = nil
        step = .loading
        do {
            let invitation = try await api.invitation(id: invitationID)
            step = .details(invitation)
        } catch is CancellationError {
        } catch {
            show(InvitationRefusal.from(error))
        }
    }

    private func show(_ refusal: InvitationRefusal) {
        switch refusal {
        case .verifyEmail: step = .confirmEmail
        case .signedOut: step = session.user == nil ? .welcome : .refused(.signedOut)
        default: step = .refused(refusal)
        }
    }

    private func createAccountAndContinue() async {
        guard !busy else { return }
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fullName.isEmpty else { problem = "Add your name."; return }
        guard address.contains("@") else { problem = "Add the email the invitation was sent to."; return }
        guard !password.isEmpty else { problem = "Create a password."; return }
        busy = true
        defer { busy = false }
        problem = nil
        await session.signUp(name: fullName, email: address, password: password)
        await afterAccount()
    }

    private func signInAndContinue() async {
        guard !busy else { return }
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard address.contains("@") else { problem = "Enter your email."; return }
        guard !password.isEmpty else { problem = "Enter your password."; return }
        busy = true
        defer { busy = false }
        problem = nil
        await session.signIn(email: address, password: password)
        await afterAccount()
    }

    private func afterAccount() async {
        guard session.user != nil else {
            problem = LoginCopy.message(for: session.error)
            return
        }
        password = ""
        await lookUp()
    }

    private func accept(_ invitation: InvitationDetails) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        problem = nil
        do {
            try await InvitationJoin.join(invitationID: invitation.id, organizationID: invitation.organizationId,
                                          api: api, session: session)
            step = .joined(invitation.organizationName)
        } catch is CancellationError {
        } catch {
            let refusal = InvitationRefusal.from(error)
            if refusal == .unreachable { problem = refusal.message } else { show(refusal) }
        }
    }

    private func sendVerification() async {
        guard !busy, let address = session.user?.email else { return }
        busy = true
        defer { busy = false }
        problem = nil
        do {
            try await api.sendInvitationVerificationEmail(email: address, invitationID: invitationID)
            step = .confirmEmail
            verificationSent = true
        } catch let failure as Problem where failure.status == 429 {
            problem = "Too many confirmation emails were requested. Wait a few minutes, then try again."
        } catch is CancellationError {
        } catch {
            problem = InvitationRefusal.unreachable.message
        }
    }

    private func signOutAndRestart() async {
        busy = true
        await session.signOut()
        busy = false
        verificationSent = false
        step = .welcome
    }
}

// MARK: - 29B: join another workspace from the switcher

/// Paste an invitation link (or its id), see whose it is, join. Below, the invitations already
/// waiting for this account's email. Push it from the workspace switcher with `.thorbisBackButton()`.
struct JoinWorkspaceView: View {
    /// Called after the server accepted and the session reopened in the new workspace.
    var onJoined: (() -> Void)? = nil

    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @State private var link = ""
    @State private var found: InvitationDetails?
    @State private var looking = false
    @State private var linkProblem: String?
    @State private var recent: [UserInvitation] = []
    @State private var recentProblem: InvitationRefusal?
    @State private var joining: String?
    @State private var joinProblem: String?
    @State private var verificationSent = false
    @FocusState private var linkFocused: Bool

    private var pastedID: String? { InvitationLink.id(fromPasted: link) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Join another workspace")
                        .font(Theme.font(34, weight: .bold)).tracking(-0.85)
                        .foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text("Paste the invite link you were sent.")
                        .font(Theme.font(15)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 4).padding(.top, 14)

                linkField.padding(.top, 18)
                if let linkProblem { FieldProblem(message: linkProblem).padding(.horizontal, 4).padding(.top, 8) }
                if looking {
                    ThorbisLoadingLine(message: "Looking up the invitation\u{2026}").frame(minHeight: 64)
                } else if let found {
                    foundCard(found).padding(.top, 10)
                    Button { Task { await join(id: found.id, organizationID: found.organizationId) } } label: {
                        HStack(spacing: 8) {
                            if joining == found.id { ProgressView().tint(.white) }
                            Text("Join \(found.organizationName)")
                        }
                        .inkCommit()
                    }
                    .buttonStyle(PressStyle())
                    .disabled(joining != nil)
                    .padding(.top, 10)
                    .accessibilityIdentifier("join-workspace-commit")
                }
                if let joinProblem { FieldProblem(message: joinProblem).padding(.horizontal, 4).padding(.top, 8) }

                recentSection.padding(.top, 24)

                Text("You keep one login. Switch any time from the workspace menu.")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4).padding(.top, 8)
            }
            .padding(.horizontal, PaperCardMetrics.margin)
            .padding(.bottom, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadRecent() }
        .task(id: pastedID) { await lookUp(pastedID) }
    }

    private var linkField: some View {
        HStack(spacing: 10) {
            TextField("Invite link", text: $link, prompt: .placeholder("Invite link"))
                .font(Theme.font(17, weight: .semibold))
                .foregroundStyle(Theme.foreground)
                .textFieldStyle(.plain)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .focused($linkFocused)
                .submitLabel(.done)
                .accessibilityIdentifier("join-workspace-link")
            Button {
                if let pasted = UIPasteboard.general.string { link = pasted }
            } label: {
                Text("Paste").paperButton(.compact, tone: .quiet)
            }
            .buttonStyle(PressStyle())
            .accessibilityIdentifier("join-workspace-paste")
        }
        .padding(.leading, 16).padding(.trailing, 6)
        .frame(minHeight: 54)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(linkFocused ? Theme.brand : Color.clear, lineWidth: 1.5))
    }

    private func foundCard(_ invitation: InvitationDetails) -> some View {
        HStack(spacing: 12) {
            Text(InvitationWords.initial(invitation.organizationName))
                .font(Theme.font(16, weight: .bold)).foregroundStyle(Theme.brandText)
                .frame(width: 40, height: 40)
                .background(Theme.brandSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(invitation.organizationName).font(Theme.font(16, weight: .semibold)).foregroundStyle(Theme.foreground)
                Text(foundLine(invitation)).font(Theme.font(14)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func foundLine(_ invitation: InvitationDetails) -> String {
        let role = InvitationWords.role(invitation.role)
        guard let inviter = invitation.inviterEmail else { return role }
        return "Invited by \(inviter) · \(role)"
    }

    @ViewBuilder private var recentSection: some View {
        if recentProblem == .verifyEmail {
            VStack(alignment: .leading, spacing: 8) {
                Text(verificationSent ? "We sent a confirmation link. Open it, then come back here."
                                      : "Confirm your email to see the invitations sent to it.")
                    .font(Theme.font(15)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                Button { Task { await sendVerification() } } label: {
                    Text(verificationSent ? "Send again" : "Send confirmation email")
                        .font(Theme.font(14, weight: .semibold)).foregroundStyle(Theme.brandText)
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 4)
                .accessibilityIdentifier("join-workspace-confirm-email")
            }
        } else if !visibleRecent.isEmpty {
            PaperSection(recentTitle) {
                ForEach(Array(visibleRecent.enumerated()), id: \.element.id) { index, invitation in
                    if index > 0 { WellDivider() }
                    recentRow(invitation)
                }
            }
        }
    }

    private var visibleRecent: [UserInvitation] {
        recent.filter { $0.status == "pending" && InvitationWords.expires($0.expiresAt) != nil }
    }

    private var recentTitle: String {
        guard let email = session.user?.email else { return "Recent invites" }
        return "Recent invites to \(email)"
    }

    private func recentRow(_ invitation: UserInvitation) -> some View {
        let name = invitation.organizationName ?? InvitationWords.role(invitation.role)
        return HStack(spacing: 12) {
            Text(InvitationWords.initial(name))
                .font(Theme.font(15, weight: .bold)).foregroundStyle(Theme.foreground)
                .frame(width: 36, height: 36)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(name).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                let line = InvitationWords.recentLine(created: invitation.createdAt, expires: invitation.expiresAt)
                if !line.isEmpty {
                    Text(line).font(Theme.font(14)).foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 8)
            Button { Task { await join(id: invitation.id, organizationID: invitation.organizationId) } } label: {
                Group {
                    if joining == invitation.id {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Join").font(Theme.font(15, weight: .semibold)).foregroundStyle(Theme.brandText)
                    }
                }
                .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .disabled(joining != nil)
            .accessibilityLabel("Join \(name)")
            .accessibilityIdentifier("join-workspace-recent")
        }
        .padding(.horizontal, PaperCardMetrics.inset)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    }

    // MARK: Actions

    private func loadRecent() async {
        do {
            recent = try await api.userInvitations()
            recentProblem = nil
        } catch is CancellationError {
        } catch {
            // The list is a convenience; the pasted link still works without it.
            recentProblem = InvitationRefusal.from(error)
        }
    }

    private func lookUp(_ id: String?) async {
        found = nil
        linkProblem = nil
        joinProblem = nil
        guard let id else {
            if !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                linkProblem = "That isn't an invite link. Copy the whole link from the invitation email."
            }
            return
        }
        // Wait for the typing to settle before asking the server.
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled else { return }
        looking = true
        defer { looking = false }
        do {
            found = try await api.invitation(id: id)
        } catch is CancellationError {
        } catch {
            let refusal = InvitationRefusal.from(error)
            if refusal == .verifyEmail { recentProblem = .verifyEmail }
            linkProblem = refusal.message
        }
    }

    private func join(id: String, organizationID: String) async {
        guard joining == nil else { return }
        joining = id
        defer { joining = nil }
        joinProblem = nil
        do {
            try await InvitationJoin.join(invitationID: id, organizationID: organizationID, api: api, session: session)
            onJoined?()
        } catch is CancellationError {
        } catch {
            let refusal = InvitationRefusal.from(error)
            if refusal == .verifyEmail { recentProblem = .verifyEmail }
            joinProblem = refusal.message
        }
    }

    private func sendVerification() async {
        guard let address = session.user?.email else { return }
        // The confirm link returns to the invitation page; without a pasted id, to the web app's start page.
        do {
            try await api.sendInvitationVerificationEmail(email: address, invitationID: pastedID)
            verificationSent = true
        } catch let failure as Problem where failure.status == 429 {
            joinProblem = "Too many confirmation emails were requested. Wait a few minutes, then try again."
        } catch is CancellationError {
        } catch {
            joinProblem = InvitationRefusal.unreachable.message
        }
    }
}

// MARK: - Invite link entry (signed out)

/// Until the invitation email's HTTPS link opens the app, a signed-out invitee pastes it here
/// (from Login). The id goes to `onID`; the host then shows `JoinTeamFlow` for it.
struct InvitationLinkEntry: View {
    let onID: (String) -> Void
    @State private var link = ""
    @State private var problem: String?
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer(minLength: 0)
                    PaperCircleButton(symbol: "xmark", label: "Close", size: 44, fill: Theme.card) { dismiss() }
                        .accessibilityIdentifier("invite-link-close")
                }
                .padding(.top, 8)
                JoinHeading(title: "Join the team", message: "Paste the invite link you were sent.")
                    .padding(.top, 6)
                HStack(spacing: 10) {
                    TextField("Invite link", text: $link, prompt: .placeholder("Invite link"))
                        .font(Theme.font(17, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                        .textFieldStyle(.plain)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($focused)
                        .submitLabel(.go)
                        .onSubmit { submit() }
                        .onChange(of: link) { _, _ in problem = nil }
                        .accessibilityIdentifier("invite-link-field")
                    Button {
                        if let pasted = UIPasteboard.general.string { link = pasted }
                    } label: {
                        Text("Paste").font(Theme.font(14, weight: .semibold)).foregroundStyle(Theme.foreground)
                            .padding(.horizontal, 14).frame(height: 40)
                            .background(Theme.fill, in: Capsule())
                            .frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityIdentifier("invite-link-paste")
                }
                .padding(.leading, 16).padding(.trailing, 6)
                .frame(minHeight: 54)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(focused ? Theme.brand : Color.clear, lineWidth: 1.5))
                .padding(.top, 18)
                if let problem { FieldProblem(message: problem).padding(.horizontal, 4).padding(.top, 8) }
            }
            .padding(.horizontal, PaperCardMetrics.margin)
            .frame(maxWidth: 470, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.canvas)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button { submit() } label: { Text("Continue").inkCommit() }
                .buttonStyle(PressStyle())
                .accessibilityIdentifier("invite-link-continue")
                .paperActionBarGround(Theme.canvas, maxWidth: 470)
        }
    }

    private func submit() {
        guard let id = InvitationLink.id(fromPasted: link) else {
            problem = "That isn't an invite link. Copy the whole link from the invitation email."
            return
        }
        onID(id)
    }
}

// MARK: - Pieces

/// Paper 05A/05B: the 28 Bold title and its muted line, 20 from the edge.
private struct JoinHeading: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.heading()).tracking(-0.56)
                .foregroundStyle(Theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(Theme.font(15)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}

/// A grouped card on the canvas, radius 20.
private struct JoinCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

/// A 13pt label above a 17 Medium answer, inside a `JoinCard`.
private struct JoinTextField: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    let content: UITextContentType

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Theme.font(13)).foregroundStyle(Theme.muted).accessibilityHidden(true)
            TextField(label, text: $text, prompt: .placeholder(placeholder))
                .font(Theme.font(17, weight: .medium))
                .foregroundStyle(Theme.foreground)
                .textFieldStyle(.plain)
                .textContentType(content)
                .keyboardType(content == UITextContentType.name ? UIKeyboardType.default : UIKeyboardType.emailAddress)
                .textInputAutocapitalization(content == UITextContentType.name ? TextInputAutocapitalization.words
                                                                                : TextInputAutocapitalization.never)
                .autocorrectionDisabled()
                .accessibilityLabel(label)
        }
        .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    }
}

/// "Role  Technician": the label muted on the left, the answer on the right.
private struct JoinFactRow: View {
    let label: String
    let value: String
    var strong = false

    var body: some View {
        HStack(spacing: 12) {
            Text(label).font(Theme.font(16)).foregroundStyle(Theme.muted)
            Spacer(minLength: 8)
            Text(value).font(Theme.font(16, weight: strong ? .semibold : .regular)).foregroundStyle(Theme.foreground)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 52)
        .accessibilityElement(children: .combine)
    }
}

/// 05C's Notifications row: Turn on asks iOS once; after that it says what iOS has.
private struct JoinNotificationsRow: View {
    /// Whether the person could be sent Payment received (from the session after joining).
    let payments: Bool
    @State private var status: UNAuthorizationStatus?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "bell")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.warning)
                .frame(width: 40, height: 40)
                .background(Theme.warningSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("Notifications").font(Theme.font(16, weight: .semibold)).foregroundStyle(Theme.foreground)
                Text(AlertWords.joinSummary(payments: payments)).font(Theme.font(14)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 76)
        .task { await refresh() }
    }

    @ViewBuilder private var trailing: some View {
        if status == .notDetermined {
            Button { Task { await turnOn() } } label: {
                Text("Turn on").paperButton(.compact, tone: .quiet)
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Turn on notifications")
            .accessibilityIdentifier("join-notifications-on")
        } else if let status {
            Text(status == .denied ? "Off" : "On").font(Theme.font(15)).foregroundStyle(Theme.muted)
        }
    }

    private func refresh() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        status = settings.authorizationStatus
    }

    private func turnOn() async {
        // Paper 71: the explainer first; its commit shows the system prompt. "Maybe later"
        // leaves the row as it was.
        guard await PermissionPrimerPresenter.ask(payments ? .notificationsWithPayments : .notifications, automatic: false) else {
            await refresh()
            return
        }
        // Design-preview runs show no explainer and ask here, as before.
        let center = UNUserNotificationCenter.current()
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
        await refresh()
        // Registers this phone for the new workspace once allowed (the same path a sign-in takes).
        PushNotifications.shared.identityChanged(signedIn: true)
    }
}

/// The invitation being accepted (Paper 05A–05C): set by an opened invite link or the login
/// screen's paste, read by the app's root, which hosts `JoinTeamFlow` above the sign-in screens.
@MainActor
final class PendingInvitation: ObservableObject {
    static let shared = PendingInvitation()
    @Published var id: String?
}

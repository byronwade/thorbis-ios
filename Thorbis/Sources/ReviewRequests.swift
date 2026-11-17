import SwiftUI

// Settings › Review requests (design.thorbis.com TG-12): when an invoice is paid in full, the
// server texts the customer the owner's review link once, only with SMS consent, between 8 AM
// and 8 PM their time and never twice in 90 days. This screen sets the two organization facts
// the server reads: `review_link` and `review_requests` ("on" or "off").
// Works offline: a change is kept on this phone and sent when signal returns.

/// The link rule the server enforces (domains/organization reviewLinkUrl), checked here first
/// so a typo is caught before it is queued.
enum ReviewLink {
    static let maxLength = 100

    static func validated(_ text: String) -> String? {
        let link = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !link.isEmpty, link.count <= maxLength,
              link.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil,
              let url = URL(string: link), url.scheme == "https",
              url.user == nil, url.password == nil,
              let host = url.host, host.contains(".") else { return nil }
        return link
    }

    static let problem = "Use one https link of up to 100 characters, like https://g.page/r/yourbusiness/review."
}

/// Organization fact changes saved on this phone while offline, sent in order once signal returns.
/// Keyed by actor and company, so a sign-out or a company switch never sends another's change.
struct PendingOrganizationFacts {
    struct Change: Codable, Equatable {
        let key: String
        let value: String
    }

    private let defaults: UserDefaults
    private let storageKey = "thorbis.pendingOrganizationFacts.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private func scope(actorID: String, organizationID: String) -> String {
        "\(actorID.lowercased())|\(organizationID.lowercased())"
    }

    private func load() -> [String: [Change]] {
        defaults.data(forKey: storageKey).flatMap { try? JSONDecoder().decode([String: [Change]].self, from: $0) } ?? [:]
    }

    private func store(_ all: [String: [Change]]) {
        defaults.set(try? JSONEncoder().encode(all), forKey: storageKey)
    }

    func changes(actorID: String, organizationID: String) -> [Change] {
        load()[scope(actorID: actorID, organizationID: organizationID)] ?? []
    }

    /// A later change to the same fact replaces the earlier one: only the last value matters.
    func put(_ change: Change, actorID: String, organizationID: String) {
        var all = load()
        let key = scope(actorID: actorID, organizationID: organizationID)
        var list = (all[key] ?? []).filter { $0.key != change.key }
        list.append(change)
        all[key] = list
        store(all)
    }

    /// Removes the change only while it is still the queued value, so a newer value saved during
    /// the send stays queued.
    func remove(_ change: Change, actorID: String, organizationID: String) {
        var all = load()
        let key = scope(actorID: actorID, organizationID: organizationID)
        let list = (all[key] ?? []).filter { $0 != change }
        all[key] = list.isEmpty ? nil : list
        store(all)
    }

    func clearAll() { defaults.removeObject(forKey: storageKey) }
}

@MainActor
final class ReviewRequestsModel: ObservableObject {
    @Published var linkDraft = ""
    @Published var askForReviews = true
    @Published private(set) var savedLink: String?
    @Published private(set) var savedOn = true
    @Published private(set) var loaded = false
    @Published private(set) var saving = false
    @Published private(set) var waitingToSync = false
    @Published var linkError: String?
    @Published var loadError: String?
    @Published private(set) var switchError: String?

    /// One flush at a time: a second caller waits for the running one, then sends what is left.
    private var flushing: Task<Void, Never>?

    private let pending: PendingOrganizationFacts
    private let cacheKey = "thorbis.reviewRequests.lastLoaded.v1"

    init(pending: PendingOrganizationFacts = .init()) { self.pending = pending }

    var dirty: Bool {
        let typed = linkDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return (!typed.isEmpty && typed != (savedLink ?? "")) || askForReviews != savedOn
    }

    /// What the owner reads under the switch.
    var summary: String {
        if !askForReviews { return "Off. No review texts are sent." }
        if savedLink == nil, linkDraft.trimmingCharacters(in: .whitespaces).isEmpty {
            return "On once you add your review link."
        }
        return "On. Paid customers get one text."
    }

    private struct Cached: Codable { let organizationID: String; let link: String?; let on: Bool }

    private func remember(organizationID: String, link: String?, on: Bool) {
        UserDefaults.standard.set(try? JSONEncoder().encode(
            Cached(organizationID: organizationID.lowercased(), link: link, on: on)), forKey: cacheKey)
    }

    private func cached(organizationID: String) -> Cached? {
        UserDefaults.standard.data(forKey: cacheKey)
            .flatMap { try? JSONDecoder().decode(Cached.self, from: $0) }
            .flatMap { $0.organizationID == organizationID.lowercased() ? $0 : nil }
    }

    /// Sends anything queued, then reads the server's facts. Offline it shows the last values
    /// it loaded with queued changes applied.
    func load(api: APIClient, actorID: String?, organizationID: String?) async {
        guard let actorID, let organizationID else { return }
        // A reload (say, when signal returns) keeps what the owner is still editing.
        let keepDrafts = loaded && dirty
        await flush(api: api, actorID: actorID, organizationID: organizationID)
        do {
            let profile = try await api.organizationProfile()
            guard profile.organizationId.lowercased() == organizationID.lowercased() else {
                loadError = "The open company changed. Close this screen and try again."
                return
            }
            savedLink = profile.value("review_link")
            savedOn = profile.value("review_requests") != "off"
            remember(organizationID: organizationID, link: savedLink, on: savedOn)
            loadError = nil
        } catch is CancellationError {
            return
        } catch let problem as Problem where problem.status == 403 {
            loadError = "Review requests need the company settings permission. Ask an owner for access."
        } catch {
            if let cached = cached(organizationID: organizationID) {
                savedLink = cached.link
                savedOn = cached.on
            } else if !error.isTransientServerFailure {
                loadError = error.localizedDescription
            }
        }
        // Queued changes are what the owner last chose; show them over the server's values.
        let queued = pending.changes(actorID: actorID, organizationID: organizationID)
        for change in queued {
            if change.key == "review_link" { savedLink = change.value }
            if change.key == "review_requests" { savedOn = change.value != "off" }
        }
        waitingToSync = !queued.isEmpty
        if !keepDrafts {
            linkDraft = savedLink ?? ""
            askForReviews = savedOn
        }
        loaded = true
    }

    /// Saves both facts. Offline (or a server hiccup) keeps them on this phone; a refusal says why.
    @discardableResult
    func save(api: APIClient, actorID: String?, organizationID: String?) async -> Bool {
        guard let actorID, let organizationID else { return false }
        linkError = nil
        switchError = nil
        var changes: [PendingOrganizationFacts.Change] = []
        let typed = linkDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty, typed != (savedLink ?? "") {
            guard let link = ReviewLink.validated(typed) else {
                linkError = ReviewLink.problem
                return false
            }
            changes.append(.init(key: "review_link", value: link))
        }
        if askForReviews != savedOn {
            changes.append(.init(key: "review_requests", value: askForReviews ? "on" : "off"))
        }
        guard !changes.isEmpty else { return true }
        saving = true
        defer { saving = false }
        for change in changes { pending.put(change, actorID: actorID, organizationID: organizationID) }
        for change in changes {
            if change.key == "review_link" { savedLink = change.value }
            if change.key == "review_requests" { savedOn = change.value != "off" }
        }
        await flush(api: api, actorID: actorID, organizationID: organizationID)
        return linkError == nil && switchError == nil
    }

    /// Sends queued changes in order, one flush at a time. A connection failure keeps the rest
    /// queued; a refusal drops that change, puts back the last confirmed value and says why, since
    /// resending it would be refused again. Each confirmed value is remembered for offline opens.
    func flush(api: APIClient, actorID: String, organizationID: String) async {
        let previous = flushing
        let run = Task { [weak self] in
            await previous?.value
            await self?.sendQueued(api: api, actorID: actorID, organizationID: organizationID)
        }
        flushing = run
        await run.value
    }

    private func sendQueued(api: APIClient, actorID: String, organizationID: String) async {
        var confirmed = cached(organizationID: organizationID)
        for change in pending.changes(actorID: actorID, organizationID: organizationID) {
            do {
                try await api.confirmOrganizationFact(change.key, value: change.value,
                                                      actorID: actorID, organizationID: organizationID)
                pending.remove(change, actorID: actorID, organizationID: organizationID)
                let link = change.key == "review_link" ? change.value : (confirmed?.link ?? savedLink)
                let on = change.key == "review_requests" ? change.value != "off" : (confirmed?.on ?? savedOn)
                remember(organizationID: organizationID, link: link, on: on)
                confirmed = Cached(organizationID: organizationID.lowercased(), link: link, on: on)
            } catch is CancellationError {
                break
            } catch where error.isTransientServerFailure {
                break
            } catch {
                pending.remove(change, actorID: actorID, organizationID: organizationID)
                if change.key == "review_link" {
                    linkError = error.localizedDescription
                    savedLink = confirmed?.link
                } else {
                    switchError = error.localizedDescription
                    savedOn = confirmed?.on ?? true
                    askForReviews = savedOn
                }
            }
        }
        waitingToSync = !pending.changes(actorID: actorID, organizationID: organizationID).isEmpty
    }
}

struct ReviewRequestsView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @StateObject private var model = ReviewRequestsModel()
    @State private var saved = 0
    @FocusState private var editingLink: Bool

    private var canEdit: Bool { session.can("organization.settings.edit") }

    var body: some View {
        ScrollView {
            // As Notification rules (Paper 96): the title in 34 Bold, one muted line, then cards
            // on the canvas with their 13 Semibold labels.
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Review requests").font(Theme.font(34, weight: .bold)).tracking(-0.85)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .accessibilityAddTraits(.isHeader)
                    Text("One text after an invoice is paid")
                        .font(Theme.font(15)).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, Theme.gutter - PaperCardMetrics.margin).padding(.top, 14).padding(.bottom, 16)
                if let error = model.loadError {
                    InlineProblem(message: error).padding(.horizontal, 4).padding(.bottom, 12)
                }
                PaperCard {
                    Toggle(isOn: $model.askForReviews) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ask for reviews").font(Theme.font(16, weight: .medium))
                            Text(model.summary).font(Theme.font(14)).foregroundStyle(Theme.muted)
                        }
                    }
                    .tint(Theme.brand)
                    .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 9)
                    .frame(minHeight: 56)
                    if let error = model.switchError {
                        InlineProblem(message: error)
                            .padding(.horizontal, PaperCardMetrics.inset).padding(.bottom, 12)
                    }
                }
                note("When an invoice is paid in full, Thorbis texts the customer your review link once. Only with their SMS consent, between 8 AM and 8 PM their time, and never twice in 90 days.")
                    .padding(.bottom, 20)
                PaperSection("Review link", count: nil) {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("https://g.page/r/yourbusiness/review", text: $model.linkDraft)
                            .font(Theme.font(16))
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($editingLink)
                            .onChange(of: model.linkDraft) { _, _ in model.linkError = nil }
                            .accessibilityLabel("Review link")
                        if let error = model.linkError {
                            InlineProblem(message: error)
                        }
                    }
                    .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 12)
                    .frame(minHeight: 56)
                }
                note("Your Google, Yelp or Facebook review page.")
                    .padding(.bottom, 20)
                if model.waitingToSync {
                    Label("Saved on this phone. Sends when you're back online.", systemImage: "icloud.and.arrow.up")
                        .font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .padding(.horizontal, 4).padding(.bottom, 20)
                }
                if model.loaded, model.askForReviews, let link = ReviewLink.validated(model.linkDraft) {
                    // Paper F6A: the text as the customer's phone shows it, the link in the brand's words colour.
                    PaperSection("What customers get", count: nil) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Thanks for choosing \(session.activeOrganization?.name ?? "us"). Mind leaving us a review?")
                                .font(Theme.font(15)).foregroundStyle(Theme.foreground)
                            Text(link).font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.brandText)
                        }
                        .textSelection(.enabled)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(Theme.fill, in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 6,
                                                                           bottomTrailingRadius: 18, topTrailingRadius: 18,
                                                                           style: .continuous))
                        .frame(maxWidth: 300, alignment: .leading)
                        .padding(PaperCardMetrics.inset)
                    }
                }
            }
            .padding(.horizontal, PaperCardMetrics.margin).padding(.bottom, 32)
            .disabled(!canEdit || !model.loaded)
        }
        .scrollDismissesKeyboard(.interactively)
        .foregroundStyle(Theme.foreground)
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            // The commit is the brand pill at the foot, there once something changed.
            if canEdit, model.dirty || model.saving {
                PaperActionBar(title: "Save", busy: model.saving) {
                    editingLink = false
                    Task {
                        if await model.save(api: api, actorID: session.user?.id,
                                            organizationID: session.activeOrganization?.id) {
                            saved += 1
                        }
                    }
                }
            }
        }
        .sensoryFeedback(.success, trigger: saved)
        .task(id: session.isOffline) {
            await model.load(api: api, actorID: session.user?.id, organizationID: session.activeOrganization?.id)
        }
    }

    /// The quiet line under a card: 13 muted, lined up with the section labels.
    private func note(_ text: String) -> some View {
        Text(text).font(Theme.font(13)).foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4).padding(.top, 8)
    }
}

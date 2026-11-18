import SwiftUI
#if DEBUG
import UIKit
#endif

/// The time shown on an opened note. An unreadable value stays as the server sent it.
enum ActivityRecordLabel {
    static func noteWhen(_ createdAt: String) -> String {
        guard let date = JobFiltering.date(createdAt) else { return createdAt }
        return date.stampLabel()
    }
}

/// Wraps an activity row in a link only when the row already names a real record.
struct ActivityLink<Content: View>: View {
    let destination: ActivityDestination?
    /// False on the customer's timeline (Paper 48G), where the row's time takes the trailing edge.
    var showsChevron = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        if let destination {
            NavigationLink(value: destination.route) { label }
                .buttonStyle(RowPressStyle())
        } else {
            label
        }
    }

    private var label: some View {
        HStack(spacing: 8) {
            content()
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            if destination != nil && showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
    }
}

struct JobNoteDetailView: View {
    let jobID: String
    let noteID: String
    @EnvironmentObject private var api: APIClient
    @State private var note: JobNoteRecord?
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        ScrollView {
            // Paper: the words on one card, radius 20, 16 from the edge; the time under it in 13 muted.
            VStack(alignment: .leading, spacing: 8) {
                if loading { SkeletonRows(count: 3, inset: 0).padding(.horizontal, 4) }
                if let error {
                    ErrorBanner(message: error) { await load() }.padding(.horizontal, -PaperCardMetrics.margin)
                }
                if let note {
                    PaperCard(padding: PaperCardMetrics.inset) {
                        Text(note.body)
                            .font(Theme.font(16))
                            .lineSpacing(3)
                            .foregroundStyle(Theme.foreground)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    Text(ActivityRecordLabel.noteWhen(note.createdAt))
                        .font(Theme.font(13))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, PaperCardMetrics.margin)
            .padding(.vertical, 16)
        }
        .background(Theme.canvas)
        .navigationTitle("Note")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        loading = note == nil
        do {
            let notes = try await api.fieldNotes(jobID)
            note = notes.first { $0.id == noteID }
            error = note == nil ? "This note is not on the job." : nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

#if DEBUG
@MainActor final class MediaDetailRetryProbe: ObservableObject {
    static let shared = MediaDetailRetryProbe()
    @Published var status = "Ready"
    var attempts = 0
    var left = false
    var opensAfterLeaving = 0
}
#endif

private struct MediaDetailScope: Hashable {
    let actor: String
    let organization: String
    let job: String
    let sessionGeneration: UUID
    let authorityRevision: UUID
    let policy: Int
    let requestGeneration: UUID
    let savedCopyRevision: UUID
    let origin: String
}

struct JobMediaDetailView: View {
    let jobID: String
    let assetID: String
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @StateObject private var preview = DocumentPreviewController()
    @State private var asset: MediaAssetRecord?
    @State private var sourceScope: MediaDetailScope?
    @State private var loadToken = UUID()
    @State private var isVisible = false
    @State private var appearanceID = UUID()
    @State private var error: String?
    @State private var loading = true

    private var readScope: MediaDetailScope? {
        guard session.can("job.view", feature: "jobs"), let actor = session.user?.id,
              let organization = session.activeOrganization?.id, let policy = session.policyVersion,
              let origin = api.normalizedOrigin else { return nil }
        return MediaDetailScope(actor: actor, organization: organization, job: jobID,
                                sessionGeneration: session.generation, authorityRevision: session.authorityRevision,
                                policy: policy, requestGeneration: api.requestGeneration,
                                savedCopyRevision: api.savedCopyScopeRevision, origin: origin)
    }

    var body: some View {
        ScrollView {
            // Paper: a 16 Medium title over a 14 muted line, then the file on a radius-20 card.
            VStack(alignment: .leading, spacing: 12) {
                #if DEBUG
                if PaperPreview.enabled, ProcessInfo.processInfo.arguments.contains("--paper-preview-media-detail-test") {
                    Button("Revoke test job access") {
                        Task { PaperPreviewProtocol.revokeJobMediaView(); await session.revalidate() }
                    }
                }
                #endif
                if readScope == nil {
                    Text("This file is unavailable. Check your job access.")
                        .font(Theme.font(15)).foregroundStyle(Theme.muted)
                        .padding(.horizontal, 4)
                } else if readScope == sourceScope {
                    if loading || preview.loading { SkeletonRows(count: 3, inset: 0).padding(.horizontal, 4) }
                    if let message = error ?? preview.error {
                        let scheduledAppearance = appearanceID
                        ErrorBanner(message: message) {
                            #if DEBUG
                            if PaperPreview.enabled, ProcessInfo.processInfo.arguments.contains("--paper-preview-media-detail-start-after-leave") {
                                MediaDetailRetryProbe.shared.status = "Retry queued"
                                try? await Task.sleep(for: .seconds(4))
                                await load(expectedAppearance: scheduledAppearance)
                                let probe = MediaDetailRetryProbe.shared
                                probe.status = "Delayed start finished; preview opened after leaving: \(probe.opensAfterLeaving)"
                                return
                            }
                            #endif
                            await load(expectedAppearance: scheduledAppearance)
                        }
                        .padding(.horizontal, -PaperCardMetrics.margin)
                    }
                    if let asset {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(asset.caption.flatMap { $0.isEmpty ? nil : $0 } ?? asset.originalFilename)
                                .font(Theme.font(16, weight: .medium))
                                .foregroundStyle(Theme.foreground)
                            Text(asset.kind == "photo" ? "Photo" : "Document")
                                .font(Theme.font(14))
                                .foregroundStyle(Theme.muted)
                        }
                        .padding(.horizontal, 4)
                    }
                    if let url = preview.url {
                        NativeDocumentPreview(url: url)
                            .accessibilityIdentifier("media-detail-file-preview")
                            .frame(minHeight: 420)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    }
                } else {
                    SkeletonRows(count: 3, inset: 0).padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, PaperCardMetrics.margin)
            .padding(.vertical, 16)
        }
        .background(Theme.canvas)
        .navigationTitle(readScope == sourceScope && asset?.kind == "photo" ? "Photo" : "File")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { appearanceID = UUID(); isVisible = true }
        .task(id: readScope) { await load() }
        .onChange(of: readScope) { _, current in
            if sourceScope != current {
                loadToken = UUID(); preview.clear(); asset = nil; sourceScope = nil; error = nil
            }
        }
        .onDisappear {
            isVisible = false
            appearanceID = UUID()
            loadToken = UUID()
            asset = nil
            sourceScope = nil
            error = nil
            #if DEBUG
            if PaperPreview.enabled, ProcessInfo.processInfo.arguments.contains("--paper-preview-media-detail-retry-leave") {
                MediaDetailRetryProbe.shared.left = true
            }
            #endif
            preview.clear()
        }
    }

    private func load(expectedAppearance: UUID? = nil) async {
        guard isVisible, expectedAppearance.map({ $0 == appearanceID }) ?? true else { return }
        #if DEBUG
        let testingRetry = PaperPreview.enabled && ProcessInfo.processInfo.arguments.contains("--paper-preview-media-detail-retry-leave")
        let attempt: Int = {
            guard testingRetry else { return 0 }
            let probe = MediaDetailRetryProbe.shared
            probe.attempts += 1
            return probe.attempts
        }()
        defer {
            if testingRetry, attempt == 2 {
                let probe = MediaDetailRetryProbe.shared
                probe.status = "Retry finished; preview opened after leaving: \(probe.opensAfterLeaving)"
            }
        }
        #endif
        let token = UUID()
        loadToken = token
        preview.clear()
        asset = nil
        error = nil
        guard let scope = readScope else { sourceScope = nil; loading = false; return }
        sourceScope = scope
        loading = true
        do {
            #if DEBUG
            if testingRetry, attempt == 1 { throw URLError(.timedOut) }
            if testingRetry, attempt == 2 {
                MediaDetailRetryProbe.shared.status = "Retry started"
                try? await Task.sleep(for: .seconds(4))
            }
            #endif
            let assets = try await api.fieldMedia(jobID, isCurrent: { readScope == scope && loadToken == token })
            try Task.checkCancellation()
            guard readScope == scope, sourceScope == scope, loadToken == token else { return }
            guard let match = assets.first(where: { $0.id == assetID && $0.jobId == scope.job &&
                $0.organizationId == scope.organization && $0.uploadState == "stored" && !$0.archived }) else {
                error = "This file is not on the job."
                loading = false
                return
            }
            asset = match
            #if DEBUG
            if testingRetry, MediaDetailRetryProbe.shared.left { MediaDetailRetryProbe.shared.opensAfterLeaving += 1 }
            #endif
            preview.open {
                guard readScope == scope, sourceScope == scope, loadToken == token else { throw CancellationError() }
                let file: URL
                #if DEBUG
                if PaperPreview.enabled, ProcessInfo.processInfo.arguments.contains("--paper-preview-media-detail-success") {
                    let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
                    let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 100, height: 100)).pdfData { $0.beginPage() }
                    try pdf.write(to: path)
                    file = path
                } else {
                    file = try await MediaTransfer(api: api).download(mediaID: match.id, filename: match.originalFilename)
                }
                #else
                file = try await MediaTransfer(api: api).download(mediaID: match.id, filename: match.originalFilename)
                #endif
                guard !Task.isCancelled, readScope == scope, sourceScope == scope, loadToken == token else {
                    try? FileManager.default.removeItem(at: file)
                    throw CancellationError()
                }
                return file
            }
        } catch is CancellationError {
        } catch {
            guard readScope == scope, sourceScope == scope, loadToken == token else { return }
            self.error = error.localizedDescription
        }
        if readScope == scope, sourceScope == scope, loadToken == token { loading = false }
    }
}

struct CustomerContactDetailView: View {
    let customerID: String
    let contactID: String
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @Environment(\.openURL) private var openURL
    @Environment(\.inboxText) private var inboxText
    @Environment(\.inboxEmail) private var inboxEmail
    @State private var contact: CustomerContactRecord?
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        ScrollView {
            // Paper 26B "Contact": initials on a 60pt circle beside the name (28 Bold) and "Spouse ·
            // Danielle Marlowe's account", Call, Text and Email as three card tiles, then how to
            // reach them on one card. Paper's permissions, "Linked to" and "Remove from account"
            // have nothing behind them on the server yet, so they are left out.
            VStack(alignment: .leading, spacing: 0) {
                if loading { SkeletonRows(count: 3, inset: 0).padding(.horizontal, 4) }
                if let error { ErrorBanner(message: error) { await load() }.padding(.horizontal, -PaperCardMetrics.margin) }
                if let contact {
                    let phone = filled(contact.phone)
                    let email = filled(contact.email)
                    let reach = JobReach(phone: phone, email: email)
                    HStack(spacing: 14) {
                        Text(initials(contact.name))
                            .font(Theme.font(20, weight: .semibold))
                            .foregroundStyle(Theme.subtle)
                            .frame(width: 60, height: 60)
                            .background(Theme.quietFill, in: Circle())
                            .dynamicTypeSize(...DynamicTypeSize.large)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(contact.name).font(Theme.font(28, weight: .bold)).tracking(-0.56)
                                .lineLimit(2).minimumScaleFactor(0.7)
                                .foregroundStyle(Theme.foreground)
                                .accessibilityAddTraits(.isHeader)
                            if let line = identityLine(contact) {
                                Text(line).font(Theme.font(15)).foregroundStyle(Theme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    if !reach.isEmpty {
                        HStack(spacing: 8) {
                            if let call = reach.call { tile("Call", glyph: .contactCall) { openURL(call) } }
                            if let text = reach.text { tile("Text", glyph: .contactText) { inboxText(text, name: contact.name, openURL: openURL) } }
                            if let mail = reach.email {
                                tile("Email", glyph: .contactEmail) { inboxEmail(mail, context: "customer:\(customerID):contact:\(contact.id)") }
                            }
                        }
                        .padding(.top, 18)
                    }
                    if phone != nil || email != nil {
                        VStack(spacing: 0) {
                            if let phone { labeled("Mobile", phone, first: true) }
                            if let email { labeled("Email", email, first: phone == nil) }
                        }
                        .panelBackground(cornerRadius: Theme.cardRadius)
                        .padding(.top, 18)
                    }
                    if contact.primary {
                        Text("\(firstName(contact.name)) is the primary contact.")
                            .font(Theme.font(13)).foregroundStyle(Theme.muted)
                            .padding(.horizontal, 4).padding(.top, 12)
                    }
                }
            }
            .padding(.horizontal, PaperCardMetrics.margin)
            .padding(.top, 16).padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func filled(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private func firstName(_ name: String) -> String {
        name.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? name
    }

    /// "Spouse · Danielle Marlowe's account": the role, then whose account they are on.
    private func identityLine(_ contact: CustomerContactRecord) -> String? {
        let owner = store.customerName(customerID)
        let account = owner == "Customer" || owner == contact.name ? nil : "\(owner)\u{2019}s account"
        let parts = [filled(contact.role), account].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    /// Paper: a card tile, radius 18, a 20pt brand glyph 4 over the word at 14 Medium.
    private func tile(_ title: String, glyph: PaperGlyph, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                PaperIcon(glyph, size: 20, color: Theme.brandText)
                Text(title).font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.foreground)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 68)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressStyle())
    }

    /// One card row: the 13 muted label 2 over its 17 Medium value, 12 above and below.
    private func labeled(_ title: String, _ value: String, first: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Theme.font(13)).foregroundStyle(Theme.muted)
            Text(value).font(Theme.font(17, weight: .medium)).foregroundStyle(Theme.foreground).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { if !first { Rectangle().fill(Theme.border).frame(height: 1) } }
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        loading = contact == nil
        do {
            let contacts = try await api.fieldContacts(customerID)
            contact = contacts.first { $0.id == contactID }
            error = contact == nil ? "This contact is not on the customer." : nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

struct ServiceLocationDetailView: View {
    let customerID: String
    let locationID: String
    @EnvironmentObject private var api: APIClient
    @State private var location: ServiceLocationRecord?
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        ScrollView {
            // Paper record: the place's name in 34 Bold, then its address (and notes) on one card.
            VStack(alignment: .leading, spacing: 0) {
                if loading { SkeletonRows(count: 3, inset: 0).padding(.horizontal, 4) }
                if let error { ErrorBanner(message: error) { await load() }.padding(.horizontal, -PaperCardMetrics.margin) }
                if let location {
                    PaperPageTitle(title: location.label, columnInset: PaperCardMetrics.margin)
                        .padding(.bottom, 16)
                    PaperCard(padding: PaperCardMetrics.inset) {
                        Text(location.address).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                            .textSelection(.enabled)
                        if let notes = location.notes, !notes.isEmpty {
                            Text(notes).font(Theme.font(14)).foregroundStyle(Theme.muted).padding(.top, 2)
                        }
                    }
                }
            }
            .padding(.horizontal, PaperCardMetrics.margin)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.canvas)
        .navigationTitle("Location")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        loading = location == nil
        do {
            let locations = try await api.fieldLocations(customerID)
            location = locations.first { $0.id == locationID }
            error = location == nil ? "This location is not on the customer." : nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

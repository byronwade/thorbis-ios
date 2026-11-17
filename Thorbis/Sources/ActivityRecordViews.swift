import SwiftUI

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

struct JobMediaDetailView: View {
    let jobID: String
    let assetID: String
    @EnvironmentObject private var api: APIClient
    @StateObject private var preview = DocumentPreviewController()
    @State private var asset: MediaAssetRecord?
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        ScrollView {
            // Paper: a 16 Medium title over a 14 muted line, then the file on a radius-20 card.
            VStack(alignment: .leading, spacing: 12) {
                if loading || preview.loading { SkeletonRows(count: 3, inset: 0).padding(.horizontal, 4) }
                if let message = error ?? preview.error {
                    ErrorBanner(message: message) { await load() }.padding(.horizontal, -PaperCardMetrics.margin)
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
                        .frame(minHeight: 420)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                }
            }
            .padding(.horizontal, PaperCardMetrics.margin)
            .padding(.vertical, 16)
        }
        .background(Theme.canvas)
        .navigationTitle(asset?.kind == "photo" ? "Photo" : "File")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onDisappear { preview.clear() }
    }

    private func load() async {
        loading = asset == nil
        do {
            let assets = try await api.fieldMedia(jobID)
            let match = assets.first { $0.id == assetID && !$0.archived }
            asset = match
            guard let match else {
                error = "This file is not on the job."
                loading = false
                return
            }
            error = nil
            preview.open { try await MediaTransfer(api: api).download(mediaID: match.id, filename: match.originalFilename) }
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

struct CustomerContactDetailView: View {
    let customerID: String
    let contactID: String
    @EnvironmentObject private var api: APIClient
    @State private var contact: CustomerContactRecord?
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        ScrollView {
            // Paper record: the name in 34 Bold with a 15 muted line, then the ways to reach them on one card.
            VStack(alignment: .leading, spacing: 0) {
                if loading { SkeletonRows(count: 3, inset: 0).padding(.horizontal, 4) }
                if let error { ErrorBanner(message: error) { await load() }.padding(.horizontal, -PaperCardMetrics.margin) }
                if let contact {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(contact.name).font(Theme.font(34, weight: .bold)).tracking(-0.85)
                            .lineLimit(2).minimumScaleFactor(0.7)
                            .foregroundStyle(Theme.foreground)
                            .accessibilityAddTraits(.isHeader)
                        if let role = contact.role, !role.isEmpty {
                            Text(role).font(Theme.font(15)).foregroundStyle(Theme.muted)
                        }
                    }
                    .padding(.horizontal, Theme.gutter - PaperCardMetrics.margin).padding(.bottom, 16)
                    let phone = filled(contact.phone)
                    let email = filled(contact.email)
                    if phone != nil || email != nil {
                        PaperCard {
                            if let phone { labeled("Phone", phone) }
                            if phone != nil, email != nil { WellDivider() }
                            if let email { labeled("Email", email) }
                        }
                    }
                }
            }
            .padding(.horizontal, PaperCardMetrics.margin)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.canvas)
        .navigationTitle("Contact")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func filled(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    /// One card row: the 14 muted label over its 16 Medium value.
    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(Theme.font(14)).foregroundStyle(Theme.muted)
            Text(value).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground).textSelection(.enabled)
        }
        .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
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
                    Text(location.label).font(Theme.font(34, weight: .bold)).tracking(-0.85)
                        .lineLimit(2).minimumScaleFactor(0.7)
                        .foregroundStyle(Theme.foreground)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.horizontal, Theme.gutter - PaperCardMetrics.margin).padding(.bottom, 16)
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
            .padding(.vertical, 16)
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

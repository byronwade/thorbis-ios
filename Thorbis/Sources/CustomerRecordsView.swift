import SwiftUI
import UIKit

/// The customer's photos, notes, documents, estimates, invoices, and activity,
/// each list still grouped under the job it came from.
struct CustomerRecordsView: View {
    let compilation: CustomerJobCompilation
    let customerID: String
    var retryMedia: () async -> Void = {}
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var openedLegacy: LegacyCustomerPhoto?

    /// The record a Records-tab activity row opens. A payment with no invoice id stays closed.
    static func activityDestination(_ entry: CustomerHistoryEntry, customerID: String) -> ActivityDestination? {
        ActivityDestinationMapping.customerHistory(entry, customerID: customerID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if compilation.identityIncomplete {
                ErrorBanner(message: "Some customer records could not be verified. Please try again.") { await retryMedia() }
            }
            if compilation.jobsAccessible {
                photosSection
                textSection("Notes", total: compilation.noteCount, groups: compilation.notes, symbol: "note.text") { $0.body }
                mediaSection("Documents", total: compilation.documentCount, groups: compilation.documents, symbol: "doc",
                             incomplete: !compilation.documentIncompleteJobIDs.isEmpty || compilation.identityIncomplete)
            } else {
                Label("Job photos, notes, and documents are unavailable with your current access.", systemImage: "lock")
                    .font(Theme.font(15)).foregroundStyle(Theme.muted)
                    .accessibilityIdentifier("customer-job-records-unavailable")
            }
            if compilation.estimatesAccessible {
                linkedSection("Estimates", total: compilation.estimateCount, groups: compilation.estimates, symbol: "doc.text", incomplete: compilation.estimatesIncomplete || compilation.identityIncomplete, extra: compilation.estimatesOffJob.map { ($0.title, PaperRoute.estimate($0.id)) }) { estimate in
                    (estimate.title, PaperRoute.estimate(estimate.id))
                }
            } else {
                unavailable("Estimates")
            }
            if compilation.invoicesAccessible {
                linkedSection("Invoices", total: compilation.invoiceCount, groups: compilation.invoices, symbol: "doc.plaintext", incomplete: compilation.invoicesIncomplete || compilation.identityIncomplete, extra: compilation.invoicesOffJob.map { (CustomerRecordLabel.invoice($0), PaperRoute.invoice($0.id)) }) { invoice in
                    (CustomerRecordLabel.invoice(invoice), PaperRoute.invoice(invoice.id))
                }
            } else {
                unavailable("Invoices")
            }
            activitySection
        }
        .navigationDestination(item: $openedLegacy) { photo in
            LegacyCustomerPhotoDetail(photo: photo)
        }
    }

    private var photosSection: some View {
        let incomplete = !compilation.mediaIncompleteJobIDs.isEmpty || compilation.identityIncomplete
        let columns = dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return VStack(alignment: .leading, spacing: 8) {
            heading("Photos", count: compilation.photoCount, symbol: "photo", incomplete: incomplete)
            if incomplete {
                ErrorBanner(message: "Some photos may be missing or duplicated. Please try again.") {
                    await retryMedia()
                }
                .accessibilityIdentifier("customer-photo-partial")
            } else if compilation.photos.isEmpty {
                Text("None yet").font(Theme.font(15)).foregroundStyle(Theme.muted)
            }
            ForEach(compilation.photos, id: \.jobID) { group in
                jobHeading(group.title, jobID: group.jobID, count: group.count, incomplete: compilation.mediaIncompleteJobIDs.contains(group.jobID) || compilation.identityIncomplete)
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(group.items) { source in
                        photoCard(source, jobID: group.jobID)
                    }
                }
            }
        }
    }

    @ViewBuilder private func photoCard(_ source: JobPhotoSource, jobID: String) -> some View {
        switch source {
        case let .modern(asset, fallback):
            let title = asset.caption.flatMap { $0.isEmpty ? nil : $0 } ?? asset.originalFilename
            if !MediaThumbnailCache.isImage(asset), let fallback {
                Button { openedLegacy = LegacyCustomerPhoto(record: fallback, jobID: jobID) } label: {
                    photoCardBody(title: title, status: nil) { LegacyCustomerThumbnail(record: fallback, jobID: jobID) }
                }
                .buttonStyle(.plain).accessibilityLabel("Photo, \(title)")
                .accessibilityIdentifier("customer-photo-\(asset.id)")
            } else {
                NavigationLink(value: PaperRoute.media(jobID: jobID, assetID: asset.id)) {
                    photoCardBody(title: title, status: asset.uploadState == "stored" ? nil : asset.uploadState.statusLabel) {
                        MediaThumbnail(record: asset)
                    }
                }
                .buttonStyle(.plain).disabled(asset.uploadState != "stored")
                .accessibilityLabel("Photo, \(title)")
                .accessibilityHint(asset.uploadState == "stored" ? "Open photo" : "Photo is not ready yet")
                .accessibilityIdentifier("customer-photo-\(asset.id)")
            }
        case let .legacy(record):
            Button { openedLegacy = LegacyCustomerPhoto(record: record, jobID: jobID) } label: {
                photoCardBody(title: "Photo", status: nil) { LegacyCustomerThumbnail(record: record, jobID: jobID) }
            }
            .buttonStyle(.plain).accessibilityLabel("Photo from job")
            .accessibilityIdentifier("customer-legacy-photo-\(record.id)")
        }
    }

    private func photoCardBody<Content: View>(title: String, status: String?, @ViewBuilder image: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            image().frame(maxWidth: .infinity).frame(height: 120).clipped()
            Text(title).font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.foreground)
                .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 8)
            if let status {
                Text(status).font(Theme.font(12)).foregroundStyle(Theme.warning)
                    .padding(.horizontal, 10).padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private func mediaSection(_ title: String, total: Int, groups: [CustomerJobGroup<MediaAssetRecord>], symbol: String, incomplete: Bool = false) -> some View {
        section(title, total: total, symbol: symbol, groups: groups, incomplete: incomplete) { asset in
            Text(asset.caption.flatMap { $0.isEmpty ? nil : $0 } ?? asset.originalFilename)
                .font(Theme.font(15)).foregroundStyle(Theme.foreground).lineLimit(2)
        }
    }

    private func textSection(_ title: String, total: Int, groups: [CustomerJobGroup<JobNoteRecord>], symbol: String, line: @escaping (JobNoteRecord) -> String) -> some View {
        section(title, total: total, symbol: symbol, groups: groups, incomplete: compilation.notesIncomplete || compilation.identityIncomplete) { note in
            DisclosureGroup {
                Text(line(note)).font(Theme.font(15)).foregroundStyle(Theme.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Text(line(note)).font(Theme.font(15)).foregroundStyle(Theme.foreground).lineLimit(3)
            }.accessibilityHint("Expand to read the full note")
        }
    }

    private func linkedSection<Item: Identifiable>(_ title: String, total: Int, groups: [CustomerJobGroup<Item>], symbol: String, incomplete: Bool = false, extra: [(String, PaperRoute)], row: @escaping (Item) -> (String, PaperRoute)) -> some View where Item: Equatable {
        VStack(alignment: .leading, spacing: 8) {
            heading(title, count: total, symbol: symbol, incomplete: incomplete)
            if incomplete {
                ErrorBanner(message: "Some records could not be verified. Please try again.") { await retryMedia() }
            } else if groups.isEmpty && extra.isEmpty {
                Text("None yet").font(Theme.font(15)).foregroundStyle(Theme.muted)
            }
            ForEach(groups, id: \.jobID) { group in
                jobHeading(group.title, jobID: group.jobID, count: group.count)
                ForEach(group.items) { item in
                    let pair = row(item)
                    NavigationLink(value: pair.1) { rowLabel(pair.0) }.buttonStyle(RowPressStyle())
                }
            }
            if !extra.isEmpty {
                Text("Not on a job").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted).padding(.top, 4)
                ForEach(Array(extra.enumerated()), id: \.offset) { _, pair in
                    NavigationLink(value: pair.1) { rowLabel(pair.0) }.buttonStyle(RowPressStyle())
                }
            }
        }
    }

    private func section<Item: Equatable>(_ title: String, total: Int, symbol: String, groups: [CustomerJobGroup<Item>], incomplete: Bool = false, @ViewBuilder row: @escaping (Item) -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            heading(title, count: total, symbol: symbol, incomplete: incomplete)
            if incomplete {
                ErrorBanner(message: "Some job records could not be loaded. Please try again.") {
                    await retryMedia()
                }
            } else if groups.isEmpty {
                Text("None yet").font(Theme.font(15)).foregroundStyle(Theme.muted)
            }
            ForEach(groups, id: \.jobID) { group in
                jobHeading(group.title, jobID: group.jobID, count: group.count)
                ForEach(Array(group.items.enumerated()), id: \.offset) { _, item in
                    row(item).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            }
        }
    }

    private func unavailable(_ title: String) -> some View {
        Label("\(title) are unavailable with your current access.", systemImage: "lock")
            .font(Theme.font(15)).foregroundStyle(Theme.muted)
            .accessibilityIdentifier("customer-\(title.lowercased())-unavailable")
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("Activity", count: compilation.activityCount + compilation.accountActivity.count, symbol: "clock", incomplete: compilation.activityIncomplete)
            if compilation.activityIncomplete {
                ErrorBanner(message: "Some activity could not be loaded. Please try again.") { await retryMedia() }
            } else if compilation.activity.isEmpty && compilation.accountActivity.isEmpty {
                Text("None yet").font(Theme.font(15)).foregroundStyle(Theme.muted)
            }
            ForEach(compilation.activity, id: \.jobID) { group in
                jobHeading(group.title, jobID: group.jobID, count: group.count)
                ForEach(group.items) { entry in
                    ActivityLink(destination: ActivityDestinationMapping.customerHistory(entry, customerID: customerID)) {
                        Text(entry.summary).font(Theme.font(15)).foregroundStyle(Theme.foreground).lineLimit(3)
                    }
                }
            }
            if !compilation.accountActivity.isEmpty {
                Text("Account").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted).padding(.top, 4)
                ForEach(compilation.accountActivity) { entry in
                    ActivityLink(destination: ActivityDestinationMapping.customerHistory(entry, customerID: customerID)) {
                        Text(entry.summary).font(Theme.font(15)).foregroundStyle(Theme.foreground).lineLimit(3)
                    }
                }
            }
        }
    }

    private func heading(_ title: String, count: Int, symbol: String, incomplete: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(Theme.muted)
            Text(title).font(Theme.font(13, weight: .medium))
            Text(incomplete ? "Partial" : "\(count)").font(Theme.font(12))
        }.foregroundStyle(Theme.muted).accessibilityAddTraits(.isHeader)
    }

    private func jobHeading(_ title: String, jobID: String, count: Int, incomplete: Bool = false) -> some View {
        NavigationLink(value: PaperRoute.job(jobID)) {
            HStack(spacing: 6) {
                Text(title).font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground).lineLimit(1)
                Text(incomplete ? "Partial" : "\(count)").font(Theme.font(12)).foregroundStyle(Theme.muted)
                Spacer(minLength: 0)
            }.frame(minHeight: 44)
        }.buttonStyle(RowPressStyle())
    }

    private func rowLabel(_ title: String) -> some View {
        HStack {
            Text(title).font(Theme.font(15)).foregroundStyle(Theme.foreground).lineLimit(2)
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
    }
}

private struct LegacyCustomerPhoto: Identifiable, Hashable {
    let record: JobPhotoRecord
    let jobID: String
    var id: String { "\(jobID):\(record.id)" }
}

private struct LegacyCustomerPhotoDetail: View {
    let photo: LegacyCustomerPhoto
    var body: some View {
        ScrollView {
            LegacyCustomerPhotoImage(record: photo.record, jobID: photo.jobID, detail: true)
                .frame(maxWidth: .infinity, minHeight: 320)
                .padding(Theme.gutter)
        }
        .background(Theme.background)
        .navigationTitle("Photo")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LegacyCustomerThumbnail: View {
    let record: JobPhotoRecord
    let jobID: String
    var body: some View {
        LegacyCustomerPhotoImage(record: record, jobID: jobID, detail: false)
    }
}

private struct LegacyCustomerPhotoImage: View {
    let record: JobPhotoRecord
    let jobID: String
    let detail: Bool
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @Environment(\.displayScale) private var scale
    @State private var epoch = UUID()
    @State private var loadedScope: MediaThumbnailScope?
    @State private var image: UIImage?
    @State private var failed = false
    @State private var attempt = 0

    private var scope: MediaThumbnailScope? {
        guard session.can("job.view", feature: "jobs"),
              let actor = session.user?.id, let organization = session.activeOrganization?.id,
              organization == record.organizationId, record.jobId == jobID,
              let policy = session.policyVersion else { return nil }
        return MediaThumbnailScope(actorID: actor, organizationID: organization, generation: session.generation,
                                   authorityRevision: session.authorityRevision, policyVersion: policy, jobID: jobID, authorizationEpoch: epoch)
    }

    var body: some View {
        let current = scope
        ZStack {
            Theme.fill
            if let image, let current, loadedScope == current {
                if detail { Image(uiImage: image).resizable().scaledToFit().accessibilityIdentifier("customer-legacy-image-loaded") }
                else { Image(uiImage: image).resizable().scaledToFill() }
            } else if detail && failed && loadedScope == current {
                VStack(spacing: 12) {
                    Text("This photo couldn't be loaded.").font(Theme.font(15))
                    Button("Try again") { attempt += 1 }.frame(minHeight: 44)
                }
            } else {
                Image(systemName: failed && loadedScope == current ? "exclamationmark.triangle" : "photo")
                    .font(.system(size: 22, weight: .light)).foregroundStyle(Theme.muted)
            }
        }
        .clipped()
        .accessibilityHidden(!detail)
        .task(id: LegacyPhotoRequest(id: record.id, scope: current, attempt: attempt)) {
            image = nil
            failed = false
            loadedScope = nil
            guard let current else { return }
            do {
                let data = try await api.legacyJobPhotoData(record, organizationID: current.organizationID, jobID: jobID)
                let pixels = detail ? 1024 : 240 * scale
                let decoded = await Task.detached(priority: .utility) {
                    LegacyPhotoDecode.thumbnail(data, pixelSize: pixels)
                }.value
                guard !Task.isCancelled, scope == current else { return }
                loadedScope = current
                image = decoded
                failed = decoded == nil
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled, scope == current else { return }
                loadedScope = current
                failed = true
            }
        }
    }
}

private struct LegacyPhotoRequest: Hashable {
    let id: String
    let scope: MediaThumbnailScope?
    let attempt: Int
}

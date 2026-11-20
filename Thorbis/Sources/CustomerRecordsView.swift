import SwiftUI
import UIKit

/// The customer's photos, notes, documents, estimates, invoices, and activity,
/// each list still grouped under the job it came from.
/// Which parts of the compiled records a screen shows. The customer page splits them across its
/// Jobs (photos, notes, documents, job activity) and Money (estimates, invoices) segments.
enum CustomerRecordsPart: CaseIterable {
    case photos, notes, documents, estimates, invoices, activity
}

struct CustomerRecordsView: View {
    let compilation: CustomerJobCompilation
    let customerID: String
    var retryMedia: () async -> Void = {}
    var parts: Set<CustomerRecordsPart> = Set(CustomerRecordsPart.allCases)
    /// Paper 48F: the customer's Media segment (chips, then each job's photos and files together).
    var mediaTab = false
    /// Each job's day for the Media segment's headings ("today", "Sep 9, 2024").
    var jobDays: [String: String] = [:]
    @State private var mediaFilter = "All"
    /// Older jobs fold to one line until "Show".
    @State private var shownMediaJobs: Set<String> = []
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.paperGroupedWells) private var wells
    @State private var openedLegacy: LegacyCustomerPhoto?
    /// These rows sit on a hub page pushed by state (Paper 48N), where a value link never opens:
    /// each row pushes its own destination by state too.
    @State private var openedRoute: PaperRoute?

    /// The record a Records-tab activity row opens. A payment with no invoice id stays closed.
    static func activityDestination(_ entry: CustomerHistoryEntry, customerID: String) -> ActivityDestination? {
        ActivityDestinationMapping.customerHistory(entry, customerID: customerID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if compilation.identityIncomplete {
                ErrorBanner(message: "Some customer records could not be verified. Please try again.") { await retryMedia() }
            }
            if mediaTab {
                if compilation.jobsAccessible { mediaSegment } else {
                    Label("Job photos, notes, and documents are unavailable with your current access.", systemImage: "lock")
                        .font(Theme.font(15)).foregroundStyle(Theme.muted)
                        .accessibilityIdentifier("customer-job-records-unavailable")
                }
            } else if compilation.jobsAccessible {
                if parts.contains(.photos) { photosSection }
                if parts.contains(.notes) {
                    textSection("Notes", total: compilation.noteCount, groups: compilation.notes, symbol: "note.text") { $0.body }
                }
                if parts.contains(.documents) {
                    mediaSection("Documents", total: compilation.documentCount, groups: compilation.documents, symbol: "doc",
                                 incomplete: !compilation.documentIncompleteJobIDs.isEmpty || compilation.identityIncomplete)
                }
            } else if !parts.isDisjoint(with: [.photos, .notes, .documents]) {
                Label("Job photos, notes, and documents are unavailable with your current access.", systemImage: "lock")
                    .font(Theme.font(15)).foregroundStyle(Theme.muted)
                    .accessibilityIdentifier("customer-job-records-unavailable")
            }
            if !parts.contains(.estimates) {
            } else if compilation.estimatesAccessible {
                linkedSection("Estimates", total: compilation.estimateCount, groups: compilation.estimates, symbol: "doc.text", incomplete: compilation.estimatesIncomplete || compilation.identityIncomplete, extra: compilation.estimatesOffJob.map { CustomerMoneyRow.estimate($0) }) { estimate in
                    CustomerMoneyRow.estimate(estimate)
                }
            } else {
                unavailable("Estimates")
            }
            if !parts.contains(.invoices) {
            } else if compilation.invoicesAccessible {
                linkedSection("Invoices", total: compilation.invoiceCount, groups: compilation.invoices, symbol: "doc.plaintext", incomplete: compilation.invoicesIncomplete || compilation.identityIncomplete, extra: compilation.invoicesOffJob.map { CustomerMoneyRow.invoice($0) }) { invoice in
                    CustomerMoneyRow.invoice(invoice)
                }
            } else {
                unavailable("Invoices")
            }
            if parts.contains(.activity) { activitySection }
        }
        .thorbisDestination(item: $openedLegacy) { photo in
            LegacyCustomerPhotoDetail(photo: photo)
        }
        .thorbisDestination(item: $openedRoute) { PaperRouteView(route: $0).tabletReadable() }
    }

    // MARK: Paper 48F

    private static let fileGlyph = PaperGlyph(box: 18, [.stroke("M5 2.5H10.5L14 6V15.5H5Z", 1.5), .stroke("M10.5 2.5V6H14", 1.5)])

    /// Chips ("All · 16", "Photos · 13", "Documents · 3"), then each job: its name with its number,
    /// day and count, its photos (the newest job three across with captions, the next four across),
    /// its files, and older jobs folded to one line with "Show".
    private var mediaSegment: some View {
        let photos = compilation.photoCount, documents = compilation.documentCount
        let incomplete = !compilation.mediaIncompleteJobIDs.isEmpty || !compilation.documentIncompleteJobIDs.isEmpty || compilation.identityIncomplete
        var order = compilation.photos.map(\.jobID)
        for group in compilation.documents where !order.contains(group.jobID) { order.append(group.jobID) }
        let showsPhotos = mediaFilter != "Documents", showsDocuments = mediaFilter != "Photos"
        let visible = order.filter { id in
            (showsPhotos && compilation.photos.contains { $0.jobID == id }) || (showsDocuments && compilation.documents.contains { $0.jobID == id })
        }
        return LazyVStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    mediaChip("All", count: photos + documents)
                    mediaChip("Photos", count: photos)
                    mediaChip("Documents", count: documents)
                }
            }
            if incomplete {
                ErrorBanner(message: "Some photos or files may be missing. Please try again.") { await retryMedia() }
                    .accessibilityIdentifier("customer-photo-partial").padding(.top, 12)
            }
            if visible.isEmpty {
                Text(mediaFilter == "Documents" ? "No documents yet" : mediaFilter == "Photos" ? "No photos yet" : "No photos or documents yet")
                    .font(Theme.font(15)).foregroundStyle(Theme.muted).padding(.horizontal, 4).padding(.top, 20)
            }
            ForEach(Array(visible.enumerated()), id: \.element) { index, jobID in
                let shots = showsPhotos ? (compilation.photos.first { $0.jobID == jobID }?.items ?? []) : []
                let files = showsDocuments ? (compilation.documents.first { $0.jobID == jobID }?.items ?? []) : []
                let title = compilation.photos.first { $0.jobID == jobID }?.title ?? compilation.documents.first { $0.jobID == jobID }?.title ?? "Job"
                if index >= 2 && !shownMediaJobs.contains(jobID) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(title) · \(mediaCounts(shots.count, files.count, short: true))").font(Theme.font(14)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                        Button { withMotion { _ = shownMediaJobs.insert(jobID) } } label: {
                            Text("Show").font(Theme.font(14, weight: .semibold)).foregroundStyle(Theme.brandText)
                                .padding(.vertical, 12).padding(.leading, 12).contentShape(Rectangle()).padding(.vertical, -12)
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel("Show \(title)")
                    }
                    .padding(.horizontal, 4).padding(.top, 20)
                } else {
                    Button { openedRoute = .job(jobID) } label: {
                        let layout = dynamicTypeSize.isAccessibilitySize
                            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
                        layout {
                            Text(title).font(Theme.font(15, weight: .semibold)).foregroundStyle(Theme.foreground)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text((["JOB-\(jobID.suffix(4).uppercased())", jobDays[jobID]].compactMap { $0 }
                                  + (shots.isEmpty ? [] : [shots.count == 1 ? "1 photo" : "\(shots.count) photos"])).joined(separator: " · "))
                                .font(Theme.font(13)).foregroundStyle(Theme.muted).lineLimit(1)
                        }
                        .padding(.horizontal, 4).padding(.top, index == 0 ? 20 : 22).padding(.bottom, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                    .accessibilityHint("Opens the job")
                    .accessibilityIdentifier("customer-records-job-\(jobID)")
                    if !shots.isEmpty {
                        let across = dynamicTypeSize.isAccessibilitySize ? 2 : index == 0 ? 3 : 4
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: across), alignment: .leading, spacing: 8) {
                            ForEach(shots) { mediaTile($0, jobID: jobID, large: index == 0) }
                        }
                        .padding(.bottom, 8)
                    }
                    VStack(spacing: 8) { ForEach(files) { mediaFile($0) } }
                }
            }
        }
    }

    private func mediaCounts(_ photos: Int, _ files: Int, short: Bool = false) -> String {
        [photos > 0 ? (photos == 1 ? "1 photo" : "\(photos) photos") : nil,
         files > 0 ? (files == 1 ? "1 doc" : "\(files) docs") : nil].compactMap { $0 }.joined(separator: ", ")
    }

    /// A 36-tall chip (44-point target): the chosen one in the ink, the rest on the card.
    private func mediaChip(_ name: String, count: Int) -> some View {
        let on = mediaFilter == name
        return Button { mediaFilter = name } label: {
            PaperChoiceChipLabel(title: "\(name) · \(count)", isOn: on)
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("customer-media-filter-\(name.lowercased())")
    }

    /// A square photo tile: radius 16 (14 when four across), its stage chip top-left and, on the
    /// newest job, its caption along the foot.
    @ViewBuilder private func mediaTile(_ source: JobPhotoSource, jobID: String, large: Bool) -> some View {
        switch source {
        case let .modern(asset, fallback):
            let title = asset.caption.flatMap { $0.isEmpty ? nil : $0 } ?? asset.originalFilename
            let stage: String? = asset.tags.contains { $0.caseInsensitiveCompare("after") == .orderedSame } ? "After"
                : asset.tags.contains { $0.caseInsensitiveCompare("before") == .orderedSame } ? "Before" : nil
            if !MediaThumbnailCache.isImage(asset), let fallback {
                Button { openedLegacy = LegacyCustomerPhoto(record: fallback, jobID: jobID) } label: {
                    mediaTileBody(stage: stage, caption: large ? title : nil, large: large) { LegacyCustomerThumbnail(record: fallback, jobID: jobID) }
                }
                .buttonStyle(.plain).accessibilityLabel("Photo, \(title)")
                .accessibilityIdentifier("customer-photo-\(asset.id)")
            } else {
                Button { openedRoute = .media(jobID: jobID, assetID: asset.id) } label: {
                    mediaTileBody(stage: stage, caption: large ? (asset.uploadState == "stored" ? title : asset.uploadState.statusLabel) : nil, large: large) {
                        MediaThumbnail(record: asset)
                    }
                }
                .buttonStyle(.plain).disabled(asset.uploadState != "stored")
                .accessibilityLabel([stage, "Photo", title].compactMap { $0 }.joined(separator: ", "))
                .accessibilityHint(asset.uploadState == "stored" ? "Open photo" : "Photo is not ready yet")
                .accessibilityIdentifier("customer-photo-\(asset.id)")
            }
        case let .legacy(record):
            Button { openedLegacy = LegacyCustomerPhoto(record: record, jobID: jobID) } label: {
                mediaTileBody(stage: nil, caption: nil, large: large) { LegacyCustomerThumbnail(record: record, jobID: jobID) }
            }
            .buttonStyle(.plain).accessibilityLabel("Photo from job")
            .accessibilityIdentifier("customer-legacy-photo-\(record.id)")
        }
    }

    private func mediaTileBody<Content: View>(stage: String?, caption: String?, large: Bool, @ViewBuilder image: () -> Content) -> some View {
        let after = stage == "After"
        let shape = RoundedRectangle(cornerRadius: large ? 16 : 14, style: .continuous)
        return (after ? Theme.successSurface : Theme.card)
            .aspectRatio(1, contentMode: .fit)
            .overlay { image().frame(maxWidth: .infinity, maxHeight: .infinity).clipped() }
            .overlay(alignment: .bottom) {
                if caption != nil {
                    LinearGradient(colors: [.clear, Theme.background.opacity(0.75)], startPoint: .top, endPoint: .bottom).frame(height: 44)
                }
            }
            .overlay(alignment: .topLeading) {
                if let stage {
                    Text(stage).font(Theme.font(large ? 12 : 11, weight: .semibold))
                        .foregroundStyle(after ? Theme.card : Theme.foreground)
                        .padding(.horizontal, large ? 8 : 7).frame(height: large ? 22 : 20)
                        .background(after ? Theme.statusDone : Theme.background.opacity(0.7), in: Capsule())
                        .padding(large ? 8 : 6)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if let caption {
                    Text(caption).font(Theme.font(12)).foregroundStyle(after ? Theme.success : Theme.muted)
                        .lineLimit(1).padding(8)
                }
            }
            .clipShape(shape).contentShape(shape)
    }

    /// A file on the card (radius 16): the brand-surface mark, its name (15 Medium) and when it was added.
    private func mediaFile(_ asset: MediaAssetRecord) -> some View {
        let added = JobFiltering.date(asset.capturedAt ?? asset.createdAt)
        return Button { openedRoute = .media(jobID: asset.jobId, assetID: asset.id) } label: {
            HStack(spacing: 12) {
                PaperIcon(Self.fileGlyph, size: 18, color: Theme.brandText)
                    .frame(width: 36, height: 36)
                    .background(Theme.brandSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 0) {
                    Text(asset.caption.flatMap { $0.isEmpty ? nil : $0 } ?? asset.originalFilename)
                        .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(asset.uploadState != "stored" ? "File is not ready yet"
                         : added.map { "Added \($0.formatted(.dateTime.month(.abbreviated).day().year()))" } ?? "Document")
                        .font(Theme.font(13)).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(RowPressStyle())
        .disabled(asset.uploadState != "stored")
        .accessibilityHint(asset.uploadState == "stored" ? "Opens the file" : "File is not ready yet")
        .accessibilityIdentifier("customer-document-\(asset.id)")
    }

    private var photosSection: some View {
        let incomplete = !compilation.mediaIncompleteJobIDs.isEmpty || compilation.identityIncomplete
        let columns = dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            // Paper 48F: three tiles across, 8 apart.
            : [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVStack(alignment: .leading, spacing: 8) {
            heading("Photos", count: compilation.photoCount, symbol: "photo", incomplete: incomplete)
            if incomplete {
                ErrorBanner(message: "Some photos may be missing or duplicated. Please try again.") {
                    await retryMedia()
                }
                .accessibilityIdentifier("customer-photo-partial")
            } else if compilation.photos.isEmpty {
                noneYet
            }
            ForEach(compilation.photos, id: \.jobID) { group in
                jobHeading(group.title, jobID: group.jobID, count: group.count, incomplete: compilation.mediaIncompleteJobIDs.contains(group.jobID) || compilation.identityIncomplete, photos: true)
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
                Button { openedRoute = .media(jobID: jobID, assetID: asset.id) } label: {
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
            // `clipped()` only clips drawing: a filled photo still answers taps beyond its 120pt
            // frame, so a tile's overflow would open the photo under it. Hit-test the frame only.
            // Paper 48F: a 114pt tile, radius 16, its caption in 12 muted under the picture.
            image().frame(maxWidth: .infinity).frame(height: 96).clipped().contentShape(Rectangle())
            Text(title).font(Theme.font(12)).foregroundStyle(Theme.muted)
                .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8).padding(.vertical, 6)
            if let status {
                Text(status).font(Theme.font(12)).foregroundStyle(Theme.warning)
                    .padding(.horizontal, 8).padding(.bottom, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelBackground(cornerRadius: 16)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func mediaSection(_ title: String, total: Int, groups: [CustomerJobGroup<MediaAssetRecord>], symbol: String, incomplete: Bool = false) -> some View {
        section(title, total: total, symbol: symbol, groups: groups, incomplete: incomplete) { asset in
            Button { openedRoute = .media(jobID: asset.jobId, assetID: asset.id) } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(asset.caption.flatMap { $0.isEmpty ? nil : $0 } ?? asset.originalFilename)
                            .font(Theme.font(15)).foregroundStyle(Theme.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                        if asset.uploadState != "stored" {
                            Text("File is not ready yet").font(Theme.font(13)).foregroundStyle(Theme.muted)
                        }
                    }
                    Spacer(minLength: 8)
                    PaperChevron()
                        .foregroundStyle(Theme.muted).accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .disabled(asset.uploadState != "stored")
            .accessibilityHint(asset.uploadState == "stored" ? "Opens the file" : "File is not ready yet")
            .accessibilityIdentifier("customer-document-\(asset.id)")
        }
    }

    private func textSection(_ title: String, total: Int, groups: [CustomerJobGroup<JobNoteRecord>], symbol: String, line: @escaping (JobNoteRecord) -> String) -> some View {
        section(title, total: total, symbol: symbol, groups: groups, incomplete: compilation.notesIncomplete || compilation.identityIncomplete) { note in
            // Left-aligned, three lines, then "More" in place (was a stock disclosure that centered
            // wrapped notes and repeated the text).
            ExpandableNoteText(text: line(note), lines: 3, color: Theme.foreground)
                .padding(.vertical, 6)
        }
    }

    private func linkedSection<Item: Identifiable>(_ title: String, total: Int, groups: [CustomerJobGroup<Item>], symbol: String, incomplete: Bool = false, extra: [CustomerMoneyRow], row: @escaping (Item) -> CustomerMoneyRow) -> some View where Item: Equatable {
        VStack(alignment: .leading, spacing: 8) {
            heading(title, count: total, symbol: symbol, incomplete: incomplete)
            if incomplete {
                ErrorBanner(message: "Some records could not be verified. Please try again.") { await retryMedia() }
            } else if groups.isEmpty && extra.isEmpty {
                noneYet
            }
            if !groups.isEmpty || !extra.isEmpty {
                panel {
                    ForEach(groups, id: \.jobID) { group in
                        jobHeading(group.title, jobID: group.jobID, count: group.count)
                        ForEach(group.items) { item in
                            moneyLink(row(item))
                        }
                    }
                    if !extra.isEmpty {
                        Text("Not on a job").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted).padding(.top, 4)
                        ForEach(extra) { item in
                            moneyLink(item)
                        }
                    }
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
                noneYet
            }
            if !groups.isEmpty {
                panel {
                    ForEach(groups, id: \.jobID) { group in
                        jobHeading(group.title, jobID: group.jobID, count: group.count)
                        ForEach(Array(group.items.enumerated()), id: \.offset) { _, item in
                            row(item).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                    }
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
                noneYet
            }
            if !compilation.activity.isEmpty || !compilation.accountActivity.isEmpty {
                panel {
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
        }
    }

    /// design 2026-10-30: the section label above its panel ("Estimates · 2"), no glyph.
    @ViewBuilder private func heading(_ title: String, count: Int, symbol: String, incomplete: Bool = false) -> some View {
        if wells {
            // Redesign phase 2: the grouped section header, "partial" in place of a count it can't vouch for.
            SectionHeader(title: title, count: incomplete ? nil : count) {
                if incomplete { Text("Partial").font(Theme.font(15)) }
            }
        } else {
            // Paper v2: the 13 Semibold label on the left, its count (or "Partial") at the trailing edge.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(incomplete ? "Partial" : "\(count)").font(Theme.font(13)).monospacedDigit()
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 4)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
    }

    /// An empty section's line, under its label's words rather than 4 points left of them.
    private var noneYet: some View {
        Text("None yet").font(Theme.font(15)).foregroundStyle(Theme.muted)
            .padding(.horizontal, RecordRoom.labelInset)
    }

    /// One white panel per section; rows pad to the panel's inset.
    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 6)
        }
    }

    private func jobHeading(_ title: String, jobID: String, count: Int, incomplete: Bool = false, photos: Bool = false) -> some View {
        Button { openedRoute = .job(jobID) } label: {
            if photos {
                // Paper 48F: the job in 15 Semibold over its tiles, "6 photos" in 13 muted trailing.
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title).font(Theme.font(15, weight: .semibold)).foregroundStyle(Theme.foreground).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(incomplete ? "Partial" : (count == 1 ? "1 photo" : "\(count) photos"))
                        .font(Theme.font(13)).monospacedDigit().foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 4).frame(minHeight: 44)
                .contentShape(Rectangle())
            } else {
                // A quiet link to the job that groups the records under it, so it never reads as one of them.
                VStack(alignment: .leading, spacing: 4) {
                    if dynamicTypeSize.isAccessibilitySize {
                        Text(title).font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.subtle)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if !dynamicTypeSize.isAccessibilitySize {
                            Text(title).font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.subtle).lineLimit(1)
                        }
                        Text(incomplete ? "Partial" : "\(count)").font(Theme.font(13)).monospacedDigit().foregroundStyle(Theme.muted)
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.muted).accessibilityHidden(true)
                        Spacer(minLength: 0)
                    }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
        }.buttonStyle(RowPressStyle())
        .accessibilityLabel("Job: \(title), \(incomplete ? "partial" : "\(count)")")
        .accessibilityHint("Opens the job")
        .accessibilityIdentifier("customer-records-job-\(jobID)")
    }

    private func moneyLink(_ row: CustomerMoneyRow) -> some View {
        Button { openedRoute = row.route } label: {
            DocumentListRowContent(status: row.status, title: row.title, subtitle: row.reference,
                                   meta: row.meta, amount: row.amount, amountNote: row.amountNote)
                .environment(\.paperRowInset, 0)
        }
        .buttonStyle(RowPressStyle())
        .accessibilityIdentifier("customer-\(row.kind)-\(row.id)")
    }
}

/// Display-only facts from one document. The invoice total is not its balance, and alternative
/// estimate options are never added together into a made-up package price.
struct CustomerMoneyRow: Identifiable {
    let id: String
    let kind: String
    let route: PaperRoute
    let title: String
    let reference: String
    let status: DocumentStatus
    let meta: String?
    let amount: String?
    let amountNote: String?

    static func estimate(_ estimate: EstimateRecord) -> Self {
        let options = estimate.options?.count ?? 0
        let amounts = CustomerDocumentAmounts(lines: estimate.lines, currency: "USD")
        let total = options == 0 && !estimate.lines.isEmpty ? amounts?.total : nil
        return Self(id: estimate.id, kind: "estimate", route: .estimate(estimate.id),
                    title: estimate.title.isEmpty ? "Estimate" : estimate.title,
                    reference: "EST-\(estimate.id.suffix(4).uppercased())",
                    status: DocumentStatus(estimateStatus: estimate.status),
                    meta: options > 0 ? "\(options) option\(options == 1 ? "" : "s")" : nil,
                    amount: total.map { money($0, currency: "USD") },
                    amountNote: total != nil ? "Last known total" : nil)
    }

    static func invoice(_ invoice: InvoiceRecord) -> Self {
        let isVoid = invoice.status == "void" || invoice.status == "voided"
        let amounts = invoice.currency == "USD"
            ? CustomerDocumentAmounts(lines: invoice.lines, currency: invoice.currency, amountPaid: invoice.amountPaid) : nil
        let isOpen = ["issued", "sent", "open"].contains(invoice.status)
        let baseStatus: DocumentStatus
        if isOpen && (amounts == nil || amounts?.due == 0) {
            // Do not infer a settled invoice from line arithmetic without payment reconciliation.
            baseStatus = DocumentStatus(tone: .scheduled, word: invoice.status.statusLabel)
        } else {
            baseStatus = DocumentStatus(invoiceStatus: invoice.status, amountPaid: invoice.amountPaid,
                                        balance: amounts?.due)
        }
        let status = DocumentStatus(tone: baseStatus.tone, word: "Last known: \(baseStatus.word)")
        let total = isVoid ? nil : amounts?.total
        let paid = !isVoid && invoice.status != "draft" && amounts != nil && invoice.amountPaid > 0
            ? "Last known paid \(money(invoice.amountPaid, currency: invoice.currency))" : nil
        return Self(id: invoice.id, kind: "invoice", route: .invoice(invoice.id), title: "Invoice",
                    reference: "INV-\(invoice.id.suffix(4).uppercased())", status: status, meta: paid,
                    amount: total.map { money($0, currency: invoice.currency) },
                    amountNote: total != nil ? "Last known total" : nil)
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
        .background(Theme.canvas)
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

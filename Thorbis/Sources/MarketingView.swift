import SwiftUI

// Marketing (Paper 92A): the place header, the reviews card, then the review request, lead
// source and campaign rows. Paper draws a star rating and a feed of reviews; the app has no
// review feed, so the card holds the company's own review link with a code to scan instead.
// 92D "Lead sources" counts the customers already on file by their "How they found us" answer.
// 92C "Campaign" schedules a send the server cannot do, so campaigns are notes kept on this phone.

@MainActor
final class MarketingModel: ObservableObject {
    enum ReviewState: Equatable {
        case loading
        case ready
        /// This person's role may not read the company profile.
        case noAccess
        case failed(String)
    }

    @Published private(set) var revision = 0
    @Published private(set) var storeError: String?
    private(set) var organizationID: String?
    private var storage: MarketingRecords?

    @Published private(set) var entries: [LeadSourceEntry] = []
    @Published private(set) var leadsLoaded = false
    @Published private(set) var leadsError: String?

    @Published private(set) var reviewLink: String?
    @Published private(set) var reviewRequestsOn: Bool?
    @Published private(set) var reviewState = ReviewState.loading

    var isBound: Bool { storage != nil }
    var campaigns: [MarketingCampaignNote] { MarketingCampaigns.sorted(storage?.campaigns ?? []) }

    func bind(organizationID: String?) {
        guard let organizationID else {
            storage = nil; self.organizationID = nil; storeError = nil; revision += 1
            return
        }
        guard self.organizationID != organizationID || storage == nil else { return }
        storage = nil
        self.organizationID = organizationID
        entries = []
        leadsLoaded = false
        leadsError = nil
        reviewLink = nil
        reviewRequestsOn = nil
        reviewState = .loading
        do {
            storage = try MarketingRecords(organizationID: organizationID)
            storeError = nil
        } catch {
            storeError = "Marketing could not open what is saved on this phone. \(error.localizedDescription)"
        }
        revision += 1
    }

    func save(_ note: MarketingCampaignNote) throws {
        guard let storage else { throw Problem(title: "Marketing is not open on this phone", status: nil, detail: nil) }
        try storage.save(note)
        revision += 1
    }

    func removeCampaign(_ id: String) throws {
        guard let storage else { throw Problem(title: "Marketing is not open on this phone", status: nil, detail: nil) }
        try storage.removeCampaign(id)
        revision += 1
    }

    /// The customers on file (archived ones left out) as the tally reads them.
    func loadLeads(api: APIClient, session: SessionController) async {
        guard session.can("customer.view", feature: "core_crm") else {
            leadsError = "Lead sources need access to customers. Ask an owner for it."
            leadsLoaded = true
            return
        }
        let generation = session.generation
        do {
            let customers = try await api.fieldCustomers()
            guard session.generation == generation, !Task.isCancelled else { return }
            entries = customers.map { LeadSourceEntry(source: $0.referralSource, createdAt: JobFiltering.date($0.createdAt)) }
            leadsError = nil
            leadsLoaded = true
        } catch is CancellationError {
            return
        } catch {
            guard session.generation == generation else { return }
            // What loaded before stays on screen; only a first load with nothing says it failed.
            leadsError = entries.isEmpty ? "Customers did not load, so there is nothing to count yet." : nil
            leadsLoaded = true
        }
    }

    /// The company's review link and whether review requests are on, from the company profile.
    func loadReview(api: APIClient, session: SessionController) async {
        guard let organizationID else { return }
        let generation = session.generation
        do {
            let profile = try await api.organizationProfile()
            guard session.generation == generation, !Task.isCancelled else { return }
            guard profile.organizationId.lowercased() == organizationID.lowercased() else {
                reviewState = .failed("The open company changed. Pull down to load it again.")
                return
            }
            let link = profile.value("review_link").flatMap { ReviewLink.validated($0) }
            reviewLink = link
            reviewRequestsOn = profile.value("review_requests") != "off"
            reviewState = .ready
        } catch is CancellationError {
            return
        } catch let problem as Problem where problem.status == 403 {
            guard session.generation == generation else { return }
            reviewState = .noAccess
        } catch {
            guard session.generation == generation else { return }
            if reviewLink == nil { reviewState = .failed("Your review link did not load.") }
        }
    }
}

private struct MarketingCampaignEditing: Identifiable {
    let id = UUID()
    let record: MarketingCampaignNote?
}

struct MarketingView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @StateObject private var model = MarketingModel()
    @State private var editor: MarketingCampaignEditing?
    @State private var showLeads = false
    #if DEBUG
    @State private var previewSettingsPage: String?
    #endif
    @State private var showReviewSettings = false
    @State private var actionError: String?
    @State private var copied = false
    @State private var code: CGImage?

    init() {}

    private var organizationID: String? { session.activeOrganization?.id }
    private var canEditCompany: Bool { session.can("organization.settings.edit") }

    var body: some View {
        let campaigns = model.campaigns
        let tally = LeadSourceTally.make(model.entries)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PaperHeader(title: "Marketing", subtitle: "Reviews, reminders and campaigns")
                VStack(alignment: .leading, spacing: 16) {
                    if let error = actionError ?? model.storeError {
                        Text(error).font(Theme.font(15)).foregroundStyle(Theme.destructive)
                            .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
                    }
                    reviewCard
                    // Paper 92A: one card of rows: the review request, each campaign, where leads come from.
                    PaperRowsCard {
                        reviewRequestsRow
                        ForEach(campaigns) { note in
                            WellDivider(leading: 16)
                            campaignRow(note)
                        }
                        WellDivider(leading: 16)
                        leadSourcesRow(tally)
                    }
                    .padding(.horizontal, -PaperCardMetrics.margin)
                    .id(model.revision)
                    PlacePhoneLine(text: campaigns.isEmpty
                                   ? "Add a campaign note with +. Notes are kept on this phone"
                                   : "Campaign notes are kept on this phone \u{00B7} nothing is sent")
                        .padding(.horizontal, -PaperCardMetrics.margin)
                }
                .paperCardMargin().padding(.top, 14).padding(.bottom, 24)
            }
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("marketing-root")
        .placeBarCreate("Add campaign note", shows: model.isBound) { editor = MarketingCampaignEditing(record: nil) }
        .refreshable { await load() }
        .task(id: organizationID ?? "") {
            editor = nil
            actionError = nil
            copied = false
            model.bind(organizationID: organizationID)
            #if DEBUG
            if PaperPreview.enabled {
                switch PaperPreview.screen {
                case "marketing-campaign": editor = MarketingCampaignEditing(record: model.campaigns.first)
                case "marketing-sources": showLeads = true
                case "checklist-templates", "checklist-template", "customer-display", "workflows": previewSettingsPage = PaperPreview.screen
                default: break
                }
            }
            #endif
            await load()
        }
        .task(id: model.reviewLink ?? "") {
            code = model.reviewLink.flatMap { URL(string: $0) }.flatMap { PaymentLinkQRCode.image(for: $0) }
            copied = false
        }
        .onChange(of: showReviewSettings) { _, showing in
            // Back from Review requests: the link may have changed there.
            if !showing { Task { await model.loadReview(api: api, session: session) } }
        }
        #if DEBUG
        // Design preview only: the three Business settings pages are pushed from plain links
        // there, so the preview opens them from this owner place to screenshot them directly.
        .thorbisDestination(item: $previewSettingsPage) { name in
            switch name {
            case "customer-display": CustomerDisplaySettingsView()
            case "workflows": WorkflowsView()
            default: ChecklistTemplatesView()
            }
        }
        #endif
        .thorbisDestination(isPresented: $showLeads) { MarketingLeadSourcesView(model: model) }
        .thorbisDestination(isPresented: $showReviewSettings) { ReviewRequestsView() }
        .sheet(item: $editor) { editing in SheetSurface {
            MarketingCampaignEditor(record: editing.record, onSave: { saved in
                try model.save(saved)
                actionError = nil
            }, onRemove: editing.record.map { note in { try model.removeCampaign(note.id) } })
        } }
    }

    private func load() async {
        await model.loadReview(api: api, session: session)
        await model.loadLeads(api: api, session: session)
    }

    // MARK: Reviews

    /// Paper 92A's reviews card (18 inside, 10 between). No rating and no review feed: the app
    /// cannot read reviews, so the card is the link customers leave one at.
    private var reviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your review link").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                .accessibilityAddTraits(.isHeader)
            switch model.reviewState {
            case .loading:
                SkeletonRows(count: 1, leading: false, inset: 0)
            case .noAccess:
                Text("Your role can\u{2019}t see the company\u{2019}s review link. Ask an owner to share it with you.")
                    .font(Theme.font(15)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            case .failed(let message):
                ErrorBanner(message: message,
                            action: .init(title: "Try again", run: { await model.loadReview(api: api, session: session) }),
                            outer: 0)
            case .ready:
                if let link = model.reviewLink, let url = URL(string: link) {
                    reviewLinkBody(link: link, url: url)
                } else {
                    Text("No review link yet").font(Theme.font(20, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(canEditCompany
                         ? "Add the link where customers leave you a review. Then show it here as a code to scan."
                         : "An owner adds the company\u{2019}s review link in Settings, under Review requests.")
                        .font(Theme.font(15)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if canEditCompany {
                        Button { showReviewSettings = true } label: {
                            Text("Add review link").font(Theme.font(16, weight: .semibold)).foregroundStyle(Theme.foreground)
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(Theme.fill, in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(PressStyle())
                        .padding(.top, 4)
                        .accessibilityIdentifier("marketing-add-review-link")
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityIdentifier("marketing-review-card")
    }

    @ViewBuilder private func reviewLinkBody(link: String, url: URL) -> some View {
        Text(link).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .accessibilityLabel("Review link, \(link)")
        if let code {
            Image(uiImage: UIImage(cgImage: code))
                .interpolation(.none).resizable().scaledToFit()
                .frame(maxWidth: 204)
                .padding(18)
                .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
                .accessibilityLabel("Review link QR code")
                .accessibilityHint("The customer scans this with their phone camera")
                .accessibilityIdentifier("marketing-review-qr")
            Text("A customer scans this with their phone camera to leave a review.")
                .font(Theme.font(14)).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { reviewButtons(link: link, url: url) }
            VStack(spacing: 8) { reviewButtons(link: link, url: url) }
        }
        .padding(.top, 4)
    }

    @ViewBuilder private func reviewButtons(link: String, url: URL) -> some View {
        Button {
            UIPasteboard.general.string = link
            copied = true
        } label: {
            pill(copied ? "Link copied" : "Copy link", symbol: copied ? "checkmark" : "doc.on.doc")
        }
        .buttonStyle(PressStyle())
        .accessibilityIdentifier("marketing-review-copy")
        ShareLink(item: url) { pill("Share", symbol: "square.and.arrow.up") }
            .buttonStyle(PressStyle())
            .accessibilityIdentifier("marketing-review-share")
    }

    private func pill(_ title: String, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 14, weight: .medium)).accessibilityHidden(true)
            Text(title).font(Theme.font(16, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(Theme.foreground)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(Theme.fill, in: Capsule())
        .contentShape(Capsule())
    }

    /// Paper 92A "Ask for a review after payment". The switch itself lives in Settings › Review
    /// requests, with the rules the server follows; this row says where it stands and opens it.
    @ViewBuilder private var reviewRequestsRow: some View {
        let state: String? = model.reviewRequestsOn.map { on in
            model.reviewLink == nil ? "No link" : (on ? "On" : "Off")
        }
        let row = OnPhoneRow(title: "Ask for a review after payment",
                           subtitle: "One text after an invoice is paid in full") {
            HStack(spacing: 6) {
                if let state {
                    Text(state).font(Theme.font(15)).foregroundStyle(Theme.muted).fixedSize()
                }
                if canEditCompany { PlaceChevron() }
            }
        }
        if canEditCompany {
            Button { showReviewSettings = true } label: { row }
                .buttonStyle(RowPressStyle())
                .accessibilityElement(children: .combine)
                .accessibilityHint("Opens Review requests")
                .accessibilityIdentifier("marketing-review-requests")
        } else {
            row.accessibilityElement(children: .combine)
        }
    }

    // MARK: Lead sources

    private func leadSourcesRow(_ tally: LeadSourceTally) -> some View {
        let line: String
        if let error = model.leadsError { line = error }
        else if !model.leadsLoaded { line = "Counting your customers\u{2026}" }
        else if tally.total == 0 { line = "No customers on file yet" }
        else if tally.recorded == 0 { line = "No customer has a source written down yet" }
        else { line = tally.summary }
        return Button { showLeads = true } label: {
            OnPhoneRow(title: "Where leads come from", subtitle: line) { PlaceChevron() }
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens lead sources")
        .accessibilityIdentifier("marketing-lead-sources")
    }

    // MARK: Campaign notes

    /// Paper 92A: the campaign's name over "Campaign · Sep 1 · …" and a chevron; it opens the note.
    private func campaignRow(_ note: MarketingCampaignNote) -> some View {
        let line = [note.channel, MarketingCampaigns.dates(note) ?? "", note.costCents.map { money($0, currency: "USD") } ?? ""]
            .filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
        return Button { editor = MarketingCampaignEditing(record: note) } label: {
            OnPhoneRow(title: note.name, subtitle: line) { PlaceChevron() }
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the note to edit or remove")
    }
}

/// job's money back to how the customer found the business.
struct MarketingLeadSourcesView: View {
    @ObservedObject var model: MarketingModel
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @State private var period = LeadSourcePeriod.days90

    private static let colors: [Color] = [Theme.brand, Theme.markForest, Theme.markPumpkin, Theme.markOlive, Theme.markBurnt]

    private func color(_ index: Int, of count: Int) -> Color {
        // "Other", when there is one, is the last row and stays grey.
        index < Self.colors.count ? Self.colors[index] : Theme.markGrey
    }

    private func subtitle(_ tally: LeadSourceTally) -> String {
        guard model.leadsLoaded else { return "Counting your customers\u{2026}" }
        let customers = tally.total == 1 ? "1 customer added" : "\(tally.total.formatted()) customers added"
        return "\(period.title) \u{00B7} \(customers)"
    }

    var body: some View {
        let tally = LeadSourceTally.make(model.entries, since: period.start(now: Date()))
        let rows = tally.grouped
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Paper 92D: the back circle rides the bar; under it the title in 28 Bold over the count.
                VStack(alignment: .leading, spacing: 2) {
                    Text("Where leads come from").font(Theme.heading()).tracking(-0.56)
                        .accessibilityAddTraits(.isHeader)
                    Text(subtitle(tally)).font(Theme.font(15)).foregroundStyle(Theme.muted)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.gutter).padding(.top, 14)
                VStack(alignment: .leading, spacing: 14) {
                    PlaceSegments(options: LeadSourcePeriod.allCases.map { (value: $0, label: $0.label) }, selection: $period, pill: true)
                        .accessibilityIdentifier("marketing-leads-period")
                    if let error = model.leadsError {
                        ErrorBanner(message: error,
                                    action: .init(title: "Try again", run: { await model.loadLeads(api: api, session: session) }),
                                    outer: 0)
                    } else if !model.leadsLoaded {
                        SkeletonRows(count: 3, leading: false, inset: 0)
                    } else if tally.total == 0 {
                        PaperEmptyState(symbol: "person.2", title: "No customers added in this range",
                                        message: "Choose a longer range, or add a customer and say how they found you.")
                    } else if tally.recorded == 0 {
                        PaperEmptyState(symbol: "questionmark.circle", title: "No sources written down",
                                        message: "Open a customer, choose Edit, and fill in How they found us. It is counted here.")
                    } else {
                        bar(rows)
                        PaperCard {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, source in
                                if index > 0 { WellDivider() }
                                sourceRow(source, color: color(index, of: rows.count))
                            }
                        }
                    }
                    if model.leadsLoaded && model.leadsError == nil && tally.unrecorded > 0 && tally.recorded > 0 {
                        note(tally.unrecorded == 1
                             ? "1 customer in this range has no source yet. Add it on the customer under How they found us."
                             : "\(tally.unrecorded.formatted()) customers in this range have no source yet. Add it on each customer under How they found us.")
                    }
                    if model.leadsLoaded && model.leadsError == nil {
                        Text("Counts every customer on file who isn\u{2019}t archived, by the range they were added in. Percentages are of customers with a source.")
                            .font(Theme.font(13)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }
                }
                .paperCardMargin().padding(.top, 16).padding(.bottom, 24)
            }
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.loadLeads(api: api, session: session) }
        .accessibilityIdentifier("marketing-leads-root")
    }

    /// Paper 92D's bar: 14 tall, radius 8, 3 between segments, each as wide as its share.
    private func bar(_ rows: [LeadSourceCount]) -> some View {
        GeometryReader { proxy in
            let gaps = CGFloat(max(rows.count - 1, 0)) * 3
            let width = max(proxy.size.width - gaps, 0)
            HStack(spacing: 3) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, source in
                    Rectangle().fill(color(index, of: rows.count))
                        .frame(width: max(width * source.share, 2))
                }
            }
            .frame(width: proxy.size.width, alignment: .leading)
        }
        .frame(height: 14)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
    }

    /// The source in 16 Semibold with its share, then how many customers, inset under the name.
    private func sourceRow(_ source: LeadSourceCount, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(color)
                    .frame(width: 10, height: 10).accessibilityHidden(true)
                Text(source.name).font(Theme.font(16, weight: .semibold)).foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(source.percent)%").font(Theme.font(16, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(Theme.foreground).fixedSize()
            }
            Text(source.count == 1 ? "1 customer" : "\(source.count.formatted()) customers")
                .font(Theme.font(14)).monospacedDigit().foregroundStyle(Theme.muted)
                .padding(.leading, 18)
        }
        .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// A plain note in place of Paper's AI line: the app works nothing out here beyond the count.
    private func note(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "info.circle").font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.muted).accessibilityHidden(true)
            Text(text).font(Theme.font(14)).foregroundStyle(Theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Campaign note editor

/// Paper 92C's sheet, as a note: the campaign's name, how it went out, when, what it cost and
/// what to remember. There is no audience and no Schedule: the app does not send campaigns.
private struct MarketingCampaignEditor: View {
    let record: MarketingCampaignNote?
    let onSave: (MarketingCampaignNote) throws -> Void
    /// Removes the note being edited; nil for a new one.
    var onRemove: (() throws -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var channel: String
    @State private var starts: Date?
    @State private var ends: Date?
    @State private var cost: String
    @State private var note: String
    @State private var missingName = false
    @State private var badCost = false
    @State private var badDates = false
    @State private var error: String?

    init(record: MarketingCampaignNote?, onSave: @escaping (MarketingCampaignNote) throws -> Void,
         onRemove: (() throws -> Void)? = nil) {
        self.onRemove = onRemove
        self.record = record
        self.onSave = onSave
        _name = State(initialValue: record?.name ?? "")
        _channel = State(initialValue: record?.channel ?? MarketingCampaignNote.channels[0])
        _starts = State(initialValue: LearnDay.date(from: record?.startsOn))
        _ends = State(initialValue: LearnDay.date(from: record?.endsOn))
        _cost = State(initialValue: MarketingCampaigns.text(cents: record?.costCents))
        _note = State(initialValue: record?.note ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            LearnEditorHeader(title: record == nil ? "Add campaign note" : "Edit campaign note",
                              saveIdentifier: "marketing-campaign-save", onCancel: { dismiss() }, onSave: save)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let error {
                        Text(error).font(Theme.font(15)).foregroundStyle(Theme.destructive)
                            .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
                    }
                    LearnCard {
                        LearnField(label: "Name", text: Binding(get: { name }, set: { name = $0; missingName = false }),
                                   prompt: "Fall tune-up reminder",
                                   problem: missingName ? "Add the name to save." : nil,
                                   identifier: "marketing-campaign-name")
                        WellDivider()
                        ThorbisSelect(options: MarketingCampaignNote.channels.map { (value: $0, label: $0) },
                                      selection: $channel, label: "Channel")
                            .padding(.horizontal, 16).frame(minHeight: 56)
                    }
                    LearnCard {
                        LearnDateRow(title: "Starts", date: Binding(get: { starts }, set: { starts = $0; badDates = false }))
                        WellDivider()
                        LearnDateRow(title: "Ends", date: Binding(get: { ends }, set: { ends = $0; badDates = false }))
                        if badDates {
                            FieldProblem(message: "The end date is before the start date.")
                                .padding(.horizontal, 16).padding(.bottom, 12)
                        }
                    }
                    LearnCard {
                        LearnField(label: "Cost", text: Binding(get: { cost }, set: { cost = $0; badCost = false }),
                                   prompt: "250.00",
                                   problem: badCost ? "Enter the cost as dollars and cents, like 250.00, or leave it empty." : nil,
                                   keyboard: .decimalPad)
                        WellDivider()
                        LearnField(label: "Note", text: $note, prompt: "Who it went to, what it said, how it did", multiline: true)
                    }
                    if let onRemove {
                        Button {
                            do { try onRemove(); dismiss() }
                            catch { self.error = error.localizedDescription }
                        } label: {
                            Text("Remove campaign note").font(Theme.font(16, weight: .semibold)).foregroundStyle(Theme.destructive)
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(Theme.card, in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityIdentifier("marketing-campaign-remove")
                    }
                    LearnFootnote(text: "Saved on this phone only. Thorbis does not send this campaign or count its results.")
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
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let typedCost = cost.trimmingCharacters(in: .whitespacesAndNewlines)
        let cents = MarketingCampaigns.cents(from: typedCost)
        missingName = title.isEmpty
        badCost = !typedCost.isEmpty && cents == nil
        let first = starts.map { LearnDay.string(from: $0) }
        let last = ends.map { LearnDay.string(from: $0) }
        if let first, let last { badDates = last < first } else { badDates = false }
        guard !missingName, !badCost, !badDates else { return }
        let words = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let saved = MarketingCampaignNote(id: record?.id ?? UUID().uuidString, name: title, channel: channel,
                                          startsOn: first, endsOn: last, costCents: cents,
                                          note: words.isEmpty ? nil : words,
                                          createdAt: record?.createdAt ?? ISO8601DateFormatter().string(from: Date()))
        do { try onSave(saved); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

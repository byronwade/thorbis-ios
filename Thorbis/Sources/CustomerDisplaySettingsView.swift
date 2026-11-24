import SwiftUI
import UIKit

// Business settings › What customers see (Paper 95).
//
// Paper 95 draws switches for what an estimate shows (hours, rates, quantities, materials, item
// photos). The server keeps those in commercial document templates, which can be written but not
// read back (`/v1/organization/commercial-document-templates` has no GET), so a switch here could
// not show its own state. This page gathers what the app can read and change today: the company
// name, logo and contact details, review requests, job notices and card payments. Each row opens
// the screen that edits it, and the preview shows the company as it is saved now.

/// What the page says about each customer-facing setting, worked out from what the server holds.
struct CustomerDisplayFacts: Equatable {
    let name: String
    /// Phone, email and website on one line, in that order; nil when none is saved.
    let contactLine: String?
    let address: String?
    let reviewSummary: String

    init(profile: OrganizationProfile?, organizationName: String?) {
        func saved(_ key: String) -> String? {
            let text = profile?.value(key)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? nil : text
        }
        let fallback = organizationName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        name = saved("legal_name") ?? (fallback.isEmpty ? "Your company" : fallback)
        let contact = ["primary_phone", "primary_email", "website"].compactMap(saved)
        contactLine = contact.isEmpty ? nil : contact.joined(separator: " \u{00B7} ")
        address = saved("business_address")
        reviewSummary = Self.reviews(profile: profile)
    }

    /// The same rule the Review requests screen reads: on unless switched off, and it only sends
    /// once a link the server accepts is saved.
    static func reviews(profile: OrganizationProfile?) -> String {
        guard let profile else { return "One text after an invoice is paid" }
        if profile.value("review_requests") == "off" { return "Off" }
        let link = profile.value("review_link").flatMap { ReviewLink.validated($0) }
        return link == nil ? "On once you add your review link" : "On \u{00B7} one text after an invoice is paid"
    }

    static func payments(_ readiness: MerchantReadiness?) -> String {
        readiness?.headline ?? "Card payments from your customers"
    }
}

/// Business settings › What customers see.
struct CustomerDisplaySettingsView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @State private var profile: OrganizationProfile?
    @State private var logo: UIImage?
    @State private var readiness: MerchantReadiness?
    @State private var loaded = false
    @State private var error: String?

    private var canEdit: Bool { session.can("organization.settings.edit") }
    private var hasNotices: Bool { MenuItem.notices.permitted(session) }
    private var facts: CustomerDisplayFacts {
        CustomerDisplayFacts(profile: profile, organizationName: session.activeOrganization?.name)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Paper 95: the 34 Bold title, one muted line, the settings card, then the preview.
                PaperHeader(title: "What customers see", subtitle: "Your name, logo and the messages customers get")
                    .environment(\.paperMenuButton, false)
                    .environment(\.paperDrawer, nil)
                VStack(alignment: .leading, spacing: 20) {
                    if let error {
                        ErrorBanner(message: error) { await load() }.padding(.horizontal, -PaperCardMetrics.margin)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        PaperCard { rows }
                        note("Each row opens the screen where it is changed.")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        PaperSection("Preview") { preview }
                        note("Your company as it is saved now. This is the name, logo and contact customers get with estimates, invoices and messages.")
                    }
                }
                .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 10).padding(.bottom, 44)
            }
            .frame(maxWidth: 600, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.canvas)
        .foregroundStyle(Theme.foreground)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("customer-display-root")
        .refreshable { await load() }
        // Runs again on the way back from a row's screen, so the page shows what was just saved.
        .onAppear { Task { await load() } }
    }

    @ViewBuilder private var rows: some View {
        if canEdit {
            NavigationLink { CompanyDetailsView().thorbisBackButton() } label: {
                row("building.2", "Company name and logo", facts.name)
            }
            .buttonStyle(RowPressStyle())
            .accessibilityIdentifier("customer-display-company")
            divider
            NavigationLink { ReviewRequestsView().thorbisBackButton() } label: {
                row("star.bubble", "Review requests", facts.reviewSummary)
            }
            .buttonStyle(RowPressStyle())
            .accessibilityIdentifier("customer-display-reviews")
        }
        if hasNotices {
            if canEdit { divider }
            NavigationLink { NoticeSettingsView().thorbisBackButton() } label: {
                row("bell", "Job notices", "Who is told when a job is booked or changed, and what was sent")
            }
            .buttonStyle(RowPressStyle())
            .accessibilityIdentifier("customer-display-notices")
        }
        if canEdit {
            divider
            NavigationLink { PaymentsSetupView().thorbisBackButton() } label: {
                row("creditcard", "Card payments", CustomerDisplayFacts.payments(readiness))
            }
            .buttonStyle(RowPressStyle())
            .accessibilityIdentifier("customer-display-payments")
        }
        if !canEdit && !hasNotices {
            Text("Ask an owner for the company settings permission to change what customers see.")
                .font(Theme.font(15)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(PaperCardMetrics.inset)
        }
    }

    private var divider: some View { WellDivider(leading: PaperCardMetrics.inset + 38) }

    private func row(_ symbol: String, _ title: String, _ subtitle: String) -> some View {
        PaperListRow(leading: .icon(symbol), title: title, subtitle: subtitle, subtitleLines: 2) {
            PaperChevron()
                .foregroundStyle(Theme.muted).accessibilityHidden(true)
        }
    }

    /// The company as a customer reads it, in the customer screens' own type.
    @ViewBuilder private var preview: some View {
        if !loaded && error == nil {
            SkeletonRows(count: 2, leading: true, inset: 0).padding(.vertical, 8)
        } else {
            let facts = self.facts
            HStack(alignment: .top, spacing: 14) {
                if let logo {
                    let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
                    Image(uiImage: logo).resizable().scaledToFit()
                        .padding(4)
                        .frame(width: 56, height: 56)
                        .background(Theme.fill, in: shape)
                        .clipShape(shape)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(facts.name).font(Theme.customerFont(22, weight: .bold)).tracking(-0.4)
                        .fixedSize(horizontal: false, vertical: true)
                    if let contact = facts.contactLine {
                        Text(contact).font(Theme.customerFont(15)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let address = facts.address {
                        Text(address).font(Theme.customerFont(15)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if logo == nil {
                        Text("No logo yet").font(Theme.font(13)).foregroundStyle(Theme.muted).padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(PaperCardMetrics.inset)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("customer-display-preview")
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(Theme.font(13)).foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    private func load() async {
        let generation = session.generation
        guard canEdit else { loaded = true; return }
        do {
            let fresh = try await api.organizationProfile()
            guard session.generation == generation else { return }
            profile = fresh
            error = nil
        } catch is CancellationError {
            return
        } catch {
            guard session.generation == generation else { return }
            if profile == nil { self.error = error.plainMessage(subject: "company details") }
        }
        loaded = true
        // The logo and payment state are extras: a failed read leaves the row's plain words.
        if let data = try? await api.logoData(), session.generation == generation { logo = UIImage(data: data) }
        if let state = try? await api.merchantReadiness(), session.generation == generation { readiness = state }
    }
}

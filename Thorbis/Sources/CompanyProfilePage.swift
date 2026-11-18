import SwiftUI

/// Paper 61B "Company profile": the logo card, then what the company is on rows that each show
/// their answer and open the form on that field, and "Business contact info" under it. The rows
/// are the server's own company facts; a fact Paper names that the server doesn't keep (licence
/// number) is not drawn. Setup keeps the plain form (`CompanyDetailsForm`).
struct CompanyDetailsView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @StateObject private var model = CompanyDetailsModel()
    @State private var editing: String?

    private var canEdit: Bool { session.can("organization.settings.edit") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TeamDetailTitle(title: "Company profile", subtitle: subtitle)
                if let profile = model.profile {
                    page(profile)
                } else if let error = model.loadError {
                    ErrorBanner(message: error, symbol: error.hasPrefix("Company details need") ? "lock" : "exclamationmark.triangle",
                                tint: error.hasPrefix("Company details need") ? Theme.muted : Theme.warning,
                                action: error.hasPrefix("Company details need") ? nil
                                    : .init(title: String(localized: "Try again")) { await model.load(api: api) })
                        .padding(.top, 12)
                } else {
                    VStack(spacing: 12) { SkeletonSection(rows: 3); SkeletonSection(rows: 2) }
                        .paperCardMargin().padding(.top, 16)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Loading company details")
                }
            }
            .padding(.bottom, 32)
            .frame(maxWidth: 600, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .thorbisDestination(item: $editing) { key in
            CompanyDetailsForm(onSaved: {
                editing = nil
                Task { await model.load(api: api) }
            }, focus: key)
        }
        .task { await model.load(api: api) }
    }

    private var subtitle: String {
        guard let profile = model.profile, !profile.coreReady else { return "What customers see on estimates and texts" }
        return profile.missingCore.count == 1 ? "1 detail is still needed to finish setup"
            : "\(profile.missingCore.count) details are still needed to finish setup"
    }

    private static let contactKeys: Set<String> = ["primary_phone", "primary_email", "website", "email_sender_address", "email_sender_name"]

    @ViewBuilder private func page(_ profile: OrganizationProfile) -> some View {
        let entries = profile.catalog.filter {
            !OperatingFacts.keys.contains($0.factKey) && $0.factKey != "logo" && CompanyFact.group($0) != 3
        }
        let contact = entries.filter { Self.contactKeys.contains($0.factKey) }
        let legal = entries.filter { CompanyFact.group($0) == 2 && !Self.contactKeys.contains($0.factKey) }
        let business = entries.filter { !Self.contactKeys.contains($0.factKey) && CompanyFact.group($0) != 2 }
        VStack(alignment: .leading, spacing: 12) {
            if !canEdit {
                ErrorBanner(message: "Ask an owner for access to edit company details.", symbol: "lock", tint: Theme.muted)
                    .padding(.horizontal, -PaperCardMetrics.margin)
            }
            if profile.catalog.contains(where: { $0.factKey == "logo" }) {
                CompanyLogoPicker(profile: (answer("legal_name") ?? session.activeOrganization?.name ?? "Your company", answer("industry")),
                                  canEdit: canEdit)
            }
            TeamCard {
                ForEach(business, id: \.factKey) { entry in
                    if entry.factKey != business.first?.factKey { WellDivider(leading: 0) }
                    row(entry)
                }
                if OperatingFacts.offered(profile) {
                    if !business.isEmpty { WellDivider(leading: 0) }
                    NavigationLink { OperatingDetailsView().thorbisBackButton() } label: { line("Hours, tax and terms", value: nil) }
                        .buttonStyle(RowPressStyle())
                }
            }
            if !contact.isEmpty {
                label("Business contact info")
                TeamCard {
                    ForEach(contact, id: \.factKey) { entry in
                        if entry.factKey != contact.first?.factKey { WellDivider(leading: 0) }
                        row(entry)
                    }
                }
            }
            if !legal.isEmpty {
                label("Legal details")
                TeamCard {
                    ForEach(legal, id: \.factKey) { entry in
                        if entry.factKey != legal.first?.factKey { WellDivider(leading: 0) }
                        row(entry)
                    }
                }
            }
            TeamCard {
                NavigationLink { CompanyFeaturesView().thorbisBackButton() } label: { line("Plan and features", value: nil) }
                    .buttonStyle(RowPressStyle())
            }
            .padding(.top, 10)
        }
        .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 16)
    }

    private func answer(_ key: String) -> String? {
        let text = (model.drafts[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private func label(_ text: String) -> some View {
        Text(text).font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 4).padding(.top, 10).padding(.bottom, -4)
    }

    @ViewBuilder private func row(_ entry: OrganizationProfile.Entry) -> some View {
        let title = CompanyFact.label(entry.factKey, fallback: entry.label)
        let needed = entry.required && !entry.confirmed
        let value = answer(entry.factKey)
        if canEdit {
            Button { editing = entry.factKey } label: { line(title, value: value ?? (needed ? "Needed" : "Add"), warns: value == nil && needed) }
                .buttonStyle(RowPressStyle())
                .accessibilityIdentifier("company-profile-\(entry.factKey)")
        } else {
            line(title, value: value ?? "Not set", chevron: false)
        }
    }

    /// Paper 61B: the label in ink, its answer in the muted tone (both 16), and a 16pt chevron.
    private func line(_ title: String, value: String?, warns: Bool = false, chevron: Bool = true) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title).font(Theme.font(16)).foregroundStyle(Theme.foreground).fixedSize()
            Text(value ?? "").font(Theme.font(16)).foregroundStyle(warns ? Theme.warning : Theme.muted)
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .trailing)
            if chevron { PaperIcon(.chevronRight, size: 16, color: Theme.muted).accessibilityHidden(true) }
        }
        .padding(.horizontal, PaperCardMetrics.inset)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

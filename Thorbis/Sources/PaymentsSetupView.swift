import SafariServices
import SwiftUI

/// `GET /v1/organization/merchant-readiness` (organization MerchantReadiness). Provider-neutral:
/// no account id, KYC data or hosted URL ever appears here.
struct MerchantReadiness: Decodable, Equatable {
    struct Requirements: Decodable, Equatable {
        let eventuallyDueCount: Int
        let currentlyDueCount: Int
        let pastDueCount: Int
        var total: Int { eventuallyDueCount + currentlyDueCount + pastDueCount }
    }

    let state: String
    let chargesReady: Bool
    let payoutsReady: Bool
    let actionRequired: Bool
    let requirements: Requirements

    /// The first question an owner has, answered in words.
    var headline: String {
        switch state {
        case "not_started": "Payments are not set up"
        case "onboarding_incomplete": "Setup is not finished"
        case "action_required": "Stripe needs something from you"
        case "under_review": "Stripe is reviewing your details"
        case "charges_ready": "You can take payments; payouts are not on yet"
        case "payouts_ready": "Payouts are on; payments are not yet"
        case "ready": "Payments and payouts are on"
        case "restricted": "Stripe has paused this account"
        case "rejected": "Stripe declined this account"
        case "disconnected": "Stripe is disconnected"
        default: "Payment status is unknown"
        }
    }

    var detail: String {
        switch state {
        case "not_started": "Connect a Stripe account so customers can pay invoices by card and your money is paid out to your bank."
        case "onboarding_incomplete": "Pick up where you left off. Stripe keeps what you already entered."
        case "action_required": "Card payments and payouts stay off until Stripe has what it asked for."
        case "under_review": "Nothing to do right now. This usually clears on its own; check back later."
        case "charges_ready": "Stripe still needs your bank details before it can pay you out."
        case "payouts_ready": "Stripe still needs details before customers can pay by card."
        case "ready": "Customers can pay by card, and Stripe pays you out to your bank."
        case "restricted", "rejected": "Open Stripe to see why and what you can do."
        case "disconnected": "Reconnect Stripe to take card payments again."
        default: "Pull down to check again."
        }
    }

    /// The hosted-onboarding button label, or nil when there is nothing for the owner to do.
    var actionTitle: String? {
        switch state {
        case "not_started": "Set up payments"
        case "onboarding_incomplete": "Continue setup"
        case "action_required", "restricted", "charges_ready", "payouts_ready": "Open Stripe"
        case "disconnected": "Reconnect Stripe"
        default: nil
        }
    }
}

/// The only response that carries a provider-hosted URL (HostedMerchantOnboardingLink).
struct HostedMerchantOnboardingLink: Decodable {
    let url: String
    let expiresAt: String

    /// Only an https Stripe page may open; anything else is refused rather than shown.
    var safeURL: URL? {
        guard let components = URLComponents(string: url), components.scheme == "https",
              let host = components.host?.lowercased(),
              host == "stripe.com" || host.hasSuffix(".stripe.com") else { return nil }
        return components.url
    }
}

extension APIClient {
    func merchantReadiness() async throws -> MerchantReadiness {
        try await send("GET", "/v1/organization/merchant-readiness")
    }

    func startMerchantOnboarding() async throws -> HostedMerchantOnboardingLink {
        try await send("POST", "/v1/organization/merchant-onboarding", body: Optional<String>.none)
    }

    /// Re-reads provider evidence after the hosted page closes.
    func reconcileMerchantOnboarding() async throws -> MerchantReadiness {
        try await send("GET", "/v1/organization/merchant-onboarding/return")
    }
}

/// Web Settings › Payments: Stripe readiness and the hosted onboarding handoff (BYR-414).
struct PaymentsSetupView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @State private var readiness: MerchantReadiness?
    @State private var hosted: URL?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("BUSINESS SETTINGS").font(Theme.monoFont(12, weight: .medium)).foregroundStyle(Theme.muted)
                    Text("Payments").font(Theme.font(26, weight: .semibold)).tracking(-0.39).accessibilityAddTraits(.isHeader)
                    Text("Card payments and payouts run through Stripe. Stripe holds your bank and identity details; Thorbis never sees them.")
                        .font(Theme.font(14)).foregroundStyle(Theme.muted).padding(.top, 4)
                }
                .padding(.bottom, 12)
                if let error { ErrorBanner(message: error).padding(.horizontal, -Theme.gutter) }
                if readiness == nil && error == nil { ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30) }
                if let readiness {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(readiness.headline).font(Theme.font(17, weight: .semibold))
                        Text(readiness.detail).font(Theme.font(14)).foregroundStyle(Theme.muted)
                    }
                    .padding(.vertical, 8)
                    PaperGroupHeader(title: "Status").padding(.top, 10)
                    statusRow("Card payments", on: readiness.chargesReady)
                    statusRow("Payouts to your bank", on: readiness.payoutsReady)
                    if readiness.requirements.total > 0 {
                        PaperGroupHeader(title: "Stripe is asking for").padding(.top, 10)
                        if readiness.requirements.pastDueCount > 0 { countRow("Past due", readiness.requirements.pastDueCount, urgent: true) }
                        if readiness.requirements.currentlyDueCount > 0 { countRow("Due now", readiness.requirements.currentlyDueCount, urgent: true) }
                        if readiness.requirements.eventuallyDueCount > 0 { countRow("Due later", readiness.requirements.eventuallyDueCount, urgent: false) }
                    }
                    if let title = readiness.actionTitle {
                        PrimaryButton(title: title, icon: "arrow.up.forward.square", busy: busy) { Task { await openStripe() } }
                            .padding(.top, 20)
                        Text("Opens Stripe in a secure browser. Tap Done when you finish to come back here.")
                            .font(Theme.font(12)).foregroundStyle(Theme.muted).padding(.top, 8)
                    }
                }
            }
            .padding(.horizontal, Theme.gutter).padding(.top, 4).padding(.bottom, 24)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .sheet(item: Binding(get: { hosted.map(HostedPage.init) }, set: { if $0 == nil { hosted = nil } }),
               onDismiss: { Task { await reconcile() } }) { page in
            SafariPage(url: page.url).ignoresSafeArea()
        }
    }

    private struct HostedPage: Identifiable { let url: URL; var id: String { url.absoluteString } }

    private func statusRow(_ title: String, on: Bool) -> some View {
        HStack {
            Text(title).font(Theme.font(15, weight: .medium))
            Spacer()
            Label(on ? "On" : "Off", systemImage: on ? "checkmark.circle.fill" : "circle")
                .font(Theme.font(14)).foregroundStyle(on ? Theme.brand : Theme.muted)
        }
        .frame(minHeight: 48)
        .accessibilityElement(children: .combine)
    }

    private func countRow(_ title: String, _ count: Int, urgent: Bool) -> some View {
        HStack {
            Text(title).font(Theme.font(15, weight: .medium))
            Spacer()
            Text(count == 1 ? "1 item" : "\(count) items").font(Theme.font(14))
                .foregroundStyle(urgent ? Theme.warning : Theme.muted)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        let generation = session.generation
        do {
            let value = try await api.merchantReadiness()
            guard session.generation == generation else { return }
            readiness = value
            error = nil
        } catch is CancellationError {} catch {
            guard session.generation == generation else { return }
            self.error = error.localizedDescription
        }
    }

    private func openStripe() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let link = try await api.startMerchantOnboarding()
            guard let url = link.safeURL else {
                error = "Stripe sent a link this app won't open. Try again from the web app."
                return
            }
            hosted = url
            error = nil
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }

    private func reconcile() async {
        let generation = session.generation
        do {
            let value = try await api.reconcileMerchantOnboarding()
            guard session.generation == generation else { return }
            readiness = value
            error = nil
        } catch is CancellationError {} catch {
            await load()
        }
    }
}

/// Stripe's hosted page in an in-app Safari view; it shares no cookies with the app.
private struct SafariPage: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .done
        return controller
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

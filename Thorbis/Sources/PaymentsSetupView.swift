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

/// `GET /v1/organization/money-availability` (organization MoneyAvailability, BYR-315).
/// The server writes every sentence; the app only lays them out.
struct MoneyAvailability: Decodable, Equatable {
    struct Balance: Decodable, Equatable, Identifiable {
        let currency: String
        let available: Int
        let pending: Int
        let explanation: String
        var id: String { currency }
    }
    struct Payout: Decodable, Equatable {
        let state: String
        let amount: Int
        let currency: String
        let arrivalDate: String
        let title: String
        let explanation: String
        let responsibleActor: String
    }
    struct Attention: Decodable, Equatable { let title: String; let explanation: String }
    let version: Int
    let asOf: String
    let balances: [Balance]
    let payouts: [Payout]
    let attention: Attention?
}

extension APIClient {
    func moneyAvailability() async throws -> MoneyAvailability {
        try await send("GET", "/v1/organization/money-availability")
    }

    func merchantReadiness(requireFresh: Bool = false) async throws -> MerchantReadiness {
        try await send("GET", "/v1/organization/merchant-readiness", requireFresh: requireFresh)
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
    @State private var availability: MoneyAvailability?
    @State private var hosted: URL?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    // MA-05: large title and one muted subtitle line; the Stripe note follows as body.
                    Text("Payments").font(Theme.font(30, weight: .medium)).tracking(-0.6).accessibilityAddTraits(.isHeader)
                    Text(subtitle).font(Theme.font(15)).foregroundStyle(Theme.muted)
                    Text("Card payments and payouts run through Stripe. Stripe holds your bank and identity details; Thorbis never sees them.")
                        .font(Theme.font(13)).foregroundStyle(Theme.muted).padding(.top, 8)
                }
                .padding(.bottom, 12)
                if let error { ErrorBanner(message: error) { await load() }.padding(.horizontal, -Theme.gutter) }
                if readiness == nil && error == nil { SkeletonRows(count: 4, leading: false, inset: 0) }
                if let readiness {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(readiness.headline).font(Theme.font(17, weight: .medium))
                        Text(readiness.detail).font(Theme.font(15)).foregroundStyle(Theme.muted)
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
                    if let availability { moneySection(availability) }
                }
            }
            .padding(.horizontal, Theme.gutter).padding(.top, 4).padding(.bottom, 24)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        // MA-08: the one commit sits in a bottom bar within thumb reach, not at the end of the scroll.
        .safeAreaInset(edge: .bottom) {
            if let title = readiness?.actionTitle {
                VStack(spacing: 8) {
                    PrimaryButton(title: title, icon: "arrow.up.forward.square", busy: busy) { Task { await openStripe() } }
                    Text("Opens Stripe in a secure browser. Tap Done there to come back.")
                        .font(Theme.font(12)).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, Theme.gutter).padding(.top, 10).padding(.bottom, 8)
                .background(Theme.background)
                .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
            }
        }
        .refreshable { await load() }
        .task { await load() }
        .sheet(item: Binding(get: { hosted.map(HostedPage.init) }, set: { if $0 == nil { hosted = nil } }),
               onDismiss: { Task { await reconcile() } }) { page in
            SafariPage(url: page.url).ignoresSafeArea()
        }
    }

    private var subtitle: String {
        guard let readiness else { return error == nil ? "Checking with Stripe…" : "Stripe status unavailable" }
        if readiness.chargesReady && readiness.payoutsReady { return "Taking cards and paying out" }
        if readiness.chargesReady { return "Taking cards · payouts not set up" }
        return "Not taking cards yet"
    }

    private struct HostedPage: Identifiable { let url: URL; var id: String { url.absoluteString } }

    private func statusRow(_ title: String, on: Bool) -> some View {
        HStack {
            Text(title).font(Theme.font(15, weight: .medium))
            Spacer()
            // Status is a word with a shape; colour is not the signal.
            Label(on ? "On" : "Not yet", systemImage: on ? "checkmark.circle.fill" : "circle.dashed")
                .font(Theme.font(15)).foregroundStyle(on ? Theme.foreground : Theme.muted)
        }
        .frame(minHeight: 48)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func moneySection(_ snapshot: MoneyAvailability) -> some View {
        if let attention = snapshot.attention {
            // MA-15: body-colour words, only the mark is tinted.
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.warning)
                VStack(alignment: .leading, spacing: 4) {
                    Text(attention.title).font(Theme.font(15, weight: .medium))
                    Text(attention.explanation).font(Theme.font(13)).foregroundStyle(Theme.muted)
                }
            }
            .foregroundStyle(Theme.foreground)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
            .padding(.top, 14)
        }
        ForEach(snapshot.balances) { balance in
            PaperGroupHeader(title: snapshot.balances.count > 1 ? "Balance · \(balance.currency)" : "Balance").padding(.top, 10)
            amountRow("Available", balance.available, balance.currency)
            amountRow("Pending", balance.pending, balance.currency)
            Text(balance.explanation).font(Theme.font(12)).foregroundStyle(Theme.muted).padding(.top, 2)
        }
        if !snapshot.payouts.isEmpty {
            PaperGroupHeader(title: "Recent payouts", count: snapshot.payouts.count).padding(.top, 14)
            ForEach(Array(snapshot.payouts.enumerated()), id: \.offset) { _, payout in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        if payout.responsibleActor == "owner" {
                            Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.warning)
                                .accessibilityLabel("Needs you")
                        }
                        Text(payout.title).font(Theme.font(15, weight: .medium))
                        Spacer()
                        Text(money(payout.amount, currency: payout.currency)).moneyStyle(.row)
                    }
                    Text(payout.explanation).font(Theme.font(12)).foregroundStyle(Theme.muted)
                }
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func amountRow(_ title: String, _ amount: Int, _ currency: String) -> some View {
        HStack {
            Text(title).font(Theme.font(15, weight: .medium))
            Spacer()
            Text(money(amount, currency: currency)).moneyStyle(.row)
                .foregroundStyle(amount < 0 ? Theme.warning : Theme.foreground)
        }
        .frame(minHeight: 44)
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
        await loadMoney()
    }

    /// Only once Stripe is connected; before that, or if the read is refused, nothing shows.
    private func loadMoney() async {
        guard let readiness, readiness.state != "not_started" else { availability = nil; return }
        let generation = session.generation
        let value = try? await api.moneyAvailability()
        guard session.generation == generation else { return }
        availability = value
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
            await loadMoney()
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

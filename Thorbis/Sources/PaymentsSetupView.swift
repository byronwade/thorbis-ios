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
    /// Money › Payouts (Paper 90): once Stripe is set up and nothing is asked of the owner, the
    /// page is the balance and the recent payouts. Setup, or anything Stripe wants, keeps the
    /// setup page below with its Open Stripe button.
    var showsPayouts = false

    private var payoutsSnapshot: MoneyAvailability? {
        guard showsPayouts, let readiness, readiness.actionTitle == nil else { return nil }
        return availability
    }

    var body: some View {
        ScrollView {
            if let snapshot = payoutsSnapshot {
                PayoutsPage(snapshot: snapshot, company: session.activeOrganization?.name ?? "")
            } else {
            VStack(alignment: .leading, spacing: 0) {
                // MA-05 / Paper v2: the 34 Bold title and one muted subtitle line.
                PaperHeader(title: "Payments", subtitle: subtitle)
                    .environment(\.paperMenuButton, false)
                    .environment(\.paperDrawer, nil)
                VStack(alignment: .leading, spacing: 20) {
                    if let error { ErrorBanner(message: error) { await load() }.padding(.horizontal, -PaperCardMetrics.margin) }
                    if readiness == nil && error == nil { SkeletonSection(rows: 3) }
                    if let readiness {
                        // Paper 15/15A: "Customer payments" with its state as a pill, then what it means.
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .center, spacing: 8) {
                                Text("Customer payments").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                                    .accessibilityAddTraits(.isHeader)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                stateBadge(readiness)
                            }
                            .frame(minHeight: 26)
                            Text(readiness.headline).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(readiness.detail).font(Theme.font(14)).foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 4)
                        PaperSection("Status") {
                            statusRow("Card payments", on: readiness.chargesReady)
                            WellDivider()
                            statusRow("Payouts to your bank", on: readiness.payoutsReady)
                        }
                        if readiness.requirements.total > 0 {
                            PaperSection("Stripe is asking for") {
                                if readiness.requirements.pastDueCount > 0 { countRow("Past due", readiness.requirements.pastDueCount, urgent: true) }
                                if readiness.requirements.currentlyDueCount > 0 {
                                    if readiness.requirements.pastDueCount > 0 { WellDivider() }
                                    countRow("Due now", readiness.requirements.currentlyDueCount, urgent: true)
                                }
                                if readiness.requirements.eventuallyDueCount > 0 {
                                    if readiness.requirements.pastDueCount + readiness.requirements.currentlyDueCount > 0 { WellDivider() }
                                    countRow("Due later", readiness.requirements.eventuallyDueCount, urgent: false)
                                }
                            }
                        }
                        if let availability { moneySection(availability) }
                    }
                    Text("Card payments and payouts run through Stripe. Stripe holds your bank and identity details; Thorbis never sees them.")
                        .font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 8).padding(.bottom, 24)
            }
            }
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        // MA-08: the one commit sits in a bottom bar within thumb reach, not at the end of the scroll.
        .safeAreaInset(edge: .bottom) {
            if let title = readiness?.actionTitle {
                VStack(spacing: 8) {
                    PrimaryButton(title: title, icon: "arrow.up.forward.square", busy: busy) { Task { await openStripe() } }
                    Text("Opens Stripe in a secure browser. Tap Done there to come back.")
                        .font(Theme.font(12)).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 10).padding(.bottom, 8)
                .background(Theme.canvas)
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

    /// Paper 15A: a pill beside "Customer payments": Verified once Stripe takes cards and pays out.
    private func stateBadge(_ readiness: MerchantReadiness) -> some View {
        let ready = readiness.chargesReady && readiness.payoutsReady
        return Text(ready ? "Verified" : "Stripe Connect")
            .font(Theme.font(13, weight: .semibold))
            .foregroundStyle(ready ? Theme.success : Theme.brandText)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(ready ? Theme.successSurface : Theme.brandSurface, in: Capsule())
    }

    private func statusRow(_ title: String, on: Bool) -> some View {
        // Status is a word with a dot; colour is not the only signal.
        PaperListRow(title: title, status: StatusWord(text: on ? "On" : "Not yet", tint: on ? Theme.statusDone : nil))
            .frame(minHeight: 56)
            .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func moneySection(_ snapshot: MoneyAvailability) -> some View {
        if let attention = snapshot.attention {
            // MA-15: body-colour words, only the mark is tinted.
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text(attention.title).font(Theme.font(16, weight: .medium))
                    Text(attention.explanation).font(Theme.font(14)).foregroundStyle(Theme.muted)
                }
            }
            .foregroundStyle(Theme.foreground)
            .padding(PaperCardMetrics.inset).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
        ForEach(snapshot.balances) { balance in
            VStack(alignment: .leading, spacing: 8) {
                PaperSection(snapshot.balances.count > 1 ? "Balance · \(balance.currency)" : "Balance") {
                    amountRow("Available", balance.available, balance.currency)
                    WellDivider()
                    amountRow("Pending", balance.pending, balance.currency)
                }
                Text(balance.explanation).font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
        if !snapshot.payouts.isEmpty {
            PaperSection("Recent payouts", count: snapshot.payouts.count) {
                ForEach(Array(snapshot.payouts.enumerated()), id: \.offset) { index, payout in
                    if index > 0 { WellDivider() }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            if payout.responsibleActor == "owner" {
                                Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.warning)
                                    .accessibilityLabel("Needs you")
                            }
                            Text(payout.title).font(Theme.font(16, weight: .medium))
                            Spacer()
                            Text(money(payout.amount, currency: payout.currency))
                                .font(Theme.monoFont(16, weight: .semibold)).moneyStyle(.row)
                        }
                        Text(payout.explanation).font(Theme.font(14)).foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 11)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func amountRow(_ title: String, _ amount: Int, _ currency: String) -> some View {
        HStack {
            Text(title).font(Theme.font(16, weight: .medium))
            Spacer()
            // Paper: a money row's figure in 16 Semibold tabular beside its 16 Medium label.
            Text(money(amount, currency: currency)).font(Theme.monoFont(16, weight: .semibold)).moneyStyle(.row)
                .foregroundStyle(amount < 0 ? Theme.warning : Theme.foreground)
        }
        .padding(.horizontal, PaperCardMetrics.inset)
        .frame(minHeight: 56)
        .accessibilityElement(children: .combine)
    }

    private func countRow(_ title: String, _ count: Int, urgent: Bool) -> some View {
        HStack {
            Text(title).font(Theme.font(16, weight: .medium))
            Spacer()
            Text(count == 1 ? "1 item" : "\(count) items").font(Theme.font(15))
                .foregroundStyle(urgent ? Theme.warning : Theme.muted)
        }
        .padding(.horizontal, PaperCardMetrics.inset)
        .frame(minHeight: 56)
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

import Foundation
@preconcurrency import StripeTerminal

/// The server returns the same durable attempt ID only after authorizing and
/// binding its token to the attempt's merchant. No provider account ID is
/// sent to the phone. This adapter is held and is not used by the app yet.
private struct AttemptBoundTerminalToken: Decodable {
    let secret: String
    let locationId: String
    let attemptId: String
}

private struct AttemptBoundTerminalTokenRequest: Encodable {
    let attemptId: String
}

extension APIClient {
    func attemptBoundTerminalToken(invoiceID: String, attemptID: String) async throws -> TerminalBoundToken {
        let response: AttemptBoundTerminalToken = try await send(
            "POST", try financialPath("/v1/invoices", id: invoiceID, suffix: "/terminal-connection-token"),
            body: AttemptBoundTerminalTokenRequest(attemptId: attemptID)
        )
        return .init(secret: response.secret, attemptID: response.attemptId, locationID: response.locationId)
    }
}

private struct TerminalCallbackBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

/// Stripe can call its provider on a non-main thread. Read and invoke the
/// installed, attempt-checked closure only on the main actor.
@MainActor private final class AttemptBoundTokenProvider: NSObject, ConnectionTokenProvider, @unchecked Sendable {
    var fetch: (@MainActor () async throws -> String)?

    nonisolated func fetchConnectionToken(_ completion: @escaping ConnectionTokenCompletionBlock) {
        let reply = TerminalCallbackBox(completion)
        Task { @MainActor [weak self] in
            guard let fetch = self?.fetch else { return reply.value(nil, CancellationError()) }
            do { reply.value(try await fetch(), nil) }
            catch { reply.value(nil, error) }
        }
    }
}

/// Owns the actual singleton/provider pairing. If the legacy provider has
/// already initialized Stripe, refuse to operate instead of assuming ownership.
@MainActor final class StripeBoundTerminalEnvironment {
    static let shared = StripeBoundTerminalEnvironment()
    private let provider = AttemptBoundTokenProvider()
    private lazy var owner = TerminalOwnership(isInitialized: { Terminal.isInitialized() }, initialize: { [provider] in
        Terminal.initWithTokenProvider(provider)
    })

    private init() {}

    var legacyAvailable: Bool { owner.legacyAvailable }
    func beginLegacyCollection() -> Bool { owner.beginLegacyCollection() }
    func endLegacyCollection() { owner.endLegacyCollection() }

    func claimLegacy(_ fetch: @escaping @MainActor () async throws -> String) throws {
        try owner.claimLegacy { provider.fetch = fetch }
    }

    func claimBound(_ fetch: @escaping @MainActor () async throws -> String) throws {
        try owner.claimBound { provider.fetch = fetch }
    }

    fileprivate func configure(_ fetch: @escaping @MainActor () async throws -> String) {
        provider.fetch = fetch
    }
}

/// Concrete SDK bridge for the held coordinator. A successful async SDK call
/// is not treated as proof that an uncertain earlier operation is reconciled;
/// the coordinator parks on any error or retirement. It is intentionally not
/// connected to TapToPayController or enabled in a distribution build.
@MainActor final class StripeBoundTerminalDriver: TerminalSessionDriver {
    typealias Intent = PaymentIntent
    typealias Result = PaymentIntent
    private let environment: StripeBoundTerminalEnvironment
    private let clientSecret: String

    init(clientSecret: String, environment: StripeBoundTerminalEnvironment = .shared) throws {
        self.environment = environment
        self.clientSecret = clientSecret
    }

    func bootstrap(_ fetch: @escaping @MainActor () async throws -> String) throws {
        try environment.claimBound(fetch)
    }

    var isConnected: Bool { Terminal.shared.connectedReader != nil }

    func disconnect() async throws { try await Terminal.shared.disconnectReader() }

    func clearCredentials() throws { try Terminal.shared.clearCachedCredentials().get() }

    func configureTokenProvider(_ fetch: @escaping @MainActor () async throws -> String) throws {
        environment.configure(fetch)
    }

    func connect(locationID: String) async throws {
        let discovery = try TapToPayDiscoveryConfigurationBuilder().build()
        let reader = try await Discovery().first(discovery)
        let config = try TapToPayConnectionConfigurationBuilder(delegate: ReaderEvents.shared, locationId: locationID)
            .setTosAcceptancePermitted(false)
            .build()
        _ = try await Terminal.shared.connectReader(reader, connectionConfig: config)
    }

    func retrieveIntent() async throws -> TerminalRetrievedIntent<PaymentIntent> {
        let intent = try await Terminal.shared.retrievePaymentIntent(clientSecret: clientSecret)
        return .init(value: intent, paymentIntentID: intent.stripeId ?? "")
    }

    func collect(_ intent: PaymentIntent) async throws -> TerminalRetrievedIntent<PaymentIntent> {
        let collected = try await Terminal.shared.collectPaymentMethod(intent)
        return .init(value: collected, paymentIntentID: collected.stripeId ?? "")
    }

    func confirm(_ intent: PaymentIntent) async throws -> PaymentIntent {
        try await Terminal.shared.confirmPaymentIntent(intent)
    }
}

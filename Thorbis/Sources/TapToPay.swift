import Foundation
import ProximityReader
@preconcurrency import StripeTerminal

/// Server contract (BYR-1550). The server owns workspace/merchant eligibility;
/// the app's signing qualification is a separate, fail-closed build gate.
struct TerminalConnectionToken: Decodable, Sendable {
    let secret: String
    let locationId: String
}

struct CardPresentIntent: Decodable, Sendable {
    let attemptId: String
    let clientSecret: String
    let paymentIntentId: String
    let locationId: String
    let amount: FieldMoney
    let expiresAt: String
}

extension APIClient {
    func terminalConnectionToken(invoiceID: String) async throws -> TerminalConnectionToken {
        try await send("POST", try financialPath("/v1/invoices", id: invoiceID, suffix: "/terminal-connection-token"))
    }

    func cardPresentIntent(invoiceID: String) async throws -> CardPresentIntent {
        try await send("POST", try financialPath("/v1/invoices", id: invoiceID, suffix: "/card-present-intents"))
    }
}

/// Tap to Pay on iPhone through Stripe Terminal. The phone only collects; the payment is settled
/// by Stripe's webhook on the server, so success here means "waiting for Thorbis to record it".
@MainActor
final class TapToPayController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case unavailable
        case preparing
        case waitingForCard
        case processing
        case recording
        case paid
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle

    static let feature = "tap_to_pay"
    // Legacy tokens have no durable attempt binding. Keep this entry closed
    // even if a build flag is changed, until the bound flow replaces it.
    private static let legacyCollectionQualified = false
    // The bound flow is wired for qualification only; it lacks durable
    // reconciliation and must not be enabled in a shipping build.
    private static let boundCollectionQualified = false

    static var buildEnabled: Bool { TapToPayReadiness.buildEnabled }

    /// Apple checks the model; Stripe also checks real-device OS/discovery support.
    /// Neither check establishes entitlement approval, which is audited separately.
    static var deviceSupported: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        PaymentCardReader.isSupported
        #endif
    }

    private let invoiceID: String
    private var intent: CardPresentIntent?

    init(invoiceID: String) {
        self.invoiceID = invoiceID
    }

    var busy: Bool { [.preparing, .waitingForCard, .processing, .recording].contains(phase) }

    /// Runs one charge for the invoice balance. `refresh` reloads the invoice's payments and
    /// returns true only once this intent's webhook-settled payment shows up.
    func charge(api: APIClient, session: SessionController? = nil, refresh: @escaping @MainActor (CardPresentIntent) async -> Bool) async {
        guard !busy else { return }
        if Self.boundCollectionQualified {
            await chargeBound(api: api, session: session, refresh: refresh)
            return
        }
        guard Self.buildEnabled, Self.legacyCollectionQualified, Self.deviceSupported else {
            phase = .unavailable
            return
        }
        guard TerminalSetup.shared.beginLegacyCollection() else {
            phase = .failed("Another card payment is already in progress.")
            return
        }
        var collectionSettled = false
        var sdkStarted = false
        defer { if collectionSettled || !sdkStarted { TerminalSetup.shared.endLegacyCollection() } }
        phase = .preparing
        do {
            let intent: CardPresentIntent
            if let cached = self.intent { intent = cached } else { intent = try await api.cardPresentIntent(invoiceID: invoiceID) }
            self.intent = intent
            try TerminalSetup.shared.prepare(api: api, invoiceID: invoiceID)
            sdkStarted = true
            guard TerminalSetup.shared.supportsTapToPay else {
                collectionSettled = true
                phase = .unavailable
                return
            }
            try await TerminalSetup.shared.connect(locationID: intent.locationId)
            let paymentIntent = try await Terminal.shared.retrievePaymentIntent(clientSecret: intent.clientSecret)
            phase = .waitingForCard
            let collected = try await Terminal.shared.collectPaymentMethod(paymentIntent)
            phase = .processing
            _ = try await Terminal.shared.confirmPaymentIntent(collected)
            phase = .recording
            for attempt in 0..<20 {
                if await refresh(intent) { collectionSettled = true; phase = .paid; return }
                try await Task.sleep(nanoseconds: UInt64(min(1 + attempt, 4)) * 1_000_000_000)
            }
            // Money moved; Thorbis records it as soon as Stripe's confirmation arrives.
            phase = .failed("The card was charged. Thorbis is still recording the payment; check the invoice in a minute.")
        } catch is CancellationError {
            phase = .idle
        } catch {
            phase = .failed(Self.message(for: error))
        }
    }

    private func chargeBound(api: APIClient, session: SessionController?, refresh: @escaping @MainActor (CardPresentIntent) async -> Bool) async {
        guard Self.buildEnabled, Self.boundCollectionQualified, Self.deviceSupported,
              let session, session.phase == .ready, session.can("invoice.payment.create", feature: "payments"),
              session.isFeatureOn(Self.feature), let actor = session.user?.id,
              let organization = session.activeOrganization?.id, let scope = api.savedCopyScope else {
            phase = .unavailable
            return
        }
        do { try StripeBoundTerminalEnvironment.shared.preflightBound() }
        catch { phase = .failed("Another card payment is already in progress."); return }
        let generation = api.requestGeneration
        let scopeRevision = api.savedCopyScopeRevision
        let sessionGeneration = session.generation
        let authorityRevision = session.authorityRevision
        let origin = api.baseURL
        let authority = BoundTapAuthority(actorID: actor, organizationID: organization, sessionGeneration: sessionGeneration,
                                          authorityRevision: authorityRevision, apiGeneration: generation, origin: origin, permitted: true)
        let current: @MainActor () -> Bool = {
            let now = BoundTapAuthority(actorID: session.user?.id ?? "", organizationID: session.activeOrganization?.id ?? "",
                                        sessionGeneration: session.generation, authorityRevision: session.authorityRevision,
                                        apiGeneration: api.requestGeneration, origin: api.baseURL,
                                        permitted: session.phase == .ready && session.can("invoice.payment.create", feature: "payments") && session.isFeatureOn(Self.feature))
            return now == authority && api.savedCopyScopeRevision == scopeRevision && api.savedCopyScope == scope
        }
        let recoveryStore = KeychainBoundTapRecoveryStore.shared
        phase = .preparing
        do {
            _ = try await BoundTapPaymentFlow.run(enabled: Self.buildEnabled && Self.boundCollectionQualified,
                                                   supported: Self.deviceSupported, isCurrent: current,
                                                   create: {
                let marker = BoundTapRecovery(origin: origin, actorID: actor, organizationID: organization,
                                               invoiceID: self.invoiceID, attemptID: nil, paymentIntentID: nil,
                                               amount: nil, currency: nil)
                return try await BoundTapRecoveryManager.prepare(store: recoveryStore, marker: marker,
                    create: { try await api.cardPresentIntent(invoiceID: self.invoiceID) }, identify: { intent, marker in
                        var receipt = marker
                        receipt.attemptID = intent.attemptId
                        receipt.paymentIntentID = intent.paymentIntentId
                        receipt.amount = intent.amount.amount
                        receipt.currency = intent.amount.currency
                        return receipt
                    })
            },
                                                   collect: { intent in
                let binding = TerminalAttemptBinding(invoiceID: self.invoiceID, attemptID: intent.attemptId,
                                                     paymentIntentID: intent.paymentIntentId, locationID: intent.locationId,
                                                     origin: origin, scope: scope, generation: generation)
                let driver = try StripeBoundTerminalDriver(clientSecret: intent.clientSecret)
                self.phase = .waitingForCard
                _ = try await TerminalSessionCoordinator().collect(binding: binding, driver: driver,
                                                                   isCurrent: current,
                                                                   fetch: { try await api.attemptBoundTerminalToken(invoiceID: self.invoiceID, attemptID: intent.attemptId) })
                self.phase = .recording
                for attempt in 0..<20 {
                    if await refresh(intent) {
                        guard current() else { throw BoundTapFlowError.uncertain }
                        // Payment history is not yet proven to be a fresh,
                        // authority-bound acknowledgement. Keep the receipt
                        // until a dedicated reconciliation path is qualified.
                        throw BoundTapFlowError.uncertain
                    }
                    try await Task.sleep(nanoseconds: UInt64(min(1 + attempt, 4)) * 1_000_000_000)
                }
                throw BoundTapFlowError.uncertain
            })
            phase = .paid
        } catch BoundTapFlowError.unavailable {
            phase = .unavailable
        } catch BoundTapFlowError.busy {
            phase = .failed("Another card payment is already in progress.")
        } catch BoundTapFlowError.retired {
            phase = .failed("Your session changed. Open the invoice again to continue.")
        } catch BoundTapFlowError.recoveryPending {
            phase = .failed("A previous card payment needs to be checked before taking another.")
        } catch BoundTapFlowError.recoveryUnavailable {
            phase = .failed("Payment recovery is unavailable. Try again before taking a card payment.")
        } catch {
            phase = .failed("Payment status is not confirmed. Check this invoice before taking another payment.")
        }
    }

    func reset() { if !busy { phase = .idle } }

    private static func message(for error: Error) -> String {
        if let problem = error as? Problem {
            switch problem.status {
            case 403: return "Tap to Pay isn't turned on for this workspace yet."
            case 409: return problem.detail ?? "Tap to Pay isn't ready for this invoice."
            case 502, 503: return "Card payments are unavailable right now. Try again in a moment."
            default: break
            }
        }
        let nsError = error as NSError
        if nsError.domain == ErrorDomain, let code = ErrorCode.Code(rawValue: nsError.code) {
            switch code {
            case .canceled: return "Payment canceled."
            case .declinedByStripeAPI, .declinedByReader: return "The card was declined. Try another card."
            case .tapToPayReaderTOSAcceptanceRequiresiCloudSignIn, .tapToPayReaderTOSNotYetAccepted:
                return "Tap to Pay needs setup. Ask an authorized administrator to accept Apple's terms."
            case .commandNotAllowed:
                return "Tap to Pay isn't available on this iPhone with the current setup. Use a payment link or another method."
            default: break
            }
        }
        return error.localizedDescription
    }
}

/// One Stripe Terminal setup per app run: the token provider is installed once and asks for a
/// connection token on the invoice being collected.
@MainActor
final class TerminalSetup: NSObject {
    static let shared = TerminalSetup()
    func beginLegacyCollection() -> Bool {
        StripeBoundTerminalEnvironment.shared.beginLegacyCollection()
    }

    func endLegacyCollection() { StripeBoundTerminalEnvironment.shared.endLegacyCollection() }
    func prepare(api: APIClient, invoiceID: String) throws {
        try StripeBoundTerminalEnvironment.shared.claimLegacy { [weak api] in
            guard let api else { throw CancellationError() }
            return try await api.terminalConnectionToken(invoiceID: invoiceID).secret
        }
    }

    var supportsTapToPay: Bool {
        guard StripeBoundTerminalEnvironment.shared.legacyAvailable, Terminal.isInitialized() else { return false }
        if case .success = Terminal.shared.supportsReaders(of: .tapToPay, discoveryMethod: .tapToPay, simulated: false) {
            return true
        }
        return false
    }

    func connect(locationID: String) async throws {
        if Terminal.shared.connectedReader != nil { return }
        let discovery = try TapToPayDiscoveryConfigurationBuilder().build()
        let reader = try await Discovery().first(discovery)
        let config = try connectionConfiguration(locationID: locationID)
        _ = try await Terminal.shared.connectReader(reader, connectionConfig: config)
    }

    func connectionConfiguration(locationID: String) throws -> TapToPayConnectionConfiguration {
        try TapToPayConnectionConfigurationBuilder(delegate: ReaderEvents.shared, locationId: locationID)
            .setTosAcceptancePermitted(false)
            .build()
    }
}

/// Discovery reports readers through a delegate; the first one (this iPhone) is all Tap to Pay needs.
final class Discovery: NSObject, DiscoveryDelegate, @unchecked Sendable {
    private let continuation = TerminalOneShot<CheckedContinuation<Reader, Error>>()
    private var cancelable: Cancelable?

    @MainActor func first(_ configuration: DiscoveryConfiguration) async throws -> Reader {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation.install(continuation)
                cancelable = Terminal.shared.discoverReaders(configuration, delegate: self) { [weak self] error in
                    self?.finish(.failure(error ?? DiscoveryEnded()))
                }
            }
        } onCancel: {
            Task { @MainActor [self] in
                cancelable?.cancel { _ in }
                finish(.failure(CancellationError()))
            }
        }
    }

    func terminal(_ terminal: Terminal, didUpdateDiscoveredReaders readers: [Reader]) {
        guard let reader = readers.first else { return }
        finish(.success(reader))
    }

    private func finish(_ result: Result<Reader, Error>) {
        guard let continuation = continuation.take() else { return }
        let sendable = Unchecked(result)
        continuation.resume(with: sendable.value)
    }
}

private struct DiscoveryEnded: Error {}

/// Stripe's Objective-C callbacks and models predate Sendable; they are used on one thread at a time.
private struct Unchecked<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

/// Apple's Tap to Pay sheet shows its own prompts; these callbacks only cover setup updates.
final class ReaderEvents: NSObject, TapToPayReaderDelegate, @unchecked Sendable {
    static let shared = ReaderEvents()
    func tapToPayReader(_ reader: Reader, didStartInstallingUpdate update: ReaderSoftwareUpdate, cancelable: Cancelable?) {}
    func tapToPayReader(_ reader: Reader, didReportReaderSoftwareUpdateProgress progress: Float) {}
    func tapToPayReader(_ reader: Reader, didFinishInstallingUpdate update: ReaderSoftwareUpdate?, error: Error?) {}
    func tapToPayReader(_ reader: Reader, didRequestReaderInput inputOptions: ReaderInputOptions = []) {}
    func tapToPayReader(_ reader: Reader, didRequestReaderDisplayMessage displayMessage: ReaderDisplayMessage) {}
    func reader(_ reader: Reader, didDisconnect reason: DisconnectReason) {}
}

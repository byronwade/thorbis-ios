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

    static var buildEnabled: Bool { TapToPayReadiness.buildEnabled }

    /// Apple checks the model; Stripe also checks real-device OS/discovery support.
    /// Neither check establishes entitlement approval, which is audited separately.
    static var deviceSupported: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        PaymentCardReader.isSupported && TerminalSetup.shared.supportsTapToPay
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
    func charge(api: APIClient, refresh: @escaping @MainActor (CardPresentIntent) async -> Bool) async {
        guard !busy else { return }
        guard Self.buildEnabled, Self.deviceSupported else {
            phase = .unavailable
            return
        }
        phase = .preparing
        do {
            let intent: CardPresentIntent
            if let cached = self.intent { intent = cached } else { intent = try await api.cardPresentIntent(invoiceID: invoiceID) }
            self.intent = intent
            TerminalSetup.shared.prepare(api: api, invoiceID: invoiceID)
            try await TerminalSetup.shared.connect(locationID: intent.locationId)
            let paymentIntent = try await Terminal.shared.retrievePaymentIntent(clientSecret: intent.clientSecret)
            phase = .waitingForCard
            let collected = try await Terminal.shared.collectPaymentMethod(paymentIntent)
            phase = .processing
            _ = try await Terminal.shared.confirmPaymentIntent(collected)
            phase = .recording
            for attempt in 0..<20 {
                if await refresh(intent) { phase = .paid; return }
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
                return "Accept Apple's Tap to Pay terms to start taking cards on this iPhone."
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
    private let tokens = TokenProvider()
    private var installed = false

    func prepare(api: APIClient, invoiceID: String) {
        tokens.api = api
        tokens.invoiceID = invoiceID
        installIfNeeded()
    }

    var supportsTapToPay: Bool {
        installIfNeeded()
        if case .success = Terminal.shared.supportsReaders(of: .tapToPay, discoveryMethod: .tapToPay, simulated: false) {
            return true
        }
        return false
    }

    private func installIfNeeded() {
        if !installed {
            Terminal.initWithTokenProvider(tokens)
            installed = true
        }
    }

    func connect(locationID: String) async throws {
        if Terminal.shared.connectedReader != nil { return }
        let discovery = try TapToPayDiscoveryConfigurationBuilder().build()
        let reader = try await Discovery().first(discovery)
        let config = try TapToPayConnectionConfigurationBuilder(delegate: ReaderEvents.shared, locationId: locationID).build()
        _ = try await Terminal.shared.connectReader(reader, connectionConfig: config)
    }
}

private final class TokenProvider: NSObject, ConnectionTokenProvider, @unchecked Sendable {
    weak var api: APIClient?
    var invoiceID = ""

    func fetchConnectionToken(_ completion: @escaping ConnectionTokenCompletionBlock) {
        let invoiceID = invoiceID
        let reply = Unchecked(completion)
        Task { @MainActor [weak api] in
            guard let api else { return reply.value(nil, CancellationError()) }
            do { reply.value(try await api.terminalConnectionToken(invoiceID: invoiceID).secret, nil) }
            catch { reply.value(nil, error) }
        }
    }
}

/// Discovery reports readers through a delegate; the first one (this iPhone) is all Tap to Pay needs.
private final class Discovery: NSObject, DiscoveryDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<Reader, Error>?
    private var cancelable: Cancelable?

    @MainActor func first(_ configuration: DiscoveryConfiguration) async throws -> Reader {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            cancelable = Terminal.shared.discoverReaders(configuration, delegate: self) { [weak self] error in
                if let error { self?.finish(.failure(error)) }
            }
        }
    }

    func terminal(_ terminal: Terminal, didUpdateDiscoveredReaders readers: [Reader]) {
        guard let reader = readers.first else { return }
        finish(.success(reader))
    }

    private func finish(_ result: Result<Reader, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        let sendable = Unchecked(result)
        continuation.resume(with: sendable.value)
    }
}

/// Stripe's Objective-C callbacks and models predate Sendable; they are used on one thread at a time.
private struct Unchecked<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

/// Apple's Tap to Pay sheet shows its own prompts; these callbacks only cover setup updates.
private final class ReaderEvents: NSObject, TapToPayReaderDelegate, @unchecked Sendable {
    static let shared = ReaderEvents()
    func tapToPayReader(_ reader: Reader, didStartInstallingUpdate update: ReaderSoftwareUpdate, cancelable: Cancelable?) {}
    func tapToPayReader(_ reader: Reader, didReportReaderSoftwareUpdateProgress progress: Float) {}
    func tapToPayReader(_ reader: Reader, didFinishInstallingUpdate update: ReaderSoftwareUpdate?, error: Error?) {}
    func tapToPayReader(_ reader: Reader, didRequestReaderInput inputOptions: ReaderInputOptions = []) {}
    func tapToPayReader(_ reader: Reader, didRequestReaderDisplayMessage displayMessage: ReaderDisplayMessage) {}
    func reader(_ reader: Reader, didDisconnect reason: DisconnectReason) {}
}

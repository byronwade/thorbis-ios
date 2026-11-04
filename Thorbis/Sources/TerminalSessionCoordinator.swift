import Foundation

/// A server attempt identity, never a provider-account identifier.
struct TerminalAttemptBinding: Equatable, Sendable {
    let invoiceID: String
    let attemptID: String
    let paymentIntentID: String
    let locationID: String
    let origin: String
    let scope: String
    let generation: UUID
}

struct TerminalBoundToken: Sendable {
    let secret: String
    let attemptID: String
    let locationID: String
}

enum TerminalBindingError: Error, Equatable {
    case busy, retired, invalidToken, invalidIntent, confirmationUncertain
}

struct TerminalRetrievedIntent<Value> {
    let value: Value
    /// Read from the Stripe SDK's returned PaymentIntent, never client input.
    let paymentIntentID: String
}

/// All methods are owned by the same actor; concrete Stripe bridging remains
/// gated until the server's attempt-bound token contract is deployed.
@MainActor protocol TerminalSessionDriver {
    associatedtype Intent
    associatedtype Result
    var isConnected: Bool { get }
    func disconnect() async throws
    func clearCredentials() throws
    func configureTokenProvider(_ fetch: @escaping @MainActor () async throws -> String) throws
    func connect(locationID: String) async throws
    func retrieveIntent() async throws -> TerminalRetrievedIntent<Intent>
    func collect(_ intent: Intent) async throws -> TerminalRetrievedIntent<Intent>
    func confirm(_ intent: Intent) async throws -> Result
}

/// Serializes the entire collection, not only reader connection. The caller
/// must retain the same durable attempt for uncertain/cancelled operations.
@MainActor final class TerminalSessionCoordinator {
    // Stripe Terminal and its token provider are process-wide singletons.
    private static var busy = false
    // Once confirmation may have started, do not start another collection until
    // a durable recovery owner has reconciled the exact attempt. This prototype
    // deliberately has no production reset; the durable owner is still pending.
    private static var uncertainAttempt: String?

    #if DEBUG
    static func resetForTests() { busy = false; uncertainAttempt = nil }
    #endif

    func collect<D: TerminalSessionDriver>(
        binding: TerminalAttemptBinding,
        driver: D,
        isCurrent: @escaping @MainActor () -> Bool,
        fetch: @escaping @MainActor () async throws -> TerminalBoundToken
    ) async throws -> D.Result {
        guard Self.uncertainAttempt == nil else { throw TerminalBindingError.confirmationUncertain }
        guard !Self.busy else { throw TerminalBindingError.busy }
        Self.busy = true
        var active = true
        defer { active = false; Self.busy = false }
        func check() throws {
            try Task.checkCancellation()
            guard active, isCurrent() else { throw TerminalBindingError.retired }
        }
        func sdk<T>(_ work: () async throws -> T) async throws -> T {
            do { return try await work() }
            catch {
                // An async SDK wrapper may return on Swift cancellation before
                // its underlying callback has terminated. Hold the process
                // lease until the durable recovery owner can reconcile it.
                Self.uncertainAttempt = binding.attemptID
                if let bindingError = error as? TerminalBindingError { throw bindingError }
                throw TerminalBindingError.confirmationUncertain
            }
        }
        func checkAfterSDK() throws {
            do { try check() }
            catch {
                Self.uncertainAttempt = binding.attemptID
                throw TerminalBindingError.confirmationUncertain
            }
        }
        try check()
        guard !binding.paymentIntentID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TerminalBindingError.invalidIntent
        }
        if driver.isConnected {
            try await sdk { try await driver.disconnect() }
            try checkAfterSDK()
        }
        try driver.clearCredentials()
        try driver.configureTokenProvider {
            try check()
            let token = try await fetch()
            try check()
            guard !token.secret.isEmpty,
                  token.attemptID == binding.attemptID,
                  token.locationID == binding.locationID else { throw TerminalBindingError.invalidToken }
            return token.secret
        }
        try check()
        try await sdk { try await driver.connect(locationID: binding.locationID) }
        try checkAfterSDK()
        let intent = try await sdk { try await driver.retrieveIntent() }
        try checkAfterSDK()
        guard intent.paymentIntentID == binding.paymentIntentID else { throw TerminalBindingError.invalidIntent }
        let collected = try await sdk { try await driver.collect(intent.value) }
        do {
            try check()
            guard collected.paymentIntentID == binding.paymentIntentID else { throw TerminalBindingError.invalidIntent }
        } catch {
            // A reader may already have collected a card. Preserve the
            // attempt for reconciliation instead of silently starting another.
            Self.uncertainAttempt = binding.attemptID
            throw TerminalBindingError.confirmationUncertain
        }
        do {
            let result = try await driver.confirm(collected.value)
            try check()
            return result
        } catch {
            Self.uncertainAttempt = binding.attemptID
            throw TerminalBindingError.confirmationUncertain
        }
    }
}

import Foundation

enum TerminalOwnershipError: Error { case occupied }

/// One owner of the process-wide SDK; legacy and bound paths cannot mix.
@MainActor final class TerminalOwnership {
    private enum Mode { case unclaimed, legacy, bound }
    private var mode: Mode = .unclaimed
    private var ownsSDK = false
    private var legacyCollectionActive = false
    private let isInitialized: () -> Bool
    private let initialize: () -> Void

    init(isInitialized: @escaping () -> Bool, initialize: @escaping () -> Void) {
        self.isInitialized = isInitialized
        self.initialize = initialize
    }

    var legacyAvailable: Bool { mode != .bound }

    func beginLegacyCollection() -> Bool {
        guard mode != .bound, !legacyCollectionActive else { return false }
        legacyCollectionActive = true
        return true
    }

    func endLegacyCollection() { legacyCollectionActive = false }

    func claimLegacy(_ install: () -> Void) throws {
        guard mode != .bound else { throw TerminalOwnershipError.occupied }
        try verifyOwnership()
        mode = .legacy
        install()
        try ensureInitialized()
    }

    func claimBound(_ install: () -> Void) throws {
        guard mode != .legacy, !legacyCollectionActive else { throw TerminalOwnershipError.occupied }
        try verifyOwnership()
        if mode == .bound { return }
        mode = .bound
        // The SDK may synchronously request a token as soon as it initializes.
        install()
        try ensureInitialized()
    }

    private func verifyOwnership() throws {
        guard ownsSDK || !isInitialized() else { throw TerminalOwnershipError.occupied }
    }

    private func ensureInitialized() throws {
        try verifyOwnership()
        if !ownsSDK {
            initialize()
            ownsSDK = true
        }
    }
}

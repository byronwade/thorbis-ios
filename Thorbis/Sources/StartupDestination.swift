import Foundation

enum StartupDestination: String, CaseIterable {
    case automatic, home, schedule, jobs, customers, properties, attention, inbox, estimates, invoices
    case billing, priceBook, money, reports, scorecard, team, notices, drafts
    case localFleet = "local-fleet", localEquipment = "local-equipment"
    case localAgreements = "local-agreements", localTeam = "local-team"

    func launchTarget(isPermitted: Bool, openedForReason: Bool) -> StartupDestination? {
        guard self != .automatic, isPermitted, !openedForReason else { return nil }
        return self
    }
}

struct StartupDestinationScope {
    let actor: String
    let workspace: String
    let origin: String

    var key: String {
        // Encode each component separately to avoid ambiguous delimiter collisions.
        let parts = [actor, workspace, origin].map { Data($0.utf8).base64EncodedString() }
        return "thorbis.startupDestination.v1." + parts.joined(separator: ".")
    }
}

struct StartupDestinationPreferences {
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func get(for scope: StartupDestinationScope) -> StartupDestination {
        defaults.string(forKey: scope.key).flatMap(StartupDestination.init(rawValue:)) ?? .automatic
    }
    func set(_ destination: StartupDestination, for scope: StartupDestinationScope) {
        if destination == .automatic { defaults.removeObject(forKey: scope.key) }
        else { defaults.set(destination.rawValue, forKey: scope.key) }
    }
}

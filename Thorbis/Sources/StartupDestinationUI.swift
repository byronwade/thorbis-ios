import Foundation

extension StartupDestination {
    var menuItem: MenuItem? { MenuItem(rawValue: rawValue) }
    var localSection: LocalWorkspaceSection? {
        guard rawValue.hasPrefix("local-") else { return nil }
        return LocalWorkspaceSection(rawValue: String(rawValue.dropFirst(6)))
    }
    var displayTitle: String { menuItem?.title ?? localSection?.title ?? "Automatic" }

    @MainActor func permitted(_ session: SessionController) -> Bool {
        if self == .automatic { return true }
        if let item = menuItem { return item.permitted(session) }
        if let local = localSection { return session.can(local.requiredCapability, feature: local.requiredFeature) }
        return false
    }

    @MainActor static func scope(session: SessionController, api: APIClient) -> StartupDestinationScope? {
        guard let actor = session.user?.id, !actor.isEmpty,
              let workspace = session.activeOrganization?.id, !workspace.isEmpty,
              let origin = api.normalizedOrigin, !origin.isEmpty else { return nil }
        return .init(actor: actor, workspace: workspace, origin: origin)
    }
}

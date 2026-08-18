enum BrowserHostedWebNotificationPermissionRequestAction: Equatable, Sendable {
    case respondDefault
    case respondDenied
    case resolveSystemAuthorization
    case promptForSitePermission
}

enum BrowserHostedWebNotificationPermissionRequestPolicy {
    static func action(
        for decision: BrowserSitePermissionDecision,
        hasUserActivation: Bool
    ) -> BrowserHostedWebNotificationPermissionRequestAction {
        switch decision {
        case .ask:
            hasUserActivation ? .promptForSitePermission : .respondDefault
        case .denyForSession, .denyPersistently:
            .respondDenied
        case .grantForSession, .grantPersistently:
            .resolveSystemAuthorization
        }
    }
}

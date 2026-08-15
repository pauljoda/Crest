enum BrowserAutomaticDownloadPolicy {
    static func action(
        isUserInitiated: Bool,
        savedDecision: BrowserSitePermissionDecision,
        isUserApprovedRetry: Bool = false
    ) -> BrowserAutomaticDownloadAction {
        if isUserInitiated || isUserApprovedRetry {
            return .allow
        }
        switch savedDecision {
        case .grantForSession, .grantPersistently:
            return .allow
        case .denyForSession, .denyPersistently:
            return .deny
        case .ask:
            return .requestPermission
        }
    }
}

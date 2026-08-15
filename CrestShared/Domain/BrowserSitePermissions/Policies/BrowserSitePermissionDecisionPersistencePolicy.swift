enum BrowserSitePermissionDecisionPersistencePolicy {
    static func isPersistent(_ decision: BrowserSitePermissionDecision) -> Bool {
        switch decision {
        case .grantPersistently, .denyPersistently:
            true
        case .ask, .grantForSession, .denyForSession:
            false
        }
    }
}

enum BrowserAutomaticPopupPolicy {
    /// WebKit applies this decision only to windows opened without user
    /// interaction. A click-activated `window.open()` is always allowed through
    /// to the UI delegate, just like an ordinary target=_blank link.
    static func allowsAutomaticPopups(
        decision: BrowserSitePermissionDecision
    ) -> Bool {
        switch decision {
        case .grantForSession, .grantPersistently:
            true
        case .ask, .denyForSession, .denyPersistently:
            false
        }
    }
}

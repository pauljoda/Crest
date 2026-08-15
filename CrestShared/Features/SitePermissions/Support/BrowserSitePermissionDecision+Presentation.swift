extension BrowserSitePermissionDecision {
    var settingsLabel: String {
        switch self {
        case .grantPersistently:
            "Allow"
        case .denyPersistently:
            "Block"
        case .grantForSession:
            "Allowed for Session"
        case .denyForSession:
            "Blocked for Session"
        case .ask:
            "Ask"
        }
    }
}

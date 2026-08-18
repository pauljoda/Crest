enum BrowserAutomaticDownloadPolicy {
    static func action(
        isUserInitiated: Bool,
        savedDecision: BrowserSitePermissionDecision,
        hasAllowedAutomaticDownload: Bool = false,
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
            return hasAllowedAutomaticDownload ? .requestPermission : .allow
        }
    }
}

/// Tracks Chrome-style automatic-download throttling for one page and origin:
/// the first file is allowed, then the site must ask before sending more.
struct BrowserAutomaticDownloadSequence {
    private(set) var hasAllowedAutomaticDownload = false

    mutating func action(
        isUserInitiated: Bool,
        savedDecision: BrowserSitePermissionDecision,
        isUserApprovedRetry: Bool = false
    ) -> BrowserAutomaticDownloadAction {
        if isUserInitiated {
            // A fresh user action starts a fresh one-download allowance.
            hasAllowedAutomaticDownload = false
        }
        let action = BrowserAutomaticDownloadPolicy.action(
            isUserInitiated: isUserInitiated,
            savedDecision: savedDecision,
            hasAllowedAutomaticDownload: hasAllowedAutomaticDownload,
            isUserApprovedRetry: isUserApprovedRetry
        )
        if !isUserInitiated,
            !isUserApprovedRetry,
            savedDecision == .ask,
            action == .allow
        {
            hasAllowedAutomaticDownload = true
        }
        return action
    }
}

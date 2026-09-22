namespace CrestCore.Domain;

/// Chrome-style automatic-download throttling for one page and origin: while
/// the site's saved decision is still Ask, the first file it sends without a
/// user gesture is allowed and any further file must ask first.
public static class AutomaticDownloadPolicy {
    #region Actions - Automatic downloads

    /// `hasAllowedAutomaticDownload` is the throttle state the caller keeps per
    /// page, origin and Space. Callers without such a scope pass false and
    /// discard the returned state.
    public static AutomaticDownloadVerdict Decide(bool isUserInitiated, bool isUserApprovedRetry,
        SitePermissionDecision savedDecision, bool hasAllowedAutomaticDownload) {
        // A fresh user action starts a fresh one-download allowance.
        bool allowance = !isUserInitiated && hasAllowedAutomaticDownload;
        var action = Action(isUserInitiated || isUserApprovedRetry, savedDecision, allowance);
        if (!isUserInitiated && !isUserApprovedRetry && savedDecision == SitePermissionDecision.Ask
            && action == AutomaticDownloadAction.Allow) allowance = true;
        return new(action, allowance);
    }

    private static AutomaticDownloadAction Action(bool isUserApproved, SitePermissionDecision savedDecision,
        bool hasAllowedAutomaticDownload) {
        if (isUserApproved) return AutomaticDownloadAction.Allow;
        return savedDecision switch {
            SitePermissionDecision.GrantForSession or SitePermissionDecision.GrantPersistently => AutomaticDownloadAction.Allow,
            SitePermissionDecision.DenyForSession or SitePermissionDecision.DenyPersistently => AutomaticDownloadAction.Deny,
            _ => hasAllowedAutomaticDownload ? AutomaticDownloadAction.RequestPermission : AutomaticDownloadAction.Allow
        };
    }

    #endregion
}

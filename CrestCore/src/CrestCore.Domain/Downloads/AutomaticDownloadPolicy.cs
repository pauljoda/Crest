using CrestCore.Contracts;

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
        if (!isUserInitiated && !isUserApprovedRetry && savedDecision.Verdict == SitePermissionVerdict.Ask
            && action == AutomaticDownloadAction.Allow) allowance = true;
        return new(action, allowance);
    }

    /// An approved download goes ahead, and so does one the saved decision
    /// grants. A saved block refuses it. Without an answer, the first automatic
    /// download goes ahead and any further one asks.
    private static AutomaticDownloadAction Action(bool isUserApproved, SitePermissionDecision savedDecision,
        bool hasAllowedAutomaticDownload) {
        if (isUserApproved || savedDecision.Grants) return AutomaticDownloadAction.Allow;
        if (savedDecision.Denies) return AutomaticDownloadAction.Deny;
        return hasAllowedAutomaticDownload ? AutomaticDownloadAction.RequestPermission : AutomaticDownloadAction.Allow;
    }

    #endregion
}

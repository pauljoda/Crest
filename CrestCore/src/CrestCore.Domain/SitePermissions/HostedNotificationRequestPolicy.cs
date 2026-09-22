namespace CrestCore.Domain;

/// A notification permission request prompts only with user activation; a
/// saved block answers denied, and a grant still needs the system's consent.
public static class HostedNotificationRequestPolicy {
    #region Actions - Notifications

    public static HostedNotificationRequestAction Action(SitePermissionDecision decision, bool hasUserActivation) => decision switch {
        SitePermissionDecision.Ask => hasUserActivation
            ? HostedNotificationRequestAction.PromptForSitePermission : HostedNotificationRequestAction.RespondDefault,
        SitePermissionDecision.DenyForSession or SitePermissionDecision.DenyPersistently => HostedNotificationRequestAction.RespondDenied,
        _ => HostedNotificationRequestAction.ResolveSystemAuthorization
    };

    #endregion
}

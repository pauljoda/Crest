namespace CrestCore.Domain;

/// What a decision means for storage and for authorization already given.
public static class SitePermissionDecisionPolicy {
    #region Actions - Decisions

    /// Only persistent answers are saved; session answers and Ask never are.
    public static bool IsPersistent(SitePermissionDecision decision) =>
        decision is SitePermissionDecision.GrantPersistently or SitePermissionDecision.DenyPersistently;

    public static bool Grants(SitePermissionDecision decision) =>
        decision is SitePermissionDecision.GrantForSession or SitePermissionDecision.GrantPersistently;

    public static bool Denies(SitePermissionDecision decision) =>
        decision is SitePermissionDecision.DenyForSession or SitePermissionDecision.DenyPersistently;

    #endregion
}

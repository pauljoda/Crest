namespace CrestCore.Domain;

/// The result of one ledger command: whether the persistent records changed,
/// and what it touched in each Space.
public sealed record SitePermissionOutcome(bool PersistenceChanged, IReadOnlyList<SitePermissionChange> Changes) {
    #region Static Variables

    public static readonly SitePermissionOutcome Unchanged = new(false, []);

    #endregion
}

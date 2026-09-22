namespace CrestCore.Domain;

/// The result of one ledger command. `PersistenceChanged` means the saved
/// document must be written again.
public sealed record SitePermissionOutcome(bool Applied, bool PersistenceChanged, IReadOnlyList<SitePermissionChange> Changes) {
    #region Variables

    public static readonly SitePermissionOutcome Rejected = new(false, false, []);

    #endregion
}

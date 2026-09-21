namespace CrestCore.Domain;

/// Stable tombstone reason codes shared by sync validation and policy.
public static class SyncDeletionReasons {
    #region Variables

    public const string ExplicitDelete = "explicitDelete";
    public const string Superseded = "superseded";
    public const string Retention = "retention";

    #endregion

    #region Actions - Validation

    public static bool Includes(string? reason)
        => reason is ExplicitDelete or Superseded or Retention;

    #endregion
}
